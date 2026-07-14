#!/usr/bin/env python3
"""
compare_session_C_p3_14c_dma_replay_golden.py — P3-14C IQ Golden Compare

Stages:
  Stage 1: Structural checks (INT_CFO_APPLIED, OUTPUT_COUNT, TLAST position)
  Stage 2: Length / TLAST checks on captured M_AXIS
  Stage 3: Sample-by-sample IQ compare — RTL M_AXIS vs Python NCO+rotator model

Sign convention (derived from RTL source):
  NCO (nco_phase_gen.v):
    phase_acc starts at 0 after phase_reset.
    step_word = (-meyr_int_cfo) << 24   (from phase3_sync_top.v line ~196)
    phase at sample n: n * step_word   (32-bit wrapping, unsigned)
    ROM index:  phase_acc[31:24]  (8 MSBs, unsigned 0-255)

  Rotator (complex_rotator.v, wraps complex_mult_iq CONJ_B=1):
    r_out = r_in * exp(-j*theta)
    I_out = I_in*cos(theta) + Q_in*sin(theta)
    Q_out = Q_in*cos(theta) - I_in*sin(theta)
    Arithmetic: (I_in * cos_q15 + Q_in * sin_q15) >> 15  (Python floor = Verilog [30:15])

  IQ packing:
    tdata[15:0]  = I (in-phase, lower 16 bits)
    tdata[31:16] = Q (quadrature, upper 16 bits)

Tolerance:
  For step_word=0 (identity rotation, our standard test stimulus):
    cos = 0x7FFF = 32767, sin = 0
    I_out = I_in * 32767 // 32768  (exact, floor)
    Q_out = Q_in * 32767 // 32768  (exact, floor)
    Tolerance: 0 (bit-exact for zero step_word)

  For non-zero step_word:
    cos/sin computed analytically from ROM formula: round(32767 * cos/sin(2pi*idx/256))
    Tolerance: +/- 1 LSB per component (floating-point ROM rounding vs hardware ROM)

OFFICIAL_GATE: PASS when all Stage 1-3 checks pass.
"""

import sys
import os
import math

# ---------------------------------------------------------------------------
# ROM model (matches nco_phase_gen.v exactly for index 0; analytically derived
# for all other indices using the same formula)
# ---------------------------------------------------------------------------

def nco_rom(idx):
    """Return (cos_s16, sin_s16) for ROM index 0-255.  Exact for index 0."""
    idx = int(idx) & 0xFF
    theta = 2.0 * math.pi * idx / 256.0
    cos_raw = round(32767.0 * math.cos(theta))
    sin_raw = round(32767.0 * math.sin(theta))
    cos_s16 = max(-32768, min(32767, cos_raw))
    sin_s16 = max(-32768, min(32767, sin_raw))
    return cos_s16, sin_s16


def python_nco_rotate(iq_frac, step_word_u32):
    """
    Apply integer NCO + rotator arithmetic matching the RTL.

    iq_frac:        list of (I, Q) tuples (signed 16-bit each)
    step_word_u32:  unsigned 32-bit NCO step word

    Returns list of (I_out, Q_out) tuples (signed 16-bit).

    Phase at sample n = n * step_word_u32  (unsigned 32-bit wrap)
    ROM index         = phase_u32 >> 24   (upper 8 bits, 0-255)
    Rotation: I_out = (I * cos + Q * sin) >> 15  (Python floor = Verilog [30:15])
              Q_out = (Q * cos - I * sin) >> 15
    """
    out = []
    for n, (I_in, Q_in) in enumerate(iq_frac):
        phase_u32 = (n * step_word_u32) & 0xFFFFFFFF
        idx = (phase_u32 >> 24) & 0xFF
        cos_s, sin_s = nco_rom(idx)

        full_real = I_in * cos_s + Q_in * sin_s
        full_imag = Q_in * cos_s - I_in * sin_s

        # Replicate Verilog [30:15] bit-select on 33-bit signed value.
        # For signal amplitudes << 32767, this is identical to Python >> 15.
        I_out = full_real >> 15
        Q_out = full_imag >> 15

        # Clamp to signed 16-bit (saturating arithmetic)
        I_out = max(-32768, min(32767, I_out))
        Q_out = max(-32768, min(32767, Q_out))

        out.append((I_out, Q_out))
    return out


# ---------------------------------------------------------------------------
# File loaders
# ---------------------------------------------------------------------------

def load_status(path):
    status = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if '=' in line:
                k, v = line.split('=', 1)
                status[k.strip()] = v.strip()
    return status


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
# Main compare
# ---------------------------------------------------------------------------

def main():
    base = os.path.join(os.path.dirname(__file__), '..', 'sim_out', 'session_C_p3_14c')

    status_path   = os.path.join(base, 'rtl_status.txt')
    m_axis_path   = os.path.join(base, 'rtl_m_axis_iq.txt')
    frac_path     = os.path.join(base, 'rtl_frac_iq.txt')

    # Check files exist
    for p in [status_path, m_axis_path, frac_path]:
        if not os.path.exists(p):
            print(f"ERROR: missing file: {p}")
            print("OFFICIAL_GATE: FAIL  (missing simulation output files)")
            sys.exit(1)

    status     = load_status(status_path)
    m_axis_iq  = load_iq(m_axis_path)
    frac_iq    = load_iq(frac_path)

    fail_count = 0
    frame_len  = int(status.get('FRAME_LEN', 576))

    # -----------------------------------------------------------------------
    # Stage 1: Structural checks
    # -----------------------------------------------------------------------
    print("--- Stage 1: Structural checks ---")

    int_cfo_applied = int(status.get('INT_CFO_APPLIED', 0))
    output_count    = int(status.get('OUTPUT_COUNT', 0))
    tlast_count     = int(status.get('TLAST_COUNT', 0))
    m_captured      = int(status.get('M_AXIS_CAPTURED', 0))
    frac_captured   = int(status.get('FRAC_CAPTURED', 0))
    first_tlast_idx = int(status.get('FIRST_TLAST_IDX', -1))

    step_word_hex = status.get('INT_CFO_STEP_WORD', '0x00000000')
    step_word_u32 = int(step_word_hex, 16) & 0xFFFFFFFF
    step_word_s32 = step_word_u32 if step_word_u32 < 0x80000000 else step_word_u32 - 0x100000000
    int_cfo_index = int(status.get('INT_CFO_INDEX', 255))

    print(f"  INT_CFO_STEP_WORD = 0x{step_word_u32:08X} ({step_word_s32} decimal)")
    print(f"  INT_CFO_INDEX     = {int_cfo_index}  (255 = zero-CFO peak)")
    print(f"  INT_CFO_APPLIED   = {int_cfo_applied}")
    print(f"  OUTPUT_COUNT      = {output_count}")
    print(f"  TLAST_COUNT       = {tlast_count}")
    print(f"  M_AXIS_CAPTURED   = {m_captured}")
    print(f"  FRAC_CAPTURED     = {frac_captured}")
    print(f"  FIRST_TLAST_IDX   = {first_tlast_idx}")

    if int_cfo_applied != 1:
        print("FAIL [1a]: INT_CFO_APPLIED != 1 (replay did not complete)")
        fail_count += 1
    else:
        print("PASS [1a]: INT_CFO_APPLIED=1")

    if output_count != frame_len:
        print(f"FAIL [1b]: OUTPUT_COUNT={output_count} expected {frame_len}")
        fail_count += 1
    else:
        print(f"PASS [1b]: OUTPUT_COUNT={output_count}")

    if tlast_count < 1:
        print(f"FAIL [1c]: TLAST_COUNT={tlast_count} expected >= 1")
        fail_count += 1
    else:
        print(f"PASS [1c]: TLAST_COUNT={tlast_count}")

    if frac_captured != frame_len:
        print(f"FAIL [1d]: FRAC_CAPTURED={frac_captured} expected {frame_len}")
        fail_count += 1
    else:
        print(f"PASS [1d]: FRAC_CAPTURED={frac_captured}")

    # -----------------------------------------------------------------------
    # Stage 2: Length / TLAST position
    # -----------------------------------------------------------------------
    print("\n--- Stage 2: Length and TLAST ---")

    if len(m_axis_iq) != frame_len:
        print(f"FAIL [2a]: M_AXIS file has {len(m_axis_iq)} lines, expected {frame_len}")
        fail_count += 1
    else:
        print(f"PASS [2a]: M_AXIS file length = {len(m_axis_iq)}")

    if first_tlast_idx != frame_len - 1:
        print(f"FAIL [2b]: TLAST at idx={first_tlast_idx}, expected {frame_len - 1}")
        fail_count += 1
    else:
        print(f"PASS [2b]: TLAST at idx={first_tlast_idx} (FRAME_LEN-1)")

    if len(frac_iq) != frame_len:
        print(f"FAIL [2c]: frac file has {len(frac_iq)} lines, expected {frame_len}")
        fail_count += 1
    else:
        print(f"PASS [2c]: frac file length = {len(frac_iq)}")

    # -----------------------------------------------------------------------
    # Stage 3: IQ compare — Python reference vs RTL M_AXIS
    # -----------------------------------------------------------------------
    print("\n--- Stage 3: IQ sample compare ---")

    # Sign-convention doc:
    #   step_word = (-meyr_int_cfo) << 24
    #   NCO phase at sample n: (n * step_word) mod 2^32
    #   ROM index: upper 8 bits of phase
    #   Rotation: r_out = r_in * exp(-j*theta)
    #     I_out = (I_in*cos + Q_in*sin) >> 15
    #     Q_out = (Q_in*cos - I_in*sin) >> 15
    #
    # For step_word=0: cos=32767, sin=0 for all n.
    #   I_out = I_in * 32767 // 32768   (exact floor, tolerance=0)
    #   Q_out = Q_in * 32767 // 32768   (exact floor, tolerance=0)
    #
    # For non-zero step_word: use analytical ROM ± 1 LSB tolerance.

    if len(frac_iq) < frame_len or len(m_axis_iq) < frame_len:
        print("SKIP [3]: insufficient data for IQ compare (Stage 1/2 failures)")
        fail_count += 1
    else:
        ref_iq = python_nco_rotate(frac_iq[:frame_len], step_word_u32)

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
                    print(f"  MISMATCH n={n}: RTL({I_rtl},{Q_rtl}) REF({I_ref},{Q_ref}) "
                          f"err=({err_i},{err_q})")

        print(f"  Tolerance:    {tolerance} LSB (step_word={'0 (identity)' if step_word_u32 == 0 else hex(step_word_u32)})")
        print(f"  Max I error:  {max_err_i}  at n={worst_idx}")
        print(f"  Max Q error:  {max_err_q}")
        print(f"  Mismatches:   {mismatch}/{frame_len}")

        if mismatch == 0:
            print(f"PASS [3a]: All {frame_len} IQ samples within tolerance")
        else:
            print(f"FAIL [3a]: {mismatch} IQ mismatches (tolerance={tolerance})")
            fail_count += 1

        # Extra: print first few samples for inspection
        print(f"\n  Sample preview (first 4):")
        for n in range(min(4, frame_len)):
            I_ref, Q_ref = ref_iq[n]
            I_rtl, Q_rtl = m_axis_iq[n]
            I_frac, Q_frac = frac_iq[n]
            print(f"    n={n}: frac=({I_frac:6d},{Q_frac:6d}) "
                  f"ref=({I_ref:6d},{Q_ref:6d}) "
                  f"rtl=({I_rtl:6d},{Q_rtl:6d})")

    # -----------------------------------------------------------------------
    # Gate result
    # -----------------------------------------------------------------------
    print()
    if fail_count == 0:
        print("==============================================")
        print("OFFICIAL_GATE: PASS")
        print("  All Stage 1-3 checks passed.")
        print("  Replay buffer + integer CFO correction")
        print("  numerically verified sample-by-sample.")
        print("==============================================")
    else:
        print("==============================================")
        print(f"OFFICIAL_GATE: FAIL  ({fail_count} failure(s))")
        print("==============================================")
        sys.exit(1)


if __name__ == '__main__':
    main()
