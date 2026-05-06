`timescale 1ns/1ps

// cp_autocorr_core_tb — 15 test groups, ~65 checks.
//
// DUT parameters: NSC=16, CP_LEN=4, ADDR_WIDTH=8, INDEX_WIDTH=4
//   → 16 lags × 4 taps × 4 cycles = 256 cycles per run (fast sim).
//
// Buffer model: 256-entry × 32-bit reg array ({Q[31:16], I[15:0]}),
// 1-clock registered latency matching iq_frame_buffer.
//
// All arithmetic uses 64-bit integers for golden model to avoid overflow.

module cp_autocorr_core_tb;

    // -----------------------------------------------------------------------
    // DUT parameters
    // -----------------------------------------------------------------------
    localparam int NSC   = 16;
    localparam int CPL   = 4;
    localparam int AW    = 8;
    localparam int IW    = 4;    // INDEX_WIDTH = log2(NSC)
    localparam int ACCW  = 40;
    localparam int RW    = 32;
    localparam int DEP   = 256;  // 2^AW

    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 50000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT port signals
    // -----------------------------------------------------------------------
    logic                         start_d;
    logic [AW-1:0]                base_addr_d;

    logic                         done;
    logic                         busy;

    wire  [AW-1:0]                buf_rd_addr;
    wire                          buf_rd_en;
    logic signed [15:0]           buf_rd_data_I_d;
    logic signed [15:0]           buf_rd_data_Q_d;

    logic [IW-1:0]                result_rd_addr_d;
    wire  signed [RW-1:0]         result_autocorr_I;
    wire  signed [RW-1:0]         result_autocorr_Q;
    wire         [RW-1:0]         result_norm_E;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    cp_autocorr_core #(
        .NSC         (NSC),
        .CP_LEN      (CPL),
        .ADDR_WIDTH  (AW),
        .ACC_WIDTH   (ACCW),
        .INDEX_WIDTH (IW),
        .RESULT_WIDTH(RW)
    ) dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .start           (start_d),
        .base_addr       (base_addr_d),
        .done            (done),
        .busy            (busy),
        .buf_rd_addr     (buf_rd_addr),
        .buf_rd_en       (buf_rd_en),
        .buf_rd_data_I   (buf_rd_data_I_d),
        .buf_rd_data_Q   (buf_rd_data_Q_d),
        .result_rd_addr  (result_rd_addr_d),
        .result_autocorr_I(result_autocorr_I),
        .result_autocorr_Q(result_autocorr_Q),
        .result_norm_E   (result_norm_E)
    );

    // -----------------------------------------------------------------------
    // Behavioral buffer model: 256 × 32-bit, 1-clock registered latency
    // -----------------------------------------------------------------------
    logic [31:0] buf_mem [0:DEP-1];

    always @(posedge aclk) begin
        if (buf_rd_en) begin
            buf_rd_data_I_d <= $signed(buf_mem[buf_rd_addr][15:0]);
            buf_rd_data_Q_d <= $signed(buf_mem[buf_rd_addr][31:16]);
        end
    end

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);           pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_val32(input string nm, input logic signed [31:0] got,
                              input longint signed exp);
        if ($signed(got) === exp[31:0])
            begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d", nm, $signed(got), exp[31:0]); fail_cnt++; end
    endtask

    task automatic chk_u32(input string nm, input logic [31:0] got,
                            input longint unsigned exp);
        if (got === exp[31:0])
            begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp[31:0]); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Helper: clear the buffer
    // -----------------------------------------------------------------------
    task automatic clear_buf();
        for (int i = 0; i < DEP; i++) buf_mem[i] = 32'd0;
    endtask

    // -----------------------------------------------------------------------
    // Helper: write a sample to buffer (I=lower 16, Q=upper 16)
    // -----------------------------------------------------------------------
    task automatic set_sample(input int addr, input int I_val, input int Q_val);
        buf_mem[addr] = {Q_val[15:0], I_val[15:0]};
    endtask

    // -----------------------------------------------------------------------
    // Helper: run autocorrelation and wait for done; returns on done pulse.
    // -----------------------------------------------------------------------
    task automatic run_autocorr(input logic [AW-1:0] baddr);
        int tctr;
        @(negedge aclk);
        base_addr_d = baddr;
        start_d     = 1'b1;
        @(negedge aclk);
        start_d     = 1'b0;
        tctr = 0;
        @(posedge aclk); #1;
        while (!done && tctr < TIMEOUT) begin
            @(posedge aclk); #1;
            tctr++;
        end
        if (tctr >= TIMEOUT)
            $display("[FAIL] TIMEOUT in run_autocorr");
    endtask

    // -----------------------------------------------------------------------
    // Golden model — 64-bit integer arithmetic
    // -----------------------------------------------------------------------
    function automatic longint signed gold_PI(input int base, lag, cp_len);
        longint signed s; int aI, aQ, bI, bQ;
        s = 0;
        for (int k = 0; k < cp_len; k++) begin
            aI = $signed(buf_mem[base+lag+k][15:0]);
            aQ = $signed(buf_mem[base+lag+k][31:16]);
            bI = $signed(buf_mem[base+lag+k+NSC][15:0]);
            bQ = $signed(buf_mem[base+lag+k+NSC][31:16]);
            s += aI*bI + aQ*bQ;
        end
        return s;
    endfunction

    function automatic longint signed gold_PQ(input int base, lag, cp_len);
        longint signed s; int aI, aQ, bI, bQ;
        s = 0;
        for (int k = 0; k < cp_len; k++) begin
            aI = $signed(buf_mem[base+lag+k][15:0]);
            aQ = $signed(buf_mem[base+lag+k][31:16]);
            bI = $signed(buf_mem[base+lag+k+NSC][15:0]);
            bQ = $signed(buf_mem[base+lag+k+NSC][31:16]);
            s += -aI*bQ + aQ*bI;
        end
        return s;
    endfunction

    function automatic longint unsigned gold_E(input int base, lag, cp_len);
        longint unsigned s; int aI, aQ, bI, bQ;
        s = 0;
        for (int k = 0; k < cp_len; k++) begin
            aI = $signed(buf_mem[base+lag+k][15:0]);
            aQ = $signed(buf_mem[base+lag+k][31:16]);
            bI = $signed(buf_mem[base+lag+k+NSC][15:0]);
            bQ = $signed(buf_mem[base+lag+k+NSC][31:16]);
            s += aI*aI + aQ*aQ + bI*bI + bQ*bQ;
        end
        return s;
    endfunction

    // -----------------------------------------------------------------------
    // Helper: read a lag result and check against golden model
    // -----------------------------------------------------------------------
    task automatic chk_lag(input string prefix, input int base, lag);
        longint signed ePI, ePQ;
        longint unsigned eE;
        ePI = gold_PI(base, lag, CPL);
        ePQ = gold_PQ(base, lag, CPL);
        eE  = gold_E (base, lag, CPL);
        result_rd_addr_d = lag[IW-1:0];
        #1;   // combinatorial read
        chk_val32({prefix, " PI"}, result_autocorr_I, ePI);
        chk_val32({prefix, " PQ"}, result_autocorr_Q, ePQ);
        chk_u32  ({prefix, " E" }, result_norm_E,     eE);
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [31:0] prng;

    initial begin
        // Default inputs
        aresetn        = 1'b0;
        start_d        = 1'b0;
        base_addr_d    = 8'd0;
        result_rd_addr_d = 4'd0;
        pass_cnt       = 0;
        fail_cnt       = 0;
        prng           = 32'hDEAD_BEEF;

        // Release reset after 4 cycles
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;

        // ====================================================================
        // T1: Reset state
        // ====================================================================
        $display("\n--- T1: Reset state ---");
        chk("T1 done=0",      done,     1'b0);
        chk("T1 busy=0",      busy,     1'b0);
        chk("T1 buf_rd_en=0", buf_rd_en,1'b0);

        // ====================================================================
        // T2: All-zero buffer → all results zero
        // ====================================================================
        $display("\n--- T2: All-zero buffer ---");
        clear_buf();
        run_autocorr(8'd0);
        chk("T2 done pulse", done, 1'b1);
        chk("T2 busy clear", busy, 1'b0);
        chk_lag("T2 lag0",  0, 0);
        chk_lag("T2 lag15", 0, 15);

        // ====================================================================
        // T3: Single non-zero tap (lag=0, tap=0 only), real-only inputs
        //   A = {I=100, Q=0}, B = {I=200, Q=0}
        //   Expected P_I=20000, P_Q=0, E=50000
        // ====================================================================
        $display("\n--- T3: Single tap, real-only ---");
        clear_buf();
        set_sample(0,          100, 0);     // A: lag=0, tap=0
        set_sample(0 + NSC,    200, 0);     // B: lag=0, tap=0
        run_autocorr(8'd0);
        chk("T3 done", done, 1'b1);
        chk_lag("T3 lag0", 0, 0);
        chk_lag("T3 lag1", 0, 1);   // lag1 should be zero (no data there)

        // ====================================================================
        // T4: All CP_LEN taps of lag=0, real-only
        //   A[k] = {I=100, Q=0}, B[k] = {I=50, Q=0} for k=0..3
        //   P_I = 4*100*50 = 20000, P_Q=0, E = 4*(100^2+50^2) = 50000
        // ====================================================================
        $display("\n--- T4: All CP_LEN taps, real-only ---");
        clear_buf();
        for (int k = 0; k < CPL; k++) begin
            set_sample(k,       100, 0);
            set_sample(k + NSC, 50,  0);
        end
        run_autocorr(8'd0);
        chk("T4 done", done, 1'b1);
        chk_lag("T4 lag0", 0, 0);

        // ====================================================================
        // T5: Q-only inputs (I=0)
        //   A = {I=0, Q=100}, B = {I=0, Q=50}
        //   P_I = 0*0+100*50 = 5000, P_Q = -(0*50)+100*0 = 0, E = 100^2+50^2 = 12500
        // ====================================================================
        $display("\n--- T5: Q-only, single tap ---");
        clear_buf();
        set_sample(0,       0, 100);
        set_sample(0 + NSC, 0, 50);
        run_autocorr(8'd0);
        chk("T5 done", done, 1'b1);
        chk_lag("T5 lag0", 0, 0);

        // ====================================================================
        // T6: Mixed I+Q, single tap at lag=0
        //   A = {I=100, Q=200}, B = {I=50, Q=75}
        //   P_I = 100*50+200*75 = 5000+15000 = 20000
        //   P_Q = -(100*75)+200*50 = -7500+10000 = 2500
        //   E   = 100^2+200^2+50^2+75^2 = 10000+40000+2500+5625 = 58125
        // ====================================================================
        $display("\n--- T6: Mixed I+Q, single tap ---");
        clear_buf();
        set_sample(0,       100, 200);
        set_sample(0 + NSC, 50,  75);
        run_autocorr(8'd0);
        chk("T6 done", done, 1'b1);
        chk_lag("T6 lag0", 0, 0);

        // ====================================================================
        // T7: Multiple lags non-zero simultaneously (lag=0 and lag=5)
        // ====================================================================
        $display("\n--- T7: Multiple non-zero lags ---");
        clear_buf();
        // Lag 0: A={I=10,Q=3}, B={I=7,Q=2} for all 4 taps
        for (int k = 0; k < CPL; k++) begin
            set_sample(k,           10, 3);
            set_sample(k + NSC,      7, 2);
        end
        // Lag 5: A={I=20,Q=5}, B={I=8,Q=4} for all 4 taps
        for (int k = 0; k < CPL; k++) begin
            set_sample(5 + k,       20, 5);
            set_sample(5 + k + NSC, 8,  4);
        end
        run_autocorr(8'd0);
        chk("T7 done", done, 1'b1);
        chk_lag("T7 lag0", 0, 0);
        chk_lag("T7 lag5", 0, 5);
        chk_lag("T7 lag3", 0, 3);   // zero lag (no data)

        // ====================================================================
        // T8: done pulse width is exactly 1 clock
        // ====================================================================
        $display("\n--- T8: done width = 1 clock ---");
        clear_buf();
        @(negedge aclk);
        base_addr_d = 8'd0; start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        // Wait for done
        begin
            int tctr; int done_cnt;
            done_cnt = 0; tctr = 0;
            @(posedge aclk); #1;
            while (!done && tctr < TIMEOUT) begin @(posedge aclk); #1; tctr++; end
            // done is high right now (just after posedge #1)
            if (done) begin
                done_cnt = 1;
                @(posedge aclk); #1;
                if (!done) done_cnt = 1; else done_cnt = 2;
            end
            chk("T8 done is 1-clock", (done_cnt == 1), 1'b1);
        end

        // ====================================================================
        // T9: busy deasserts simultaneously with done
        // ====================================================================
        $display("\n--- T9: busy deasserts with done ---");
        clear_buf();
        run_autocorr(8'd0);
        // At this point 'done' was just sampled high (by run_autocorr's final posedge)
        chk("T9 busy=0 on done", busy, 1'b0);
        // Start another run and check busy asserts quickly
        @(negedge aclk);
        start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        @(posedge aclk); #1;
        chk("T9 busy=1 while running", busy, 1'b1);
        // Wait for done
        begin
            int tctr; tctr = 0;
            while (!done && tctr < TIMEOUT) begin @(posedge aclk); #1; tctr++; end
        end

        // ====================================================================
        // T10: Back-to-back runs update results correctly
        // ====================================================================
        $display("\n--- T10: Back-to-back runs ---");
        clear_buf();
        // Run 1: lag=0 gets {I=10, Q=0} * {I=5, Q=0} × 4 taps = P_I=200
        for (int k = 0; k < CPL; k++) begin
            set_sample(k,       10, 0);
            set_sample(k + NSC, 5,  0);
        end
        run_autocorr(8'd0);
        chk("T10 run1 done", done, 1'b1);
        result_rd_addr_d = 4'd0; #1;
        chk_val32("T10 run1 lag0 PI", result_autocorr_I, 200);

        // Run 2: clear and use different values
        clear_buf();
        for (int k = 0; k < CPL; k++) begin
            set_sample(k,       30, 0);
            set_sample(k + NSC, 7,  0);
        end
        run_autocorr(8'd0);
        chk("T10 run2 done", done, 1'b1);
        result_rd_addr_d = 4'd0; #1;
        chk_val32("T10 run2 lag0 PI", result_autocorr_I, 840);  // 4*30*7

        // ====================================================================
        // T11: Non-zero base_addr
        //   Place data at offset 20 in buffer
        // ====================================================================
        $display("\n--- T11: Non-zero base_addr ---");
        clear_buf();
        // Place lag=0 samples at base=20
        set_sample(20,          50, 0);
        set_sample(20 + NSC,   100, 0);
        run_autocorr(8'd20);
        chk("T11 done", done, 1'b1);
        chk_lag("T11 lag0", 20, 0);   // base=20, lag=0

        // ====================================================================
        // T12: Negative inputs
        //   A = {I=-100, Q=-200}, B = {I=50, Q=-75}
        //   P_I = (-100)*50 + (-200)*(-75) = -5000+15000 = 10000
        //   P_Q = -(-100)*(-75) + (-200)*50 = -7500-10000 = -17500
        //   E   = 100^2+200^2+50^2+75^2 = 58125
        // ====================================================================
        $display("\n--- T12: Negative inputs ---");
        clear_buf();
        set_sample(0,       -100, -200);
        set_sample(0 + NSC,  50,  -75);
        run_autocorr(8'd0);
        chk("T12 done", done, 1'b1);
        chk_lag("T12 lag0", 0, 0);

        // ====================================================================
        // T13: All NSC lags non-zero (full sweep)
        //   Each lag m: A={I=1,Q=0}, B={I=2,Q=0} for CP_LEN taps
        //   Expected per lag: P_I=CPL*1*2=8, P_Q=0, E=CPL*(1+4)=20
        // ====================================================================
        $display("\n--- T13: All lags sweep ---");
        clear_buf();
        for (int m = 0; m < NSC; m++) begin
            for (int k = 0; k < CPL; k++) begin
                set_sample(m + k,       1, 0);
                set_sample(m + k + NSC, 2, 0);
            end
        end
        run_autocorr(8'd0);
        chk("T13 done", done, 1'b1);
        // Check first, middle, last lag
        chk_lag("T13 lag0",  0, 0);
        chk_lag("T13 lag8",  0, 8);
        chk_lag("T13 lag15", 0, 15);

        // ====================================================================
        // T14: result_rd_addr reads correct lag after run
        // ====================================================================
        $display("\n--- T14: result_rd_addr selects different lags ---");
        clear_buf();
        // Lag 2: {I=300, Q=0} * {I=400, Q=0} → P_I=4*120000=480000
        for (int k = 0; k < CPL; k++) begin
            set_sample(2 + k,       300, 0);
            set_sample(2 + k + NSC, 400, 0);
        end
        // Lag 11: {I=500, Q=0} * {I=600, Q=0} → P_I=4*300000=1200000
        for (int k = 0; k < CPL; k++) begin
            set_sample(11 + k,       500, 0);
            set_sample(11 + k + NSC, 600, 0);
        end
        run_autocorr(8'd0);
        chk("T14 done", done, 1'b1);
        chk_lag("T14 lag2",  0, 2);
        chk_lag("T14 lag11", 0, 11);
        // Lag 7 should be zero
        result_rd_addr_d = 4'd7; #1;
        chk_val32("T14 lag7 PI=0", result_autocorr_I, 0);

        // ====================================================================
        // T15: PRNG smoke — random I/Q values for lag=0 all taps
        // ====================================================================
        $display("\n--- T15: PRNG smoke test ---");
        clear_buf();
        for (int k = 0; k < CPL; k++) begin
            // Galois LFSR step
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            set_sample(k,       $signed(prng[15:0]),  $signed(prng[31:16]));
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            set_sample(k + NSC, $signed(prng[15:0]),  $signed(prng[31:16]));
        end
        run_autocorr(8'd0);
        chk("T15 done", done, 1'b1);
        chk_lag("T15 lag0_PI_PQ_E", 0, 0);
        // Verify a zero lag is still zero (other lags not filled)
        chk_lag("T15 lag5_zero",    0, 5);

        // ====================================================================
        // Summary
        // ====================================================================
        $display("\n========================================");
        $display("PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("========================================\n");

        $finish;
    end

endmodule
