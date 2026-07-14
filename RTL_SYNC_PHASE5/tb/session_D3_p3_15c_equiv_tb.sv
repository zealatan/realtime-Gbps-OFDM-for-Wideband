`timescale 1ns/1ps

// session_D3_p3_15c_equiv_tb — P3-15C Equivalence Robustness TB
//
// Reusable TB driven by plusargs:
//   +STIM_FILE=<path>   — .mem hex file (704 words)
//   +OUT_PREFIX=<path>  — prefix for output files:
//                           <prefix>_status.txt
//                           <prefix>_m_axis_iq.txt
//                           <prefix>_frac_iq.txt
//   +STIM_LABEL=<str>   — display label (default "stim_XX")
//
// Flow: reset → enable → feed 704 samples → capture M_AXIS + frac tap
//       → read AXI-Lite registers → write files → print STIM_GATE
//
// Gate: STIM_GATE: PASS / FAIL  (structural checks only; IQ compare is Python-side)
//
// Structural checks:
//   [S1] INT_CFO_APPLIED = 1
//   [S2] M_AXIS captured = 576
//   [S3] TLAST at index 575
//   [S4] frac captured = 576
//
// Watchdog: 200000 cycles
// Simulator: iverilog -g2012

module session_D3_p3_15c_equiv_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer FRAME_LEN       = 2 * (NSC + CP_LEN);   // 576

    localparam integer THRESHOLD_TB = 40000;
    localparam integer STIM_DEPTH   = 704;
    localparam integer MAX_CAP      = 1024;

    // AXI-Lite register addresses (7-bit)
    localparam [6:0] ADDR_CONTROL     = 7'h04;
    localparam [6:0] ADDR_STATUS      = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT   = 7'h14;
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
    // Debug tap — frac-corrected stream
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
    // Capture arrays
    // -----------------------------------------------------------------------
    reg [31:0] m_axis_cap    [0:MAX_CAP-1];
    reg        m_axis_tlast_r[0:MAX_CAP-1];
    integer    m_axis_out_count;

    reg [31:0] frac_cap      [0:MAX_CAP-1];
    integer    frac_cap_count;

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_out_count < MAX_CAP) begin
            m_axis_cap[m_axis_out_count]     = m_axis_tdata;
            m_axis_tlast_r[m_axis_out_count] = m_axis_tlast;
            m_axis_out_count                 = m_axis_out_count + 1;
        end
    end

    always @(posedge aclk) begin
        if (dbg_frac_m_tvalid && dbg_frac_m_tready && frac_cap_count < MAX_CAP)
            frac_cap[frac_cap_count++] = dbg_frac_m_tdata;
    end

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    integer cycle_count;
    always @(posedge aclk) cycle_count = cycle_count + 1;

    initial begin
        cycle_count = 0;
        #(200000 * 10);
        $display("WATCHDOG TIMEOUT at cycle %0d", cycle_count);
        $display("STIM_GATE: FAIL (watchdog timeout)");
        $finish;
    end

    // -----------------------------------------------------------------------
    // AXI-Lite tasks
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
    // Stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // Main test
    // -----------------------------------------------------------------------
    integer i;
    integer fail_count;
    integer first_tlast_idx;
    integer fd_s, fd_m, fd_f;

    reg [31:0] reg_fsi;
    reg [31:0] reg_slot;
    reg [31:0] reg_frac_v;
    reg [31:0] reg_frac_p;
    reg [31:0] reg_int_cfo_v;
    reg [31:0] reg_int_cfo_e;
    reg [31:0] reg_int_cfo_i;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_out_count;
    reg [31:0] reg_tlast_count;
    reg [31:0] reg_status;
    reg [31:0] reg_errors;

    string stim_path;
    string out_prefix;
    string stim_label;

    initial begin
        fail_count       = 0;
        m_axis_out_count = 0;
        frac_cap_count   = 0;
        first_tlast_idx  = -1;

        // Plusargs
        if (!$value$plusargs("STIM_FILE=%s",   stim_path))  stim_path  = "golden/phase3_iq_stimulus.mem";
        if (!$value$plusargs("OUT_PREFIX=%s",  out_prefix)) out_prefix = "sim_out/session_D3_p3_15c/stim_01";
        if (!$value$plusargs("STIM_LABEL=%s",  stim_label)) stim_label = "stim_XX";

        $display("[D3] === %s ===", stim_label);
        $display("[D3] STIM_FILE  = %s", stim_path);
        $display("[D3] OUT_PREFIX = %s", out_prefix);

        // AXI-Lite idle
        m_axi_awaddr  = 7'h00; m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0; m_axi_wstrb   = 4'h0; m_axi_wvalid = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00; m_axi_arvalid = 1'b0; m_axi_rready = 1'b0;

        s_axis_tdata  = 32'h0; s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
        m_axis_tready = 1'b1;

        // Load stimulus
        $readmemh(stim_path, stim_mem);

        // ============================================================
        // Phase 1: Reset
        // ============================================================
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // ============================================================
        // Phase 2: Enable DUT
        // ============================================================
        axi_write(ADDR_CONTROL, 32'h00000001);   // enable=1
        repeat (3) @(posedge aclk);

        // ============================================================
        // Phase 3: Feed 704 stimulus samples
        // ============================================================
        $display("[D3] Feeding %0d stimulus samples...", STIM_DEPTH);
        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge aclk); #1;
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
            while (!s_axis_tready) begin @(posedge aclk); #1; end
        end
        @(posedge aclk); #1;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        // ============================================================
        // Phase 4: Wait for FRAME_LEN M_AXIS beats
        // ============================================================
        $display("[D3] Waiting for %0d M_AXIS beats...", FRAME_LEN);
        while (m_axis_out_count < FRAME_LEN)
            @(posedge aclk);

        // Capture first TLAST position
        begin : find_tlast_blk
            integer k;
            for (k = 0; k < m_axis_out_count; k = k + 1) begin
                if (m_axis_tlast_r[k] && (first_tlast_idx < 0))
                    first_tlast_idx = k;
            end
        end

        repeat (20) @(posedge aclk);

        // ============================================================
        // Phase 5: Read AXI-Lite status registers
        // ============================================================
        axi_read(ADDR_FSI);         reg_fsi         = axi_rd_data;
        axi_read(ADDR_SLOT_IDX);    reg_slot        = axi_rd_data;
        axi_read(ADDR_FRAC_CFO_V);  reg_frac_v      = axi_rd_data;
        axi_read(ADDR_FRAC_CFO_P);  reg_frac_p      = axi_rd_data;
        axi_read(ADDR_INT_CFO_V);   reg_int_cfo_v   = axi_rd_data;
        axi_read(ADDR_INT_CFO_E);   reg_int_cfo_e   = axi_rd_data;
        axi_read(ADDR_INT_CFO_I);   reg_int_cfo_i   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   reg_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_OUT_COUNT);   reg_out_count   = axi_rd_data;
        axi_read(ADDR_TLAST_COUNT); reg_tlast_count = axi_rd_data;
        axi_read(ADDR_STATUS);      reg_status      = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS); reg_errors      = axi_rd_data;

        // ============================================================
        // Phase 6: Write output files
        // ============================================================

        // status.txt
        fd_s = $fopen({out_prefix, "_status.txt"}, "w");
        $fdisplay(fd_s, "FRAME_START_INDEX=%0d",        reg_fsi);
        $fdisplay(fd_s, "SLOT_START_INDEX=%0d",         reg_slot);
        $fdisplay(fd_s, "PEAK_LAG_AUTO=%0d",            reg_slot - reg_fsi);
        $fdisplay(fd_s, "FRAC_CFO_VALID=%0d",           reg_frac_v[0]);
        $fdisplay(fd_s, "FRAC_CFO_WORD=%0d",            $signed(reg_frac_p[15:0]));
        $fdisplay(fd_s, "INT_CFO_VALID=%0d",            reg_int_cfo_v[0]);
        $fdisplay(fd_s, "INT_CFO_STEP_WORD=0x%08X",     reg_int_cfo_e);
        $fdisplay(fd_s, "INT_CFO_STEP_WORD_DEC=%0d",    $signed(reg_int_cfo_e));
        $fdisplay(fd_s, "INT_CFO_INDEX=%0d",            reg_int_cfo_i);
        $fdisplay(fd_s, "INT_CFO_APPLIED=%0d",          reg_int_cfo_a[0]);
        $fdisplay(fd_s, "OUTPUT_COUNT=%0d",             reg_out_count);
        $fdisplay(fd_s, "TLAST_COUNT=%0d",              reg_tlast_count);
        $fdisplay(fd_s, "STATUS=0x%08X",                reg_status);
        $fdisplay(fd_s, "ERROR_FLAGS=0x%08X",           reg_errors);
        $fdisplay(fd_s, "M_AXIS_CAPTURED=%0d",          m_axis_out_count);
        $fdisplay(fd_s, "FRAC_CAPTURED=%0d",            frac_cap_count);
        $fdisplay(fd_s, "FIRST_TLAST_IDX=%0d",          first_tlast_idx);
        $fdisplay(fd_s, "FRAME_LEN=%0d",                FRAME_LEN);
        $fclose(fd_s);

        // m_axis_iq.txt — signed decimal I Q per line
        fd_m = $fopen({out_prefix, "_m_axis_iq.txt"}, "w");
        for (i = 0; i < m_axis_out_count; i = i + 1)
            $fdisplay(fd_m, "%0d %0d",
                $signed(m_axis_cap[i][15:0]),
                $signed(m_axis_cap[i][31:16]));
        $fclose(fd_m);

        // frac_iq.txt — signed decimal I Q per line
        fd_f = $fopen({out_prefix, "_frac_iq.txt"}, "w");
        for (i = 0; i < frac_cap_count; i = i + 1)
            $fdisplay(fd_f, "%0d %0d",
                $signed(frac_cap[i][15:0]),
                $signed(frac_cap[i][31:16]));
        $fclose(fd_f);

        $display("[D3] Files written:");
        $display("  %s_status.txt", out_prefix);
        $display("  %s_m_axis_iq.txt  (%0d samples)", out_prefix, m_axis_out_count);
        $display("  %s_frac_iq.txt    (%0d samples)", out_prefix, frac_cap_count);

        // ============================================================
        // Phase 7: Structural checks
        // ============================================================
        $display("[D3] Structural checks:");

        // S1: INT_CFO_APPLIED = 1
        if (reg_int_cfo_a[0] !== 1'b1) begin
            $display("FAIL [S1]: INT_CFO_APPLIED=%0d expected 1", reg_int_cfo_a[0]);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S1]: INT_CFO_APPLIED=1");

        // S2: M_AXIS captured == FRAME_LEN
        if (m_axis_out_count !== FRAME_LEN) begin
            $display("FAIL [S2]: M_AXIS captured=%0d expected %0d",
                     m_axis_out_count, FRAME_LEN);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S2]: M_AXIS=%0d == FRAME_LEN", m_axis_out_count);

        // S3: TLAST at FRAME_LEN-1
        if (first_tlast_idx !== FRAME_LEN - 1) begin
            $display("FAIL [S3]: TLAST at %0d, expected %0d",
                     first_tlast_idx, FRAME_LEN - 1);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S3]: TLAST at %0d (FRAME_LEN-1)", first_tlast_idx);

        // S4: frac captured == FRAME_LEN
        if (frac_cap_count !== FRAME_LEN) begin
            $display("FAIL [S4]: frac captured=%0d expected %0d",
                     frac_cap_count, FRAME_LEN);
            fail_count = fail_count + 1;
        end else
            $display("PASS [S4]: frac captured=%0d == FRAME_LEN", frac_cap_count);

        // Summary
        $display("[D3] frame_start=%0d  slot=%0d  frac_cfo_word=%0d  peak=%0d  step=0x%08X",
                 reg_fsi, reg_slot, $signed(reg_frac_p[15:0]),
                 reg_int_cfo_i, reg_int_cfo_e);

        if (fail_count == 0)
            $display("STIM_GATE: PASS");
        else
            $display("STIM_GATE: FAIL (%0d structural failures)", fail_count);

        $finish;
    end

endmodule
