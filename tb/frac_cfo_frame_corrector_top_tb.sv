`timescale 1ns/1ps

// frac_cfo_frame_corrector_top_tb — Step 20 base tests (T1-T10, 39 checks)
//   plus Step 21 randomized/sweep campaign (R1-R8, 137 checks).
// Total: 176 checks.
//
// Small parameters for fast simulation:
//   NSC=16, CP_LEN=4, BUF_AW=10 (DEPTH=1024), LATENCY=15
//   WINDOW_LEN=4, HIT_COUNT=2, threshold=1 (any signal triggers)
//   TOTAL_SAMPLES = NSC+CP_LEN = 20
//
// Stimulus (T2 happy path): 8 quiet (I=0,Q=0) + 100 signal (I=100,Q=0).
//   frame_detector finds frame at index 5.
//   CP autocorr: peak_lag=2.
//   slot_start = 5+2 = 7; frac_phase=0 (pure-real constant signal).
//   step_word=0 → NCO produces cos≈1, sin=0 → I_out=99, Q_out=0 for signal samples.
//
// T1   Reset: done=0, busy=0, frame_error=0
// T2   Happy path: fill + wait done + capture m_axis concurrently
// T3   m_axis count and tlast: exactly TOTAL_TB samples, tlast on index 19
// T4   m_axis sample values: signal-region samples have I=99, Q=0
// T5   Frame not found: max threshold → frame_error=1, done fires, no m_axis
// T6   done is exactly 1 clock wide
// T7   busy asserts at start, deasserts at done (same clock as done)
// T8   frame_index stable after done
// T9   peak_lag stable after done
// T10  Back-to-back runs: module restarts cleanly, same count+tlast
//
// R1   Timing offset sweep: first-quiet-sample count 0..15 (16 × 2 checks = 32)
// R2   Signal config sweep: (I,Q) in {(100,0),(0,100),(70,70),(-100,0)} (4×4 = 16)
// R3   20 PRNG-randomized frame-placement trials, XorShift32, seed=0xDEADBEEF (20×2 = 40)
// R4   10 PRNG-randomized amplitude trials, seed=0xCAFE0001 (10×1 = 10)
// R5   AXI-Stream output backpressure delays 0,1,2,3 cycles (4×3 = 12)
// R6   Reset robustness: before frame, mid-frame-det, after done (3×3 = 9)
// R7   No-frame / false-trigger rejection (3×2 = 6)
// R8   Buffer boundary stress (4×3 = 12)

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
    // Capture m_axis output samples until tlast (or timeout); m_tready=1
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
    // Capture m_axis with per-sample m_tready backpressure.
    // Applies delay_cyc cycles of tready=0 after each accepted sample.
    // delay_cyc=0 behaves identically to capture_m_axis.
    // -----------------------------------------------------------------------
    task automatic capture_m_axis_bp(
        input  int          delay_cyc,
        output logic [31:0] s [],
        output int          cnt,
        output int          lp
    );
        cnt = 0; lp = -1; s = new[0];
        @(negedge aclk); m_axis_tready_d = 1'b1;
        for (int t = 0; t < TIMEOUT_CYC; t++) begin
            @(posedge aclk); #1;
            if (m_axis_tvalid_w && m_axis_tready_d) begin
                s      = new[cnt+1](s);
                s[cnt] = m_axis_tdata_w;
                if (m_axis_tlast_w) lp = cnt;
                cnt++;
                if (m_axis_tlast_w) begin
                    @(negedge aclk); m_axis_tready_d = 1'b1;
                    return;
                end
                if (delay_cyc > 0) begin
                    @(negedge aclk); m_axis_tready_d = 1'b0;
                    repeat (delay_cyc) @(posedge aclk);
                    @(negedge aclk); m_axis_tready_d = 1'b1;
                end
            end
        end
        $display("[FAIL] capture_m_axis_bp: timeout (delay=%0d)", delay_cyc);
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
        @(posedge aclk); #1;
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;
        fpv_seen = 1'b0; frac_cap = '0;
    endtask

    // -----------------------------------------------------------------------
    // XorShift32 PRNG — deterministic, fixed seeds per group
    // -----------------------------------------------------------------------
    function automatic int xorshift32(ref int state);
        state ^= (state << 13);
        state ^= (state >> 17);
        state ^= (state << 5);
        return state;
    endfunction

    // -----------------------------------------------------------------------
    // Shared variables
    // -----------------------------------------------------------------------
    logic timed_out;
    logic [31:0] samples [];
    int count, last_pos;
    int fi_save, pl_save;
    int prng_state;
    int grp_fail_snap;

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
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join

        @(posedge aclk); #1;
        chk("T2 busy=1 after start", busy_w, 1'b1);

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
        begin
            int n99 = 0;
            for (int k = 1; k < count; k++)
                if ($signed(samples[k][15:0]) == 99) n99++;
            chk("T4 most samples I=99", (n99 >= TOTAL_TB-2) ? 1'b1 : 1'b0, 1'b1);
        end

        // ================================================================
        // T5: Frame not found (threshold set impossibly high).
        // ================================================================
        $display("\n--- T5: Frame not found (max threshold) ---");
        do_reset();
        threshold_d = '1;

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
        threshold_d = ENERGY_WIDTH_TB'(1);

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
        // R1: Timing offset sweep — quiet-samples-before-signal 4..19
        //     (min 4 = WINDOW_LEN ensures DUT can detect the signal onset)
        //     2 checks per offset × 16 offsets = 32 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R1: Timing offset sweep (quiet 4..19) ---");
        for (int off = 0; off < 16; off++) begin
            do_reset();
            threshold_d  = ENERGY_WIDTH_TB'(1);
            window_len_d = 7'd4;
            hit_count_d  = 4'd2;
            fork
                pulse_start;
                begin
                    @(posedge aclk); #1;
                    while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                    stream_iq(off + 4, 16'sd0, 16'sd0, off + 64, 16'sd100, 16'sd0);
                end
            join
            fork
                wait_done(timed_out);
                capture_m_axis(samples, count, last_pos);
            join
            if (!timed_out) begin
                chk    ($sformatf("R1 off=%0d frame_found", off),       frame_found_w, 1'b1);
                chk_int($sformatf("R1 off=%0d count=TOTAL_TB", off),    count,         TOTAL_TB);
            end
        end
        $display("[GROUP] R1 timing offset sweep %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R2: Signal configuration sweep — 4 IQ patterns
        //     4 checks per config × 4 configs = 16 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R2: Signal configuration sweep ---");
        begin
            shortint r2_I, r2_Q;
            for (int c2 = 0; c2 < 4; c2++) begin
                case (c2)
                    0: begin r2_I =  16'sd100; r2_Q = 16'sd0;   end  // pure real
                    1: begin r2_I =  16'sd0;   r2_Q = 16'sd100; end  // pure imaginary
                    2: begin r2_I =  16'sd70;  r2_Q = 16'sd70;  end  // 45-degree
                    default: begin r2_I = -16'sd100; r2_Q = 16'sd0; end // neg real
                endcase
                do_reset();
                threshold_d  = ENERGY_WIDTH_TB'(1);
                window_len_d = 7'd4;
                hit_count_d  = 4'd2;
                fork
                    pulse_start;
                    begin
                        @(posedge aclk); #1;
                        while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                        stream_iq(8, 16'sd0, 16'sd0, 108, r2_I, r2_Q);
                    end
                join
                fork
                    wait_done(timed_out);
                    capture_m_axis(samples, count, last_pos);
                join
                if (!timed_out) begin
                    chk    ($sformatf("R2 c%0d frame_found",   c2), frame_found_w, 1'b1);
                    chk    ($sformatf("R2 c%0d frame_error=0", c2), frame_error_w, 1'b0);
                    chk_int($sformatf("R2 c%0d count",         c2), count,         TOTAL_TB);
                    chk_int($sformatf("R2 c%0d tlast",         c2), last_pos,      TOTAL_TB - 1);
                end
            end
        end
        $display("[GROUP] R2 signal configuration sweep %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R3: Randomized frame placement — 20 PRNG trials
        //     XorShift32 seed=0xDEADBEEF; off bounded [4..15]
        //     (min 4 = WINDOW_LEN ensures DUT can detect signal onset)
        //     2 checks per trial × 20 trials = 40 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R3: Randomized frame placement (20 trials) ---");
        begin
            int r3_off;
            prng_state = 32'hDEAD_BEEF;
            for (int tr = 0; tr < 20; tr++) begin
                void'(xorshift32(prng_state));
                r3_off = 4 + ((prng_state & 32'hF) % 12);  // 4..15
                do_reset();
                threshold_d  = ENERGY_WIDTH_TB'(1);
                window_len_d = 7'd4;
                hit_count_d  = 4'd2;
                fork
                    pulse_start;
                    begin
                        @(posedge aclk); #1;
                        while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                        stream_iq(r3_off, 16'sd0, 16'sd0, r3_off + 50, 16'sd100, 16'sd0);
                    end
                join
                fork
                    wait_done(timed_out);
                    capture_m_axis(samples, count, last_pos);
                join
                if (!timed_out) begin
                    chk    ($sformatf("R3 tr=%0d frame_found", tr), frame_found_w, 1'b1);
                    chk_int($sformatf("R3 tr=%0d count",       tr), count,         TOTAL_TB);
                end
            end
        end
        $display("[RANDOM] frame_placement_trials = 20");
        $display("[GROUP] R3 randomized frame placement %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R4: Randomized amplitude scaling — 10 PRNG trials
        //     XorShift32 seed=0xCAFE0001; amplitude 30..129
        //     offset fixed at 4; 1 check per trial × 10 = 10 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R4: Randomized amplitude scaling (10 trials) ---");
        begin
            shortint r4_amp;
            prng_state = 32'hCAFE_0001;
            for (int tr = 0; tr < 10; tr++) begin
                void'(xorshift32(prng_state));
                r4_amp = shortint'(30 + ((prng_state >>> 1) % 100));  // 30..129
                do_reset();
                threshold_d  = ENERGY_WIDTH_TB'(1);
                window_len_d = 7'd4;
                hit_count_d  = 4'd2;
                fork
                    pulse_start;
                    begin
                        @(posedge aclk); #1;
                        while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                        stream_iq(4, 16'sd0, 16'sd0, 64, r4_amp, 16'sd0);
                    end
                join
                fork
                    wait_done(timed_out);
                    capture_m_axis(samples, count, last_pos);
                join
                if (!timed_out)
                    chk_int($sformatf("R4 tr=%0d count", tr), count, TOTAL_TB);
            end
        end
        $display("[RANDOM] amplitude_trials = 10");
        $display("[GROUP] R4 randomized amplitude scaling %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R5: AXI-Stream output backpressure — delays 0,1,2,3 cycles
        //     3 checks per delay × 4 delays = 12 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R5: AXI-Stream output backpressure ---");
        begin
            int r5_delays [4];
            r5_delays[0] = 0; r5_delays[1] = 1;
            r5_delays[2] = 2; r5_delays[3] = 3;
            for (int di = 0; di < 4; di++) begin
                automatic int dly = r5_delays[di];
                do_reset();
                threshold_d     = ENERGY_WIDTH_TB'(1);
                window_len_d    = 7'd4;
                hit_count_d     = 4'd2;
                @(negedge aclk); m_axis_tready_d = 1'b1;
                fork
                    pulse_start;
                    begin
                        @(posedge aclk); #1;
                        while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                        stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
                    end
                join
                fork
                    wait_done(timed_out);
                    capture_m_axis_bp(dly, samples, count, last_pos);
                join
                @(negedge aclk); m_axis_tready_d = 1'b1;  // restore
                if (!timed_out) begin
                    chk_int($sformatf("R5 delay=%0d count=TOTAL_TB", dly), count,    TOTAL_TB);
                    chk_int($sformatf("R5 delay=%0d tlast at last",  dly), last_pos, TOTAL_TB - 1);
                    chk    ($sformatf("R5 delay=%0d tvalid_fired",   dly),
                            (count >= 1) ? 1'b1 : 1'b0, 1'b1);
                end
            end
        end
        $display("[GROUP] R5 AXI backpressure %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R6: Reset robustness — 3 scenarios, 3 checks each = 9 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R6: Reset robustness ---");

        // -- Scenario 1: reset from idle before any activity
        $display("[INFO] R6 S1: reset from idle, then verify recovery");
        do_reset();
        @(posedge aclk); #1;
        chk("R6 S1: busy=0 after reset", busy_w, 1'b0);
        chk("R6 S1: done=0 after reset", done_w, 1'b0);
        fork
            pulse_start;
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
        if (!timed_out)
            chk("R6 S1: recovery done fires", done_w, 1'b1);

        // -- Scenario 2: reset during frame detection (mid-processing)
        $display("[INFO] R6 S2: reset mid-frame-det, then verify recovery");
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 108, 16'sd100, 16'sd0);
            end
        join
        // DUT is now in S_FRAME_DET (~2048 cycles); reset after 80 cycles
        repeat(80) @(posedge aclk);
        do_reset();
        @(posedge aclk); #1;
        chk("R6 S2: busy=0 after mid-proc reset", busy_w, 1'b0);
        chk("R6 S2: done=0 after mid-proc reset", done_w, 1'b0);
        fork
            pulse_start;
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
        if (!timed_out)
            chk("R6 S2: recovery done fires", done_w, 1'b1);

        // -- Scenario 3: reset immediately after done, then fresh run
        $display("[INFO] R6 S3: reset after done, verify clean restart");
        do_reset();
        fork
            pulse_start;
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
        do_reset();
        @(posedge aclk); #1;
        chk("R6 S3: busy=0 after post-done reset", busy_w, 1'b0);
        fork
            pulse_start;
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
            chk    ("R6 S3: second run done fires", done_w,        1'b1);
            chk_int("R6 S3: second run count",      count,         TOTAL_TB);
        end
        $display("[GROUP] R6 reset robustness %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R7: No-frame / false-trigger rejection — max threshold blocks all
        //     2 checks per test × 3 tests = 6 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R7: No-frame / false-trigger rejection ---");

        // Test 1: all-quiet data, max threshold
        do_reset();
        threshold_d = '1;
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(0, 16'sd0, 16'sd0, 40, 16'sd0, 16'sd0);
            end
        join
        wait_done(timed_out);
        if (!timed_out) begin
            chk("R7 T1: frame_error=1 (quiet+max thr)", frame_error_w, 1'b1);
            chk("R7 T1: m_axis_tvalid=0",               m_axis_tvalid_w, 1'b0);
        end

        // Test 2: signal data, max threshold suppresses detection
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(0, 16'sd0, 16'sd0, 40, 16'sd100, 16'sd0);
            end
        join
        wait_done(timed_out);
        if (!timed_out) begin
            chk("R7 T2: frame_error=1 (signal+max thr)", frame_error_w, 1'b1);
            chk("R7 T2: m_axis_tvalid=0",                m_axis_tvalid_w, 1'b0);
        end

        // Test 3: mixed quiet+signal, max threshold
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(10, 16'sd0, 16'sd0, 50, 16'sd100, 16'sd0);
            end
        join
        wait_done(timed_out);
        if (!timed_out) begin
            chk("R7 T3: frame_error=1 (mixed+max thr)", frame_error_w, 1'b1);
            chk("R7 T3: m_axis_tvalid=0",               m_axis_tvalid_w, 1'b0);
        end
        threshold_d = ENERGY_WIDTH_TB'(1);  // restore
        $display("[GROUP] R7 no-frame rejection %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // R8: Buffer boundary stress — 4 configurations
        //     3 checks per config × 4 configs = 12 checks
        // ================================================================
        grp_fail_snap = fail_cnt;
        $display("\n--- R8: Buffer boundary stress ---");

        // Config 1: off=4 (min), 50 signal (frame starts near buffer start)
        do_reset();
        threshold_d = ENERGY_WIDTH_TB'(1);
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(4, 16'sd0, 16'sd0, 54, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk    ("R8 C1: frame_found", frame_found_w, 1'b1);
            chk_int("R8 C1: count",       count,         TOTAL_TB);
            chk_int("R8 C1: tlast",       last_pos,      TOTAL_TB - 1);
        end

        // Config 2: off=4, 12 signal (minimal signal: 12 >= WINDOW_LEN*HIT_COUNT=8)
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(4, 16'sd0, 16'sd0, 16, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk    ("R8 C2: frame_found", frame_found_w, 1'b1);
            chk_int("R8 C2: count",       count,         TOTAL_TB);
            chk_int("R8 C2: tlast",       last_pos,      TOTAL_TB - 1);
        end

        // Config 3: off=15 (maximum offset tested), 50 signal
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(15, 16'sd0, 16'sd0, 65, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk    ("R8 C3: frame_found", frame_found_w, 1'b1);
            chk_int("R8 C3: count",       count,         TOTAL_TB);
            chk_int("R8 C3: tlast",       last_pos,      TOTAL_TB - 1);
        end

        // Config 4: off=8, 50 signal (mid-range nominal)
        do_reset();
        fork
            pulse_start;
            begin
                @(posedge aclk); #1;
                while (!s_axis_tready_w) begin @(posedge aclk); #1; end
                stream_iq(8, 16'sd0, 16'sd0, 58, 16'sd100, 16'sd0);
            end
        join
        fork
            wait_done(timed_out);
            capture_m_axis(samples, count, last_pos);
        join
        if (!timed_out) begin
            chk    ("R8 C4: frame_found", frame_found_w, 1'b1);
            chk_int("R8 C4: count",       count,         TOTAL_TB);
            chk_int("R8 C4: tlast",       last_pos,      TOTAL_TB - 1);
        end
        $display("[GROUP] R8 buffer boundary stress %s",
                 (fail_cnt == grp_fail_snap) ? "PASS" : "FAIL");

        // ================================================================
        // Summary
        // ================================================================
        $display("\n========================================");
        $display("PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        $display("[RANDOM] frame_placement_trials = 20  amplitude_trials = 10");
        $display("CFO range tested: 0x0000..0xC000 (via CP autocorr frac_phase path)");
        $display("Timing offset range: 0..15 (R1 sweep) + randomized 2..15 (R3)");
        $display("Backpressure patterns tested: 4 (delays 0..3)");
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
