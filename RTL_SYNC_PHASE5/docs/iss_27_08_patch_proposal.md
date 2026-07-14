# ISS-27 / ISS-08 — Patch Proposal: internal slot params → 14-symbol / 4032-sample convention

**Status:** PROPOSAL ONLY — no `rtl/` edits applied. Review-ready.
**Date:** 2026-06-22
**Author:** analysis agent (read-only)
**Source issue:** `docs/iss_triage_2026-06-19.md` (ISS-27 + ISS-08), classified **STILL-VALID (partial)**

---

## 0. TL;DR

The board wrapper (`phase3_sync_axis_dma_wrapper.v`) and all golden/stimulus
metadata already use the new **14-symbol slot** (2 sync + 12 data) ×
288 = **4032 samples**. But the *internal* synchronizer chain still hardcodes
the OLD **2-symbol / 576-sample** slot in two modules:

- `rtl/slot_start_controller.v` — `FRAME_TOTAL = 2*(NSC+CP_LEN) = 576`
- `rtl/phase3_sync_top.v` — `NUM_DATA = 5`, `FRAME_LEN = 2*(NSC+CP_LEN) = 576`
- `rtl/meyr_slot_frontend.v` — `NUM_DATA = 5` (parameter default; header already says 12)

The wrapper drives `OUTPUT_SAMPLES = FRAME_LEN = 576` into the frac corrector
via `phase3_sync_top`, so the corrector only replays **576** of the **4032**
slot samples. The wrapper's M_AXIS TLAST counter expects **4032**
(`int_frame_len` default = 4032). Result: a hard length mismatch between what
the internal chain produces (576 corrected beats) and what the wrapper /
golden vectors expect (4032 beats). This is a real functional inconsistency.

The fix is a **3-line family of parameter/localparam bumps**, BUT it carries a
non-trivial ripple: the frac corrector's internal capture buffer is only
**4096 deep (BUF_AW=12)** while the new slot needs `slot_start + 4031` ≈ 4095
read addresses *and* the stimulus is 4160 samples. See §3 (Ripple) — the buffer
margin is the dominant risk.

---

## 1. Where each frame constant lives (file:line, current → proposed)

### 1a. The "golden" reference values (NOT changed — these define the target)

| Source | file:line | value |
|---|---|---|
| C ref | `ref/pluto.h:52` | `#define NUM_SYN_BLOCKS 2` |
| C ref | `ref/pluto.h:55` | `#define NUM_DATA_BLOCKS 12` |
| C ref | `ref/pluto.h:57-58` | `NSC 256`, `CP_LEN 32` → SYM_LEN 288 |
| meta json | `golden/phase3_iq_stimulus_meta.json` | `frame_len:4032, num_data_blocks:12, num_sync_blocks:2, num_blocks_per_slot:14` |
| fullchain manifest | `golden/p5_wrapper_fullchain/manifest.json` | `FRAME_LEN:4032, NUM_DATA:12, NUM_SYMBOLS:14, expected_output_count:4032` |
| AXI-Lite reg default | `rtl/phase3_axi_lite_regs.v:463` | `frame_len_samples_o <= 12'd4032` (already correct) |
| Wrapper localparam | `rtl/phase3_sync_axis_dma_wrapper.v:199-200` | `NUM_BLOCKS_PER_SLOT=14`, `FRAME_LEN_LP=4032` (already correct) |

**Canonical target:** 14 symbols × 288 = **4032 samples**; NUM_SYN=2,
NUM_DATA=12, payload (data) offset = 2×288 = **576**.

### 1b. The STALE internal constants (THESE must change)

| # | file:line | localparam/param | current | proposed | role |
|---|---|---|---|---|---|
| C1 | `rtl/slot_start_controller.v:61` | `FRAME_TOTAL = 2 * (NSC + CP_LEN)` | **576** | `14 * (NSC + CP_LEN)` = **4032** | drives `frame_len` output (= required `OUTPUT_SAMPLES` of corrector) |
| C2 | `rtl/phase3_sync_top.v:51` | `parameter NUM_DATA = 5` | **5** | **12** | passed to `meyr_slot_frontend.NUM_DATA` |
| C3 | `rtl/phase3_sync_top.v:104` | `localparam FRAME_LEN = 2 * (NSC + CP_LEN)` | **576** | `14 * (NSC + CP_LEN)` = **4032** | passed as `OUTPUT_SAMPLES` to `frac_cfo_frame_corrector_top` (line 304) |
| C4 | `rtl/meyr_slot_frontend.v:43` | `parameter NUM_DATA = 5` | **5** | **12** | slot geometry (SLOT_LEN, sym decode, data_sym_idx) |

> Note C2/C4: `phase3_sync_top` instantiates `meyr_slot_frontend` with
> `.NUM_DATA(NUM_DATA)` (line 374), so fixing C2 propagates into the
> instance. But the **module default** at C4 should ALSO be bumped to 12 so
> any standalone TB / other instantiation gets the correct geometry and the
> header comment (`:14` "NUM_DATA = 12") stops lying (ISS-08). Belt and braces.

> `NUM_SYN` is already **2** everywhere (`slot_start_controller` has no
> NUM_SYN; `phase3_sync_top:50` NUM_SYN=2; `meyr_slot_frontend:41` NUM_SYN=2).
> No change needed for NUM_SYN.

### 1c. Constants that derive correctly once C1–C4 land (no edit needed, listed for audit)

- `slot_start_controller`: `PSS_OFFSET=CP_LEN=32`, `SSS_OFFSET=2*CP_LEN+NSC=320`
  — unchanged (sync symbols are still symbols 0,1; payload offsets are intra-slot).
- `phase3_sync_top`: `PSS_OFFSET`, `SSS_OFFSET` (lines 102-103) — same, unchanged.
- `meyr_slot_frontend`: `SYM_LEN=288`, `TOTAL_SYMS=NUM_SYN+NUM_DATA`,
  `SLOT_LEN=TOTAL_SYMS*SYM_LEN`, `sym_num`, `sym_phase`, counters — all derived
  from params; auto-update once NUM_DATA=12 (see §3 width check).
- `frac_cfo_frame_corrector_top`: `TOTAL_SAMPLES = OUTPUT_SAMPLES`,
  `PLAY_CNT_W = $clog2(TOTAL_SAMPLES+1)`, `play_rd_ptr[PLAY_CNT_W-1:0]` —
  auto-resize (see §3).

---

## 2. Unified-diff-style snippets (PROPOSED — do not apply yet)

### C1 — `rtl/slot_start_controller.v`

```diff
@@ rtl/slot_start_controller.v:59-61 @@
     localparam integer PSS_OFFSET  = CP_LEN;                    // 32
     localparam integer SSS_OFFSET  = 2 * CP_LEN + NSC;          // 320
-    localparam integer FRAME_TOTAL = 2 * (NSC + CP_LEN);        // 576
+    // 14-symbol slot: 2 sync (PSS,SSS) + 12 data = 14 * (NSC+CP_LEN) = 4032
+    localparam integer FRAME_TOTAL = 14 * (NSC + CP_LEN);       // 4032
```

> Optional hardening: parameterize the symbol count instead of the literal 14
> so the magic number lives in one place:
> ```diff
> @@ rtl/slot_start_controller.v:30-34 @@
>  module slot_start_controller #(
>      parameter integer NSC         = 256,
>      parameter integer CP_LEN      = 32,
> +    parameter integer NUM_SYMS    = 14,  // 2 sync + 12 data
>      parameter integer BUF_AW      = 12,
>      parameter integer INDEX_WIDTH = 9
> @@ FRAME_TOTAL @@
> -    localparam integer FRAME_TOTAL = 14 * (NSC + CP_LEN);
> +    localparam integer FRAME_TOTAL = NUM_SYMS * (NSC + CP_LEN);
> ```
> (Reviewer's call; the plain literal-14 bump is the minimal change.)

### C2 — `rtl/phase3_sync_top.v` (NUM_DATA param default)

```diff
@@ rtl/phase3_sync_top.v:49-51 @@
-    // C-ref TX slot: 2 sync + 5 data = 7 symbols.
+    // TX slot: 2 sync + 12 data = 14 symbols (pluto.h NUM_DATA_BLOCKS=12).
     parameter integer NUM_SYN         = 2,
-    parameter integer NUM_DATA        = 5
+    parameter integer NUM_DATA        = 12
```

### C3 — `rtl/phase3_sync_top.v` (FRAME_LEN localparam)

```diff
@@ rtl/phase3_sync_top.v:102-104 @@
     localparam integer PSS_OFFSET    = CP_LEN;
     localparam integer SSS_OFFSET    = 2 * CP_LEN + NSC;
-    localparam integer FRAME_LEN     = 2 * (NSC + CP_LEN);
+    // 14-symbol slot -> corrector must replay all 4032 samples.
+    localparam integer FRAME_LEN     = (NUM_SYN + NUM_DATA) * (NSC + CP_LEN); // 14*288 = 4032
```

> Preferred form ties FRAME_LEN to (NUM_SYN+NUM_DATA) so C2 and C3 cannot
> drift apart. `(2+12)*288 = 4032`. This value flows to
> `frac_cfo_frame_corrector_top.OUTPUT_SAMPLES` at line 304.

### C4 — `rtl/meyr_slot_frontend.v` (NUM_DATA param default)

```diff
@@ rtl/meyr_slot_frontend.v:41-43 @@
     parameter NUM_SYN       = 2,
-    // C-ref TX slot = 2 sync + 5 data symbols.
-    parameter NUM_DATA      = 5
+    // TX slot = 2 sync + 12 data symbols (pluto.h NUM_DATA_BLOCKS=12).
+    parameter NUM_DATA      = 12
```

---

## 3. Ripple-effect analysis (counter widths, buffer depth, address math)

Going 576 → 4032 multiplies the slot length by 7×. Every counter/address that
spans a slot must be re-checked. Findings:

### 3.1 SELF-RESIZING (no edit needed — confirmed safe)

| Location | expression | @576 | @4032 | safe? |
|---|---|---|---|---|
| `frac_cfo_frame_corrector_top.v:105` | `PLAY_CNT_W = $clog2(TOTAL_SAMPLES+1)` | 10 b (≥577) | 13 b (≥4033) | YES, auto |
| `frac_cfo_frame_corrector_top.v:210` | `play_rd_ptr[PLAY_CNT_W-1:0]` | 10 b | 13 b | YES, auto |
| `meyr_slot_frontend.v:83` | `slot_cnt[$clog2(SLOT_LEN)-1:0]` | $clog2(2016)=11 b | $clog2(4032)=12 b | YES, auto |
| `meyr_slot_frontend.v:87` | `sym_num[$clog2(TOTAL_SYMS)-1:0]` | $clog2(7)=3 b | $clog2(14)=4 b | YES, auto |
| `meyr_slot_frontend.v:88` | `sym_phase[$clog2(SYM_LEN)-1:0]` | 9 b (=288) | 9 b | YES, unchanged |
| `slot_start_controller.v:65` | `frame_len = FRAME_TOTAL[BUF_AW-1:0]` | 576 fits 12 b | 4032 fits 12 b | YES (4032 < 4096) |

### 3.2 FIXED-WIDTH FIELDS — check for truncation/overflow

| Location | field | width | needs | verdict |
|---|---|---|---|---|
| `meyr_slot_frontend.v:64` | `data_sym_idx[3:0]` | 4 b (0..15) | 0..11 (NUM_DATA-1=11) | **OK** — 4 bits holds 11. (At NUM_DATA=5 it held 0..4; at 12 holds 0..11; would break only at >16 data syms.) |
| `phase3_sync_top.v` instance line 374 | `.NUM_DATA(NUM_DATA)` | — | propagates 12 | OK once C2 applied |
| `slot_start_controller.v:63-65` | PSS/SSS/frame_len `[BUF_AW-1:0]` | 12 b | 32,320,4032 all <4096 | OK |
| wrapper `out_frame_cnt[11:0]`, `in_frame_cnt[11:0]` (`:282,:320`) | TLAST counters | 12 b | compares to `int_frame_len`(12 b)=4032 | OK (already sized for 4032; 4032 ≤ 4095) |
| AXI-Lite `FRAME_LEN_SAMPLES[11:0]` (`phase3_axi_lite_regs.v:454-463`) | 12 b, default 4032, range 1-4095 | 4032 | OK (already correct) |

### 3.3 ⚠ DOMINANT RISK — frac corrector capture buffer depth (BUF_AW=12 → 4096)

This is the one place where the 7× expansion gets **dangerously tight**, and
it is NOT auto-resized:

- `frac_cfo_frame_corrector_top.v:225-228` instantiates `iq_frame_buffer` with
  `ADDR_WIDTH=BUF_AW=12`, `DEPTH = 1<<BUF_AW = 4096`.
- `iq_frame_buffer.v` captures input until **`full` (4096 samples)** or `tlast`
  (`iq_frame_buffer.v:55-57,71-74`). It is a *single-slot* buffer.
- After detection the corrector replays `buf_rd_addr = slot_start_r + play_rd_ptr`
  (`frac_cfo_frame_corrector_top.v:363`) for `play_rd_ptr = 0..TOTAL_SAMPLES-1`
  = **0..4031**.

Consequences once FRAME_LEN=4032:

1. **Read-address span:** max read addr = `slot_start_r + 4031`. The golden
   stimulus has `slot_start ≈ 64` (= PRE_ZEROS, see meta json), giving
   `64 + 4031 = 4095` — fits in 4096 with **margin = 1 entry**. Any slot_start
   > 64 makes `buf_rd_addr` exceed 4095 and **wrap** (BUF_AW truncation),
   reading stale/garbage samples. At 576 the margin was huge (64+575=639);
   at 4032 it is effectively zero.
2. **Capture overflow:** the stimulus file is **4160 samples**
   (`samples_per_file:4160` = 64 pre + 4032 frame + 64 post). The 4096-deep
   buffer goes `full` at sample 4096 and de-asserts `s_axis_tready`, dropping
   the last 64 samples. For the *current* golden stimulus the dropped tail is
   POST_ZEROS, so it is harmless — but this is fragile and undocumented.

**Recommendation (flag for reviewer, larger change — out of minimal scope):**
bump `BUF_AW` from 12 → 13 (DEPTH 8192) in the corrector path so a full
14-symbol slot plus a realistic non-zero `slot_start` fits with margin. This
touches:
- `phase3_sync_top.v:35` `parameter BUF_AW = 12` → 13 (and the wrapper
  `phase3_sync_axis_dma_wrapper.v:47`), which widens `frame_index`,
  `slot_start`, `buf_rd_addr`, `frame_detector` search_len, AXI-Lite BUF_AW,
  the `iq_replay_buffer_576` already defaults ADDR_W=13.
- Cross-check `frame_detector` `search_len = {1'b1,{BUF_AW{1'b0}}}`
  (`frac_cfo_frame_corrector_top.v:270`) scales with BUF_AW automatically.

**The C1–C4 minimal patch alone is FUNCTIONAL for the current golden stim**
(slot_start=64, post-zeros tail), but the BUF_AW=12 margin-of-1 must be called
out as a latent bug. Decide BUF_AW=13 as a companion change or accept the
documented constraint `slot_start ≤ 64`.

### 3.4 Watchdogs / thresholds already pre-adjusted (no edit)

- `phase3_sync_axis_dma_wrapper.v:336-349` TLAST_TIMEOUT counter already
  widened to 16 b with threshold 16384 explicitly "so 576→4032 does not
  falsely trip" — good, no change.
- `frac_cfo_frame_corrector_top` S_FILL `acq_wdog` is an *inactivity* watchdog
  (cycles with no accepted sample), not a length counter — unaffected by slot
  length.

### 3.5 `iq_replay_buffer_576.v` — already migrated, currently UNUSED

`iq_replay_buffer_576.v:53-54` already defaults `FRAME_LEN=4032, ADDR_W=13`
with a `$fatal` guard `FRAME_LEN > (1<<ADDR_W)`. Per `CLAUDE.md` the replay
buffer was **retired in P5-03** (wrapper comment `:186` "replay buffer
RETIRED"); it is not instantiated in the active wrapper. No change needed; note
it as already-consistent dead code.

---

## 4. Verification plan

Order matters: lint/elaboration first (catches width issues), then the
functional gates. Per `CLAUDE.md`, the master command is
`python3 hil/agent_fsm/scripts/run_rtl_regression.py` (must stay 11/11 PASS).

| # | Gate / TB | Why re-run | Engine |
|---|---|---|---|
| V1 | `LINT_CORDIC` + elaboration of all 3 edited modules | confirm no width/truncation warnings after C1–C4 (esp. `data_sym_idx`, `slot_cnt`) | xvlog/xelab (lint) |
| V2 | `P5-CORRECTED` (`scripts/run_p5_corrected_gate.sh`) | bit-exact M_AXIS — directly checks corrector now replays **4032** beats, not 576. **Primary functional gate for this fix.** | xsim, full chain |
| V3 | `P5-CONT-SMOKE / NIGHTLY / ROBUST` (`run_p5_03_*_gate.sh`) | continuous-stream / no-drop behavior across the longer slot; exercises wrapper TLAST counter @4032 | xsim, full chain |
| V4 | `P5-AXI-COV` (`run_p5_axi_cov.sh`) | FRAME_LEN_SAMPLES reg already 4032; confirm no regression | xsim |
| V5 | `P5-D1-3WAY` (`run_p5_d1_3way_gate.sh`) | C ↔ Python ↔ RTL equivalence on the 14-symbol slot (uses `golden/p5_wrapper_fullchain`, expected_output_count=4032) | xsim + C + py |
| V6 | `P5-EQUIV` (`run_p5_equiv_gate.sh`) | meyr_cfo_top 17/17 — unaffected by slot length but part of required set; sanity | xsim |
| V7 | meyr_slot_frontend unit TB (if present in `tb/`) | verify data_sym_idx now spans 0..11 and SLOT_LEN counter wraps at 4032 | xsim |

> **Cache note (CLAUDE.md):** gates are cached on RTL/TB mtime. After applying
> C1–C4, `touch` the three edited files (or any dependency) to force cold runs,
> or the gates may report stale PASS.
>
> **Stim regeneration:** the active full-chain stimulus
> (`golden/p5_wrapper_fullchain/`) is already 4032/4160. The legacy
> `golden/p3_15d_stimuli/*_meta.json` still say `frame_len:576` — those feed
> the **P3-15D** gate (frac-CFO sweep), which exercises the corrector at the
> *old* single-symbol output and is NOT in the required-11 set per CLAUDE.md.
> Confirm P3-15D either is excluded or its stim is regenerated; flag if it
> trips on the new default FRAME_LEN. (It may pass an explicit OUTPUT_SAMPLES
> param — verify before assuming breakage.)
>
> All functional confirmation requires **xsim / full-chain** (V2–V7). No
> Vivado synthesis/timing is needed to validate ISS-27/08 (pure
> functional/parameter change), though a follow-up OOC re-synth is prudent if
> BUF_AW=13 is adopted (§3.3) since it changes RAM sizing.

---

## 5. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| **R1: BUF_AW=12 capture buffer margin-of-1** (§3.3). `slot_start + 4031` ≤ 4095 only while `slot_start ≤ 64`. Larger timing offset → read-address wrap → corrupted replay. | **HIGH** (latent) | Adopt BUF_AW=13 companion change OR document hard constraint `slot_start ≤ 64` and add an assertion. Current golden stim is safe (slot_start=64). |
| **R2: 4160-sample stim vs 4096 buffer** — last 64 samples dropped when `full`. Harmless today (POST_ZEROS) but fragile. | MEDIUM | Same as R1 (BUF_AW=13 removes it). Document that input must end (tlast) within 4096 samples of capture_start. |
| **R3: P3-15D legacy stim still 576** — gate may fail if it relies on default FRAME_LEN. | MEDIUM | Verify P3-15D's OUTPUT_SAMPLES wiring; regenerate its stim if needed. Not in required-11 set. |
| **R4: C2/C3 drift** — if FRAME_LEN literal and NUM_DATA edited independently they can desync. | LOW | Use derived form `FRAME_LEN=(NUM_SYN+NUM_DATA)*(NSC+CP_LEN)` (C3 preferred snippet). |
| **R5: data_sym_idx** at exactly the 4-bit boundary (max 11 of 15). | LOW | Fits; no action. Would break only if NUM_DATA>14. |
| **R6: longer slot increases latency / fill time** — any TB timeout tuned for 576 may expire. | LOW–MED | TLAST_TIMEOUT already widened (§3.4). Re-check TB-level `#timeout` waits in `tb/` continuous gates; bump if they assume ~576-cycle slots. |
| **R7: meyr_cfo_top** ("don't touch", 302 MHz). | NONE | Unaffected — it consumes only PSS+SSS (2N), which is independent of NUM_DATA. No edit proposed. |

**Net:** the C1–C4 parameter bump is low-risk and functionally correct for the
existing golden vectors. The single must-resolve item before calling ISS-27/08
*closed* is **R1 (BUF_AW capture margin)** — either size it up (BUF_AW=13) or
formally constrain + assert `slot_start ≤ 64`.

---

## 6. Change manifest (for the eventual PR — NOT applied here)

```
rtl/slot_start_controller.v      C1   FRAME_TOTAL 576 -> 4032   (1 line)
rtl/phase3_sync_top.v            C2   NUM_DATA    5   -> 12      (1 line)
rtl/phase3_sync_top.v            C3   FRAME_LEN   576 -> 4032    (1 line)
rtl/meyr_slot_frontend.v         C4   NUM_DATA    5   -> 12      (1 line)
[optional companion, R1]         BUF_AW 12 -> 13 in phase3_sync_top.v:35
                                 + phase3_sync_axis_dma_wrapper.v:47
```
4 minimal lines (+2 optional for the buffer-depth hardening).
No `meyr_cfo_top` edits. No Vivado required for functional sign-off.
