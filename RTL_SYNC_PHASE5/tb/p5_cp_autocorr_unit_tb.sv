`timescale 1ns/1ps
//
// p5_cp_autocorr_unit_tb — Unit testbench for streaming_cp_autocorr
//
// DUT      : rtl/streaming_cp_autocorr.v  (NSC=256, CP_LEN=32)
// Stimulus : golden/phase3_iq_stimulus_q15.hex   (704 samples)
//            each line = {Q[15:0], I[15:0]} hex,  Phase2 packing
// Check    : sample_index at peak |P|^2 ≈ 23 ± 2
//            (golden value GOLDEN_PEAK_LAG=23 from P3-24A regression)
// Gate     : exactly one of
//              GATE_P5_CP_UNIT: PASS
//              GATE_P5_CP_UNIT: FAIL
// Watchdog : 10000 cycles after stream end with no out_valid → FAIL
//
// Simulator: iverilog -g2012 (default) or xsim
//
module p5_cp_autocorr_unit_tb;

    // ------------------------------------------------------------------
    // Parameters
    // ------------------------------------------------------------------
    localparam integer SAMPLE_W = 16;
    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer ACC_W    = 48;

    localparam integer STIM_DEPTH      = 704;
    localparam integer MAX_CAPTURE     = 2048;
    localparam integer GOLDEN_PEAK_LAG = 23;          // peak_index_auto from C ref
    localparam integer PEAK_TOL        = 2;
    // From golden/phase3_iq_stimulus_meta.json
    localparam integer GOLDEN_FRAME_START   = 41;     // expected_frame_start
    localparam integer GOLDEN_PSS_START     = 64;     // expected_pss_start
    localparam integer SYMBOL_PERIOD        = NSC + CP_LEN; // 288
    // Strobe-to-strobe pipeline latency from s_valid to avg_pi_stb in steady state:
    //   delay_sample (1) + complex_mult (3) + moving_avg (4) = 8 cycles.
    localparam integer PIPELINE_LATENCY     = 8;

    // ------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------
    reg clk;
    reg aresetn;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    // ------------------------------------------------------------------
    // DUT signals
    // ------------------------------------------------------------------
    reg                       s_valid;
    reg  [2*SAMPLE_W-1:0]     s_data;

    wire signed [ACC_W-1:0]   p_i;
    wire signed [ACC_W-1:0]   p_q;
    wire        [ACC_W-1:0]   energy;
    wire                      out_valid;
    wire        [31:0]        sample_index;

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    streaming_cp_autocorr #(
        .SAMPLE_W (SAMPLE_W),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .ACC_W    (ACC_W)
    ) u_dut (
        .clk          (clk),
        .aresetn      (aresetn),
        .s_valid      (s_valid),
        .s_data       (s_data),
        .p_i          (p_i),
        .p_q          (p_q),
        .energy       (energy),
        .out_valid    (out_valid),
        .sample_index (sample_index)
    );

    // ------------------------------------------------------------------
    // Stimulus memory: 704 lines of {Q[15:0], I[15:0]} hex
    // ------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // ------------------------------------------------------------------
    // Capture arrays for every out_valid beat (NOTE: out_valid is a permanent
    // latch in this DUT — once set, it stays HIGH every clock. We capture one
    // beat per cycle while out_valid=1 and use a fixed drain to bound runtime
    // instead of edge detection.)
    // ------------------------------------------------------------------
    reg signed [ACC_W-1:0] cap_pi    [0:MAX_CAPTURE-1];
    reg signed [ACC_W-1:0] cap_pq    [0:MAX_CAPTURE-1];
    reg        [ACC_W-1:0] cap_eng   [0:MAX_CAPTURE-1];
    reg        [31:0]      cap_index [0:MAX_CAPTURE-1];
    integer cap_count;
    integer first_valid_seen;

    integer drain_cycles;
    integer stream_done;

    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            cap_count        <= 0;
            first_valid_seen <= 0;
            drain_cycles     <= 0;
        end else begin
            // Only capture on the *new* moving-avg output strobe (avg_pi_stb).
            // out_valid is a sticky latch in this DUT, so it cannot be used to
            // gate per-beat capture. Use the hierarchical probe into u_dut.
            if (out_valid) first_valid_seen <= 1;
            if (u_dut.avg_pi_stb) begin
                if (cap_count < MAX_CAPTURE) begin
                    // Use the moving_avg combinational outputs directly so we
                    // see the strobe-aligned beat (the DUT's p_i/p_q registers
                    // would lag by one cycle vs. the strobe).
                    cap_pi[cap_count]    <= u_dut.avg_pi_out[ACC_W-1:0];
                    cap_pq[cap_count]    <= u_dut.avg_pq_out[ACC_W-1:0];
                    cap_eng[cap_count]   <= u_dut.avg_e_out[ACC_W-1:0];
                    cap_index[cap_count] <= sample_index;
                end
                cap_count <= cap_count + 1;
            end
            if (stream_done) begin
                drain_cycles <= drain_cycles + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Watchdog (post-stream)
    // ------------------------------------------------------------------
    initial begin
        stream_done = 0;
    end

    // ------------------------------------------------------------------
    // Stimulus + verification flow
    // ------------------------------------------------------------------
    integer i;
    integer k;

    // Squared-magnitude accumulators (use plain integer to avoid SV-only types)
    reg signed [2*ACC_W-1:0] mag2_cur;
    reg signed [2*ACC_W-1:0] mag2_best;
    reg        [31:0]        idx_best;
    reg        [31:0]        cap_at_best;
    reg signed [ACC_W-1:0]   tmp_pi;
    reg signed [ACC_W-1:0]   tmp_pq;

    integer peak_ok;
    integer have_valid;
    integer peak_input_sample;
    integer peak_intra_symbol;
    integer derived_peak_lag;

    initial begin
        // Default IO
        s_valid = 1'b0;
        s_data  = {2*SAMPLE_W{1'b0}};

        // Load stimulus
        $readmemh("golden/phase3_iq_stimulus_q15.hex", stim_mem);

        // Reset
        aresetn = 1'b0;
        repeat (20) @(posedge clk);
        aresetn = 1'b1;
        repeat (5) @(posedge clk);

        // ------------------------------------------------------------------
        // Stream 704 samples, one per clock, s_valid=1
        // ------------------------------------------------------------------
        $display("=== [P5_CP_UNIT] Streaming %0d IQ samples ===", STIM_DEPTH);
        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge clk);
            s_valid <= 1'b1;
            s_data  <= stim_mem[i];
        end
        @(posedge clk);
        s_valid <= 1'b0;
        s_data  <= {2*SAMPLE_W{1'b0}};

        stream_done = 1;
        $display("  Stream complete. Draining pipeline...");

        // Drain — out_valid is a sticky latch in this DUT (asserted forever
        // after the first strobe), so we cannot detect end-of-output via
        // out_valid going low. Use a bounded drain that is long enough to
        // flush NSC + CP_LEN + pipeline latency (~ 300 cycles) plus margin,
        // bounded by the hard 10000-cycle post-stream watchdog.
        while (drain_cycles < 1024 && drain_cycles < 10000) @(posedge clk);

        if (cap_count == 0 || !first_valid_seen) begin
            $display("FAIL: out_valid never asserted.");
            $display("GATE_P5_CP_UNIT: FAIL");
            $finish;
        end

        // ------------------------------------------------------------------
        // Find peak |P|^2 = p_i^2 + p_q^2 across captured beats
        // ------------------------------------------------------------------
        mag2_best   = 0;
        idx_best    = 0;
        cap_at_best = 0;
        have_valid  = 0;

        for (k = 0; k < cap_count && k < MAX_CAPTURE; k = k + 1) begin
            tmp_pi   = cap_pi[k];
            tmp_pq   = cap_pq[k];
            mag2_cur = $signed(tmp_pi) * $signed(tmp_pi)
                     + $signed(tmp_pq) * $signed(tmp_pq);
            if (!have_valid || mag2_cur > mag2_best) begin
                mag2_best   = mag2_cur;
                idx_best    = cap_index[k];
                cap_at_best = k;
                have_valid  = 1;
            end
        end

        // ------------------------------------------------------------------
        // Evaluate against golden
        // ------------------------------------------------------------------
        // DUT's `sample_index` is the count of accepted input samples at the
        // strobe cycle. In steady state: sample_index = peak_input + PIPELINE.
        // The first frame's CP peak (input n = PSS_START = 64) is missed
        // because delay_sample needs NSC=256 inputs to fill, so the observable
        // peaks appear one OFDM-symbol (NSC+CP_LEN=288) later:
        //   1st observable peak: input = PSS_START + SYMBOL_PERIOD     = 352
        //   2nd observable peak: input = PSS_START + 2*SYMBOL_PERIOD   = 640
        // Recover the *relative* peak_lag (== GOLDEN_PEAK_LAG=23 from C ref):
        //   peak_lag = (peak_sample_index - PIPELINE) mod SYMBOL_PERIOD
        //              - GOLDEN_FRAME_START
        peak_input_sample  = idx_best - PIPELINE_LATENCY;
        peak_intra_symbol  = peak_input_sample % SYMBOL_PERIOD;
        derived_peak_lag   = peak_intra_symbol - GOLDEN_FRAME_START;
        // Wrap into [-SYMBOL_PERIOD/2, +SYMBOL_PERIOD/2]
        if (derived_peak_lag < -SYMBOL_PERIOD/2)
            derived_peak_lag = derived_peak_lag + SYMBOL_PERIOD;
        if (derived_peak_lag >  SYMBOL_PERIOD/2)
            derived_peak_lag = derived_peak_lag - SYMBOL_PERIOD;

        peak_ok = 0;
        if (derived_peak_lag >= GOLDEN_PEAK_LAG - PEAK_TOL &&
            derived_peak_lag <= GOLDEN_PEAK_LAG + PEAK_TOL)
            peak_ok = 1;

        $display("");
        $display("=== [P5_CP_UNIT] Results ===");
        $display("  Stimulus       : golden/phase3_iq_stimulus_q15.hex");
        $display("  Captured beats : %0d", cap_count);
        $display("  Peak sample_idx: %0d", idx_best);
        $display("  Peak input n   : %0d  (= sample_idx - PIPELINE(%0d))",
                 peak_input_sample, PIPELINE_LATENCY);
        $display("  Intra-symbol   : %0d  (= input mod SYMBOL_PERIOD(%0d))",
                 peak_intra_symbol, SYMBOL_PERIOD);
        $display("  Derived peak_lag: %0d  (golden=%0d +/- %0d)  [intra - frame_start(%0d)]",
                 derived_peak_lag, GOLDEN_PEAK_LAG, PEAK_TOL, GOLDEN_FRAME_START);
        $display("  Peak |P|^2     : %0d", mag2_best);
        $display("  Peak p_i       : %0d", cap_pi[cap_at_best]);
        $display("  Peak p_q       : %0d", cap_pq[cap_at_best]);
        $display("  Peak energy    : %0d", cap_eng[cap_at_best]);
        $display("  Peak cap_index : %0d (of %0d captured beats)", cap_at_best, cap_count);
        $display("");

        // Debug: dump top 10 beats with largest |P|^2 by linear search
        $display("  --- Top |P|^2 beats (sample_index, |P|^2) ---");
        begin : top_dump
            integer dk;
            integer dj;
            integer dtop_n;
            reg signed [2*ACC_W-1:0] dmag;
            reg signed [2*ACC_W-1:0] top_mag [0:9];
            reg [31:0]               top_idx [0:9];
            for (dk = 0; dk < 10; dk = dk + 1) begin
                top_mag[dk] = 0;
                top_idx[dk] = 0;
            end
            for (dk = 0; dk < cap_count && dk < MAX_CAPTURE; dk = dk + 1) begin
                dmag = $signed(cap_pi[dk]) * $signed(cap_pi[dk])
                     + $signed(cap_pq[dk]) * $signed(cap_pq[dk]);
                // Insert into top-10
                for (dj = 0; dj < 10; dj = dj + 1) begin
                    if (dmag > top_mag[dj]) begin
                        // shift down
                        for (dtop_n = 9; dtop_n > dj; dtop_n = dtop_n - 1) begin
                            top_mag[dtop_n] = top_mag[dtop_n-1];
                            top_idx[dtop_n] = top_idx[dtop_n-1];
                        end
                        top_mag[dj] = dmag;
                        top_idx[dj] = cap_index[dk];
                        dj = 10; // break
                    end
                end
            end
            for (dk = 0; dk < 10; dk = dk + 1)
                $display("    [%0d] sample_index=%0d  |P|^2=%0d",
                         dk, top_idx[dk], top_mag[dk]);
        end
        $display("");

        if (peak_ok) begin
            $display("GATE_P5_CP_UNIT: PASS");
        end else begin
            $display("REASON: derived peak_lag=%0d out of [%0d, %0d]",
                     derived_peak_lag, GOLDEN_PEAK_LAG - PEAK_TOL,
                     GOLDEN_PEAK_LAG + PEAK_TOL);
            $display("GATE_P5_CP_UNIT: FAIL");
        end

        $finish;
    end

    // ------------------------------------------------------------------
    // Diagnostic: record the very first avg_pi_stb sample_index (one line)
    integer first_strobe_sidx;
    integer first_strobe_seen;
    initial begin first_strobe_sidx = -1; first_strobe_seen = 0; end
    always @(posedge clk) begin
        if (aresetn && u_dut.avg_pi_stb && !first_strobe_seen) begin
            first_strobe_sidx <= sample_index;
            first_strobe_seen <= 1;
            $display("  [INFO] first avg_pi_stb at sample_index=%0d (expect %0d=NSC+PIPELINE)",
                     sample_index, NSC + PIPELINE_LATENCY);
        end
    end

    // ------------------------------------------------------------------
    // Hard watchdog — total simulation cycles (safety net)
    // ------------------------------------------------------------------
    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge clk) begin
        cycle_cnt <= cycle_cnt + 1;
        if (cycle_cnt > 100000) begin
            $display("WDG: total-cycle timeout (%0d)", cycle_cnt);
            $display("GATE_P5_CP_UNIT: FAIL");
            $finish;
        end
        if (stream_done && drain_cycles >= 10000 && !first_valid_seen) begin
            $display("WDG: %0d cycles after stream end with no out_valid",
                     drain_cycles);
            $display("GATE_P5_CP_UNIT: FAIL");
            $finish;
        end
    end

endmodule
