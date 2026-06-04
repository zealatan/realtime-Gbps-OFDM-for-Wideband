`timescale 1ns/1ps

// frac_cfo_sync_axi_stream_wrapper
// Combines AXI4-Lite control/status plane with the frac_cfo_frame_corrector_top DUT.
//
// AXI-Lite registers (byte offsets):
//   0x00 CONTROL : [2]=enable, [1]=clear_status_pulse, [0]=soft_reset_pulse
//   0x04 STATUS  : [6]=output_seen, [5]=input_seen, [4]=in_frame(busy),
//                  [3]=frame_error, [2]=frame_detected, [1]=done, [0]=busy
//   0x08 CFG_CFO_STEP      : stored, not connected to DUT (future use)
//   0x0C CFG_TIMING_OFFSET : stored, not connected to DUT (future use)
//   0x10 CFG_FRAME_LEN     : stored, not connected to DUT (future use)
//   0x14 SAMPLE_COUNT      : AXI-Stream input handshakes since last reset
//   0x18 OUTPUT_COUNT      : AXI-Stream output handshakes since last reset
//   0x1C DEBUG_STATE       : {4'd0, peak_lag[8:0], frac_phase[15:0], fsm_state[2:0]}
//
// AXI-Stream gating: when enable=0, s_axis_tready=0 and DUT input is disconnected.
// Soft reset: dut_aresetn = aresetn && !soft_reset_pulse.
// DUT start: one-shot pulse on rising edge of enable_out.
// Sticky status cleared by soft_reset_pulse OR clear_status_pulse.

module frac_cfo_sync_axi_stream_wrapper #(
    // DUT parameters
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer BUF_AW       = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32,
    parameter integer PHASE_WIDTH  = 16,
    parameter integer POWER_WIDTH  = 33,
    parameter integer ENERGY_WIDTH = 40,
    parameter integer WINDOW_LEN   = 25,
    parameter integer HIT_COUNT    = 10,
    parameter integer THRESHOLD    = 10240000,
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer LATENCY         = 15
) (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite control/status
    input  wire [5:0]  s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,

    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,

    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,

    input  wire [5:0]  s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,

    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,

    // AXI-Stream IQ input
    input  wire [31:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tlast,

    // AXI-Stream corrected output
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    // -----------------------------------------------------------------------
    // Internal: control register file outputs
    // -----------------------------------------------------------------------
    wire        enable_out;
    wire        soft_reset_pulse;
    wire        clear_status_pulse;
    wire [31:0] cfg_cfo_step;       // stored only, not used by DUT
    wire [31:0] cfg_timing_offset;  // stored only, not used by DUT
    wire [31:0] cfg_frame_len;      // stored only, not used by DUT

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    wire        dut_aresetn;
    reg         dut_start;
    wire        dut_done;
    wire        dut_busy;
    wire        dut_frame_error;
    wire [BUF_AW-1:0]      dut_frame_index;
    wire                   dut_frame_found;
    wire [INDEX_WIDTH-1:0] dut_peak_lag;
    wire [METRIC_WIDTH-1:0] dut_peak_metric;
    wire [PHASE_WIDTH-1:0] dut_frac_phase;
    wire                   dut_frac_phase_valid;

    wire [31:0] dut_s_axis_tdata;
    wire        dut_s_axis_tvalid;
    wire        dut_s_axis_tready;
    wire        dut_s_axis_tlast;

    wire [31:0] dut_m_axis_tdata;
    wire        dut_m_axis_tvalid;
    wire        dut_m_axis_tready;
    wire        dut_m_axis_tlast;

    // -----------------------------------------------------------------------
    // Soft-reset: hold DUT in reset while soft_reset_pulse is asserted
    // -----------------------------------------------------------------------
    assign dut_aresetn = aresetn && !soft_reset_pulse;

    // -----------------------------------------------------------------------
    // Start generation: rising edge of enable_out
    // -----------------------------------------------------------------------
    reg enable_prev_r;

    always @(posedge aclk) begin
        if (!aresetn || soft_reset_pulse)
            enable_prev_r <= 1'b0;
        else
            enable_prev_r <= enable_out;
    end

    always @(posedge aclk) begin
        if (!aresetn || soft_reset_pulse)
            dut_start <= 1'b0;
        else
            dut_start <= enable_out && !enable_prev_r;
    end

    // -----------------------------------------------------------------------
    // AXI-Stream gating
    // -----------------------------------------------------------------------
    assign dut_s_axis_tdata  = s_axis_tdata;
    assign dut_s_axis_tvalid = enable_out ? s_axis_tvalid  : 1'b0;
    assign dut_s_axis_tlast  = s_axis_tlast;
    assign s_axis_tready     = enable_out ? dut_s_axis_tready : 1'b0;

    assign m_axis_tdata  = dut_m_axis_tdata;
    assign m_axis_tvalid = dut_m_axis_tvalid;
    assign dut_m_axis_tready = m_axis_tready;
    assign m_axis_tlast  = dut_m_axis_tlast;

    // -----------------------------------------------------------------------
    // Sticky status registers
    // -----------------------------------------------------------------------
    reg done_sticky_r;
    reg frame_detected_sticky_r;
    reg frame_error_sticky_r;
    reg input_seen_sticky_r;
    reg output_seen_sticky_r;

    wire clear_sticky = soft_reset_pulse || clear_status_pulse;

    always @(posedge aclk) begin
        if (!aresetn || clear_sticky) begin
            done_sticky_r           <= 1'b0;
            frame_detected_sticky_r <= 1'b0;
            frame_error_sticky_r    <= 1'b0;
            input_seen_sticky_r     <= 1'b0;
            output_seen_sticky_r    <= 1'b0;
        end else begin
            if (dut_done)
                done_sticky_r <= 1'b1;
            if (dut_done && dut_frame_found && !dut_frame_error)
                frame_detected_sticky_r <= 1'b1;
            if (dut_frame_error)
                frame_error_sticky_r <= 1'b1;
            if (dut_s_axis_tvalid && dut_s_axis_tready)
                input_seen_sticky_r <= 1'b1;
            if (dut_m_axis_tvalid && dut_m_axis_tready)
                output_seen_sticky_r <= 1'b1;
        end
    end

    // -----------------------------------------------------------------------
    // Sample / output counters
    // -----------------------------------------------------------------------
    reg [31:0] sample_count_r;
    reg [31:0] output_count_r;

    always @(posedge aclk) begin
        if (!aresetn || clear_sticky) begin
            sample_count_r <= 32'd0;
            output_count_r <= 32'd0;
        end else begin
            if (dut_s_axis_tvalid && dut_s_axis_tready)
                sample_count_r <= sample_count_r + 32'd1;
            if (dut_m_axis_tvalid && dut_m_axis_tready)
                output_count_r <= output_count_r + 32'd1;
        end
    end

    // -----------------------------------------------------------------------
    // Capture peak_lag and frac_phase at done
    // -----------------------------------------------------------------------
    reg [INDEX_WIDTH-1:0] peak_lag_r;
    reg [PHASE_WIDTH-1:0] frac_phase_r;
    reg [2:0]             dbg_state_r;

    always @(posedge aclk) begin
        if (!aresetn || clear_sticky) begin
            peak_lag_r   <= {INDEX_WIDTH{1'b0}};
            frac_phase_r <= {PHASE_WIDTH{1'b0}};
            dbg_state_r  <= 3'd0;
        end else begin
            if (dut_done) begin
                peak_lag_r   <= dut_peak_lag;
                frac_phase_r <= dut_frac_phase;
            end
            // dbg_state: expose DUT FSM encoded in the lower 3 bits via a
            // combinatorial pass-through.  We can't read the DUT state
            // register directly, so approximate from observable signals.
            if      (dut_busy)                  dbg_state_r <= 3'd1; // in-progress
            else if (done_sticky_r)             dbg_state_r <= 3'd6; // done
            else                                dbg_state_r <= 3'd0; // idle
        end
    end

    // DEBUG_STATE: {4'd0, peak_lag[8:0], frac_phase[15:0], fsm_state[2:0]}
    wire [31:0] debug_state_in =
        {4'd0,
         peak_lag_r[8:0],
         frac_phase_r[15:0],
         dbg_state_r};

    // -----------------------------------------------------------------------
    // Control/status register file
    // -----------------------------------------------------------------------
    frac_cfo_sync_control_s_axi #(
        .AXI_ADDR_WIDTH(6),
        .AXI_DATA_WIDTH(32)
    ) u_ctrl (
        .s_axi_aclk    (aclk),
        .s_axi_aresetn (aresetn),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),

        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .soft_reset_pulse   (soft_reset_pulse),
        .clear_status_pulse (clear_status_pulse),
        .enable_out         (enable_out),
        .cfg_cfo_step       (cfg_cfo_step),
        .cfg_timing_offset  (cfg_timing_offset),
        .cfg_frame_len      (cfg_frame_len),

        .status_busy                  (dut_busy),
        .status_done_sticky           (done_sticky_r),
        .status_frame_detected_sticky (frame_detected_sticky_r),
        .status_frame_error_sticky    (frame_error_sticky_r),
        .status_in_frame              (dut_busy),
        .status_input_seen_sticky     (input_seen_sticky_r),
        .status_output_seen_sticky    (output_seen_sticky_r),
        .sample_count_in              (sample_count_r),
        .output_count_in              (output_count_r),
        .debug_state_in               (debug_state_in)
    );

    // -----------------------------------------------------------------------
    // DUT: frac_cfo_frame_corrector_top
    // -----------------------------------------------------------------------
    frac_cfo_frame_corrector_top #(
        .NSC          (NSC),
        .CP_LEN       (CP_LEN),
        .BUF_AW       (BUF_AW),
        .ACC_WIDTH    (ACC_WIDTH),
        .METRIC_WIDTH (METRIC_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .RESULT_WIDTH (RESULT_WIDTH),
        .PHASE_WIDTH  (PHASE_WIDTH),
        .POWER_WIDTH  (POWER_WIDTH),
        .ENERGY_WIDTH (ENERGY_WIDTH),
        .WINDOW_LEN   (WINDOW_LEN),
        .HIT_COUNT    (HIT_COUNT),
        .THRESHOLD    (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .LATENCY         (LATENCY)
    ) u_dut (
        .aclk    (aclk),
        .aresetn (dut_aresetn),

        .s_axis_tdata  (dut_s_axis_tdata),
        .s_axis_tvalid (dut_s_axis_tvalid),
        .s_axis_tready (dut_s_axis_tready),
        .s_axis_tlast  (dut_s_axis_tlast),

        .start       (dut_start),
        .done        (dut_done),
        .busy        (dut_busy),
        .frame_error (dut_frame_error),

        .threshold_in  ({{(ENERGY_WIDTH-32){1'b0}}, THRESHOLD[31:0]}),
        .window_len_in (WINDOW_LEN[6:0]),
        .hit_count_in  (HIT_COUNT[3:0]),

        .frame_index      (dut_frame_index),
        .frame_found      (dut_frame_found),
        .peak_lag         (dut_peak_lag),
        .peak_metric      (dut_peak_metric),
        .frac_phase       (dut_frac_phase),
        .frac_phase_valid (dut_frac_phase_valid),

        .m_axis_tdata  (dut_m_axis_tdata),
        .m_axis_tvalid (dut_m_axis_tvalid),
        .m_axis_tready (dut_m_axis_tready),
        .m_axis_tlast  (dut_m_axis_tlast)
    );

endmodule
