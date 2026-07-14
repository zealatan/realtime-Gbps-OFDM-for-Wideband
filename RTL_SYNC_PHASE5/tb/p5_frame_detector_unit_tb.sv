`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// p5_frame_detector_unit_tb
//
// Self-contained unit testbench for rtl/frame_detector.v.
// Does NOT pull in phase3_sync_top, replay buffers, or any of the
// retired Meyr modules — only the four files the DUT needs:
//   - rtl/frame_detector.v
//   - rtl/sample_power_sq.v        (declared by dependency, not instantiated by wrapper)
//   - rtl/sliding_window_sum.v
//   - rtl/frame_detect_fsm.v
//
// The buffer read interface is modelled by a simple `reg` array stub with a
// 1-cycle registered read (matches the iq_frame_buffer behaviour expected by
// the wrapper).
//
// Stimulus:
//   golden/phase3_iq_stimulus_q15.hex (704 lines), each line {Q[15:0], I[15:0]}.
//
// Golden frame index (from C reference, see
// tb/p3_12b_frame_detector_golden_regression_tb.sv constants):
//   GOLDEN_FRAME_INDEX = 41   ±1 sample
//
// Gate output (the regression runner greps for these exact lines):
//   GATE_P5_FRAME_UNIT: PASS
//   GATE_P5_FRAME_UNIT: FAIL
// -----------------------------------------------------------------------------

module p5_frame_detector_unit_tb;

    // --------------------------------------------------------------------- //
    // Parameters
    // --------------------------------------------------------------------- //
    localparam integer DATA_WIDTH   = 32;
    localparam integer ADDR_WIDTH   = 12;
    localparam integer INDEX_WIDTH  = 12;
    localparam integer POWER_WIDTH  = 33;
    localparam integer ENERGY_WIDTH = 40;
    localparam integer WINDOW_LEN   = 25;
    localparam integer HIT_COUNT    = 10;

    // 40-bit threshold (fits in ENERGY_WIDTH=40)
    localparam [ENERGY_WIDTH-1:0] THRESHOLD_VAL = 40'd40000;

    // Search range
    localparam [ADDR_WIDTH-1:0]   SEARCH_BASE_VAL = 12'd0;
    localparam [ADDR_WIDTH:0]     SEARCH_LEN_VAL  = 13'd128;

    localparam integer GOLDEN_FRAME_INDEX = 41;
    localparam integer FRAME_TOL          = 1;

    localparam real    CLK_HALF   = 5.0;     // 100 MHz
    localparam integer WDG_CYCLES = 100000;
    localparam integer BUF_DEPTH  = 704;

    // --------------------------------------------------------------------- //
    // Clock / reset
    // --------------------------------------------------------------------- //
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #(CLK_HALF) aclk = ~aclk;

    // --------------------------------------------------------------------- //
    // IQ buffer stub: read 32-bit {Q[15:0], I[15:0]} from hex file
    // and present it on buf_rd_data_I/Q with 1-cycle registered latency.
    // --------------------------------------------------------------------- //
    reg [31:0] iq_buf [0:BUF_DEPTH-1];

    // DUT outputs to the buffer stub
    wire [ADDR_WIDTH-1:0] buf_rd_addr_w;
    wire                  buf_rd_en_w;

    // Buffer registered read
    reg [31:0] buf_rd_word_r;
    always @(posedge aclk) begin
        if (!aresetn) begin
            buf_rd_word_r <= 32'h0;
        end else if (buf_rd_en_w) begin
            // Range-protected read
            if (buf_rd_addr_w < BUF_DEPTH[ADDR_WIDTH-1:0])
                buf_rd_word_r <= iq_buf[buf_rd_addr_w];
            else
                buf_rd_word_r <= 32'h0;
        end
    end

    wire [15:0] buf_rd_data_I_w = buf_rd_word_r[15:0];
    wire [15:0] buf_rd_data_Q_w = buf_rd_word_r[31:16];

    // --------------------------------------------------------------------- //
    // DUT
    // --------------------------------------------------------------------- //
    reg                          start;
    wire                         done_w;
    wire                         busy_w;
    wire                         frame_found_w;
    wire [INDEX_WIDTH-1:0]       frame_index_w;

    frame_detector #(
        .DATA_WIDTH   (DATA_WIDTH),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .POWER_WIDTH  (POWER_WIDTH),
        .ENERGY_WIDTH (ENERGY_WIDTH),
        .WINDOW_LEN   (WINDOW_LEN),
        .HIT_COUNT    (HIT_COUNT),
        .THRESHOLD    (40'd10240000)   // wrapper default, overridden by threshold_in
    ) u_dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .start          (start),
        .threshold_in   (THRESHOLD_VAL),
        .window_len_in  (7'd25),
        .hit_count_in   (4'd10),
        .search_base    (SEARCH_BASE_VAL),
        .search_len     (SEARCH_LEN_VAL),
        .buf_rd_addr    (buf_rd_addr_w),
        .buf_rd_en      (buf_rd_en_w),
        .buf_rd_data_I  (buf_rd_data_I_w),
        .buf_rd_data_Q  (buf_rd_data_Q_w),
        .frame_index    (frame_index_w),
        .frame_found    (frame_found_w),
        .done           (done_w),
        .busy           (busy_w)
    );

    // --------------------------------------------------------------------- //
    // Watchdog + capture
    // --------------------------------------------------------------------- //
    integer cycle_cnt;
    reg     done_seen;
    reg     frame_found_cap;
    reg [INDEX_WIDTH-1:0] frame_index_cap;

    always @(posedge aclk) begin
        if (!aresetn) begin
            cycle_cnt       <= 0;
            done_seen       <= 1'b0;
            frame_found_cap <= 1'b0;
            frame_index_cap <= {INDEX_WIDTH{1'b0}};
        end else begin
            cycle_cnt <= cycle_cnt + 1;
            if (done_w && !done_seen) begin
                done_seen       <= 1'b1;
                frame_found_cap <= frame_found_w;
                frame_index_cap <= frame_index_w;
            end
        end
    end

    // --------------------------------------------------------------------- //
    // Main test sequence
    // --------------------------------------------------------------------- //
    integer i;
    integer delta;
    integer fail_cnt;

    initial begin : tb_main
        // Init buffer
        for (i = 0; i < BUF_DEPTH; i = i + 1)
            iq_buf[i] = 32'h0;

        // Load IQ stimulus
        $readmemh("golden/phase3_iq_stimulus_q15.hex", iq_buf, 0, BUF_DEPTH-1);

        start    = 1'b0;
        fail_cnt = 0;

        // Reset
        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4) @(posedge aclk);

        // Single-cycle start pulse
        @(posedge aclk);
        start <= 1'b1;
        @(posedge aclk);
        start <= 1'b0;

        // Wait for done or watchdog
        fork
            begin : wait_done
                while (!done_seen) @(posedge aclk);
            end
            begin : wait_wdg
                repeat (WDG_CYCLES) @(posedge aclk);
                $display("[FAIL] WDG TIMEOUT: no done within %0d cycles", WDG_CYCLES);
                fail_cnt = fail_cnt + 1;
                disable wait_done;
            end
        join_any
        disable fork;

        @(posedge aclk);

        // --------------------------- Checks ----------------------------- //
        $display("");
        $display("=== P5 frame_detector unit checks ===");
        $display("  cycle_cnt          = %0d", cycle_cnt);
        $display("  done_seen          = %0b", done_seen);
        $display("  frame_found_cap    = %0b", frame_found_cap);
        $display("  frame_index_cap    = %0d (golden=%0d, tol=%0d)",
                 frame_index_cap, GOLDEN_FRAME_INDEX, FRAME_TOL);
        $display("");

        if (!done_seen) begin
            $display("[FAIL] C0 done never asserted");
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("[PASS] C0 done asserted");
        end

        if (frame_found_cap !== 1'b1) begin
            $display("[FAIL] C1 frame_found != 1 (got=%0b)", frame_found_cap);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("[PASS] C1 frame_found == 1");
        end

        // |frame_index_cap - golden| <= tol  (no $abs/int' needed)
        if (frame_index_cap >= GOLDEN_FRAME_INDEX)
            delta = frame_index_cap - GOLDEN_FRAME_INDEX;
        else
            delta = GOLDEN_FRAME_INDEX - frame_index_cap;

        if (delta > FRAME_TOL) begin
            $display("[FAIL] C2 frame_index out of tolerance  got=%0d exp=%0d delta=%0d tol=%0d",
                     frame_index_cap, GOLDEN_FRAME_INDEX, delta, FRAME_TOL);
            fail_cnt = fail_cnt + 1;
        end else begin
            $display("[PASS] C2 frame_index within tolerance  got=%0d exp=%0d delta=%0d",
                     frame_index_cap, GOLDEN_FRAME_INDEX, delta);
        end

        $display("");
        if (fail_cnt == 0) begin
            $display("GATE_P5_FRAME_UNIT: PASS");
        end else begin
            $display("GATE_P5_FRAME_UNIT: FAIL  (%0d check(s) failed)", fail_cnt);
        end

        $finish;
    end

endmodule
