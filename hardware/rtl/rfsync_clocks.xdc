# RF 6c-2: pl_clk0 (99.99 MHz) and pl_clk1 (153.6 MHz) are independent PS PL
# clock outputs (separate CRL_APB divisors, no fixed phase relationship) ->
# treat them as asynchronous. Every real datapath crossing between them has a
# proper synchronizer:
#   - RFDC m20 (clk_adc2) -> pl_clk1 : axis_data_fifo (rfsync_fifo) async CDC
#   - loop_ctrl_gpio (pl_clk0) -> rfsync_cap/ctrl (pl_clk1) : dut_capture
#     ctrl_meta/ctrl_sync (* ASYNC_REG *) double-flop
#   - interconnect M07 (pl_clk0) -> dut_0/s_axi (pl_clk1) : auto_cc async-lite
#     clock converter handshake
# Without this, the tool times the GPIO->ASYNC_REG and auto_cc handshake paths
# as synchronous (requirement ~0.012ns) and reports WNS ~ -1.4 ns spuriously.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks clk_pl_0] \
    -group [get_clocks -include_generated_clocks clk_pl_1]
