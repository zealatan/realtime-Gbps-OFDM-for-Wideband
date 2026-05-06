`timescale 1ns/1ps

// nco_phase_gen: 32-bit NCO phase accumulator with behavioral sin/cos pipeline.
//
// Operation:
//   - load_step=1: latch step_word into step_word_r on the next rising edge.
//   - phase_reset=1: synchronously clear phase_acc_r to 0 (takes priority over enable).
//   - enable=1 (and !phase_reset): phase_acc_r += step_word_r each clock.
//
// The 16 MSBs of phase_acc_r are fed to an internal LATENCY-stage behavioral
// sin/cos pipeline (models Xilinx CORDIC IP v6.0 rotate mode).
// Phase encoding: 0x7FFF = +π (Q1.15 radians).
//
// sincos_valid follows enable by exactly LATENCY clocks; asserts only for cycles
// where enable=1 and phase_reset=0.
//
// Synthesis target: replace inline behavioral pipeline with cordic_v6_0 IP.

module nco_phase_gen #(
    parameter integer NCO_PHASE_WIDTH     = 32,
    parameter integer CORDIC_PHASE_WIDTH  = 16,
    parameter integer ROTATOR_COEFF_WIDTH = 16,
    parameter integer LATENCY             = 15
) (
    input  wire                                       aclk,
    input  wire                                       aresetn,

    // Control
    input  wire                                       load_step,
    input  wire signed [NCO_PHASE_WIDTH-1:0]          step_word,
    input  wire                                       phase_reset,
    input  wire                                       enable,

    // Outputs
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]      sin_out,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]      cos_out,
    output wire                                       sincos_valid,
    output wire        [NCO_PHASE_WIDTH-1:0]          phase_acc
);

    // -----------------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------------
    reg [NCO_PHASE_WIDTH-1:0]     step_word_r;
    reg [NCO_PHASE_WIDTH-1:0]     phase_acc_r;

    // LATENCY-stage sin/cos pipeline
    reg [ROTATOR_COEFF_WIDTH-1:0] sin_pipe   [0:LATENCY-1];
    reg [ROTATOR_COEFF_WIDTH-1:0] cos_pipe   [0:LATENCY-1];
    reg                           valid_pipe  [0:LATENCY-1];
    reg [ROTATOR_COEFF_WIDTH-1:0] sin_out_r;
    reg [ROTATOR_COEFF_WIDTH-1:0] cos_out_r;
    reg                           sincos_valid_r;

    // -----------------------------------------------------------------------
    // Combinatorial sin/cos from current (pre-accumulation) phase
    // Simulation only — synthesis replaces this block with Xilinx CORDIC IP.
    // -----------------------------------------------------------------------
    wire signed [CORDIC_PHASE_WIDTH-1:0] cordic_in;
    assign cordic_in = phase_acc_r[NCO_PHASE_WIDTH-1 -: CORDIC_PHASE_WIDTH];

    real    r_ph, r_sin_v, r_cos_v;
    integer sin_int_v, cos_int_v;
    reg [ROTATOR_COEFF_WIDTH-1:0] sin_comb, cos_comb;

    always @(*) begin
        r_ph      = $itor($signed(cordic_in)) /
                    ((1 << (CORDIC_PHASE_WIDTH-1)) - 1.0) *
                    3.14159265358979323846;
        r_sin_v   = $sin(r_ph);
        r_cos_v   = $cos(r_ph);
        sin_int_v = $rtoi(r_sin_v * ((1 << (ROTATOR_COEFF_WIDTH-1)) - 1));
        cos_int_v = $rtoi(r_cos_v * ((1 << (ROTATOR_COEFF_WIDTH-1)) - 1));
        sin_comb  = sin_int_v[ROTATOR_COEFF_WIDTH-1:0];
        cos_comb  = cos_int_v[ROTATOR_COEFF_WIDTH-1:0];
    end

    // -----------------------------------------------------------------------
    // Output assignments
    // -----------------------------------------------------------------------
    assign phase_acc    = phase_acc_r;
    assign sin_out      = sin_out_r;
    assign cos_out      = cos_out_r;
    assign sincos_valid = sincos_valid_r;

    // -----------------------------------------------------------------------
    // Sequential logic
    // -----------------------------------------------------------------------
    integer k;
    always @(posedge aclk) begin
        if (!aresetn) begin
            step_word_r    <= {NCO_PHASE_WIDTH{1'b0}};
            phase_acc_r    <= {NCO_PHASE_WIDTH{1'b0}};
            sin_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
            cos_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
            sincos_valid_r <= 1'b0;
            for (k = 0; k < LATENCY; k = k + 1) begin
                sin_pipe  [k] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                cos_pipe  [k] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                valid_pipe[k] <= 1'b0;
            end
        end else begin
            // Step word latch
            if (load_step)
                step_word_r <= step_word;

            // Phase accumulator (phase_reset beats enable)
            if (phase_reset)
                phase_acc_r <= {NCO_PHASE_WIDTH{1'b0}};
            else if (enable)
                phase_acc_r <= phase_acc_r + step_word_r;

            // sin/cos pipeline (captures PRE-accumulation phase; invalid on phase_reset)
            sin_pipe  [0] <= sin_comb;
            cos_pipe  [0] <= cos_comb;
            valid_pipe[0] <= enable && !phase_reset;
            for (k = 1; k < LATENCY; k = k + 1) begin
                sin_pipe  [k] <= sin_pipe  [k-1];
                cos_pipe  [k] <= cos_pipe  [k-1];
                valid_pipe[k] <= valid_pipe[k-1];
            end
            sin_out_r      <= sin_pipe  [LATENCY-1];
            cos_out_r      <= cos_pipe  [LATENCY-1];
            sincos_valid_r <= valid_pipe[LATENCY-1];
        end
    end

endmodule
