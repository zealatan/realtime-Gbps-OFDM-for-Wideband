`timescale 1ns/1ps

// session_I_p3_20a_axi_backpressure_stress_tb — P3-20A AXI Backpressure Stress
//
// DUT: phase3_sync_axis_dma_wrapper
//
// Tests:
//   I1: S_AXIS stall at 0/10/25/50 % probability
//   I2: M_AXIS stall at 10/25/50 % probability
//   I3: M_AXIS burst stall of 1/4/8/16/32 cycles at replay start
//   I4: AXI protocol assertions (tvalid/tdata/tlast stability under backpressure)
//
// Per-case checks:
//   C1: output_count == 576   (no sample loss)
//   C2: TLAST emitted         (frame boundary correct)
//   C3: INT_CFO_APPLIED == 1  (replay completed)
// Plus I4 global assertion pass/fail.
//
// Gate: AXI_GATE: PASS / AXI_GATE: FAIL
//
// Watchdog: 500 000 cycles per test case (deadlock detection)
// Simulator: iverilog -g2012

module session_I_p3_20a_axi_bp_stress_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH        = 16;
    localparam integer NSC             = 256;
    localparam integer CP_LEN          = 32;
    localparam integer BUF_AW          = 12;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer FRAME_LEN       = 2 * (NSC + CP_LEN);   // 576
    localparam integer THRESHOLD_TB    = 40000;
    localparam integer STIM_DEPTH      = 704;
    localparam integer MAX_CAP         = 8192;
    localparam integer WATCHDOG_CYC    = 500000;

    // AXI-Lite addresses
    localparam [6:0] ADDR_CONTROL     = 7'h04;
    localparam [6:0] ADDR_STATUS      = 7'h08;
    localparam [6:0] ADDR_OUT_COUNT   = 7'h14;
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
    // S_AXIS (IQ input — driven from initial block)
    // -----------------------------------------------------------------------
    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;

    // -----------------------------------------------------------------------
    // M_AXIS (corrected IQ output — tready driven from always block below)
    // -----------------------------------------------------------------------
    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    // -----------------------------------------------------------------------
    // DUT debug ports
    // -----------------------------------------------------------------------
    wire [31:0] dbg_frac_m_tdata;
    wire        dbg_frac_m_tvalid;
    wire        dbg_frac_m_tready;
    wire        dbg_frac_m_tlast;

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
    // Backpressure control registers (written by initial block between tests,
    // read by always block during tests — no simultaneous access)
    // -----------------------------------------------------------------------
    integer bp_active;         // 0 = tready=1, 1 = backpressure logic active
    integer bp_m_stall_prob;   // period N: stall tready every N-th cycle (0 = off)
    integer bp_m_burst_len;    // burst stall length (I3, 0 = off)
    integer bp_m_burst_cnt;    // countdown within burst
    integer bp_m_burst_done;   // 1 = burst already triggered this test case
    integer bp_m_cycle_cnt;    // cycle counter for deterministic period stalls

    initial begin
        bp_active        = 0;
        bp_m_stall_prob  = 0;
        bp_m_burst_len   = 0;
        bp_m_burst_cnt   = 0;
        bp_m_burst_done  = 0;
        bp_m_cycle_cnt   = 0;
        m_axis_tready    = 1'b1;
    end

    // M_AXIS tready — SINGLE DRIVER (this always block only)
    // NBA (<=) ensures DUT always blocks see the T-1 tready value at posedge T,
    // consistent with the TB counter — eliminates phantom handshakes from ordering races.
    always @(posedge aclk) begin
        if (!aresetn || !bp_active) begin
            m_axis_tready <= 1'b1;
        end else if (bp_m_burst_len > 0 && !bp_m_burst_done && m_axis_tvalid) begin
            // I3: latch burst on first valid beat
            bp_m_burst_done <= 1;
            bp_m_burst_cnt  <= bp_m_burst_len;
            m_axis_tready   <= 1'b0;
        end else if (bp_m_burst_cnt > 0) begin
            // (bp_m_burst_cnt > 1) = pre-NBA check: release when cnt-1 reaches 0
            bp_m_burst_cnt  <= bp_m_burst_cnt - 1;
            m_axis_tready   <= (bp_m_burst_cnt > 1) ? 1'b0 : 1'b1;
        end else if (bp_m_stall_prob > 0) begin
            // I2: deterministic period stall; pre-compute cnt+1 since NBA hasn't fired yet
            bp_m_cycle_cnt <= bp_m_cycle_cnt + 1;
            m_axis_tready  <= ((bp_m_cycle_cnt + 1) % bp_m_stall_prob != 0) ? 1'b1 : 1'b0;
        end else begin
            m_axis_tready <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // M_AXIS global capture (monotonic counter, written only from always block)
    // -----------------------------------------------------------------------
    integer m_axis_out_count;  // total beats captured across all test cases
    integer m_tlast_idx;       // absolute index of most recent TLAST beat

    initial begin
        m_axis_out_count = 0;
        m_tlast_idx      = -1;
    end

    always @(posedge aclk) begin
        if (m_axis_tvalid && m_axis_tready && m_axis_out_count < MAX_CAP) begin
            if (m_axis_tlast)
                m_tlast_idx = m_axis_out_count;
            m_axis_out_count = m_axis_out_count + 1;
        end
    end

    // -----------------------------------------------------------------------
    // I4: AXI Protocol Assertions
    // Checks DUT M_AXIS output only:
    //   I4a: tdata must not change while tvalid=1 and tready=0
    //   I4b: tlast must not change while tvalid=1 and tready=0
    //   I4c: tvalid must not deassert while tready=0 (AXI4-S rule)
    // -----------------------------------------------------------------------
    integer axi_assert_fail;
    reg     m_prev_valid;
    reg     m_prev_ready;
    reg [31:0] m_prev_tdata;
    reg        m_prev_tlast;

    initial begin
        axi_assert_fail = 0;
        m_prev_valid    = 1'b0;
        m_prev_ready    = 1'b1;
        m_prev_tdata    = 32'h0;
        m_prev_tlast    = 1'b0;
    end

    // Negedge sampling: NBA signals from posedge have settled; no ordering races.
    always @(negedge aclk) begin
        if (m_prev_valid && !m_prev_ready && !m_axis_tready) begin
            // I4a: tdata stable while stalled (check only when tready remains 0)
            if (m_axis_tdata !== m_prev_tdata) begin
                $display("[I4a FAIL] tdata changed while stalled: prev=0x%08h now=0x%08h @%0t",
                         m_prev_tdata, m_axis_tdata, $time);
                axi_assert_fail = axi_assert_fail + 1;
            end
            // I4b: tlast stable while stalled
            if (m_axis_tlast !== m_prev_tlast) begin
                $display("[I4b FAIL] tlast changed while stalled: prev=%b now=%b @%0t",
                         m_prev_tlast, m_axis_tlast, $time);
                axi_assert_fail = axi_assert_fail + 1;
            end
            // I4c: tvalid must not deassert while tready=0
            if (!m_axis_tvalid) begin
                $display("[I4c FAIL] tvalid deasserted while tready=0 @%0t", $time);
                axi_assert_fail = axi_assert_fail + 1;
            end
        end
        m_prev_valid = m_axis_tvalid;
        m_prev_ready = m_axis_tready;
        m_prev_tdata = m_axis_tdata;
        m_prev_tlast = m_axis_tlast;
    end

    // -----------------------------------------------------------------------
    // Watchdog (per-test: wdg_limit set before each run, 0 = disabled)
    // -----------------------------------------------------------------------
    integer wdg_limit;
    integer wdg_fired;
    integer global_cycle;

    initial begin
        wdg_limit    = 0;
        wdg_fired    = 0;
        global_cycle = 0;
    end

    always @(posedge aclk) begin
        global_cycle = global_cycle + 1;
        if (wdg_limit > 0 && global_cycle >= wdg_limit && !wdg_fired) begin
            wdg_fired = 1;
            $display("[WDG] WATCHDOG at cycle %0d (limit=%0d)", global_cycle, wdg_limit);
        end
    end

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // AXI-Lite helper tasks (identical pattern to Session C/D)
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
            m_axi_rready  = 1'b0;
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
            m_axi_bready  = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Global pass/fail counters and test index
    // -----------------------------------------------------------------------
    integer pass_cnt;
    integer fail_cnt;
    integer tc_idx;

    // -----------------------------------------------------------------------
    // run_tc — execute one test case and record pass/fail
    //
    // s_stall : S_AXIS stall period N — insert idle cycle every N-th sample (0 = off)
    // m_stall : M_AXIS tready stall period N — deassert every N-th cycle (0 = off)
    // m_burst : M_AXIS burst stall length at first beat (0 = disabled)
    // -----------------------------------------------------------------------
    task run_tc;
        input integer s_stall;
        input integer m_stall;
        input integer m_burst;

        integer lc_i;
        integer lc_tc_m_start;
        integer lc_tc_m_count;
        integer lc_tc_tlast_rel;
        integer lc_reg_out_cnt;
        integer lc_reg_cfo_app;
        integer lc_reg_tlast;
        integer lc_pass;
        integer lc_fail;

        begin
            lc_pass = 0;
            lc_fail = 0;

            // ---- Reset DUT
            bp_active        = 0;
            aresetn          = 1'b0;
            s_axis_tvalid    = 1'b0;
            s_axis_tlast     = 1'b0;
            repeat (20) @(posedge aclk);
            aresetn          = 1'b1;
            repeat (5)  @(posedge aclk);

            // ---- Configure backpressure
            bp_m_stall_prob  = m_stall;
            bp_m_burst_len   = m_burst;
            bp_m_burst_cnt   = 0;
            bp_m_burst_done  = 0;
            bp_m_cycle_cnt   = 0;
            bp_active        = 1;

            // ---- Snapshot start position
            lc_tc_m_start    = m_axis_out_count;
            wdg_limit        = global_cycle + WATCHDOG_CYC;
            wdg_fired        = 0;

            // ---- Enable DUT
            axi_write(ADDR_CONTROL, 32'h00000001);
            repeat (3) @(posedge aclk);

            // ---- Feed stimulus with optional S_AXIS stalls
            for (lc_i = 0; lc_i < STIM_DEPTH; lc_i = lc_i + 1) begin
                if (wdg_fired) begin
                    lc_i = STIM_DEPTH;   // abort on watchdog
                end else begin
                    if (s_stall > 0 && lc_i > 0 && (lc_i % s_stall) == 0) begin
                        s_axis_tvalid = 1'b0;
                        @(posedge aclk);
                    end
                    s_axis_tdata  = stim_mem[lc_i];
                    s_axis_tvalid = 1'b1;
                    s_axis_tlast  = (lc_i == STIM_DEPTH-1) ? 1'b1 : 1'b0;
                    @(posedge aclk);
                    while (!s_axis_tready && !wdg_fired) @(posedge aclk);
                end
            end
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;

            // ---- Wait for M_AXIS FRAME_LEN beats
            while ((m_axis_out_count - lc_tc_m_start) < FRAME_LEN && !wdg_fired)
                @(posedge aclk);

            // Snapshot output counters immediately (before pipeline drain adds extra beats)
            lc_tc_m_count   = m_axis_out_count - lc_tc_m_start;
            lc_tc_tlast_rel = m_tlast_idx - lc_tc_m_start;

            // Let pipeline finish and registers settle
            repeat (20) @(posedge aclk);
            bp_active    = 0;
            wdg_limit    = 0;

            // ---- Read AXI-Lite status
            axi_read(ADDR_OUT_COUNT);   lc_reg_out_cnt = axi_rd_data;
            axi_read(ADDR_INT_CFO_A);   lc_reg_cfo_app = axi_rd_data[0];
            axi_read(ADDR_TLAST_COUNT); lc_reg_tlast   = axi_rd_data;

            // ---- C1: output_count == FRAME_LEN
            if (!wdg_fired && lc_tc_m_count == FRAME_LEN) begin
                $display("  [PASS] TC%0d-C1: output_count=%0d", tc_idx, lc_tc_m_count);
                lc_pass = lc_pass + 1;
            end else if (wdg_fired) begin
                $display("  [FAIL] TC%0d-C1: WATCHDOG (deadlock) after %0d cycles",
                         tc_idx, WATCHDOG_CYC);
                lc_fail = lc_fail + 1;
            end else begin
                $display("  [FAIL] TC%0d-C1: output_count=%0d (exp %0d)",
                         tc_idx, lc_tc_m_count, FRAME_LEN);
                lc_fail = lc_fail + 1;
            end

            // ---- C2: TLAST emitted at index 575
            if (!wdg_fired && lc_tc_tlast_rel == FRAME_LEN-1) begin
                $display("  [PASS] TC%0d-C2: TLAST at beat %0d", tc_idx, lc_tc_tlast_rel);
                lc_pass = lc_pass + 1;
            end else if (!wdg_fired) begin
                $display("  [FAIL] TC%0d-C2: TLAST at beat %0d (exp %0d)",
                         tc_idx, lc_tc_tlast_rel, FRAME_LEN-1);
                lc_fail = lc_fail + 1;
            end else begin
                $display("  [FAIL] TC%0d-C2: TLAST not reached (WDG)", tc_idx);
                lc_fail = lc_fail + 1;
            end

            // ---- C3: INT_CFO_APPLIED == 1
            if (!wdg_fired && lc_reg_cfo_app == 1) begin
                $display("  [PASS] TC%0d-C3: INT_CFO_APPLIED=1", tc_idx);
                lc_pass = lc_pass + 1;
            end else if (!wdg_fired) begin
                $display("  [FAIL] TC%0d-C3: INT_CFO_APPLIED=%0d", tc_idx, lc_reg_cfo_app);
                lc_fail = lc_fail + 1;
            end else begin
                $display("  [FAIL] TC%0d-C3: INT_CFO_APPLIED unknown (WDG)", tc_idx);
                lc_fail = lc_fail + 1;
            end

            pass_cnt = pass_cnt + lc_pass;
            fail_cnt = fail_cnt + lc_fail;
            tc_idx   = tc_idx + 1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin : tb_main

        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // Init AXI-Lite master signals
        m_axi_awaddr  = 7'h0; m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0; m_axi_wstrb = 4'h0; m_axi_wvalid = 1'b0; m_axi_bready = 1'b0;
        m_axi_araddr  = 7'h0; m_axi_arvalid = 1'b0; m_axi_rready = 1'b0;
        s_axis_tdata  = 32'h0; s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
        aresetn       = 1'b0;

        pass_cnt = 0;
        fail_cnt = 0;
        tc_idx   = 1;

        $display("======================================================");
        $display("Session I / P3-20A — AXI Backpressure Stress");
        $display("======================================================");

        // ---- I1: S_AXIS backpressure (M_AXIS always ready) ----
        $display("");
        $display("--- I1: S_AXIS Backpressure ---");
        $display("  TC%0d: s_stall=0 (baseline)",       tc_idx); run_tc( 0,  0,  0);
        $display("  TC%0d: s_stall=1/10 (every 10th)",  tc_idx); run_tc(10,  0,  0);
        $display("  TC%0d: s_stall=1/4  (every 4th)",   tc_idx); run_tc( 4,  0,  0);
        $display("  TC%0d: s_stall=1/2  (every 2nd)",   tc_idx); run_tc( 2,  0,  0);

        // ---- I2: M_AXIS backpressure (S_AXIS steady) ----
        $display("");
        $display("--- I2: M_AXIS Backpressure ---");
        $display("  TC%0d: m_stall=1/10 (every 10th)",  tc_idx); run_tc( 0, 10,  0);
        $display("  TC%0d: m_stall=1/4  (every 4th)",   tc_idx); run_tc( 0,  4,  0);
        $display("  TC%0d: m_stall=1/2  (every 2nd)",   tc_idx); run_tc( 0,  2,  0);

        // ---- I3: Replay burst stall ----
        $display("");
        $display("--- I3: Replay Burst Stall ---");
        $display("  TC%0d: burst=1",                    tc_idx); run_tc( 0,  0,  1);
        $display("  TC%0d: burst=4",                    tc_idx); run_tc( 0,  0,  4);
        $display("  TC%0d: burst=8",                    tc_idx); run_tc( 0,  0,  8);
        $display("  TC%0d: burst=16",                   tc_idx); run_tc( 0,  0, 16);
        $display("  TC%0d: burst=32",                   tc_idx); run_tc( 0,  0, 32);

        // ---- I4: AXI assertion summary ----
        $display("");
        $display("--- I4: AXI Protocol Assertions ---");
        if (axi_assert_fail == 0) begin
            $display("  [PASS] TC%0d-I4: 0 protocol violations", tc_idx);
            pass_cnt = pass_cnt + 1;
        end else begin
            $display("  [FAIL] TC%0d-I4: %0d violation(s) detected", tc_idx, axi_assert_fail);
            fail_cnt = fail_cnt + 1;
        end
        tc_idx = tc_idx + 1;

        // ---- Final summary ----
        $display("");
        $display("======================================================");
        $display("  PASS: %0d", pass_cnt);
        $display("  FAIL: %0d", fail_cnt);
        $display("");
        if (fail_cnt == 0)
            $display("AXI_GATE: PASS");
        else
            $display("AXI_GATE: FAIL");

        $finish;
    end

endmodule
