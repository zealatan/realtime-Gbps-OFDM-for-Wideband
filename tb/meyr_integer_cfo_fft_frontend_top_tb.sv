`timescale 1ns/1ps

// Testbench for meyr_integer_cfo_fft_frontend_top — Step 34
//
// BYPASS MODE NOTE:
//   The FFT frontend (fft256_dual_symbol_frontend) uses a placeholder
//   S_COMPUTE stage that copies input samples unchanged to output.
//   T3-T12 shift tests inject FREQUENCY-DOMAIN vectors as the "time-domain"
//   input so that the bypass produces the correct estimator inputs.
//   True time-domain → FFT → estimator verification requires a production
//   FFT IP and is pending.
//
// T2 (fft_model_single_bin) validates the behavioral DFT model standalone.
//
// SYNTHETIC TERM2 NOTE:
//   The Meyr core uses a synthetic PRNG term2 ROM (seed 32'hCAFE_B0BB).
//   This testbench mirrors the same PRNG sequence to build shift test vectors.
//   Real mU/goldU-derived term2 ROM remains pending from Step 33.

module meyr_integer_cfo_fft_frontend_top_tb;

    localparam integer FFT_LEN    = 256;
    localparam integer NSC        = FFT_LEN;
    localparam integer IQ_WIDTH   = 16;
    localparam integer PROD_WIDTH = 32;
    localparam integer ACC_WIDTH  = 56;
    localparam integer SCORE_WIDTH = 64;
    localparam integer INDEX_WIDTH = 9;
    localparam integer CENTER     = NSC - 1;  // 255

    localparam real CLK_PERIOD = 10.0;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                         aclk;
    logic                         aresetn;
    logic                         start;
    logic                         s_valid;
    logic                         s_ready;
    logic                         s_symbol_sel;
    logic [7:0]                   s_index;
    logic signed [IQ_WIDTH-1:0]   s_i, s_q;
    logic                         busy;
    logic                         done;
    logic                         error;
    logic signed [15:0]           int_cfo;
    logic [INDEX_WIDTH-1:0]       peak_index;
    logic [SCORE_WIDTH-1:0]       peak_score;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    meyr_integer_cfo_fft_frontend_top #(
        .FFT_LEN    (FFT_LEN),
        .IQ_WIDTH   (IQ_WIDTH),
        .PROD_WIDTH (PROD_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SCORE_WIDTH(SCORE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (start),
        .s_valid     (s_valid),
        .s_ready     (s_ready),
        .s_symbol_sel(s_symbol_sel),
        .s_index     (s_index),
        .s_i         (s_i),
        .s_q         (s_q),
        .busy        (busy),
        .done        (done),
        .error       (error),
        .int_cfo     (int_cfo),
        .peak_index  (peak_index),
        .peak_score  (peak_score)
    );

    // -----------------------------------------------------------------------
    // Behavioral FFT model (for T2 standalone DFT validation)
    // -----------------------------------------------------------------------
    logic signed [IQ_WIDTH-1:0] bfft_in_i  [0:FFT_LEN-1];
    logic signed [IQ_WIDTH-1:0] bfft_in_q  [0:FFT_LEN-1];
    logic signed [IQ_WIDTH-1:0] bfft_out_i [0:FFT_LEN-1];
    logic signed [IQ_WIDTH-1:0] bfft_out_q [0:FFT_LEN-1];
    logic bfft_compute;

    fft256_behavioral_model #(
        .FFT_LEN (FFT_LEN),
        .IQ_WIDTH(IQ_WIDTH)
    ) u_bfft (
        .in_i   (bfft_in_i),
        .in_q   (bfft_in_q),
        .out_i  (bfft_out_i),
        .out_q  (bfft_out_q),
        .compute(bfft_compute)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Mirror of core's synthetic term2 PRNG (seed 32'hCAFE_B0BB).
    // Must match seed and XOR-shift sequence in meyr_integer_cfo_core.v.
    // Values stored as IQ_WIDTH=16 (8-bit sign-extended).
    // -----------------------------------------------------------------------
    logic signed [IQ_WIDTH-1:0] tb_term2_i [0:NSC-1];
    logic signed [IQ_WIDTH-1:0] tb_term2_q [0:NSC-1];

    initial begin : gen_prng
        integer j;
        logic [31:0] seed;
        seed = 32'hCAFE_B0BB;
        for (j = 0; j < NSC; j++) begin
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_i[j] = {{(IQ_WIDTH-8){seed[7]}}, seed[7:0]};
            seed = seed ^ (seed << 13);
            seed = seed ^ (seed >> 17);
            seed = seed ^ (seed << 5);
            tb_term2_q[j] = {{(IQ_WIDTH-8){seed[7]}}, seed[7:0]};
        end
    end

    // -----------------------------------------------------------------------
    // Test counters
    // -----------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer grp_fail_snap;

    task chk(input logic cond, input string msg);
        if (cond) pass_cnt++;
        else begin $display("FAIL: %s", msg); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    task reset_dut;
        aresetn      = 1'b0;
        start        = 1'b0;
        s_valid      = 1'b0;
        s_symbol_sel = 1'b0;
        s_index      = 8'd0;
        s_i          = '0;
        s_q          = '0;
        bfft_compute = 1'b0;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // Send one sample (PSS or SSS) with handshake
    // -----------------------------------------------------------------------
    task send_sample(
        input logic                  sel,
        input integer                n,
        input logic signed [IQ_WIDTH-1:0] si, sq
    );
        @(negedge aclk);
        s_valid = 1'b1; s_symbol_sel = sel;
        s_index = n[7:0]; s_i = si; s_q = sq;
        @(posedge aclk);
        // Wait for handshake
        while (!s_ready) @(posedge aclk);
        @(negedge aclk);
        s_valid = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Stream PSS then SSS for a given shift_s.
    // BYPASS MODE: injects freq-domain vectors as "time-domain" input.
    //   PSS_freq[k] = term2_prng[k-shift_s]  (shifted synthetic term2)
    //   SSS_freq[k] = 1 + j0
    // Since the frontend's S_COMPUTE is a bypass (copies input),
    // the estimator receives these frequency-domain values directly.
    // -----------------------------------------------------------------------
    task stream_pss_sss(input integer shift_s);
        integer n, src;
        logic signed [IQ_WIDTH-1:0] pi, pq;
        // PSS freq-domain bins (injected as "PSS time-domain")
        for (n = 0; n < NSC; n++) begin
            src = n - shift_s;
            if (src >= 0 && src < NSC) begin
                pi = tb_term2_i[src];
                pq = tb_term2_q[src];
            end else begin
                pi = IQ_WIDTH'(0);
                pq = IQ_WIDTH'(0);
            end
            send_sample(1'b0, n, pi, pq);
        end
        // SSS freq-domain bins = 1 + j0
        for (n = 0; n < NSC; n++) begin
            send_sample(1'b1, n, IQ_WIDTH'(1), IQ_WIDTH'(0));
        end
    endtask

    // -----------------------------------------------------------------------
    // Run a full shift test and check results
    // -----------------------------------------------------------------------
    task run_and_check(
        input integer  shift_s,
        input integer  exp_peak,
        input integer  exp_cfo,
        input string   name
    );
        integer timeout;
        @(negedge aclk);
        start = 1'b1;
        @(posedge aclk);
        @(negedge aclk);
        start = 1'b0;

        stream_pss_sss(shift_s);

        // Wait for done
        @(posedge aclk);
        timeout = 0;
        while (!done && timeout < 500000) begin
            @(posedge aclk);
            timeout++;
        end

        if (timeout >= 500000) begin
            $display("FAIL [%0s]: TIMEOUT after %0d cycles", name, timeout);
            fail_cnt += 2;
        end else begin
            if (peak_index == exp_peak) pass_cnt++;
            else begin
                $display("FAIL [%0s]: peak_index=%0d expected=%0d",
                         name, peak_index, exp_peak);
                fail_cnt++;
            end
            if ($signed(int_cfo) == exp_cfo) pass_cnt++;
            else begin
                $display("FAIL [%0s]: int_cfo=%0d expected=%0d",
                         name, $signed(int_cfo), exp_cfo);
                fail_cnt++;
            end
        end
        repeat(2) @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("=== meyr_integer_cfo_fft_frontend_top_tb ===");
        $display("NOTE: T3-T12 use bypass mode (freq-domain vectors injected as");
        $display("      time-domain input).  term2 ROM is synthetic PRNG fallback.");
        $display("      Real mU/goldU and production FFT are pending.");

        reset_dut();

        // ------------------------------------------------------------------
        // T1: reset_defaults
        // ------------------------------------------------------------------
        $display("T1: reset_defaults");
        grp_fail_snap = fail_cnt;
        chk(!busy,  "T1 busy=0 after reset");
        chk(!done,  "T1 done=0 after reset");
        chk(!error, "T1 error=0 after reset");
        if (fail_cnt == grp_fail_snap) $display("T1: PASS");

        // ------------------------------------------------------------------
        // T2: fft_model_single_bin — validate behavioral DFT model.
        //   DC input: in_i[n]=1, in_q[n]=0 for all n.
        //   Expected: X[0]_I = FFT_LEN = 256, X[0]_Q = 0, X[1..] ≈ 0.
        // ------------------------------------------------------------------
        $display("T2: fft_model_single_bin (behavioral DFT DC validation)");
        grp_fail_snap = fail_cnt;
        begin : t2_blk
            integer k;
            for (k = 0; k < FFT_LEN; k++) begin
                bfft_in_i[k] = IQ_WIDTH'(1);
                bfft_in_q[k] = IQ_WIDTH'(0);
            end
            @(negedge aclk); bfft_compute = 1'b1;
            @(posedge aclk); // DFT fires on posedge compute
            #1;               // allow any delta propagation
            chk(bfft_out_i[0] == IQ_WIDTH'(FFT_LEN),
                "T2 DFT DC: X[0]_I = FFT_LEN = 256");
            chk(bfft_out_q[0] == IQ_WIDTH'(0),
                "T2 DFT DC: X[0]_Q = 0");
            chk(bfft_out_i[1] == IQ_WIDTH'(0),
                "T2 DFT DC: X[1]_I = 0 (no adjacent bin energy)");
            @(negedge aclk); bfft_compute = 1'b0;
        end
        if (fail_cnt == grp_fail_snap) $display("T2: PASS");

        // ------------------------------------------------------------------
        // T3: zero_cfo — shift=0 → peak_index=255, int_cfo=0
        // ------------------------------------------------------------------
        $display("T3: zero_cfo (shift=0)");
        grp_fail_snap = fail_cnt;
        run_and_check(0, 255, 0, "T3");
        chk(peak_score > 0, "T3 peak_score > 0");
        if (fail_cnt == grp_fail_snap) $display("T3: PASS");

        // ------------------------------------------------------------------
        // T4: positive_shift_plus1 → peak_index=256, int_cfo=+1
        // ------------------------------------------------------------------
        $display("T4: positive_shift_plus1");
        grp_fail_snap = fail_cnt;
        run_and_check(1, 256, 1, "T4");
        if (fail_cnt == grp_fail_snap) $display("T4: PASS");

        // ------------------------------------------------------------------
        // T5: negative_shift_minus1 → peak_index=254, int_cfo=-1
        // ------------------------------------------------------------------
        $display("T5: negative_shift_minus1");
        grp_fail_snap = fail_cnt;
        run_and_check(-1, 254, -1, "T5");
        if (fail_cnt == grp_fail_snap) $display("T5: PASS");

        // ------------------------------------------------------------------
        // T6: positive_shift_plus3 → peak_index=258, int_cfo=+3
        // ------------------------------------------------------------------
        $display("T6: positive_shift_plus3");
        grp_fail_snap = fail_cnt;
        run_and_check(3, 258, 3, "T6");
        if (fail_cnt == grp_fail_snap) $display("T6: PASS");

        // ------------------------------------------------------------------
        // T7: negative_shift_minus4 → peak_index=251, int_cfo=-4
        // ------------------------------------------------------------------
        $display("T7: negative_shift_minus4");
        grp_fail_snap = fail_cnt;
        run_and_check(-4, 251, -4, "T7");
        if (fail_cnt == grp_fail_snap) $display("T7: PASS");

        // ------------------------------------------------------------------
        // T8: positive_shift_plus8 → peak_index=263, int_cfo=+8
        // ------------------------------------------------------------------
        $display("T8: positive_shift_plus8");
        grp_fail_snap = fail_cnt;
        run_and_check(8, 263, 8, "T8");
        if (fail_cnt == grp_fail_snap) $display("T8: PASS");

        // ------------------------------------------------------------------
        // T9: negative_shift_minus8 → peak_index=247, int_cfo=-8
        // ------------------------------------------------------------------
        $display("T9: negative_shift_minus8");
        grp_fail_snap = fail_cnt;
        run_and_check(-8, 247, -8, "T9");
        if (fail_cnt == grp_fail_snap) $display("T9: PASS");

        // ------------------------------------------------------------------
        // T10: restart_two_frames — shift=0 then shift=+3
        // ------------------------------------------------------------------
        $display("T10: restart_two_frames");
        grp_fail_snap = fail_cnt;
        run_and_check(0, 255,  0, "T10a");
        run_and_check(3, 258,  3, "T10b");
        if (fail_cnt == grp_fail_snap) $display("T10: PASS");

        // ------------------------------------------------------------------
        // T11: start_while_busy → error asserted
        // ------------------------------------------------------------------
        $display("T11: start_while_busy");
        grp_fail_snap = fail_cnt;
        begin : t11_blk
            integer to;
            @(negedge aclk); start = 1'b1;
            @(posedge aclk); @(negedge aclk); start = 1'b0;
            @(posedge aclk);
            chk(busy, "T11 busy after first start");
            // Second start while busy
            @(negedge aclk); start = 1'b1;
            @(posedge aclk); @(negedge aclk); start = 1'b0;
            @(posedge aclk);
            chk(error, "T11 error=1 after start-while-busy");
            // Drain the running frame
            stream_pss_sss(0);
            @(posedge aclk);
            to = 0;
            while (!done && to < 500000) begin @(posedge aclk); to++; end
            repeat(2) @(posedge aclk);
            reset_dut();
        end
        if (fail_cnt == grp_fail_snap) $display("T11: PASS");

        // ------------------------------------------------------------------
        // T12: index_alignment — shift +2 and -2
        // ------------------------------------------------------------------
        $display("T12: index_alignment (+2 and -2)");
        grp_fail_snap = fail_cnt;
        run_and_check( 2, 257,  2, "T12a");
        run_and_check(-2, 253, -2, "T12b");
        if (fail_cnt == grp_fail_snap) $display("T12: PASS");

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

endmodule
