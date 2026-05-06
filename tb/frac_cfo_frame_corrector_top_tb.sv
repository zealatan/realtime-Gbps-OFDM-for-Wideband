`timescale 1ns/1ps

// frac_cfo_frame_corrector_top_tb — 10 test groups, ~44 checks.
//
// Small parameters for fast simulation:
//   NSC=16, CP_LEN=4, BUF_AW=10 (DEPTH=1024), LATENCY=15
//   WINDOW_LEN=4, HIT_COUNT=2, threshold=1 (any signal triggers)
//   TOTAL_SAMPLES = NSC+CP_LEN = 20
//
// Stimulus (T2 happy path): 8 quiet (I=0,Q=0) + 100 signal (I=100,Q=0).
//   frame_detector finds frame at index 5 (first above-threshold window).
//   CP autocorr: peak_lag=2 (metric=-10000 → max unsigned for lag<3; lag≥3 gives metric=0).
//   slot_start = 5+2 = 7: buf[7]=quiet→I_out=0, buf[8..26]=signal→I_out=99.
//   frac_phase=0 (pure-real constant signal → atan2(0,P_I)=0).
//   step_word=0 → NCO produces cos≈1, sin=0 → I_out=99, Q_out=0 for signal samples.
//
// T5 uses threshold_d='1 (max) so no frame is found regardless of leftover buffer
// data from T2 (iq_frame_buffer does not clear on reset; only freshly captured
// addresses receive new data, but old addresses retain prior values).
//
// T1   Reset: done=0, busy=0, frame_error=0
// T2   Happy path: fill + wait done + capture m_axis concurrently
//        → frame_found, frac_phase=0, m_axis produces 20 samples
// T3   m_axis count and tlast: exactly TOTAL_TB samples, tlast on index 19
// T4   m_axis sample values: samples[1..2] have I=99, Q=0 (signal-region samples)
// T5   Frame not found: max threshold → frame_error=1, done fires, no m_axis
// T6   done is exactly 1 clock wide
// T7   busy asserts at start, deasserts at done (same clock as done)
// T8   frame_index stable after done
// T9   peak_lag stable after done
// T10  Back-to-back runs: module restarts cleanly, same count+tlast

module frac_cfo_frame_corrector_top_tb;

    localparam int NSC_TB          = 16;
    localparam int CP_LEN_TB       = 4;
    localparam int TOTAL_TB        = NSC_TB + CP_LEN_TB;  // 20
    localparam int BUF_AW_TB       = 10;
    localparam int METRIC_WIDTH_TB = 32;
    localparam int INDEX_WIDTH_TB  = 9;
    localparam int RESULT_WIDTH_TB = 32;
    localparam int PHASE_WIDTH_TB  = 16;
    localparam int ENERGY_WIDTH_TB = 40;
    localparam int LATENCY_TB      = 15;
    localparam int CLK_HALF        = 5;
    localparam int TIMEOUT_CYC     = 400000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic [31:0] s_axis_tdata_d;
    logic        s_axis_tvalid_d;
    wire         s_axis_tready_w;
    logic        s_axis_tlast_d;

    logic        start_d;
    wire         done_w, busy_w, frame_error_w;

    logic [ENERGY_WIDTH_TB-1:0] threshold_d;
    logic [6:0]                 window_len_d;
    logic [3:0]                 hit_count_d;

    wire [BUF_AW_TB-1:0]        frame_index_w;
    wire                        frame_found_w;
    wire [INDEX_WIDTH_TB-1:0]   peak_lag_w;
    wire [METRIC_WIDTH_TB-1:0]  peak_metric_w;
    wire [PHASE_WIDTH_TB-1:0]   frac_phase_w;
    wire                        frac_phase_valid_w;

    wire [31:0]  m_axis_tdata_w;
    wire         m_axis_tvalid_w;
    logic        m_axis_tready_d;
    wire         m_axis_tlast_w;

    frac_cfo_frame_corrector_top #(
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
        .THRESHOLD   (1),
        .LATENCY     (LATENCY_TB)
    ) dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_tdata    (s_axis_tdata_d),
        .s_axis_tvalid   (s_axis_tvalid_d),
        .s_axis_tready   (s_axis_tready_w),
        .s_axis_tlast    (s_axis_tlast_d),
        .start           (start_d),
        .done            (done_w),
        .busy            (busy_w),
        .frame_error     (frame_error_w),
        .threshold_in    (threshold_d),
        .window_len_in   (window_len_d),
        .hit_count_in    (hit_count_d),
        .frame_index     (frame_index_w),
        .frame_found     (frame_found_w),
        .peak_lag        (peak_lag_w),
        .peak_metric     (peak_metric_w),
        .frac_phase      (frac_phase_w),
        .frac_phase_valid(frac_phase_valid_w),
        .m_axis_tdata    (m_axis_tdata_w),
        .m_axis_tvalid   (m_axis_tvalid_w),
        .m_axis_tready   (m_axis_tready_d),
        .m_axis_tlast    (m_axis_tlast_w)
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

    task automatic chk_nonzero(input string nm, input int got);
        if (got !== 0) begin $display("[PASS] %s = %0d (nonzero)", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s is zero (expected nonzero)", nm); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Stream N samples; first_n beats use (I0,Q0), rest use (I1,Q1)
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
    // Capture m_axis output samples until tlast (or timeout)
    // -----------------------------------------------------------------------
    task automatic capture_m_axis(
        output logic [31:0] samples [],
        output int count,
        output int last_pos
    );
        count    = 0;
        last_pos = -1;
        samples  = new[0];
        for (int t = 0; t < TIMEOUT_CYC; t++) begin
            @(posedge aclk); #1;
            if (m_axis_tvalid_w && m_axis_tready_d) begin
                samples = new[count+1](samples);
                samples[count] = m_axis_tdata_w;
                if (m_axis_tlast_w) last_pos = count;
                count++;
                if (m_axis_tlast_w) return;
            end
        end
        $display("[FAIL] capture_m_axis: timeout waiting for tlast");
        fail_cnt++;
    endtask

    // -----------------------------------------------------------------------
    // Pulse start for 1 clock
    // -----------------------------------------------------------------------
    task automatic pulse_start;
        @(negedge aclk);
        start_d = 1'b1;
        @(posedge aclk); #1;
        @(negedge aclk);
        start_d = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Reset DUT; wait for reset NBA to propagate; clear fpv_seen
    // -----------------------------------------------------------------------
    task automatic do_reset;
        @(negedge aclk); aresetn = 1'b0;
        @(posedge aclk); #1;   // reset posedge: always block NB clears fpv_seen
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;   // first post-reset posedge: safe point to BA-clear
        fpv_seen = 1'b0; frac_cap = '0;
    endtask

    logic timed_out;
    logic [31:0] samples [];
    int count, last_pos;
    int fi_save, pl_save;

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn         = 1'b0;
        start_d         = 1'b0;
        s_axis_tdata_d  = '0;
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
        m_axis_tready_d = 1'b1;
        threshold_d     = ENERGY_WIDTH_TB'(1);
        window_len_d    = 7'd4;
        hit_count_d     = 4'd2;
        pass_cnt = 0;
        fail_cnt = 0;
        fpv_seen = 0;
        frac_cap = '0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ================================================================
        // T1: Reset state
        // ================================================================
        $display("\n--- T1: Reset ---");
        @(posedge aclk); #1;
        chk("T1 done=0",        done_w,        1'b0);
        chk("T1 busy=0",        busy_w,        1'b0);
        chk("T1 frame_error=0", frame_error_w, 1'b0);

        // ================================================================
        // T2: Happy path — 8 quiet + 100 signal.
        //   m_axis captured concurrently (results used in T3/T4).
        // ================================================================
        $display("\n--- T2: Happy path (8 quiet + 100 signal) ---");
        fork
            begin : start_proc
                pulse_start;
            end
            begin : stream_proc
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                // Fill slightly more than needed so buffer captures full frame
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join

        @(posedge aclk); #1;
        chk("T2 busy=1 after start", busy_w, 1'b1);

        // Wait for done and capture m_axis concurrently
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join

        if (!timed_out) begin
            chk    ("T2 done fires",           done_w,        1'b1);
            chk    ("T2 frame_found",           frame_found_w, 1'b1);
            chk    ("T2 frame_error=0",         frame_error_w, 1'b0);
            chk    ("T2 frac_phase_valid seen", fpv_seen,      1'b1);
            chk_int("T2 frac_phase=0",          $signed(frac_cap), 0);
            @(posedge aclk); #1;
            chk    ("T2 busy=0 after done",     busy_w, 1'b0);
        end

        fi_save = int'(frame_index_w);
        pl_save = int'(peak_lag_w);

        // ================================================================
        // T3: m_axis output count and tlast position
        // ================================================================
        $display("\n--- T3: m_axis count and tlast ---");
        chk_int("T3 m_axis sample count",    count,    TOTAL_TB);
        chk_int("T3 tlast on last sample",   last_pos, TOTAL_TB - 1);
        chk    ("T3 m_axis_tvalid fires",
                 (count >= 1) ? 1'b1 : 1'b0, 1'b1);

        // ================================================================
        // T4: m_axis sample values.
        //   slot_start = frame_index+peak_lag = 5+2 = 7.
        //   samples[0] = buf[7] = quiet (I=0) → I_out=0.
        //   samples[1] = buf[8] = signal (I=100) → I_out=99.
        //   samples[2] = buf[9] = signal → I_out=99.
        // ================================================================
        $display("\n--- T4: m_axis sample values (zero CFO, signal region) ---");
        if (count >= 2) begin
            chk_int("T4 samples[1] I=99", $signed(samples[1][15:0]),  99);
            chk_int("T4 samples[1] Q=0",  $signed(samples[1][31:16]),  0);
        end
        if (count >= 3) begin
            chk_int("T4 samples[2] I=99", $signed(samples[2][15:0]),  99);
            chk_int("T4 samples[2] Q=0",  $signed(samples[2][31:16]),  0);
        end
        // Verify most samples have I=99 (signal region)
        begin
            int n99 = 0;
            for (int k = 1; k < count; k++)  // skip k=0 (quiet boundary)
                if ($signed(samples[k][15:0]) == 99) n99++;
            chk("T4 most samples I=99", (n99 >= TOTAL_TB-2) ? 1'b1 : 1'b0, 1'b1);
        end

        // ================================================================
        // T5: Frame not found (threshold set impossibly high so frame_detector
        //   never finds a hit regardless of buffer contents from T2).
        //   iq_frame_buffer memory does NOT reset, so old signal data
        //   at unused addresses persists; max threshold is the safe approach.
        // ================================================================
        $display("\n--- T5: Frame not found (max threshold) ---");
        do_reset();
        threshold_d = '1;    // max 40-bit value → effective threshold impossibly high

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
        threshold_d = ENERGY_WIDTH_TB'(1);  // restore normal threshold

        if (!timed_out) begin
            chk("T5 done fires",             done_w,             1'b1);
            chk("T5 frame_found=0",          frame_found_w,      1'b0);
            chk("T5 frame_error=1",          frame_error_w,      1'b1);
            chk("T5 frac_phase_valid=0",     frac_phase_valid_w, 1'b0);
            @(posedge aclk); #1;
            chk("T5 busy=0 after done",      busy_w,             1'b0);
            chk("T5 m_axis idle",            m_axis_tvalid_w,    1'b0);
        end

        // ================================================================
        // T6: done pulse width exactly 1 clock
        // ================================================================
        $display("\n--- T6: done pulse width = 1 clock ---");
        do_reset();

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk("T6 done=1 at done cycle", done_w, 1'b1);
            @(posedge aclk); #1;
            chk("T6 done=0 next cycle",    done_w, 1'b0);
        end

        // ================================================================
        // T7: busy asserts at start, deasserts at done
        // ================================================================
        $display("\n--- T7: busy timeline ---");
        do_reset();
        @(posedge aclk); #1;
        chk("T7 busy=0 before start", busy_w, 1'b0);

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        @(posedge aclk); #1;
        chk("T7 busy=1 during run", busy_w, 1'b1);

        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk("T7 done=1 at transition", done_w, 1'b1);
            chk("T7 busy=0 at done",       busy_w, 1'b0);
        end

        // ================================================================
        // T8: frame_index stable after done (non-zero: first signal window)
        // ================================================================
        $display("\n--- T8: frame_index stable after done ---");
        do_reset();

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk_nonzero("T8 frame_index nonzero", int'(frame_index_w));
            fi_save = int'(frame_index_w);
            @(posedge aclk); #1;
            chk_int("T8 frame_index stable", int'(frame_index_w), fi_save);
        end

        // ================================================================
        // T9: peak_lag stable after done
        // ================================================================
        $display("\n--- T9: peak_lag stable after done ---");
        do_reset();

        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            pl_save = int'(peak_lag_w);
            @(posedge aclk); #1;
            chk_int("T9 peak_lag stable", int'(peak_lag_w), pl_save);
            chk    ("T9 frac_phase_valid seen", fpv_seen, 1'b1);
        end

        // ================================================================
        // T10: Back-to-back runs — module restarts cleanly
        // ================================================================
        $display("\n--- T10: Back-to-back runs ---");
        do_reset();

        // First run
        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        fi_save = int'(frame_index_w);

        // Second run immediately after done
        fork
            begin
                pulse_start;
            end
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk    ("T10 second done fires",      done_w,        1'b1);
            chk    ("T10 frame_found again",       frame_found_w, 1'b1);
            chk_int("T10 frame_index consistent",  int'(frame_index_w), fi_save);
            chk_int("T10 m_axis count = TOTAL_TB", count,         TOTAL_TB);
            chk_int("T10 tlast on last sample",    last_pos,      TOTAL_TB - 1);
        end

        // ================================================================
        // Summary
        // ================================================================
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
        #(TIMEOUT_CYC * CLK_HALF * 20);
        $display("[FAIL] Global watchdog timeout");
        $finish;
    end

endmodule
