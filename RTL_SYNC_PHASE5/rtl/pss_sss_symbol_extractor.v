`timescale 1ns/1ps

// PSS/SSS Symbol Extractor - Step 36C standalone module.

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

    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]            s_axis_tdata,
    input  wire                             s_axis_tlast,

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

    // Vivado-safe constants instead of SystemVerilog sized casts like FRAME_INDEX_WIDTH'(NSC)
    localparam [FRAME_INDEX_WIDTH-1:0] NSC_FI   = NSC[FRAME_INDEX_WIDTH-1:0];
    localparam [NSC_W-1:0]             NSC_LAST = (NSC - 1);

    reg [1:0]                       state;
    reg [FRAME_INDEX_WIDTH-1:0]     frame_idx;

    reg [NSC_W-1:0]                 pss_cnt;
    reg [NSC_W-1:0]                 sss_cnt;
    reg                             pss_done_r;
    reg                             sss_done_r;

    reg                             hold_valid;
    reg  [2*IQ_WIDTH-1:0]           hold_data;
    reg                             hold_tlast_r;
    reg                             hold_sel;
    reg  [7:0]                      hold_index;

    assign m_axis_tvalid  = hold_valid;
    assign m_axis_tdata   = hold_data;
    assign m_axis_tlast   = hold_tlast_r;
    assign m_symbol_sel   = hold_sel;
    assign m_symbol_index = hold_index;

    assign s_axis_tready = (state == S_STREAM) ? !hold_valid :
                           (state == S_DONE)   ? 1'b1 :
                                                  1'b0;

    wire s_fire = s_axis_tvalid && s_axis_tready;
    wire m_fire = m_axis_tvalid && m_axis_tready;

    wire [FRAME_INDEX_WIDTH-1:0] pss_fft_end = pss_fft_start + NSC_FI;
    wire [FRAME_INDEX_WIDTH-1:0] sss_fft_end = sss_fft_start + NSC_FI;

    wire in_pss_window = !pss_done_r &&
                         (frame_idx >= pss_fft_start) &&
                         (frame_idx <  pss_fft_end);

    wire in_sss_window = !sss_done_r &&
                         (frame_idx >= sss_fft_start) &&
                         (frame_idx <  sss_fft_end);

    wire pss_last_sample = in_pss_window && (pss_cnt == NSC_LAST);
    wire sss_last_sample = in_sss_window && (sss_cnt == NSC_LAST);

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

            if (hold_valid && m_axis_tready) begin
                hold_valid <= 1'b0;
            end

            case (state)

                S_IDLE: begin
                    busy       <= 1'b0;
                    error      <= 1'b0;
                    error_code <= 4'd0;

                    if (start) begin
                        if ((pss_fft_end > frame_len) ||
                            (sss_fft_end > frame_len) ||
                            (pss_fft_start == sss_fft_start) ||
                            ((pss_fft_start < sss_fft_start) &&
                             (pss_fft_end > sss_fft_start)) ||
                            ((sss_fft_start < pss_fft_start) &&
                             (sss_fft_end > pss_fft_start))) begin

                            error      <= 1'b1;
                            error_code <= 4'd1;
                            busy       <= 1'b0;
                            state      <= S_ERROR;

                        end else begin
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
                            busy         <= 1'b1;
                            state        <= S_STREAM;
                        end
                    end
                end

                S_STREAM: begin
                    if (s_fire) begin
                        if (in_pss_window || in_sss_window) begin
                            hold_valid   <= 1'b1;
                            hold_data    <= s_axis_tdata;
                            hold_sel     <= in_sss_window ? 1'b1 : 1'b0;
                            hold_tlast_r <= in_pss_window ? pss_last_sample : sss_last_sample;
                            hold_index   <= in_pss_window ? pss_cnt[7:0] : sss_cnt[7:0];

                            if (in_pss_window) begin
                                pss_cnt <= pss_cnt + {{(NSC_W-1){1'b0}}, 1'b1};
                            end

                            if (in_sss_window) begin
                                sss_cnt <= sss_cnt + {{(NSC_W-1){1'b0}}, 1'b1};
                            end
                        end

                        if (pss_last_sample) begin
                            pss_done_r <= 1'b1;
                        end

                        if (sss_last_sample) begin
                            sss_done_r <= 1'b1;
                        end

                        if (s_axis_tlast) begin
                            if ((pss_done_r || pss_last_sample) &&
                                (sss_done_r || sss_last_sample)) begin
                                state <= S_DONE;
                            end else begin
                                error      <= 1'b1;
                                error_code <= 4'd2;
                                busy       <= 1'b0;
                                state      <= S_ERROR;
                            end
                        end else begin
                            frame_idx <= frame_idx + {{(FRAME_INDEX_WIDTH-1){1'b0}}, 1'b1};

                            if ((pss_done_r || pss_last_sample) &&
                                (sss_done_r || sss_last_sample)) begin
                                state <= S_DONE;
                            end
                        end
                    end

                    if (start) begin
                        error      <= 1'b1;
                        error_code <= 4'd4;
                    end
                end

                S_DONE: begin
                    if (!hold_valid) begin
                        done  <= 1'b1;
                        busy  <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                S_ERROR: begin
                    busy <= 1'b0;

                    if (start) begin
                        error      <= 1'b0;
                        error_code <= 4'd0;
                        state      <= S_IDLE;
                    end
                end

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
