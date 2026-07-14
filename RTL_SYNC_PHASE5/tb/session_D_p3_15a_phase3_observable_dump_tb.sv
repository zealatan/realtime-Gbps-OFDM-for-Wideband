`timescale 1ns/1ps

// session_D_p3_15a_phase3_observable_dump_tb — Phase 3 Observable Dump
//
// Session D / P3-15A: Full C golden equivalence infrastructure.
// DUT: phase3_sync_axis_dma_wrapper (same RTL as Session C / P3-14C)
//
// Purpose: Dump all Phase 3 synchronization observables to text files for
//          staged comparison against C reference golden values.
//
// Outputs:
//   sim_out/session_D_p3_15a/rtl_observables.txt  — scalar status (key VALUE)
//   sim_out/session_D_p3_15a/rtl_m_axis_iq.txt    — M_AXIS IQ pairs (I Q per line)
//   sim_out/session_D_p3_15a/rtl_m_axis_meta.txt  — M_AXIS metadata (key=value)
//
// Observable sources:
//   Hierarchical probes → frame_found, frame_index, peak_lag, slot_start,
//                         frac_cfo_valid, frac_cfo_word, int_cfo_valid,
//                         int_cfo_word, meyr_peak_index
//   AXI-Lite registers  → INT_CFO_APPLIED, OUTPUT_COUNT, TLAST_COUNT, STATUS
//   M_AXIS capture      → sample-by-sample IQ output from replay buffer
//
// Gate:
//   SANITY_GATE: PASS — frame detected, INT_CFO_APPLIED=1, OUTPUT_COUNT=576, TLAST_COUNT=1
//   SANITY_GATE: FAIL — structural check failed
//
// Simulator: iverilog -g2012    Watchdog: 200000 cycles

module session_D_p3_15a_phase3_observable_dump_tb;

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

    localparam integer THRESHOLD_TB  = 40000;
    localparam integer STIM_DEPTH    = 704;
    localparam integer MAX_CAP       = 1024;

    // Golden expected values
    localparam integer GOLDEN_FRAME_IDX  = 41;
    localparam integer GOLDEN_PEAK_LAG   = 23;
    localparam integer GOLDEN_SLOT_START = 64;

    // AXI-Lite register addresses (7-bit word-addressed)
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
    // S_AXIS (IQ input)
    // -----------------------------------------------------------------------
    reg  [2*IQ_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    reg                   s_axis_tlast;

    // -----------------------------------------------------------------------
    // M_AXIS (corrected IQ output)
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    // -----------------------------------------------------------------------
    // DUT debug tap (frac-corrected stream)
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

        .dbg_frac_m_tdata  (dbg_frac_m_tdata),
        .dbg_frac_m_tvalid (dbg_frac_m_tvalid),
        .dbg_frac_m_tready (dbg_frac_m_tready),
        .dbg_frac_m_tlast  (dbg_frac_m_tlast)
    );

    // -----------------------------------------------------------------------
    // AXI-Lite helper tasks (pattern matches Session C — no fork/join)
    // -----------------------------------------------------------------------
    reg [31:0] axi_rd_data;

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
    // Watchdog (separate initial block — matches Session C style)
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial begin
        cycle_cnt = 0;
        forever begin
            @(posedge aclk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt > 200000) begin
                $display("WDG: WATCHDOG TRIGGERED after 200000 cycles — pipeline did not complete");
                $display("  m_axis_out_count=%0d", m_axis_out_count);
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // M_AXIS capture (blocking assignments — matches Session C)
    // -----------------------------------------------------------------------
    integer m_axis_out_count;
    reg [31:0] m_axis_cap [0:MAX_CAP-1];
    reg        m_axis_tlast_pos [0:MAX_CAP-1];

    initial m_axis_out_count = 0;

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_out_count < MAX_CAP) begin
            m_axis_cap    [m_axis_out_count] = m_axis_tdata;
            m_axis_tlast_pos[m_axis_out_count] = m_axis_tlast;
            m_axis_out_count = m_axis_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Frac IQ capture — P3-15B: replay buffer input (dbg_frac_m bus)
    // Captures frac-corrected samples on every handshake; used by
    // gen_c_m_axis_iq_golden.py to apply software NCO model for Stage 4/5.
    // -----------------------------------------------------------------------
    integer frac_out_count;
    reg [31:0] frac_cap [0:MAX_CAP-1];

    initial frac_out_count = 0;

    always @(posedge aclk) begin
        if (dbg_frac_m_tvalid && dbg_frac_m_tready && frac_out_count < MAX_CAP) begin
            frac_cap[frac_out_count] = dbg_frac_m_tdata;
            frac_out_count = frac_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // Hierarchical probe latches for frame/CFO observables
    //   Uses non-blocking to avoid multiple-driver issues; initial block polls
    //   latch_done (integer) which uses blocking assignment.
    // -----------------------------------------------------------------------
    integer latch_frame_found;
    integer latch_frame_index;
    integer latch_peak_lag;
    integer latch_slot_start;
    integer latch_frac_valid;
    integer latch_frac_word;
    integer latch_int_valid;
    integer latch_int_word_probe;
    integer latch_meyr_peak;
    integer latch_done_cycle;

    initial begin
        latch_frame_found     = 0;
        latch_frame_index     = 0;
        latch_peak_lag        = 0;
        latch_slot_start      = 0;
        latch_frac_valid      = 0;
        latch_frac_word       = 0;
        latch_int_valid       = 0;
        latch_int_word_probe  = 0;
        latch_meyr_peak       = 0;
        latch_done_cycle      = -1;
    end

    // Latch frame/CFO signals on frame_start_valid pulse (= frac_cfo_valid in phase3_sync_top)
    always @(posedge aclk) begin
        if (u_dut.dut_frame_start_valid) begin
            latch_frame_found    = 1;
            latch_frame_index    = u_dut.dut_frame_start_index;
            latch_peak_lag       = u_dut.dut_peak_index;
            latch_frac_valid     = 1;
            latch_frac_word      = $signed(u_dut.dut_frac_cfo_word);
        end
        if (u_dut.dut_slot_start_valid) begin
            latch_slot_start     = u_dut.dut_slot_start_index;
        end
        if (u_dut.dut_int_cfo_valid) begin
            latch_int_valid      = 1;
            latch_int_word_probe = $signed(u_dut.dut_int_cfo_word);
            latch_meyr_peak      = u_dut.dut_meyr_peak_index;
            latch_done_cycle     = cycle_cnt;
        end
    end

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    integer i;
    integer first_tlast_idx;
    integer fd_obs, fd_iq, fd_meta;

    reg [31:0] reg_status;
    reg [31:0] reg_out_count;
    reg [31:0] reg_int_cfo_v;
    reg [31:0] reg_int_cfo_e;
    reg [31:0] reg_int_cfo_i;
    reg [31:0] reg_int_cfo_a;
    reg [31:0] reg_tlast_count;

    initial begin
        first_tlast_idx = -1;

        // ---- AXI-Lite master init
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

        // ---- Load IQ stimulus
        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

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
        axi_write(ADDR_CONTROL, 32'h00000001);   // enable=1, bypass=0
        repeat (3) @(posedge aclk);

        // ====================================================================
        // Phase 3: Feed stimulus (704 samples)
        // ====================================================================
        $display("[P3-15A] Feeding %0d IQ samples...", STIM_DEPTH);
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
        $display("[P3-15A] Stimulus done. Waiting for M_AXIS output...");

        // ====================================================================
        // Phase 4: Wait for M_AXIS completion (watchdog in separate initial)
        // ====================================================================
        while (m_axis_out_count < FRAME_LEN) @(posedge aclk);

        // Capture first tlast position
        begin : find_tlast
            integer k;
            for (k = 0; k < m_axis_out_count; k = k + 1) begin
                if (m_axis_tlast_pos[k] && (first_tlast_idx < 0))
                    first_tlast_idx = k;
            end
        end

        // Wait for registers to settle
        repeat (20) @(posedge aclk);

        // ====================================================================
        // Phase 5: Read AXI-Lite status registers
        // ====================================================================
        $display("[P3-15A] Reading status registers...");
        axi_read(ADDR_STATUS);      reg_status      = axi_rd_data;
        axi_read(ADDR_OUT_COUNT);   reg_out_count   = axi_rd_data;
        axi_read(ADDR_INT_CFO_V);   reg_int_cfo_v   = axi_rd_data;
        axi_read(ADDR_INT_CFO_E);   reg_int_cfo_e   = axi_rd_data;
        axi_read(ADDR_INT_CFO_I);   reg_int_cfo_i   = axi_rd_data;
        axi_read(ADDR_INT_CFO_A);   reg_int_cfo_a   = axi_rd_data;
        axi_read(ADDR_TLAST_COUNT); reg_tlast_count = axi_rd_data;

        // ====================================================================
        // Phase 6: Write output files
        // ====================================================================

        // rtl_observables.txt
        fd_obs = $fopen("sim_out/session_D_p3_15a/rtl_observables.txt", "w");
        if (fd_obs == 0) begin
            $display("ERROR: Cannot open rtl_observables.txt"); $finish;
        end
        $fdisplay(fd_obs, "# Session D / P3-15A RTL Observable Dump");
        $fdisplay(fd_obs, "# DUT: phase3_sync_axis_dma_wrapper");
        $fdisplay(fd_obs, "# Source: hierarchical probes + AXI-Lite registers");
        $fdisplay(fd_obs, "# Format: KEY VALUE");
        $fdisplay(fd_obs, "");
        $fdisplay(fd_obs, "# --- Frame / timing (hierarchical probes) ---");
        $fdisplay(fd_obs, "FRAME_FOUND %0d",       latch_frame_found);
        $fdisplay(fd_obs, "FRAME_INDEX %0d",        latch_frame_index);
        $fdisplay(fd_obs, "PEAK_LAG %0d",           latch_peak_lag);
        $fdisplay(fd_obs, "SLOT_START_INDEX %0d",   latch_slot_start);
        $fdisplay(fd_obs, "");
        $fdisplay(fd_obs, "# --- Fractional CFO (hierarchical probes) ---");
        $fdisplay(fd_obs, "FRAC_CFO_VALID %0d",     latch_frac_valid);
        $fdisplay(fd_obs, "FRAC_CFO_WORD %0d",      latch_frac_word);
        $fdisplay(fd_obs, "");
        $fdisplay(fd_obs, "# --- Integer CFO / Meyr (hierarchical probes) ---");
        $fdisplay(fd_obs, "INT_CFO_VALID %0d",      latch_int_valid);
        $fdisplay(fd_obs, "INT_CFO_WORD_PROBE %0d", latch_int_word_probe);
        $fdisplay(fd_obs, "MEYR_PEAK_INDEX %0d",    latch_meyr_peak);
        $fdisplay(fd_obs, "DONE_CYCLE %0d",         latch_done_cycle);
        $fdisplay(fd_obs, "");
        $fdisplay(fd_obs, "# --- AXI-Lite status registers ---");
        $fdisplay(fd_obs, "STATUS_REG 0x%08X",      reg_status);
        $fdisplay(fd_obs, "OUTPUT_COUNT %0d",       reg_out_count);
        $fdisplay(fd_obs, "INT_CFO_VALID_AXI %0d",  reg_int_cfo_v);
        $fdisplay(fd_obs, "INT_CFO_WORD_AXI %0d",   $signed(reg_int_cfo_e));
        $fdisplay(fd_obs, "INT_CFO_INDEX_AXI %0d",  reg_int_cfo_i);
        $fdisplay(fd_obs, "INT_CFO_APPLIED %0d",    reg_int_cfo_a[0]);
        $fdisplay(fd_obs, "TLAST_COUNT %0d",        reg_tlast_count);
        $fdisplay(fd_obs, "");
        $fdisplay(fd_obs, "# --- M_AXIS capture ---");
        $fdisplay(fd_obs, "M_AXIS_CAPTURED %0d",    m_axis_out_count);
        $fdisplay(fd_obs, "FIRST_TLAST_IDX %0d",    first_tlast_idx);
        $fdisplay(fd_obs, "FRAME_LEN %0d",          FRAME_LEN);
        $fclose(fd_obs);
        $display("SESSION_D: rtl_observables.txt written");

        // rtl_m_axis_meta.txt
        fd_meta = $fopen("sim_out/session_D_p3_15a/rtl_m_axis_meta.txt", "w");
        if (fd_meta != 0) begin
            $fdisplay(fd_meta, "OUTPUT_COUNT=%0d",      reg_out_count);
            $fdisplay(fd_meta, "TLAST_COUNT=%0d",       reg_tlast_count);
            $fdisplay(fd_meta, "FIRST_TLAST_IDX=%0d",   first_tlast_idx);
            $fdisplay(fd_meta, "M_AXIS_CAPTURED=%0d",   m_axis_out_count);
            $fdisplay(fd_meta, "FRAME_LEN=%0d",         FRAME_LEN);
            $fdisplay(fd_meta, "INT_CFO_APPLIED=%0d",   reg_int_cfo_a[0]);
            $fdisplay(fd_meta, "FRAC_CAPTURED=%0d",     frac_out_count);
            $fdisplay(fd_meta, "INT_CFO_STEP_WORD=0x%08X", reg_int_cfo_e);
            $fclose(fd_meta);
            $display("SESSION_D: rtl_m_axis_meta.txt written");
        end

        // rtl_m_axis_iq.txt
        fd_iq = $fopen("sim_out/session_D_p3_15a/rtl_m_axis_iq.txt", "w");
        if (fd_iq != 0) begin
            for (i = 0; i < m_axis_out_count; i = i + 1) begin
                $fdisplay(fd_iq, "%0d %0d",
                    $signed(m_axis_cap[i][15:0]),
                    $signed(m_axis_cap[i][31:16]));
            end
            $fclose(fd_iq);
            $display("SESSION_D: rtl_m_axis_iq.txt written (%0d samples)", m_axis_out_count);
        end

        // rtl_frac_iq.txt — P3-15B: frac-corrected IQ before integer NCO
        begin : write_frac_iq
            integer fd_frac;
            fd_frac = $fopen("sim_out/session_D_p3_15a/rtl_frac_iq.txt", "w");
            if (fd_frac != 0) begin
                for (i = 0; i < frac_out_count; i = i + 1) begin
                    $fdisplay(fd_frac, "%0d %0d",
                        $signed(frac_cap[i][15:0]),
                        $signed(frac_cap[i][31:16]));
                end
                $fclose(fd_frac);
                $display("SESSION_D: rtl_frac_iq.txt written (%0d samples)", frac_out_count);
            end
        end

        // ====================================================================
        // Phase 7: Sanity gate evaluation
        // ====================================================================
        $display("");
        $display("=== Session D / P3-15A Observable Dump ===");
        $display("  FRAME_FOUND      = %0d", latch_frame_found);
        $display("  FRAME_INDEX      = %0d  (golden=%0d)", latch_frame_index, GOLDEN_FRAME_IDX);
        $display("  PEAK_LAG         = %0d  (golden=%0d)", latch_peak_lag, GOLDEN_PEAK_LAG);
        $display("  SLOT_START_INDEX = %0d  (golden=%0d)", latch_slot_start, GOLDEN_SLOT_START);
        $display("  FRAC_CFO_VALID   = %0d", latch_frac_valid);
        $display("  FRAC_CFO_WORD    = %0d", latch_frac_word);
        $display("  INT_CFO_VALID    = %0d", latch_int_valid);
        $display("  INT_CFO_WORD     = %0d", latch_int_word_probe);
        $display("  MEYR_PEAK_INDEX  = %0d", latch_meyr_peak);
        $display("  INT_CFO_APPLIED  = %0d", reg_int_cfo_a[0]);
        $display("  OUTPUT_COUNT     = %0d", reg_out_count);
        $display("  M_AXIS_CAPTURED  = %0d", m_axis_out_count);
        $display("  FRAC_CAPTURED    = %0d", frac_out_count);
        $display("  FIRST_TLAST_IDX  = %0d", first_tlast_idx);

        if (latch_frame_found == 1 &&
            latch_frame_index >= GOLDEN_FRAME_IDX - 1 &&
            latch_frame_index <= GOLDEN_FRAME_IDX + 1 &&
            reg_int_cfo_a[0] == 1'b1 &&
            reg_out_count == FRAME_LEN &&
            reg_tlast_count == 32'd1) begin
            $display("");
            $display("SANITY_GATE: PASS");
        end else begin
            $display("");
            $display("SANITY_GATE: FAIL");
            if (latch_frame_found != 1)
                $display("  REASON: frame not detected");
            if (reg_int_cfo_a[0] != 1'b1)
                $display("  REASON: INT_CFO_APPLIED=%0d (expected 1)", reg_int_cfo_a[0]);
            if (reg_out_count != FRAME_LEN)
                $display("  REASON: OUTPUT_COUNT=%0d (expected %0d)", reg_out_count, FRAME_LEN);
            if (reg_tlast_count != 32'd1)
                $display("  REASON: TLAST_COUNT=%0d (expected 1)", reg_tlast_count);
        end

        $finish;
    end

endmodule
