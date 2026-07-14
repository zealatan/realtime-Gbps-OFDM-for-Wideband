#!/usr/bin/env python3
"""
gen_c_m_axis_iq_golden.py — Session D / P3-15B

Generate c_m_axis_iq_golden.txt by applying a software NCO model to the
frac-corrected IQ captured from the RTL replay buffer input.

Inputs:
  sim_out/session_D_p3_15a/rtl_frac_iq.txt    — frac IQ from dbg_frac_m bus
  sim_out/session_D_p3_15a/rtl_m_axis_meta.txt — INT_CFO_STEP_WORD

Outputs:
  golden/session_D_p3_15a/c_m_axis_iq_golden.txt  — software NCO output (I Q per line)

Side-effects:
  Updates golden/session_D_p3_15a/c_reference_observables.json:
    m_axis.available = true
    m_axis.length    = <N>
    m_axis.tlast_index = <N-1>
    m_axis.iq_file   = "golden/session_D_p3_15a/c_m_axis_iq_golden.txt"

NCO model (identical to Session C / P3-14C python_nco_rotate):
  step_word_u32 = INT_CFO_STEP_WORD & 0xFFFFFFFF
  phase[n]      = (n * step_word_u32) & 0xFFFFFFFF   (32-bit unsigned wrap)
  idx[n]        = phase[n] >> 24                      (upper 8 bits, 0-255)
  cos, sin      = round(32767 * cos/sin(2*pi*idx/256)) clamped to [-32768, 32767]
  I_out[n]      = (I[n]*cos + Q[n]*sin) >> 15        (floor = Verilog [30:15])
  Q_out[n]      = (Q[n]*cos - I[n]*sin) >> 15
  Output clamped to signed 16-bit.

Exit codes:
  0 — success
  1 — error (missing input file, bad format)
"""

import json
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT       = os.path.dirname(SCRIPT_DIR)

FRAC_IQ_FILE   = os.path.join(ROOT, "sim_out",  "session_D_p3_15a", "rtl_frac_iq.txt")
META_FILE      = os.path.join(ROOT, "sim_out",  "session_D_p3_15a", "rtl_m_axis_meta.txt")
OBS_FILE       = os.path.join(ROOT, "sim_out",  "session_D_p3_15a", "rtl_observables.txt")
C_IQ_OUT       = os.path.join(ROOT, "golden",   "session_D_p3_15a", "c_m_axis_iq_golden.txt")
C_REF_JSON     = os.path.join(ROOT, "golden",   "session_D_p3_15a", "c_reference_observables.json")
C_IQ_REL       = "golden/session_D_p3_15a/c_m_axis_iq_golden.txt"


# ---------------------------------------------------------------------------
# NCO ROM model — matches nco_phase_gen.v formula exactly
# ---------------------------------------------------------------------------
def nco_rom(idx):
    idx = int(idx) & 0xFF
    theta = 2.0 * math.pi * idx / 256.0
    cos_v = max(-32768, min(32767, round(32767.0 * math.cos(theta))))
    sin_v = max(-32768, min(32767, round(32767.0 * math.sin(theta))))
    return cos_v, sin_v


def python_nco_rotate(iq_frac, step_word_u32):
    """Apply integer NCO + rotator matching RTL arithmetic."""
    out = []
    for n, (I_in, Q_in) in enumerate(iq_frac):
        phase_u32 = (n * step_word_u32) & 0xFFFFFFFF
        idx = (phase_u32 >> 24) & 0xFF
        cos_s, sin_s = nco_rom(idx)

        full_real = I_in * cos_s + Q_in * sin_s
        full_imag = Q_in * cos_s - I_in * sin_s

        # Verilog [30:15] bit-select = Python >> 15 for amplitudes << 32767
        I_out = full_real >> 15
        Q_out = full_imag >> 15

        # Saturating 16-bit clamp
        I_out = max(-32768, min(32767, I_out))
        Q_out = max(-32768, min(32767, Q_out))
        out.append((I_out, Q_out))
    return out


# ---------------------------------------------------------------------------
# File helpers
# ---------------------------------------------------------------------------
def load_iq(path):
    pairs = []
    with open(path) as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                try:
                    pairs.append((int(parts[0]), int(parts[1])))
                except ValueError:
                    pass
    return pairs


def load_kv(path):
    """Load KEY=VALUE or KEY VALUE pairs; '#' lines ignored."""
    d = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                k, v = line.split('=', 1)
                d[k.strip()] = v.strip()
            elif ' ' in line:
                parts = line.split(None, 1)
                if len(parts) == 2:
                    d[parts[0]] = parts[1]
    return d


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("=" * 68)
    print("Session D / P3-15B — Generate C M_AXIS IQ Golden")
    print("=" * 68)

    # -----------------------------------------------------------------------
    # 1. Load frac IQ
    # -----------------------------------------------------------------------
    print(f"\n[1] Loading frac IQ: {FRAC_IQ_FILE}")
    if not os.path.isfile(FRAC_IQ_FILE):
        print(f"ERROR: {FRAC_IQ_FILE} not found.")
        print("  Re-run simulation: ./scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh")
        sys.exit(1)

    frac_iq = load_iq(FRAC_IQ_FILE)
    print(f"  Loaded {len(frac_iq)} frac IQ pairs")

    if len(frac_iq) == 0:
        print("ERROR: frac IQ file is empty.")
        sys.exit(1)

    # -----------------------------------------------------------------------
    # 2. Load step_word
    # -----------------------------------------------------------------------
    print(f"\n[2] Loading step_word from meta/observables")

    step_word_u32 = None

    # Try meta file first (has INT_CFO_STEP_WORD=0x...)
    if os.path.isfile(META_FILE):
        meta = load_kv(META_FILE)
        sw_str = meta.get("INT_CFO_STEP_WORD")
        if sw_str:
            try:
                step_word_u32 = int(sw_str, 16) & 0xFFFFFFFF
                print(f"  INT_CFO_STEP_WORD from meta: {sw_str} = {step_word_u32} (u32)")
            except ValueError:
                pass

    # Fallback to observables.txt (INT_CFO_WORD_AXI is signed decimal)
    if step_word_u32 is None and os.path.isfile(OBS_FILE):
        obs = load_kv(OBS_FILE)
        sw_str = obs.get("INT_CFO_WORD_AXI")
        if sw_str:
            try:
                signed_val = int(sw_str)
                step_word_u32 = signed_val & 0xFFFFFFFF
                print(f"  INT_CFO_WORD_AXI from observables: {sw_str} → u32=0x{step_word_u32:08X}")
            except ValueError:
                pass

    if step_word_u32 is None:
        print("ERROR: Could not determine step_word from meta or observables.")
        sys.exit(1)

    step_word_s32 = step_word_u32 if step_word_u32 < 0x80000000 else step_word_u32 - 0x100000000
    int_cfo_idx = (-step_word_s32) >> 24 if step_word_s32 <= 0 else 256 - (step_word_u32 >> 24)
    print(f"  step_word: 0x{step_word_u32:08X}  ({step_word_s32} signed)")
    print(f"  NCO ROM idx[0]: {(step_word_u32 >> 24) & 0xFF}")

    # -----------------------------------------------------------------------
    # 3. Apply NCO model
    # -----------------------------------------------------------------------
    print(f"\n[3] Applying software NCO model to {len(frac_iq)} samples...")
    c_iq = python_nco_rotate(frac_iq, step_word_u32)
    print(f"  Generated {len(c_iq)} output IQ pairs")

    # -----------------------------------------------------------------------
    # 4. Write c_m_axis_iq_golden.txt
    # -----------------------------------------------------------------------
    os.makedirs(os.path.dirname(C_IQ_OUT), exist_ok=True)
    print(f"\n[4] Writing: {C_IQ_OUT}")
    with open(C_IQ_OUT, 'w') as f:
        for I_out, Q_out in c_iq:
            f.write(f"{I_out} {Q_out}\n")
    print(f"  Written {len(c_iq)} IQ pairs")

    # -----------------------------------------------------------------------
    # 5. Update c_reference_observables.json
    # -----------------------------------------------------------------------
    print(f"\n[5] Updating C reference JSON: {C_REF_JSON}")
    if not os.path.isfile(C_REF_JSON):
        print(f"  [warn] JSON not found — creating minimal skeleton")
        c_ref = {}
    else:
        with open(C_REF_JSON) as f:
            c_ref = json.load(f)

    frame_len = len(c_iq)
    c_ref["m_axis"] = {
        "available":   True,
        "length":      frame_len,
        "tlast_index": frame_len - 1,
        "iq_file":     C_IQ_REL
    }

    with open(C_REF_JSON, 'w') as f:
        json.dump(c_ref, f, indent=2)
    print(f"  m_axis.available = true")
    print(f"  m_axis.length    = {frame_len}")
    print(f"  m_axis.tlast_index = {frame_len - 1}")
    print(f"  m_axis.iq_file   = {C_IQ_REL}")

    # -----------------------------------------------------------------------
    # 6. Preview
    # -----------------------------------------------------------------------
    print(f"\n[6] Preview (first 4 / last 2 samples):")
    for k in range(min(4, len(c_iq))):
        fi, fq = frac_iq[k]
        ci, cq = c_iq[k]
        print(f"  [{k:4d}] frac=({fi:6d},{fq:6d}) → nco=({ci:6d},{cq:6d})")
    if len(c_iq) > 4:
        for k in [len(c_iq)-2, len(c_iq)-1]:
            fi, fq = frac_iq[k]
            ci, cq = c_iq[k]
            print(f"  [{k:4d}] frac=({fi:6d},{fq:6d}) → nco=({ci:6d},{cq:6d})")

    print(f"\nC_GOLDEN_GEN: PASS")
    print(f"  Output: {C_IQ_OUT}")
    print(f"  Samples: {len(c_iq)}")


if __name__ == "__main__":
    main()
