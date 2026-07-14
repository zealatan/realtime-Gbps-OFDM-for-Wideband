#!/usr/bin/env python3
"""
gen_meyr_reference_roms.py — P3-08 Meyr backend ROM generator

Generates:
  vectors/meyr_pss_reference_romhex.txt  — 256-entry ROM (PSS cross-product reference)
  vectors/meyr_sss_reference_romhex.txt  — 256-entry ROM (SSS sign reference, all +1)
  golden/meyr_reference_debug.json       — debug metadata

ROM derivation strategy
-----------------------
The fft256_dual_symbol_frontend is a bypass stub: it passes time-domain PSS/SSS
samples unchanged as "FFT bins."  meyr_integer_cfo_core therefore correlates:

  term1[j] = PSS_td[j] × conj(SSS_td[j])   (time-domain cross-product)

against:

  term2[j] = PSS_rom[j] × sign(SSS_rom_I[j])

For peak_index=255 (int_cfo=0) we need term2 ∝ term1_ref, so:

  PSS_rom[j]  = term1_ref[j]  normalized to Q1.15
  SSS_rom_I[j] = +32767 → sign = +1 → term2[j] = PSS_rom[j] ✓

Frac-CFO correction analysis
-----------------------------
The RTL frac corrector produces:
  corrected[k] = frame_norot[frame_index + k] × exp(j × 2π × EPS_FRAC × frame_index / NSC)

The const-phase term is the same for PSS and SSS → cancels in term1 = PSS × conj(SSS).
Therefore un-rotated frame samples give the correct ROM without knowing the exact
frac correction phase word.

Sample positions
----------------
PSS[j] = frame_norot_scaled[SLOT_START + CP_LEN + j]  (j = 0..255)
SSS[j] = frame_norot_scaled[SLOT_START + 2*CP_LEN + NSC + j]  (j = 0..255)

Where SLOT_START=64 = PRE_ZEROS (from golden_dump slotStartIndex output).
The frac corrector outputs FRAME_LEN samples starting from slotStart, so
output[CP_LEN+j] = S1[j] (PSS OFDM symbol, no cyclic shift).

Both span a cyclic rotation of the IFFT output by 233 samples (due to frame detector
firing at sample 41, 23 samples before slotStart=64 which is at the CP start).
The same cyclic rotation appears in both PSS and SSS → cancels in term1 ✓

ROM packing format
------------------
meyr_integer_cfo_core $readmemh format (one 32-bit word per line, hex):
  pss_word = {PSS_Q[31:16], PSS_I[15:0]}
  sss_word = {SSS_Q[31:16], SSS_I[15:0]}

Unpacked by core:
  _pss_i_val = $signed(packed[15:0])   → Q1.15
  _pss_q_val = $signed(packed[31:16])  → Q1.15
  _sss_i_val = $signed(packed[15:0])   → sign() only

Consistency check: FRAME_INDEX, CP_LEN, NSC must match RTL parameters.
"""

import numpy as np
import json
import os
import sys

# ---------------------------------------------------------------------------
# Parameters — must match gen_phase3_iq_stimulus.py and RTL parameters
# ---------------------------------------------------------------------------
NSC         = 256
CP_LEN      = 32
PRE_ZEROS   = 64
POST_ZEROS  = 64
TARGET_PEAK = 3000.0
EPS_FRAC    = 0.05
SEED        = 0xC0FFEE    # np.random.default_rng seed

# Slot start observed in RTL simulation (RTL_SLOT_START_INDEX = 64 = PRE_ZEROS).
# The frac_cfo_frame_corrector_top begins its FRAME_LEN-sample output at slotStart,
# not at frame_index (41).  Within the corrected output frame:
#   output[CP_LEN..CP_LEN+NSC-1] = S1 (PSS OFDM symbol)
#   output[2*CP_LEN+NSC..FRAME_LEN-1] = S2 (SSS OFDM symbol)
# So PSS starts at input position SLOT_START + CP_LEN = 64 + 32 = 96  (= S1[0]).
SLOT_START = 64


# ---------------------------------------------------------------------------
# OFDM symbol builder (identical to gen_phase3_iq_stimulus.py)
# ---------------------------------------------------------------------------
def _make_ofdm_symbol(rng, nsc, cp_len):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=nsc)
    freq   = table[angles]
    td     = np.fft.ifft(freq)
    cp     = td[-cp_len:]
    return np.concatenate([cp, td])


# ---------------------------------------------------------------------------
# Build un-rotated reference frame (same as gen_frame() without CFO)
# ---------------------------------------------------------------------------
def _build_reference_frame():
    rng  = np.random.default_rng(SEED)
    sym1 = _make_ofdm_symbol(rng, NSC, CP_LEN)
    sym2 = _make_ofdm_symbol(rng, NSC, CP_LEN)

    frame = np.concatenate([
        np.zeros(PRE_ZEROS,  dtype=np.complex128),
        sym1,
        sym2,
        np.zeros(POST_ZEROS, dtype=np.complex128),
    ])

    sig   = np.concatenate([sym1, sym2])
    peak  = max(float(np.abs(sig.real).max()), float(np.abs(sig.imag).max()))
    scale = TARGET_PEAK / peak if peak > 0 else 1.0
    return frame * scale, scale


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    root        = os.path.normpath(os.path.join(script_dir, ".."))
    vec_dir     = os.path.join(root, "vectors")
    golden_dir  = os.path.join(root, "golden")
    os.makedirs(vec_dir,    exist_ok=True)
    os.makedirs(golden_dir, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Regenerate un-rotated reference frame
    # ------------------------------------------------------------------
    frame_norot, scale = _build_reference_frame()
    print(f"[rom_gen] Frame length: {len(frame_norot)}")
    print(f"[rom_gen] Peak scale: {scale:.6f}  (target amplitude {TARGET_PEAK})")

    # ------------------------------------------------------------------
    # 2. Extract PSS and SSS time-domain windows
    #    (matching the indices the RTL extractor will produce)
    #
    #    PSS[j] = frac_corrected[CP_LEN + j]
    #           ≈ frame_norot_scaled[FRAME_INDEX + CP_LEN + j]
    #
    #    SSS[j] = frac_corrected[2*CP_LEN + NSC + j]
    #           ≈ frame_norot_scaled[FRAME_INDEX + 2*CP_LEN + NSC + j]
    # ------------------------------------------------------------------
    pss_start = SLOT_START + CP_LEN            # 64 + 32 = 96  (= S1[0] in frame_norot)
    sss_start = SLOT_START + 2 * CP_LEN + NSC  # 64 + 320 = 384 (= S2[0] in frame_norot)

    if pss_start + NSC > len(frame_norot):
        print(f"[rom_gen] ERROR: PSS window [{pss_start}..{pss_start+NSC-1}] exceeds frame length {len(frame_norot)}")
        sys.exit(1)
    if sss_start + NSC > len(frame_norot):
        print(f"[rom_gen] ERROR: SSS window [{sss_start}..{sss_start+NSC-1}] exceeds frame length {len(frame_norot)}")
        sys.exit(1)

    pss_float = frame_norot[pss_start : pss_start + NSC]
    sss_float = frame_norot[sss_start : sss_start + NSC]

    print(f"[rom_gen] PSS window: frame[{pss_start}..{pss_start+NSC-1}]")
    print(f"[rom_gen] SSS window: frame[{sss_start}..{sss_start+NSC-1}]")
    print(f"[rom_gen] PSS[0]: I={pss_float[0].real:.3f}  Q={pss_float[0].imag:.3f}")
    print(f"[rom_gen] SSS[0]: I={sss_float[0].real:.3f}  Q={sss_float[0].imag:.3f}")

    # ------------------------------------------------------------------
    # 3. Convert to int16 (same as RTL IQ representation)
    # ------------------------------------------------------------------
    pss_i = np.clip(np.round(pss_float.real), -32768, 32767).astype(np.int32)
    pss_q = np.clip(np.round(pss_float.imag), -32768, 32767).astype(np.int32)
    sss_i = np.clip(np.round(sss_float.real), -32768, 32767).astype(np.int32)
    sss_q = np.clip(np.round(sss_float.imag), -32768, 32767).astype(np.int32)

    print(f"[rom_gen] PSS int16[0]: I={int(pss_i[0])}  Q={int(pss_q[0])}")
    print(f"[rom_gen] SSS int16[0]: I={int(sss_i[0])}  Q={int(sss_q[0])}")

    # ------------------------------------------------------------------
    # 4. Compute term1_ref[j] = PSS_i16[j] × conj(SSS_i16[j])
    #    = (PSS_i + j*PSS_q) × (SSS_i - j*SSS_q)
    #    real: PSS_i*SSS_i + PSS_q*SSS_q
    #    imag: PSS_q*SSS_i - PSS_i*SSS_q
    # ------------------------------------------------------------------
    t1_i = pss_i * sss_i + pss_q * sss_q   # int32, max ≈ 2 × 3000^2 = 18e6
    t1_q = pss_q * sss_i - pss_i * sss_q

    max_abs = max(int(np.abs(t1_i).max()), int(np.abs(t1_q).max()))
    mean_sq = float(np.mean(t1_i.astype(np.float64)**2 + t1_q.astype(np.float64)**2))
    print(f"[rom_gen] term1_ref max abs: {max_abs}  (expected ~{2*int(TARGET_PEAK)**2})")
    print(f"[rom_gen] term1_ref mean power: {mean_sq:.3e}")

    # ------------------------------------------------------------------
    # 5. Normalize term1_ref to Q1.15 for PSS ROM
    # ------------------------------------------------------------------
    q15_max  = 32767
    if max_abs == 0:
        print("[rom_gen] WARNING: term1_ref is all-zero — ROM will be zero stubs")
        q15_scale = 1.0
    else:
        q15_scale = float(q15_max) / float(max_abs)

    pss_rom_i = np.clip(np.round(t1_i * q15_scale), -32768, 32767).astype(np.int16)
    pss_rom_q = np.clip(np.round(t1_q * q15_scale), -32768, 32767).astype(np.int16)

    print(f"[rom_gen] Q1.15 normalization scale: {q15_scale:.6e}")
    print(f"[rom_gen] PSS_rom[0]: I={int(pss_rom_i[0])}  Q={int(pss_rom_q[0])}")

    # ------------------------------------------------------------------
    # 6. SSS ROM: all I=+32767, Q=0  →  sign(SSS_I) = +1 for all bins
    #    This makes term2[j] = PSS_rom[j] × 1 = PSS_rom[j]  ✓
    # ------------------------------------------------------------------
    sss_rom_i = np.full(NSC, q15_max, dtype=np.int16)
    sss_rom_q = np.zeros(NSC,         dtype=np.int16)

    # ------------------------------------------------------------------
    # 7. Write ROM files (format: {Q[31:16], I[15:0]}, 8 hex digits)
    # ------------------------------------------------------------------
    pss_path = os.path.join(vec_dir, "meyr_pss_reference_romhex.txt")
    sss_path = os.path.join(vec_dir, "meyr_sss_reference_romhex.txt")

    pss_lines = []
    sss_lines = []
    for j in range(NSC):
        pi = int(pss_rom_i[j]) & 0xFFFF
        pq = int(pss_rom_q[j]) & 0xFFFF
        si = int(sss_rom_i[j]) & 0xFFFF
        sq = int(sss_rom_q[j]) & 0xFFFF
        pss_lines.append(f"{(pq << 16) | pi:08x}")
        sss_lines.append(f"{(sq << 16) | si:08x}")

    with open(pss_path, "w") as f:
        f.write("\n".join(pss_lines) + "\n")
    with open(sss_path, "w") as f:
        f.write("\n".join(sss_lines) + "\n")

    print(f"[rom_gen] Written {NSC} entries → {pss_path}")
    print(f"[rom_gen] Written {NSC} entries → {sss_path}")

    # ------------------------------------------------------------------
    # 8. Sanity check: verify PSS ROM is non-zero
    # ------------------------------------------------------------------
    nonzero_pss = int(np.count_nonzero(pss_rom_i.astype(np.int32) | pss_rom_q.astype(np.int32)))
    print(f"[rom_gen] PSS ROM non-zero bins: {nonzero_pss}/{NSC}")
    if nonzero_pss == 0:
        print("[rom_gen] ERROR: PSS ROM is all zero — check parameters")
        sys.exit(1)

    # ------------------------------------------------------------------
    # 9. Predict expected correlation score at lag=255 vs lag=0
    # ------------------------------------------------------------------
    # At lag=255 (CENTER): corr = Σ (t1/2^16) × conj(term2)
    # Both use same scale, so corr_magnitude ≈ Σ (t1_q15 >> 16) × term2_q15
    # term2 = PSS_rom, term1 = pss_i16 × conj(sss_i16) (before Q15 normalization)
    # After normalization: expected score at peak ≈ (Σ |t1_q15|^2) / (2^16)^2 × (2^16)^2
    # Qualitative: non-zero positive score at lag=255
    t2_i = pss_rom_i.astype(np.int32)
    t2_q = pss_rom_q.astype(np.int32)
    corr_i_peak = int(np.sum((t1_i >> 16) * t2_i + (t1_q >> 16) * t2_q))
    corr_q_peak = int(np.sum((t1_q >> 16) * t2_i - (t1_i >> 16) * t2_q))
    score_peak  = corr_i_peak**2 + corr_q_peak**2
    print(f"[rom_gen] Predicted corr[255] magnitude: {np.sqrt(corr_i_peak**2+corr_q_peak**2):.3e}")
    print(f"[rom_gen] Predicted score[255]: {score_peak:.3e}")
    if corr_i_peak <= 0:
        print("[rom_gen] WARNING: expected positive real part at lag=255")

    # ------------------------------------------------------------------
    # 10. Write debug JSON
    # ------------------------------------------------------------------
    debug = {
        "generator": "gen_meyr_reference_roms.py",
        "strategy":  "stimulus-derived time-domain cross-product (bypass-compatible)",
        "parameters": {
            "NSC":         NSC,
            "CP_LEN":      CP_LEN,
            "SLOT_START":  SLOT_START,
            "PSS_start_in_frame": pss_start,
            "SSS_start_in_frame": sss_start,
            "TARGET_PEAK": TARGET_PEAK,
            "EPS_FRAC":    EPS_FRAC,
            "SEED":        SEED,
            "q15_scale":   q15_scale,
            "max_abs_term1": max_abs,
        },
        "pss_rom_first_entry": {
            "I": int(pss_rom_i[0]),
            "Q": int(pss_rom_q[0]),
            "packed_hex": pss_lines[0],
        },
        "pss_rom_last_entry": {
            "I": int(pss_rom_i[-1]),
            "Q": int(pss_rom_q[-1]),
            "packed_hex": pss_lines[-1],
        },
        "sss_rom_convention": "all I=+32767 Q=0 → sign=+1 → term2[j]=PSS_rom[j]",
        "nonzero_pss_bins": nonzero_pss,
        "predicted_peak_lag": 255,
        "predicted_int_cfo": 0,
        "predicted_step_word": 0,
        "predicted_score_at_peak": score_peak,
        "expected_RTL_INTEGER_CFO_WORD": 0,
        "expected_RTL_MEYR_PEAK_INDEX": 255,
        "rom_packing": "{Q[31:16], I[15:0]} as 8-hex-digit lines",
        "note": (
            "PSS_rom[j] = term1_ref[j] = PSS_td_ref[j] × conj(SSS_td_ref[j]) normalized to Q1.15. "
            "Valid only for the current stimulus (INT_CFO=0, SEED=0xC0FFEE). "
            "For ±1 CFO variants, re-run with CFO-shifted stimulus."
        ),
    }
    dbg_path = os.path.join(golden_dir, "meyr_reference_debug.json")
    with open(dbg_path, "w") as f:
        json.dump(debug, f, indent=2)
        f.write("\n")
    print(f"[rom_gen] Written debug metadata → {dbg_path}")
    print("[rom_gen] Done.")


if __name__ == "__main__":
    main()
