`timescale 1ns/1ps
// meyr_fft256_harness_adapter — testbench-to-AXI-Stream shim for Meyr FFT tests
//
// Converts per-sample (valid/ready/index/IQ) testbench interface to
// AXI4-Stream {Im,Re} tdata format required by meyr_fft256_actual_integration_top.
//
// Combinational pass-through — no registers, no latency.
// TLAST is asserted at index=255 (NSC-1) when valid=1.

module meyr_fft256_harness_adapter #(
    parameter integer IQ_WIDTH = 16
)(
    // TB-side (per-sample) interface
    input  wire                    s_valid,
    output wire                    s_ready,
    input  wire                    s_symbol_sel,
    input  wire [7:0]              s_index,
    input  wire signed [IQ_WIDTH-1:0] s_i,
    input  wire signed [IQ_WIDTH-1:0] s_q,

    // AXI4-Stream output to DUT
    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready,
    output wire [2*IQ_WIDTH-1:0]   m_axis_tdata,
    output wire                    m_axis_tlast,
    output wire                    m_axis_symbol_sel
);

    assign m_axis_tvalid    = s_valid;
    assign s_ready          = m_axis_tready;
    assign m_axis_tdata     = {s_q[IQ_WIDTH-1:0], s_i[IQ_WIDTH-1:0]};
    assign m_axis_tlast     = s_valid && (s_index == 8'hFF);
    assign m_axis_symbol_sel = s_symbol_sel;

endmodule
