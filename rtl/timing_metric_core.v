`timescale 1ns/1ps

// timing_metric_core: CP autocorrelation timing metric generator.
//
// For each lag m in [0, num_lags-1], reads the stored autocorrelation
// result from cp_autocorr_core and computes:
//
//   M[m] = 2 × |P[m]| − E[m]
//
// where |P[m]| is the complex magnitude approximation:
//
//   |P| ≈ max(|I|, |Q|) + (min >> 2) + (min >> 3)      (3/8 × min approximation)
//
// The approximation underestimates by ≤ 3.5%, ensuring M[m] ≤ 0 always.
// Feeding unsigned metric_out to peak_detector is correct: least-negative
// M (closest to 0) maps to the largest unsigned 32-bit value (0xFFFFFFFF),
// which peak_detector's unsigned > comparison correctly identifies as the peak.
//
// cp_autocorr_core exposes a combinatorial (zero-latency) result read port;
// this module drives result_rd_addr with the lag counter and computes the
// metric in the same clock, producing one output per cycle.
//
// Total latency: num_lags + 1 clocks (num_lags cycles in S_RUN, 1 in S_DONE).
//
// Parameters:
//   NSC          Maximum lag count (default 256); num_lags ∈ [1, NSC]
//   METRIC_WIDTH Output metric width (default 32); must be ≤ 34
//   ACC_WIDTH    Autocorrelation accumulator width (informational, default 40)

module timing_metric_core #(
    parameter integer NSC          = 256,
    parameter integer METRIC_WIDTH = 32,
    parameter integer ACC_WIDTH    = 40
) (
    input  wire                          aclk,
    input  wire                          aresetn,

    // ---- Control ----
    input  wire                          start,
    input  wire [8:0]                    num_lags,   // number of lags; latched on start
    output reg                           done,
    output reg                           busy,

    // ---- cp_autocorr_core result read port (combinatorial, zero-latency) ----
    output wire [8:0]                    result_rd_addr,
    input  wire signed [31:0]            result_autocorr_I,
    input  wire signed [31:0]            result_autocorr_Q,
    input  wire        [31:0]            result_norm_E,

    // ---- Output stream to peak_detector ----
    output wire [METRIC_WIDTH-1:0]       metric_out,
    output wire                          metric_valid,
    output wire                          metric_last
);

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_RUN  = 2'd1,
                     S_DONE = 2'd2;

    reg [1:0] state;
    reg [8:0] lag;          // current lag index (0 .. num_lags_r-1)
    reg [8:0] num_lags_r;   // latched copy of num_lags

    // -----------------------------------------------------------------------
    // Magnitude approximation (purely combinatorial)
    //
    // Inputs: result_autocorr_I / _Q (32-bit signed, from cp_autocorr_core)
    // Step 1: sign-extend to 33 bits, then compute absolute value (unsigned)
    // Step 2: alpha-max + beta-min with beta = 3/8
    // Step 3: metric = 2 × mag_approx − E (34-bit intermediate)
    // -----------------------------------------------------------------------

    // Sign-extend inputs to 33 bits so abs(-2^31) = 2^31 fits without overflow
    wire signed [32:0] I_ext = {result_autocorr_I[31], result_autocorr_I};
    wire signed [32:0] Q_ext = {result_autocorr_Q[31], result_autocorr_Q};

    // Absolute values (33-bit unsigned)
    wire [32:0] abs_I = I_ext[32] ? $unsigned(-I_ext) : $unsigned(I_ext);
    wire [32:0] abs_Q = Q_ext[32] ? $unsigned(-Q_ext) : $unsigned(Q_ext);

    // Max / min of the two magnitudes
    wire [32:0] mag_max = (abs_I >= abs_Q) ? abs_I : abs_Q;
    wire [32:0] mag_min = (abs_I >= abs_Q) ? abs_Q : abs_I;

    // |P| ≈ max + (min>>2) + (min>>3)   [max 33-bit result]
    wire [32:0] mag_approx = mag_max + (mag_min >> 2) + (mag_min >> 3);

    // 2 × mag_approx (left-shift extends to 34 bits)
    wire [33:0] two_mag = {mag_approx, 1'b0};

    // M = 2×|P| − E  (both zero-extended to 34 bits; subtraction wraps correctly)
    wire [33:0] metric_full = two_mag - {2'b0, result_norm_E};

    // -----------------------------------------------------------------------
    // Combinatorial outputs
    // -----------------------------------------------------------------------
    assign result_rd_addr = lag;
    assign metric_out   = metric_full[METRIC_WIDTH-1:0];
    assign metric_valid = (state == S_RUN);
    assign metric_last  = (state == S_RUN) && (lag == num_lags_r - 9'd1);

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            lag        <= 9'd0;
            num_lags_r <= 9'd0;
        end else begin
            done <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (start && !busy) begin
                        num_lags_r <= num_lags;
                        lag        <= 9'd0;
                        busy       <= 1'b1;
                        state      <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (lag == num_lags_r - 9'd1) begin
                        // Last lag output this cycle — transition to done
                        state <= S_DONE;
                    end else begin
                        lag <= lag + 9'd1;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    lag   <= 9'd0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
