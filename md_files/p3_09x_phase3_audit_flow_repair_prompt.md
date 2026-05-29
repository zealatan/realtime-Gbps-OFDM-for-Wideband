# P3-09X — Phase 3 Architecture / Verification Flow Audit and Repair

**Session role:** Claude-A — P3-09X Phase3 Architecture / Verification Flow Audit and Repair Owner  
**Date:** 2026-05-28  
**Status:** Audit complete; xsim runner created; iverilog demoted in all runners

---

## Full Prompt (verbatim)

```
ROLE
====
Claude-A — P3-09X Phase3 Architecture / Verification Flow Audit and Repair Owner

WORKSPACE
=========
/home/zealatan/RTL_SYNC_PHASE3

MANDATORY ARCHIVAL RULE
=======================
Before making any changes, create:
md_files/p3_09x_phase3_audit_flow_repair_prompt.md

This archive must contain:
* this full prompt
* your interpretation
* files inspected
* planned modifications
* final summary

BACKGROUND
==========
The Phase3 project may have drifted from the original FPGA/Vivado-oriented plan.

Known concerns:
1. Some recent PASS results were produced using iverilog, not Vivado xsim.
2. Official verification should be Vivado/xsim based.
3. Replay buffer wording may be confused with raw RF frame buffering.
4. P3-08 Meyr PASS used a bypass-FFT-compatible ROM workaround, not real FFT validation.
5. P3-09 integer CFO sweep is blocked until real FFT path is integrated.
6. P3-10A replay buffer draft may not satisfy 1 sample/clock replay throughput.

GOAL
====
Perform a full architecture and verification-flow audit.
Repair the official simulation flow so Vivado xsim is the authoritative CI gate.

This is primarily audit + scripts + documentation.
Do NOT implement new algorithmic RTL.
Do NOT integrate replay buffer.
Do NOT integrate real FFT.

TASKS
=====
1. Inspect all relevant archives [md_files/step01*, step02*, step03*, step04*,
   p3_02*, p3_04*, p3_05*, p3_05b*, p3_05c*, p3_06*, p3_07*, p3_08*, p3_09*,
   p3_10a* if present]
2. Inspect current RTL/scripts/docs
3. Create audit report: docs/p3_09x_phase3_audit_report.md
4. Create or repair Vivado xsim official runner: scripts/run_phase3_sync_xsim.sh
5. Demote iverilog (optional quick check only, not official sign-off)
6. Update documentation: docs/p3_09x_verification_flow_status.md
7. If Vivado/xsim unavailable: fail gracefully with BLOCKED_XSIM_UNAVAILABLE

PASS CRITERIA
=============
* Audit report exists
* xsim runner exists
* official CI policy is documented
* iverilog is no longer treated as authoritative
* no algorithmic RTL modified
* no fake PASS
* final response lists all confirmed drift points and repaired items

DO NOT MODIFY
=============
* ref/ algorithm semantics
* fractional CFO sign convention
* Meyr math core
* replay buffer RTL
* real FFT integration
* FPGA/Vitis/board files
```

---

## Interpretation

The core problem is that all CI_GATE PASS results from P3-05C onward were obtained using
iverilog 11.0, not Vivado xsim. Several secondary drifts compound this:

1. `run_p3_08_meyr_backend.sh` and `run_p3_09_integer_cfo_sweep.sh` hard-code `SIM="iverilog"`,
   meaning even if xsim were installed, the operators would get iverilog results by default.

2. The P3-09 runner contains a dead xsim code path ("not implemented in this skeleton") and
   an incorrect RTL source list (three nonexistent files, missing 15+ required files).

3. The P3-08 Meyr PASS is built on the bypass FFT path: the ROMs were derived from
   time-domain cross-products, not frequency-domain DFT. This is only valid for k_int=0.

4. The replay buffer throughput (1 sample per 2 cycles) differs from the "1 sample/clock"
   requirement originally stated, though it is documented as acceptable given the ~130K
   cycle Meyr latency.

Scope of repairs: scripts, documentation, and a new xsim runner. No RTL changes.

---

## Files Inspected

| File | Key Finding |
|------|-------------|
| `md_files/p3_05c_full_rtl_golden_compare_prompt.md` | CI_GATE PASS was iverilog |
| `md_files/p3_08_meyr_backend_bringup_prompt.md` | Bypass-ROM strategy confirmed |
| `md_files/p3_09_integer_cfo_sweep_prep_prompt.md` | Sweep blocked on real FFT |
| `md_files/p3_10a_replay_buffer_standalone_prompt.md` | Replay buffer 1 sample/2 cycle |
| `scripts/run_phase3_sync_sim.sh` | Defaults to xsim; no graceful xsim-unavailable path |
| `scripts/run_p3_08_meyr_backend.sh` | Hard-codes `SIM="iverilog"` |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | Hard-codes `SIM="iverilog"`; xsim path stub; wrong RTL source list |
| `scripts/run_p3_10a_iq_replay_buffer_sim.sh` | Defaults to iverilog; xsim path exists but untested |
| `scripts/compare_golden_rtl.py` | 10 checks, correct logic |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | Confirmed: "FFT PLACEHOLDER" bypass stub |
| `docs/p3_08_meyr_backend_bringup.md` | Simulation results table shows iverilog 11.0 |
| `docs/p3_09_integer_cfo_sweep_status.md` | BLOCKED on real FFT; k_int=0 only PASS |
| `docs/p3_10a_iq_replay_buffer.md` | 1 sample/2 cycle documented; not 1 sample/clock |
| `rtl/phase3_sync_top.v` | No replay buffer instantiation; integer CFO not applied |

---

## Planned Modifications

### New files
| File | Purpose |
|------|---------|
| `md_files/p3_09x_phase3_audit_flow_repair_prompt.md` | This mandatory archive |
| `docs/p3_09x_phase3_audit_report.md` | Full architecture/verification audit |
| `scripts/run_phase3_sync_xsim.sh` | Official xsim-only CI runner |
| `docs/p3_09x_verification_flow_status.md` | Official CI policy document |

### Modified files
| File | Change |
|------|--------|
| `scripts/run_p3_08_meyr_backend.sh` | Default SIM: iverilog→xsim; iverilog demote note |
| `scripts/run_p3_09_integer_cfo_sweep.sh` | Default SIM: iverilog→xsim; implement xsim compile path; fix RTL source list |
| `scripts/run_p3_10a_iq_replay_buffer_sim.sh` | Add demote note in header |

---

## Final Summary

| Item | Status |
|------|--------|
| Mandatory archive | CREATED |
| Audit report | CREATED (`docs/p3_09x_phase3_audit_report.md`) |
| xsim official runner | CREATED (`scripts/run_phase3_sync_xsim.sh`) |
| Verification flow status doc | CREATED (`docs/p3_09x_verification_flow_status.md`) |
| run_p3_08 default SIM | REPAIRED (iverilog→xsim) |
| run_p3_09 default SIM | REPAIRED (iverilog→xsim) |
| run_p3_09 xsim compile path | REPAIRED (was stub/unimplemented) |
| run_p3_09 RTL source list | REPAIRED (3 nonexistent files removed; 15+ missing files added) |
| run_p3_10a iverilog note | REPAIRED (demote note added) |
| iverilog runner preserved | YES (not deleted; demoted to optional sanity) |
| No algorithmic RTL modified | CONFIRMED |
| No fake PASS | CONFIRMED |
