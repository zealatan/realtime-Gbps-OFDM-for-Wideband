// =====================================================================
// ofdm_transceiver_top.v
// ---------------------------------------------------------------------
// MODE-SELECTABLE OFDM TRANSCEIVER TOP.
//
// ONE design that, by a runtime mode[1:0] select, behaves as:
//
//   mode 0  TX        : data_bits_flat -> tx_ofdm_top -> tx_out_* master.
//                       The RX chain is held idle (no input driven into it).
//
//   mode 1  RX        : ext_s_axis (raw 4160-sample sync-capable frame)
//                       -> rx_full_chain_top -> m_bits_* demod master.
//                       The TX is held idle (not started).
//
//   mode 2  LOOPBACK  : tx_ofdm_top -> internal 64+4032+64 = 4160 frame
//                       wrap (the SAME framing proven in
//                       tb/tx_rx_full_loopback_tb.sv, BER 0/10608)
//                       -> rx_full_chain_top -> m_bits_* demod master,
//                       plus rx_ber_checker for on-chip self-test BER.
//                       No external I/O needed.
//
// This wrapper instantiates ONLY frozen, independently-verified modules:
//     tx_ofdm_top        (frozen TX,  4032-sample slot, BER=0 standalone)
//     rx_full_chain_top  (frozen RX,  sync + FFT/CE/EQ/16QAM demod)
//     rx_ber_checker     (passive demod BER monitor)
// Nothing inside those modules is modified.
//
// TWO KEY MUXES
// -------------
//   1. RX input mux:
//        rx_s_axis = (mode==LOOPBACK) ? tx_framed_stream : ext_s_axis
//      In TX mode the RX input is forced idle (tvalid=0), so an idle TX can
//      never inject into the RX.
//   2. TX output exposure:
//        tx_out_* carries the TX master in TX and LOOPBACK modes (the live
//        transmit stream). In RX mode the TX is not started, so tx_out is
//        idle.
//
// LOOPBACK FRAMING (factored out of the proven TB)
// ------------------------------------------------
//   The live TX emits a 4032-sample slot (m_last on 4031). In LOOPBACK the
//   wrapper captures that slot into a 4032-word buffer, then a small framing
//   FSM replays it into the RX S_AXIS as:
//        64 lead-in zeros | 4032 slot | 64 trailing zeros  = 4160 beats,
//   honoring rx s_axis_tready, asserting tlast on the final (4159th) beat.
//   This is byte-identical to golden/rx_downstream/tx_slot_iq.hex framing.
//
// CONTROL
// -------
//   mode[1:0]      runtime mode select (0/1/2 as above).
//   start          1-cycle pulse: in TX/LOOPBACK kicks the TX slot (and, in
//                  LOOPBACK, arms the framing replay once the slot is buffered).
//   ber_ctrl[31:0] rx_ber_checker control, board-mirrored layout:
//                      bit0     = soft clear (level)
//                      bit7:4   = status_sel (which BER counter to read)
//                      bit11:8  = rot_off (0..11 whole-symbol ref rotation)
//   ber_status     selected rx_ber_checker counter (read total_bit_errors at
//                  status_sel=0; the aligned rot_off reads 0).
//   The synchronizer enable / frame_len / threshold are configured through the
//   pass-through AXI4-Lite slave (regs 0x04 enable, 0x0C frame_len=4032,
//   0x68 threshold) exactly as rx_full_chain_top / the board top expect.
//
// All control signals are plain top-level inputs here so the design is usable
// directly (GPIO) OR by wiring mode/start/ber_ctrl to AXI-Lite/GPIO registers
// in the board BD (documented; the board integration is the remaining step).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module ofdm_transceiver_top #(
    parameter integer IQ_WIDTH   = 16,
    parameter integer NSC        = 256,
    parameter integer CP_LEN     = 32,
    parameter integer NUM_SYN    = 2,
    parameter integer NUM_DATA   = 12,
    parameter integer NUM_PILOTS = 32,
    parameter integer NDATA_SC   = 221,
    parameter integer BPC_MAX    = 8,
    parameter integer SCALE_SH   = 4,
    parameter integer THRESHOLD  = 40000,
    parameter integer LEAD_IN    = 64,
    parameter integer TRAILER    = 64,
    // TX ROMs
    parameter         TX_SPECMAP  = "rtl/tx_rom/tx_specmap.hex",
    parameter         TX_SYNC_ROM = "rtl/tx_rom/tx_sync_rom.hex",
    // RX ROMs
    parameter         EQ_LUT_FILE  = "rx_equalizer_recip_lut.hex",
    parameter         CE_W_ROM     = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    parameter         CE_RECIP_ROM = "ce_pilot_recip.hex",
    parameter         BER_REF_ROM  = "rx_ber_ref_rom.hex"
) (
    input  wire        aclk,
    input  wire        aresetn,

    // ====== MODE / CONTROL ======
    input  wire  [1:0] mode,         // 0=TX, 1=RX, 2=LOOPBACK
    input  wire  [1:0] mod_sel,      // 0=QPSK 1=16QAM 2=64QAM 3=256QAM (data)
    input  wire        start,        // 1-cycle pulse (TX/LOOPBACK)
    input  wire        lb_cont,      // LOOPBACK continuous re-emit (level); when
                                     // high the framing FSM re-arms after every
                                     // frame so the live-TX slot streams back-to-
                                     // back (gapless) into the RX for the on-chip
                                     // continuous BER checker. Default 0 = single-
                                     // frame (bit-exact prior behavior).
    input  wire [31:0] ber_ctrl,     // rx_ber_checker control (see header)
    output wire [31:0] ber_status,   // selected rx_ber_checker counter

    // ====== STATUS ======
    output wire        tx_busy,
    output wire        rx_frame_locked,  // sync frame_start_valid seen (sticky)

    // ====== TX DATA INPUT (TX / LOOPBACK) ======
    input  wire [NUM_DATA*NDATA_SC*BPC_MAX-1:0] data_bits_flat,
    // TX pilot ROM addressed read (caller / board ROM returns word)
    output wire [8:0]              tx_pilot_addr,
    input  wire [2*IQ_WIDTH-1:0]   tx_pilot_tdata,

    // ====== TX OUTPUT STREAM (transmit master; TX / LOOPBACK) ======
    output wire [2*IQ_WIDTH-1:0]   tx_out_tdata,
    output wire                    tx_out_tvalid,
    input  wire                    tx_out_tready,
    output wire                    tx_out_tlast,

    // ====== EXTERNAL RX INPUT (RX mode) : raw IQ frame ======
    input  wire [2*IQ_WIDTH-1:0]   ext_s_axis_tdata,
    input  wire                    ext_s_axis_tvalid,
    output wire                    ext_s_axis_tready,
    input  wire                    ext_s_axis_tlast,

    // ====== RX pilot ROM stream (RX / LOOPBACK) ======
    input  wire [2*IQ_WIDTH-1:0]   rx_pilot_tdata,
    output wire                    rx_pilot_tready,

    // ====== RX DEMOD OUTPUT (RX / LOOPBACK) ======
    output wire [BPC_MAX-1:0]      m_bits_tdata,
    output wire                    m_bits_tvalid,
    input  wire                    m_bits_tready,
    output wire                    m_bits_tlast,
    output wire                    m_bits_tuser,

    // ====== AXI4-Lite slave (-> sync wrapper inside rx_full_chain_top) ======
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
    localparam integer SLOT_LEN   = (NUM_SYN + NUM_DATA) * (NSC + CP_LEN); // 4032
    localparam integer FRAME_LEN  = LEAD_IN + SLOT_LEN + TRAILER;          // 4160

    localparam [1:0] MODE_TX = 2'd0, MODE_RX = 2'd1, MODE_LB = 2'd2;

    wire mode_tx = (mode == MODE_TX);
    wire mode_rx = (mode == MODE_RX);
    wire mode_lb = (mode == MODE_LB);
    wire tx_active = mode_tx | mode_lb;   // TX runs in TX and LOOPBACK

    // =================================================================
    // 1. LIVE TX  (tx_ofdm_top) — frozen
    // =================================================================
    wire        tx_m_valid;
    wire [2*IQ_WIDTH-1:0] tx_m_tdata;
    wire        tx_m_last;
    wire        tx_m_ready;     // see mux below
    // gate start: only kick the TX when TX or LOOPBACK is selected
    wire        tx_start = start & tx_active;

    tx_ofdm_top #(
        .DATA_W(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NPIL(NUM_PILOTS), .NDATA_SC(NDATA_SC), .BPC_MAX(BPC_MAX),
        .Q16_1(1610), .Q16_3(4829),
        .SPECMAP(TX_SPECMAP), .SYNC_ROM(TX_SYNC_ROM)
    ) u_tx (
        .clk(aclk), .rst_n(aresetn),
        .mod_sel(mod_sel),
        .start(tx_start), .busy(tx_busy),
        .data_bits_flat(data_bits_flat),
        .pilot_addr(tx_pilot_addr), .pilot_tdata(tx_pilot_tdata),
        .m_valid(tx_m_valid), .m_ready(tx_m_ready),
        .m_tdata(tx_m_tdata), .m_last(tx_m_last)
    );

    // -----------------------------------------------------------------
    // LOOPBACK slot capture : PING-PONG double buffer (M2-full). A new payload
    // slot is captured into the SPARE buffer (~rd_sel) while the framing FSM
    // keeps emitting the ACTIVE buffer (rd_sel) -- the emitted stream NEVER
    // stops, so the RX sync stays locked across a payload change. The old
    // single-buffer scheme reset the framing FSM on every tx_start, stalling the
    // stream -> the RX lost lock (errf=0x9 desync on multi-frame streaming).
    // The 576-sample sync preamble is identical for every payload, so the RX
    // re-detects each back-to-back frame; only the data symbols swap.
    // -----------------------------------------------------------------
    reg [2*IQ_WIDTH-1:0] slot_mem0 [0:SLOT_LEN-1];
    reg [2*IQ_WIDTH-1:0] slot_mem1 [0:SLOT_LEN-1];
    reg [12:0] cap_cnt;        // 0..4032
    reg        rd_sel;         // buffer the framing FSM emits (spare = ~rd_sel)
    reg        fill_ready;     // spare holds a fresh complete slot, waiting to swap
    reg        slot_ready;     // >=1 slot ever captured (arms framing)
    wire       wr_sel   = ~rd_sel;                 // capture always fills the spare
    wire       cap_beat = mode_lb & tx_m_valid & tx_m_ready;

    // ping-pong memory write : capture the live TX slot into the spare buffer.
    // (cap_cnt / fill_ready / rd_sel are advanced by the unified FSM below; the
    // swap only ever fires when fill_ready=1, i.e. no capture is in flight, so
    // wr_sel can never flip mid-capture.)
    always @(posedge aclk) begin
        if (cap_beat && cap_cnt < SLOT_LEN[12:0]) begin
            if (wr_sel) slot_mem1[cap_cnt] <= tx_m_tdata;
            else        slot_mem0[cap_cnt] <= tx_m_tdata;
        end
    end

    // TX master ready:
    //   - LOOPBACK : the capture always accepts (1 sample/clk) AND honor the
    //                exposed tx_out backpressure (tied high by board normally).
    //   - TX       : the external transmit consumer (tx_out_tready).
    //   - RX       : TX idle (not started); ready don't-care, hold low.
    assign tx_m_ready = mode_lb ? 1'b1 :
                        mode_tx ? tx_out_tready :
                                  1'b0;

    // TX output stream exposed in TX / LOOPBACK
    assign tx_out_tdata  = tx_m_tdata;
    assign tx_out_tvalid = tx_active & tx_m_valid;
    assign tx_out_tlast  = tx_m_last;

    // =================================================================
    // 2. LOOPBACK FRAMING FSM : replay 64 zeros + 4032 slot + 64 zeros
    //    into the RX S_AXIS, honoring rx tready, tlast on the last beat.
    //    Factored from tb/tx_rx_full_loopback_tb.sv drive_input().
    // =================================================================
    reg  [13:0] fr_idx;        // 0..4159
    reg         fr_run;        // framing replay active
    reg         fr_done;       // replay finished
    // start the replay once the first slot is captured (LOOPBACK only)
    wire        fr_arm = mode_lb & slot_ready & ~fr_run & ~fr_done;

    wire        lb_s_tvalid;
    wire [2*IQ_WIDTH-1:0] lb_s_tdata;
    wire        lb_s_tlast;
    wire        rx_s_tready;   // from sync (rx_full_chain S_AXIS tready)

    wire        fr_in_slot = (fr_idx >= LEAD_IN[13:0]) &&
                             (fr_idx <  LEAD_IN[13:0] + SLOT_LEN[13:0]);
    // read the ACTIVE ping-pong buffer
    wire [2*IQ_WIDTH-1:0] slot_rd = rd_sel ? slot_mem1[fr_idx - LEAD_IN[13:0]]
                                           : slot_mem0[fr_idx - LEAD_IN[13:0]];

    assign lb_s_tvalid = fr_run;
    assign lb_s_tdata  = fr_in_slot ? slot_rd : {(2*IQ_WIDTH){1'b0}};
    assign lb_s_tlast  = fr_run & (fr_idx == FRAME_LEN[13:0]-1);

    // Unified capture-advance + framing FSM (one block owns cap_cnt / slot_ready
    // / fill_ready / rd_sel / fr_* so buffer ownership never has two drivers).
    always @(posedge aclk) begin
        if (!aresetn || !mode_lb) begin
            cap_cnt    <= 13'd0;
            rd_sel     <= 1'b0;
            fill_ready <= 1'b0;
            slot_ready <= 1'b0;
            fr_idx     <= 14'd0;
            fr_run     <= 1'b0;
            fr_done    <= 1'b0;
        end else begin
            // ---- capture arm / advance (fills the spare buffer ~rd_sel) ----
            if (tx_start) begin
                cap_cnt <= 13'd0;              // (re)arm capture into the spare
                if (!lb_cont) begin            // single-frame: re-arm framing per
                    slot_ready <= 1'b0;        // kick + wait for the fresh slot
                    fill_ready <= 1'b0;        // (bit-exact legacy behavior)
                    fr_idx     <= 14'd0;
                    fr_run     <= 1'b0;
                    fr_done    <= 1'b0;
                end
                // lb_cont: DO NOT touch framing/slot_ready -> stream stays
                // continuous; the new slot swaps in seamlessly at the next
                // frame boundary via fill_ready.
            end else if (cap_beat) begin
                if (cap_cnt < SLOT_LEN[12:0]) cap_cnt <= cap_cnt + 13'd1;
                if (tx_m_last) begin
                    slot_ready <= 1'b1;        // >=1 slot available
                    fill_ready <= 1'b1;        // spare now holds a complete slot
                end
            end
            // ---- framing FSM (continuous, seamless ping-pong swap) ----
            if (fr_arm) begin
                fr_run     <= 1'b1;
                fr_idx     <= 14'd0;
                rd_sel     <= ~rd_sel;         // emit the just-filled spare
                fill_ready <= 1'b0;
            end else if (fr_run && rx_s_tready) begin
                if (fr_idx == FRAME_LEN[13:0]-1) begin
                    if (lb_cont) begin
                        fr_idx <= 14'd0;       // fr_run stays 1 (gapless next frame)
                        if (fill_ready) begin  // seamless payload swap at boundary
                            rd_sel     <= ~rd_sel;
                            fill_ready <= 1'b0;
                        end
                    end else begin
                        fr_run  <= 1'b0;
                        fr_done <= 1'b1;
                    end
                end else begin
                    fr_idx <= fr_idx + 14'd1;
                end
            end
        end
    end

    // =================================================================
    // 3. RX INPUT MUX  (the key mux)
    //    rx_s_axis = LOOPBACK ? tx_framed_stream : ext_s_axis
    //    TX mode  : force idle (tvalid=0) so an idle TX cannot inject.
    // =================================================================
    wire [2*IQ_WIDTH-1:0] rx_s_tdata  = mode_lb ? lb_s_tdata  : ext_s_axis_tdata;
    wire                  rx_s_tvalid = mode_lb ? lb_s_tvalid :
                                        mode_rx ? ext_s_axis_tvalid : 1'b0;
    wire                  rx_s_tlast  = mode_lb ? lb_s_tlast  : ext_s_axis_tlast;

    // external S_AXIS ready only meaningful in RX mode
    assign ext_s_axis_tready = mode_rx ? rx_s_tready : 1'b0;

    // =================================================================
    // 4. FULL RX  (rx_full_chain_top) — frozen
    // =================================================================
    wire [2*IQ_WIDTH-1:0] dbg_sync_m_tdata;
    wire                  dbg_sync_m_tvalid, dbg_sync_m_tready, dbg_sync_m_tlast;
    wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                  dbg_frac_m_tvalid, dbg_frac_m_tready, dbg_frac_m_tlast;

    rx_full_chain_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NUM_PILOTS(NUM_PILOTS), .NDATA_SC(NDATA_SC), .BPC_MAX(BPC_MAX),
        .SCALE_SH(SCALE_SH), .THRESHOLD(THRESHOLD),
        .EQ_LUT_FILE(EQ_LUT_FILE), .CE_W_ROM(CE_W_ROM), .CE_RECIP_ROM(CE_RECIP_ROM)
    ) u_rx (
        .aclk(aclk), .aresetn(aresetn),
        .mod_sel(mod_sel),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axis_tdata(rx_s_tdata), .s_axis_tvalid(rx_s_tvalid), .s_axis_tready(rx_s_tready), .s_axis_tlast(rx_s_tlast),
        .pilot_tdata(rx_pilot_tdata), .pilot_tready(rx_pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .dbg_sync_m_tdata(dbg_sync_m_tdata), .dbg_sync_m_tvalid(dbg_sync_m_tvalid),
        .dbg_sync_m_tready(dbg_sync_m_tready), .dbg_sync_m_tlast(dbg_sync_m_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready), .dbg_frac_m_tlast(dbg_frac_m_tlast)
    );

    // sticky frame-lock status (read from the sync wrapper debug-tap)
    reg frame_locked_r;
    always @(posedge aclk) begin
        if (!aresetn) frame_locked_r <= 1'b0;
        else if (u_rx.u_sync.u_dut.dbg_frame_start_valid) frame_locked_r <= 1'b1;
    end
    assign rx_frame_locked = frame_locked_r;

    // =================================================================
    // 5. ON-CHIP BER SELF-TEST  (rx_ber_checker) — passive tap
    // =================================================================
    rx_ber_checker #(
        .NDATA_SC(NDATA_SC), .NUM_DATA(NUM_DATA), .REF_ROM_FILE(BER_REF_ROM)
    ) u_ber (
        .aclk(aclk), .aresetn(aresetn),
        .m_bits_tvalid(m_bits_tvalid), .m_bits_tready(m_bits_tready),
        .m_bits_tdata(m_bits_tdata[3:0]), .m_bits_tuser(m_bits_tuser), .m_bits_tlast(m_bits_tlast),
        .rot_off(ber_ctrl[11:8]),
        .clr(ber_ctrl[0]),
        .status_sel(ber_ctrl[7:4]),
        .status_data(ber_status)
    );

endmodule

`default_nettype wire
