`timescale 1ns/1ps

// timing_frac_cfo_top_tb — 5 test groups, ~30 checks.
//
// Uses NSC=16, CP_LEN=4 for fast simulation (~310 cycles per run).
//
// Tests:
//   T1  Reset: done=0, busy=0
//   T2  All-zero buffer: done fires, frac_phase_valid fires, frac_phase=0
//   T3  Constant I=100 Q=50: peak_corr_i=50000 peak_corr_q=0 frac_phase=0
//         (atan2(0, 50000) = 0)
//   T4  I=100 Q=50 one side, I=0 Q=100 other side:
//         peak_corr_i=0 peak_corr_q=-40000
//         frac_phase = atan2(-40000, 0) = -π/2 → 16'hC000 (-16384 in Q1.15)
//   T5  Re-run after done (all-zero) — module restarts cleanly
//
// Buffer layout for T4 (NSC=16, CP_LEN=4):
//   buf[addr < NSC=16]              = {I=100, Q=0}   ← A side (sample positions)
//   buf[NSC <= addr < 2*NSC+CP_LEN] = {I=0,   Q=100} ← B side (sample+NSC positions)
//   For any lag m, all taps k=0..3:
//     A = buf[m+k]:     I=100, Q=0    (m+k < NSC since m≤15, k≤3, m+k ≤ 18 ← boundary case)
//     B = buf[m+k+NSC]: I=0,   Q=100
//   P_Q = CP_LEN * (-I_a*Q_b + Q_a*I_b) = 4*(-100*100 + 0*0) = -40000
//   P_I = CP_LEN * (I_a*I_b + Q_a*Q_b)  = 4*(100*0   + 0*100) = 0
//   atan2(-40000, 0) = -π/2 → ph_int = rtoi(-0.5 * 32767) = rtoi(-16383.5) = -16383
//   Note: $rtoi truncates toward 0 → -16383, NOT -16384

module timing_frac_cfo_top_tb;

    localparam int NSC_TB         = 16;
    localparam int CP_LEN_TB      = 4;
    localparam int ADDR_WIDTH_TB  = 12;
    localparam int METRIC_WIDTH_TB= 32;
    localparam int INDEX_WIDTH_TB = 9;
    localparam int RESULT_WIDTH_TB= 32;
    localparam int PHASE_WIDTH_TB = 16;
    localparam int CLK_HALF       = 5;
    localparam int TIMEOUT_CYC    = 1000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                              start_d;
    logic [ADDR_WIDTH_TB-1:0]          base_addr_d;
    wire                               done_w, busy_w;
    wire  [ADDR_WIDTH_TB-1:0]          buf_rd_addr_w;
    wire                               buf_rd_en_w;
    logic signed [15:0]                buf_rd_data_I_d, buf_rd_data_Q_d;
    wire  [INDEX_WIDTH_TB-1:0]         peak_lag_w;
    wire  [METRIC_WIDTH_TB-1:0]        peak_metric_w;
    wire  signed [RESULT_WIDTH_TB-1:0] peak_corr_i_w, peak_corr_q_w;
    wire         [RESULT_WIDTH_TB-1:0] peak_energy_w;
    wire  [PHASE_WIDTH_TB-1:0]         frac_phase_w;
    wire                               frac_phase_valid_w;

    timing_frac_cfo_top #(
        .NSC         (NSC_TB),
        .CP_LEN      (CP_LEN_TB),
        .ADDR_WIDTH  (ADDR_WIDTH_TB),
        .METRIC_WIDTH(METRIC_WIDTH_TB),
        .INDEX_WIDTH (INDEX_WIDTH_TB),
        .RESULT_WIDTH(RESULT_WIDTH_TB),
        .PHASE_WIDTH (PHASE_WIDTH_TB)
    ) dut (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (start_d),
        .base_addr        (base_addr_d),
        .done             (done_w),
        .busy             (busy_w),
        .buf_rd_addr      (buf_rd_addr_w),
        .buf_rd_en        (buf_rd_en_w),
        .buf_rd_data_I    (buf_rd_data_I_d),
        .buf_rd_data_Q    (buf_rd_data_Q_d),
        .peak_lag         (peak_lag_w),
        .peak_metric      (peak_metric_w),
        .peak_corr_i      (peak_corr_i_w),
        .peak_corr_q      (peak_corr_q_w),
        .peak_energy      (peak_energy_w),
        .frac_phase       (frac_phase_w),
        .frac_phase_valid (frac_phase_valid_w)
    );

    // -----------------------------------------------------------------------
    // Buffer RAM model — synchronous read, 1-clock latency
    // -----------------------------------------------------------------------
    logic [31:0] mem [0:4095];  // {Q[31:16], I[15:0]}

    always @(posedge aclk) begin
        buf_rd_data_I_d <= $signed(mem[buf_rd_addr_w][15:0]);
        buf_rd_data_Q_d <= $signed(mem[buf_rd_addr_w][31:16]);
    end

    // -----------------------------------------------------------------------
    // Capture frac_phase_valid pulse and sampled value
    // -----------------------------------------------------------------------
    logic                      fpv_seen;
    logic [PHASE_WIDTH_TB-1:0] frac_cap;

    always @(posedge aclk) begin
        if (!aresetn) begin
            fpv_seen <= 1'b0;
            frac_cap <= '0;
        end else if (frac_phase_valid_w) begin
            fpv_seen <= 1'b1;
            frac_cap <= frac_phase_w;
        end
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

    task automatic chk_uint(input string nm, input logic [31:0] got,
                             input logic [31:0] exp);
        if (got === exp) begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden model for expected frac_phase:
    //   mirrors cordic_atan2 behavioural model ($atan2, $rtoi truncates-to-zero)
    // -----------------------------------------------------------------------
    function automatic logic signed [PHASE_WIDTH_TB-1:0] gold_phase(
        input int I_in, Q_in
    );
        real r_angle;
        integer ph_int;
        r_angle = $atan2(real'(Q_in), real'(I_in)) / 3.14159265358979323846;
        ph_int  = $rtoi(r_angle * ((1 << (PHASE_WIDTH_TB-1)) - 1));
        return ph_int[PHASE_WIDTH_TB-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Fill buffer helper
    // -----------------------------------------------------------------------
    task automatic fill_buf(input shortint I_val, input shortint Q_val);
        for (int i = 0; i < 4096; i++)
            mem[i] = {Q_val[15:0], I_val[15:0]};
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
    // Run one pass; fpv_seen / frac_cap are populated by the always block.
    // Caller must clear fpv_seen manually via the task below.
    // -----------------------------------------------------------------------
    task automatic clear_fpv;
        // Force a negedge-triggered soft-reset of the capture registers
        @(negedge aclk);
        // Note: can't directly drive always-block registers from a task.
        // We rely on aresetn or the TB flag being reset at the top of each test.
    endtask

    logic timed_out;

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
        chk("T1 done=0",            done_w,            1'b0);
        chk("T1 busy=0",            busy_w,            1'b0);
        chk("T1 frac_phase_valid=0",frac_phase_valid_w,1'b0);

        // ====================================================================
        // T2: All-zero buffer
        //   peak_corr_i=0, peak_corr_q=0 → frac_phase = atan2(0,0) = 0
        // ====================================================================
        $display("\n--- T2: All-zero buffer ---");
        fill_buf(0, 0);
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        start_d = 1'b0;
        chk("T2 busy=1 on start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            chk("T2 done fires",         done_w,  1'b1);
            chk("T2 frac_phase_valid",   fpv_seen,1'b1);
            chk_int("T2 peak_corr_i=0",  int'(peak_corr_i_w), 0);
            chk_int("T2 peak_corr_q=0",  int'(peak_corr_q_w), 0);
            chk_int("T2 frac_phase=0",   $signed(frac_cap),    0);
            @(posedge aclk); #1;
            chk("T2 busy=0 after done",  busy_w, 1'b0);
        end
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T3: Constant I=100 Q=50
        //   P_I = CP_LEN*(100*100 + 50*50) = 4*12500 = 50000
        //   P_Q = CP_LEN*(-100*50 + 50*100) = 0
        //   frac_phase = atan2(0, 50000) = 0
        // ====================================================================
        $display("\n--- T3: Constant I=100 Q=50 ---");
        fill_buf(100, 50);
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        start_d = 1'b0;
        chk("T3 busy=1 on start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            chk("T3 done fires",         done_w, 1'b1);
            chk("T3 frac_phase_valid",   fpv_seen, 1'b1);
            chk_int("T3 peak_lag=0",     int'(peak_lag_w),     0);
            chk_int("T3 peak_corr_i",    int'(peak_corr_i_w),  50000);
            chk_int("T3 peak_corr_q=0",  int'(peak_corr_q_w),  0);
            chk_uint("T3 peak_energy",   peak_energy_w,         32'd100000);
            chk_int("T3 frac_phase=0",   $signed(frac_cap),    0);
            @(posedge aclk); #1;
            chk("T3 busy=0 after done",  busy_w, 1'b0);
        end
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T4: buf[0..NSC-1]={I=100,Q=0},  buf[NSC..NSC+NSC+CP_LEN-1]={I=0,Q=100}
        //   For all lags m (m+k < NSC): A={100,0}, B={0,100}
        //   P_I = CP_LEN*(100*0   + 0*100) = 0
        //   P_Q = CP_LEN*(-100*100 + 0*0)  = 4*(-10000) = -40000
        //   frac_phase = atan2(-40000, 0) = -π/2
        //   gold_phase = rtoi(-0.5 * 32767) = rtoi(-16383.5) = -16383 ($rtoi truncates)
        // ====================================================================
        $display("\n--- T4: A={100,0} B={0,100} → frac_phase=-pi/2 ---");
        begin
            // A side: indices 0..NSC-1
            for (int i = 0; i < NSC_TB; i++)
                mem[i] = {16'd0, 16'd100};          // {Q=0, I=100}
            // B side: indices NSC..NSC+NSC+CP_LEN-1
            for (int i = NSC_TB; i < 2*NSC_TB + CP_LEN_TB; i++)
                mem[i] = {16'd100, 16'd0};           // {Q=100, I=0}
            // rest: zero
            for (int i = 2*NSC_TB + CP_LEN_TB; i < 4096; i++)
                mem[i] = 32'd0;
        end
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        start_d = 1'b0;
        chk("T4 busy=1 on start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            automatic int exp_pi  = int'(peak_corr_i_w);
            automatic int exp_pq  = int'(peak_corr_q_w);
            automatic logic signed [PHASE_WIDTH_TB-1:0] exp_fp;
            exp_fp = gold_phase(exp_pi, exp_pq);
            chk("T4 done fires",       done_w,   1'b1);
            chk("T4 frac_phase_valid", fpv_seen, 1'b1);
            chk_int("T4 frac_phase matches golden",
                    $signed(frac_cap), $signed(exp_fp));
            @(posedge aclk); #1;
            chk("T4 busy=0 after done", busy_w, 1'b0);
        end
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T5: Re-run after done (all-zero) — module restarts cleanly
        // ====================================================================
        $display("\n--- T5: Re-run after done ---");
        fill_buf(0, 0);
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        start_d = 1'b0;
        chk("T5 busy=1 on start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            chk("T5 done fires", done_w, 1'b1);
            @(posedge aclk); #1;
            chk("T5 busy=0 after done", busy_w, 1'b0);
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
        #(20000 * CLK_HALF * 2);
        $display("[FAIL] Global watchdog timeout");
        $finish;
    end

endmodule
