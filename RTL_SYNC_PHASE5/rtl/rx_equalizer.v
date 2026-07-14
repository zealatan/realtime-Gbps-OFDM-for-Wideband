// =====================================================================
// rx_equalizer.v  — AXI-Stream zero-forcing equalizer (top wrapper)
// ---------------------------------------------------------------------
// Streams freq-domain RX symbols and the channel estimate H, one complex
// sample per clock, and produces the equalized symbols
//
//   eq[i] = RX[i] * conj(H[i]) / |H[i]|^2          (ZF, receiver.c fde)
//
// at 1 sample/clk, back-to-back, fully pipelined. Guards |H|^2 == 0 -> 0.
//
// INTERFACE (one 32-bit beat = one complex sample, {Q[31:16], I[15:0]}):
//   * s_axis_rx   : RX freq-domain sample (TDATA = {rxQ,rxI})
//   * s_axis_h    : channel estimate H    (TDATA = {hQ ,hI })  (Q15;
//                   H is sign-extended to 18b inside the divider)
//   * s_axis_*_tuser : carries the bin index (0..255) for downstream
//                      carrier extraction; passed straight through.
//   * m_axis      : equalized sample (TDATA = {eqQ,eqI}); TUSER = bin idx.
//
//   Both input streams advance together: a transfer happens only when
//   BOTH s_axis_rx_tvalid and s_axis_h_tvalid are high and the pipeline
//   is allowed to advance. Backpressure (m_axis_tready low while the
//   output is occupied) freezes the whole pipeline via a common clock
//   enable, so NO samples are dropped and throughput is 1/clk whenever
//   downstream is ready. The intrinsic latency is the divider depth (9).
//
//   (Carrier extraction to the 221 dataIndx bins is a downstream concern;
//    this module equalizes every bin and tags it with TUSER so the next
//    stage / TB can keep only the data carriers. The accompanying TB
//    performs exactly that extraction and checks against eq_out.hex.)
//
// Synthesizable Verilog-2001. Target part: xczu49dr-ffvf1760-2-e.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_equalizer #(
    parameter integer DW       = 16,
    parameter integer HW       = 18,
    parameter integer OW       = 16,
    parameter integer TUSERW   = 16,
    parameter         LUT_FILE = "rx_equalizer_recip_lut.hex"
)(
    input  wire                    clk,
    input  wire                    rst_n,

    // RX freq-domain stream  {Q,I}
    input  wire                    s_axis_rx_tvalid,
    output wire                    s_axis_rx_tready,
    input  wire [31:0]             s_axis_rx_tdata,
    input  wire [TUSERW-1:0]       s_axis_rx_tuser,

    // channel-estimate stream {Q,I}
    input  wire                    s_axis_h_tvalid,
    output wire                    s_axis_h_tready,
    input  wire [31:0]             s_axis_h_tdata,

    // equalized output stream {Q,I}
    output wire                    m_axis_tvalid,
    input  wire                    m_axis_tready,
    output wire [31:0]             m_axis_tdata,
    output wire [TUSERW-1:0]       m_axis_tuser
);
    localparam integer LAT = 9;   // divider pipeline depth

    // -----------------------------------------------------------------
    // Common clock enable: advance the whole pipeline only when an input
    // pair is available AND the output can accept (or is empty). Because
    // the latency is fixed, we track an output-valid that is the LAT-deep
    // shifted input-fire; the pipeline stalls (ce=0) when the registered
    // output is valid but downstream is not ready.
    // -----------------------------------------------------------------
    wire in_pair  = s_axis_rx_tvalid & s_axis_h_tvalid;
    wire out_busy;             // a beat is sitting at m_axis waiting
    wire ce;                   // pipeline clock-enable

    // Output holding register (1-deep). It is the only place that can
    // back up; the fixed-latency body cannot absorb backpressure, so we
    // stall the body when the holding reg is full and not draining.
    reg              o_valid;
    reg [OW-1:0]     o_i, o_q;
    reg [TUSERW-1:0] o_user;

    wire             core_ovalid;
    wire signed [OW-1:0] core_i, core_q;
    wire [TUSERW-1:0]    core_user;

    // The body advances when: output reg will be free next cycle
    // (either empty, or being accepted now). This is the standard
    // fixed-latency-with-skid condition.
    assign ce       = (!o_valid) | m_axis_tready;
    assign out_busy = o_valid;

    // a real input transfer (fire) happens only when ce AND both inputs
    assign s_axis_rx_tready = ce & s_axis_h_tvalid;
    assign s_axis_h_tready  = ce & s_axis_rx_tvalid;
    wire   fire = ce & in_pair;

    // -----------------------------------------------------------------
    // divider core, gated by ce. in_valid = fire; the core's own valid
    // pipeline (LAT deep) reproduces the output strobe.
    // -----------------------------------------------------------------
    rx_eq_complex_div #(
        .DW(DW), .HW(HW), .OW(OW), .UW(TUSERW), .LUT_FILE(LUT_FILE)
    ) u_div (
        .clk      (clk),
        .rst_n    (rst_n),
        .ce       (ce),
        .in_valid (fire),
        .rx_i     ($signed(s_axis_rx_tdata[15:0])),
        .rx_q     ($signed(s_axis_rx_tdata[31:16])),
        .h_i      ($signed({{(HW-16){s_axis_h_tdata[15]}},  s_axis_h_tdata[15:0]})),
        .h_q      ($signed({{(HW-16){s_axis_h_tdata[31]}},  s_axis_h_tdata[31:16]})),
        .in_user  (s_axis_rx_tuser),
        .out_valid(core_ovalid),
        .eq_i     (core_i),
        .eq_q     (core_q),
        .out_user (core_user)
    );

    // -----------------------------------------------------------------
    // output holding register
    // -----------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            o_valid <= 1'b0;
            o_i <= {OW{1'b0}}; o_q <= {OW{1'b0}}; o_user <= {TUSERW{1'b0}};
        end else begin
            if (ce) begin
                // when ce, a new core result may land; capture it
                o_valid <= core_ovalid;
                o_i     <= core_i;
                o_q     <= core_q;
                o_user  <= core_user;
            end
            // when !ce (stalled because o_valid && !tready) hold value
        end
    end

    assign m_axis_tvalid = o_valid;
    assign m_axis_tdata  = {o_q, o_i};
    assign m_axis_tuser  = o_user;

endmodule
`default_nettype wire
