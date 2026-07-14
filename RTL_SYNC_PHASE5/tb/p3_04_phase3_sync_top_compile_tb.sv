`timescale 1ns/1ps

// P3-04 compile-only testbench for phase3_sync_top.
//
// Purpose: verify the design elaborates cleanly and key outputs are not X/Z
// after reset.  No functional stimulus beyond idle AXIS input.
//
// Pass criterion: simulation completes 1000 cycles without $fatal.

module p3_04_phase3_sync_top_compile_tb;

    // -----------------------------------------------------------------------
    // Parameters (match phase3_sync_top defaults)
    // -----------------------------------------------------------------------
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer ACC_WIDTH       = 40;
    localparam integer METRIC_WIDTH    = 32;
    localparam integer INDEX_WIDTH     = 9;
    localparam integer RESULT_WIDTH    = 32;
    localparam integer PHASE_WIDTH     = 16;
    localparam integer POWER_WIDTH     = 33;
    localparam integer ENERGY_WIDTH    = 40;
    localparam integer WINDOW_LEN      = 25;
    localparam integer HIT_COUNT       = 10;
    localparam integer THRESHOLD       = 10240000;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer CORDIC_LATENCY  = 15;
    localparam integer IQ_WIDTH        = 16;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic                        aclk;
    logic                        aresetn;

    logic [2*IQ_WIDTH-1:0]       s_axis_tdata;
    logic                        s_axis_tvalid;
    wire                         s_axis_tready;
    logic                        s_axis_tlast;

    logic [ENERGY_WIDTH-1:0]     threshold_in;
    logic [6:0]                  window_len_in;
    logic [3:0]                  hit_count_in;

    logic                        start;
    wire                         done;
    wire                         busy;
    wire                         error;
    wire  [3:0]                  error_code;

    wire                         dbg_frame_start_valid;
    wire  [BUF_AW-1:0]           dbg_frame_start_index;
    wire                         dbg_peak_valid;
    wire  [INDEX_WIDTH-1:0]      dbg_peak_index;
    wire                         dbg_slot_start_valid;
    wire  [BUF_AW-1:0]           dbg_slot_start_index;
    wire                         dbg_frac_cfo_valid;
    wire  [PHASE_WIDTH-1:0]      dbg_frac_cfo_word;
    wire  [BUF_AW-1:0]           dbg_pss_start;
    wire  [BUF_AW-1:0]           dbg_sss_start;
    wire                         dbg_integer_cfo_valid;
    wire  [NCO_PHASE_WIDTH-1:0]  dbg_integer_cfo_word;
    wire                         dbg_done;
    wire  [3:0]                  dbg_error_code;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    phase3_sync_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .ACC_WIDTH       (ACC_WIDTH),
        .METRIC_WIDTH    (METRIC_WIDTH),
        .INDEX_WIDTH     (INDEX_WIDTH),
        .RESULT_WIDTH    (RESULT_WIDTH),
        .PHASE_WIDTH     (PHASE_WIDTH),
        .POWER_WIDTH     (POWER_WIDTH),
        .ENERGY_WIDTH    (ENERGY_WIDTH),
        .WINDOW_LEN      (WINDOW_LEN),
        .HIT_COUNT       (HIT_COUNT),
        .THRESHOLD       (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .CORDIC_LATENCY  (CORDIC_LATENCY),
        .IQ_WIDTH        (IQ_WIDTH)
    ) u_dut (
        .aclk                  (aclk),
        .aresetn               (aresetn),
        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tready         (s_axis_tready),
        .s_axis_tlast          (s_axis_tlast),
        .threshold_in          (threshold_in),
        .window_len_in         (window_len_in),
        .hit_count_in          (hit_count_in),
        .start                 (start),
        .done                  (done),
        .busy                  (busy),
        .error                 (error),
        .error_code            (error_code),
        .dbg_frame_start_valid (dbg_frame_start_valid),
        .dbg_frame_start_index (dbg_frame_start_index),
        .dbg_peak_valid        (dbg_peak_valid),
        .dbg_peak_index        (dbg_peak_index),
        .dbg_slot_start_valid  (dbg_slot_start_valid),
        .dbg_slot_start_index  (dbg_slot_start_index),
        .dbg_frac_cfo_valid    (dbg_frac_cfo_valid),
        .dbg_frac_cfo_word     (dbg_frac_cfo_word),
        .dbg_pss_start         (dbg_pss_start),
        .dbg_sss_start         (dbg_sss_start),
        .dbg_integer_cfo_valid (dbg_integer_cfo_valid),
        .dbg_integer_cfo_word  (dbg_integer_cfo_word),
        .dbg_done              (dbg_done),
        .dbg_error_code        (dbg_error_code)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Stimulus: reset then idle AXIS input for 1000 cycles
    // -----------------------------------------------------------------------
    initial begin
        // Safe idle values
        aresetn       = 1'b0;
        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        threshold_in  = THRESHOLD;
        window_len_in = WINDOW_LEN[6:0];
        hit_count_in  = HIT_COUNT[3:0];
        start         = 1'b0;

        // Hold reset for 8 clock edges
        repeat (4) @(posedge aclk);
        aresetn = 1'b1;

        // Idle for 1000 cycles
        repeat (1000) @(posedge aclk);

        // Check key outputs are not X/Z after reset
        @(posedge aclk);
        if ($isunknown(done))
            $fatal(1, "COMPILE_TB FAIL: done is X/Z after reset");
        if ($isunknown(busy))
            $fatal(1, "COMPILE_TB FAIL: busy is X/Z after reset");
        if ($isunknown(error))
            $fatal(1, "COMPILE_TB FAIL: error is X/Z after reset");
        if ($isunknown(dbg_pss_start))
            $fatal(1, "COMPILE_TB FAIL: dbg_pss_start is X/Z after reset");
        if ($isunknown(dbg_sss_start))
            $fatal(1, "COMPILE_TB FAIL: dbg_sss_start is X/Z after reset");

        // Verify constant offset outputs match expected parameter values
        if (dbg_pss_start !== BUF_AW'(CP_LEN))
            $fatal(1, "COMPILE_TB FAIL: dbg_pss_start=%0d expected %0d",
                   dbg_pss_start, CP_LEN);
        if (dbg_sss_start !== BUF_AW'(2*CP_LEN + NSC))
            $fatal(1, "COMPILE_TB FAIL: dbg_sss_start=%0d expected %0d",
                   dbg_sss_start, 2*CP_LEN + NSC);

        $display("P3-04 COMPILE_TB: elaboration and idle run PASSED");
        $display("  dbg_pss_start = %0d (expected %0d)", dbg_pss_start, CP_LEN);
        $display("  dbg_sss_start = %0d (expected %0d)", dbg_sss_start, 2*CP_LEN+NSC);
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog: prevent infinite hang
    // -----------------------------------------------------------------------
    initial begin
        #200000;
        $fatal(1, "COMPILE_TB FAIL: simulation timeout");
    end

endmodule
