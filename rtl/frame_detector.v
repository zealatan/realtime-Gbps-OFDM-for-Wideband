`timescale 1ns/1ps

// frame_detector: sliding-window energy-based frame start detector.
//
// Algorithm matches C frame_detector() (Toan's version, receiver.c:327):
//   envelopeBlock[j] = (1/wndLen) * sum_{i=j}^{j+wndLen-1} (I[i]^2 + Q[i]^2)
//   Case A (window[0] < threshold): scan forward for HIT_COUNT consecutive
//     above-threshold windows.
//   Case B (window[0] >= threshold): skip initial above-threshold region,
//     then behave like Case A.
//   frame_index = start address of the first window in the winning run.
//
// RTL avoids division: compares running energy_acc (window SUM) vs
// threshold_in * window_len_in.  The caller must supply threshold_in already
// scaled for Q1.15 input format (default = C_threshold × 256 = 10,240,000).
//
// Buffer read interface has 1-clock registered latency (matches iq_frame_buffer):
//   buf_rd_addr registered → data valid 1 cycle later (in S_PROC).
//   Each sample costs 2 clocks (S_FETCH + S_PROC).
//
// Parameters:
//   DATA_WIDTH    Sample word width (default 32 = {Q[31:16], I[15:0]})
//   ADDR_WIDTH    Buffer address width (default 12)
//   INDEX_WIDTH   frame_index output width (default 12)
//   POWER_WIDTH   Per-sample I^2+Q^2 width (default 33; max ~2^31 fits in 33 bits)
//   ENERGY_WIDTH  Accumulator / threshold-product width (default 40)
//   WINDOW_LEN    Default window length (overridable at run-time via window_len_in)
//   HIT_COUNT     Default consecutive-hit count (overridable via hit_count_in)
//   THRESHOLD     Default threshold (Q1.15-scaled; overridable via threshold_in)

module frame_detector #(
    parameter integer DATA_WIDTH    = 32,
    parameter integer ADDR_WIDTH    = 12,
    parameter integer INDEX_WIDTH   = 12,
    parameter integer POWER_WIDTH   = 33,
    parameter integer ENERGY_WIDTH  = 40,
    parameter integer WINDOW_LEN    = 25,
    parameter integer HIT_COUNT     = 10,
    parameter integer THRESHOLD     = 10240000
) (
    input  wire                         aclk,
    input  wire                         aresetn,

    // ---- Control (from sync_control_fsm or testbench) ----
    input  wire                         start,
    input  wire [ENERGY_WIDTH-1:0]      threshold_in,   // Q1.15-scaled sum threshold
    input  wire [6:0]                   window_len_in,  // samples per window (1..64)
    input  wire [3:0]                   hit_count_in,   // consecutive hits required (1..15)
    input  wire [ADDR_WIDTH-1:0]        search_base,    // first buffer address to scan
    input  wire [ADDR_WIDTH:0]          search_len,     // total samples to scan

    // ---- Buffer read port (1-clock registered latency) ----
    output reg  [ADDR_WIDTH-1:0]        buf_rd_addr,
    output reg                          buf_rd_en,
    input  wire [15:0]                  buf_rd_data_I,
    input  wire [15:0]                  buf_rd_data_Q,

    // ---- Results ----
    output reg  [INDEX_WIDTH-1:0]       frame_index,    // buffer address of frame start
    output reg                          frame_found,
    output reg                          done,           // 1-clock pulse
    output reg                          busy
);

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                     S_FETCH = 2'd1,
                     S_PROC  = 2'd2,
                     S_DONE  = 2'd3;
    reg [1:0] state;

    // -----------------------------------------------------------------------
    // Latched control inputs (captured when start fires)
    // -----------------------------------------------------------------------
    reg [ENERGY_WIDTH-1:0]  thresh_mult;    // threshold_in * window_len_in
    reg [6:0]               wlen_r;
    reg [3:0]               hcnt_r;
    reg [ADDR_WIDTH-1:0]    sbase_r;
    reg [ADDR_WIDTH:0]      slen_r;

    // -----------------------------------------------------------------------
    // Sliding-window power accumulator
    // -----------------------------------------------------------------------
    reg [POWER_WIDTH-1:0]   pow_buf [0:63]; // circular power buffer (max window = 64)
    reg [5:0]               pow_wr_ptr;     // write pointer, wraps modulo wlen_r
    reg [ENERGY_WIDTH-1:0]  energy_acc;     // running window energy sum
    reg [6:0]               win_fill;       // samples currently in window (0 → wlen_r)

    // -----------------------------------------------------------------------
    // Scan state
    // -----------------------------------------------------------------------
    reg [ADDR_WIDTH:0]      sample_idx;     // index of sample currently being processed
    reg                     skip_phase;     // high while skipping Case B initial region
    reg [3:0]               hit_ctr;        // consecutive above-threshold windows seen
    reg [INDEX_WIDTH-1:0]   first_hit_addr; // buffer addr of first window in current run

    // -----------------------------------------------------------------------
    // Combinatorial signals
    // -----------------------------------------------------------------------

    // Per-sample energy (always non-negative; max (32767^2)*2 < 2^31 fits in POWER_WIDTH=33)
    wire [POWER_WIDTH-1:0] new_power =
        ($signed(buf_rd_data_I) * $signed(buf_rd_data_I)) +
        ($signed(buf_rd_data_Q) * $signed(buf_rd_data_Q));

    // Start address of the window whose newest sample is sample_idx
    wire [ADDR_WIDTH-1:0] cur_win_start =
        sbase_r + sample_idx[ADDR_WIDTH-1:0] - {{(ADDR_WIDTH-7){1'b0}}, wlen_r} + 1;

    // -----------------------------------------------------------------------
    // Module-level temporaries (blocking-assigned in always; synthesize as wires)
    // -----------------------------------------------------------------------
    reg [POWER_WIDTH-1:0]   oldest_pwr;
    reg [ENERGY_WIDTH-1:0]  next_acc;
    reg                     win_was_full;   // win_fill >= wlen_r before this sample
    reg                     first_win_done; // win_fill == wlen_r-1: first window completes
    reg                     found_flag;     // set when hit run reaches hcnt_r

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            frame_found <= 1'b0;
            frame_index <= {INDEX_WIDTH{1'b0}};
            buf_rd_addr <= {ADDR_WIDTH{1'b0}};
            buf_rd_en   <= 1'b0;
            sample_idx  <= {(ADDR_WIDTH+1){1'b0}};
            win_fill    <= 7'd0;
            energy_acc  <= {ENERGY_WIDTH{1'b0}};
            pow_wr_ptr  <= 6'd0;
            hit_ctr     <= 4'd0;
            skip_phase  <= 1'b0;
        end else begin
            done <= 1'b0;   // default: 1-clock pulse

            case (state)

                // --------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        // Latch control inputs
                        thresh_mult <= threshold_in * window_len_in;
                        wlen_r      <= window_len_in;
                        hcnt_r      <= hit_count_in;
                        sbase_r     <= search_base;
                        slen_r      <= search_len;

                        // Clear scan state
                        energy_acc  <= {ENERGY_WIDTH{1'b0}};
                        pow_wr_ptr  <= 6'd0;
                        win_fill    <= 7'd0;
                        sample_idx  <= {(ADDR_WIDTH+1){1'b0}};
                        hit_ctr     <= 4'd0;
                        skip_phase  <= 1'b0;
                        frame_found <= 1'b0;

                        // Issue first buffer read
                        buf_rd_addr <= search_base;
                        buf_rd_en   <= 1'b1;
                        busy        <= 1'b1;
                        state       <= S_FETCH;
                    end
                end

                // --------------------------------------------------------
                // Wait exactly 1 cycle for iq_frame_buffer to register addr
                // and produce rd_data (1-clock latency).
                // --------------------------------------------------------
                S_FETCH: begin
                    state <= S_PROC;
                end

                // --------------------------------------------------------
                // buf_rd_data_I/Q are valid for sample[sample_idx].
                // --------------------------------------------------------
                S_PROC: begin
                    found_flag    = 1'b0;
                    win_was_full  = (win_fill >= wlen_r);
                    first_win_done= (win_fill == wlen_r - 1);

                    // --- Step 1: update sliding-window accumulator -------
                    oldest_pwr = pow_buf[pow_wr_ptr];
                    pow_buf[pow_wr_ptr] <= new_power;
                    pow_wr_ptr <= (pow_wr_ptr == wlen_r - 1) ? 6'd0 :
                                                               pow_wr_ptr + 1;

                    if (!win_was_full) begin
                        next_acc = energy_acc + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, new_power};
                        win_fill <= win_fill + 1;
                    end else begin
                        next_acc = energy_acc
                                 + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, new_power}
                                 - {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, oldest_pwr};
                    end
                    energy_acc <= next_acc;

                    // --- Step 2: threshold comparison --------------------
                    if (first_win_done) begin
                        // First window just completed: determine Case A vs B
                        if (next_acc > thresh_mult)
                            skip_phase <= 1'b1;   // Case B: above threshold at start
                        // Case A: skip_phase stays 0; scanning begins on next window
                    end else if (win_was_full) begin
                        // Sliding-window step: apply Case A / Case B logic
                        if (skip_phase) begin
                            // Case B skip: wait for first below-threshold window
                            if (next_acc <= thresh_mult)
                                skip_phase <= 1'b0;
                        end else begin
                            // Scanning: count consecutive above-threshold windows
                            if (next_acc > thresh_mult) begin
                                if (hit_ctr + 1 >= hcnt_r) begin
                                    // Run of hcnt_r consecutive hits achieved
                                    frame_index <= (hit_ctr == 4'd0) ?
                                                   cur_win_start[INDEX_WIDTH-1:0] :
                                                   first_hit_addr;
                                    frame_found <= 1'b1;
                                    found_flag  = 1'b1;
                                end else begin
                                    if (hit_ctr == 4'd0)
                                        first_hit_addr <= cur_win_start[INDEX_WIDTH-1:0];
                                    hit_ctr <= hit_ctr + 1;
                                end
                            end else begin
                                hit_ctr <= 4'd0;
                            end
                        end
                    end

                    // --- Step 3: advance or terminate -------------------
                    if (found_flag) begin
                        buf_rd_en <= 1'b0;
                        state     <= S_DONE;
                    end else if (sample_idx + 1 < slen_r) begin
                        buf_rd_addr <= sbase_r + sample_idx[ADDR_WIDTH-1:0] + 1;
                        sample_idx  <= sample_idx + 1;
                        state       <= S_FETCH;
                    end else begin
                        // Exhausted search range without finding frame
                        buf_rd_en <= 1'b0;
                        state     <= S_DONE;
                    end
                end

                // --------------------------------------------------------
                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
