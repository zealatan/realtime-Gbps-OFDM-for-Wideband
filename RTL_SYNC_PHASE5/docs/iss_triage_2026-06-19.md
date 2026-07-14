# RTL Issue Triage — 2026-06-19

Triage of the open / non-resolved RTL issues against the **current** `rtl/` code
(meyr_cfo_top FFT-correlation design, top = `phase3_sync_axis_dma_wrapper`).

Source of issue records: `status/dashboard.json` `issues[]`.
(The path `rtl_dashboard/rtl_issues.html` referenced in the task does not exist
in this tree; the live issue store is `status/dashboard.json`, rendered to
`p5_issue_tracker.html` by `scripts/gen_dashboards.py`.)

Classification key:
- **STILL-VALID** — the bug/gap described is still present in current code.
- **FIXED-IN-CODE-BUT-OPEN** — the described fix is present in `rtl/` (or `scripts/`),
  issue kept open for re-verification.
- **OBSOLETE** — no longer applies due to the new meyr_cfo_top design / retired modules.

This file does **not** edit any issue record; issues stay open.

## Triage table

| ID | sev | area | status (json) | classification | evidence (file:line) | note |
|----|-----|------|---------------|----------------|----------------------|------|
| ISS-02 | high | algorithm | resolved | FIXED-IN-CODE-BUT-OPEN | `rtl/meyr_ifft_peak_dut.v:191-192` (`(power>max_power) && (s2_idx != n_runtime)` excludes Nyquist bin) | Nyquist-bin guard present exactly as the fix described. |
| ISS-05 | high | structural | resolved | OBSOLETE | no `rtl/meyr_corr_ctrl.v` / `meyr_fft512_in_ctrl.v` / `out_ctrl.v`; not in `scripts/phase3_dut_filelist.f` | Dead serial-Meyr path; modules gone in new design. |
| ISS-06 | medium | integration | open | FIXED-IN-CODE-BUT-OPEN | `rtl/phase3_sync_top.v:396-410` (`meyr_sync_capture u_capture` 2N buffer with `out_tready`/`overrun_event` between slot_frontend and core) | Method-1 sync_capture decouple is wired; still open pending back-to-back verification. |
| ISS-07 | medium | rtl | resolved | FIXED-IN-CODE-BUT-OPEN | `rtl/meyr_sync_capture.v:17,74` ("driven from a SINGLE always-block") | r1_pending now single-driver; //VERIFY tags consolidated. |
| ISS-08 | medium | integration | resolved | STILL-VALID (partial) | `rtl/meyr_slot_frontend.v:58` (`pss_first_beat` added) BUT `:43` `parameter NUM_DATA = 5` and header `:14` says 12 | pss_first_beat marker done; slot geometry NUM_DATA still 5, not the 12 the header claims — overlaps ISS-27. |
| ISS-09 | high | timing | partial | STILL-VALID | per docs: best WNS −0.568 ns (~219 MHz) vs 250 MHz target; blocker `meyr_sync_capture` LUTRAM combinational read | Timing not met; see `docs/p5_05_status.md`. Out of scope for file-only triage but gap is real. |
| ISS-11 | low | housekeeping | open | FIXED-IN-CODE (cruft absent) | `find rtl/ -name '*Zone.Identifier*'` → none | No ADS cruft files present currently; trivially clean. |
| ISS-12 | critical | hardware | blocked | OBSOLETE (for RTL triage) | n/a — physical board connection | Hardware-only; superseded by ISS-20 (HIL_TEST_PASS). No RTL bearing. |
| ISS-13 | medium | verification | resolved | FIXED-IN-CODE-BUT-OPEN | `tb/p5_invariants.sv` (20 assert/property bind) | SVA invariant bind present; passes in P5-EQUIV per notes. |
| ISS-14 | high | build | resolved | FIXED-IN-CODE-BUT-OPEN | `scripts/phase3_dut_filelist.f` closure = single meyr_cfo_top top; old fft256/meyr_integer_cfo modules absent from `rtl/` | One-DUT consolidation done; orphans `meyr_ak_dut.v`,`meyr_mult_FFT_ak_bk_dut.v` remain on disk but excluded from closure. |
| ISS-15 | low | infra | partial | STILL-VALID | `rtl/xfft_N/xfft_N.xci` (real IP, xsim-only); no behavioral xfft model | xsim-only decision recorded; iverilog fallback still absent. |
| ISS-17 | critical | rtl | resolved | FIXED-IN-CODE-BUT-OPEN | `rtl/meyr_Rm_dut.v:84` (`initial $readmemh("bk_conj_fft512_rom.txt", rom)`) | ROM init present in RTL; HW TODO = add `vectors/bk_conj_fft512_rom.txt` as Vivado source. |
| ISS-18 | high | verification | resolved | FIXED-IN-CODE-BUT-OPEN (registry diverged) | `scripts/run_rtl_regression.py` gate list (11 gates, reconstructed) | P5-D-CONT not present by name in the reconstructed registry; the original `hil/agent_fsm` registry was lost. TB exists; gate plumbing partially reconstructed. |
| ISS-19 | high | integration | resolved | FIXED-IN-CODE-BUT-OPEN | `rtl/phase3_sync_top.v:159` (`frac_m_first_beat = frac_m_tvalid && !frac_m_seen_in_frame`), slot_start rewired | first-beat slot_start fix present exactly as described. |
| ISS-21 | medium | verification | open | STILL-VALID | `rtl/phase3_sync_axis_dma_wrapper.v:57` (`parameter THRESHOLD = 10240000`) | Default THRESHOLD still far above stim energy; no elaboration-time assertion/lint guard added. TB-side override is the only mitigation. |
| ISS-22 | high | rtl | resolved | FIXED-IN-CODE-BUT-OPEN | `rtl/phase3_sync_top.v:134` (`assign frac_m_tready = 1'b1;`) | Floating-tready fix present (single line) as described. |
| ISS-23 | medium | verification | open | STILL-VALID | `rtl/phase3_sync_axis_dma_wrapper.v:57` THRESHOLD default vs HW; no sim/HW reconciliation in code | DC-tone sim-vs-HW frame_detector discrepancy unresolved; needs bitstream THRESHOLD inspection (no code change present). |
| ISS-24 | high | rtl | open | STILL-VALID | `rtl/phase3_sync_axis_dma_wrapper.v:385-408` (auto-rearm on DUT-idle, still one-shot per slot; no concurrent slot-k/k+1 Meyr pipeline) | Re-arm timing improved (P5-03), but the concurrent-Meyr throughput architecture change is NOT implemented → ~50% M_AXIS duty stands. |
| ISS-25 | low | verification | open | STILL-VALID | no warmup/soft-reset in `rtl/meyr_cfo_top.v` / `meyr_ifft_peak_dut.v` / `meyr_Rm_dut.v` (grep empty); workaround is TB-side warmup run | Cold-start +102-bin bias root cause not addressed in RTL. |
| ISS-26 | medium | verification | open | FIXED-IN-CODE-BUT-OPEN | `scripts/gen_p5_wrapper_full_chain_stim.py` exists (B[k]-matched full-chain stim, NUM_DATA_BLOCKS 5→12) | The Step-2c matched-stim generator the NEXT action asked for is written; open pending absolute-k_int re-verification with matched stim. |
| ISS-27 | medium | spec | open | STILL-VALID (partial) | wrapper updated: `rtl/phase3_sync_axis_dma_wrapper.v:199-200` (`NUM_BLOCKS_PER_SLOT=14`, FRAME_LEN_LP=4032). BUT internal not bumped: `rtl/slot_start_controller.v:61,65` (`FRAME_TOTAL = 2*(NSC+CP_LEN) = 576`), `rtl/phase3_sync_top.v:51` (`NUM_DATA=5`), `:104` (`FRAME_LEN = 2*(NSC+CP_LEN)`) | Agent C wrapper/golden work done; Agent B's RTL slot-param bump (slot_start_controller frame_len, phase3_sync_top NUM_DATA/FRAME_LEN) still owed → internal chain still 576-sample, wrapper expects 4032. Real inconsistency. |

## Summary counts

Issues triaged: 21 (the 11 non-resolved open/partial/blocked + 10 resolved entries
whose "FIXED ..." notes describe a code fix to verify; ISS-01/03/04/10/16/20 are
clean closures with no current-code action and are omitted).

- **STILL-VALID (bug/gap present in current code): 8**
  ISS-08 (partial), ISS-09, ISS-15, ISS-21, ISS-23, ISS-24, ISS-25, ISS-27 (partial)
- **FIXED-IN-CODE-BUT-OPEN (fix present, kept open for re-verify): 11**
  ISS-02, ISS-06, ISS-07, ISS-11, ISS-13, ISS-14, ISS-17, ISS-18, ISS-19, ISS-22, ISS-26
- **OBSOLETE (new design / retired modules / hardware-only): 2**
  ISS-05, ISS-12

### Highest-priority STILL-VALID items
1. **ISS-27 + ISS-08** — internal slot params (`slot_start_controller` FRAME_TOTAL=576,
   `phase3_sync_top` NUM_DATA=5/FRAME_LEN=576) are out of sync with the wrapper's
   4032-sample 14-symbol slot. Functional mismatch until Agent B bumps them.
2. **ISS-24** — wrapper FSM still one-shot per slot; no concurrent Meyr pipelining,
   so the "250 Msps continuous, zero drops" throughput spec is not met (~50% duty).
3. **ISS-09** — 250 MHz timing not met (~219 MHz best); reused-chain bottleneck.
