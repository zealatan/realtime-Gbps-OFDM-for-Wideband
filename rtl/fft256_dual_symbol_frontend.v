`timescale 1ns/1ps

// fft256_dual_symbol_frontend — P3-25A production restore
//
// Accepts PSS (symbol_sel=0) then SSS (symbol_sel=1) time-domain samples,
// runs each symbol through fft256_xilinx_wrapper, captures the 256 output
// bins, then streams PSS FFT bins (m_symbol_sel=0) followed by SSS FFT
// bins (m_symbol_sel=1) to the downstream Meyr estimator.
//
// USE_BEHAVIORAL_STUB controls fft256_xilinx_wrapper mode:
//   0 — production: real Xilinx xfft_v9_1 IP (Vivado synthesis + xsim)
//   1 — passthrough stub (compile-only, NOT an FFT)
//   2 — sequential-output stub (hardening tests)
//   3 — behavioral exact 256-pt DFT (iverilog simulation; real arithmetic)
//
// For iverilog-based simulation (sessions E/D/K), the default of 3 enables
// the exact behavioral DFT without requiring the Xilinx IP.  For production
// synthesis and xsim validation, the Vivado instantiation must override
// USE_BEHAVIORAL_STUB=0 to bind the real IP.
//
// FLUSH_COUNT (default 1): discard N FFT output frames before capture to
// drain Xilinx IP pipeline residue.  For USE_BEHAVIORAL_STUB=3 this adds
// extra simulation cycles but produces the same correct result.
//
// Ported from meyr_fft256_actual_integration_top (Session P3-13B/C verified).
// External interface preserved from Step-34 fft256_dual_symbol_frontend.
// Verified: OFFICIAL_GATE PASS — P3-13C, all 9 k_int sweep cases (xsim).

module fft256_dual_symbol_frontend #(
    parameter integer FFT_LEN             = 256,
    parameter integer IQ_WIDTH            = 16,
    parameter integer USE_BEHAVIORAL_STUB = 3,
    parameter integer FLUSH_COUNT         = 1,
    parameter integer WATCHDOG_CYCLES     = 2047
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    // Time-domain input stream
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,   // 0=PSS  1=SSS
    input  wire [7:0]                   s_index,        // sample index (informational)
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    // Frequency-domain output stream
    output reg                          m_valid,
    input  wire                         m_ready,
    output reg                          m_symbol_sel,   // 0=PSS_FFT  1=SSS_FFT
    output reg  [7:0]                   m_index,        // bin index 0..FFT_LEN-1
    output reg  signed [IQ_WIDTH-1:0]   m_i,
    output reg  signed [IQ_WIDTH-1:0]   m_q,

    output reg                          busy,
    output reg                          done,
    output reg                          error
);

    localparam [15:0] WDOG_LIM = WATCHDOG_CYCLES[15:0];

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_PSS_FILL   = 4'd1,
        S_PSS_STREAM = 4'd2,
        S_PSS_FLUSH  = 4'd3,
        S_PSS_CAP    = 4'd4,
        S_SSS_FILL   = 4'd5,
        S_SSS_STREAM = 4'd6,
        S_SSS_FLUSH  = 4'd7,
        S_SSS_CAP    = 4'd8,
        S_STREAM_PSS = 4'd9,
        S_STREAM_SSS = 4'd10,
        S_DONE       = 4'd11;

    reg [3:0] state;

    // Input time-domain buffers
    reg [2*IQ_WIDTH-1:0] pss_in_buf [0:FFT_LEN-1];
    reg [2*IQ_WIDTH-1:0] sss_in_buf [0:FFT_LEN-1];

    // FFT output capture buffers (indexed by bin index from tuser)
    reg signed [IQ_WIDTH-1:0] fft_pss_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_pss_q [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_sss_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_sss_q [0:FFT_LEN-1];

    reg [7:0]  in_cnt;
    reg [7:0]  stream_cnt;
    reg [7:0]  cap_bin_cnt;
    reg [7:0]  stream_ptr;
    reg [7:0]  flush_rem;
    reg [15:0] watchdog_cnt;

    // Accept PSS only in S_PSS_FILL, SSS only in S_SSS_FILL
    assign s_ready = ((state == S_PSS_FILL) && !s_symbol_sel) ||
                     ((state == S_SSS_FILL) &&  s_symbol_sel);

    // -------------------------------------------------------------------------
    // FFT wrapper wires
    // -------------------------------------------------------------------------
    wire fft_s_ready;
    wire fft_m_valid;
    wire [2*IQ_WIDTH-1:0] fft_m_tdata;
    wire [7:0]             fft_m_tuser;
    wire                   fft_m_tlast;
    wire                   fft_err_w;

    wire stream_state = (state == S_PSS_STREAM) || (state == S_SSS_STREAM);

    // Feed FFT from active input buffer during streaming states (continuous tvalid)
    wire [2*IQ_WIDTH-1:0] fft_in_data =
        (state == S_PSS_STREAM) ? pss_in_buf[stream_cnt] :
        (state == S_SSS_STREAM) ? sss_in_buf[stream_cnt] :
                                  {(2*IQ_WIDTH){1'b0}};

    wire fft_s_tvalid = stream_state;
    wire fft_s_tlast  = stream_state && (stream_cnt == 8'd255);

    fft256_xilinx_wrapper #(
        .FFT_LEN             (FFT_LEN),
        .IQ_WIDTH            (IQ_WIDTH),
        .FFT_OUT_WIDTH       (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB)
    ) u_fft (
        .aclk                       (aclk),
        .aresetn                    (aresetn),
        .start                      (1'b0),
        .s_axis_tvalid              (fft_s_tvalid),
        .s_axis_tready              (fft_s_ready),
        .s_axis_tdata               (fft_in_data),
        .s_axis_tlast               (fft_s_tlast),
        .m_axis_tvalid              (fft_m_valid),
        .m_axis_tready              (1'b1),
        .m_axis_tdata               (fft_m_tdata),
        .m_axis_tuser               (fft_m_tuser),
        .m_axis_tlast               (fft_m_tlast),
        .busy                       (),
        .done                       (),
        .error                      (fft_err_w),
        .event_frame_started        (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt (),
        .event_status_channel_halt   ()
    );

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            in_cnt       <= 8'd0;
            stream_cnt   <= 8'd0;
            cap_bin_cnt  <= 8'd0;
            stream_ptr   <= 8'd0;
            flush_rem    <= FLUSH_COUNT[7:0];
            watchdog_cnt <= 16'd0;
            m_valid      <= 1'b0;
            m_symbol_sel <= 1'b0;
            m_index      <= 8'd0;
            m_i          <= {IQ_WIDTH{1'b0}};
            m_q          <= {IQ_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;
            if (start && busy) begin
                error <= 1'b1;
                // synthesis translate_off
                $display("[DFS_ERR] start_while_busy t=%0t state=%0d", $time, state);
                // synthesis translate_on
            end
            if (fft_err_w) begin
                error <= 1'b1;
                // synthesis translate_off
                $display("[DFS_ERR] fft_err_w t=%0t state=%0d", $time, state);
                // synthesis translate_on
            end

            case (state)

                // ---------------------------------------------------------------
                S_IDLE: begin
                    busy    <= 1'b0;
                    m_valid <= 1'b0;
                    if (start && !busy) begin
                        busy      <= 1'b1;
                        in_cnt    <= 8'd0;
                        flush_rem <= FLUSH_COUNT[7:0];
                        state     <= S_PSS_FILL;
                        // synthesis translate_off
                        $display("[DFS] t=%0t START → S_PSS_FILL flush_rem=%0d", $time, FLUSH_COUNT[7:0]);
                        // synthesis translate_on
                    end
                end

                // Accept 256 PSS time-domain samples; pack {Q,I} for FFT
                S_PSS_FILL: begin
                    if (s_valid && s_ready) begin
                        pss_in_buf[in_cnt] <= {s_q, s_i};
                        if (in_cnt == 8'd255) begin
                            in_cnt     <= 8'd0;
                            stream_cnt <= 8'd0;
                            state      <= S_PSS_STREAM;
                            // synthesis translate_off
                            $display("[DFS] t=%0t PSS_FILL done → S_PSS_STREAM", $time);
                            // synthesis translate_on
                        end else begin
                            in_cnt <= in_cnt + 8'd1;
                        end
                    end
                end

                // Stream PSS to FFT with continuous tvalid (no gaps)
                S_PSS_STREAM: begin
                    // synthesis translate_off
                    if (!fft_s_ready)
                        $display("[DBG_PSS_STREAM] STALL cnt=%0d", stream_cnt);
                    // synthesis translate_on
                    if (fft_s_ready) begin
                        if (stream_cnt == 8'd255) begin
                            stream_cnt   <= 8'd0;
                            cap_bin_cnt  <= 8'd0;
                            watchdog_cnt <= 16'd0;
                            state <= (flush_rem > 8'd0) ? S_PSS_FLUSH : S_PSS_CAP;
                        end else begin
                            stream_cnt <= stream_cnt + 8'd1;
                        end
                    end
                end

                // Discard PSS FFT output (flush frame to drain pipeline), re-stream
                S_PSS_FLUSH: begin
                    if (fft_m_valid) begin
                        watchdog_cnt <= 16'd0;
                        if (cap_bin_cnt == 8'd255) begin
                            cap_bin_cnt <= 8'd0;
                            stream_cnt  <= 8'd0;
                            flush_rem   <= flush_rem - 8'd1;
                            state       <= S_PSS_STREAM;
                            // synthesis translate_off
                            $display("[DFS] t=%0t PSS_FLUSH done → S_PSS_STREAM flush_rem=%0d", $time, flush_rem - 8'd1);
                            // synthesis translate_on
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_PSS_FLUSH] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Capture 256 PSS FFT output bins via xk_index (tuser)
                S_PSS_CAP: begin
                    if (fft_m_valid) begin
                        fft_pss_i[fft_m_tuser] <= $signed(fft_m_tdata[IQ_WIDTH-1:0]);
                        fft_pss_q[fft_m_tuser] <= $signed(fft_m_tdata[2*IQ_WIDTH-1:IQ_WIDTH]);
                        watchdog_cnt <= 16'd0;
                        if (cap_bin_cnt == 8'd255) begin
                            cap_bin_cnt <= 8'd0;
                            in_cnt      <= 8'd0;
                            state       <= S_SSS_FILL;
                            // synthesis translate_off
                            $display("[DFS] t=%0t PSS_CAP done → S_SSS_FILL s_valid=%0d s_sym=%0d s_ready=%0d",
                                     $time, s_valid, s_symbol_sel, s_ready);
                            // synthesis translate_on
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_PSS_CAP] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Accept 256 SSS time-domain samples
                S_SSS_FILL: begin
                    // synthesis translate_off
                    if (in_cnt == 8'd1 && !(s_valid && s_ready))
                        $display("[DFS] t=%0t SSS_FILL STALL@1 s_valid=%0d s_ready=%0d s_sym=%0d",
                                 $time, s_valid, s_ready, s_symbol_sel);
                    // synthesis translate_on
                    if (s_valid && s_ready) begin
                        sss_in_buf[in_cnt] <= {s_q, s_i};
                        // synthesis translate_off
                        if (in_cnt <= 8'd3)
                            $display("[DFS] t=%0t SSS_FILL got sample in_cnt=%0d", $time, in_cnt);
                        // synthesis translate_on
                        if (in_cnt == 8'd255) begin
                            in_cnt     <= 8'd0;
                            stream_cnt <= 8'd0;
                            state      <= S_SSS_STREAM;
                            // synthesis translate_off
                            $display("[DFS] t=%0t SSS_FILL done → S_SSS_STREAM", $time);
                            // synthesis translate_on
                        end else begin
                            in_cnt <= in_cnt + 8'd1;
                        end
                    end
                end

                // Stream SSS to FFT with continuous tvalid
                S_SSS_STREAM: begin
                    // synthesis translate_off
                    if (!fft_s_ready)
                        $display("[DBG_SSS_STREAM] STALL cnt=%0d", stream_cnt);
                    // synthesis translate_on
                    if (fft_s_ready) begin
                        if (stream_cnt == 8'd255) begin
                            stream_cnt   <= 8'd0;
                            cap_bin_cnt  <= 8'd0;
                            watchdog_cnt <= 16'd0;
                            state <= (flush_rem > 8'd0) ? S_SSS_FLUSH : S_SSS_CAP;
                        end else begin
                            stream_cnt <= stream_cnt + 8'd1;
                        end
                    end
                end

                // Discard SSS FFT output (flush frame), re-stream
                S_SSS_FLUSH: begin
                    if (fft_m_valid) begin
                        watchdog_cnt <= 16'd0;
                        if (cap_bin_cnt == 8'd255) begin
                            cap_bin_cnt <= 8'd0;
                            stream_cnt  <= 8'd0;
                            flush_rem   <= flush_rem - 8'd1;
                            state       <= S_SSS_STREAM;
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_SSS_FLUSH] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Capture 256 SSS FFT output bins via xk_index (tuser)
                S_SSS_CAP: begin
                    if (fft_m_valid) begin
                        fft_sss_i[fft_m_tuser] <= $signed(fft_m_tdata[IQ_WIDTH-1:0]);
                        fft_sss_q[fft_m_tuser] <= $signed(fft_m_tdata[2*IQ_WIDTH-1:IQ_WIDTH]);
                        watchdog_cnt <= 16'd0;
                        if (cap_bin_cnt == 8'd255) begin
                            cap_bin_cnt <= 8'd0;
                            stream_ptr  <= 8'd0;
                            state       <= S_STREAM_PSS;
                            // synthesis translate_off
                            $display("[DFS] t=%0t SSS_CAP done → S_STREAM_PSS", $time);
                            // synthesis translate_on
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_SSS_CAP] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Stream PSS FFT bins to output (m_symbol_sel=0), index 0..FFT_LEN-1
                S_STREAM_PSS: begin
                    m_valid      <= 1'b1;
                    m_symbol_sel <= 1'b0;
                    m_index      <= stream_ptr;
                    m_i          <= fft_pss_i[stream_ptr];
                    m_q          <= fft_pss_q[stream_ptr];
                    if (m_valid && m_ready) begin
                        if (stream_ptr == FFT_LEN - 1) begin
                            stream_ptr <= 8'd0;
                            state      <= S_STREAM_SSS;
                            // synthesis translate_off
                            $display("[DFS] t=%0t STREAM_PSS done → S_STREAM_SSS", $time);
                            // synthesis translate_on
                        end else begin
                            stream_ptr <= stream_ptr + 8'd1;
                            m_index    <= stream_ptr + 8'd1;
                            m_i        <= fft_pss_i[stream_ptr + 8'd1];
                            m_q        <= fft_pss_q[stream_ptr + 8'd1];
                        end
                    end
                end

                // Stream SSS FFT bins to output (m_symbol_sel=1), index 0..FFT_LEN-1
                S_STREAM_SSS: begin
                    m_valid      <= 1'b1;
                    m_symbol_sel <= 1'b1;
                    m_index      <= stream_ptr;
                    m_i          <= fft_sss_i[stream_ptr];
                    m_q          <= fft_sss_q[stream_ptr];
                    if (m_valid && m_ready && m_symbol_sel) begin
                        if (stream_ptr == FFT_LEN - 1) begin
                            m_valid <= 1'b0;
                            state   <= S_DONE;
                        end else begin
                            stream_ptr <= stream_ptr + 8'd1;
                            m_index    <= stream_ptr + 8'd1;
                            m_i        <= fft_sss_i[stream_ptr + 8'd1];
                            m_q        <= fft_sss_q[stream_ptr + 8'd1];
                        end
                    end
                end

                // ---------------------------------------------------------------
                S_DONE: begin
                    m_valid <= 1'b0;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= S_IDLE;
                    // synthesis translate_off
                    $display("[DFS] t=%0t S_DONE error=%0d", $time, error);
                    // synthesis translate_on
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
