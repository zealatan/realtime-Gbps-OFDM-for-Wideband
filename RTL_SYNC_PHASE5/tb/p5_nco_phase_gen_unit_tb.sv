// -----------------------------------------------------------------------------
// p5_nco_phase_gen_unit_tb.sv
//
// Unit testbench for rtl/nco_phase_gen.v (NCO phase accumulator).
//
// DUT facts (from RTL):
//   - NCO_PHASE_WIDTH = 32, signed step_word
//   - aresetn (active-low) clears step/phase/pipeline to 0
//   - load_step  : 1-cycle pulse copies step_word -> step_word_r
//   - phase_reset: synchronous clears phase_acc_r to 0
//   - enable     : gates accumulator AND sin/cos pipeline
//   - phase_acc_r updates as: phase_acc_r <= phase_acc_r + step_word_r (mod 2^32)
//
// Subtests:
//   A) Zero step      -> phase stays 0 for 100 cycles
//   B) Constant +step -> phase increments by step each enabled cycle
//   C) Constant -step -> phase decrements by step each enabled cycle
//   D) Wrap-around    -> step that crosses MAX wraps mod 2^32 correctly
//   E) Random steps   -> expected = sum(steps) mod 2^32 == phase_acc each cycle
//
// Gate line (exactly one):
//   GATE_P5_NCO_UNIT: PASS
//   GATE_P5_NCO_UNIT: FAIL
//
// Watchdog : 10000 cycles total simulation -> FAIL
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module p5_nco_phase_gen_unit_tb;

    // -----------------------------
    // Clock / reset / DUT signals
    // -----------------------------
    localparam integer NCO_PHASE_WIDTH    = 32;
    localparam integer CORDIC_PHASE_WIDTH = 16;
    localparam integer ROT_COEFF_WIDTH    = 16;
    localparam integer LATENCY            = 15;

    reg                                aclk        = 1'b0;
    reg                                aresetn     = 1'b0;
    reg                                load_step   = 1'b0;
    reg  signed [NCO_PHASE_WIDTH-1:0]  step_word   = 32'sd0;
    reg                                phase_reset = 1'b0;
    reg                                enable      = 1'b0;

    wire signed [ROT_COEFF_WIDTH-1:0]  sin_out;
    wire signed [ROT_COEFF_WIDTH-1:0]  cos_out;
    wire                               sincos_valid;
    wire        [NCO_PHASE_WIDTH-1:0]  phase_acc;

    // 4 ns period -> 250 MHz, matches project line rate.
    always #2 aclk = ~aclk;

    // -----------------------------
    // DUT
    // -----------------------------
    nco_phase_gen #(
        .NCO_PHASE_WIDTH    (NCO_PHASE_WIDTH),
        .CORDIC_PHASE_WIDTH (CORDIC_PHASE_WIDTH),
        .ROTATOR_COEFF_WIDTH(ROT_COEFF_WIDTH),
        .LATENCY            (LATENCY)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .load_step   (load_step),
        .step_word   (step_word),
        .phase_reset (phase_reset),
        .enable      (enable),
        .sin_out     (sin_out),
        .cos_out     (cos_out),
        .sincos_valid(sincos_valid),
        .phase_acc   (phase_acc)
    );

    // -----------------------------
    // Watchdog
    // -----------------------------
    integer cyc_count;
    reg     wdog_fail;
    initial begin
        cyc_count = 0;
        wdog_fail = 1'b0;
    end
    always @(posedge aclk) begin
        cyc_count <= cyc_count + 1;
        if (cyc_count > 10000) begin
            $display("WDG: TIMEOUT after %0d cycles", cyc_count);
            wdog_fail <= 1'b1;
        end
    end

    // -----------------------------
    // Helpers
    // -----------------------------
    task do_async_reset;
        begin
            aresetn     = 1'b0;
            load_step   = 1'b0;
            step_word   = 32'sd0;
            phase_reset = 1'b0;
            enable      = 1'b0;
            @(posedge aclk); #1;
            @(posedge aclk); #1;
            aresetn     = 1'b1;
            @(posedge aclk); #1;
        end
    endtask

    task load_step_word(input signed [NCO_PHASE_WIDTH-1:0] s);
        begin
            step_word = s;
            load_step = 1'b1;
            @(posedge aclk); #1;
            load_step = 1'b0;
            step_word = 32'sd0; // value lives in step_word_r now
        end
    endtask

    // -----------------------------
    // Pass / Fail trackers
    // -----------------------------
    reg pass_A, pass_B, pass_C, pass_D, pass_E;

    // -----------------------------
    // TEST A — zero step, 100 cycles, phase stays 0
    // -----------------------------
    task run_test_A;
        integer i;
        integer fails;
        begin
            fails = 0;
            do_async_reset();
            load_step_word(32'sd0);
            enable = 1'b1;
            for (i = 0; i < 100; i = i + 1) begin
                @(posedge aclk); #1;
                if (phase_acc !== 32'h0000_0000) begin
                    if (fails < 4)
                        $display("[P5-NCO] test_A: cycle %0d phase_acc=0x%08h (expected 0)",
                                 i, phase_acc);
                    fails = fails + 1;
                end
            end
            enable = 1'b0;
            if (fails == 0) begin
                pass_A = 1'b1;
                $display("[P5-NCO] test_A PASS  (zero step, 100 cycles, phase==0)");
            end else begin
                pass_A = 1'b0;
                $display("[P5-NCO] test_A FAIL  (%0d mismatches)", fails);
            end
        end
    endtask

    // -----------------------------
    // TEST B — constant +0x10000000, 256 cycles, phase increases by step/cycle
    // -----------------------------
    task run_test_B;
        integer i;
        integer fails;
        reg [31:0] expected;
        reg [31:0] step_val;
        begin
            fails    = 0;
            step_val = 32'h1000_0000;
            do_async_reset();
            load_step_word(step_val);
            // After load, accumulator is still 0. First enabled posedge
            // -> phase_acc_r <= 0 + step_val.
            expected = 32'h0000_0000;
            enable   = 1'b1;
            for (i = 0; i < 256; i = i + 1) begin
                expected = expected + step_val;
                @(posedge aclk); #1;
                if (phase_acc !== expected) begin
                    if (fails < 4)
                        $display("[P5-NCO] test_B: cycle %0d phase_acc=0x%08h expected=0x%08h",
                                 i, phase_acc, expected);
                    fails = fails + 1;
                end
            end
            enable = 1'b0;
            if (fails == 0) begin
                pass_B = 1'b1;
                $display("[P5-NCO] test_B PASS  (+step accumulation, 256 cycles)");
            end else begin
                pass_B = 1'b0;
                $display("[P5-NCO] test_B FAIL  (%0d mismatches)", fails);
            end
        end
    endtask

    // -----------------------------
    // TEST C — constant -0x10000000, 256 cycles, phase decreases (mod 2^32)
    // -----------------------------
    task run_test_C;
        integer i;
        integer fails;
        reg [31:0] expected;
        reg signed [31:0] step_val;
        begin
            fails    = 0;
            step_val = -32'sh1000_0000;
            do_async_reset();
            load_step_word(step_val);
            expected = 32'h0000_0000;
            enable   = 1'b1;
            for (i = 0; i < 256; i = i + 1) begin
                expected = expected + step_val; // unsigned wrap is fine
                @(posedge aclk); #1;
                if (phase_acc !== expected) begin
                    if (fails < 4)
                        $display("[P5-NCO] test_C: cycle %0d phase_acc=0x%08h expected=0x%08h",
                                 i, phase_acc, expected);
                    fails = fails + 1;
                end
            end
            enable = 1'b0;
            if (fails == 0) begin
                pass_C = 1'b1;
                $display("[P5-NCO] test_C PASS  (-step accumulation, 256 cycles)");
            end else begin
                pass_C = 1'b0;
                $display("[P5-NCO] test_C FAIL  (%0d mismatches)", fails);
            end
        end
    endtask

    // -----------------------------
    // TEST D — wrap-around: step=0x80000000 forces immediate cross of MAX,
    //          a second enabled cycle wraps back to 0.
    // -----------------------------
    task run_test_D;
        integer fails;
        reg [31:0] step_val;
        reg [31:0] after1, after2;
        begin
            fails    = 0;
            step_val = 32'h8000_0000;
            do_async_reset();
            load_step_word(step_val);
            enable = 1'b1;
            @(posedge aclk); #1; // phase: 0 + 0x80000000 = 0x80000000 (negative half)
            after1 = phase_acc;
            @(posedge aclk); #1; // phase: 0x80000000 + 0x80000000 = 0x00000000 (wrap)
            after2 = phase_acc;
            enable = 1'b0;
            if (after1 !== 32'h8000_0000) begin
                $display("[P5-NCO] test_D: after step1 phase_acc=0x%08h expected=0x80000000",
                         after1);
                fails = fails + 1;
            end
            if (after2 !== 32'h0000_0000) begin
                $display("[P5-NCO] test_D: after step2 phase_acc=0x%08h expected=0x00000000 (wrap)",
                         after2);
                fails = fails + 1;
            end
            if (fails == 0) begin
                pass_D = 1'b1;
                $display("[P5-NCO] test_D PASS  (wrap 0->0x80000000->0)");
            end else begin
                pass_D = 1'b0;
                $display("[P5-NCO] test_D FAIL  (%0d mismatches)", fails);
            end
        end
    endtask

    // -----------------------------
    // TEST E — random steps: expected = sum(steps) mod 2^32
    // For each iteration we load a new step, then take ONE accumulator step.
    // -----------------------------
    task run_test_E;
        integer i;
        integer fails;
        reg [31:0] expected;
        reg [31:0] step_val;
        begin
            fails    = 0;
            expected = 32'h0000_0000;
            do_async_reset();
            // Seed: keep deterministic across re-runs
            for (i = 0; i < 50; i = i + 1) begin
                step_val = $random; // signed 32b pseudo-random
                load_step_word(step_val);
                // Take one accumulator tick
                enable = 1'b1;
                @(posedge aclk); #1;
                enable = 1'b0;
                expected = expected + step_val; // unsigned 32-b wrap matches RTL
                if (phase_acc !== expected) begin
                    if (fails < 4)
                        $display("[P5-NCO] test_E: iter %0d step=0x%08h phase_acc=0x%08h expected=0x%08h",
                                 i, step_val, phase_acc, expected);
                    fails = fails + 1;
                end
            end
            if (fails == 0) begin
                pass_E = 1'b1;
                $display("[P5-NCO] test_E PASS  (50 random steps, modulo-2^32 sum match)");
            end else begin
                pass_E = 1'b0;
                $display("[P5-NCO] test_E FAIL  (%0d mismatches)", fails);
            end
        end
    endtask

    // -----------------------------
    // Top sequencer
    // -----------------------------
    initial begin
        pass_A = 1'b0;
        pass_B = 1'b0;
        pass_C = 1'b0;
        pass_D = 1'b0;
        pass_E = 1'b0;

        $display("========================================================================");
        $display("p5_nco_phase_gen_unit_tb — NCO phase accumulator unit TB");
        $display("  NCO_PHASE_WIDTH = %0d, LATENCY = %0d", NCO_PHASE_WIDTH, LATENCY);
        $display("========================================================================");

        run_test_A();
        run_test_B();
        run_test_C();
        run_test_D();
        run_test_E();

        $display("------------------------------------------------------------------------");
        $display("Subtest summary:");
        $display("  A (zero step)            : %s", pass_A ? "PASS" : "FAIL");
        $display("  B (constant +step)       : %s", pass_B ? "PASS" : "FAIL");
        $display("  C (constant -step)       : %s", pass_C ? "PASS" : "FAIL");
        $display("  D (wrap-around)          : %s", pass_D ? "PASS" : "FAIL");
        $display("  E (random steps mod 2^32): %s", pass_E ? "PASS" : "FAIL");
        $display("------------------------------------------------------------------------");

        if (wdog_fail) begin
            $display("GATE_P5_NCO_UNIT: FAIL");
            $display("  REASON: watchdog timeout");
        end else if (pass_A && pass_B && pass_C && pass_D && pass_E) begin
            $display("GATE_P5_NCO_UNIT: PASS");
        end else begin
            $display("GATE_P5_NCO_UNIT: FAIL");
        end

        $finish;
    end

endmodule
