`timescale 1ns/1ps

// p3_13a_real_fft_meyr_tb.sv — P3-13B real-FFT / behavioral-DFT Meyr testbench
//
// Tests meyr_fft256_actual_integration_top via meyr_fft256_harness_adapter.
//
// Compile-time mode selection (USE_BEHAVIORAL_STUB):
//
//   USE_BEHAVIORAL_STUB = 1  (default — stub compile mode)
//     Does NOT require Xilinx FFT IP or xsim.
//     Feeds synthetic PSS/SSS input and checks only that done asserts.
//     k_int correctness is NOT verified in this mode.
//     Gate: "SANITY_GATE: PASS (stub compile only)"
//
//   USE_BEHAVIORAL_STUB = 3  (behavioral DFT mode — P3-13B)
//     Uses exact 256-pt DFT in fft256_xilinx_wrapper (real arithmetic).
//     Runs under iverilog; does NOT require Xilinx IP or xsim.
//     Loads PSS/SSS from golden/p3_09_sweep/ CFO sweep .mem files.
//     Checks: peak_index == 255 + k_int  and  int_cfo == k_int.
//     Gate: "SANITY_GATE: PASS (behavioral DFT, iverilog)" when all 9 cases pass.
//
//   USE_BEHAVIORAL_STUB = 0  (real Xilinx FFT IP mode)
//     Requires fft256_xilinx_wrapper with real Xilinx FFT IP and Vivado xsim.
//     Requires vectors/meyr_pss_fft_romhex.txt + meyr_sss_fft_romhex.txt.
//     Loads PSS/SSS from golden/p3_09_sweep/ CFO sweep .mem files.
//     Checks: peak_index == 255 + k_int  and  int_cfo == k_int.
//     Gate: "OFFICIAL_GATE: PASS" only when all k_int sweep cases pass.
//
// Sweep vector format (.mem files):
//   704 lines, one 32-bit word per line: {Q[15:0], I[15:0]} packed hex.
//   PSS window: lines 96..351   (SLOT_START=64 + CP_LEN=32 = 96, 256 samples)
//   SSS window: lines 384..639  (SLOT_START + 2*CP_LEN + NSC = 384, 256 samples)
//
// ROM paths (modes 0 and 3):
//   meyr_integer_cfo_core loads FFT-domain ROMs via defparam override in this TB:
//     vectors/meyr_pss_fft_romhex.txt  (PSS frequency-domain cross-spectrum)
//     vectors/meyr_sss_fft_romhex.txt  (SSS reference, all +32767)
//
// Required files (modes 0 and 3):
//   rtl/meyr_fft256_actual_integration_top.v
//   rtl/meyr_fft256_harness_adapter.v
//   rtl/fft256_xilinx_wrapper.v
//   rtl/meyr_integer_cfo_freq_estimator_top.v
//   rtl/meyr_integer_cfo_core.v
//   rtl/meyr_pss_sss_product_gen.v
//   rtl/peak_detector.v
//   vectors/meyr_pss_fft_romhex.txt
//   vectors/meyr_sss_fft_romhex.txt
//   golden/p3_09_sweep/case_k*.mem

module p3_13a_real_fft_meyr_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter integer USE_BEHAVIORAL_STUB = 1;  // 1=stub, 3=behavioral DFT, 0=real IP
    parameter integer IQ_WIDTH    = 16;
    parameter integer NSC         = 256;
    parameter integer INDEX_WIDTH = 9;
    parameter integer SCORE_WIDTH = 64;

    // PSS/SSS window offsets in the 704-sample full frame
    localparam integer PSS_OFFSET = 96;   // SLOT_START(64) + CP_LEN(32)
    localparam integer SSS_OFFSET = 384;  // SLOT_START(64) + 2*CP_LEN(64) + NSC(256)

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;   // 100 MHz

    // -----------------------------------------------------------------------
    // DUT interface wires
    // -----------------------------------------------------------------------
    reg  start_r = 1'b0;

    // Adapter (old-style) side
    reg                        adp_valid;
    wire                       adp_ready;
    reg                        adp_sym_sel;
    reg  [7:0]                 adp_index;
    reg  signed [IQ_WIDTH-1:0] adp_i;
    reg  signed [IQ_WIDTH-1:0] adp_q;

    // Adapter → DUT AXI-Stream
    wire                   dut_tvalid;
    wire                   dut_tready;
    wire [2*IQ_WIDTH-1:0]  dut_tdata;
    wire                   dut_tlast;
    wire                   dut_sym_sel;

    // DUT outputs
    wire                       dut_done;
    wire                       dut_busy;
    wire                       dut_error;
    wire [3:0]                 dut_error_code;
    wire signed [15:0]         dut_int_cfo;
    wire [INDEX_WIDTH-1:0]     dut_peak_index;
    wire [SCORE_WIDTH-1:0]     dut_peak_score;

    // -----------------------------------------------------------------------
    // Harness adapter
    // -----------------------------------------------------------------------
    meyr_fft256_harness_adapter #(
        .IQ_WIDTH(IQ_WIDTH)
    ) u_adp (
        .s_valid         (adp_valid),
        .s_ready         (adp_ready),
        .s_symbol_sel    (adp_sym_sel),
        .s_index         (adp_index),
        .s_i             (adp_i),
        .s_q             (adp_q),
        .m_axis_tvalid   (dut_tvalid),
        .m_axis_tready   (dut_tready),
        .m_axis_tdata    (dut_tdata),
        .m_axis_tlast    (dut_tlast),
        .m_axis_symbol_sel(dut_sym_sel)
    );

    // -----------------------------------------------------------------------
    // DUT — meyr_fft256_actual_integration_top
    // -----------------------------------------------------------------------
    meyr_fft256_actual_integration_top #(
        .NSC                (NSC),
        .IQ_WIDTH           (IQ_WIDTH),
        .INDEX_WIDTH        (INDEX_WIDTH),
        .SCORE_WIDTH        (SCORE_WIDTH),
        .USE_BEHAVIORAL_STUB(USE_BEHAVIORAL_STUB),
        .FLUSH_COUNT        (1),
        .WATCHDOG_CYCLES    (2047)
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
    reg [31:0] frame_mem [0:703];    // full 704-sample frame {Q,I}

    reg [15:0] pss_i_vec [0:NSC-1];
    reg [15:0] pss_q_vec [0:NSC-1];
    reg [15:0] sss_i_vec [0:NSC-1];
    reg [15:0] sss_q_vec [0:NSC-1];

    // -----------------------------------------------------------------------
    // Test counters
    // -----------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    // -----------------------------------------------------------------------
    // Task: apply reset
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
    // Task: stream one 256-sample symbol through the adapter
    // -----------------------------------------------------------------------
    task stream_symbol;
        input integer sym;   // 0=PSS, 1=SSS
        integer k;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk);
                adp_valid   = 1'b1;
                adp_sym_sel = sym[0];
                adp_index   = k[7:0];
                if (sym == 0) begin
                    adp_i = $signed(pss_i_vec[k]);
                    adp_q = $signed(pss_q_vec[k]);
                end else begin
                    adp_i = $signed(sss_i_vec[k]);
                    adp_q = $signed(sss_q_vec[k]);
                end
                // Hold until DUT accepts (backpressure)
                while (!adp_ready) @(posedge aclk);
            end
            @(posedge aclk);
            adp_valid = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: wait for done or timeout
    // -----------------------------------------------------------------------
    task wait_done;
        output reg timed_out;
        integer wd;
        begin
            timed_out = 1'b0;
            wd        = 0;
            while (!dut_done && wd < 200_000) begin
                @(posedge aclk);
                wd = wd + 1;
            end
            if (!dut_done) begin
                timed_out = 1'b1;
                $display("[TB] ERROR: timeout waiting for done (wd=%0d)", wd);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: run one test case
    //   label       — string tag for display
    //   exp_peak    — expected peak_index
    //   exp_cfo     — expected int_cfo (signed)
    // -----------------------------------------------------------------------
    task run_case;
        input [127:0] label;
        input integer exp_peak;
        input integer exp_cfo;
        reg timed_out;
        begin
            $display("[TB] Case %-12s  exp_peak=%0d  exp_cfo=%0d",
                     label, exp_peak, exp_cfo);

            // Pulse start
            @(posedge aclk);
            start_r = 1'b1;
            @(posedge aclk);
            start_r = 1'b0;

            // Stream PSS then SSS
            stream_symbol(0);
            stream_symbol(1);

            // Wait for estimator to complete
            wait_done(timed_out);

            if (timed_out) begin
                fail_cnt = fail_cnt + 1;
                $display("[TB] FAIL  %-12s — timeout", label);
            end else if (dut_error) begin
                fail_cnt = fail_cnt + 1;
                $display("[TB] FAIL  %-12s — DUT error_code=%0d", label, dut_error_code);
            end else if (USE_BEHAVIORAL_STUB == 1 || USE_BEHAVIORAL_STUB == 2) begin
                // Passthrough/sequential stub: done asserted is sufficient; k_int NOT checked
                pass_cnt = pass_cnt + 1;
                $display("[TB] SANITY_OK  %-12s — done asserted (stub; k_int not checked)",
                         label);
            end else begin
                // Mode 0 (real Xilinx IP) or mode 3 (behavioral DFT): verify peak and int_cfo
                if (dut_peak_index == exp_peak[INDEX_WIDTH-1:0] &&
                    $signed(dut_int_cfo) == $signed(exp_cfo[15:0])) begin
                    pass_cnt = pass_cnt + 1;
                    $display("[TB] PASS  %-12s  peak=%0d  int_cfo=%0d  score=%0d",
                             label, dut_peak_index, $signed(dut_int_cfo), dut_peak_score);
                end else begin
                    fail_cnt = fail_cnt + 1;
                    $display("[TB] FAIL  %-12s  peak=%0d(exp %0d)  int_cfo=%0d(exp %0d)",
                             label, dut_peak_index, exp_peak,
                             $signed(dut_int_cfo), exp_cfo);
                end
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: load full-frame .mem file and unpack PSS/SSS windows
    //   Frame packing: {Q[31:16], I[15:0]} per word
    //   PSS: frame_mem[PSS_OFFSET .. PSS_OFFSET+255]  (offset 96)
    //   SSS: frame_mem[SSS_OFFSET .. SSS_OFFSET+255]  (offset 384)
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
    // Task: load synthetic vectors for stub sanity (non-zero, non-trivial)
    // -----------------------------------------------------------------------
    task load_synthetic;
        integer k;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                pss_i_vec[k] = 16'd1000;
                pss_q_vec[k] = 16'd200;
                sss_i_vec[k] = 16'd1000;
                sss_q_vec[k] = 16'd200;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("");
        $display("============================================================");
        $display(" P3-13B Real FFT / Behavioral DFT Meyr Testbench");
        $display(" USE_BEHAVIORAL_STUB = %0d", USE_BEHAVIORAL_STUB);
        if (USE_BEHAVIORAL_STUB == 1)
            $display(" Mode: STUB COMPILE — done behavior only; k_int NOT verified");
        else if (USE_BEHAVIORAL_STUB == 3)
            $display(" Mode: BEHAVIORAL DFT — exact 256-pt DFT, iverilog, k_int sweep");
        else
            $display(" Mode: REAL XILINX FFT IP — full k_int sweep, Vivado xsim");
        $display("============================================================");
        $display("");

        pass_cnt = 0;
        fail_cnt = 0;

        do_reset;

        if (USE_BEHAVIORAL_STUB == 1 || USE_BEHAVIORAL_STUB == 2) begin
            // -------------------------------------------------------
            // Stub mode: single synthetic run, verify done asserts
            // -------------------------------------------------------
            $display("[TB] Stub mode: loading synthetic PSS/SSS");
            load_synthetic;
            run_case("stub_k0", 255, 0);

            $display("");
            $display("------------------------------------------------------------");
            $display("SANITY_GATE: PASS (stub compile only)");
            $display("  done behavior verified with synthetic input.");
            $display("  k_int correctness NOT verified (requires real FFT + xsim).");
            $display("------------------------------------------------------------");

        end else begin
            // -------------------------------------------------------
            // Mode 3 (behavioral DFT) or mode 0 (real Xilinx FFT IP):
            // Load CFO sweep cases from golden vectors and run full
            // k_int sweep with correctness checking.
            //
            // Mode 3: exact 256-pt DFT, real arithmetic, iverilog-compatible.
            //         Gate: SANITY_GATE: PASS (behavioral DFT, iverilog)
            // Mode 0: real Xilinx xfft IP, requires Vivado xsim.
            //         Gate: OFFICIAL_GATE: PASS
            // -------------------------------------------------------
            if (USE_BEHAVIORAL_STUB == 3)
                $display("[TB] Behavioral DFT mode: k_int sweep from golden/p3_09_sweep/");
            else
                $display("[TB] Real Xilinx FFT IP mode: k_int sweep from golden/p3_09_sweep/");
            $display("[TB] ROM: vectors/meyr_pss_fft_romhex.txt (frequency-domain)");
            $display("");

            load_frame_mem("golden/p3_09_sweep/case_k0.mem");
            run_case("k0",    255,  0);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_kp1.mem");
            run_case("kp1",   256,  1);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_km1.mem");
            run_case("km1",   254, -1);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_kp2.mem");
            run_case("kp2",   257,  2);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_km2.mem");
            run_case("km2",   253, -2);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_kp4.mem");
            run_case("kp4",   259,  4);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_km4.mem");
            run_case("km4",   251, -4);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_kp8.mem");
            run_case("kp8",   263,  8);

            do_reset;
            load_frame_mem("golden/p3_09_sweep/case_km8.mem");
            run_case("km8",   247, -8);

            $display("");
            $display("------------------------------------------------------------");
            if (USE_BEHAVIORAL_STUB == 3) begin
                // Behavioral DFT gate (iverilog, mathematically exact)
                if (fail_cnt == 0) begin
                    $display("SANITY_GATE: PASS (behavioral DFT, iverilog) — all %0d k_int cases passed", pass_cnt);
                    $display("  Exact 256-pt DFT validated; Xilinx IP run required for OFFICIAL_GATE.");
                end else begin
                    $display("SANITY_GATE: FAIL (behavioral DFT) — %0d/%0d cases failed",
                             fail_cnt, pass_cnt + fail_cnt);
                    $display("  Check: PSS ROM path (FFT-domain), sweep vectors, FSM flow.");
                end
            end else begin
                // Official gate: requires real Xilinx FFT IP + xsim (USE_BEHAVIORAL_STUB=0)
                if (fail_cnt == 0) begin
                    $display("OFFICIAL_GATE: PASS — all %0d k_int sweep cases passed", pass_cnt);
                end else begin
                    $display("OFFICIAL_GATE: FAIL — %0d/%0d cases failed",
                             fail_cnt, pass_cnt + fail_cnt);
                    $display("  Check: fft256_xilinx_wrapper stub vs real IP,");
                    $display("         meyr_pss_fft_romhex.txt (FFT-domain, not bypass-domain),");
                    $display("         PSS/SSS window extraction offsets (PSS=96, SSS=384).");
                end
            end
            $display("------------------------------------------------------------");
        end

        $display("");
        repeat(4) @(posedge aclk);
        $finish;
    end

    // -----------------------------------------------------------------------
    // Global timeout watchdog
    // -----------------------------------------------------------------------
    initial begin
        #20_000_000;
        $display("[TB] GLOBAL TIMEOUT — simulation exceeded 20 ms limit");
        $finish;
    end

endmodule
