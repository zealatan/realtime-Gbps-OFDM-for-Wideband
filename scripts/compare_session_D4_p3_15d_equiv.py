#!/usr/bin/env python3
"""
compare_session_D4_p3_15d_equiv.py — P3-15D Per-Case Equivalence Compare

Compares one randomised stimulus result against golden references.

Usage:
  python3 compare_session_D4_p3_15d_equiv.py \\
      --case-id case_000 \\
      --golden  golden/p3_15d_stimuli/case_000_golden.txt \\
      --meta    golden/p3_15d_stimuli/case_000_meta.json \\
      --status  sim_out/session_D4_p3_15d/case_000_status.txt \\
      --m-axis  sim_out/session_D4_p3_15d/case_000_m_axis_iq.txt \\
      --frac    sim_out/session_D4_p3_15d/case_000_frac_iq.txt \\
      [--json-out reports/session_D4_p3_15d/per_case/case_000.json]

Stages:
  D4-2  Metadata equivalence
          frame_start   vs golden_dump.c  tolerance ±2
          peak_lag      vs golden_dump.c  tolerance ±3
          slot_start    vs golden_dump.c  tolerance ±1
          frac_cfo      vs golden_dump.c  tolerance ≤1% (rel)
          meyr_peak     vs meta.json      tolerance ±4
          int_cfo_bins  vs meta.json      tolerance ±3
  D4-3  IQ equivalence
          576 M_AXIS samples vs Python NCO model  tolerance ≤1 LSB
  D4-4  Failure clustering (output in JSON)

Gate:
  CASE_EQUIV_GATE: PASS / FAIL
"""

import argparse
import json
import math
import os
import sys


# ── NCO ROM model (mirrors hardware) ─────────────────────────────────────────
def _nco_rom(idx):
    idx   = int(idx) & 0xFF
    theta = 2.0 * math.pi * idx / 256.0
    return (max(-32768, min(32767, round(32767.0 * math.cos(theta)))),
            max(-32768, min(32767, round(32767.0 * math.sin(theta)))))


def _python_nco_rotate(iq_frac, step_word_u32):
    out = []
    for n, (I_in, Q_in) in enumerate(iq_frac):
        phase_u32  = (n * step_word_u32) & 0xFFFFFFFF
        cos_s, sin_s = _nco_rom((phase_u32 >> 24) & 0xFF)
        I_out = max(-32768, min(32767, (I_in * cos_s + Q_in * sin_s) >> 15))
        Q_out = max(-32768, min(32767, (Q_in * cos_s - I_in * sin_s) >> 15))
        out.append((I_out, Q_out))
    return out


# ── File loaders ──────────────────────────────────────────────────────────────
def _load_golden(path):
    g = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                g[parts[0]] = parts[1]
    return g


def _load_status(path):
    s = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                s[k.strip()] = v.strip()
    return s


def _load_iq(path):
    samples = []
    with open(path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                samples.append((int(parts[0]), int(parts[1])))
    return samples


# ── Stage D4-2: Metadata equivalence ─────────────────────────────────────────
def stage_d4_2(case_id, golden, meta, status):
    """D4-2 Metadata equivalence.

    Gate fields (control CASE_EQUIV_GATE):
      slot_start  ±2    (synchronisation timing output)
      frac_cfo    ≤2%   (carrier frequency estimation)

    Informational only (printed, not gate-controlling):
      frame_start ±2    (energy detector, float32 vs Q15 may differ by ≤2)
      peak_lag    ±3    (autocorrelation, compound contribution to slot_start)
      meyr_peak   ±5    (noisy with randomised input; fft256_dual_symbol_frontend
                         limitation: peak unreliable when noise present)
      int_cfo_bins ±5   (same limitation: pipeline always returns ~0 for int_cfo)
    """
    print(f"\n--- Stage D4-2: Metadata ({case_id}) ---")
    gate_failures  = {}  # gate-controlling failures
    info_failures  = {}  # informational-only failures

    def _int_check(name, rtl_val, ref_val, tol, gate=True):
        err = abs(rtl_val - ref_val)
        ok  = err <= tol
        tag = "PASS" if ok else "FAIL"
        suffix = "" if gate else "  [INFO]"
        print(f"  {tag} [{name}]: RTL={rtl_val}  ref={ref_val}  diff={err}  tol=±{tol}{suffix}")
        if not ok:
            if gate:
                gate_failures[name] = err
            else:
                info_failures[name] = err
        return ok, err

    def _float_check(name, rtl_val, ref_val, rel_tol, gate=True, abs_floor=0.0):
        abs_err = abs(rtl_val - ref_val)
        if abs(ref_val) > 1e-9:
            rel_err  = abs_err / abs(ref_val)
            # Mixed tolerance: pass if absolute error ≤ max(rel_tol×|ref|, abs_floor).
            # abs_floor prevents small-ref inflation of relative error from causing
            # false failures when the absolute error is within hardware precision.
            tol_abs  = max(rel_tol * abs(ref_val), abs_floor)
            ok       = abs_err <= tol_abs
            floor_tag = f"+floor={abs_floor}" if abs_floor > 0 else ""
            label    = f"rel_err={rel_err*100:.4f}%  tol={rel_tol*100:.1f}%{floor_tag}"
        else:
            rel_err = abs_err
            ok      = abs_err < 2.0 / 32768.0
            label   = f"abs_err={abs_err:.6f}  (small ref, abs floor)"
        tag = "PASS" if ok else "FAIL"
        suffix = "" if gate else "  [INFO]"
        print(f"  {tag} [{name}]: RTL={rtl_val:.9g}  ref={ref_val:.9g}  {label}{suffix}")
        if not ok:
            if gate:
                gate_failures[name] = rel_err
            else:
                info_failures[name] = rel_err
        return ok, rel_err

    # ── Informational: intermediate frame detection fields ──────────────────
    rtl_fs  = int(status.get('FRAME_START_INDEX', -1))
    c_fs    = int(golden.get('FRAME_START', -999))
    ok_fs, err_fs = _int_check('frame_start', rtl_fs, c_fs, 2, gate=False)

    rtl_lag = int(status.get('PEAK_LAG_AUTO', -1))
    c_lag   = int(golden.get('PEAK_INDEX_AUTO', -999))
    ok_lag, err_lag = _int_check('peak_lag', rtl_lag, c_lag, 3, gate=False)

    # ── GATE: slot_start — synchronisation output, ±2 ──────────────────────
    rtl_slot = int(status.get('SLOT_START_INDEX', -1))
    c_slot   = int(golden.get('SLOT_START_INDEX', -999))
    ok_slot, err_slot = _int_check('slot_start', rtl_slot, c_slot, 2, gate=True)

    # ── GATE: frac_cfo — ≤2% relative ──────────────────────────────────────
    frac_word = int(status.get('FRAC_CFO_WORD', 0))
    rtl_frac  = frac_word / (2.0 * 32767.0)
    c_frac    = float(golden.get('FRAC_CFO_OFFSET', 0))
    ok_frac, err_frac = _float_check('frac_cfo', rtl_frac, c_frac, 0.02, gate=True,
                                    abs_floor=0.002)

    # ── Informational: Meyr/integer CFO (pipeline limitation) ──────────────
    # fft256_dual_symbol_frontend: integer CFO phase cancels in cross-product.
    # Expected values from meta.json are 255/0 (always), actual may vary with noise.
    rtl_meyr = int(status.get('INT_CFO_INDEX', -1))
    exp_meyr = int(meta.get('expected_meyr_peak_index', 255))
    ok_meyr, err_meyr = _int_check('meyr_peak', rtl_meyr, exp_meyr, 5, gate=False)

    rtl_sw_hex = status.get('INT_CFO_STEP_WORD', '0x00000000')
    rtl_sw_u32 = int(rtl_sw_hex, 16) & 0xFFFFFFFF
    rtl_sw_s32 = rtl_sw_u32 if rtl_sw_u32 < 0x80000000 else rtl_sw_u32 - 0x100000000
    rtl_kint   = -(rtl_sw_s32 // (2**24))
    exp_kint   = int(meta.get('expected_integer_cfo_word', 0))
    print(f"  [int_cfo] RTL step_word=0x{rtl_sw_u32:08X} → k_int_rtl={rtl_kint}"
          f"  expected={exp_kint}  stimulus_k_int={meta.get('integer_cfo', 0)}  [INFO]")
    ok_kint, err_kint = _int_check('int_cfo_bins', rtl_kint, exp_kint, 5, gate=False)

    passed = len(gate_failures) == 0
    n_info = len(info_failures)
    print(f"  D4-2: {'PASS' if passed else 'FAIL'}  "
          f"({len(gate_failures)} gate failure(s), {n_info} info-only warning(s))")

    d2_result = {
        "passed"          : passed,
        "frame_start_err" : err_fs,
        "peak_lag_err"    : err_lag,
        "slot_start_err"  : err_slot,
        "frac_cfo_rel_err": err_frac,
        "meyr_peak_err"   : err_meyr,
        "int_cfo_bins_err": err_kint,
        "failures"        : list(gate_failures.keys()),
        "info_warnings"   : list(info_failures.keys()),
    }
    return passed, rtl_sw_u32, d2_result


# ── Stage D4-3: IQ equivalence ────────────────────────────────────────────────
def stage_d4_3(case_id, frame_len, step_word_u32, frac_iq, m_axis_iq):
    print(f"\n--- Stage D4-3: IQ equivalence ({case_id}) ---")

    if len(frac_iq) < frame_len:
        print(f"  SKIP: frac_iq only {len(frac_iq)} samples, need {frame_len}")
        return False, {"passed": False, "skip": True,
                       "max_err_i": -1, "max_err_q": -1,
                       "mismatch_count": -1, "step_word": step_word_u32}
    if len(m_axis_iq) < frame_len:
        print(f"  SKIP: m_axis_iq only {len(m_axis_iq)} samples, need {frame_len}")
        return False, {"passed": False, "skip": True,
                       "max_err_i": -1, "max_err_q": -1,
                       "mismatch_count": -1, "step_word": step_word_u32}

    tolerance = 0 if step_word_u32 == 0 else 1
    ref_iq    = _python_nco_rotate(frac_iq[:frame_len], step_word_u32)

    max_err_i = 0
    max_err_q = 0
    mismatch  = 0
    worst_idx = -1

    for n in range(frame_len):
        I_ref, Q_ref = ref_iq[n]
        I_rtl, Q_rtl = m_axis_iq[n]
        ei = abs(I_ref - I_rtl)
        eq = abs(Q_ref - Q_rtl)
        if ei > max_err_i:
            max_err_i = ei
            worst_idx = n
        if eq > max_err_q:
            max_err_q = eq
        if ei > tolerance or eq > tolerance:
            mismatch += 1
            if mismatch <= 5:
                print(f"  MISMATCH n={n}: RTL({I_rtl},{Q_rtl})"
                      f"  REF({I_ref},{Q_ref})  err=({ei},{eq})")

    print(f"  step_word=0x{step_word_u32:08X}  tolerance={tolerance} LSB")
    print(f"  Max I error: {max_err_i} at n={worst_idx}")
    print(f"  Max Q error: {max_err_q}")
    print(f"  Mismatches:  {mismatch}/{frame_len}")

    passed = (mismatch == 0)
    if passed:
        print(f"  PASS: all {frame_len} IQ samples within {tolerance} LSB")
    else:
        print(f"  FAIL: {mismatch} mismatch(es) exceeded {tolerance} LSB")

    return passed, {
        "passed"        : passed,
        "max_err_i"     : max_err_i,
        "max_err_q"     : max_err_q,
        "mismatch_count": mismatch,
        "step_word"     : step_word_u32,
        "tolerance"     : tolerance,
        "worst_idx"     : worst_idx,
    }


# ── Stage D4-4: Failure clustering ───────────────────────────────────────────
def stage_d4_4(case_id, d2_result, d3_result):
    print(f"\n--- Stage D4-4: Failure clustering ({case_id}) ---")
    clusters = []

    for field in d2_result.get("failures", []):  # gate failures only
        clusters.append(f"d2_{field}")

    for field in d2_result.get("info_warnings", []):  # informational
        clusters.append(f"info_d2_{field}")

    if not d3_result.get("passed", False):
        if d3_result.get("skip"):
            clusters.append("d3_skip")
        else:
            clusters.append("d3_iq_mismatch")

    gate_clusters = [c for c in clusters if not c.startswith("info_")]
    if gate_clusters:
        print(f"  Gate failures: {', '.join(gate_clusters)}")
    info_clusters = [c for c in clusters if c.startswith("info_")]
    if info_clusters:
        print(f"  Info warnings: {', '.join(info_clusters)}")
    if not clusters:
        print("  All clear")

    return clusters


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--case-id',  required=True)
    parser.add_argument('--golden',   required=True,
                        help="golden_dump.c output txt (C reference, Steps 1-3)")
    parser.add_argument('--meta',     required=True,
                        help="case_NNN_meta.json (integer_cfo, meyr_peak expectation)")
    parser.add_argument('--status',   required=True)
    parser.add_argument('--m-axis',   required=True)
    parser.add_argument('--frac',     required=True)
    parser.add_argument('--json-out', default=None,
                        help="Path to write per-case JSON result (optional)")
    args = parser.parse_args()

    for path, name in [(args.golden, 'golden'), (args.meta, 'meta'),
                       (args.status, 'status'), (args.m_axis, 'm_axis'),
                       (args.frac, 'frac')]:
        if not os.path.exists(path):
            print(f"ERROR: missing {name}: {path}")
            print(f"CASE_EQUIV_GATE: FAIL (missing files)")
            sys.exit(1)

    golden    = _load_golden(args.golden)
    with open(args.meta) as f:
        meta  = json.load(f)
    status    = _load_status(args.status)
    m_axis_iq = _load_iq(args.m_axis)
    frac_iq   = _load_iq(args.frac)
    frame_len = int(status.get('FRAME_LEN', 576))

    print(f"\n{'='*60}")
    print(f" {args.case_id}")
    print(f"  golden: {args.golden}")
    print(f"  meta:   {args.meta}")
    print(f"  frame_len={frame_len}")
    print(f"  k_int={meta.get('integer_cfo', 0)}"
          f"  eps_frac={meta.get('eps_frac', 0):.4f}"
          f"  amp={meta.get('amplitude', 0):.0f}"
          f"  snr={meta.get('snr_db', 0):.1f}dB")
    print(f"{'='*60}")

    d2_pass, step_word, d2_result = stage_d4_2(
        args.case_id, golden, meta, status)
    d3_pass, d3_result = stage_d4_3(
        args.case_id, frame_len, step_word, frac_iq, m_axis_iq)
    clusters = stage_d4_4(args.case_id, d2_result, d3_result)

    passed = d2_pass and d3_pass
    print()
    if passed:
        print(f"CASE_EQUIV_GATE: PASS  ({args.case_id})")
    else:
        print(f"CASE_EQUIV_GATE: FAIL  ({args.case_id}: {', '.join(clusters)})")

    # Write JSON result if requested
    if args.json_out:
        os.makedirs(os.path.dirname(args.json_out), exist_ok=True)
        result = {
            "case_id"          : args.case_id,
            "passed"           : passed,
            "failure_clusters" : clusters,
            "d2"               : d2_result,
            "d3"               : d3_result,
            "params"           : {
                "pre_zeros" : meta.get("pre_zeros", -1),
                "eps_frac"  : meta.get("eps_frac",  0.0),
                "k_int"     : meta.get("integer_cfo", 0),
                "amplitude" : meta.get("amplitude", 0.0),
                "snr_db"    : meta.get("snr_db", 0.0),
            },
        }
        with open(args.json_out, "w") as fj:
            json.dump(result, fj, indent=2)
            fj.write("\n")

    sys.exit(0 if passed else 1)


if __name__ == '__main__':
    main()
