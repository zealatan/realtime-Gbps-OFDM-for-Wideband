`timescale 1ns/1ps

// session_B2_p3_13d_fft_hardening_tb — P3-13D Real FFT Hardening
//
// B2-1  Input backpressure at 0 / 10 / 25 / 50 % stall rates.
//       adp_valid randomly deasserted using a 32-bit LFSR.
//       Checks: peak_index preserved, int_cfo preserved, no deadlock.
//
// B2-2  Frame boundary validation.
//       pss_only   — stream PSS, withhold SSS; verify DUT waits, no spurious done.
//       sss_only   — zero PSS, real SSS; verify DUT completes (no deadlock).
//       pss_sss    — complete normal frame; verify flush + correct result.
//       back_to_back — two consecutive frames, no inter-frame reset.
//
// B2-3  Latency characterisation.
//       Measures PSS stream duration, PSS-to-SSS gap, post-stream-to-done.
//       Generates a table; informational only.
//
// Gate: FFT_HARDENING_GATE: PASS
//       FFT_HARDENING_GATE: FAIL
//
// DUT:  meyr_fft256_actual_integration_top (USE_BEHAVIORAL_STUB=3)
// Stim: golden/p3_09_sweep/case_k0.mem  (k_int=0, exp peak=255, int_cfo=0)
// ROMs: vectors/meyr_pss_fft_romhex.txt / meyr_sss_fft_romhex.txt

module session_B2_p3_13d_fft_hardening_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter integer USE_BEHAVIORAL_STUB = 3;
    parameter integer IQ_WIDTH    = 16;
    parameter integer NSC         = 256;
    parameter integer INDEX_WIDTH = 9;
    parameter integer SCORE_WIDTH = 64;

    localparam integer PSS_OFFSET = 96;    // SLOT_START(64)+CP_LEN(32)
    localparam integer SSS_OFFSET = 384;   // SLOT_START(64)+2*CP+NSC

    localparam integer EXP_PEAK  = 255;
    localparam integer EXP_CFO   = 0;

    // Cycle budgets
    localparam integer WD_FULL     = 500_000;  // full PSS+SSS run
    localparam integer WD_PSS_WAIT = 2500;     // post-PSS wait in pss_only check

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;   // 100 MHz, posedge at t=5,15,25,...

    // Cycle counter (blocking; ±1 cycle OK for latency reporting)
    integer sim_cyc;
    initial sim_cyc = 0;
    always @(posedge aclk) sim_cyc = sim_cyc + 1;

    // -----------------------------------------------------------------------
    // DUT interface
    // -----------------------------------------------------------------------
    reg        start_r    = 1'b0;
    reg        adp_valid  = 1'b0;
    wire       adp_ready;
    reg        adp_sym_sel;
    reg  [7:0] adp_index;
    reg  signed [IQ_WIDTH-1:0] adp_i;
    reg  signed [IQ_WIDTH-1:0] adp_q;

    wire                   dut_tvalid, dut_tready, dut_tlast, dut_sym_sel;
    wire [2*IQ_WIDTH-1:0]  dut_tdata;
    wire                   dut_done, dut_busy, dut_error;
    wire [3:0]             dut_error_code;
    wire signed [15:0]     dut_int_cfo;
    wire [INDEX_WIDTH-1:0] dut_peak_index;
    wire [SCORE_WIDTH-1:0] dut_peak_score;

    // -----------------------------------------------------------------------
    // Harness adapter
    // -----------------------------------------------------------------------
    meyr_fft256_harness_adapter #(.IQ_WIDTH(IQ_WIDTH)) u_adp (
        .s_valid           (adp_valid),
        .s_ready           (adp_ready),
        .s_symbol_sel      (adp_sym_sel),
        .s_index           (adp_index),
        .s_i               (adp_i),
        .s_q               (adp_q),
        .m_axis_tvalid     (dut_tvalid),
        .m_axis_tready     (dut_tready),
        .m_axis_tdata      (dut_tdata),
        .m_axis_tlast      (dut_tlast),
        .m_axis_symbol_sel (dut_sym_sel)
    );

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    meyr_fft256_actual_integration_top #(
        .NSC                (NSC),
        .IQ_WIDTH           (IQ_WIDTH),
        .INDEX_WIDTH        (INDEX_WIDTH),
        .SCORE_WIDTH        (SCORE_WIDTH),
        .USE_BEHAVIORAL_STUB(USE_BEHAVIORAL_STUB),
        .FLUSH_COUNT        (1),
        .WATCHDOG_CYCLES    (2047),
        .PSS_ROM_FILE       ("vectors/meyr_pss_fft_romhex.txt"),
        .SSS_ROM_FILE       ("vectors/meyr_sss_fft_romhex.txt")
    ) u_dut (
        .aclk                  (aclk),
        .aresetn               (aresetn),
        .start                 (start_r),
        .s_axis_tvalid         (dut_tvalid),
        .s_axis_tready         (dut_tready),
        .s_axis_tdata          (dut_tdata),
        .s_axis_tlast          (dut_tlast),
        .s_symbol_sel          (dut_sym_sel),
        .done                  (dut_done),
        .busy                  (dut_busy),
        .error                 (dut_error),
        .error_code            (dut_error_code),
        .ev_tlast_missing_o    (),
        .ev_tlast_unexpected_o (),
        .ev_data_in_halt_o     (),
        .ev_data_out_halt_o    (),
        .ev_status_halt_o      (),
        .int_cfo               (dut_int_cfo),
        .peak_index            (dut_peak_index),
        .peak_score            (dut_peak_score)
    );

    // -----------------------------------------------------------------------
    // Stimulus storage
    // -----------------------------------------------------------------------
    reg [31:0] frame_mem   [0:703];
    reg [15:0] pss_i_vec   [0:NSC-1];
    reg [15:0] pss_q_vec   [0:NSC-1];
    reg [15:0] sss_i_vec   [0:NSC-1];
    reg [15:0] sss_q_vec   [0:NSC-1];

    // -----------------------------------------------------------------------
    // Pass / fail counters
    // -----------------------------------------------------------------------
    integer b21_pass, b21_fail;
    integer b22_pass, b22_fail;
    integer b23_fail;

    // -----------------------------------------------------------------------
    // LFSR — 32-bit maximal-length (taps 31,21,1,0)
    // -----------------------------------------------------------------------
    reg [31:0] lfsr;

    task lfsr_step;
        begin
            lfsr = {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: reset DUT
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            aresetn    = 1'b0;
            start_r    = 1'b0;
            adp_valid  = 1'b0;
            adp_sym_sel = 1'b0;
            adp_index  = 8'd0;
            adp_i      = {IQ_WIDTH{1'b0}};
            adp_q      = {IQ_WIDTH{1'b0}};
            repeat(8) @(posedge aclk);
            aresetn = 1'b1;
            repeat(4) @(posedge aclk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: load frame .mem and unpack PSS/SSS windows
    // -----------------------------------------------------------------------
    task load_frame_mem;
        input [255:0] fname;
        integer k;
        begin
            $readmemh(fname, frame_mem, 0, 703);
            for (k = 0; k < NSC; k = k + 1) begin
                pss_i_vec[k] = frame_mem[PSS_OFFSET + k][15:0];
                pss_q_vec[k] = frame_mem[PSS_OFFSET + k][31:16];
                sss_i_vec[k] = frame_mem[SSS_OFFSET + k][15:0];
                sss_q_vec[k] = frame_mem[SSS_OFFSET + k][31:16];
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: stream one symbol with pseudo-random input stalls
    //   sym       0=PSS  1=SSS
    //   stall_pct probability of inserting a 1-4 cycle gap before each sample
    // -----------------------------------------------------------------------
    task stream_sym;
        input integer sym;
        input integer stall_pct;
        integer k;
        integer gap;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk); #1;
                adp_valid   = 1'b1;
                adp_sym_sel = sym[0];
                adp_index   = k[7:0];
                adp_i = $signed(sym == 0 ? pss_i_vec[k] : sss_i_vec[k]);
                adp_q = $signed(sym == 0 ? pss_q_vec[k] : sss_q_vec[k]);
                while (!adp_ready) begin @(posedge aclk); #1; end
                // Stall AFTER presenting: DUT captures this sample, then we deassert
                if (stall_pct > 0) begin
                    lfsr_step;
                    if ((lfsr[6:0] % 100) < stall_pct) begin
                        lfsr_step;
                        gap = 1 + (lfsr[2:0] % 4);
                        @(posedge aclk); #1;
                        adp_valid = 1'b0;
                        repeat(gap) begin @(posedge aclk); #1; end
                    end
                end
            end
            @(posedge aclk); #1;
            adp_valid = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: stream a symbol of all-zero samples (sss_only boundary test)
    // -----------------------------------------------------------------------
    task stream_zero_sym;
        input integer sym;
        integer k;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk); #1;
                adp_valid   = 1'b1;
                adp_sym_sel = sym[0];
                adp_index   = k[7:0];
                adp_i       = {IQ_WIDTH{1'b0}};
                adp_q       = {IQ_WIDTH{1'b0}};
                while (!adp_ready) begin @(posedge aclk); #1; end
            end
            @(posedge aclk); #1;
            adp_valid = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: wait for done or timeout
    // -----------------------------------------------------------------------
    task wait_done;
        output reg timed_out;
        input  integer max_cyc;
        integer wd;
        begin
            timed_out = 1'b0;
            wd = 0;
            while (!dut_done && wd < max_cyc) begin
                @(posedge aclk);
                wd = wd + 1;
            end
            if (!dut_done) timed_out = 1'b1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: pulse start for one clock
    // -----------------------------------------------------------------------
    task pulse_start;
        begin
            @(posedge aclk); #1; start_r = 1'b1;
            @(posedge aclk); #1; start_r = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: B2-1 — run one backpressure case
    // -----------------------------------------------------------------------
    task run_bp_case;
        input [127:0] label;
        input integer stall_pct;
        reg timed_out;
        begin
            $display("[B2-1] %-8s stall=%0d%%", label, stall_pct);
            pulse_start;
            stream_sym(0, stall_pct);
            stream_sym(1, stall_pct);
            wait_done(timed_out, WD_FULL);

            if (timed_out) begin
                b21_fail = b21_fail + 1;
                $display("[B2-1] FAIL  %-8s — DEADLOCK (no done in %0d cycles)",
                         label, WD_FULL);
            end else if (dut_error) begin
                b21_fail = b21_fail + 1;
                $display("[B2-1] FAIL  %-8s — DUT error_code=%0d", label, dut_error_code);
            end else if (dut_peak_index == EXP_PEAK[INDEX_WIDTH-1:0] &&
                         $signed(dut_int_cfo) == $signed(EXP_CFO[15:0])) begin
                b21_pass = b21_pass + 1;
                $display("[B2-1] PASS  %-8s  peak=%0d  int_cfo=%0d  score=%0d",
                         label, dut_peak_index, $signed(dut_int_cfo), dut_peak_score);
            end else begin
                b21_fail = b21_fail + 1;
                $display("[B2-1] FAIL  %-8s  peak=%0d(exp %0d)  int_cfo=%0d(exp %0d)",
                         label, dut_peak_index, EXP_PEAK,
                         $signed(dut_int_cfo), EXP_CFO);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: B2-3 — run latency measurement case
    //   Records timestamps at key handshake points and prints a table.
    // -----------------------------------------------------------------------
    task run_latency_case;
        integer t_pss0, t_pss255, t_sss0, t_sss255, t_done_lat;
        integer k;
        reg timed_out_lat;
        begin
            t_pss0 = 0; t_pss255 = 0; t_sss0 = 0; t_sss255 = 0; t_done_lat = 0;

            do_reset;
            pulse_start;

            // PSS stream — record first/last accepted cycles
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk); #1;
                adp_valid   = 1'b1;
                adp_sym_sel = 1'b0;
                adp_index   = k[7:0];
                adp_i = $signed(pss_i_vec[k]);
                adp_q = $signed(pss_q_vec[k]);
                while (!adp_ready) begin @(posedge aclk); #1; end
                if (k == 0)   t_pss0   = sim_cyc;
                if (k == 255) t_pss255 = sim_cyc;
            end
            @(posedge aclk); #1; adp_valid = 1'b0;

            // SSS stream (stalls in 'while !adp_ready' while DUT processes PSS)
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk); #1;
                adp_valid   = 1'b1;
                adp_sym_sel = 1'b1;
                adp_index   = k[7:0];
                adp_i = $signed(sss_i_vec[k]);
                adp_q = $signed(sss_q_vec[k]);
                while (!adp_ready) begin @(posedge aclk); #1; end
                if (k == 0)   t_sss0   = sim_cyc;
                if (k == 255) t_sss255 = sim_cyc;
            end
            @(posedge aclk); #1; adp_valid = 1'b0;

            wait_done(timed_out_lat, WD_FULL);
            t_done_lat = sim_cyc;

            if (timed_out_lat) begin
                b23_fail = b23_fail + 1;
                $display("[B2-3] FAIL — timeout; latency unmeasurable");
            end else begin
                $display("");
                $display("[B2-3] Latency table  (USE_BEHAVIORAL_STUB=%0d, FLUSH_COUNT=1, 100 MHz)",
                         USE_BEHAVIORAL_STUB);
                $display("[B2-3]   %-42s %5d cyc",
                         "PSS stream (PSS[0]..PSS[255] accepted):",
                         t_pss255 - t_pss0 + 1);
                $display("[B2-3]   %-42s %5d cyc",
                         "PSS processing gap (last PSS → first SSS):",
                         t_sss0 - t_pss255);
                $display("[B2-3]   %-42s %5d cyc",
                         "SSS stream (SSS[0]..SSS[255] accepted):",
                         t_sss255 - t_sss0 + 1);
                $display("[B2-3]   %-42s %5d cyc",
                         "Post-stream latency (last SSS → done):",
                         t_done_lat - t_sss255);
                $display("[B2-3]   %-42s %5d cyc",
                         "Total (first PSS → done):",
                         t_done_lat - t_pss0);
                $display("[B2-3]");
                $display("[B2-3]   FLUSH_COUNT=1 inserts one extra FFT pass per symbol.");
                $display("[B2-3]   PSS processing gap ~= 2×256 (restream) + 2×257 (flush+cap).");
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        $display("");
        $display("====================================================");
        $display(" P3-13D Real FFT Hardening");
        $display(" USE_BEHAVIORAL_STUB=%0d (behavioral DFT)", USE_BEHAVIORAL_STUB);
        $display(" Stimulus: golden/p3_09_sweep/case_k0.mem");
        $display("====================================================");
        $display("");

        b21_pass = 0; b21_fail = 0;
        b22_pass = 0; b22_fail = 0;
        b23_fail = 0;

        load_frame_mem("golden/p3_09_sweep/case_k0.mem");

        // ===================================================================
        // B2-1: Backpressure sweep
        // ===================================================================
        $display("----------------------------------------------------");
        $display("B2-1: Input Backpressure");
        $display("  adp_valid randomly stalled at 0/10/25/50 pct");
        $display("  Verify peak=%0d int_cfo=%0d preserved, no deadlock",
                 EXP_PEAK, EXP_CFO);
        $display("----------------------------------------------------");

        do_reset; lfsr = 32'hDEADB00F; run_bp_case("s0pct",  0);
        do_reset; lfsr = 32'hCAFEB00F; run_bp_case("s10pct", 10);
        do_reset; lfsr = 32'hFACE1234; run_bp_case("s25pct", 25);
        do_reset; lfsr = 32'h600DFeed; run_bp_case("s50pct", 50);

        $display("");
        $display("B2-1 results: %0d passed, %0d failed (of 4)", b21_pass, b21_fail);
        if (b21_fail == 0) $display("B2-1_GATE: PASS");
        else               $display("B2-1_GATE: FAIL");

        // ===================================================================
        // B2-2: Frame boundary validation
        // ===================================================================
        $display("");
        $display("----------------------------------------------------");
        $display("B2-2: Frame Boundary Validation");
        $display("  Verify flush logic and frame separation");
        $display("----------------------------------------------------");

        // ---- pss_only ----
        // Stream PSS, never stream SSS.
        // After WD_PSS_WAIT cycles DUT must still be busy waiting in S_SSS_BUF.
        $display("[B2-2] pss_only: PSS streamed, SSS withheld for %0d cycles",
                 WD_PSS_WAIT);
        begin : blk_pss_only
            do_reset;
            pulse_start;
            stream_sym(0, 0);
            repeat(WD_PSS_WAIT) @(posedge aclk);
            if (!dut_done && dut_busy) begin
                b22_pass = b22_pass + 1;
                $display("[B2-2] PASS  pss_only — DUT waits in S_SSS_BUF (done=0 busy=1)");
            end else begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  pss_only — done=%0b busy=%0b error=%0b",
                         dut_done, dut_busy, dut_error);
            end
        end

        // ---- sss_only (zero PSS + real SSS) ----
        // DUT fills PSS buffer with zeros, SSS with real data.
        // Cross-spectrum is zero everywhere; estimator returns score=0 at some peak.
        // Must complete without deadlock or FSM crash.
        $display("[B2-2] sss_only: zero PSS, real SSS — verify completion, no deadlock");
        begin : blk_sss_only
            reg timed_out_sss;
            do_reset;
            pulse_start;
            stream_zero_sym(0);             // zeros as PSS
            stream_sym(1, 0);               // real SSS
            wait_done(timed_out_sss, WD_FULL);
            if (timed_out_sss) begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  sss_only — DEADLOCK (done never asserted)");
            end else if (dut_error) begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  sss_only — DUT error_code=%0d", dut_error_code);
            end else begin
                b22_pass = b22_pass + 1;
                $display("[B2-2] PASS  sss_only — done=1 error=0  peak=%0d score=%0d",
                         dut_peak_index, dut_peak_score);
            end
        end

        // ---- pss_sss normal ----
        // Complete frame; also directly verifies that FLUSH_COUNT=1 flush state
        // is correctly traversed (any flush error → dut_error=1).
        $display("[B2-2] pss_sss: complete frame, verify flush + correct results");
        begin : blk_pss_sss
            reg timed_out_n;
            do_reset;
            pulse_start;
            stream_sym(0, 0);
            stream_sym(1, 0);
            wait_done(timed_out_n, WD_FULL);
            if (timed_out_n) begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  pss_sss — timeout");
            end else if (dut_error) begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  pss_sss — DUT error_code=%0d (flush error?)",
                         dut_error_code);
            end else if (dut_peak_index == EXP_PEAK[INDEX_WIDTH-1:0] &&
                         $signed(dut_int_cfo) == $signed(EXP_CFO[15:0])) begin
                b22_pass = b22_pass + 1;
                $display("[B2-2] PASS  pss_sss  peak=%0d int_cfo=%0d (flush verified)",
                         dut_peak_index, $signed(dut_int_cfo));
            end else begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  pss_sss  peak=%0d(exp %0d) int_cfo=%0d(exp %0d)",
                         dut_peak_index, EXP_PEAK,
                         $signed(dut_int_cfo), EXP_CFO);
            end
        end

        // ---- back_to_back ----
        // Two consecutive frames without inter-frame reset.
        // FSM must return to S_IDLE cleanly and accept a second start.
        // flush_rem is reloaded from FLUSH_COUNT on each start.
        $display("[B2-2] back_to_back: two consecutive frames, no inter-frame reset");
        begin : blk_b2b
            reg timed_out_f1, timed_out_f2;
            integer b2b_ok;
            b2b_ok = 0;

            // Frame 1
            do_reset;
            pulse_start;
            stream_sym(0, 0);
            stream_sym(1, 0);
            wait_done(timed_out_f1, WD_FULL);
            if (!timed_out_f1 && !dut_error &&
                dut_peak_index == EXP_PEAK[INDEX_WIDTH-1:0] &&
                $signed(dut_int_cfo) == $signed(EXP_CFO[15:0])) begin
                b2b_ok = b2b_ok + 1;
                $display("[B2-2] back_to_back frame1 OK  peak=%0d int_cfo=%0d",
                         dut_peak_index, $signed(dut_int_cfo));
            end else begin
                $display("[B2-2] back_to_back frame1 FAIL  to=%0b err=%0b peak=%0d",
                         timed_out_f1, dut_error, dut_peak_index);
            end

            // Frame 2: immediate restart, DUT already in S_IDLE
            repeat(2) @(posedge aclk);
            pulse_start;
            stream_sym(0, 0);
            stream_sym(1, 0);
            wait_done(timed_out_f2, WD_FULL);
            if (!timed_out_f2 && !dut_error &&
                dut_peak_index == EXP_PEAK[INDEX_WIDTH-1:0] &&
                $signed(dut_int_cfo) == $signed(EXP_CFO[15:0])) begin
                b2b_ok = b2b_ok + 1;
                $display("[B2-2] back_to_back frame2 OK  peak=%0d int_cfo=%0d",
                         dut_peak_index, $signed(dut_int_cfo));
            end else begin
                $display("[B2-2] back_to_back frame2 FAIL  to=%0b err=%0b peak=%0d",
                         timed_out_f2, dut_error, dut_peak_index);
            end

            if (b2b_ok == 2) begin
                b22_pass = b22_pass + 1;
                $display("[B2-2] PASS  back_to_back — frame separation correct (2/2 pass)");
            end else begin
                b22_fail = b22_fail + 1;
                $display("[B2-2] FAIL  back_to_back — %0d/2 frames correct", b2b_ok);
            end
        end

        $display("");
        $display("B2-2 results: %0d passed, %0d failed (of 4)", b22_pass, b22_fail);
        if (b22_fail == 0) $display("B2-2_GATE: PASS");
        else               $display("B2-2_GATE: FAIL");

        // ===================================================================
        // B2-3: Latency characterisation
        // ===================================================================
        $display("");
        $display("----------------------------------------------------");
        $display("B2-3: Latency Characterisation");
        $display("----------------------------------------------------");

        run_latency_case;

        $display("");
        if (b23_fail == 0) $display("B2-3_GATE: PASS (informational)");
        else               $display("B2-3_GATE: FAIL");

        // ===================================================================
        // Gate
        // ===================================================================
        $display("");
        $display("====================================================");
        $display(" P3-13D FFT Hardening Summary");
        $display("  B2-1 backpressure : %0d/%0d passed", b21_pass, b21_pass+b21_fail);
        $display("  B2-2 boundary     : %0d/%0d passed", b22_pass, b22_pass+b22_fail);
        $display("  B2-3 latency      : %s", (b23_fail==0) ? "measured" : "FAIL");
        $display("====================================================");

        if (b21_fail == 0 && b22_fail == 0 && b23_fail == 0) begin
            $display("FFT_HARDENING_GATE: PASS");
            $display("  Peak/int_cfo preserved under 0-50%% input stall.");
            $display("  Flush logic correct; frame separation verified.");
            $display("  Latency table printed above.");
        end else begin
            $display("FFT_HARDENING_GATE: FAIL");
            if (b21_fail > 0)
                $display("  B2-1: %0d backpressure case(s) failed", b21_fail);
            if (b22_fail > 0)
                $display("  B2-2: %0d boundary case(s) failed", b22_fail);
            if (b23_fail > 0)
                $display("  B2-3: latency run timed out");
        end
        $display("====================================================");
        $display("");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Global simulation timeout (50 ms wall-clock limit)
    // -----------------------------------------------------------------------
    initial begin
        #50_000_000;
        $display("[B2] GLOBAL TIMEOUT — simulation exceeded 50 ms");
        $display("FFT_HARDENING_GATE: FAIL — global timeout");
        $finish;
    end

endmodule
