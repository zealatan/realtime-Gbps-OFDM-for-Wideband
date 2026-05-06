`timescale 1ns/1ps

// complex_rotator: rotates an IQ sample by exp(-j*theta) using NCO sin/cos.
//
// r_out[n] = r_in[n] * exp(-j theta[n])
//          = (I_in + j*Q_in) * (cos(theta) - j*sin(theta))
//
//   I_out = I_in*cos + Q_in*sin
//   Q_out = Q_in*cos - I_in*sin
//
// Corresponds to apply_carrier_freq_offset() in receiver.c (CFO correction form).
//
// Data convention (project standard):
//   tdata[15:0]  = I (in-phase)
//   tdata[31:16] = Q (quadrature)
//
// sin_in/cos_in connect directly to nco_phase_gen sin_out/cos_out.
// sincos_valid gates the B-side of the internal multiplier.
//
// Internally wraps complex_mult_iq with CONJ_B=1:
//   A × conj(B) where B = (cos + j*sin) implements the (cos - j*sin) correction.

module complex_rotator #(
    parameter integer DATA_WIDTH      = 32,
    parameter integer COMPONENT_WIDTH = 16,
    parameter integer SHIFT           = 15
) (
    input  wire                              aclk,
    input  wire                              aresetn,

    // IQ input stream: {Q[31:16], I[15:0]}
    input  wire [DATA_WIDTH-1:0]             s_axis_iq_tdata,
    input  wire                              s_axis_iq_tvalid,
    output wire                              s_axis_iq_tready,
    input  wire                              s_axis_iq_tlast,

    // NCO sin/cos (connects to nco_phase_gen sin_out/cos_out)
    input  wire signed [COMPONENT_WIDTH-1:0] sin_in,
    input  wire signed [COMPONENT_WIDTH-1:0] cos_in,
    input  wire                              sincos_valid,

    // Rotated IQ output stream: {Q[31:16], I[15:0]}
    output wire [DATA_WIDTH-1:0]             m_axis_tdata,
    output wire                              m_axis_tvalid,
    input  wire                              m_axis_tready,
    output wire                              m_axis_tlast
);
    // Pack NCO phasor as {Q=sin, I=cos} per project convention.
    // CONJ_B=1 in complex_mult_iq negates sin, giving the exp(-j*theta) rotation.
    wire [DATA_WIDTH-1:0] sc_tdata = {sin_in, cos_in};

    complex_mult_iq #(
        .DATA_WIDTH      (DATA_WIDTH),
        .COMPONENT_WIDTH (COMPONENT_WIDTH),
        .SHIFT           (SHIFT),
        .CONJ_A          (0),
        .CONJ_B          (1)
    ) u_mult (
        .aclk            (aclk),
        .aresetn         (aresetn),

        .s_axis_a_tdata  (s_axis_iq_tdata),
        .s_axis_a_tvalid (s_axis_iq_tvalid),
        .s_axis_a_tready (s_axis_iq_tready),
        .s_axis_a_tlast  (s_axis_iq_tlast),

        .s_axis_b_tdata  (sc_tdata),
        .s_axis_b_tvalid (sincos_valid),
        .s_axis_b_tready (),           // NCO has no backpressure input
        .s_axis_b_tlast  (1'b0),

        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast)
    );

endmodule
