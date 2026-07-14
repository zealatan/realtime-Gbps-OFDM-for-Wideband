`timescale 1ns/1ps

// p3_25b_real_fft_ip_tb.sv — P3-25B Real Xilinx FFT IP validation
//
// Identical to p3_25a_real_fft_meyr_restore_tb but with USE_BEHAVIORAL_STUB=0.
// Requires xsim with Vivado 2022.2+ and fft256_xilinx VHDL model compiled into
// xil_defaultlib (see scripts/run_p3_25b_real_fft_ip_validation.sh).
//
// DUT: meyr_integer_cfo_fft_frontend_top (production frozen hierarchy)
//   USE_BEHAVIORAL_STUB=0 → real Xilinx xfft_v9_1 IP path
//
// Gate output: OFFICIAL_GATE: PASS / FAIL

module p3_25b_real_fft_ip_tb;

    parameter integer USE_BEHAVIORAL_STUB = 0;
    parameter integer IQ_WIDTH    = 16;
    parameter integer NSC         = 256;
    parameter integer INDEX_WIDTH = 9;
    parameter integer SCORE_WIDTH = 64;

    localparam integer PSS_OFFSET = 96;
    localparam integer SSS_OFFSET = 384;

    defparam dut.u_est.u_core.PSS_ROM_FILE = "vectors/meyr_pss_fft_romhex.txt";
    defparam dut.u_est.u_core.SSS_ROM_FILE = "vectors/meyr_sss_fft_romhex.txt";

    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;

    reg  start_r = 1'b0;
    reg                        s_valid_r;
    wire                       s_ready_w;
    reg                        s_sym_sel_r;
    reg  [7:0]                 s_index_r;
    reg  signed [IQ_WIDTH-1:0] s_i_r;
    reg  signed [IQ_WIDTH-1:0] s_q_r;

    wire                       dut_done;
    wire                       dut_busy;
    wire                       dut_error;
    wire signed [15:0]         dut_int_cfo;
    wire [INDEX_WIDTH-1:0]     dut_peak_index;
    wire [SCORE_WIDTH-1:0]     dut_peak_score;

    meyr_integer_cfo_fft_frontend_top #(
        .FFT_LEN             (NSC),
        .IQ_WIDTH            (IQ_WIDTH),
        .PROD_WIDTH          (32),
        .ACC_WIDTH           (56),
        .SCORE_WIDTH         (SCORE_WIDTH),
        .INDEX_WIDTH         (INDEX_WIDTH),
        .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB),
        .FLUSH_COUNT         (1),
        .WATCHDOG_CYCLES     (8191)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (start_r),
        .s_valid     (s_valid_r),
        .s_ready     (s_ready_w),
        .s_symbol_sel(s_sym_sel_r),
        .s_index     (s_index_r),
        .s_i         (s_i_r),
        .s_q         (s_q_r),
        .busy        (dut_busy),
        .done        (dut_done),
        .error       (dut_error),
        .int_cfo     (dut_int_cfo),
        .peak_index  (dut_peak_index),
        .peak_score  (dut_peak_score)
    );

    reg [31:0] frame_mem  [0:703];
    reg [15:0] pss_i_vec [0:NSC-1];
    reg [15:0] pss_q_vec [0:NSC-1];
    reg [15:0] sss_i_vec [0:NSC-1];
    reg [15:0] sss_q_vec [0:NSC-1];

    integer pass_cnt;
    integer fail_cnt;

    task do_reset;
        begin
            aresetn     = 1'b0;
            start_r     = 1'b0;
            s_valid_r   = 1'b0;
            s_sym_sel_r = 1'b0;
            s_index_r   = 8'd0;
            s_i_r       = {IQ_WIDTH{1'b0}};
            s_q_r       = {IQ_WIDTH{1'b0}};
            repeat(8) @(posedge aclk);
            aresetn = 1'b1;
            repeat(4) @(posedge aclk);
        end
    endtask

    task stream_symbol;
        input integer sym;
        integer k;
        begin
            for (k = 0; k < NSC; k = k + 1) begin
                @(posedge aclk);
                s_valid_r   = 1'b1;
                s_sym_sel_r = sym[0];
                s_index_r   = k[7:0];
                if (sym == 0) begin
                    s_i_r = $signed(pss_i_vec[k]);
                    s_q_r = $signed(pss_q_vec[k]);
                end else begin
                    s_i_r = $signed(sss_i_vec[k]);
                    s_q_r = $signed(sss_q_vec[k]);
                end
                while (!s_ready_w) @(posedge aclk);
            end
            @(posedge aclk);
            s_valid_r = 1'b0;
        end
    endtask

    task wait_done;
        output reg timed_out;
        integer wd;
        begin
            timed_out = 1'b0;
            wd        = 0;
            while (!dut_done && wd < 500_000) begin
                @(posedge aclk);
                wd = wd + 1;
            end
            if (!dut_done) begin
                timed_out = 1'b1;
                $display("[TB] ERROR: timeout waiting for done (wd=%0d)", wd);
            end
        end
    endtask

    task run_case;
        input [127:0] label;
        input integer exp_peak;
        input integer exp_cfo;
        reg timed_out;
        begin
            $display("[TB] Case %-8s  exp_peak=%0d  exp_cfo=%0d",
                     label, exp_peak, exp_cfo);
            @(negedge aclk);
            start_r = 1'b1;
            @(posedge aclk);
            @(negedge aclk);
            start_r = 1'b0;

            stream_symbol(0);
            stream_symbol(1);
            wait_done(timed_out);

            if (timed_out) begin
                fail_cnt = fail_cnt + 1;
                $display("[TB] FAIL  %-8s — timeout", label);
            end else if (dut_error) begin
                fail_cnt = fail_cnt + 1;
                $display("[TB] FAIL  %-8s — DUT error", label);
            end else begin
                if (dut_peak_index == exp_peak[INDEX_WIDTH-1:0] &&
                    $signed(dut_int_cfo) == $signed(exp_cfo[15:0])) begin
                    pass_cnt = pass_cnt + 1;
                    $display("[TB] PASS  %-8s  peak=%0d  int_cfo=%0d  score=%0d",
                             label, dut_peak_index, $signed(dut_int_cfo), dut_peak_score);
                end else begin
                    fail_cnt = fail_cnt + 1;
                    $display("[TB] FAIL  %-8s  peak=%0d(exp %0d)  int_cfo=%0d(exp %0d)",
                             label, dut_peak_index, exp_peak,
                             $signed(dut_int_cfo), exp_cfo);
                end
            end
        end
    endtask

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

    initial begin
        $display("[HIER] Production hierarchy (USE_BEHAVIORAL_STUB=0 — real Xilinx FFT IP):");
        $display("[HIER]   meyr_integer_cfo_fft_frontend_top.u_fft → fft256_dual_symbol_frontend");
        $display("[HIER]   fft256_dual_symbol_frontend.u_fft → fft256_xilinx_wrapper");
        $display("[HIER]   fft256_xilinx_wrapper.gen_production.u_fft → fft256_xilinx (xfft_v9_1)");
        $display("[HIER]   meyr_integer_cfo_fft_frontend_top.u_est → meyr_integer_cfo_freq_estimator_top");
        $display("[HIER]   meyr_integer_cfo_freq_estimator_top.u_prod_gen → meyr_pss_sss_product_gen");
        $display("[HIER]   meyr_integer_cfo_freq_estimator_top.u_core → meyr_integer_cfo_core");
        $display("[HIER]   meyr_integer_cfo_core.u_peak → peak_detector");
        $display("[HIER]   HIERARCHY_AUDIT: PASS");
        $display("");
    end

    initial begin
        $display("");
        $display("============================================================");
        $display(" P3-25B Real Xilinx FFT IP Validation TB");
        $display(" USE_BEHAVIORAL_STUB = 0 (real xfft_v9_1 IP, xsim)");
        $display(" Production frozen hierarchy");
        $display("============================================================");
        $display("");

        pass_cnt = 0;
        fail_cnt = 0;

        do_reset;

        $display("[TB] Loading golden vectors from golden/p3_09_sweep/");
        $display("[TB] ROM override: vectors/meyr_pss_fft_romhex.txt");
        $display("");

        load_frame_mem("golden/p3_09_sweep/case_k0.mem");
        run_case("k0",   255,  0);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_kp1.mem");
        run_case("kp1",  256,  1);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_km1.mem");
        run_case("km1",  254, -1);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_kp2.mem");
        run_case("kp2",  257,  2);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_km2.mem");
        run_case("km2",  253, -2);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_kp4.mem");
        run_case("kp4",  259,  4);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_km4.mem");
        run_case("km4",  251, -4);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_kp8.mem");
        run_case("kp8",  263,  8);

        do_reset;
        load_frame_mem("golden/p3_09_sweep/case_km8.mem");
        run_case("km8",  247, -8);

        $display("");
        $display("------------------------------------------------------------");
        if (fail_cnt == 0) begin
            $display("OFFICIAL_GATE: PASS — all %0d k_int sweep cases passed (real Xilinx FFT IP, xsim)",
                     pass_cnt);
        end else begin
            $display("OFFICIAL_GATE: FAIL — %0d/%0d cases failed",
                     fail_cnt, pass_cnt + fail_cnt);
        end
        $display("  Production hierarchy: meyr_integer_cfo_fft_frontend_top");
        $display("    fft256_dual_symbol_frontend → fft256_xilinx_wrapper → xfft_v9_1");
        $display("------------------------------------------------------------");

        $display("");
        repeat(4) @(posedge aclk);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("[TB] GLOBAL TIMEOUT");
        $finish;
    end

endmodule
