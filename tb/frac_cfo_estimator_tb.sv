`timescale 1ns/1ps

// frac_cfo_estimator_tb — 10 test groups, ~30 checks.
//
// Provides a behavioral model of cp_autocorr_core's combinatorial result
// read port (two 256-entry reg arrays, combinatorial assign by result_rd_addr).
//
// Golden phase: same atan2/$rtoi computation as cordic_atan2 behavioral model.

module frac_cfo_estimator_tb;

    localparam int PW       = 16;
    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 2000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic       start_d;
    logic [8:0] peak_lag_d;
    logic       done;
    logic       busy;

    wire  [8:0]            result_rd_addr;
    logic signed [31:0]    autocorr_I_d;
    logic signed [31:0]    autocorr_Q_d;

    logic [PW-1:0]  frac_phase;
    logic           frac_phase_valid;

    frac_cfo_estimator #(
        .PHASE_WIDTH(PW)
    ) dut (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (start_d),
        .peak_lag         (peak_lag_d),
        .result_rd_addr   (result_rd_addr),
        .autocorr_I       (autocorr_I_d),
        .autocorr_Q       (autocorr_Q_d),
        .frac_phase       (frac_phase),
        .frac_phase_valid (frac_phase_valid),
        .done             (done),
        .busy             (busy)
    );

    // -----------------------------------------------------------------------
    // Behavioral RAM — combinatorial read (matches cp_autocorr_core)
    // -----------------------------------------------------------------------
    logic signed [31:0] ram_PI [0:255];
    logic signed [31:0] ram_PQ [0:255];

    assign autocorr_I_d = ram_PI[result_rd_addr];
    assign autocorr_Q_d = ram_PQ[result_rd_addr];

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);                             pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_phase(input string nm,
                              input logic [PW-1:0] got,
                              input logic [PW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%04X (%0d)",
                           nm, got, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%04X(%0d) exp=0x%04X(%0d)",
                           nm, got, $signed(got), exp, $signed(exp)); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden model — mirrors cordic_atan2 behavioral computation
    // -----------------------------------------------------------------------
    function automatic logic [PW-1:0] gold_phase(
        input logic signed [31:0] I_in,
        input logic signed [31:0] Q_in
    );
        real r_I_g, r_Q_g, r_ang_g;
        integer ph_g;
        r_I_g   = $itor(I_in);
        r_Q_g   = $itor(Q_in);
        r_ang_g = $atan2(r_Q_g, r_I_g) / 3.14159265358979323846;
        ph_g    = $rtoi(r_ang_g * ((1 << (PW-1)) - 1));
        return ph_g[PW-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------------
    task automatic clear_ram();
        for (int i = 0; i < 256; i++) begin
            ram_PI[i] = 32'sd0;
            ram_PQ[i] = 32'sd0;
        end
    endtask

    logic [PW-1:0] cap_phase;

    // Run one estimation at peak_lag=lag; capture frac_phase after done.
    task automatic run_and_capture(input logic [8:0] lag);
        int tctr;
        @(negedge aclk);
        peak_lag_d = lag;
        start_d    = 1'b1;
        @(posedge aclk); #1;   // FSM enters S_SEND
        start_d    = 1'b0;
        tctr = 0;
        while (!done && tctr < TIMEOUT) begin
            @(posedge aclk); #1;
            tctr++;
        end
        if (tctr >= TIMEOUT) $display("[FAIL] TIMEOUT");
        cap_phase = frac_phase;
    endtask

    // -----------------------------------------------------------------------
    // Test temporaries (module-level per Vivado xvlog rules)
    // -----------------------------------------------------------------------
    int done_cnt_l, tctr_l;
    logic [31:0] prng;
    logic signed [31:0] t10_I [0:7];
    logic signed [31:0] t10_Q [0:7];
    int i10;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn    = 1'b0;
        start_d    = 1'b0;
        peak_lag_d = 9'd0;
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
        chk("T1 done=0",             done,             1'b0);
        chk("T1 busy=0",             busy,             1'b0);
        chk("T1 frac_phase_valid=0", frac_phase_valid, 1'b0);

        // ====================================================================
        // T2: Angle=0 — I=+100000, Q=0 → phase=0x0000
        // ====================================================================
        $display("\n--- T2: Angle=0 (I=+100000, Q=0) ---");
        clear_ram();
        ram_PI[0] = 32'sd100000;
        ram_PQ[0] = 32'sd0;
        run_and_capture(9'd0);
        chk("T2 done",       done,             1'b1);
        chk("T2 phase_valid", frac_phase_valid, 1'b1);
        chk_phase("T2 phase=0", cap_phase, gold_phase(32'sd100000, 32'sd0));

        // ====================================================================
        // T3: Angle=+π/2 — I=0, Q=+100000 → phase≈0x3FFF
        // ====================================================================
        $display("\n--- T3: Angle=+pi/2 ---");
        clear_ram();
        ram_PI[0] = 32'sd0;
        ram_PQ[0] = 32'sd100000;
        run_and_capture(9'd0);
        chk("T3 done", done, 1'b1);
        chk_phase("T3 phase=+pi/2", cap_phase,
                  gold_phase(32'sd0, 32'sd100000));

        // ====================================================================
        // T4: Angle=-π/2 — I=0, Q=-100000 → phase≈0xC001
        // ====================================================================
        $display("\n--- T4: Angle=-pi/2 ---");
        clear_ram();
        ram_PI[0] = 32'sd0;
        ram_PQ[0] = -32'sd100000;
        run_and_capture(9'd0);
        chk("T4 done", done, 1'b1);
        chk_phase("T4 phase=-pi/2", cap_phase,
                  gold_phase(32'sd0, -32'sd100000));

        // ====================================================================
        // T5: Angle=+π — I=-100000, Q=0 → phase=0x7FFF
        // ====================================================================
        $display("\n--- T5: Angle=+pi ---");
        clear_ram();
        ram_PI[0] = -32'sd100000;
        ram_PQ[0] = 32'sd0;
        run_and_capture(9'd0);
        chk("T5 done", done, 1'b1);
        chk_phase("T5 phase=+pi", cap_phase,
                  gold_phase(-32'sd100000, 32'sd0));

        // ====================================================================
        // T6: peak_lag selects the correct RAM entry
        //   lag=0: I=+100000,Q=0 → 0
        //   lag=5: I=0,Q=+100000 → +π/2
        //   lag=10: I=-100000,Q=0 → +π
        // ====================================================================
        $display("\n--- T6: peak_lag selection ---");
        clear_ram();
        ram_PI[ 0] = 32'sd100000;  ram_PQ[ 0] = 32'sd0;
        ram_PI[ 5] = 32'sd0;       ram_PQ[ 5] = 32'sd100000;
        ram_PI[10] = -32'sd100000; ram_PQ[10] = 32'sd0;
        run_and_capture(9'd0);
        chk_phase("T6 lag=0  → 0",    cap_phase, gold_phase(32'sd100000,  32'sd0));
        run_and_capture(9'd5);
        chk_phase("T6 lag=5  → pi/2", cap_phase, gold_phase(32'sd0, 32'sd100000));
        run_and_capture(9'd10);
        chk_phase("T6 lag=10 → pi",   cap_phase, gold_phase(-32'sd100000, 32'sd0));

        // ====================================================================
        // T7: done pulse width = exactly 1 clock
        // ====================================================================
        $display("\n--- T7: done pulse width ---");
        clear_ram();
        ram_PI[0] = 32'sd50000;
        @(negedge aclk);
        peak_lag_d = 9'd0; start_d = 1'b1;
        @(posedge aclk); #1; start_d = 1'b0;
        done_cnt_l = 0; tctr_l = 0;
        while (!done && tctr_l < TIMEOUT) begin @(posedge aclk); #1; tctr_l++; end
        done_cnt_l = done ? 1 : 0;
        @(posedge aclk); #1;
        if (done_cnt_l == 1 && !done) done_cnt_l = 1;
        else if (done_cnt_l == 1 && done) done_cnt_l = 2;
        chk("T7 done width=1", (done_cnt_l == 1), 1'b1);

        // ====================================================================
        // T8: busy behavior
        // ====================================================================
        $display("\n--- T8: busy behavior ---");
        clear_ram();
        ram_PI[0] = 32'sd50000;
        run_and_capture(9'd0);
        chk("T8 busy=0 after done", busy, 1'b0);
        @(negedge aclk); peak_lag_d = 9'd0; start_d = 1'b1;
        @(posedge aclk); #1; start_d = 1'b0;
        chk("T8 busy=1 while running", busy, 1'b1);
        tctr_l = 0;
        while (!done && tctr_l < TIMEOUT) begin @(posedge aclk); #1; tctr_l++; end

        // ====================================================================
        // T9: back-to-back runs update result correctly
        // ====================================================================
        $display("\n--- T9: back-to-back runs ---");
        clear_ram();
        ram_PI[0] = 32'sd100000; ram_PQ[0] = 32'sd0;
        run_and_capture(9'd0);
        chk("T9 run1 done", done, 1'b1);
        chk_phase("T9 run1 phase", cap_phase, gold_phase(32'sd100000, 32'sd0));
        clear_ram();
        ram_PI[0] = 32'sd0; ram_PQ[0] = 32'sd100000;
        run_and_capture(9'd0);
        chk("T9 run2 done", done, 1'b1);
        chk_phase("T9 run2 phase", cap_phase, gold_phase(32'sd0, 32'sd100000));

        // ====================================================================
        // T10: PRNG smoke test — 8 lags with random values
        // ====================================================================
        $display("\n--- T10: PRNG smoke ---");
        clear_ram();
        for (i10 = 0; i10 < 8; i10 = i10 + 1) begin
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            t10_I[i10] = $signed(prng);
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            t10_Q[i10] = $signed(prng);
            ram_PI[i10] = t10_I[i10];
            ram_PQ[i10] = t10_Q[i10];
        end
        for (i10 = 0; i10 < 8; i10 = i10 + 1) begin
            run_and_capture(i10[8:0]);
            chk_phase($sformatf("T10 lag%0d", i10), cap_phase,
                      gold_phase(t10_I[i10], t10_Q[i10]));
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
