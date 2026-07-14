#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
run_rtl_regression.py  --  RECONSTRUCTED required-gate regression registry.

==============================================================================
RECONSTRUCTION NOTICE
==============================================================================
The project CLAUDE.md references `hil/agent_fsm/scripts/run_rtl_regression.py`
as the canonical "required-gate registry". That file/directory did NOT survive
the copy onto this machine. This file is a faithful RECONSTRUCTION, rebuilt by
inventorying the surviving `scripts/run_*.sh` gate scripts and mapping each of
the 11 gate names listed in CLAUDE.md to the actual script that emits it.

It is intentionally data-driven: the registry below (GATES) is the single
source of truth; main() just iterates it. Edit the table, not the logic.

CLAUDE.md required set (11): LINT_CORDIC, P3-15A, P3-15C, P3-23A, P5-EQUIV,
P5-CONT-SMOKE, P5-CONT-NIGHTLY, P5-CONT-ROBUST, P5-CORRECTED, P5-AXI-COV,
P5-D1-3WAY.

ENVIRONMENT CAVEATS (why "runnable now" is not the same as "required"):
  * This machine has Vivado 2021.1 (xsim). Several scripts hardcode
    VIVADO_DIR=/home/zealatan/.../Vivado/2022.2 and source settings64.sh from
    there. Those need path repair before they will run here. They are flagged
    needs_path_repair=True below.
  * IP-dependent gates (pure_rtl=False) instantiate Xilinx XFFT IP
    (xfft_N/xfft_2N/xfft_IFFT .xci) and/or meyr_cfo_top, and require a
    compiled simlib + Vivado-generated IP. They cannot run on a bare xsim.
  * Pure-RTL gates (pure_rtl=True) compile only project RTL/TB and can run
    on the local xsim (or iverilog sanity) once on PATH.

NOTE on LINT_CORDIC: no `scripts/run_*.sh` emits a "LINT_CORDIC" token. The
lint gate was driven elsewhere (the lost hil/agent_fsm tree). It is recorded
here as MISSING with script=None so the summary can account for it honestly.

This script does NOT run anything by default unless invoked. It is safe to
import. Run with --list to print the table without executing.
==============================================================================
"""

import argparse
import os
import subprocess
import sys

# Repo root = parent of this scripts/ directory.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def S(rel):
    """Absolute path to a script under the repo root (or None passthrough)."""
    return None if rel is None else os.path.join(ROOT, rel)


# -----------------------------------------------------------------------------
# THE REGISTRY  (single source of truth)
#
# Each entry:
#   name            : canonical gate name from CLAUDE.md
#   script          : path to the run_*.sh that emits it (None == missing)
#   required        : part of the 11-gate required set
#   pure_rtl        : True  -> PURE-RTL (xsim-only, no Xilinx IP)
#                     False -> XFFT-IP-DEPENDENT (needs simlib + generated IP)
#                     None  -> N/A (e.g. lint, or missing)
#   token           : the PASS/FAIL token printed on stdout / written to the
#                     gate file, used to grade the run
#   needs_path_repair : hardcodes /home/zealatan or VIVADO_DIR=...2022.2
# -----------------------------------------------------------------------------
GATES = [
    dict(
        name="LINT_CORDIC",
        script=None,                       # MISSING — no run_*.sh emits it
        required=True,
        pure_rtl=None,
        token="LINT_CORDIC",
        needs_path_repair=False,
        note="lint gate lived in lost hil/agent_fsm tree; not reconstructible from scripts/",
    ),
    dict(
        name="P3-15A",
        script=S("scripts/run_session_D_p3_15a_full_c_golden_equivalence.sh"),
        required=True,
        pure_rtl=True,                     # phase3_dut_filelist.f, no xfft IP
        token="EQUIV_GATE: PASS",
        needs_path_repair=False,
    ),
    dict(
        name="P3-15C",
        script=S("scripts/run_session_D3_p3_15c_equiv_robustness.sh"),
        required=True,
        pure_rtl=True,
        token="ROBUST_EQUIV_GATE: PASS",
        needs_path_repair=False,
    ),
    dict(
        name="P3-23A",
        script=S("scripts/run_session_L_p3_23a_stress.sh"),
        required=True,
        pure_rtl=True,
        token="STRESS_GATE: PASS",         # xsim official; iverilog -> SANITY_STRESS_GATE
        needs_path_repair=False,
    ),
    dict(
        name="P5-EQUIV",
        script=S("scripts/run_p5_equiv_gate.sh"),
        required=True,
        pure_rtl=False,                    # drives meyr_cfo_top + xfft IPs via run_p5_d
        token="P5_EQUIV_GATE: PASS",
        needs_path_repair=True,            # underlying run_p5_d_meyr_cfo_top_unit.sh
    ),
    dict(
        name="P5-CONT-SMOKE",
        script=S("scripts/run_p5_03_smoke_gate.sh"),
        required=True,
        pure_rtl=False,                    # sync_top continuous TB w/ xfft IPs
        token="P5_CONT_SMOKE_GATE: PASS",
        needs_path_repair=True,            # underlying run_p5_03_smoke.sh
    ),
    dict(
        name="P5-CONT-NIGHTLY",
        script=S("scripts/run_p5_03_nightly_gate.sh"),
        required=True,
        pure_rtl=False,
        token="P5_CONT_NIGHTLY_GATE: PASS",
        needs_path_repair=True,            # underlying run_p5_03_nightly.sh
    ),
    dict(
        name="P5-CONT-ROBUST",
        script=S("scripts/run_p5_03_robust_gate.sh"),
        required=True,
        pure_rtl=False,
        token="P5_CONT_ROBUST_GATE: PASS",
        needs_path_repair=True,            # underlying run_p5_03_robust.sh
    ),
    dict(
        name="P5-CORRECTED",
        script=S("scripts/run_p5_corrected_gate.sh"),
        required=True,
        pure_rtl=False,                    # depends on nightly dumps (IP path)
        token="P5_CORRECTED_GATE: PASS",
        needs_path_repair=True,            # pulls nightly via run_p5_03_nightly_gate.sh
    ),
    dict(
        name="P5-AXI-COV",
        script=S("scripts/run_p5_axi_cov.sh"),
        required=True,
        pure_rtl=False,                    # Vivado batch cov run (xfft part)
        token="P5_AXI_COV_GATE: PASS",
        needs_path_repair=True,            # VIVADO_DIR=...2022.2 hardcoded
    ),
    dict(
        name="P5-D1-3WAY",
        script=S("scripts/run_p5_d1_3way_gate.sh"),
        required=True,
        pure_rtl=True,                     # C(gcc) + python compare, no xsim/IP
        token="P5_D1_3WAY_GATE: PASS",
        needs_path_repair=False,
    ),
    # ---- OFDM TRANSMITTER (TX) gates -- new, NOT part of the required-11 ----
    dict(
        name="TX-MAP",
        script=S("scripts/run_tx_map_gate.sh"),
        required=False,
        pure_rtl=True,                     # tx_subcarrier_map: integer map, no IP
        token="TX_TXMAP_GATE: PASS",
        needs_path_repair=False,
        note="16-QAM map + pilot insert + fftshift; spectrum EXACT vs golden",
    ),
    dict(
        name="TX-IFFT",
        script=S("scripts/run_tx_ifft_gate.sh"),
        required=False,
        pure_rtl=False,                    # xfft_N driven INVERSE (real IP)
        token="TX_TXIFFT_GATE: PASS",
        needs_path_repair=False,
        note="256-pt IDFT(xfft_N inverse)+BFP+CP vs tx_dsym_out.hex (TOL 64)",
    ),
    dict(
        name="TX-TOP",
        script=S("scripts/run_tx_top_gate.sh"),
        required=False,
        pure_rtl=False,                    # full TX chain w/ real xfft IP
        token="TX_TXTOP_GATE: PASS",
        needs_path_repair=False,
        note="full 4032 slot: sync EXACT + 12 data symbols vs golden (TOL 64)",
    ),
    dict(
        name="TX-RX-LOOP",
        script=S("scripts/run_tx_loop_gate.sh"),
        required=False,
        pure_rtl=False,                    # TX(inv IP) -> RX(fwd IP) end-to-end
        token="TX_TXLOOP_GATE: PASS",
        needs_path_repair=False,
        note="TX RTL -> rx_downstream_top -> demod : BER 0 / 10608 (headline)",
    ),
    # ---- PHASE-2 DIVERSE MULTI-MODULATION ROBUSTNESS gates (new) ----------
    # The clean + multipath-channel + CFO cases assert BER==0 for ALL FOUR
    # modulations (QPSK/16/64/256-QAM) and are REQUIRED.  The AWGN waterfall is
    # a BER-vs-SNR curve (informative, non-required) -- see run_tx_rx_impair.sh
    # awgn / vivado_xsim/reports/impair_summary.txt.
    dict(
        name="IMPAIR-CLEAN",
        script=S("scripts/run_impair_clean_gate.sh"),
        required=True,
        pure_rtl=False,                    # TX(inv IP) -> impair(identity) -> RX(fwd IP)
        token="IMPAIR_CLEAN_GATE: PASS",
        needs_path_repair=False,
        note="clean multi-mod loopback : BER 0 for QPSK/16/64/256-QAM (Phase-1 result, re-gated)",
    ),
    dict(
        name="IMPAIR-CHANNEL",
        script=S("scripts/run_impair_channel_gate.sh"),
        required=True,
        pure_rtl=False,                    # 3-tap multipath on the TX->RX stream
        token="IMPAIR_CHANNEL_GATE: PASS",
        needs_path_repair=False,
        note="freq-selective 3-tap channel : pilot CE + ZF EQ equalize -> BER 0 all 4 mods",
    ),
    dict(
        name="CFO-ALLMODS",
        script=S("scripts/run_cfo_allmods_gate.sh"),
        required=True,
        pure_rtl=False,                    # full sync chain (frac+int CFO) + 3 xfft IPs
        token="CFO_ALLMODS_GATE: PASS",
        needs_path_repair=False,
        note="EPS=0.25 subcarrier CFO : frozen sync corrects -> BER 0 all 4 mods (TX-generated frame)",
    ),
]


def list_gates():
    """Print the registry as a table (no execution)."""
    hdr = "{:<16} {:<5} {:<9} {:<11} {}".format(
        "GATE", "REQ", "PURE_RTL", "PATH_REPAIR", "SCRIPT")
    print(hdr)
    print("-" * len(hdr))
    for g in GATES:
        pr = {True: "pure-rtl", False: "ip-dep", None: "n/a"}[g["pure_rtl"]]
        scr = g["script"] if g["script"] else "<MISSING>"
        print("{:<16} {:<5} {:<9} {:<11} {}".format(
            g["name"],
            "yes" if g["required"] else "no",
            pr,
            "yes" if g.get("needs_path_repair") else "no",
            scr,
        ))


def run_gate(g, timeout):
    """
    Run one gate's script and grade it by scanning stdout for its token.
    Returns one of: "PASS", "FAIL", "MISSING", "SKIP".
    """
    script = g["script"]
    if not script:
        return "MISSING"
    if not os.path.exists(script):
        print("  [{}] script not found: {}".format(g["name"], script))
        return "MISSING"

    print("  [{}] running {}".format(g["name"], os.path.relpath(script, ROOT)))
    try:
        proc = subprocess.run(
            ["bash", script],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        print("  [{}] TIMEOUT after {}s".format(g["name"], timeout))
        return "FAIL"
    except OSError as exc:
        print("  [{}] could not launch: {}".format(g["name"], exc))
        return "SKIP"

    out = proc.stdout or ""
    token = g["token"]
    # PASS iff the exact "<token>" (which already ends in ": PASS") appears.
    if token in out:
        return "PASS"
    # If the FAIL variant of the same gate prefix appears, call it FAIL.
    fail_prefix = token.rsplit(":", 1)[0] + ": FAIL"
    if fail_prefix in out or proc.returncode != 0:
        return "FAIL"
    # Token never showed up at all (blocked / unparseable).
    print("  [{}] gate token not found in output (rc={})".format(
        g["name"], proc.returncode))
    return "FAIL"


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Reconstructed required-gate RTL regression runner.")
    ap.add_argument("--list", action="store_true",
                    help="print the gate registry and exit (no execution)")
    ap.add_argument("--all", action="store_true",
                    help="run every gate, not just the required set")
    ap.add_argument("--timeout", type=int, default=1800,
                    help="per-gate timeout in seconds (default 1800)")
    args = ap.parse_args(argv)

    if args.list:
        list_gates()
        return 0

    selected = GATES if args.all else [g for g in GATES if g["required"]]

    results = {}
    for g in selected:
        results[g["name"]] = run_gate(g, args.timeout)

    # Summary counts.
    n_pass = sum(1 for r in results.values() if r == "PASS")
    n_fail = sum(1 for r in results.values() if r == "FAIL")
    n_skip = sum(1 for r in results.values() if r in ("SKIP", "MISSING"))
    total = len(results)

    print("")
    print("=" * 60)
    for name, r in results.items():
        print("  {:<16} {}".format(name, r))
    print("=" * 60)

    overall = "PASS" if (n_fail == 0 and n_skip == 0) else "FAIL"
    # required=NP/MF/Kskip  ==  N pass / M fail / K skipped, out of total.
    print("Overall: {}  required={}P/{}F/{}skip  (of {})".format(
        overall, n_pass, n_fail, n_skip, total))

    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
