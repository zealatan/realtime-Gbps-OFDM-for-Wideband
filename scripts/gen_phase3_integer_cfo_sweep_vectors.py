#!/usr/bin/env python3
"""
gen_phase3_integer_cfo_sweep_vectors.py — P3-09 integer CFO sweep vector generator

Generates per-case IQ stimulus files for k_int sweep:
  k_int ∈ {-8, -4, -2, -1, 0, +1, +2, +4, +8}

Output directory: golden/p3_09_sweep/
  case_km8.mem, case_km4.mem, ..., case_kp8.mem   — Q15 IQ hex stimulus
  manifest.json                                     — expected values for all cases

IQ format (same as golden/phase3_iq_stimulus.mem):
  One 32-bit word per line: {Q[15:0], I[15:0]} packed hex

Signal construction per case:
  1. Build un-rotated OFDM frame (same SEED, same amplitude as P3-05B baseline)
  2. Apply frac CFO:    frame[n] *= exp(j·2π·EPS_FRAC·n/NSC)
  3. Apply integer CFO: frame[n] *= exp(j·2π·k_int·n/NSC)
  Total rotation per sample n: exp(j·2π·(EPS_FRAC + k_int)·n/NSC)

IMPORTANT — Bypass FFT Limitation
----------------------------------
With fft256_dual_symbol_frontend.v in bypass (stub) mode, the Meyr core receives
time-domain samples.  Integer CFO rotation cancels in the cross-product:

  term1[j] = PSS_td_shifted[j] × conj(SSS_td_shifted[j])
           = PSS_td_ref[j] × conj(SSS_td_ref[j])   (phase cancels for integer k_int)

Therefore bypass mode always produces peak_index=255 and int_cfo=0, regardless of k_int.

The manifest records REAL-FFT-MODE expected values (peak_index = 255+k_int).
The compare script checks against real-FFT-mode expectations; bypass-mode results will
fail for k_int≠0, which is the correct behaviour (no fake PASS).

Real FFT mode requires:
  - fft256_dual_symbol_frontend.v S_COMPUTE replaced with actual FFT IP
  - Reference ROMs populated with frequency-domain PSS/SSS cross-product
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
EPS_FRAC    = 0.05      # fractional CFO (subcarrier spacings)
SEED        = 0xC0FFEE

# RTL encoding constants (from phase3_sync_top.v)
CENTER          = NSC - 1       # 255: zero-CFO peak index
NSC_LOG2        = 8             # log2(256)
INT_CFO_SHIFT   = 32 - NSC_LOG2  # 24

# Sweep definition
SWEEP_K_INT = [-8, -4, -2, -1, 0, 1, 2, 4, 8]


def _case_tag(k_int):
    if k_int < 0:
        return f"km{abs(k_int)}"
    elif k_int == 0:
        return "k0"
    else:
        return f"kp{k_int}"


def _make_ofdm_symbol(rng):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=NSC)
    freq   = table[angles]
    td     = np.fft.ifft(freq)
    cp     = td[-CP_LEN:]
    return np.concatenate([cp, td])   # CP_LEN + NSC = 288 samples


def _build_base_frame():
    """Un-rotated OFDM frame (no CFO), normalised to TARGET_PEAK per component."""
    rng  = np.random.default_rng(SEED)
    sym1 = _make_ofdm_symbol(rng)
    sym2 = _make_ofdm_symbol(rng)
    frame = np.concatenate([
        np.zeros(PRE_ZEROS,  dtype=np.complex128),
        sym1,
        sym2,
        np.zeros(POST_ZEROS, dtype=np.complex128),
    ])
    sig   = np.concatenate([sym1, sym2])
    peak  = max(float(np.abs(sig.real).max()), float(np.abs(sig.imag).max()))
    scale = TARGET_PEAK / peak if peak > 0 else 1.0
    return frame * scale


def _apply_cfo(frame, eps_frac, k_int):
    """Apply fractional + integer CFO: frame[n] *= exp(j·2π·(eps_frac+k_int)·n/NSC)."""
    n      = np.arange(len(frame), dtype=np.float64)
    total  = eps_frac + k_int
    return frame * np.exp(1j * 2.0 * np.pi * total * n / NSC)


def _to_q15_mem_lines(frame):
    """Convert complex frame to list of '{Q[15:0], I[15:0]}' hex strings."""
    lines = []
    for s in frame:
        i16 = int(max(-32768, min(32767, round(float(s.real))))) & 0xFFFF
        q16 = int(max(-32768, min(32767, round(float(s.imag))))) & 0xFFFF
        lines.append(f"{q16:04X}{i16:04X}")
    return lines


def _int_cfo_word(k_int):
    """Signed 32-bit NCO step word: −k_int × 2^INT_CFO_SHIFT."""
    raw = (-k_int) << INT_CFO_SHIFT
    # Convert to signed 32-bit Python int
    if raw >= (1 << 31):
        raw -= (1 << 32)
    return raw


def _expected_peak_index(k_int):
    return CENTER + k_int   # 255 + k_int


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    out_dir    = os.path.join(root, "golden", "p3_09_sweep")
    os.makedirs(out_dir, exist_ok=True)

    base_frame = _build_base_frame()
    print(f"[sweep_gen] Base frame: {len(base_frame)} samples  "
          f"peak_I={float(np.abs(base_frame.real).max()):.1f}")

    manifest_cases = {}

    for k_int in SWEEP_K_INT:
        tag   = _case_tag(k_int)
        fname = f"case_{tag}.mem"
        fpath = os.path.join(out_dir, fname)

        frame = _apply_cfo(base_frame, EPS_FRAC, k_int)

        lines = _to_q15_mem_lines(frame)
        with open(fpath, "w") as f:
            f.write("\n".join(lines) + "\n")

        peak_idx    = _expected_peak_index(k_int)
        cfo_word    = _int_cfo_word(k_int)

        manifest_cases[tag] = {
            "k_int"                    : k_int,
            "stimulus_file"            : fname,
            "n_samples"                : len(frame),
            "real_fft_mode": {
                "expected_meyr_peak_index"  : peak_idx,
                "expected_int_cfo"          : k_int,
                "expected_integer_cfo_word" : cfo_word,
                "note": "Valid only when fft256_dual_symbol_frontend uses real FFT",
            },
            "bypass_fft_mode": {
                "expected_meyr_peak_index"  : CENTER,
                "expected_int_cfo"          : 0,
                "expected_integer_cfo_word" : 0,
                "note": "Bypass mode: integer CFO cancels in PSS×conj(SSS) cross-product",
            },
            "front_end_expected": {
                "DETECTION_STATUS"  : 1,
                "frameStart"        : 41,
                "peakIndexAuto"     : 23,
                "slotStartIndex"    : 64,
                "PSS_START"         : CP_LEN,
                "SSS_START"         : 2 * CP_LEN + NSC,
                "PSS_SAMPLE_COUNT"  : NSC,
                "SSS_SAMPLE_COUNT"  : NSC,
                "note": "Front-end outputs are k_int-independent (integer CFO does not shift autocorr peak)",
            },
        }

        print(f"[sweep_gen] k_int={k_int:+d}  tag={tag:5s}  "
              f"peak_index(real_fft)={peak_idx:3d}  "
              f"cfo_word={cfo_word:12d}  -> {fname}")

    # Write manifest
    manifest = {
        "generator"     : "gen_phase3_integer_cfo_sweep_vectors.py",
        "date"          : "2026-05-28",
        "sweep_k_int"   : SWEEP_K_INT,
        "nsc"           : NSC,
        "cp_len"        : CP_LEN,
        "center"        : CENTER,
        "int_cfo_shift" : INT_CFO_SHIFT,
        "seed"          : SEED,
        "eps_frac"      : EPS_FRAC,
        "amplitude"     : TARGET_PEAK,
        "formula": {
            "peak_index"           : "255 + k_int",
            "int_cfo"              : "k_int",
            "integer_cfo_word"     : "-k_int * 2^INT_CFO_SHIFT = -k_int * 16777216",
        },
        "bypass_fft_limitation": (
            "With bypass fft256_dual_symbol_frontend.v, integer CFO cancels in "
            "PSS_td × conj(SSS_td) cross-product.  All k_int cases yield peak=255 "
            "and int_cfo=0.  Real FFT backend is required for k_int≠0 sweep."
        ),
        "cases": manifest_cases,
    }

    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"[sweep_gen] manifest -> {manifest_path}")
    print(f"[sweep_gen] Generated {len(SWEEP_K_INT)} stimulus files in {out_dir}/")
    print("[sweep_gen] Done.")


if __name__ == "__main__":
    main()
