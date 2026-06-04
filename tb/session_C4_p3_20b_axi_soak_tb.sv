`timescale 1ns/1ps

// session_C4_p3_20b_axi_soak_tb — P3-20B AXI Soak Test
//
// DUT: phase3_sync_axis_dma_wrapper
// CHK: tb/common/axi_stream_checker.sv (M_AXIS, assertions A1-A5)
//
// Mode selection via plusarg +MODE=<mode>:
//   quick    10 frames B1 + 10 frames B3 each (no B2); watchdog 15M cycles
//   standard 100 frames B1 + 100 frames B3 each (no B2); watchdog 80M cycles
//   soak     100 frames B1 + 1000 frames B2 + 100 frames B3 each; watchdog 220M cycles
//   (default = standard if no plusarg)
//
// Phases:
//   B1   N frames back-to-back, no backpressure
//   B2   1000 frames back-to-back, no backpressure  (soak only)
//   B3   N frames × 10% / 25% / 50% M_AXIS stall
//   B4   replay_done count == total frames (global, across all phases)
//   B5   output_count never decreases between frames
//   CHK  AXI-S checker A1-A5 on M_AXIS throughout
//
// Gate:
//   AXI_SOAK_GATE: PASS  — all active phases pass
//   AXI_SOAK_GATE: FAIL  — any failure

module session_C4_p3_20b_axi_soak_tb;

    // -----------------------------------------------------------------------
    // Static parameters
    // -----------------------------------------------------------------------
    localparam integer IQ_WIDTH     = 16;
    localparam integer NSC          = 256;
    localparam integer CP_LEN       = 32;
    localparam integer BUF_AW       = 12;
    localparam integer NCO_PW       = 32;
    localparam integer FRAME_LEN    = 2 * (NSC + CP_LEN);  // 576
    localparam integer THRESHOLD_TB = 40000;
    localparam integer STIM_DEPTH   = 704;

    // AXI-Lite addresses
    localparam [6:0] ADDR_CONTROL    = 7'h04;
    localparam [6:0] ADDR_OUT_COUNT  = 7'h14;
    localparam [6:0] ADDR_TLAST_CNT  = 7'h50;
    localparam [6:0] ADDR_ERROR_FLAGS= 7'h54;

    // -----------------------------------------------------------------------
    // Mode: determined at time-0 from plusarg, used by watchdog + test body
    // -----------------------------------------------------------------------
    integer tb_mode;       // 0=quick 1=standard 2=soak
    integer n_b1_frames;
    integer n_b2_frames;   // 0 = skip B2
    integer n_b3_frames;
    integer prog_interval; // print every N frames
    reg [31:0] watchdog_limit;

    // -----------------------------------------------------------------------
    // Clock / Reset
    // -----------------------------------------------------------------------
    reg aclk;
    reg aresetn;
    initial aclk = 1'b0;
    always #5 aclk = ~aclk;

    // -----------------------------------------------------------------------
    // AXI-Lite master
    // -----------------------------------------------------------------------
    reg  [6:0]  m_axi_awaddr;  reg         m_axi_awvalid; wire        m_axi_awready;
    reg  [31:0] m_axi_wdata;   reg  [3:0]  m_axi_wstrb;   reg         m_axi_wvalid;
    wire        m_axi_wready;  wire [1:0]  m_axi_bresp;   wire        m_axi_bvalid;
    reg         m_axi_bready;
    reg  [6:0]  m_axi_araddr;  reg         m_axi_arvalid; wire        m_axi_arready;
    wire [31:0] m_axi_rdata;   wire [1:0]  m_axi_rresp;   wire        m_axi_rvalid;
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
        .BUF_AW          (BUF_AW),
        .THRESHOLD       (THRESHOLD_TB),
        .NCO_PHASE_WIDTH (NCO_PW)
    ) u_dut (
        .aclk               (aclk),            .aresetn            (aresetn),
        .s_axi_awaddr       (m_axi_awaddr),    .s_axi_awvalid      (m_axi_awvalid),
        .s_axi_awready      (m_axi_awready),   .s_axi_wdata        (m_axi_wdata),
        .s_axi_wstrb        (m_axi_wstrb),     .s_axi_wvalid       (m_axi_wvalid),
        .s_axi_wready       (m_axi_wready),    .s_axi_bresp        (m_axi_bresp),
        .s_axi_bvalid       (m_axi_bvalid),    .s_axi_bready       (m_axi_bready),
        .s_axi_araddr       (m_axi_araddr),    .s_axi_arvalid      (m_axi_arvalid),
        .s_axi_arready      (m_axi_arready),   .s_axi_rdata        (m_axi_rdata),
        .s_axi_rresp        (m_axi_rresp),     .s_axi_rvalid       (m_axi_rvalid),
        .s_axi_rready       (m_axi_rready),
        .s_axis_tdata       (s_axis_tdata),    .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),   .s_axis_tlast       (s_axis_tlast),
        .m_axis_tdata       (m_axis_tdata),    .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),   .m_axis_tlast       (m_axis_tlast),
        .dbg_frac_m_tdata   (dbg_frac_m_tdata),
        .dbg_frac_m_tvalid  (dbg_frac_m_tvalid),
        .dbg_frac_m_tready  (dbg_frac_m_tready),
        .dbg_frac_m_tlast   (dbg_frac_m_tlast)
    );

    // -----------------------------------------------------------------------
    // AXI-Stream checker (Part A — M_AXIS)
    // -----------------------------------------------------------------------
    reg         chk_enable;
    wire [31:0] chk_err_tdata, chk_err_tlast;
    wire [31:0] chk_err_xv, chk_err_xd, chk_err_xl;
    wire [31:0] chk_err_dtlast, chk_warn_stall;
    wire [31:0] chk_total_errors;

    axi_stream_checker #(
        .DATA_WIDTH        (2*IQ_WIDTH),
        .STALL_WARN_THRESH (1000)
    ) u_m_chk (
        .aclk                (aclk),
        .aresetn             (aresetn),
        .tvalid              (m_axis_tvalid),
        .tready              (m_axis_tready),
        .tdata               (m_axis_tdata),
        .tlast               (m_axis_tlast),
        .enable              (chk_enable),
        .err_tdata_stability (chk_err_tdata),
        .err_tlast_stability (chk_err_tlast),
        .err_x_tvalid        (chk_err_xv),
        .err_x_tdata         (chk_err_xd),
        .err_x_tlast         (chk_err_xl),
        .err_double_tlast    (chk_err_dtlast),
        .warn_long_stall     (chk_warn_stall),
        .total_errors        (chk_total_errors)
    );

    // -----------------------------------------------------------------------
    // Watchdog — limit set from mode at time-0 in main initial block
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    initial cycle_cnt = 0;
    always @(posedge aclk) cycle_cnt = cycle_cnt + 1;

    initial begin
        forever begin
            @(posedge aclk);
            if (cycle_cnt > watchdog_limit) begin
                $display("WDG: TIMEOUT at %0d cycles (limit=%0d)",
                         cycle_cnt, watchdog_limit);
                $display("AXI_SOAK_GATE: FAIL");
                $finish;
            end
        end
    end

    // -----------------------------------------------------------------------
    // B4: global replay_done pulse counter
    // -----------------------------------------------------------------------
    reg [31:0] b4_replay_done_cnt;
    always @(posedge aclk) begin
        if (!aresetn)
            b4_replay_done_cnt <= 32'd0;
        else if (u_dut.replay_done)
            b4_replay_done_cnt <= b4_replay_done_cnt + 32'd1;
    end

    // -----------------------------------------------------------------------
    // B5: output_count backward-motion check
    // Suppressed for 2 cycles around soft-reset using dut_aresetn edge detect.
    // -----------------------------------------------------------------------
    reg [31:0] b5_prev_oc;
    reg [31:0] b5_err_backward;
    reg        b5_dut_aresetn_d;

    always @(posedge aclk) begin
        if (!aresetn) begin
            b5_prev_oc       <= 32'd0;
            b5_err_backward  <= 32'd0;
            b5_dut_aresetn_d <= 1'b1;
        end else begin
            b5_dut_aresetn_d <= u_dut.dut_aresetn;
            if (u_dut.dut_aresetn && b5_dut_aresetn_d &&
                (u_dut.output_count < b5_prev_oc)) begin
                b5_err_backward <= b5_err_backward + 32'd1;
                $display("[B5 @%0t] output_count backward: prev=%0d now=%0d",
                         $time, b5_prev_oc, u_dut.output_count);
            end
            b5_prev_oc <= u_dut.output_count;
        end
    end

    // -----------------------------------------------------------------------
    // M_AXIS random stall: 7-bit primitive LFSR (x^7+x^3+1, period 127)
    // -----------------------------------------------------------------------
    reg [6:0] m_lfsr;
    integer   m_stall_thresh;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tready <= 1'b1;
            m_lfsr        <= 7'h2D;
        end else begin
            m_lfsr <= {m_lfsr[5:0], m_lfsr[6] ^ m_lfsr[2]};
            m_axis_tready <= (m_stall_thresh == 0) ? 1'b1 :
                             (m_lfsr >= m_stall_thresh[6:0]) ? 1'b1 : 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // Stimulus memory and shared task variables
    // -----------------------------------------------------------------------
    reg [31:0] stim_mem [0:STIM_DEPTH-1];
    reg [6:0]  s_lfsr;
    integer    s_gap_thresh;
    reg [31:0] axi_rd_data;
    integer    ii;

    // Scratch used by run_soak_phase (sequential, no re-entrance issue)
    integer phase_fi;
    integer phase_expected_oc;
    integer phase_rd_oc;
    integer phase_rd_tlast;
    integer phase_rd_err;
    integer phase_b4_base;

    // Top-level pass flags
    integer b1_pass, b2_pass;
    integer b3a_pass, b3b_pass, b3c_pass, b3_pass;
    integer b4_pass, b5_pass, chk_pass;
    integer gate_pass;

    reg [63:0] mode_str;  // 8-char right-padded mode name for display

    // -----------------------------------------------------------------------
    // 7-bit primitive LFSR step function
    // -----------------------------------------------------------------------
    function [6:0] lfsr7_step;
        input [6:0] s;
        begin
            lfsr7_step = {s[5:0], s[6] ^ s[2]};
        end
    endfunction

    // -----------------------------------------------------------------------
    // AXI-Lite tasks
    // -----------------------------------------------------------------------
    task axi_write;
        input [6:0]  addr;
        input [31:0] data;
        begin
            @(posedge aclk);
            m_axi_awaddr  = addr;  m_axi_awvalid = 1'b1;
            m_axi_wdata   = data;  m_axi_wstrb   = 4'hF;
            m_axi_wvalid  = 1'b1;  m_axi_bready  = 1'b1;
            while (!(m_axi_awready && m_axi_wready)) @(posedge aclk);
            @(posedge aclk);
            m_axi_awvalid = 1'b0;  m_axi_wvalid = 1'b0;
            while (!m_axi_bvalid) @(posedge aclk);
            @(posedge aclk);
            m_axi_bready = 1'b0;
        end
    endtask

    task axi_read;
        input [6:0] addr;
        begin
            @(posedge aclk);
            m_axi_araddr  = addr;  m_axi_arvalid = 1'b1;
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

    task do_soft_reset;
        begin
            axi_write(ADDR_CONTROL, 32'h00000003);
            repeat (30) @(posedge aclk);
        end
    endtask

    // -----------------------------------------------------------------------
    // wait_oc: spin on u_dut.output_count (direct, avoids AXI polling overhead)
    // -----------------------------------------------------------------------
    task wait_oc;
        input integer target;
        begin
            while (u_dut.output_count < target) repeat (500) @(posedge aclk);
        end
    endtask

    // -----------------------------------------------------------------------
    // feed_one_frame: feed STIM_DEPTH samples, waiting for tready per sample.
    // s_gap_thresh = 0 means continuous; non-zero inserts one idle cycle with
    // probability s_gap_thresh/128 before each sample.
    // -----------------------------------------------------------------------
    task feed_one_frame;
        begin
            for (ii = 0; ii < STIM_DEPTH; ii = ii + 1) begin
                s_lfsr = lfsr7_step(s_lfsr);
                if ((s_gap_thresh > 0) && (s_lfsr < s_gap_thresh[6:0])) begin
                    @(posedge aclk);
                    s_axis_tvalid = 1'b0;
                    s_axis_tdata  = 32'h0;
                    s_axis_tlast  = 1'b0;
                end
                @(posedge aclk);
                s_axis_tdata  = stim_mem[ii];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (ii == STIM_DEPTH - 1) ? 1'b1 : 1'b0;
                while (!s_axis_tready) @(posedge aclk);
            end
            @(posedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // run_soak_phase: soft reset, run n_frames, wait, read registers, report.
    // Progress printed every prog_interval frames (module-level variable).
    // Output: pass=1 iff output_count/tlast_count match and no STALL_TIMEOUT.
    // -----------------------------------------------------------------------
    task run_soak_phase;
        input  integer n_frames;
        input  integer stall_thr;
        output integer pass;
        begin
            do_soft_reset;
            m_stall_thresh    = stall_thr;
            s_gap_thresh      = 0;
            s_lfsr            = 7'h1D;
            phase_expected_oc = FRAME_LEN * n_frames;
            phase_b4_base     = b4_replay_done_cnt;

            for (phase_fi = 0; phase_fi < n_frames; phase_fi = phase_fi + 1) begin
                feed_one_frame;
                if (((phase_fi + 1) % prog_interval == 0) ||
                    (phase_fi == n_frames - 1)) begin
                    $display("    frame %0d/%0d  oc=%0d  replay_done=%0d  cycle=%0d",
                             phase_fi + 1, n_frames,
                             u_dut.output_count,
                             b4_replay_done_cnt - phase_b4_base,
                             cycle_cnt);
                end
            end

            wait_oc(phase_expected_oc);
            repeat (30) @(posedge aclk);

            if (u_dut.replay_busy)
                $display("  [B4] WARNING: replay_busy still high after completion");

            axi_read(ADDR_OUT_COUNT);    phase_rd_oc    = axi_rd_data;
            axi_read(ADDR_TLAST_CNT);    phase_rd_tlast = axi_rd_data;
            axi_read(ADDR_ERROR_FLAGS);  phase_rd_err   = axi_rd_data;

            pass = ((phase_rd_oc    == phase_expected_oc) &&
                    (phase_rd_tlast == n_frames)           &&
                    ((phase_rd_err & 4'h8) == 0))          ? 1 : 0;

            $display("  out=%0d  tlast=%0d  err=0x%X  replay_done=%0d  b5_bk=%0d  %s",
                     phase_rd_oc, phase_rd_tlast, phase_rd_err,
                     b4_replay_done_cnt - phase_b4_base,
                     b5_err_backward,
                     pass ? "PASS" : "FAIL");
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        // ── Mode selection (time-0, before first clock edge) ─────────────────
        if      ($test$plusargs("MODE=quick")) tb_mode = 0;
        else if ($test$plusargs("MODE=soak"))  tb_mode = 2;
        else                                    tb_mode = 1;  // standard

        case (tb_mode)
            0: begin  // quick
                n_b1_frames   = 10;
                n_b2_frames   = 0;
                n_b3_frames   = 10;
                prog_interval = 1;
                watchdog_limit = 32'd15_000_000;
            end
            2: begin  // soak
                n_b1_frames   = 100;
                n_b2_frames   = 1000;
                n_b3_frames   = 100;
                prog_interval = 100;
                watchdog_limit = 32'd220_000_000;
            end
            default: begin  // standard
                n_b1_frames   = 100;
                n_b2_frames   = 0;
                n_b3_frames   = 100;
                prog_interval = 10;
                watchdog_limit = 32'd80_000_000;
            end
        endcase
        case (tb_mode)
            0:       mode_str = "quick   ";
            2:       mode_str = "soak    ";
            default: mode_str = "standard";
        endcase

        // ── Signal initialisation ────────────────────────────────────────────
        m_axi_awaddr  = 7'h00;   m_axi_awvalid = 1'b0;
        m_axi_wdata   = 32'h0;   m_axi_wstrb   = 4'h0;
        m_axi_wvalid  = 1'b0;    m_axi_bready  = 1'b0;
        m_axi_araddr  = 7'h00;   m_axi_arvalid = 1'b0;   m_axi_rready = 1'b0;
        s_axis_tdata  = 32'h0;   s_axis_tvalid = 1'b0;   s_axis_tlast = 1'b0;
        m_stall_thresh = 0;
        s_gap_thresh   = 0;
        s_lfsr         = 7'h1D;
        chk_enable     = 1'b0;
        b2_pass        = 1;  // default pass for skipped B2

        $readmemh("golden/phase3_iq_stimulus.mem", stim_mem);

        // ── Hard reset ───────────────────────────────────────────────────────
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (5)  @(posedge aclk);
        axi_write(ADDR_CONTROL, 32'h00000001);  // enable=1
        repeat (5) @(posedge aclk);
        chk_enable = 1'b1;

        $display("=== [C4] AXI Soak Test — P3-20B ===");
        $display("  Mode: %s  watchdog: %0d  B1=%0d B2=%0d B3=%0d frames",
                 mode_str, watchdog_limit, n_b1_frames, n_b2_frames, n_b3_frames);

        // ====================================================================
        // B1
        // ====================================================================
        $display("");
        $display("--- B1: %0d frames, stall=0%% ---", n_b1_frames);
        run_soak_phase(n_b1_frames, 0, b1_pass);
        $display("B1_RESULT: %s  (out=%0d tlast=%0d)",
                 b1_pass ? "PASS":"FAIL", phase_rd_oc, phase_rd_tlast);

        // ====================================================================
        // B2 (soak only)
        // ====================================================================
        if (n_b2_frames > 0) begin
            $display("");
            $display("--- B2: %0d frames, stall=0%% ---", n_b2_frames);
            run_soak_phase(n_b2_frames, 0, b2_pass);
            $display("B2_RESULT: %s  (out=%0d tlast=%0d)",
                     b2_pass ? "PASS":"FAIL", phase_rd_oc, phase_rd_tlast);
        end else begin
            $display("");
            $display("--- B2: SKIPPED (mode=%s) ---", mode_str);
            $display("B2_RESULT: SKIP");
        end

        // ====================================================================
        // B3
        // ====================================================================
        $display("");
        $display("--- B3a: %0d frames, stall=10%% ---", n_b3_frames);
        run_soak_phase(n_b3_frames, 13, b3a_pass);

        $display("");
        $display("--- B3b: %0d frames, stall=25%% ---", n_b3_frames);
        run_soak_phase(n_b3_frames, 32, b3b_pass);

        $display("");
        $display("--- B3c: %0d frames, stall=50%% ---", n_b3_frames);
        run_soak_phase(n_b3_frames, 64, b3c_pass);

        b3_pass = (b3a_pass && b3b_pass && b3c_pass) ? 1 : 0;
        $display("B3_RESULT: %s  (a=%s b=%s c=%s)",
                 b3_pass?"PASS":"FAIL",
                 b3a_pass?"PASS":"FAIL", b3b_pass?"PASS":"FAIL", b3c_pass?"PASS":"FAIL");

        // ====================================================================
        // B4: replay_done count
        // Expected = B1 + B2 + 3*B3
        // ====================================================================
        begin : b4_check
            integer b4_expected;
            b4_expected = n_b1_frames + n_b2_frames + 3 * n_b3_frames;
            $display("");
            $display("--- B4: Replay restart soak ---");
            $display("  Total replay_done: %0d  expected: %0d",
                     b4_replay_done_cnt, b4_expected);
            // Accept ±2 tolerance for soft-reset boundary timing
            b4_pass = ((b4_replay_done_cnt >= b4_expected - 2) &&
                       (b4_replay_done_cnt <= b4_expected + 2)) ? 1 : 0;
            $display("B4_RESULT: %s  (replay_done=%0d expected=%0d)",
                     b4_pass?"PASS":"FAIL", b4_replay_done_cnt, b4_expected);
        end

        // ====================================================================
        // B5: counter stability
        // ====================================================================
        $display("");
        $display("--- B5: Counter stability ---");
        b5_pass = (b5_err_backward == 0) ? 1 : 0;
        $display("B5_RESULT: %s  (backward_errors=%0d)",
                 b5_pass?"PASS":"FAIL", b5_err_backward);

        // ====================================================================
        // Checker summary (A1-A5)
        // ====================================================================
        $display("");
        $display("--- Checker (A1-A5) ---");
        $display("  A1 tdata stability : %0d", chk_err_tdata);
        $display("  A2 tlast stability : %0d", chk_err_tlast);
        $display("  A3 X tvalid/tdata/tlast : %0d / %0d / %0d",
                 chk_err_xv, chk_err_xd, chk_err_xl);
        $display("  A4 double TLAST    : %0d", chk_err_dtlast);
        $display("  A5 long stall warns: %0d", chk_warn_stall);
        $display("  total_errors       : %0d", chk_total_errors);
        chk_pass = (chk_total_errors == 0) ? 1 : 0;
        $display("CHK_RESULT: %s", chk_pass?"PASS":"FAIL");

        // ====================================================================
        // Gate
        // ====================================================================
        gate_pass = (b1_pass && b2_pass && b3_pass &&
                     b4_pass && b5_pass && chk_pass) ? 1 : 0;

        $display("");
        $display("=== [C4] Results (%s mode) ===", mode_str);
        $display("  B1  %0d frames no-stall  : %s", n_b1_frames,  b1_pass ?"PASS":"FAIL");
        if (n_b2_frames > 0)
            $display("  B2  %0d frames no-stall  : %s", n_b2_frames,  b2_pass ?"PASS":"FAIL");
        else
            $display("  B2  (skipped)");
        $display("  B3a %0d frames 10%% stall : %s", n_b3_frames, b3a_pass?"PASS":"FAIL");
        $display("  B3b %0d frames 25%% stall : %s", n_b3_frames, b3b_pass?"PASS":"FAIL");
        $display("  B3c %0d frames 50%% stall : %s", n_b3_frames, b3c_pass?"PASS":"FAIL");
        $display("  B4  replay restart soak : %s",              b4_pass ?"PASS":"FAIL");
        $display("  B5  counter stability   : %s",              b5_pass ?"PASS":"FAIL");
        $display("  CHK A1-A4 assertions    : %s",              chk_pass?"PASS":"FAIL");
        $display("  Total cycles: %0d", cycle_cnt);

        $display("");
        $display("B1_GATE: %s",  b1_pass ?"PASS":"FAIL");
        $display("B2_GATE: %s",  b2_pass ?"PASS":"FAIL");
        $display("B3_GATE: %s",  b3_pass ?"PASS":"FAIL");
        $display("B4_GATE: %s",  b4_pass ?"PASS":"FAIL");
        $display("B5_GATE: %s",  b5_pass ?"PASS":"FAIL");
        $display("CHK_GATE: %s", chk_pass?"PASS":"FAIL");

        if (gate_pass)
            $display("AXI_SOAK_GATE: PASS");
        else begin
            $display("AXI_SOAK_GATE: FAIL");
            if (!b1_pass)  $display("  FAIL B1");
            if (!b2_pass)  $display("  FAIL B2");
            if (!b3_pass)  $display("  FAIL B3 (a=%0d b=%0d c=%0d)", b3a_pass, b3b_pass, b3c_pass);
            if (!b4_pass)  $display("  FAIL B4: replay_done=%0d", b4_replay_done_cnt);
            if (!b5_pass)  $display("  FAIL B5: %0d backward events", b5_err_backward);
            if (!chk_pass) $display("  FAIL CHK: %0d total errors", chk_total_errors);
        end

        $finish;
    end

endmodule
