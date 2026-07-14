#!/usr/bin/env python3
"""
gen_meyr_fft_reference_roms.py — P3-13A frequency-domain Meyr ROM generator

Generates FFT-domain reference ROMs for use when fft256_xilinx_wrapper is
instantiated via meyr_fft256_actual_integration_top (NOT the bypass stub).

ROM derivation:
  PSS_fft = np.fft.fft(pss_td_ref, 256)
  SSS_fft = np.fft.fft(sss_td_ref, 256)
  ROM[j]  = PSS_fft[j] * conj(SSS_fft[j])

Where pss_td_ref / sss_td_ref are the same reference time-domain windows used
by gen_meyr_reference_roms.py (bypass-compatible path).  The only difference is
the FFT step: the bypass path uses the raw time-domain cross-product, while this
script uses the true frequency-domain cross-spectrum.

With real FFT + integer CFO k_int applied to input:
  FFT(PSS_td shifted by k_int)[k] = PSS_fft_ref[k - k_int]  (circular shift)
  cross_spectrum_received[k] = cross_spectrum_ref[k - k_int]
  Estimator lag correlation → peak at lag = k_int from center
  peak_index = 255 + k_int,  int_cfo = k_int  ✓

With bypass stub (fft256_dual_symbol_frontend):
  The stub passes time-domain samples unchanged as "FFT bins".
  The cross-spectrum becomes time-domain PSS_td * conj(SSS_td) which has no
  integer-CFO sensitivity — all k_int values map to peak_index=255, int_cfo=0.
  This ROM is NOT compatible with the bypass stub; use gen_meyr_reference_roms.py.

Outputs (NEW files only — existing bypass ROMs are not touched):
  vectors/meyr_pss_fft_romhex.txt   — 256-entry PSS frequency-domain cross-spectrum
  vectors/meyr_sss_fft_romhex.txt   — 256-entry SSS reference (all I=+32767, sign=+1)
  golden/meyr_fft_reference_debug.json — debug metadata

ROM packing format (identical convention to bypass ROMs):
  One 32-bit word per line, 8 hex digits, MSB-first:
    word = {Q[31:16], I[15:0]}   (Q in upper halfword, I in lower halfword)
  Signed Q1.15 representation; max magnitude = 32767.

Safety guard: script aborts if it would overwrite meyr_pss_reference_romhex.txt
or meyr_sss_reference_romhex.txt (the bypass-compatible ROMs).
"""

import numpy as np
import json
import os
import sys

# ---------------------------------------------------------------------------
# Parameters — must match gen_meyr_reference_roms.py and RTL parameters
# ---------------------------------------------------------------------------
NSC         = 256
CP_LEN      = 32
PRE_ZEROS   = 64
POST_ZEROS  = 64
TARGET_PEAK = 3000.0
EPS_FRAC    = 0.05
SEED        = 0xC0FFEE

# RTL-observed slot start index (slotStartIndex = 64 = PRE_ZEROS in golden dump)
SLOT_START  = 64


# ---------------------------------------------------------------------------
# OFDM symbol builder — identical to gen_phase3_iq_stimulus.py
# ---------------------------------------------------------------------------
def _make_ofdm_symbol(rng, nsc, cp_len):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=nsc)
    freq   = table[angles]
    td     = np.fft.ifft(freq)
    cp     = td[-cp_len:]
    return np.concatenate([cp, td])


# ---------------------------------------------------------------------------
# Build un-rotated reference frame
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
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    vec_dir    = os.path.join(root, "vectors")
    golden_dir = os.path.join(root, "golden")
    os.makedirs(vec_dir,    exist_ok=True)
    os.makedirs(golden_dir, exist_ok=True)

    pss_out = os.path.join(vec_dir, "meyr_pss_fft_romhex.txt")
    sss_out = os.path.join(vec_dir, "meyr_sss_fft_romhex.txt")

    # Safety guard: never overwrite the bypass-compatible ROMs
    bypass_guard_files = [
        os.path.join(vec_dir, "meyr_pss_reference_romhex.txt"),
        os.path.join(vec_dir, "meyr_sss_reference_romhex.txt"),
    ]
    for g in bypass_guard_files:
        if pss_out == g or sss_out == g:
            print(f"[fft_rom_gen] ABORT: output path would overwrite bypass ROM {g}")
            sys.exit(1)

    for g in bypass_guard_files:
        if os.path.exists(g):
            print(f"[fft_rom_gen] GUARD: bypass ROM '{os.path.basename(g)}' untouched ✓")
        else:
            print(f"[fft_rom_gen] NOTE:  bypass ROM '{os.path.basename(g)}' not present")

    print()

    # ------------------------------------------------------------------
    # 1. Build reference frame and extract time-domain windows
    # ------------------------------------------------------------------
    frame_norot, scale = _build_reference_frame()
    print(f"[fft_rom_gen] Frame length : {len(frame_norot)} samples")
    print(f"[fft_rom_gen] Peak scale   : {scale:.6f}  (target amplitude {TARGET_PEAK})")

    pss_start = SLOT_START + CP_LEN            # 64 + 32 = 96
    sss_start = SLOT_START + 2 * CP_LEN + NSC  # 64 + 64 + 256 = 384

    for name, start in [("PSS", pss_start), ("SSS", sss_start)]:
        if start + NSC > len(frame_norot):
            print(f"[fft_rom_gen] ERROR: {name} window [{start}..{start+NSC-1}] "
                  f"exceeds frame length {len(frame_norot)}")
            sys.exit(1)

    pss_td_float = frame_norot[pss_start : pss_start + NSC]
    sss_td_float = frame_norot[sss_start : sss_start + NSC]

    print(f"[fft_rom_gen] PSS TD window: frame[{pss_start}..{pss_start+NSC-1}]")
    print(f"[fft_rom_gen] SSS TD window: frame[{sss_start}..{sss_start+NSC-1}]")
    print(f"[fft_rom_gen] PSS_td[0] float: I={pss_td_float[0].real:.3f}  Q={pss_td_float[0].imag:.3f}")
    print(f"[fft_rom_gen] SSS_td[0] float: I={sss_td_float[0].real:.3f}  Q={sss_td_float[0].imag:.3f}")

    # ------------------------------------------------------------------
    # 2. Quantize to int16 (matching RTL IQ representation)
    #    This matches how the RTL receives and stores samples.
    # ------------------------------------------------------------------
    pss_i16 = np.clip(np.round(pss_td_float.real), -32768, 32767).astype(np.float64)
    pss_q16 = np.clip(np.round(pss_td_float.imag), -32768, 32767).astype(np.float64)
    sss_i16 = np.clip(np.round(sss_td_float.real), -32768, 32767).astype(np.float64)
    sss_q16 = np.clip(np.round(sss_td_float.imag), -32768, 32767).astype(np.float64)

    pss_cplx = pss_i16 + 1j * pss_q16
    sss_cplx = sss_i16 + 1j * sss_q16

    print(f"[fft_rom_gen] PSS_td[0] int16: I={int(pss_i16[0])}  Q={int(pss_q16[0])}")
    print(f"[fft_rom_gen] SSS_td[0] int16: I={int(sss_i16[0])}  Q={int(sss_q16[0])}")

    # ------------------------------------------------------------------
    # 3. Compute 256-point FFT of each time-domain symbol
    # ------------------------------------------------------------------
    pss_fft = np.fft.fft(pss_cplx, NSC)
    sss_fft = np.fft.fft(sss_cplx, NSC)

    print(f"[fft_rom_gen] PSS_fft[0]: I={pss_fft[0].real:.1f}  Q={pss_fft[0].imag:.1f}")
    print(f"[fft_rom_gen] PSS_fft[1]: I={pss_fft[1].real:.1f}  Q={pss_fft[1].imag:.1f}")
    print(f"[fft_rom_gen] SSS_fft[0]: I={sss_fft[0].real:.1f}  Q={sss_fft[0].imag:.1f}")

    # ------------------------------------------------------------------
    # 4. Cross-spectrum: ROM[j] = PSS_fft[j] * conj(SSS_fft[j])
    # ------------------------------------------------------------------
    cross = pss_fft * np.conj(sss_fft)

    cs_i = cross.real
    cs_q = cross.imag

    max_abs_i = float(np.abs(cs_i).max())
    max_abs_q = float(np.abs(cs_q).max())
    max_abs   = max(max_abs_i, max_abs_q)
    mean_pwr  = float(np.mean(cs_i**2 + cs_q**2))

    print(f"[fft_rom_gen] Cross-spectrum max |I| : {max_abs_i:.3e}")
    print(f"[fft_rom_gen] Cross-spectrum max |Q| : {max_abs_q:.3e}")
    print(f"[fft_rom_gen] Cross-spectrum max total: {max_abs:.3e}")
    print(f"[fft_rom_gen] Cross-spectrum mean power: {mean_pwr:.3e}")

    if max_abs == 0:
        print("[fft_rom_gen] ERROR: cross-spectrum is all-zero — check frame parameters")
        sys.exit(1)

    # ------------------------------------------------------------------
    # 5. Normalize to Q1.15
    # ------------------------------------------------------------------
    q15_max   = 32767
    q15_scale = float(q15_max) / max_abs

    pss_rom_i = np.clip(np.round(cs_i * q15_scale), -32768, 32767).astype(np.int16)
    pss_rom_q = np.clip(np.round(cs_q * q15_scale), -32768, 32767).astype(np.int16)

    print(f"[fft_rom_gen] Q1.15 normalization scale: {q15_scale:.4e}")
    print(f"[fft_rom_gen] PSS_rom[0]: I={int(pss_rom_i[0])}  Q={int(pss_rom_q[0])}")
    print(f"[fft_rom_gen] PSS_rom[1]: I={int(pss_rom_i[1])}  Q={int(pss_rom_q[1])}")

    nonzero = int(np.count_nonzero(
        pss_rom_i.astype(np.int32) | pss_rom_q.astype(np.int32)))
    print(f"[fft_rom_gen] PSS ROM non-zero bins: {nonzero}/{NSC}")
    if nonzero < NSC // 2:
        print("[fft_rom_gen] WARNING: more than half of PSS ROM bins are zero — check parameters")

    # ------------------------------------------------------------------
    # 6. SSS ROM: all I=+32767, Q=0  →  sign(SSS_I) = +1 for all bins
    #    Identical convention to bypass ROM.
    # ------------------------------------------------------------------
    sss_rom_i = np.full(NSC, q15_max, dtype=np.int16)
    sss_rom_q = np.zeros(NSC, dtype=np.int16)

    # ------------------------------------------------------------------
    # 7. Write ROM files — {Q[31:16], I[15:0]}, 8 hex digits per line
    # ------------------------------------------------------------------
    pss_lines = []
    sss_lines = []
    for j in range(NSC):
        pi = int(pss_rom_i[j]) & 0xFFFF
        pq = int(pss_rom_q[j]) & 0xFFFF
        si = int(sss_rom_i[j]) & 0xFFFF
        sq = int(sss_rom_q[j]) & 0xFFFF
        pss_lines.append(f"{(pq << 16) | pi:08x}")
        sss_lines.append(f"{(sq << 16) | si:08x}")

    with open(pss_out, "w") as f:
        f.write("\n".join(pss_lines) + "\n")
    with open(sss_out, "w") as f:
        f.write("\n".join(sss_lines) + "\n")

    print(f"[fft_rom_gen] Written {NSC} entries → {pss_out}")
    print(f"[fft_rom_gen] Written {NSC} entries → {sss_out}")

    # ------------------------------------------------------------------
    # 8. Sanity: predict peak score at k_int=0 (self-correlation)
    # ------------------------------------------------------------------
    score_pred = float(np.sum(
        pss_rom_i.astype(np.float64)**2 + pss_rom_q.astype(np.float64)**2))
    print(f"[fft_rom_gen] Predicted self-correlation score (k_int=0): {score_pred:.3e}")
    print(f"[fft_rom_gen] Expected peak_index (k_int=0): 255")
    print(f"[fft_rom_gen] Expected int_cfo    (k_int=0): 0")
    if nonzero == 0:
        print("[fft_rom_gen] ERROR: PSS ROM is all-zero — self-correlation will fail")
        sys.exit(1)

    # ------------------------------------------------------------------
    # 9. Write debug JSON
    # ------------------------------------------------------------------
    debug = {
        "generator": "gen_meyr_fft_reference_roms.py",
        "strategy":  "frequency-domain cross-spectrum (real FFT path only)",
        "warning":   "NOT compatible with bypass fft256_dual_symbol_frontend stub",
        "parameters": {
            "NSC":              NSC,
            "CP_LEN":           CP_LEN,
            "SLOT_START":       SLOT_START,
            "pss_td_start_in_frame": pss_start,
            "sss_td_start_in_frame": sss_start,
            "TARGET_PEAK":      TARGET_PEAK,
            "EPS_FRAC":         EPS_FRAC,
            "SEED":             SEED,
            "q15_scale":        q15_scale,
            "max_abs_cross":    max_abs,
        },
        "rom_packing": "{Q[31:16], I[15:0]} as 8-hex-digit lines, signed Q1.15",
        "pss_fft_rom_first": {
            "I": int(pss_rom_i[0]),
            "Q": int(pss_rom_q[0]),
            "packed_hex": pss_lines[0],
        },
        "pss_fft_rom_last": {
            "I": int(pss_rom_i[-1]),
            "Q": int(pss_rom_q[-1]),
            "packed_hex": pss_lines[-1],
        },
        "sss_fft_rom_convention": "all I=+32767 Q=0, sign(I)=+1 → term2[j] = PSS_fft_rom[j]",
        "nonzero_pss_bins":  nonzero,
        "formula": {
            "peak_index": "255 + k_int  (valid only with real FFT backend)",
            "int_cfo":    "k_int",
        },
        "predicted_score_k0": score_pred,
        "validation_gate": (
            "Requires fft256_xilinx_wrapper with USE_BEHAVIORAL_STUB=0 + Xilinx xsim. "
            "Do NOT use with fft256_dual_symbol_frontend bypass stub."
        ),
        "output_files": [pss_out, sss_out],
        "bypass_roms_untouched": bypass_guard_files,
    }
    dbg_path = os.path.join(golden_dir, "meyr_fft_reference_debug.json")
    with open(dbg_path, "w") as f:
        json.dump(debug, f, indent=2)
        f.write("\n")
    print(f"[fft_rom_gen] Written debug metadata → {dbg_path}")
    print("[fft_rom_gen] Done.")


if __name__ == "__main__":
    main()
