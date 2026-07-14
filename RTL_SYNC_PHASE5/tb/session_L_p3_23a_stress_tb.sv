`timescale 1ns/1ps

// session_L_p3_23a_stress_tb — P3-23A Multi-Frame and Reset Stress
//
// DUT: phase3_sync_axis_dma_wrapper
//
// Tests:
//   L1  Multi-frame back-to-back (N_FRAMES_FAST=10)
//         verify: no deadlock, output_count == N*576, TLAST at beat 575 per frame
//   L2  Soft reset during frame acquisition (after 300 of 704 input samples)
//         verify: DUT recovers; next full frame completes with correct output and TLAST
//   L3  Soft reset during replay correction (after REPLAY_RESET_AT M_AXIS beats)
//         verify: DUT recovers; next full frame completes with correct output and TLAST
//   L4  Enable toggle mid-stimulus (disable at samples TOGGLE_AT_0 and TOGGLE_AT_1)
//         verify: no lockup; frame eventually completes; correct output count and TLAST
//
// All tests verified back-to-back in one simulation run.
// Hard reset between tests to ensure clean state.
//
// Gate: STRESS_GATE: PASS  — all 23 checks pass
//       STRESS_GATE: FAIL  — any check fails
//
// Simulator: iverilog -g2012    Watchdog: 2500000 cycles (~20 frames)
//
// AXI-Lite CONTROL register (0x04):
//   bit[0] = enable (R/W)
//   bit[1] = soft_reset_pulse (W1S; reads back 0; does NOT clear enable)

module session_L_p3_23a_stress_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer FRAME_LEN       = 2 * (NSC + CP_LEN);   // 576
    localparam integer THRESHOLD_TB    = 40000;
    localparam integer STIM_DEPTH      = 704;
    localparam integer GOLDEN_FRAME_IDX = 41;

    // L1: number of back-to-back frames
    localparam integer N_FRAMES_FAST   = 10;
    // L2: number of samples fed before the mid-acquisition soft reset
    localparam integer ACQN_RESET_AT   = 300;
    // L3: M_AXIS beats received before the mid-replay soft reset
    localparam integer REPLAY_RESET_AT = 50;
    // L4: sample indices where enable is toggled 0→1
    localparam integer TOGGLE_AT_0     = 100;
    localparam integer TOGGLE_AT_1     = 350;
    localparam integer TOGGLE_PAUSE    = 20;   // cycles held at enable=0

    // AXI-Lite addresses (from phase3_axi_lite_regs.v)
    localparam [6:0] ADDR_CONTROL     = 7'h04;
    localparam [6:0] ADDR_STATUS      = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT   = 7'h14;
    localparam [6:0] ADDR_INT_CFO_A   = 7'h44;
    localparam [6:0] ADDR_TLAST_COUNT = 7'h50;
    localparam [6:0] ADDR_ERROR_FLAGS = 7'h54;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    reg aclk;
    reg aresetn;

    initial aclk = 1'b0;
    always #5 aclk = ~aclk;   // 100 MHz

    // -----------------------------------------------------------------------
    // AXI-Lite master signals
    // -----------------------------------------------------------------------
    reg  [6:0]  m_axi_awaddr;
    reg         m_axi_awvalid;
    wire        m_axi_awready;
    reg  [31:0] m_axi_wdata;
    reg  [3:0]  m_axi_wstrb;
    reg         m_axi_wvalid;
    wire        m_axi_wready;
    wire  [1:0] m_axi_bresp;
    wire        m_axi_bvalid;
    reg         m_axi_bready;
    reg  [6:0]  m_axi_araddr;
    reg         m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire  [1:0] m_axi_rresp;
    wire        m_axi_rvalid;
    reg         m_axi_rready;

    // -----------------------------------------------------------------------
    // S_AXIS / M_AXIS
    // -----------------------------------------------------------------------
    reg  [2*IQ_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    reg                   s_axis_tlast;

    wire [2*IQ_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                  dbg_frac_m_tvalid;
    wire                  dbg_frac_m_tready;
    wire                  dbg_frac_m_tlast;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    phase3_sync_axis_dma_wrapper #(
        .IQ_WIDTH        (IQ_WIDTH),
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .THRESHOLD       (THRESHOLD_TB)
    ) u_dut (
        .aclk               (aclk),
        .aresetn            (aresetn),
        .s_axi_awaddr       (m_axi_awaddr),
        .s_axi_awvalid      (m_axi_awvalid),
        .s_axi_awready      (m_axi_awready),
        .s_axi_wdata        (m_axi_wdata),
        .s_axi_wstrb        (m_axi_wstrb),
        .s_axi_wvalid       (m_axi_wvalid),
        .s_axi_wready       (m_axi_wready),
        .s_axi_bresp        (m_axi_bresp),
        .s_axi_bvalid       (m_axi_bvalid),
        .s_axi_bready       (m_axi_bready),
        .s_axi_araddr       (m_axi_araddr),
        .s_axi_arvalid      (m_axi_arvalid),
        .s_axi_arready      (m_axi_arready),
        .s_axi_rdata        (m_axi_rdata),
        .s_axi_rresp        (m_axi_rresp),
        .s_axi_rvalid       (m_axi_rvalid),
        .s_axi_rready       (m_axi_rready),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tlast       (s_axis_tlast),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tlast       (m_axis_tlast),
        .dbg_frac_m_tdata   (dbg_frac_m_tdata),
        .dbg_frac_m_tvalid  (dbg_frac_m_tvalid),
        .dbg_frac_m_tready  (dbg_frac_m_tready),
        .dbg_frac_m_tlast   (dbg_frac_m_tlast)
    );

    // -----------------------------------------------------------------------
    // Stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // Global M_AXIS beat counters (blocking assigns — iverilog-safe)
    // -----------------------------------------------------------------------
    integer m_total_beats;       // cumulative beats across all tests
    integer m_total_tlast;       // cumulative TLAST events
    integer m_last_tlast_beat;   // m_total_beats index of most recent TLAST

    initial begin
        m_total_beats     = 0;
        m_total_tlast     = 0;
        m_last_tlast_beat = -1;
    end

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            m_total_beats = m_total_beats + 1;
            if (m_axis_tlast) begin
                m_last_tlast_beat = m_total_beats - 1;
                m_total_tlast     = m_total_tlast + 1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Cycle counter and watchdog
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge aclk) cycle_cnt = cycle_cnt + 1;

    initial begin
        wait (cycle_cnt > 2500000);
        $display("[WDG] TIMEOUT at cycle %0d", cycle_cnt);
        $display("  m_total_beats=%0d  m_total_tlast=%0d", m_total_beats, m_total_tlast);
        $display("STRESS_GATE: FAIL");
        $finish;
    end

    // -----------------------------------------------------------------------
    // AXI-Lite tasks (Session C/D/E proven pattern — sequential, no fork/join)
    // -----------------------------------------------------------------------
    reg [31:0] axi_rd_data;

    task axi_write;
        input [6:0]  addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            m_axi_awaddr  = addr;
            m_axi_awvalid = 1'b1;
            m_axi_wdata   = data;
            m_axi_wstrb   = 4'hF;
            m_axi_wvalid  = 1'b1;
            m_axi_bready  = 1'b1;
            while (!(m_axi_awready && m_axi_wready)) @(posedge aclk);
            @(posedge aclk);
            m_axi_awvalid = 1'b0;
            m_axi_wvalid  = 1'b0;
            while (!m_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
            m_axi_bready  = 1'b0;
        end
    endtask

    task axi_read;
        input [6:0] addr;
        begin
            @(posedge aclk);
            m_axi_araddr  = addr;
            m_axi_arvalid = 1'b1;
            m_axi_rready  = 1'b1;
            while (!m_axi_arready) @(posedge aclk);
            @(posedge aclk);
            m_axi_arvalid = 1'b0;
            while (!m_axi_rvalid) @(posedge aclk);
            axi_rd_data   = m_axi_rdata;
            @(posedge aclk);
            m_axi_rready  = 1'b0;
        end
    endtask

    // hard_reset_and_enable: apply aresetn=0 for 20 cycles, release, write enable=1
    task hard_reset_and_enable;
        begin
            aresetn = 1'b0;
            repeat (20) @(posedge aclk);
            aresetn = 1'b1;
            repeat (5)  @(posedge aclk);
            axi_write(ADDR_CONTROL, 32'h00000001);
            repeat (3)  @(posedge aclk);
        end
    endtask

    // soft_reset: write CTRL bit[1]=1 (pulse); enable=1 is preserved by the register.
    // Bit[1] is W1S self-clearing: dut_aresetn pulses low for 1 cycle.
    // After reset: start_armed_r fires on reset_done_w rising edge; start fires
    // automatically on the next cycle when enable=1 and DUT is idle.
    task do_soft_reset;
        begin
            axi_write(ADDR_CONTROL, 32'h00000003);  // enable=1, soft_reset=1
            repeat (5) @(posedge aclk);             // dut_aresetn cycles; start re-arms
            axi_write(ADDR_CONTROL, 32'h00000001);  // ensure enable=1, reset cleared
            repeat (3) @(posedge aclk);
        end
    endtask

    // feed_frame: present all STIM_DEPTH samples with TLAST on the last beat
    integer ff_i;
    task feed_frame;
        begin
            for (ff_i = 0; ff_i < STIM_DEPTH; ff_i = ff_i + 1) begin
                @(posedge aclk);
                s_axis_tdata  = stim_mem[ff_i];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (ff_i == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
                while (!s_axis_tready) @(posedge aclk);
            end
            @(posedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Pass/fail state
    // -----------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;

    // -----------------------------------------------------------------------
    // Per-test scratch registers
    // -----------------------------------------------------------------------
    reg [31:0] r_out_count;
    reg [31:0] r_tlast_count;
    reg [31:0] r_int_cfo_a;
    reg [31:0] r_error_flags;

    integer f;
    integer frame_beat_start;
    integer beats_before;
    integer tlast_before;
    integer exp_beat;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        // ---- signal idle state ----
        m_axi_awaddr  = 7'h00;  m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;  m_axi_wstrb   = 4'h0;  m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00;  m_axi_arvalid = 1'b0;  m_axi_rready  = 1'b0;
        s_axis_tdata  = 32'h0;  s_axis_tvalid = 1'b0;  s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;
        pass_cnt = 0;  fail_cnt = 0;
        aresetn = 1'b0;

        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ====================================================================
        // L1 — Multi-frame back-to-back (N_FRAMES_FAST = 10)
        // ====================================================================
        $display("");
        $display("=== [L1] Multi-frame (%0d frames back-to-back) ===", N_FRAMES_FAST);
        hard_reset_and_enable();

        for (f = 0; f < N_FRAMES_FAST; f = f + 1) begin
            frame_beat_start = m_total_beats;
            $display("  [L1] Frame %0d — beat_start=%0d", f + 1, frame_beat_start);
            feed_frame();
            while (m_total_beats < frame_beat_start + FRAME_LEN) @(posedge aclk);
            $display("  [L1] Frame %0d done  last_tlast_beat=%0d  expected=%0d",
                     f + 1, m_last_tlast_beat, frame_beat_start + FRAME_LEN - 1);
        end
        repeat (10) @(posedge aclk);

        axi_read(ADDR_OUT_COUNT);   r_out_count   = axi_rd_data;
        axi_read(ADDR_TLAST_COUNT); r_tlast_count = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); r_error_flags = axi_rd_data;

        $display("  [L1] total_beats=%0d  exp=%0d", m_total_beats, N_FRAMES_FAST * FRAME_LEN);
        $display("  [L1] total_tlast=%0d  exp=%0d", m_total_tlast, N_FRAMES_FAST);
        $display("  [L1] reg_out_count=0x%08h  reg_tlast=0x%08h", r_out_count, r_tlast_count);

        if (m_total_beats == N_FRAMES_FAST * FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_beat_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_beat_count (%0d vs %0d)",
                m_total_beats, N_FRAMES_FAST * FRAME_LEN);
        end

        if (m_total_tlast == N_FRAMES_FAST) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_tlast_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_tlast_count (%0d vs %0d)",
                m_total_tlast, N_FRAMES_FAST);
        end

        exp_beat = N_FRAMES_FAST * FRAME_LEN - 1;
        if (m_last_tlast_beat == exp_beat) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_last_tlast_position");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_last_tlast_position (%0d vs %0d)",
                m_last_tlast_beat, exp_beat);
        end

        if (r_out_count == N_FRAMES_FAST * FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_reg_out_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_reg_out_count (0x%08h)", r_out_count);
        end

        if (r_tlast_count == N_FRAMES_FAST) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_reg_tlast_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_reg_tlast_count (0x%08h)",
                r_tlast_count);
        end

        if (r_error_flags == 32'h0) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L1_no_error");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L1_no_error (flags=0x%08h)", r_error_flags);
        end

        // ====================================================================
        // L2 — Soft reset during frame acquisition
        //       Feed 300 of 704 samples → soft reset → feed full frame → verify
        // ====================================================================
        $display("");
        $display("=== [L2] Soft reset during acquisition (after %0d samples) ===",
                 ACQN_RESET_AT);
        hard_reset_and_enable();
        beats_before = m_total_beats;
        tlast_before = m_total_tlast;

        $display("  [L2] Feeding first %0d samples...", ACQN_RESET_AT);
        for (ff_i = 0; ff_i < ACQN_RESET_AT; ff_i = ff_i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[ff_i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = 1'b0;
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk);
        s_axis_tvalid = 1'b0;

        $display("  [L2] Asserting soft reset at cycle %0d...", cycle_cnt);
        do_soft_reset();
        $display("  [L2] Reset done at cycle %0d; feeding recovery frame...", cycle_cnt);

        feed_frame();
        while (m_total_beats < beats_before + FRAME_LEN) @(posedge aclk);
        repeat (10) @(posedge aclk);

        axi_read(ADDR_OUT_COUNT);   r_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   r_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); r_error_flags = axi_rd_data;

        $display("  [L2] beats_delta=%0d  reg_out=0x%08h  int_cfo_a=0x%08h",
                 m_total_beats - beats_before, r_out_count, r_int_cfo_a);

        if ((m_total_beats - beats_before) == FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_recovery_beat_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_recovery_beat_count (%0d vs %0d)",
                m_total_beats - beats_before, FRAME_LEN);
        end

        if ((m_total_tlast - tlast_before) == 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_recovery_tlast_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_recovery_tlast_count (%0d)",
                m_total_tlast - tlast_before);
        end

        if (m_last_tlast_beat == beats_before + FRAME_LEN - 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_recovery_tlast_position");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_recovery_tlast_position (%0d vs %0d)",
                m_last_tlast_beat, beats_before + FRAME_LEN - 1);
        end

        if (r_out_count == FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_reg_out_count_post_reset");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_reg_out_count_post_reset (0x%08h)",
                r_out_count);
        end

        if (r_int_cfo_a[0] == 1'b1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_int_cfo_applied");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_int_cfo_applied (0x%08h)", r_int_cfo_a);
        end

        if (r_error_flags == 32'h0) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L2_no_error");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L2_no_error (0x%08h)", r_error_flags);
        end

        // ====================================================================
        // L3 — Soft reset during replay correction
        //       Feed full frame → wait for REPLAY_RESET_AT M_AXIS beats → reset
        //       → feed full frame again → verify
        // ====================================================================
        $display("");
        $display("=== [L3] Soft reset during replay (after %0d M_AXIS beats) ===",
                 REPLAY_RESET_AT);
        hard_reset_and_enable();

        $display("  [L3] Feeding stimulus; waiting for %0d replay beats...", REPLAY_RESET_AT);
        // Run feed_frame in parallel with the beat watch:
        //   feed_frame delivers all 704 samples, then the DUT runs Meyr + replay.
        //   After feed_frame returns the stimulus is done; we wait for beats.
        feed_frame();
        while (m_total_beats < REPLAY_RESET_AT) @(posedge aclk);

        $display("  [L3] %0d replay beats received — asserting soft reset at cycle %0d",
                 REPLAY_RESET_AT, cycle_cnt);
        do_soft_reset();

        // Re-baseline after reset: any residual pipeline beats are now in m_total_beats.
        // The DUT's output_count register was cleared by dut_aresetn.
        beats_before = m_total_beats;
        tlast_before = m_total_tlast;
        $display("  [L3] Reset done; feeding recovery frame (beat_baseline=%0d)...",
                 beats_before);

        feed_frame();
        while (m_total_beats < beats_before + FRAME_LEN) @(posedge aclk);
        repeat (10) @(posedge aclk);

        axi_read(ADDR_OUT_COUNT);   r_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   r_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); r_error_flags = axi_rd_data;

        $display("  [L3] beats_delta=%0d  reg_out=0x%08h  int_cfo_a=0x%08h",
                 m_total_beats - beats_before, r_out_count, r_int_cfo_a);

        if ((m_total_beats - beats_before) == FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_recovery_beat_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_recovery_beat_count (%0d vs %0d)",
                m_total_beats - beats_before, FRAME_LEN);
        end

        if ((m_total_tlast - tlast_before) == 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_recovery_tlast_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_recovery_tlast_count (%0d)",
                m_total_tlast - tlast_before);
        end

        if (m_last_tlast_beat == beats_before + FRAME_LEN - 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_recovery_tlast_position");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_recovery_tlast_position (%0d vs %0d)",
                m_last_tlast_beat, beats_before + FRAME_LEN - 1);
        end

        if (r_out_count == FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_reg_out_count_post_reset");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_reg_out_count_post_reset (0x%08h)",
                r_out_count);
        end

        if (r_int_cfo_a[0] == 1'b1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_int_cfo_applied");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_int_cfo_applied (0x%08h)", r_int_cfo_a);
        end

        if (r_error_flags == 32'h0) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L3_no_error");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L3_no_error (0x%08h)", r_error_flags);
        end

        // ====================================================================
        // L4 — Enable toggle mid-stimulus
        //       Disable enable at sample TOGGLE_AT_0 (20-cycle pause), re-enable,
        //       disable again at TOGGLE_AT_1, re-enable, complete frame → verify.
        //
        // When enable=0: s_axis_tready=0, DUT pauses input, m_axis_tvalid=0.
        // The TB de-asserts s_axis_tvalid before each disable write so no
        // in-progress transaction is left dangling.
        // ====================================================================
        $display("");
        $display("=== [L4] Enable toggle (off at samples %0d and %0d, %0d-cycle pause) ===",
                 TOGGLE_AT_0, TOGGLE_AT_1, TOGGLE_PAUSE);
        hard_reset_and_enable();
        beats_before = m_total_beats;
        tlast_before = m_total_tlast;

        for (ff_i = 0; ff_i < STIM_DEPTH; ff_i = ff_i + 1) begin
            if (ff_i == TOGGLE_AT_0 || ff_i == TOGGLE_AT_1) begin
                s_axis_tvalid = 1'b0;                          // idle tvalid first
                @(posedge aclk);
                axi_write(ADDR_CONTROL, 32'h00000000);         // enable=0
                repeat (TOGGLE_PAUSE) @(posedge aclk);
                axi_write(ADDR_CONTROL, 32'h00000001);         // enable=1
                repeat (2) @(posedge aclk);
                $display("  [L4] Enable toggled at sample %0d, cycle=%0d", ff_i, cycle_cnt);
            end
            @(posedge aclk);
            s_axis_tdata  = stim_mem[ff_i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (ff_i == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        while (m_total_beats < beats_before + FRAME_LEN) @(posedge aclk);
        repeat (10) @(posedge aclk);

        axi_read(ADDR_OUT_COUNT);   r_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   r_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); r_error_flags = axi_rd_data;

        $display("  [L4] beats_delta=%0d  reg_out=0x%08h  int_cfo_a=0x%08h",
                 m_total_beats - beats_before, r_out_count, r_int_cfo_a);

        if ((m_total_beats - beats_before) == FRAME_LEN) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L4_beat_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L4_beat_count (%0d vs %0d)",
                m_total_beats - beats_before, FRAME_LEN);
        end

        if ((m_total_tlast - tlast_before) == 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L4_tlast_count");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L4_tlast_count (%0d)",
                m_total_tlast - tlast_before);
        end

        if (m_last_tlast_beat == beats_before + FRAME_LEN - 1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L4_tlast_position");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L4_tlast_position (%0d vs %0d)",
                m_last_tlast_beat, beats_before + FRAME_LEN - 1);
        end

        if (r_int_cfo_a[0] == 1'b1) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L4_int_cfo_applied");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L4_int_cfo_applied (0x%08h)", r_int_cfo_a);
        end

        if (r_error_flags == 32'h0) begin
            pass_cnt = pass_cnt + 1; $display("  [PASS] L4_no_error");
        end else begin
            fail_cnt = fail_cnt + 1; $display("  [FAIL] L4_no_error (0x%08h)", r_error_flags);
        end

        // ====================================================================
        // Gate report
        // ====================================================================
        $display("");
        $display("=== [P3-23A] STRESS SUMMARY ===");
        $display("  Total checks: %0d   PASS: %0d   FAIL: %0d",
                 pass_cnt + fail_cnt, pass_cnt, fail_cnt);
        $display("  L1 beat/TLAST continuity — %0d frames", N_FRAMES_FAST);
        $display("  L2 reset during acquisition (sample %0d)", ACQN_RESET_AT);
        $display("  L3 reset during replay (beat %0d)", REPLAY_RESET_AT);
        $display("  L4 enable toggle (samples %0d, %0d)", TOGGLE_AT_0, TOGGLE_AT_1);
        if (fail_cnt == 0)
            $display("STRESS_GATE: PASS");
        else
            $display("STRESS_GATE: FAIL (%0d checks failed)", fail_cnt);
        $finish;
    end

endmodule
