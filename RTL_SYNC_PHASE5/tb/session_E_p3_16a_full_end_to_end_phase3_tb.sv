`timescale 1ns/1ps

// session_E_p3_16a_full_end_to_end_phase3_tb — P3-16A Full End-to-End Integrated Regression
//
// DUT: phase3_sync_axis_dma_wrapper (P3-14B)
//   Exercises the complete Phase3 pipeline in a single simulation:
//     frame detector → frac CFO correction → pss_sss_symbol_extractor
//     → Meyr integer CFO (FFT + core) → replay buffer → integer NCO/rotator
//     → M_AXIS output
//
// Stimulus: golden/phase3_iq_stimulus.mem (704 samples, k_int=0, amplitude=3000)
//   Expected: frame_index=41 (±1), slot_start=64 (±1), frac_cfo≈+0.05,
//             int_cfo=0 (peak_index=255 ±1 due to bypass FFT timing),
//             576 M_AXIS samples with TLAST at sample 575.
//
// Note on FFT: phase3_sync_top instantiates meyr_integer_cfo_fft_frontend_top,
//   which uses fft256_dual_symbol_frontend (time-domain bypass for iverilog).
//   For k_int=0 stimulus the bypass gives int_cfo=0 (correct), so all pipeline
//   stages produce valid outputs. Non-zero k_int requires the real Xilinx FFT
//   IP path (validated separately in P3-13B/C).
//
// Checks (8 total):
//   C1  frame_found          — frame_start_valid fired
//   C2  frame_index          — ∈ [40, 42]  (golden=41, ±1)
//   C3  frac_cfo_valid       — fractional CFO pipeline completed
//   C4  int_cfo_valid        — Meyr FFT + estimator pipeline completed
//   C5  int_cfo_applied      — replay started (AXI reg 0x44 = 1)
//   C6  output_count         — replay produced exactly 576 M_AXIS beats
//   C7  tlast_at_575         — first TLAST fired at beat index 575
//   C8  m_axis_continuity    — max gap in tvalid during replay < MAX_GAP_LIMIT
//
// Gate outputs:
//   INTEGRATION_GATE: PASS          — all 8 checks pass
//   INTEGRATION_GATE: PARTIAL_PASS  — C1-C4 pass (detect+Meyr OK), C5-C8 fail
//   INTEGRATION_GATE: FAIL          — C1 or C2 fail (fundamental failure)
//
// Simulator: iverilog -g2012    Watchdog: 200000 cycles

module session_E_p3_16a_full_end_to_end_phase3_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer PHASE_WIDTH     = 16;
    localparam integer INDEX_WIDTH     = 9;
    localparam integer FRAME_LEN       = 2 * (NSC + CP_LEN);   // 576

    // Stimulus amplitude = 3000 per component → use lowered threshold
    localparam integer THRESHOLD_TB = 40000;
    localparam integer STIM_DEPTH   = 704;
    localparam integer MAX_CAP      = 1024;

    // Golden expected values
    localparam integer GOLDEN_FRAME_IDX  = 41;
    localparam integer GOLDEN_SLOT_START = 64;
    localparam integer GOLDEN_PEAK_IDX   = 255;   // Meyr peak for k_int=0

    // Continuity limit: max idle cycles between M_AXIS beats during replay.
    // iq_replay_buffer_576 has 1-sample/2-cycle BRAM throughput → 1-cycle gap
    // between beats.  NCO bubble (every ~30 beats) adds at most 1 extra cycle.
    localparam integer MAX_GAP_LIMIT = 4;

    // AXI-Lite register addresses (7-bit byte addresses)
    localparam [6:0] ADDR_CONTROL     = 7'h04;
    localparam [6:0] ADDR_STATUS      = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT   = 7'h14;
    localparam [6:0] ADDR_FSV         = 7'h18;
    localparam [6:0] ADDR_FSI         = 7'h1C;
    localparam [6:0] ADDR_SLOT_IDX    = 7'h24;
    localparam [6:0] ADDR_FRAC_CFO_V  = 7'h28;
    localparam [6:0] ADDR_FRAC_CFO_P  = 7'h2C;
    localparam [6:0] ADDR_INT_CFO_V   = 7'h38;
    localparam [6:0] ADDR_INT_CFO_E   = 7'h3C;
    localparam [6:0] ADDR_INT_CFO_I   = 7'h40;
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
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    reg         m_axi_bready;
    reg  [6:0]  m_axi_araddr;
    reg         m_axi_arvalid;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
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

    // -----------------------------------------------------------------------
    // Debug tap (frac-corrected stream)
    // -----------------------------------------------------------------------
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
        .BUF_AW          (BUF_AW),
        .THRESHOLD       (THRESHOLD_TB),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH)
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
    // AXI-Lite helper tasks (sequential, no fork/join — iverilog-safe)
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

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial begin
        cycle_cnt = 0;
        forever begin
            @(posedge aclk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt > 200000) begin
                $display("WDG: TIMEOUT after 200000 cycles — pipeline did not complete");
                $display("  m_axis_out_count=%0d  latch_frame_found=%0d  latch_int_valid=%0d",
                         m_axis_out_count, latch_frame_found, latch_int_valid);
                $display("INTEGRATION_GATE: FAIL");
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // M_AXIS capture array
    // -----------------------------------------------------------------------
    integer m_axis_out_count;
    reg [31:0] m_axis_cap     [0:MAX_CAP-1];
    reg        m_axis_tlast_v [0:MAX_CAP-1];

    initial m_axis_out_count = 0;

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_out_count < MAX_CAP) begin
            m_axis_cap    [m_axis_out_count] = m_axis_tdata;
            m_axis_tlast_v[m_axis_out_count] = m_axis_tlast;
            m_axis_out_count = m_axis_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // M_AXIS continuity monitor
    //   Counts consecutive cycles where m_axis_tvalid=0 during the replay
    //   phase only.  Tracking starts on the first accepted beat and STOPS
    //   once FRAME_LEN beats have been captured, so post-replay pipeline
    //   idle time is excluded from the measurement.
    //
    //   Expected gap: iq_replay_buffer_576 has 1-sample/2-cycle BRAM throughput,
    //   giving a 1-cycle gap between every pair of output beats.  Occasional
    //   2-cycle gaps can occur when the NCO CORDIC pipeline drains a bubble
    //   (one bubble every ~30 beats due to the 2-cycle buffer stride).
    //   MAX_GAP_LIMIT=4 covers both cases with margin.
    // -----------------------------------------------------------------------
    integer m_axis_gap_cur;
    integer m_axis_gap_max;
    integer m_axis_active;

    initial begin
        m_axis_gap_cur = 0;
        m_axis_gap_max = 0;
        m_axis_active  = 0;
    end

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready)
            m_axis_active = 1;

        // Only count gaps while actively receiving the replay frame.
        // Stop once FRAME_LEN beats captured to exclude post-replay idle.
        if (m_axis_active && (m_axis_out_count < FRAME_LEN)) begin
            if (!m_axis_tvalid || !m_axis_tready) begin
                m_axis_gap_cur = m_axis_gap_cur + 1;
                if (m_axis_gap_cur > m_axis_gap_max)
                    m_axis_gap_max = m_axis_gap_cur;
            end else begin
                m_axis_gap_cur = 0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Hierarchical probe latches
    // -----------------------------------------------------------------------
    integer latch_frame_found;
    integer latch_frame_index;
    integer latch_peak_lag;
    integer latch_slot_start;
    integer latch_frac_valid;
    integer latch_frac_word;
    integer latch_int_valid;
    integer latch_int_word;
    integer latch_meyr_peak;
    integer latch_int_cfo_cycle;

    initial begin
        latch_frame_found    = 0;
        latch_frame_index    = 0;
        latch_peak_lag       = 0;
        latch_slot_start     = 0;
        latch_frac_valid     = 0;
        latch_frac_word      = 0;
        latch_int_valid      = 0;
        latch_int_word       = 0;
        latch_meyr_peak      = 0;
        latch_int_cfo_cycle  = -1;
    end

    always @(posedge aclk) begin
        if (u_dut.dut_frame_start_valid) begin
            latch_frame_found <= 1;
            latch_frame_index <= u_dut.dut_frame_start_index;
            latch_peak_lag    <= u_dut.dut_peak_index;
            latch_frac_valid  <= 1;
            latch_frac_word   <= $signed(u_dut.dut_frac_cfo_word);
        end
        if (u_dut.dut_slot_start_valid) begin
            latch_slot_start  <= u_dut.dut_slot_start_index;
        end
        if (u_dut.dut_int_cfo_valid) begin
            latch_int_valid     <= 1;
            latch_int_word      <= $signed(u_dut.dut_int_cfo_word);
            latch_meyr_peak     <= u_dut.dut_meyr_peak_index;
            latch_int_cfo_cycle <= cycle_cnt;
        end
    end

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;
    integer first_tlast_idx;

    // AXI-Lite register reads
    reg [31:0] reg_status;
    reg [31:0] reg_out_count;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_int_cfo_i;
    reg [31:0] reg_int_cfo_e;
    reg [31:0] reg_tlast_count;
    reg [31:0] reg_error_flags;

    // Per-check pass flags
    integer c1_frame_found;
    integer c2_frame_index;
    integer c3_frac_valid;
    integer c4_int_valid;
    integer c5_int_applied;
    integer c6_output_count;
    integer c7_tlast_pos;
    integer c8_continuity;
    integer checks_passed;

    initial begin
        first_tlast_idx = -1;

        // AXI-Lite master idle state
        m_axi_awaddr  = 7'h00;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;
        m_axi_wstrb   = 4'h0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        // S_AXIS idle
        s_axis_tdata  = 32'h0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        // M_AXIS sink: always ready
        m_axis_tready = 1'b1;

        // Load IQ stimulus
        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ====================================================================
        // Phase 1: Reset
        // ====================================================================
        $display("=== [P3-16A] Phase 1: Reset (20 cycles) ===");
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // ====================================================================
        // Phase 2: Enable DUT via AXI-Lite CONTROL register
        // ====================================================================
        $display("=== [P3-16A] Phase 2: Enable DUT ===");
        axi_write(ADDR_CONTROL, 32'h00000001);   // enable=1, bypass=0
        repeat (3) @(posedge aclk);

        // ====================================================================
        // Phase 3: Feed stimulus (704 IQ samples, TLAST on last beat)
        //   Each beat is {Q[15:0], I[15:0]} packed 32-bit word.
        // ====================================================================
        $display("=== [P3-16A] Phase 3: Feeding %0d IQ samples ===", STIM_DEPTH);
        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        $display("  Stimulus done. Waiting for M_AXIS completion (FRAME_LEN=%0d)...", FRAME_LEN);

        // ====================================================================
        // Phase 4: Wait for M_AXIS to deliver FRAME_LEN beats
        // ====================================================================
        while (m_axis_out_count < FRAME_LEN) @(posedge aclk);
        $display("  M_AXIS: %0d beats received at cycle %0d", m_axis_out_count, cycle_cnt);

        // Find first TLAST position
        begin : find_tlast
            integer k;
            for (k = 0; k < m_axis_out_count; k = k + 1) begin
                if (m_axis_tlast_v[k] && (first_tlast_idx < 0))
                    first_tlast_idx = k;
            end
        end

        repeat (20) @(posedge aclk);

        // ====================================================================
        // Phase 5: Read AXI-Lite status registers
        // ====================================================================
        $display("=== [P3-16A] Phase 5: Read status registers ===");
        axi_read(ADDR_STATUS);      reg_status      = axi_rd_data;
        axi_read(ADDR_OUT_COUNT);   reg_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   reg_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_INT_CFO_I);   reg_int_cfo_i   = axi_rd_data;
        axi_read(ADDR_INT_CFO_E);   reg_int_cfo_e   = axi_rd_data;
        axi_read(ADDR_TLAST_COUNT); reg_tlast_count = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); reg_error_flags = axi_rd_data;

        // ====================================================================
        // Phase 6: Evaluate checks
        // ====================================================================

        c1_frame_found = (latch_frame_found == 1)                             ? 1 : 0;
        c2_frame_index = (latch_frame_index >= GOLDEN_FRAME_IDX - 1 &&
                          latch_frame_index <= GOLDEN_FRAME_IDX + 1)          ? 1 : 0;
        c3_frac_valid  = (latch_frac_valid == 1)                              ? 1 : 0;
        c4_int_valid   = (latch_int_valid  == 1)                              ? 1 : 0;
        c5_int_applied = (reg_int_cfo_a[0] == 1'b1)                          ? 1 : 0;
        c6_output_count= (reg_out_count    == FRAME_LEN)                      ? 1 : 0;
        c7_tlast_pos   = (first_tlast_idx  == FRAME_LEN - 1)                 ? 1 : 0;
        c8_continuity  = (m_axis_gap_max   <  MAX_GAP_LIMIT)                 ? 1 : 0;

        checks_passed = c1_frame_found + c2_frame_index + c3_frac_valid +
                        c4_int_valid   + c5_int_applied + c6_output_count +
                        c7_tlast_pos   + c8_continuity;

        // ====================================================================
        // Phase 7: Report
        // ====================================================================
        $display("");
        $display("=== [P3-16A] Integrated Regression Results ===");
        $display("  Stimulus:  golden/phase3_iq_stimulus.mem (%0d samples, k_int=0)", STIM_DEPTH);
        $display("  Threshold: %0d  (amplitude=3000 stimulus)", THRESHOLD_TB);
        $display("  Cycle:     %0d", cycle_cnt);
        $display("");
        $display("  --- Frame Detection ---");
        $display("  C1  frame_found       : %0d  %s", latch_frame_found,
                 c1_frame_found ? "PASS" : "FAIL (expected 1)");
        $display("  C2  frame_index       : %0d  %s  (golden=%0d ±1)",
                 latch_frame_index, c2_frame_index ? "PASS" : "FAIL", GOLDEN_FRAME_IDX);
        $display("      peak_lag          : %0d", latch_peak_lag);
        $display("      slot_start_index  : %0d  (golden=%0d ±1)",
                 latch_slot_start, GOLDEN_SLOT_START);
        $display("");
        $display("  --- CFO Pipeline ---");
        $display("  C3  frac_cfo_valid    : %0d  %s", latch_frac_valid,
                 c3_frac_valid ? "PASS" : "FAIL");
        $display("      frac_cfo_word     : %0d", latch_frac_word);
        $display("  C4  int_cfo_valid     : %0d  %s", latch_int_valid,
                 c4_int_valid ? "PASS" : "FAIL");
        $display("      int_cfo_word      : %0d  (step for NCO)", latch_int_word);
        $display("      meyr_peak_index   : %0d  (golden=%0d ±1, bypass-FFT ±1 expected)",
                 latch_meyr_peak, GOLDEN_PEAK_IDX);
        $display("      int_cfo_valid_cyc : %0d", latch_int_cfo_cycle);
        $display("");
        $display("  --- Replay + M_AXIS ---");
        $display("  C5  int_cfo_applied   : %0d  %s  (AXI reg 0x44)",
                 reg_int_cfo_a[0], c5_int_applied ? "PASS" : "FAIL (expected 1)");
        $display("  C6  output_count      : %0d  %s  (expected %0d)",
                 reg_out_count, c6_output_count ? "PASS" : "FAIL", FRAME_LEN);
        $display("  C7  tlast_at_575      : idx=%0d  %s  (expected 575)",
                 first_tlast_idx, c7_tlast_pos ? "PASS" : "FAIL");
        $display("  C8  m_axis_continuity : max_gap=%0d  %s  (limit=%0d)",
                 m_axis_gap_max, c8_continuity ? "PASS" : "FAIL", MAX_GAP_LIMIT);
        $display("");
        $display("  --- AXI-Lite Registers ---");
        $display("  STATUS      : 0x%08X  (bit0=busy, bit1=done_seen, bit2=err_seen)",
                 reg_status);
        $display("  TLAST_COUNT : %0d  (expected 1)", reg_tlast_count);
        $display("  INT_CFO_IDX : %0d  (AXI reg 0x40, bypass-FFT ±1 expected)",
                 reg_int_cfo_i);
        $display("  ERROR_FLAGS : 0x%X  (expected 0)", reg_error_flags);
        $display("");
        $display("  Checks passed: %0d / 8", checks_passed);
        $display("");

        // Gate decision
        if (checks_passed == 8) begin
            $display("INTEGRATION_GATE: PASS");
            $display("  All 8 end-to-end regression checks passed.");
            $display("  Pipeline: frame_detect → frac_cfo → Meyr_FFT → replay → M_AXIS  OK");
        end else if (c1_frame_found && c2_frame_index && c3_frac_valid && c4_int_valid) begin
            $display("INTEGRATION_GATE: PARTIAL_PASS");
            $display("  C1-C4 passed: frame detection and Meyr CFO pipeline are functional.");
            $display("  C5-C8 issues: replay buffer or M_AXIS stream has problems.");
            if (!c5_int_applied)
                $display("  REASON: INT_CFO_APPLIED=0 — replay buffer did not start");
            if (!c6_output_count)
                $display("  REASON: OUTPUT_COUNT=%0d != 576 — replay incomplete", reg_out_count);
            if (!c7_tlast_pos)
                $display("  REASON: TLAST at idx=%0d != 575", first_tlast_idx);
            if (!c8_continuity)
                $display("  REASON: M_AXIS max gap=%0d >= %0d — stream not continuous",
                         m_axis_gap_max, MAX_GAP_LIMIT);
        end else begin
            $display("INTEGRATION_GATE: FAIL");
            if (!c1_frame_found)
                $display("  REASON: frame not detected (check THRESHOLD=%0d, stimulus, RTL)",
                         THRESHOLD_TB);
            if (!c2_frame_index)
                $display("  REASON: frame_index=%0d out of [%0d,%0d]",
                         latch_frame_index, GOLDEN_FRAME_IDX-1, GOLDEN_FRAME_IDX+1);
            if (!c3_frac_valid)
                $display("  REASON: frac_cfo_valid never fired");
            if (!c4_int_valid)
                $display("  REASON: int_cfo_valid never fired — Meyr/FFT pipeline stalled");
        end

        $finish;
    end

endmodule
