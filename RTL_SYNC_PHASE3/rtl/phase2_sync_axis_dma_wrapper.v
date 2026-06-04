`timescale 1ns/1ps

// phase2_sync_axis_dma_wrapper — P2-12 / P2-18 / P2-20E
// Board-integration wrapper: wraps phase2_streaming_sync_top with
// enable gating, soft_reset, counter-based TLAST, status counters,
// bypass mode, configurable frame length, and debug error flags.
//
// Enable gate:
//   enable=0 → s_ready=0 (blocks upstream), m_valid=0 (no output produced).
//   enable=1 → normal or bypass mode.
//
// Bypass mode (P2-20E):
//   When BYPASS_ENABLE=1, input AXIS passes directly to output AXIS.
//   Core receives no data. Use for DMA path isolation testing.
//
// TLAST generation (P2-20E):
//   m_tlast driven by register-driven frame counter.
//   FRAME_LEN_SAMPLES register sets period (default 288).
//   FORCE_TLAST (self-clearing) fires TLAST on next output beat.
//   COUNTER_CLEAR (self-clearing) resets out_frame_cnt and tlast_count.
//
// Error flags (P2-20E):
//   FRAME_LEN_MISMATCH: s_tlast at unexpected input beat position
//   TLAST_TIMEOUT:      no output TLAST for > 8190 consecutive output beats
//   RESET_WHILE_ACTIVE: reset fell while output_count > 0
//   STALL_TIMEOUT:      m_valid high, m_ready low for > 254 cycles

module phase2_sync_axis_dma_wrapper #(
    parameter integer SAMPLE_W    = 16,
    parameter integer NSC         = 256,
    parameter integer CP_LEN      = 32,
    parameter integer ACC_W       = 48,
    parameter integer METRIC_W    = 32,
    parameter integer USE_AXI_CTRL = 0
) (
    input  wire        clk,
    input  wire        aresetn,

    // External control (used when USE_AXI_CTRL=0)
    input  wire        enable,
    input  wire        soft_reset,

    // AXI-Stream slave input
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,
    input  wire        s_tlast,

    // AXI-Stream master output
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,
    output wire        m_tlast,

    // Status / debug counters
    output reg  [31:0] input_count,
    output reg  [31:0] output_count,
    output reg  [31:0] timing_lock_count,
    output reg         nco_locked_seen,
    output reg  [31:0] last_lock_index,
    output reg  [15:0] last_frac_phase,
    output reg  [31:0] tlast_count,    // P2-20E: output TLAST fires since last clear

    // AXI4-Lite slave (tie inputs to 0 when USE_AXI_CTRL=0)
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
    input  wire        s_axi_rready
);

    // -----------------------------------------------------------------------
    // Internal control wires
    // -----------------------------------------------------------------------
    wire int_enable;
    wire int_soft_reset;
    wire        int_bypass_en;
    wire        int_force_tlast;
    wire        int_counter_clear;
    wire        int_debug_mode;
    wire [11:0] int_frame_len;

    // Integer CFO side-path wires (P2-18)
    wire        icfo_valid_w;
    wire [15:0] icfo_estimate_w;
    wire [8:0]  icfo_lock_index_w;
    wire        icfo_busy_w;

    // Reset/idle wires — declared here; assigned after dut_aresetn is defined
    wire reset_done_w;
    wire pipeline_idle_w;

    // -----------------------------------------------------------------------
    // Soft reset and dut_aresetn — declared before error flag logic
    // -----------------------------------------------------------------------
    reg  soft_reset_r;
    wire dut_aresetn = aresetn && !soft_reset_r;
    reg  dut_aresetn_prev;

    // -----------------------------------------------------------------------
    // P2-20E: Error flag generation
    // All blocks below use dut_aresetn and dut_aresetn_prev declared above.
    // -----------------------------------------------------------------------

    // Input beat counter (tracks position mod frame_len for FRAME_LEN_MISMATCH)
    reg [11:0] in_frame_cnt;
    always @(posedge clk) begin
        if (!dut_aresetn) begin
            in_frame_cnt <= 12'd0;
        end else if (s_valid && s_ready) begin
            in_frame_cnt <= (in_frame_cnt >= int_frame_len - 1) ?
                            12'd0 : in_frame_cnt + 12'd1;
        end
    end

    // bit0: FRAME_LEN_MISMATCH
    wire err_frame_mismatch = s_valid && s_ready && s_tlast &&
                              (in_frame_cnt != int_frame_len - 1);

    // bit1: TLAST_TIMEOUT — no output TLAST for > 8190 consecutive output beats
    reg [12:0] tlast_timeout_cnt;
    always @(posedge clk) begin
        if (!dut_aresetn) begin
            tlast_timeout_cnt <= 13'd0;
        end else if (m_valid && m_ready) begin
            if (m_tlast)
                tlast_timeout_cnt <= 13'd0;
            else if (tlast_timeout_cnt < 13'h1FFE)
                tlast_timeout_cnt <= tlast_timeout_cnt + 13'd1;
        end
    end
    wire err_tlast_timeout = (tlast_timeout_cnt == 13'd8190);

    // bit2: RESET_WHILE_ACTIVE — dut_aresetn falling edge while output_count > 0
    wire err_reset_active = dut_aresetn_prev && !dut_aresetn && (output_count > 32'd0);

    // bit3: STALL_TIMEOUT — m_valid high, m_ready low for > 254 cycles
    reg [7:0] stall_cnt;
    always @(posedge clk) begin
        if (!dut_aresetn) begin
            stall_cnt <= 8'd0;
        end else if (m_valid && !m_ready && stall_cnt < 8'hFE) begin
            stall_cnt <= stall_cnt + 8'd1;
        end else if (!m_valid || m_ready) begin
            stall_cnt <= 8'd0;
        end
    end
    wire err_stall_timeout = (stall_cnt == 8'd254);

    wire [3:0] error_set_w = {err_stall_timeout, err_reset_active,
                              err_tlast_timeout, err_frame_mismatch};

    // -----------------------------------------------------------------------
    // Generate: AXI-Lite register bank or external control
    // -----------------------------------------------------------------------
    generate
        if (USE_AXI_CTRL == 1) begin : g_axi_ctrl
            wire        axi_enable_w;
            wire        axi_soft_reset_pulse_w;
            wire        axi_bypass_en_w;
            wire        axi_force_tlast_w;
            wire        axi_counter_clear_w;
            wire        axi_debug_mode_w;
            wire [11:0] axi_frame_len_w;

            phase2_axi_lite_regs #(
                .ADDR_WIDTH (7),
                .DATA_WIDTH (32)
            ) u_regs (
                .aclk                  (clk),
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
                .nco_locked_seen_i     (nco_locked_seen),
                .input_count_i         (input_count),
                .output_count_i        (output_count),
                .timing_lock_count_i   (timing_lock_count),
                .last_lock_index_i     (last_lock_index),
                .last_frac_phase_i     (last_frac_phase),
                .int_cfo_valid_i       (icfo_valid_w),
                .int_cfo_estimate_i    (icfo_estimate_w),
                .int_cfo_lock_index_i  (icfo_lock_index_w),
                .reset_done_i          (reset_done_w),
                .tlast_count_i         (tlast_count),
                .error_set_i           (error_set_w),
                .enable_o              (axi_enable_w),
                .soft_reset_pulse_o    (axi_soft_reset_pulse_w),
                .bypass_enable_o       (axi_bypass_en_w),
                .force_tlast_o         (axi_force_tlast_w),
                .counter_clear_o       (axi_counter_clear_w),
                .debug_mode_o          (axi_debug_mode_w),
                .frame_len_samples_o   (axi_frame_len_w)
            );
            assign int_enable        = axi_enable_w;
            assign int_soft_reset    = axi_soft_reset_pulse_w;
            assign int_bypass_en     = axi_bypass_en_w;
            assign int_force_tlast   = axi_force_tlast_w;
            assign int_counter_clear = axi_counter_clear_w;
            assign int_debug_mode    = axi_debug_mode_w;
            assign int_frame_len     = axi_frame_len_w;
        end else begin : g_ext_ctrl
            assign s_axi_awready = 1'b1;
            assign s_axi_wready  = 1'b1;
            assign s_axi_bresp   = 2'b10;
            assign s_axi_bvalid  = 1'b0;
            assign s_axi_arready = 1'b1;
            assign s_axi_rdata   = 32'b0;
            assign s_axi_rresp   = 2'b10;
            assign s_axi_rvalid  = 1'b0;
            assign int_enable        = enable;
            assign int_soft_reset    = soft_reset;
            assign int_bypass_en     = 1'b0;
            assign int_force_tlast   = 1'b0;
            assign int_counter_clear = 1'b0;
            assign int_debug_mode    = 1'b0;
            assign int_frame_len     = NSC + CP_LEN;
            wire _unused_icfo = icfo_valid_w | (|icfo_estimate_w) | (|icfo_lock_index_w) | icfo_busy_w;
            wire _unused_rst  = reset_done_w | pipeline_idle_w;
            wire _unused_err  = |error_set_w;
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Soft reset: one-cycle pipeline → clean deassert
    // -----------------------------------------------------------------------
    always @(posedge clk) soft_reset_r <= int_soft_reset;

    // -----------------------------------------------------------------------
    // Reset completion pulse (P2-20D)
    // -----------------------------------------------------------------------
    always @(posedge clk) dut_aresetn_prev <= dut_aresetn;
    assign reset_done_w    = dut_aresetn && !dut_aresetn_prev;
    assign pipeline_idle_w = (input_count == output_count);

    // -----------------------------------------------------------------------
    // Core internal wires
    // -----------------------------------------------------------------------
    wire        core_s_ready;
    wire        core_m_valid;
    wire [31:0] core_m_data;
    wire        timing_lock_w;
    wire [31:0] lock_index_w;
    wire [METRIC_W-1:0] metric_dbg_w;
    wire [15:0] frac_phase_dbg_w;
    wire        nco_locked_w;
    wire [3:0]  state_dbg_w;

    // -----------------------------------------------------------------------
    // Enable + bypass gating (P2-20E)
    //   Normal:  s_valid→core; core→m_valid/m_data
    //   Bypass:  s_valid↔m_valid; s_data→m_data; m_ready→s_ready
    // -----------------------------------------------------------------------
    wire gated_s_valid = int_enable && !int_bypass_en ? s_valid : 1'b0;
    assign s_ready = int_enable ? (int_bypass_en ? m_ready     : core_s_ready) : 1'b0;
    assign m_valid = int_enable ? (int_bypass_en ? s_valid     : core_m_valid) : 1'b0;
    assign m_data  =               int_bypass_en ? s_data      : core_m_data;

    // -----------------------------------------------------------------------
    // TLAST generation — register-driven counter (P2-20E)
    // force_tlast_latch: sticky flag set by int_force_tlast pulse, cleared on
    // the first accepted output beat (ensures TLAST fires even if the pulse
    // arrives several cycles before the beat handshake).
    // -----------------------------------------------------------------------
    reg [11:0] out_frame_cnt;
    reg        force_tlast_latch;

    always @(posedge clk) begin
        if (!dut_aresetn || int_counter_clear) begin
            force_tlast_latch <= 1'b0;
        end else begin
            if (int_force_tlast)
                force_tlast_latch <= 1'b1;
            else if (m_valid && m_ready && force_tlast_latch)
                force_tlast_latch <= 1'b0;
        end
    end

    wire tlast_now = (out_frame_cnt >= int_frame_len - 1) || force_tlast_latch;

    always @(posedge clk) begin
        if (!dut_aresetn || int_counter_clear) begin
            out_frame_cnt <= 12'd0;
            tlast_count   <= 32'd0;
        end else if (m_valid && m_ready) begin
            if (tlast_now) begin
                out_frame_cnt <= 12'd0;
                tlast_count   <= tlast_count + 32'd1;
            end else begin
                out_frame_cnt <= out_frame_cnt + 12'd1;
            end
        end
    end

    assign m_tlast = m_valid && tlast_now;

    // -----------------------------------------------------------------------
    // Input handshake counter
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!dut_aresetn)
            input_count <= 32'd0;
        else if (s_valid && s_ready)
            input_count <= input_count + 32'd1;
    end

    // -----------------------------------------------------------------------
    // Output handshake counter
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!dut_aresetn)
            output_count <= 32'd0;
        else if (m_valid && m_ready)
            output_count <= output_count + 32'd1;
    end

    // -----------------------------------------------------------------------
    // timing_lock rising-edge detection, counter, and latch
    // -----------------------------------------------------------------------
    reg timing_lock_prev;
    always @(posedge clk) begin
        if (!dut_aresetn) begin
            timing_lock_count <= 32'd0;
            timing_lock_prev  <= 1'b0;
            last_lock_index   <= 32'd0;
            last_frac_phase   <= 16'd0;
        end else begin
            timing_lock_prev <= timing_lock_w;
            if (timing_lock_w && !timing_lock_prev) begin
                timing_lock_count <= timing_lock_count + 32'd1;
                last_lock_index   <= lock_index_w;
                last_frac_phase   <= frac_phase_dbg_w;
            end
        end
    end

    // -----------------------------------------------------------------------
    // nco_locked sticky flag
    // -----------------------------------------------------------------------
    always @(posedge clk) begin
        if (!dut_aresetn)
            nco_locked_seen <= 1'b0;
        else if (nco_locked_w)
            nco_locked_seen <= 1'b1;
    end

    // -----------------------------------------------------------------------
    // Integer CFO estimator side path (P2-18)
    // -----------------------------------------------------------------------
    phase2_integer_cfo_estimator #(
        .NSC          (NSC),
        .CP_LEN       (CP_LEN),
        .IQ_WIDTH     (SAMPLE_W),
        .USE_FFT_STUB (1)
    ) u_icfo_est (
        .aclk                  (clk),
        .aresetn               (dut_aresetn),
        .s_axis_tvalid         (core_m_valid && m_ready),
        .s_axis_tready         (),
        .s_axis_tdata          (core_m_data),
        .timing_lock           (timing_lock_w),
        .integer_cfo_valid     (icfo_valid_w),
        .integer_cfo_estimate  (icfo_estimate_w),
        .integer_cfo_lock_index(icfo_lock_index_w),
        .integer_cfo_busy      (icfo_busy_w)
    );

    // -----------------------------------------------------------------------
    // phase2_streaming_sync_top core
    // -----------------------------------------------------------------------
    phase2_streaming_sync_top #(
        .SAMPLE_W (SAMPLE_W),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .ACC_W    (ACC_W),
        .METRIC_W (METRIC_W)
    ) u_phase2_core (
        .clk            (clk),
        .aresetn        (dut_aresetn),
        .s_valid        (gated_s_valid),
        .s_ready        (core_s_ready),
        .s_data         (s_data),
        .m_valid        (core_m_valid),
        .m_ready        (m_ready),
        .m_data         (core_m_data),
        .timing_lock    (timing_lock_w),
        .lock_index     (lock_index_w),
        .metric_dbg     (metric_dbg_w),
        .frac_phase_dbg (frac_phase_dbg_w),
        .nco_locked     (nco_locked_w),
        .state_dbg      (state_dbg_w)
    );

endmodule
