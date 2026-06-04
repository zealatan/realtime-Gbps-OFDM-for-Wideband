`timescale 1ns/1ps

// timing_frac_cfo_top: CP timing synchronization + fractional CFO estimation.
//
// Sequences:
//   1. timing_sync_top  (autocorr → metric → peak detection → corr latch)
//   2. frac_cfo_estimator  (CORDIC atan2 of peak autocorrelation phasor)
//
// C reference (inside synchronization()):
//   peakIndexAuto = VanDeBeekAutoCorrelation(...);
//   fracfreqOffset = -atan2(autoCorrOutQ[peakIndexAuto],
//                           autoCorrOutI[peakIndexAuto]) / (2 * PI);
//
// cp_autocorr_core is internal to timing_sync_top.  After timing_sync_top.done,
// the peak autocorrelation values are stable in its peak_corr_i/q outputs.
// These latched values are fed directly to frac_cfo_estimator as autocorr_I/Q,
// eliminating the need to re-access cp_autocorr_core's RAM.
// frac_cfo_estimator's result_rd_addr output is left unconnected.
//
// frac_phase is the raw atan2 output (Q1.15-encoded radians, range ±π).
// The NCO step word for CFO correction is computed externally:
//   step = round(-frac_phase × 2^32 / (2π))
//
// FSM: IDLE → TIMING → FRAC_CFO → DONE
//
// Latency (defaults, NSC=256, CP_LEN=32):
//   TIMING:   ~32,789 cycles  (cp_autocorr + metric + peak)
//   FRAC_CFO: 17 cycles       (frac_cfo_estimator, CORDIC_LATENCY=15)
//   DONE:     1 cycle

module timing_frac_cfo_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32,
    parameter integer PHASE_WIDTH  = 16
) (
    input  wire                              aclk,
    input  wire                              aresetn,

    // Control
    input  wire                              start,
    input  wire [ADDR_WIDTH-1:0]             base_addr,
    output reg                               done,
    output reg                               busy,

    // Buffer read port (pass-through to cp_autocorr_core inside timing_sync_top)
    output wire [ADDR_WIDTH-1:0]             buf_rd_addr,
    output wire                              buf_rd_en,
    input  wire signed [15:0]                buf_rd_data_I,
    input  wire signed [15:0]                buf_rd_data_Q,

    // Timing synchronization outputs (registered, stable after done)
    output wire [INDEX_WIDTH-1:0]            peak_lag,
    output wire [METRIC_WIDTH-1:0]           peak_metric,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_i,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_q,
    output wire        [RESULT_WIDTH-1:0]    peak_energy,

    // Fractional CFO output (registered in frac_cfo_estimator, stable after done)
    output wire [PHASE_WIDTH-1:0]            frac_phase,
    output wire                              frac_phase_valid
);

    localparam [1:0]
        S_IDLE     = 2'd0,
        S_TIMING   = 2'd1,
        S_FRAC_CFO = 2'd2,
        S_DONE     = 2'd3;

    reg [1:0] state;

    // -----------------------------------------------------------------------
    // timing_sync_top
    // -----------------------------------------------------------------------
    reg  tst_start_r;
    wire tst_done;

    timing_sync_top #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .METRIC_WIDTH(METRIC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH)
    ) u_tst (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .start         (tst_start_r),
        .base_addr     (base_addr),
        .done          (tst_done),
        .busy          (),
        .buf_rd_addr   (buf_rd_addr),
        .buf_rd_en     (buf_rd_en),
        .buf_rd_data_I (buf_rd_data_I),
        .buf_rd_data_Q (buf_rd_data_Q),
        .peak_lag      (peak_lag),
        .peak_metric   (peak_metric),
        .peak_corr_i   (peak_corr_i),
        .peak_corr_q   (peak_corr_q),
        .peak_energy   (peak_energy)
    );

    // -----------------------------------------------------------------------
    // frac_cfo_estimator
    //
    // autocorr_I/Q are driven by timing_sync_top's latched peak_corr_i/q.
    // peak_lag is forwarded directly; it is latched by frac_cfo_estimator
    // on its start pulse.  result_rd_addr is left open (NC).
    // -----------------------------------------------------------------------
    reg  fce_start_r;
    wire fce_done;

    frac_cfo_estimator #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) u_fce (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (fce_start_r),
        .peak_lag         (peak_lag),
        .result_rd_addr   (),
        .autocorr_I       (peak_corr_i),
        .autocorr_Q       (peak_corr_q),
        .frac_phase       (frac_phase),
        .frac_phase_valid (frac_phase_valid),
        .done             (fce_done),
        .busy             ()
    );

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            tst_start_r <= 1'b0;
            fce_start_r <= 1'b0;
        end else begin
            done        <= 1'b0;
            tst_start_r <= 1'b0;
            fce_start_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (start && !busy) begin
                        busy        <= 1'b1;
                        tst_start_r <= 1'b1;
                        state       <= S_TIMING;
                    end
                end

                // Wait for timing_sync_top to complete autocorr + metric + peak latch.
                S_TIMING: begin
                    if (tst_done) begin
                        fce_start_r <= 1'b1;
                        state       <= S_FRAC_CFO;
                    end
                end

                // Wait for CORDIC atan2 pipeline to drain.
                S_FRAC_CFO: begin
                    if (fce_done) begin
                        state <= S_DONE;
                    end
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
