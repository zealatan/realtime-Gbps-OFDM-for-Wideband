// =====================================================================
// rx_full_top.v
// ---------------------------------------------------------------------
// FULL-RX INTEGRATION — STEP 1 : SYNC  ->  FFT FRONT-END
// ---------------------------------------------------------------------
// This is the first stage of a step-by-step full-RX integration. It
// attaches ONLY the FFT front-end (rx_fft_frontend) to the existing,
// frozen synchronizer DUT (phase3_sync_axis_dma_wrapper). No CE / EQ /
// demod yet — those are added in later steps.
//
// DATA PATH
// ---------
//   S_AXIS (raw IQ, {Q[31:16],I[15:0]} Q15)
//      -> phase3_sync_axis_dma_wrapper   (frame detect + timing + CFO)
//      -> sync m_axis (4032-sample corrected slot, beat0 = PSS CP start)
//      -> rx_fft_frontend                (skip 2 sync syms + per-sym CP,
//                                          256-pt FFT + fftshift + 1/16)
//      -> M_AXIS_FFT  (12 x 256 freq bins, fftshift order, {Q,I} Q15)
//
// The seam between the two is a plain AXI-Stream; backpressure is
// honored in both directions (the fft front-end's s_ready feeds the
// sync wrapper's m_axis_tready).
//
// NOTHING in the synchronizer is modified — this module only INSTANTIATES
// the existing wrapper and the existing fft front-end and wires them.
//
// The AXI-Lite slave and all sync debug ports are passed straight
// through to this module's boundary so a TB can configure the regs
// (threshold 0x68, frame_len 0x0C, debug_ctrl 0x4C) and observe the
// frame-detect / peak / slot-start indications exactly as the existing
// sync gates do.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_top #(
    parameter integer IQ_WIDTH        = 16,
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
    parameter integer NUM_SYN         = 2,
    parameter integer NUM_DATA        = 12,
    parameter integer SCALE_SH        = 4,
    parameter integer THRESHOLD       = 10240000
) (
    input  wire        aclk,
    input  wire        aresetn,

    // ---- AXI4-Lite slave (-> sync wrapper) ----
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

    // ---- AXI-Stream slave : raw IQ in ----
    input  wire [2*IQ_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // ---- AXI-Stream master : FFT freq bins out ----
    output wire [2*IQ_WIDTH-1:0] m_axis_fft_tdata,
    output wire                  m_axis_fft_tvalid,
    input  wire                  m_axis_fft_tready,
    output wire                  m_axis_fft_tlast,   // 1 on last bin (255) of each symbol

    // ---- seam tap : the sync corrected M_AXIS (for observation/debug) ----
    output wire [2*IQ_WIDTH-1:0] dbg_sync_m_tdata,
    output wire                  dbg_sync_m_tvalid,
    output wire                  dbg_sync_m_tready,
    output wire                  dbg_sync_m_tlast,

    // ---- sync debug taps (frac-corrected tap, passed through) ----
    output wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata,
    output wire                  dbg_frac_m_tvalid,
    output wire                  dbg_frac_m_tready,
    output wire                  dbg_frac_m_tlast
);

    // -----------------------------------------------------------------
    // seam wires : sync wrapper M_AXIS  ->  fft front-end S
    // -----------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0] sync_m_tdata;
    wire                  sync_m_tvalid;
    wire                  sync_m_tready;
    wire                  sync_m_tlast;

    // -----------------------------------------------------------------
    // 1.  EXISTING, FROZEN SYNCHRONIZER DUT  (do NOT modify)
    // -----------------------------------------------------------------
    phase3_sync_axis_dma_wrapper #(
        .IQ_WIDTH   (IQ_WIDTH),
        .NSC        (NSC),
        .CP_LEN     (CP_LEN),
        .THRESHOLD  (THRESHOLD)
    ) u_sync (
        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axi_awaddr  (s_axi_awaddr),  .s_axi_awvalid (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),   .s_axi_wstrb   (s_axi_wstrb),   .s_axi_wvalid  (s_axi_wvalid),  .s_axi_wready (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),   .s_axi_bvalid  (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),  .s_axi_arvalid (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),   .s_axi_rresp   (s_axi_rresp),   .s_axi_rvalid  (s_axi_rvalid),  .s_axi_rready (s_axi_rready),

        .s_axis_tdata  (s_axis_tdata),  .s_axis_tvalid (s_axis_tvalid), .s_axis_tready (s_axis_tready), .s_axis_tlast (s_axis_tlast),

        // sync corrected stream  ->  seam
        .m_axis_tdata  (sync_m_tdata),  .m_axis_tvalid (sync_m_tvalid), .m_axis_tready (sync_m_tready), .m_axis_tlast (sync_m_tlast),

        .dbg_frac_m_tdata (dbg_frac_m_tdata), .dbg_frac_m_tvalid (dbg_frac_m_tvalid),
        .dbg_frac_m_tready (dbg_frac_m_tready), .dbg_frac_m_tlast (dbg_frac_m_tlast)
    );

    // -----------------------------------------------------------------
    // 2.  FFT FRONT-END  (consumes the corrected slot)
    // -----------------------------------------------------------------
    // The fft front-end's s_ready back-pressures the sync M_AXIS, so the
    // corrected slot is consumed at the rate the FFT can accept body
    // samples (sync / CP samples are always accepted and dropped).
    rx_fft_frontend #(
        .DATA_W   (IQ_WIDTH),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .NUM_SYN  (NUM_SYN),
        .NUM_DATA (NUM_DATA),
        .SCALE_SH (SCALE_SH)
    ) u_fft (
        .clk      (aclk),
        .rst_n    (aresetn),

        .s_valid  (sync_m_tvalid),
        .s_ready  (sync_m_tready),
        .s_tdata  (sync_m_tdata),
        .s_tlast  (sync_m_tlast),   // slot-boundary re-anchor (NO-OP in lock)

        .m_valid  (m_axis_fft_tvalid),
        .m_ready  (m_axis_fft_tready),
        .m_tdata  (m_axis_fft_tdata),
        .m_last   (m_axis_fft_tlast)
    );

    // -----------------------------------------------------------------
    // 3.  seam observation taps
    // -----------------------------------------------------------------
    assign dbg_sync_m_tdata  = sync_m_tdata;
    assign dbg_sync_m_tvalid = sync_m_tvalid;
    assign dbg_sync_m_tready = sync_m_tready;
    assign dbg_sync_m_tlast  = sync_m_tlast;

endmodule

`default_nettype wire
