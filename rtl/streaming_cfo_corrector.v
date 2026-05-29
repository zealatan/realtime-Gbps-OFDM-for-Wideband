`timescale 1ns/1ps

// streaming_cfo_corrector — P2-06
// Applies fractional CFO correction to an AXI-Stream IQ path.
// Wraps Phase1 frac_cfo_corrector_top (nco_phase_gen + complex_rotator).
//
// Pre-lock behavior: step_word=0 → identity rotation (cos≈1, sin≈0).
// NCO warm-up: 15 cycles of s_ready=0 after aresetn rising edge.
// Re-lock: load_step updates step_word with no phase reset; no dead-time.
//
//
// step_word equation: step_word = sign_ext(frac_phase) <<< 8
//   frac_phase Q1.15: 0x7FFF = +pi → step_word = +frac_phase * 256 (32-bit signed)

module streaming_cfo_corrector #(
    parameter integer SAMPLE_W = 16,
    parameter integer STEP_W   = 32,
    parameter integer PHASE_W  = 16
) (
    input  wire        clk,
    input  wire        aresetn,

    // AXI-Stream IQ input: {Q[31:16], I[15:0]}
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,

    // CFO control
    input  wire        frac_phase_valid,
    input  wire [15:0] frac_phase,

    // AXI-Stream IQ output: {Q[31:16], I[15:0]}
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,

    // Status
    output reg         nco_locked,
    output wire [1:0]  state_dbg     // {sincos_valid, nco_locked}
);

    // Step word: shift left 8; extend sign before shift to avoid truncation.
    // Positive frac_phase (positive CFO) → positive step_word → NCO advances forward
    // → complex_rotator applies exp(-j*theta) with theta>0 → cancels the positive CFO.
    wire signed [31:0] fp_ext      = {{16{frac_phase[15]}}, frac_phase};
    wire signed [31:0] step_word_w = fp_ext <<< 8;

    // nco_locked: asserts on first frac_phase_valid, stays asserted
    always @(posedge clk) begin
        if (!aresetn)
            nco_locked <= 1'b0;
        else if (frac_phase_valid)
            nco_locked <= 1'b1;
    end

    wire sincos_valid_w;
    assign state_dbg = {sincos_valid_w, nco_locked};

    frac_cfo_corrector_top #(
        .DATA_WIDTH          (2 * SAMPLE_W),  // 32
        .COMPONENT_WIDTH     (SAMPLE_W),      // 16
        .SHIFT               (SAMPLE_W - 1),  // 15
        .NCO_PHASE_WIDTH     (STEP_W),        // 32
        .CORDIC_PHASE_WIDTH  (PHASE_W),       // 16
        .ROTATOR_COEFF_WIDTH (SAMPLE_W),      // 16
        .LATENCY             (15)
    ) u_corrector (
        .aclk              (clk),
        .aresetn           (aresetn),
        .load_step         (frac_phase_valid),
        .step_word         (step_word_w),
        .phase_reset       (1'b0),   // accumulate continuously; no dead-time on re-lock
        .enable            (~sincos_valid_w | (s_valid & s_ready)),  // warm-up free-run; fire-gated after
        .s_axis_iq_tdata   (s_data),
        .s_axis_iq_tvalid  (s_valid),
        .s_axis_iq_tready  (s_ready),
        .s_axis_iq_tlast   (1'b0),
        .m_axis_tdata      (m_data),
        .m_axis_tvalid     (m_valid),
        .m_axis_tready     (m_ready),
        .m_axis_tlast      (),
        .phase_acc         (),
        .sin_out           (),
        .cos_out           (),
        .sincos_valid      (sincos_valid_w)
    );

endmodule
