#!/usr/bin/env python3
"""check_fft_ip_outputs.py — Compare RTL xsim outputs vs reference vectors.

Reads:
  vivado_xsim/vectors/rtl_out_case_<N>.csv   (from xsim_fft_ip_value_protocol_tb)
  vivado_xsim/vectors/fft_ref_case_<N>.csv   (from gen_fft_reference.py)

Writes:
  vivado_xsim/reports/xsim_fft_ip_gate.html  (HTML comparison table)
  vivado_xsim/reports/xsim_fft_ip_check.csv  (per-bin delta summary)
  vivado_xsim/reports/xsim_execution_status.txt  (gate result line)
"""

import os
import csv
import sys
import math
import datetime

TOLERANCE  = 4       # ±4 LSB per bin component (matches TB)
FFT_LEN    = 256
NUM_CASES  = 6
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJ_ROOT  = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))
VEC_DIR    = os.path.join(PROJ_ROOT, "vivado_xsim", "vectors")
RPT_DIR    = os.path.join(PROJ_ROOT, "vivado_xsim", "reports")

os.makedirs(RPT_DIR, exist_ok=True)

CASE_NAMES = {
    0: "Impulse n=0",
    1: "Complex tone k=1",
    2: "Real cosine k=17",
    3: "DC constant",
    4: "32-sample comb",
    5: "Zero input",
}


def read_rtl_csv(case_num):
    path = os.path.join(VEC_DIR, f"rtl_out_case_{case_num}.csv")
    if not os.path.exists(path):
        return None, path
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append((int(row["bin"]), int(row["re"]), int(row["im"])))
    return rows, path


def read_ref_csv(case_num):
    path = os.path.join(VEC_DIR, f"fft_ref_case_{case_num}.csv")
    if not os.path.exists(path):
        return None, path
    rows = []
    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append((int(row["bin"]), int(row["ref_re"]), int(row["ref_im"])))
    return rows, path


def abs_err(got, expected):
    return abs(got - expected)


def generate_html(case_results, gate_result, timestamp):
    color_pass = "#2d6a2d"
    color_fail = "#8b0000"
    color_warn = "#7a5500"
    color_miss = "#444"

    def badge(label, color):
        return (f'<span style="background:{color};color:#fff;'
                f'padding:2px 8px;border-radius:4px;font-weight:bold;">{label}</span>')

    rows = ""
    for case_num, info in case_results.items():
        status = info["status"]
        if status == "PASS":
            color = "#1e4d1e"
            b = badge("PASS", color_pass)
        elif status == "MISS_RTL":
            color = "#2a2a2a"
            b = badge("NO RTL CSV", color_miss)
        elif status == "MISS_REF":
            color = "#2a2a2a"
            b = badge("NO REF CSV", color_miss)
        else:
            color = "#4d0000"
            b = badge(f"FAIL ({info['fail_count']} bins)", color_fail)

        rows += f"""
        <tr style="background:{color};">
          <td style="padding:4px 8px;">{case_num}</td>
          <td style="padding:4px 8px;">{CASE_NAMES.get(case_num,'')}</td>
          <td style="padding:4px 8px;">{b}</td>
          <td style="padding:4px 8px;">{info.get('max_err_re','-')}</td>
          <td style="padding:4px 8px;">{info.get('max_err_im','-')}</td>
          <td style="padding:4px 8px;">{info.get('fail_count',0)}</td>
        </tr>"""

    gate_color = color_pass if "PASS" in gate_result else color_fail
    gate_badge = badge(gate_result, gate_color)

    html = f"""<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<title>FFT IP xsim Gate Report</title>
<style>
  body{{font-family:monospace;background:#1a1a1a;color:#ddd;margin:20px;}}
  h1{{color:#aaf;}} h2{{color:#88f;}}
  table{{border-collapse:collapse;width:100%;max-width:900px;}}
  th{{background:#333;padding:6px 10px;text-align:left;color:#bdf;}}
  td{{border-bottom:1px solid #333;}}
</style>
</head><body>
<h1>FFT IP Value + Protocol Gate Report</h1>
<p>Generated: {timestamp}</p>
<p>Tolerance: ±{TOLERANCE} LSB per component</p>
<p>Gate result: {gate_badge}</p>

<h2>Per-Case Summary</h2>
<table>
<tr>
  <th>#</th><th>Case</th><th>Status</th>
  <th>Max err Re</th><th>Max err Im</th><th>Fail bins</th>
</tr>
{rows}
</table>

<h2>Notes</h2>
<ul>
<li>RTL CSV: written by <code>xsim_fft_ip_value_protocol_tb.sv</code> via <code>$fwrite</code></li>
<li>Ref CSV: written by <code>gen_fft_reference.py</code> with SCALE=1/16</li>
<li><code>MISS_RTL</code> = xsim was not run or TB did not write CSV</li>
<li><code>MISS_REF</code> = run <code>gen_fft_reference.py</code> first</li>
<li>Gate label <code>PASS_VIVADO_XSIM_REAL_IP</code> requires all 6 cases PASS</li>
</ul>
</body></html>"""
    return html


def main():
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"check_fft_ip_outputs.py — {timestamp}")
    print(f"Vectors: {VEC_DIR}")
    print()

    case_results = {}
    total_fails  = 0
    missing_count = 0
    all_pass = True

    csv_out_rows = [["case", "bin", "rtl_re", "rtl_im", "ref_re", "ref_im",
                     "err_re", "err_im", "fail"]]

    for case_num in range(NUM_CASES):
        rtl_rows, rtl_path = read_rtl_csv(case_num)
        ref_rows, ref_path = read_ref_csv(case_num)

        if rtl_rows is None:
            print(f"  Case {case_num}: MISS_RTL ({rtl_path})")
            case_results[case_num] = {"status": "MISS_RTL"}
            missing_count += 1
            all_pass = False
            continue
        if ref_rows is None:
            print(f"  Case {case_num}: MISS_REF ({ref_path})")
            case_results[case_num] = {"status": "MISS_REF"}
            missing_count += 1
            all_pass = False
            continue

        rtl_by_bin = {r[0]: (r[1], r[2]) for r in rtl_rows}
        ref_by_bin = {r[0]: (r[1], r[2]) for r in ref_rows}

        fail_bins = 0
        max_err_re = 0
        max_err_im = 0

        for k in range(FFT_LEN):
            rtl_re, rtl_im = rtl_by_bin.get(k, (None, None))
            ref_re, ref_im = ref_by_bin.get(k, (None, None))
            if rtl_re is None or ref_re is None:
                continue
            err_re = abs_err(rtl_re, ref_re)
            err_im = abs_err(rtl_im, ref_im)
            max_err_re = max(max_err_re, err_re)
            max_err_im = max(max_err_im, err_im)
            fail = (err_re > TOLERANCE) or (err_im > TOLERANCE)
            if fail:
                fail_bins += 1
                total_fails += 1
            csv_out_rows.append([case_num, k, rtl_re, rtl_im, ref_re, ref_im,
                                  err_re, err_im, int(fail)])

        status = "PASS" if fail_bins == 0 else "FAIL"
        if fail_bins > 0:
            all_pass = False
        case_results[case_num] = {
            "status":     status,
            "fail_count": fail_bins,
            "max_err_re": max_err_re,
            "max_err_im": max_err_im,
        }
        print(f"  Case {case_num} ({CASE_NAMES.get(case_num,'')}): {status}  "
              f"max_err=({max_err_re},{max_err_im})  fail_bins={fail_bins}")

    # -----------------------------------------------------------------------
    # Gate decision
    # -----------------------------------------------------------------------
    if missing_count > 0:
        gate_result = f"BLOCKED_MISSING_FILES ({missing_count} CSV files not found)"
    elif all_pass:
        gate_result = f"PASS_VIVADO_XSIM_REAL_IP (all {NUM_CASES} cases, tol ±{TOLERANCE} LSB)"
    else:
        gate_result = f"FAIL_VALUE_MISMATCH ({total_fails} bin-component errors across all cases)"

    print()
    print("=" * 64)
    print(f"GATE: {gate_result}")
    print("=" * 64)

    # -----------------------------------------------------------------------
    # Write outputs
    # -----------------------------------------------------------------------
    status_path = os.path.join(RPT_DIR, "xsim_execution_status.txt")
    with open(status_path, "w") as f:
        f.write(f"FFT_IP_CHECKER_GATE: {gate_result}\n")
        f.write(f"Generated: {timestamp}\n")
        f.write(f"Tolerance: ±{TOLERANCE} LSB\n")
        f.write(f"Cases checked: {NUM_CASES - missing_count}/{NUM_CASES}\n")
    print(f"Gate status: {status_path}")

    html_path = os.path.join(RPT_DIR, "xsim_fft_ip_gate.html")
    with open(html_path, "w") as f:
        f.write(generate_html(case_results, gate_result, timestamp))
    print(f"HTML report: {html_path}")

    csv_path = os.path.join(RPT_DIR, "xsim_fft_ip_check.csv")
    with open(csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(csv_out_rows)
    print(f"CSV detail:  {csv_path}")

    return 0 if ("PASS" in gate_result) else 1


if __name__ == "__main__":
    sys.exit(main())
