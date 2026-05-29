# P3-02 — Reference-Style Frame Detector (Archive)

## Original Prompt

Role: Claude-A — P3-02 Reference-Style Frame Detector Owner.

Mandatory archive: md_files/p3_02_reference_style_frame_detector_prompt.md (this file).

Create rtl/reference_style_frame_detector.v implementing the C frame_detector()
(receiver.c:327, Toan's version) as a streaming RTL module.
Create tb/p3_02_reference_style_frame_detector_tb.sv with 8 test cases (T01-T08).
Create scripts/run_p3_02_reference_style_frame_detector_sim.sh.
Create docs/p3_02_reference_style_frame_detector.md.

Reuse legacy primitives where practical:
  sample_power_sq from rtl/phase2_legacy/ (2-cycle latency)
  moving_avg_optimized from rtl/phase2_legacy/ (power-of-2 only — not used: WND_LEN=25)

FSM: IDLE / SEARCH_RISE / SEARCH_FALL / DONE

Pass criteria: TB PASS 0 FAIL; frame_index matches C rule.

## Interpretation

The C frame_detector() (receiver.c lines 327-382) implements:
  envelopeBlock[j] = mean(I[j..j+WND-1]^2 + Q[j..j+WND-1]^2)
  Case A (window[0] < threshold): scan for CONFIRM_LEN consecutive above-threshold windows.
  Case B (window[0] >= threshold): find first drop below threshold (startIndex),
    then apply Case A counting from startIndex.
  Return: j + 1 - CONFIRM_LEN at the CONFIRM_LEN-th hit
        = window index of first hit in the winning run.

RTL avoids division: compares running window SUM vs threshold*WND_LEN.
Threshold port accepts the pre-scaled sum threshold (caller multiplies by WND_LEN).

moving_avg_optimized NOT used: its window is 2^WINDOW_SHIFT samples (power-of-2 only),
incompatible with WND_LEN=25. Sliding window implemented with WND_LEN-stage shift register.

IQ word: {Q[2*IQ_W-1:IQ_W], I[IQ_W-1:0]}. Power is symmetric; order irrelevant.

## Files Inspected

- ref/receiver.c lines 327-382 (Toan's frame_detector)
- rtl/phase2_legacy/sample_power_sq.v (2-cycle latency, IQ_WIDTH/OUT_WIDTH params)
- rtl/phase2_legacy/moving_avg_optimized.v (power-of-2 window, not suitable)
- rtl/unit_test/frame_detector.v (existing buffer-read implementation, reference only)

## Architecture Decisions

AXI-Stream input (s_tdata/s_tvalid/s_tready/s_tlast).
s_tready = busy (backpressure from module when not running).
sample_power_sq: enable=busy, reset=~aresetn, input_strobe = s_tvalid & s_tready.
Sliding window: WND_LEN-stage shift register, running_sum updated on each pwr_stb.
End-of-stream: s_tlast sets eos_armed; drain_cnt (init 2) decrements on each pwr_stb
  after eos_armed; when drain_cnt==1 (last pwr_stb), go to S_DONE if not found.
frame_index output = window start index (sample address) of first hit in winning run.
  Computed as: pwr_cnt_old - (WND_LEN-1) captured when consec transitions 0→1.

## Files Created

- md_files/p3_02_reference_style_frame_detector_prompt.md (this file)
- rtl/reference_style_frame_detector.v
- tb/p3_02_reference_style_frame_detector_tb.sv (T01-T08)
- scripts/run_p3_02_reference_style_frame_detector_sim.sh
- docs/p3_02_reference_style_frame_detector.md
