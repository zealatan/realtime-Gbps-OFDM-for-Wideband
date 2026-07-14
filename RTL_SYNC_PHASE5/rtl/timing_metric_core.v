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
    // Exact squared metric (purely combinatorial)
    //
    // cp_autocorr_core stores P_I, P_Q, E all as upper 32 bits (>> 8) of 40-bit accumulators.
    // Squared comparison: sq_neg = E_s² − 4×(P_I_s² + P_Q_s²) ≥ 0  (Cauchy-Schwarz).
    // Peak at the lag with smallest sq_neg (closest to 0 = best CP correlation).
    // metric_out = ~(sq_neg >> 27): inverts so peak_detector MAX finds the minimum sq_neg.
    // Avoids magnitude approximation errors that flip the ordering at small correlation angles.
    // -----------------------------------------------------------------------

    // Sign-extend P inputs to 33 bits; compute absolute values (33-bit unsigned)
    wire signed [32:0] I_ext = {result_autocorr_I[31], result_autocorr_I};
    wire signed [32:0] Q_ext = {result_autocorr_Q[31], result_autocorr_Q};
    wire [32:0] abs_I = I_ext[32] ? $unsigned(-I_ext) : $unsigned(I_ext);
    wire [32:0] abs_Q = Q_ext[32] ? $unsigned(-Q_ext) : $unsigned(Q_ext);

    // Squared |P|²: 33×33 → 66-bit unsigned products
    wire [65:0] sq_I = abs_I * abs_I;
    wire [65:0] sq_Q = abs_Q * abs_Q;

    // E² (32×32 → 64-bit unsigned; result_norm_E = E>>8)
    wire [63:0] sq_E = result_norm_E * result_norm_E;

    // sq_neg = E_s² − 4×|P_s|² ≥ 0  (68-bit, always non-negative by Cauchy-Schwarz)
    // E_s max = 2^29 → sq_E max = 2^58; |P_s| max = 2^23 → 4×(sq_I+sq_Q) max = 2^49.
    wire [67:0] sq_neg = {4'b0, sq_E} - {sq_I + sq_Q, 2'b00};

    // -----------------------------------------------------------------------
    // Combinatorial outputs
    // -----------------------------------------------------------------------
    assign result_rd_addr = lag;
    // Scale sq_neg to 32 bits by taking bits [58:27] (÷ 2^27); invert for MAX peak detection.
    // Correct lag: sq_neg ≈ 0 → metric_out ≈ 0xFFFFFFFF. Wrong lags: smaller metric_out.
    assign metric_out = ~sq_neg[58:27];
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
