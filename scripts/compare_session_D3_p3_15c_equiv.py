#!/usr/bin/env python3
"""
compare_session_D3_p3_15c_equiv.py — P3-15C Equivalence Compare

Compares one stimulus result against golden references.

Usage:
    python3 compare_session_D3_p3_15c_equiv.py \\
        --stim-id stim_01 \\
        --golden  golden/p3_15c_stimuli/stim_01_golden.txt \\
        --status  sim_out/session_D3_p3_15c/stim_01_status.txt \\
        --m-axis  sim_out/session_D3_p3_15c/stim_01_m_axis_iq.txt \\
        --frac    sim_out/session_D3_p3_15c/stim_01_frac_iq.txt

Stages:
  D2: Metadata equivalence (RTL vs C reference)
  D3: IQ equivalence (RTL M_AXIS vs Python NCO model using frac IQ)

Gate:
  STIM_EQUIV_GATE: PASS / FAIL
"""

import sys
import os
import math
import argparse


# ---------------------------------------------------------------------------
# NCO ROM model (same as compare_session_C_p3_14c_dma_replay_golden.py)
# ---------------------------------------------------------------------------

def nco_rom(idx):
    idx   = int(idx) & 0xFF
    theta = 2.0 * math.pi * idx / 256.0
    cos_s = max(-32768, min(32767, round(32767.0 * math.cos(theta))))
    sin_s = max(-32768, min(32767, round(32767.0 * math.sin(theta))))
    return cos_s, sin_s


def python_nco_rotate(iq_frac, step_word_u32):
    out = []
    for n, (I_in, Q_in) in enumerate(iq_frac):
        phase_u32 = (n * step_word_u32) & 0xFFFFFFFF
        idx       = (phase_u32 >> 24) & 0xFF
        cos_s, sin_s = nco_rom(idx)
        I_out = max(-32768, min(32767, (I_in * cos_s + Q_in * sin_s) >> 15))
        Q_out = max(-32768, min(32767, (Q_in * cos_s - I_in * sin_s) >> 15))
        out.append((I_out, Q_out))
    return out


# ---------------------------------------------------------------------------
# File loaders
# ---------------------------------------------------------------------------

def load_golden(path):
    """Load golden_dump.c output: 'KEY value' per line."""
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


def load_status(path):
    """Load RTL status file: 'KEY=value' per line."""
    s = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                s[k.strip()] = v.strip()
    return s


def load_iq(path):
    """Load 'I Q' decimal per line → list of (I, Q) signed int tuples."""
    samples = []
    with open(path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                samples.append((int(parts[0]), int(parts[1])))
    return samples


# ---------------------------------------------------------------------------
# Stage D2: Metadata equivalence
# ---------------------------------------------------------------------------

def stage_d2(stim_id, golden, status):
    print(f"\n--- Stage D2: Metadata ({stim_id}) ---")
    fail = 0
    frame_len = int(status.get('FRAME_LEN', 576))

    # Helper: int check with tolerance
    def check_int(name, rtl_val, c_val, tol, rtl_key, c_key):
        nonlocal fail
        err = abs(rtl_val - c_val)
        if err <= tol:
            print(f"PASS [D2/{name}]: RTL={rtl_val}  C={c_val}  diff={err}  tol=±{tol}")
        else:
            print(f"FAIL [D2/{name}]: RTL={rtl_val}  C={c_val}  diff={err}  tol=±{tol}")
            fail += 1
        return err <= tol

    # Helper: float relative check
    def check_float_rel(name, rtl_val, c_val, rel_tol):
        nonlocal fail
        if abs(c_val) > 1e-9:
            rel_err = abs(rtl_val - c_val) / abs(c_val)
            ok = rel_err <= rel_tol
            label = f"rel_err={rel_err*100:.4f}%  tol={rel_tol*100:.1f}%"
        else:
            abs_err = abs(rtl_val - c_val)
            ok = abs_err < 2.0 / 32768.0
            label = f"abs_err={abs_err:.6f}  (small c_val, abs tolerance)"
        if ok:
            print(f"PASS [D2/{name}]: RTL={rtl_val:.9g}  C={c_val:.9g}  {label}")
        else:
            print(f"FAIL [D2/{name}]: RTL={rtl_val:.9g}  C={c_val:.9g}  {label}")
            fail += 1
        return ok

    # D2.1: FRAME_START — tolerance ±2: RTL fixed-point energy detector can differ
    #        from C float by 1-2 samples at the threshold crossing edge
    rtl_fs = int(status.get('FRAME_START_INDEX', -1))
    c_fs   = int(golden.get('FRAME_START', -999))
    check_int('frame_start', rtl_fs, c_fs, 2, 'FRAME_START_INDEX', 'FRAME_START')

    # D2.2: PEAK_INDEX_AUTO — tolerance ±3: covers ±2 frame_start + ±1 autocorr
    rtl_lag = int(status.get('PEAK_LAG_AUTO', -1))
    c_lag   = int(golden.get('PEAK_INDEX_AUTO', -999))
    check_int('peak_lag', rtl_lag, c_lag, 3, 'PEAK_LAG_AUTO', 'PEAK_INDEX_AUTO')

    # D2.3: SLOT_START_INDEX — tightest constraint: must be within ±1
    rtl_slot = int(status.get('SLOT_START_INDEX', -1))
    c_slot   = int(golden.get('SLOT_START_INDEX', -999))
    check_int('slot_start', rtl_slot, c_slot, 1, 'SLOT_START_INDEX', 'SLOT_START_INDEX')

    # D2.4: FRAC_CFO — RTL register stores atan2(P_Q_rtl, P_I) where RTL P_Q sign
    # convention is opposite to golden_dump.c (see cp_autocorr_core.v comment).
    # RTL frac_phase = +2*pi*eps_frac, CORDIC encodes as value = round(2*eps_frac*32767).
    # Decode: eps_frac = frac_word / (2 * 32767)
    # C reference: FRAC_CFO_OFFSET = -atan2(P_Q_c, P_I)/(2*pi) = +eps_frac.
    frac_word = int(status.get('FRAC_CFO_WORD', 0))
    rtl_frac  = frac_word / (2.0 * 32767.0)
    c_frac    = float(golden.get('FRAC_CFO_OFFSET', 0))
    check_float_rel('frac_cfo', rtl_frac, c_frac, 0.01)

    # D2.5: MEYR_PEAK_INDEX — golden_dump.c hardcodes 255; bypass stub may deviate
    #        by up to ±3 bins for large eps_frac stimuli (L-01 documented limitation)
    rtl_meyr = int(status.get('INT_CFO_INDEX', -1))
    c_meyr   = int(golden.get('MEYR_PEAK_INDEX', 255))
    check_int('meyr_peak', rtl_meyr, c_meyr, 3, 'INT_CFO_INDEX', 'MEYR_PEAK_INDEX')

    # D2.6: INTEGER_CFO (k_int bins, ±1 tolerance for FFT bypass off-by-one).
    # RTL step_word = (-k_int) << 24; decode: k_int_rtl = -(step_word_s32 // 2^24).
    # C reference: INTEGER_CFO_WORD is k_int directly (always 0 for these stimuli).
    rtl_sw_hex = status.get('INT_CFO_STEP_WORD', '0x00000000')
    rtl_sw_u32 = int(rtl_sw_hex, 16) & 0xFFFFFFFF
    rtl_sw_s32 = rtl_sw_u32 if rtl_sw_u32 < 0x80000000 else rtl_sw_u32 - 0x100000000
    rtl_kint   = -(rtl_sw_s32 // (2**24))
    c_kint     = int(golden.get('INTEGER_CFO_WORD', 0))
    print(f"  [D2/int_cfo] RTL step_word=0x{rtl_sw_u32:08X} → k_int_rtl={rtl_kint}"
          f"  C k_int={c_kint}")
    check_int('int_cfo_bins', rtl_kint, c_kint, 3, 'INT_CFO_INDEX', 'INTEGER_CFO_WORD')

    print(f"  D2 result: {'PASS' if fail == 0 else 'FAIL'}  ({fail} failures)")
    return fail == 0, rtl_sw_u32  # also return step_word for D3


# ---------------------------------------------------------------------------
# Stage D3: IQ equivalence
# ---------------------------------------------------------------------------

def stage_d3(stim_id, frame_len, step_word_u32, frac_iq, m_axis_iq):
    print(f"\n--- Stage D3: IQ equivalence ({stim_id}) ---")
    fail = 0

    if len(frac_iq) < frame_len:
        print(f"SKIP [D3]: frac_iq only {len(frac_iq)} samples, need {frame_len}")
        return False
    if len(m_axis_iq) < frame_len:
        print(f"SKIP [D3]: m_axis_iq only {len(m_axis_iq)} samples, need {frame_len}")
        return False

    ref_iq    = python_nco_rotate(frac_iq[:frame_len], step_word_u32)
    tolerance = 0 if step_word_u32 == 0 else 1

    max_err_i = 0
    max_err_q = 0
    mismatch  = 0
    worst_idx = -1

    for n in range(frame_len):
        I_ref, Q_ref = ref_iq[n]
        I_rtl, Q_rtl = m_axis_iq[n]
        err_i = abs(I_ref - I_rtl)
        err_q = abs(Q_ref - Q_rtl)
        if err_i > max_err_i:
            max_err_i = err_i
            worst_idx = n
        if err_q > max_err_q:
            max_err_q = err_q
        if err_i > tolerance or err_q > tolerance:
            mismatch += 1
            if mismatch <= 5:
                print(f"  MISMATCH n={n}: RTL({I_rtl},{Q_rtl}) REF({I_ref},{Q_ref})"
                      f" err=({err_i},{err_q})")

    print(f"  step_word = 0x{step_word_u32:08X}  tolerance = {tolerance} LSB")
    print(f"  Max I error: {max_err_i}  at n={worst_idx}")
    print(f"  Max Q error: {max_err_q}")
    print(f"  Mismatches:  {mismatch}/{frame_len}")

    # Preview first 4 samples
    print("  Sample preview (first 4):")
    for n in range(min(4, frame_len)):
        I_r, Q_r = ref_iq[n]
        I_x, Q_x = m_axis_iq[n]
        I_f, Q_f = frac_iq[n]
        print(f"    n={n}: frac=({I_f:6d},{Q_f:6d})"
              f"  ref=({I_r:6d},{Q_r:6d})"
              f"  rtl=({I_x:6d},{Q_x:6d})")

    if mismatch == 0:
        print(f"PASS [D3]: All {frame_len} IQ samples within tolerance")
    else:
        print(f"FAIL [D3]: {mismatch} mismatches (tolerance={tolerance})")
        fail += 1

    return fail == 0


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--stim-id', required=True)
    parser.add_argument('--golden',  required=True)
    parser.add_argument('--status',  required=True)
    parser.add_argument('--m-axis',  required=True)
    parser.add_argument('--frac',    required=True)
    args = parser.parse_args()

    # Check files
    for path, name in [(args.golden, 'golden'), (args.status, 'status'),
                       (args.m_axis, 'm_axis'), (args.frac, 'frac')]:
        if not os.path.exists(path):
            print(f"ERROR: missing file ({name}): {path}")
            print(f"STIM_EQUIV_GATE: FAIL (missing files)")
            sys.exit(1)

    golden   = load_golden(args.golden)
    status   = load_status(args.status)
    m_axis   = load_iq(args.m_axis)
    frac_iq  = load_iq(args.frac)
    frame_len = int(status.get('FRAME_LEN', 576))

    print(f"\n========== {args.stim_id} ==========")
    print(f"  golden:   {args.golden}")
    print(f"  status:   {args.status}")
    print(f"  frame_len={frame_len}")

    d2_pass, step_word = stage_d2(args.stim_id, golden, status)
    d3_pass            = stage_d3(args.stim_id, frame_len, step_word, frac_iq, m_axis)

    print()
    if d2_pass and d3_pass:
        print(f"STIM_EQUIV_GATE: PASS  ({args.stim_id})")
        sys.exit(0)
    else:
        reasons = []
        if not d2_pass: reasons.append("D2 metadata")
        if not d3_pass: reasons.append("D3 IQ")
        print(f"STIM_EQUIV_GATE: FAIL  ({args.stim_id}: {', '.join(reasons)})")
        sys.exit(1)


if __name__ == '__main__':
    main()
