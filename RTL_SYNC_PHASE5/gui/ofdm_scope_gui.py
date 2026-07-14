#!/usr/bin/env python3
"""ofdm_scope_gui.py — real-time OFDM CONSTELLATION + CHANNEL scope GUI.

A browser-based, stdlib-only HTTP server (http.server.ThreadingHTTPServer) so
it runs headless on the lab machine and is viewable remotely.  The server side
reads a captured OFDM baseband .bin/.hex, runs the bit-faithful RX-downstream
demod (FFT -> pilot channel-estimation -> ZF equalize -> QAM demod, ported from
RTL_SYNC_PHASE5/scripts/rx_downstream_ref.py) with numpy, renders three panels
with matplotlib (Agg -> PNG, base64-embedded), and serves an auto-refreshing
page for the "real-time" feel.

Three panels (the ones the user asked for):
  1. CONSTELLATION : equalized 221 data subcarriers x 12 symbols as I/Q points,
     symbol-colored, with the ideal constellation grid for the modulation.
  2. CHANNEL       : |H| (dB) and angle(H) (deg) vs subcarrier index
     (pilot-interpolated channel).
  3. METRICS       : EVM (%), BER (vs golden bits if available), detected
     modulation, sync info (frame_start, CFO estimate, peak), RMS, SNR.

Capture formats (selectable):
  * rf      : RF DDC capture, signed 32-bit words {Q[31:16], I[15:0]}, packed
              5 x 4096 complex (sweep) or 1 x N (off). 153.6 Msps DDC baseband.
              A coarse residual-CFO + timing search aligns onto a 4032-sample
              OFDM slot before demod.
  * digital : digital-loopback / golden TX slot (the known-good BER=0 path):
              tx_slot_iq.hex (4032 x {Q[31:16],I[15:0]} hex words) OR the
              float .npy, OR a raw .bin in the same 32-bit packing. Slot is
              2 sync + 12 data symbols of 288; demod is sample-exact -> BER 0.

Real-time:
  * the page auto-refreshes every N seconds (configurable) -> re-read + re-demod
    + re-render, so a freshly-overwritten capture file shows up live.
  * a "Capture now" button hits /api/capture which (optionally) invokes the
    existing board capture flow (scripts/run_rfsync.sh <label>) and then
    re-renders. Board trigger is OFF unless --capture-cmd / --board is given,
    so the GUI also works in pure file-replay mode with no board.

Deps: numpy + matplotlib only (both already used across the repo). Server is
pure stdlib.

Run:
  python3 ofdm_scope_gui.py --capture <path> --format digital --mod 16qam --port 8080
  python3 ofdm_scope_gui.py --capture tests/08_rfdc_capture/capture_clean1_sweep.bin \
                            --format rf --mod 16qam --port 8080
  then open http://<host>:8080
"""

from __future__ import annotations

import argparse
import base64
import html
import io
import json
import os
import subprocess
import threading
import time
import traceback
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as mpl

# ----------------------------------------------------------------------------
# Locate + import the verified reference demod (rx_downstream_ref.py).
# ----------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
P5_ROOT = os.path.dirname(HERE)                      # RTL_SYNC_PHASE5/
REPO_ROOT = os.path.dirname(P5_ROOT)                 # FPGA_Based_OFDM_Transceiver/
SCRIPTS = os.path.join(P5_ROOT, "scripts")
GOLDEN = os.path.join(P5_ROOT, "golden", "rx_downstream")

import sys
if SCRIPTS not in sys.path:
    sys.path.insert(0, SCRIPTS)
import rx_downstream_ref as R   # noqa: E402  (path injected above)


# ============================================================================
# Capture loading
# ============================================================================
def _unpack_words(words):
    """uint32 words {Q[31:16], I[15:0]} (signed 16-bit) -> complex float."""
    w = words.astype(np.uint32)
    I = (w & 0xFFFF).astype(np.int16).astype(np.float64)
    Q = ((w >> 16) & 0xFFFF).astype(np.int16).astype(np.float64)
    return I + 1j * Q


def load_capture(path, fmt):
    """Read a capture file -> (complex_iq float array, info dict).

    fmt == 'digital' : tx_slot golden / digital-loopback. Accepts:
        .hex (one 8-hex word/line, {Q,I}), .npy (Nx2 float [I,Q] or complex),
        or .bin (raw little-endian 32-bit {Q,I}).
        Returned IQ is scaled by 1/Q15_SCALE so it sits at amplitude ~1.

    fmt == 'rf' : RF DDC capture, raw little-endian signed 32-bit {Q,I}.
        Returned IQ is the raw int amplitude (left un-normalised; the demod
        pipeline is scale-invariant because the ZF equalizer divides out H).
    """
    info = {"path": path, "format": fmt}
    ext = os.path.splitext(path)[1].lower()

    if fmt == "digital":
        if ext == ".hex":
            txt = np.loadtxt(path, dtype=str)
            words = np.array([int(x, 16) for x in np.atleast_1d(txt)],
                             dtype=np.uint32)
            iq = _unpack_words(words) / R.Q15_SCALE
        elif ext == ".npy":
            arr = np.load(path)
            if np.iscomplexobj(arr):
                iq = arr.astype(complex).ravel()
            elif arr.ndim == 2 and arr.shape[1] == 2:
                iq = (arr[:, 0] + 1j * arr[:, 1]).astype(complex)
            else:
                iq = arr.astype(complex).ravel()
            # float .npy from rx_downstream_ref is already amplitude ~1
        else:  # raw .bin in {Q,I} packing
            words = np.fromfile(path, dtype="<u4")
            iq = _unpack_words(words) / R.Q15_SCALE
        info["nsamp"] = int(len(iq))
        info["scale_note"] = "amplitude ~1 (Q15_SCALE normalised)"
        return iq, info

    # fmt == 'rf'
    words = np.fromfile(path, dtype="<u4")
    iq = _unpack_words(words)
    info["nsamp"] = int(len(iq))
    info["nwin"] = int(len(iq) // 4096)
    info["scale_note"] = "raw DDC int amplitude (153.6 Msps)"
    return iq, info


# ============================================================================
# Demod pipeline (reuses rx_downstream_ref primitives)
# ============================================================================
def _load_golden_pilots():
    """Return (plt[12,32] complex, tx_bits[12,bps] or None) from golden."""
    p = os.path.join(GOLDEN, "16qam", "pilot_rom_float.npy")
    if not os.path.exists(p):
        p = os.path.join(GOLDEN, "pilot_rom_float.npy")
    plt_arr = np.load(p)                       # (12,32,2)
    plt_c = plt_arr[..., 0] + 1j * plt_arr[..., 1]
    return plt_c


def _golden_bits(mod_name):
    """Return tx_bits matrix (12 x bps) for the given mod, or None."""
    for cand in (os.path.join(GOLDEN, mod_name, "tx_bits.txt"),
                 os.path.join(GOLDEN, "tx_bits.txt")):
        if os.path.exists(cand):
            rows = [[int(c) for c in ln.strip()]
                    for ln in open(cand) if ln.strip()]
            return np.array(rows, dtype=int)
    return None


def _coarse_cfo_correct(iq):
    """Coarse residual CFO estimate via CP autocorrelation (Schmidl/Moose-ish).

    Uses the cyclic-prefix repetition: for each candidate symbol, the CP (32
    samples) equals the tail of the body (32 samples NSC apart). Averaging the
    angle of sum(x[n]*conj(x[n+NSC])) over the slot gives a per-sample phase
    increment -> coarse CFO. Returns (corrected_iq, cfo_norm) where cfo_norm is
    cycles/sample. Robust to scale; skips if energy ~0.
    """
    if len(iq) < R.SYM_LEN:
        return iq, 0.0
    x = iq[:max(R.SLOT_LEN, R.SYM_LEN)]
    acc = 0.0 + 0.0j
    # correlate over available length lagged by NSC
    n = len(x) - R.NSC
    if n <= 0:
        return iq, 0.0
    acc = np.sum(x[:n] * np.conj(x[R.NSC:R.NSC + n]))
    if np.abs(acc) < 1e-9:
        return iq, 0.0
    phi = np.angle(acc)               # phase over NSC samples
    cfo_norm = phi / (2.0 * np.pi * R.NSC)
    nidx = np.arange(len(iq))
    corr = iq * np.exp(-1j * 2.0 * np.pi * cfo_norm * nidx)
    return corr, float(cfo_norm)


def _timing_metric(iq):
    """CP-autocorrelation timing metric over the capture; returns (P array)."""
    L = R.CP_LEN
    D = R.NSC
    n = len(iq)
    if n < D + L:
        return np.zeros(max(1, n)), 0
    # sliding sum of x[k]*conj(x[k+D]) over a window of L
    prod = iq[:n - D] * np.conj(iq[D:])
    # window sum length L
    csum = np.concatenate([[0], np.cumsum(prod)])
    win = csum[L:] - csum[:-L]                 # len = len(prod)-L+1
    P = np.abs(win)
    return P, int(np.argmax(P)) if len(P) else 0


def find_slot_start(iq, fmt):
    """Find the 4032-sample OFDM slot start.

    digital golden: data begins after NUM_SYN sync symbols. The committed
        golden tx_slot has zero sync region, so the first non-zero sample marks
        the start of the (zeroed) slot at index 0; we return 0 and the demod
        offsets by NUM_SYN*SYM_LEN.

    rf: search the CP-autocorrelation timing metric for the strongest periodic
        structure, then back off to a symbol boundary so a full 14-symbol slot
        fits inside the capture.
    """
    if fmt == "digital":
        return 0, {"method": "digital-slot@0"}

    P, pk = _timing_metric(iq)
    # we want a slot start such that start + SLOT_LEN <= len(iq)
    start = pk
    # back off to leave room for a full slot; clamp
    if start + R.SLOT_LEN > len(iq):
        start = max(0, len(iq) - R.SLOT_LEN)
    # align to symbol grid relative to the peak
    info = {"method": "rf-cp-autocorr", "raw_peak": int(pk),
            "peak_metric": float(P[pk]) if len(P) else 0.0}
    return int(start), info


def demod_slot(iq, slot_start, mod_name, plt_c):
    """Run FFT->CE->ZF->demod over the 12 data symbols of one slot.

    Returns dict with constellation points, channel H (symbol 0), per-symbol
    arrays, BER (if golden bits match), EVM, etc.
    """
    mod_sel = {v: k for k, v in R.MOD_NAMES.items()}[mod_name]
    k = R.MOD_K[mod_sel]
    bps = 2 * k

    eq_all = []
    sym_color = []
    H_used = None
    rx_bits_rows = []
    for z in range(R.NUM_DATA):
        off = slot_start + (R.NUM_SYN + z) * R.SYM_LEN
        seg = iq[off:off + R.SYM_LEN]
        if len(seg) < R.SYM_LEN:
            break
        rxSym = R.rx_fft(seg)
        Hp = R.ch_estimation_fdm(rxSym, plt_c[z])
        H = R.interp_fft(Hp)
        Hest = np.zeros(R.NSC, dtype=complex)
        Hest[1:1 + (R.NSC - 2)] = H[0:R.NSC - 2]
        if H_used is None:
            H_used = Hest
        eq = R.fde_zf(rxSym, Hest)
        eqd = np.array([eq[i] for i in R.DATA_INDX])
        eq_all.append(eqd)
        sym_color.append(np.full(len(eqd), z))
        rb = np.zeros(R.NUM_DATA_SC * bps, dtype=int)
        for n in range(R.NUM_DATA_SC):
            b = R.demod_qam(eqd[n], mod_sel, R.Q15_DEMOD)
            rb[n * bps:(n + 1) * bps] = b
        rx_bits_rows.append(rb)

    if not eq_all:
        raise RuntimeError("no full OFDM symbol found at slot_start "
                           f"{slot_start} (capture too short?)")

    pts = np.concatenate(eq_all)
    colors = np.concatenate(sym_color)
    n_sym = len(eq_all)

    # ideal (decision) symbols for EVM: re-mod the demodulated bits
    ideal = np.array([R.mod_qam(R.demod_qam(p, mod_sel, R.Q15_DEMOD), mod_sel)
                      for p in pts])
    ref_pow = np.mean(np.abs(ideal) ** 2) or 1.0
    evm_rms = np.sqrt(np.mean(np.abs(pts - ideal) ** 2) / ref_pow)

    # SNR estimate from EVM (EVM ~ 1/sqrt(SNR)) -> dB
    snr_db = -20.0 * np.log10(evm_rms) if evm_rms > 0 else float("inf")

    # BER vs golden bits (only valid for the digital golden capture)
    ber = None
    nerr = nbits = 0
    gbits = _golden_bits(mod_name)
    if gbits is not None and gbits.shape[0] >= n_sym:
        rx_mat = np.array(rx_bits_rows)
        gb = gbits[:n_sym]
        if gb.shape[1] == rx_mat.shape[1]:
            nerr = int(np.sum(gb != rx_mat))
            nbits = int(gb.size)
            ber = nerr / nbits if nbits else None

    return {
        "points": pts,
        "colors": colors,
        "n_sym": n_sym,
        "H": H_used,
        "evm": float(evm_rms),
        "snr_db": float(snr_db),
        "ber": ber,
        "nerr": int(nerr),
        "nbits": int(nbits),
        "mod_name": mod_name,
        "mod_sel": mod_sel,
        "k": k,
    }


# ============================================================================
# ANIMATED DEMO mode
# ----------------------------------------------------------------------------
# Instead of re-reading a static capture file, synthesize a TIME-VARYING
# received OFDM signal from the known golden TX slot on EACH /api/points poll,
# applying impairments that are smooth functions of wall-clock time so
# consecutive polls differ slightly -> smooth scope-like animation. The REAL
# demod pipeline (FFT -> pilot-CE -> ZF-EQ -> QAM-demod) then runs on the
# synthetic signal, so constellation / channel / EVM / BER all track the
# current synthetic conditions live.
#
# Impairments (all smooth periodic functions of t seconds):
#   * residual CFO / phase rotation  cfo(t) = A_cfo*sin(2*pi*t/T_cfo)
#       -> whole constellation + channel-angle panel slowly rotate
#   * SNR breathing  SNR(t) = SNR0 + SNR_A*sin(2*pi*t/T_snr) dB
#       -> AWGN level oscillates; clusters tighten/loosen; BER/EVM rise & fall
#   * channel fade   a mild 2-tap multipath whose 2nd-tap delay/phase/gain
#       drift slowly -> |H(k)| panel ripples and changes shape; ZF EQ corrects
#       most of it, residual shows up in EVM
#   * modulation cycle (optional)  QPSK->16->64->256-QAM->repeat over T_mod
#       -> constellation density changes; ideal grid + metrics follow
#
# Determinism: the AWGN RNG is seeded by a quantized timestamp so a given
# instant is reproducible-ish but the stream stays lively. Heavy golden loads
# are cached once per modulation.
# ============================================================================
_DEMO_CACHE = {}   # mod_name -> {"slot": complex[4032], "plt": complex[12,32]}


def _load_demo_golden(mod_name):
    """Load (and cache) the golden TX slot + pilots for a modulation.

    Returns dict {"slot": complex[SLOT_LEN], "plt": complex[NUM_DATA,NUM_PILOTS]}.
    The golden tx_slot_iq_float.npy is the clean 4032-sample OFDM slot
    (2 sync + 12 data symbols) at amplitude ~1; pilot_rom_float.npy holds the
    per-symbol QPSK pilot grid the CE consumes.
    """
    cached = _DEMO_CACHE.get(mod_name)
    if cached is not None:
        return cached
    base = os.path.join(GOLDEN, mod_name)
    slot_npy = os.path.join(base, "tx_slot_iq_float.npy")
    if not os.path.exists(slot_npy):
        raise FileNotFoundError(
            f"demo golden not found for {mod_name}: {slot_npy} "
            f"(run scripts/rx_downstream_ref.py to generate it)")
    arr = np.load(slot_npy)                      # (4032, 2) [I, Q]
    slot = (arr[:, 0] + 1j * arr[:, 1]).astype(complex)
    plt_arr = np.load(os.path.join(base, "pilot_rom_float.npy"))   # (12,32,2)
    plt_c = plt_arr[..., 0] + 1j * plt_arr[..., 1]
    cached = {"slot": slot, "plt": plt_c}
    _DEMO_CACHE[mod_name] = cached
    return cached


# demo modulation cycle order (low -> high density)
_DEMO_MOD_CYCLE = ("qpsk", "16qam", "64qam", "256qam")


def demo_mod_for_time(t, periods, enabled):
    """Pick the modulation for time t when --demo-cycle-mod is on.

    Cycles qpsk->16qam->64qam->256qam, each held for T_mod/4 seconds so one
    full cycle takes T_mod. When disabled, returns None (caller keeps the
    fixed --mod)."""
    if not enabled:
        return None
    T_mod = periods["T_mod"]
    seg = T_mod / len(_DEMO_MOD_CYCLE)
    idx = int((t % T_mod) / seg) % len(_DEMO_MOD_CYCLE)
    return _DEMO_MOD_CYCLE[idx]


def demo_impairments(t, periods):
    """Evaluate the smooth time-varying impairment parameters at time t (s).

    Returns dict with cfo_norm (cyc/sample), snr_db, and the 2-tap channel
    description (tap2 gain/delay/phase). All are smooth periodic functions of
    t so consecutive polls differ only slightly -> smooth animation."""
    two_pi = 2.0 * np.pi
    # residual CFO: slow phase rotation of the whole constellation
    A_cfo = periods["A_cfo"]                      # cyc/sample amplitude
    cfo_norm = A_cfo * np.sin(two_pi * t / periods["T_cfo"])
    # SNR breathing
    snr_db = periods["SNR0"] + periods["SNR_A"] * np.sin(two_pi * t /
                                                         periods["T_snr"])
    # channel fade: a mild 2-tap multipath; 2nd tap drifts slowly
    g2 = periods["TAP2_G"] * (0.6 + 0.4 * np.sin(two_pi * t / periods["T_fade"]))
    # tap delay slides between 1..(D_MAX) samples
    d_span = periods["TAP2_DMAX"] - 1.0
    delay2 = 1.0 + 0.5 * d_span * (1.0 + np.sin(two_pi * t /
                                                periods["T_fade_d"]))
    phase2 = two_pi * t / periods["T_fade_ph"]
    return {
        "cfo_norm": float(cfo_norm),
        "snr_db": float(snr_db),
        "tap2_g": float(g2),
        "tap2_delay": float(delay2),
        "tap2_phase": float(phase2),
    }


def _apply_channel_2tap(iq, g2, delay2, phase2):
    """Apply a mild 2-tap multipath: y = x + g2*exp(j*phase2)*x[n-delay2].

    delay2 is fractional; we use the nearest-integer delay for a cheap,
    frequency-selective ripple (ZF EQ corrects most of it). Tap1 is unit at
    delay 0."""
    d = int(round(delay2))
    if d < 1:
        d = 1
    y = iq.copy()
    tap = g2 * np.exp(1j * phase2)
    y[d:] += tap * iq[:-d]
    return y


def synth_demo_iq(t, mod_name, periods, seed_quant=0.25):
    """Synthesize a time-varying received OFDM slot at wall-clock time t.

    Pipeline: golden clean slot -> 2-tap channel fade -> residual-CFO phase
    rotation -> AWGN at the breathing SNR. Returns (iq complex[SLOT_LEN],
    plt complex[12,32], imp dict, used_mod_name).

    Deterministic-per-instant: the AWGN RNG is seeded from a quantized
    timestamp (seed_quant seconds) so the same instant reproduces, while
    motion stays smooth across polls."""
    g = _load_demo_golden(mod_name)
    clean = g["slot"]
    plt_c = g["plt"]
    imp = demo_impairments(t, periods)

    # 1) channel fade (frequency-selective ripple)
    y = _apply_channel_2tap(clean, imp["tap2_g"], imp["tap2_delay"],
                            imp["tap2_phase"])

    # 2) residual-CFO phase rotation (whole constellation rotates)
    n = np.arange(len(y))
    y = y * np.exp(1j * 2.0 * np.pi * imp["cfo_norm"] * n)

    # 3) AWGN at the breathing SNR. Signal power measured on the clean slot's
    #    active region; noise scaled to hit SNR(t).
    sig_pow = float(np.mean(np.abs(clean) ** 2)) or 1.0
    snr_lin = 10.0 ** (imp["snr_db"] / 10.0)
    npow = sig_pow / snr_lin
    seed = int(t / seed_quant) & 0x7FFFFFFF
    rng = np.random.default_rng(seed)
    noise = (rng.standard_normal(len(y)) +
             1j * rng.standard_normal(len(y))) * np.sqrt(npow / 2.0)
    y = y + noise
    return y, plt_c, imp, mod_name


def run_pipeline_demo(cfg):
    """Animated-demo equivalent of run_pipeline: synthesize a time-varying RX
    slot from the golden TX and run the REAL demod. Returns a result dict
    shaped like run_pipeline's so points_json / render_* work unchanged."""
    periods = cfg["demo_periods"]
    cycle_mod = cfg.get("demo_cycle_mod", False)
    t = time.time() - cfg.get("demo_t0", 0.0)

    # modulation: cycle if enabled, else the fixed --mod (never 'auto' in demo)
    base_mod = cfg["mod"] if cfg["mod"] != "auto" else "16qam"
    cyc = demo_mod_for_time(t, periods, cycle_mod)
    mod_name = cyc if cyc is not None else base_mod

    iq, plt_c, imp, used_mod = synth_demo_iq(t, mod_name, periods)

    # RMS (DC-removed) of the synthetic slot
    x = iq - iq.mean()
    rms = float(np.sqrt(np.mean(np.abs(x) ** 2))) if len(x) else 0.0

    # slot start is exact for the synthetic golden-aligned slot
    slot_start = 0
    res = demod_slot(iq, slot_start, used_mod, plt_c)

    res["rms"] = rms
    res["cfo_norm"] = float(imp["cfo_norm"])
    # report CFO in Hz using the DDC sample rate so the panel is meaningful
    res["cfo_hz"] = float(imp["cfo_norm"] * 153.6e6)
    res["slot_start"] = int(slot_start)
    res["sync_info"] = {"method": "demo-synth@0", "peak_metric": 0.0}
    res["capture_info"] = {
        "path": f"[DEMO synth {used_mod}]",
        "format": "demo",
        "nsamp": int(len(iq)),
    }
    # surface the commanded (ground-truth) impairments so the metrics panel can
    # show what the animation is currently doing
    res["demo_snr_cmd_db"] = float(imp["snr_db"])
    res["demo_tap2_g"] = float(imp["tap2_g"])
    res["demo_tap2_delay"] = float(imp["tap2_delay"])
    res["demo_t"] = float(t)

    if cfg.get("render_png", False):
        res["png_const"] = render_constellation(res)
        res["png_chan"] = render_channel(res)
    res["ts"] = time.strftime("%Y-%m-%d %H:%M:%S")
    res["mtime"] = t          # ever-changing so the client sees fresh frames
    return res


def ideal_constellation(mod_sel):
    """Return the ideal constellation points for the reference grid."""
    k = R.MOD_K[mod_sel]
    nlev = 1 << k
    levels = [(-(nlev - 1) + 2 * i) for i in range(nlev)]   # odd integers
    S = R.MOD_SCALE[mod_sel]
    pts = [(a * S) + 1j * (b * S) for a in levels for b in levels]
    return np.array(pts)


def auto_detect_mod(iq, slot_start, plt_c):
    """Try each modulation, pick the one with lowest EVM."""
    best = None
    for name in ("qpsk", "16qam", "64qam", "256qam"):
        try:
            r = demod_slot(iq, slot_start, name, plt_c)
            if best is None or r["evm"] < best["evm"]:
                best = r
        except Exception:
            continue
    return best


# ============================================================================
# JSON serialization (for the live client-side canvas renderer)
# ============================================================================
def _r(x, nd=4):
    """Round a float (or non-finite) to nd decimals for compact JSON."""
    try:
        f = float(x)
    except (TypeError, ValueError):
        return None
    if not np.isfinite(f):
        return None
    return round(f, nd)


def _rlist(arr, nd=4):
    return [_r(v, nd) for v in np.asarray(arr).ravel().tolist()]


# ----------------------------------------------------------------------------
# THROUGHPUT metric (OFDM numerology).
# ----------------------------------------------------------------------------
# Per slot the PHY carries NUM_DATA_SC (221) data subcarriers x NUM_DATA (12)
# data symbols = 2652 data-SC, each carrying bits_per_SC = 2*k bits
# (QPSK:2, 16QAM:4, 64QAM:6, 256QAM:8). One slot is SLOT_LEN (4032) samples;
# on the wire it is framed to FRAMED_PERIOD (4160) samples (the 4032-sample slot
# plus the inter-slot guard). At sample rate Fs samples/s:
#   gross_bps   = DATA_SC_PER_SLOT * bits_per_SC * (Fs / SLOT_LEN)
#   framed_bps  = DATA_SC_PER_SLOT * bits_per_SC * (Fs / FRAMED_PERIOD)
#   goodput_bps = gross_bps * (1 - BER)   (information bits after bit errors)
# Reference (Fs=153.6 Msps): QPSK 202 / 16QAM 404 / 64QAM 606 / 256QAM 808 Mbps
# gross; at Fs=162 Msps (board sustained): 213 / 426 / 639 / 852.
DATA_SC_PER_SLOT = R.NUM_DATA_SC * R.NUM_DATA      # 221 * 12 = 2652
FRAMED_PERIOD = 4160                               # framed slot period (samples)


def throughput_block(res, fs):
    """Compute the live throughput block from the current demod result + Fs.

    bits_per_SC = 2*k (k = MOD_K[mod_sel]); BER drops goodput below gross.
    Returns a JSON-able dict (rates in Mbps, rounded) for /api/points."""
    bits_per_sc = 2 * int(res["k"])
    ber = res.get("ber")
    ber_f = float(ber) if (ber is not None and np.isfinite(ber)) else 0.0
    gross_bps = DATA_SC_PER_SLOT * bits_per_sc * (fs / R.SLOT_LEN)
    framed_bps = DATA_SC_PER_SLOT * bits_per_sc * (fs / FRAMED_PERIOD)
    goodput_bps = gross_bps * (1.0 - ber_f)
    return {
        "gross_mbps": _r(gross_bps / 1e6, 1),
        "framed_mbps": _r(framed_bps / 1e6, 1),
        "goodput_mbps": _r(goodput_bps / 1e6, 1),
        "bits_per_sc": int(bits_per_sc),
        "fs_msps": _r(fs / 1e6, 1),
    }


def points_json(res, fs=153.6e6):
    """Build a compact JSON-able dict of constellation points + channel +
    metrics from a demod result. Floats rounded so it serializes fast and
    the wire payload stays small (~tens of KB for 221x12 points)."""
    pts = res["points"]
    colors = res["colors"]
    H = res["H"]
    sc = np.arange(R.NSC)
    magdb = 20.0 * np.log10(np.maximum(np.abs(H), 1e-6))
    ang = np.degrees(np.angle(H))
    pilot_mask = np.zeros(R.NSC, dtype=int)
    pilot_mask[R.PLT_INDX] = 1
    # ideal grid for the detected modulation (so the client can overlay it)
    ideal = ideal_constellation(res["mod_sel"])

    info = res.get("capture_info", {})
    is_rf = info.get("format") == "rf"
    is_demo = info.get("format") == "demo"
    thru = throughput_block(res, fs)
    return {
        "ok": True,
        "ts": res.get("ts"),
        "mtime": res.get("mtime"),
        # live PHY throughput (gross / framed / goodput) from mod + BER + Fs
        "throughput": thru,
        # constellation: parallel I/Q arrays + per-point symbol index (color)
        "const": {
            "I": _rlist(pts.real, 4),
            "Q": _rlist(pts.imag, 4),
            "sym": [int(c) for c in np.asarray(colors).ravel().tolist()],
            "n_sym": int(res["n_sym"]),
            "n_data_sc": int(R.NUM_DATA_SC),
            "ideal_I": _rlist(ideal.real, 4),
            "ideal_Q": _rlist(ideal.imag, 4),
        },
        # channel estimate over all NSC subcarriers
        "chan": {
            "sc": [int(v) for v in sc.tolist()],
            "magdb": _rlist(magdb, 3),
            "angdeg": _rlist(ang, 2),
            "pilot_mask": [int(v) for v in pilot_mask.tolist()],
            "pilot_idx": [int(v) for v in np.asarray(R.PLT_INDX).tolist()],
        },
        # scalar metrics for the live text panel
        "metrics": {
            "mod": res["mod_name"],
            "evm_pct": _r(100.0 * res["evm"], 3),
            "ber": (None if res["ber"] is None else _r(res["ber"], 6)),
            "nerr": int(res["nerr"]),
            "nbits": int(res["nbits"]),
            "snr_db": _r(res["snr_db"], 2),
            "n_symbols": int(res["n_sym"]),
            "n_data_sc": int(R.NUM_DATA_SC),
            "slot_start": int(res["slot_start"]),
            "sync_method": res.get("sync_info", {}).get("method", ""),
            "peak": _r(res.get("sync_info", {}).get("peak_metric", 0.0), 4),
            "cfo": _r(res.get("cfo_norm", 0.0), 6),
            "cfo_hz": _r(res.get("cfo_hz", 0.0), 1),
            "rms": _r(res.get("rms", 0.0), 4),
            "rf": bool(is_rf),
            "demo": bool(is_demo),
            # commanded (ground-truth) demo impairments for the live panel
            "demo_snr_cmd": _r(res.get("demo_snr_cmd_db"), 2),
            "demo_tap2_g": _r(res.get("demo_tap2_g"), 3),
            "demo_tap2_delay": _r(res.get("demo_tap2_delay"), 2),
            "demo_t": _r(res.get("demo_t"), 1),
            "capture": os.path.basename(info.get("path", "")) or
                       info.get("path", ""),
            "nsamp": int(info.get("nsamp", 0)),
        },
    }


# ============================================================================
# Rendering (matplotlib Agg -> base64 PNG)
# ============================================================================
def _fig_to_b64(fig):
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=96, bbox_inches="tight",
                facecolor=fig.get_facecolor())
    mpl.close(fig)
    buf.seek(0)
    return base64.b64encode(buf.read()).decode("ascii")


def render_constellation(res):
    fig = mpl.figure(figsize=(5.6, 5.4), facecolor="#ffffff")
    ax = fig.add_subplot(111)
    pts = res["points"]
    ax.scatter(pts.real, pts.imag, c=res["colors"], cmap="turbo",
               s=7, alpha=0.55, linewidths=0)
    ideal = ideal_constellation(res["mod_sel"])
    ax.scatter(ideal.real, ideal.imag, marker="+", c="#111111",
               s=130, linewidths=1.6, label="ideal")
    lim = max(1.0, np.percentile(np.abs(pts), 99.5) * 1.15,
              np.max(np.abs(ideal)) * 1.25)
    ax.set_xlim(-lim, lim)
    ax.set_ylim(-lim, lim)
    ax.axhline(0, color="#cccccc", lw=0.7)
    ax.axvline(0, color="#cccccc", lw=0.7)
    ax.set_aspect("equal")
    ax.grid(True, color="#eeeeee", lw=0.6)
    ax.set_title(f"Constellation  {res['mod_name'].upper()}  "
                 f"({res['n_sym']} sym x {R.NUM_DATA_SC} SC)", fontsize=11)
    ax.set_xlabel("I"); ax.set_ylabel("Q")
    return _fig_to_b64(fig)


def render_channel(res):
    H = res["H"]
    sc = np.arange(R.NSC)
    magdb = 20.0 * np.log10(np.maximum(np.abs(H), 1e-6))
    ang = np.degrees(np.angle(H))
    fig = mpl.figure(figsize=(6.4, 5.4), facecolor="#ffffff")
    ax1 = fig.add_subplot(211)
    ax1.plot(sc, magdb, color="#2369a8", lw=1.3)
    dmask = np.zeros(R.NSC, bool); dmask[R.DATA_INDX] = True
    ax1.plot(sc[dmask], magdb[dmask], ".", color="#2369a8", ms=2.5)
    ax1.plot(R.PLT_INDX, magdb[R.PLT_INDX], "o", color="#b46500",
             ms=4, label="pilots")
    ax1.set_ylabel("|H|  (dB)")
    ax1.set_title("Estimated channel  H(k)  (pilot-interpolated)", fontsize=11)
    ax1.grid(True, color="#eeeeee"); ax1.legend(fontsize=8, loc="lower center")
    ax2 = fig.add_subplot(212)
    ax2.plot(sc, ang, color="#2f7d53", lw=1.3)
    ax2.plot(R.PLT_INDX, ang[R.PLT_INDX], "o", color="#b46500", ms=4)
    ax2.set_ylabel("angle(H) (deg)"); ax2.set_xlabel("subcarrier index k")
    ax2.set_ylim(-185, 185)
    ax2.grid(True, color="#eeeeee")
    fig.tight_layout()
    return _fig_to_b64(fig)


# ============================================================================
# Top-level run: load -> sync -> demod -> render -> metrics
# ============================================================================
def run_pipeline(cfg):
    """Read the configured capture, demod, render. Returns a result dict."""
    path = cfg["capture"]
    fmt = cfg["format"]
    mod = cfg["mod"]
    if not os.path.exists(path):
        raise FileNotFoundError(path)

    iq_full, info = load_capture(path, fmt)

    # capture RMS (DC-removed)
    x = iq_full - iq_full.mean()
    rms = float(np.sqrt(np.mean(np.abs(x) ** 2))) if len(x) else 0.0

    # For RF capture: optional coarse CFO correction over the selected window.
    cfo_norm = 0.0
    iq = iq_full
    if fmt == "rf":
        # take a window holding at least one slot (use first 4096-window block
        # that fits a slot, else whole thing)
        if len(iq_full) >= R.SLOT_LEN:
            iq = iq_full
        iq, cfo_norm = _coarse_cfo_correct(iq)

    slot_start, sync_info = find_slot_start(iq, fmt)

    if mod == "auto":
        res = auto_detect_mod(iq, slot_start, _PLT)
        if res is None:
            raise RuntimeError("auto-detect failed for all modulations")
    else:
        res = demod_slot(iq, slot_start, mod, _PLT)

    res["rms"] = rms
    res["cfo_norm"] = float(cfo_norm)
    res["cfo_hz"] = float(cfo_norm * 153.6e6) if fmt == "rf" else 0.0
    res["slot_start"] = int(slot_start)
    res["sync_info"] = sync_info
    res["capture_info"] = info

    # PNG panels are only needed for the legacy/fallback PNG page. The live
    # client-side canvas page uses /api/points instead, so skip the (slow)
    # matplotlib render when not requested.
    if cfg.get("render_png", True):
        res["png_const"] = render_constellation(res)
        res["png_chan"] = render_channel(res)
    res["ts"] = time.strftime("%Y-%m-%d %H:%M:%S")
    res["mtime"] = os.path.getmtime(path)
    return res


# pilots loaded once
_PLT = None


# ============================================================================
# HTTP server
# ============================================================================
class State:
    def __init__(self, cfg):
        self.cfg = cfg
        self.lock = threading.Lock()
        self.last = None
        self.last_err = None
        self._last_compute = 0.0      # wall time of last successful demod

    def compute(self, render_png=None):
        """Run the demod pipeline. render_png overrides cfg['render_png'] for
        this call (the live JSON page passes False to skip matplotlib)."""
        with self.lock:
            try:
                saved = self.cfg.get("render_png", True)
                if render_png is not None:
                    self.cfg["render_png"] = render_png
                try:
                    if self.cfg.get("demo"):
                        self.last = run_pipeline_demo(self.cfg)
                    else:
                        self.last = run_pipeline(self.cfg)
                finally:
                    self.cfg["render_png"] = saved
                self.last_err = None
                self._last_compute = time.time()
            except Exception as exc:
                self.last_err = f"{exc}\n{traceback.format_exc()}"
        return self.last, self.last_err

    def compute_cached(self, render_png=False):
        """Return the latest demod, re-running only if the cache TTL expired
        or the capture file changed on disk. Cheap for rapid polling."""
        ttl = float(self.cfg.get("cache_ttl", 0.5))
        now = time.time()
        # demo mode has no capture file; the synthetic signal is time-varying,
        # so just honour the (short) TTL. NOTE: compute() takes self.lock, so we
        # must NOT call it while already holding the lock (RLock is not used).
        if self.cfg.get("demo"):
            with self.lock:
                fresh = (self.last is not None and
                         (now - self._last_compute) < ttl)
                if fresh:
                    return self.last, self.last_err
            return self.compute(render_png=render_png)
        with self.lock:
            fresh = self.last is not None and (now - self._last_compute) < ttl
            stale_file = False
            if self.last is not None:
                try:
                    if os.path.getmtime(self.cfg["capture"]) != \
                            self.last.get("mtime"):
                        stale_file = True
                except OSError:
                    pass
        if fresh and not stale_file:
            return self.last, self.last_err
        return self.compute(render_png=render_png)


def metrics_block(res, fs=153.6e6):
    """Build the HTML metrics list."""
    ber = res["ber"]
    ber_s = "n/a (no golden)" if ber is None else (
        f"{ber:.3e}  ({res['nerr']}/{res['nbits']} bits)")
    tp = throughput_block(res, fs)
    rows = [
        ("Modulation (detected)", res["mod_name"].upper()),
        ("PHY throughput (gross)",
         f"{tp['gross_mbps']:.1f} Mbps  ({tp['bits_per_sc']} b/SC "
         f"@{tp['fs_msps']:.1f} Msps)"),
        ("Framed throughput",  f"{tp['framed_mbps']:.1f} Mbps"),
        ("Goodput (x(1-BER))", f"{tp['goodput_mbps']:.1f} Mbps"),
        ("BER vs golden", ber_s),
        ("EVM (rms)", f"{100*res['evm']:.3f} %"),
        ("SNR estimate", f"{res['snr_db']:.1f} dB"),
        ("Symbols demodulated", f"{res['n_sym']} / {R.NUM_DATA}"),
        ("Data subcarriers/sym", f"{R.NUM_DATA_SC}"),
        ("Slot start (sample)", f"{res['slot_start']}  "
                                f"[{res['sync_info'].get('method','')}]"),
        ("CFO estimate", (f"{res['cfo_norm']:.3e} cyc/sample "
                          f"({res['cfo_hz']/1e3:.1f} kHz)"
                          if res["capture_info"]["format"] == "rf"
                          else "0 (digital, exact)")),
        ("Sync peak metric", f"{res['sync_info'].get('peak_metric', 0):.3g}"),
        ("Capture RMS", f"{res['rms']:.4g}"),
        ("Capture", os.path.basename(res["capture_info"]["path"])),
        ("Format / samples", f"{res['capture_info']['format']} / "
                             f"{res['capture_info']['nsamp']}"),
        ("Rendered at", res["ts"]),
    ]
    out = []
    for k, v in rows:
        cls = ""
        if k == "BER vs golden" and ber == 0.0:
            cls = "ok"
        elif k == "BER vs golden" and ber not in (None, 0.0):
            cls = "warn"
        if k == "EVM (rms)" and res["evm"] < 0.10:
            cls = "ok"
        out.append(f'<div class="m {cls}"><span class="ml">{html.escape(k)}'
                   f'</span><span class="mv">{html.escape(str(v))}</span></div>')
    return "\n".join(out)


PAGE_CSS = """
:root{--bg:#0f1822;--panel:#172331;--ink:#e7eef6;--muted:#90a2b6;
--line:#26384b;--blue:#4ea3e0;--green:#5fd391;--orange:#e0a44e;--red:#e06b6b;}
*{box-sizing:border-box}
body{margin:0;font-family:Inter,system-ui,Arial,sans-serif;background:var(--bg);
color:var(--ink)}
.top{display:flex;align-items:center;justify-content:space-between;
padding:12px 20px;background:#0b121b;border-bottom:1px solid var(--line)}
.top h1{margin:0;font-size:17px;letter-spacing:.02em}
.top .sub{color:var(--muted);font-size:12px;margin-top:2px}
.pill{font-size:12px;color:#cfe;border:1px solid var(--line);border-radius:999px;
padding:5px 12px}
.bar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;padding:12px 20px;
background:#0d1620;border-bottom:1px solid var(--line)}
.bar label{font-size:11px;color:var(--muted);text-transform:uppercase;
letter-spacing:.06em;margin-right:4px}
.bar select,.bar input{background:#0b121b;color:var(--ink);border:1px solid
var(--line);border-radius:6px;padding:6px 8px;font:inherit}
.btn{background:var(--blue);color:#04121d;border:none;border-radius:6px;
padding:7px 14px;font-weight:700;cursor:pointer}
.btn.sec{background:#0b121b;color:var(--blue);border:1px solid var(--blue)}
.btn:disabled{opacity:.5;cursor:not-allowed}
.grid{display:grid;grid-template-columns:1fr 1fr 320px;gap:14px;padding:16px 20px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;
padding:12px}
.card h2{margin:0 0 8px;font-size:13px;color:var(--muted);text-transform:
uppercase;letter-spacing:.06em}
.card img{width:100%;border-radius:6px;background:#fff}
.m{display:flex;justify-content:space-between;gap:8px;padding:7px 4px;
border-bottom:1px solid var(--line);font-size:13px}
.ml{color:var(--muted)} .mv{font-weight:600;text-align:right}
.m.ok .mv{color:var(--green)} .m.warn .mv{color:var(--orange)}
.err{margin:16px 20px;padding:14px;background:#2a1414;border:1px solid #5a2a2a;
border-radius:8px;color:#f0b0b0;white-space:pre-wrap;font-family:monospace;
font-size:12px}
@media(max-width:1100px){.grid{grid-template-columns:1fr}}
"""


def render_page(state):
    cfg = state.cfg
    res = state.last
    err = state.last_err
    refresh = cfg["refresh"]
    auto = cfg.get("auto", True)

    def opt(val, cur):
        return f'<option value="{val}"{" selected" if val==cur else ""}>{val}</option>'

    fmt_opts = "".join(opt(v, cfg["format"]) for v in ("digital", "rf"))
    mod_opts = "".join(opt(v, cfg["mod"]) for v in
                       ("auto", "qpsk", "16qam", "64qam", "256qam"))

    meta_refresh = (f'<meta http-equiv="refresh" content="{refresh}">'
                    if auto else "")

    if err:
        body = f'<div class="err">PIPELINE ERROR:\n{html.escape(err)}</div>'
    elif res is None:
        body = '<div class="err">no result yet</div>'
    else:
        body = f"""
<div class="grid">
  <div class="card"><h2>Constellation</h2>
    <img src="data:image/png;base64,{res['png_const']}"></div>
  <div class="card"><h2>Channel  |H| / angle(H)</h2>
    <img src="data:image/png;base64,{res['png_chan']}"></div>
  <div class="card"><h2>Metrics</h2>
    {metrics_block(res, cfg.get('fs', 153.6e6))}</div>
</div>"""

    if err or res is None:
        status = "ERROR" if err else "—"
    else:
        tp = throughput_block(res, cfg.get("fs", 153.6e6))
        rate = f"{tp['gross_mbps']:.0f} Mbps {res['mod_name'].upper()}"
        ber_evm = (f"BER {res['ber']:.0e}" if res['ber'] is not None
                   else f"EVM {100*res['evm']:.2f}%")
        status = f"{rate} | {ber_evm}"

    return f"""<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
{meta_refresh}
<title>OFDM Scope — Constellation + Channel</title>
<style>{PAGE_CSS}</style></head><body>
<div class="top">
  <div><h1>OFDM Scope — Constellation + Channel</h1>
    <div class="sub">ZCU216 RX downstream demod (FFT &rarr; pilot CE &rarr; ZF EQ &rarr; QAM)</div></div>
  <div class="pill">{html.escape(cfg['capture'])} &nbsp;|&nbsp; {status}</div>
</div>
<form class="bar" method="get" action="/">
  <label>Capture</label>
  <input name="capture" value="{html.escape(cfg['capture'])}" size="46">
  <label>Format</label><select name="format">{fmt_opts}</select>
  <label>Mod</label><select name="mod">{mod_opts}</select>
  <label>Refresh(s)</label><input name="refresh" value="{refresh}" size="3">
  <label>Auto</label><input type="checkbox" name="auto" value="1" {"checked" if auto else ""}>
  <button class="btn sec" type="submit">Apply / Reload</button>
  <button class="btn" type="button" onclick="capnow(this)">Capture now</button>
  <span id="capmsg" style="color:var(--muted);font-size:12px"></span>
</form>
{body}
<script>
async function capnow(b){{
  b.disabled=true; var m=document.getElementById('capmsg'); m.textContent='triggering board capture...';
  try{{
    const r=await fetch('/api/capture',{{method:'POST'}}); const d=await r.json();
    m.textContent=d.message||'done';
    if(d.ok) setTimeout(()=>location.reload(),800);
  }}catch(e){{m.textContent='error: '+e;}}
  b.disabled=false;
}}
</script>
</body></html>"""


# ============================================================================
# LIVE client-side page: HTML5 canvas + vanilla JS, fetch /api/points loop.
# No PNG, no page reload -> smooth scope-like updates.
# ============================================================================
LIVE_CSS = """
:root{--bg:#0a0f16;--panel:#101a26;--ink:#e7eef6;--muted:#8aa0b6;
--line:#1e2e3f;--blue:#4ea3e0;--green:#5fd391;--orange:#e0a44e;--red:#e06b6b;
--grid:#1a2a3a;--axis:#33506a;}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{font-family:Inter,system-ui,Arial,sans-serif;background:var(--bg);
color:var(--ink)}
.top{display:flex;align-items:center;justify-content:space-between;
padding:10px 18px;background:#060b11;border-bottom:1px solid var(--line)}
.top h1{margin:0;font-size:16px;letter-spacing:.02em}
.top .sub{color:var(--muted);font-size:11px;margin-top:2px}
.top a{color:var(--blue);font-size:12px;text-decoration:none}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;
background:#456;margin-right:6px;vertical-align:middle}
.dot.live{background:var(--green);box-shadow:0 0 8px var(--green)}
.dot.stop{background:var(--orange)}
.dot.err{background:var(--red)}
.bar{display:flex;gap:10px;flex-wrap:wrap;align-items:center;padding:10px 18px;
background:#0a121c;border-bottom:1px solid var(--line)}
.bar label{font-size:11px;color:var(--muted);text-transform:uppercase;
letter-spacing:.05em}
.bar input[type=range]{vertical-align:middle}
.btn{background:var(--blue);color:#04121d;border:none;border-radius:6px;
padding:6px 13px;font-weight:700;cursor:pointer}
.btn.sec{background:#0b121b;color:var(--blue);border:1px solid var(--blue)}
.btn:disabled{opacity:.5;cursor:not-allowed}
.wrap{display:grid;grid-template-columns:minmax(360px,1fr) minmax(360px,1fr) 300px;
gap:12px;padding:14px 18px;align-items:start}
.card{background:var(--panel);border:1px solid var(--line);border-radius:10px;
padding:10px}
.card h2{margin:0 0 8px;font-size:12px;color:var(--muted);text-transform:
uppercase;letter-spacing:.06em}
canvas{width:100%;height:auto;display:block;border-radius:6px;background:#070d14}
.m{display:flex;justify-content:space-between;gap:8px;padding:6px 3px;
border-bottom:1px solid var(--line);font-size:13px}
.ml{color:var(--muted)} .mv{font-weight:600;text-align:right;font-variant-numeric:tabular-nums}
.m.ok .mv{color:var(--green)} .m.warn .mv{color:var(--orange)}
.foot{color:var(--muted);font-size:11px;padding:0 18px 14px}
@media(max-width:1150px){.wrap{grid-template-columns:1fr}}
"""

# JS kept as a plain string (no .format) -> use __TOKEN__ placeholders.
LIVE_JS = r"""
(function(){
  const Q = new URLSearchParams(location.search);
  let refreshMs = parseInt(Q.get('refresh_ms')||'__REFRESH_MS__',10);
  if(!(refreshMs>=30)) refreshMs = __REFRESH_MS__;
  let polling = true, timer=null, inflight=false, lastMtime=null, frames=0;

  const $ = id => document.getElementById(id);
  const dot = $('dot'), statusTxt=$('statusTxt');
  const slider=$('refresh'), refOut=$('refOut');
  const cv = $('cvConst'), cx = cv.getContext('2d');
  const ch = $('cvChan'),  hx = ch.getContext('2d');
  refOut.textContent = refreshMs+' ms'; slider.value = refreshMs;

  // ---- 12 distinct symbol colors (turbo-ish) ----
  const SYMCOL = ['#3b4cc0','#3b73e8','#39a0f0','#2bcad0','#3fdf9b','#7ef25a',
                  '#c6ef3a','#f4d13a','#f7a52a','#f3701c','#dd400f','#b40426'];
  function symColor(s){ return SYMCOL[((s%12)+12)%12]; }

  // ---- HiDPI canvas sizing ----
  function fit(canvas){
    const dpr = window.devicePixelRatio||1;
    const w = canvas.clientWidth||520;
    const h = parseInt(canvas.dataset.h||'520',10);
    canvas.style.height = h+'px';
    if(canvas.width!==Math.round(w*dpr)||canvas.height!==Math.round(h*dpr)){
      canvas.width=Math.round(w*dpr); canvas.height=Math.round(h*dpr);
    }
    return {w:canvas.width, h:canvas.height, dpr};
  }

  // ---- Constellation ----
  function drawConst(d){
    const g=cx, {w,h}=fit(cv);
    g.clearRect(0,0,w,h); g.fillStyle='#070d14'; g.fillRect(0,0,w,h);
    const c=d.const;
    // range from ideal grid + points
    let lim=1.0;
    for(const v of c.ideal_I) lim=Math.max(lim,Math.abs(v));
    for(const v of c.ideal_Q) lim=Math.max(lim,Math.abs(v));
    lim*=1.35;
    const pad=Math.min(w,h)*0.06, S=(Math.min(w,h)-2*pad)/(2*lim);
    const cxp=w/2, cyp=h/2;
    const X=v=>cxp+v*S, Y=v=>cyp-v*S;
    // grid
    g.strokeStyle='#152433'; g.lineWidth=1;
    for(let i=-Math.ceil(lim);i<=Math.ceil(lim);i++){
      g.beginPath(); g.moveTo(X(i),0); g.lineTo(X(i),h); g.stroke();
      g.beginPath(); g.moveTo(0,Y(i)); g.lineTo(w,Y(i)); g.stroke();
    }
    // axes
    g.strokeStyle='#33506a'; g.lineWidth=1.4;
    g.beginPath(); g.moveTo(0,Y(0)); g.lineTo(w,Y(0)); g.stroke();
    g.beginPath(); g.moveTo(X(0),0); g.lineTo(X(0),h); g.stroke();
    // unit circle
    g.strokeStyle='rgba(78,163,224,.25)'; g.beginPath();
    g.arc(X(0),Y(0),S,0,2*Math.PI); g.stroke();
    // points
    const I=c.I,Qa=c.Q,sym=c.sym,n=I.length,r=Math.max(1.2,2.2*(window.devicePixelRatio||1));
    for(let i=0;i<n;i++){
      g.fillStyle=symColor(sym[i]); g.globalAlpha=0.7;
      g.beginPath(); g.arc(X(I[i]),Y(Qa[i]),r,0,6.283); g.fill();
    }
    g.globalAlpha=1;
    // ideal grid markers (+)
    g.strokeStyle='#dfe8f2'; g.lineWidth=1.6;
    const m=4*(window.devicePixelRatio||1);
    for(let i=0;i<c.ideal_I.length;i++){
      const px=X(c.ideal_I[i]),py=Y(c.ideal_Q[i]);
      g.beginPath(); g.moveTo(px-m,py); g.lineTo(px+m,py);
      g.moveTo(px,py-m); g.lineTo(px,py+m); g.stroke();
    }
    // label
    g.fillStyle='#8aa0b6'; g.font=(13*(window.devicePixelRatio||1))+'px sans-serif';
    g.fillText((d.metrics.mod||'').toUpperCase()+'  '+c.n_sym+' sym x '+
               c.n_data_sc+' SC', 10*(window.devicePixelRatio||1),
               20*(window.devicePixelRatio||1));
  }

  // ---- Channel |H| (dB, top half) + angle (deg, bottom half) ----
  function drawChan(d){
    const g=hx,{w,h}=fit(ch);
    g.clearRect(0,0,w,h); g.fillStyle='#070d14'; g.fillRect(0,0,w,h);
    const c=d.chan, N=c.sc.length;
    const padL=44*(window.devicePixelRatio||1), padR=10*(window.devicePixelRatio||1);
    const plotW=w-padL-padR;
    const topH=h*0.5, botY=h*0.55, botH=h*0.42;
    const xk=k=>padL+(k/(N-1))*plotW;
    // ---- |H| dB ----
    let mn=Infinity,mx=-Infinity;
    for(const v of c.magdb){ if(v==null)continue; if(v<mn)mn=v; if(v>mx)mx=v; }
    if(!isFinite(mn)){mn=-60;mx=0;} if(mx-mn<6){mx+=3;mn-=3;}
    const yMag=v=>{ if(v==null)v=mn; return 6+(1-(v-mn)/(mx-mn))*(topH-12); };
    g.strokeStyle='#142233'; g.lineWidth=1;
    for(let i=0;i<=4;i++){ const yy=6+i/4*(topH-12);
      g.beginPath(); g.moveTo(padL,yy); g.lineTo(w-padR,yy); g.stroke(); }
    g.strokeStyle='#4ea3e0'; g.lineWidth=1.6; g.beginPath();
    for(let k=0;k<N;k++){ const X=xk(k),Yv=yMag(c.magdb[k]);
      if(k===0)g.moveTo(X,Yv); else g.lineTo(X,Yv); } g.stroke();
    // pilots
    g.fillStyle='#e0a44e';
    for(const pk of c.pilot_idx){ g.beginPath();
      g.arc(xk(pk),yMag(c.magdb[pk]),3*(window.devicePixelRatio||1),0,6.283); g.fill(); }
    g.fillStyle='#8aa0b6'; g.font=(12*(window.devicePixelRatio||1))+'px sans-serif';
    g.fillText('|H| dB',6,14*(window.devicePixelRatio||1));
    // ---- angle deg ----
    const yAng=v=>{ if(v==null)v=0; return botY+(1-(v+180)/360)*botH; };
    g.strokeStyle='#142233'; g.lineWidth=1;
    for(let i=0;i<=4;i++){ const yy=botY+i/4*botH;
      g.beginPath(); g.moveTo(padL,yy); g.lineTo(w-padR,yy); g.stroke(); }
    g.strokeStyle='#5fd391'; g.lineWidth=1.6; g.beginPath();
    for(let k=0;k<N;k++){ const X=xk(k),Yv=yAng(c.angdeg[k]);
      if(k===0)g.moveTo(X,Yv); else g.lineTo(X,Yv); } g.stroke();
    g.fillStyle='#e0a44e';
    for(const pk of c.pilot_idx){ g.beginPath();
      g.arc(xk(pk),yAng(c.angdeg[pk]),3*(window.devicePixelRatio||1),0,6.283); g.fill(); }
    g.fillStyle='#8aa0b6';
    g.fillText('angle(H) deg  (-180..180)',6,botY+13*(window.devicePixelRatio||1));
    g.fillText('subcarrier k',w-90*(window.devicePixelRatio||1),h-4);
  }

  // ---- Metrics panel ----
  function row(k,v,cls){ return '<div class="m '+(cls||'')+'"><span class="ml">'+
    k+'</span><span class="mv">'+v+'</span></div>'; }
  function drawMetrics(d){
    const m=d.metrics;
    let berCls='', berS='n/a (no golden)';
    if(m.ber!==null){ berS=m.ber.toExponential(2)+'  ('+m.nerr+'/'+m.nbits+')';
      berCls = m.ber===0 ? 'ok':'warn'; }
    const evmCls = (m.evm_pct!=null && m.evm_pct<10)?'ok':'';
    let h='';
    h+=row('Modulation',(m.mod||'').toUpperCase());
    // ---- live PHY throughput (gross / framed / goodput) ----
    const tp=d.throughput;
    if(tp){
      const mod=(m.mod||'').toUpperCase();
      h+=row('PHY (gross)',(tp.gross_mbps==null?'-':tp.gross_mbps.toFixed(1)+' Mbps'),'ok');
      h+=row('Framed',(tp.framed_mbps==null?'-':tp.framed_mbps.toFixed(1)+' Mbps'));
      h+=row('Goodput',(tp.goodput_mbps==null?'-':tp.goodput_mbps.toFixed(1)+' Mbps'),
             (tp.goodput_mbps!=null && tp.gross_mbps!=null && tp.goodput_mbps<tp.gross_mbps)?'warn':'ok');
      h+=row('Throughput cfg',mod+' @'+(tp.fs_msps==null?'-':tp.fs_msps.toFixed(1))+
             'Msps ('+tp.bits_per_sc+' b/SC)');
    }
    h+=row('BER vs golden',berS,berCls);
    h+=row('EVM (rms)',(m.evm_pct==null?'-':m.evm_pct.toFixed(3)+' %'),evmCls);
    h+=row('SNR est',(m.snr_db==null?'-':m.snr_db.toFixed(1)+' dB'));
    if(m.demo){
      h+=row('SNR commanded',(m.demo_snr_cmd==null?'-':m.demo_snr_cmd.toFixed(1)+' dB'),'ok');
      h+=row('Fade tap2 gain',(m.demo_tap2_g==null?'-':m.demo_tap2_g.toFixed(3)));
      h+=row('Fade tap2 delay',(m.demo_tap2_delay==null?'-':m.demo_tap2_delay.toFixed(2)+' smp'));
      h+=row('Demo t',(m.demo_t==null?'-':m.demo_t.toFixed(1)+' s'));
    }
    h+=row('Symbols',m.n_symbols+' / 12');
    h+=row('Data SC/sym',m.n_data_sc);
    h+=row('Slot start',m.slot_start+'  ['+(m.sync_method||'')+']');
    h+=row('Sync peak',m.peak==null?'-':m.peak);
    h+=row('CFO',(m.rf||m.demo)?((m.cfo==null?'-':m.cfo)+' ('+(m.cfo_hz/1e3).toFixed(1)+' kHz)'):'0 (digital)');
    h+=row('Capture RMS',m.rms==null?'-':m.rms);
    h+=row('Capture',m.capture+' ('+m.nsamp+')');
    h+=row('Demod @',d.ts||'-');
    h+=row('Frames drawn',frames);
    $('metrics').innerHTML=h;
  }

  function setStatus(cls,txt){ dot.className='dot '+cls; statusTxt.textContent=txt; }

  async function tick(){
    if(inflight) return; inflight=true;
    try{
      const r=await fetch('/api/points',{cache:'no-store'});
      const d=await r.json();
      if(!d.ok){ setStatus('err', d.error?('error: '+d.error.split('\n')[0]):'no data');
        inflight=false; return; }
      frames++;
      drawConst(d); drawChan(d); drawMetrics(d);
      lastMtime=d.mtime;
      let tpS='';
      if(d.throughput && d.throughput.goodput_mbps!=null){
        tpS = '  '+d.throughput.goodput_mbps.toFixed(1)+' Mbps';
      }
      setStatus(polling?'live':'stop',
        (polling?'LIVE ':'PAUSED ')+ (d.metrics.ber===0?'BER 0':
          (d.metrics.evm_pct!=null?('EVM '+d.metrics.evm_pct.toFixed(2)+'%'):''))+tpS);
    }catch(e){ setStatus('err','fetch error: '+e); }
    inflight=false;
  }

  function schedule(){ if(timer) clearInterval(timer);
    if(polling) timer=setInterval(tick, refreshMs); }

  $('toggle').onclick=function(){ polling=!polling;
    this.textContent=polling?'Stop':'Start';
    setStatus(polling?'live':'stop',polling?'LIVE':'PAUSED');
    schedule(); if(polling) tick(); };

  slider.oninput=function(){ refreshMs=parseInt(this.value,10);
    refOut.textContent=refreshMs+' ms'; schedule(); };

  $('capnow').onclick=async function(){
    this.disabled=true; const m=$('capmsg'); m.textContent='triggering capture...';
    try{ const r=await fetch('/api/capture',{method:'POST'}); const d=await r.json();
      m.textContent=d.message||'done'; if(d.ok) setTimeout(tick,500); }
    catch(e){ m.textContent='error: '+e; }
    this.disabled=false;
  };

  window.addEventListener('resize', ()=>{ if(lastMtime!==null) tick(); });
  // first paint + start loop
  tick(); schedule();
})();
"""


def render_live_page(state):
    """Self-contained live page: canvas + vanilla JS polling /api/points."""
    cfg = state.cfg
    refresh_ms = int(cfg.get("refresh_ms", 200))
    js = (LIVE_JS
          .replace("__REFRESH_MS__", str(refresh_ms)))
    cap = html.escape(cfg.get("capture", ""))
    return f"""<!doctype html><html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>OFDM Live Scope</title>
<style>{LIVE_CSS}</style></head><body>
<div class="top">
  <div><h1><span id="dot" class="dot live"></span>OFDM Live Scope
    &mdash; <span id="statusTxt">starting...</span></h1>
    <div class="sub">client-side canvas &middot; fetch /api/points &middot; no PNG, no reload
      &middot; <a href="/png">legacy PNG view</a></div></div>
  <div class="sub">{cap}</div>
</div>
<div class="bar">
  <button id="toggle" class="btn">Stop</button>
  <label>Refresh</label>
  <input id="refresh" type="range" min="50" max="2000" step="50" value="{refresh_ms}">
  <span id="refOut" style="min-width:64px;color:var(--muted)"></span>
  <button id="capnow" class="btn sec">Capture now</button>
  <span id="capmsg" style="color:var(--muted);font-size:12px"></span>
</div>
<div class="wrap">
  <div class="card"><h2>Constellation</h2>
    <canvas id="cvConst" data-h="520"></canvas></div>
  <div class="card"><h2>Channel  |H| (dB) / angle(H) (deg)</h2>
    <canvas id="cvChan" data-h="520"></canvas></div>
  <div class="card"><h2>Metrics</h2><div id="metrics"></div></div>
</div>
<div class="foot">Drag the Refresh slider to set the poll interval. Start/Stop
pauses polling. "Capture now" runs the configured board capture (if any) then
refetches. Symbol colors index the 12 OFDM data symbols.</div>
<script>{js}</script>
</body></html>"""


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        server_version = "OfdmScopeGui/1.0"

        def _send(self, body, ctype="text/html; charset=utf-8", status=200):
            data = body.encode("utf-8") if isinstance(body, str) else body
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def _apply_query(self):
            from urllib.parse import urlparse, parse_qs
            q = parse_qs(urlparse(self.path).query)
            changed = False
            for key in ("capture", "format", "mod"):
                if key in q:
                    state.cfg[key] = q[key][0]; changed = True
            if "refresh" in q:
                try:
                    state.cfg["refresh"] = max(1, int(q["refresh"][0]))
                except ValueError:
                    pass
            # checkbox: present only when checked
            if urlparse(self.path).query:
                state.cfg["auto"] = ("auto" in q)
            return changed or bool(urlparse(self.path).query)

        def do_GET(self):
            try:
                path = self.path.split("?")[0]
                # ---- LIVE client-side canvas page (default) ----
                if path in ("/", "/live", "/index.html"):
                    self._apply_query()
                    self._send(render_live_page(state))
                # ---- legacy / fallback PNG page (matplotlib) ----
                elif path == "/png":
                    self._apply_query()
                    state.compute(render_png=True)
                    self._send(render_page(state))
                # ---- JSON data endpoint for the live canvas ----
                elif path == "/api/points":
                    res, err = state.compute_cached(render_png=False)
                    if err or res is None:
                        out = {"ok": False, "error": err or "no result"}
                    else:
                        out = points_json(res, state.cfg.get("fs", 153.6e6))
                    self._send(json.dumps(out), "application/json")
                elif path == "/api/state":
                    res, err = state.last, state.last_err
                    out = {"error": err} if err else {
                        "ber": res["ber"] if res else None,
                        "evm": res["evm"] if res else None,
                        "mod": res["mod_name"] if res else None,
                        "ts": res["ts"] if res else None,
                    }
                    self._send(json.dumps(out), "application/json")
                elif path == "/healthz":
                    self._send("ok", "text/plain")
                else:
                    self._send("not found", "text/plain",
                               HTTPStatus.NOT_FOUND)
            except Exception as exc:
                self._send(f"server error: {exc}", "text/plain", 500)

        def do_POST(self):
            if self.path.split("?")[0] != "/api/capture":
                self._send(json.dumps({"ok": False, "message": "not found"}),
                           "application/json", HTTPStatus.NOT_FOUND)
                return
            cmd = state.cfg.get("capture_cmd")
            if not cmd:
                self._send(json.dumps({
                    "ok": False,
                    "message": "board capture disabled (no --capture-cmd); "
                               "file-replay mode. The page still auto-refreshes "
                               "the current capture file."}),
                    "application/json")
                return
            try:
                proc = subprocess.run(cmd, shell=True, cwd=REPO_ROOT,
                                      capture_output=True, text=True,
                                      timeout=state.cfg.get("capture_timeout",
                                                            240))
                state.compute()
                ok = proc.returncode == 0
                self._send(json.dumps({
                    "ok": ok,
                    "message": (f"capture cmd rc={proc.returncode}; re-rendered"
                                if ok else
                                f"capture cmd FAILED rc={proc.returncode}: "
                                f"{proc.stderr[-200:]}")}),
                    "application/json")
            except subprocess.TimeoutExpired:
                self._send(json.dumps({"ok": False,
                                       "message": "capture cmd timed out"}),
                           "application/json")
            except Exception as exc:
                self._send(json.dumps({"ok": False, "message": str(exc)}),
                           "application/json")

        def log_message(self, fmt, *args):
            print(f"[gui] {self.address_string()} - {fmt % args}")

    return Handler


# ============================================================================
# main
# ============================================================================
def main():
    global _PLT
    ap = argparse.ArgumentParser(
        description="Real-time OFDM constellation + channel scope GUI")
    ap.add_argument("--capture", default=None,
                    help="path to capture .bin/.hex/.npy "
                         "(not required in --demo mode)")
    ap.add_argument("--format", choices=["digital", "rf"], default="digital",
                    help="capture format (default: digital golden/loopback)")
    ap.add_argument("--mod", default="16qam",
                    choices=["auto", "qpsk", "16qam", "64qam", "256qam"],
                    help="modulation (or 'auto' to detect by lowest EVM)")
    ap.add_argument("--refresh", type=int, default=5,
                    help="legacy PNG page auto-refresh period seconds (default 5)")
    ap.add_argument("--refresh-ms", type=int, default=200,
                    help="live page poll interval in ms (default 200)")
    ap.add_argument("--cache-ttl", type=float, default=0.5,
                    help="seconds to reuse a cached demod for /api/points "
                         "(default 0.5); file-mtime change forces a re-demod")
    ap.add_argument("--no-auto", action="store_true",
                    help="disable legacy PNG page auto-refresh")
    ap.add_argument("--fs", type=float, default=153.6e6,
                    help="sample rate (Hz) for the live THROUGHPUT metric "
                         "(default 153.6e6 = RF DDC baseband; board sustained "
                         "is 162e6)")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--capture-cmd", default=None,
                    help="shell cmd run by 'Capture now' (e.g. "
                         "'scripts/run_rfsync.sh mylabel'); off if unset")
    ap.add_argument("--board", action="store_true",
                    help="shortcut: --capture-cmd 'scripts/run_rfsync.sh gui'")
    # ---- ANIMATED DEMO mode ----
    ap.add_argument("--demo", action="store_true",
                    help="animated demo: synthesize a TIME-VARYING received "
                         "OFDM signal from the golden TX each poll (no board / "
                         "no capture file). Constellation + channel + EVM/BER "
                         "move smoothly in real time.")
    ap.add_argument("--demo-cycle-mod", action="store_true", default=False,
                    help="in --demo mode, cycle QPSK->16->64->256-QAM over "
                         "--demo-t-mod seconds (constellation density changes)")
    ap.add_argument("--no-demo-cycle-mod", dest="demo_cycle_mod",
                    action="store_false",
                    help="disable the demo modulation cycle (hold --mod)")
    ap.add_argument("--demo-t-cfo", type=float, default=12.0,
                    help="demo residual-CFO rotation period (s, default 12)")
    ap.add_argument("--demo-cfo-amp", type=float, default=8e-5,
                    help="demo residual-CFO amplitude (cyc/sample, default "
                         "8e-5 ~ +/-12 kHz @153.6 Msps)")
    ap.add_argument("--demo-t-snr", type=float, default=9.0,
                    help="demo SNR-breathing period (s, default 9)")
    ap.add_argument("--demo-snr0", type=float, default=28.0,
                    help="demo SNR breathing center (dB, default 28)")
    ap.add_argument("--demo-snr-amp", type=float, default=12.0,
                    help="demo SNR breathing amplitude (dB, default 12 -> "
                         "16..40 dB)")
    ap.add_argument("--demo-t-fade", type=float, default=15.0,
                    help="demo channel-fade tap-gain period (s, default 15)")
    ap.add_argument("--demo-t-mod", type=float, default=24.0,
                    help="demo modulation-cycle period (s, default 24 -> 6 s "
                         "per modulation)")
    args = ap.parse_args()

    if not args.demo and not args.capture:
        ap.error("--capture is required unless --demo is given")

    _PLT = _load_golden_pilots()

    capture_cmd = args.capture_cmd
    if args.board and not capture_cmd:
        capture_cmd = "scripts/run_rfsync.sh gui"

    # demo mode: synthetic time-varying impairment periods (seconds) chosen so
    # motion is visible but not dizzying (few seconds to tens of seconds).
    demo_periods = {
        "T_cfo": max(0.5, args.demo_t_cfo),
        "A_cfo": args.demo_cfo_amp,
        "T_snr": max(0.5, args.demo_t_snr),
        "SNR0": args.demo_snr0,
        "SNR_A": args.demo_snr_amp,
        "T_fade": max(0.5, args.demo_t_fade),       # tap-gain breathing
        "T_fade_d": max(0.5, args.demo_t_fade * 1.7),  # tap-delay slide
        "T_fade_ph": max(0.5, args.demo_t_fade * 0.8),  # tap-phase spin
        "TAP2_G": 0.30,                              # max 2nd-tap gain
        "TAP2_DMAX": 6.0,                            # max 2nd-tap delay (smp)
        "T_mod": max(2.0, args.demo_t_mod),
    }

    # in demo mode default the capture label + a short cache TTL so the
    # animation stays fresh while keeping per-request compute light.
    demo_ttl = min(args.cache_ttl, 0.15) if args.demo else args.cache_ttl
    cfg = {
        "capture": args.capture or "[DEMO synth]",
        "format": "demo" if args.demo else args.format,
        "mod": args.mod,
        "refresh": max(1, args.refresh),
        "refresh_ms": max(30, args.refresh_ms),
        "cache_ttl": max(0.0, demo_ttl),
        "auto": not args.no_auto,
        "fs": float(args.fs),
        "capture_cmd": capture_cmd,
        "capture_timeout": 240,
        "render_png": True,
        # ---- demo ----
        "demo": bool(args.demo),
        "demo_cycle_mod": bool(args.demo_cycle_mod),
        "demo_periods": demo_periods,
        "demo_t0": time.time(),
    }
    state = State(cfg)
    # warm compute so first page is instant (PNG off; live page uses JSON)
    state.compute(render_png=False)
    if state.last_err:
        print("[warn] initial demod failed:\n" + state.last_err)
    else:
        r = state.last
        print(f"[ok] initial render: mod={r['mod_name']} "
              f"BER={r['ber']} EVM={100*r['evm']:.3f}% "
              f"n_sym={r['n_sym']} rms={r['rms']:.3g}")

    httpd = ThreadingHTTPServer((args.host, args.port), make_handler(state))
    if args.demo:
        p = demo_periods
        print(f"OFDM LIVE scope GUI [ANIMATED DEMO]: "
              f"http://{args.host}:{args.port}/  (synth from golden TX, "
              f"mod={args.mod}, cycle_mod={cfg['demo_cycle_mod']})")
        print(f"  impairment periods: CFO {p['T_cfo']}s "
              f"(amp {p['A_cfo']:.1e} cyc/smp), SNR {p['T_snr']}s "
              f"({p['SNR0']:.0f}+/-{p['SNR_A']:.0f} dB), fade {p['T_fade']}s, "
              f"mod-cycle {p['T_mod']}s")
    else:
        print(f"OFDM LIVE scope GUI: http://{args.host}:{args.port}/  "
              f"(capture={args.capture}, format={args.format}, mod={args.mod})")
    print(f"  live canvas page: /  (poll /api/points every "
          f"{cfg['refresh_ms']} ms)   legacy PNG page: /png")
    print(f"  throughput metric Fs = {cfg['fs']/1e6:.1f} Msps "
          f"(gross = 2652 * bits/SC * Fs/4032)")
    if capture_cmd:
        print(f"  board capture enabled: {capture_cmd}")
    else:
        print("  file-replay mode (no board trigger)")
    sys.stdout.flush()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nshutting down")


if __name__ == "__main__":
    main()
