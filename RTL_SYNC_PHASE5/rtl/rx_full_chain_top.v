// =====================================================================
// rx_full_chain_top.v
// ---------------------------------------------------------------------
// FULL-RX INTEGRATION — STEP 2 : SYNC -> FULL DOWNSTREAM (FFT/CE/EQ/DEMOD)
// ---------------------------------------------------------------------
// Step 1 (rx_full_top.v) proved the SYNC -> FFT front-end seam. This step
// extends it to the COMPLETE downstream by attaching the existing,
// independently-verified rtl/rx_downstream_top.v (BER=0 standalone)
// directly to the synchronizer DUT's corrected M_AXIS.
//
// DATA PATH
// ---------
//   S_AXIS (raw IQ, {Q[31:16],I[15:0]} Q15, 4160-sample frame)
//      -> phase3_sync_axis_dma_wrapper   (frame detect + timing + CFO)
//      -> sync m_axis (4032-sample corrected slot, beat0 = PSS CP start)
//      -> rx_downstream_top
//             rx_fft_frontend  (skip 2 sync syms + per-sym CP, 256pt FFT
//                               + fftshift + 1/16)
//          -> rx_ch_est        (pilot-based CE + 32-tap interp_fft)
//          -> ping-pong RX-bin / H align buffer
//          -> rx_equalizer     (ZF: RX*conj(H)/|H|^2)
//          -> data-carrier gate (221 dataIndx bins)
//          -> rx_demod_16qam   (hard-slice 4 bits/carrier)
//      -> M_AXIS_BITS  (12 x 884 = 10608 demodulated bits)
//
// NOTHING in the synchronizer, the downstream top, or the 4 downstream
// modules is modified — this module ONLY instantiates the two frozen tops
// (phase3_sync_axis_dma_wrapper + rx_downstream_top) and wires the plain
// AXI-Stream seam between them.
//
// SEAM TIMING NOTE (carried from step 1)
// --------------------------------------
// The sync DUT emits its corrected slot-1 sample EARLY (slot_start_index
// = 63 vs the offset-free golden's 64) — a within-tolerance (+/-2) timing
// quantization. This puts a 1-sample cyclic rotation (per-bin linear phase
// ramp) on every FFT symbol. Step 1 confirmed it directly: the seam best-
// aligns at offset -1 (sum|d| ~= 1008, essentially exact) and the FFT
// magnitudes match the golden on 3036/3048 bins while I/Q rotate — a PURE
// phase ramp, not a scale/ordering/timing bug. That ramp is absorbed by
// the pilot-based channel estimation (the CE captures the 1-sample timing
// phase as a 1-tap channel delay, well inside interp_fft's 32-tap budget)
// and divided out by the ZF equalizer — exactly as the C reference handles
// residual timing. The END-TO-END criterion is therefore demod BER vs the
// offset-free golden bits, NOT a per-stage (FFT/H/EQ) bit-match.
//
// The AXI-Lite slave and the sync debug taps are passed straight through
// to this module's boundary so a TB can configure the regs and observe the
// frame-detect / peak / slot-start indications exactly as the sync gates do.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_chain_top #(
    parameter integer IQ_WIDTH   = 16,
    parameter integer NSC        = 256,
    parameter integer CP_LEN     = 32,
    parameter integer NUM_SYN    = 2,
    parameter integer NUM_DATA   = 12,
    parameter integer NUM_PILOTS = 32,
    parameter integer NDATA_SC   = 221,
    parameter integer BPC_MAX    = 8,
    parameter integer SCALE_SH   = 4,
    parameter integer THRESHOLD  = 10240000,
    parameter         EQ_LUT_FILE = "rx_equalizer_recip_lut.hex",
    parameter         CE_W_ROM    = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    parameter         CE_RECIP_ROM = "rtl/rx_ch_est_rom/ce_pilot_recip.hex"
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

    // ---- pilot ROM stream : one word pulled per captured pilot bin ----
    input  wire [2*IQ_WIDTH-1:0] pilot_tdata,
    output wire                  pilot_tready,

    // ---- modulation select for the data demod (pilots stay QPSK) ----
    input  wire [1:0]            mod_sel,        // 0=QPSK 1=16QAM 2=64QAM 3=256QAM

    // ---- AXI-Stream master : demodulated bits out ----
    output wire [BPC_MAX-1:0]    m_bits_tdata,   // 16-QAM: [b0 b1 b2 b3] in [3:0]
    output wire                  m_bits_tvalid,
    input  wire                  m_bits_tready,
    output wire                  m_bits_tlast,   // last data carrier (220) of a symbol
    output wire                  m_bits_tuser,   // first data carrier (0) of a symbol

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
    // seam wires : sync wrapper M_AXIS  ->  rx_downstream_top S
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
    // 2.  FULL DOWNSTREAM  (FFT -> CE -> EQ -> DEMOD), frozen, BER=0 standalone
    // -----------------------------------------------------------------
    // The downstream top's s_ready (sourced from rx_fft_frontend's s_ready)
    // back-pressures the sync M_AXIS exactly like step 1; CP/sync samples are
    // always accepted and dropped, body samples are consumed at the FFT rate.
    rx_downstream_top #(
        .DW          (IQ_WIDTH),
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .NUM_SYN     (NUM_SYN),
        .NUM_DATA    (NUM_DATA),
        .NUM_PILOTS  (NUM_PILOTS),
        .NDATA_SC    (NDATA_SC),
        .TUSERW      (16),
        .BPC_MAX     (BPC_MAX),
        .EQ_LUT_FILE (EQ_LUT_FILE),
        .CE_W_ROM    (CE_W_ROM),
        .CE_RECIP_ROM (CE_RECIP_ROM)
    ) u_ds (
        .clk     (aclk),
        .rst_n   (aresetn),

        .mod_sel (mod_sel),

        // sync corrected slot in
        .s_valid (sync_m_tvalid),
        .s_ready (sync_m_tready),
        .s_tdata (sync_m_tdata),
        // sync slot-boundary tlast -> re-anchors FFT slot_pos (DESYNC-514 self-
        // heal); previously left UNCONNECTED (only tapped to dbg_sync_m_tlast).
        .s_tlast (sync_m_tlast),

        // pilot ROM stream
        .pilot_tdata  (pilot_tdata),
        .pilot_tready (pilot_tready),

        // demodulated bits out
        .m_valid (m_bits_tvalid),
        .m_ready (m_bits_tready),
        .m_bits  (m_bits_tdata),
        .m_last  (m_bits_tlast),
        .m_user  (m_bits_tuser)
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
