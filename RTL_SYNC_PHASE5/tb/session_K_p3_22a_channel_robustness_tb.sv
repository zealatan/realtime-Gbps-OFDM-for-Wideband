`timescale 1ns/1ps

// session_K_p3_22a_channel_robustness_tb — P3-22A Channel Robustness
//
// DUT: phase3_sync_axis_dma_wrapper
// Purpose: drive a channel-impaired IQ stimulus (AWGN or multipath), measure
//   frame_found, frame drift, peak drift, and replay completion.
//
// Stimulus file:
//   Selected at compile time via the STIM_FILE macro.
//   The runner generates a tiny include file per test case:
//     `define STIM_FILE "golden/p3_22a/<case>.mem"
//   Default (no override): falls back to the clean golden stimulus.
//
// Checks (5 total; wider tolerances than Session E to accommodate channel):
//   C1  frame_found          — frame_start_valid fired
//   C2  frame_index          — |frame_index − 41| ≤ FRAME_IDX_TOLERANCE (5)
//   C3  frac_cfo_valid       — fractional CFO pipeline completed
//   C4  int_cfo_applied      — replay completed (AXI reg 0x44 = 1)
//   C5  output_count         — 576 M_AXIS beats produced
//
// Gate outputs (exactly one emitted per simulation):
//   CASE_PASS          — C1-C5 all pass
//   CASE_PARTIAL_PASS  — C1-C3 pass, C4-C5 fail (detect + frac OK, replay stalled)
//   CASE_FAIL          — C1 fails (no frame) or C2 fails (frame badly drifted)
//
// Machine-readable RESULT line (always printed before gate):
//   RESULT frame_found=N frame_idx=N frame_drift=N peak_lag=N peak_drift=N
//          slot_start=N frac_valid=N int_valid=N int_applied=N
//          out_count=N tlast_ok=N
//
// Simulator: iverilog -g2012    Watchdog: 200000 cycles

`ifndef STIM_FILE
  `define STIM_FILE "golden/phase3_iq_stimulus.mem"
`endif

module session_K_p3_22a_channel_robustness_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH         = 16;
    localparam integer NSC              = 256;
    localparam integer CP_LEN           = 32;
    localparam integer BUF_AW           = 12;
    localparam integer NCO_PHASE_WIDTH  = 32;
    localparam integer FRAME_LEN        = 2 * (NSC + CP_LEN);  // 576
    localparam integer THRESHOLD_TB     = 40000;
    localparam integer STIM_DEPTH       = 704;
    localparam integer MAX_CAP          = 1024;

    // Golden expected values (clean k_int=0 stimulus)
    localparam integer GOLDEN_FRAME_IDX  = 41;
    localparam integer GOLDEN_PEAK_LAG   = 23;
    localparam integer GOLDEN_SLOT_START = 64;

    // Channel-tolerant thresholds (wider than Session E ±1)
    localparam integer FRAME_IDX_TOLERANCE = 5;   // |frame_index − 41| ≤ 5
    localparam integer MAX_GAP_LIMIT       = 4;

    // AXI-Lite register addresses (byte-addressed, 7-bit)
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
    // AXI-Lite helper tasks (sequential, iverilog-safe — no fork/join)
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
    initial cycle_cnt = 0;
    always @(posedge aclk) cycle_cnt = cycle_cnt + 1;

    initial begin
        forever begin
            @(posedge aclk);
            if (cycle_cnt > 200000) begin
                $display("WDG: TIMEOUT at 200000 cycles");
                $display("  frame_found=%0d  int_cfo_valid=%0d  out_count=%0d",
                         latch_frame_found, latch_int_valid, m_axis_out_count);
                if (!latch_frame_found)
                    $display("  REASON: frame not detected (noise floor may exceed threshold=%0d)", THRESHOLD_TB);
                else if (!latch_int_valid)
                    $display("  REASON: int_cfo_valid never fired (Meyr/FFT pipeline stall)");
                else
                    $display("  REASON: replay did not complete within timeout");
                $display("RESULT frame_found=%0d frame_idx=%0d frame_drift=%0d peak_lag=%0d peak_drift=%0d slot_start=%0d frac_valid=%0d int_valid=%0d int_applied=0 out_count=%0d tlast_ok=0",
                         latch_frame_found, latch_frame_index,
                         latch_frame_index - GOLDEN_FRAME_IDX,
                         latch_peak_lag, latch_peak_lag - GOLDEN_PEAK_LAG,
                         latch_slot_start,
                         latch_frac_valid, latch_int_valid,
                         m_axis_out_count);
                $display("CASE_FAIL");
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // M_AXIS capture
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
    // M_AXIS continuity monitor (replay phase only, same as Session E)
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

    initial begin
        latch_frame_found  = 0;
        latch_frame_index  = 0;
        latch_peak_lag     = 0;
        latch_slot_start   = 0;
        latch_frac_valid   = 0;
        latch_frac_word    = 0;
        latch_int_valid    = 0;
        latch_int_word     = 0;
        latch_meyr_peak    = 0;
    end

    always @(posedge aclk) begin
        if (u_dut.dut_frame_start_valid) begin
            latch_frame_found <= 1;
            latch_frame_index <= u_dut.dut_frame_start_index;
            latch_peak_lag    <= u_dut.dut_peak_index;
            latch_frac_valid  <= 1;
            latch_frac_word   <= $signed(u_dut.dut_frac_cfo_word);
        end
        if (u_dut.dut_slot_start_valid)
            latch_slot_start  <= u_dut.dut_slot_start_index;
        if (u_dut.dut_int_cfo_valid) begin
            latch_int_valid   <= 1;
            latch_int_word    <= $signed(u_dut.dut_int_cfo_word);
            latch_meyr_peak   <= u_dut.dut_meyr_peak_index;
        end
    end

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;
    integer first_tlast_idx;

    reg [31:0] reg_status;
    reg [31:0] reg_out_count;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_int_cfo_i;
    reg [31:0] reg_int_cfo_e;
    reg [31:0] reg_tlast_count;
    reg [31:0] reg_error_flags;

    integer c1_frame_found;
    integer c2_frame_index;
    integer c3_frac_valid;
    integer c4_int_applied;
    integer c5_output_count;
    integer checks_passed;

    integer frame_drift;
    integer peak_drift;
    integer tlast_ok;

    initial begin
        first_tlast_idx = -1;

        // AXI-Lite master idle
        m_axi_awaddr  = 7'h00;  m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;  m_axi_wstrb   = 4'h0;
        m_axi_wvalid  = 1'b0;   m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00;  m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        // S_AXIS idle
        s_axis_tdata  = 32'h0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        // M_AXIS sink: always ready
        m_axis_tready = 1'b1;

        // Load channel-impaired stimulus (macro set by runner)
        $readmemh(`STIM_FILE, stim_mem);

        // ====================================================================
        // Phase 1: Reset
        // ====================================================================
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // ====================================================================
        // Phase 2: Enable DUT
        // ====================================================================
        axi_write(ADDR_CONTROL, 32'h00000001);
        repeat (3) @(posedge aclk);

        // ====================================================================
        // Phase 3: Feed 704 IQ samples
        // ====================================================================
        $display("=== [P3-22A] Feeding %0d IQ samples  stimulus: %s ===",
                 STIM_DEPTH, `STIM_FILE);
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

        // ====================================================================
        // Phase 4: Wait for FRAME_LEN M_AXIS beats
        // ====================================================================
        while (m_axis_out_count < FRAME_LEN) @(posedge aclk);
        $display("  M_AXIS: %0d beats at cycle %0d", m_axis_out_count, cycle_cnt);

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
        frame_drift = latch_frame_index - GOLDEN_FRAME_IDX;
        peak_drift  = latch_peak_lag    - GOLDEN_PEAK_LAG;
        tlast_ok    = (first_tlast_idx  == FRAME_LEN - 1) ? 1 : 0;

        c1_frame_found  = (latch_frame_found == 1)                           ? 1 : 0;
        c2_frame_index  = ((frame_drift >= -FRAME_IDX_TOLERANCE) &&
                           (frame_drift <=  FRAME_IDX_TOLERANCE))            ? 1 : 0;
        c3_frac_valid   = (latch_frac_valid  == 1)                           ? 1 : 0;
        c4_int_applied  = (reg_int_cfo_a[0]  == 1'b1)                       ? 1 : 0;
        c5_output_count = (reg_out_count     == FRAME_LEN)                   ? 1 : 0;

        checks_passed = c1_frame_found + c2_frame_index + c3_frac_valid +
                        c4_int_applied + c5_output_count;

        // ====================================================================
        // Phase 7: Report
        // ====================================================================
        $display("");
        $display("=== [P3-22A] Channel Robustness Results ===");
        $display("  Stimulus : %s", `STIM_FILE);
        $display("  Threshold: %0d  Cycle: %0d", THRESHOLD_TB, cycle_cnt);
        $display("");
        $display("  --- Frame Detection ---");
        $display("  C1  frame_found  : %0d  %s",
                 latch_frame_found, c1_frame_found ? "PASS" : "FAIL");
        $display("  C2  frame_index  : %0d  drift=%0d  %s  (golden=%0d, tol=±%0d)",
                 latch_frame_index, frame_drift,
                 c2_frame_index ? "PASS" : "FAIL", GOLDEN_FRAME_IDX, FRAME_IDX_TOLERANCE);
        $display("      peak_lag     : %0d  drift=%0d  (golden=%0d)",
                 latch_peak_lag, peak_drift, GOLDEN_PEAK_LAG);
        $display("      slot_start   : %0d  (golden=%0d)", latch_slot_start, GOLDEN_SLOT_START);
        $display("");
        $display("  --- CFO Pipeline ---");
        $display("  C3  frac_valid   : %0d  %s  frac_word=%0d",
                 latch_frac_valid, c3_frac_valid ? "PASS" : "FAIL", latch_frac_word);
        $display("      int_valid    : %0d  int_word=%0d  meyr_peak=%0d",
                 latch_int_valid, latch_int_word, latch_meyr_peak);
        $display("");
        $display("  --- Replay + M_AXIS ---");
        $display("  C4  int_applied  : %0d  %s",
                 reg_int_cfo_a[0], c4_int_applied ? "PASS" : "FAIL");
        $display("  C5  output_count : %0d  %s  (expected %0d)",
                 reg_out_count, c5_output_count ? "PASS" : "FAIL", FRAME_LEN);
        $display("      tlast_at     : idx=%0d  %s  (expected %0d)",
                 first_tlast_idx, tlast_ok ? "OK" : "MISS", FRAME_LEN - 1);
        $display("      max_gap      : %0d  (limit=%0d)", m_axis_gap_max, MAX_GAP_LIMIT);
        $display("");
        $display("  --- AXI Registers ---");
        $display("  STATUS      : 0x%08X", reg_status);
        $display("  INT_CFO_IDX : %0d  INT_CFO_EST : 0x%08X",
                 reg_int_cfo_i, reg_int_cfo_e);
        $display("  TLAST_COUNT : %0d  ERROR_FLAGS : 0x%X",
                 reg_tlast_count, reg_error_flags);
        $display("");
        $display("  Checks passed: %0d / 5", checks_passed);
        $display("");

        // Machine-readable RESULT line (parser target in runner script)
        $display("RESULT frame_found=%0d frame_idx=%0d frame_drift=%0d peak_lag=%0d peak_drift=%0d slot_start=%0d frac_valid=%0d int_valid=%0d int_applied=%0d out_count=%0d tlast_ok=%0d",
                 latch_frame_found, latch_frame_index, frame_drift,
                 latch_peak_lag, peak_drift, latch_slot_start,
                 latch_frac_valid, latch_int_valid,
                 reg_int_cfo_a[0], reg_out_count, tlast_ok);

        // Gate decision
        if (checks_passed == 5) begin
            $display("CASE_PASS");
            $display("  All 5 channel-robustness checks passed.");
        end else if (c1_frame_found && c2_frame_index && c3_frac_valid) begin
            $display("CASE_PARTIAL_PASS");
            $display("  C1-C3 pass (detection + frac CFO OK).");
            if (!c4_int_applied)
                $display("  C4 FAIL: INT_CFO_APPLIED=0 (replay did not complete)");
            if (!c5_output_count)
                $display("  C5 FAIL: OUTPUT_COUNT=%0d != %0d", reg_out_count, FRAME_LEN);
        end else begin
            $display("CASE_FAIL");
            if (!c1_frame_found)
                $display("  REASON: frame not detected (threshold=%0d, noise may exceed threshold)", THRESHOLD_TB);
            if (c1_frame_found && !c2_frame_index)
                $display("  REASON: frame_index=%0d outside [%0d,%0d] (channel drift > tolerance)",
                         latch_frame_index,
                         GOLDEN_FRAME_IDX - FRAME_IDX_TOLERANCE,
                         GOLDEN_FRAME_IDX + FRAME_IDX_TOLERANCE);
            if (!c3_frac_valid)
                $display("  REASON: frac_cfo_valid never fired");
        end

        $finish;
    end

endmodule
