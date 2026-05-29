`timescale 1ns/1ps

// meyr_fft256_harness_adapter — P3-13A standalone harness adapter
//
// Converts the old-style separate I/Q test interface used by existing Phase3
// testbenches into the packed AXI-Stream format expected by
// meyr_fft256_actual_integration_top.
//
// STANDALONE HARNESS ONLY — do NOT instantiate inside phase3_sync_top or any
// production RTL path.
//
// Interface mapping:
//
//   Old-style input (from TB / existing Phase3 test infrastructure):
//     s_valid       — sample valid
//     s_ready       — back-pressure from downstream (output)
//     s_symbol_sel  — 0=PSS, 1=SSS
//     s_index[7:0]  — sample index within symbol (0..255)
//     s_i[15:0]     — signed I sample (Q1.15 or raw int16)
//     s_q[15:0]     — signed Q sample
//
//   AXI-Stream output (to meyr_fft256_actual_integration_top):
//     m_axis_tvalid      — valid
//     m_axis_tready      — ready (from DUT)
//     m_axis_tdata[31:0] — packed {Q[31:16], I[15:0]}
//     m_axis_tlast       — last sample of current symbol (s_index == 255)
//     m_axis_symbol_sel  — informational pass-through (not used by DUT FSM)
//
// Packing convention {Q[31:16], I[15:0]} matches the DUT unpacking:
//   pss_buf[k][IQ_WIDTH-1:0]          = I  (lower halfword)
//   pss_buf[k][2*IQ_WIDTH-1:IQ_WIDTH] = Q  (upper halfword)
//
// The adapter is purely combinational (no registered state).

module meyr_fft256_harness_adapter #(
    parameter integer IQ_WIDTH = 16
)(
    // Old-style input
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    // AXI-Stream output to meyr_fft256_actual_integration_top
    output wire                         m_axis_tvalid,
    input  wire                         m_axis_tready,
    output wire [2*IQ_WIDTH-1:0]        m_axis_tdata,
    output wire                         m_axis_tlast,
    output wire                         m_axis_symbol_sel
);

    assign m_axis_tvalid    = s_valid;
    assign s_ready          = m_axis_tready;
    assign m_axis_tdata     = {s_q[IQ_WIDTH-1:0], s_i[IQ_WIDTH-1:0]};
    assign m_axis_tlast     = s_valid && (s_index == 8'd255);
    assign m_axis_symbol_sel = s_symbol_sel;

endmodule
