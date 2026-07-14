#!/usr/bin/env python3
"""
gen_p3_21a_cfo_sweep_vectors.py — P3-21A CFO Coverage Expansion vector generator

Generates IQ stimulus files for three sweep groups:

  J1 — Integer CFO sweep (standalone Meyr TB with behavioral DFT)
       k_int ∈ {0, ±1, ±2, ±4, ±8, ±12, ±16}, frac_cfo=0
       Verify: peak_index = 255 + k_int,  int_cfo = k_int

  J2 — Fractional CFO sweep (full wrapper TB)
       k_int=0, frac ∈ {-0.45, -0.30, -0.15, 0, +0.15, +0.30, +0.45}
       Verify: frac_cfo_valid, output_count=4032, TLAST

  J3 — Combined sweep (full wrapper TB, bypass-FFT limitation documented)
       (+16,+0.45), (-16,-0.45), (+12,-0.30), (-12,+0.30)
       Verify: frame_found, frac_cfo_valid, output_count=4032, TLAST

Output: golden/p3_21a_sweep/
  j1_k{tag}.mem          — Q15 IQ hex, 4160 samples
  j2_frac_{tag}.mem      — Q15 IQ hex, 4160 samples
  j3_{k}_{f}.mem         — Q15 IQ hex, 4160 samples
  manifest.json          — expected values for all cases

Slot geometry (2026-06-19 spec bump — NUM_DATA_BLOCKS 5 -> 12):
  PRE_ZEROS (64) | sync sym0 (PSS-like) | sync sym1 (SSS-like)
                 | data sym0 ... data sym11
                 | POST_ZEROS (64)
  Total slot = 14 OFDM symbols (2 sync + 12 data) = 14 * 288 = 4032 samples
  Total file = 64 + 4032 + 64 = 4160 samples.

Signal construction per case:
  1. Build un-rotated OFDM frame (same SEED as P3-05B baseline) — 14 symbols
     (each = CP + IDFT(random QPSK)) wrapped in PRE/POST zeros.
  2. Apply total CFO:  frame[n] *= exp(j·2π·(frac_cfo + k_int)·n/NSC)
     The rotation is applied across the WHOLE 4160 samples (continuous CFO),
     not just the 576-sample sync region.
     For J1: frac_cfo=0 → pure integer rotation
     For J2: k_int=0    → pure fractional rotation
     For J3: both non-zero

Note on expected values:
  Sync-region landmarks (peak_lag=23, frame_start≈41, slot_start≈64,
  meyr_peak_index=255+k_int, etc.) are unchanged — sync region remains
  at the very front of the slot. Only the slot LENGTH grew. Wrapper-level
  M_AXIS output_count rises to FRAME_LEN = 4032 = TLAST beat index 4031.

Mathematical note (VanDeBeek CP autocorrelation):
  |P| is invariant to both integer and fractional CFO — timing metric unchanged.
  frac_cfo_estimator correctly recovers frac_cfo for all |frac| < 0.5.
  The Meyr estimator in J1 uses behavioral DFT → correct peak for any k_int.
  In J2/J3 (full wrapper), bypass FFT gives int_cfo=0 regardless of k_int.
"""

import numpy as np
import json
import os

# ── Signal parameters (must match RTL) ──────────────────────────────────────
NSC         = 256
CP_LEN      = 32
SYM_LEN     = NSC + CP_LEN          # 288 samples per OFDM symbol incl. CP
NUM_SYNC    = 2                     # PSS + SSS sync symbols (unchanged)
NUM_DATA    = 12                    # 2026-06-19 spec bump: 5 -> 12 data symbols
NUM_SYMBOLS = NUM_SYNC + NUM_DATA   # 14
FRAME_LEN   = NUM_SYMBOLS * SYM_LEN # 4032 (was 576 with 2-symbol slot)
PRE_ZEROS   = 64
POST_ZEROS  = 64
TOTAL_LEN   = PRE_ZEROS + FRAME_LEN + POST_ZEROS  # 4160
TARGET_PEAK = 3000.0
SEED        = 0xC0FFEE

CENTER      = NSC - 1               # 255: zero-CFO peak index
INT_CFO_SHIFT = 32 - 8              # 24 (NSC_LOG2=8)

# ── Sweep definitions ────────────────────────────────────────────────────────
J1_K_INT = [0, 1, -1, 2, -2, 4, -4, 8, -8, 12, -12, 16, -16]

J2_FRAC  = [-0.45, -0.30, -0.15, 0.0, 0.15, 0.30, 0.45]

J3_PAIRS = [
    ( 16,  0.45),
    (-16, -0.45),
    ( 12, -0.30),
    (-12,  0.30),
]


# ── Signal builders ──────────────────────────────────────────────────────────
def _make_ofdm_symbol(rng):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=NSC)
    td     = np.fft.ifft(table[angles])
    cp     = td[-CP_LEN:]
    return np.concatenate([cp, td])


def _build_base_frame():
    """Build the 4160-sample base frame: PRE_ZEROS | 14 OFDM symbols | POST_ZEROS.

    Slot = 2 sync symbols (PSS + SSS placeholders) + 12 data symbols.
    Each symbol = CP_LEN + NSC = 288 samples. SEED kept for reproducibility;
    drawing all 14 symbols from the same rng sequence preserves the first 2
    symbols byte-for-byte vs the legacy 576-sample base frame, so sync-region
    landmarks (peak_lag, frame_start) are unchanged.
    """
    rng    = np.random.default_rng(SEED)
    syms   = [_make_ofdm_symbol(rng) for _ in range(NUM_SYMBOLS)]
    sig    = np.concatenate(syms)
    frame  = np.concatenate([
        np.zeros(PRE_ZEROS,  dtype=np.complex128),
        sig,
        np.zeros(POST_ZEROS, dtype=np.complex128),
    ])
    assert len(frame) == TOTAL_LEN, f"frame {len(frame)} != {TOTAL_LEN}"
    peak   = max(float(np.abs(sig.real).max()), float(np.abs(sig.imag).max()))
    return frame * (TARGET_PEAK / peak if peak > 0 else 1.0)


def _apply_cfo(frame, frac, k_int):
    n = np.arange(len(frame), dtype=np.float64)
    return frame * np.exp(1j * 2.0 * np.pi * (frac + k_int) * n / NSC)


def _to_mem_lines(frame):
    lines = []
    for s in frame:
        i16 = int(max(-32768, min(32767, round(float(s.real))))) & 0xFFFF
        q16 = int(max(-32768, min(32767, round(float(s.imag))))) & 0xFFFF
        lines.append(f"{q16:04X}{i16:04X}")
    return lines


def _write_mem(path, frame):
    with open(path, "w") as f:
        f.write("\n".join(_to_mem_lines(frame)) + "\n")


def _int_cfo_word(k_int):
    raw = (-k_int) << INT_CFO_SHIFT
    if raw >= (1 << 31):
        raw -= (1 << 32)
    return raw


def _expected_frac_word(frac):
    """RTL frac_cfo_word = +2 * frac * 32768 (positive for positive frac CFO)."""
    return round(2.0 * frac * 32768.0)


# ── Main ─────────────────────────────────────────────────────────────────────
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    out_dir    = os.path.join(root, "golden", "p3_21a_sweep")
    os.makedirs(out_dir, exist_ok=True)

    base = _build_base_frame()
    print(f"[gen_p3_21a] Base frame: {len(base)} samples  "
          f"peak_I={float(np.abs(base.real).max()):.1f}")

    manifest = {
        "date": "2026-06-19",
        "spec_change": (
            "NUM_DATA_BLOCKS 5 -> 12: slot is now 2 sync + 12 data = 14 "
            "OFDM symbols. FRAME_LEN 576 -> 4032; per-file length 704 -> 4160. "
            "Sync-region landmarks unchanged (peak_lag, frame_start)."
        ),
        "cases": {},
    }

    # ── J1: integer CFO sweep ────────────────────────────────────────────────
    print("\n--- J1: Integer CFO sweep (frac=0) ---")
    j1_files = {}
    for k in J1_K_INT:
        tag   = f"kp{k}" if k >= 0 else f"km{abs(k)}"
        fname = f"j1_{tag}.mem"
        fpath = os.path.join(out_dir, fname)
        _write_mem(fpath, _apply_cfo(base, 0.0, k))
        exp_peak = CENTER + k     # 255 + k_int
        exp_word = _int_cfo_word(k)
        j1_files[tag] = fname
        manifest["cases"][f"j1_{tag}"] = {
            "group": "J1_integer_cfo",
            "k_int": k, "frac_cfo": 0.0,
            "file": fname,
            "checks": {
                "meyr_peak_index": exp_peak,
                "int_cfo": k,
                "int_cfo_word (real-FFT mode)": exp_word,
            },
            "note": "behavioral DFT mode gives correct peak for |k_int|<=255",
        }
        print(f"  k={k:+3d}  peak={exp_peak}  word={exp_word:11d}  -> {fname}")

    # ── J2: fractional CFO sweep ─────────────────────────────────────────────
    print("\n--- J2: Fractional CFO sweep (k_int=0) ---")
    j2_files = {}
    for frac in J2_FRAC:
        sign  = "p" if frac >= 0 else "m"
        dig   = f"{abs(frac)*100:03.0f}"
        tag   = f"{sign}{dig}"
        fname = f"j2_frac_{tag}.mem"
        fpath = os.path.join(out_dir, fname)
        _write_mem(fpath, _apply_cfo(base, frac, 0))
        exp_word = _expected_frac_word(frac)
        j2_files[tag] = fname
        manifest["cases"][f"j2_frac_{tag}"] = {
            "group": "J2_frac_cfo",
            "k_int": 0, "frac_cfo": frac,
            "file": fname,
            "checks": {
                "frame_found": True,
                "frac_cfo_valid": True,
                "output_count": FRAME_LEN,
                "tlast_beat": FRAME_LEN - 1,
                "frac_cfo_word_approx": exp_word,
            },
            "note": "full wrapper check; bypass FFT gives int_cfo=0 (correct for k_int=0)",
        }
        print(f"  frac={frac:+.2f}  word={exp_word:+6d}  -> {fname}")

    # ── J3: combined sweep ───────────────────────────────────────────────────
    print("\n--- J3: Combined sweep ---")
    j3_files = {}
    for (k, frac) in J3_PAIRS:
        k_sign  = "p" if k >= 0 else "m"
        f_sign  = "fp" if frac >= 0 else "fm"
        k_dig   = abs(k)
        f_dig   = f"{abs(frac)*100:03.0f}"
        tag     = f"k{k_sign}{k_dig}_{f_sign}{f_dig}"
        fname   = f"j3_{tag}.mem"
        fpath   = os.path.join(out_dir, fname)
        _write_mem(fpath, _apply_cfo(base, frac, k))
        exp_frac_word = _expected_frac_word(frac)
        j3_files[tag] = fname
        manifest["cases"][f"j3_{tag}"] = {
            "group": "J3_combined",
            "k_int": k, "frac_cfo": frac,
            "file": fname,
            "checks": {
                "frame_found": True,
                "frac_cfo_valid": True,
                "output_count": FRAME_LEN,
                "tlast_beat": FRAME_LEN - 1,
                "frac_cfo_word_approx": exp_frac_word,
            },
            "bypass_fft_limitation": (
                f"bypass FFT gives int_cfo=0 regardless of k_int={k}; "
                "replay completes but integer CFO correction is not applied"
            ),
        }
        print(f"  ({k:+d},{frac:+.2f})  frac_word={exp_frac_word:+6d}  -> {fname}")

    # ── Manifest ─────────────────────────────────────────────────────────────
    manifest["summary"] = {
        "j1_count": len(J1_K_INT),
        "j2_count": len(J2_FRAC),
        "j3_count": len(J3_PAIRS),
        "total": len(J1_K_INT) + len(J2_FRAC) + len(J3_PAIRS),
    }
    manifest["parameters"] = {
        "NSC": NSC, "CP_LEN": CP_LEN,
        "SYM_LEN":     SYM_LEN,
        "NUM_SYNC":    NUM_SYNC,
        "NUM_DATA":    NUM_DATA,
        "NUM_SYMBOLS": NUM_SYMBOLS,
        "FRAME_LEN":   FRAME_LEN,
        "PRE_ZEROS":   PRE_ZEROS, "POST_ZEROS": POST_ZEROS,
        "TOTAL_LEN":   TOTAL_LEN,
        "amplitude":   TARGET_PEAK, "SEED": SEED,
        "center_meyr": CENTER,
    }
    manifest["invariants"] = {
        "timing_metric_vs_cfo": (
            "|P| = sum(|s[n+k]|^2 * exp(-j*2pi*eps)) for CP lag → |P| magnitude "
            "is invariant to both frac and integer CFO; frame detection always works"
        ),
        "j1_meyr_mode": "behavioral DFT (USE_BEHAVIORAL_STUB=3); exact 256-pt DFT",
        "j2j3_fft_mode": "bypass fft256_dual_symbol_frontend; int_cfo=0 always",
    }

    mpath = os.path.join(out_dir, "manifest.json")
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    total = len(J1_K_INT) + len(J2_FRAC) + len(J3_PAIRS)
    print(f"\n[gen_p3_21a] {total} stimulus files in {out_dir}/")
    print(f"[gen_p3_21a] manifest -> {mpath}")
    print("[gen_p3_21a] Done.")


if __name__ == "__main__":
    main()
