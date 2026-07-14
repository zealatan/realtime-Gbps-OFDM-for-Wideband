`timescale 1ns/1ps

// frame_detect_fsm: C reference frame detection semantics only.
//
// Implements exactly:
//   if first_window_energy <= thresh_mult:   # Case 1
//       scan forward for hit_count consecutive windows > thresh_mult
//   else:                                    # Case 2
//       skip windows until energy <= thresh_mult
//       then scan for hit_count consecutive windows > thresh_mult
//
// Inputs come from sliding_window_sum (one pulse per complete window).
// thresh_mult is pre-computed by the wrapper as threshold_in * window_len.
//
// No sample power computation, no rolling accumulation, no buffer read logic.
//
// FSM states:
//   IDLE          — waiting for clear deassertion and first window_valid
//   CHECK_FIRST   — classify first window as Case1 or Case2
//   CASE1_SCAN    — Case1: count consecutive above-threshold windows
//   CASE2_SKIP    — Case2: wait for energy to fall to or below threshold
//   CASE2_SCAN    — Case2: count consecutive above-threshold windows after skip
//   FOUND         — latch frame_index, assert frame_found
//   FSM_DONE      — one-cycle done pulse
//
// frame_found and frame_index are stable from FOUND state until clear or reset.

module frame_detect_fsm #(
    parameter integer ENERGY_WIDTH = 40,
    parameter integer INDEX_WIDTH  = 12
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         clear,              // synchronous clear from wrapper

    // From sliding_window_sum
    input  wire [ENERGY_WIDTH-1:0]      window_energy,
    input  wire                         window_valid,
    input  wire [INDEX_WIDTH-1:0]       window_start_index,

    // From wrapper (pre-computed at start)
    input  wire [ENERGY_WIDTH-1:0]      thresh_mult,        // threshold_in * window_len
    input  wire [3:0]                   hit_count,          // consecutive hits required

    // Results
    output reg  [INDEX_WIDTH-1:0]       frame_index,
    output reg                          frame_found,
    output reg                          busy,
    output reg                          done
);

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_CHECK_FIRST= 3'd1,
        S_CASE1_SCAN = 3'd2,
        S_CASE2_SKIP = 3'd3,
        S_CASE2_SCAN = 3'd4,
        S_FOUND      = 3'd5,
        S_FSM_DONE   = 3'd6;

    reg [2:0] state;
    reg [3:0] hit_ctr;
    reg [INDEX_WIDTH-1:0] first_hit_addr;

    wire above_thresh = (window_energy > thresh_mult);

    always @(posedge aclk) begin
        if (!aresetn || clear) begin
            state          <= S_IDLE;
            hit_ctr        <= 4'd0;
            first_hit_addr <= {INDEX_WIDTH{1'b0}};
            frame_found    <= 1'b0;
            frame_index    <= {INDEX_WIDTH{1'b0}};
            busy           <= 1'b0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;   // default: one-cycle pulse

            case (state)

                S_IDLE: begin
                    if (window_valid) begin
                        busy <= 1'b1;
                        if (above_thresh) begin
                            state <= S_CASE2_SKIP;
                        end else begin
                            hit_ctr <= 4'd0;
                            state   <= S_CASE1_SCAN;
                        end
                    end
                end

                S_CASE1_SCAN: begin
                    if (window_valid) begin
                        if (above_thresh) begin
                            if (hit_ctr == 4'd0)
                                first_hit_addr <= window_start_index;
                            if (hit_ctr + 1 >= hit_count) begin
                                state <= S_FOUND;
                            end else begin
                                hit_ctr <= hit_ctr + 4'd1;
                            end
                        end else begin
                            hit_ctr <= 4'd0;
                        end
                    end
                end

                S_CASE2_SKIP: begin
                    if (window_valid) begin
                        if (!above_thresh) begin
                            // Energy dropped — begin Case2 scan
                            hit_ctr <= 4'd0;
                            state   <= S_CASE2_SCAN;
                        end
                        // Still above threshold: keep skipping
                    end
                end

                S_CASE2_SCAN: begin
                    if (window_valid) begin
                        if (above_thresh) begin
                            if (hit_ctr == 4'd0)
                                first_hit_addr <= window_start_index;
                            if (hit_ctr + 1 >= hit_count) begin
                                state <= S_FOUND;
                            end else begin
                                hit_ctr <= hit_ctr + 4'd1;
                            end
                        end else begin
                            hit_ctr <= 4'd0;
                        end
                    end
                end

                S_FOUND: begin
                    frame_found <= 1'b1;
                    frame_index <= first_hit_addr;
                    state       <= S_FSM_DONE;
                end

                S_FSM_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
