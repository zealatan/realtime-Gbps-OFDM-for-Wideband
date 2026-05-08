# reports/step29b/ — Step 29B ZCU102 UART Test Reports

This directory holds artifacts captured during the Step 29B ZCU102 board bring-up and UART
known-vector test.

## Expected Files

| File | Description | Status |
|------|-------------|--------|
| `step29b_uart_log.txt` | Full UART terminal output captured during the run | NOT RUN |
| `step29b_result.md` | Short result summary: INPUT_COUNT, OUTPUT_COUNT, RESULT | NOT RUN |

## Execution Status

Board execution has not been performed yet.

The following tasks are pending manual execution on a Windows PC with ZCU102 connected:

1. Program FPGA: `outputs/step28/sync_phase1_bd_wrapper.bit` via Vivado Hardware Manager
2. Build Vitis application from `sw/step29a_vitis_known_vector/`
3. Run application on ZCU102 via JTAG (psu_cortexa53_0, standalone)
4. Capture UART terminal output (115200 baud, Silicon Labs CP2108 Interface 0)
5. Save full UART log as `step29b_uart_log.txt` in this directory

## Required Artifacts

- Bitstream: `outputs/step28/sync_phase1_bd_wrapper.bit`
- XSA: `outputs/step28/sync_phase1_bd_wrapper.xsa`
- Software: `sw/step29a_vitis_known_vector/`

## Reference

See `docs/step29b_zcu102_vitis_bringup_uart_test.md` for the full bring-up procedure,
expected UART output, pass/fail criteria, and debug checklist.

## Pass Criteria

RESULT: PASS requires all of:
- `done_sticky` = 1
- `frame_error_sticky` = 0
- `ERROR_STATUS` = 0
- `INPUT_COUNT` = 28
- `OUTPUT_COUNT` ≥ 1
