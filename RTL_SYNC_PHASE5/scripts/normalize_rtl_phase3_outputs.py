#!/usr/bin/env python3
"""
normalize_rtl_phase3_outputs.py — Session D / P3-15A
Convert RTL observable dump text files to normalized JSON (same schema as
c_reference_observables.json).

Inputs:
  sim_out/session_D_p3_15a/rtl_observables.txt   — key VALUE per line
  sim_out/session_D_p3_15a/rtl_m_axis_meta.txt   — key=value per line
  sim_out/session_D_p3_15a/rtl_m_axis_iq.txt     — "I Q" per line (optional)

Output:
  sim_out/session_D_p3_15a/rtl_observables.json

Usage:
  python3 scripts/normalize_rtl_phase3_outputs.py [--sim-dir sim_out/session_D_p3_15a]
"""

import argparse
import json
import math
import os
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT       = os.path.dirname(SCRIPT_DIR)

Q15_MAX = 32768.0


# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------
def parse_kv_space(path):
    """Parse 'KEY VALUE' space-separated file (like golden_values.txt format)."""
    kv = {}
    if not os.path.isfile(path):
        return kv
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split(None, 1)
            if len(parts) == 2:
                kv[parts[0]] = parts[1]
    return kv


def parse_kv_eq(path):
    """Parse 'KEY=VALUE' format (like rtl_m_axis_meta.txt)."""
    kv = {}
    if not os.path.isfile(path):
        return kv
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                k, _, v = line.partition("=")
                kv[k.strip()] = v.strip()
    return kv


def load_iq_file(path):
    """Load IQ pairs from 'I Q' per-line file. Returns list of (I,Q) tuples."""
    pairs = []
    if not os.path.isfile(path):
        return pairs
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) >= 2:
                try:
                    pairs.append((int(parts[0]), int(parts[1])))
                except ValueError:
                    pass
    return pairs


def get_int(d, key, fallback=None):
    if key not in d:
        return fallback
    try:
        val = d[key]
        if val.startswith("0x") or val.startswith("0X"):
            return int(val, 16)
        return int(val)
    except (ValueError, AttributeError):
        return fallback


def get_float(d, key, fallback=None):
    if key not in d:
        return fallback
    try:
        return float(d[key])
    except (ValueError, AttributeError):
        return fallback


def frac_word_to_offset(word_q15):
    """Convert Q1.15 signed integer to fractional CFO float offset.
    RTL convention: word = +offset * 2 * 32768  (same sign as C).
    """
    return float(word_q15) / (2.0 * Q15_MAX)


def nco_word_to_bins(nco_word_signed):
    """Convert NCO step word (32-bit signed) to integer CFO subcarrier bins.
    step_word = (-int_cfo_bins) << 24  (from phase3_sync_top.v)
    inv: int_cfo_bins = -(step_word >> 24)  (arithmetic right shift)
    """
    if nco_word_signed is None:
        return None
    return -(nco_word_signed >> 24)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Normalize RTL Phase3 output files to JSON")
    ap.add_argument("--sim-dir", default=os.path.join(ROOT, "sim_out", "session_D_p3_15a"),
                    help="Directory containing RTL output txt files")
    ap.add_argument("--out", default=None,
                    help="Output JSON path (default: <sim-dir>/rtl_observables.json)")
    ap.add_argument("--iq-file", default=None,
                    help="Path to rtl_m_axis_iq.txt (relative to project root)")
    ap.add_argument("--verbose", "-v", action="store_true")
    args = ap.parse_args()

    sim_dir = args.sim_dir
    obs_txt  = os.path.join(sim_dir, "rtl_observables.txt")
    meta_txt = os.path.join(sim_dir, "rtl_m_axis_meta.txt")
    iq_txt   = args.iq_file or os.path.join(sim_dir, "rtl_m_axis_iq.txt")
    out_json = args.out or os.path.join(sim_dir, "rtl_observables.json")

    print("=" * 64)
    print("Session D / P3-15A — RTL Output Normalization")
    print("=" * 64)

    # -----------------------------------------------------------------------
    # Load inputs
    # -----------------------------------------------------------------------
    print(f"\n[1] Loading rtl_observables.txt: {obs_txt}")
    obs = parse_kv_space(obs_txt)
    if not obs:
        print(f"  [warn] File not found or empty: {obs_txt}")
        print(f"  Run RTL simulation first:")
        print(f"    ./scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh --sim iverilog")
    else:
        print(f"  Keys: {list(obs.keys())}")

    print(f"\n[2] Loading rtl_m_axis_meta.txt: {meta_txt}")
    meta = parse_kv_eq(meta_txt)
    if not meta:
        print(f"  [info] Not found — M_AXIS metadata unavailable")
    else:
        print(f"  Keys: {list(meta.keys())}")

    print(f"\n[3] Loading rtl_m_axis_iq.txt: {iq_txt}")
    iq_pairs = load_iq_file(iq_txt)
    m_axis_iq_available = len(iq_pairs) > 0
    if m_axis_iq_available:
        print(f"  Loaded {len(iq_pairs)} IQ pairs")
    else:
        print(f"  [info] Not found or empty — M_AXIS IQ unavailable")

    # -----------------------------------------------------------------------
    # Extract scalar observables
    # -----------------------------------------------------------------------
    frame_found_raw  = get_int(obs, "FRAME_FOUND",       0)
    frame_index      = get_int(obs, "FRAME_INDEX",        None)
    peak_lag         = get_int(obs, "PEAK_LAG",           None)
    slot_start       = get_int(obs, "SLOT_START_INDEX",   None)
    frac_valid_raw   = get_int(obs, "FRAC_CFO_VALID",     0)
    frac_word        = get_int(obs, "FRAC_CFO_WORD",      None)
    int_valid_raw    = get_int(obs, "INT_CFO_VALID",      0)
    int_word_probe   = get_int(obs, "INT_CFO_WORD_PROBE", None)
    meyr_peak        = get_int(obs, "MEYR_PEAK_INDEX",    None)
    done_cycle       = get_int(obs, "DONE_CYCLE",         None)
    int_cfo_applied  = get_int(obs, "INT_CFO_APPLIED",    None)
    output_count     = get_int(obs, "OUTPUT_COUNT",       None)
    tlast_count      = get_int(obs, "TLAST_COUNT",        None)
    m_axis_captured  = get_int(obs, "M_AXIS_CAPTURED",    None)
    first_tlast_idx  = get_int(obs, "FIRST_TLAST_IDX",    None)
    frame_len        = get_int(obs, "FRAME_LEN",          576)

    # AXI-Lite register reads (prefer these for int_cfo_applied if probe missing)
    int_cfo_word_axi  = get_int(obs, "INT_CFO_WORD_AXI",  None)
    int_cfo_index_axi = get_int(obs, "INT_CFO_INDEX_AXI", None)

    # From meta file (overrides obs for M_AXIS fields if present)
    if meta:
        if output_count  is None: output_count  = get_int(meta, "OUTPUT_COUNT", None)
        if tlast_count   is None: tlast_count   = get_int(meta, "TLAST_COUNT", None)
        if first_tlast_idx is None: first_tlast_idx = get_int(meta, "FIRST_TLAST_IDX", None)
        if m_axis_captured is None: m_axis_captured = get_int(meta, "M_AXIS_CAPTURED", None)
        if int_cfo_applied is None: int_cfo_applied = get_int(meta, "INT_CFO_APPLIED", None)

    # Derived values
    frame_found      = bool(frame_found_raw)
    frac_cfo_valid   = bool(frac_valid_raw)
    int_cfo_valid    = bool(int_valid_raw)

    frac_offset      = frac_word_to_offset(frac_word) if frac_word is not None else None

    # Prefer probe value for int_cfo_word; also compute bins from it
    int_cfo_word_nco = int_word_probe
    int_cfo_est_bins = nco_word_to_bins(int_cfo_word_nco) if int_cfo_word_nco is not None else None

    # M_AXIS availability
    m_axis_available = (output_count is not None and output_count > 0 and
                        m_axis_iq_available)

    # -----------------------------------------------------------------------
    # Build JSON
    # -----------------------------------------------------------------------
    out = {
        "_meta": {
            "session": "D / P3-15A",
            "source": "RTL simulation (iverilog/xsim)",
            "generated_by": "scripts/normalize_rtl_phase3_outputs.py",
            "obs_file": os.path.relpath(obs_txt, ROOT) if obs else None,
            "meta_file": os.path.relpath(meta_txt, ROOT) if meta else None,
            "iq_file_used": os.path.relpath(iq_txt, ROOT) if m_axis_iq_available else None,
        },
        "frame_found":      frame_found,
        "frame_index":      frame_index,
        "peak_lag":         peak_lag,
        "slot_start_index": slot_start,
        "frac_cfo_valid":   frac_cfo_valid,
        "frac_cfo_offset_float": round(frac_offset, 8) if frac_offset is not None else None,
        "frac_cfo_word":    frac_word,
        "int_cfo_valid":    int_cfo_valid,
        "int_cfo_index":    meyr_peak,
        "int_cfo_est_bins": int_cfo_est_bins,
        "int_cfo_word_nco": int_cfo_word_nco,
        "int_cfo_word_axi": int_cfo_word_axi,
        "int_cfo_index_axi": int_cfo_index_axi,
        "int_cfo_applied":  int_cfo_applied,
        "done_cycle":       done_cycle,
        "m_axis": {
            "available":      m_axis_available,
            "length":         output_count,
            "tlast_count":    tlast_count,
            "tlast_index":    first_tlast_idx,
            "captured":       m_axis_captured,
            "frame_len":      frame_len,
            "iq_file":        os.path.relpath(iq_txt, ROOT) if m_axis_iq_available else None,
            "iq_pairs":       len(iq_pairs) if m_axis_iq_available else 0
        }
    }

    # -----------------------------------------------------------------------
    # Write JSON
    # -----------------------------------------------------------------------
    os.makedirs(os.path.dirname(out_json), exist_ok=True)
    with open(out_json, "w") as f:
        json.dump(out, f, indent=2)
    print(f"\n[4] Written: {out_json}")

    # -----------------------------------------------------------------------
    # Summary
    # -----------------------------------------------------------------------
    print("\n[5] Observable summary:")
    fields = [
        ("frame_found",      out["frame_found"]),
        ("frame_index",      out["frame_index"]),
        ("peak_lag",         out["peak_lag"]),
        ("slot_start_index", out["slot_start_index"]),
        ("frac_cfo_valid",   out["frac_cfo_valid"]),
        ("frac_cfo_word",    out["frac_cfo_word"]),
        ("int_cfo_valid",    out["int_cfo_valid"]),
        ("int_cfo_index",    out["int_cfo_index"]),
        ("int_cfo_est_bins", out["int_cfo_est_bins"]),
        ("int_cfo_applied",  out["int_cfo_applied"]),
        ("m_axis.available", out["m_axis"]["available"]),
        ("m_axis.length",    out["m_axis"]["length"]),
        ("m_axis.tlast_idx", out["m_axis"]["tlast_index"]),
    ]
    n_missing = 0
    for name, val in fields:
        status = "OK" if val is not None else "MISSING"
        if val is None:
            n_missing += 1
        print(f"  {status:7s}  {name} = {val}")

    print(f"\n  Missing fields: {n_missing}")

    if n_missing == 0:
        print("\nRTL_NORMALIZE: PASS (all fields available)")
        return 0
    else:
        print(f"\nRTL_NORMALIZE: PARTIAL ({n_missing} fields unavailable)")
        return 1


if __name__ == "__main__":
    sys.exit(main())
