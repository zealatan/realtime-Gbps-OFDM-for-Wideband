`timescale 1ns/1ps

// Testbench for meyr_integer_cfo_core
//
// Mirrors the RTL's synthetic term2 ROM (seed 32'hCAFE_B0BB, XOR-shift32).
// Generates term1 as shifted copies of term2, drives the DUT, and checks
// peak_index and int_cfo against the expected values.
//
// Correlation convention (same as RTL):
//   corr[p] = sum_{n=n_start..n_end} term1[n+lag] * conj(term2[n])
//   lag = p - 255
//
// Shift s → term1[n] = term2[n-s] for 0<=n-s<256, else 0
//         → peak at p = 255+s, int_cfo = s

module meyr_integer_cfo_core_tb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam integer NSC         = 256;
    localparam integer PROD_WIDTH  = 32;
    localparam integer ACC_WIDTH   = 56;
    localparam integer SCORE_WIDTH = 64;
    localparam integer INDEX_WIDTH = 9;
    localparam integer LAG_COUNT   = 2 * NSC - 1;  // 511
    localparam integer CENTER      = NSC - 1;       // 255

    localparam real CLK_PERIOD = 10.0; // 100 MHz

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic                          aclk;
    logic                          aresetn;
    logic                          start;
    logic                          term1_valid;
    logic [7:0]                    term1_index;
    logic signed [PROD_WIDTH-1:0]  term1_i;
    logic signed [PROD_WIDTH-1:0]  term1_q;
    logic                          term1_ready;
    logic                          busy;
    logic                          done;
    logic                          error;
    logic signed [15:0]            int_cfo;
    logic [INDEX_WIDTH-1:0]        peak_index;
    logic [SCORE_WIDTH-1:0]        peak_score;

    // -------------------------------------------------------------------------
    // DUT
    // -------------------------------------------------------------------------
    meyr_integer_cfo_core #(
        .NSC        (NSC),
        .IQ_WIDTH   (16),
        .PROD_WIDTH (PROD_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SCORE_WIDTH(SCORE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (start),
        .term1_valid (term1_valid),
        .term1_index (term1_index),
        .term1_i     (term1_i),
        .term1_q     (term1_q),
        .term1_ready (term1_ready),
        .busy        (busy),
        .done        (done),
        .error       (error),
        .int_cfo     (int_cfo),
        .peak_index  (peak_index),
        .peak_score  (peak_score)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -------------------------------------------------------------------------
    // Mirror of the RTL synthetic term2 ROM
    // MUST match seed and XOR-shift sequence in rtl/meyr_integer_cfo_core.v
    // -------------------------------------------------------------------------
    logic signed [PROD_WIDTH-1:0] tb_term2_i [0:NSC-1];
    logic signed [PROD_WIDTH-1:0] tb_term2_q [0:NSC-1];

    initial begin : gen_tb_term2
        integer j;
        logic [31:0] seed;
        seed = 32'hCAFE_B0BB;
        for (j = 0; j < NSC; j++) begin
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_i[j] = {{(PROD_WIDTH-8){seed[7]}}, seed[7:0]};
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_q[j] = {{(PROD_WIDTH-8){seed[7]}}, seed[7:0]};
        end
    end

    // -------------------------------------------------------------------------
    // Test counters
    // -------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer grp_fail_snap;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------

    task reset_dut;
        aresetn = 0;
        start = 0;
        term1_valid = 0;
        term1_index = 0;
        term1_i = 0;
        term1_q = 0;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1;
        @(posedge aclk);
    endtask

    // Send one term1 sample (waits for term1_ready, then drives for one cycle)
    task send_term1_sample(
        input [7:0]                   idx,
        input signed [PROD_WIDTH-1:0] ti,
        input signed [PROD_WIDTH-1:0] tq
    );
        @(negedge aclk);
        wait(term1_ready);
        @(negedge aclk);
        term1_valid = 1;
        term1_index = idx;
        term1_i     = ti;
        term1_q     = tq;
        @(posedge aclk);
        @(negedge aclk);
        term1_valid = 0;
    endtask

    // Stream all NSC term1 samples for a given integer CFO shift s.
    // For shift s: term1[n] = term2[n-s] if 0<=n-s<NSC, else 0.
    task stream_term1_for_shift(input integer shift_s);
        integer n;
        integer src;
        for (n = 0; n < NSC; n++) begin
            src = n - shift_s;
            if (src >= 0 && src < NSC) begin
                send_term1_sample(n[7:0], tb_term2_i[src], tb_term2_q[src]);
            end else begin
                send_term1_sample(n[7:0], 32'sd0, 32'sd0);
            end
        end
    endtask

    // Pulse start and stream term1; wait for done; check results
    task run_and_check(
        input integer  shift_s,
        input integer  exp_peak_index,
        input integer  exp_int_cfo,
        input string   test_name
    );
        integer timeout;
        // Pulse start
        @(negedge aclk);
        start = 1;
        @(posedge aclk);
        @(negedge aclk);
        start = 0;

        // Stream term1
        stream_term1_for_shift(shift_s);

        // Wait for done with timeout
        timeout = 0;
        @(posedge aclk);
        while (!done && timeout < 200000) begin
            @(posedge aclk);
            timeout++;
        end

        // Check
        if (timeout >= 200000) begin
            $display("FAIL [%0s]: TIMEOUT waiting for done", test_name);
            fail_cnt++;
        end else begin
            if (peak_index == exp_peak_index) begin
                pass_cnt++;
            end else begin
                $display("FAIL [%0s]: peak_index=%0d expected=%0d",
                         test_name, peak_index, exp_peak_index);
                fail_cnt++;
            end
            if ($signed(int_cfo) == exp_int_cfo) begin
                pass_cnt++;
            end else begin
                $display("FAIL [%0s]: int_cfo=%0d expected=%0d",
                         test_name, $signed(int_cfo), exp_int_cfo);
                fail_cnt++;
            end
        end

        // Extra clock after done
        repeat(2) @(posedge aclk);
    endtask

    // -------------------------------------------------------------------------
    // Check helper (non-run check)
    // -------------------------------------------------------------------------
    task chk(input logic cond, input string msg);
        if (cond) begin
            pass_cnt++;
        end else begin
            $display("FAIL: %s", msg);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("=== meyr_integer_cfo_core_tb ===");

        reset_dut();

        // ------------------------------------------------------------------
        // T1: reset_defaults
        //   After reset, busy=0, done=0, error=0
        // ------------------------------------------------------------------
        $display("T1: reset_defaults");
        grp_fail_snap = fail_cnt;
        chk(!busy,  "T1 busy=0 after reset");
        chk(!done,  "T1 done=0 after reset");
        chk(!error, "T1 error=0 after reset");
        if (fail_cnt == grp_fail_snap) $display("T1: PASS");

        // ------------------------------------------------------------------
        // T2: zero_cfo — term1 = term2 (shift=0)
        //   Expected peak_index=255, int_cfo=0
        // ------------------------------------------------------------------
        $display("T2: zero_cfo (shift=0)");
        grp_fail_snap = fail_cnt;
        run_and_check(0, 255, 0, "T2");
        chk(peak_score > 0, "T2 peak_score > 0");
        if (fail_cnt == grp_fail_snap) $display("T2: PASS");

        // ------------------------------------------------------------------
        // T3: positive_shift_plus1
        //   Expected peak_index=256, int_cfo=+1
        // ------------------------------------------------------------------
        $display("T3: positive_shift_plus1");
        grp_fail_snap = fail_cnt;
        run_and_check(1, 256, 1, "T3");
        if (fail_cnt == grp_fail_snap) $display("T3: PASS");

        // ------------------------------------------------------------------
        // T4: negative_shift_minus1
        //   Expected peak_index=254, int_cfo=-1
        // ------------------------------------------------------------------
        $display("T4: negative_shift_minus1");
        grp_fail_snap = fail_cnt;
        run_and_check(-1, 254, -1, "T4");
        if (fail_cnt == grp_fail_snap) $display("T4: PASS");

        // ------------------------------------------------------------------
        // T5: positive_shift_plus3
        //   Expected peak_index=258, int_cfo=+3
        // ------------------------------------------------------------------
        $display("T5: positive_shift_plus3");
        grp_fail_snap = fail_cnt;
        run_and_check(3, 258, 3, "T5");
        if (fail_cnt == grp_fail_snap) $display("T5: PASS");

        // ------------------------------------------------------------------
        // T6: negative_shift_minus4
        //   Expected peak_index=251, int_cfo=-4
        // ------------------------------------------------------------------
        $display("T6: negative_shift_minus4");
        grp_fail_snap = fail_cnt;
        run_and_check(-4, 251, -4, "T6");
        if (fail_cnt == grp_fail_snap) $display("T6: PASS");

        // ------------------------------------------------------------------
        // T7: positive_shift_plus8
        //   Expected peak_index=263, int_cfo=+8
        // ------------------------------------------------------------------
        $display("T7: positive_shift_plus8");
        grp_fail_snap = fail_cnt;
        run_and_check(8, 263, 8, "T7");
        if (fail_cnt == grp_fail_snap) $display("T7: PASS");

        // ------------------------------------------------------------------
        // T8: negative_shift_minus8
        //   Expected peak_index=247, int_cfo=-8
        // ------------------------------------------------------------------
        $display("T8: negative_shift_minus8");
        grp_fail_snap = fail_cnt;
        run_and_check(-8, 247, -8, "T8");
        if (fail_cnt == grp_fail_snap) $display("T8: PASS");

        // ------------------------------------------------------------------
        // T9: restart_two_frames — run shift 0, then shift +3 back-to-back
        // ------------------------------------------------------------------
        $display("T9: restart_two_frames");
        grp_fail_snap = fail_cnt;
        run_and_check(0,  255, 0,  "T9a");
        run_and_check(3,  258, 3,  "T9b");
        if (fail_cnt == grp_fail_snap) $display("T9: PASS");

        // ------------------------------------------------------------------
        // T10: start_while_busy — start a run, pulse start again before done
        //   Expected: error becomes 1
        // ------------------------------------------------------------------
        $display("T10: start_while_busy");
        grp_fail_snap = fail_cnt;
        begin
            // Begin a run but don't wait for done before sending second start
            @(negedge aclk);
            start = 1;
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            // Give one clock, then pulse start again while busy
            @(posedge aclk);
            chk(busy, "T10 busy asserted after first start");
            @(negedge aclk);
            start = 1;     // second start — should set error
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            @(posedge aclk);
            chk(error, "T10 error=1 after start-while-busy");
            // Drain the run to allow cleanup
            stream_term1_for_shift(0);
            begin : t10_wait
                integer to;
                to = 0;
                @(posedge aclk);
                while (!done && to < 200000) begin @(posedge aclk); to++; end
            end
            repeat(2) @(posedge aclk);
            // Reset to clear sticky error
            reset_dut();
        end
        if (fail_cnt == grp_fail_snap) $display("T10: PASS");

        // ------------------------------------------------------------------
        // T11: zero_term1 — all-zero term1, expect score=0
        //   Tie-break: first/lowest index wins → peak_index=0, int_cfo=-255
        // ------------------------------------------------------------------
        $display("T11: zero_term1");
        grp_fail_snap = fail_cnt;
        begin
            // Pulse start
            @(negedge aclk);
            start = 1;
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            // Stream all zeros
            for (int n = 0; n < NSC; n++) begin
                send_term1_sample(n[7:0], 32'sd0, 32'sd0);
            end
            // Wait for done
            begin : t11_wait
                integer to;
                to = 0;
                @(posedge aclk);
                while (!done && to < 200000) begin @(posedge aclk); to++; end
                chk(to < 200000, "T11 no timeout");
            end
            chk(peak_score == 0,     "T11 peak_score=0 for zero input");
            // peak_detector ties go to first (index 0) → int_cfo = 0-255 = -255
            chk(peak_index  == 0,    "T11 peak_index=0 (first wins)");
            chk($signed(int_cfo) == -255, "T11 int_cfo=-255");
            repeat(2) @(posedge aclk);
        end
        if (fail_cnt == grp_fail_snap) $display("T11: PASS");

        // ------------------------------------------------------------------
        // T12: boundary_shifts — test +2 and -2 (confirms sign symmetry)
        // ------------------------------------------------------------------
        $display("T12: boundary_shifts (+2 and -2)");
        grp_fail_snap = fail_cnt;
        run_and_check( 2, 257,  2, "T12a");
        run_and_check(-2, 253, -2, "T12b");
        if (fail_cnt == grp_fail_snap) $display("T12: PASS");

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

endmodule
