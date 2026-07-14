# =============================================================================
# phase3_dut_filelist_newdesign.f
# -----------------------------------------------------------------------------
# Source-file list for the CURRENT OFDM-sync design (RTL_SYNC_PHASE5).
#
# Top module : phase3_sync_axis_dma_wrapper  (-> phase3_sync_top)
# CFO core   : meyr_cfo_top  (NEW FFT-correlation integer-CFO core)
#
# This list was built by computing the full instantiation closure starting
# from the top module phase3_sync_axis_dma_wrapper and recursively walking
# every module instance found in rtl/*.v. Modules are listed in dependency
# order: leaf primitives first, the top module last.
#
# Paths are relative to RTL_SYNC_PHASE5/ (i.e. they begin with rtl/).
#
# NOTE 1 - Xilinx xfft IP cores are EXTERNAL and are NOT listed here. They
#          are added to the project separately via their .xci files:
#              rtl/xfft_N/xfft_N.xci      (used by meyr_cfo_top)
#              rtl/xfft_2N/xfft_2N.xci    (used by meyr_Rm_dut)
#              rtl/xfft_IFFT/xfft_IFFT.xci (used by meyr_ifft_peak_dut)
#          The instance names xfft_N / xfft_2N / xfft_IFFT in the RTL resolve
#          to these IP cores, not to any rtl/*.v file.
#
# NOTE 2 - This file does NOT replace the legacy scripts/phase3_dut_filelist.f.
#          The legacy filelist points at the RETIRED old-design rtl/DUT/*.v
#          tree and references modules that no longer exist (e.g.
#          fft256_xilinx_wrapper, meyr_integer_cfo_core, ...). Use THIS file
#          for the current meyr_cfo_top design.
#
# NOTE 3 - Modules present in rtl/*.v but NOT in this production closure
#          (orphans, intentionally excluded): iq_replay_buffer_576,
#          meyr_ak_dut, meyr_mult_FFT_ak_bk_dut, pss_sss_symbol_extractor,
#          timing_frac_cfo_top, timing_metric_core.
# =============================================================================

# ---- primitives / shared leaf cells -----------------------------------------
rtl/ram_2port.v
rtl/delayT.v
rtl/complex_mult.v
rtl/complex_mult_iq.v
rtl/complex_mult_32.v
rtl/cordic_atan2.v
rtl/nco_phase_gen.v
rtl/complex_rotator.v

# ---- timing-sync chain (CP autocorrelation + peak detect) -------------------
rtl/delay_sample.v
rtl/moving_avg_optimized.v
rtl/sample_power_sq.v
rtl/complex_to_mag.v
rtl/streaming_cp_autocorr.v
rtl/peak_detector.v
rtl/timing_sync_top.v

# ---- fractional-CFO chain ----------------------------------------------------
rtl/frac_cfo_estimator.v
rtl/frame_frac_cfo_top.v
rtl/frac_cfo_corrector_top.v

# ---- frame-detect / frame buffering -----------------------------------------
rtl/sliding_window_sum.v
rtl/frame_detect_fsm.v
rtl/frame_detector.v
rtl/iq_frame_buffer.v
rtl/iq_capture_pingpong.v
rtl/frac_cfo_frame_corrector_top.v

# ---- Meyr integer-CFO core (NEW FFT-correlation) ----------------------------
rtl/meyr_feeder.v
rtl/meyr_ak_buf.v
rtl/meyr_zeropad.v
rtl/meyr_FFT_ak_dut.v
rtl/meyr_Rm_dut.v
rtl/meyr_ifft_peak_dut.v
rtl/meyr_cfo_top.v
rtl/meyr_slot_frontend.v
rtl/meyr_sync_capture.v
rtl/slot_start_controller.v

# ---- top: orchestrator FSM + board-integration wrapper ----------------------
rtl/phase3_axi_lite_regs.v
rtl/phase3_sync_top.v
rtl/phase3_sync_axis_dma_wrapper.v
