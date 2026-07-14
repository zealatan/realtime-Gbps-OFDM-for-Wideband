// =====================================================================
// rx_downstream_top.v
// ---------------------------------------------------------------------
// OFDM RX DOWNSTREAM integration TOP.  Wires the 4 verified, golden-
// validated, timing-closed downstream modules into one AXI-Stream chain:
//
//      (sync M_AXIS, 4032 {Q,I} Q15)
//             |
//   +---------v----------+
//   |  rx_fft_frontend   |  symbol-extract + 256pt FFT + fftshift + 1/16
//   +---------+----------+  -> 12 x 256 freq bins, fftshift order, {Q,I}
//             |  (FX[i], i=bin 0..255, m_last on bin 255)
//             +----------------------------+
//             |                            |
//   +---------v----------+        +--------v--------------------------+
//   |   rx_ch_est        |        |  RX-BIN ALIGN BUFFER (ping-pong)  |
//   |  (CE + interp_fft) |        |  256x32 x2 : stores FX symbol s,  |
//   |  + pilot_rom       |        |  replays it bin-by-bin in lockstep|
//   +---------+----------+        |  with the matching H symbol s     |
//             |  (H[i], 12x256)   +--------+--------------------------+
//             |                            |
//             |  H stream  ----------------+----  (drives the read of the
//             |                            |       align buffer: the EQ
//   +---------v----------------------------v--------+ consumes RX[i] and
//   |              rx_equalizer (ZF)                 | H[i] for the SAME
//   |   eq[i] = RX[i]*conj(H[i]) / |H[i]|^2          | symbol/bin together
//   +---------+-------------------------------------+
//             |  (eq[i], all 256 bins, TUSER = bin index 0..255)
//   +---------v----------+
//   |  DATA-CARRIER GATE |  keep only the 221 dataIndx bins (ascending);
//   |  (dataIndx mask)   |  drop pilots / DC / bins 0,255.
//   +---------+----------+
//             |  (12 x 221 equalized data carriers)
//   +---------v----------+
//   |  rx_demod_16qam    |  hard-slice -> 4 bits/carrier
//   +---------+----------+
//             |  m_bits[3:0], m_last on carrier 220 of each symbol
//             v   (12 x 884 bits)
//
// ---------------------------------------------------------------------
// ALIGNMENT SCHEME  (the core integration concern)
// ---------------------------------------------------------------------
// rx_ch_est has SYMBOL-GRANULARITY latency: it must collect a whole
// symbol's 256 bins (to capture the 32 pilots), then run the interp MAC
// pipeline, before the FIRST H bin of that symbol appears.  The matching
// RX freq bins emerge from the FFT front-end MUCH earlier.  So the EQ
// cannot just be fed FX and H from the two source streams directly --
// they are skewed by (at least) one whole symbol.
//
// Fix: a ping-pong RX-bin buffer.  The FFT front-end's m_axis FX stream
// is FORKED:
//    (a) into rx_ch_est  (which derives H), and
//    (b) into a 256x32 ping-pong RAM that stores every FX symbol.
// The H stream out of rx_ch_est is the MASTER of the equalizer feed: for
// every H beat (symbol s, bin b, in order 0..255) we read the SAME (s,b)
// FX word back out of the align buffer and present BOTH to the EQ on the
// same cycle.  The two EQ inputs are therefore bin-for-bin, symbol-for-
// symbol aligned by construction, independent of the exact ch_est
// latency.  Because ch_est emits exactly one ordered 0..255 H symbol per
// stored FX symbol, the buffer's write/read symbol pointers track each
// other with a 2-deep ping-pong (capture symbol s+1 while H of symbol s
// is read out).
//
// FORK BACK-PRESSURE: the FFT front-end FX beat is only accepted when
// BOTH consumers can take it: rx_ch_est (s_axis_tready) AND the align
// buffer (room in the target ping-pong bank).  The align-buffer read
// side is paced by the H stream / EQ ready, so no FX bin is ever dropped
// or duplicated and AXI-Stream tready is honored end to end.
//
// ---------------------------------------------------------------------
// DATA-CARRIER GATE
// ---------------------------------------------------------------------
// rx_equalizer equalizes all 256 bins and tags each with its bin index
// on m_axis_tuser.  rx_demod_16qam only wants the 221 dataIndx carriers
// (CONTRACT sec 2/3.3).  A tiny combinational mask (is_data_bin) drops
// the 35 non-data bins (32 pilots + DC + bins 0/255) and forwards only
// the data carriers to the demod, asserting s_last on the last data
// carrier of each symbol (bin 254 is the final dataIndx entry).
//
// ---------------------------------------------------------------------
// TOTAL LATENCY (sym-extract -> first output bit), approx:
//   FFT front-end : 576 (sync skip) + 32 (CP) + 256 (fill) + xfft pipe
//                   (~ a few hundred) + readout regs.  First FX symbol
//                   appears after ~1 symbol of fill + IP latency.
//   ch_est        : +256 (collect symbol) + 8 (interp pipe) before H[0].
//   align buffer  : +1 (registered read).
//   equalizer     : +9 (divider depth) +1 (output reg).
//   data gate     : +1.
//   demod         : +1.
//   => first bit emerges ~ (2 symbols + FFT-IP + ~12) cycles after the
//      first data sample is presented; steady-state throughput is then a
//      sustained 1 carrier/clk on the data carriers (gaps only on the 35
//      non-data bins per symbol, which is the natural data density).
//   The full-chain TB measures and prints the exact first-bit latency.
//
// ---------------------------------------------------------------------
// TIMING:  this top adds only a 256x32 ping-pong RAM + a handful of
// counters / a comb data-mask.  The min Fmax across the 4 submodules is
// the equalizer (~268 MHz, the complex divider).  The added align buffer
// is a simple synchronous-write / registered-read RAM (BRAM-mappable)
// and the data gate is comparator logic, neither deeper than the
// equalizer's divider path -> the integrated Fmax is still set by the
// equalizer (~268 MHz), not by this wrapper.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_downstream_top #(
    parameter integer DW         = 16,    // I/Q sample width (Q15)
    parameter integer NSC        = 256,
    parameter integer CP_LEN     = 32,
    parameter integer NUM_SYN    = 2,
    parameter integer NUM_DATA   = 12,
    parameter integer NUM_PILOTS = 32,
    parameter integer NDATA_SC   = 221,
    parameter integer TUSERW     = 16,
    parameter integer BPC_MAX    = 8,     // max demod bits/carrier (256-QAM)
    parameter         EQ_LUT_FILE = "rx_equalizer_recip_lut.hex",
    parameter         CE_W_ROM    = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    // CE pilot-reciprocal ROM W[k]=conj(plt[k])/|plt[k]|^2 (replaces CE divide);
    // relative default resolves next to ce_interp_W.hex (like CE_W_ROM).
    parameter         CE_RECIP_ROM = "rtl/rx_ch_est_rom/ce_pilot_recip.hex"
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // ---- modulation select for the data demod (pilots stay QPSK) ----
    input  wire [1:0]            mod_sel,    // 0=QPSK 1=16QAM 2=64QAM 3=256QAM

    // ---- slave : synchronizer corrected M_AXIS, {Q[31:16],I[15:0]} Q15 ----
    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [2*DW-1:0]       s_tdata,    // {Q,I} Q15
    // sync slot-boundary marker -> re-anchors the FFT front-end slot_pos to the
    // true frame boundary (DESYNC-514 self-heal); NO-OP in normal lock.
    input  wire                  s_tlast,

    // ---- pilot ROM stream : one word pulled per captured pilot bin ----
    input  wire [2*DW-1:0]       pilot_tdata,
    output wire                  pilot_tready,

    // ---- master : demodulated bits, up to BPC_MAX bits/data-carrier ----
    //   m_bits[K-1:0]=I axis, m_bits[2K-1:K]=Q axis, K=mod_sel+1. For
    //   16-QAM (mod_sel=1) m_bits[3:0]=[b0 b1 b2 b3] as before.
    output wire                  m_valid,
    input  wire                  m_ready,
    output wire [BPC_MAX-1:0]    m_bits,
    output wire                  m_last,     // last data carrier (220) of a symbol
    output wire                  m_user      // first data carrier (0) of a symbol
);
    localparam integer PW = 8;  // log2(256)

    // =================================================================
    // 1.  FFT FRONT-END  -> freq bins FX[i]
    // =================================================================
    wire        fx_valid;
    wire        fx_ready;
    wire [31:0] fx_tdata;
    wire        fx_last;       // 1 on bin 255 of each symbol

    wire        fx_fstart;     // 1 on bin 0 of the frame's first data symbol (sym0)

    rx_fft_frontend #(
        .DATA_W(DW), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA), .SCALE_SH(4)
    ) u_fft (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_tdata(s_tdata),
        .s_tlast(s_tlast),
        .m_valid(fx_valid), .m_ready(fx_ready),
        .m_tdata(fx_tdata), .m_last(fx_last),
        .m_fstart(fx_fstart)
    );

    // =================================================================
    // 2.  FORK FX -> (a) rx_ch_est, (b) RX-bin align buffer
    //     A FX beat is accepted only when BOTH consumers are ready.
    // =================================================================
    wire ce_in_ready;      // rx_ch_est s_axis_tready
    wire buf_wr_ready;     // align buffer has room in the target bank
    wire fx_fire = fx_valid & fx_ready;

    assign fx_ready = ce_in_ready & buf_wr_ready;

    // valid presented to each consumer only when the OTHER is also ready
    wire ce_in_valid  = fx_valid & buf_wr_ready;
    wire buf_wr_valid = fx_valid & ce_in_ready;

    // =================================================================
    // 3.  RX-BIN ALIGN BUFFER  (ping-pong 256x32, 2 banks)
    //     Write side: captures FX symbol-by-symbol (bin 0..255), driven
    //       by the FORK (buf_wr_valid & buf_wr_ready).
    //     Read side : paced by the H stream / equalizer feed.  For every
    //       H beat (symbol s, bin b) we read back FX(s,b).  The read
    //       symbol pointer follows the write pointer with a ping-pong
    //       full/empty handshake so RX and H reach the EQ in lockstep.
    // =================================================================
    // The align buffer is paced ENTIRELY by the H stream so it can never
    // desync from rx_ch_est:
    //   * write side  : driven by the FX fork (same beat that feeds CE), so
    //     the FX symbol and the CE input symbol are written in lockstep.
    //   * read side   : the read column = the bin position of the CURRENT H
    //     beat; the read bank flips exactly on h_tlast.  Because rx_ch_est
    //     consumes ALL 256 FX bins of symbol s before it can emit H[s], the
    //     matching FX symbol is always fully buffered by the time its H is
    //     read out.  A symbol-count guard (rd_sym < wr_sym) makes this
    //     explicit and provides the EQ-feed valid gate.
    //
    // NUM_BANKS=3 (vs the minimal 2) gives one symbol of slack so the FFT
    // front-end can keep writing FX[s+1] while H[s] reads out and CE works
    // on s, with no back-pressure bubble at the fork.
    localparam integer NB    = 3;           // ping-pong-pong banks
    localparam integer NBLOG = 2;           // ceil(log2(3))
    reg  [31:0] rxbuf [0:NB-1][0:NSC-1];
    // Zero-init the FFT->EQ align RAM so silicon BRAM/LUTRAM powers up to a
    // KNOWN 0 (it is combinationally read at :rxbuf_rdata while sync-reset
    // pointers race the async FFT frontend; uninitialized it reads 0 in sim
    // but RANDOM on silicon -> non-deterministic BER).  Mirrors ram_2port.v.
    integer rxbuf_init_b, rxbuf_init_k;
    initial begin
        for (rxbuf_init_b = 0; rxbuf_init_b < NB;  rxbuf_init_b = rxbuf_init_b + 1)
            for (rxbuf_init_k = 0; rxbuf_init_k < NSC; rxbuf_init_k = rxbuf_init_k + 1)
                rxbuf[rxbuf_init_b][rxbuf_init_k] = 32'h0;
    end

    reg  [PW-1:0]    wr_bin;     // 0..255 write column
    reg  [NBLOG-1:0] wr_bank;    // bank being written (0..2, round-robin)
    reg  [3:0]       wr_sym;     // count of fully-written FX symbols (mod 16)

    wire wr_fire = buf_wr_valid & buf_wr_ready;
    // room to write while fewer than NB symbols are in flight (wr-rd)
    wire [3:0] rd_sym;
    wire [3:0] inflight = wr_sym - rd_sym;
    assign buf_wr_ready = (inflight < NB[3:0]);

    // ---- WRITE-side per-frame SELF-HEAL --------------------------------
    // fx_fstart pulses on bin 0 of the frame's first data symbol, latency-
    // aligned to the align-buffer write side (it rides WITH fx_tdata).  On the
    // marker beat we RE-ANCHOR the write geometry to the frame-start bank/bin
    // (bank 0, bin 0).  In steady lock the marker ALWAYS coincides with the
    // natural per-symbol wrap to bank 0 (NUM_DATA=12 is a multiple of NB=3), so
    // wr_bank is already 0 and wr_bin already 0 -> this is a BIT-EXACT NO-OP.
    // After a transient stall it snaps a drifted write bank back to bank 0 so
    // the FFT<->align symbol pairing can never stay a symbol offset.
    // NOTE: wr_sym (mod-16, paired with rd_sym for the inflight guard) is NOT
    // re-anchored here -- it must stay a monotone free-running counter so
    // inflight = wr_sym - rd_sym remains valid across the (differently-timed)
    // write/read frame markers.
`ifdef NO_SELFHEAL
    wire wr_heal = 1'b0;                   // TEST-ONLY: disable the self-heal
`else
    wire wr_heal = wr_fire & fx_fstart;   // frame-start beat accepted
`endif
`ifdef FAULT_INJECT_WRBANK
    reg fault_done; reg [3:0] fault_at_sym;
    initial begin
        fault_done = 1'b0;
        if (!$value$plusargs("FAULT_AT_SYM=%d", fault_at_sym)) fault_at_sym = 4'd5;
    end
`endif
    // effective bank/column this beat writes into (healed on the marker)
    wire [NBLOG-1:0] wr_bank_eff = wr_heal ? {NBLOG{1'b0}} : wr_bank;
    wire [PW-1:0]    wr_bin_eff  = wr_heal ? {PW{1'b0}}    : wr_bin;
`ifdef SELFHEAL_PROBE
    // TEST-ONLY marker-integrity probe (guarded; never in the bitstream):
    // logs each per-frame write-anchor event and whether the align write bank
    // was already frame-aligned (NO-OP) or had DRIFTED (anchor corrects it).
    always @(posedge clk) if (rst_n & wr_fire & fx_fstart)
        $display("[PROBE] fx_fstart @t=%0t wr_bank=%0d wr_bin=%0d wr_sym=%0d %s",
                 $time, wr_bank, wr_bin, wr_sym,
                 (wr_bank==0 && wr_bin==0) ? "ALIGNED" : "DRIFTED*");
`endif

    // frame_wr_sym : the wr_sym value at which the frame's sym0 is written (the
    // frame-start bank is bank 0).  Captured on the write marker so the READ side
    // can detect its OWN frame boundary (rd_sym==frame_wr_sym) and re-anchor
    // rd_bank to bank 0 there -- the read-side analogue of the write anchor,
    // which also re-aligns the CE-output <-> align-read bank pairing after a
    // stall.  frame_valid gates it until the first marker is seen.
    reg  [3:0] frame_wr_sym;
    reg        frame_valid;
    initial begin frame_wr_sym = 4'd0; frame_valid = 1'b0; end

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_bin    <= {PW{1'b0}};
            wr_bank   <= {NBLOG{1'b0}};
            wr_sym    <= 4'd0;
            frame_wr_sym <= 4'd0;
            frame_valid  <= 1'b0;
        end else if (wr_fire) begin
            if (wr_heal) begin frame_wr_sym <= wr_sym; frame_valid <= 1'b1; end
            rxbuf[wr_bank_eff][wr_bin_eff] <= fx_tdata;
            if (wr_bin_eff == NSC-1) begin
                wr_bin  <= {PW{1'b0}};
                wr_bank <= (wr_bank_eff == NB-1) ? {NBLOG{1'b0}} : wr_bank_eff + 1'b1;
                wr_sym  <= wr_sym + 4'd1;
            end else begin
                wr_bin  <= wr_bin_eff + 1'b1;
                wr_bank <= wr_bank_eff;
            end
`ifdef FAULT_INJECT_WRBANK
            // TEST-ONLY (guarded): inject a ONE-TIME write-bank slip at a chosen
            // symbol boundary to EMULATE the ILA-observed transient-stall pointer
            // drift.  This LAST non-blocking write to wr_bank overrides the normal
            // advance above (source-order-last NBA wins), bumping wr_bank by an
            // EXTRA +1 -> the FFT<->align pairing shifts by one symbol.  Without
            // the fx_fstart self-heal this desyncs PERMANENTLY (~47% BER for all
            // later frames); WITH the fix the next frame marker snaps wr_bank back
            // to bank 0 and the receiver returns to BER=0.  Never in the bitstream.
            if (wr_bin_eff==NSC-1 && wr_sym==fault_at_sym && !fault_done) begin
                wr_bank    <= (wr_bank_eff>=NB-2) ? (wr_bank_eff+2-NB) : wr_bank_eff + 2'd2; // +2 instead of +1
                fault_done <= 1'b1;
            end
`endif
        end
    end

    // Read side: paced by the H/EQ handshake (eq_feed_fire).
    reg  [PW-1:0]    rd_bin;
    reg  [NBLOG-1:0] rd_bank;
    reg  [3:0]       rd_sym_r;
    assign rd_sym = rd_sym_r;

    wire eq_feed_fire;          // a {RX,H} pair accepted by the EQ this cycle
    wire rd_ready = (rd_sym != wr_sym);   // matching FX symbol is buffered

    // ---- READ-side per-frame SELF-HEAL --------------------------------
    // The write anchor re-aligns the align-buffer WRITE bank to frame-sym0 in
    // bank 0, but the align-buffer READ bank (rd_bank) is paced by the CE H
    // stream (eq_feed_fire) and can drift RELATIVE to the read-domain frame
    // phase after a long output stall (the CE ping-pong / interp-engine re-arms
    // in a phase the write anchor does not touch -> the align-READ <-> CE-output
    // bank pairing slips, an ~50% desync that the write anchor alone does NOT
    // heal).  Fix: the read side re-anchors rd_bank to the frame-start bank
    // (bank 0) at its OWN frame boundary -- detected as rd_sym == frame_wr_sym,
    // the wr_sym value latched when the write side wrote frame-sym0 (both are the
    // SAME mod-16 symbol counter, advanced once per symbol, so equality marks the
    // exact read of the frame's sym0).  In steady lock rd_bank is ALREADY 0 at
    // that boundary (write anchored sym0 to bank 0, NUM_DATA=12 % NB=3 == 0), so
    // this is a BIT-EXACT NO-OP; after a stall it snaps a drifted rd_bank back to
    // bank 0, restoring the align-read <-> CE-output pairing.  Gated by
    // frame_valid so it is inert until the first frame marker is observed.
    wire rd_boundary = (rd_bin == {PW{1'b0}});
    wire rd_heal     = eq_feed_fire & rd_boundary & frame_valid
                       & (rd_sym_r == frame_wr_sym) & (rd_bank != {NBLOG{1'b0}});
    wire [NBLOG-1:0] rd_bank_eff = rd_heal ? {NBLOG{1'b0}} : rd_bank;

    // combinational read of the active read bank (healed selection)
    wire [31:0] rxbuf_rdata = rxbuf[rd_bank_eff][rd_bin];

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_bin   <= {PW{1'b0}};
            rd_bank  <= {NBLOG{1'b0}};
            rd_sym_r <= 4'd0;
        end else if (eq_feed_fire) begin
            if (rd_bin == NSC-1) begin
                rd_bin   <= {PW{1'b0}};
                rd_bank  <= (rd_bank_eff == NB-1) ? {NBLOG{1'b0}} : rd_bank_eff + 1'b1;
                rd_sym_r <= rd_sym_r + 4'd1;
            end else begin
                rd_bin  <= rd_bin + 1'b1;
                rd_bank <= rd_bank_eff;
            end
        end
    end

    // =================================================================
    // 4.  CHANNEL ESTIMATION  (CE + interp_fft)  -> H[i]
    // =================================================================
    wire [31:0] h_tdata;
    wire        h_tvalid;
    wire        h_tready;
    wire        h_tlast;

    rx_ch_est #(
        .NSC(NSC), .NUM_PILOTS(NUM_PILOTS), .NUM_DATA(NUM_DATA),
        .W_ROM(CE_W_ROM), .W_RECIP_ROM(CE_RECIP_ROM)
    ) u_ce (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(fx_tdata),
        .s_axis_tvalid(ce_in_valid),
        .s_axis_tready(ce_in_ready),
        .s_axis_tlast(fx_last),
        .pilot_tdata(pilot_tdata),
        .pilot_tready(pilot_tready),
        .m_axis_tdata(h_tdata),
        .m_axis_tvalid(h_tvalid),
        .m_axis_tready(h_tready),
        .m_axis_tlast(h_tlast)
    );

    // -----------------------------------------------------------------
    // EQ FEED: pair the H stream with the aligned RX bin from the buffer.
    //   - present a beat to the EQ when the H stream is valid AND the read
    //     bank is fully written (the matching FX symbol is buffered).
    //   - the EQ accepts when its s_axis_rx/h tready is high.
    //   - the SAME handshake advances the H consumption, the align-buffer
    //     read pointer, and feeds the equalizer -> bin-for-bin lockstep.
    // -----------------------------------------------------------------
    wire eq_rx_ready;          // rx_equalizer s_axis_rx_tready
    wire eq_h_ready;           // rx_equalizer s_axis_h_tready

    wire eq_feed_valid = h_tvalid & rd_ready;   // both RX and H available
    // equalizer takes RX & H together; its two readys are equal by design
    // (each is gated by the other's tvalid).  Present both valids high.
    assign eq_feed_fire = eq_feed_valid & eq_rx_ready;
    // consume one H beat exactly when the EQ feed fires
    assign h_tready     = eq_feed_fire;

    // =================================================================
    // 5.  EQUALIZER  (ZF)  -> eq[i], TUSER = bin index
    // =================================================================
    wire        eq_m_valid;
    wire        eq_m_ready;
    wire [31:0] eq_m_tdata;
    wire [TUSERW-1:0] eq_m_tuser;

    rx_equalizer #(
        .DW(DW), .HW(18), .OW(DW), .TUSERW(TUSERW), .LUT_FILE(EQ_LUT_FILE)
    ) u_eq (
        .clk(clk), .rst_n(rst_n),
        .s_axis_rx_tvalid(eq_feed_valid),
        .s_axis_rx_tready(eq_rx_ready),
        .s_axis_rx_tdata (rxbuf_rdata),
        .s_axis_rx_tuser ({{(TUSERW-PW){1'b0}}, rd_bin}),
        .s_axis_h_tvalid (eq_feed_valid),
        .s_axis_h_tready (eq_h_ready),
        .s_axis_h_tdata  (h_tdata),
        .m_axis_tvalid(eq_m_valid),
        .m_axis_tready(eq_m_ready),
        .m_axis_tdata (eq_m_tdata),
        .m_axis_tuser (eq_m_tuser)
    );

    // =================================================================
    // 6.  DATA-CARRIER GATE : keep only the 221 dataIndx bins.
    //     dataIndx = bins 1..254 minus the 32 pilots (1+8k) minus DC(128).
    //     Forward only data carriers to the demod; assert s_last on the
    //     LAST data carrier of a symbol (bin 254) and s_user on the FIRST
    //     (bin 2).
    // =================================================================
    wire [PW-1:0] eq_bin = eq_m_tuser[PW-1:0];

    // is_pilot_bin: b in [1,249] and (b-1) divisible by 8
    function automatic is_pilot_bin(input [PW-1:0] b);
        is_pilot_bin = (b >= 1) && (b <= 249) && (((b-1) & 8'h07) == 0);
    endfunction
    // data carrier: 1..254, not DC(128), not a pilot, not 0/255
    function automatic is_data_bin(input [PW-1:0] b);
        is_data_bin = (b >= 1) && (b <= 254) && (b != 128) && !is_pilot_bin(b);
    endfunction

    wire eq_is_data  = is_data_bin(eq_bin);
    wire eq_is_first = (eq_bin == 8'd2);     // first dataIndx entry
    wire eq_is_last  = (eq_bin == 8'd254);   // last  dataIndx entry

    // demod slave handshake
    wire        dm_s_valid = eq_m_valid & eq_is_data;
    wire        dm_s_ready;
    // EQ output is accepted when: it is a non-data bin (discarded, always
    // accepted) OR it is a data bin and the demod can take it.
    assign eq_m_ready = eq_m_valid & (~eq_is_data | dm_s_ready);

    wire signed [DW-1:0] dm_s_i = $signed(eq_m_tdata[DW-1:0]);
    wire signed [DW-1:0] dm_s_q = $signed(eq_m_tdata[2*DW-1:DW]);

    // =================================================================
    // 7.  QAM DEMOD (runtime mod_sel) -> up to BPC_MAX bits / data carrier
    // =================================================================
    rx_demod_qam #(.DATA_W(DW), .BPC_MAX(BPC_MAX)) u_demod (
        .clk(clk), .rst_n(rst_n),
        .mod_sel(mod_sel),
        .s_valid(dm_s_valid),
        .s_ready(dm_s_ready),
        .s_i(dm_s_i), .s_q(dm_s_q),
        .s_last(eq_is_last),
        .s_user(eq_is_first),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_bits(m_bits), .m_last(m_last), .m_user(m_user)
    );

endmodule

`default_nettype wire
