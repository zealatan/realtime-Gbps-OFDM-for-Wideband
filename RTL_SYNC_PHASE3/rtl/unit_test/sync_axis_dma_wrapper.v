`timescale 1ns/1ps

// sync_axis_dma_wrapper: DMA-facing AXI-Stream adapter for the Phase-1
// OFDM synchronizer pipeline.  Sits between an AXI DMA and the pipeline
// AXI-Stream ports and adds:
//
//   * Frame boundary / TLAST generation based on sample count
//   * Full backpressure propagation (tready pass-through)
//   * Timeout watchdog when upstream goes silent
//   * Drain state to consume a late TLAST from upstream DMA
//   * Frame-abort on early TLAST
//
// State machine:
//
//   S_IDLE  → (enable && start) → S_RECV
//   S_RECV  → (count == frame_len && tvalid && tready):
//               if s_axis_tlast on same beat   → S_DONE  (TLAST already consumed)
//               else                            → S_DRAIN (wait for late TLAST)
//   S_RECV  → (early s_axis_tlast)             → S_DONE  with error
//   S_RECV  → (timeout, upstream silent)        → S_DRAIN with timeout/error
//   S_DRAIN → (s_axis_tlast OR drain_cnt max)  → S_DONE
//   S_DONE  → pulse done_o or error_o           → S_IDLE
//
// TLAST policy:
//   m_axis_tlast is asserted combinatorially when in S_RECV and either
//   (a) the sample count hits frame_len_i (wrapper generates TLAST), or
//   (b) s_axis_tlast arrives from upstream (forwarded regardless of count).
//
// Backpressure:
//   s_axis_tready = m_axis_tready when in S_RECV.
//   s_axis_tready = 1 (drain) when in S_DRAIN.
//   s_axis_tready = 0 otherwise.

module sync_axis_dma_wrapper #(
    parameter integer DATA_WIDTH     = 32,
    parameter integer MAX_FRAME_LEN  = 4096,  // max samples per frame (sets counter width)
    parameter integer TIMEOUT_CYCLES = 1024,  // upstream-silence timeout
    parameter integer MAX_DRAIN_CYCS = 512    // drain safety limit (cycles)
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // Control (from AXI-Lite register bank or TB)
    input  wire                   enable_i,
    input  wire                   start_i,       // 1-cycle pulse
    input  wire [31:0]            frame_len_i,   // runtime samples per frame

    // DMA-facing AXI-Stream input
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    // Pipeline-facing AXI-Stream output
    output wire [DATA_WIDTH-1:0]  m_axis_tdata,
    output wire                   m_axis_tvalid,
    input  wire                   m_axis_tready,
    output wire                   m_axis_tlast,

    // Status outputs (1-cycle pulses)
    output reg                    done_o,
    output reg                    error_o,
    output reg                    timeout_o,

    // Debug
    output wire [$clog2(MAX_FRAME_LEN+1)-1:0] sample_count_o
);

    // -----------------------------------------------------------------------
    // Counter widths
    // -----------------------------------------------------------------------
    localparam CNT_W = $clog2(MAX_FRAME_LEN + 1);
    localparam TO_W  = $clog2(TIMEOUT_CYCLES + 2);
    localparam DR_W  = $clog2(MAX_DRAIN_CYCS + 2);

    localparam [TO_W-1:0] TO_MAX = TIMEOUT_CYCLES;
    localparam [DR_W-1:0] DR_MAX = MAX_DRAIN_CYCS - 1;

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam [1:0]
        S_IDLE  = 2'd0,
        S_RECV  = 2'd1,
        S_DRAIN = 2'd2,
        S_DONE  = 2'd3;

    reg [1:0]       state;
    reg [CNT_W-1:0] sample_cnt;
    reg [TO_W-1:0]  to_cnt;
    reg [DR_W-1:0]  drain_cnt;
    reg             err_flag;

    // -----------------------------------------------------------------------
    // Derived signals
    // -----------------------------------------------------------------------
    wire in_recv  = (state == S_RECV);
    wire in_drain = (state == S_DRAIN);

    // Effective frame length — guard against zero
    wire [CNT_W-1:0] flen =
        (frame_len_i[CNT_W-1:0] == {CNT_W{1'b0}}) ? {{(CNT_W-1){1'b0}}, 1'b1}
                                                    : frame_len_i[CNT_W-1:0];

    // is_last: true when sample_cnt points at the last expected sample
    wire is_last  = (sample_cnt == (flen - {{(CNT_W-1){1'b0}}, 1'b1}));
    wire transfer = in_recv && s_axis_tvalid && m_axis_tready;

    // -----------------------------------------------------------------------
    // Combinatorial AXI-Stream outputs
    // -----------------------------------------------------------------------
    // tready: propagate backpressure in RECV; always accept (drain) in DRAIN
    assign s_axis_tready = in_recv  ? m_axis_tready :
                           in_drain ? 1'b1           : 1'b0;

    // tdata/tvalid: direct pass-through in RECV only
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tvalid = in_recv && s_axis_tvalid;

    // tlast: generated when count hits frame_len OR when upstream asserts it
    assign m_axis_tlast  = in_recv && s_axis_tvalid && (is_last || s_axis_tlast);

    assign sample_count_o = sample_cnt;

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= S_IDLE;
            sample_cnt <= {CNT_W{1'b0}};
            to_cnt     <= {TO_W{1'b0}};
            drain_cnt  <= {DR_W{1'b0}};
            err_flag   <= 1'b0;
            done_o     <= 1'b0;
            error_o    <= 1'b0;
            timeout_o  <= 1'b0;
        end else begin
            done_o    <= 1'b0;
            error_o   <= 1'b0;
            timeout_o <= 1'b0;

            case (state)
                // ---------------------------------------------------------
                // IDLE: wait for enable + start pulse, then receive
                // ---------------------------------------------------------
                S_IDLE: begin
                    sample_cnt <= {CNT_W{1'b0}};
                    to_cnt     <= {TO_W{1'b0}};
                    drain_cnt  <= {DR_W{1'b0}};
                    err_flag   <= 1'b0;
                    if (enable_i && start_i)
                        state <= S_RECV;
                end

                // ---------------------------------------------------------
                // RECV: pass-through with sample counting and TLAST gen
                // ---------------------------------------------------------
                S_RECV: begin
                    if (transfer) begin
                        sample_cnt <= sample_cnt + {{(CNT_W-1){1'b0}}, 1'b1};
                        to_cnt     <= {TO_W{1'b0}};   // reset timeout on each transfer

                        if (is_last) begin
                            // Frame complete.  If TLAST arrived on same beat → no
                            // drain needed; otherwise drain the remaining DMA burst.
                            state <= s_axis_tlast ? S_DONE : S_DRAIN;
                        end else if (s_axis_tlast) begin
                            // Early TLAST: truncated frame, signal error
                            err_flag <= 1'b1;
                            state    <= S_DONE;
                        end
                        // else: mid-frame, continue
                    end else if (!s_axis_tvalid) begin
                        // Upstream is silent — advance timeout counter.
                        // Backpressure (tvalid=1, tready=0) does NOT count.
                        if (to_cnt == TO_MAX) begin
                            timeout_o <= 1'b1;
                            err_flag  <= 1'b1;
                            state     <= S_DRAIN;
                        end else begin
                            to_cnt <= to_cnt + {{(TO_W-1){1'b0}}, 1'b1};
                        end
                    end
                    // else: tvalid=1 tready=0 → backpressure stall, hold state
                end

                // ---------------------------------------------------------
                // DRAIN: consume upstream samples until TLAST or drain limit
                // ---------------------------------------------------------
                S_DRAIN: begin
                    if ((s_axis_tvalid && s_axis_tlast) || (drain_cnt == DR_MAX)) begin
                        state     <= S_DONE;
                        drain_cnt <= {DR_W{1'b0}};
                    end else begin
                        drain_cnt <= drain_cnt + {{(DR_W-1){1'b0}}, 1'b1};
                    end
                end

                // ---------------------------------------------------------
                // DONE: pulse status for one cycle then return to idle
                // ---------------------------------------------------------
                S_DONE: begin
                    if (err_flag) error_o <= 1'b1;
                    else          done_o  <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
