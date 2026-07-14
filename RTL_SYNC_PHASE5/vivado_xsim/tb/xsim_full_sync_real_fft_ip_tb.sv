`timescale 1ns/1ps
// xsim_full_sync_real_fft_ip_tb.sv  — XIP-004 FULL_SYNC_REAL_IP_GATE
//
// Full 5G/NR sync end-to-end with real Xilinx FFT IP (USE_BEHAVIORAL_STUB=0).
//
// DUT: phase3_sync_top — complete synchronization pipeline:
//   AXI-S 704-sample input → frame_detector → frac_cfo_frame_corrector_top
//   → pss_sss_symbol_extractor → meyr_integer_cfo_fft_frontend_top
//   (real Xilinx xfft_v9_1_8 IP) → int_cfo
//
// Stimulus: golden/p3_09_sweep/case_{k}.mem — same .mem files as XIP-003.
//   704 samples each: 64 pre-zeros + 576-sample frame + 64 post-zeros.
//   9 cases: k_int = 0, +1, -1, +2, -2, +4, -4, +8, -8
//
// Front-end expected (k_int-independent, golden from phase3_iq_stimulus_meta.json):
//   frame_start_index ∈ [40..42]   (golden = 41)
//   peak_lag          ∈ [22..24]   (golden = 23)
//   slot_start_index  ∈ [63..65]   (golden = 64)
//
// Meyr expected (k_int-dependent, formula: peak = 255 + k_int):
//   meyr_peak_index = 255 + k_int
//   int_cfo         = k_int  (decoded from NCO step word = -k_int * 2^24)
//
// Gate:
//   GATE: PASS_VIVADO_XSIM_REAL_IP — all 9 cases, all checks pass
//   GATE: FAIL                     — >=1 case failed
//
// USE_BEHAVIORAL_STUB=0 enforced via defparam (phase3_sync_top uses default=3 internally).
// THRESHOLD=40000 required for amplitude=3000 stimulus (default 10240000 is too high).

module xsim_full_sync_real_fft_ip_tb;

    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer INDEX_WIDTH     = 9;
    localparam integer PHASE_WIDTH     = 16;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer ENERGY_WIDTH    = 40;
    localparam integer N_SAMPLES       = 704;
    localparam integer THRESHOLD       = 40000;
    localparam integer WINDOW_LEN      = 25;
    localparam integer HIT_COUNT       = 10;

    // Front-end golden (k_int-independent)
    localparam integer FRAME_IDX_EXP  = 41;
    localparam integer PEAK_LAG_EXP   = 23;
    localparam integer SLOT_START_EXP = 64;

    // Override USE_BEHAVIORAL_STUB to 0 for real Xilinx FFT IP.
    // phase3_sync_top does not expose this parameter; defparam reaches into hierarchy.
    defparam dut.u_meyr_fft.USE_BEHAVIORAL_STUB = 0;
    defparam dut.u_meyr_fft.FLUSH_COUNT         = 1;
    defparam dut.u_meyr_fft.WATCHDOG_CYCLES     = 8191;
    defparam dut.u_meyr_fft.u_est.u_core.PSS_ROM_FILE = "vectors/meyr_pss_fft_romhex.txt";
    defparam dut.u_meyr_fft.u_est.u_core.SSS_ROM_FILE = "vectors/meyr_sss_fft_romhex.txt";

    // Clock
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;

    // AXI-S stimulus
    reg  [2*IQ_WIDTH-1:0] s_axis_tdata  = 32'h0;
    reg                   s_axis_tvalid = 1'b0;
    reg                   s_axis_tlast  = 1'b0;
    reg                   start_r       = 1'b0;

    // DUT port wires
    wire                        s_axis_tready;
    wire                        dut_done;
    wire                        dut_busy;
    wire                        dut_error;
    wire [3:0]                  dut_error_code;
    wire                        dut_frame_start_valid;
    wire [BUF_AW-1:0]           dut_frame_start_index;
    wire                        dut_peak_valid;
    wire [INDEX_WIDTH-1:0]      dut_peak_index;
    wire                        dut_slot_start_valid;
    wire [BUF_AW-1:0]           dut_slot_start_index;
    wire                        dut_frac_cfo_valid;
    wire [PHASE_WIDTH-1:0]      dut_frac_cfo_word;
    wire [BUF_AW-1:0]           dut_pss_start;
    wire [BUF_AW-1:0]           dut_sss_start;
    wire                        dut_int_cfo_valid;
    wire [NCO_PHASE_WIDTH-1:0]  dut_int_cfo_word;
    wire                        dut_dbg_done;
    wire [3:0]                  dut_dbg_error;
    wire [2*IQ_WIDTH-1:0]       dut_frac_m_tdata;
    wire                        dut_frac_m_tvalid;
    wire                        dut_frac_m_tready;
    wire                        dut_frac_m_tlast;
    wire [INDEX_WIDTH-1:0]      dut_meyr_peak_index;

    localparam [ENERGY_WIDTH-1:0] THRESHOLD_LP = THRESHOLD;

    phase3_sync_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .WINDOW_LEN      (WINDOW_LEN),
        .HIT_COUNT       (HIT_COUNT),
        .IQ_WIDTH        (IQ_WIDTH)
    ) dut (
        .aclk                   (aclk),
        .aresetn                (aresetn),
        .s_axis_tdata           (s_axis_tdata),
        .s_axis_tvalid          (s_axis_tvalid),
        .s_axis_tready          (s_axis_tready),
        .s_axis_tlast           (s_axis_tlast),
        .threshold_in           (THRESHOLD_LP),
        .window_len_in          (WINDOW_LEN[6:0]),
        .hit_count_in           (HIT_COUNT[3:0]),
        .start                  (start_r),
        .done                   (dut_done),
        .busy                   (dut_busy),
        .error                  (dut_error),
        .error_code             (dut_error_code),
        .dbg_frame_start_valid  (dut_frame_start_valid),
        .dbg_frame_start_index  (dut_frame_start_index),
        .dbg_peak_valid         (dut_peak_valid),
        .dbg_peak_index         (dut_peak_index),
        .dbg_slot_start_valid   (dut_slot_start_valid),
        .dbg_slot_start_index   (dut_slot_start_index),
        .dbg_frac_cfo_valid     (dut_frac_cfo_valid),
        .dbg_frac_cfo_word      (dut_frac_cfo_word),
        .dbg_pss_start          (dut_pss_start),
        .dbg_sss_start          (dut_sss_start),
        .dbg_integer_cfo_valid  (dut_int_cfo_valid),
        .dbg_integer_cfo_word   (dut_int_cfo_word),
        .dbg_done               (dut_dbg_done),
        .dbg_error_code         (dut_dbg_error),
        .dbg_frac_m_tdata       (dut_frac_m_tdata),
        .dbg_frac_m_tvalid      (dut_frac_m_tvalid),
        .dbg_frac_m_tready      (dut_frac_m_tready),
        .dbg_frac_m_tlast       (dut_frac_m_tlast),
        .dbg_meyr_peak_index    (dut_meyr_peak_index)
    );

    // Stimulus memory
    reg [31:0] stim_mem [0:N_SAMPLES-1];

    // Per-case latches (cleared in do_reset; set by always block on DUT events)
    integer latch_frame_valid;
    integer latch_frame_index;
    integer latch_peak_lag;
    integer latch_frac_valid;
    integer latch_frac_word;
    integer latch_slot_valid;
    integer latch_slot_start;
    integer latch_int_valid;
    integer latch_meyr_peak;
    integer latch_int_word;

    always @(posedge aclk) begin
        if (dut_frame_start_valid) begin
            latch_frame_valid = 1;
            latch_frame_index = dut_frame_start_index;
            latch_peak_lag    = dut_peak_index;
            latch_frac_valid  = 1;
            latch_frac_word   = $signed(dut_frac_cfo_word);
        end
        if (dut_slot_start_valid) begin
            latch_slot_valid  = 1;
            latch_slot_start  = dut_slot_start_index;
        end
        if (dut_int_cfo_valid) begin
            latch_int_valid   = 1;
            latch_meyr_peak   = dut_meyr_peak_index;
            latch_int_word    = $signed(dut_int_cfo_word);
        end
    end

    // Counters
    integer pass_cnt;
    integer fail_cnt;
    integer total_cases;

    // -------------------------------------------------------------------------
    // Tasks
    // -------------------------------------------------------------------------

    task do_reset;
        begin
            aresetn       = 1'b0;
            start_r       = 1'b0;
            s_axis_tdata  = 32'h0;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            latch_frame_valid = 0; latch_frame_index = 0;
            latch_peak_lag    = 0; latch_frac_valid  = 0;
            latch_frac_word   = 0; latch_slot_valid  = 0;
            latch_slot_start  = 0; latch_int_valid   = 0;
            latch_meyr_peak   = 0; latch_int_word    = 0;
            repeat(8) @(posedge aclk);
            aresetn = 1'b1;
            repeat(4) @(posedge aclk);
        end
    endtask

    task stream_stimulus;
        integer k;
        begin
            for (k = 0; k < N_SAMPLES; k = k + 1) begin
                @(posedge aclk); #1;
                s_axis_tdata  = stim_mem[k];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (k == N_SAMPLES - 1) ? 1'b1 : 1'b0;
                while (!s_axis_tready) begin @(posedge aclk); #1; end
            end
            @(posedge aclk); #1;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    task wait_done;
        output reg timed_out;
        integer wd;
        begin
            timed_out = 1'b0;
            wd        = 0;
            while (!dut_done && wd < 1_000_000) begin
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
        input [255:0] mem_file;
        input integer exp_k_int;
        input integer exp_peak;
        reg   timed_out;
        integer computed_int_cfo;
        integer pass_this;
        begin
            $display("[TB] Case %-8s  exp_peak=%0d  exp_cfo=%0d", label, exp_peak, exp_k_int);
            do_reset();
            $readmemh(mem_file, stim_mem, 0, N_SAMPLES-1);

            @(negedge aclk);
            start_r = 1'b1;
            @(posedge aclk); #1;
            start_r = 1'b0;

            stream_stimulus();
            wait_done(timed_out);

            // Decode int_cfo: step_word = -k_int * 2^24  =>  k_int = -step_word / 2^24
            if (latch_int_word == 0)
                computed_int_cfo = 0;
            else
                computed_int_cfo = (-latch_int_word) / 16777216;

            pass_this = 1;

            if (timed_out) begin
                pass_this = 0;
                $display("[TB] FAIL  %-8s — timeout after 1M cycles", label);
            end else if (dut_error) begin
                pass_this = 0;
                $display("[TB] FAIL  %-8s — DUT error code=0x%01X", label, dut_error_code);
            end else begin
                if (!latch_frame_valid) begin
                    $display("[TB] FAIL  %-8s — frame_start_valid never fired", label);
                    pass_this = 0;
                end
                if (latch_frame_index < FRAME_IDX_EXP - 1 ||
                    latch_frame_index > FRAME_IDX_EXP + 1) begin
                    $display("[TB] FAIL  %-8s — frame_index=%0d (exp %0d±1)",
                             label, latch_frame_index, FRAME_IDX_EXP);
                    pass_this = 0;
                end
                if (latch_peak_lag < PEAK_LAG_EXP - 1 ||
                    latch_peak_lag > PEAK_LAG_EXP + 1) begin
                    $display("[TB] FAIL  %-8s — peak_lag=%0d (exp %0d±1)",
                             label, latch_peak_lag, PEAK_LAG_EXP);
                    pass_this = 0;
                end
                if (!latch_frac_valid) begin
                    $display("[TB] FAIL  %-8s — frac_cfo_valid never fired", label);
                    pass_this = 0;
                end
                if (!latch_slot_valid) begin
                    $display("[TB] FAIL  %-8s — slot_start_valid never fired", label);
                    pass_this = 0;
                end
                if (!latch_int_valid) begin
                    $display("[TB] FAIL  %-8s — int_cfo_valid never fired", label);
                    pass_this = 0;
                end
                if (latch_meyr_peak != exp_peak) begin
                    $display("[TB] FAIL  %-8s — meyr_peak=%0d (exp %0d)",
                             label, latch_meyr_peak, exp_peak);
                    pass_this = 0;
                end
                if (computed_int_cfo != exp_k_int) begin
                    $display("[TB] FAIL  %-8s — int_cfo=%0d (exp %0d) nco_word=%0d",
                             label, computed_int_cfo, exp_k_int, latch_int_word);
                    pass_this = 0;
                end
            end

            if (pass_this) begin
                pass_cnt = pass_cnt + 1;
                $display("[TB] PASS  %-8s  frame=%0d  peak_lag=%0d  slot=%0d  frac=%0d  meyr_peak=%0d  int_cfo=%0d",
                         label, latch_frame_index, latch_peak_lag, latch_slot_start,
                         latch_frac_word, latch_meyr_peak, computed_int_cfo);
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("[TB] FAIL  %-8s  frame=%0d  peak_lag=%0d  slot=%0d  frac=%0d  meyr_peak=%0d  int_cfo=%0d",
                         label, latch_frame_index, latch_peak_lag, latch_slot_start,
                         latch_frac_word, latch_meyr_peak, computed_int_cfo);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Main
    // -------------------------------------------------------------------------
    initial begin
        pass_cnt    = 0;
        fail_cnt    = 0;
        total_cases = 0;

        $display("[TB] XIP-004 FULL_SYNC_REAL_IP_GATE");
        $display("[TB] DUT: phase3_sync_top (USE_BEHAVIORAL_STUB=0 via defparam)");
        $display("[TB] Stimulus: golden/p3_09_sweep/*.mem (9 cases, k_int=0,+/-1,+/-2,+/-4,+/-8)");
        $display("[TB] THRESHOLD=%0d  WINDOW_LEN=%0d  HIT_COUNT=%0d", THRESHOLD, WINDOW_LEN, HIT_COUNT);
        $display("");

        do_reset();

        run_case("k0",  "golden/p3_09_sweep/case_k0.mem",    0,  255); total_cases++;
        run_case("kp1", "golden/p3_09_sweep/case_kp1.mem",   1,  256); total_cases++;
        run_case("km1", "golden/p3_09_sweep/case_km1.mem",  -1,  254); total_cases++;
        run_case("kp2", "golden/p3_09_sweep/case_kp2.mem",   2,  257); total_cases++;
        run_case("km2", "golden/p3_09_sweep/case_km2.mem",  -2,  253); total_cases++;
        run_case("kp4", "golden/p3_09_sweep/case_kp4.mem",   4,  259); total_cases++;
        run_case("km4", "golden/p3_09_sweep/case_km4.mem",  -4,  251); total_cases++;
        run_case("kp8", "golden/p3_09_sweep/case_kp8.mem",   8,  263); total_cases++;
        run_case("km8", "golden/p3_09_sweep/case_km8.mem",  -8,  247); total_cases++;

        $display("");
        $display("[TB] ============================================================");
        $display("[TB] Results: %0d/%0d PASS  %0d FAIL", pass_cnt, total_cases, fail_cnt);

        if (fail_cnt == 0) begin
            $display("GATE: PASS_VIVADO_XSIM_REAL_IP (%0d/%0d cases)", pass_cnt, total_cases);
        end else begin
            $display("GATE: FAIL (%0d/%0d cases failed)", fail_cnt, total_cases);
        end
        $display("[TB] ============================================================");
        $finish;
    end

    // Global watchdog: 9 cases x 1M timeout = 9M cycles max; budget 12M (120ms @100MHz)
    initial begin
        #(120_000_000);
        $display("[TB] GLOBAL WATCHDOG — simulation hung after 120ms");
        $display("GATE: FAIL");
        $finish;
    end

endmodule
