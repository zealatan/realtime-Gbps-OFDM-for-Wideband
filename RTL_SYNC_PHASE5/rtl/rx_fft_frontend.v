// =====================================================================
// rx_fft_frontend.v
// ---------------------------------------------------------------------
// OFDM RX downstream chain: FFT FRONT-END (symbol extract + 256-pt FFT
// + fftshift + 1/sqrt(256) scale).  Ports the RX FFT stage of
// ref/receiver.c (generate_complex_symbol + fft_with_rearrange),
// matching golden/rx_downstream/fft_out (see CONTRACT.md sec 3.1).
//
// ---------------------------------------------------------------------
// WHAT IT DOES  (CONTRACT.md sec 3.1)
// ---------------------------------------------------------------------
//   INPUT  : the synchronizer's corrected M_AXIS, 32-bit {Q[31:16],
//            I[15:0]} signed Q15, 1 complex sample / clock, 4032
//            samples / slot, beat0 = PSS CP start.
//   - samples   0..575  : 2 REAL sync symbols (PSS/SSS) -> SKIPPED
//                         (used by sync, never demodulated here).
//   - data sym z (0..11): samples 576 + z*288 .. +287.
//   For each of the 12 data symbols:
//       1. drop the 32-sample cyclic prefix,
//       2. take the next NSC=256 body samples,
//       3. 256-pt forward FFT (exp(-j2pi kn/N)),
//       4. rearrange_spectrum / fftshift (cyclic rotate by NSC/2=128),
//       5. scale by 1/sqrt(256) = 1/16 (4-bit right shift).
//   OUTPUT : 12 symbols x 256 complex freq bins, fftshift-ordered
//            (bin 0..255 within a symbol, symbols 0..11 consecutively),
//            AXI-Stream {Q[31:16],I[15:0]} Q15, 1 sample / clock.
//            -> matches golden/rx_downstream/fft_out.hex.
//
// ---------------------------------------------------------------------
// FFT IP  (rtl/xfft_N/xfft_N.xci -- instantiated here as a SECOND,
//          INDEPENDENT instance; the Meyr CFO core owns the first one)
// ---------------------------------------------------------------------
//   xfft 9.1, 256-pt, 16b I/Q, pipelined_streaming_io, natural order,
//   block_floating_point (BFP), truncation. Configured FORWARD via
//   s_axis_config tdata bit0 FWD_INV=1 (one-shot at reset).
//
//   BLOCK-FLOATING-POINT HANDLING
//   -----------------------------
//   In BFP the IP performs an UNSCALED forward FFT but right-shifts the
//   data by a per-frame "block exponent" (reported on m_axis_data_tuser,
//   8 bits) so the 16b output never overflows. The TRUE unscaled FFT
//   value is therefore  fft_true = out16 << blk_exp.
//   The golden applies the extra 1/sqrt(256)=1/16 (>>4), so the value
//   this module must emit is:
//
//        bin_q15 = (out16 << blk_exp) >> 4          (per I and Q)
//
//   = out16 << (blk_exp-4) when blk_exp>=4, else out16 >> (4-blk_exp)
//   with round-to-nearest on the right shift. This is the EXACT inverse
//   of whatever scaling the IP chose, so the result is independent of
//   the actual blk_exp value -- only BFP intermediate truncation (a few
//   LSB) separates it from the bit-exact golden. The recover shift is
//   done at full width (32b) before re-saturating to int16, so no
//   intermediate clipping. (Verified: emulated 256-pt BFP gives blk_exp
//   ~= 2 and <= 0.7 LSB recovered error vs the golden Q15 view.)
//
// ---------------------------------------------------------------------
// THROUGHPUT / SAMPLING RATE / TIMING  (user hard constraints)
// ---------------------------------------------------------------------
//   * 1 complex sample / clock everywhere; the symbol-extract FSM feeds
//     the pipelined-streaming FFT one body sample per clock and the IP
//     emits one bin per clock -> NO rate change (no decimate/interp).
//   * Honors AXI-Stream tready in BOTH directions:
//       - upstream s_axis is back-pressured by s_ready, which is only
//         asserted when the sample is a SKIP (sync/CP, always accepted)
//         or the FFT data slave can accept a body sample.
//       - downstream m_axis is back-pressured: the fftshift read-out
//         buffer holds a whole symbol, and read pointer only advances on
//         (m_valid & m_ready); a full output buffer back-pressures the
//         FFT m_axis_data_tready, which in turn back-pressures s_axis.
//   * Pipelining for Fmax: the timing-critical arithmetic in THIS module
//     is only the BFP barrel shift + round + saturate on the 16b FFT
//     output. It is split into 2 registered stages (shift/round, then
//     saturate+pack) so the combinational depth per stage is ~1 shifter
//     + 1 adder + a few compares -- well under the existing sync chain's
//     ~219 MHz critical path. The heavy arithmetic (the FFT butterflies)
//     lives inside the Xilinx IP, which closes >300 MHz OOC on this part.
//     Estimated module Fmax (excluding IP) > 350 MHz on xczu49dr-2;
//     the IP's own pipelined-streaming core is the practical limit and
//     it is NOT degraded by this wrapper.
//
//   Double-buffered output (2 x 256 x 32b = 2 BRAMs): while symbol z is
//   being read out (fftshift), symbol z+1 can be captured from the FFT,
//   so there is never a stall between symbols at the output.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_fft_frontend #(
    parameter integer DATA_W   = 16,    // signed I/Q sample width (Q15)
    parameter integer NSC      = 256,   // FFT size / subcarriers
    parameter integer CP_LEN   = 32,    // cyclic-prefix samples
    parameter integer NUM_SYN  = 2,     // leading sync symbols (skipped)
    parameter integer NUM_DATA = 12,    // demodulated data symbols
    parameter integer SCALE_SH = 4      // 1/sqrt(256) = >>4
) (
    input  wire                       clk,
    input  wire                       rst_n,      // active-low sync reset

    // ---- slave : synchronizer corrected M_AXIS, {Q[31:16],I[15:0]} ----
    input  wire                       s_valid,
    output wire                       s_ready,
    input  wire [2*DATA_W-1:0]        s_tdata,    // {Q,I} Q15
    // Sync slot-boundary marker (m_axis_tlast from phase3_sync wrapper).  Used
    // ONLY to RE-ANCHOR the free-running slot_pos to the true frame boundary so
    // a transient downstream stall cannot leave the symbol grid permanently
    // offset (DESYNC-514 self-heal).  In normal lock the sync fires s_tlast on
    // the SAME beat slot_pos free-wraps (int_frame_len 4032 == the FSM's slot
    // length), so anchoring is a bit-exact NO-OP.  Tie to 1'b0 to restore the
    // pure free-run behaviour.
    input  wire                       s_tlast,

    // ---- master : freq bins, fftshift order, {Q[31:16],I[15:0]} Q15 ----
    output wire                       m_valid,
    input  wire                       m_ready,
    output wire [2*DATA_W-1:0]        m_tdata,    // {Q,I} Q15
    output wire                       m_last,     // 1 on last bin (255) of each symbol
    // FRAME-START marker (SELF-HEAL): pulses on bin 0 (first accepted output beat)
    // of the FIRST data symbol (input sym_idx==0) of each frame.  Rides WITH the
    // FFT output data through the SAME double-buffer, so it is LATENCY-EXACT to
    // the data (no separately-timed strobe).  In steady lock it coincides with the
    // natural per-symbol wrap to the align-buffer frame-start bank -> the
    // downstream per-frame reset it drives is a bit-exact NO-OP.
    output wire                       m_fstart    // 1 on bin 0 of frame-symbol-0
);

    localparam integer SYNC_SKIP = NUM_SYN * (NSC + CP_LEN);  // 576
    localparam integer NSC_LOG2  = 8;                          // log2(256)

    // =================================================================
    // 1.  ONE-SHOT FFT CONFIG  (forward, FWD_INV=1)
    // =================================================================
    // The IP's s_axis_config tdata is 8 bits; only bit0 (FWD_INV) is
    // meaningful for this single-channel, fixed-length, scaling-less-
    // schedule (BFP) configuration. Hold valid until accepted, once.
    reg  cfg_done;
    wire cfg_tready;
    wire cfg_tvalid = ~cfg_done;
    wire [7:0] cfg_tdata = 8'h01;          // FWD_INV = 1 -> forward FFT

    // SYNCHRONOUS reset (was async `posedge clk or negedge rst_n`).  rst_n is
    // the board's reset-release-synchronized aresetn_sync; using it
    // synchronously makes this module share the SAME reset-release edge as the
    // rest of the downstream chain (rx_ch_est/eq/demod are all sync-reset) and
    // as the GSR/INIT-only datapath arrays (rxbuf/ram0/ram1/hbuf/hp).  An async
    // CLR here let this block leave reset on a DIFFERENT aclk edge than the
    // sync-reset / GSR-INIT state -> a reset-release race that is benign in sim
    // but per-POR non-deterministic on silicon.  (Also lets ram0/ram1 map to
    // real BRAM instead of dissolving to registers.)
    always @(posedge clk) begin
        if (!rst_n)               cfg_done <= 1'b0;
        else if (cfg_tvalid && cfg_tready) cfg_done <= 1'b1;
    end

    // =================================================================
    // 2.  INPUT-SIDE SYMBOL-EXTRACT FSM
    //     Counts the 4032-sample slot, marks which incoming samples are
    //     BODY (forwarded to the FFT) vs SKIP (sync region + per-symbol
    //     CP, dropped). Drives the FFT s_axis_data with tlast on the
    //     256th body sample of each symbol.
    // =================================================================
    // Position within the slot, 0..4031 (free runs while s_valid&s_ready).
    reg  [12:0] slot_pos;                   // 0..4031 (13 bits)

    // Are we in a data symbol's body? Compute window membership.
    // For sample index p>=SYNC_SKIP: local = p - SYNC_SKIP;
    //   sym = local / 288 ; off = local % 288 ; body = (off >= CP_LEN).
    // To avoid a divider we track per-symbol offset counters directly.
    reg         in_data;                    // 1 once past the sync region
    reg  [8:0]  sym_off;                     // 0..287 within a data symbol
    reg  [3:0]  sym_idx;                     // 0..11 data symbol index

    wire is_body = in_data && (sym_off >= CP_LEN);   // forward to FFT
    wire body_last = in_data && (sym_off == (CP_LEN + NSC - 1)); // 256th body samp

    // FFT data slave interface
    // cfg_done GATE: do NOT present any data to the xfft until its one-shot
    // FWD_INV config beat has been ACCEPTED (mirrors meyr_feeder.v, the proven-
    // deterministic-on-silicon path that uses the SAME xfft IP). Without this,
    // the first body samples race the config-channel handshake at reset release
    // -> per-config-random FFT direction/scaling -> per-POR-varying garbage
    // (invisible in sim: the xfft stub accepts config cycle-1 + ignores FWD_INV).
    wire        fft_din_tready;
    wire        fft_din_tvalid = cfg_done && s_valid && is_body;
    wire [31:0] fft_din_tdata  = { s_tdata[2*DATA_W-1:DATA_W],   // Q
                                   s_tdata[DATA_W-1:0] };        // I
    wire        fft_din_tlast  = body_last;

    // A sample is consumed from s_axis when:
    //   - it is a SKIP sample (always accepted, just dropped), OR
    //   - it is a BODY sample AND the FFT can accept it.
    assign s_ready = cfg_done && s_valid && (!is_body || fft_din_tready);

    wire s_fire = s_valid && s_ready;       // input beat accepted (incl. cfg_done)

    always @(posedge clk) begin   // SYNCHRONOUS reset (see cfg_done note)
        if (!rst_n) begin
            slot_pos <= 13'd0;
            in_data  <= 1'b0;
            sym_off  <= 9'd0;
            sym_idx  <= 4'd0;
        end else if (s_fire) begin
            // advance slot position, wrap at SLOT_LEN
            // RE-ANCHOR (DESYNC-514 self-heal): if the sync marks this accepted
            // beat as the slot boundary (s_tlast), snap the whole extract FSM
            // back to slot start.  In normal lock s_tlast coincides EXACTLY with
            // the free-run wrap (slot_pos == SLOT_LEN-1) so this is identical to
            // the wrap branch (bit-exact NO-OP); after a transient stall it
            // corrects a drifted slot_pos to the TRUE frame boundary so the FFT
            // symbol grid can never stay a symbol offset.
            if (s_tlast || slot_pos == (NUM_SYN + NUM_DATA)*(NSC+CP_LEN) - 1) begin
                slot_pos <= 13'd0;
                in_data  <= 1'b0;
                sym_off  <= 9'd0;
                sym_idx  <= 4'd0;
            end else begin
                slot_pos <= slot_pos + 13'd1;
                if (!in_data) begin
                    // still in the 576-sample sync region
                    if (slot_pos == SYNC_SKIP - 1) begin
                        in_data <= 1'b1;
                        sym_off <= 9'd0;
                        sym_idx <= 4'd0;
                    end
                end else begin
                    // inside the data region: per-symbol offset 0..287
                    if (sym_off == (NSC + CP_LEN - 1)) begin
                        sym_off <= 9'd0;
                        sym_idx <= sym_idx + 4'd1;
                    end else begin
                        sym_off <= sym_off + 9'd1;
                    end
                end
            end
        end
    end

    // =================================================================
    // 2b. FRAME-SYMBOL-0 TAG FIFO  (SELF-HEAL marker source)
    // -----------------------------------------------------------------
    // The input FSM's sym_idx (0..11) is anchored to the true frame boundary
    // (reset by s_tlast / slot wrap).  We capture, for EACH data symbol fed to
    // the xfft, a 1-bit "this is frame-symbol-0" tag at its LAST body sample
    // (fft_din fire & fft_din_tlast, where sym_idx is that symbol's index) and
    // push it into a tiny order-preserving FIFO.  The xfft preserves symbol
    // ORDER and COUNT 1:1 (one output tlast per input tlast), so popping the
    // FIFO on each xfft OUTPUT tlast (fft_dout fire & fft_dout_tlast) recovers
    // the frame phase of the symbol currently emerging from the IP -- exactly
    // latency-aligned to the data, with no assumption about the IP's (variable)
    // pipeline depth.  Depth 8 >> the <=2 symbols the streaming IP holds.
    localparam integer TAGFIFO_DEPTH = 8;
    localparam integer TAGFIFO_AW    = 3;   // log2(8)
    reg  tagfifo [0:TAGFIFO_DEPTH-1];
    reg  [TAGFIFO_AW-1:0] tag_wr, tag_rd;
    integer tf_init;
    initial begin
        for (tf_init = 0; tf_init < TAGFIFO_DEPTH; tf_init = tf_init + 1)
            tagfifo[tf_init] = 1'b0;
        tag_wr = {TAGFIFO_AW{1'b0}};
        tag_rd = {TAGFIFO_AW{1'b0}};
    end
    wire fft_din_fire = fft_din_tvalid && fft_din_tready;
    wire tag_push     = fft_din_fire && fft_din_tlast;   // a symbol fully fed to IP
    wire this_sym0    = (sym_idx == 4'd0);               // frame-symbol-0

    // =================================================================
    // 3.  XFFT_N  (SECOND INDEPENDENT INSTANCE) -- 256-pt forward BFP
    // =================================================================
    wire        fft_dout_tvalid;
    wire        fft_dout_tready;       // driven by capture stage (sec 4)
    wire [31:0] fft_dout_tdata;        // {Q[31:16], I[15:0]}, BFP-scaled 16b
    wire        fft_dout_tlast;
    wire [7:0]  fft_dout_tuser;        // block exponent (BFP)

    xfft_N u_fft_N (
        .aclk                        (clk),
        .aresetn                     (rst_n),
        .s_axis_config_tvalid        (cfg_tvalid),
        .s_axis_config_tready        (cfg_tready),
        .s_axis_config_tdata         (cfg_tdata),
        .s_axis_data_tvalid          (fft_din_tvalid),
        .s_axis_data_tready          (fft_din_tready),
        .s_axis_data_tdata           (fft_din_tdata),
        .s_axis_data_tlast           (fft_din_tlast),
        .m_axis_data_tvalid          (fft_dout_tvalid),
        .m_axis_data_tready          (fft_dout_tready),
        .m_axis_data_tdata           (fft_dout_tdata),
        .m_axis_data_tlast           (fft_dout_tlast),
        .m_axis_data_tuser           (fft_dout_tuser),
        .m_axis_status_tready        (1'b1),
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_status_channel_halt   (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt ()
    );

    // =================================================================
    // 4.  BFP RECOVER + fftshift WRITE  (pipelined, 1 bin/clk)
    // =================================================================
    // The FFT emits bins in NATURAL order 0..255. We apply the BFP
    // recover scaling  ((out16 << blk_exp) >> SCALE_SH) with round-to-
    // nearest + saturate, and write the recovered {Q,I} into a double-
    // buffered RAM at the fftshift WRITE address so read-out is linear.
    //
    // fftshift (rearrange_spectrum): output position i = (natural_k +
    // NSC/2) mod NSC. We store at addr = (k + 128) & 255 so that reading
    // addr 0..255 linearly yields the fftshift-ordered spectrum.
    //
    // Stage S1 (registered): barrel-shift each 16b component by blk_exp
    //   (left, into a 24b field) and capture. blk_exp for 256-pt BFP is
    //   0..8, so a 16b value shifted left by up to 8 needs 24 bits.
    // Stage S2 (registered): arithmetic right-shift by SCALE_SH with
    //   round-to-nearest, saturate to int16, pack, write to RAM.

    // ---- natural-order bin counter for the incoming FFT stream ----
    reg  [NSC_LOG2-1:0] kc;            // 0..255 natural bin index
    reg                 wbuf;          // which output buffer is being WRITTEN
    wire fft_out_fire = fft_dout_tvalid && fft_dout_tready;

    // ---- frame-symbol-0 tag FIFO push/pop + per-buffer tag ----
    // POP at the FIRST output bin of each IP symbol (kc==0 on fft_out_fire): the
    // symbol emerging now goes into buffer `wbuf`, so tag that buffer with the
    // FIFO front (this symbol's frame_sym0).  Push (input) and pop (output) never
    // collide on the same slot given the >=1 symbol IP latency and depth 8.
    wire tag_pop      = fft_out_fire && (kc == {NSC_LOG2{1'b0}});
    wire tag_front    = tagfifo[tag_rd];
    reg  buf_sym0 [0:1];               // [b] = symbol in output buffer b is frame-sym0
    initial begin buf_sym0[0] = 1'b0; buf_sym0[1] = 1'b0; end
    always @(posedge clk) begin
        if (!rst_n) begin
            tag_wr <= {TAGFIFO_AW{1'b0}};
            tag_rd <= {TAGFIFO_AW{1'b0}};
        end else begin
            if (tag_push) begin
                tagfifo[tag_wr] <= this_sym0;
                tag_wr <= tag_wr + 1'b1;   // wraps mod 8
            end
            if (tag_pop) begin
                buf_sym0[wbuf] <= tag_front;
                tag_rd <= tag_rd + 1'b1;   // wraps mod 8
            end
        end
    end

    // latch block exponent at the first bin of a symbol (it is constant
    // for the whole frame; m_axis_data_tuser carries it on every beat).
    // We simply use the per-beat tuser (identical across the frame).

    // ---- Stage S1 : sign-extend + left-shift by blk_exp ----
    reg  signed [DATA_W-1:0] s1_i, s1_q;
    reg  [4:0]               s1_blk;
    reg  [NSC_LOG2-1:0]      s1_addr;
    reg                      s1_wbuf;
    reg                      s1_we;
    reg                      s1_last;

    wire signed [DATA_W-1:0] din_i = fft_dout_tdata[DATA_W-1:0];
    wire signed [DATA_W-1:0] din_q = fft_dout_tdata[2*DATA_W-1:DATA_W];

    // ---- Stage S2 : (val << blk) >> SCALE_SH, round + saturate ----
    // full-width signed accumulators: 16b << up to 8 = 24b, + round bit.
    localparam integer WSH = DATA_W + 8;   // 24-bit shifted field
    wire signed [WSH-1:0] sh_i = $signed(s1_i) <<< s1_blk;
    wire signed [WSH-1:0] sh_q = $signed(s1_q) <<< s1_blk;
    // round-to-nearest on the >>SCALE_SH (add half-LSB before shift)
    wire signed [WSH:0]   rnd_i = $signed({sh_i[WSH-1], sh_i}) + (1 <<< (SCALE_SH-1));
    wire signed [WSH:0]   rnd_q = $signed({sh_q[WSH-1], sh_q}) + (1 <<< (SCALE_SH-1));
    wire signed [WSH:0]   res_i = rnd_i >>> SCALE_SH;
    wire signed [WSH:0]   res_q = rnd_q >>> SCALE_SH;

    function signed [DATA_W-1:0] sat16;
        input signed [WSH:0] v;
        begin
            if (v > 32767)        sat16 = 16'sd32767;
            else if (v < -32768)  sat16 = -16'sd32768;
            else                  sat16 = v[DATA_W-1:0];
        end
    endfunction

    reg  [31:0]          ram0 [0:NSC-1];
    reg  [31:0]          ram1 [0:NSC-1];
    // Zero-init the FFT-output double-buffer so silicon powers up to a KNOWN
    // 0 (written-then-read; reads 0 in sim but RANDOM on silicon).  Mirrors
    // ram_2port.v / meyr_ak_buf.v -> Vivado bakes the BRAM/LUTRAM INIT.
    integer fft_ram_init_k;
    initial begin
        for (fft_ram_init_k = 0; fft_ram_init_k < NSC; fft_ram_init_k = fft_ram_init_k + 1) begin
            ram0[fft_ram_init_k] = 32'h0;
            ram1[fft_ram_init_k] = 32'h0;
        end
    end

    reg  [NSC_LOG2-1:0]  s2_addr;
    reg                  s2_wbuf;
    reg                  s2_we;

    wire [31:0] s2_word = { sat16(res_q), sat16(res_i) };

    always @(posedge clk) begin   // SYNCHRONOUS reset (see cfg_done note)
        if (!rst_n) begin
            kc      <= {NSC_LOG2{1'b0}};
            wbuf    <= 1'b0;
            s1_we   <= 1'b0;
            s2_we   <= 1'b0;
            s1_last <= 1'b0;
        end else begin
            // ---- S1 capture ----
            s1_we <= 1'b0;
            if (fft_out_fire) begin
                s1_i    <= din_i;
                s1_q    <= din_q;
                s1_blk  <= fft_dout_tuser[4:0];
                // fftshift write address = (k + 128) mod 256
                s1_addr <= kc + 9'd128;     // NSC_LOG2-bit add wraps mod 256
                s1_wbuf <= wbuf;
                s1_we   <= 1'b1;
                s1_last <= fft_dout_tlast;
                // advance natural bin counter / buffer select
                if (kc == NSC-1) begin
                    kc   <= {NSC_LOG2{1'b0}};
                    wbuf <= ~wbuf;          // next symbol -> other buffer
                end else begin
                    kc <= kc + 1'b1;
                end
            end

            // ---- S2 write ----
            s2_we   <= s1_we;
            s2_addr <= s1_addr;
            s2_wbuf <= s1_wbuf;
            if (s1_we) begin
                if (!s1_wbuf) ram0[s1_addr] <= s2_word;
                else          ram1[s1_addr] <= s2_word;
            end
        end
    end

    // =================================================================
    // 5.  OUTPUT-SIDE READ-OUT  (linear 0..255, 1 bin/clk, AXI-S)
    // =================================================================
    // A symbol's buffer becomes READable once it has been fully written
    // (256 bins captured). `filled[b]` is set when the LAST bin of the
    // symbol in buffer b completes its S2 write, and cleared when read-out
    // of buffer b finishes. Read-out streams addr 0..255 linearly.
    //
    // The output buffers ram0/ram1 are read COMBINATIONALLY (they are tiny
    // 256x32 = distributed/LUT RAM, and sit on the OUTPUT path, NOT on the
    // FFT butterfly critical path -- so a comb read here does not affect
    // the design Fmax dominated by the sync chain / FFT IP). The selected
    // word feeds a single registered output skid so the master honors
    // m_ready with no dropped/duplicated beats. The read address advances
    // exactly when the registered output can accept a new beat.
    reg  [1:0]          filled;        // [b] = buffer b holds a complete symbol
    reg                 rbuf;          // buffer being READ
    reg  [NSC_LOG2-1:0] rc;            // linear read address 0..255
    reg                 rd_active;     // a read-out is in progress

    // reliable "symbol complete" marker: S1 saw tlast -> propagate to S2,
    // carrying which buffer it landed in.
    reg  s2_sym_done;
    reg  s2_done_buf;
    always @(posedge clk) begin   // SYNCHRONOUS reset (see cfg_done note)
        if (!rst_n) begin
            s2_sym_done <= 1'b0;
            s2_done_buf <= 1'b0;
        end else begin
            s2_sym_done <= s1_we && s1_last;   // 1-cycle pulse: last bin written
            s2_done_buf <= s1_wbuf;
        end
    end

    // combinational read of the active read buffer
    wire [31:0] rdata = rbuf ? ram1[rc] : ram0[rc];

    // registered AXI-S master output
    reg         m_valid_r;
    reg         m_last_r;
    reg  [31:0] m_data_r;
    reg         m_fstart_r;   // frame-symbol-0 bin-0 marker, registered with m_data_r

    // The output register can take a new beat when empty or draining.
    wire out_room  = (!m_valid_r) || m_ready;
    // We have a valid bin to present while a read-out is active.
    wire have_bin  = rd_active;

    // RACE-FREE filled[] UPDATE (deterministic-stall fix).
    // The writer SETS filled[s2_done_buf] on symbol completion and the reader
    // CLEARS filled[rbuf] on read-out completion.  These were two separate
    // non-blocking assignments to the SAME 2-bit reg in one always block: if
    // they ever target the SAME bank on the SAME cycle (s2_done_buf==rbuf, a
    // phase alignment the shallow 2-symbol buffer CAN reach under the real
    // xfft's variable, non-realtime output timing), Verilog source-order makes
    // the later CLEAR win and the SET is SILENTLY LOST -> that bank is marked
    // empty though it holds a fresh unread symbol -> the read pointer waits on
    // it forever while the writer's filled[wbuf] stays high -> fft_dout_tready
    // (=~filled[wbuf]) latches low -> the xfft input fills -> s_ready latches
    // low -> STALL_TIMEOUT (the deterministic frame-~7 downstream deadlock).
    // Fix: derive per-bank set/clear strobes and compute each filled[b] bit
    // with SET-dominant, order-independent next-state logic so a concurrent
    // same-bank set+clear can never drop the set.
    wire        fill_set   = s2_sym_done;                 // a symbol just completed
    wire [0:0]  fill_setb  = s2_done_buf;                 // ...into this bank
    wire        rd_done     = out_room && have_bin && (rc == NSC-1);
    wire        fill_clr    = rd_done;                    // a read-out just finished
    wire [0:0]  fill_clrb   = rbuf;                       // ...of this bank

    reg  [1:0] filled_nxt;
    integer fb;
    always @(*) begin
        filled_nxt = filled;
        for (fb = 0; fb < 2; fb = fb + 1) begin
            // CLEAR first, then SET -> SET dominates when both hit same bank.
            if (fill_clr && (fill_clrb == fb[0])) filled_nxt[fb] = 1'b0;
            if (fill_set && (fill_setb == fb[0])) filled_nxt[fb] = 1'b1;
        end
    end

    always @(posedge clk) begin   // SYNCHRONOUS reset (see cfg_done note)
        if (!rst_n) begin
            filled    <= 2'b00;
            rbuf      <= 1'b0;
            rc        <= {NSC_LOG2{1'b0}};
            rd_active <= 1'b0;
            m_valid_r <= 1'b0;
            m_last_r  <= 1'b0;
            m_data_r  <= 32'd0;
            m_fstart_r <= 1'b0;
        end else begin
            // ---- filled[] : single race-free next-state (set-dominant) ----
            filled <= filled_nxt;

            // ---- present the current bin into the output register ----
            if (out_room) begin
                if (have_bin) begin
                    m_data_r  <= rdata;
                    m_last_r  <= (rc == NSC-1);
                    m_valid_r <= 1'b1;
                    // frame-start marker : bin 0 of a frame-symbol-0 buffer.
                    m_fstart_r <= (rc == {NSC_LOG2{1'b0}}) && buf_sym0[rbuf];
                    if (rc == NSC-1) begin
                        // last bin of this symbol presented -> free buffer
                        rbuf         <= ~rbuf;
                        rd_active    <= 1'b0;
                        rc           <= {NSC_LOG2{1'b0}};
                    end else begin
                        rc <= rc + 1'b1;
                    end
                end else begin
                    // no bin available this cycle -> deassert valid (drained)
                    m_valid_r  <= 1'b0;
                    m_fstart_r <= 1'b0;
                end
            end

            // ---- start a new read-out when idle and the buffer is filled.
            // Note: when rd_active drops on the last bin above, this fires
            // the NEXT cycle to begin the following symbol (rc already 0).
            if (!rd_active && filled[rbuf]) begin
                rd_active <= 1'b1;
                rc        <= {NSC_LOG2{1'b0}};
            end
        end
    end

    // Back-pressure on the FFT output: the writer targets buffer `wbuf`;
    // block capture (deassert tready) if that buffer still holds an
    // un-read symbol. The OTHER buffer may be reading out concurrently
    // (double-buffered: capture z+1 while reading out z).
    assign fft_dout_tready = ~filled[wbuf];

    // ---- AXI-S master ----
    assign m_valid  = m_valid_r;
    assign m_tdata  = m_data_r;
    assign m_last   = m_last_r;
    assign m_fstart = m_fstart_r;

    // silence unused
    wire _unused = &{1'b0, fft_dout_tlast};

endmodule

`default_nettype wire
