`timescale 1ns/1ps

// session_J_p3_21a_j1_meyr_sweep_tb — P3-21A J1: Integer CFO Sweep (Extended)
//
// Extends the P3-13B behavioral-DFT Meyr sweep to include k_int = ±12, ±16.
// Uses meyr_fft256_actual_integration_top with USE_BEHAVIORAL_STUB=3 (exact
// 256-pt DFT, iverilog-compatible, no Xilinx FFT IP required).
//
// Sweep: k_int ∈ {0, ±1, ±2, ±4, ±8, ±12, ±16}  (13 cases)
// Stimulus: golden/p3_21a_sweep/j1_k{tag}.mem  (frac=0, pure integer CFO)
// ROMs:     vectors/meyr_pss_fft_romhex.txt / meyr_sss_fft_romhex.txt
//
// Per-case checks:
//   peak_index == 255 + k_int
//   int_cfo    == k_int
//
// Gate output:
//   J1_GATE: PASS  — all 13 cases pass
//   J1_GATE: FAIL  — one or more cases fail

module session_J_p3_21a_j1_meyr_sweep_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    parameter integer USE_BEHAVIORAL_STUB = 3;   // behavioral DFT, iverilog
    parameter integer IQ_WIDTH    = 16;
    parameter integer NSC         = 256;
    parameter integer INDEX_WIDTH = 9;
    parameter integer SCORE_WIDTH = 64;

    localparam integer PSS_OFFSET = 96;    // SLOT_START(64) + CP_LEN(32)
    localparam integer SSS_OFFSET = 384;   // SLOT_START(64) + 2*CP_LEN + NSC

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;   // 100 MHz

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
        .s_valid          (adp_valid),
        .s_ready          (adp_ready),
        .s_symbol_sel     (adp_sym_sel),
        .s_index          (adp_index),
        .s_i              (adp_i),
        .s_q              (adp_q),
        .m_axis_tvalid    (dut_tvalid),
        .m_axis_tready    (dut_tready),
        .m_axis_tdata     (dut_tdata),
        .m_axis_tlast     (dut_tlast),
        .m_axis_symbol_sel(dut_sym_sel)
    );

    // -----------------------------------------------------------------------
    // DUT — meyr_fft256_actual_integration_top (behavioral DFT mode)
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
    // Pass/fail counters
    // -----------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

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
    // Task: load frame file and unpack PSS/SSS windows
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
    // Task: stream one 256-sample symbol through the adapter
    // -----------------------------------------------------------------------
    task stream_symbol;
        input integer sym;
        integer k;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk);
                adp_valid   = 1'b1;
                adp_sym_sel = sym[0];
                adp_index   = k[7:0];
                adp_i = $signed(sym == 0 ? pss_i_vec[k] : sss_i_vec[k]);
                adp_q = $signed(sym == 0 ? pss_q_vec[k] : sss_q_vec[k]);
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
            if (!dut_done) timed_out = 1'b1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: run one k_int case
    // -----------------------------------------------------------------------
    task run_case;
        input [127:0] label;
        input integer exp_peak;
        input integer exp_cfo;
        reg timed_out;
        begin
            $display("[J1] Case %-10s  exp_peak=%0d  exp_cfo=%0d",
                     label, exp_peak, exp_cfo);

            @(posedge aclk);
            start_r = 1'b1;
            @(posedge aclk);
            start_r = 1'b0;

            stream_symbol(0);
            stream_symbol(1);

            wait_done(timed_out);

            if (timed_out) begin
                fail_cnt = fail_cnt + 1;
                $display("[J1] FAIL  %-10s — timeout after 200K cycles", label);
            end else if (dut_error) begin
                fail_cnt = fail_cnt + 1;
                $display("[J1] FAIL  %-10s — DUT error_code=%0d", label, dut_error_code);
            end else if (dut_peak_index == exp_peak[INDEX_WIDTH-1:0] &&
                         $signed(dut_int_cfo) == $signed(exp_cfo[15:0])) begin
                pass_cnt = pass_cnt + 1;
                $display("[J1] PASS  %-10s  peak=%0d  int_cfo=%0d  score=%0d",
                         label, dut_peak_index, $signed(dut_int_cfo), dut_peak_score);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[J1] FAIL  %-10s  peak=%0d(exp %0d)  int_cfo=%0d(exp %0d)",
                         label, dut_peak_index, exp_peak,
                         $signed(dut_int_cfo), exp_cfo);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $display("");
        $display("====================================================");
        $display(" P3-21A J1: Integer CFO Sweep (Extended)");
        $display(" USE_BEHAVIORAL_STUB=%0d (behavioral DFT)", USE_BEHAVIORAL_STUB);
        $display(" Sweep: k_int ∈ {0,±1,±2,±4,±8,±12,±16}  (13 cases)");
        $display(" ROMs:  vectors/meyr_pss_fft_romhex.txt");
        $display("====================================================");
        $display("");

        pass_cnt = 0;
        fail_cnt = 0;

        // -- k_int = 0 --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp0.mem");
        run_case("k0",    255,  0);

        // -- k_int = +1, -1 --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp1.mem");
        run_case("kp1",   256,  1);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km1.mem");
        run_case("km1",   254, -1);

        // -- k_int = +2, -2 --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp2.mem");
        run_case("kp2",   257,  2);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km2.mem");
        run_case("km2",   253, -2);

        // -- k_int = +4, -4 --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp4.mem");
        run_case("kp4",   259,  4);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km4.mem");
        run_case("km4",   251, -4);

        // -- k_int = +8, -8 --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp8.mem");
        run_case("kp8",   263,  8);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km8.mem");
        run_case("km8",   247, -8);

        // -- k_int = +12, -12  (new in P3-21A) --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp12.mem");
        run_case("kp12",  267, 12);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km12.mem");
        run_case("km12",  243, -12);

        // -- k_int = +16, -16  (new in P3-21A) --
        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_kp16.mem");
        run_case("kp16",  271, 16);

        do_reset;
        load_frame_mem("golden/p3_21a_sweep/j1_km16.mem");
        run_case("km16",  239, -16);

        // ---------------------------------------------------------------
        // Gate output
        // ---------------------------------------------------------------
        $display("");
        $display("----------------------------------------------------");
        $display("J1 results: %0d passed, %0d failed (of 13 cases)",
                 pass_cnt, fail_cnt);
        if (fail_cnt == 0) begin
            $display("J1_GATE: PASS");
            $display("  Exact 256-pt DFT confirmed for k_int ∈ {0,±1,±2,±4,±8,±12,±16}.");
        end else begin
            $display("J1_GATE: FAIL");
            $display("  %0d case(s) failed — check ROMs and sweep vectors.", fail_cnt);
        end
        $display("----------------------------------------------------");
        $display("");
        $finish;
    end

endmodule
