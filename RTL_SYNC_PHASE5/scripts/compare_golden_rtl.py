#!/usr/bin/env python3
"""
compare_golden_rtl.py — Phase 3 golden C vs RTL comparison (phase3_sync_top)

Usage:
    python3 scripts/compare_golden_rtl.py \\
        golden/phase3_golden_values.txt \\
        sim_out/rtl_results.txt

Exits 0 on PASS, 1 on FAIL.

Golden keys (from golden_dump.c):
    DETECTION_STATUS, FRAME_START, PEAK_INDEX_AUTO, SLOT_START_INDEX,
    FRAC_CFO_OFFSET, PSS_START, SSS_START

RTL keys (from phase3_sync_reference_compare_tb.sv):
    DETECTION_STATUS, RTL_FRAME_START_INDEX, RTL_PEAK_INDEX,
    RTL_SLOT_START_INDEX, RTL_FRAC_CFO_WORD, RTL_PSS_START,
    RTL_SSS_START, RTL_INTEGER_CFO_WORD, RTL_DONE, RTL_ERROR_CODE

Tolerances:
    frameStart      : ±1 sample (absolute)
    peakIndex       : ±1 sample (absolute)
    slotStartIndex  : ±1 sample (absolute)
    frac CFO        : 1% relative (on Q1.15 domain value) OR ±2 LSB floor
    PSS/SSS offsets : exact match (these are parameter-derived constants)
    integer CFO     : informational only (not a PASS blocker)
"""

import sys
import math

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
PI = math.pi
Q15_MAX = 32768.0  # 2^15

# Frac CFO relative tolerance (1%) and absolute floor (2 Q1.15 LSB)
FRAC_CFO_REL_TOL     = 0.01
FRAC_CFO_ABS_FLOOR   = 2.0   # LSB in Q1.15 domain


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def parse_kv_file(path):
    """Parse a space-separated key value file, skipping # comment lines."""
    kv = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                kv[parts[0]] = parts[1]
    return kv


def check_int(name, golden_int, rtl_int, abs_tol, note=""):
    """Compare two integer values with an absolute tolerance. Returns True on PASS."""
    delta = abs(golden_int - rtl_int)
    ok = delta <= abs_tol
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] {name}")
    print(f"         golden={golden_int}  rtl={rtl_int}  "
          f"delta={delta}  tol=±{abs_tol} samples")
    if note:
        print(f"         note: {note}")
    return ok


def check_frac_cfo(g_offset_float, r_word_int):
    """
    Compare frac CFO.

    C side:  FRAC_CFO_OFFSET = −atan2(P_Q, P_I) / (2π)  ∈ [−0.5, +0.5]
    RTL side: RTL_FRAC_CFO_WORD = atan2(P_Q, P_I) × 32768/π  (Q1.15 signed int)
              The RTL cp_autocorr_core uses the FORWARD product convention so
              atan2 output has SAME sign as the CFO (opposite to the C convention).

    Relationship (verified by simulation):
        RTL_word = +FRAC_CFO_OFFSET × 2 × 32768

    We compare in the Q1.15 domain:
        expected_q15 = +g_offset_float × 2 × 32768
        delta_q15    = |expected_q15 − r_word_int|
        tolerance    = max(|expected_q15| × REL_TOL, ABS_FLOOR)

    Returns True on PASS.
    """
    expected_q15 = g_offset_float * 2.0 * Q15_MAX
    delta = abs(expected_q15 - float(r_word_int))
    tol = max(abs(expected_q15) * FRAC_CFO_REL_TOL, FRAC_CFO_ABS_FLOOR)

    # Also compute the float frac offset equivalents for display
    rtl_offset = float(r_word_int) / (2.0 * Q15_MAX)
    rel_err_pct = (delta / abs(expected_q15) * 100.0) if abs(expected_q15) > 1e-9 else 0.0

    ok = delta <= tol
    status = "PASS" if ok else "FAIL"
    print(f"  [{status}] frac CFO (Q1.15 domain)")
    print(f"         golden offset = {g_offset_float:.9g}  rtl offset = {rtl_offset:.9g}")
    print(f"         expected_q15 = {expected_q15:.3f}  rtl_word = {r_word_int}"
          f"  delta = {delta:.3f}")
    print(f"         tol = max({abs(expected_q15):.3f}×{FRAC_CFO_REL_TOL*100:.0f}%,"
          f" {FRAC_CFO_ABS_FLOOR}LSB) = {tol:.3f}")
    print(f"         relative error: {rel_err_pct:.3f}%")
    return ok


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <golden_file> <rtl_results_file>")
        sys.exit(1)

    golden_path = sys.argv[1]
    rtl_path    = sys.argv[2]

    try:
        golden = parse_kv_file(golden_path)
    except FileNotFoundError:
        print(f"ERROR: Golden file not found: {golden_path}")
        sys.exit(1)

    try:
        rtl = parse_kv_file(rtl_path)
    except FileNotFoundError:
        print(f"ERROR: RTL results file not found: {rtl_path}")
        sys.exit(1)

    print("=" * 64)
    print("Phase 3 — Golden C vs RTL Comparison  (phase3_sync_top)")
    print(f"  Golden : {golden_path}")
    print(f"  RTL    : {rtl_path}")
    print("=" * 64)

    all_pass = True

    # ------------------------------------------------------------------
    # Check 0: Detection status
    # ------------------------------------------------------------------
    print("\n--- Detection Status ---")
    g_det = int(golden.get("DETECTION_STATUS", "0"))
    r_det = int(rtl.get("DETECTION_STATUS", "0"))
    r_err = int(rtl.get("RTL_ERROR_CODE", "0"))
    r_done = int(rtl.get("RTL_DONE", "0"))

    if g_det == r_det:
        print(f"  [PASS] DETECTION_STATUS: both={g_det}")
    else:
        print(f"  [FAIL] DETECTION_STATUS: golden={g_det}  rtl={r_det}")
        if r_err != 0:
            print(f"  RTL error_code={r_err}  (check frame detection threshold)")
        elif not r_done:
            print(f"  RTL done never fired  (simulation timeout or IQ too short)")
        all_pass = False

    if not r_done:
        print("\n  [FATAL] RTL done was never asserted — cannot compare values.")
        print(f"\n{'PASS' if all_pass else 'FAIL'}")
        sys.exit(0 if all_pass else 1)

    if g_det == 0 or r_det == 0:
        print("\n  Cannot compare indices/CFO (detection failed on one side).")
        print(f"\n{'PASS' if all_pass else 'FAIL'}")
        sys.exit(0 if all_pass else 1)

    # ------------------------------------------------------------------
    # Check 1: frameStart
    # ------------------------------------------------------------------
    print("\n--- frameStart: FRAME_START vs RTL_FRAME_START_INDEX ---")
    g_fs = int(golden.get("FRAME_START", "-1"))
    r_fs = int(rtl.get("RTL_FRAME_START_INDEX", "-1"))
    if r_fs == -1:
        print("  [FAIL] RTL_FRAME_START_INDEX not captured (dbg_frame_start_valid never fired)")
        all_pass = False
    else:
        all_pass &= check_int("frameStart", g_fs, r_fs, 1)

    # ------------------------------------------------------------------
    # Check 2: peakIndex
    # ------------------------------------------------------------------
    print("\n--- peakIndex: PEAK_INDEX_AUTO vs RTL_PEAK_INDEX ---")
    g_pi = int(golden.get("PEAK_INDEX_AUTO", "-1"))
    r_pi = int(rtl.get("RTL_PEAK_INDEX", "-1"))
    if r_pi == -1:
        print("  [FAIL] RTL_PEAK_INDEX not captured (dbg_peak_valid never fired)")
        all_pass = False
    else:
        all_pass &= check_int("peakIndex", g_pi, r_pi, 1)

    # ------------------------------------------------------------------
    # Check 3: slotStartIndex
    # ------------------------------------------------------------------
    print("\n--- slotStartIndex: SLOT_START_INDEX vs RTL_SLOT_START_INDEX ---")
    g_ss = int(golden.get("SLOT_START_INDEX", "-1"))
    r_ss = int(rtl.get("RTL_SLOT_START_INDEX", "-1"))
    if r_ss == -1:
        print("  [FAIL] RTL_SLOT_START_INDEX not captured (dbg_slot_start_valid never fired)")
        all_pass = False
    else:
        all_pass &= check_int(
            "slotStartIndex", g_ss, r_ss, 1,
            note="C: peakIndexAuto+frameStart; RTL: frame_index+peak_lag latched on frac_done"
        )

    # ------------------------------------------------------------------
    # Check 4: Fractional CFO
    # ------------------------------------------------------------------
    print("\n--- frac CFO: FRAC_CFO_OFFSET vs RTL_FRAC_CFO_WORD ---")
    g_frac = float(golden.get("FRAC_CFO_OFFSET", "0"))
    r_frac_raw = rtl.get("RTL_FRAC_CFO_WORD", None)
    if r_frac_raw is None or int(r_frac_raw) == -99999:
        print("  [FAIL] RTL_FRAC_CFO_WORD not captured (dbg_frac_cfo_valid never fired)")
        all_pass = False
    else:
        all_pass &= check_frac_cfo(g_frac, int(r_frac_raw))

    # ------------------------------------------------------------------
    # Check 5: PSS_START (constant sanity check)
    # ------------------------------------------------------------------
    print("\n--- PSS offset: PSS_START vs RTL_PSS_START ---")
    g_pss = int(golden.get("PSS_START", str(32)))     # default CP_LEN=32
    r_pss = int(rtl.get("RTL_PSS_START", str(32)))
    all_pass &= check_int("pss_start (constant)", g_pss, r_pss, 0,
                          note="Must be CP_LEN=32 exactly")

    # ------------------------------------------------------------------
    # Check 6: SSS_START (constant sanity check)
    # ------------------------------------------------------------------
    print("\n--- SSS offset: SSS_START vs RTL_SSS_START ---")
    g_sss = int(golden.get("SSS_START", str(320)))    # default 2*CP_LEN+NSC=320
    r_sss = int(rtl.get("RTL_SSS_START", str(320)))
    all_pass &= check_int("sss_start (constant)", g_sss, r_sss, 0,
                          note="Must be 2*CP_LEN+NSC=320 exactly")

    # ------------------------------------------------------------------
    # Check 7: PSS sample count (extraction window verification)
    # ------------------------------------------------------------------
    print("\n--- PSS sample count: PSS_SAMPLE_COUNT vs RTL_PSS_SAMPLE_COUNT ---")
    g_pss_cnt = int(golden.get("PSS_SAMPLE_COUNT", "256"))
    r_pss_cnt_raw = rtl.get("RTL_PSS_SAMPLE_COUNT", None)
    if r_pss_cnt_raw is None:
        print("  [FAIL] RTL_PSS_SAMPLE_COUNT not present in RTL results")
        all_pass = False
    else:
        all_pass &= check_int("pss_sample_count", g_pss_cnt, int(r_pss_cnt_raw), 0,
                              note="Must be exactly NSC=256 samples extracted")

    # ------------------------------------------------------------------
    # Check 8: SSS sample count (extraction window verification)
    # ------------------------------------------------------------------
    print("\n--- SSS sample count: SSS_SAMPLE_COUNT vs RTL_SSS_SAMPLE_COUNT ---")
    g_sss_cnt = int(golden.get("SSS_SAMPLE_COUNT", "256"))
    r_sss_cnt_raw = rtl.get("RTL_SSS_SAMPLE_COUNT", None)
    if r_sss_cnt_raw is None:
        print("  [FAIL] RTL_SSS_SAMPLE_COUNT not present in RTL results")
        all_pass = False
    else:
        all_pass &= check_int("sss_sample_count", g_sss_cnt, int(r_sss_cnt_raw), 0,
                              note="Must be exactly NSC=256 samples extracted")

    # ------------------------------------------------------------------
    # Check 9: Meyr peak index (P3-08 — real PASS check with valid ROM)
    # ------------------------------------------------------------------
    print("\n--- Meyr peak index: MEYR_PEAK_INDEX vs RTL_MEYR_PEAK_INDEX ---")
    g_peak_raw = golden.get("MEYR_PEAK_INDEX", None)
    r_peak_raw = rtl.get("RTL_MEYR_PEAK_INDEX", None)
    if g_peak_raw is None:
        print("  [INFO] MEYR_PEAK_INDEX not in golden file (old golden_dump binary)")
        print("         Rebuild golden_dump to enable this check.")
    elif r_peak_raw is None or int(r_peak_raw) == -1:
        print("  [FAIL] RTL_MEYR_PEAK_INDEX not captured (Meyr estimator did not complete)")
        all_pass = False
    else:
        all_pass &= check_int("meyr_peak_index", int(g_peak_raw), int(r_peak_raw), 1,
                              note="Expected NSC-1=255 for INT_CFO=0 with valid ROM")

    # ------------------------------------------------------------------
    # Check 10: Integer CFO step word (P3-08 — real PASS check with valid ROM)
    # ------------------------------------------------------------------
    print("\n--- Integer CFO step word: INTEGER_CFO_WORD vs RTL_INTEGER_CFO_WORD ---")
    g_cfo_raw = golden.get("INTEGER_CFO_WORD", None)
    r_int_cfo = int(rtl.get("RTL_INTEGER_CFO_WORD", "-99999"))

    if g_cfo_raw is None:
        print("  [INFO] INTEGER_CFO_WORD not in golden file (old golden_dump binary)")
        print("         Rebuild golden_dump to enable this check.")
        if r_int_cfo != -99999:
            int_cfo_bins = (-r_int_cfo) >> 24
            print(f"  [INFO] RTL_INTEGER_CFO_WORD = {r_int_cfo}"
                  f"  (≈ {int_cfo_bins} subcarrier bins)")
    elif r_int_cfo == -99999:
        print("  [FAIL] RTL_INTEGER_CFO_WORD not captured (Meyr estimator did not complete)")
        all_pass = False
    else:
        g_int_cfo = int(g_cfo_raw)
        all_pass &= check_int("integer_cfo_word", g_int_cfo, r_int_cfo, 0,
                              note="Expected 0 for INT_CFO=0 stimulus with valid ROM")

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    print("\n" + "=" * 64)
    result = "PASS" if all_pass else "FAIL"
    print(f"Overall result: {result}")
    print("=" * 64)

    sys.exit(0 if all_pass else 1)


if __name__ == "__main__":
    main()
