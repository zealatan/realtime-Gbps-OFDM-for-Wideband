`timescale 1ns/1ps

// frame_detector (modular wrapper) — P3-12A refactor.
//
// Architecture:
//   frame_detector (this wrapper)
//   ├─ sample_power_sq       (combinatorial I^2+Q^2)
//   ├─ sliding_window_sum    (registered ring-buffer rolling accumulator)
//   └─ frame_detect_fsm      (C reference Case1/Case2 detection FSM)
//
// Pipeline stages (sample_valid → frame_found):
//   S_PROC (sample_valid=1) → posedge: SWS updates, window_valid registered
//   Next posedge: FSM sees window_valid, updates state; frame_found registered
//   Total: ~2 clock cycles from sample_valid to FSM state update.
//
// After all search_len samples issued the wrapper holds in S_DRAIN for
// DRAIN_CYCLES to allow the two-stage pipeline to settle, then exits.
//
// Buffer read interface is unchanged from the monolithic design:
//   buf_rd_addr registered → data valid 1 cycle later (buf has 1-clock latency).
//   Each sample costs 2 wrapper clocks (S_FETCH + S_PROC).
//
// Port interface is identical to the previous monolithic frame_detector.v;
// frac_cfo_frame_corrector_top.v requires NO changes.

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

    // Control
    input  wire                         start,
    input  wire [ENERGY_WIDTH-1:0]      threshold_in,
    input  wire [6:0]                   window_len_in,
    input  wire [3:0]                   hit_count_in,
    input  wire [ADDR_WIDTH-1:0]        search_base,
    input  wire [ADDR_WIDTH:0]          search_len,

    // Buffer read port (1-clock registered latency)
    output reg  [ADDR_WIDTH-1:0]        buf_rd_addr,
    output reg                          buf_rd_en,
    input  wire [15:0]                  buf_rd_data_I,
    input  wire [15:0]                  buf_rd_data_Q,

    // Results
    output reg  [INDEX_WIDTH-1:0]       frame_index,
    output reg                          frame_found,
    output reg                          done,
    output reg                          busy
);

    // -----------------------------------------------------------------------
    // Wrapper FSM states
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE  = 3'd0,
        S_START = 3'd1,     // 1-cycle clear pulse to submodules
        S_FETCH = 3'd2,     // issue buf read, wait 1 cycle
        S_PROC  = 3'd3,     // data valid, drive sample_valid
        S_DRAIN = 3'd4,     // allow SWS→FSM pipeline to settle
        S_DONE  = 3'd5;

    localparam integer DRAIN_CYCLES = 6;
    localparam integer DRAIN_CTR_W  = 3;

    reg [2:0] state;
    reg [DRAIN_CTR_W-1:0] drain_ctr;

    // -----------------------------------------------------------------------
    // Latched control inputs
    // -----------------------------------------------------------------------
    reg [ENERGY_WIDTH-1:0]  thresh_mult;    // threshold_in * window_len_in
    reg [6:0]               wlen_r;
    reg [3:0]               hcnt_r;
    reg [ADDR_WIDTH-1:0]    sbase_r;
    reg [ADDR_WIDTH:0]      slen_r;

    // -----------------------------------------------------------------------
    // Sample counter
    // -----------------------------------------------------------------------
    reg [ADDR_WIDTH:0]  sample_idx;

    // -----------------------------------------------------------------------
    // sub-module clear (1-cycle high when S_START)
    // -----------------------------------------------------------------------
    wire sub_clear = (state == S_START);

    // -----------------------------------------------------------------------
    // sample_valid: high during S_PROC
    // -----------------------------------------------------------------------
    wire sample_valid_w = (state == S_PROC);

    // Current sample's buffer address
    wire [ADDR_WIDTH-1:0] cur_addr = sbase_r + sample_idx[ADDR_WIDTH-1:0];

    // -----------------------------------------------------------------------
    // sample_power_sq instantiation (combinatorial)
    // -----------------------------------------------------------------------
    wire [POWER_WIDTH-1:0] sample_power_w;

    sample_power_sq #(
        .DATA_WIDTH (16),
        .POWER_WIDTH(POWER_WIDTH)
    ) u_pow (
        .i_in     ($signed(buf_rd_data_I)),
        .q_in     ($signed(buf_rd_data_Q)),
        .power_out(sample_power_w)
    );

    // -----------------------------------------------------------------------
    // sliding_window_sum instantiation
    // -----------------------------------------------------------------------
    wire [ENERGY_WIDTH-1:0] win_energy_w;
    wire                    win_valid_w;
    wire [ADDR_WIDTH-1:0]   win_start_w;

    sliding_window_sum #(
        .POWER_WIDTH (POWER_WIDTH),
        .ENERGY_WIDTH(ENERGY_WIDTH),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .MAX_WINDOW  (64)
    ) u_sws (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .clear           (sub_clear),
        .sample_power    (sample_power_w),
        .sample_valid    (sample_valid_w),
        .sample_addr_in  (cur_addr),
        .window_len      (wlen_r),
        .window_energy   (win_energy_w),
        .window_valid    (win_valid_w),
        .window_start_addr(win_start_w)
    );

    // -----------------------------------------------------------------------
    // frame_detect_fsm instantiation
    // -----------------------------------------------------------------------
    wire [INDEX_WIDTH-1:0]  fsm_frame_index_w;
    wire                    fsm_frame_found_w;

    frame_detect_fsm #(
        .ENERGY_WIDTH(ENERGY_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH)
    ) u_fsm (
        .aclk               (aclk),
        .aresetn            (aresetn),
        .clear              (sub_clear),
        .window_energy      (win_energy_w),
        .window_valid       (win_valid_w),
        .window_start_index (win_start_w[INDEX_WIDTH-1:0]),
        .thresh_mult        (thresh_mult),
        .hit_count          (hcnt_r),
        .frame_index        (fsm_frame_index_w),
        .frame_found        (fsm_frame_found_w),
        .busy               (),
        .done               ()
    );

    // -----------------------------------------------------------------------
    // Wrapper FSM
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
            drain_ctr   <= {DRAIN_CTR_W{1'b0}};
            thresh_mult <= {ENERGY_WIDTH{1'b0}};
            wlen_r      <= 7'd0;
            hcnt_r      <= 4'd0;
            sbase_r     <= {ADDR_WIDTH{1'b0}};
            slen_r      <= {(ADDR_WIDTH+1){1'b0}};
        end else begin
            done <= 1'b0;   // default: 1-clock pulse

            case (state)

                // ------------------------------------------------------------
                S_IDLE: begin
                    if (start) begin
                        thresh_mult <= threshold_in * {{6{1'b0}}, window_len_in};
                        wlen_r      <= window_len_in;
                        hcnt_r      <= hit_count_in;
                        sbase_r     <= search_base;
                        slen_r      <= search_len;
                        sample_idx  <= {(ADDR_WIDTH+1){1'b0}};
                        frame_found <= 1'b0;
                        busy        <= 1'b1;
                        state       <= S_START;
                    end
                end

                // ------------------------------------------------------------
                // Hold clear=1 for 1 cycle, then issue first read.
                // ------------------------------------------------------------
                S_START: begin
                    buf_rd_addr <= search_base;
                    buf_rd_en   <= 1'b1;
                    state       <= S_FETCH;
                end

                // ------------------------------------------------------------
                // Wait 1 cycle for buffer registered read to complete.
                // ------------------------------------------------------------
                S_FETCH: begin
                    state <= S_PROC;
                end

                // ------------------------------------------------------------
                // buf_rd_data_I/Q valid. Drive sample_valid (wire).
                // Check for early termination by FSM frame found signal.
                // ------------------------------------------------------------
                S_PROC: begin
                    if (fsm_frame_found_w) begin
                        // FSM found frame from a prior window — stop scanning.
                        buf_rd_en <= 1'b0;
                        state     <= S_DONE;
                    end else if (sample_idx + 1 < slen_r) begin
                        // Advance to next sample
                        sample_idx  <= sample_idx + 1;
                        buf_rd_addr <= sbase_r + sample_idx[ADDR_WIDTH-1:0] + 1;
                        state       <= S_FETCH;
                    end else begin
                        // Search range exhausted; drain pipeline
                        buf_rd_en <= 1'b0;
                        drain_ctr <= {DRAIN_CTR_W{1'b0}};
                        state     <= S_DRAIN;
                    end
                end

                // ------------------------------------------------------------
                // Wait for SWS + FSM pipeline to flush.
                // ------------------------------------------------------------
                S_DRAIN: begin
                    if (fsm_frame_found_w) begin
                        state <= S_DONE;
                    end else if (drain_ctr + 1 == DRAIN_CYCLES[DRAIN_CTR_W-1:0]) begin
                        state <= S_DONE;
                    end else begin
                        drain_ctr <= drain_ctr + 1;
                    end
                end

                // ------------------------------------------------------------
                S_DONE: begin
                    frame_found <= fsm_frame_found_w;
                    frame_index <= fsm_frame_index_w[INDEX_WIDTH-1:0];
                    done        <= 1'b1;
                    busy        <= 1'b0;
                    state       <= S_IDLE;
                end

            endcase
        end
    end

endmodule
