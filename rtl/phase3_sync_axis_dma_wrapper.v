`timescale 1ns/1ps

// phase3_sync_axis_dma_wrapper — P3-14B
// Board-integration wrapper: wraps phase3_sync_top with AXI-Lite control/status
// registers, enable gating, soft reset, replay buffer, integer CFO correction,
// input/output counters, TLAST generation, bypass mode, and wrapper-level error flags.
//
// P3-14B additions over P3-14A:
//   - iq_replay_buffer_576: captures frac-corrected IQ during frame run
//   - nco_phase_gen (u_int_nco): integer CFO step word → sin/cos
//   - complex_rotator (u_int_rot): applies integer correction to replayed IQ
//   - M_AXIS now carries fully corrected (frac + integer) IQ stream
//   - INT_CFO_APPLIED and INT_CFO_INDEX registers fully wired
//   - Start re-arm deferred until replay_done (prevents capture collision)
//
// Pipeline (non-bypass):
//   S_AXIS → phase3_sync_top (frac corr + Meyr) → replay buffer (capture)
//            ↓ (after Meyr done)
//   replay buffer → integer NCO + rotator → M_AXIS (DMA)
//
// Enable gate:
//   enable=0 → s_axis_tready=0, m_axis_tvalid=0.
//   enable=1 → normal or bypass mode.
//
// Bypass mode (bypass_enable=1):
//   S_AXIS passes directly to M_AXIS. DUT and replay buffer receive no data.
//
// Start/done/replay protocol:
//   After dut_aresetn rising edge: start_armed=1 → start fires.
//   After meyr_done (int_cfo_valid): replay_start fires; replay buffer plays back.
//   After replay_done: start_armed=1 (re-arm for next frame).
//   After error (done && error):  start_armed=0; wait for soft_reset.
//
// TLAST generation:
//   Counter-based M_AXIS TLAST, counter period = FRAME_LEN_SAMPLES register (default 576).
//   The replay buffer outputs exactly FRAME_LEN beats per replay, so the counter
//   fires naturally on each replay cycle.
//
// INT_CFO_APPLIED:
//   Sticky bit; set when replay_busy first asserts. Cleared by dut_aresetn.

module phase3_sync_axis_dma_wrapper #(
    parameter integer IQ_WIDTH        = 16,
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
    parameter integer BUF_AW          = 12,
    parameter integer ACC_WIDTH       = 40,
    parameter integer METRIC_WIDTH    = 32,
    parameter integer INDEX_WIDTH     = 9,
    parameter integer RESULT_WIDTH    = 32,
    parameter integer PHASE_WIDTH     = 16,
    parameter integer POWER_WIDTH     = 33,
    parameter integer ENERGY_WIDTH    = 40,
    parameter integer WINDOW_LEN      = 25,
    parameter integer HIT_COUNT       = 10,
    parameter integer THRESHOLD       = 10240000,
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer CORDIC_LATENCY  = 15
) (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite slave
    input  wire  [6:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire  [3:0] s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire  [1:0] s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire  [6:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire  [1:0] s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI-Stream slave (from DMA, PS → PL raw IQ)
    input  wire [2*IQ_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // AXI-Stream master (PL → DMA): integer-CFO-corrected IQ
    output wire [2*IQ_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    // Debug: frac-corrected stream tap (between frac corrector and extractor)
    output wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata,
    output wire                  dbg_frac_m_tvalid,
    output wire                  dbg_frac_m_tready,
    output wire                  dbg_frac_m_tlast
);

    // -----------------------------------------------------------------------
    // Internal control wires from AXI-Lite register bank
    // -----------------------------------------------------------------------
    wire        int_enable;
    wire        int_soft_reset;
    wire        int_bypass_en;
    wire        int_force_tlast;
    wire        int_counter_clear;
    wire        int_debug_mode;
    wire [11:0] int_frame_len;

    // -----------------------------------------------------------------------
    // Soft reset and dut_aresetn
    // -----------------------------------------------------------------------
    reg  soft_reset_r;
    wire dut_aresetn = aresetn && !soft_reset_r;
    reg  dut_aresetn_prev;

    always @(posedge aclk) soft_reset_r    <= int_soft_reset;
    always @(posedge aclk) dut_aresetn_prev <= dut_aresetn;

    wire reset_done_w    = dut_aresetn && !dut_aresetn_prev;
    wire pipeline_idle_w = (input_count == output_count);

    // -----------------------------------------------------------------------
    // Input/output counters
    // -----------------------------------------------------------------------
    reg [31:0] input_count;
    reg [31:0] output_count;

    wire s_hs = s_axis_tvalid && s_axis_tready;   // accepted input beat
    wire m_hs = m_axis_tvalid && m_axis_tready;   // accepted output beat

    always @(posedge aclk) begin
        if (!dut_aresetn)
            input_count <= 32'd0;
        else if (s_hs)
            input_count <= input_count + 32'd1;
    end

    always @(posedge aclk) begin
        if (!dut_aresetn)
            output_count <= 32'd0;
        else if (m_hs)
            output_count <= output_count + 32'd1;
    end

    // -----------------------------------------------------------------------
    // phase3_sync_top wires
    // -----------------------------------------------------------------------
    wire        dut_s_axis_tready;
    wire        dut_busy;
    wire        dut_done;
    wire        dut_error;
    wire [3:0]  dut_error_code;

    wire                         dut_frame_start_valid;
    wire [BUF_AW-1:0]            dut_frame_start_index;
    wire [INDEX_WIDTH-1:0]       dut_peak_index;
    wire                         dut_slot_start_valid;
    wire [BUF_AW-1:0]            dut_slot_start_index;
    wire                         dut_frac_cfo_valid;
    wire [PHASE_WIDTH-1:0]       dut_frac_cfo_word;
    wire                         dut_int_cfo_valid;
    wire [NCO_PHASE_WIDTH-1:0]   dut_int_cfo_word;

    // P3-14B: frac-corrected stream tap and Meyr peak index
    wire [2*IQ_WIDTH-1:0]  dut_frac_m_tdata;
    wire                   dut_frac_m_tvalid;
    wire                   dut_frac_m_tready;
    wire                   dut_frac_m_tlast;
    wire [INDEX_WIDTH-1:0] dut_meyr_peak_index;

    // -----------------------------------------------------------------------
    // Enable + bypass gating
    //   Normal:  gated S_AXIS → DUT
    //   Bypass:  S_AXIS ↔ M_AXIS; DUT receives nothing
    // -----------------------------------------------------------------------
    wire gated_s_valid = int_enable && !int_bypass_en && s_axis_tvalid;

    assign s_axis_tready = !int_enable ? 1'b0 :
                           int_bypass_en ? m_axis_tready :
                           dut_s_axis_tready;

    // -----------------------------------------------------------------------
    // P3-14B: Replay buffer
    //
    // Captures the frac-corrected IQ stream as a side-channel: wr_valid fires
    // on each accepted beat between frac corrector and pss_sss_symbol_extractor.
    // After Meyr integer CFO estimate arrives (dut_int_cfo_valid), replay starts.
    // The replayed IQ is fed through the integer NCO + rotator to M_AXIS.
    //
    // FRAME_LEN = 2*(NSC+CP_LEN) = 576 for default parameters.
    // REPLAY_AW = 10 → 1024-entry RAM, which is >= 576.
    // -----------------------------------------------------------------------
    localparam integer FRAME_LEN_LP   = 2 * (NSC + CP_LEN);
    localparam integer REPLAY_AW      = 10;
    // Effective NCO latency = LATENCY pipeline stages + 1 output register.
    localparam integer NCO_WU_CYCLES  = CORDIC_LATENCY + 1;

    // Accepted frac-corrected beat (side-channel monitor — does not gate the stream)
    wire frac_hs = dut_frac_m_tvalid & dut_frac_m_tready;

    wire               replay_buf_wr_ready;
    wire               replay_capture_done;
    wire               replay_capture_error;
    wire               replay_busy;
    wire               replay_done;
    wire               replay_rd_valid;
    wire               replay_rd_ready;
    wire [2*IQ_WIDTH-1:0] replay_rd_data;
    wire               replay_rd_tlast;

    // Integer NCO warmup counter.
    // When dut_int_cfo_valid fires the new step_word is latched but sincos_valid
    // is already 1 from prior free-run with step_word=0.  The nco_phase_gen
    // pipeline only advances when enable=1, so we must force enable=1 for
    // exactly CORDIC_LATENCY+1 cycles before replay starts.
    //
    // The +1 accounts for the output register in nco_phase_gen (sin_out_r),
    // which adds one extra cycle of latency beyond the LATENCY-stage pipeline.
    // Effective NCO latency = LATENCY + 1 = 16 cycles total.
    // Replay starts when wu_cnt==1 (the last warmup edge), so the first
    // replay sample handshake occurs exactly when sin_out_r holds phase n=0.
    reg [4:0] int_nco_wu_cnt;
    always @(posedge aclk) begin
        if (!dut_aresetn)
            int_nco_wu_cnt <= 5'd0;
        else if (dut_int_cfo_valid)
            int_nco_wu_cnt <= NCO_WU_CYCLES[4:0];
        else if (int_nco_wu_cnt > 5'd0)
            int_nco_wu_cnt <= int_nco_wu_cnt - 5'd1;
    end
    wire int_nco_wu_active = (int_nco_wu_cnt > 5'd0);

    // replay_start: pulse on the last warmup cycle so the first replay sample
    // is accepted one cycle after the pipeline is fully primed (cnt==1 → 0).
    wire replay_start_w = (int_nco_wu_cnt == 5'd1);

    // Clear replay buffer: after each replay (or error) so next capture is fresh
    reg replay_buf_clear;
    always @(posedge aclk) begin
        if (!dut_aresetn)
            replay_buf_clear <= 1'b0;
        else
            replay_buf_clear <= replay_done | (dut_done & dut_error);
    end

    iq_replay_buffer_576 #(
        .DATA_W    (2*IQ_WIDTH),
        .FRAME_LEN (FRAME_LEN_LP),
        .ADDR_W    (REPLAY_AW)
    ) u_replay_buf (
        .clk           (aclk),
        .aresetn       (dut_aresetn),
        .clear         (replay_buf_clear),
        .wr_valid      (frac_hs),
        .wr_ready      (replay_buf_wr_ready),
        .wr_data       (dut_frac_m_tdata),
        .capture_done  (replay_capture_done),
        .capture_error (replay_capture_error),
        .replay_start  (replay_start_w),
        .replay_busy   (replay_busy),
        .replay_done   (replay_done),
        .rd_valid      (replay_rd_valid),
        .rd_ready      (replay_rd_ready),
        .rd_data       (replay_rd_data),
        .rd_tlast      (replay_rd_tlast)
    );

    // -----------------------------------------------------------------------
    // P3-14B: Integer CFO NCO
    //
    // Loaded with dut_int_cfo_word (32-bit NCO step) when dut_int_cfo_valid fires.
    // Phase is reset simultaneously; warmup counter forces enable=1 for
    // CORDIC_LATENCY cycles to fill the pipeline before replay starts.
    // -----------------------------------------------------------------------
    wire signed [PHASE_WIDTH-1:0] int_nco_sin_w;
    wire signed [PHASE_WIDTH-1:0] int_nco_cos_w;
    wire                          int_nco_sincos_valid;
    wire [NCO_PHASE_WIDTH-1:0]    int_nco_phase_acc;

    wire int_nco_enable = int_nco_wu_active | !int_nco_sincos_valid | (replay_rd_valid & replay_rd_ready);

    nco_phase_gen #(
        .NCO_PHASE_WIDTH     (NCO_PHASE_WIDTH),
        .CORDIC_PHASE_WIDTH  (PHASE_WIDTH),
        .ROTATOR_COEFF_WIDTH (PHASE_WIDTH),
        .LATENCY             (CORDIC_LATENCY)
    ) u_int_nco (
        .aclk        (aclk),
        .aresetn     (dut_aresetn),
        .load_step   (dut_int_cfo_valid),
        .step_word   (dut_int_cfo_word),
        .phase_reset (dut_int_cfo_valid),
        .enable      (int_nco_enable),
        .sin_out     (int_nco_sin_w),
        .cos_out     (int_nco_cos_w),
        .sincos_valid(int_nco_sincos_valid),
        .phase_acc   (int_nco_phase_acc)
    );

    // -----------------------------------------------------------------------
    // P3-14B: Integer CFO correction rotator
    //
    // Input:  replay buffer output (frac-corrected IQ replay)
    // Output: integer-corrected IQ stream → M_AXIS
    // Throughput limited by m_axis_tready backpressure.
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0] int_corr_m_tdata;
    wire                  int_corr_m_tvalid;
    wire                  int_corr_m_tready;
    wire                  int_corr_m_tlast;

    // Gate tready: only consume corrected output when enabled and not bypassing
    assign int_corr_m_tready = int_enable && !int_bypass_en && m_axis_tready;

    complex_rotator #(
        .DATA_WIDTH      (2*IQ_WIDTH),
        .COMPONENT_WIDTH (IQ_WIDTH),
        .SHIFT           (IQ_WIDTH - 1)
    ) u_int_rot (
        .aclk            (aclk),
        .aresetn         (dut_aresetn),
        .s_axis_iq_tdata (replay_rd_data),
        .s_axis_iq_tvalid(replay_rd_valid),
        .s_axis_iq_tready(replay_rd_ready),
        .s_axis_iq_tlast (replay_rd_tlast),
        .sin_in          (int_nco_sin_w),
        .cos_in          (int_nco_cos_w),
        .sincos_valid    (int_nco_sincos_valid),
        .m_axis_tdata    (int_corr_m_tdata),
        .m_axis_tvalid   (int_corr_m_tvalid),
        .m_axis_tready   (int_corr_m_tready),
        .m_axis_tlast    (int_corr_m_tlast)
    );

    // -----------------------------------------------------------------------
    // Core M_AXIS source: integer-corrected stream (P3-14B: no longer stubbed)
    // -----------------------------------------------------------------------
    wire        core_m_valid = int_corr_m_tvalid;
    wire [2*IQ_WIDTH-1:0] core_m_data = int_corr_m_tdata;

    assign m_axis_tvalid = int_enable ? (int_bypass_en ? s_axis_tvalid : core_m_valid) : 1'b0;
    assign m_axis_tdata  = int_bypass_en ? s_axis_tdata : core_m_data;

    // -----------------------------------------------------------------------
    // TLAST generation — register-driven counter (same as P3-14A)
    // Counter fires at FRAME_LEN_SAMPLES beats; matches replay buffer output length.
    // force_tlast_latch: sticky, set by int_force_tlast pulse, cleared on first consumed beat.
    // -----------------------------------------------------------------------
    reg [11:0] out_frame_cnt;
    reg [31:0] tlast_count;
    reg        force_tlast_latch;

    always @(posedge aclk) begin
        if (!dut_aresetn || int_counter_clear) begin
            force_tlast_latch <= 1'b0;
        end else begin
            if (int_force_tlast)
                force_tlast_latch <= 1'b1;
            else if (m_hs && force_tlast_latch)
                force_tlast_latch <= 1'b0;
        end
    end

    wire tlast_now = (out_frame_cnt >= int_frame_len - 1) || force_tlast_latch;

    always @(posedge aclk) begin
        if (!dut_aresetn || int_counter_clear) begin
            out_frame_cnt <= 12'd0;
            tlast_count   <= 32'd0;
        end else if (m_hs) begin
            if (tlast_now) begin
                out_frame_cnt <= 12'd0;
                tlast_count   <= tlast_count + 32'd1;
            end else begin
                out_frame_cnt <= out_frame_cnt + 12'd1;
            end
        end
    end

    assign m_axis_tlast = m_axis_tvalid && tlast_now;

    // -----------------------------------------------------------------------
    // Wrapper-level error detection (same flags as Phase2)
    // -----------------------------------------------------------------------

    // Input beat counter (mod frame_len) for FRAME_LEN_MISMATCH
    reg [11:0] in_frame_cnt;
    always @(posedge aclk) begin
        if (!dut_aresetn) begin
            in_frame_cnt <= 12'd0;
        end else if (s_hs) begin
            in_frame_cnt <= (in_frame_cnt >= int_frame_len - 1) ?
                            12'd0 : in_frame_cnt + 12'd1;
        end
    end

    // bit0: FRAME_LEN_MISMATCH
    wire err_frame_mismatch = s_axis_tvalid && s_axis_tready && s_axis_tlast &&
                              (in_frame_cnt != int_frame_len - 1);

    // bit1: TLAST_TIMEOUT
    reg [12:0] tlast_timeout_cnt;
    always @(posedge aclk) begin
        if (!dut_aresetn) begin
            tlast_timeout_cnt <= 13'd0;
        end else if (m_hs) begin
            if (m_axis_tlast)
                tlast_timeout_cnt <= 13'd0;
            else if (tlast_timeout_cnt < 13'h1FFE)
                tlast_timeout_cnt <= tlast_timeout_cnt + 13'd1;
        end
    end
    wire err_tlast_timeout = (tlast_timeout_cnt == 13'd8190);

    // bit2: RESET_WHILE_ACTIVE
    wire err_reset_active = dut_aresetn_prev && !dut_aresetn && (output_count > 32'd0);

    // bit3: STALL_TIMEOUT
    reg [7:0] stall_cnt;
    always @(posedge aclk) begin
        if (!dut_aresetn) begin
            stall_cnt <= 8'd0;
        end else if (m_axis_tvalid && !m_axis_tready && stall_cnt < 8'hFE) begin
            stall_cnt <= stall_cnt + 8'd1;
        end else if (!m_axis_tvalid || m_axis_tready) begin
            stall_cnt <= 8'd0;
        end
    end
    wire err_stall_timeout = (stall_cnt == 8'd254);

    wire [3:0] error_set_w = {err_stall_timeout, err_reset_active,
                              err_tlast_timeout, err_frame_mismatch};

    // -----------------------------------------------------------------------
    // P3-14B: INT_CFO_APPLIED sticky register
    // Set when replay_busy first asserts (integer correction is active).
    // Cleared by dut_aresetn.
    // -----------------------------------------------------------------------
    reg int_cfo_applied_r;

    always @(posedge aclk) begin
        if (!dut_aresetn)
            int_cfo_applied_r <= 1'b0;
        else if (replay_busy)
            int_cfo_applied_r <= 1'b1;
    end

    // -----------------------------------------------------------------------
    // Start pulse logic (auto-rearm)
    //
    // P3-14B change vs P3-14A:
    //   Re-arm after replay_done (not dut_done) to prevent new capture starting
    //   while a replay is still in progress, which would corrupt the buffer.
    // -----------------------------------------------------------------------
    reg start_r;
    reg start_armed_r;

    always @(posedge aclk) begin
        if (!dut_aresetn) begin
            start_r       <= 1'b0;
            start_armed_r <= 1'b0;
        end else begin
            start_r <= 1'b0;
            // Arm: rising edge of dut_aresetn (reset just released)
            if (reset_done_w) begin
                start_armed_r <= 1'b1;
            end else if (dut_done && dut_error) begin
                start_armed_r <= 1'b0;   // stop after error; wait for soft_reset
            end else if (replay_done) begin
                start_armed_r <= 1'b1;   // re-arm only after replay completes
            end
            // Fire start when enabled, armed, and DUT idle
            if (int_enable && start_armed_r && !dut_busy) begin
                start_r       <= 1'b1;
                start_armed_r <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // AXI-Lite register bank
    // -----------------------------------------------------------------------
    phase3_axi_lite_regs #(
        .ADDR_WIDTH      (7),
        .DATA_WIDTH      (32),
        .BUF_AW          (BUF_AW),
        .INDEX_WIDTH     (INDEX_WIDTH),
        .PHASE_WIDTH     (PHASE_WIDTH),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH)
    ) u_regs (
        .aclk                  (aclk),
        .aresetn               (aresetn),
        .s_axi_awaddr          (s_axi_awaddr),
        .s_axi_awvalid         (s_axi_awvalid),
        .s_axi_awready         (s_axi_awready),
        .s_axi_wdata           (s_axi_wdata),
        .s_axi_wstrb           (s_axi_wstrb),
        .s_axi_wvalid          (s_axi_wvalid),
        .s_axi_wready          (s_axi_wready),
        .s_axi_bresp           (s_axi_bresp),
        .s_axi_bvalid          (s_axi_bvalid),
        .s_axi_bready          (s_axi_bready),
        .s_axi_araddr          (s_axi_araddr),
        .s_axi_arvalid         (s_axi_arvalid),
        .s_axi_arready         (s_axi_arready),
        .s_axi_rdata           (s_axi_rdata),
        .s_axi_rresp           (s_axi_rresp),
        .s_axi_rvalid          (s_axi_rvalid),
        .s_axi_rready          (s_axi_rready),
        .busy_i                (dut_busy),
        .done_pulse_i          (dut_done),
        .error_i               (dut_error),
        .error_code_i          (dut_error_code),
        .input_count_i         (input_count),
        .output_count_i        (output_count),
        .frame_start_valid_i   (dut_frame_start_valid),
        .frame_start_index_i   (dut_frame_start_index),
        .peak_index_i          (dut_peak_index),
        .slot_start_valid_i    (dut_slot_start_valid),
        .slot_start_index_i    (dut_slot_start_index),
        .frac_cfo_valid_i      (dut_frac_cfo_valid),
        .frac_cfo_phase_i      (dut_frac_cfo_word),
        .int_cfo_valid_i       (dut_int_cfo_valid),
        .int_cfo_est_i         (dut_int_cfo_word),
        // P3-14B: INT_CFO_APPLIED and INT_CFO_INDEX
        .int_cfo_applied_i     (int_cfo_applied_r),
        .int_cfo_index_i       (dut_meyr_peak_index),
        .reset_done_i          (reset_done_w),
        .tlast_count_i         (tlast_count),
        .error_set_i           (error_set_w),
        .enable_o              (int_enable),
        .soft_reset_pulse_o    (int_soft_reset),
        .bypass_enable_o       (int_bypass_en),
        .force_tlast_o         (int_force_tlast),
        .counter_clear_o       (int_counter_clear),
        .debug_mode_o          (int_debug_mode),
        .frame_len_samples_o   (int_frame_len)
    );

    // -----------------------------------------------------------------------
    // THRESHOLD parameter widened to ENERGY_WIDTH bits for port connection
    // -----------------------------------------------------------------------
    localparam [ENERGY_WIDTH-1:0] THRESHOLD_LP = THRESHOLD;

    // -----------------------------------------------------------------------
    // phase3_sync_top — Algorithm DUT (minimal output additions in P3-14B)
    // -----------------------------------------------------------------------
    phase3_sync_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .ACC_WIDTH       (ACC_WIDTH),
        .METRIC_WIDTH    (METRIC_WIDTH),
        .INDEX_WIDTH     (INDEX_WIDTH),
        .RESULT_WIDTH    (RESULT_WIDTH),
        .PHASE_WIDTH     (PHASE_WIDTH),
        .POWER_WIDTH     (POWER_WIDTH),
        .ENERGY_WIDTH    (ENERGY_WIDTH),
        .WINDOW_LEN      (WINDOW_LEN),
        .HIT_COUNT       (HIT_COUNT),
        .THRESHOLD       (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .CORDIC_LATENCY  (CORDIC_LATENCY),
        .IQ_WIDTH        (IQ_WIDTH)
    ) u_dut (
        .aclk                   (aclk),
        .aresetn                (dut_aresetn),

        .s_axis_tdata           (s_axis_tdata),
        .s_axis_tvalid          (gated_s_valid),
        .s_axis_tready          (dut_s_axis_tready),
        .s_axis_tlast           (s_axis_tlast),

        // Frame detector runtime config — tied to parameter defaults.
        .threshold_in           (THRESHOLD_LP),
        .window_len_in          (WINDOW_LEN[6:0]),
        .hit_count_in           (HIT_COUNT[3:0]),

        .start                  (start_r),
        .done                   (dut_done),
        .busy                   (dut_busy),
        .error                  (dut_error),
        .error_code             (dut_error_code),

        .dbg_frame_start_valid  (dut_frame_start_valid),
        .dbg_frame_start_index  (dut_frame_start_index),
        .dbg_peak_valid         (),
        .dbg_peak_index         (dut_peak_index),
        .dbg_slot_start_valid   (dut_slot_start_valid),
        .dbg_slot_start_index   (dut_slot_start_index),
        .dbg_frac_cfo_valid     (dut_frac_cfo_valid),
        .dbg_frac_cfo_word      (dut_frac_cfo_word),
        .dbg_pss_start          (),
        .dbg_sss_start          (),
        .dbg_integer_cfo_valid  (dut_int_cfo_valid),
        .dbg_integer_cfo_word   (dut_int_cfo_word),
        .dbg_done               (),
        .dbg_error_code         (),
        // P3-14B: frac-corrected stream tap and Meyr peak index
        .dbg_frac_m_tdata       (dut_frac_m_tdata),
        .dbg_frac_m_tvalid      (dut_frac_m_tvalid),
        .dbg_frac_m_tready      (dut_frac_m_tready),
        .dbg_frac_m_tlast       (dut_frac_m_tlast),
        .dbg_meyr_peak_index    (dut_meyr_peak_index)
    );

    // Debug output: expose frac-corrected stream for golden-compare TB
    assign dbg_frac_m_tdata  = dut_frac_m_tdata;
    assign dbg_frac_m_tvalid = dut_frac_m_tvalid;
    assign dbg_frac_m_tready = dut_frac_m_tready;
    assign dbg_frac_m_tlast  = dut_frac_m_tlast;

endmodule
