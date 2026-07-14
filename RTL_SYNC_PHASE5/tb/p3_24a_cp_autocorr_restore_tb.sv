`timescale 1ns/1ps

// p3_24a_cp_autocorr_restore_tb — P3-24A CP Autocorr Restore Regression
//
// DUT: phase3_sync_axis_dma_wrapper (full Phase 3 pipeline)
// Stimulus: golden/phase3_iq_stimulus.mem (704 samples, k_int=0, amplitude=3000)
//
// Verifies that timing_sync_top (streaming_cp_autocorr adapter) produces
// the same peak_lag and downstream results as the old cp_autocorr_core path.
//
// Checks (8 total):
//   C1  frame_found    latch_frame_found == 1
//   C2  frame_index    ∈ [40, 42]   (golden=41, ±1)
//   C3  peak_lag       ∈ [22, 24]   (golden≈23, ±1)
//   C4  slot_start     ∈ [63, 65]   (golden≈64, ±1)
//   C5  frac_cfo_valid fractional CFO pipeline complete
//   C6  int_cfo_valid  Meyr estimator complete
//   C7  output_count   M_AXIS delivered exactly 4032 beats (14-symbol slot)
//   C8  tlast_at_4031  TLAST fired at beat index 4031
//
// Gate:
//   SANITY_CP_AUTOCORR_RESTORE_GATE: PASS    — all 8 checks pass
//   SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL    — one or more checks fail
//
// Simulator: iverilog -g2012    Watchdog: 1400000 cycles (scaled 7x for 4032-beat slot)

module p3_24a_cp_autocorr_restore_tb;

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
    localparam integer FRAME_LEN       = 14 * (NSC + CP_LEN);  // 4032 (14-symbol slot)

    localparam integer THRESHOLD_TB  = 40000;
    localparam integer STIM_DEPTH    = 704;

    localparam integer GOLDEN_FRAME_IDX  = 41;
    localparam integer GOLDEN_PEAK_LAG   = 23;
    localparam integer GOLDEN_SLOT_START = 64;

    // AXI-Lite register byte addresses (7-bit)
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
    // AXI-Lite master
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

    // Debug tap (frac-corrected stream) — required DUT port
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
    // AXI-Lite helper tasks
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
            if (cycle_cnt > 1400000) begin
                $display("WDG: TIMEOUT after 1400000 cycles — pipeline did not complete");
                $display("SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL");
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // M_AXIS output counter and TLAST tracker
    // -----------------------------------------------------------------------
    integer m_axis_out_count;
    integer first_tlast_idx;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_out_count <= 0;
            first_tlast_idx  <= -1;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (first_tlast_idx < 0 && m_axis_tlast)
                first_tlast_idx <= m_axis_out_count;
            m_axis_out_count <= m_axis_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Pipeline signal latches (hierarchical probes into u_dut)
    // -----------------------------------------------------------------------
    integer latch_frame_found;
    integer latch_frame_index;
    integer latch_peak_lag;
    integer latch_slot_start;
    integer latch_frac_valid;
    integer latch_int_valid;

    initial begin
        latch_frame_found = 0;
        latch_frame_index = 0;
        latch_peak_lag    = 0;
        latch_slot_start  = 0;
        latch_frac_valid  = 0;
        latch_int_valid   = 0;
    end

    always @(posedge aclk) begin
        if (u_dut.dut_frame_start_valid) begin
            latch_frame_found <= 1;
            latch_frame_index <= u_dut.dut_frame_start_index;
            latch_peak_lag    <= u_dut.dut_peak_index;
        end
        if (u_dut.dut_slot_start_valid)
            latch_slot_start  <= u_dut.dut_slot_start_index;
        if (u_dut.dut_frac_cfo_valid)
            latch_frac_valid  <= 1;
        if (u_dut.dut_int_cfo_valid)
            latch_int_valid   <= 1;
    end

    // -----------------------------------------------------------------------
    // Check registers and AXI-Lite status
    // -----------------------------------------------------------------------
    reg [31:0] reg_out_count;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_error_flags;

    integer c1_frame_found;
    integer c2_frame_index;
    integer c3_peak_lag;
    integer c4_slot_start;
    integer c5_frac_valid;
    integer c6_int_valid;
    integer c7_output_count;
    integer c8_tlast_pos;
    integer checks_passed;

    // -----------------------------------------------------------------------
    // Stimulus and verification flow
    // -----------------------------------------------------------------------
    integer i;

    initial begin
        // Initialize AXI-Lite master
        m_axi_awaddr  = 7'h0;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;
        m_axi_wstrb   = 4'h0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h0;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        s_axis_tdata  = 32'h0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;

        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ================================================================
        // Phase 1: Reset
        // ================================================================
        $display("=== [P3-24A] Phase 1: Reset (20 cycles) ===");
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // ================================================================
        // Phase 2: Enable DUT
        // ================================================================
        $display("=== [P3-24A] Phase 2: Enable DUT ===");
        axi_write(ADDR_CONTROL, 32'h00000001);
        repeat (3) @(posedge aclk);

        // ================================================================
        // Phase 3: Feed 704 IQ samples
        // ================================================================
        $display("=== [P3-24A] Phase 3: Feeding %0d IQ samples ===", STIM_DEPTH);
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
        $display("  Stimulus done. Waiting for M_AXIS (%0d beats)...", FRAME_LEN);

        // ================================================================
        // Phase 4: Wait for M_AXIS to deliver FRAME_LEN beats
        // ================================================================
        while (m_axis_out_count < FRAME_LEN) @(posedge aclk);
        $display("  M_AXIS: %0d beats at cycle %0d", m_axis_out_count, cycle_cnt);
        repeat (20) @(posedge aclk);

        // ================================================================
        // Phase 5: Read AXI-Lite status registers
        // ================================================================
        $display("=== [P3-24A] Phase 5: Read status registers ===");
        axi_read(ADDR_OUT_COUNT);   reg_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   reg_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); reg_error_flags = axi_rd_data;

        // ================================================================
        // Phase 6: Evaluate checks
        // ================================================================
        c1_frame_found  = (latch_frame_found == 1)                               ? 1 : 0;
        c2_frame_index  = (latch_frame_index >= GOLDEN_FRAME_IDX - 1 &&
                           latch_frame_index <= GOLDEN_FRAME_IDX + 1)            ? 1 : 0;
        c3_peak_lag     = (latch_peak_lag    >= GOLDEN_PEAK_LAG - 1 &&
                           latch_peak_lag    <= GOLDEN_PEAK_LAG + 1)             ? 1 : 0;
        c4_slot_start   = (latch_slot_start  >= GOLDEN_SLOT_START - 1 &&
                           latch_slot_start  <= GOLDEN_SLOT_START + 1)           ? 1 : 0;
        c5_frac_valid   = (latch_frac_valid  == 1)                               ? 1 : 0;
        c6_int_valid    = (latch_int_valid   == 1)                               ? 1 : 0;
        c7_output_count = (reg_out_count     == FRAME_LEN)                       ? 1 : 0;
        c8_tlast_pos    = (first_tlast_idx   == FRAME_LEN - 1)                  ? 1 : 0;

        checks_passed = c1_frame_found + c2_frame_index + c3_peak_lag +
                        c4_slot_start  + c5_frac_valid  + c6_int_valid +
                        c7_output_count + c8_tlast_pos;

        // ================================================================
        // Phase 7: Report
        // ================================================================
        $display("");
        $display("=== [P3-24A] CP Autocorr Restore Regression Results ===");
        $display("  Stimulus:  golden/phase3_iq_stimulus.mem (%0d samples)", STIM_DEPTH);
        $display("  Threshold: %0d  Cycle: %0d", THRESHOLD_TB, cycle_cnt);
        $display("");
        $display("  --- Frame Detection + CP Timing ---");
        $display("  C1  frame_found    : %0d  %s",
                 latch_frame_found, c1_frame_found ? "PASS" : "FAIL (expected 1)");
        $display("  C2  frame_index    : %0d  %s  (golden=%0d ±1)",
                 latch_frame_index, c2_frame_index ? "PASS" : "FAIL", GOLDEN_FRAME_IDX);
        $display("  C3  peak_lag       : %0d  %s  (golden=%0d ±1)",
                 latch_peak_lag, c3_peak_lag ? "PASS" : "FAIL", GOLDEN_PEAK_LAG);
        $display("  C4  slot_start     : %0d  %s  (golden=%0d ±1)",
                 latch_slot_start, c4_slot_start ? "PASS" : "FAIL", GOLDEN_SLOT_START);
        $display("");
        $display("  --- CFO Pipeline ---");
        $display("  C5  frac_cfo_valid : %0d  %s",
                 latch_frac_valid, c5_frac_valid ? "PASS" : "FAIL");
        $display("  C6  int_cfo_valid  : %0d  %s",
                 latch_int_valid, c6_int_valid ? "PASS" : "FAIL");
        $display("");
        $display("  --- M_AXIS Output ---");
        $display("  C7  output_count   : %0d  %s  (expected %0d)",
                 reg_out_count, c7_output_count ? "PASS" : "FAIL", FRAME_LEN);
        $display("  C8  tlast_at_4031  : idx=%0d  %s  (expected %0d)",
                 first_tlast_idx, c8_tlast_pos ? "PASS" : "FAIL", FRAME_LEN - 1);
        $display("");
        $display("  Checks passed: %0d / 8", checks_passed);
        $display("  Error flags:   0x%08h", reg_error_flags);
        $display("");

        if (checks_passed == 8) begin
            $display("SANITY_CP_AUTOCORR_RESTORE_GATE: PASS");
        end else begin
            $display("SANITY_CP_AUTOCORR_RESTORE_GATE: FAIL");
            if (!c1_frame_found)
                $display("  REASON: frame not detected");
            if (!c2_frame_index)
                $display("  REASON: frame_index=%0d out of [%0d,%0d]",
                         latch_frame_index, GOLDEN_FRAME_IDX-1, GOLDEN_FRAME_IDX+1);
            if (!c3_peak_lag)
                $display("  REASON: peak_lag=%0d out of [%0d,%0d] — streaming_cp_autocorr mismatch",
                         latch_peak_lag, GOLDEN_PEAK_LAG-1, GOLDEN_PEAK_LAG+1);
            if (!c4_slot_start)
                $display("  REASON: slot_start=%0d out of [%0d,%0d]",
                         latch_slot_start, GOLDEN_SLOT_START-1, GOLDEN_SLOT_START+1);
            if (!c5_frac_valid)
                $display("  REASON: frac_cfo_valid never fired");
            if (!c6_int_valid)
                $display("  REASON: int_cfo_valid never fired — Meyr pipeline stalled");
            if (!c7_output_count)
                $display("  REASON: output_count=%0d != %0d", reg_out_count, FRAME_LEN);
            if (!c8_tlast_pos)
                $display("  REASON: first TLAST at index %0d (expected %0d)",
                         first_tlast_idx, FRAME_LEN - 1);
        end

        $finish;
    end

endmodule
