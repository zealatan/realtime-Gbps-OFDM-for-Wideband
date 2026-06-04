# Phase 3 Production DUT Source List — single source of truth
# All paths are relative to the project root (RTL_SYNC_PHASE3/).
# Do NOT add rtl/phase2_legacy/, rtl/unit_test/, or bare rtl/*.v paths.
# Updated: P3-24D source unification.
#
# Usage (iverilog):
#   (cd "${ROOT}" && iverilog -g2012 -f scripts/phase3_dut_filelist.f -o out.vvp tb.sv)
#
# Usage (xvlog — no -f support):
#   mapfile -t DUT_SRCS < <(sed "s|^|${ROOT}/|" "${ROOT}/scripts/phase3_dut_filelist.f")
#   xvlog --nolog -sv "${DUT_SRCS[@]}" tb.sv

# --- primitives (no dependencies) ---
rtl/DUT/ram_2port.v
rtl/DUT/complex_mult.v
rtl/DUT/complex_mult_iq.v
rtl/DUT/complex_rotator.v
rtl/DUT/complex_to_mag.v
rtl/DUT/delay_sample.v
rtl/DUT/delayT.v
rtl/DUT/nco_phase_gen.v
rtl/DUT/peak_detector.v

# --- sub-block RTL ---
rtl/DUT/cordic_atan2.v
rtl/DUT/moving_avg_optimized.v
rtl/DUT/sample_power_sq.v
rtl/DUT/sliding_window_sum.v
rtl/DUT/streaming_cp_autocorr.v
rtl/DUT/timing_metric_core.v

# --- frame detector hierarchy ---
rtl/DUT/frame_detect_fsm.v
rtl/DUT/frame_detector.v

# --- timing / frac-CFO hierarchy ---
rtl/DUT/frac_cfo_estimator.v
rtl/DUT/timing_sync_top.v
rtl/DUT/timing_frac_cfo_top.v
rtl/DUT/frame_frac_cfo_top.v
rtl/DUT/frac_cfo_corrector_top.v
rtl/DUT/iq_frame_buffer.v
rtl/DUT/frac_cfo_frame_corrector_top.v

# --- PSS/SSS / Meyr integer CFO hierarchy ---
rtl/DUT/pss_sss_symbol_extractor.v
rtl/DUT/slot_start_controller.v
rtl/DUT/fft256_xilinx_wrapper.v
rtl/DUT/fft256_dual_symbol_frontend.v
rtl/DUT/meyr_pss_sss_product_gen.v
rtl/DUT/meyr_integer_cfo_core.v
rtl/DUT/meyr_integer_cfo_freq_estimator_top.v
rtl/DUT/meyr_integer_cfo_fft_frontend_top.v

# --- Phase 3 top-level ---
rtl/DUT/iq_replay_buffer_576.v
rtl/DUT/phase3_sync_top.v
rtl/DUT/phase3_axi_lite_regs.v
rtl/DUT/phase3_sync_axis_dma_wrapper.v
