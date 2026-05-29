#!/usr/bin/env python3
"""
gen_phase3_iq_stimulus.py
Deterministic IQ stimulus generator for Phase 3 golden comparison.

Generates three files:
  golden/phase3_iq_stimulus.f32        — binary float32 interleaved I0 Q0 I1 Q1 ...
  golden/phase3_iq_stimulus.mem        — hex, one 32-bit word per line: {Q[15:0], I[15:0]}
  golden/phase3_iq_stimulus_meta.json  — metadata + expected synchronisation indices

Signal structure (total = 704 samples):
  [PRE_ZEROS=64] [CP1=32 | S1=256] [CP2=32 | S2=256] [POST_ZEROS=64]

CP is the exact last CP_LEN samples of each IFFT symbol — VanDeBeek autocorrelation peaks
at the CP/tail alignment lag.  Fractional CFO rotates the phase of the full frame.

The generator re-runs the C-reference frame_detector and auto_corr algorithms
(exact translation from scripts/golden_dump.c) to record deterministic expected
values; these will match golden_dump output for the same .f32 input.
"""

import numpy as np
import json
import os

# ── Stimulus parameters ──────────────────────────────────────────────────────
NSC         = 256
CP_LEN      = 32
FRAME_LEN   = 2 * (NSC + CP_LEN)   # 576 (one slot = 2 symbols with CPs)
PRE_ZEROS   = 64
POST_ZEROS  = 64
TARGET_PEAK = 3000.0                # max |I| or |Q| in float domain
EPS_FRAC    = 0.05                  # fractional CFO in subcarrier spacings
INT_CFO     = 0
NOISE_ON    = False
SEED        = 0xC0FFEE

# Reference algorithm constants (must match golden_dump.c)
WND_LEN   = 25
THRESHOLD = 40000.0


# ── OFDM symbol builder ──────────────────────────────────────────────────────
def _make_ofdm_symbol(rng, nsc, cp_len):
    """QPSK subcarriers → IFFT → prepend CP (= exact copy of symbol tail)."""
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=nsc)
    freq   = table[angles]
    td     = np.fft.ifft(freq)     # length nsc; numpy normalises by N
    cp     = td[-cp_len:]          # last cp_len samples — exact CP copy
    return np.concatenate([cp, td])  # [CP | symbol], length = cp_len + nsc


# ── Frame assembly ───────────────────────────────────────────────────────────
def gen_frame():
    """Return 704-sample complex128 frame ready for float32 serialisation."""
    rng  = np.random.default_rng(SEED)
    sym1 = _make_ofdm_symbol(rng, NSC, CP_LEN)   # 288 samples
    sym2 = _make_ofdm_symbol(rng, NSC, CP_LEN)   # 288 samples

    frame = np.concatenate([
        np.zeros(PRE_ZEROS,  dtype=np.complex128),
        sym1,
        sym2,
        np.zeros(POST_ZEROS, dtype=np.complex128),
    ])  # 64 + 288 + 288 + 64 = 704

    # Peak-normalise: max per-component float = TARGET_PEAK.
    # Operating on the signal portion only keeps zeros at exactly 0.
    sig = np.concatenate([sym1, sym2])
    peak = max(np.abs(sig.real).max(), np.abs(sig.imag).max())
    if peak > 0.0:
        scale = TARGET_PEAK / peak
        frame = frame * scale

    # Apply fractional CFO: x[n] *= exp(j*2*pi*eps*n/NSC)
    n     = np.arange(len(frame), dtype=np.float64)
    frame = frame * np.exp(1j * 2.0 * np.pi * EPS_FRAC * n / NSC)

    return frame


# ── C-reference algorithms (direct translation of golden_dump.c) ─────────────
def _frame_detector(I, Q, wnd_len, threshold):
    """Mirror of golden_dump.c frame_detector(). Returns indexFrame or -1."""
    half = len(I) // 2 + 10

    # Sliding window energy using cumsum for efficiency
    energy = I[:half + wnd_len] ** 2 + Q[:half + wnd_len] ** 2
    cum    = np.empty(half + wnd_len + 1, dtype=np.float64)
    cum[0] = 0.0
    np.cumsum(energy, out=cum[1:])
    env = (cum[wnd_len: wnd_len + half] - cum[:half]) / wnd_len

    if env[0] < threshold:       # Case A
        ctr = 0
        for j in range(1, half):
            if env[j] > threshold:
                ctr += 1
                if ctr == 10:
                    return j + 1 - 10
            else:
                ctr = 0
    else:                        # Case B
        start_idx = 0
        for j in range(1, half):
            if env[j] < threshold:
                start_idx = j
                break
        if start_idx > 0:
            ctr = 0
            for j in range(start_idx, half):
                if env[j] > threshold:
                    ctr += 1
                    if ctr == 10:
                        return j + 1 - 10
                else:
                    ctr = 0
    return -1


def _auto_corr(I, Q, nsc, cp_len):
    """Mirror of golden_dump.c auto_corr(). Returns (P_I, P_Q, normVal)."""
    P_I = np.zeros(nsc, dtype=np.float64)
    P_Q = np.zeros(nsc, dtype=np.float64)
    E   = np.zeros(nsc, dtype=np.float64)
    for m in range(nsc):
        aI = I[m:m+cp_len]
        aQ = Q[m:m+cp_len]
        bI = I[m+nsc:m+nsc+cp_len]
        bQ = Q[m+nsc:m+nsc+cp_len]
        P_I[m] = float(np.sum(aI * bI + aQ * bQ))
        P_Q[m] = float(np.sum(-aI * bQ + aQ * bI))
        E[m]   = float(np.sum(aI**2 + aQ**2 + bI**2 + bQ**2))
    return P_I, P_Q, E


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    golden_dir = os.path.join(root, "golden")
    os.makedirs(golden_dir, exist_ok=True)

    # Generate
    frame = gen_frame()
    N     = len(frame)
    I     = frame.real.astype(np.float32)
    Q     = frame.imag.astype(np.float32)
    print(f"[gen] {N} samples  peak_I={float(np.abs(I).max()):.1f}"
          f"  peak_Q={float(np.abs(Q).max()):.1f}")

    # ── Write .f32 ────────────────────────────────────────────────────────────
    f32_path = os.path.join(golden_dir, "phase3_iq_stimulus.f32")
    iq_flat = np.empty(2 * N, dtype=np.float32)
    iq_flat[0::2] = I
    iq_flat[1::2] = Q
    iq_flat.tofile(f32_path)
    print(f"[gen] Written {N} float32 IQ pairs → {f32_path}")

    # ── Write .mem ────────────────────────────────────────────────────────────
    mem_path = os.path.join(golden_dir, "phase3_iq_stimulus.mem")
    with open(mem_path, "w") as fmem:
        for i_f, q_f in zip(I, Q):
            i16 = int(max(-32768, min(32767, round(float(i_f))))) & 0xFFFF
            q16 = int(max(-32768, min(32767, round(float(q_f))))) & 0xFFFF
            fmem.write(f"{q16:04X}{i16:04X}\n")
    print(f"[gen] Written {N} Q15 hex words → {mem_path}")

    # ── Run reference algorithms (mirrors golden_dump.c) ─────────────────────
    I64 = I.astype(np.float64)
    Q64 = Q.astype(np.float64)

    frame_start = _frame_detector(I64, Q64, WND_LEN, THRESHOLD)
    detection_ok = (frame_start >= 0)
    if not detection_ok:
        print("[gen] WARNING: frame_detector returned -1 "
              "(signal energy below threshold). Falling back to 0.")
        frame_start = 0
    print(f"[gen] frame_start = {frame_start}  detection_ok={detection_ok}")

    P_I, P_Q, E_norm = _auto_corr(I64[frame_start:], Q64[frame_start:], NSC, CP_LEN)
    metric   = 2.0 * np.sqrt(P_I**2 + P_Q**2) - E_norm
    peak_idx = int(np.argmax(metric))
    slot_start   = peak_idx + frame_start
    frac_cfo_out = float(-np.arctan2(P_Q[peak_idx], P_I[peak_idx]) / (2.0 * np.pi))

    print(f"[gen] peakIndexAuto  = {peak_idx}")
    print(f"[gen] slotStartIndex = {slot_start}")
    print(f"[gen] fracfreqOffset = {frac_cfo_out:.9g}")

    # ── Write metadata ────────────────────────────────────────────────────────
    meta = {
        "nsamples_total"               : N,
        "pre_zeros"                    : PRE_ZEROS,
        "post_zeros"                   : POST_ZEROS,
        "nsc"                          : NSC,
        "cp_len"                       : CP_LEN,
        "frame_len"                    : FRAME_LEN,
        "expected_frame_start"         : frame_start,
        "expected_peak_index_auto"     : peak_idx,
        "expected_pss_start"           : PRE_ZEROS,
        "expected_sss_start"           : PRE_ZEROS + NSC + CP_LEN,
        "expected_slot_start_approx"   : slot_start,
        "expected_frac_cfo_offset"     : frac_cfo_out,
        "eps_frac"                     : EPS_FRAC,
        "integer_cfo"                  : INT_CFO,
        "amplitude_peak_per_component" : TARGET_PEAK,
        "noise_snr"                    : "off",
        "seed"                         : SEED,
        "detection_ok"                 : detection_ok,
        "file_format": {
            "f32": "binary little-endian float32, interleaved: I0 Q0 I1 Q1 ...",
            "mem": "ASCII hex, one 32-bit word per line: {Q[15:0], I[15:0]}, "
                   "signed clamp to int16 (same packing as RTL s_axis_tdata)"
        },
        "notes": (
            f"frame_start={frame_start}: first of 10 consecutive windows above "
            f"threshold={THRESHOLD} (wnd={WND_LEN}). "
            f"peakIndexAuto={peak_idx}: lag of CP/tail alignment relative to frameStart. "
            f"slotStartIndex={slot_start}=peakIndexAuto+frameStart=PRE_ZEROS. "
            f"fracfreqOffset≈+eps_frac={EPS_FRAC} (CP autocorr phase encodes CFO)."
        )
    }
    meta_path = os.path.join(golden_dir, "phase3_iq_stimulus_meta.json")
    with open(meta_path, "w") as fj:
        json.dump(meta, fj, indent=2)
        fj.write("\n")
    print(f"[gen] Written metadata → {meta_path}")
    print("[gen] Done.")


if __name__ == "__main__":
    main()
