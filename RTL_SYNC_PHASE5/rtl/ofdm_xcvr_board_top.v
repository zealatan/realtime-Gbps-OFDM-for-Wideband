// =====================================================================
// ofdm_xcvr_board_top.v
// ---------------------------------------------------------------------
// BOARD ADAPTER for the mode-selectable OFDM transceiver.
//
// Wraps the FROZEN ofdm_transceiver_top (TX / RX / LOOPBACK by mode[1:0])
// and presents the EXACT SAME formal boundary as the previously-packaged
// rx_full_board_top IP (same AXI4-Lite slave + s_axis/m_axis AXIS + ber
// GPIO ports). This makes it a DROP-IN replacement in the proven
// 11_full_rx_loopback BD: only the IP VLNV in the BD is swapped; all the
// wiring (dut_player.m_axis -> s_axis, m_axis -> dut_capture.s_axis,
// AXI-Lite, ber_ctrl/ber_status GPIO) stays byte-identical.
//
// This adapter ADDS the board-side glue that the bare ofdm_transceiver_top
// leaves external (and that rx_full_board_top already provided), WITHOUT
// touching any frozen module:
//
//   1. INTERNAL pilot ROM ($readmemh pilot_rom.hex), 384 words, feeding
//      BOTH the TX addressed-read pilot port (tx_pilot_addr/tdata) and the
//      RX streamed pilot port (rx_pilot_tdata/tready). Self-contained.
//   2. INTERNAL TX data-bits ROM ($readmemb-style packed hex, 332 words)
//      driving data_bits_flat for TX / LOOPBACK -- the same golden bits the
//      host BER compares against (tx_bits.txt == tx_data_bits.txt).
//   3. bit -> 32b beat adapter on the demod output (m_bits[3:0] ->
//      {28'b0,b0..b3}) with a per-frame tlast every 2652 nibbles -- byte-
//      identical to rx_full_board_top so ber_demod_bits.py / dut_capture
//      are unchanged.
//   4. M_AXIS MUX: in TX mode (mode==0) the m_axis carries the live TX
//      output IQ (tx_out_*), so dut_capture records the EMITTED slot for the
//      host to verify byte-exact vs golden tx_slot_iq_4032.hex. In RX/LOOPBACK
//      it carries the packed demod nibbles.
//   5. MODE / START decode from the existing ber_ctrl GPIO (NO new GPIO,
//      NO BD rewiring):
//        ber_ctrl[31:30] = mode   (0=TX, 1=RX, 2=LOOPBACK)
//        ber_ctrl[29]    = start  (level; rising edge -> 1-cycle start pulse)
//        ber_ctrl[11:0]  = real rx_ber_checker control (clr / status_sel /
//                          rot_off), passed straight through.
//      ber_status is the rx_ber_checker counter exactly as before (secondary
//      readout; the headline BER is host-computed from dut_capture).
//
// All of (1)-(5) is plain board glue (ROMs, a counter, muxes, an edge
// detector). The OFDM transmit / receive / loopback datapath is 100% the
// frozen ofdm_transceiver_top (which itself only wraps the frozen
// tx_ofdm_top + rx_full_chain_top + rx_ber_checker).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module ofdm_xcvr_board_top #(
    parameter integer IQ_WIDTH        = 16,
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
    // knob-compat with rx_full_board_top so the BD CONFIG.THRESHOLD override works
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
    parameter integer THRESHOLD       = 40000,
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
    parameter         BER_REF_ROM     = "rx_ber_ref_rom.hex",
    parameter         TX_DATA_BITS_ROM= "tx_data_bits_packed.hex",
    parameter         TX_SPECMAP      = "tx_specmap.hex",
    parameter         TX_SYNC_ROM     = "tx_sync_rom.hex"
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

    // ---- AXI-Stream slave : MM2S TX-payload in (from AXI DMA MM2S, DDR) ----
    // 32-bit, 332 beats -> 10608-bit data_bits_flat4 (see axi_to_parallel_tx).
    input  wire [31:0]           tx_s_axis_tdata,
    input  wire                  tx_s_axis_tvalid,
    output wire                  tx_s_axis_tready,
    input  wire                  tx_s_axis_tlast,

    // ---- AXI-Stream master : demod bits OR (TX mode) tx IQ -> dut_capture ----
    output wire [2*IQ_WIDTH-1:0] m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast,

    // ---- Debug: frac-corrected stream tap (kept for IP-iface compat) ----
    output wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata,
    output wire                  dbg_frac_m_tvalid,
    output wire                  dbg_frac_m_tready,
    output wire                  dbg_frac_m_tlast,

    // ---- ber GPIO : ber_ctrl[31:30]=mode, [29]=start, [11:0]=real ber ctrl ----
    input  wire [31:0] ber_ctrl,
    output wire [31:0] ber_status
);
    localparam integer TOTAL_NIBBLES = NUM_DATA * NDATA_SC;        // 2652
    localparam integer BPC_MAX       = 8;                          // 256-QAM
    localparam integer NDATA_BITS    = NUM_DATA * NDATA_SC * 4;    // 10608 (16-QAM ROM)
    localparam integer NCARR         = NUM_DATA * NDATA_SC;        // 2652 carriers
    localparam integer PROM_DEPTH    = NUM_DATA * NUM_PILOTS;      // 384
    localparam integer DBROM_WORDS    = (NDATA_BITS + 31) / 32;    // 332

    // dbg_frac tap: repurposed as a MM2S-bridge diagnostic (BD leaves it open).
    // Driven below, after the bridge instance (tdata={frame_cnt,beat_cnt}).
    assign dbg_frac_m_tready = 1'b1;
    assign dbg_frac_m_tlast  = 1'b0;

    // =================================================================
    // MODE / START decode from ber_ctrl (board contract; no new GPIO)
    // =================================================================
    wire [1:0] mode      = ber_ctrl[31:30];
    wire       start_lvl = ber_ctrl[29];
    // ber_ctrl[28] = continuous-loopback (level): in LOOPBACK the framing FSM
    // re-emits the captured live-TX slot back-to-back so the on-chip passive
    // rx_ber_checker can tally a long continuous run. 0 = single-frame (default).
    wire       lb_cont_lvl = ber_ctrl[28];
    // ber_ctrl[27] = use_dma (level): 0 = TX payload from the on-chip golden ROM
    // (bit-identical to the pre-DMA build), 1 = TX payload from the MM2S DMA
    // bridge active bank (arbitrary DDR payload). Default 0 -> golden.
    wire       use_dma_lvl = ber_ctrl[27];
    // ber_ctrl[12] = transceiver soft-reset (level). Resets the WHOLE u_xcvr
    // (TX + RX sync + demod + loopback framing FSM) so multi-frame loopback can
    // idle the framing state BETWEEN frames -- the DUT_CONTROL soft-reset only
    // reaches the phase3 sync core, not the transceiver's loopback adapter, so
    // without this every 2nd+ frame desyncs (RESET_WHILE_ACTIVE). The bridge
    // bank lives outside u_xcvr, so a DMA'd payload survives this reset.
    reg xcvr_srst_d0, xcvr_srst_d1;
    always @(posedge aclk) begin
        if (!aresetn) begin xcvr_srst_d0 <= 1'b0; xcvr_srst_d1 <= 1'b0; end
        else begin xcvr_srst_d0 <= ber_ctrl[12]; xcvr_srst_d1 <= xcvr_srst_d0; end
    end
    wire xcvr_rstn = aresetn & ~xcvr_srst_d1;
    // 2-FF synchronize the async GPIO level, then rising-edge -> 1-cyc pulse
    reg start_d0, start_d1, start_d2;
    always @(posedge aclk) begin
        if (!aresetn) begin
            start_d0 <= 1'b0; start_d1 <= 1'b0; start_d2 <= 1'b0;
        end else begin
            start_d0 <= start_lvl;
            start_d1 <= start_d0;
            start_d2 <= start_d1;
        end
    end
    wire start_pulse = start_d1 & ~start_d2;

    wire [31:0] ber_ctrl_inner = {20'b0, ber_ctrl[11:0]};  // clr/status_sel/rot_off

    localparam [1:0] MODE_TX = 2'd0;
    wire mode_tx = (mode == MODE_TX);

    // =================================================================
    // INTERNAL pilot ROM (shared TX addressed-read + RX streamed)
    // =================================================================
    (* rom_style = "block" *) reg [2*IQ_WIDTH-1:0] pilot_rom [0:PROM_DEPTH-1];
    initial $readmemh(PILOT_ROM_FILE, pilot_rom);

    // TX side: addressed read
    wire  [8:0]               tx_pilot_addr;
    wire  [2*IQ_WIDTH-1:0]    tx_pilot_tdata = pilot_rom[tx_pilot_addr[8:0]];

    // RX side: streamed (one word per pilot bin via rx_pilot_tready)
    wire                      rx_pilot_tready;
    reg   [8:0]               rx_plt_ptr;
    wire  [2*IQ_WIDTH-1:0]    rx_pilot_tdata = pilot_rom[rx_plt_ptr[8:0]];
    always @(posedge aclk) begin
        if (!aresetn)                                       rx_plt_ptr <= 9'd0;
        else if (start_pulse)                               rx_plt_ptr <= 9'd0;
        else if (rx_pilot_tready && rx_plt_ptr < PROM_DEPTH-1)
                                                            rx_plt_ptr <= rx_plt_ptr + 9'd1;
    end

    // =================================================================
    // INTERNAL TX data-bits ROM (packed 32b words -> data_bits_flat)
    // =================================================================
    reg [31:0] db_rom [0:DBROM_WORDS-1];
    initial $readmemh(TX_DATA_BITS_ROM, db_rom);
    // 16-QAM packed (4 bits/carrier) flat bus from the ROM (golden fallback)
    wire [NDATA_BITS-1:0] rom_flat4;
    genvar gw;
    generate
        for (gw = 0; gw < DBROM_WORDS; gw = gw + 1) begin : g_dbrom
            if ((gw*32 + 32) <= NDATA_BITS) begin : g_full
                assign rom_flat4[gw*32 +: 32] = db_rom[gw];
            end else begin : g_part
                // last partial word (10608 = 331*32 + 16)
                assign rom_flat4[gw*32 +: (NDATA_BITS - gw*32)] =
                       db_rom[gw][(NDATA_BITS - gw*32)-1:0];
            end
        end
    endgenerate

    // =================================================================
    // MM2S DMA -> parallel TX-payload bridge (arbitrary DDR payload).
    //   use_dma=0 -> rom_flat4 (golden, pre-DMA-identical)
    //   use_dma=1 -> DMA active double-buffer bank (arbitrary payload)
    // Same bit order as tx_data_bits_packed.hex (verified 0-diff vs golden).
    // =================================================================
    wire [NDATA_BITS-1:0] data_bits_flat4;
    wire                  tx_load_done;
    wire [15:0]           tx_dma_beats, tx_dma_frames;
    axi_to_parallel_tx #(
        .NDATA_BITS(NDATA_BITS), .SW(32)
    ) u_tx_bridge (
        .aclk(aclk), .aresetn(aresetn),
        .rom_flat4(rom_flat4),
        .use_dma(use_dma_lvl),
        .s_axis_tdata (tx_s_axis_tdata),
        .s_axis_tvalid(tx_s_axis_tvalid),
        .s_axis_tready(tx_s_axis_tready),
        .s_axis_tlast (tx_s_axis_tlast),
        .data_bits_flat4(data_bits_flat4),
        .load_done(tx_load_done),
        .beat_count(tx_dma_beats),
        .frame_count(tx_dma_frames),
        .dbg_rdaddr(ber_ctrl[24:16]),
        .dbg_rdword(tx_dma_dbgword)
    );
    wire [31:0] tx_dma_dbgword;
    // bridge diagnostic on the otherwise-open dbg_frac tap
    assign dbg_frac_m_tdata  = {tx_dma_frames, tx_dma_beats};
    assign dbg_frac_m_tvalid = tx_load_done;

    // OBSERVABILITY (bug2): expose the MM2S bridge counters on ber_status when
    // ber_ctrl[26]=1 so firmware can read, per DMA transfer, how many frames the
    // bridge completed (frame_count delta should be exactly 1; >1 => spurious/
    // burst tlast partial-fills) and the live beat pointer (widx).
    // ber_ctrl[26]=1 -> bridge debug on ber_status; [25]=1 -> active-bank word at
    // addr ber_ctrl[24:16], else {frame_count, beat_count}.
    wire [31:0] ber_status_core;
    assign ber_status = ber_ctrl[26]
                      ? (ber_ctrl[25] ? tx_dma_dbgword : {tx_dma_frames, tx_dma_beats})
                      : ber_status_core;

    // Board uses 16-QAM (mod_sel=1): expand each carrier's 4 ROM bits into the
    // low nibble of an 8-bit (BPC_MAX) per-carrier slot; high bits = 0.
    localparam [1:0] BOARD_MOD_SEL = 2'd1;   // 16-QAM (board default, unchanged)
    wire [NCARR*BPC_MAX-1:0] data_bits_flat;
    genvar gc;
    generate
        for (gc = 0; gc < NCARR; gc = gc + 1) begin : g_expand
            assign data_bits_flat[gc*BPC_MAX +: BPC_MAX] =
                   { {(BPC_MAX-4){1'b0}}, data_bits_flat4[gc*4 +: 4] };
        end
    endgenerate

    // =================================================================
    // FROZEN mode-selectable transceiver
    // =================================================================
    wire [2*IQ_WIDTH-1:0] tx_out_tdata;
    wire                  tx_out_tvalid, tx_out_tlast;
    wire                  tx_out_tready;

    wire [BPC_MAX-1:0]    m_bits_tdata;
    wire                  m_bits_tvalid, m_bits_tready, m_bits_tlast, m_bits_tuser;

    ofdm_transceiver_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NUM_PILOTS(NUM_PILOTS), .NDATA_SC(NDATA_SC), .BPC_MAX(BPC_MAX),
        .SCALE_SH(4), .THRESHOLD(THRESHOLD),
        .EQ_LUT_FILE(EQ_LUT_FILE), .CE_W_ROM(CE_W_ROM), .CE_RECIP_ROM(CE_RECIP_ROM),
        .BER_REF_ROM(BER_REF_ROM),
        .TX_SPECMAP(TX_SPECMAP), .TX_SYNC_ROM(TX_SYNC_ROM)
    ) u_xcvr (
        .aclk(aclk), .aresetn(xcvr_rstn),
        .mode(mode), .mod_sel(BOARD_MOD_SEL), .start(start_pulse), .lb_cont(lb_cont_lvl),
        .ber_ctrl(ber_ctrl_inner), .ber_status(ber_status_core),
        .tx_busy(), .rx_frame_locked(),
        .data_bits_flat(data_bits_flat),
        .tx_pilot_addr(tx_pilot_addr), .tx_pilot_tdata(tx_pilot_tdata),
        .tx_out_tdata(tx_out_tdata), .tx_out_tvalid(tx_out_tvalid),
        .tx_out_tready(tx_out_tready), .tx_out_tlast(tx_out_tlast),
        .ext_s_axis_tdata(s_axis_tdata), .ext_s_axis_tvalid(s_axis_tvalid),
        .ext_s_axis_tready(s_axis_tready), .ext_s_axis_tlast(s_axis_tlast),
        .rx_pilot_tdata(rx_pilot_tdata), .rx_pilot_tready(rx_pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready)
    );

    // =================================================================
    // bit -> 32b beat adapter (RX / LOOPBACK demod path), per-frame tlast
    // =================================================================
    reg [12:0] beat_cnt;                                   // 0..2651
    wire [2*IQ_WIDTH-1:0] demod_word = {{(2*IQ_WIDTH-4){1'b0}}, m_bits_tdata[3:0]};
    wire demod_tlast = m_bits_tvalid && (beat_cnt == TOTAL_NIBBLES-1);
    always @(posedge aclk) begin
        if (!aresetn) beat_cnt <= 13'd0;
        else if (m_bits_tvalid && m_bits_tready) begin
            if (beat_cnt == TOTAL_NIBBLES-1) beat_cnt <= 13'd0;
            else                             beat_cnt <= beat_cnt + 13'd1;
        end
    end

    // =================================================================
    // M_AXIS MUX:
    //   TX mode      -> live TX output IQ (dut_capture records emitted slot)
    //   RX/LOOPBACK  -> packed demod nibbles
    // The non-selected source's ready is held so it does not stall.
    // =================================================================
    assign m_axis_tdata  = mode_tx ? tx_out_tdata  : demod_word;
    assign m_axis_tvalid = mode_tx ? tx_out_tvalid : m_bits_tvalid;
    assign m_axis_tlast  = mode_tx ? tx_out_tlast  : demod_tlast;

    // demod consumer ready: only when NOT TX mode (in TX mode the demod path
    // is idle anyway). TX output consumer ready: only in TX mode.
    assign m_bits_tready = (~mode_tx) & m_axis_tready;
    assign tx_out_tready = mode_tx ? m_axis_tready : 1'b1;

endmodule

`default_nettype wire
