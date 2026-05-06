`timescale 1ns/1ps

// frac_cfo_corrector_top: integrates nco_phase_gen + complex_rotator.
//
// Programs the NCO with a pre-computed step word (step = round(-frac_phase × 2^32 / 2π))
// and rotates each IQ sample by exp(-j*theta[n]).
//
// Caller must:
//   1. Assert load_step with the desired step_word for 1 cycle.
//   2. Assert phase_reset for 1 cycle to clear the phase accumulator.
//   3. Assert enable.  sincos_valid goes high exactly LATENCY clocks later.
//   4. Begin sending IQ samples only after sincos_valid is high.

module frac_cfo_corrector_top #(
    parameter integer DATA_WIDTH          = 32,
    parameter integer COMPONENT_WIDTH     = 16,
    parameter integer SHIFT               = 15,
    parameter integer NCO_PHASE_WIDTH     = 32,
    parameter integer CORDIC_PHASE_WIDTH  = 16,
    parameter integer ROTATOR_COEFF_WIDTH = 16,
    parameter integer LATENCY             = 15
) (
    input  wire                                      aclk,
    input  wire                                      aresetn,

    // NCO control
    input  wire                                      load_step,
    input  wire signed [NCO_PHASE_WIDTH-1:0]         step_word,
    input  wire                                      phase_reset,
    input  wire                                      enable,

    // IQ input stream: {Q[31:16], I[15:0]}
    input  wire [DATA_WIDTH-1:0]                     s_axis_iq_tdata,
    input  wire                                      s_axis_iq_tvalid,
    output wire                                      s_axis_iq_tready,
    input  wire                                      s_axis_iq_tlast,

    // Rotated IQ output stream: {Q[31:16], I[15:0]}
    output wire [DATA_WIDTH-1:0]                     m_axis_tdata,
    output wire                                      m_axis_tvalid,
    input  wire                                      m_axis_tready,
    output wire                                      m_axis_tlast,

    // Debug / monitoring
    output wire [NCO_PHASE_WIDTH-1:0]                phase_acc,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     sin_out,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     cos_out,
    output wire                                      sincos_valid
);

    nco_phase_gen #(
        .NCO_PHASE_WIDTH     (NCO_PHASE_WIDTH),
        .CORDIC_PHASE_WIDTH  (CORDIC_PHASE_WIDTH),
        .ROTATOR_COEFF_WIDTH (ROTATOR_COEFF_WIDTH),
        .LATENCY             (LATENCY)
    ) u_nco (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .load_step   (load_step),
        .step_word   (step_word),
        .phase_reset (phase_reset),
        .enable      (enable),
        .sin_out     (sin_out),
        .cos_out     (cos_out),
        .sincos_valid(sincos_valid),
        .phase_acc   (phase_acc)
    );

    complex_rotator #(
        .DATA_WIDTH      (DATA_WIDTH),
        .COMPONENT_WIDTH (COMPONENT_WIDTH),
        .SHIFT           (SHIFT)
    ) u_rot (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_iq_tdata (s_axis_iq_tdata),
        .s_axis_iq_tvalid(s_axis_iq_tvalid),
        .s_axis_iq_tready(s_axis_iq_tready),
        .s_axis_iq_tlast (s_axis_iq_tlast),
        .sin_in          (sin_out),
        .cos_in          (cos_out),
        .sincos_valid    (sincos_valid),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast)
    );

endmodule
