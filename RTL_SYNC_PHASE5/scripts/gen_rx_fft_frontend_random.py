#!/usr/bin/env python3
"""
gen_rx_fft_frontend_random.py
=============================
ROBUST randomized golden generator for the rx_fft_frontend RTL unit.

The single-frame gate (golden/rx_downstream/{tx_slot_iq_4032,fft_out}.hex)
proves ONE slot.  This generator produces N >= 20 INDEPENDENT random test
slots PLUS hand-picked edge cases (PAPR / single-tone / all-zero / impulse)
so the FFT front-end is verified over a wide input range.

It reuses the validated reference model (scripts/rx_downstream_ref.py) for
the symbol build (random 16-QAM data on dataIndx + random QPSK pilots,
rearrange_spectrum + IDFT + CP) and reproduces the EXACT RX front-end path
the DUT implements:

    per data symbol z (z = 0..11):
        body = sym288[CP_LEN : CP_LEN+NSC]          # drop the 32-sample CP
        spec = fftshift( fft(body) )                # FWD FFT exp(-j) + rearrange
        bin  = round( spec / 16 )                   # 1/sqrt(256) post-scale
        saturate to int16, pack {Q[31:16], I[15:0]}

CRITICAL EQUIVALENCE (verified against the existing golden to <=1 LSB):
    The DUT is a pure INTEGER datapath.  With time samples quantised to int
    Q15 at scale S, body_float = body_int / S, and the golden is
        round( S * fftshift(fft(body_float)) / 16 )
      = round(     fftshift(fft(body_int))   / 16 ).
    So the scale S cancels: the golden depends only on the INTEGER input
    samples.  We therefore (a) quantise each random slot's time samples to
    int Q15 at the project scale, then (b) compute the golden DIRECTLY from
    those integer samples with the integer-domain FFT path above.  This is
    exactly what the DUT (xfft + BFP-recover + >>4 round) must reproduce,
    independent of any amplitude scaling choice.

The sync region (samples 0..575, 2 sync symbols) is SKIPPED by the DUT, so
we fill it with the real fc_kp0 PSS/SSS (kept byte-identical, harmless) -
its content cannot affect any output bin.

OUTPUTS (golden/rx_fft_rand/):
    slots_in.hex     N_VEC * 4032 lines, int Q15 {Q,I}  (concatenated slots)
    fft_out.hex      N_VEC * 3072 lines, int Q15 {Q,I}  (concatenated goldens)
    meta.txt         N_VEC, per-vector description, peak |sample|, sat flags

numpy only.  Does NOT modify any RTL or existing golden.
"""

import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import rx_downstream_ref as R   # noqa: E402

OUT = os.path.join(ROOT, "golden", "rx_fft_rand")

NSC      = R.NSC          # 256
CP_LEN   = R.CP_LEN       # 32
SYM_LEN  = R.SYM_LEN      # 288
NUM_SYN  = R.NUM_SYN      # 2
NUM_DATA = R.NUM_DATA     # 12
SLOT_LEN = R.SLOT_LEN     # 4032
SYNC_SKIP = NUM_SYN * SYM_LEN   # 576

# Project Q15 time-domain scale (RMS-matched to fc_kp0, see CONTRACT.md).
# The golden is scale-invariant (cancels in fft/16) but we quantise the
# time samples at this scale so the input hex matches the project amplitude
# regime and the saturation/PAPR edge cases are meaningful.
Q15_SCALE = 5090.697374

N_RANDOM = 24            # >= 20 random slots
SEED     = 0xC0FFEE

INT16_MAX =  32767
INT16_MIN = -32768


def fftshift(x):
    h = len(x) // 2
    return np.concatenate([x[h:], x[:h]])


def q15(v):
    """round + saturate a float array to int Q15."""
    iv = np.round(v).astype(np.int64)
    return np.clip(iv, INT16_MIN, INT16_MAX).astype(np.int64)


def pack_word(iv, qv):
    iv = int(max(INT16_MIN, min(INT16_MAX, int(iv)))) & 0xFFFF
    qv = int(max(INT16_MIN, min(INT16_MAX, int(qv)))) & 0xFFFF
    return ((qv << 16) | iv) & 0xFFFFFFFF


def golden_from_int_slot(slot_int):
    """slot_int : complex int128 array length 4032 (real=I, imag=Q).
    Returns the 12*256 golden bins as complex int (real=I, imag=Q),
    computed by the EXACT DUT path: drop CP, fwd FFT, fftshift, /16,
    round-half-away, saturate int16. Also returns a per-symbol sat flag."""
    out = np.zeros(NUM_DATA * NSC, dtype=complex)
    saturated = False
    for z in range(NUM_DATA):
        off = SYNC_SKIP + z * SYM_LEN
        body = slot_int[off + CP_LEN: off + CP_LEN + NSC]
        spec = fftshift(np.fft.fft(body)) / 16.0
        ri = np.round(spec.real)
        rq = np.round(spec.imag)
        si = np.clip(ri, INT16_MIN, INT16_MAX)
        sq = np.clip(rq, INT16_MIN, INT16_MAX)
        if np.any(si != ri) or np.any(sq != rq):
            saturated = True
        out[z * NSC:(z + 1) * NSC] = si + 1j * sq
    return out, saturated


# ----------------------------------------------------------------------
# random / edge-case data-symbol builders
# ----------------------------------------------------------------------
def build_random_slot(rng):
    """A full random data slot: 12 OFDM symbols, each random 16-QAM data on
    dataIndx + random QPSK pilots on pltIndx, rearrange + IDFT + CP. Returns
    the 3456-sample float concatenation (sync region added by caller)."""
    syms = np.zeros((NUM_DATA, SYM_LEN), dtype=complex)
    for z in range(NUM_DATA):
        dbits = rng.integers(0, 2, size=R.DATA_BITS_PER_BLOCK)
        pbits = rng.integers(0, 2, size=R.PILOT_BITS_PER_BLOCK)
        plt = np.array([R.mod_qpsk(pbits[p * 2:p * 2 + 2])
                        for p in range(R.NUM_PILOTS)])
        sym, _ = R.tx_modulate_block(dbits, plt)
        syms[z] = sym
    return syms.reshape(-1)


def build_edge_full_scale(rng):
    """PAPR stress: random 16-QAM/QPSK slot scaled so the time-domain peak
    sits just under int16 full-scale. Verifies no overflow at max amplitude
    within the no-clip regime."""
    data = build_random_slot(rng)
    peak = np.max(np.abs(np.concatenate([data.real, data.imag])))
    # target ~0.985 * full scale at Q15_SCALE so quantised samples are near
    # int16 max but the front-end output must NOT overflow.
    target_amp = 0.985 * (INT16_MAX / Q15_SCALE)
    data = data * (target_amp / peak)
    return data


def build_edge_single_tone():
    """One pure subcarrier (data bin) active in every symbol -> a complex
    sinusoid in time. FFT must yield a single non-zero bin per symbol."""
    syms = np.zeros((NUM_DATA, SYM_LEN), dtype=complex)
    for z in range(NUM_DATA):
        spec = np.zeros(NSC, dtype=complex)
        spec[R.DATA_INDX[37]] = 1.0 + 0.0j          # unit tone on one carrier
        body = R.fftw_backward(R.rearrange_spectrum(spec)) / np.sqrt(NSC)
        syms[z] = np.concatenate([body[NSC - CP_LEN:], body])
    return syms.reshape(-1)


def build_edge_zero():
    """All-zero slot -> every output bin must be exactly 0."""
    return np.zeros(NUM_DATA * SYM_LEN, dtype=complex)


def build_edge_impulse():
    """Max-magnitude time-domain impulse: one body sample at +/-full scale.
    A unit time impulse FFTs to a flat spectrum (all bins equal magnitude),
    stressing the BFP block-exponent + recover path uniformly."""
    # build directly in the INTEGER domain so we control the exact peak.
    slot = np.zeros(NUM_DATA * SYM_LEN, dtype=complex)
    for z in range(NUM_DATA):
        off = z * SYM_LEN + CP_LEN          # first body sample of the symbol
        slot[off] = INT16_MAX + 1j * (-INT16_MIN - 1)   # 32767 + j*32767
    return slot  # already integer-valued (returned as-is, NOT * scale)


# ----------------------------------------------------------------------
def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(SEED)

    # ---- sync region (fc_kp0 PSS/SSS), kept identical; DUT skips it ----
    fc = os.path.join(ROOT, "golden", "p5_wrapper_fullchain", "fc_kp0.mem")
    def unpack(h):
        w = int(h, 16)
        re = w & 0xFFFF; im = (w >> 16) & 0xFFFF
        if re >= 0x8000: re -= 0x10000
        if im >= 0x8000: im -= 0x10000
        return re + 1j * im
    fc_raw = open(fc).read().split()
    sync_int = np.array([unpack(h) for h in fc_raw[64:64 + SYNC_SKIP]])  # 576

    vectors = []   # (name, slot_int[4032], is_prescaled_int)

    # ---- N random data slots ----
    for n in range(N_RANDOM):
        data_f = build_random_slot(rng)
        di = q15(data_f.real * Q15_SCALE)
        dq = q15(data_f.imag * Q15_SCALE)
        slot = np.concatenate([sync_int, di + 1j * dq])
        vectors.append((f"random_{n:02d}", slot))

    # ---- edge: PAPR / near-full-scale ----
    data_f = build_edge_full_scale(rng)
    di = q15(data_f.real * Q15_SCALE); dq = q15(data_f.imag * Q15_SCALE)
    vectors.append(("edge_full_scale_papr",
                    np.concatenate([sync_int, di + 1j * dq])))

    # ---- edge: single tone ----
    data_f = build_edge_single_tone()
    di = q15(data_f.real * Q15_SCALE); dq = q15(data_f.imag * Q15_SCALE)
    vectors.append(("edge_single_tone",
                    np.concatenate([sync_int, di + 1j * dq])))

    # ---- edge: all-zero data ----
    data_f = build_edge_zero()
    di = q15(data_f.real * Q15_SCALE); dq = q15(data_f.imag * Q15_SCALE)
    vectors.append(("edge_all_zero",
                    np.concatenate([sync_int, di + 1j * dq])))

    # ---- edge: max-magnitude impulse (already integer) ----
    slot_imp = np.concatenate([sync_int, build_edge_impulse()])
    vectors.append(("edge_impulse_fullscale", slot_imp))

    n_vec = len(vectors)

    # ---- compute golden + dump ----
    in_lines = []
    out_lines = []
    meta = [f"N_VEC {n_vec}"]
    any_sat = False
    for vi, (name, slot) in enumerate(vectors):
        assert len(slot) == SLOT_LEN, (name, len(slot))
        # peak abs sample (data region only - sync region fixed)
        dpart = slot[SYNC_SKIP:]
        peak = int(np.max(np.abs(np.concatenate(
            [dpart.real, dpart.imag])))) if len(dpart) else 0
        in_sat = peak >= INT16_MAX
        for c in slot:
            in_lines.append(f"{pack_word(int(c.real), int(c.imag)):08X}")
        gold, out_sat = golden_from_int_slot(slot)
        any_sat = any_sat or out_sat
        for c in gold:
            out_lines.append(f"{pack_word(int(c.real), int(c.imag)):08X}")
        gmax = int(np.max(np.abs(np.concatenate(
            [gold.real, gold.imag])))) if len(gold) else 0
        meta.append(f"VEC {vi:02d} {name} in_peak={peak} in_sat={int(in_sat)} "
                    f"out_max={gmax} out_sat={int(out_sat)}")
        print(f"  [{vi:02d}] {name:24s} in_peak={peak:6d} "
              f"out_max={gmax:6d} out_sat={int(out_sat)}")

    with open(os.path.join(OUT, "slots_in.hex"), "w") as f:
        f.write("\n".join(in_lines) + "\n")
    with open(os.path.join(OUT, "fft_out.hex"), "w") as f:
        f.write("\n".join(out_lines) + "\n")
    with open(os.path.join(OUT, "meta.txt"), "w") as f:
        f.write("\n".join(meta) + "\n")

    print(f"\n[done] N_VEC = {n_vec}  "
          f"({N_RANDOM} random + 4 edge)  scale={Q15_SCALE:.6f}")
    print(f"       slots_in.hex = {len(in_lines)} lines "
          f"({n_vec} x {SLOT_LEN})")
    print(f"       fft_out.hex  = {len(out_lines)} lines "
          f"({n_vec} x {NUM_DATA*NSC})")
    print(f"       any golden output saturated to int16: {any_sat}")
    print(f"       wrote -> {OUT}")
    return n_vec


if __name__ == "__main__":
    main()
