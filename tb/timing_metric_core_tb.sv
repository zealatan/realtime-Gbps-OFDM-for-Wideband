`timescale 1ns/1ps

// timing_metric_core_tb — 15 test groups, ~65 checks.
//
// Provides a behavioral model of cp_autocorr_core's combinatorial result
// read port (three 256-entry reg arrays, combinatorial assign by result_rd_addr).
//
// Golden metric function mirrors RTL:
//   abs = negate if negative (using longint arithmetic)
//   mag = max(abs_I, abs_Q) + (min>>2) + (min>>3)
//   M[m] = lower MW bits of (2*mag - E)  [wraps correctly since M <= 0 always]
//
// All test temporaries declared at top of initial block (Vivado xvlog restriction:
// no variable declarations inside unnamed begin-end blocks within initial).

module timing_metric_core_tb;

    localparam int MW        = 32;
    localparam int CLK_HALF  = 5;
    localparam int TIMEOUT   = 10000;
    localparam int N_LAGS_TB = 8;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic         start_d;
    logic [8:0]   num_lags_d;
    logic         done;
    logic         busy;

    wire  [8:0]   result_rd_addr;
    logic signed [31:0] result_autocorr_I_d;
    logic signed [31:0] result_autocorr_Q_d;
    logic        [31:0] result_norm_E_d;

    wire  [MW-1:0] metric_out;
    wire           metric_valid;
    wire           metric_last;

    timing_metric_core #(
        .NSC         (256),
        .METRIC_WIDTH(MW),
        .ACC_WIDTH   (40)
    ) dut (
        .aclk              (aclk),
        .aresetn           (aresetn),
        .start             (start_d),
        .num_lags          (num_lags_d),
        .done              (done),
        .busy              (busy),
        .result_rd_addr    (result_rd_addr),
        .result_autocorr_I (result_autocorr_I_d),
        .result_autocorr_Q (result_autocorr_Q_d),
        .result_norm_E     (result_norm_E_d),
        .metric_out        (metric_out),
        .metric_valid      (metric_valid),
        .metric_last       (metric_last)
    );

    // -----------------------------------------------------------------------
    // Behavioral result RAM — combinatorial read (matches cp_autocorr_core)
    // -----------------------------------------------------------------------
    logic signed [31:0] ram_PI [0:255];
    logic signed [31:0] ram_PQ [0:255];
    logic        [31:0] ram_E  [0:255];

    assign result_autocorr_I_d = ram_PI[result_rd_addr];
    assign result_autocorr_Q_d = ram_PQ[result_rd_addr];
    assign result_norm_E_d     = ram_E [result_rd_addr];

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);                           pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_metric(input string nm,
                               input logic [MW-1:0] got, input logic [MW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%08X (%0d)", nm, got, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%08X(%0d) exp=0x%08X(%0d)",
                           nm, got, $signed(got), exp, $signed(exp)); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden metric — uses 64-bit signed longint to avoid overflow
    // -----------------------------------------------------------------------
    function automatic logic [MW-1:0] gold_metric(
        input longint PI, input longint PQ, input longint E
    );
        longint aI, aQ, mx, mn, mag, two_mag, res;
        aI      = (PI < 0) ? -PI : PI;
        aQ      = (PQ < 0) ? -PQ : PQ;
        mx      = (aI >= aQ) ? aI : aQ;
        mn      = (aI >= aQ) ? aQ : aI;
        mag     = mx + (mn >> 2) + (mn >> 3);
        two_mag = mag << 1;
        res     = two_mag - E;   // wraps in 64-bit; lower MW bits match RTL
        return res[MW-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------------
    task automatic clear_ram();
        for (int i = 0; i < 256; i++) begin
            ram_PI[i] = 32'sd0;
            ram_PQ[i] = 32'sd0;
            ram_E [i] = 32'd0;
        end
    endtask

    // Captured metric stream (module-level so tasks can return values)
    logic [MW-1:0] cap_metrics [0:511];  // oversized capture buffer
    int            cap_cnt;
    int            cap_last_pos;

    task automatic run_and_capture(input int nlags);
        int tctr;
        cap_cnt      = 0;
        cap_last_pos = -1;

        @(negedge aclk);
        num_lags_d = nlags[8:0];
        start_d    = 1'b1;
        @(posedge aclk); #1;   // FSM enters S_RUN, lag=0 — sample immediately
        start_d    = 1'b0;

        tctr = 0;
        while (!done && tctr < TIMEOUT) begin
            if (metric_valid && cap_cnt < nlags) begin
                cap_metrics[cap_cnt] = metric_out;
                if (metric_last) cap_last_pos = cap_cnt;
                cap_cnt++;
            end
            @(posedge aclk); #1;
            tctr++;
        end
        if (tctr >= TIMEOUT)
            $display("[FAIL] TIMEOUT in run_and_capture");
    endtask

    task automatic run_wait(input int nlags);
        int tctr;
        @(negedge aclk);
        num_lags_d = nlags[8:0]; start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        tctr = 0;
        @(posedge aclk); #1;
        while (!done && tctr < TIMEOUT) begin @(posedge aclk); #1; tctr++; end
        if (tctr >= TIMEOUT) $display("[FAIL] TIMEOUT in run_wait");
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [31:0] prng;
    logic [MW-1:0] exp_m;
    int tctr_l, done_cnt_l;

    initial begin
        aresetn    = 1'b0;
        start_d    = 1'b0;
        num_lags_d = N_LAGS_TB;
        prng       = 32'hABCD_1234;
        pass_cnt   = 0;
        fail_cnt   = 0;

        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;

        // ====================================================================
        // T1: Reset state
        // ====================================================================
        $display("\n--- T1: Reset state ---");
        chk("T1 done=0",         done,         1'b0);
        chk("T1 busy=0",         busy,         1'b0);
        chk("T1 metric_valid=0", metric_valid, 1'b0);

        // ====================================================================
        // T2: All-zero inputs → M[m] = 0 for all lags
        // ====================================================================
        $display("\n--- T2: All-zero inputs ---");
        clear_ram();
        run_and_capture(N_LAGS_TB);
        chk("T2 done",       done, 1'b1);
        chk_metric("T2 lag0", cap_metrics[0], 32'd0);
        chk_metric("T2 lag7", cap_metrics[7], 32'd0);

        // ====================================================================
        // T3: Real-only, single non-zero lag (m=0)
        //   PI=20000, PQ=0, E=50000
        //   |P| = 20000, M = 40000 - 50000 = -10000
        // ====================================================================
        $display("\n--- T3: Real-only, single lag ---");
        clear_ram();
        ram_PI[0] = 32'sd20000;
        ram_PQ[0] = 32'sd0;
        ram_E [0] = 32'd50000;
        run_and_capture(N_LAGS_TB);
        chk("T3 done", done, 1'b1);
        chk_metric("T3 lag0 M=-10000", cap_metrics[0], gold_metric(20000, 0, 50000));
        chk_metric("T3 lag1 M=0",      cap_metrics[1], 32'd0);
        chk_metric("T3 lag7 M=0",      cap_metrics[7], 32'd0);

        // ====================================================================
        // T4: Mixed I+Q at lag=3
        //   PI=20000, PQ=2500, E=58125
        //   max=20000, min=2500 → mag = 20000 + 625 + 312 = 20937
        //   M = 41874 - 58125 = -16251
        // ====================================================================
        $display("\n--- T4: Mixed I+Q ---");
        clear_ram();
        ram_PI[3] = 32'sd20000;
        ram_PQ[3] = 32'sd2500;
        ram_E [3] = 32'd58125;
        run_and_capture(N_LAGS_TB);
        chk("T4 done", done, 1'b1);
        chk_metric("T4 lag3 metric", cap_metrics[3], gold_metric(20000, 2500, 58125));
        chk_metric("T4 lag0 zero",   cap_metrics[0], 32'd0);

        // ====================================================================
        // T5: num_lags=4, verify exactly 4 outputs, last at position 3
        // ====================================================================
        $display("\n--- T5: num_lags=4 ---");
        clear_ram();
        ram_PI[0] = 32'sd1000;  ram_E[0] = 32'd5000;
        ram_PI[1] = 32'sd2000;  ram_E[1] = 32'd10000;
        ram_PI[2] = 32'sd3000;  ram_E[2] = 32'd15000;
        ram_PI[3] = 32'sd4000;  ram_E[3] = 32'd20000;
        run_and_capture(4);
        chk("T5 done",     done, 1'b1);
        chk("T5 cnt==4",   (cap_cnt == 4), 1'b1);
        chk("T5 last=3",   (cap_last_pos == 3), 1'b1);
        chk_metric("T5 lag0", cap_metrics[0], gold_metric(1000, 0, 5000));
        chk_metric("T5 lag3", cap_metrics[3], gold_metric(4000, 0, 20000));

        // ====================================================================
        // T6: metric_valid gating (0 before start, 1 in RUN, 0 after done)
        // ====================================================================
        $display("\n--- T6: metric_valid gating ---");
        chk("T6 valid=0 before start", metric_valid, 1'b0);
        clear_ram();
        @(negedge aclk);
        num_lags_d = N_LAGS_TB; start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        @(posedge aclk); #1;
        chk("T6 valid=1 in RUN", metric_valid, 1'b1);
        tctr_l = 0;
        while (!done && tctr_l < TIMEOUT) begin @(posedge aclk); #1; tctr_l++; end
        @(posedge aclk); #1;
        chk("T6 valid=0 after done", metric_valid, 1'b0);

        // ====================================================================
        // T7: metric_last exactly on last lag
        // ====================================================================
        $display("\n--- T7: metric_last position ---");
        clear_ram();
        run_and_capture(5);
        chk("T7 done",     done, 1'b1);
        chk("T7 last=4",   (cap_last_pos == 4), 1'b1);
        chk("T7 cnt=5",    (cap_cnt == 5), 1'b1);

        // ====================================================================
        // T8: done pulse width = exactly 1 clock
        // ====================================================================
        $display("\n--- T8: done pulse width ---");
        clear_ram();
        @(negedge aclk);
        num_lags_d = N_LAGS_TB; start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        done_cnt_l = 0; tctr_l = 0;
        @(posedge aclk); #1;
        while (!done && tctr_l < TIMEOUT) begin @(posedge aclk); #1; tctr_l++; end
        done_cnt_l = done ? 1 : 0;
        @(posedge aclk); #1;
        if (done_cnt_l == 1 && !done) done_cnt_l = 1;
        else if (done_cnt_l == 1 && done) done_cnt_l = 2;
        chk("T8 done width=1", (done_cnt_l == 1), 1'b1);

        // ====================================================================
        // T9: busy deasserts on done; asserts on start
        // ====================================================================
        $display("\n--- T9: busy behavior ---");
        clear_ram();
        run_and_capture(N_LAGS_TB);
        chk("T9 busy=0 on done", busy, 1'b0);
        @(negedge aclk);
        num_lags_d = N_LAGS_TB; start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        @(posedge aclk); #1;
        chk("T9 busy=1 while running", busy, 1'b1);
        tctr_l = 0;
        while (!done && tctr_l < TIMEOUT) begin @(posedge aclk); #1; tctr_l++; end

        // ====================================================================
        // T10: Back-to-back runs update results correctly
        // ====================================================================
        $display("\n--- T10: Back-to-back runs ---");
        clear_ram();
        ram_PI[0] = 32'sd1000; ram_E[0] = 32'd3000;
        run_and_capture(N_LAGS_TB);
        chk("T10 run1 done",  done, 1'b1);
        chk_metric("T10 run1 lag0", cap_metrics[0], gold_metric(1000, 0, 3000));
        clear_ram();
        ram_PI[0] = 32'sd5000; ram_E[0] = 32'd12000;
        run_and_capture(N_LAGS_TB);
        chk("T10 run2 done",  done, 1'b1);
        chk_metric("T10 run2 lag0", cap_metrics[0], gold_metric(5000, 0, 12000));

        // ====================================================================
        // T11: Negative PI/PQ → abs identical to positive equivalents
        //   PI=-20000, PQ=-2500 → same |P| as +20000,+2500
        // ====================================================================
        $display("\n--- T11: Negative inputs ---");
        clear_ram();
        ram_PI[2] = -32'sd20000;
        ram_PQ[2] = -32'sd2500;
        ram_E [2] =  32'd58125;
        run_and_capture(N_LAGS_TB);
        chk("T11 done", done, 1'b1);
        chk_metric("T11 lag2 (neg==pos)", cap_metrics[2],
                   gold_metric(-20000, -2500, 58125));

        // ====================================================================
        // T12: Large values near 32-bit range
        //   PI=0x4000_0000 (2^30), PQ=0, E=0x8000_0000 (2^31)
        //   |P| = 2^30, M = 2^31 - 2^31 = 0
        // ====================================================================
        $display("\n--- T12: Large values ---");
        clear_ram();
        ram_PI[0] = 32'sh4000_0000;
        ram_PQ[0] = 32'sd0;
        ram_E [0] = 32'h8000_0000;
        run_and_capture(N_LAGS_TB);
        chk("T12 done", done, 1'b1);
        chk_metric("T12 lag0 large", cap_metrics[0],
                   gold_metric(32'sh4000_0000, 0, 32'h8000_0000));

        // ====================================================================
        // T13: num_lags=1 (single output, metric_last on first/only output)
        // ====================================================================
        $display("\n--- T13: num_lags=1 ---");
        clear_ram();
        ram_PI[0] = 32'sd10000;
        ram_E [0] = 32'd25000;
        run_and_capture(1);
        chk("T13 done",    done, 1'b1);
        chk("T13 cnt=1",   (cap_cnt == 1), 1'b1);
        chk("T13 last=0",  (cap_last_pos == 0), 1'b1);
        chk_metric("T13 lag0", cap_metrics[0], gold_metric(10000, 0, 25000));

        // ====================================================================
        // T14: All 8 lags with distinct values — full golden model check
        // ====================================================================
        $display("\n--- T14: All lags golden model ---");
        clear_ram();
        ram_PI[0]=32'sd1000; ram_PQ[0]= 32'sd500; ram_E[0]=32'd4000;
        ram_PI[1]=32'sd2000; ram_PQ[1]=-32'sd300; ram_E[1]=32'd9000;
        ram_PI[2]=32'sd3000; ram_PQ[2]= 32'sd800; ram_E[2]=32'd16000;
        ram_PI[3]=32'sd4000; ram_PQ[3]=-32'sd200; ram_E[3]=32'd25000;
        ram_PI[4]=32'sd5000; ram_PQ[4]= 32'sd100; ram_E[4]=32'd36000;
        ram_PI[5]=32'sd6000; ram_PQ[5]=-32'sd700; ram_E[5]=32'd49000;
        ram_PI[6]=32'sd7000; ram_PQ[6]= 32'sd400; ram_E[6]=32'd64000;
        ram_PI[7]=32'sd8000; ram_PQ[7]= 32'sd900; ram_E[7]=32'd81000;
        run_and_capture(N_LAGS_TB);
        chk("T14 done",    done, 1'b1);
        chk("T14 cnt=8",   (cap_cnt == N_LAGS_TB), 1'b1);
        chk_metric("T14 lag0", cap_metrics[0], gold_metric(1000,  500, 4000));
        chk_metric("T14 lag1", cap_metrics[1], gold_metric(2000, -300, 9000));
        chk_metric("T14 lag2", cap_metrics[2], gold_metric(3000,  800, 16000));
        chk_metric("T14 lag3", cap_metrics[3], gold_metric(4000, -200, 25000));
        chk_metric("T14 lag4", cap_metrics[4], gold_metric(5000,  100, 36000));
        chk_metric("T14 lag5", cap_metrics[5], gold_metric(6000, -700, 49000));
        chk_metric("T14 lag6", cap_metrics[6], gold_metric(7000,  400, 64000));
        chk_metric("T14 lag7", cap_metrics[7], gold_metric(8000,  900, 81000));

        // ====================================================================
        // T15: PRNG smoke test
        // ====================================================================
        $display("\n--- T15: PRNG smoke ---");
        clear_ram();
        for (int i = 0; i < N_LAGS_TB; i++) begin
            longint pi_v, pq_v, e_v, abs_pi, abs_pq;
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            pi_v = $signed(prng);
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            pq_v = $signed(prng);
            abs_pi = (pi_v < 0) ? -pi_v : pi_v;
            abs_pq = (pq_v < 0) ? -pq_v : pq_v;
            e_v    = (abs_pi + abs_pq) * 4;   // ensure E >= 2*|P| so M <= 0
            if (e_v > 32'hFFFF_FFFF) e_v = 32'hFFFF_FFFF;
            ram_PI[i] = pi_v[31:0];
            ram_PQ[i] = pq_v[31:0];
            ram_E [i] = e_v[31:0];
        end
        run_and_capture(N_LAGS_TB);
        chk("T15 done",    done, 1'b1);
        chk("T15 cnt=8",   (cap_cnt == N_LAGS_TB), 1'b1);
        for (int i = 0; i < N_LAGS_TB; i++) begin
            chk_metric($sformatf("T15 lag%0d", i), cap_metrics[i],
                       gold_metric($signed(ram_PI[i]),
                                   $signed(ram_PQ[i]),
                                   ram_E[i]));
        end

        // ====================================================================
        // Summary
        // ====================================================================
        $display("\n========================================");
        $display("PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("CI GATE: PASSED");
        else               $display("CI GATE: FAILED");
        $display("========================================\n");

        $finish;
    end

endmodule
