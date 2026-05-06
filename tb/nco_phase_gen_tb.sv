`timescale 1ns/1ps

// nco_phase_gen_tb — 10 test groups, ~38 checks.
//
// Tests:
//   T1  Reset state
//   T2  step_word=0, phase stays 0; sin(0)≈0, cos(0)≈1
//   T3  Positive step_word increments phase_acc each enable cycle
//   T4  Negative step_word decrements phase_acc
//   T5  sincos_valid timing: not valid at T+LATENCY-1, valid at T+LATENCY
//   T6  enable=0 gaps hold phase_acc; sincos_valid=0 for gap cycles
//   T7  Natural wraparound
//   T8  phase_reset clears accumulator mid-run
//   T9  load_step latches step_word correctly
//   T10 Golden model sin/cos verification (4 samples, step_word=0x10000000)

module nco_phase_gen_tb;

    localparam int NW       = 32;   // NCO_PHASE_WIDTH
    localparam int CPW      = 16;   // CORDIC_PHASE_WIDTH
    localparam int RCW      = 16;   // ROTATOR_COEFF_WIDTH
    localparam int LAT      = 15;   // LATENCY
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
    logic              load_step_d;
    logic signed [31:0] step_word_d;
    logic              phase_reset_d;
    logic              enable_d;

    wire signed [RCW-1:0] sin_out;
    wire signed [RCW-1:0] cos_out;
    wire                  sincos_valid;
    wire           [NW-1:0] phase_acc_out;

    nco_phase_gen #(
        .NCO_PHASE_WIDTH    (NW),
        .CORDIC_PHASE_WIDTH (CPW),
        .ROTATOR_COEFF_WIDTH(RCW),
        .LATENCY            (LAT)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .load_step   (load_step_d),
        .step_word   (step_word_d),
        .phase_reset (phase_reset_d),
        .enable      (enable_d),
        .sin_out     (sin_out),
        .cos_out     (cos_out),
        .sincos_valid(sincos_valid),
        .phase_acc   (phase_acc_out)
    );

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
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
            begin $display("[PASS] %s = 0x%08X (%0d)",
                           nm, got, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%08X(%0d) exp=0x%08X(%0d)",
                           nm, got, $signed(got), exp, $signed(exp)); fail_cnt++; end
    endtask

    task automatic chk_coeff(input string nm,
                              input logic signed [RCW-1:0] got,
                              input logic signed [RCW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%04X (%0d)",
                           nm, got, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%04X(%0d) exp=0x%04X(%0d)",
                           nm, got, $signed(got), exp, $signed(exp)); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden sin/cos — mirrors nco_phase_gen behavioral model
    // -----------------------------------------------------------------------
    function automatic logic signed [RCW-1:0] gold_sin(input logic [NW-1:0] acc);
        real r_ph_g, r_sin_g;
        integer sin_int_g;
        r_ph_g    = $itor($signed(acc[NW-1:NW-CPW])) / ((1 << (CPW-1)) - 1.0)
                    * 3.14159265358979323846;
        r_sin_g   = $sin(r_ph_g);
        sin_int_g = $rtoi(r_sin_g * ((1 << (RCW-1)) - 1));
        return sin_int_g[RCW-1:0];
    endfunction

    function automatic logic signed [RCW-1:0] gold_cos(input logic [NW-1:0] acc);
        real r_ph_g, r_cos_g;
        integer cos_int_g;
        r_ph_g    = $itor($signed(acc[NW-1:NW-CPW])) / ((1 << (CPW-1)) - 1.0)
                    * 3.14159265358979323846;
        r_cos_g   = $cos(r_ph_g);
        cos_int_g = $rtoi(r_cos_g * ((1 << (RCW-1)) - 1));
        return cos_int_g[RCW-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Helper tasks
    // -----------------------------------------------------------------------

    // Load step_word and optionally clear phase
    task automatic setup(input logic [NW-1:0] sw, input logic do_reset);
        @(negedge aclk);
        step_word_d   = $signed(sw);
        load_step_d   = 1'b1;
        phase_reset_d = do_reset;
        @(posedge aclk); #1;
        load_step_d   = 1'b0;
        phase_reset_d = 1'b0;
    endtask

    // Module-level sin/cos capture
    logic signed [RCW-1:0] cap_sin [0:31];
    logic signed [RCW-1:0] cap_cos [0:31];
    int cap_cnt;

    // Capture the next n valid sincos outputs
    task automatic capture_n(input int n);
        int tout;
        cap_cnt = 0;
        tout    = 0;
        while (cap_cnt < n && tout < TIMEOUT) begin
            @(posedge aclk); #1;
            if (sincos_valid && cap_cnt < 32) begin
                cap_sin[cap_cnt] = sin_out;
                cap_cos[cap_cnt] = cos_out;
                cap_cnt++;
            end
            tout++;
        end
        if (tout >= TIMEOUT) $display("[FAIL] TIMEOUT in capture_n");
    endtask

    // -----------------------------------------------------------------------
    // Test temporaries
    // -----------------------------------------------------------------------
    int tctr_l;
    logic [NW-1:0] exp_acc;
    logic [NW-1:0] t10_phases [0:4];   // pre-accumulation phase for each sample
    int i10;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn       = 1'b0;
        load_step_d   = 1'b0;
        step_word_d   = 32'sd0;
        phase_reset_d = 1'b0;
        enable_d      = 1'b0;
        pass_cnt      = 0;
        fail_cnt      = 0;

        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;

        // ====================================================================
        // T1: Reset state
        // ====================================================================
        $display("\n--- T1: Reset state ---");
        chk_acc("T1 phase_acc=0", phase_acc_out, 32'd0);
        chk("T1 sincos_valid=0",  sincos_valid,   1'b0);

        // ====================================================================
        // T2: step_word=0, enable — phase_acc stays 0; sin≈0, cos≈1
        // ====================================================================
        $display("\n--- T2: step_word=0, phase constant ---");
        setup(32'd0, 1'b1);   // load 0, reset phase
        @(negedge aclk); enable_d = 1'b1;
        repeat(LAT+1) @(posedge aclk);
        #1; enable_d = 1'b0;
        chk_acc("T2 phase_acc still 0", phase_acc_out, 32'd0);
        // Check sin/cos for phase=0: sin(0)=0, cos(0)=1
        // Capture is already at sincos_valid=1 (LAT+1 clocks after first enable)
        chk("T2 sincos_valid=1", sincos_valid, 1'b1);
        chk_coeff("T2 sin(0)=0",    sin_out, gold_sin(32'd0));
        chk_coeff("T2 cos(0)≈1",    cos_out, gold_cos(32'd0));

        // ====================================================================
        // T3: Positive step_word increments phase_acc each enable cycle
        //   step_word = 32'h00010000 (= 1 in MSB region)
        // ====================================================================
        $display("\n--- T3: Positive step_word ---");
        setup(32'h0001_0000, 1'b1);   // step=0x10000, reset phase
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T3 step1", phase_acc_out, 32'h0001_0000);
        @(posedge aclk); #1;
        chk_acc("T3 step2", phase_acc_out, 32'h0002_0000);
        @(posedge aclk); #1;
        chk_acc("T3 step3", phase_acc_out, 32'h0003_0000);
        @(posedge aclk); #1;
        chk_acc("T3 step4", phase_acc_out, 32'h0004_0000);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T4: Negative step_word decrements phase_acc
        // ====================================================================
        $display("\n--- T4: Negative step_word ---");
        setup($unsigned(-32'sd65536), 1'b1);  // step = -0x10000
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T4 step1 = -0x10000", phase_acc_out, 32'hFFFF_0000);
        @(posedge aclk); #1;
        chk_acc("T4 step2 = -0x20000", phase_acc_out, 32'hFFFE_0000);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T5: sincos_valid timing — not valid at T+LATENCY-1, valid at T+LATENCY
        // ====================================================================
        $display("\n--- T5: sincos_valid timing ---");
        // Flush pipeline first (wait for any prior enables to clear)
        repeat(LAT+2) @(posedge aclk); #1;
        setup(32'h1000_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;            // posedge T: pipeline stage 0 loads
        enable_d = 1'b0;
        // After LAT-1 more posedges (T+1..T+LAT-1): sincos_valid should be 0
        repeat(LAT-1) @(posedge aclk); #1;
        chk("T5 not valid at T+LAT-1", sincos_valid, 1'b0);
        @(posedge aclk); #1;            // posedge T+LAT
        chk("T5 valid at T+LAT",       sincos_valid, 1'b1);

        // ====================================================================
        // T6: enable=0 gaps hold phase_acc; gap cycles produce no valid output
        // ====================================================================
        $display("\n--- T6: enable=0 gaps ---");
        setup(32'h0001_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;  exp_acc = 32'h0001_0000;
        chk_acc("T6 after 1st enable", phase_acc_out, exp_acc);
        // Disable for 3 clocks
        @(negedge aclk); enable_d = 1'b0;
        @(posedge aclk); #1;
        chk_acc("T6 gap1 hold", phase_acc_out, exp_acc);
        @(posedge aclk); #1;
        chk_acc("T6 gap2 hold", phase_acc_out, exp_acc);
        @(posedge aclk); #1;
        chk_acc("T6 gap3 hold", phase_acc_out, exp_acc);
        // Re-enable
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T6 after 2nd enable", phase_acc_out, 32'h0002_0000);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T7: Natural wraparound
        //   step_word = 0x8000_0001; two enables: 0→0x8000_0001→0x0000_0002
        // ====================================================================
        $display("\n--- T7: Wraparound ---");
        setup(32'h8000_0001, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T7 first",  phase_acc_out, 32'h8000_0001);
        @(posedge aclk); #1;
        chk_acc("T7 wrap",   phase_acc_out, 32'h0000_0002);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T8: phase_reset clears accumulator mid-run
        // ====================================================================
        $display("\n--- T8: phase_reset mid-run ---");
        setup(32'h0001_0000, 1'b1);
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); @(posedge aclk); @(posedge aclk); #1;
        // phase_acc = 3 * 0x10000 = 0x30000
        @(negedge aclk); enable_d = 1'b0; phase_reset_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T8 after reset", phase_acc_out, 32'd0);
        @(negedge aclk); phase_reset_d = 1'b0;
        // Re-enable: should start from 0
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T8 restart from 0", phase_acc_out, 32'h0001_0000);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T9: load_step latches step_word correctly
        //   Initially step_word_r=0 after reset.
        //   Enable once (phase stays 0), then load new step, enable again.
        // ====================================================================
        $display("\n--- T9: load_step ---");
        // Full reset
        @(negedge aclk); aresetn = 1'b0;
        @(posedge aclk); #1;
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;
        // step_word_r=0 after reset; enable once → phase_acc stays 0
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T9 no step loaded", phase_acc_out, 32'd0);
        @(negedge aclk); enable_d = 1'b0;
        // Now load step = 0x20000, enable once
        @(negedge aclk);
        step_word_d = 32'h0002_0000; load_step_d = 1'b1; phase_reset_d = 1'b1;
        @(posedge aclk); #1;
        load_step_d = 1'b0; phase_reset_d = 1'b0;
        @(negedge aclk); enable_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T9 after load", phase_acc_out, 32'h0002_0000);
        @(negedge aclk); enable_d = 1'b0;

        // ====================================================================
        // T10: Golden model sin/cos check
        //   step_word = 0x1000_0000; 4 enable pulses; compare each output.
        //   Sample k is presented to CORDIC at PRE-accumulation phase = k*step_word.
        // ====================================================================
        $display("\n--- T10: Golden model sin/cos ---");
        // Flush pipeline
        repeat(LAT+3) @(posedge aclk); #1;
        setup(32'h1000_0000, 1'b1);

        // Record pre-accumulation phase for each of 4 samples
        t10_phases[0] = 32'd0;
        t10_phases[1] = 32'h1000_0000;
        t10_phases[2] = 32'h2000_0000;
        t10_phases[3] = 32'h3000_0000;

        // Drive 4 consecutive enables
        for (i10 = 0; i10 < 4; i10 = i10 + 1) begin
            @(negedge aclk); enable_d = 1'b1;
        end
        @(negedge aclk); enable_d = 1'b0;

        // Capture 4 outputs
        capture_n(4);
        for (i10 = 0; i10 < 4; i10 = i10 + 1) begin
            chk_coeff($sformatf("T10 sin[%0d]", i10),
                      cap_sin[i10], gold_sin(t10_phases[i10]));
            chk_coeff($sformatf("T10 cos[%0d]", i10),
                      cap_cos[i10], gold_cos(t10_phases[i10]));
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
