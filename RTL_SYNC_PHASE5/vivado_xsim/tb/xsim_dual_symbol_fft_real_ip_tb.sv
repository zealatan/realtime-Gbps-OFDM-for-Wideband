`timescale 1ns/1ps
// xsim_dual_symbol_fft_real_ip_tb.sv
// Gate TB for fft256_dual_symbol_frontend with USE_BEHAVIORAL_STUB=0.
//
// Protocol: feed 256 PSS samples, wait for DUT to open for SSS, feed 256 SSS
// samples, then capture the 512-bin output stream (PSS 0..255, SSS 0..255).
//
// Value check: complex tone k=8, A=1024.
//   Bin 8 should have re≈1024; all other bins ≈0.
//   SCALE = 1/256 (1/N for N=256-pt FFT).
//
// Gate output:
//   GATE: PASS_VIVADO_XSIM_REAL_IP
//   GATE: FAIL_VALUE_MISMATCH
//   GATE: FAIL_PROTOCOL

module xsim_dual_symbol_fft_real_ip_tb;

    localparam FFT_LEN    = 256;
    localparam IQ_WIDTH   = 16;
    localparam CLK_PERIOD = 10;
    localparam SCALE      = 256;    // 1/N = 1/256 (all 8 stages scale)
    localparam A          = 1024;
    localparam integer TIMEOUT_LONG = 500000;  // generous: covers FFT pipeline

    // DUT ports
    reg                          aclk;
    reg                          aresetn;
    reg                          start;
    reg                          s_valid;
    wire                         s_ready;
    reg                          s_symbol_sel;
    reg  [7:0]                   s_index;
    reg  signed [IQ_WIDTH-1:0]   s_i;
    reg  signed [IQ_WIDTH-1:0]   s_q;
    wire                         m_valid;
    reg                          m_ready;
    wire                         m_symbol_sel;
    wire [7:0]                   m_index;
    wire signed [IQ_WIDTH-1:0]   m_i;
    wire signed [IQ_WIDTH-1:0]   m_q;
    wire                         busy;
    wire                         done;
    wire                         error;

    fft256_dual_symbol_frontend #(
        .FFT_LEN             (FFT_LEN),
        .IQ_WIDTH            (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB (0),
        .FLUSH_COUNT         (1),
        .WATCHDOG_CYCLES     (TIMEOUT_LONG)
    ) dut (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .start        (start),
        .s_valid      (s_valid),
        .s_ready      (s_ready),
        .s_symbol_sel (s_symbol_sel),
        .s_index      (s_index),
        .s_i          (s_i),
        .s_q          (s_q),
        .m_valid      (m_valid),
        .m_ready      (m_ready),
        .m_symbol_sel (m_symbol_sel),
        .m_index      (m_index),
        .m_i          (m_i),
        .m_q          (m_q),
        .busy         (busy),
        .done         (done),
        .error        (error)
    );

    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // Captured FFT outputs
    reg signed [IQ_WIDTH-1:0] pss_re [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] pss_im [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] sss_re [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] sss_im [0:FFT_LEN-1];

    integer fail_count;
    integer n, k;
    real    angle;
    integer wd;

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    function integer abs_val(input integer v);
        abs_val = (v < 0) ? -v : v;
    endfunction

    // Feed one symbol: drive FFT_LEN samples, then deassert valid.
    // Uses p3_25b-style protocol (no #1, blocking assign after posedge).
    task stream_symbol;
        input integer sym;
        integer k2;
        begin
            for (k2 = 0; k2 < FFT_LEN; k2 = k2 + 1) begin
                @(posedge aclk);
                angle        = 2.0 * 3.14159265358979 * 8.0 * k2 / 256.0;
                s_i          = $rtoi(A * $cos(angle));
                s_q          = $rtoi(A * $sin(angle));
                s_symbol_sel = sym[0];
                s_index      = k2[7:0];
                s_valid      = 1'b1;
                while (!s_ready) @(posedge aclk);
            end
            @(posedge aclk);
            s_valid = 1'b0;
        end
    endtask

    // Wait for DUT to be ready to accept a new symbol (s_ready goes high).
    task wait_for_ready;
        output reg timed_out;
        integer cnt;
        begin
            timed_out = 0;
            cnt = 0;
            while (!s_ready && cnt < TIMEOUT_LONG) begin
                @(posedge aclk);
                cnt = cnt + 1;
            end
            if (!s_ready) begin
                timed_out = 1;
                $display("  [FAIL_PROTOCOL] wait_for_ready timed out (cnt=%0d)", cnt);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Capture output stream: 2*FFT_LEN bins (PSS then SSS, in order).
    task capture_output;
        output reg timed_out;
        integer total, cnt, sss_idx;
        begin
            timed_out = 0;
            total = 0;
            cnt   = 0;
            m_ready = 1'b1;
            while (total < 2*FFT_LEN && cnt < TIMEOUT_LONG) begin
                @(posedge aclk);
                cnt = cnt + 1;
                if (m_valid) begin
                    if (m_symbol_sel == 1'b0 && total < FFT_LEN) begin
                        pss_re[total] = m_i;
                        pss_im[total] = m_q;
                        if (m_index !== total[7:0]) begin
                            $display("  [FAIL_PROTOCOL] PSS m_index=%0d exp=%0d", m_index, total);
                            fail_count = fail_count + 1;
                        end
                        total = total + 1;
                    end else if (m_symbol_sel == 1'b1) begin
                        sss_idx = total - FFT_LEN;
                        sss_re[sss_idx] = m_i;
                        sss_im[sss_idx] = m_q;
                        if (m_index !== sss_idx[7:0]) begin
                            $display("  [FAIL_PROTOCOL] SSS m_index=%0d exp=%0d",
                                     m_index, total-FFT_LEN);
                            fail_count = fail_count + 1;
                        end
                        total = total + 1;
                    end
                    // m_valid with sel=0 and total>=FFT_LEN: pipeline drain bin, skip
                end
            end
            if (total < 2*FFT_LEN) begin
                timed_out = 1;
                $display("  [FAIL_PROTOCOL] capture_output timed out: got %0d/%0d bins",
                         total, 2*FFT_LEN);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    reg timed_out_r;

    initial begin
        fail_count    = 0;
        aresetn       = 0;
        start         = 0;
        s_valid       = 0;
        s_symbol_sel  = 0;
        s_index       = 0;
        s_i           = 0; s_q = 0;
        m_ready       = 1;

        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4) @(posedge aclk);

        // Pulse start
        @(posedge aclk);
        start = 1'b1;
        @(posedge aclk);
        start = 1'b0;

        // Wait for DUT to open for PSS input
        wait_for_ready(timed_out_r);
        if (timed_out_r) begin
            $display("GATE: FAIL_PROTOCOL (PSS ready timeout)");
            $finish;
        end

        // -------------------------------------------------------------------
        // Step 1: Feed 256 PSS samples
        // -------------------------------------------------------------------
        $display("\n--- Feeding PSS (sel=0) ---");
        stream_symbol(0);

        // Wait for DUT to finish PSS processing and open for SSS.
        // s_ready = (S_SSS_FILL && s_symbol_sel): pre-set sel=1 so s_ready
        // asserts as soon as the DUT enters S_SSS_FILL.
        s_symbol_sel = 1'b1;
        $display("  Waiting for DUT to open for SSS...");
        wait_for_ready(timed_out_r);
        if (timed_out_r) begin
            $display("GATE: FAIL_PROTOCOL (SSS ready timeout)");
            $finish;
        end
        $display("  DUT ready for SSS.");

        // -------------------------------------------------------------------
        // Step 2: Feed 256 SSS samples
        // -------------------------------------------------------------------
        $display("\n--- Feeding SSS (sel=1) ---");
        stream_symbol(1);

        // -------------------------------------------------------------------
        // Step 3: Capture 512 output bins (PSS 256 then SSS 256)
        // -------------------------------------------------------------------
        $display("\n--- Capturing output stream (512 bins) ---");
        capture_output(timed_out_r);
        if (timed_out_r) begin
            $display("GATE: FAIL_PROTOCOL (output capture timeout)");
            $finish;
        end
        $display("  Output capture complete.");

        // Wait for done
        wd = 0;
        while (!done && wd < TIMEOUT_LONG) begin
            @(posedge aclk);
            wd = wd + 1;
        end
        if (done)
            $display("  done pulse received.");
        else begin
            $display("  [FAIL_PROTOCOL] done never fired (wd=%0d)", wd);
            fail_count = fail_count + 1;
        end

        // -------------------------------------------------------------------
        // Value checks: complex tone k=8, A=1024, scale=1/256
        // Expected: bin 8 re≈1024, sidelobes ≈0; same for SSS
        // -------------------------------------------------------------------
        $display("\n--- Value checks (tone k=8, A=%0d, SCALE=%0d) ---", A, SCALE);
        begin
            integer expected_re_8, errs;
            expected_re_8 = A * FFT_LEN / SCALE;  // 1024
            errs = 0;

            // PSS bin 8
            if (abs_val($signed(pss_re[8]) - expected_re_8) > 64 ||
                abs_val($signed(pss_im[8])) > 64) begin
                $display("  [FAIL_VALUE_MISMATCH] PSS bin 8: re=%0d im=%0d expected re≈%0d",
                         $signed(pss_re[8]), $signed(pss_im[8]), expected_re_8);
                errs = errs + 1; fail_count = fail_count + 1;
            end
            for (k = 0; k < FFT_LEN; k = k + 1) begin
                if (k == 8) begin : skip_k8 end else begin
                    if (abs_val($signed(pss_re[k])) > 64 || abs_val($signed(pss_im[k])) > 64) begin
                        if (errs < 3)
                            $display("  [FAIL_VALUE_MISMATCH] PSS bin %0d: re=%0d im=%0d (exp ≈0)",
                                     k, $signed(pss_re[k]), $signed(pss_im[k]));
                        errs = errs + 1; fail_count = fail_count + 1;
                    end
                end
            end

            // SSS bin 8
            if (abs_val($signed(sss_re[8]) - expected_re_8) > 64 ||
                abs_val($signed(sss_im[8])) > 64) begin
                $display("  [FAIL_VALUE_MISMATCH] SSS bin 8: re=%0d im=%0d expected re≈%0d",
                         $signed(sss_re[8]), $signed(sss_im[8]), expected_re_8);
                errs = errs + 1; fail_count = fail_count + 1;
            end
            for (k = 0; k < FFT_LEN; k = k + 1) begin
                if (k == 8) begin : skip_k8_sss end else begin
                    if (abs_val($signed(sss_re[k])) > 64 || abs_val($signed(sss_im[k])) > 64) begin
                        if (errs < 6)
                            $display("  [FAIL_VALUE_MISMATCH] SSS bin %0d: re=%0d im=%0d (exp ≈0)",
                                     k, $signed(sss_re[k]), $signed(sss_im[k]));
                        errs = errs + 1; fail_count = fail_count + 1;
                    end
                end
            end

            if (errs == 0)
                $display("  Value check PASS: PSS/SSS bin 8 ≈ %0d, sidelobes suppressed", expected_re_8);
        end

        if (error) begin
            $display("  [FAIL_PROTOCOL] DUT error flag asserted");
            fail_count = fail_count + 1;
        end

        // -------------------------------------------------------------------
        $display("\n========================================");
        if (fail_count == 0)
            $display("GATE: PASS_VIVADO_XSIM_REAL_IP");
        else
            $display("GATE: FAIL_VALUE_MISMATCH (fail_count=%0d)", fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin
        #(CLK_PERIOD * TIMEOUT_LONG * 4);
        $display("  [ERROR] Global watchdog fired");
        $display("GATE: FAIL_PROTOCOL");
        $finish;
    end

endmodule
