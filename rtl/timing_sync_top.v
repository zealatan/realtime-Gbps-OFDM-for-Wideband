`timescale 1ns/1ps

// timing_sync_top: CP-based timing synchronization.
//
// Sequences cp_autocorr_core → timing_metric_core → peak_detector and
// latches the autocorrelation values at the winning lag for downstream
// fractional CFO estimation:
//   frac_cfo = -atan2(peak_corr_q, peak_corr_i) / (2*pi)
//
// FSM: IDLE → AUTOCORR → METRIC → LATCH → DONE
//
// Timing:
//   AUTOCORR: 4*CP_LEN*NSC + 1 cycles
//   METRIC:   NSC cycles (timing_metric_core + peak_detector run concurrently)
//   LATCH:    1 cycle (combinatorial read from cp_autocorr_core result RAM)
//   DONE:     1 cycle (done pulse)
//
// cp_autocorr_core exposes a zero-latency combinatorial result read port.
// During METRIC, timing_metric_core drives result_rd_addr.
// During LATCH, this module drives result_rd_addr = peak_index to capture
// the autocorrelation values at the winning lag.

module timing_sync_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32
) (
    input  wire                              aclk,
    input  wire                              aresetn,

    // Control
    input  wire                              start,
    input  wire [ADDR_WIDTH-1:0]             base_addr,
    output reg                               done,
    output reg                               busy,

    // Buffer read port (pass-through to cp_autocorr_core)
    output wire [ADDR_WIDTH-1:0]             buf_rd_addr,
    output wire                              buf_rd_en,
    input  wire signed [15:0]                buf_rd_data_I,
    input  wire signed [15:0]                buf_rd_data_Q,

    // Results
    output reg  [INDEX_WIDTH-1:0]            peak_lag,
    output reg  [METRIC_WIDTH-1:0]           peak_metric,
    output reg  signed [RESULT_WIDTH-1:0]    peak_corr_i,
    output reg  signed [RESULT_WIDTH-1:0]    peak_corr_q,
    output reg         [RESULT_WIDTH-1:0]    peak_energy
);

    // -----------------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE     = 3'd0,
        S_AUTOCORR = 3'd1,
        S_METRIC   = 3'd2,
        S_LATCH    = 3'd3,
        S_DONE     = 3'd4;

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // Sub-module control / status wires
    // -----------------------------------------------------------------------
    reg                         ac_start_r;
    wire                        ac_done, ac_busy;
    wire [INDEX_WIDTH-1:0]      tmc_result_rd_addr_w;
    wire signed [RESULT_WIDTH-1:0] ac_result_I, ac_result_Q;
    wire        [RESULT_WIDTH-1:0] ac_result_E;

    reg                         tmc_start_r;
    wire                        tmc_done, tmc_busy;
    wire [METRIC_WIDTH-1:0]     tmc_metric_out;
    wire                        tmc_metric_valid, tmc_metric_last;

    reg                         pd_start_r;
    wire                        pd_done, pd_busy;
    wire [INDEX_WIDTH-1:0]      pd_peak_index;
    wire [METRIC_WIDTH-1:0]     pd_peak_value;

    // -----------------------------------------------------------------------
    // result_rd_addr mux: timing_metric_core owns it during METRIC;
    // this module drives peak_index during LATCH to read winning values.
    // -----------------------------------------------------------------------
    wire [INDEX_WIDTH-1:0] result_rd_addr_mux =
        (state == S_LATCH) ? pd_peak_index
                           : tmc_result_rd_addr_w;

    // -----------------------------------------------------------------------
    // cp_autocorr_core
    // -----------------------------------------------------------------------
    cp_autocorr_core #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH)
    ) u_ac (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (ac_start_r),
        .base_addr        (base_addr),
        .done             (ac_done),
        .busy             (ac_busy),
        .buf_rd_addr      (buf_rd_addr),
        .buf_rd_en        (buf_rd_en),
        .buf_rd_data_I    (buf_rd_data_I),
        .buf_rd_data_Q    (buf_rd_data_Q),
        .result_rd_addr   (result_rd_addr_mux),
        .result_autocorr_I(ac_result_I),
        .result_autocorr_Q(ac_result_Q),
        .result_norm_E    (ac_result_E)
    );

    // -----------------------------------------------------------------------
    // timing_metric_core
    // -----------------------------------------------------------------------
    timing_metric_core #(
        .NSC         (NSC),
        .METRIC_WIDTH(METRIC_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH)
    ) u_tmc (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (tmc_start_r),
        .num_lags         (9'(NSC)),
        .done             (tmc_done),
        .busy             (tmc_busy),
        .result_rd_addr   (tmc_result_rd_addr_w),
        .result_autocorr_I(ac_result_I),
        .result_autocorr_Q(ac_result_Q),
        .result_norm_E    (ac_result_E),
        .metric_out       (tmc_metric_out),
        .metric_valid     (tmc_metric_valid),
        .metric_last      (tmc_metric_last)
    );

    // -----------------------------------------------------------------------
    // peak_detector
    // -----------------------------------------------------------------------
    peak_detector #(
        .METRIC_WIDTH(METRIC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .COUNT_WIDTH (10)
    ) u_pd (
        .aclk       (aclk),
        .aresetn    (aresetn),
        .start      (pd_start_r),
        .max_count  (10'(NSC)),
        .data_in    (tmc_metric_out),
        .data_valid (tmc_metric_valid),
        .data_last  (tmc_metric_last),
        .peak_index (pd_peak_index),
        .peak_value (pd_peak_value),
        .done       (pd_done),
        .busy       (pd_busy),
        .error      ()
    );

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            ac_start_r  <= 1'b0;
            tmc_start_r <= 1'b0;
            pd_start_r  <= 1'b0;
            peak_lag    <= {INDEX_WIDTH{1'b0}};
            peak_metric <= {METRIC_WIDTH{1'b0}};
            peak_corr_i <= {RESULT_WIDTH{1'b0}};
            peak_corr_q <= {RESULT_WIDTH{1'b0}};
            peak_energy <= {RESULT_WIDTH{1'b0}};
        end else begin
            // 1-cycle pulse defaults
            done        <= 1'b0;
            ac_start_r  <= 1'b0;
            tmc_start_r <= 1'b0;
            pd_start_r  <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (start && !busy) begin
                        busy       <= 1'b1;
                        ac_start_r <= 1'b1;
                        state      <= S_AUTOCORR;
                    end
                end

                // Wait for cp_autocorr_core to finish all NSC lags.
                S_AUTOCORR: begin
                    if (ac_done) begin
                        tmc_start_r <= 1'b1;
                        pd_start_r  <= 1'b1;
                        state       <= S_METRIC;
                    end
                end

                // timing_metric_core streams metrics to peak_detector.
                // Wait for peak_detector done (fires on data_last accepted).
                S_METRIC: begin
                    if (pd_done) begin
                        peak_lag    <= pd_peak_index;
                        peak_metric <= pd_peak_value;
                        state       <= S_LATCH;
                    end
                end

                // result_rd_addr_mux now drives pd_peak_index into cp_autocorr_core.
                // The combinatorial result read is valid this cycle — latch it.
                S_LATCH: begin
                    peak_corr_i <= ac_result_I;
                    peak_corr_q <= ac_result_Q;
                    peak_energy <= ac_result_E;
                    state       <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
