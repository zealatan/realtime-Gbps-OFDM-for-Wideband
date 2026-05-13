`timescale 1ns/1ps

// Testbench for meyr_integer_cfo_freq_estimator_top
//
// Test strategy (no FFT required):
//   term2 inside the core uses synthetic XOR-shift32 PRNG (seed 32'hCAFE_B0BB).
//   This testbench mirrors the same PRNG to build PSS/SSS test vectors:
//     SSS_FFT[n] = 1 + j0   (unit real)
//     PSS_FFT[n] = term2[n-s] if 0 <= n-s < NSC, else 0   (shifted copy)
//   Then term1[n] = PSS[n] * conj(SSS[n]) = PSS[n] = term2[n-s]
//   The correlation produces peak at p=255+s, int_cfo=s. ✓
//
//   PSS/SSS values are 8-bit PRNG values sign-extended to 16 bits (IQ_WIDTH).
//   With SSS=1+j0, the product_gen is a simple pass-through.
//
// SYNTHETIC FALLBACK NOTE:
//   All shift tests use the synthetic PRNG term2 ROM (seed 32'hCAFE_B0BB).
//   Real mU/goldU-derived term2 ROM is pending (ref/receiver.c does not
//   define the mU/goldU sequences — they are external parameters).

module meyr_integer_cfo_freq_estimator_top_tb;

    localparam integer NSC         = 256;
    localparam integer IQ_WIDTH    = 16;
    localparam integer PROD_WIDTH  = 32;
    localparam integer ACC_WIDTH   = 56;
    localparam integer SCORE_WIDTH = 64;
    localparam integer INDEX_WIDTH = 9;
    localparam integer CENTER      = NSC - 1;   // 255

    localparam real CLK_PERIOD = 10.0;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                          aclk;
    logic                          aresetn;
    logic                          start;
    logic                          s_valid;
    logic                          s_ready;
    logic [7:0]                    s_index;
    logic signed [IQ_WIDTH-1:0]    pss_i, pss_q;
    logic signed [IQ_WIDTH-1:0]    sss_i, sss_q;
    logic                          busy;
    logic                          done;
    logic                          error;
    logic signed [15:0]            int_cfo;
    logic [INDEX_WIDTH-1:0]        peak_index;
    logic [SCORE_WIDTH-1:0]        peak_score;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    meyr_integer_cfo_freq_estimator_top #(
        .NSC        (NSC),
        .IQ_WIDTH   (IQ_WIDTH),
        .PROD_WIDTH (PROD_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SCORE_WIDTH(SCORE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) dut (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .start     (start),
        .s_valid   (s_valid),
        .s_ready   (s_ready),
        .s_index   (s_index),
        .pss_i     (pss_i),
        .pss_q     (pss_q),
        .sss_i     (sss_i),
        .sss_q     (sss_q),
        .busy      (busy),
        .done      (done),
        .error     (error),
        .int_cfo   (int_cfo),
        .peak_index(peak_index),
        .peak_score(peak_score)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Mirror of core's synthetic term2 PRNG (seed 32'hCAFE_B0BB)
    // MUST match seed and XOR-shift sequence in meyr_integer_cfo_core.v
    // -----------------------------------------------------------------------
    logic signed [IQ_WIDTH-1:0] tb_term2_i [0:NSC-1];  // 16-bit for PSS feed
    logic signed [IQ_WIDTH-1:0] tb_term2_q [0:NSC-1];

    initial begin : gen_tb_term2
        integer j;
        logic [31:0] seed;
        seed = 32'hCAFE_B0BB;
        for (j = 0; j < NSC; j++) begin
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_i[j] = {{(IQ_WIDTH-8){seed[7]}}, seed[7:0]};
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_q[j] = {{(IQ_WIDTH-8){seed[7]}}, seed[7:0]};
        end
    end

    // -----------------------------------------------------------------------
    // Test counters
    // -----------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer grp_fail_snap;

    // -----------------------------------------------------------------------
    // Tasks
    // -----------------------------------------------------------------------
    task reset_dut;
        aresetn = 0;
        start   = 0;
        s_valid = 0;
        s_index = 0;
        pss_i   = 0; pss_q = 0;
        sss_i   = 0; sss_q = 0;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1;
        @(posedge aclk);
    endtask

    // Send one PSS/SSS sample pair; waits for s_ready before driving
    task send_pss_sss_sample(
        input [7:0]                   idx,
        input signed [IQ_WIDTH-1:0]   pi, pq, si, sq
    );
        @(negedge aclk);
        wait(s_ready);
        @(negedge aclk);
        s_valid = 1;
        s_index = idx;
        pss_i   = pi;  pss_q = pq;
        sss_i   = si;  sss_q = sq;
        @(posedge aclk);
        @(negedge aclk);
        s_valid = 0;
    endtask

    // Stream NSC PSS/SSS pairs for a given shift s.
    // PSS[n] = term2[n-s] if 0<=n-s<NSC, else 0; SSS[n] = 1+j0
    task stream_for_shift(input integer shift_s);
        integer n, src;
        for (n = 0; n < NSC; n++) begin
            src = n - shift_s;
            if (src >= 0 && src < NSC) begin
                send_pss_sss_sample(n[7:0],
                    tb_term2_i[src], tb_term2_q[src],
                    IQ_WIDTH'(1), IQ_WIDTH'(0));
            end else begin
                send_pss_sss_sample(n[7:0],
                    {IQ_WIDTH{1'b0}}, {IQ_WIDTH{1'b0}},
                    IQ_WIDTH'(1), IQ_WIDTH'(0));
            end
        end
    endtask

    // Full run: start, stream, wait for done, check results
    task run_and_check(
        input integer  shift_s,
        input integer  exp_peak,
        input integer  exp_cfo,
        input string   test_name
    );
        integer timeout;
        @(negedge aclk);
        start = 1;
        @(posedge aclk);
        @(negedge aclk);
        start = 0;

        stream_for_shift(shift_s);

        timeout = 0;
        @(posedge aclk);
        while (!done && timeout < 300000) begin
            @(posedge aclk);
            timeout++;
        end

        if (timeout >= 300000) begin
            $display("FAIL [%0s]: TIMEOUT", test_name);
            fail_cnt += 2;
        end else begin
            if (peak_index == exp_peak) begin
                pass_cnt++;
            end else begin
                $display("FAIL [%0s]: peak_index=%0d expected=%0d",
                         test_name, peak_index, exp_peak);
                fail_cnt++;
            end
            if ($signed(int_cfo) == exp_cfo) begin
                pass_cnt++;
            end else begin
                $display("FAIL [%0s]: int_cfo=%0d expected=%0d",
                         test_name, $signed(int_cfo), exp_cfo);
                fail_cnt++;
            end
        end
        repeat(2) @(posedge aclk);
    endtask

    task chk(input logic cond, input string msg);
        if (cond) pass_cnt++;
        else begin $display("FAIL: %s", msg); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("=== meyr_integer_cfo_freq_estimator_top_tb ===");
        $display("NOTE: Shift tests use synthetic PRNG term2 ROM (seed 32'hCAFE_B0BB).");
        $display("      Real mU/goldU ROM extraction is pending.");

        reset_dut();

        // ------------------------------------------------------------------
        // T1: reset_defaults
        // ------------------------------------------------------------------
        $display("T1: reset_defaults");
        grp_fail_snap = fail_cnt;
        chk(!busy,  "T1 busy=0 after reset");
        chk(!done,  "T1 done=0 after reset");
        chk(!error, "T1 error=0 after reset");
        if (fail_cnt == grp_fail_snap) $display("T1: PASS");

        // ------------------------------------------------------------------
        // T2: zero_cfo — shift=0 → peak_index=255, int_cfo=0
        // ------------------------------------------------------------------
        $display("T2: zero_cfo (shift=0)");
        grp_fail_snap = fail_cnt;
        run_and_check(0, 255, 0, "T2");
        chk(peak_score > 0, "T2 peak_score > 0");
        if (fail_cnt == grp_fail_snap) $display("T2: PASS");

        // ------------------------------------------------------------------
        // T3: positive_shift_plus1 → peak_index=256, int_cfo=+1
        // ------------------------------------------------------------------
        $display("T3: positive_shift_plus1");
        grp_fail_snap = fail_cnt;
        run_and_check(1, 256, 1, "T3");
        if (fail_cnt == grp_fail_snap) $display("T3: PASS");

        // ------------------------------------------------------------------
        // T4: negative_shift_minus1 → peak_index=254, int_cfo=-1
        // ------------------------------------------------------------------
        $display("T4: negative_shift_minus1");
        grp_fail_snap = fail_cnt;
        run_and_check(-1, 254, -1, "T4");
        if (fail_cnt == grp_fail_snap) $display("T4: PASS");

        // ------------------------------------------------------------------
        // T5: positive_shift_plus3 → peak_index=258, int_cfo=+3
        // ------------------------------------------------------------------
        $display("T5: positive_shift_plus3");
        grp_fail_snap = fail_cnt;
        run_and_check(3, 258, 3, "T5");
        if (fail_cnt == grp_fail_snap) $display("T5: PASS");

        // ------------------------------------------------------------------
        // T6: negative_shift_minus4 → peak_index=251, int_cfo=-4
        // ------------------------------------------------------------------
        $display("T6: negative_shift_minus4");
        grp_fail_snap = fail_cnt;
        run_and_check(-4, 251, -4, "T6");
        if (fail_cnt == grp_fail_snap) $display("T6: PASS");

        // ------------------------------------------------------------------
        // T7: positive_shift_plus8 → peak_index=263, int_cfo=+8
        // ------------------------------------------------------------------
        $display("T7: positive_shift_plus8");
        grp_fail_snap = fail_cnt;
        run_and_check(8, 263, 8, "T7");
        if (fail_cnt == grp_fail_snap) $display("T7: PASS");

        // ------------------------------------------------------------------
        // T8: negative_shift_minus8 → peak_index=247, int_cfo=-8
        // ------------------------------------------------------------------
        $display("T8: negative_shift_minus8");
        grp_fail_snap = fail_cnt;
        run_and_check(-8, 247, -8, "T8");
        if (fail_cnt == grp_fail_snap) $display("T8: PASS");

        // ------------------------------------------------------------------
        // T9: restart_two_frames — run shift 0 then shift +3 back-to-back
        // ------------------------------------------------------------------
        $display("T9: restart_two_frames");
        grp_fail_snap = fail_cnt;
        run_and_check(0,  255, 0,  "T9a");
        run_and_check(3,  258, 3,  "T9b");
        if (fail_cnt == grp_fail_snap) $display("T9: PASS");

        // ------------------------------------------------------------------
        // T10: start_while_busy — second start before done → error=1
        // ------------------------------------------------------------------
        $display("T10: start_while_busy");
        grp_fail_snap = fail_cnt;
        begin
            @(negedge aclk);
            start = 1;
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            @(posedge aclk);
            chk(busy, "T10 busy after first start");
            @(negedge aclk);
            start = 1;
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            @(posedge aclk);
            chk(error, "T10 error=1 after start-while-busy");
            // Drain the in-progress run
            stream_for_shift(0);
            begin : t10_wait
                integer to;
                to = 0;
                @(posedge aclk);
                while (!done && to < 300000) begin @(posedge aclk); to++; end
            end
            repeat(2) @(posedge aclk);
            reset_dut();
        end
        if (fail_cnt == grp_fail_snap) $display("T10: PASS");

        // ------------------------------------------------------------------
        // T11: zero_term1 — all-zero PSS/SSS → score=0, tie-break index=0
        //   With all-zero PSS: term1=0 for all j → all scores=0 → peak_index=0
        //   int_cfo = 0 - 255 = -255
        // ------------------------------------------------------------------
        $display("T11: zero_pss_input");
        grp_fail_snap = fail_cnt;
        begin
            @(negedge aclk);
            start = 1;
            @(posedge aclk);
            @(negedge aclk);
            start = 0;
            // Stream all zeros for PSS; SSS=1+j0 (doesn't matter; product=0)
            for (int n = 0; n < NSC; n++) begin
                send_pss_sss_sample(n[7:0],
                    {IQ_WIDTH{1'b0}}, {IQ_WIDTH{1'b0}},
                    IQ_WIDTH'(1),     IQ_WIDTH'(0));
            end
            begin : t11_wait
                integer to;
                to = 0;
                @(posedge aclk);
                while (!done && to < 300000) begin @(posedge aclk); to++; end
                chk(to < 300000, "T11 no timeout");
            end
            chk(peak_score == 0,            "T11 peak_score=0 for zero PSS");
            chk(peak_index  == 0,           "T11 peak_index=0 (first wins on tie)");
            chk($signed(int_cfo) == -255,   "T11 int_cfo=-255");
            repeat(2) @(posedge aclk);
        end
        if (fail_cnt == grp_fail_snap) $display("T11: PASS");

        // ------------------------------------------------------------------
        // T12: product_gen_to_core_index_alignment — shift +2 and -2
        //   Verifies that the product_gen's m_index correctly aligns with
        //   the buffer write address used by the core.
        // ------------------------------------------------------------------
        $display("T12: index_alignment (+2 and -2)");
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
