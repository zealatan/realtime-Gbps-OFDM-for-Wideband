`timescale 1ns/1ps

// meyr_fft256_actual_integration_top — Step 39 (A-FIX3) + Step 42-A + Step 42-B
//
// Step 42-B additions:
//   FLUSH_COUNT (default 1): discard N FFT output frames before capture to clear
//   pipeline residue.  flush_rem is shared across PSS/SSS; PSS consumes all credits
//   first so SSS only flushes if flush_rem>0 when SSS reaches STREAM (FLUSH_COUNT>1).
//
//   WATCHDOG_CYCLES (default 2047): configurable watchdog limit (16-bit).
//
//   All 5 FFT events connected and latched sticky:
//     ev_tlast_missing_o, ev_tlast_unexpected_o,
//     ev_data_in_halt_o, ev_data_out_halt_o, ev_status_halt_o.
//
//   New FSM states: S_PSS_FLUSH (4'd10), S_SSS_FLUSH (4'd11).

module meyr_fft256_actual_integration_top #(
    parameter integer NSC               = 256,
    parameter integer IQ_WIDTH          = 16,
    parameter integer PROD_WIDTH        = 32,
    parameter integer ACC_WIDTH         = 56,
    parameter integer SCORE_WIDTH       = 64,
    parameter integer INDEX_WIDTH       = 9,
    // 0=production, 1=passthrough stub, 2=sequential-output hardening stub
    parameter integer USE_BEHAVIORAL_STUB = 0,
    // Stub mode 2: STUB_TLAST_AT>=256 means TLAST never; STUB_STOP_AT=last bin
    parameter integer STUB_TLAST_AT     = 255,
    parameter integer STUB_STOP_AT      = 255,
    // Step 42-B: flush N FFT output frames before capture (0 = no flush)
    parameter integer FLUSH_COUNT       = 1,
    // Step 42-B: watchdog timeout in aclk cycles (fires when no fft_m_valid for this many cycles)
    parameter integer WATCHDOG_CYCLES   = 2047,
    parameter PSS_ROM_FILE = "vectors/meyr_pss_fft_romhex.txt",
    parameter SSS_ROM_FILE = "vectors/meyr_sss_fft_romhex.txt"
)(
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         start,

    // Time-domain input: PSS (NSC samples) then SSS (NSC samples)
    input  wire                         s_axis_tvalid,
    output wire                         s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]        s_axis_tdata,
    input  wire                         s_axis_tlast,
    input  wire                         s_symbol_sel,   // informational only

    output reg                          done,
    output reg                          busy,
    output reg                          error,
    output reg  [3:0]                   error_code,

    // Step 42-B: sticky FFT event latches (set on rising edge, cleared on reset only)
    output reg                          ev_tlast_missing_o,
    output reg                          ev_tlast_unexpected_o,
    output reg                          ev_data_in_halt_o,
    output reg                          ev_data_out_halt_o,
    output reg                          ev_status_halt_o,

    output wire signed [15:0]           int_cfo,
    output wire [INDEX_WIDTH-1:0]       peak_index,
    output wire [SCORE_WIDTH-1:0]       peak_score
);

    localparam [15:0] WDOG_LIM = WATCHDOG_CYCLES[15:0];

    localparam [3:0]
        S_IDLE       = 4'd0,
        S_PSS_BUF    = 4'd1,   // buffer PSS time-domain samples (intermittent OK)
        S_PSS_STREAM = 4'd2,   // stream PSS to FFT (continuous tvalid=1)
        S_PSS_CAP    = 4'd3,   // capture PSS FFT output bins
        S_SSS_BUF    = 4'd4,   // buffer SSS time-domain samples
        S_SSS_STREAM = 4'd5,   // stream SSS to FFT (continuous tvalid=1)
        S_SSS_CAP    = 4'd6,   // capture SSS FFT output bins
        S_EST        = 4'd7,
        S_WAIT_EST   = 4'd8,
        S_DONE       = 4'd9,
        S_PSS_FLUSH  = 4'd10,  // Step 42-B: discard PSS FFT output (flush frame)
        S_SSS_FLUSH  = 4'd11;  // Step 42-B: discard SSS FFT output (flush frame)

    reg [3:0] state;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    reg [7:0]  in_cnt;
    reg [7:0]  stream_cnt;
    reg [7:0]  replay_k;
    reg [7:0]  cap_bin_cnt;
    reg [15:0] watchdog_cnt;   // Step 42-B: widened to 16 bits for WATCHDOG_CYCLES
    reg [7:0]  flush_rem;      // Step 42-B: remaining flush frames before capture

    // -------------------------------------------------------------------------
    // Input buffers (time-domain samples before FFT)
    // -------------------------------------------------------------------------
    reg [2*IQ_WIDTH-1:0] pss_in_buf [0:NSC-1];
    reg [2*IQ_WIDTH-1:0] sss_in_buf [0:NSC-1];

    // -------------------------------------------------------------------------
    // FFT capture buffers (frequency-domain bins)
    // -------------------------------------------------------------------------
    reg [2*IQ_WIDTH-1:0] pss_buf [0:NSC-1];
    reg [2*IQ_WIDTH-1:0] sss_buf [0:NSC-1];

    // -------------------------------------------------------------------------
    // State predicates
    // -------------------------------------------------------------------------
    wire buf_state    = (state == S_PSS_BUF)    || (state == S_SSS_BUF);
    wire stream_state = (state == S_PSS_STREAM) || (state == S_SSS_STREAM);

    // Accept input only during buffering states; extractor stalls otherwise
    assign s_axis_tready = buf_state;

    // -------------------------------------------------------------------------
    // FFT wrapper wires
    // -------------------------------------------------------------------------
    wire fft_s_ready;
    wire fft_m_valid;
    wire [2*IQ_WIDTH-1:0] fft_m_tdata;
    wire [7:0]             fft_m_tuser;   // xk_index
    wire                   fft_m_tlast;
    wire                   fft_err_w;
    wire                   fft_ev_tlast_missing_w;
    wire                   fft_ev_tlast_unexpected_w;
    wire                   fft_ev_data_in_halt_w;     // Step 42-B
    wire                   fft_ev_data_out_halt_w;    // Step 42-B
    wire                   fft_ev_status_halt_w;      // Step 42-B

    // Feed FFT from input buffer during stream states (continuous tvalid)
    wire [2*IQ_WIDTH-1:0] fft_in_data =
        (state == S_PSS_STREAM) ? pss_in_buf[stream_cnt] :
        (state == S_SSS_STREAM) ? sss_in_buf[stream_cnt] :
                                  s_axis_tdata;

    wire fft_s_tvalid = stream_state;                           // always 1 during streaming
    wire fft_s_tlast  = stream_state && (stream_cnt == 8'd255); // last sample of frame

    fft256_xilinx_wrapper #(
        .FFT_LEN             (NSC),
        .IQ_WIDTH            (IQ_WIDTH),
        .FFT_OUT_WIDTH       (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB),
        .STUB_TLAST_AT       (STUB_TLAST_AT),
        .STUB_STOP_AT        (STUB_STOP_AT)
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
        .event_tlast_unexpected     (fft_ev_tlast_unexpected_w),
        .event_tlast_missing        (fft_ev_tlast_missing_w),
        .event_data_in_channel_halt (fft_ev_data_in_halt_w),
        .event_data_out_channel_halt(fft_ev_data_out_halt_w),
        .event_status_channel_halt  (fft_ev_status_halt_w)
    );

    // -------------------------------------------------------------------------
    // Estimator instance
    // -------------------------------------------------------------------------
    reg  est_start_r;
    reg  est_s_valid_r;
    wire est_s_ready;
    wire est_done;
    wire est_err_w;
    wire signed [15:0]        est_int_cfo;
    wire [INDEX_WIDTH-1:0]    est_peak_index;
    wire [SCORE_WIDTH-1:0]    est_peak_score;

    meyr_integer_cfo_freq_estimator_top #(
        .NSC         (NSC),
        .IQ_WIDTH    (IQ_WIDTH),
        .PROD_WIDTH  (PROD_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .SCORE_WIDTH (SCORE_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .PSS_ROM_FILE(PSS_ROM_FILE),
        .SSS_ROM_FILE(SSS_ROM_FILE)
    ) u_est (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .start     (est_start_r),
        .s_valid   (est_s_valid_r),
        .s_ready   (est_s_ready),
        .s_index   (replay_k),
        .pss_i     (pss_buf[replay_k][IQ_WIDTH-1:0]),
        .pss_q     (pss_buf[replay_k][2*IQ_WIDTH-1:IQ_WIDTH]),
        .sss_i     (sss_buf[replay_k][IQ_WIDTH-1:0]),
        .sss_q     (sss_buf[replay_k][2*IQ_WIDTH-1:IQ_WIDTH]),
        .busy      (),
        .done      (est_done),
        .error     (est_err_w),
        .int_cfo   (est_int_cfo),
        .peak_index(est_peak_index),
        .peak_score(est_peak_score)
    );

    // -------------------------------------------------------------------------
    // Output capture registers
    // -------------------------------------------------------------------------
    reg signed [15:0]     int_cfo_r;
    reg [INDEX_WIDTH-1:0] peak_index_r;
    reg [SCORE_WIDTH-1:0] peak_score_r;

    assign int_cfo    = int_cfo_r;
    assign peak_index = peak_index_r;
    assign peak_score = peak_score_r;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state                 <= S_IDLE;
            done                  <= 1'b0;
            busy                  <= 1'b0;
            error                 <= 1'b0;
            error_code            <= 4'd0;
            in_cnt                <= 8'd0;
            stream_cnt            <= 8'd0;
            replay_k              <= 8'd0;
            cap_bin_cnt           <= 8'd0;
            watchdog_cnt          <= 16'd0;
            flush_rem             <= FLUSH_COUNT[7:0];
            est_start_r           <= 1'b0;
            est_s_valid_r         <= 1'b0;
            int_cfo_r             <= 16'sd0;
            peak_index_r          <= {INDEX_WIDTH{1'b0}};
            peak_score_r          <= {SCORE_WIDTH{1'b0}};
            ev_tlast_missing_o    <= 1'b0;
            ev_tlast_unexpected_o <= 1'b0;
            ev_data_in_halt_o     <= 1'b0;
            ev_data_out_halt_o    <= 1'b0;
            ev_status_halt_o      <= 1'b0;
        end else begin
            done        <= 1'b0;
            est_start_r <= 1'b0;

            // Sticky FFT event latches (set on rising edge, cleared only by reset)
            if (fft_ev_tlast_missing_w)    ev_tlast_missing_o    <= 1'b1;
            if (fft_ev_tlast_unexpected_w) ev_tlast_unexpected_o <= 1'b1;
            if (fft_ev_data_in_halt_w)     ev_data_in_halt_o     <= 1'b1;
            if (fft_ev_data_out_halt_w)    ev_data_out_halt_o    <= 1'b1;
            if (fft_ev_status_halt_w)      ev_status_halt_o      <= 1'b1;

            // FFT IP error signals (production mode only; stubs tie these low)
            if (fft_ev_tlast_missing_w)    begin error <= 1'b1; error_code <= 4'd2; end
            if (fft_ev_tlast_unexpected_w) begin error <= 1'b1; error_code <= 4'd2; end
            if (fft_err_w)                 begin error <= 1'b1; error_code <= 4'd2; end
            if (est_err_w)                 begin error <= 1'b1; error_code <= 4'd3; end

            case (state)

                S_IDLE: begin
                    busy          <= 1'b0;
                    est_s_valid_r <= 1'b0;
                    if (start && !busy) begin
                        busy      <= 1'b1;
                        in_cnt    <= 8'd0;
                        flush_rem <= FLUSH_COUNT[7:0];  // reload on each start
                        state     <= S_PSS_BUF;
                    end else if (start && busy) begin
                        error      <= 1'b1;
                        error_code <= 4'd1;
                    end
                end

                // Buffer 256 PSS time-domain samples (tready=1, intermittent input OK)
                S_PSS_BUF: begin
                    if (s_axis_tvalid) begin
                        // synthesis translate_off
                        if (in_cnt < 4 || in_cnt >= 252)
                            $display("[DBG_PSS_IN] in_cnt=%0d tdata=%h", in_cnt, s_axis_tdata);
                        // synthesis translate_on
                        pss_in_buf[in_cnt] <= s_axis_tdata;
                        if (in_cnt == 8'd255) begin
                            in_cnt     <= 8'd0;
                            stream_cnt <= 8'd0;
                            state      <= S_PSS_STREAM;
                        end else begin
                            in_cnt <= in_cnt + 8'd1;
                        end
                    end
                end

                // Stream PSS to FFT with continuous tvalid=1 (no gaps)
                S_PSS_STREAM: begin
                    // synthesis translate_off
                    if (stream_cnt < 8 || stream_cnt >= 248)
                        $display("[DBG_PSS_STREAM] cnt=%0d data=%h tready=%0b",
                                 stream_cnt, fft_in_data, fft_s_ready);
                    if (!fft_s_ready)
                        $display("[DBG_PSS_STREAM] STALL cnt=%0d", stream_cnt);
                    // synthesis translate_on
                    if (fft_s_ready) begin
                        if (stream_cnt == 8'd255) begin
                            stream_cnt   <= 8'd0;
                            cap_bin_cnt  <= 8'd0;
                            watchdog_cnt <= 16'd0;
                            // Step 42-B: flush if credits remain, else capture
                            state <= (flush_rem > 8'd0) ? S_PSS_FLUSH : S_PSS_CAP;
                        end else begin
                            stream_cnt <= stream_cnt + 8'd1;
                        end
                    end
                end

                // Step 42-B: discard PSS FFT output (flush frame), then re-stream
                // Watchdog: fires at WATCHDOG_CYCLES idle cycles → error_code=4 → S_DONE
                // TLAST mismatch: non-fatal error_code=5, capture continues
                S_PSS_FLUSH: begin
                    if (fft_m_valid) begin
                        // synthesis translate_off
                        if (cap_bin_cnt >= 8'd253 || fft_m_tlast)
                            $display("[DBG_PSS_FLUSH] bin=%0d cap_cnt=%0d tlast=%0b",
                                     fft_m_tuser, cap_bin_cnt, fft_m_tlast);
                        // synthesis translate_on
                        watchdog_cnt <= 16'd0;
                        if (fft_m_tlast && (cap_bin_cnt != 8'd255)) begin
                            error      <= 1'b1;
                            error_code <= 4'd5;
                        end
                        if (cap_bin_cnt == 8'd255) begin
                            if (!fft_m_tlast) begin error <= 1'b1; error_code <= 4'd5; end
                            cap_bin_cnt <= 8'd0;
                            stream_cnt  <= 8'd0;
                            flush_rem   <= flush_rem - 8'd1;
                            state       <= S_PSS_STREAM;  // re-stream same buffer
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_PSS_FLUSH] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error       <= 1'b1;
                            error_code  <= 4'd4;
                            cap_bin_cnt <= 8'd0;
                            state       <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Capture PSS FFT output bins via xk_index.
                // Exit when cap_bin_cnt reaches 255 (256th bin captured).
                // Watchdog fires after WATCHDOG_CYCLES idle cycles → error_code=4.
                // error_code 4 = watchdog, 5 = TLAST mismatch.
                S_PSS_CAP: begin
                    if (fft_m_valid) begin
                        // synthesis translate_off
                        if (fft_m_tuser < 4 || cap_bin_cnt >= 8'd253 || fft_m_tlast)
                            $display("[DBG_PSS_CAP] bin=%0d cap_cnt=%0d tdata=%h tlast=%0b",
                                     fft_m_tuser, cap_bin_cnt, fft_m_tdata, fft_m_tlast);
                        // synthesis translate_on
                        pss_buf[fft_m_tuser] <= fft_m_tdata;
                        watchdog_cnt <= 16'd0;

                        if (fft_m_tlast && (cap_bin_cnt != 8'd255)) begin
                            error      <= 1'b1;
                            error_code <= 4'd5;
                        end

                        if (cap_bin_cnt == 8'd255) begin
                            if (!fft_m_tlast) begin
                                error      <= 1'b1;
                                error_code <= 4'd5;
                            end
                            cap_bin_cnt <= 8'd0;
                            in_cnt      <= 8'd0;
                            state       <= S_SSS_BUF;
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_PSS_CAP] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error       <= 1'b1;
                            error_code  <= 4'd4;
                            cap_bin_cnt <= 8'd0;
                            state       <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Buffer 256 SSS time-domain samples
                S_SSS_BUF: begin
                    if (s_axis_tvalid) begin
                        // synthesis translate_off
                        if (in_cnt < 4 || in_cnt >= 252)
                            $display("[DBG_SSS_IN] in_cnt=%0d tdata=%h", in_cnt, s_axis_tdata);
                        // synthesis translate_on
                        sss_in_buf[in_cnt] <= s_axis_tdata;
                        if (in_cnt == 8'd255) begin
                            in_cnt     <= 8'd0;
                            stream_cnt <= 8'd0;
                            state      <= S_SSS_STREAM;
                        end else begin
                            in_cnt <= in_cnt + 8'd1;
                        end
                    end
                end

                // Stream SSS to FFT with continuous tvalid=1
                S_SSS_STREAM: begin
                    // synthesis translate_off
                    if (stream_cnt < 4 || stream_cnt >= 252)
                        $display("[DBG_SSS_STREAM] cnt=%0d data=%h tready=%0b",
                                 stream_cnt, fft_in_data, fft_s_ready);
                    if (!fft_s_ready)
                        $display("[DBG_SSS_STREAM] STALL cnt=%0d", stream_cnt);
                    // synthesis translate_on
                    if (fft_s_ready) begin
                        if (stream_cnt == 8'd255) begin
                            stream_cnt   <= 8'd0;
                            cap_bin_cnt  <= 8'd0;
                            watchdog_cnt <= 16'd0;
                            // Step 42-B: flush if credits remain, else capture
                            state <= (flush_rem > 8'd0) ? S_SSS_FLUSH : S_SSS_CAP;
                        end else begin
                            stream_cnt <= stream_cnt + 8'd1;
                        end
                    end
                end

                // Step 42-B: discard SSS FFT output (flush frame), then re-stream
                S_SSS_FLUSH: begin
                    if (fft_m_valid) begin
                        // synthesis translate_off
                        if (cap_bin_cnt >= 8'd253 || fft_m_tlast)
                            $display("[DBG_SSS_FLUSH] bin=%0d cap_cnt=%0d tlast=%0b",
                                     fft_m_tuser, cap_bin_cnt, fft_m_tlast);
                        // synthesis translate_on
                        watchdog_cnt <= 16'd0;
                        if (fft_m_tlast && (cap_bin_cnt != 8'd255)) begin
                            error      <= 1'b1;
                            error_code <= 4'd5;
                        end
                        if (cap_bin_cnt == 8'd255) begin
                            if (!fft_m_tlast) begin error <= 1'b1; error_code <= 4'd5; end
                            cap_bin_cnt <= 8'd0;
                            stream_cnt  <= 8'd0;
                            flush_rem   <= flush_rem - 8'd1;
                            state       <= S_SSS_STREAM;  // re-stream same buffer
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_SSS_FLUSH] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error       <= 1'b1;
                            error_code  <= 4'd4;
                            cap_bin_cnt <= 8'd0;
                            state       <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Capture SSS FFT output bins via xk_index.
                S_SSS_CAP: begin
                    if (fft_m_valid) begin
                        // synthesis translate_off
                        if (fft_m_tuser < 4 || cap_bin_cnt >= 8'd253 || fft_m_tlast)
                            $display("[DBG_SSS_CAP] bin=%0d cap_cnt=%0d tdata=%h tlast=%0b",
                                     fft_m_tuser, cap_bin_cnt, fft_m_tdata, fft_m_tlast);
                        // synthesis translate_on
                        sss_buf[fft_m_tuser] <= fft_m_tdata;
                        watchdog_cnt <= 16'd0;

                        if (fft_m_tlast && (cap_bin_cnt != 8'd255)) begin
                            error      <= 1'b1;
                            error_code <= 4'd5;
                        end

                        if (cap_bin_cnt == 8'd255) begin
                            if (!fft_m_tlast) begin
                                error      <= 1'b1;
                                error_code <= 4'd5;
                            end
                            cap_bin_cnt <= 8'd0;
                            replay_k    <= 8'd0;
                            est_start_r <= 1'b1;
                            state       <= S_EST;
                        end else begin
                            cap_bin_cnt <= cap_bin_cnt + 8'd1;
                        end
                    end else begin
                        if (watchdog_cnt == WDOG_LIM) begin
                            // synthesis translate_off
                            $display("[DBG_SSS_CAP] WATCHDOG fired cap_cnt=%0d", cap_bin_cnt);
                            // synthesis translate_on
                            error       <= 1'b1;
                            error_code  <= 4'd4;
                            cap_bin_cnt <= 8'd0;
                            state       <= S_DONE;
                        end else begin
                            watchdog_cnt <= watchdog_cnt + 16'd1;
                        end
                    end
                end

                // Replay buffered PSS/SSS bins to estimator
                S_EST: begin
                    est_s_valid_r <= 1'b1;
                    if (est_s_valid_r && est_s_ready) begin
                        if (replay_k == 8'd255) begin
                            est_s_valid_r <= 1'b0;
                            state         <= S_WAIT_EST;
                        end else begin
                            replay_k <= replay_k + 8'd1;
                        end
                    end
                end

                S_WAIT_EST: begin
                    if (est_done) begin
                        int_cfo_r    <= est_int_cfo;
                        peak_index_r <= est_peak_index;
                        peak_score_r <= est_peak_score;
                        state        <= S_DONE;
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
