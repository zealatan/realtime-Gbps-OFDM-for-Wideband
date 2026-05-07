# Step 26 Prompt — BRAM Preload/Readback Wrapper for Known-Vector FPGA Test

[Full prompt text archived from user message — Step 26 session 2026-05-07]

## Goal
Create a BRAM preload/readback wrapper (rtl/frac_cfo_sync_bram_test_wrapper.v) for
known-vector FPGA testing. Allow software/PS/Vitis or Vivado block design to:
- Write input IQ samples into input memory
- Configure synchronizer through AXI-Lite registers
- Start a run, stream input memory into synchronizer
- Capture synchronizer AXI-Stream output into output memory
- Read output memory and status counters back through AXI-Lite
- Compare against Python/testbench golden reference

## Context
- Phase 1 frame-buffered FSM-controlled synchronizer for functional FPGA bring-up
- Build on Step 25 (AXI-Lite + AXI-Stream debug/config wrapper)
- Simulation-friendly RTL only — no Xilinx IP, no block design, no bitstream

## Architecture
- Top wrapper: frac_cfo_sync_bram_test_wrapper.v
- Instantiates frac_cfo_frame_corrector_top directly (Option A — avoids dual AXI slave)
- One AXI-Lite slave (16-bit address, 32-bit data)
- Input memory (inferred reg array, MEM_ADDR_WIDTH=10 = 1024 entries)
- Output memory (inferred reg array, MEM_ADDR_WIDTH=10 = 1024 entries)
- Stream source FSM: reads input_mem → drives s_axis into DUT
- Stream sink FSM: receives m_axis from DUT → stores in output_mem

## Register Map (word-aligned, 32-bit)
- 0x0000 CONTROL: [3]=enable, [2]=clear_status_pulse, [1]=soft_reset_pulse, [0]=start_pulse
- 0x0004 STATUS: [8]=frame_error_sticky, [7]=wrapped_done_sticky, [6]=output_overflow_sticky,
                  [5]=input_underflow_sticky, [4]=output_done, [3]=input_done,
                  [2]=running, [1]=done_sticky, [0]=busy
- 0x0008 CFG_CFO_STEP
- 0x000C CFG_TIMING_OFFSET
- 0x0010 CFG_FRAME_LEN
- 0x0014 INPUT_LEN
- 0x0018 OUTPUT_MAX_LEN
- 0x001C INPUT_COUNT (R/O)
- 0x0020 OUTPUT_COUNT (R/O)
- 0x0024 DEBUG_STATE (R/O)
- 0x0028 ERROR_STATUS (R/O)

## Memory Map
- 0x1000–0x1FFF: input memory window (1024 × 32-bit words)
- 0x2000–0x2FFF: output memory window (1024 × 32-bit words, read-only from AXI)

## Files to Create
- rtl/frac_cfo_sync_bram_test_wrapper.v
- tb/frac_cfo_sync_bram_test_wrapper_tb.sv
- scripts/run_frac_cfo_sync_bram_test_wrapper_sim.sh
- docs/step26_bram_preload_readback_wrapper.md
- ai_context/current_status.md (update)
- md_files/26_bram_preload_readback_wrapper_prompt.md (this file)

## Test Groups
T1 Reset/default status, T2 Register write/readback, T3 Input memory write/readback,
T4 Output memory default/clear, T5 Invalid address, T6 Start without enable,
T7 Basic known-vector run, T8 CFO zero run, T9 Output max/overflow,
T10 Clear status, T11 Soft reset, T12 Backpressure/stream behavior

## Constraints
- No DMA, no Xilinx IP, no Vivado block design, no bitstream, no implementation, no Vitis
- No FFT, no integer CFO, no int_cfo_estimator.v, no Phase 2
- Preserve existing synchronizer RTL (no modification)
