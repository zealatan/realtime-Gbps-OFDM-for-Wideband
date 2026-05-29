# P3-11 — Real FFT / Meyr Integration Plan

**Version:** 1.0  
**Date:** 2026-05-28  
**Status:** PLAN ONLY — Implementation deferred to P3-12

---

## Objective

Enable the Meyr integer CFO estimator to operate correctly for k_int ≠ 0 by integrating
the real FFT backend (`meyr_fft256_actual_integration_top.v`) with an appropriate test
harness and frequency-domain reference ROMs.

**Selected Option: Option C — Separate Test Harness**

No production RTL is modified. All new work is in scripts, testbenches, and adapter modules.

---

## Files to CREATE in P3-12

| File | Purpose |
|------|---------|
| `scripts/gen_meyr_fft_reference_roms.py` | New ROM generator using DFT(PSS)×conj(DFT(SSS)) |
| `vectors/meyr_pss_fft_romhex.txt` | New 256-entry ROM for real FFT path (separate from bypass ROMs) |
| `vectors/meyr_sss_fft_romhex.txt` | New 256-entry SSS ROM for real FFT path (same +32767 convention) |
| `rtl/meyr_fft256_harness_adapter.v` | Interface adapter: s_i/s_q + per-symbol tlast → packed s_axis |
| `tb/p3_11_real_fft_meyr_tb.sv` | Standalone testbench for meyr_fft256_actual_integration_top |
| `scripts/run_p3_11_real_fft_meyr_dryrun_xsim.sh` | Dry-run script with BLOCKED guard (already created in P3-11) |
| `scripts/run_p3_11_real_fft_meyr_sim.sh` | Full simulation runner (xsim or iverilog STUB=1 fallback) |
| `docs/p3_12_real_fft_meyr_integration_status.md` | Status doc (create in P3-12 session) |
| `md_files/p3_12_real_fft_meyr_integration_prompt.md` | Mandatory archive (create at P3-12 start) |

---

## Files NOT to Modify

| File | Reason |
|------|--------|
| `rtl/phase3_sync_top.v` | Production orchestration — DO NOT TOUCH |
| `rtl/unit_test/meyr_integer_cfo_fft_frontend_top.v` | Unit test module — DO NOT TOUCH |
| `rtl/unit_test/fft256_dual_symbol_frontend.v` | Bypass stub — DO NOT TOUCH (Guard 2 in P3-09 runner) |
| `rtl/meyr_fft256_actual_integration_top.v` | Already complete (Step 42-B) — read-only |
| `rtl/fft256_xilinx_wrapper.v` | Stable IP wrapper — DO NOT TOUCH |
| `rtl/meyr_integer_cfo_freq_estimator_top.v` | Core math — DO NOT TOUCH |
| `rtl/meyr_integer_cfo_core.v` | Core math — DO NOT TOUCH |
| `rtl/meyr_pss_sss_product_gen.v` | Core math — DO NOT TOUCH |
| `vectors/meyr_pss_reference_romhex.txt` | Bypass-compatible ROM — DO NOT OVERWRITE |
| `vectors/meyr_sss_reference_romhex.txt` | Bypass-compatible ROM — DO NOT OVERWRITE |
| `golden/meyr_reference_debug.json` | P3-08 sentinel — DO NOT DELETE |
| All golden/ vectors | Existing golden — DO NOT TOUCH |
| All replay buffer / FPGA / Vitis / board files | Out of scope |

---

## Compile Order for iverilog (USE_BEHAVIORAL_STUB=1 — FSM verification only)

```bash
iverilog -g2012 -o sim_out/p3_11_stub_sim \
    rtl/meyr_pss_sss_product_gen.v \
    rtl/meyr_integer_cfo_core.v \
    rtl/peak_detector.v \
    rtl/meyr_integer_cfo_freq_estimator_top.v \
    rtl/fft256_xilinx_wrapper.v \
    rtl/meyr_fft256_actual_integration_top.v \
    rtl/meyr_fft256_harness_adapter.v \
    tb/p3_11_real_fft_meyr_tb.sv
```

Notes:
- `peak_detector.v` is required by `meyr_integer_cfo_core.v`
- `rtl/unit_test/fft256_dual_symbol_frontend.v` is **NOT** in this compile list (different path)
- `fft256_xilinx_wrapper.v` with `USE_BEHAVIORAL_STUB=1` requires no external IP files

---

## Compile Order for Vivado xsim (USE_BEHAVIORAL_STUB=0 — accurate simulation)

```tcl
# Step 1: Generate Xilinx FFT IP
# In Vivado TCL console:
#   create_ip -name xfft -vendor xilinx.com -library ip -version 9.1 -module_name fft256_xilinx
#   set_property -dict [list CONFIG.C_NFFT_MAX {8} CONFIG.C_ARCH {radix_2_lite} \
#     CONFIG.C_HAS_ARESETN {0} CONFIG.C_THROTTLE_SCHEME {0}] [get_ips fft256_xilinx]
#   generate_target all [get_ips fft256_xilinx]

# Step 2: Compile RTL + IP
xvlog --sv \
    <path_to_ip>/fft256_xilinx/sim/fft256_xilinx.v \
    rtl/meyr_pss_sss_product_gen.v \
    rtl/meyr_integer_cfo_core.v \
    rtl/peak_detector.v \
    rtl/meyr_integer_cfo_freq_estimator_top.v \
    rtl/fft256_xilinx_wrapper.v \
    rtl/meyr_fft256_actual_integration_top.v \
    rtl/meyr_fft256_harness_adapter.v \
    tb/p3_11_real_fft_meyr_tb.sv

# Step 3: Elaborate
xelab p3_11_real_fft_meyr_tb -debug all -snapshot p3_11_snap

# Step 4: Simulate
xsim p3_11_snap -runall
```

---

## meyr_fft256_harness_adapter.v Specification

The adapter bridges the extractor-style interface (separate I/Q, s_index, s_symbol_sel)
to the AXI-Stream interface of meyr_fft256_actual_integration_top.

```
module meyr_fft256_harness_adapter #(
    parameter integer NSC      = 256,
    parameter integer IQ_WIDTH = 16,
    ...
    parameter integer USE_BEHAVIORAL_STUB = 1   // must thread through to meyr_fft256
)(
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         start,

    // Extractor-style input (matches extractor output)
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    output wire                         done,
    output wire                         busy,
    output wire                         error,
    output wire signed [15:0]           int_cfo,
    output wire [8:0]                   peak_index,
    output wire [63:0]                  peak_score
);
    // Internal wires
    wire [2*IQ_WIDTH-1:0] axis_tdata = {s_q[IQ_WIDTH-1:0], s_i[IQ_WIDTH-1:0]};
    wire axis_tlast = (s_index == 8'd255) && s_valid && s_ready;  // per-symbol last

    meyr_fft256_actual_integration_top #(
        .NSC                (NSC),
        .IQ_WIDTH           (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB(USE_BEHAVIORAL_STUB)
    ) u_actual (
        .aclk               (aclk),
        .aresetn            (aresetn),
        .start              (start),
        .s_axis_tvalid      (s_valid),
        .s_axis_tready      (s_ready),
        .s_axis_tdata       (axis_tdata),
        .s_axis_tlast       (axis_tlast),
        .s_symbol_sel       (s_symbol_sel),
        .done               (done),
        .busy               (busy),
        .error              (error),
        .error_code         (),   // leave open
        .ev_tlast_missing_o (),   // leave open
        .ev_tlast_unexpected_o(), // leave open
        .ev_data_in_halt_o  (),   // leave open
        .ev_data_out_halt_o (),   // leave open
        .ev_status_halt_o   (),   // leave open
        .int_cfo            (int_cfo),
        .peak_index         (peak_index),
        .peak_score         (peak_score)
    );
endmodule
```

**TLAST note:** The expression `(s_index == 8'd255) && s_valid && s_ready` generates a 1-cycle pulse coincident with the 256th sample handshake. This is the correct semantic for the Xilinx FFT IP (tlast marks the last sample of a frame). If the extractor drives s_index from 0..255 sequentially with valid handshaking, this expression is correct.

---

## gen_meyr_fft_reference_roms.py Specification

The new ROM generator replaces `gen_meyr_reference_roms.py` for the real FFT path.
It must NOT overwrite the bypass-compatible ROMs — it writes to separate files.

```
Output files:
  vectors/meyr_pss_fft_romhex.txt    (frequency-domain cross-product ROM)
  vectors/meyr_sss_fft_romhex.txt    (all +32767, same convention)
  golden/meyr_fft_reference_debug.json

Algorithm:
  1. Build reference frame (identical to gen_meyr_reference_roms.py)
  2. Extract pss_td_ref = frame_norot[SLOT_START+CP_LEN .. SLOT_START+CP_LEN+NSC-1]
     Extract sss_td_ref = frame_norot[SLOT_START+2*CP_LEN+NSC .. SLOT_START+3*CP_LEN+2*NSC-1]
  3. PSS_fft = np.fft.fft(pss_td_ref.real + 1j*pss_td_ref.imag)  ← 256-point DFT
     SSS_fft = np.fft.fft(sss_td_ref.real + 1j*sss_td_ref.imag)
  4. term1_fft[j] = PSS_fft[j] * np.conj(SSS_fft[j])
  5. Normalize to Q1.15, pack {Q[31:16], I[15:0]}, write 256 lines

IMPORTANT: Integer quantization of PSS_fft and SSS_fft must match the
Xilinx FFT IP output scaling exactly. The IP uses SCALE_SCH=0xAA
(scale at alternating radix-2 stages). For a 16-bit input with amplitude A,
output bins have magnitude ≈ A × N × 2^(−ceil(log2(N)/2)) where N=256.
This scaling factor must be verified against actual FFT IP output in xsim.

For iverilog testing with STUB=1, no scaling correction needed (stub passes zeros;
results are not meaningful for CFO). ROM values are only exercised in xsim + STUB=0.
```

---

## Testbench p3_11_real_fft_meyr_tb.sv Specification

```
Module: p3_11_real_fft_meyr_tb
Purpose: Standalone test of meyr_fft256_actual_integration_top via harness adapter

Test sequence (per k_int case):
  1. Reset DUT (assert aresetn=0 for 10 clocks)
  2. Load per-case stimulus from golden/p3_09_sweep/case_kXX.mem
  3. Assert start=1 for 1 clock
  4. Stream PSS (256 samples, s_symbol_sel=0, s_index=0..255) via handshake
  5. Stream SSS (256 samples, s_symbol_sel=1, s_index=0..255) via handshake
  6. Wait for done pulse (timeout: 10,000 cycles)
  7. Capture int_cfo, peak_index, peak_score
  8. Write to sim_out/p3_11_results_kXX.txt
  9. Reset and repeat for next k_int

ROM files to use: vectors/meyr_pss_fft_romhex.txt, vectors/meyr_sss_fft_romhex.txt
Parameter: USE_BEHAVIORAL_STUB as +define or parameter (default 1 for iverilog)

Expected outcomes (per case):
  STUB=1: done fires; int_cfo=0 (stub passes zeros); NOT a correctness check
  STUB=0: done fires; peak_index = 255+k_int; int_cfo = k_int; integer_cfo_word = −k_int×2^24
```

---

## Expected Blockers

| Blocker | Probability | Mitigation |
|---------|------------|------------|
| Xilinx FFT IP not available | **HIGH** (confirmed: no ip/ dir) | Use USE_BEHAVIORAL_STUB=1 for iverilog; install Vivado for full test |
| xsim not installed | **HIGH** (confirmed) | iverilog for compile verification; deferred until Vivado available |
| ROM scaling mismatch | MEDIUM | Verify FFT IP output scale in xsim; tune gen_meyr_fft_reference_roms.py |
| TLAST generation error in adapter | LOW | adapter tlast logic straightforward; verify with $display in TB |
| meyr_integer_cfo_core $readmemh path | LOW | Use ROM file parameter or $readmemh with explicit path |
| fft256_xilinx IP port name mismatch | LOW | Port names verified in Step 39 comments in meyr_fft256_actual_integration_top.v |
| iverilog doesn't handle generate blocks in fft256_xilinx_wrapper | LOW | STUB=1/2 blocks are pure RTL, no IP; should compile cleanly |

---

## Test Sequence (P3-12)

### Phase 1: Compile Verification (iverilog + STUB=1)

```bash
# Run dry-run script to check file existence
bash scripts/run_p3_11_real_fft_meyr_dryrun_xsim.sh

# Generate frequency-domain ROMs
python3 scripts/gen_meyr_fft_reference_roms.py

# Compile with iverilog (STUB=1, no Xilinx IP)
iverilog -g2012 -DUSE_BEHAVIORAL_STUB=1 -o sim_out/p3_11_stub_sim \
    rtl/meyr_pss_sss_product_gen.v \
    rtl/meyr_integer_cfo_core.v \
    rtl/peak_detector.v \
    rtl/meyr_integer_cfo_freq_estimator_top.v \
    rtl/fft256_xilinx_wrapper.v \
    rtl/meyr_fft256_actual_integration_top.v \
    rtl/meyr_fft256_harness_adapter.v \
    tb/p3_11_real_fft_meyr_tb.sv

vvp sim_out/p3_11_stub_sim > logs/p3_11_stub.log 2>&1
```

**Pass criteria (Phase 1):**
- iverilog compiles without error
- done fires for each test case (no timeout)
- No simulator errors or $finish with non-zero code
- int_cfo=0 for all cases (expected for STUB=1 — zeros from passthrough)

### Phase 2: Accurate Simulation (xsim + STUB=0 + Xilinx IP)

Preconditions:
1. Vivado installed and on PATH
2. Xilinx FFT IP generated (`create_ip` + `generate_target`)
3. `fft256_xilinx.v` sim file in `ip/fft256_xilinx/fft256_xilinx/fft256_xilinx_sim_netlist.v` or equivalent

```bash
# Run full xsim compilation (see compile order above)
bash scripts/run_p3_11_real_fft_meyr_sim.sh --sim xsim
```

**Pass criteria (Phase 2) — one case per k_int:**

| Check | Condition | Tolerance |
|-------|-----------|-----------|
| done | fires within 10,000 cycles | exact |
| error | 0 | exact |
| peak_index | == 255 + k_int | ±1 |
| int_cfo | == k_int | exact |
| integer_cfo_word | == −k_int × 16777216 | exact |

---

## ROM File Selection Strategy

To avoid overwriting P3-08 bypass-compatible ROMs, two separate ROM pairs are maintained:

| ROM pair | Files | Compatible with |
|----------|-------|----------------|
| Bypass ROMs (P3-08) | `vectors/meyr_pss_reference_romhex.txt` + `vectors/meyr_sss_reference_romhex.txt` | fft256_dual_symbol_frontend (bypass); phase3_sync_top CI_GATE |
| FFT ROMs (P3-12) | `vectors/meyr_pss_fft_romhex.txt` + `vectors/meyr_sss_fft_romhex.txt` | meyr_fft256_actual_integration_top (real FFT); p3_11 harness TB |

`meyr_integer_cfo_core` has parameters `PSS_ROM_FILE` and `SSS_ROM_FILE` with defaults pointing to the bypass ROMs. The P3-12 testbench overrides these via `defparam` or `#(...)` instantiation to point to the FFT ROMs.

**The bypass ROMs must NOT be overwritten.** P3-09 Guard 2 and P3-08 CI_GATE both depend on them.

---

## P3-12 Session Kickoff Checklist

- [ ] Create `md_files/p3_12_real_fft_meyr_integration_prompt.md` (mandatory archive)
- [ ] Run `bash scripts/run_p3_11_real_fft_meyr_dryrun_xsim.sh` — verify BLOCKED guard fires correctly
- [ ] Create `scripts/gen_meyr_fft_reference_roms.py` — frequency-domain ROM generator
- [ ] Run ROM generator — verify `vectors/meyr_pss_fft_romhex.txt` is non-zero
- [ ] Create `rtl/meyr_fft256_harness_adapter.v` — interface adapter
- [ ] Create `tb/p3_11_real_fft_meyr_tb.sv` — standalone testbench
- [ ] Compile with iverilog (STUB=1) — Phase 1 pass criteria
- [ ] Update `docs/p3_12_real_fft_meyr_integration_status.md` — record Phase 1 result
- [ ] If Vivado available: repeat with STUB=0 — Phase 2 pass criteria
- [ ] Update memory: project_rtl_sync_phase3.md with P3-12 deliverables
