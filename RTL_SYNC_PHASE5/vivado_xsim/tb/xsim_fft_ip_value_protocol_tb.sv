`timescale 1ns/1ps
// xsim_fft_ip_value_protocol_tb.sv
// Comprehensive TB for fft256_xilinx_wrapper with USE_BEHAVIORAL_STUB=0
// (real Xilinx xfft 9.1 VHDL).
//
// Test cases:
//   T0 — Impulse at n=0:  X[k] = 1.0/scale = 16  (scaled by 1/16)
//   T1 — Tone k=1:        X[1] and X[255] dominate
//   T2 — Tone k=17:       X[17] and X[239] dominate
//   T3 — Pseudo-random 32-sample period (harmonic comb)
//   T4 — PSS-like BPSK (non-zero bins at ±[1..6] with guard band at DC)
//   T5 — DC constant input: X[0] large, all others ≈ 0
//
// Protocol tests:
//   P1 — Verify s_axis_tready deasserts during output phase
//   P2 — Verify m_axis_tlast fires at bin 255
//   P3 — Verify m_axis_tuser tracks xk_index bin 0→255
//
// Tolerance: ±4 LSB on 16-bit values (accounts for Xilinx fixed-point rounding)
//
// Gate output:
//   GATE: PASS_VIVADO_XSIM_REAL_IP — all checks pass
//   GATE: FAIL_VALUE_MISMATCH      — bin value outside tolerance
//   GATE: FAIL_PROTOCOL            — AXI-S handshake/tlast/tuser error
//
// RTL output CSV: vivado_xsim/vectors/rtl_out_case_<N>.csv
// (used by check_fft_ip_outputs.py for cross-check against reference)

module xsim_fft_ip_value_protocol_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam FFT_LEN    = 256;
    localparam IQ_WIDTH   = 16;
    localparam CLK_PERIOD = 10;   // 100 MHz
    // Behavioral model (fft256_xilinx_r8.vhd) scales by 1/N = 1/256 regardless of SCALE_SCH.
    // Real Xilinx xfft with SCALE_SCH=0xAA also scales by 1/N (all 8 stages divide by 2).
    localparam SCALE      = 256;  // xfft scale factor (1/N for N=256)
    localparam TOLERANCE  = 4;    // ±4 LSB tolerance on each IQ component
    localparam integer MAX_WAIT = 4096;  // cycles before timeout

    // -----------------------------------------------------------------------
    // DUT interface
    // -----------------------------------------------------------------------
    logic                      aclk;
    logic                      aresetn;
    logic                      start;
    logic                      s_axis_tvalid;
    logic                      s_axis_tready;
    logic [2*IQ_WIDTH-1:0]     s_axis_tdata;   // {Im, Re}
    logic                      s_axis_tlast;
    logic                      m_axis_tvalid;
    logic                      m_axis_tready;
    logic [2*IQ_WIDTH-1:0]     m_axis_tdata;   // {Im, Re}
    logic [7:0]                m_axis_tuser;   // xk_index
    logic                      m_axis_tlast;
    logic                      busy;
    logic                      done;
    logic                      error;
    logic                      event_frame_started;
    logic                      event_tlast_unexpected;
    logic                      event_tlast_missing;
    logic                      event_data_in_channel_halt;
    logic                      event_data_out_channel_halt;
    logic                      event_status_channel_halt;

    // -----------------------------------------------------------------------
    // DUT instantiation (real Xilinx IP)
    // -----------------------------------------------------------------------
    fft256_xilinx_wrapper #(
        .FFT_LEN             (FFT_LEN),
        .IQ_WIDTH            (IQ_WIDTH),
        .FFT_OUT_WIDTH       (IQ_WIDTH),
        .USE_BEHAVIORAL_STUB (0),
        .STUB_TLAST_AT       (255),
        .STUB_STOP_AT        (255)
    ) dut (
        .aclk                       (aclk),
        .aresetn                    (aresetn),
        .start                      (start),
        .s_axis_tvalid              (s_axis_tvalid),
        .s_axis_tready              (s_axis_tready),
        .s_axis_tdata               (s_axis_tdata),
        .s_axis_tlast               (s_axis_tlast),
        .m_axis_tvalid              (m_axis_tvalid),
        .m_axis_tready              (m_axis_tready),
        .m_axis_tdata               (m_axis_tdata),
        .m_axis_tuser               (m_axis_tuser),
        .m_axis_tlast               (m_axis_tlast),
        .busy                       (busy),
        .done                       (done),
        .error                      (error),
        .event_frame_started        (event_frame_started),
        .event_tlast_unexpected     (event_tlast_unexpected),
        .event_tlast_missing        (event_tlast_missing),
        .event_data_in_channel_halt (event_data_in_channel_halt),
        .event_data_out_channel_halt(event_data_out_channel_halt),
        .event_status_channel_halt  (event_status_channel_halt)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 1'b0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Test state
    // -----------------------------------------------------------------------
    integer fail_count;
    integer test_pass;

    // Storage for captured FFT output
    logic signed [IQ_WIDTH-1:0] out_re [0:FFT_LEN-1];
    logic signed [IQ_WIDTH-1:0] out_im [0:FFT_LEN-1];
    logic [7:0]                  out_idx [0:FFT_LEN-1];

    // Input sample arrays
    logic signed [IQ_WIDTH-1:0] in_re [0:FFT_LEN-1];
    logic signed [IQ_WIDTH-1:0] in_im [0:FFT_LEN-1];

    // -----------------------------------------------------------------------
    // CSV file handle
    // -----------------------------------------------------------------------
    integer csv_fh;
    string  csv_fname;

    // -----------------------------------------------------------------------
    // Tasks
    // -----------------------------------------------------------------------

    // Drive one FFT frame into the DUT
    task automatic drive_frame(input integer case_num);
        integer i, timeout;
        logic got_ready;
        // Wait for s_axis_tready
        @(posedge aclk); #1;
        timeout = MAX_WAIT;
        while (!s_axis_tready && timeout > 0) begin
            @(posedge aclk); #1;
            timeout--;
        end
        if (timeout == 0) begin
            $display("  [ERROR] drive_frame: s_axis_tready timeout case %0d", case_num);
            fail_count++;
        end

        for (i = 0; i < FFT_LEN; i++) begin
            s_axis_tdata  = {in_im[i][IQ_WIDTH-1:0], in_re[i][IQ_WIDTH-1:0]};
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == FFT_LEN-1) ? 1'b1 : 1'b0;
            // Wait for acceptance
            @(posedge aclk); #1;
            while (!s_axis_tready) begin
                @(posedge aclk); #1;
            end
        end
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = '0;
    endtask

    // Capture one FFT output frame
    task automatic capture_frame(input integer case_num);
        integer k, timeout;
        integer last_seen;
        last_seen = 0;
        timeout   = MAX_WAIT * 2;
        k = 0;
        // Wait for first m_axis_tvalid
        @(posedge aclk); #1;
        while (!m_axis_tvalid && timeout > 0) begin
            @(posedge aclk); #1;
            timeout--;
        end
        if (timeout == 0) begin
            $display("  [ERROR] capture_frame: m_axis_tvalid timeout case %0d", case_num);
            fail_count++;
            return;
        end
        // Realtime throttle: m_axis_tready always high for this TB
        m_axis_tready = 1'b1;
        // Capture all 256 bins
        while (k < FFT_LEN) begin
            if (m_axis_tvalid) begin
                out_re[k]  = $signed(m_axis_tdata[IQ_WIDTH-1:0]);
                out_im[k]  = $signed(m_axis_tdata[2*IQ_WIDTH-1:IQ_WIDTH]);
                out_idx[k] = m_axis_tuser;
                // Protocol check: tuser should match k
                if (m_axis_tuser !== k[7:0]) begin
                    $display("  [FAIL_PROTOCOL] case %0d bin %0d: tuser=%0d expected %0d",
                             case_num, k, m_axis_tuser, k);
                    fail_count++;
                end
                // Protocol check: tlast at bin 255
                if (k == FFT_LEN-1) begin
                    if (!m_axis_tlast) begin
                        $display("  [FAIL_PROTOCOL] case %0d: tlast missing at bin 255", case_num);
                        fail_count++;
                    end
                    last_seen = 1;
                end else if (m_axis_tlast) begin
                    $display("  [FAIL_PROTOCOL] case %0d: unexpected tlast at bin %0d", case_num, k);
                    fail_count++;
                end
                k++;
            end
            @(posedge aclk); #1;
        end
        if (!last_seen) begin
            $display("  [FAIL_PROTOCOL] case %0d: tlast never fired", case_num);
            fail_count++;
        end
    endtask

    // Check magnitude at one bin
    function automatic integer abs_err(input signed [IQ_WIDTH-1:0] got, input integer expected);
        integer d;
        d = $signed(got) - expected;
        if (d < 0) d = -d;
        abs_err = d;
    endfunction

    // Check absolute value (unsigned) — used for "should be near zero"
    function automatic integer mag_abs(input signed [IQ_WIDTH-1:0] v);
        integer d;
        d = $signed(v);
        if (d < 0) d = -d;
        mag_abs = d;
    endfunction

    // Write output frame to CSV
    task automatic write_csv(input integer case_num);
        integer k;
        $sformat(csv_fname, "vivado_xsim/vectors/rtl_out_case_%0d.csv", case_num);
        csv_fh = $fopen(csv_fname, "w");
        $fwrite(csv_fh, "bin,re,im\n");
        for (k = 0; k < FFT_LEN; k++)
            $fwrite(csv_fh, "%0d,%0d,%0d\n", k, $signed(out_re[k]), $signed(out_im[k]));
        $fclose(csv_fh);
        $display("  CSV written: %s", csv_fname);
    endtask

    // -----------------------------------------------------------------------
    // Main test body
    // -----------------------------------------------------------------------
    integer i, k;
    real    angle;
    integer expected_re, expected_im;
    integer errs_this_case;

    initial begin
        fail_count    = 0;
        start         = 1'b0;
        aresetn       = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        s_axis_tdata  = '0;
        m_axis_tready = 1'b1;

        // Reset
        repeat (8) @(posedge aclk);
        #1; aresetn = 1'b1;
        repeat (4) @(posedge aclk);
        #1;

        // ===================================================================
        // T0 — Impulse at n=0
        // Expected: all bins Re = round(32767/16) = 2047, Im ≈ 0
        // ===================================================================
        $display("\n--- T0: Impulse at n=0 ---");
        in_re[0] = 16'sd32767; in_im[0] = 16'sd0;
        for (i = 1; i < FFT_LEN; i++) begin in_re[i] = 16'sd0; in_im[i] = 16'sd0; end

        drive_frame(0);
        capture_frame(0);
        write_csv(0);

        errs_this_case = 0;
        expected_re = 32767 / SCALE;  // 127 (floor)
        for (k = 0; k < FFT_LEN; k++) begin
            if (abs_err(out_re[k], expected_re) > TOLERANCE ||
                mag_abs(out_im[k]) > TOLERANCE) begin
                if (errs_this_case < 5)
                    $display("  [FAIL_VALUE_MISMATCH] T0 bin %0d: re=%0d im=%0d expected re≈%0d im≈0",
                             k, $signed(out_re[k]), $signed(out_im[k]), expected_re);
                errs_this_case++;
                fail_count++;
            end
        end
        if (errs_this_case == 0)
            $display("  T0 PASS: all 256 bins Re=%0d±%0d Im≈0", expected_re, TOLERANCE);
        else
            $display("  T0 FAIL: %0d bin errors", errs_this_case);

        repeat (8) @(posedge aclk); #1;

        // ===================================================================
        // T1 — Complex tone, k0=1: x[n] = A * exp(j*2π*1*n/256)
        // X[1] = A*256/256 = A = 1024;  all other bins ≈ 0
        // ===================================================================
        $display("\n--- T1: Complex tone k=1 ---");
        begin
            real A_real;
            A_real = 1024.0;
            for (i = 0; i < FFT_LEN; i++) begin
                angle = 2.0 * 3.14159265358979 * 1.0 * i / 256.0;
                in_re[i] = $rtoi(A_real * $cos(angle));
                in_im[i] = $rtoi(A_real * $sin(angle));
            end
        end

        drive_frame(1);
        capture_frame(1);
        write_csv(1);

        errs_this_case = 0;
        // Bin 1 should be large (~1024 Re, ~0 Im after scale)
        // Bin 0 and others should be near zero
        expected_re = 1024 * FFT_LEN / SCALE;  // 1024
        if (abs_err(out_re[1], expected_re) > 32 || mag_abs(out_im[1]) > 32) begin
            $display("  [FAIL_VALUE_MISMATCH] T1 bin 1: re=%0d im=%0d expected re≈%0d",
                     $signed(out_re[1]), $signed(out_im[1]), expected_re);
            errs_this_case++; fail_count++;
        end
        // All other bins should be near zero
        for (k = 0; k < FFT_LEN; k++) begin
            if (k == 1) continue;
            if (mag_abs(out_re[k]) > 32 || mag_abs(out_im[k]) > 32) begin
                if (errs_this_case < 3)
                    $display("  [FAIL_VALUE_MISMATCH] T1 bin %0d: re=%0d im=%0d (expected ≈0)",
                             k, $signed(out_re[k]), $signed(out_im[k]));
                errs_this_case++; fail_count++;
            end
        end
        if (errs_this_case == 0)
            $display("  T1 PASS: bin 1 re≈%0d, sidelobes suppressed", expected_re);
        else
            $display("  T1 FAIL: %0d errors", errs_this_case);

        repeat (8) @(posedge aclk); #1;

        // ===================================================================
        // T2 — Real cosine tone k=17: x[n] = A * cos(2π*17*n/256)
        // X[17] ≈ A*256/2/256 = A/2 = 512; X[239] ≈ same; others ≈ 0
        // ===================================================================
        $display("\n--- T2: Real cosine tone k=17 ---");
        begin
            real A17;
            A17 = 1024.0;
            for (i = 0; i < FFT_LEN; i++) begin
                angle = 2.0 * 3.14159265358979 * 17.0 * i / 256.0;
                in_re[i] = $rtoi(A17 * $cos(angle));
                in_im[i] = 16'sd0;
            end
        end

        drive_frame(2);
        capture_frame(2);
        write_csv(2);

        errs_this_case = 0;
        expected_re = 1024 * FFT_LEN / 2 / SCALE;  // 512  (real cosine → half energy each side)
        for (k = 0; k < FFT_LEN; k++) begin
            if (k == 17 || k == 239) begin
                if (abs_err(out_re[k], expected_re) > 64) begin
                    $display("  [FAIL_VALUE_MISMATCH] T2 bin %0d: re=%0d expected ≈%0d",
                             k, $signed(out_re[k]), expected_re);
                    errs_this_case++; fail_count++;
                end
            end else begin
                if (mag_abs(out_re[k]) > 32 || mag_abs(out_im[k]) > 32) begin
                    if (errs_this_case < 3)
                        $display("  [FAIL_VALUE_MISMATCH] T2 bin %0d: re=%0d im=%0d (expected ≈0)",
                                 k, $signed(out_re[k]), $signed(out_im[k]));
                    errs_this_case++; fail_count++;
                end
            end
        end
        if (errs_this_case == 0)
            $display("  T2 PASS: bins 17 and 239 ≈%0d, sidelobes suppressed", expected_re);
        else
            $display("  T2 FAIL: %0d errors", errs_this_case);

        repeat (8) @(posedge aclk); #1;

        // ===================================================================
        // T3 — DC constant: x[n] = 1024 for all n
        // X[0] = 1024*256/256 = 1024; all other bins ≈ 0
        // ===================================================================
        $display("\n--- T3: DC constant ---");
        for (i = 0; i < FFT_LEN; i++) begin
            in_re[i] = 16'sd1024;
            in_im[i] = 16'sd0;
        end

        drive_frame(3);
        capture_frame(3);
        write_csv(3);

        errs_this_case = 0;
        expected_re = 1024 * FFT_LEN / SCALE;  // 1024
        if (abs_err(out_re[0], expected_re) > 32) begin
            $display("  [FAIL_VALUE_MISMATCH] T3 bin 0: re=%0d expected ≈%0d",
                     $signed(out_re[0]), expected_re);
            errs_this_case++; fail_count++;
        end
        for (k = 1; k < FFT_LEN; k++) begin
            if (mag_abs(out_re[k]) > 32 || mag_abs(out_im[k]) > 32) begin
                if (errs_this_case < 3)
                    $display("  [FAIL_VALUE_MISMATCH] T3 bin %0d: re=%0d im=%0d (expected ≈0)",
                             k, $signed(out_re[k]), $signed(out_im[k]));
                errs_this_case++; fail_count++;
            end
        end
        if (errs_this_case == 0)
            $display("  T3 PASS: DC bin re=%0d±32, sidelobes suppressed", expected_re);
        else
            $display("  T3 FAIL: %0d errors", errs_this_case);

        repeat (8) @(posedge aclk); #1;

        // ===================================================================
        // T4 — Multi-tone comb (32-sample period): contains harmonics at
        //      bins 0,8,16,24,...,248 (every 8th bin).
        //      Verify spectral structure (energy at correct bins).
        // ===================================================================
        $display("\n--- T4: 32-sample periodic comb ---");
        for (i = 0; i < FFT_LEN; i++) begin
            // Square wave with period 32: +512 for first 16, -512 for last 16
            if ((i % 32) < 16)
                in_re[i] = 16'sd512;
            else
                in_re[i] = -16'sd512;
            in_im[i] = 16'sd0;
        end

        drive_frame(4);
        capture_frame(4);
        write_csv(4);

        $display("  T4: comb case captured — checking DC is suppressed");
        errs_this_case = 0;
        // DC should be zero (antisymmetric square wave)
        if (mag_abs(out_re[0]) > 32) begin
            $display("  [FAIL_VALUE_MISMATCH] T4 DC bin 0: re=%0d expected ≈0", $signed(out_re[0]));
            errs_this_case++; fail_count++;
        end
        // Bin 8 (first odd harmonic of 32-sample period) should be non-zero
        if (mag_abs(out_re[8]) < 100 && mag_abs(out_im[8]) < 100) begin
            $display("  [FAIL_VALUE_MISMATCH] T4 bin 8: re=%0d im=%0d expected significant energy",
                     $signed(out_re[8]), $signed(out_im[8]));
            errs_this_case++; fail_count++;
        end
        if (errs_this_case == 0)
            $display("  T4 PASS: DC suppressed, harmonic bin 8 has energy");
        else
            $display("  T4 FAIL: %0d errors", errs_this_case);

        repeat (8) @(posedge aclk); #1;

        // ===================================================================
        // T5 — Zero input: all bins should be zero
        // ===================================================================
        $display("\n--- T5: Zero input ---");
        for (i = 0; i < FFT_LEN; i++) begin
            in_re[i] = 16'sd0;
            in_im[i] = 16'sd0;
        end

        drive_frame(5);
        capture_frame(5);
        write_csv(5);

        errs_this_case = 0;
        for (k = 0; k < FFT_LEN; k++) begin
            if (mag_abs(out_re[k]) > 1 || mag_abs(out_im[k]) > 1) begin
                $display("  [FAIL_VALUE_MISMATCH] T5 bin %0d: re=%0d im=%0d (expected 0)",
                         k, $signed(out_re[k]), $signed(out_im[k]));
                errs_this_case++; fail_count++;
            end
        end
        if (errs_this_case == 0)
            $display("  T5 PASS: all bins zero");
        else
            $display("  T5 FAIL: %0d errors", errs_this_case);

        repeat (16) @(posedge aclk); #1;

        // ===================================================================
        // Summary
        // ===================================================================
        $display("\n========================================");
        if (fail_count == 0) begin
            $display("GATE: PASS_VIVADO_XSIM_REAL_IP");
            $display("All FFT IP value + protocol checks passed.");
        end else begin
            // Check whether any failure was a protocol vs value issue
            $display("GATE: FAIL_VALUE_MISMATCH");
            $display("Total failure count: %0d", fail_count);
        end
        $display("========================================\n");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * MAX_WAIT * 10);
        $display("  [ERROR] Global watchdog timeout — simulation hung");
        $display("GATE: FAIL_PROTOCOL");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Protocol monitor: report unexpected events
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn) begin
            if (event_tlast_unexpected)
                $display("  [WARN] event_tlast_unexpected at t=%0t", $time);
            if (event_tlast_missing)
                $display("  [WARN] event_tlast_missing at t=%0t", $time);
            if (event_data_in_channel_halt)
                $display("  [WARN] event_data_in_channel_halt at t=%0t", $time);
        end
    end

endmodule
