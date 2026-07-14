`timescale 1ns/1ps

// P3-10A testbench for iq_replay_buffer_576
//
// Tests:
//   T01  reset defaults
//   T02  capture exactly 4032 samples, capture_done fires (14-symbol slot)
//   T03  replay exactly 4032 samples, rd_tlast on final sample
//   T04  output backpressure during replay
//   T05  clear mid-capture
//   T06  replay_start before capture_done (capture_error asserted, ignored)
//   T07  two captures back-to-back with clear
//   T08  randomized rd_ready stalls
//
// Pass criterion: tb_pass==N, tb_fail==0  (CI_GATE PASS)
//
// Compatibility: non-automatic tasks; module-level result vars.
//   Works with iverilog 11 -g2012.

module p3_10a_iq_replay_buffer_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer DATA_W     = 32;
    localparam integer FRAME_LEN  = 4032;   // 14-symbol slot (NUM_BLOCKS_PER_SLOT=14)
    localparam integer ADDR_W     = 13;     // 2^13 = 8192 >= 4032
    localparam integer CLK_HALF   = 5;      // 10 ns period
    localparam integer TIMEOUT    = 210000; // per-loop watchdog (cycles), scaled 7x

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    reg               clk;
    reg               aresetn;
    reg               clear;

    reg               wr_valid;
    reg  [DATA_W-1:0] wr_data;
    wire              wr_ready;

    wire              capture_done;
    wire              capture_error;

    reg               replay_start;
    wire              replay_busy;
    wire              replay_done;

    wire              rd_valid;
    reg               rd_ready;
    wire [DATA_W-1:0] rd_data;
    wire              rd_tlast;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    iq_replay_buffer_576 #(
        .DATA_W    (DATA_W),
        .FRAME_LEN (FRAME_LEN),
        .ADDR_W    (ADDR_W)
    ) u_dut (
        .clk          (clk),
        .aresetn      (aresetn),
        .clear        (clear),
        .wr_valid     (wr_valid),
        .wr_ready     (wr_ready),
        .wr_data      (wr_data),
        .capture_done (capture_done),
        .capture_error(capture_error),
        .replay_start (replay_start),
        .replay_busy  (replay_busy),
        .replay_done  (replay_done),
        .rd_valid     (rd_valid),
        .rd_ready     (rd_ready),
        .rd_data      (rd_data),
        .rd_tlast     (rd_tlast)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial clk = 1'b0;
    always #CLK_HALF clk = ~clk;

    // -----------------------------------------------------------------------
    // Scoreboard + shared state
    // -----------------------------------------------------------------------
    integer tb_pass;
    integer tb_fail;

    // Mirror of what was written — used for data verification
    reg [DATA_W-1:0] exp_mem [0:FRAME_LEN-1];

    // Shared output vars for non-automatic tasks (set by task, read by tests)
    integer cap_fires;
    integer rp_rx_count;
    integer rp_tlast_idx;
    integer rp_data_ok;

    // -----------------------------------------------------------------------
    // CHECK helpers — compare and accumulate pass/fail
    // -----------------------------------------------------------------------
    task chk1;
        input [159:0] name;
        input         actual;
        input         expected;
        begin
            if (actual === expected) begin
                $display("  PASS [%s] = %0b", name, actual);
                tb_pass = tb_pass + 1;
            end else begin
                $display("  FAIL [%s] got %0b, exp %0b", name, actual, expected);
                tb_fail = tb_fail + 1;
            end
        end
    endtask

    task chk32;
        input [159:0] name;
        input [31:0]  actual;
        input [31:0]  expected;
        begin
            if (actual === expected) begin
                $display("  PASS [%s] = %0d", name, actual);
                tb_pass = tb_pass + 1;
            end else begin
                $display("  FAIL [%s] got %0d (0x%08x), exp %0d (0x%08x)",
                         name, actual, actual, expected, expected);
                tb_fail = tb_fail + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // RESET helper
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            aresetn      = 1'b0;
            clear        = 1'b0;
            wr_valid     = 1'b0;
            wr_data      = {DATA_W{1'b0}};
            replay_start = 1'b0;
            rd_ready     = 1'b0;
            repeat (6) @(posedge clk);
            aresetn = 1'b1;
            repeat (2) @(posedge clk);
            #1;
        end
    endtask

    // -----------------------------------------------------------------------
    // CAPTURE helper
    //   Drives wr_valid=1 until capture_done fires.
    //   Stores accepted samples in exp_mem[].
    //   Sets cap_fires = number of accepted writes.
    //   base: data pattern start value.
    // -----------------------------------------------------------------------
    task do_capture;
        input [31:0] base;
        integer f, tcnt;
        begin
            f    = 0;
            tcnt = 0;
            wr_valid = 1'b1;
            wr_data  = base;
            while (f < FRAME_LEN) begin
                @(posedge clk); #1;
                if (wr_ready & wr_valid) begin
                    exp_mem[f] = wr_data;
                    f          = f + 1;
                    wr_data    = base + f;
                end
                tcnt = tcnt + 1;
                if (tcnt > TIMEOUT)
                    $fatal(1, "do_capture: timeout after %0d cycles", tcnt);
            end
            // Wait one extra cycle for capture_done to settle
            @(posedge clk); #1;
            wr_valid  = 1'b0;
            cap_fires = f;
        end
    endtask

    // -----------------------------------------------------------------------
    // REPLAY helper
    //   Asserts replay_start, then receives FRAME_LEN samples.
    //   use_bp: insert rd_ready=0 for bp_cycles at sample stall_at.
    //   Sets rp_rx_count, rp_tlast_idx, rp_data_ok.
    // -----------------------------------------------------------------------
    task do_replay;
        input         use_bp;
        input integer stall_at;
        input integer bp_cycles;
        integer r, tcnt, j;
        begin
            r    = 0;
            tcnt = 0;
            rp_rx_count  = 0;
            rp_tlast_idx = -1;
            rp_data_ok   = 1;

            rd_ready     = 1'b1;
            replay_start = 1'b1;
            @(posedge clk); #1;
            replay_start = 1'b0;

            while (r < FRAME_LEN) begin
                // Insert backpressure stall at requested sample index
                if (use_bp & (r == stall_at)) begin
                    rd_ready = 1'b0;
                    repeat (bp_cycles) @(posedge clk);
                    #1;
                    rd_ready = 1'b1;
                end

                @(posedge clk); #1;
                if (rd_valid & rd_ready) begin
                    if (rd_data !== exp_mem[r]) begin
                        $display("    DATA MISMATCH s%0d: got 0x%08x exp 0x%08x",
                                 r, rd_data, exp_mem[r]);
                        rp_data_ok = 0;
                    end
                    if (rd_tlast)
                        rp_tlast_idx = r;
                    r = r + 1;
                end
                tcnt = tcnt + 1;
                if (tcnt > TIMEOUT)
                    $fatal(1, "do_replay: timeout at sample %0d", r);
            end
            // Wait one extra cycle for replay_done
            @(posedge clk); #1;
            rd_ready    = 1'b0;
            rp_rx_count = r;
        end
    endtask

    // -----------------------------------------------------------------------
    // REPLAY with randomized backpressure
    //   Uses $random for ~50% rd_ready stall rate.
    //   Sets rp_rx_count, rp_tlast_idx, rp_data_ok.
    // -----------------------------------------------------------------------
    task do_replay_rand;
        integer r, tcnt, rnd_val;
        begin
            r    = 0;
            tcnt = 0;
            rp_rx_count  = 0;
            rp_tlast_idx = -1;
            rp_data_ok   = 1;

            replay_start = 1'b1;
            @(posedge clk); #1;
            replay_start = 1'b0;

            while (r < FRAME_LEN) begin
                // Randomize rd_ready: 0 or 1
                rnd_val  = $random;
                rd_ready = rnd_val[0];

                @(posedge clk); #1;
                if (rd_valid & rd_ready) begin
                    if (rd_data !== exp_mem[r]) begin
                        $display("    T08 DATA MISMATCH s%0d: got 0x%08x exp 0x%08x",
                                 r, rd_data, exp_mem[r]);
                        rp_data_ok = 0;
                    end
                    if (rd_tlast)
                        rp_tlast_idx = r;
                    r = r + 1;
                end
                tcnt = tcnt + 1;
                if (tcnt > TIMEOUT)
                    $fatal(1, "do_replay_rand: timeout at sample %0d", r);
            end
            @(posedge clk); #1;
            rd_ready    = 1'b0;
            rp_rx_count = r;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main stimulus
    // -----------------------------------------------------------------------
    integer i, partial_cnt;

    initial begin : tb_main
        tb_pass = 0;
        tb_fail = 0;

        // Safe initial values (tasks will override)
        aresetn      = 1'b0;
        clear        = 1'b0;
        wr_valid     = 1'b0;
        wr_data      = {DATA_W{1'b0}};
        replay_start = 1'b0;
        rd_ready     = 1'b0;

        // ==============================================================
        // T01: Reset defaults
        // ==============================================================
        $display("\n--- T01: Reset defaults ---");
        do_reset();
        chk1 ("T01 wr_ready=1",       wr_ready,      1'b1);
        chk1 ("T01 capture_done=0",   capture_done,  1'b0);
        chk1 ("T01 capture_error=0",  capture_error, 1'b0);
        chk1 ("T01 replay_busy=0",    replay_busy,   1'b0);
        chk1 ("T01 replay_done=0",    replay_done,   1'b0);
        chk1 ("T01 rd_valid=0",       rd_valid,      1'b0);
        chk1 ("T01 rd_tlast=0",       rd_tlast,      1'b0);

        // ==============================================================
        // T02: Capture exactly 4032 samples, capture_done fires
        // ==============================================================
        $display("\n--- T02: Capture exactly 4032 samples ---");
        do_reset();
        do_capture(32'hA000_0000);
        chk32("T02 fires==4032",      cap_fires,     FRAME_LEN);
        chk1 ("T02 capture_done=1",   capture_done,  1'b1);
        chk1 ("T02 wr_ready=0",       wr_ready,      1'b0);
        chk1 ("T02 capture_error=0",  capture_error, 1'b0);

        // ==============================================================
        // T03: Replay 4032 samples, rd_tlast on final sample
        //   (uses S_CAPTURED state left by T02 — no reset between T02/T03)
        // ==============================================================
        $display("\n--- T03: Replay 4032 samples, tlast on last ---");
        // Module is in S_CAPTURED from T02
        do_replay(0, 0, 0);
        chk32("T03 rx_count==4032",    rp_rx_count,   FRAME_LEN);
        chk32("T03 tlast at idx 4031", rp_tlast_idx,  FRAME_LEN - 1);
        chk1 ("T03 data ok",          rp_data_ok[0], 1'b1);
        chk1 ("T03 replay_done=1",    replay_done,   1'b1);
        chk1 ("T03 replay_busy=0",    replay_busy,   1'b0);
        @(posedge clk); #1;
        chk1 ("T03 replay_done clears", replay_done, 1'b0);

        // ==============================================================
        // T04: Output backpressure during replay
        // ==============================================================
        $display("\n--- T04: Backpressure during replay ---");
        do_reset();
        do_capture(32'hA100_0000);
        // Stall rd_ready for 50 cycles at sample 100
        do_replay(1, 100, 50);
        chk32("T04 rx_count==4032",    rp_rx_count,   FRAME_LEN);
        chk32("T04 tlast at idx 4031", rp_tlast_idx,  FRAME_LEN - 1);
        chk1 ("T04 data ok",          rp_data_ok[0], 1'b1);
        chk1 ("T04 replay_done=1",    replay_done,   1'b1);

        // ==============================================================
        // T05: Clear mid-capture
        // ==============================================================
        $display("\n--- T05: Clear mid-capture ---");
        do_reset();
        // Send 100 samples to partially fill buffer
        partial_cnt = 0;
        wr_valid    = 1'b1;
        wr_data     = 32'hC050_0000;
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk); #1;
            if (wr_ready & wr_valid)
                partial_cnt = partial_cnt + 1;
            wr_data = 32'hC050_0000 + partial_cnt;
        end
        wr_valid = 1'b0;
        @(posedge clk); #1;
        chk1("T05 pre-clear wr_ready=1", wr_ready, 1'b1);

        // Synchronous clear
        clear = 1'b1;
        @(posedge clk); #1;
        clear = 1'b0;
        @(posedge clk); #1;

        chk1 ("T05 post-clear wr_ready=1",    wr_ready,     1'b1);
        chk1 ("T05 post-clear capture_done=0", capture_done, 1'b0);

        // Fresh 4032-sample capture
        do_capture(32'hC500_0000);
        chk32("T05 second capture fires==4032", cap_fires,    FRAME_LEN);
        chk1 ("T05 second capture_done=1",      capture_done, 1'b1);

        // ==============================================================
        // T06: replay_start before capture_done
        // ==============================================================
        $display("\n--- T06: Premature replay_start -> capture_error ---");
        do_reset();
        partial_cnt = 0;
        wr_valid    = 1'b1;
        wr_data     = 32'hD060_0000;
        // Send 100 samples
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk); #1;
            if (wr_ready & wr_valid) begin
                exp_mem[partial_cnt] = wr_data;
                partial_cnt = partial_cnt + 1;
                wr_data = 32'hD060_0000 + partial_cnt;
            end
        end

        // Fire premature replay_start
        replay_start = 1'b1;
        @(posedge clk); #1;
        replay_start = 1'b0;
        @(posedge clk); #1;

        chk1("T06 capture_error=1",  capture_error, 1'b1);
        chk1("T06 replay_busy=0",    replay_busy,   1'b0);
        chk1("T06 wr_ready=1",       wr_ready,      1'b1);

        // Continue sending remaining samples to complete FRAME_LEN (4032)
        while (partial_cnt < FRAME_LEN) begin
            @(posedge clk); #1;
            if (wr_ready & wr_valid) begin
                exp_mem[partial_cnt] = wr_data;
                partial_cnt = partial_cnt + 1;
                wr_data = 32'hD060_0000 + partial_cnt;
            end
        end
        @(posedge clk); #1;
        wr_valid = 1'b0;

        chk32("T06 total accepted==4032", partial_cnt,  FRAME_LEN);
        chk1 ("T06 capture_done=1",       capture_done, 1'b1);

        // Replay still succeeds from S_CAPTURED despite capture_error
        do_replay(0, 0, 0);
        chk32("T06 replay rx==4032",    rp_rx_count,  FRAME_LEN);
        chk32("T06 tlast at 4031",      rp_tlast_idx, FRAME_LEN - 1);
        chk1 ("T06 replay_done=1",     replay_done,  1'b1);

        // ==============================================================
        // T07: Two captures back-to-back with clear
        // ==============================================================
        $display("\n--- T07: Two back-to-back captures ---");
        do_reset();

        // First capture + replay
        do_capture(32'hE070_0000);
        chk32("T07a fires==4032",  cap_fires,    FRAME_LEN);
        do_replay(0, 0, 0);
        chk32("T07a rx==4032",     rp_rx_count,  FRAME_LEN);
        chk1 ("T07a data ok",      rp_data_ok[0],1'b1);
        chk1 ("T07a replay_done",  replay_done,  1'b1);

        // Clear → second capture
        clear = 1'b1;
        @(posedge clk); #1;
        clear = 1'b0;
        @(posedge clk); #1;
        chk1("T07 after-clear wr_ready=1", wr_ready, 1'b1);

        // Second capture + replay (different data pattern)
        do_capture(32'hF070_0000);
        chk32("T07b fires==4032",   cap_fires,    FRAME_LEN);
        do_replay(0, 0, 0);
        chk32("T07b rx==4032",      rp_rx_count,  FRAME_LEN);
        chk32("T07b tlast at 4031", rp_tlast_idx, FRAME_LEN - 1);
        chk1 ("T07b data ok",       rp_data_ok[0],1'b1);

        // ==============================================================
        // T08: Randomized rd_ready stalls
        // ==============================================================
        $display("\n--- T08: Randomized rd_ready stalls ---");
        do_reset();
        do_capture(32'hA800_0000);
        chk32("T08 capture fires==4032", cap_fires,    FRAME_LEN);
        do_replay_rand();
        chk32("T08 rx==4032",            rp_rx_count,  FRAME_LEN);
        chk32("T08 tlast at idx 4031",   rp_tlast_idx, FRAME_LEN - 1);
        chk1 ("T08 data ok",            rp_data_ok[0],1'b1);
        chk1 ("T08 replay_done=1",      replay_done,  1'b1);

        // ==============================================================
        // Summary
        // ==============================================================
        $display("\n==========================================");
        $display("P3-10A iq_replay_buffer_576 TB Summary");
        $display("  PASS: %0d", tb_pass);
        $display("  FAIL: %0d", tb_fail);
        if (tb_fail == 0)
            $display("CI_GATE: PASS");
        else
            $display("CI_GATE: FAIL");
        $display("==========================================");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Global watchdog scaled 7x for the 4032-beat frame
    // (14 000 000 ns = 1 400 000 cycles @ 10 ns)
    // -----------------------------------------------------------------------
    initial begin
        #(CLK_HALF * 2 * 1400000);
        $fatal(1, "P3-10A TB: global simulation timeout");
    end

endmodule
