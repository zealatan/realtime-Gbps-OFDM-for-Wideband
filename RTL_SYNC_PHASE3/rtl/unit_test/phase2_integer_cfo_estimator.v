`timescale 1ns/1ps

// phase2_integer_cfo_estimator — P2-18
//
// Side-path integer CFO estimator for Phase2.
// Taps the corrected IQ stream as a sideband (always-ready; never backpressures
// the main corrected output path).
//
// On each timing_lock rising edge, if idle, captures FRAME_LEN = 2*(CP_LEN+NSC)
// samples into an internal buffer, then replays through:
//   pss_sss_symbol_extractor → meyr_fft256_actual_integration_top
// to produce int_cfo / peak_index.  Results are exposed as 1-clock pulses.
//
// USE_FFT_STUB=1 (default): passthrough FFT stub for compile/pipeline tests.
// USE_FFT_STUB=0: Xilinx xfft IP (production mode; needs IP compile).

module phase2_integer_cfo_estimator #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer IQ_WIDTH     = 16,
    parameter integer PROD_WIDTH   = 32,
    parameter integer ACC_WIDTH    = 56,
    parameter integer SCORE_WIDTH  = 64,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer USE_FFT_STUB = 1
)(
    input  wire        aclk,
    input  wire        aresetn,

    // Side tap from corrected IQ stream — always-ready, zero backpressure
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]  s_axis_tdata,

    // Rising edge of timing_lock starts a capture when idle
    input  wire        timing_lock,

    // Integer CFO results
    output reg                     integer_cfo_valid,
    output reg  signed [15:0]      integer_cfo_estimate,
    output reg  [INDEX_WIDTH-1:0]  integer_cfo_lock_index,
    output reg                     integer_cfo_busy
);

    // -----------------------------------------------------------------------
    // Derived constants
    // -----------------------------------------------------------------------
    localparam integer FRAME_LEN     = 2 * (CP_LEN + NSC);   // 576
    localparam integer PSS_FFT_START = CP_LEN;                // 32
    localparam integer SSS_FFT_START = CP_LEN + NSC + CP_LEN; // 320
    localparam integer FRAME_IDX_W   = 12;

    // 10-bit counters: covers 0..575 (FRAME_LEN-1 < 1024 = 2^10)
    localparam integer CNT_W     = 10;
    localparam [CNT_W-1:0] LAST  = FRAME_LEN - 1;  // 575

    // Extractor expects FRAME_INDEX_WIDTH-bit constants
    localparam [FRAME_IDX_W-1:0] LP_PSS_START = PSS_FFT_START;
    localparam [FRAME_IDX_W-1:0] LP_SSS_START = SSS_FFT_START;
    localparam [FRAME_IDX_W-1:0] LP_FRAME_LEN = FRAME_LEN;

    localparam [2:0]
        S_IDLE    = 3'd0,
        S_CAPTURE = 3'd1,
        S_REPLAY  = 3'd2,
        S_WAIT    = 3'd3,
        S_DONE    = 3'd4;

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // Frame buffer: FRAME_LEN × 2*IQ_WIDTH registers
    // -----------------------------------------------------------------------
    reg [2*IQ_WIDTH-1:0] frame_buf [0:FRAME_LEN-1];
    reg [CNT_W-1:0]      buf_cnt;

    // -----------------------------------------------------------------------
    // Replay counter
    // -----------------------------------------------------------------------
    reg [CNT_W-1:0] replay_cnt;

    // -----------------------------------------------------------------------
    // Timing-lock edge detect
    // -----------------------------------------------------------------------
    reg  timing_lock_prev;
    wire timing_lock_rise = timing_lock && !timing_lock_prev;

    // -----------------------------------------------------------------------
    // Always-ready: side path never stalls main corrected stream
    // -----------------------------------------------------------------------
    assign s_axis_tready = 1'b1;

    // -----------------------------------------------------------------------
    // Declare all inter-instance wires before any instantiation
    // (required in Verilog-2001 to avoid implicit forward declarations)
    // -----------------------------------------------------------------------

    // Extractor control
    reg  ext_start;
    wire ext_s_tready;
    wire ext_m_valid;
    wire [2*IQ_WIDTH-1:0] ext_m_tdata;
    wire ext_m_tlast;
    wire ext_m_symbol_sel;
    wire [7:0]             ext_m_symbol_index;
    wire ext_busy_w;
    wire ext_done_w;
    wire ext_error_w;

    // FFT/estimator control
    reg  fft_start;
    wire fft_s_tready;
    wire fft_done;
    wire fft_busy_w;
    wire fft_error_w;
    wire signed [15:0]     fft_int_cfo;
    wire [INDEX_WIDTH-1:0] fft_peak_index;
    wire [SCORE_WIDTH-1:0] fft_peak_score;

    // Replay stream signals
    wire replay_valid = (state == S_REPLAY);
    wire replay_tlast = replay_valid && (replay_cnt == LAST);
    wire replay_fire  = replay_valid && ext_s_tready;

    pss_sss_symbol_extractor #(
        .NSC               (NSC),
        .CP_LEN            (CP_LEN),
        .IQ_WIDTH          (IQ_WIDTH),
        .FRAME_INDEX_WIDTH (FRAME_IDX_W)
    ) u_extractor (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .start         (ext_start),
        .pss_fft_start (LP_PSS_START),
        .sss_fft_start (LP_SSS_START),
        .frame_len     (LP_FRAME_LEN),
        .s_axis_tvalid (replay_valid),
        .s_axis_tready (ext_s_tready),
        .s_axis_tdata  (frame_buf[replay_cnt]),
        .s_axis_tlast  (replay_tlast),
        .m_axis_tvalid (ext_m_valid),
        .m_axis_tready (fft_s_tready),
        .m_axis_tdata  (ext_m_tdata),
        .m_axis_tlast  (ext_m_tlast),
        .m_symbol_sel  (ext_m_symbol_sel),
        .m_symbol_index(ext_m_symbol_index),
        .busy          (ext_busy_w),
        .done          (ext_done_w),
        .error         (ext_error_w)
    );

    meyr_fft256_actual_integration_top #(
        .NSC                (NSC),
        .IQ_WIDTH           (IQ_WIDTH),
        .PROD_WIDTH         (PROD_WIDTH),
        .ACC_WIDTH          (ACC_WIDTH),
        .SCORE_WIDTH        (SCORE_WIDTH),
        .INDEX_WIDTH        (INDEX_WIDTH),
        .USE_BEHAVIORAL_STUB(USE_FFT_STUB),
        .FLUSH_COUNT        (0),
        .WATCHDOG_CYCLES    (2047)
    ) u_fft_est (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .start                (fft_start),
        .s_axis_tvalid        (ext_m_valid),
        .s_axis_tready        (fft_s_tready),
        .s_axis_tdata         (ext_m_tdata),
        .s_axis_tlast         (ext_m_tlast),
        .s_symbol_sel         (ext_m_symbol_sel),
        .done                 (fft_done),
        .busy                 (fft_busy_w),
        .error                (fft_error_w),
        .error_code           (),
        .ev_tlast_missing_o   (),
        .ev_tlast_unexpected_o(),
        .ev_data_in_halt_o    (),
        .ev_data_out_halt_o   (),
        .ev_status_halt_o     (),
        .int_cfo              (fft_int_cfo),
        .peak_index           (fft_peak_index),
        .peak_score           (fft_peak_score)
    );

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state                  <= S_IDLE;
            buf_cnt                <= {CNT_W{1'b0}};
            replay_cnt             <= {CNT_W{1'b0}};
            timing_lock_prev       <= 1'b0;
            ext_start              <= 1'b0;
            fft_start              <= 1'b0;
            integer_cfo_valid      <= 1'b0;
            integer_cfo_estimate   <= 16'sd0;
            integer_cfo_lock_index <= {INDEX_WIDTH{1'b0}};
            integer_cfo_busy       <= 1'b0;
        end else begin
            timing_lock_prev  <= timing_lock;
            ext_start         <= 1'b0;
            fft_start         <= 1'b0;
            integer_cfo_valid <= 1'b0;

            case (state)

                S_IDLE: begin
                    integer_cfo_busy <= 1'b0;
                    if (timing_lock_rise) begin
                        buf_cnt <= {CNT_W{1'b0}};
                        state   <= S_CAPTURE;
                    end
                end

                // Capture FRAME_LEN samples; ignore any timing_lock during capture
                S_CAPTURE: begin
                    integer_cfo_busy <= 1'b1;
                    if (s_axis_tvalid && s_axis_tready) begin // fire = tvalid && tready (AXI-Stream)
                        frame_buf[buf_cnt] <= s_axis_tdata;
                        if (buf_cnt == LAST) begin
                            replay_cnt <= {CNT_W{1'b0}};
                            ext_start  <= 1'b1;
                            fft_start  <= 1'b1;
                            state      <= S_REPLAY;
                        end else begin
                            buf_cnt <= buf_cnt + 10'd1;
                        end
                    end
                end

                // Replay buffer → extractor → fft_est pipeline
                S_REPLAY: begin
                    if (replay_fire) begin
                        if (replay_cnt == LAST) begin
                            state <= S_WAIT;
                        end else begin
                            replay_cnt <= replay_cnt + 10'd1;
                        end
                    end
                end

                // Wait for meyr_fft256 to complete; abort on error
                S_WAIT: begin
                    if (fft_done) begin
                        integer_cfo_estimate   <= fft_int_cfo;
                        integer_cfo_lock_index <= fft_peak_index;
                        state                  <= S_DONE;
                    end else if (fft_error_w) begin
                        integer_cfo_busy <= 1'b0;
                        state            <= S_IDLE;
                    end
                end

                S_DONE: begin
                    integer_cfo_valid <= 1'b1;
                    integer_cfo_busy  <= 1'b0;
                    state             <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    // Suppress unused-signal warnings
    wire _unused = ext_busy_w | ext_done_w | ext_error_w | (|ext_m_symbol_index)
                 | fft_busy_w | (|fft_peak_score);

endmodule
