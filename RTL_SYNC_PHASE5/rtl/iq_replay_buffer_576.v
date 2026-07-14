`timescale 1ns/1ps

// iq_replay_buffer_576 — P3-10A
//
// Standalone synthesizable replay buffer: captures FRAME_LEN IQ samples
// into block RAM, then replays them on a downstream AXIS port on request.
//
// FRAME_LEN parameter: default 4032 for the 14-symbol slot
// (NUM_DATA_BLOCKS=12 plus PSS+SSS pair: 14 * (NSC+CP_LEN) = 14*288 = 4032).
// Module name retained as iq_replay_buffer_576 for instantiation
// compatibility with the existing wrapper.
//
// Write side (capture):
//   wr_ready asserted only in S_CAPTURING.
//   Fire = wr_valid & wr_ready.
//   After exactly FRAME_LEN fires, capture_done pulses (1 cycle) and the
//   module enters S_CAPTURED.
//
// Read side (replay):
//   On replay_start pulse (from S_CAPTURED): replay_busy asserts, FRAME_LEN
//   samples stream to rd_valid/rd_ready/rd_data/rd_tlast.
//   rd_tlast asserts on sample index FRAME_LEN-1.
//   replay_done pulses (1 cycle) when the last sample is consumed.
//   Module enters S_DONE; clear required for next capture.
//
// Clear:
//   Synchronous, highest priority. Resets FSM to S_CAPTURING from any state.
//   Safe at any point including mid-capture and mid-replay.
//
// Error:
//   capture_error asserts (sticky) if replay_start received while in
//   S_CAPTURING. Cleared by reset or clear. Does not block replay once
//   S_CAPTURED is reached.
//
// FSM:
//   S_CAPTURING → (FRAME_LEN fires) → S_CAPTURED
//   S_CAPTURED  → (replay_start)    → S_REPLAYING
//   S_REPLAYING → (last consumed)   → S_DONE
//   any state   → (clear or reset)  → S_CAPTURING
//
// Read pipeline (1-cycle BRAM latency):
//   s1: do_read issues address; mem_q valid next cycle (s1_pending=1)
//   s2: output hold register (rd_valid/rd_data/rd_tlast)
//   s2_can_accept = !rd_valid | (rd_valid & rd_ready)
//   do_read = S_REPLAYING & !s1_pending & s2_can_accept & rd_ptr < FRAME_LEN
//   Throughput: 1 sample per 2 cycles.
//
// Synthesis target: Xilinx Artix/Kintex/Zynq
//   (* ram_style = "block" *) infers one BRAM18E2 (576 x 32b < 18 Kb).

module iq_replay_buffer_576 #(
    parameter integer DATA_W    = 32,
    parameter integer FRAME_LEN = 4032,
    parameter integer ADDR_W    = 13   // 2^13 = 8192 >= 4032
)(
    input  wire              clk,
    input  wire              aresetn,
    input  wire              clear,

    // Write side — AXIS slave (capture)
    input  wire              wr_valid,
    output wire              wr_ready,
    input  wire [DATA_W-1:0] wr_data,

    // Capture status
    output reg               capture_done,   // 1-cycle pulse: FRAME_LEN samples stored
    output reg               capture_error,  // sticky: replay_start during S_CAPTURING

    // Replay control
    input  wire              replay_start,   // 1-cycle pulse: begin replay (S_CAPTURED only)
    output reg               replay_busy,    // asserted throughout S_REPLAYING
    output reg               replay_done,    // 1-cycle pulse: last sample consumed

    // Read side — AXIS master (replay output)
    output reg               rd_valid,
    input  wire              rd_ready,
    output reg  [DATA_W-1:0] rd_data,
    output reg               rd_tlast
);

    // -----------------------------------------------------------------------
    // Compile-time parameter check
    // -----------------------------------------------------------------------
    // synthesis translate_off
    initial begin
        if (FRAME_LEN > (1 << ADDR_W))
            $fatal(1, "iq_replay_buffer_576: FRAME_LEN=%0d exceeds 2^ADDR_W=%0d",
                   FRAME_LEN, 1 << ADDR_W);
        if (FRAME_LEN == 0)
            $fatal(1, "iq_replay_buffer_576: FRAME_LEN must be > 0");
    end
    // synthesis translate_on

    // -----------------------------------------------------------------------
    // FSM encoding
    // -----------------------------------------------------------------------
    localparam [1:0]
        S_CAPTURING = 2'd0,
        S_CAPTURED  = 2'd1,
        S_REPLAYING = 2'd2,
        S_DONE      = 2'd3;

    reg [1:0] state;

    // -----------------------------------------------------------------------
    // Memory (infers BRAM18E2 on Xilinx with block ram_style)
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:(1 << ADDR_W) - 1];

    // -----------------------------------------------------------------------
    // Write side
    // -----------------------------------------------------------------------
    reg [ADDR_W-1:0] wr_ptr;

    assign wr_ready = (state == S_CAPTURING);
    wire   wr_fire  = wr_valid & wr_ready;

    always @(posedge clk) begin
        if (wr_fire)
            mem[wr_ptr] <= wr_data;
    end

    // -----------------------------------------------------------------------
    // Read pipeline
    //   s1: address issued on do_read; mem_q captures result next cycle
    //   s2: output hold register — rd_valid/rd_data/rd_tlast
    // -----------------------------------------------------------------------
    reg [ADDR_W-1:0] rd_ptr;
    reg              s1_pending;   // read in-flight; result arrives next cycle
    reg              s1_last;      // pending read is the FRAME_LEN-1 sample
    reg [DATA_W-1:0] mem_q;        // registered memory output

    // s2 can accept a new result: s2 is empty, or will be consumed this cycle
    wire s2_can_accept = !rd_valid | (rd_valid & rd_ready);

    // Issue a new memory read when all four conditions hold
    wire do_read = (state == S_REPLAYING) &
                   (~s1_pending)           &
                   s2_can_accept           &
                   (rd_ptr < FRAME_LEN);

    always @(posedge clk) begin
        if (do_read)
            mem_q <= mem[rd_ptr];
    end

    // -----------------------------------------------------------------------
    // Main FSM — state, write side, read address pipeline, status pulses
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            state         <= S_CAPTURING;
            wr_ptr        <= {ADDR_W{1'b0}};
            rd_ptr        <= {ADDR_W{1'b0}};
            s1_pending    <= 1'b0;
            s1_last       <= 1'b0;
            capture_done  <= 1'b0;
            capture_error <= 1'b0;
            replay_busy   <= 1'b0;
            replay_done   <= 1'b0;
        end else begin
            // Pulse outputs default to 0 every cycle
            capture_done <= 1'b0;
            replay_done  <= 1'b0;

            if (clear) begin
                // Synchronous clear: return to S_CAPTURING unconditionally
                state         <= S_CAPTURING;
                wr_ptr        <= {ADDR_W{1'b0}};
                rd_ptr        <= {ADDR_W{1'b0}};
                s1_pending    <= 1'b0;
                s1_last       <= 1'b0;
                capture_error <= 1'b0;
                replay_busy   <= 1'b0;

            end else begin
                case (state)

                    // ----------------------------------------------------------
                    // S_CAPTURING: accept writes, detect premature replay
                    // ----------------------------------------------------------
                    S_CAPTURING: begin
                        if (replay_start)
                            capture_error <= 1'b1;

                        if (wr_fire) begin
                            if (wr_ptr == FRAME_LEN - 1) begin
                                capture_done <= 1'b1;
                                wr_ptr       <= {ADDR_W{1'b0}};
                                state        <= S_CAPTURED;
                            end else
                                wr_ptr <= wr_ptr + 1'b1;
                        end
                    end

                    // ----------------------------------------------------------
                    // S_CAPTURED: wait for replay_start
                    // ----------------------------------------------------------
                    S_CAPTURED: begin
                        if (replay_start) begin
                            state       <= S_REPLAYING;
                            replay_busy <= 1'b1;
                            rd_ptr      <= {ADDR_W{1'b0}};
                            s1_pending  <= 1'b0;
                            s1_last     <= 1'b0;
                        end
                    end

                    // ----------------------------------------------------------
                    // S_REPLAYING: issue memory reads, stream output, detect end
                    // ----------------------------------------------------------
                    S_REPLAYING: begin
                        // Advance read address pipeline
                        if (do_read) begin
                            s1_pending <= 1'b1;
                            s1_last    <= (rd_ptr == FRAME_LEN - 1);
                            rd_ptr     <= rd_ptr + 1'b1;
                        end else if (s1_pending) begin
                            // Result is being captured into output stage this cycle
                            s1_pending <= 1'b0;
                        end

                        // Detect end: last sample consumed by downstream
                        if (rd_valid & rd_ready & rd_tlast) begin
                            replay_done <= 1'b1;
                            replay_busy <= 1'b0;
                            state       <= S_DONE;
                        end
                    end

                    // ----------------------------------------------------------
                    // S_DONE: replay complete; wait for clear
                    // ----------------------------------------------------------
                    S_DONE: ;

                    default: state <= S_CAPTURING;

                endcase
            end
        end
    end

    // -----------------------------------------------------------------------
    // Output stage (s2): capture mem_q when s1_pending; hold under backpressure
    //
    // Priority (highest first):
    //   1. reset / clear  → flush
    //   2. s1_pending      → load new result from mem_q
    //   3. rd_valid & rd_ready → consume (no new result incoming)
    //
    // At any cycle where s1_pending=1, rd_valid is guaranteed 0 (a read was
    // issued only when s2_can_accept, which ensures rd_valid will be 0 by
    // the time the result arrives).
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            rd_valid <= 1'b0;
            rd_data  <= {DATA_W{1'b0}};
            rd_tlast <= 1'b0;
        end else if (clear) begin
            rd_valid <= 1'b0;
            rd_data  <= {DATA_W{1'b0}};
            rd_tlast <= 1'b0;
        end else if (s1_pending) begin
            // Memory result stable in mem_q: load into output register
            rd_data  <= mem_q;
            rd_tlast <= s1_last;
            rd_valid <= 1'b1;
        end else if (rd_valid & rd_ready) begin
            // Sample consumed; no new result arriving this cycle
            rd_valid <= 1'b0;
            rd_tlast <= 1'b0;
        end
    end

endmodule
