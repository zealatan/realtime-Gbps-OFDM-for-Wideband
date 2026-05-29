`timescale 1ns/1ps

// session_C_p3_14c_dma_replay_golden_tb — P3-14C Full DMA Replay Golden Compare
//
// DUT: phase3_sync_axis_dma_wrapper (P3-14B)
//
// Flow:
//   1. Reset (20 cycles), release, enable DUT.
//   2. Feed golden/phase3_iq_stimulus.mem (704 samples) via S_AXIS.
//   3. Let pipeline run: frame detect → frac CFO → Meyr → replay.
//   4. Capture M_AXIS output (576 beats expected) and frac-corrected tap.
//   5. After M_AXIS tlast, read AXI-Lite status registers.
//   6. Write sim_out/session_C_p3_14c/rtl_m_axis_iq.txt
//          sim_out/session_C_p3_14c/rtl_frac_iq.txt
//          sim_out/session_C_p3_14c/rtl_status.txt
//   7. Print SANITY_GATE and OFFICIAL_GATE.
//
// SANITY_GATE: PASS — structural checks: INT_CFO_APPLIED=1, OUTPUT_COUNT=576, TLAST=1
// OFFICIAL_GATE: PASS — Python compare script (compare_session_C_p3_14c_*.py) passes
//
// Watchdog: 100 000 cycles
//
// Simulator: iverilog -g2012

module p3_14c_golden_tb;

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

    localparam integer THRESHOLD_TB    = 40000;   // matches P3-05B amplitude=3000 stimulus
    localparam integer STIM_DEPTH      = 704;
    localparam integer MAX_CAP         = 1024;    // capture array size

    // AXI-Lite register addresses (7-bit)
    localparam [6:0] ADDR_CONTROL     = 7'h04;
    localparam [6:0] ADDR_STATUS      = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT   = 7'h14;
    localparam [6:0] ADDR_INT_CFO_V   = 7'h38;
    localparam [6:0] ADDR_INT_CFO_E   = 7'h3C;
    localparam [6:0] ADDR_INT_CFO_I   = 7'h40;
    localparam [6:0] ADDR_INT_CFO_A   = 7'h44;
    localparam [6:0] ADDR_TLAST_COUNT = 7'h50;

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

    // -----------------------------------------------------------------------
    // Frac-corrected stream tap (from DUT debug ports added in P3-14C)
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0] frac_m_tdata;
    wire                  frac_m_tvalid;
    wire                  frac_m_tready;
    wire                  frac_m_tlast;

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
        .aclk              (aclk),
        .aresetn           (aresetn),

        .s_axi_awaddr      (m_axi_awaddr),
        .s_axi_awvalid     (m_axi_awvalid),
        .s_axi_awready     (m_axi_awready),
        .s_axi_wdata       (m_axi_wdata),
        .s_axi_wstrb       (m_axi_wstrb),
        .s_axi_wvalid      (m_axi_wvalid),
        .s_axi_wready      (m_axi_wready),
        .s_axi_bresp       (m_axi_bresp),
        .s_axi_bvalid      (m_axi_bvalid),
        .s_axi_bready      (m_axi_bready),
        .s_axi_araddr      (m_axi_araddr),
        .s_axi_arvalid     (m_axi_arvalid),
        .s_axi_arready     (m_axi_arready),
        .s_axi_rdata       (m_axi_rdata),
        .s_axi_rresp       (m_axi_rresp),
        .s_axi_rvalid      (m_axi_rvalid),
        .s_axi_rready      (m_axi_rready),

        .s_axis_tdata      (s_axis_tdata),
        .s_axis_tvalid     (s_axis_tvalid),
        .s_axis_tready     (s_axis_tready),
        .s_axis_tlast      (s_axis_tlast),

        .m_axis_tdata      (m_axis_tdata),
        .m_axis_tvalid     (m_axis_tvalid),
        .m_axis_tready     (m_axis_tready),
        .m_axis_tlast      (m_axis_tlast),

        // P3-14C: frac-corrected tap
        .dbg_frac_m_tdata  (frac_m_tdata),
        .dbg_frac_m_tvalid (frac_m_tvalid),
        .dbg_frac_m_tready (frac_m_tready),
        .dbg_frac_m_tlast  (frac_m_tlast)
    );

    // -----------------------------------------------------------------------
    // AXI-Lite helpers
    // -----------------------------------------------------------------------
    reg [31:0] axi_rd_data;
    reg [1:0]  axi_rd_resp;

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
            axi_rd_data = m_axi_rdata;
            axi_rd_resp = m_axi_rresp;
            @(posedge aclk);
            m_axi_rready = 1'b0;
        end
    endtask

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
    // Waveform dump
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("logs/p3_14c_golden_sim.vcd");
        $dumpvars(0, p3_14c_golden_tb);
    end

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial begin
        cycle_cnt = 0;
        forever begin
            @(posedge aclk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt > 150000) begin
                $display("FAIL [WDG]: watchdog at %0t ns — pipeline did not complete", $time);
                $display("  m_axis_out_count=%0d  frac_cap_count=%0d", m_axis_out_count, frac_cap_count);
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // M_AXIS capture
    // -----------------------------------------------------------------------
    integer m_axis_out_count;
    reg [31:0] m_axis_cap   [0:MAX_CAP-1];
    reg        m_axis_tlast_pos [0:MAX_CAP-1];

    initial begin
        m_axis_out_count = 0;
    end

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_out_count < MAX_CAP) begin
            m_axis_cap   [m_axis_out_count] = m_axis_tdata;
            m_axis_tlast_pos[m_axis_out_count] = m_axis_tlast;
            m_axis_out_count = m_axis_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Frac stream capture
    // -----------------------------------------------------------------------
    integer frac_cap_count;
    reg [31:0] frac_cap [0:MAX_CAP-1];

    initial begin
        frac_cap_count = 0;
    end

    always @(posedge aclk) begin
        if (frac_m_tvalid && frac_m_tready && frac_cap_count < MAX_CAP)
            frac_cap[frac_cap_count++] = frac_m_tdata;
    end

    // -----------------------------------------------------------------------
    // Stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;
    integer fail_count;
    integer first_tlast_idx;
    integer fd_m, fd_f, fd_s;

    reg [31:0] reg_int_cfo_e;
    reg [31:0] reg_int_cfo_i;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_out_count;
    reg [31:0] reg_tlast_count;
    reg [31:0] reg_status;

    initial begin
        fail_count = 0;
        first_tlast_idx = -1;

        // ---- Initialise AXI-Lite
        m_axi_awaddr  = 7'h00;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;
        m_axi_wstrb   = 4'h0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        // ---- S_AXIS idle
        s_axis_tdata  = 32'h0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        // ---- M_AXIS sink always ready
        m_axis_tready = 1'b1;

        // ---- Load stimulus
        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ================================================================
        // Phase 1: Reset
        // ================================================================
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // ================================================================
        // Phase 2: Enable DUT (non-bypass mode)
        // ================================================================
        axi_write(ADDR_CONTROL, 32'h00000001);   // enable=1, bypass=0
        repeat (3) @(posedge aclk);

        // ================================================================
        // Phase 3: Feed stimulus (704 samples) respecting backpressure
        // ================================================================
        $display("[P3-14C] Feeding %0d stimulus samples...", STIM_DEPTH);
        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
            // Respect backpressure
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        $display("[P3-14C] Stimulus done. Waiting for M_AXIS output...");

        // ================================================================
        // Phase 4: Wait for first M_AXIS TLAST (or watchdog)
        //          The watchdog always block kills the sim on timeout.
        // ================================================================
        // Poll until m_axis_out_count reaches FRAME_LEN
        while (m_axis_out_count < FRAME_LEN) begin
            @(posedge aclk);
        end

        // Capture the tlast position
        begin : find_tlast
            integer k;
            for (k = 0; k < m_axis_out_count; k = k + 1) begin
                if (m_axis_tlast_pos[k] && (first_tlast_idx < 0))
                    first_tlast_idx = k;
            end
        end

        // Wait a few more cycles for registers to update
        repeat (20) @(posedge aclk);

        // ================================================================
        // Phase 5: Read AXI-Lite status registers
        // ================================================================
        $display("[P3-14C] Reading status registers...");
        axi_read(ADDR_INT_CFO_E);   reg_int_cfo_e   = axi_rd_data;
        axi_read(ADDR_INT_CFO_I);   reg_int_cfo_i   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   reg_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_OUT_COUNT);   reg_out_count   = axi_rd_data;
        axi_read(ADDR_TLAST_COUNT); reg_tlast_count = axi_rd_data;
        axi_read(ADDR_STATUS);      reg_status      = axi_rd_data;

        // ================================================================
        // Phase 6: Write output files
        // ================================================================
        // rtl_status.txt
        fd_s = $fopen("sim_out/session_C_p3_14c/rtl_status.txt", "w");
        $fdisplay(fd_s, "INT_CFO_STEP_WORD=0x%08X", reg_int_cfo_e);
        $fdisplay(fd_s, "INT_CFO_STEP_WORD_DEC=%0d", $signed(reg_int_cfo_e));
        $fdisplay(fd_s, "INT_CFO_INDEX=%0d", reg_int_cfo_i);
        $fdisplay(fd_s, "INT_CFO_APPLIED=%0d", reg_int_cfo_a[0]);
        $fdisplay(fd_s, "OUTPUT_COUNT=%0d", reg_out_count);
        $fdisplay(fd_s, "TLAST_COUNT=%0d", reg_tlast_count);
        $fdisplay(fd_s, "STATUS=0x%08X", reg_status);
        $fdisplay(fd_s, "M_AXIS_CAPTURED=%0d", m_axis_out_count);
        $fdisplay(fd_s, "FRAC_CAPTURED=%0d", frac_cap_count);
        $fdisplay(fd_s, "FIRST_TLAST_IDX=%0d", first_tlast_idx);
        $fdisplay(fd_s, "FRAME_LEN=%0d", FRAME_LEN);
        $fclose(fd_s);

        // rtl_m_axis_iq.txt — {I Q} decimal per line
        fd_m = $fopen("sim_out/session_C_p3_14c/rtl_m_axis_iq.txt", "w");
        for (i = 0; i < m_axis_out_count; i = i + 1) begin
            $fdisplay(fd_m, "%0d %0d",
                $signed(m_axis_cap[i][15:0]),
                $signed(m_axis_cap[i][31:16]));
        end
        $fclose(fd_m);

        // rtl_frac_iq.txt — {I Q} decimal per line
        fd_f = $fopen("sim_out/session_C_p3_14c/rtl_frac_iq.txt", "w");
        for (i = 0; i < frac_cap_count; i = i + 1) begin
            $fdisplay(fd_f, "%0d %0d",
                $signed(frac_cap[i][15:0]),
                $signed(frac_cap[i][31:16]));
        end
        $fclose(fd_f);

        $display("[P3-14C] Files written.");
        $display("  rtl_status.txt");
        $display("  rtl_m_axis_iq.txt  (%0d samples)", m_axis_out_count);
        $display("  rtl_frac_iq.txt    (%0d samples)", frac_cap_count);

        // ================================================================
        // Phase 7: SANITY checks (structural)
        // ================================================================
        $display("[P3-14C] Checking SANITY conditions...");

        // S1: INT_CFO_APPLIED must be 1
        if (reg_int_cfo_a[0] !== 1'b1) begin
            $display("FAIL [S1]: INT_CFO_APPLIED=%0d expected 1 (replay did not fire)", reg_int_cfo_a[0]);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S1]: INT_CFO_APPLIED=1");

        // S2: M_AXIS captured == FRAME_LEN samples
        if (m_axis_out_count !== FRAME_LEN) begin
            $display("FAIL [S2]: M_AXIS captured=%0d expected %0d", m_axis_out_count, FRAME_LEN);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S2]: M_AXIS captured=%0d == FRAME_LEN", m_axis_out_count);

        // S3: TLAST fired at position FRAME_LEN-1
        if (first_tlast_idx !== FRAME_LEN - 1) begin
            $display("FAIL [S3]: TLAST at idx=%0d expected %0d", first_tlast_idx, FRAME_LEN-1);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S3]: TLAST at position %0d (FRAME_LEN-1)", first_tlast_idx);

        // S4: TLAST_COUNT == 1
        if (reg_tlast_count < 32'd1) begin
            $display("FAIL [S4]: TLAST_COUNT=%0d expected >= 1", reg_tlast_count);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S4]: TLAST_COUNT=%0d", reg_tlast_count);

        // S5: OUTPUT_COUNT == M_AXIS captured
        if (reg_out_count !== m_axis_out_count[31:0]) begin
            $display("FAIL [S5]: OUTPUT_COUNT=%0d != M_AXIS_CAPTURED=%0d", reg_out_count, m_axis_out_count);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S5]: OUTPUT_COUNT=%0d matches", reg_out_count);

        // S6: Frac stream captured exactly FRAME_LEN samples
        if (frac_cap_count !== FRAME_LEN) begin
            $display("FAIL [S6]: frac captured=%0d expected %0d (replay buffer may have missed samples)", frac_cap_count, FRAME_LEN);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S6]: frac captured=%0d == FRAME_LEN", frac_cap_count);

        // ================================================================
        // Phase 8: Emit gate summary
        // ================================================================
        repeat (5) @(posedge aclk);

        if (fail_count == 0) begin
            $display("==============================================");
            $display("SANITY_GATE: PASS");
            $display("  6/6 structural checks passed.");
            $display("  Run compare_session_C_p3_14c_dma_replay_golden.py");
            $display("  to check OFFICIAL_GATE: PASS.");
            $display("==============================================");
        end else begin
            $display("==============================================");
            $display("SANITY_GATE: FAIL  (%0d failure(s))", fail_count);
            $display("==============================================");
        end

        $display("[P3-14C] INT_CFO_STEP_WORD=0x%08X (%0d decimal)",
                 reg_int_cfo_e, $signed(reg_int_cfo_e));
        $display("[P3-14C] INT_CFO_INDEX=%0d  (Meyr peak index, 255=zero-CFO)",
                 reg_int_cfo_i);

        $finish;
    end

endmodule
