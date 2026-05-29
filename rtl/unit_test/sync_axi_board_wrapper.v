`timescale 1ns/1ps

// sync_axi_board_wrapper: AXI-Lite board-level wrapper for Phase-1 OFDM synchronizer.
//
// USE_MOCK_DATAPATH=1 (FV13): uses sync_axi_smoke_mock_dp for fast smoke tests.
// USE_MOCK_DATAPATH=0 (FV13-R, production): wires phase1_ofdm_synchronizer_top.
//
// FV13-R additions:
//   - Corrected gen_real port connections (removed non-existent m_axis/peak_metric)
//   - fft_error_i wired to meyr_error from phase1_top (proxy for FFT/Meyr errors)
//   - error_code_i wired to meyr_error_code (4-bit from Meyr FSM)
//   - m_axis_iq outputs tied to 0 in real path (phase1_top does not expose them)
//   - BUSY_WATCHDOG_CYCLES: wrapper-level deadlock guard — fires frame_error+done
//     and auto-resets datapath after N busy cycles (0=disabled)
//   - USE_BEHAVIORAL_STUB/STUB_TLAST_AT/STUB_STOP_AT/FLUSH_COUNT/MEYR_WATCHDOG_CYCLES
//     passed through to phase1_ofdm_synchronizer_top → meyr_fft256_actual_integration_top

module sync_axi_board_wrapper #(
    parameter integer NSC              = 256,
    parameter integer CP_LEN          = 32,
    parameter integer OUTPUT_SAMPLES  = 576,
    parameter integer PSS_FFT_START   = 32,
    parameter integer SSS_FFT_START   = 320,
    parameter integer BUF_AW          = 12,
    parameter integer ENERGY_WIDTH    = 40,
    parameter integer WINDOW_LEN      = 25,
    parameter integer HIT_COUNT       = 10,
    parameter integer THRESHOLD       = 10240000,
    parameter integer IQ_WIDTH        = 16,
    parameter integer SCORE_WIDTH     = 64,
    parameter integer MEYR_IDX_WIDTH  = 9,
    parameter integer AXI_ADDR_WIDTH  = 6,
    parameter integer AXI_DATA_WIDTH  = 32,
    // FV13 smoke-test controls (no effect when USE_MOCK_DATAPATH=0)
    parameter integer USE_MOCK_DATAPATH   = 0,
    parameter integer MOCK_BUSY_CYCLES    = 20,
    parameter integer MOCK_INJECT_ERROR   = 0,
    // FV13-R: FFT/Meyr stub parameters (passed through to real datapath)
    parameter integer USE_BEHAVIORAL_STUB = 2,
    parameter integer STUB_TLAST_AT       = 255,
    parameter integer STUB_STOP_AT        = 255,
    parameter integer FLUSH_COUNT         = 0,
    parameter integer MEYR_WATCHDOG_CYCLES = 2047,
    // FV13-R: wrapper-level busy watchdog (0 = disabled)
    parameter integer BUSY_WATCHDOG_CYCLES = 0,
    // Step 43: acquisition-stage inactivity watchdog in frac_cfo_frame_corrector_top
    // (0 = disabled; non-zero N fires frame_error + error_code=6 after N idle IQ cycles)
    parameter integer ACQ_WATCHDOG_CYCLES = 0
) (
    input  wire                        aclk,
    input  wire                        aresetn,

    // AXI4-Lite register interface
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                        s_axi_awvalid,
    output wire                        s_axi_awready,
    input  wire [AXI_DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                        s_axi_wvalid,
    output wire                        s_axi_wready,
    output wire [1:0]                  s_axi_bresp,
    output wire                        s_axi_bvalid,
    input  wire                        s_axi_bready,
    input  wire [AXI_ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire                        s_axi_arvalid,
    output wire                        s_axi_arready,
    output wire [AXI_DATA_WIDTH-1:0]  s_axi_rdata,
    output wire [1:0]                  s_axi_rresp,
    output wire                        s_axi_rvalid,
    input  wire                        s_axi_rready,

    // AXI-Stream IQ sample input (from DMA / loopback)
    input  wire [31:0]                 s_axis_iq_tdata,
    input  wire                        s_axis_iq_tvalid,
    output wire                        s_axis_iq_tready,
    input  wire                        s_axis_iq_tlast,

    // AXI-Stream corrected IQ output (real path: tied to 0; mock path: from mock)
    output wire [31:0]                 m_axis_iq_tdata,
    output wire                        m_axis_iq_tvalid,
    input  wire                        m_axis_iq_tready,
    output wire                        m_axis_iq_tlast,

    // Observable status (for ILA / JTAG)
    output wire                        frame_found_o,
    output wire [BUF_AW-1:0]          frame_index_o,
    output wire [MEYR_IDX_WIDTH-1:0]  peak_lag_o,
    output wire signed [15:0]          frac_phase_o,
    output wire signed [31:0]          int_cfo_o
);

    // -----------------------------------------------------------------------
    // Register bank
    // -----------------------------------------------------------------------
    wire        start_pulse_w;
    wire        enable_w;
    wire        soft_reset_w;
    wire        clear_sticky_w;
    wire [31:0] frame_len_w;
    wire [31:0] nsc_w;
    wire [31:0] cp_len_w;

    // -----------------------------------------------------------------------
    // Datapath status wires driven from generate blocks
    // -----------------------------------------------------------------------
    wire        dp_busy_w;          // datapath: busy
    wire        dp_done_w;          // datapath: done (1-cycle pulse)
    wire        dp_frame_error_w;   // datapath: frame_error (1-cycle pulse)
    wire        dp_fft_error_w;     // datapath: fft/meyr error event
    wire [31:0] dp_error_code_w;    // datapath: error code (from Meyr)
    wire        dp_meyr_valid_w;    // datapath: Meyr result valid proxy

    // -----------------------------------------------------------------------
    // Wrapper-level busy watchdog
    // -----------------------------------------------------------------------
    // When BUSY_WATCHDOG_CYCLES > 0 and the datapath stays busy for that many
    // cycles without self-terminating, the watchdog fires: it pulses done+error
    // for one cycle and issues a one-cycle datapath soft-reset to prevent hang.
    // wdog_fired_r stays set until the next start_pulse to mask dp_busy_w.
    // -----------------------------------------------------------------------
    reg [15:0] wdog_cnt_r;
    reg        wdog_done_r;     // 1-cycle pulse
    reg        wdog_error_r;    // 1-cycle pulse
    reg        wdog_srst_r;     // 1-cycle datapath reset pulse
    reg        wdog_fired_r;    // sticky: cleared by start_pulse

    always @(posedge aclk) begin
        if (!aresetn) begin
            wdog_cnt_r   <= 16'd0;
            wdog_done_r  <= 1'b0;
            wdog_error_r <= 1'b0;
            wdog_srst_r  <= 1'b0;
            wdog_fired_r <= 1'b0;
        end else begin
            wdog_done_r  <= 1'b0;
            wdog_error_r <= 1'b0;
            wdog_srst_r  <= 1'b0;

            if (start_pulse_w && enable_w) begin
                // New transaction — arm watchdog
                wdog_cnt_r   <= 16'd0;
                wdog_fired_r <= 1'b0;
            end else if (dp_done_w || dp_frame_error_w) begin
                // Datapath self-terminated — disarm watchdog
                wdog_fired_r <= 1'b0;
            end else if (dp_busy_w && !wdog_fired_r &&
                         BUSY_WATCHDOG_CYCLES > 0) begin
                if (wdog_cnt_r == BUSY_WATCHDOG_CYCLES[15:0] - 16'd1) begin
                    wdog_done_r  <= 1'b1;
                    wdog_error_r <= 1'b1;
                    wdog_srst_r  <= 1'b1;   // auto-reset datapath
                    wdog_fired_r <= 1'b1;
                end else begin
                    wdog_cnt_r <= wdog_cnt_r + 16'd1;
                end
            end
        end
    end

    // Merged done/frame_error visible to register bank
    wire done_w        = dp_done_w        | wdog_done_r;
    wire frame_error_w = dp_frame_error_w | wdog_error_r;
    // Mask busy when watchdog has fired (wrapper reports not-busy)
    wire busy_w        = dp_busy_w & !wdog_fired_r;
    wire fft_error_w   = dp_fft_error_w;
    wire meyr_valid_w  = dp_meyr_valid_w;
    wire [31:0] error_code_reg_w = dp_error_code_w;

    // Debug registers: latch on done
    wire signed [15:0]          int_cfo_dp_w;
    wire [MEYR_IDX_WIDTH-1:0]   peak_index_dp_w;
    wire [MEYR_IDX_WIDTH-1:0]   peak_lag_w;
    wire signed [15:0]           frac_phase_dp_w;
    wire                         frac_phase_valid_w;
    wire [SCORE_WIDTH-1:0]       peak_score_w;

    reg [31:0] int_cfo_lat, frac_phase_lat, peak_index_lat;
    always @(posedge aclk) begin
        if (!aresetn) begin
            int_cfo_lat    <= 32'd0;
            frac_phase_lat <= 32'd0;
            peak_index_lat <= 32'd0;
        end else if (done_w) begin
            int_cfo_lat    <= {{16{int_cfo_dp_w[15]}}, int_cfo_dp_w};
            frac_phase_lat <= {{16{frac_phase_dp_w[15]}}, frac_phase_dp_w};
            peak_index_lat <= {{(32-MEYR_IDX_WIDTH){1'b0}}, peak_index_dp_w};
        end
    end

    wire [31:0] int_cfo_reg_w    = int_cfo_lat;
    wire [31:0] frac_phase_reg_w = frac_phase_lat;
    wire [31:0] peak_index_reg_w = peak_index_lat;

    assign peak_lag_o   = peak_lag_w;
    assign frac_phase_o = frac_phase_dp_w;
    assign int_cfo_o    = {{16{int_cfo_dp_w[15]}}, int_cfo_dp_w};

    // -----------------------------------------------------------------------
    // Register bank
    // -----------------------------------------------------------------------
    axi_lite_sync_regs #(
        .ADDR_WIDTH (AXI_ADDR_WIDTH),
        .DATA_WIDTH (AXI_DATA_WIDTH)
    ) u_regs (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .s_axi_awaddr     (s_axi_awaddr),
        .s_axi_awvalid    (s_axi_awvalid),
        .s_axi_awready    (s_axi_awready),
        .s_axi_wdata      (s_axi_wdata),
        .s_axi_wstrb      (s_axi_wstrb),
        .s_axi_wvalid     (s_axi_wvalid),
        .s_axi_wready     (s_axi_wready),
        .s_axi_bresp      (s_axi_bresp),
        .s_axi_bvalid     (s_axi_bvalid),
        .s_axi_bready     (s_axi_bready),
        .s_axi_araddr     (s_axi_araddr),
        .s_axi_arvalid    (s_axi_arvalid),
        .s_axi_arready    (s_axi_arready),
        .s_axi_rdata      (s_axi_rdata),
        .s_axi_rresp      (s_axi_rresp),
        .s_axi_rvalid     (s_axi_rvalid),
        .s_axi_rready     (s_axi_rready),
        .busy_i           (busy_w),
        .done_i           (done_w),
        .error_i          (frame_error_w),
        .frame_error_i    (frame_error_w),
        .fft_error_i      (fft_error_w),
        .meyr_valid_i     (meyr_valid_w),
        .int_cfo_i        (int_cfo_reg_w),
        .frac_phase_i     (frac_phase_reg_w),
        .peak_index_i     (peak_index_reg_w),
        .error_code_i     (error_code_reg_w),
        .start_pulse_o    (start_pulse_w),
        .enable_o         (enable_w),
        .soft_reset_o     (soft_reset_w),
        .clear_sticky_o   (clear_sticky_w),
        .frame_len_o      (frame_len_w),
        .nsc_o            (nsc_w),
        .cp_len_o         (cp_len_w)
    );

    // -----------------------------------------------------------------------
    // Soft-reset gating: deassert aresetn to datapath on soft_reset pulse or
    // when the busy watchdog fires (auto-reset).
    // -----------------------------------------------------------------------
    reg soft_reset_r;
    always @(posedge aclk) soft_reset_r <= soft_reset_w;
    wire dp_aresetn = aresetn && !soft_reset_r && !wdog_srst_r;

    // -----------------------------------------------------------------------
    // Datapath: real or mock selected by USE_MOCK_DATAPATH
    // -----------------------------------------------------------------------
    generate if (USE_MOCK_DATAPATH == 1) begin : gen_mock

        // All dp_* wires driven from mock
        wire mock_meyr_err;
        assign dp_fft_error_w  = 1'b0;
        assign dp_error_code_w = 32'd0;
        assign dp_meyr_valid_w = dp_done_w;

        sync_axi_smoke_mock_dp #(
            .BUSY_CYCLES     (MOCK_BUSY_CYCLES),
            .INJECT_ERROR    (MOCK_INJECT_ERROR),
            .BUF_AW          (BUF_AW),
            .MEYR_IDX_WIDTH  (MEYR_IDX_WIDTH),
            .SCORE_WIDTH     (SCORE_WIDTH),
            .IQ_WIDTH        (IQ_WIDTH),
            .ENERGY_WIDTH    (ENERGY_WIDTH)
        ) u_mock (
            .aclk             (aclk),
            .aresetn          (dp_aresetn),
            .start            (start_pulse_w && enable_w),
            .s_axis_tdata     (s_axis_iq_tdata),
            .s_axis_tvalid    (s_axis_iq_tvalid),
            .s_axis_tready    (s_axis_iq_tready),
            .s_axis_tlast     (s_axis_iq_tlast),
            .m_axis_tdata     (m_axis_iq_tdata),
            .m_axis_tvalid    (m_axis_iq_tvalid),
            .m_axis_tready    (m_axis_iq_tready),
            .m_axis_tlast     (m_axis_iq_tlast),
            .threshold_in     ({ENERGY_WIDTH{1'b0}}),
            .window_len_in    (7'd0),
            .hit_count_in     (4'd0),
            .busy             (dp_busy_w),
            .done             (dp_done_w),
            .frame_error      (dp_frame_error_w),
            .meyr_error       (mock_meyr_err),
            .frame_index      (frame_index_o),
            .peak_lag         (peak_lag_w),
            .peak_metric      (),
            .frac_phase       (frac_phase_dp_w),
            .frame_found      (frame_found_o),
            .frac_phase_valid (frac_phase_valid_w),
            .int_cfo          (int_cfo_dp_w),
            .peak_index       (peak_index_dp_w),
            .peak_score       (peak_score_w)
        );

    end else begin : gen_real

        // In the real path, phase1_ofdm_synchronizer_top does not expose a
        // corrected-IQ output stream; tie m_axis to zero.
        assign m_axis_iq_tdata  = 32'd0;
        assign m_axis_iq_tvalid = 1'b0;
        assign m_axis_iq_tlast  = 1'b0;

        // Internal wires for error code and meyr_error from real datapath
        wire        real_meyr_err;
        wire [3:0]  real_meyr_code;

        assign dp_fft_error_w  = real_meyr_err;
        assign dp_error_code_w = {{28{1'b0}}, real_meyr_code};
        assign dp_meyr_valid_w = dp_done_w && !dp_frame_error_w;

        phase1_ofdm_synchronizer_top #(
            .NSC                 (NSC),
            .CP_LEN              (CP_LEN),
            .OUTPUT_SAMPLES      (OUTPUT_SAMPLES),
            .PSS_FFT_START       (PSS_FFT_START),
            .SSS_FFT_START       (SSS_FFT_START),
            .BUF_AW              (BUF_AW),
            .ENERGY_WIDTH        (ENERGY_WIDTH),
            .WINDOW_LEN          (WINDOW_LEN),
            .HIT_COUNT           (HIT_COUNT),
            .THRESHOLD           (THRESHOLD),
            .IQ_WIDTH            (IQ_WIDTH),
            .SCORE_WIDTH         (SCORE_WIDTH),
            .MEYR_IDX_WIDTH      (MEYR_IDX_WIDTH),
            .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB),
            .STUB_TLAST_AT       (STUB_TLAST_AT),
            .STUB_STOP_AT        (STUB_STOP_AT),
            .FLUSH_COUNT         (FLUSH_COUNT),
            .WATCHDOG_CYCLES     (MEYR_WATCHDOG_CYCLES),
            .ACQ_WATCHDOG_CYCLES (ACQ_WATCHDOG_CYCLES)
        ) u_sync_real (
            .aclk              (aclk),
            .aresetn           (dp_aresetn),
            .start             (start_pulse_w && enable_w),
            .threshold_in      ({{(ENERGY_WIDTH-1){1'b0}}, 1'b1}),
            .window_len_in     (7'd0),
            .hit_count_in      (4'd0),
            .s_axis_tdata      (s_axis_iq_tdata),
            .s_axis_tvalid     (s_axis_iq_tvalid),
            .s_axis_tready     (s_axis_iq_tready),
            .s_axis_tlast      (s_axis_iq_tlast),
            .done              (dp_done_w),
            .busy              (dp_busy_w),
            .frame_found       (frame_found_o),
            .frame_error       (dp_frame_error_w),
            .meyr_error        (real_meyr_err),
            .meyr_error_code   (real_meyr_code),
            .frame_index       (frame_index_o),
            .peak_lag          (peak_lag_w),
            .frac_phase        (frac_phase_dp_w),
            .frac_phase_valid  (frac_phase_valid_w),
            .int_cfo           (int_cfo_dp_w),
            .peak_index        (peak_index_dp_w),
            .peak_score        (peak_score_w)
        );

    end endgenerate

endmodule
