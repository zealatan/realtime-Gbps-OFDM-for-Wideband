# scripts/ — board build & bring-up helpers

Repo-level helper scripts for **hardware build and ZCU216 bring-up** (Vivado
block-design TCL, board capture, silicon compare). For the RTL **simulation /
regression** gates see `../RTL_SYNC_PHASE5/scripts/` instead.

## What's here (by kind)

| Pattern | Purpose |
|---------|---------|
| `build_*.tcl`        | Vivado block-design / project build scripts (DDC, digital loopback, full-RX loopback, RF-sync, transceiver) |
| `*_bd*.tcl`          | block-design edit / finalize scripts |
| `package_*_ip.tcl`   | package the DUT / transceiver RTL as a Vivado IP |
| `*_capture*.py/.sh`  | capture IQ / FFT samples from the board |
| `compare_board_capture.py`, `demod_silicon_capture.py` | compare silicon captures against golden / demod on host |
| `gen_*waveform*.py`, `gen_stim_*.py` | generate DAC stimulus / test vectors |
| `logs/`              | build & capture logs |

## Notes

- Hardware build/synthesis runs on the **locked part** `xczu9eg-ffvb1156-2-e`;
  RFSoC tools are **Vivado 2021.1** / **Vitis 2022.2**.
- `*.bak_*` files are timestamped backups of TCL edited during bring-up — safe
  to ignore.

See the [repo-root README](../README.md) for the full build-and-run flow.
