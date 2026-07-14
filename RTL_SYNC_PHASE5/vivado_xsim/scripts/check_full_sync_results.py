#!/usr/bin/env python3
"""check_full_sync_results.py — XIP-004 FULL_SYNC_REAL_IP_GATE result checker.

Parses vivado_xsim/logs/xsim_full_sync_sim.log, extracts per-case PASS/FAIL
status, and writes:
  vivado_xsim/reports/xip004_full_sync_results.csv
  vivado_xsim/reports/xip004_full_sync_gate.txt
  vivado_xsim/reports/xip004_full_sync_gate.html

Usage: python3 check_full_sync_results.py  (from project root)
"""

import re
import sys
import os
from datetime import date

ROOT        = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SIM_LOG     = os.path.join(ROOT, "vivado_xsim", "logs", "xsim_full_sync_sim.log")
RPT_DIR     = os.path.join(ROOT, "vivado_xsim", "reports")
CSV_OUT     = os.path.join(RPT_DIR, "xip004_full_sync_results.csv")
GATE_TXT    = os.path.join(RPT_DIR, "xip004_full_sync_gate.txt")
GATE_HTML   = os.path.join(RPT_DIR, "xip004_full_sync_gate.html")

# Expected values
EXP_FRAME_IDX  = 41
EXP_PEAK_LAG   = 23
EXP_SLOT_START = 64

CASES = [
    ("k0",  0,  255),
    ("kp1", 1,  256),
    ("km1", -1, 254),
    ("kp2", 2,  257),
    ("km2", -2, 253),
    ("kp4", 4,  259),
    ("km4", -4, 251),
    ("kp8", 8,  263),
    ("km8", -8, 247),
]

def parse_sim_log(path):
    """Extract per-case results from simulation log."""
    results = []
    gate_line = None

    if not os.path.exists(path):
        print(f"[ERROR] Sim log not found: {path}")
        return results, "NOT_RUN"

    with open(path) as f:
        lines = f.readlines()

    for line in lines:
        # Match TB PASS/FAIL lines: "[TB] PASS  k0   frame=41  peak_lag=23  ..."
        m = re.match(
            r'\[TB\] (PASS|FAIL)\s+(\S+)\s+frame=(\d+)\s+peak_lag=(\d+)\s+slot=(\d+)\s+'
            r'frac=(-?\d+)\s+meyr_peak=(\d+)\s+int_cfo=(-?\d+)',
            line.strip()
        )
        if m:
            result = {
                "status":     m.group(1),
                "label":      m.group(2),
                "frame":      int(m.group(3)),
                "peak_lag":   int(m.group(4)),
                "slot":       int(m.group(5)),
                "frac_word":  int(m.group(6)),
                "meyr_peak":  int(m.group(7)),
                "int_cfo":    int(m.group(8)),
            }
            results.append(result)

        # Match gate line
        if "GATE:" in line and ("PASS_VIVADO_XSIM_REAL_IP" in line or "FAIL" in line):
            gate_line = line.strip()

    return results, gate_line

def write_csv(results, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    header = "label,status,frame_idx,peak_lag,slot_start,frac_cfo_word,meyr_peak,int_cfo\n"
    with open(path, "w") as f:
        f.write(header)
        for r in results:
            f.write(f"{r['label']},{r['status']},{r['frame']},{r['peak_lag']},"
                    f"{r['slot']},{r['frac_word']},{r['meyr_peak']},{r['int_cfo']}\n")
    print(f"  CSV: {path}")

def write_gate_txt(gate_line, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write((gate_line or "FULL_SYNC_GATE: NOT_RUN") + "\n")
    print(f"  Gate TXT: {path}")

def write_gate_html(results, gate_line, path):
    today = date.today().isoformat()
    is_pass = gate_line and "PASS_VIVADO_XSIM_REAL_IP" in gate_line
    gate_color  = "#27ae60" if is_pass else "#e74c3c"
    gate_status = "PASS_VIVADO_XSIM_REAL_IP" if is_pass else "FAIL"

    rows = ""
    for r in results:
        color = "#eaffea" if r["status"] == "PASS" else "#ffeaea"
        rows += (
            f'<tr style="background:{color}">'
            f'<td>{r["label"]}</td>'
            f'<td><b>{r["status"]}</b></td>'
            f'<td>{r["frame"]}</td>'
            f'<td>{r["peak_lag"]}</td>'
            f'<td>{r["slot"]}</td>'
            f'<td>{r["frac_word"]}</td>'
            f'<td>{r["meyr_peak"]}</td>'
            f'<td>{r["int_cfo"]}</td>'
            f'</tr>\n'
        )

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8">
<title>XIP-004 FULL_SYNC_REAL_IP_GATE Results</title>
<style>
  body {{ font-family: monospace; margin: 20px; }}
  h1 {{ color: #2c3e50; }}
  .gate {{ font-size:1.4em; font-weight:bold; color:{gate_color}; border:2px solid {gate_color};
           display:inline-block; padding:8px 20px; border-radius:4px; }}
  table {{ border-collapse:collapse; margin-top:20px; }}
  th {{ background:#2c3e50; color:white; padding:8px 12px; }}
  td {{ padding:6px 12px; border:1px solid #ccc; }}
  .exp {{ color:#666; font-size:0.85em; }}
</style>
</head><body>
<h1>XIP-004 FULL_SYNC_REAL_IP_GATE</h1>
<p>Gate: <span class="gate">{gate_status}</span></p>
<p>Date: {today} &nbsp;|&nbsp; DUT: phase3_sync_top (USE_BEHAVIORAL_STUB=0) &nbsp;|&nbsp;
   Cases: 9 (k_int=0,&plusmn;1,&plusmn;2,&plusmn;4,&plusmn;8)</p>
<p class="exp">
  Front-end expected (all cases): frame_index=41&plusmn;1, peak_lag=23&plusmn;1, slot_start=64&plusmn;1<br>
  Meyr expected: meyr_peak = 255 + k_int, int_cfo = k_int
</p>
<table>
<tr>
  <th>Case</th><th>Status</th><th>frame_idx</th><th>peak_lag</th>
  <th>slot_start</th><th>frac_word</th><th>meyr_peak</th><th>int_cfo</th>
</tr>
{rows}
</table>
<p style="margin-top:20px; color:#888; font-size:0.85em;">
  Generated by check_full_sync_results.py — {today}
</p>
</body></html>
"""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(html)
    print(f"  Gate HTML: {path}")

def main():
    print(f"[check] Parsing: {SIM_LOG}")
    results, gate_line = parse_sim_log(SIM_LOG)
    print(f"[check] Cases found: {len(results)}")
    print(f"[check] Gate line:   {gate_line}")

    write_csv(results, CSV_OUT)
    write_gate_txt(gate_line or "FULL_SYNC_GATE: NOT_RUN", GATE_TXT)
    write_gate_html(results, gate_line, GATE_HTML)

    pass_count = sum(1 for r in results if r["status"] == "PASS")
    fail_count = sum(1 for r in results if r["status"] == "FAIL")
    print(f"[check] Summary: {pass_count} PASS, {fail_count} FAIL / {len(results)} total")

    return 0 if (gate_line and "PASS_VIVADO_XSIM_REAL_IP" in gate_line) else 1

if __name__ == "__main__":
    sys.exit(main())
