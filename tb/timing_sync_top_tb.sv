`timescale 1ns/1ps

// timing_sync_top_tb — 4 test groups, ~25 checks.
//
// Uses reduced NSC=16, CP_LEN=4 to keep simulation fast
// (~280 cycles per run vs ~33k at full scale).
//
// Buffer model: synchronous ROM with 1-clock read latency (matches
// cp_autocorr_core's expected buf_rd_en/buf_rd_addr/buf_rd_data interface).
//
// Tests:
//   T1  Reset: done=0, busy=0
//   T2  All-zero buffer → all metrics=0, peak at lag=0 (first-wins default),
//       peak_corr_i/q/energy=0, done fires, busy de-asserts
//   T3  Constant I=100 Q=50 → known P_I/P_Q/E at every lag; peak_lag=0,
//       peak_corr_i=50000 peak_corr_q=0 peak_energy=100000
//   T4  Re-run after done (step_word=0): second run completes cleanly
//
// Arithmetic for T3 (NSC=16, CP_LEN=4):
//   P_I[m] = 4*(100*100 + 50*50)   = 50000
//   P_Q[m] = 4*(-100*50 + 50*100)  = 0
//   E[m]   = 4*(100²+50²+100²+50²) = 100000
//   M[m]   = 2*50000 - 100000 = 0  → metric_out=0 for all lags
//   peak_detector never improves on initial running_max=0 → peak_lag=0

module timing_sync_top_tb;

    localparam int NSC_TB         = 16;
    localparam int CP_LEN_TB      = 4;
    localparam int ADDR_WIDTH_TB  = 12;
    localparam int METRIC_WIDTH_TB= 32;
    localparam int INDEX_WIDTH_TB = 9;
    localparam int RESULT_WIDTH_TB= 32;
    localparam int CLK_HALF       = 5;
    // Autocorr: 4*CP_LEN*NSC+1 = 257; metric: 16; latch+done: 2. Total ~280.
    localparam int TIMEOUT_CYC    = 1000;

    // Expected values for T3
    localparam int EXP_CORR_I  = 50000;
    localparam int EXP_CORR_Q  = 0;
    localparam int EXP_ENERGY  = 100000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                        start_d;
    logic [ADDR_WIDTH_TB-1:0]    base_addr_d;
    wire                         done_w, busy_w;
    wire  [ADDR_WIDTH_TB-1:0]    buf_rd_addr_w;
    wire                         buf_rd_en_w;
    logic signed [15:0]          buf_rd_data_I_d, buf_rd_data_Q_d;
    wire  [INDEX_WIDTH_TB-1:0]   peak_lag_w;
    wire  [METRIC_WIDTH_TB-1:0]  peak_metric_w;
    wire  signed [RESULT_WIDTH_TB-1:0] peak_corr_i_w, peak_corr_q_w;
    wire         [RESULT_WIDTH_TB-1:0] peak_energy_w;

    timing_sync_top #(
        .NSC         (NSC_TB),
        .CP_LEN      (CP_LEN_TB),
        .ADDR_WIDTH  (ADDR_WIDTH_TB),
        .METRIC_WIDTH(METRIC_WIDTH_TB),
        .INDEX_WIDTH (INDEX_WIDTH_TB),
        .RESULT_WIDTH(RESULT_WIDTH_TB)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .start         (start_d),
        .base_addr     (base_addr_d),
        .done          (done_w),
        .busy          (busy_w),
        .buf_rd_addr   (buf_rd_addr_w),
        .buf_rd_en     (buf_rd_en_w),
        .buf_rd_data_I (buf_rd_data_I_d),
        .buf_rd_data_Q (buf_rd_data_Q_d),
        .peak_lag      (peak_lag_w),
        .peak_metric   (peak_metric_w),
        .peak_corr_i   (peak_corr_i_w),
        .peak_corr_q   (peak_corr_q_w),
        .peak_energy   (peak_energy_w)
    );

    // -----------------------------------------------------------------------
    // Buffer RAM model — synchronous read, 1-clock latency
    // buf_rd_data_I/Q hold the value written to the RAM
    // -----------------------------------------------------------------------
    logic [31:0] mem [0:4095];  // {Q[31:16], I[15:0]}

    always @(posedge aclk) begin
        // Register address → data appears 1 cycle later (matches BRAM behaviour)
        buf_rd_data_I_d <= $signed(mem[buf_rd_addr_w][15:0]);
        buf_rd_data_Q_d <= $signed(mem[buf_rd_addr_w][31:16]);
    end

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp) begin $display("[PASS] %s", nm); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_int(input string nm, input int got, input int exp);
        if (got === exp) begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_uint(input string nm, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Wait for done with timeout
    // -----------------------------------------------------------------------
    task automatic wait_done(output logic timed_out);
        int cnt;
        timed_out = 1'b0;
        for (cnt = 0; cnt < TIMEOUT_CYC; cnt++) begin
            @(posedge aclk); #1;
            if (done_w) return;
        end
        timed_out = 1'b1;
        $display("[FAIL] timeout waiting for done");
        fail_cnt++;
    endtask

    // -----------------------------------------------------------------------
    // Initialize buffer to constant value
    // -----------------------------------------------------------------------
    task automatic fill_buf(input shortint I_val, input shortint Q_val);
        for (int i = 0; i < 4096; i++)
            mem[i] = {Q_val[15:0], I_val[15:0]};
    endtask

    // -----------------------------------------------------------------------
    // Run one timing_sync_top pass; return outputs
    // -----------------------------------------------------------------------
    task automatic run_pass(
        input  logic [ADDR_WIDTH_TB-1:0] baddr,
        output logic timed_out,
        output logic [INDEX_WIDTH_TB-1:0]   pl,
        output logic [METRIC_WIDTH_TB-1:0]  pm,
        output logic signed [RESULT_WIDTH_TB-1:0] ci, cq,
        output logic        [RESULT_WIDTH_TB-1:0] en
    );
        @(negedge aclk);
        start_d     = 1'b1;
        base_addr_d = baddr;
        @(posedge aclk); #1;
        start_d = 1'b0;
        chk("busy asserted on start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            pl = peak_lag_w;
            pm = peak_metric_w;
            ci = peak_corr_i_w;
            cq = peak_corr_q_w;
            en = peak_energy_w;
            @(posedge aclk); #1;   // confirm busy de-asserted
            chk("busy de-asserted after done", busy_w, 1'b0);
        end
    endtask

    // -----------------------------------------------------------------------
    // Temporaries
    // -----------------------------------------------------------------------
    logic timed_out;
    logic [INDEX_WIDTH_TB-1:0]          r_pl;
    logic [METRIC_WIDTH_TB-1:0]         r_pm;
    logic signed [RESULT_WIDTH_TB-1:0]  r_ci, r_cq;
    logic        [RESULT_WIDTH_TB-1:0]  r_en;

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn     = 1'b0;
        start_d     = 1'b0;
        base_addr_d = '0;
        pass_cnt    = 0;
        fail_cnt    = 0;
        fill_buf(0, 0);

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T1: Reset
        // ====================================================================
        $display("\n--- T1: Reset ---");
        @(posedge aclk); #1;
        chk("T1 done=0", done_w, 1'b0);
        chk("T1 busy=0", busy_w, 1'b0);

        // ====================================================================
        // T2: All-zero buffer
        //   All metrics = 0, peak_detector never updates → peak_lag=0
        //   (index stays at reset value; running_max starts at 0 and 0>0 is false)
        //   All corr/energy outputs = 0
        // ====================================================================
        $display("\n--- T2: All-zero buffer ---");
        fill_buf(0, 0);
        run_pass(12'h000, timed_out, r_pl, r_pm, r_ci, r_cq, r_en);
        if (!timed_out) begin
            chk_int ("T2 peak_lag=0",    int'(r_pl), 0);
            chk_int ("T2 peak_corr_i=0", int'(r_ci), 0);
            chk_int ("T2 peak_corr_q=0", int'(r_cq), 0);
            chk_uint("T2 peak_energy=0", r_en,       32'd0);
        end

        // ====================================================================
        // T3: Constant I=100 Q=50 buffer
        //   Expected per lag: corr_i=50000, corr_q=0, energy=100000
        //   All metrics=0 → peak_lag=0 (first-wins, no improvement over 0)
        // ====================================================================
        $display("\n--- T3: Constant I=100 Q=50 ---");
        fill_buf(100, 50);
        run_pass(12'h000, timed_out, r_pl, r_pm, r_ci, r_cq, r_en);
        if (!timed_out) begin
            chk_int ("T3 peak_lag=0",             int'(r_pl), 0);
            chk_int ("T3 peak_corr_i=50000",      int'(r_ci), EXP_CORR_I);
            chk_int ("T3 peak_corr_q=0",          int'(r_cq), EXP_CORR_Q);
            chk_uint("T3 peak_energy=100000",     r_en,       32'(EXP_ENERGY));
        end

        // ====================================================================
        // T4: Re-run (all-zero again) — verify module restarts cleanly
        // ====================================================================
        $display("\n--- T4: Re-run after done ---");
        fill_buf(0, 0);
        run_pass(12'h000, timed_out, r_pl, r_pm, r_ci, r_cq, r_en);
        if (!timed_out) begin
            chk_int("T4 peak_lag=0",    int'(r_pl), 0);
            chk_int("T4 peak_corr_i=0", int'(r_ci), 0);
            chk_int("T4 peak_corr_q=0", int'(r_cq), 0);
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

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    initial begin
        #(10000 * CLK_HALF * 2);
        $display("[FAIL] Global watchdog timeout");
        $finish;
    end

endmodule
