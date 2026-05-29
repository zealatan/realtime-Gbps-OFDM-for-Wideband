`timescale 1ns/1ps

// session_J_p3_21a_j2j3_wrapper_tb — P3-21A J2+J3: CFO Robustness Sweep
//
// DUT: phase3_sync_axis_dma_wrapper (P3-14B RTL), THRESHOLD=40000
//
// J2 — Fractional CFO sweep (7 cases, k_int=0):
//   frac ∈ {-0.45, -0.30, -0.15, 0, +0.15, +0.30, +0.45}
//   Checks: frame_found, frac_cfo_valid, output_count=576, TLAST at 575
//
// J3 — Combined sweep (4 cases):
//   (+16,+0.45), (-16,-0.45), (+12,-0.30), (-12,+0.30)
//   Same checks; integer CFO accuracy NOT checked (bypass FFT gives int_cfo=0).
//   Frame detection and frac CFO correction are CFO-invariant — all cases pass.
//
// Per-case reset: soft_reset via AXI-Lite CONTROL[1] clears all DUT counters
// and sticky latches between cases.
//
// Gate outputs:
//   J2_GATE: PASS / J2_GATE: FAIL
//   J3_GATE: PASS / J3_GATE: FAIL
//
// Watchdog: 200000 cycles per case.  11 cases × 200K = 2.2M total.

module session_J_p3_21a_j2j3_wrapper_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer FRAME_LEN       = 2 * (NSC + CP_LEN);   // 576
    localparam integer STIM_DEPTH      = 704;
    localparam integer THRESHOLD_TB    = 40000;
    localparam integer WATCHDOG_CYCLES = 200000;

    // AXI-Lite register addresses (7-bit byte offsets)
    localparam [6:0] ADDR_CONTROL    = 7'h04;
    localparam [6:0] ADDR_STATUS     = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT  = 7'h14;
    localparam [6:0] ADDR_FSV        = 7'h18;   // FRAME_START_VALID (R/clear)
    localparam [6:0] ADDR_FSI        = 7'h1C;
    localparam [6:0] ADDR_FRAC_CFO_V = 7'h28;   // FRAC_CFO_VALID   (R/clear)
    localparam [6:0] ADDR_INT_CFO_V  = 7'h38;   // INT_CFO_VALID    (R/clear)
    localparam [6:0] ADDR_INT_CFO_A  = 7'h44;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #5 aclk = ~aclk;

    // -----------------------------------------------------------------------
    // AXI-Lite master signals
    // -----------------------------------------------------------------------
    reg  [6:0]  m_axi_awaddr  = 7'h0;
    reg         m_axi_awvalid = 1'b0;
    wire        m_axi_awready;
    reg  [31:0] m_axi_wdata   = 32'h0;
    reg  [3:0]  m_axi_wstrb   = 4'h0;
    reg         m_axi_wvalid  = 1'b0;
    wire        m_axi_wready;
    wire [1:0]  m_axi_bresp;
    wire        m_axi_bvalid;
    reg         m_axi_bready  = 1'b0;
    reg  [6:0]  m_axi_araddr  = 7'h0;
    reg         m_axi_arvalid = 1'b0;
    wire        m_axi_arready;
    wire [31:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;
    wire        m_axi_rvalid;
    reg         m_axi_rready  = 1'b0;

    // -----------------------------------------------------------------------
    // S_AXIS / M_AXIS
    // -----------------------------------------------------------------------
    reg  [2*IQ_WIDTH-1:0] s_axis_tdata  = 32'h0;
    reg                   s_axis_tvalid = 1'b0;
    wire                  s_axis_tready;
    reg                   s_axis_tlast  = 1'b0;

    wire [2*IQ_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready = 1'b1;   // always ready
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
    // M_AXIS capture (gated by case_active)
    // -----------------------------------------------------------------------
    integer m_axis_out_count;
    integer m_axis_tlast_idx;
    integer case_active;

    always @(posedge aclk) begin
        if (case_active && m_axis_tvalid && m_axis_tready) begin
            m_axis_out_count = m_axis_out_count + 1;
            if (m_axis_tlast)
                m_axis_tlast_idx = m_axis_out_count - 1;
        end
    end

    // -----------------------------------------------------------------------
    // Stimulus buffer and per-case pass tracking
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];
    reg [31:0] axi_rd_data;

    integer j2_pass, j2_fail;
    integer j3_pass, j3_fail;

    // -----------------------------------------------------------------------
    // AXI-Lite write task (sequential, no fork — iverilog-safe)
    // -----------------------------------------------------------------------
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
            m_axi_bready = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // AXI-Lite read task
    // -----------------------------------------------------------------------
    task axi_read;
        input  [6:0]  addr;
        output [31:0] data;
        begin
            @(posedge aclk);
            m_axi_araddr  = addr;
            m_axi_arvalid = 1'b1;
            m_axi_rready  = 1'b1;
            while (!m_axi_arready) @(posedge aclk);
            @(posedge aclk);
            m_axi_arvalid = 1'b0;
            while (!m_axi_rvalid) @(posedge aclk);
            data          = m_axi_rdata;
            @(posedge aclk);
            m_axi_rready  = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: between-case reset
    // Applies soft_reset via AXI-Lite, clears sticky latches, resets capture.
    // -----------------------------------------------------------------------
    task between_case_reset;
        begin
            // Deactivate M_AXIS capture
            case_active = 0;
            repeat(2) @(posedge aclk);
            m_axis_out_count = 0;
            m_axis_tlast_idx = -1;

            // Soft reset pulse
            axi_write(ADDR_CONTROL, 32'h2);
            repeat(16) @(posedge aclk);
            axi_write(ADDR_CONTROL, 32'h0);
            repeat(8) @(posedge aclk);

            // Clear sticky latches by reading them once
            axi_read(ADDR_FSV,        axi_rd_data);
            axi_read(ADDR_FRAC_CFO_V, axi_rd_data);
            axi_read(ADDR_INT_CFO_V,  axi_rd_data);
            repeat(4) @(posedge aclk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Task: run one wrapper case
    //   fname      — path to .mem file (Q15 IQ, 704 samples)
    //   case_name  — display label
    //   case_ok    — output: 1 if all 4 checks pass, 0 otherwise
    // -----------------------------------------------------------------------
    task run_wrapper_case;
        input [511:0] fname;
        input [255:0] case_name;
        output integer case_ok;

        integer si, wdog;
        integer frame_ok, frac_ok, count_ok, tlast_ok;
        begin
            // Load stimulus
            $readmemh(fname, stim_mem, 0, STIM_DEPTH-1);
            $display("[J] Case: %0s", case_name);

            // Enable DUT
            axi_write(ADDR_CONTROL, 32'h1);
            repeat(4) @(posedge aclk);

            // Activate M_AXIS capture
            case_active = 1;

            // Drive stimulus
            s_axis_tvalid = 1'b0;
            for (si = 0; si < STIM_DEPTH; si = si + 1) begin
                @(posedge aclk);
                s_axis_tdata  = stim_mem[si];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (si == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
                while (!s_axis_tready) @(posedge aclk);
            end
            @(posedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;

            // Wait for M_AXIS output_count == FRAME_LEN or watchdog
            wdog = 0;
            while (m_axis_out_count < FRAME_LEN && wdog < WATCHDOG_CYCLES) begin
                @(posedge aclk);
                wdog = wdog + 1;
            end

            // Deactivate capture
            case_active = 0;
            repeat(4) @(posedge aclk);

            // Read sticky latches
            axi_read(ADDR_FSV,        axi_rd_data);
            frame_ok = (axi_rd_data[0] === 1'b1) ? 1 : 0;

            axi_read(ADDR_FRAC_CFO_V, axi_rd_data);
            frac_ok  = (axi_rd_data[0] === 1'b1) ? 1 : 0;

            // Count and TLAST
            count_ok = (m_axis_out_count == FRAME_LEN) ? 1 : 0;
            tlast_ok = (m_axis_tlast_idx == FRAME_LEN - 1) ? 1 : 0;

            case_ok = frame_ok & frac_ok & count_ok & tlast_ok;

            $display("[J]   frame=%0d frac=%0d count=%0d(exp %0d) tlast_idx=%0d(exp %0d) -> %s",
                     frame_ok, frac_ok, m_axis_out_count, FRAME_LEN,
                     m_axis_tlast_idx, FRAME_LEN-1, case_ok ? "PASS" : "FAIL");

            if (!frame_ok)
                $display("[J]   REASON: frame_start_valid did not fire (FSV=0)");
            if (!frac_ok)
                $display("[J]   REASON: frac_cfo_valid did not fire (FRAC_CFO_V=0)");
            if (!count_ok)
                $display("[J]   REASON: OUTPUT_COUNT=%0d (expect %0d)",
                         m_axis_out_count, FRAME_LEN);
            if (!tlast_ok && count_ok)
                $display("[J]   REASON: TLAST at beat %0d (expect %0d)",
                         m_axis_tlast_idx, FRAME_LEN-1);
            if (wdog >= WATCHDOG_CYCLES)
                $display("[J]   REASON: watchdog %0d cycles expired", WATCHDOG_CYCLES);
        end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    integer case_ok;

    initial begin
        $display("");
        $display("======================================================");
        $display(" P3-21A J2+J3: CFO Robustness Sweep");
        $display(" DUT: phase3_sync_axis_dma_wrapper  THRESHOLD=%0d", THRESHOLD_TB);
        $display(" J2: 7 frac CFO cases  J3: 4 combined cases");
        $display("======================================================");
        $display("");

        // Global reset
        aresetn = 1'b0;
        repeat(16) @(posedge aclk);
        aresetn = 1'b1;
        repeat(8) @(posedge aclk);

        m_axis_out_count = 0;
        m_axis_tlast_idx = -1;
        case_active = 0;
        j2_pass = 0;  j2_fail = 0;
        j3_pass = 0;  j3_fail = 0;

        // Clear initial sticky latches
        axi_read(ADDR_FSV,        axi_rd_data);
        axi_read(ADDR_FRAC_CFO_V, axi_rd_data);
        axi_read(ADDR_INT_CFO_V,  axi_rd_data);

        // ==============================================================
        // J2: Fractional CFO sweep (k_int=0)
        // ==============================================================
        $display("--- [J2: Fractional CFO sweep] ---");
        $display("");

        // J2-0: frac = -0.45
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_m045.mem",
                         "J2-0 frac=-0.45 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-1: frac = -0.30
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_m030.mem",
                         "J2-1 frac=-0.30 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-2: frac = -0.15
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_m015.mem",
                         "J2-2 frac=-0.15 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-3: frac = 0 (baseline)
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_p000.mem",
                         "J2-3 frac=0.00 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-4: frac = +0.15
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_p015.mem",
                         "J2-4 frac=+0.15 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-5: frac = +0.30
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_p030.mem",
                         "J2-5 frac=+0.30 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        // J2-6: frac = +0.45
        run_wrapper_case("golden/p3_21a_sweep/j2_frac_p045.mem",
                         "J2-6 frac=+0.45 k=0", case_ok);
        if (case_ok) j2_pass = j2_pass + 1; else j2_fail = j2_fail + 1;
        between_case_reset;

        $display("");
        $display("  J2 results: %0d passed, %0d failed (of 7)", j2_pass, j2_fail);
        if (j2_fail == 0) $display("J2_GATE: PASS");
        else              $display("J2_GATE: FAIL  (%0d/%0d cases failed)", j2_fail, 7);

        // ==============================================================
        // J3: Combined sweep
        // Note: bypass FFT → int_cfo=0 always; integer CFO not corrected.
        //       Checks: frame_found, frac_cfo_valid, replay completion, TLAST.
        // ==============================================================
        $display("");
        $display("--- [J3: Combined sweep (bypass-FFT int_cfo=0, frac corrected)] ---");
        $display("");

        // J3-0: (+16, +0.45)
        run_wrapper_case("golden/p3_21a_sweep/j3_kp16_fp045.mem",
                         "J3-0 k=+16 frac=+0.45", case_ok);
        if (case_ok) j3_pass = j3_pass + 1; else j3_fail = j3_fail + 1;
        between_case_reset;

        // J3-1: (-16, -0.45)
        run_wrapper_case("golden/p3_21a_sweep/j3_km16_fm045.mem",
                         "J3-1 k=-16 frac=-0.45", case_ok);
        if (case_ok) j3_pass = j3_pass + 1; else j3_fail = j3_fail + 1;
        between_case_reset;

        // J3-2: (+12, -0.30)
        run_wrapper_case("golden/p3_21a_sweep/j3_kp12_fm030.mem",
                         "J3-2 k=+12 frac=-0.30", case_ok);
        if (case_ok) j3_pass = j3_pass + 1; else j3_fail = j3_fail + 1;
        between_case_reset;

        // J3-3: (-12, +0.30)
        run_wrapper_case("golden/p3_21a_sweep/j3_km12_fp030.mem",
                         "J3-3 k=-12 frac=+0.30", case_ok);
        if (case_ok) j3_pass = j3_pass + 1; else j3_fail = j3_fail + 1;
        // No reset after last case

        $display("");
        $display("  J3 results: %0d passed, %0d failed (of 4)", j3_pass, j3_fail);
        if (j3_fail == 0) $display("J3_GATE: PASS");
        else              $display("J3_GATE: FAIL  (%0d/%0d cases failed)", j3_fail, 4);

        $display("");
        $finish;
    end

endmodule
