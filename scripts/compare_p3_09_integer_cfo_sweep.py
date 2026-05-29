#!/usr/bin/env python3
"""
compare_p3_09_integer_cfo_sweep.py — P3-09 integer CFO sweep comparison

Usage:
    python3 scripts/compare_p3_09_integer_cfo_sweep.py \\
        golden/p3_09_sweep/manifest.json \\
        sim_out/p3_09_sweep/

Reads the manifest (written by gen_phase3_integer_cfo_sweep_vectors.py) and one
RTL results file per case from sim_out/p3_09_sweep/case_{tag}_results.txt.

Checks per case:
  1. detection: DETECTION_STATUS == 1
  2. timeout:   RTL_DONE == 1
  3. no error:  RTL_ERROR_CODE == 0
  4. meyr peak: RTL_MEYR_PEAK_INDEX == 255 + k_int  (tolerance ±1)
  5. int_cfo:   int_cfo derived from RTL_INTEGER_CFO_WORD == k_int  (exact)
  6. cfo_word:  RTL_INTEGER_CFO_WORD == −k_int × 16777216  (exact)

Exits 0 if all present cases PASS, 1 if any present case FAILS.
Cases whose results file is absent are reported as SKIP (not FAIL).

Note: with bypass fft256_dual_symbol_frontend, all k_int≠0 cases will FAIL checks
4–6 because integer CFO cancels in the time-domain cross-product. This is the
expected and CORRECT behaviour — do not fake PASS.
"""

import sys
import os
import json

INT_CFO_SHIFT = 24          # 32 − log2(256)
INT_CFO_SCALE = 1 << INT_CFO_SHIFT   # 16777216
CENTER        = 255


def parse_kv(path):
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


def int_cfo_from_word(word_s32):
    """Decode integer CFO bins from NCO step word: int_cfo = −word / 2^24."""
    return -word_s32 >> INT_CFO_SHIFT


def compare_case(tag, k_int, rtl_path, verbose=True):
    """
    Compare a single sweep case.
    Returns (status, details) where status is 'PASS', 'FAIL', or 'SKIP'.
    """
    if not os.path.exists(rtl_path):
        return "SKIP", f"  [SKIP] {tag}: results file not found: {rtl_path}"

    rtl = parse_kv(rtl_path)

    expected_peak_index  = CENTER + k_int
    expected_int_cfo     = k_int
    expected_cfo_word    = (-k_int) * INT_CFO_SCALE
    # Convert to signed 32-bit
    if expected_cfo_word >= (1 << 31):
        expected_cfo_word -= (1 << 32)

    lines   = []
    case_ok = True

    lines.append(f"\n--- Case {tag}  (k_int={k_int:+d}) ---")
    lines.append(f"    RTL file: {rtl_path}")

    # Check 1: detection
    det = int(rtl.get("DETECTION_STATUS", "0"))
    ok  = (det == 1)
    case_ok &= ok
    lines.append(f"  [{'PASS' if ok else 'FAIL'}] detection: DETECTION_STATUS={det}  (expected 1)")

    # Check 2: timeout / done
    done_seen = int(rtl.get("RTL_DONE", "0"))
    ok = (done_seen == 1)
    case_ok &= ok
    lines.append(f"  [{'PASS' if ok else 'FAIL'}] timeout:   RTL_DONE={done_seen}  (expected 1)")

    # Check 3: no error
    err_code = int(rtl.get("RTL_ERROR_CODE", "0"))
    ok = (err_code == 0)
    case_ok &= ok
    lines.append(f"  [{'PASS' if ok else 'FAIL'}] no_error:  RTL_ERROR_CODE={err_code}  (expected 0)")

    # Check 4: Meyr peak index
    peak_raw = rtl.get("RTL_MEYR_PEAK_INDEX", None)
    if peak_raw is None or int(peak_raw) == -1:
        case_ok = False
        lines.append(f"  [FAIL] meyr_peak: RTL_MEYR_PEAK_INDEX not captured")
    else:
        rtl_peak = int(peak_raw)
        delta    = abs(rtl_peak - expected_peak_index)
        ok       = (delta <= 1)
        case_ok &= ok
        lines.append(f"  [{'PASS' if ok else 'FAIL'}] meyr_peak: RTL={rtl_peak}  "
                     f"expected={expected_peak_index}  delta={delta}  tol=±1")

    # Check 5 & 6: integer CFO step word
    word_raw = rtl.get("RTL_INTEGER_CFO_WORD", None)
    if word_raw is None or int(word_raw) == -99999:
        case_ok = False
        lines.append(f"  [FAIL] cfo_word:  RTL_INTEGER_CFO_WORD not captured")
    else:
        rtl_word    = int(word_raw)
        rtl_int_cfo = int_cfo_from_word(rtl_word)

        ok5 = (rtl_int_cfo == expected_int_cfo)
        case_ok &= ok5
        lines.append(f"  [{'PASS' if ok5 else 'FAIL'}] int_cfo:   derived={rtl_int_cfo}  "
                     f"expected={expected_int_cfo}")

        ok6 = (rtl_word == expected_cfo_word)
        case_ok &= ok6
        lines.append(f"  [{'PASS' if ok6 else 'FAIL'}] cfo_word:  RTL={rtl_word}  "
                     f"expected={expected_cfo_word}")

    status = "PASS" if case_ok else "FAIL"
    lines.append(f"  => Case result: {status}")

    return status, "\n".join(lines)


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <manifest.json> <sim_out_dir>")
        print(f"  manifest.json : golden/p3_09_sweep/manifest.json")
        print(f"  sim_out_dir   : sim_out/p3_09_sweep/")
        sys.exit(1)

    manifest_path = sys.argv[1]
    sim_dir       = sys.argv[2]

    try:
        with open(manifest_path) as f:
            manifest = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: manifest not found: {manifest_path}")
        print("       Run gen_phase3_integer_cfo_sweep_vectors.py first.")
        sys.exit(1)

    print("=" * 64)
    print("P3-09 — Integer CFO Sweep Comparison")
    print(f"  Manifest : {manifest_path}")
    print(f"  Sim dir  : {sim_dir}")
    print("=" * 64)

    cases     = manifest.get("cases", {})
    sweep     = manifest.get("sweep_k_int", [])
    all_pass  = True
    any_seen  = False
    skip_list = []
    fail_list = []
    pass_list = []

    for k_int in sweep:
        tag      = ("km" + str(abs(k_int))) if k_int < 0 else ("k0" if k_int == 0 else "kp" + str(k_int))
        rtl_path = os.path.join(sim_dir, f"case_{tag}_results.txt")

        status, detail = compare_case(tag, k_int, rtl_path)
        print(detail)

        if status == "PASS":
            pass_list.append(tag)
            any_seen = True
        elif status == "FAIL":
            fail_list.append(tag)
            all_pass = False
            any_seen = True
        else:
            skip_list.append(tag)

    print("\n" + "=" * 64)
    print("Summary")
    print(f"  PASS : {len(pass_list)}  {pass_list}")
    print(f"  FAIL : {len(fail_list)}  {fail_list}")
    print(f"  SKIP : {len(skip_list)}  {skip_list}")

    if not any_seen:
        print("\n  [INFO] No RTL result files found — run simulation first.")
        print("         Expected path: sim_out/p3_09_sweep/case_{tag}_results.txt")
        print("\nBLOCKED — no simulation results available")
        sys.exit(1)

    if skip_list:
        print(f"\n  [INFO] {len(skip_list)} case(s) skipped (no results file).")

    result = "PASS" if (all_pass and not fail_list) else "FAIL"
    print(f"\nOverall: {result}")
    print("=" * 64)

    sys.exit(0 if result == "PASS" else 1)


if __name__ == "__main__":
    main()
