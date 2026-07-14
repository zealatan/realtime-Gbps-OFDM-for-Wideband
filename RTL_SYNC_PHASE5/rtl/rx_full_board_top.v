// =====================================================================
// rx_full_board_top.v
// ---------------------------------------------------------------------
// BOARD-INTEGRATION wrapper for the FULL RX chain (sync + downstream
// FFT/CE/EQ/16QAM-demod).  This is the STAGE-1 self-contained DUT IP for
// the ZCU216 digital-loopback build.  It presents the SAME top-level
// interface as phase3_sync_axis_dma_wrapper (AXI-Lite slave + AXIS slave
// + AXIS master + dbg_frac_m tap) so it drops straight into the existing
// 10_digital_loopback BD / firmware / dut_capture path UNCHANGED.
//
// The ONLY differences vs the frozen rx_full_chain_top:
//   1. INTERNAL pilot ROM ($readmemh of the 384-word pilot_rom.hex) feeds
//      the downstream pilot stream, so the design is self-contained (no
//      external pilot port).  One word is pulled per pilot bin via
//      pilot_tready (32 pilots x 12 symbols = 384, natural order).
//   2. The m_axis master no longer carries corrected IQ; it carries the
//      DEMODULATED bits.  Each m_axis beat = one data-subcarrier nibble
//      {28'b0, b0,b1,b2,b3} (4 demod bits in [3:0]).  10608 bits = 2652
//      nibbles -> 2652 m_axis beats, captured verbatim by dut_capture
//      (DEPTH 4096 >= 2652).  tlast asserts on the final (2651st) beat.
//
// NOTHING inside rx_full_chain_top / the sync wrapper / the downstream
// modules is modified.  This file only adds the pilot ROM + the bit->beat
// adapter and re-uses the verified, BER=0 chain.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_board_top #(
    parameter integer IQ_WIDTH        = 16,
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
    // The following params exist only so the packaged IP exposes the same
    // knobs as phase3_sync_axis_dma_wrapper (the BD sets THRESHOLD=40000).
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
    parameter integer CORDIC_LATENCY  = 15,
    parameter integer NUM_SYN         = 2,
    parameter integer NUM_DATA        = 12,
    parameter integer NUM_PILOTS      = 32,
    parameter integer NDATA_SC        = 221,
    parameter         PILOT_ROM_FILE  = "pilot_rom.hex",
    parameter         EQ_LUT_FILE     = "rx_equalizer_recip_lut.hex",
    parameter         CE_W_ROM        = "ce_interp_W.hex",
    parameter         CE_RECIP_ROM    = "ce_pilot_recip.hex",
    parameter         BER_REF_ROM     = "rx_ber_ref_rom.hex"
)(
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

    // ---- AXI-Stream slave : raw IQ in (from dut_player) ----
    input  wire [2*IQ_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // ---- AXI-Stream master : PACKED DEMOD BITS out (to dut_capture) ----
    //   m_axis_tdata = {28'b0, b0,b1,b2,b3} per data subcarrier
    output wire [2*IQ_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    // ---- Debug: frac-corrected stream tap (passed through) ----
    output wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata,
    output wire                  dbg_frac_m_tvalid,
    output wire                  dbg_frac_m_tready,
    output wire                  dbg_frac_m_tlast,

    // ---- On-chip HW BER error counter (additive m_bits tap) ----
    //   ber_ctrl[0]     = soft clear (level)
    //   ber_ctrl[7:4]   = status_sel (0=total_bit_errors 1=frames_checked
    //                     2=total_nibbles 3=err_flags 4={warmup} 5=signature)
    //   ber_ctrl[11:8]  = rot_off (0..11) reference whole-symbol rotation;
    //                     firmware searches this for the aligned phase
    //   ber_status      = selected 32-bit counter word
    input  wire [31:0] ber_ctrl,
    output wire [31:0] ber_status
);
    localparam integer TOTAL_NIBBLES = NUM_DATA * NDATA_SC;   // 12*221 = 2652

    // -----------------------------------------------------------------
    // RESET-RELEASE SYNCHRONIZER (async assert, synchronous deassert).
    // The board hands us a RAW async `aresetn`.  The datapath mixes
    // async-reset leaves (rx_fft_frontend, tx_subcarrier_map) and
    // sync-reset leaves (rx_downstream_top, rx_ch_est, rx_equalizer,
    // demods); an unsynchronized async-deassert lets them leave reset on
    // different aclk edges -> a reset-release race that is benign in sim
    // (everything settles at t=0) but non-deterministic on silicon.  This
    // standard 3-stage synchronizer guarantees the DATA CHAIN sees a clean,
    // edge-aligned deassert.  u_chain (which also carries the AXI-Lite slave)
    // is driven from aresetn_sync too: the synchronizer only DELAYS deassert
    // by a few aclk edges (assert is still async/immediate), which never
    // changes the AXI-Lite handshake protocol -- firmware issues its first
    // AXI transaction long after reset release.
    // -----------------------------------------------------------------
    reg [2:0] aresetn_sync_q;
    always @(posedge aclk or negedge aresetn)
        if (!aresetn) aresetn_sync_q <= 3'b000;
        else          aresetn_sync_q <= {aresetn_sync_q[1:0], 1'b1};
    wire aresetn_sync = aresetn_sync_q[2];

    // -----------------------------------------------------------------
    // internal pilot ROM : 384 words, {Q[31:16],I[15:0]} Q15
    // -----------------------------------------------------------------
    localparam integer PROM_DEPTH = NUM_DATA * NUM_PILOTS;    // 384
    localparam integer PAW        = (PROM_DEPTH <= 1) ? 1 : $clog2(PROM_DEPTH);

    (* rom_style = "block" *) reg [2*IQ_WIDTH-1:0] pilot_rom [0:PROM_DEPTH-1];
    initial $readmemh(PILOT_ROM_FILE, pilot_rom);

    reg  [PAW:0] prom_addr;              // 1 extra bit for safe compare
    wire [2*IQ_WIDTH-1:0] pilot_tdata = pilot_rom[prom_addr[PAW-1:0]];
    wire                  pilot_tready;  // from downstream (1 per pilot bin)

    always @(posedge aclk) begin
        if (!aresetn_sync) begin
            prom_addr <= 0;
        end else if (pilot_tready) begin
            if (prom_addr == PROM_DEPTH-1) prom_addr <= 0;  // wrap per slot
            else                           prom_addr <= prom_addr + 1'b1;
        end
    end

    // -----------------------------------------------------------------
    // the frozen full chain (sync + downstream).  Its AXI-Lite/AXIS-slave
    // boundary is wired straight to this module's ports.
    // -----------------------------------------------------------------
    wire [3:0] m_bits_tdata;
    wire       m_bits_tvalid;
    wire       m_bits_tready;
    wire       m_bits_tlast;     // last data carrier (220) of a symbol
    wire       m_bits_tuser;     // first data carrier (0) of a symbol

    rx_full_chain_top #(
        .IQ_WIDTH    (IQ_WIDTH),
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .NUM_SYN     (NUM_SYN),
        .NUM_DATA    (NUM_DATA),
        .NUM_PILOTS  (NUM_PILOTS),
        .NDATA_SC    (NDATA_SC),
        .THRESHOLD   (THRESHOLD),
        .EQ_LUT_FILE (EQ_LUT_FILE),
        .CE_W_ROM    (CE_W_ROM),
        .CE_RECIP_ROM (CE_RECIP_ROM)
    ) u_chain (
        .aclk          (aclk),
        .aresetn       (aresetn_sync),

        // FIX: the multi-mod demod (rx_demod_qam) needs mod_sel; the board
        // digital-loopback / golden waveform is 16-QAM (mod_sel=1).  Previously
        // unconnected -> floated to QPSK (mod_sel=0) -> ~50% BER vs 16-QAM golden.
        .mod_sel       (2'd1),

        .s_axi_awaddr  (s_axi_awaddr),  .s_axi_awvalid (s_axi_awvalid), .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),   .s_axi_wstrb   (s_axi_wstrb),   .s_axi_wvalid  (s_axi_wvalid),  .s_axi_wready (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),   .s_axi_bvalid  (s_axi_bvalid),  .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),  .s_axi_arvalid (s_axi_arvalid), .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),   .s_axi_rresp   (s_axi_rresp),   .s_axi_rvalid  (s_axi_rvalid),  .s_axi_rready (s_axi_rready),

        .s_axis_tdata  (s_axis_tdata),  .s_axis_tvalid (s_axis_tvalid), .s_axis_tready (s_axis_tready), .s_axis_tlast (s_axis_tlast),

        .pilot_tdata   (pilot_tdata),   .pilot_tready  (pilot_tready),

        .m_bits_tdata  (m_bits_tdata),  .m_bits_tvalid (m_bits_tvalid),
        .m_bits_tready (m_bits_tready), .m_bits_tlast  (m_bits_tlast),  .m_bits_tuser (m_bits_tuser),

        // seam tap (unused at the board boundary)
        .dbg_sync_m_tdata  (), .dbg_sync_m_tvalid (), .dbg_sync_m_tready (), .dbg_sync_m_tlast (),

        .dbg_frac_m_tdata  (dbg_frac_m_tdata), .dbg_frac_m_tvalid (dbg_frac_m_tvalid),
        .dbg_frac_m_tready (dbg_frac_m_tready), .dbg_frac_m_tlast  (dbg_frac_m_tlast)
    );

    // -----------------------------------------------------------------
    // bit -> beat adapter : one 32-bit m_axis beat per demod nibble.
    //   tdata = {28'b0, b0,b1,b2,b3}.  Count beats to assert tlast on the
    //   final (2651st) nibble of the slot.  Pure pass-through handshake.
    // -----------------------------------------------------------------
    reg [12:0] beat_cnt;   // 0..2651 (needs 12 bits; 13 for headroom)

    assign m_axis_tdata  = {{(2*IQ_WIDTH-4){1'b0}}, m_bits_tdata};
    assign m_axis_tvalid = m_bits_tvalid;
    assign m_bits_tready = m_axis_tready;
    assign m_axis_tlast  = m_bits_tvalid && (beat_cnt == TOTAL_NIBBLES-1);

    always @(posedge aclk) begin
        if (!aresetn_sync) begin
            beat_cnt <= 13'd0;
        end else if (m_bits_tvalid && m_axis_tready) begin
            if (beat_cnt == TOTAL_NIBBLES-1) beat_cnt <= 13'd0;
            else                             beat_cnt <= beat_cnt + 1'b1;
        end
    end

    // -----------------------------------------------------------------
    // ON-CHIP HW BER error counter (passive snoop on the m_bits stream).
    // Read-only tap: it does NOT drive m_bits_tready (that is owned by the
    // bit->beat adapter above). Compares each accepted demod nibble against
    // the golden 2652-nibble reference and accumulates bit errors / frames.
    // -----------------------------------------------------------------
    rx_ber_checker #(
        .NDATA_SC     (NDATA_SC),
        .NUM_DATA     (NUM_DATA),
        .REF_ROM_FILE (BER_REF_ROM)
    ) u_ber (
        .aclk          (aclk),
        .aresetn       (aresetn_sync),
        .m_bits_tvalid (m_bits_tvalid),
        .m_bits_tready (m_bits_tready),   // = m_axis_tready (passive read)
        .m_bits_tdata  (m_bits_tdata),
        .m_bits_tuser  (m_bits_tuser),
        .m_bits_tlast  (m_bits_tlast),
        .rot_off       (ber_ctrl[11:8]),
        .clr           (ber_ctrl[0]),
        .status_sel    (ber_ctrl[7:4]),
        .status_data   (ber_status)
    );

endmodule

`default_nettype wire
