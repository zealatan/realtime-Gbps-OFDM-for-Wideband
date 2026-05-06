# Step 20: frac_cfo_frame_corrector_top

## Module: `rtl/frac_cfo_frame_corrector_top.v`

Top-level integration of the full OFDM synchronization + fractional CFO correction chain.
Accepts a raw AXI-Stream IQ input, runs frame detection and CFO estimation on the captured
buffer, then streams CFO-corrected IQ samples out via AXI-Stream.

## Sub-modules instantiated

| Instance   | Module                  | Role                              |
|------------|-------------------------|-----------------------------------|
| u_buf      | iq_frame_buffer         | Shared IQ sample buffer           |
| u_fd       | frame_detector          | Scan buffer for frame start index |
| u_tfc      | timing_frac_cfo_top     | CP timing + frac CFO estimation   |
| u_corr     | frac_cfo_corrector_top  | NCO + complex_rotator correction  |

## FSM

```
S_IDLE ──start──► S_FILL ──buf_capture_done──► S_FRAME_DET
                                                    │
                                          frame_found=1
                                                    │
                                              S_TIMING_CFO
                                                    │
                                          frac_phase_valid
                                                    │
                                               S_LOAD_NCO  (wait NCO_WAIT=17 clocks)
                                                    │
                                               S_CORRECT   (stream TOTAL_SAMPLES)
                                                    │
                                                S_DONE ──► S_IDLE
                             frame_found=0 ──► S_DONE (frame_error=1)
```

## Buffer read mux

The single iq_frame_buffer read port is muxed in priority order:
- S_FRAME_DET  → frame_detector read port
- S_TIMING_CFO → timing_frac_cfo_top read port
- S_CORRECT    → FSM playback pointer (slot_start + play_rd_ptr)

## 1-deep hold FIFO (playback latency compensation)

`play_rd_pend` tracks an in-flight buffer read. On the cycle after `can_issue`, `buf_rd_data` is
latched into `play_hold_data`. The corrector input is driven from the hold register. Prevents
over-read while respecting axis_complex_mult back-pressure.

## NCO step word

`step_word = {(-frac_phase_r), 16'h0000}`

Converts Q1.15 fractional phase (from cordic_atan2) into a 32-bit two's-complement NCO phase
increment. Negation applies frequency correction in the opposite direction to the detected CFO.

## Testbench: `tb/frac_cfo_frame_corrector_top_tb.sv`

Parameters: NSC_TB=16, CP_LEN_TB=4, BUF_AW_TB=10, TOTAL_TB=20, LATENCY_TB=15

| Test | Description                        | Checks |
|------|------------------------------------|--------|
| T1   | Reset: done=busy=frame_error=0     | 3      |
| T2   | Happy path (8 quiet + 100 signal)  | 9      |
| T3   | m_axis output count and tlast      | 3      |
| T4   | Sample values (zero-CFO Q1.15)     | 5      |
| T5   | No frame found (max threshold)     | 6      |
| T6   | done pulse width = 1 clock         | 2      |
| T7   | busy timeline                      | 4      |
| T8   | frame_index stable after done      | 2      |
| T9   | peak_lag stable after done         | 2      |
| T10  | Back-to-back runs                  | 5      |

**Result: PASS: 39   FAIL: 0   CI GATE: PASSED**

## Simulation script

`scripts/run_frac_cfo_frame_corrector_top_sim.sh`
