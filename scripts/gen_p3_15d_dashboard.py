#!/usr/bin/env python3
"""
gen_p3_15d_dashboard.py — P3-15D Regression Dashboard Generator

Reads per-case JSON results from reports/session_D4_p3_15d/per_case/
and writes docs/session_D4_randomized_equivalence_dashboard.md

Usage:
  python3 scripts/gen_p3_15d_dashboard.py \\
      --per-case-dir  reports/session_D4_p3_15d/per_case \\
      --n-cases       100 \\
      --out           docs/session_D4_randomized_equivalence_dashboard.md
"""

import argparse
import datetime
import json
import os
import sys


def ascii_hist_float(values, edges, bar_width=50):
    counts = [0] * (len(edges) - 1)
    for v in values:
        placed = False
        for i in range(len(edges) - 1):
            if edges[i] <= v < edges[i + 1]:
                counts[i] += 1
                placed = True
                break
        if not placed and values and v >= edges[-1]:
            counts[-1] += 1
    max_c  = max(counts) if counts else 1
    lines  = []
    for i, c in enumerate(counts):
        bar  = "█" * int(bar_width * c / max_c) if max_c > 0 else ""
        lo, hi = edges[i], edges[i + 1]
        lines.append(f"  [{lo:5.2f},{hi:5.2f}): {bar:<{bar_width}} {c}")
    return "\n".join(lines)


def ascii_hist_int(values, edges, bar_width=40):
    counts = [0] * (len(edges) - 1)
    for v in values:
        for i in range(len(edges) - 1):
            if edges[i] <= v < edges[i + 1]:
                counts[i] += 1
                break
    max_c = max(counts) if counts else 1
    lines = []
    for i, c in enumerate(counts):
        bar  = "█" * int(bar_width * c / max_c) if max_c > 0 else ""
        lo, hi = edges[i], edges[i + 1]
        lines.append(f"  [{lo:2d},{hi:2d}): {bar:<{bar_width}} {c}")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--per-case-dir", required=True)
    parser.add_argument("--n-cases",      type=int, required=True)
    parser.add_argument("--out",          required=True)
    args = parser.parse_args()

    results = []
    for i in range(args.n_cases):
        case_id = f"case_{i:03d}"
        jpath   = os.path.join(args.per_case_dir, f"{case_id}.json")
        if os.path.exists(jpath):
            with open(jpath) as f:
                results.append(json.load(f))
        else:
            results.append({
                "case_id"          : case_id,
                "passed"           : False,
                "failure_clusters" : ["no_result"],
                "d2"               : {},
                "d3"               : {},
            })

    n_cases  = args.n_cases
    n_pass   = sum(1 for r in results if r.get("passed"))
    n_fail   = n_cases - n_pass
    pass_pct = 100.0 * n_pass / n_cases if n_cases else 0.0

    # IQ error aggregates
    ei_all  = [r["d3"].get("max_err_i", 0) for r in results
               if r.get("d3") and r["d3"].get("max_err_i", -1) >= 0]
    eq_all  = [r["d3"].get("max_err_q", 0) for r in results
               if r.get("d3") and r["d3"].get("max_err_q", -1) >= 0]
    worst_ei = max(ei_all) if ei_all else 0
    worst_eq = max(eq_all) if eq_all else 0

    # Failure clustering
    cluster_counts = {}
    for r in results:
        for c in r.get("failure_clusters", []):
            cluster_counts[c] = cluster_counts.get(c, 0) + 1

    # D2 metric distributions (all cases)
    frac_errs = [r["d2"].get("frac_cfo_rel_err", 0) * 100
                 for r in results if r.get("d2") and "frac_cfo_rel_err" in r["d2"]]
    fs_errs   = [r["d2"].get("frame_start_err", 0)
                 for r in results if r.get("d2") and "frame_start_err" in r["d2"]]
    ss_errs   = [r["d2"].get("slot_start_err", 0)
                 for r in results if r.get("d2") and "slot_start_err" in r["d2"]]

    # Parameter coverage
    params    = [r.get("params", {}) for r in results if "params" in r]
    k_int_vals = [p.get("k_int",      0)   for p in params]
    eps_vals   = [p.get("eps_frac",   0.0) for p in params]
    amp_vals   = [p.get("amplitude",  0.0) for p in params]
    snr_vals   = [p.get("snr_db",     0.0) for p in params]
    pre_vals   = [p.get("pre_zeros",  0)   for p in params]

    k_int_dist = {}
    for k in k_int_vals:
        k_int_dist[k] = k_int_dist.get(k, 0) + 1

    date_str = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    lines = []
    lines += [
        "# Session D4 — P3-15D Randomized Equivalence Regression Dashboard",
        "",
        f"Generated: {date_str}",
        "",
        "---",
        "",
        "## Summary",
        "",
        "| Metric | Value |",
        "|--------|-------|",
        f"| Total cases | {n_cases} |",
        f"| **Pass** | **{n_pass}/{n_cases}  ({pass_pct:.1f}%)** |",
        f"| Fail | {n_fail}/{n_cases} |",
        f"| Worst-case I error | {worst_ei} LSB |",
        f"| Worst-case Q error | {worst_eq} LSB |",
        "",
        "---",
        "",
        "## Gate",
        "",
        "```text",
        "RANDOM_EQUIV_GATE: PASS" if n_fail == 0
            else f"RANDOM_EQUIV_GATE: FAIL  ({n_fail} case(s) failed)",
        "```",
    ]

    if n_fail > 0:
        lines += [
            "",
            "### Failed Cases",
            "",
        ]
        for r in results:
            if not r.get("passed"):
                cid  = r.get("case_id", "?")
                clus = [c for c in r.get("failure_clusters", []) if not c.startswith("info_")]
                info = [c for c in r.get("failure_clusters", []) if c.startswith("info_")]
                gate_str = ", ".join(clus) if clus else "unknown"
                info_str = f" | info: {', '.join(info)}" if info else ""
                lines.append(f"- `{cid}`: {gate_str}{info_str}")

    lines += [
        "",
        "---",
        "",
        "## D4-2 Metadata Error Distributions",
        "",
        "### Fractional CFO relative error (%)",
        "",
        "```text",
    ]
    if frac_errs:
        lines.append(ascii_hist_float(frac_errs, [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]))
        lines += [
            "```",
            "",
            f"N={len(frac_errs)}  Max={max(frac_errs):.4f}%"
            f"  Mean={sum(frac_errs)/len(frac_errs):.4f}%",
        ]
    else:
        lines += ["```", "(no data)"]

    lines += [
        "",
        "### Slot start error (samples)",
        "",
        "```text",
    ]
    if ss_errs:
        lines.append(ascii_hist_int(ss_errs, [0, 1, 2, 3, 4, 5, 6]))
        lines += [
            "```",
            "",
            f"N={len(ss_errs)}  Max={max(ss_errs)}  Mean={sum(ss_errs)/len(ss_errs):.2f}",
        ]
    else:
        lines += ["```", "(no data)"]

    lines += [
        "",
        "---",
        "",
        "## D4-4 Failure Histogram (gate-controlling only)",
        "",
    ]
    gate_clusters = {k: v for k, v in cluster_counts.items() if not k.startswith("info_")}
    if gate_clusters:
        lines += [
            "| Cluster | Count |",
            "|---------|-------|",
        ]
        for c, n in sorted(gate_clusters.items(), key=lambda x: -x[1]):
            lines.append(f"| `{c}` | {n} |")
    else:
        lines.append("No gate failures.")

    info_clusters = {k: v for k, v in cluster_counts.items() if k.startswith("info_")}
    if info_clusters:
        lines += [
            "",
            "### Informational warnings (non-gate, expected from pipeline limitations)",
            "",
            "| Cluster | Count |",
            "|---------|-------|",
        ]
        for c, n in sorted(info_clusters.items(), key=lambda x: -x[1]):
            lines.append(f"| `{c}` | {n} |")

    lines += [
        "",
        "---",
        "",
        "## Parameter Coverage",
        "",
        "| Parameter | Range | N |",
        "|-----------|-------|---|",
    ]

    def rng_f(vals):
        return f"[{min(vals):.2f}, {max(vals):.2f}]" if vals else "N/A"

    def rng_i(vals):
        return f"[{min(vals)}, {max(vals)}]" if vals else "N/A"

    lines += [
        f"| pre_zeros | {rng_i(pre_vals)} | {len(pre_vals)} |",
        f"| eps_frac  | {rng_f(eps_vals)} | {len(eps_vals)} |",
        f"| k_int     | {rng_i(k_int_vals)} | {len(k_int_vals)} |",
        f"| amplitude | {rng_f(amp_vals)} | {len(amp_vals)} |",
        f"| snr_db    | {rng_f(snr_vals)} | {len(snr_vals)} |",
    ]

    if k_int_dist:
        lines += [
            "",
            "### k\\_int distribution",
            "",
            "| k_int | Count |",
            "|-------|-------|",
        ]
        for k in sorted(k_int_dist.keys()):
            lines.append(f"| {k:+d} | {k_int_dist[k]} |")

    lines += [
        "",
        "---",
        "",
        "## Methodology",
        "",
        "- **Gate checks** (control CASE\\_EQUIV\\_GATE / RANDOM\\_EQUIV\\_GATE):",
        "  - `slot_start` ±2: synchronisation timing output vs C golden",
        "  - `frac_cfo`  ≤2%: fractional CFO estimate vs C golden",
        "  - D4-3 IQ ≤1 LSB: M\\_AXIS output vs Python NCO model (self-consistency)",
        "- **Informational only** (printed, not gate-controlling):",
        "  - `frame_start` ±2, `peak_lag` ±3: intermediate frame detection fields",
        "  - `meyr_peak`, `int_cfo_bins`: `fft256_dual_symbol_frontend` cannot",
        "    reliably recover integer CFO with noisy input (phase cancels in",
        "    cross-product — documented limitation L-01)",
        "- **Noise model**: Gaussian noise added to OFDM frame region only",
        "  (guard zeros kept clean so frame detector agrees between float32 and Q15)",
        "- **Simulator**: iverilog (sanity gate); xsim pending for official gate",
        "",
        f"*Regression logs: `logs/session_D4_p3_15d_*.log`*",
        f"*Per-case JSON:  `reports/session_D4_p3_15d/per_case/`*",
    ]

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"[dashboard] Written: {args.out}")
    print(f"[dashboard] {n_pass}/{n_cases} PASS  ({pass_pct:.1f}%)")


if __name__ == "__main__":
    main()
