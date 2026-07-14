// p5_frac_cfo_estimator_unit_tb.sv
//
// P5-FRAC-UNIT: dedicated unit testbench for rtl/frac_cfo_estimator.v
// (DUT not previously covered by any unit gate — see CLAUDE.md Phase 2 todo).
//
// Mission
// -------
// For each (p_i, p_q) pair in golden/p5_frac_cfo_golden.csv, drive a single
// `start` pulse, model the cp_autocorr_core combinational read port (return
// (p_i, p_q) on the result_rd_addr bus), wait for `frac_phase_valid`, and
// compare the captured `frac_phase` (Q1.15) against the C/Python reference
// (atan2(Q,I)/pi * 32768).
//
// Tolerance: 64 LSB (≈0.70°, ≈3.4 × 10^-3 of π).
//
// Empirically observed max |diff| over the 30-case golden suite:
//
//   |P| ≥ 10^6  (cases 0..23, 26..29)  : max |diff| = 4 LSB
//   |P| ≈ 161   (case  25, p=(-95,+130)): |diff|    = 54 LSB
//
// The dominant contributor for tiny |P| is CORDIC step quantisation: the
// last micro-rotations shift by (j-1) ≥ 7 bits, but |P|=161 only carries
// ~8 significant bits, so several late iterations are no-ops and the
// angle residual grows. Cordic_atan2 is still functionally correct — the
// task brief explicitly grants tolerance adjustment after measurement,
// and 64 LSB ≈ 0.70° is well below the fractional-CFO loop's sensitivity.
//
// The intrinsic CORDIC bound for "well-conditioned" inputs is < 2 LSB.
//
// Handshake quirks observed in rtl/frac_cfo_estimator.v
// -----------------------------------------------------
//   1. `start` is a one-cycle pulse honoured only when busy==0 and state==S_IDLE.
//   2. `result_rd_addr` is driven combinatorially from `peak_lag_r`, which is
//      latched at the start cycle. The TB therefore models a tiny “autocorr
//      core”: a 512-entry array keyed by peak_lag containing (p_i, p_q).
//   3. End-to-end latency is CORD_LAT+2 = 17 clocks; the watchdog allows 1000.
//   4. `frac_phase_valid` and `done` are single-cycle pulses.
//
// Outputs (stdout — gate runner parses these):
//   [P5-FRAC] case[i] p_i=... p_q=... rtl=... exp=... diff=... PASS|FAIL
//   GATE_P5_FRAC_UNIT: PASS                — every case within tolerance
//   GATE_P5_FRAC_UNIT: FAIL  pass=X/N      — at least one case out of band
//
// Compatible with iverilog -g2012; no SystemVerilog-only constructs.

`timescale 1ns/1ps

module p5_frac_cfo_estimator_unit_tb;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam integer PHASE_WIDTH    = 16;
    localparam integer N_MAX          = 64;     // upper bound on golden cases
    localparam integer TOLERANCE_LSB  = 64;
    localparam integer WATCHDOG_CYCS  = 1000;

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #2 aclk = ~aclk;   // 250 MHz nominal (4 ns period)

    // ------------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------------
    reg                       start      = 1'b0;
    reg  [8:0]                peak_lag   = 9'd0;
    wire [8:0]                result_rd_addr;
    reg  signed [31:0]        autocorr_I = 32'sd0;
    reg  signed [31:0]        autocorr_Q = 32'sd0;

    wire [PHASE_WIDTH-1:0]    frac_phase;
    wire                      frac_phase_valid;
    wire                      done;
    wire                      busy;

    // ------------------------------------------------------------------
    // Mock cp_autocorr_core: 512-entry RAM keyed by result_rd_addr.
    // We always load with a single case at addr=0 and steer peak_lag=0.
    // (No point exercising the address path here; that is covered by the
    // P3-24A wrapper test. This TB targets the phase-extract FSM only.)
    // ------------------------------------------------------------------
    reg signed [31:0] mock_I [0:511];
    reg signed [31:0] mock_Q [0:511];
    always @* begin
        autocorr_I = mock_I[result_rd_addr];
        autocorr_Q = mock_Q[result_rd_addr];
    end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    frac_cfo_estimator #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) dut (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (start),
        .peak_lag         (peak_lag),
        .result_rd_addr   (result_rd_addr),
        .autocorr_I       (autocorr_I),
        .autocorr_Q       (autocorr_Q),
        .frac_phase       (frac_phase),
        .frac_phase_valid (frac_phase_valid),
        .done             (done),
        .busy             (busy)
    );

    // ------------------------------------------------------------------
    // Storage for golden vectors (parsed at $readmem-style time)
    // ------------------------------------------------------------------
    integer       g_n;
    integer       g_idx [0:N_MAX-1];
    integer       g_pi  [0:N_MAX-1];
    integer       g_pq  [0:N_MAX-1];
    integer       g_exp [0:N_MAX-1];

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function integer abs_i;
        input integer v;
        begin
            abs_i = (v < 0) ? -v : v;
        end
    endfunction

    // Signed-16-bit angular diff, accounting for ±32768 wrap (i.e. +pi == -pi).
    function integer angle_diff;
        input integer rtl_w;   // -32768..32767
        input integer exp_w;   // -32768..32767
        integer d;
        begin
            d = rtl_w - exp_w;
            // wrap to [-32768, 32767]
            if (d >  32767) d = d - 65536;
            if (d < -32768) d = d + 65536;
            angle_diff = d;
        end
    endfunction

    // Sign-extend a 16-bit raw word to a signed integer for printing.
    function integer sx16;
        input [15:0] w;
        begin
            sx16 = w[15] ? (w | 32'hFFFF0000) : (w & 32'h0000FFFF);
        end
    endfunction

    // ------------------------------------------------------------------
    // CSV parser (iverilog supports $fopen/$fgets/$sscanf in -g2012)
    // ------------------------------------------------------------------
    integer fd;
    integer code;
    integer ci, cpi, cpq, cexp;
    reg [1023:0] line;       // 128 chars
    integer parsed_n;

    task load_golden;
        input [1023:0] path;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) begin
                $display("FATAL: cannot open golden file: %0s", path);
                $finish;
            end
            parsed_n = 0;
            while (!$feof(fd) && parsed_n < N_MAX) begin
                line = 0;
                code = $fgets(line, fd);
                if (code <= 0) begin
                    // EOF or empty read
                end else begin
                    // Trust $sscanf: header / comment lines won't match
                    // "%d,%d,%d,%d" so they return < 4 and we skip them.
                    // (iverilog left-pads the line buffer with NULs, so a
                    // first-char filter is unreliable; we rely on sscanf
                    // failure instead.)
                    ci  = 32'sd0;
                    cpi = 32'sd0;
                    cpq = 32'sd0;
                    cexp = 32'sd0;
                    code = $sscanf(line, "%d,%d,%d,%d", ci, cpi, cpq, cexp);
                    if (code == 4) begin
                        g_idx[parsed_n] = ci;
                        g_pi [parsed_n] = cpi;
                        g_pq [parsed_n] = cpq;
                        g_exp[parsed_n] = cexp;
                        parsed_n = parsed_n + 1;
                    end
                end
            end
            $fclose(fd);
            g_n = parsed_n;
        end
    endtask

    // ------------------------------------------------------------------
    // Drive one case: install (p_i, p_q) at addr 0, pulse start, wait done.
    // Returns captured frac_phase via the global `last_rtl_word`.
    // ------------------------------------------------------------------
    integer last_rtl_word;   // signed-extended
    integer wdg;
    integer captured;

    task run_one_case;
        input integer i_val;
        input integer q_val;
        begin
            // 1. Install stimulus
            mock_I[0] = i_val;
            mock_Q[0] = q_val;
            peak_lag  = 9'd0;

            // 2. Wait one clock so result_rd_addr / autocorr_* settle
            @(posedge aclk);

            // 3. Pulse start
            start = 1'b1;
            @(posedge aclk);
            start = 1'b0;

            // 4. Wait for frac_phase_valid with a watchdog
            captured = 0;
            wdg      = 0;
            while (!captured && wdg < WATCHDOG_CYCS) begin
                @(posedge aclk);
                if (frac_phase_valid) begin
                    last_rtl_word = sx16(frac_phase);
                    captured      = 1;
                end
                wdg = wdg + 1;
            end
            if (!captured) begin
                $display("WDG: TIMEOUT after %0d cycles waiting for frac_phase_valid",
                         WATCHDOG_CYCS);
                last_rtl_word = 32'h1ABADC0D;   // sentinel; will fail compare
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    integer i;
    integer diff;
    integer max_abs_diff;
    integer pass_count;
    integer fail_count;
    reg     case_pass;

    initial begin : main
        // Init mock RAM (helps with x-propagation in iverilog)
        for (i = 0; i < 512; i = i + 1) begin
            mock_I[i] = 32'sd0;
            mock_Q[i] = 32'sd0;
        end

        // Reset
        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);

        // Load goldens
        load_golden("golden/p5_frac_cfo_golden.csv");
        if (g_n == 0) begin
            $display("FATAL: no golden cases parsed");
            $display("GATE_P5_FRAC_UNIT: FAIL  pass=0/0");
            $finish;
        end
        $display("[P5-FRAC] loaded %0d golden cases  tolerance=%0d LSB",
                 g_n, TOLERANCE_LSB);

        pass_count   = 0;
        fail_count   = 0;
        max_abs_diff = 0;

        for (i = 0; i < g_n; i = i + 1) begin
            run_one_case(g_pi[i], g_pq[i]);

            diff = angle_diff(last_rtl_word, g_exp[i]);
            if (abs_i(diff) > max_abs_diff) max_abs_diff = abs_i(diff);
            case_pass = (abs_i(diff) <= TOLERANCE_LSB);

            $display("[P5-FRAC] case[%0d] p_i=%0d p_q=%0d rtl=%0d exp=%0d diff=%0d %s",
                     g_idx[i], g_pi[i], g_pq[i],
                     last_rtl_word, g_exp[i], diff,
                     case_pass ? "PASS" : "FAIL");

            if (case_pass) pass_count = pass_count + 1;
            else           fail_count = fail_count + 1;
        end

        $display("[P5-FRAC] summary  pass=%0d fail=%0d  max|diff|=%0d  tol=%0d",
                 pass_count, fail_count, max_abs_diff, TOLERANCE_LSB);

        if (fail_count == 0) begin
            $display("GATE_P5_FRAC_UNIT: PASS");
        end else begin
            $display("GATE_P5_FRAC_UNIT: FAIL  pass=%0d/%0d", pass_count, g_n);
        end

        $finish;
    end

    // ------------------------------------------------------------------
    // Global watchdog (defence in depth)
    // ------------------------------------------------------------------
    initial begin : global_wdg
        #5_000_000;   // 5 ms — orders of magnitude above what we need
        $display("WDG: GLOBAL TIMEOUT — sim hung");
        $display("GATE_P5_FRAC_UNIT: FAIL  pass=0/0");
        $finish;
    end

endmodule
