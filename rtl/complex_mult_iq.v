`timescale 1ns/1ps

// complex_mult_iq: AXI-Stream complex multiplier using the project's I/Q packing.
//
// Project convention (both input and output):
//   tdata[15:0]  = I (in-phase  / real part)
//   tdata[31:16] = Q (quadrature / imaginary part)
//
// axis_complex_mult.v convention:
//   tdata[31:16] = real
//   tdata[15:0]  = imaginary
//
// This wrapper swaps the upper and lower halves on both inputs before passing to
// axis_complex_mult, and swaps the output back.  The swap is pure wire rewiring
// (zero LUTs).
//
// Standard complex product: (I_a + j*Q_a) × (I_b + j*Q_b)
//   I_out = I_a*I_b − Q_a*Q_b
//   Q_out = I_a*Q_b + Q_a*I_b
//
// If CONJ_A=1: computes conj(A) × B  (negates Q_a before multiplying)
//   I_out = I_a*I_b + Q_a*Q_b
//   Q_out = I_a*Q_b − Q_a*I_b
//
// If CONJ_B=1: computes A × conj(B)  (negates Q_b before multiplying)
//   I_out = I_a*I_b + Q_a*Q_b
//   Q_out = Q_a*I_b − I_a*Q_b
//
// Note: CONJ_A is used by cp_autocorr_core (conj(rx[m+k]) × rx[m+k+NSC]).
//       CONJ_B is provided symmetrically for completeness.
//
// All AXI-Stream handshake signals (tvalid, tready, tlast) pass through unchanged.
//
// Parameters:
//   DATA_WIDTH        Full TDATA width (must equal 2*COMPONENT_WIDTH, default 32)
//   COMPONENT_WIDTH   Width of each I or Q word (default 16)
//   SHIFT             Right-shift for Q1.15 output (default 15)
//   CONJ_A            0 = normal, 1 = conjugate A input (negates Q_a)
//   CONJ_B            0 = normal, 1 = conjugate B input (negates Q_b)

module complex_mult_iq #(
    parameter integer DATA_WIDTH      = 32,
    parameter integer COMPONENT_WIDTH = 16,
    parameter integer SHIFT           = 15,
    parameter integer CONJ_A          = 0,
    parameter integer CONJ_B          = 0
) (
    input  wire                     aclk,
    input  wire                     aresetn,

    // Input A: {Q_a[31:16], I_a[15:0]}
    input  wire [DATA_WIDTH-1:0]    s_axis_a_tdata,
    input  wire                     s_axis_a_tvalid,
    output wire                     s_axis_a_tready,
    input  wire                     s_axis_a_tlast,

    // Input B: {Q_b[31:16], I_b[15:0]}
    input  wire [DATA_WIDTH-1:0]    s_axis_b_tdata,
    input  wire                     s_axis_b_tvalid,
    output wire                     s_axis_b_tready,
    input  wire                     s_axis_b_tlast,

    // Output: {Q_out[31:16], I_out[15:0]}
    output wire [DATA_WIDTH-1:0]    m_axis_tdata,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast
);
    localparam CW = COMPONENT_WIDTH;

    // -----------------------------------------------------------------------
    // Input A reordering: {Q_a, I_a} → {I_a, Q_a_eff} for axis_complex_mult
    //   axis_complex_mult treats upper half as real, lower as imaginary.
    //   We put I in the upper (real) slot and Q in the lower (imaginary) slot.
    //   If CONJ_A=1, negate Q_a (= a_tdata[31:16]) to form conj(A).
    // -----------------------------------------------------------------------
    wire [CW-1:0] a_q_in = s_axis_a_tdata[DATA_WIDTH-1 : CW];  // Q_a (upper in ours)
    wire [CW-1:0] a_i_in = s_axis_a_tdata[CW-1         : 0];   // I_a (lower in ours)

    wire [CW-1:0] a_q_eff;
    generate
        if (CONJ_A == 1) begin : gen_conj_a
            assign a_q_eff = ~a_q_in + 1'b1;   // two's-complement negate Q_a
        end else begin : gen_no_conj_a
            assign a_q_eff = a_q_in;
        end
    endgenerate

    // Feed axis_complex_mult: upper=I_a (real), lower=Q_a_eff (imag)
    wire [DATA_WIDTH-1:0] a_reordered = {a_i_in, a_q_eff};

    // -----------------------------------------------------------------------
    // Input B reordering: {Q_b, I_b} → {I_b, Q_b_eff}
    // -----------------------------------------------------------------------
    wire [CW-1:0] b_q_in = s_axis_b_tdata[DATA_WIDTH-1 : CW];
    wire [CW-1:0] b_i_in = s_axis_b_tdata[CW-1         : 0];

    wire [CW-1:0] b_q_eff;
    generate
        if (CONJ_B == 1) begin : gen_conj_b
            assign b_q_eff = ~b_q_in + 1'b1;
        end else begin : gen_no_conj_b
            assign b_q_eff = b_q_in;
        end
    endgenerate

    wire [DATA_WIDTH-1:0] b_reordered = {b_i_in, b_q_eff};

    // -----------------------------------------------------------------------
    // axis_complex_mult core
    //   Produces: m_axis_tdata = {I_out[31:16], Q_out[15:0]}  (its convention)
    // -----------------------------------------------------------------------
    wire [DATA_WIDTH-1:0] mult_out;
    wire                  mult_valid;
    wire                  mult_tlast;

    axis_complex_mult #(
        .DATA_WIDTH      (DATA_WIDTH),
        .COMPONENT_WIDTH (CW),
        .SHIFT           (SHIFT)
    ) core (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_a_tdata  (a_reordered),
        .s_axis_a_tvalid (s_axis_a_tvalid),
        .s_axis_a_tready (s_axis_a_tready),
        .s_axis_a_tlast  (s_axis_a_tlast),
        .s_axis_b_tdata  (b_reordered),
        .s_axis_b_tvalid (s_axis_b_tvalid),
        .s_axis_b_tready (s_axis_b_tready),
        .s_axis_b_tlast  (s_axis_b_tlast),
        .m_axis_tdata    (mult_out),
        .m_axis_tvalid   (mult_valid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (mult_tlast)
    );

    // -----------------------------------------------------------------------
    // Output: swap back to {Q_out[31:16], I_out[15:0]}
    //   mult_out[31:16] = I_out (real, axis convention)
    //   mult_out[15:0]  = Q_out (imag, axis convention)
    //   → our convention: {Q_out, I_out}
    // -----------------------------------------------------------------------
    assign m_axis_tdata  = {mult_out[CW-1:0], mult_out[DATA_WIDTH-1:CW]};
    assign m_axis_tvalid = mult_valid;
    assign m_axis_tlast  = mult_tlast;

endmodule
