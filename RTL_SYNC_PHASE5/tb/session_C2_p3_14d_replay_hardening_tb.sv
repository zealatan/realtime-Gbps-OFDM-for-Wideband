`timescale 1ns/1ps

// session_C2_p3_14d_replay_hardening_tb — P3-14D Replay Correction Hardening
//
// DUT: phase3_sync_axis_dma_wrapper (same RTL as Sessions E and K)
// Stimulus: golden/phase3_iq_stimulus.mem (704 samples, k_int=+1 natural result)
//
// Four test phases (run sequentially, single simulation):
//
//   C2-1  Replay Backpressure
//         Deterministic bp pattern: 5-high / 3-low, max stall burst = 3 cycles.
//         Checks: output_count=576, tlast_count=1, STALL_TIMEOUT=0.
//
//   C2-2  Integer CFO Sweep Replay
//         13 k_int values: 0, +-1, +-2, +-4, +-8, +-12, +-16.
//         step_word = (-k_int * 2^24) mod 2^32.
//         For each case: soft reset, force dut_int_cfo_word, run one frame.
//         Checks: output_count=576, INT_CFO_APPLIED=1, tlast_count=1.
//
//   C2-3  Replay Restart (4 consecutive frames, no inter-frame reset)
//         Relies on auto-rearm: start_armed fires after replay_done.
//         Checks: output_count increments by 576 per frame (absolute 576/1152/1728/2304).
//
//   C2-4  Rotator Stability
//         Monitors int_nco_phase_acc on every replay_rd handshake.
//         Checks: consecutive phase delta == step_word for all 576 replay beats.
//         Checks: phase_acc resets to 0 after a second soft reset.
//
// Gate:
//   REPLAY_HARDENING_GATE: PASS  — all four phases pass
//   REPLAY_HARDENING_GATE: FAIL  — any phase fails
//
// Machine-readable per-phase RESULT lines are printed before the gate line.
//
// Simulator: iverilog -g2012    Watchdog: 3000000 cycles

module session_C2_p3_14d_replay_hardening_tb;

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
    localparam integer WATCHDOG_CYCLES = 3000000;
    localparam integer N_CFO_CASES     = 13;

    // AXI-Lite addresses (byte-addressed, 7-bit)
    localparam [6:0] ADDR_CONTROL    = 7'h04;
    localparam [6:0] ADDR_OUT_COUNT  = 7'h14;
    localparam [6:0] ADDR_INT_CFO_A  = 7'h44;
    localparam [6:0] ADDR_TLAST_CNT  = 7'h50;
    localparam [6:0] ADDR_ERROR_FLAGS= 7'h54;

    // -----------------------------------------------------------------------
    // Clock / Reset
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
    reg                   m_axis_tready;   // driven by bp_always
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
    // Watchdog
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge aclk) cycle_cnt = cycle_cnt + 1;

    initial begin
        forever begin
            @(posedge aclk);
            if (cycle_cnt > WATCHDOG_CYCLES) begin
                $display("WDG: TIMEOUT at %0d cycles — REPLAY_HARDENING_GATE: FAIL",
                         WATCHDOG_CYCLES);
                $display("REPLAY_HARDENING_GATE: FAIL");
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Backpressure control (C2-1)
    // Pattern: m_axis_tready=1 for 5 cycles, 0 for 3 cycles, repeat.
    // Max stall burst = 3 cycles << STALL_TIMEOUT=254.
    // bp_active=0: always ready (used during C2-2, C2-3, C2-4).
    // -----------------------------------------------------------------------
    reg       bp_active;
    reg [3:0] bp_cnt;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tready <= 1'b1;
            bp_cnt        <= 4'd0;
        end else if (!bp_active) begin
            m_axis_tready <= 1'b1;
            bp_cnt        <= 4'd0;
        end else begin
            if (bp_cnt >= 4'd7)
                bp_cnt <= 4'd0;
            else
                bp_cnt <= bp_cnt + 4'd1;
            m_axis_tready <= (bp_cnt < 4'd5) ? 1'b1 : 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // C2-4 phase continuity monitor
    // Watches replay_rd handshakes; checks int_nco_phase_acc delta = step_word.
    // c24_reset is pulsed by initial block to clear between uses.
    // c24_monitor_en is set by initial block during the C2-4 run.
    // c24_expected_step is set before enabling the monitor.
    // -----------------------------------------------------------------------
    reg        c24_monitor_en;
    reg        c24_reset;
    reg [31:0] c24_expected_step;

    reg        c24_first_sample;
    reg [31:0] c24_prev_phase;
    reg [31:0] c24_phase_errors;
    reg [31:0] c24_sample_cnt;

    always @(posedge aclk) begin
        if (!aresetn || c24_reset) begin
            c24_first_sample <= 1'b0;
            c24_prev_phase   <= 32'd0;
            c24_phase_errors <= 32'd0;
            c24_sample_cnt   <= 32'd0;
        end else if (c24_monitor_en &&
                     u_dut.replay_rd_valid && u_dut.replay_rd_ready) begin
            if (!c24_first_sample) begin
                c24_prev_phase   <= u_dut.int_nco_phase_acc;
                c24_first_sample <= 1'b1;
            end else begin
                if ((u_dut.int_nco_phase_acc - c24_prev_phase) != c24_expected_step)
                    c24_phase_errors <= c24_phase_errors + 32'd1;
                c24_prev_phase <= u_dut.int_nco_phase_acc;
            end
            c24_sample_cnt <= c24_sample_cnt + 32'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Stimulus memory
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];

    // -----------------------------------------------------------------------
    // Module-level variables for main test sequence
    // -----------------------------------------------------------------------
    reg [31:0] axi_rd_data;
    integer    ii;
    integer    jj;

    // C2-1
    integer c21_out_count;
    integer c21_tlast_count;
    integer c21_err_flags;
    integer c21_pass;

    // C2-2
    reg [31:0] c22_step_words [0:N_CFO_CASES-1];
    integer    c22_k_ints_arr  [0:N_CFO_CASES-1];
    integer    c22_pass_count;
    reg [31:0] forced_sw;
    integer    c22_this_oc;
    integer    c22_this_ia;
    integer    c22_this_tlast;
    integer    c22_pass;

    // C2-3
    integer c23_frame_oc [0:3];
    integer c23_pass;

    // C2-4
    integer c24_phase_cont_ok;
    integer c24_phase_reset_ok;
    integer c24_pass;

    // Overall
    integer gate_pass;

    // -----------------------------------------------------------------------
    // AXI-Lite helper tasks
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

    // Soft reset: enable=1, soft_reset_pulse=1. dut_aresetn goes low for 1 cycle.
    // Wait 30 cycles for pipeline flush and re-arm to fire.
    task do_soft_reset;
        begin
            axi_write(ADDR_CONTROL, 32'h00000003);
            repeat (30) @(posedge aclk);
        end
    endtask

    // Feed STIM_DEPTH samples. If send_tlast=1, assert TLAST on last sample.
    // NOTE: TLAST at sample 703 with FRAME_LEN_SAMPLES=576 sets FRAME_LEN_MISMATCH
    // error flag (in_frame_cnt=127 != 575). This is expected and documented.
    task feed_stimulus;
        input integer send_tlast;
        begin
            for (ii = 0; ii < STIM_DEPTH; ii = ii + 1) begin
                @(posedge aclk);
                s_axis_tdata  = stim_mem[ii];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (send_tlast && (ii == STIM_DEPTH - 1)) ? 1'b1 : 1'b0;
                while (!s_axis_tready) @(posedge aclk);
            end
            @(posedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    // Poll OUTPUT_COUNT via AXI until it reaches target.
    task wait_output_count;
        input integer target;
        begin
            axi_read(ADDR_OUT_COUNT);
            while (axi_rd_data < target) begin
                repeat (200) @(posedge aclk);
                axi_read(ADDR_OUT_COUNT);
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        // ── Signal initialization ────────────────────────────────────────────
        m_axi_awaddr   = 7'h00;  m_axi_awvalid  = 1'b0;
        m_axi_wdata    = 32'h0;  m_axi_wstrb    = 4'h0;
        m_axi_wvalid   = 1'b0;   m_axi_bready   = 1'b0;
        m_axi_araddr   = 7'h00;  m_axi_arvalid  = 1'b0;
        m_axi_rready   = 1'b0;

        s_axis_tdata   = 32'h0;
        s_axis_tvalid  = 1'b0;
        s_axis_tlast   = 1'b0;

        bp_active      = 1'b0;
        c24_monitor_en = 1'b0;
        c24_reset      = 1'b0;
        c24_expected_step = 32'd0;
        forced_sw      = 32'd0;

        // ── Load stimulus ────────────────────────────────────────────────────
        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ── Initialize C2-2 step_word table ─────────────────────────────────
        // step_word = (-k_int * 2^24) mod 2^32
        c22_step_words[0]  = 32'h00000000;  c22_k_ints_arr[0]  =  0;
        c22_step_words[1]  = 32'hFF000000;  c22_k_ints_arr[1]  =  1;
        c22_step_words[2]  = 32'h01000000;  c22_k_ints_arr[2]  = -1;
        c22_step_words[3]  = 32'hFE000000;  c22_k_ints_arr[3]  =  2;
        c22_step_words[4]  = 32'h02000000;  c22_k_ints_arr[4]  = -2;
        c22_step_words[5]  = 32'hFC000000;  c22_k_ints_arr[5]  =  4;
        c22_step_words[6]  = 32'h04000000;  c22_k_ints_arr[6]  = -4;
        c22_step_words[7]  = 32'hF8000000;  c22_k_ints_arr[7]  =  8;
        c22_step_words[8]  = 32'h08000000;  c22_k_ints_arr[8]  = -8;
        c22_step_words[9]  = 32'hF4000000;  c22_k_ints_arr[9]  = 12;
        c22_step_words[10] = 32'h0C000000;  c22_k_ints_arr[10] = -12;
        c22_step_words[11] = 32'hF0000000;  c22_k_ints_arr[11] = 16;
        c22_step_words[12] = 32'h10000000;  c22_k_ints_arr[12] = -16;

        // ── Hard reset ───────────────────────────────────────────────────────
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);

        // Enable DUT (enable=1, soft_reset=0)
        axi_write(ADDR_CONTROL, 32'h00000001);
        repeat (5) @(posedge aclk);

        $display("=== [C2] Replay Correction Hardening — Session C2 / P3-14D ===");
        $display("  Cycle start: %0d", cycle_cnt);

        // ====================================================================
        // C2-1: Replay Backpressure
        // Pattern: 5-ready / 3-stall, max burst stall = 3 cycles.
        // Verify: output_count==576, tlast_count==1, STALL_TIMEOUT==0.
        // ====================================================================
        $display("");
        $display("--- C2-1: Replay Backpressure ---");

        do_soft_reset;
        bp_active = 1'b1;
        feed_stimulus(1);
        wait_output_count(FRAME_LEN);
        repeat (20) @(posedge aclk);
        bp_active = 1'b0;

        axi_read(ADDR_OUT_COUNT);    c21_out_count  = axi_rd_data;
        axi_read(ADDR_TLAST_CNT);   c21_tlast_count = axi_rd_data;
        axi_read(ADDR_ERROR_FLAGS);  c21_err_flags   = axi_rd_data;

        c21_pass = ((c21_out_count  == FRAME_LEN) &&
                    (c21_tlast_count == 1)          &&
                    ((c21_err_flags & 4'h8) == 0))   ? 1 : 0;

        $display("  output_count  : %0d  (expected %0d)  %s",
                 c21_out_count, FRAME_LEN,
                 (c21_out_count == FRAME_LEN) ? "OK" : "FAIL");
        $display("  tlast_count   : %0d  (expected 1)  %s",
                 c21_tlast_count, (c21_tlast_count == 1) ? "OK" : "FAIL");
        $display("  error_flags   : 0x%0X  stall_timeout=%0d  %s",
                 c21_err_flags, (c21_err_flags >> 3) & 1,
                 ((c21_err_flags & 4'h8) == 0) ? "OK" : "FAIL");
        $display("  C2-1: %s", c21_pass ? "PASS" : "FAIL");
        $display("C21_RESULT backpressure_count=%0d tlast_count=%0d stall_timeout=%0d c21_pass=%0d",
                 c21_out_count, c21_tlast_count, (c21_err_flags >> 3) & 1, c21_pass);

        // ====================================================================
        // C2-2: Integer CFO Sweep Replay
        // For each of 13 k_int values: soft reset, force step_word, run frame.
        // Verify: output_count=576, INT_CFO_APPLIED=1, tlast_count=1.
        // FRAME_LEN_MISMATCH error flag (bit 0) is expected; not checked.
        // ====================================================================
        $display("");
        $display("--- C2-2: Integer CFO Sweep Replay (%0d cases) ---", N_CFO_CASES);

        c22_pass_count = 0;

        for (jj = 0; jj < N_CFO_CASES; jj = jj + 1) begin
            do_soft_reset;

            forced_sw = c22_step_words[jj];
            force u_dut.dut_int_cfo_word = forced_sw;

            feed_stimulus(1);
            wait_output_count(FRAME_LEN);
            repeat (10) @(posedge aclk);

            axi_read(ADDR_OUT_COUNT);   c22_this_oc    = axi_rd_data;
            axi_read(ADDR_INT_CFO_A);   c22_this_ia    = axi_rd_data;
            axi_read(ADDR_TLAST_CNT);   c22_this_tlast = axi_rd_data;

            release u_dut.dut_int_cfo_word;

            if ((c22_this_oc    == FRAME_LEN) &&
                (c22_this_ia[0] == 1'b1)       &&
                (c22_this_tlast == 1)) begin
                c22_pass_count = c22_pass_count + 1;
                $display("  k_int=%4d  step=0x%08X  oc=%0d  ia=%0d  tlast=%0d  PASS",
                         c22_k_ints_arr[jj], c22_step_words[jj],
                         c22_this_oc, c22_this_ia[0], c22_this_tlast);
            end else begin
                $display("  k_int=%4d  step=0x%08X  oc=%0d  ia=%0d  tlast=%0d  FAIL",
                         c22_k_ints_arr[jj], c22_step_words[jj],
                         c22_this_oc, c22_this_ia[0], c22_this_tlast);
            end
        end

        c22_pass = (c22_pass_count == N_CFO_CASES) ? 1 : 0;
        $display("  C2-2: %0d/%0d passed  %s",
                 c22_pass_count, N_CFO_CASES, c22_pass ? "PASS" : "FAIL");
        $display("C22_RESULT k_pass=%0d k_fail=%0d c22_pass=%0d",
                 c22_pass_count, N_CFO_CASES - c22_pass_count, c22_pass);

        // ====================================================================
        // C2-3: Replay Restart (4 consecutive frames, no inter-frame reset)
        // Auto-rearm: after replay_done, start_armed fires and DUT re-starts.
        // output_count accumulates across frames (no reset between them).
        // Checks: absolute output_count == 576 * (frame+1) after each frame.
        // ====================================================================
        $display("");
        $display("--- C2-3: Replay Restart (4 frames, no reset) ---");

        do_soft_reset;

        for (jj = 0; jj < 4; jj = jj + 1) begin
            feed_stimulus(1);
            wait_output_count((jj + 1) * FRAME_LEN);
            repeat (20) @(posedge aclk);
            axi_read(ADDR_OUT_COUNT);
            c23_frame_oc[jj] = axi_rd_data;
            $display("  frame %0d: output_count=%0d  (expected %0d)  %s",
                     jj, c23_frame_oc[jj], (jj + 1) * FRAME_LEN,
                     (c23_frame_oc[jj] == (jj + 1) * FRAME_LEN) ? "OK" : "FAIL");
        end

        c23_pass = ((c23_frame_oc[0] == 1 * FRAME_LEN) &&
                    (c23_frame_oc[1] == 2 * FRAME_LEN) &&
                    (c23_frame_oc[2] == 3 * FRAME_LEN) &&
                    (c23_frame_oc[3] == 4 * FRAME_LEN)) ? 1 : 0;
        $display("  C2-3: %s", c23_pass ? "PASS" : "FAIL");
        $display("C23_RESULT frame0_oc=%0d frame1_oc=%0d frame2_oc=%0d frame3_oc=%0d c23_pass=%0d",
                 c23_frame_oc[0], c23_frame_oc[1], c23_frame_oc[2], c23_frame_oc[3],
                 c23_pass);

        // ====================================================================
        // C2-4: Rotator Stability
        //
        // Phase continuity: monitor int_nco_phase_acc on every replay_rd
        // handshake. Consecutive deltas must equal the natural step_word
        // (whatever Meyr computed from the golden stimulus). After warmup,
        // the NCO advances by exactly step_word per accepted replay beat.
        //
        // Phase reset: after a second soft reset, verify int_nco_phase_acc
        // returns to 0 before any new Meyr result fires.
        //
        // The expected step_word for C2-4 is the natural Meyr output for
        // the golden stimulus. We determine it by reading INT_CFO_EST after
        // the frame completes, then use that value to validate the monitor.
        // ====================================================================
        $display("");
        $display("--- C2-4: Rotator Stability ---");

        do_soft_reset;

        // Clear phase monitor state
        c24_reset = 1'b1;
        @(posedge aclk);
        c24_reset = 1'b0;

        // Pre-configure expected step to 0; will update after Meyr fires.
        // We rely on natural Meyr: start monitoring from first replay beat.
        // The delta check will use c24_expected_step set before monitor is active.
        // Since we don't know step_word ahead of time, we set it AFTER one frame.
        // Two-pass approach:
        //   Pass 1: run frame, read INT_CFO_EST, learn actual step_word
        //   Pass 2: run second frame (after soft reset), monitor with known step_word

        // Pass 1: determine natural step_word
        feed_stimulus(1);
        wait_output_count(FRAME_LEN);
        repeat (10) @(posedge aclk);

        axi_read(7'h3C);  // INT_CFO_EST
        c24_expected_step = axi_rd_data;
        $display("  Natural step_word from Meyr: 0x%08X", c24_expected_step);

        // Pass 2: soft reset, enable monitor, run frame, check phase deltas
        do_soft_reset;

        c24_reset = 1'b1;
        @(posedge aclk);
        c24_reset = 1'b0;

        c24_monitor_en = 1'b1;
        feed_stimulus(1);
        wait_output_count(FRAME_LEN);
        repeat (20) @(posedge aclk);
        c24_monitor_en = 1'b0;

        c24_phase_cont_ok = ((c24_phase_errors == 32'd0) && (c24_sample_cnt >= FRAME_LEN)) ? 1 : 0;

        $display("  Phase continuity: errors=%0d  samples=%0d  expected_step=0x%08X  %s",
                 c24_phase_errors, c24_sample_cnt, c24_expected_step,
                 c24_phase_cont_ok ? "PASS" : "FAIL");

        // Phase reset check: after soft reset, int_nco_phase_acc must be 0
        // (step_word=0 after reset, phase_acc cleared by aresetn).
        do_soft_reset;
        repeat (5) @(posedge aclk);
        c24_phase_reset_ok = (u_dut.int_nco_phase_acc == {NCO_PHASE_WIDTH{1'b0}}) ? 1 : 0;

        $display("  Phase reset: int_nco_phase_acc=0x%08X  %s",
                 u_dut.int_nco_phase_acc, c24_phase_reset_ok ? "PASS" : "FAIL");

        c24_pass = (c24_phase_cont_ok && c24_phase_reset_ok) ? 1 : 0;
        $display("  C2-4: %s", c24_pass ? "PASS" : "FAIL");
        $display("C24_RESULT phase_cont_ok=%0d phase_reset_ok=%0d sample_cnt=%0d c24_pass=%0d",
                 c24_phase_cont_ok, c24_phase_reset_ok, c24_sample_cnt, c24_pass);

        // ====================================================================
        // Gate decision
        // ====================================================================
        repeat (10) @(posedge aclk);

        gate_pass = (c21_pass && c22_pass && c23_pass && c24_pass) ? 1 : 0;

        $display("");
        $display("=== [C2] Replay Hardening Summary ===");
        $display("  C2-1 Backpressure     : %s", c21_pass ? "PASS" : "FAIL");
        $display("  C2-2 CFO Sweep        : %s  (%0d/%0d)", c22_pass ? "PASS" : "FAIL", c22_pass_count, N_CFO_CASES);
        $display("  C2-3 Restart (4x)     : %s", c23_pass ? "PASS" : "FAIL");
        $display("  C2-4 Rotator Stability: %s", c24_pass ? "PASS" : "FAIL");
        $display("  Total cycles          : %0d", cycle_cnt);
        $display("");

        if (gate_pass) begin
            $display("REPLAY_HARDENING_GATE: PASS");
            $display("  All four replay hardening phases passed.");
        end else begin
            $display("REPLAY_HARDENING_GATE: FAIL");
            if (!c21_pass) $display("  C2-1 FAIL: backpressure test failed (count=%0d tlast=%0d stall_to=%0d)",
                                    c21_out_count, c21_tlast_count, (c21_err_flags >> 3) & 1);
            if (!c22_pass) $display("  C2-2 FAIL: %0d/%0d CFO sweep cases failed",
                                    N_CFO_CASES - c22_pass_count, N_CFO_CASES);
            if (!c23_pass) $display("  C2-3 FAIL: restart counts were %0d %0d %0d %0d",
                                    c23_frame_oc[0], c23_frame_oc[1], c23_frame_oc[2], c23_frame_oc[3]);
            if (!c24_pass) $display("  C2-4 FAIL: phase_cont=%0d phase_reset=%0d errors=%0d",
                                    c24_phase_cont_ok, c24_phase_reset_ok, c24_phase_errors);
        end

        $finish;
    end

endmodule
