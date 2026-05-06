`timescale 1ns/1ps

// frame_timing_sync_top_tb — 4 test groups, ~20 checks.
//
// Small parameters for fast simulation:
//   NSC=16, CP_LEN=4, BUF_AW=8 (DEPTH=256)
//   WINDOW_LEN=4, HIT_COUNT=2, threshold_in=1 (any signal triggers)
//
// T1  Reset: done=0, busy=0, frame_error=0
// T2  Happy path: 8 quiet (I=0,Q=0) + 100 signal (I=100,Q=50) samples
//       → frame found, timing done, frac_phase=0
// T3  Frame not found: 32 all-zero samples
//       → frame_error=1, done fires, frac_phase_valid never asserted
// T4  Re-run after done: same as T2 → module restarts cleanly

module frame_timing_sync_top_tb;

    localparam int NSC_TB          = 16;
    localparam int CP_LEN_TB       = 4;
    localparam int BUF_AW_TB       = 10;
    localparam int METRIC_WIDTH_TB = 32;
    localparam int INDEX_WIDTH_TB  = 9;
    localparam int RESULT_WIDTH_TB = 32;
    localparam int PHASE_WIDTH_TB  = 16;
    localparam int ENERGY_WIDTH_TB = 40;
    localparam int CLK_HALF        = 5;
    localparam int TIMEOUT_CYC     = 5000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic [31:0]                       s_axis_tdata_d;
    logic                              s_axis_tvalid_d;
    wire                               s_axis_tready_w;
    logic                              s_axis_tlast_d;

    logic                              start_d;
    wire                               done_w, busy_w, frame_error_w;

    logic [ENERGY_WIDTH_TB-1:0]        threshold_d;
    logic [6:0]                        window_len_d;
    logic [3:0]                        hit_count_d;

    wire  [BUF_AW_TB-1:0]              frame_index_w;
    wire                               frame_found_w;
    wire  [INDEX_WIDTH_TB-1:0]         peak_lag_w;
    wire  [METRIC_WIDTH_TB-1:0]        peak_metric_w;
    wire  signed [RESULT_WIDTH_TB-1:0] peak_corr_i_w, peak_corr_q_w;
    wire         [RESULT_WIDTH_TB-1:0] peak_energy_w;
    wire  [PHASE_WIDTH_TB-1:0]         frac_phase_w;
    wire                               frac_phase_valid_w;

    frame_timing_sync_top #(
        .NSC         (NSC_TB),
        .CP_LEN      (CP_LEN_TB),
        .BUF_AW      (BUF_AW_TB),
        .METRIC_WIDTH(METRIC_WIDTH_TB),
        .INDEX_WIDTH (INDEX_WIDTH_TB),
        .RESULT_WIDTH(RESULT_WIDTH_TB),
        .PHASE_WIDTH (PHASE_WIDTH_TB),
        .ENERGY_WIDTH(ENERGY_WIDTH_TB),
        .WINDOW_LEN  (4),
        .HIT_COUNT   (2),
        .THRESHOLD   (1)
    ) dut (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .s_axis_tdata     (s_axis_tdata_d),
        .s_axis_tvalid    (s_axis_tvalid_d),
        .s_axis_tready    (s_axis_tready_w),
        .s_axis_tlast     (s_axis_tlast_d),
        .start            (start_d),
        .done             (done_w),
        .busy             (busy_w),
        .frame_error      (frame_error_w),
        .threshold_in     (threshold_d),
        .window_len_in    (window_len_d),
        .hit_count_in     (hit_count_d),
        .frame_index      (frame_index_w),
        .frame_found      (frame_found_w),
        .peak_lag         (peak_lag_w),
        .peak_metric      (peak_metric_w),
        .peak_corr_i      (peak_corr_i_w),
        .peak_corr_q      (peak_corr_q_w),
        .peak_energy      (peak_energy_w),
        .frac_phase       (frac_phase_w),
        .frac_phase_valid (frac_phase_valid_w)
    );

    // -----------------------------------------------------------------------
    // Capture frac_phase_valid pulse
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

    // -----------------------------------------------------------------------
    // Stream n samples with given I/Q via AXI-Stream.
    // Waits for tready before each beat; first_n beats use (I0,Q0),
    // remaining beats use (I1,Q1).
    // -----------------------------------------------------------------------
    task automatic stream_iq(
        input int first_n, input shortint I0, input shortint Q0,
        input int total_n, input shortint I1, input shortint Q1
    );
        int i = 0;
        while (i < total_n) begin
            @(negedge aclk);
            if (i < first_n)
                s_axis_tdata_d = {Q0[15:0], I0[15:0]};
            else
                s_axis_tdata_d = {Q1[15:0], I1[15:0]};
            s_axis_tvalid_d = 1'b1;
            s_axis_tlast_d  = (i == total_n - 1) ? 1'b1 : 1'b0;
            // Sample tready at posedge before NBA phase: on the accepting edge for
            // tlast, iq_frame_buffer sets busy<=0 (NB), so tready goes low only
            // after the NBA phase. No #1 here ensures we see tready=1 on that edge.
            @(posedge aclk);
            if (s_axis_tready_w) i++;
        end
        @(negedge aclk);
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
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
    // Pulse start for one clock
    // -----------------------------------------------------------------------
    task automatic pulse_start;
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        @(negedge aclk);
        start_d = 1'b0;
    endtask

    logic timed_out;

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn         = 1'b0;
        start_d         = 1'b0;
        s_axis_tdata_d  = '0;
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
        threshold_d     = ENERGY_WIDTH_TB'(1);
        window_len_d    = 7'd4;
        hit_count_d     = 4'd2;
        pass_cnt = 0;
        fail_cnt = 0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T1: Reset
        // ====================================================================
        $display("\n--- T1: Reset ---");
        @(posedge aclk); #1;
        chk("T1 done=0",        done_w,        1'b0);
        chk("T1 busy=0",        busy_w,        1'b0);
        chk("T1 frame_error=0", frame_error_w, 1'b0);

        // ====================================================================
        // T2: Happy path
        //   8 quiet (I=0,Q=0) + 100 signal (I=100,Q=50), total 108 samples
        //   Frame detector (window=4, hit=2, thresh=1) detects frame in signal region.
        //   timing_frac_cfo_top sees uniform I=100,Q=50 → frac_phase=0
        // ====================================================================
        $display("\n--- T2: Happy path (8 quiet + 100 signal) ---");
        fork
            begin : start_proc
                pulse_start;
            end
            begin : stream_proc
                // Wait for capture to start (tready goes high 1-2 cycles after start)
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                // stream_iq: first 8 beats quiet, remaining 100 signal
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd50);
            end
        join
        @(posedge aclk); #1;
        chk("T2 busy=1 after start", busy_w, 1'b1);
        wait_done(timed_out);
        if (!timed_out) begin
            chk    ("T2 done fires",         done_w,        1'b1);
            chk    ("T2 frame_found",         frame_found_w, 1'b1);
            chk    ("T2 frame_error=0",       frame_error_w, 1'b0);
            chk    ("T2 frac_phase_valid",    fpv_seen,      1'b1);
            chk_int("T2 frac_phase=0",        $signed(frac_cap), 0);
            chk_int("T2 peak_corr_q=0",       int'(peak_corr_q_w), 0);
            @(posedge aclk); #1;
            chk    ("T2 busy=0 after done",   busy_w, 1'b0);
        end
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T3: Frame not found (all-zero buffer, 32 samples)
        //   frame_detector exhausts search → frame_found=0 → frame_error=1
        // ====================================================================
        $display("\n--- T3: Frame not found (32 zeros) ---");
        // Reset to clear fpv_seen
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(32, 16'sd0, 16'sd0, 32, 16'sd0, 16'sd0);
            end
        join
        wait_done(timed_out);
        if (!timed_out) begin
            chk("T3 done fires",        done_w,        1'b1);
            chk("T3 frame_found=0",     frame_found_w, 1'b0);
            chk("T3 frame_error=1",     frame_error_w, 1'b1);
            chk("T3 fpv_seen=0",        fpv_seen,      1'b0);
            @(posedge aclk); #1;
            chk("T3 busy=0 after done", busy_w,        1'b0);
        end
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T4: Re-run after done (same as T2) — module restarts cleanly
        // ====================================================================
        $display("\n--- T4: Re-run after done ---");
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd50);
            end
        join
        wait_done(timed_out);
        if (!timed_out) begin
            chk    ("T4 done fires",      done_w,        1'b1);
            chk    ("T4 frame_found",     frame_found_w, 1'b1);
            chk    ("T4 frac_phase_valid",fpv_seen,      1'b1);
            chk_int("T4 frac_phase=0",    $signed(frac_cap), 0);
            @(posedge aclk); #1;
            chk    ("T4 busy=0",          busy_w,        1'b0);
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
        #(40000 * CLK_HALF * 2);
        $display("[FAIL] Global watchdog timeout");
        $finish;
    end

endmodule
