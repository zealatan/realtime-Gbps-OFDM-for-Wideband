`timescale 1ns/1ps

// meyr_integer_cfo_fft_frontend_top — P3-25A production restore
//
// Connects the FFT256 dual-symbol frontend to the Meyr frequency-domain
// integer CFO estimator.  Accepts time-domain PSS/SSS samples, routes them
// through fft256_dual_symbol_frontend (which computes the real 256-pt FFT
// via fft256_xilinx_wrapper), buffers PSS FFT bins, pairs each SSS bin
// with the buffered PSS bin at the same index, then feeds all NSC pairs
// to the Meyr estimator.
//
// USE_BEHAVIORAL_STUB controls fft256_xilinx_wrapper mode:
//   0 — production: real Xilinx xfft_v9_1 IP (synthesis / xsim)
//   3 — behavioral exact 256-pt DFT (iverilog simulation)
// Default is 3 for iverilog compatibility; Vivado synthesis must override to 0.
//
// FLUSH_COUNT=1: discard one FFT output frame before capture to drain the
// Xilinx IP pipeline residue.  For behavioral DFT (mode 3), this adds extra
// simulation cycles with no functional impact.
//
// Hierarchy (frozen):
//   meyr_integer_cfo_fft_frontend_top
//   ├─ fft256_dual_symbol_frontend
//   │   └─ fft256_xilinx_wrapper
//   └─ meyr_integer_cfo_freq_estimator_top
//       ├─ meyr_pss_sss_product_gen
//       └─ meyr_integer_cfo_core
//           └─ peak_detector
//
// Protocol:
//   1. Pulse start=1.
//   2. Stream FFT_LEN PSS samples (s_symbol_sel=0, s_index=0..FFT_LEN-1).
//   3. Stream FFT_LEN SSS samples (s_symbol_sel=1, s_index=0..FFT_LEN-1).
//   4. Wait for done pulse; read int_cfo/peak_index/peak_score.
//
// Verified (via meyr_fft256_actual_integration_top, same FFT/estimator path):
//   SANITY_GATE: PASS (behavioral DFT, iverilog) — P3-13B
//   OFFICIAL_GATE: PASS (real Xilinx IP, xsim)   — P3-13C

module meyr_integer_cfo_fft_frontend_top #(
    parameter integer FFT_LEN             = 256,
    parameter integer IQ_WIDTH            = 16,
    parameter integer PROD_WIDTH          = 32,
    parameter integer ACC_WIDTH           = 56,
    parameter integer SCORE_WIDTH         = 64,
    parameter integer INDEX_WIDTH         = 9,
    // FFT wrapper mode: 0=production Xilinx IP, 3=behavioral DFT (iverilog)
    parameter integer USE_BEHAVIORAL_STUB = 3,
    parameter integer FLUSH_COUNT         = 1,
    parameter integer WATCHDOG_CYCLES     = 2047
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    // Time-domain PSS/SSS input stream (passed to FFT frontend)
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    output wire                         busy,
    output wire                         done,
    output wire                         error,

    output wire signed [15:0]           int_cfo,
    output wire [INDEX_WIDTH-1:0]       peak_index,
    output wire [SCORE_WIDTH-1:0]       peak_score
);

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_FILL_PSS   = 3'd1,
        S_START_EST  = 3'd2,
        S_STREAM_SSS = 3'd3,
        S_WAIT_EST   = 3'd4,
        S_DONE       = 3'd5;

    reg [2:0] state;
    reg busy_r, done_r, error_r;
    reg [8:0] pss_fill_cnt;
    reg [8:0] sss_cnt;

    // PSS FFT bin buffer — filled as frontend streams PSS FFT output
    reg signed [IQ_WIDTH-1:0] pss_fft_buf_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] pss_fft_buf_q [0:FFT_LEN-1];

    assign busy  = busy_r;
    assign done  = done_r;
    assign error = error_r;

    // -------------------------------------------------------------------------
    // FFT frontend instance
    // -------------------------------------------------------------------------
    reg  fft_start_r;
    wire fft_m_valid, fft_m_symbol_sel;
    wire [7:0]                  fft_m_index;
    wire signed [IQ_WIDTH-1:0]  fft_m_i, fft_m_q;
    wire fft_busy, fft_done, fft_error;
    reg  fft_m_ready_r;

    fft256_dual_symbol_frontend #(
        .FFT_LEN             (FFT_LEN),
        .IQ_WIDTH            (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB),
        .FLUSH_COUNT         (FLUSH_COUNT),
        .WATCHDOG_CYCLES     (WATCHDOG_CYCLES)
    ) u_fft (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (fft_start_r),
        .s_valid     (s_valid),
        .s_ready     (s_ready),
        .s_symbol_sel(s_symbol_sel),
        .s_index     (s_index),
        .s_i         (s_i),
        .s_q         (s_q),
        .m_valid     (fft_m_valid),
        .m_ready     (fft_m_ready_r),
        .m_symbol_sel(fft_m_symbol_sel),
        .m_index     (fft_m_index),
        .m_i         (fft_m_i),
        .m_q         (fft_m_q),
        .busy        (fft_busy),
        .done        (fft_done),
        .error       (fft_error)
    );

    // -------------------------------------------------------------------------
    // Estimator instance
    // -------------------------------------------------------------------------
    reg  est_start_r;
    wire est_s_ready;
    wire est_busy, est_done, est_error;
    wire signed [15:0]          est_int_cfo;
    wire [INDEX_WIDTH-1:0]      est_peak_index;
    wire [SCORE_WIDTH-1:0]      est_peak_score;

    // Pair buffered PSS bin with current SSS bin; valid only in S_STREAM_SSS
    wire est_s_valid = (state == S_STREAM_SSS) &&
                       fft_m_valid && (fft_m_symbol_sel == 1'b1);

    meyr_integer_cfo_freq_estimator_top #(
        .NSC        (FFT_LEN),
        .IQ_WIDTH   (IQ_WIDTH),
        .PROD_WIDTH (PROD_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SCORE_WIDTH(SCORE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_est (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .start     (est_start_r),
        .s_valid   (est_s_valid),
        .s_ready   (est_s_ready),
        .s_index   (fft_m_index),
        .pss_i     (pss_fft_buf_i[fft_m_index]),
        .pss_q     (pss_fft_buf_q[fft_m_index]),
        .sss_i     (fft_m_i),
        .sss_q     (fft_m_q),
        .busy      (est_busy),
        .done      (est_done),
        .error     (est_error),
        .int_cfo   (est_int_cfo),
        .peak_index(est_peak_index),
        .peak_score(est_peak_score)
    );

    // Output capture registers
    reg signed [15:0]     int_cfo_r;
    reg [INDEX_WIDTH-1:0] peak_index_r;
    reg [SCORE_WIDTH-1:0] peak_score_r;
    assign int_cfo    = int_cfo_r;
    assign peak_index = peak_index_r;
    assign peak_score = peak_score_r;

    // -------------------------------------------------------------------------
    // fft_m_ready combinatorial:
    //   S_FILL_PSS:   accept PSS bins; stall SSS bins
    //   S_STREAM_SSS: gate by estimator s_ready (backpressure)
    //   others:       0
    // -------------------------------------------------------------------------
    always @(*) begin
        case (state)
            S_FILL_PSS:   fft_m_ready_r = !fft_m_symbol_sel || !fft_m_valid;
            S_STREAM_SSS: fft_m_ready_r = est_s_ready;
            default:      fft_m_ready_r = 1'b0;
        endcase
    end

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            busy_r       <= 1'b0;
            done_r       <= 1'b0;
            error_r      <= 1'b0;
            pss_fill_cnt <= 9'd0;
            sss_cnt      <= 9'd0;
            fft_start_r  <= 1'b0;
            est_start_r  <= 1'b0;
            int_cfo_r    <= 16'sd0;
            peak_index_r <= {INDEX_WIDTH{1'b0}};
            peak_score_r <= {SCORE_WIDTH{1'b0}};
        end else begin
            done_r      <= 1'b0;
            fft_start_r <= 1'b0;
            est_start_r <= 1'b0;

            if (start && busy_r) begin
                error_r <= 1'b1;
                // synthesis translate_off
                $display("[TOP_ERR] start_while_busy t=%0t state=%0d", $time, state);
                // synthesis translate_on
            end
            if (fft_error && !error_r) begin
                error_r <= 1'b1;
                // synthesis translate_off
                $display("[TOP_ERR] fft_error first set t=%0t state=%0d", $time, state);
                // synthesis translate_on
            end
            if (est_error && !error_r) begin
                error_r <= 1'b1;
                // synthesis translate_off
                $display("[TOP_ERR] est_error first set t=%0t state=%0d", $time, state);
                // synthesis translate_on
            end

            case (state)

                // ---------------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy_r) begin
                        busy_r       <= 1'b1;
                        pss_fill_cnt <= 9'd0;
                        sss_cnt      <= 9'd0;
                        fft_start_r  <= 1'b1;
                        state        <= S_FILL_PSS;
                    end
                end

                // ---------------------------------------------------------------
                // Receive PSS FFT bins from frontend output.
                // fft_m_ready stalls SSS bins until all PSS bins are buffered.
                // Transition when FFT_LEN PSS bins have been received.
                // ---------------------------------------------------------------
                S_FILL_PSS: begin
                    if (fft_m_valid && !fft_m_symbol_sel) begin
                        pss_fft_buf_i[fft_m_index] <= fft_m_i;
                        pss_fft_buf_q[fft_m_index] <= fft_m_q;
                        if (pss_fill_cnt < FFT_LEN)
                            pss_fill_cnt <= pss_fill_cnt + 9'd1;
                    end
                    if (pss_fill_cnt == FFT_LEN)
                        state <= S_START_EST;
                end

                // ---------------------------------------------------------------
                // Pulse estimator start; estimator enters S_RECV next clock.
                // ---------------------------------------------------------------
                S_START_EST: begin
                    est_start_r <= 1'b1;
                    state       <= S_STREAM_SSS;
                end

                // ---------------------------------------------------------------
                // Pair each SSS bin with the buffered PSS bin at the same index
                // and feed to the estimator.
                // ---------------------------------------------------------------
                S_STREAM_SSS: begin
                    if (est_s_valid && est_s_ready) begin
                        if (sss_cnt < FFT_LEN)
                            sss_cnt <= sss_cnt + 9'd1;
                    end
                    if (sss_cnt == FFT_LEN)
                        state <= S_WAIT_EST;
                end

                // ---------------------------------------------------------------
                S_WAIT_EST: begin
                    if (est_done) begin
                        int_cfo_r    <= est_int_cfo;
                        peak_index_r <= est_peak_index;
                        peak_score_r <= est_peak_score;
                        state        <= S_DONE;
                    end
                end

                // ---------------------------------------------------------------
                S_DONE: begin
                    done_r <= 1'b1;
                    busy_r <= 1'b0;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
