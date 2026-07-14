# Phase 5 — Meyr FFT-correlation integer-CFO core source list
# meyr_cfo_top hierarchy only. Old serial-Meyr files are NOT included.
#
# Excluded by design:
#   - rtl/meyr_corr_ctrl.v   (dead path; refers to nonexistent
#     meyr_fft512_in_ctrl / meyr_fft512_out_ctrl; not on the
#     meyr_cfo_top -> meyr_Rm_dut datapath)
#
# Usage (xvlog):
#   mapfile -t SRCS < <(sed "s|^|${ROOT}/|" "${ROOT}/scripts/phase5_meyr_cfo_filelist.f")
#   xvlog --nolog "${SRCS[@]}" tb.sv
#
# FFT IPs (xfft_N, xfft_2N, xfft_IFFT) live under rtl/xfft_*/*.xci and
# must be added to the Vivado project sources separately; xvlog does
# not consume .xci directly.

# --- primitives ---
rtl/complex_mult.v
rtl/complex_mult_32.v

# --- A[k] + zero-pad chain ---
rtl/meyr_ak_buf.v
rtl/meyr_zeropad.v
rtl/meyr_FFT_ak_dut.v

# --- new FFT-correlation Meyr datapath ---
rtl/meyr_feeder.v
rtl/meyr_Rm_dut.v
rtl/meyr_ifft_peak_dut.v
rtl/meyr_cfo_top.v

# --- L2 integration bridge ---
rtl/meyr_slot_frontend.v
rtl/meyr_sync_capture.v
