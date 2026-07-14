# RTL_SYNC_PHASE5 — the OFDM transceiver design

This directory holds the complete, mode-selectable **OFDM transceiver** RTL
for the AMD **ZCU216 RFSoC**, plus its testbenches, reference models, golden
vectors and run scripts. See the [repo-root README](../README.md) for the
big-picture overview; this file is the working reference for the design itself.

> **Status:** sim BER = 0 (all 3 modes, all 4 modulations) and **ZCU216
> silicon BER = 0** at full rate (187.5 MHz). RF DAC→ADC analog loopback: C2R
> mixer bug fixed on silicon; residual traced to a degraded SMA cable.

## Numerology

`NSC=256`, `CP_LEN=32`, 221 data sub-carriers + 32 QPSK pilots, 12 data + 2
sync (PSS/SSS) symbols per frame, slot length **4032** samples.
`mode[1:0]` = TX / RX / LOOPBACK · `mod_sel[1:0]` = QPSK / 16-QAM / 64-QAM /
256-QAM.

## Layout

```
rtl/        synthesizable Verilog
  ofdm_transceiver_top.v     mode-selectable TX/RX/LOOPBACK top
  ofdm_xcvr_board_top.v      board adapter (GPIO/AXI-Lite control)
  tx_subcarrier_map.v        QAM map + QPSK pilots + fftshift
  tx_ifft_frontend.v         256-pt IDFT (xfft) + cyclic prefix
  tx_ofdm_top.v              PSS/SSS + 12 data symbols -> 4032 slot
  rx_full_chain_top.v        full RX: sync->FFT->CE->EQ->demod
  meyr_cfo_top.v + meyr_*    frame sync + integer-CFO (Meyr) core
  frame_detector.v, frac_cfo_*   timing + fractional-CFO chain
  rx_fft_frontend.v          256-pt FFT front-end
  rx_ch_est.v                pilot-based channel estimation
  rx_equalizer.v             zero-forcing equalizer
  rx_demod_qam.v             QAM slicer / demodulator
  rx_ber_checker.v           on-chip BER counter
  xfft_{N,2N,IFFT}/          real Xilinx xfft 9.1 IP (.xci)
  tx_rom/, rx_ch_est_rom/    generated ROM hex (constellations, LUTs)
tb/         SystemVerilog testbenches
golden/     bit-exact reference vectors
ref/        C reference (receiver.c, transmitter.c)
scripts/    run_*.sh gates, run_rtl_regression.py, rx_downstream_ref.py (golden)
docs/       specs, gate logs, block diagrams
status/     dashboard.json — single source of truth for KPIs
vivado_xsim/tcl/  xsim project Tcl (build artifacts gitignored)
```

## Build / test

> **Real-IP rule:** gates run against the **real Xilinx xfft 9.1 IP** on the
> locked part `xczu9eg-ffvb1156-2-e`. A stub/fallback run is sanity only — a
> gate is "PASS" only on a real-IP run. Sim tool: **Vivado 2021.1**.

```bash
# 3-mode transceiver (TX / RX / LOOPBACK) end-to-end — BER must be 0
bash scripts/run_xcvr_3mode.sh

# 4-modulation clean digital loopback (QPSK/16/64/256-QAM) — BER must be 0
bash scripts/run_tx_rx_loop_allmods.sh

# required-gate regression
python3 scripts/run_rtl_regression.py
python3 scripts/run_rtl_regression.py --list    # list gates without running
```

Gate reports land in `vivado_xsim/reports/`.

## Design flow

C reference (`ref/receiver.c`, `ref/transmitter.c`) → NumPy golden model
(`scripts/rx_downstream_ref.py`) → RTL → xsim with **real** xfft IP → ZCU216
silicon. Every block is bit-exact against its golden vector before it is
trusted. See `docs/` for per-gate logs and the block diagrams.

*Internal project — not publicly licensed.*
