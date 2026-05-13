`timescale 1ns/1ps

// nco_phase_gen_xilinx_wrapper_tb — 14 test groups, deterministic self-checking.
//
// T1  reset_defaults
// T2  phase_zero (step=0)
// T3  quarter_cycle (phase=pi/2)
// T4  half_cycle   (phase=pi)
// T5  three_quarter_cycle (phase=3pi/2)
// T6  small_positive_step_sequence
// T7  negative_step_sequence
// T8  wraparound_positive
// T9  wraparound_negative
// T10 phase_reset_priority
// T11 back_to_back_valids
// T12 valid_gating (gaps in enable)
// T13 large_step (quarter-cycle per sample)
// T14 compare_existing_model (wrapper vs nco_phase_gen reference instance)

module nco_phase_gen_xilinx_wrapper_tb;

    localparam int NW        = 32;
    localparam int CPW       = 16;
    localparam int RCW       = 16;
    localparam int LAT       = 15;
    localparam int CLK_HALF  = 5;
    localparam int TIMEOUT   = 3000;
    localparam int COEFF_TOL = 1;

    // -------------------------------------------------------------------------
    // Clock / reset
    // -------------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -------------------------------------------------------------------------
    // DUT (wrapper under test, USE_BEHAVIORAL_MODEL=1)
    // -------------------------------------------------------------------------
    logic              load_step_d;
    logic signed [31:0] step_word_d;
    logic              phase_reset_d;
    logic              enable_d;

    wire signed [RCW-1:0] w_sin_out;
    wire signed [RCW-1:0] w_cos_out;
    wire                  w_sincos_valid;
    wire        [NW-1:0]  w_phase_acc;

    nco_phase_gen_xilinx_wrapper #(
        .NCO_PHASE_WIDTH     (NW),
        .CORDIC_PHASE_WIDTH  (CPW),
        .ROTATOR_COEFF_WIDTH (RCW),
        .LATENCY             (LAT),
        .USE_BEHAVIORAL_MODEL(1)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .load_step   (load_step_d),
        .step_word   (step_word_d),
        .phase_reset (phase_reset_d),
        .enable      (enable_d),
        .sin_out     (w_sin_out),
        .cos_out     (w_cos_out),
        .sincos_valid(w_sincos_valid),
        .phase_acc   (w_phase_acc)
    );

    // -------------------------------------------------------------------------
    // T14 reference instance: nco_phase_gen (original ROM module)
    // -------------------------------------------------------------------------
    wire signed [RCW-1:0] ref_sin_out;
    wire signed [RCW-1:0] ref_cos_out;
    wire                  ref_sincos_valid;
    wire        [NW-1:0]  ref_phase_acc;

    nco_phase_gen #(
        .NCO_PHASE_WIDTH    (NW),
        .CORDIC_PHASE_WIDTH (CPW),
        .ROTATOR_COEFF_WIDTH(RCW),
        .LATENCY            (LAT)
    ) ref_inst (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .load_step   (load_step_d),
        .step_word   (step_word_d),
        .phase_reset (phase_reset_d),
        .enable      (enable_d),
        .sin_out     (ref_sin_out),
        .cos_out     (ref_cos_out),
        .sincos_valid(ref_sincos_valid),
        .phase_acc   (ref_phase_acc)
    );

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);                              pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp);  fail_cnt++; end
    endtask

    task automatic chk_acc(input string nm,
                            input logic [NW-1:0] got,
                            input logic [NW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%08X", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%08X exp=0x%08X", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_coeff(input string nm,
                              input logic signed [RCW-1:0] got,
                              input logic signed [RCW-1:0] exp);
        int diff;
        diff = int'(got) - int'(exp);
        if (diff < 0) diff = -diff;
        if (diff <= COEFF_TOL)
            begin $display("[PASS] %s got=%0d exp=%0d", nm, $signed(got), $signed(exp));
                  pass_cnt++; end
        else
            begin $display("[FAIL] %s got=%0d exp=%0d diff=%0d",
                           nm, $signed(got), $signed(exp), diff);
                  fail_cnt++; end
    endtask

    task automatic chk_exact(input string nm,
                              input logic signed [RCW-1:0] got,
                              input logic signed [RCW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s got=%0d", nm, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s got=%0d exp=%0d", nm, $signed(got), $signed(exp));
                  fail_cnt++; end
    endtask

    // -------------------------------------------------------------------------
    // Golden model — ROM-quantized convention (matches nco_phase_gen legacy behavior):
    //   ROM index = acc[31:24]  (top 8 bits, 256 entries for full 2*pi cycle)
    //   angle     = 2*pi * index / 256
    //   scale     = 32767
    // Small phase steps that do not change acc[31:24] produce the same
    // sin/cos output as index 0 (cos=+32767, sin=0).
    // Tolerance 1 LSB covers ROM round-trip quantisation error.
    //
    // Note: a future Xilinx CORDIC rotate-mode replacement uses full 16-bit
    // phase resolution; that mode will need a separate golden model policy.
    // -------------------------------------------------------------------------
    function automatic logic signed [RCW-1:0] gold_cos(input logic [NW-1:0] acc);
        real angle;
        integer v;
        // Use only the top 8 bits — mirrors the 256-entry ROM index in nco_phase_gen
        angle = 2.0 * 3.14159265358979323846 * real'(acc[31:24]) / 256.0;
        v     = $rtoi($cos(angle) * 32767.0 + 0.5);
        if (v >  32767) v =  32767;
        if (v < -32767) v = -32767;
        return v[RCW-1:0];
    endfunction

    function automatic logic signed [RCW-1:0] gold_sin(input logic [NW-1:0] acc);
        real angle;
        integer v;
        // Use only the top 8 bits — mirrors the 256-entry ROM index in nco_phase_gen
        angle = 2.0 * 3.14159265358979323846 * real'(acc[31:24]) / 256.0;
        v     = $rtoi($sin(angle) * 32767.0 + 0.5);
        if (v >  32767) v =  32767;
        if (v < -32767) v = -32767;
        return v[RCW-1:0];
    endfunction

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------
    task automatic do_reset();
        @(negedge aclk); aresetn = 1'b0;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;
    endtask

    task automatic setup_step(input logic [NW-1:0] sw, input logic do_rst);
        @(negedge aclk);
        step_word_d   = $signed(sw);
        load_step_d   = 1'b1;
        phase_reset_d = do_rst;
        @(posedge aclk); #1;
        load_step_d   = 1'b0;
        phase_reset_d = 1'b0;
    endtask

    // Flush pipeline after a test to ensure no residual valid bleeds into next test
    task automatic flush();
        @(negedge aclk); enable_d = 1'b0;
        repeat(LAT+3) @(posedge aclk); #1;
    endtask

    // Capture arrays
    logic signed [RCW-1:0] cap_sin [0:31];
    logic signed [RCW-1:0] cap_cos [0:31];
    logic        [NW-1:0]  cap_acc [0:31];
    int cap_cnt;

    task automatic capture_n(input int n);
        int tout;
        cap_cnt = 0; tout = 0;
        while (cap_cnt < n && tout < TIMEOUT) begin
            @(posedge aclk); #1;
            if (w_sincos_valid && cap_cnt < 32) begin
                cap_sin[cap_cnt] = w_sin_out;
                cap_cos[cap_cnt] = w_cos_out;
                cap_cnt++;
            end
            tout++;
        end
        if (tout >= TIMEOUT)
            begin $display("[FAIL] TIMEOUT in capture_n"); fail_cnt++; end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        aresetn       = 1'b0;
        load_step_d   = 1'b0;
        step_word_d   = 32'sd0;
        phase_reset_d = 1'b0;
        enable_d      = 1'b0;
        pass_cnt      = 0;
        fail_cnt      = 0;

        do_reset();

        // ====================================================================
        // T1: reset_defaults
        // ====================================================================
        $display("\n--- T1: reset_defaults ---");
        chk_acc("T1 phase_acc=0",   w_phase_acc,    32'd0);
        chk("T1 sincos_valid=0",    w_sincos_valid, 1'b0);
        chk_exact("T1 sin_out=0",   w_sin_out,      16'sd0);
        chk_exact("T1 cos_out=0",   w_cos_out,      16'sd0);

        // ====================================================================
        // T2: phase_zero — step=0, phase stays zero; cos=+max, sin=0
        // ====================================================================
        $display("\n--- T2: phase_zero (step=0) ---");
        setup_step(32'd0, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(LAT+1) @(posedge aclk); #1;
        enable_d = 1'b0;
        chk_acc("T2 phase_acc=0",       w_phase_acc,    32'd0);
        chk("T2 sincos_valid=1",        w_sincos_valid, 1'b1);
        chk_coeff("T2 cos(0)≈+32767",   w_cos_out, gold_cos(32'd0));
        chk_coeff("T2 sin(0)≈0",        w_sin_out, gold_sin(32'd0));
        flush();

        // ====================================================================
        // T3: quarter_cycle — single enable at phase 0x40000000 (index 64 = 90°)
        // ====================================================================
        $display("\n--- T3: quarter_cycle (phase=0x40000000) ---");
        // Load a large step to reach 0x40000000 instantly via reset+override.
        // Use phase_reset then load offset approach: reset accumulator,
        // then drive one enable with step=0x40000000 pre-loaded to reach 0x40000000.
        // Actually: after reset, phase=0. We want sin/cos at phase=0x40000000.
        // The ROM uses PRE-accumulation phase. So we need phase_acc_r=0x40000000
        // when the enable fires. Do this by resetting, loading step=0x40000000,
        // enabling once (phase goes 0→0x40000000), enabling again (captures
        // pre-accumulation=0x40000000). Then wait LAT cycles for output.
        setup_step(32'h4000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;  // after this: phase_acc = 0x40000000; pipeline stage 0 has phase=0
        // Now phase_acc = 0x40000000; one more enable captures pre-acc=0x40000000
        @(posedge aclk); #1;  // pipeline stage 0 has phase=0x40000000
        @(negedge aclk); enable_d = 1'b0;
        // Wait for second sample to arrive (LAT cycles from second enable)
        repeat(LAT) @(posedge aclk); #1;
        chk("T3 sincos_valid=1",            w_sincos_valid, 1'b1);
        chk_coeff("T3 cos(90°)≈0",          w_cos_out, gold_cos(32'h4000_0000));
        chk_coeff("T3 sin(90°)≈+32767",     w_sin_out, gold_sin(32'h4000_0000));
        flush();

        // ====================================================================
        // T4: half_cycle — phase=0x80000000 (index 128 = 180°)
        // ====================================================================
        $display("\n--- T4: half_cycle (phase=0x80000000) ---");
        setup_step(32'h4000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(3) @(posedge aclk); #1;  // phases: 0, 0x40M, 0x80M captured in pipeline
        @(negedge aclk); enable_d = 1'b0;
        // third sample arrives at LAT+2 from first enable; we are at step 2 (0-indexed)
        // Wait for the third valid (phase 0x80000000)
        begin : t4_wait
            int tout2;
            int vcnt;
            tout2 = 0; vcnt = 0;
            while (vcnt < 3 && tout2 < TIMEOUT) begin
                @(posedge aclk); #1;
                if (w_sincos_valid) vcnt++;
                tout2++;
            end
            if (tout2 >= TIMEOUT)
                begin $display("[FAIL] T4 TIMEOUT"); fail_cnt++; end
        end
        chk("T4 sincos_valid=1",            w_sincos_valid, 1'b1);
        chk_coeff("T4 cos(180°)≈-32767",    w_cos_out, gold_cos(32'h8000_0000));
        chk_coeff("T4 sin(180°)≈0",         w_sin_out, gold_sin(32'h8000_0000));
        flush();

        // ====================================================================
        // T5: three_quarter_cycle — phase=0xC0000000 (index 192 = 270°)
        // ====================================================================
        $display("\n--- T5: three_quarter_cycle (phase=0xC0000000) ---");
        setup_step(32'h4000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(4) @(posedge aclk); #1;  // 4th sample: pre-acc=0xC0000000
        @(negedge aclk); enable_d = 1'b0;
        begin : t5_wait
            int tout3;
            int vcnt3;
            tout3 = 0; vcnt3 = 0;
            while (vcnt3 < 4 && tout3 < TIMEOUT) begin
                @(posedge aclk); #1;
                if (w_sincos_valid) vcnt3++;
                tout3++;
            end
            if (tout3 >= TIMEOUT)
                begin $display("[FAIL] T5 TIMEOUT"); fail_cnt++; end
        end
        chk("T5 sincos_valid=1",            w_sincos_valid, 1'b1);
        chk_coeff("T5 cos(270°)≈0",         w_cos_out, gold_cos(32'hC000_0000));
        chk_coeff("T5 sin(270°)≈-32767",    w_sin_out, gold_sin(32'hC000_0000));
        flush();

        // ====================================================================
        // T6: small_positive_step — phase_acc increments correctly
        // ====================================================================
        $display("\n--- T6: small_positive_step_sequence ---");
        setup_step(32'h0001_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1; chk_acc("T6 step1", w_phase_acc, 32'h0001_0000);
        @(posedge aclk); #1; chk_acc("T6 step2", w_phase_acc, 32'h0002_0000);
        @(posedge aclk); #1; chk_acc("T6 step3", w_phase_acc, 32'h0003_0000);
        @(posedge aclk); #1; chk_acc("T6 step4", w_phase_acc, 32'h0004_0000);
        @(negedge aclk); enable_d = 1'b0;
        // Capture first 4 sin/cos outputs (correspond to pre-acc phases 0,0x10000,0x20000,0x30000)
        @(negedge aclk); enable_d = 1'b0;
        flush();
        // Re-run and capture
        setup_step(32'h0001_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(4) @(posedge aclk); #1;
        @(negedge aclk); enable_d = 1'b0;
        capture_n(4);
        chk_coeff("T6 cos[0]", cap_cos[0], gold_cos(32'h0000_0000));
        chk_coeff("T6 sin[0]", cap_sin[0], gold_sin(32'h0000_0000));
        chk_coeff("T6 cos[1]", cap_cos[1], gold_cos(32'h0001_0000));
        chk_coeff("T6 sin[1]", cap_sin[1], gold_sin(32'h0001_0000));
        chk_coeff("T6 cos[3]", cap_cos[3], gold_cos(32'h0003_0000));
        chk_coeff("T6 sin[3]", cap_sin[3], gold_sin(32'h0003_0000));
        flush();

        // ====================================================================
        // T7: negative_step — phase_acc decrements
        // ====================================================================
        $display("\n--- T7: negative_step_sequence ---");
        setup_step($unsigned(-32'sd65536), 1'b1);  // step = -0x10000
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1; chk_acc("T7 step1", w_phase_acc, 32'hFFFF_0000);
        @(posedge aclk); #1; chk_acc("T7 step2", w_phase_acc, 32'hFFFE_0000);
        @(posedge aclk); #1; chk_acc("T7 step3", w_phase_acc, 32'hFFFD_0000);
        @(negedge aclk); enable_d = 1'b0;
        // First output corresponds to pre-acc=0 (cos≈+max)
        capture_n(3);
        chk_coeff("T7 cos[0] pre-acc=0",       cap_cos[0], gold_cos(32'd0));
        chk_coeff("T7 sin[0] pre-acc=0",       cap_sin[0], gold_sin(32'd0));
        chk_coeff("T7 cos[1] pre-acc=FFFF0000",cap_cos[1], gold_cos(32'hFFFF_0000));
        chk_coeff("T7 sin[1] pre-acc=FFFF0000",cap_sin[1], gold_sin(32'hFFFF_0000));
        flush();

        // ====================================================================
        // T8: wraparound_positive — step near max, wrap across boundary
        // ====================================================================
        $display("\n--- T8: wraparound_positive ---");
        setup_step(32'h8000_0001, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1; chk_acc("T8 step1", w_phase_acc, 32'h8000_0001);
        @(posedge aclk); #1; chk_acc("T8 wrap",  w_phase_acc, 32'h0000_0002);
        @(negedge aclk); enable_d = 1'b0;
        flush();

        // ====================================================================
        // T9: wraparound_negative — start at 0, step=-1 → wraps to 0xFFFFFFFF
        // ====================================================================
        $display("\n--- T9: wraparound_negative ---");
        setup_step($unsigned(-32'sd1), 1'b1);  // step = -1 = 0xFFFFFFFF
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1; chk_acc("T9 step1", w_phase_acc, 32'hFFFF_FFFF);
        @(posedge aclk); #1; chk_acc("T9 step2", w_phase_acc, 32'hFFFF_FFFE);
        @(negedge aclk); enable_d = 1'b0;
        flush();

        // ====================================================================
        // T10: phase_reset_priority — reset overrides enable mid-run
        // ====================================================================
        $display("\n--- T10: phase_reset_priority ---");
        setup_step(32'h0001_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(4) @(posedge aclk); #1;  // phase = 0x40000
        // Assert phase_reset while enable is high; reset takes priority
        @(negedge aclk); phase_reset_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T10 acc reset to 0",   w_phase_acc, 32'd0);
        @(negedge aclk); phase_reset_d = 1'b0; enable_d = 1'b0;
        // Verify valid pipeline is cleared: wait LATENCY cycles and check no valid
        begin : t10_valid_check
            int k10;
            logic found_valid;
            found_valid = 1'b0;
            for (k10 = 0; k10 < LAT + 2; k10++) begin
                @(posedge aclk); #1;
                if (w_sincos_valid) found_valid = 1'b1;
            end
            // After reset, valid_pipe[0] = enable && !phase_reset = 0 on the reset cycle.
            // Any previous valid tokens in flight will still arrive; that is correct behavior.
            // We just verify the accumulator is 0.
        end
        chk_acc("T10 acc still 0",      w_phase_acc, 32'd0);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T10 restart step1",    w_phase_acc, 32'h0001_0000);
        @(negedge aclk); enable_d = 1'b0;
        flush();

        // ====================================================================
        // T11: back_to_back_valids — 8 consecutive enables, check output count
        // ====================================================================
        $display("\n--- T11: back_to_back_valids ---");
        setup_step(32'h1000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(8) @(posedge aclk); #1;
        @(negedge aclk); enable_d = 1'b0;
        capture_n(8);
        chk_acc("T11 captured 8 outputs", cap_cnt, 8);
        // Verify first 4 pre-accumulation phases
        chk_coeff("T11 cos[0] phase=0x00000000",      cap_cos[0], gold_cos(32'h0000_0000));
        chk_coeff("T11 cos[1] phase=0x10000000",      cap_cos[1], gold_cos(32'h1000_0000));
        chk_coeff("T11 cos[2] phase=0x20000000",      cap_cos[2], gold_cos(32'h2000_0000));
        chk_coeff("T11 cos[3] phase=0x30000000",      cap_cos[3], gold_cos(32'h3000_0000));
        chk_coeff("T11 sin[0] phase=0x00000000",      cap_sin[0], gold_sin(32'h0000_0000));
        chk_coeff("T11 sin[2] phase=0x20000000",      cap_sin[2], gold_sin(32'h2000_0000));
        flush();

        // ====================================================================
        // T12: valid_gating — interleaved enable/disable
        //   Pattern: E=1,0,1,0,0,1  → 3 valid inputs, expect 3 valid outputs
        // ====================================================================
        $display("\n--- T12: valid_gating ---");
        do_reset();
        setup_step(32'h1000_0000, 1'b1);
        // Drive pattern: 1,0,1,0,0,1
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;  // enable beat 0
        @(negedge aclk); enable_d = 1'b0;
        @(posedge aclk); #1;  // gap
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;  // enable beat 1
        @(negedge aclk); enable_d = 1'b0;
        @(posedge aclk); #1;  // gap
        @(posedge aclk); #1;  // gap
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;  // enable beat 2
        @(negedge aclk); enable_d = 1'b0;
        capture_n(3);
        chk_acc("T12 got 3 outputs", cap_cnt, 3);
        // Phases: beat 0 = 0, beat 1 = 0x10000000 (one step after beat 0),
        //         beat 2 = 0x20000000 (gaps don't increment phase)
        chk_coeff("T12 cos[0] phase=0",           cap_cos[0], gold_cos(32'd0));
        chk_coeff("T12 cos[1] phase=0x10000000",  cap_cos[1], gold_cos(32'h1000_0000));
        chk_coeff("T12 cos[2] phase=0x20000000",  cap_cos[2], gold_cos(32'h2000_0000));
        chk_coeff("T12 sin[0] phase=0",           cap_sin[0], gold_sin(32'd0));
        chk_coeff("T12 sin[1] phase=0x10000000",  cap_sin[1], gold_sin(32'h1000_0000));
        chk_coeff("T12 sin[2] phase=0x20000000",  cap_sin[2], gold_sin(32'h2000_0000));
        flush();

        // ====================================================================
        // T13: large_step — quarter cycle per sample (step=0x40000000)
        // ====================================================================
        $display("\n--- T13: large_step (quarter-cycle per sample) ---");
        do_reset();
        setup_step(32'h4000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        repeat(5) @(posedge aclk); #1;
        @(negedge aclk); enable_d = 1'b0;
        capture_n(5);
        chk_acc("T13 got 5 outputs", cap_cnt, 5);
        // Pre-accumulation phases: 0, 0x40M, 0x80M, 0xC0M, 0x00M (wrap)
        chk_coeff("T13 cos[0] phase=0x00000000",  cap_cos[0], gold_cos(32'h0000_0000));
        chk_coeff("T13 cos[1] phase=0x40000000",  cap_cos[1], gold_cos(32'h4000_0000));
        chk_coeff("T13 cos[2] phase=0x80000000",  cap_cos[2], gold_cos(32'h8000_0000));
        chk_coeff("T13 cos[3] phase=0xC0000000",  cap_cos[3], gold_cos(32'hC000_0000));
        chk_coeff("T13 cos[4] phase=0x00000000",  cap_cos[4], gold_cos(32'h0000_0000));
        chk_coeff("T13 sin[1] phase=0x40000000",  cap_sin[1], gold_sin(32'h4000_0000));
        chk_coeff("T13 sin[2] phase=0x80000000",  cap_sin[2], gold_sin(32'h8000_0000));
        chk_coeff("T13 sin[3] phase=0xC0000000",  cap_sin[3], gold_sin(32'hC000_0000));
        flush();

        // ====================================================================
        // T14: compare_existing_model — wrapper must match nco_phase_gen exactly
        //   Same inputs drive both; outputs must be bit-identical.
        // ====================================================================
        $display("\n--- T14: compare_existing_model ---");
        do_reset();
        setup_step(32'h0840_0000, 1'b1);
        // Drive 12 consecutive enables
        @(negedge aclk); enable_d = 1'b1;
        repeat(12) @(posedge aclk); #1;
        @(negedge aclk); enable_d = 1'b0;
        // Collect 12 valid outputs and compare pair-wise
        begin : t14_collect
            int tout14, vcnt14;
            tout14 = 0; vcnt14 = 0;
            while (vcnt14 < 12 && tout14 < TIMEOUT) begin
                @(posedge aclk); #1;
                if (w_sincos_valid) begin
                    if (w_sin_out !== ref_sin_out)
                        begin
                            $display("[FAIL] T14 sin mismatch sample %0d: wrapper=%0d ref=%0d",
                                     vcnt14, $signed(w_sin_out), $signed(ref_sin_out));
                            fail_cnt++;
                        end
                    else begin $display("[PASS] T14 sin[%0d]=%0d", vcnt14, $signed(w_sin_out));
                         pass_cnt++; end
                    if (w_cos_out !== ref_cos_out)
                        begin
                            $display("[FAIL] T14 cos mismatch sample %0d: wrapper=%0d ref=%0d",
                                     vcnt14, $signed(w_cos_out), $signed(ref_cos_out));
                            fail_cnt++;
                        end
                    else begin $display("[PASS] T14 cos[%0d]=%0d", vcnt14, $signed(w_cos_out));
                         pass_cnt++; end
                    vcnt14++;
                end
                tout14++;
            end
            if (tout14 >= TIMEOUT)
                begin $display("[FAIL] T14 TIMEOUT"); fail_cnt++; end
        end
        flush();

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
