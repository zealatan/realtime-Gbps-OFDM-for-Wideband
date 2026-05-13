`timescale 1ns/1ps

// PSS/SSS Symbol Extractor — Step 36C standalone module.
//
// Accepts a corrected time-domain frame as an AXI-Stream and extracts exactly
// NSC samples for the PSS FFT window and NSC samples for the SSS FFT window.
// CP removal is implicit: pss_fft_start / sss_fft_start point to the first
// post-CP sample; the CP is never forwarded downstream.
//
// Backpressure policy: one-deep hold register + combinatorial output.
// m_axis_tvalid is driven combinatorially from hold_valid.
// s_axis_tready is deasserted while hold_valid is set (downstream stalls input).
// This guarantees no selected sample is dropped.
//
// Error codes (sticky until next start):
//   0 = no error
//   1 = invalid_config  (window out of frame, windows overlap, or equal starts)
//   2 = frame_tlast_too_early (input ended before both windows complete)
//   3 = reserved
//   4 = start_while_busy (ignored; logged via error_code)
//
// done is a one-cycle pulse after the hold register drains post-completion.

module pss_sss_symbol_extractor #(
    parameter integer NSC               = 256,
    parameter integer CP_LEN            = 32,
    parameter integer IQ_WIDTH          = 16,
    parameter integer FRAME_INDEX_WIDTH = 12
)(
    input  wire                             aclk,
    input  wire                             aresetn,

    input  wire                             start,

    input  wire [FRAME_INDEX_WIDTH-1:0]     pss_fft_start,
    input  wire [FRAME_INDEX_WIDTH-1:0]     sss_fft_start,
    input  wire [FRAME_INDEX_WIDTH-1:0]     frame_len,

    // Input: corrected frame stream
    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]            s_axis_tdata,
    input  wire                             s_axis_tlast,

    // Output: extracted symbol stream (combinatorial from hold register)
    output wire                             m_axis_tvalid,
    input  wire                             m_axis_tready,
    output wire [2*IQ_WIDTH-1:0]            m_axis_tdata,
    output wire                             m_axis_tlast,
    output wire                             m_symbol_sel,
    output wire [7:0]                       m_symbol_index,

    output reg                              busy,
    output reg                              done,
    output reg                              error,
    output reg  [3:0]                       error_code
);

    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_STREAM = 2'd1;
    localparam [1:0] S_DONE   = 2'd2;
    localparam [1:0] S_ERROR  = 2'd3;

    localparam integer NSC_W = $clog2(NSC + 1);

    reg [1:0]                       state;
    reg [FRAME_INDEX_WIDTH-1:0]     frame_idx;

    reg [NSC_W-1:0]                 pss_cnt;
    reg [NSC_W-1:0]                 sss_cnt;
    reg                             pss_done_r;
    reg                             sss_done_r;

    // One-deep hold register
    reg                             hold_valid;
    reg  [2*IQ_WIDTH-1:0]           hold_data;
    reg                             hold_tlast_r;
    reg                             hold_sel;
    reg  [7:0]                      hold_index;

    // Combinatorial output directly from hold register
    assign m_axis_tvalid  = hold_valid;
    assign m_axis_tdata   = hold_data;
    assign m_axis_tlast   = hold_tlast_r;
    assign m_symbol_sel   = hold_sel;
    assign m_symbol_index = hold_index;

    // Accept input: stream (with backpressure) or done (drain/discard remainder)
    assign s_axis_tready = (state == S_STREAM) ? !hold_valid : (state == S_DONE);

    wire s_fire = s_axis_tvalid && s_axis_tready;
    wire m_fire = m_axis_tvalid && m_axis_tready;

    // Window membership (frame_idx relative to each symbol's FFT start)
    wire in_pss_window = !pss_done_r &&
                         (frame_idx >= pss_fft_start) &&
                         (frame_idx <  pss_fft_start + FRAME_INDEX_WIDTH'(NSC));
    wire in_sss_window = !sss_done_r &&
                         (frame_idx >= sss_fft_start) &&
                         (frame_idx <  sss_fft_start + FRAME_INDEX_WIDTH'(NSC));

    // Completion flags (combinatorial look-ahead)
    wire pss_last_sample = in_pss_window && (pss_cnt == NSC_W'(NSC - 1));
    wire sss_last_sample = in_sss_window && (sss_cnt == NSC_W'(NSC - 1));

    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            frame_idx    <= {FRAME_INDEX_WIDTH{1'b0}};
            pss_cnt      <= {NSC_W{1'b0}};
            sss_cnt      <= {NSC_W{1'b0}};
            pss_done_r   <= 1'b0;
            sss_done_r   <= 1'b0;
            hold_valid   <= 1'b0;
            hold_data    <= {(2*IQ_WIDTH){1'b0}};
            hold_tlast_r <= 1'b0;
            hold_sel     <= 1'b0;
            hold_index   <= 8'd0;
            busy         <= 1'b0;
            done         <= 1'b0;
            error        <= 1'b0;
            error_code   <= 4'd0;
        end else begin
            done <= 1'b0;

            // Drain hold register when downstream is ready
            if (hold_valid && m_axis_tready)
                hold_valid <= 1'b0;

            case (state)

                // -----------------------------------------------------------
                S_IDLE: begin
                    busy       <= 1'b0;
                    error      <= 1'b0;
                    error_code <= 4'd0;
                    if (start) begin
                        if ((pss_fft_start + FRAME_INDEX_WIDTH'(NSC) > frame_len) ||
                            (sss_fft_start + FRAME_INDEX_WIDTH'(NSC) > frame_len) ||
                            (pss_fft_start == sss_fft_start) ||
                            // overlap: PSS window starts before SSS end and vice-versa
                            ((pss_fft_start < sss_fft_start) &&
                             (pss_fft_start + FRAME_INDEX_WIDTH'(NSC) > sss_fft_start)) ||
                            ((sss_fft_start < pss_fft_start) &&
                             (sss_fft_start + FRAME_INDEX_WIDTH'(NSC) > pss_fft_start)))
                        begin
                            error      <= 1'b1;
                            error_code <= 4'd1;
                            state      <= S_ERROR;
                        end else begin
                            frame_idx  <= {FRAME_INDEX_WIDTH{1'b0}};
                            pss_cnt    <= {NSC_W{1'b0}};
                            sss_cnt    <= {NSC_W{1'b0}};
                            pss_done_r <= 1'b0;
                            sss_done_r <= 1'b0;
                            busy       <= 1'b1;
                            state      <= S_STREAM;
                        end
                    end
                end

                // -----------------------------------------------------------
                S_STREAM: begin
                    if (s_fire) begin
                        if (in_pss_window || in_sss_window) begin
                            // Load hold register (tready was 1 => hold was empty)
                            hold_valid   <= 1'b1;
                            hold_data    <= s_axis_tdata;
                            hold_sel     <= in_sss_window ? 1'b1 : 1'b0;
                            hold_tlast_r <= in_pss_window ? pss_last_sample : sss_last_sample;
                            hold_index   <= in_pss_window ? pss_cnt[7:0] : sss_cnt[7:0];

                            if (in_pss_window) pss_cnt <= pss_cnt + 1;
                            if (in_sss_window) sss_cnt <= sss_cnt + 1;
                        end

                        // Update completion flags
                        if (pss_last_sample) pss_done_r <= 1'b1;
                        if (sss_last_sample) sss_done_r <= 1'b1;

                        if (s_axis_tlast) begin
                            // Check that both windows are (or will be) complete
                            if ((pss_done_r || pss_last_sample) &&
                                (sss_done_r || sss_last_sample))
                            begin
                                state <= S_DONE;
                            end else begin
                                error      <= 1'b1;
                                error_code <= 4'd2;
                                busy       <= 1'b0;
                                state      <= S_ERROR;
                            end
                        end else begin
                            frame_idx <= frame_idx + 1;
                            // Check if both windows complete mid-frame
                            if ((pss_done_r || pss_last_sample) &&
                                (sss_done_r || sss_last_sample))
                                state <= S_DONE;
                        end
                    end

                    // start_while_busy
                    if (start) begin
                        error      <= 1'b1;
                        error_code <= 4'd4;
                    end
                end

                // -----------------------------------------------------------
                S_DONE: begin
                    if (!hold_valid) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                // -----------------------------------------------------------
                S_ERROR: begin
                    // Sticky until next start (handled in S_IDLE)
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
