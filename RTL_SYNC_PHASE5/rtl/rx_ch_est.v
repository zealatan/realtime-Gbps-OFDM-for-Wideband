// ============================================================================
// rx_ch_est.v  --  OFDM RX channel estimation + FFT interpolation (CE + interp_fft)
//
// Ports receiver.c ch_estimation_fdm() + interp_fft() to RTL.
//
//   (1) ch_estimation_fdm : at each of the 32 pilot bins pltIndx={1,9,...,249}
//         H_pilot[k] = rx[pltIndx[k]] * conj(plt[k]) / |plt[k]|^2
//       The transmitted QPSK pilot plt[k] is KNOWN, so the per-pilot reciprocal
//         W[k] = conj(plt[k]) / |plt[k]|^2  (at Q15 scale)
//       is a PRECOMPUTED complex CONSTANT. The CE is therefore a single complex
//         H_pilot[k] = rx[pltIndx[k]] * W[k]
//       MULTIPLY -- no run-time divide. This is mathematically identical to the
//       old 64-bit single-cycle complex divide (655 logic levels, ~77 ns, could
//       not close timing), so golden hest.hex is UNCHANGED (0 LSB on golden, the
//       same 0-3 LSB budget on the 24 robust channels). W is loaded from
//       W_RECIP_ROM (golden/rx_downstream/ce_pilot_recip.hex, 384 = 12*32 words,
//       {Wi[17:0],Wr[17:0]}, 16 frac bits) via $readmemh, addressed by the same
//       pilot pull counter that advances pilot_tready (slot-major k=0..31 inner).
//
//   (2) interp_fft : 32-pt IFFT of the 32 pilot-H into the low 32 time taps,
//       zero taps[32:256], 256-pt forward FFT -> H_fft[0..255].
//       Because taps[32:256]==0, the WHOLE interp_fft is LINEAR in the 32 pilot
//       inputs and collapses to a single fixed 256x32 complex matrix W:
//             H_fft[k] = sum_{m=0..31} W[k][m] * H_pilot[m]
//             W = DFT256[:,0:32] @ (IDFT32 / 32)
//       W is stored in rtl/rx_ch_est_rom/ce_interp_W.hex (18-bit signed, 16
//       fractional bits). This avoids any FFT IP, is fully pipelined, and is the
//       cheapest path to timing closure (no feedback, pure MAC adder-tree).
//
//   (3) +1 offset (receiver.c l.152-153): Hest[1..254] = H_fft[0..253];
//       Hest[0] = Hest[255] = 0. Implemented by only computing H_fft[0..253]
//       and writing them to output bins 1..254, with bins 0/255 forced 0.
//
// I/O: AXI-Stream, ONE complex sample / clock, {Q[31:16], I[15:0]} Q15
//      (scale 5090.70 -> H=1.0 reads ~0x13E3). tready honored.
//
// Throughput: 1 sample/clk sustained. Input symbol N+1 captured into the
// alternate pilot bank while output symbol N streams (ping-pong) -> no bubble.
//
// Pipelining (timing closure): CE divide spread over the 256-cycle symbol
// (only 32 pilots). The interp MAC is a fully-registered 32-wide complex
// multiply + 5-level balanced adder tree (9-stage fixed latency, 1 bin/clk),
// so each pipeline stage is a single multiply or a single add -> short logic
// depth, no feedback paths.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_ch_est #(
    parameter integer NSC        = 256,
    parameter integer NUM_PILOTS = 32,
    parameter integer DW         = 16,
    parameter integer CW         = 18,    // interp coeff width (signed)
    parameter integer CF         = 16,    // interp coeff fractional bits
    parameter integer HW         = 18,    // internal H_pilot width
    parameter         W_ROM      = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    // CE pilot-reciprocal ROM : W[k] = conj(plt[k])/|plt[k]|^2 at Q15 scale,
    // 384 = NUM_DATA*NUM_PILOTS words, {Wi[RCW-1:0],Wr[RCW-1:0]}, RCF frac bits.
    parameter         W_RECIP_ROM = "golden/rx_downstream/ce_pilot_recip.hex",
    parameter integer NUM_DATA   = 12,    // symbols per slot (ROM depth = 12*32)
    parameter integer RCW        = 18,    // CE recip coeff width (signed)
    parameter integer RCF        = 16,    // CE recip coeff fractional bits
    parameter integer SCQ        = 20851496, // SC=5090.697374 in Q12 (legacy, unused)
    parameter integer SCQ_SHIFT  = 12
)(
    input  wire                  clk,
    input  wire                  rst_n,

    // S_AXIS : freq-domain symbols, bin 0..255/symbol, {Q,I} Q15
    input  wire [31:0]           s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,   // on bin 255

    // pilot ROM stream : one word pulled per captured pilot bin
    input  wire [31:0]           pilot_tdata,
    output wire                  pilot_tready,

    // M_AXIS : H[k], bin 0..255/symbol, {Q,I} Q15
    output wire [31:0]           m_axis_tdata,
    output wire                  m_axis_tvalid,
    input  wire                  m_axis_tready,
    output wire                  m_axis_tlast    // on bin 255
);
    localparam integer PW    = $clog2(NSC);
    localparam integer PLW   = $clog2(NUM_PILOTS);
    localparam integer CWORD = 2*CW;

    function automatic is_pilot_bin(input [PW-1:0] b);
        is_pilot_bin = (b >= 1) && (b <= 249) && (((b-1) & 3'b111) == 0);
    endfunction

    // ---- forward declarations (referenced across blocks; xsim needs them up top)
    reg        eng_busy [0:1];     // interp engine reading ping-pong bank b
    reg  [1:0] hbuf_full;          // output H buffer bank full (packed: race-free next-state)
    reg        o_active;           // M_AXIS sequencer streaming
    reg        o_buf;
    reg [PW-1:0] o_bin;
    wire       o_fire;
    wire       out_ready_pipe = ~(hbuf_full[0] & hbuf_full[1]);

    // ========================================================================
    // INPUT / CE : capture 32 pilots -> H_pilot[m] in ping-pong banks
    // ========================================================================
    reg  [PW-1:0] in_bin;
    reg           in_buf;
    reg signed [HW-1:0] hp_i [0:1][0:NUM_PILOTS-1];
    reg signed [HW-1:0] hp_q [0:1][0:NUM_PILOTS-1];
    // Zero-init the pilot H banks so silicon powers up KNOWN (written-then-
    // read ping-pong; reads 0 in sim but RANDOM on silicon).  Mirrors
    // ram_2port.v -> Vivado bakes the LUTRAM/BRAM INIT.
    integer hp_init_b, hp_init_m;
    initial begin
        for (hp_init_b = 0; hp_init_b < 2; hp_init_b = hp_init_b + 1)
            for (hp_init_m = 0; hp_init_m < NUM_PILOTS; hp_init_m = hp_init_m + 1) begin
                hp_i[hp_init_b][hp_init_m] = {HW{1'b0}};
                hp_q[hp_init_b][hp_init_m] = {HW{1'b0}};
            end
    end

    reg           sym_ready;
    reg           sym_ready_buf;

    wire signed [DW-1:0] rxI = s_axis_tdata[DW-1:0];
    wire signed [DW-1:0] rxQ = s_axis_tdata[31:16];

    wire in_fire    = s_axis_tvalid & s_axis_tready;
    wire this_pilot = is_pilot_bin(in_bin);
    wire [PLW-1:0] pl_k = (in_bin - 1) >> 3;

    // ---- CE pilot-reciprocal ROM : W[k] = conj(plt[k])/|plt[k]|^2 (Q15 scale)
    // 384 = NUM_DATA*NUM_PILOTS words, {Wi[RCW-1:0],Wr[RCW-1:0]}, RCF frac bits.
    // Addressed by a pull counter advancing on each captured pilot bin, mirroring
    // how the upstream pilot ROM is sequenced (slot-major, k=0..31 inner; wraps
    // per slot). This replaces the old single-cycle 64-bit complex DIVIDE
    // (~77 ns / 655 logic levels) with one complex MULTIPLY (math-identical).
    localparam integer PROM_DEPTH = NUM_DATA * NUM_PILOTS;     // 384
    localparam integer PAW        = (PROM_DEPTH <= 1) ? 1 : $clog2(PROM_DEPTH);
    (* rom_style = "block" *)
    reg [2*RCW-1:0] wrecip [0:PROM_DEPTH-1];
    initial $readmemh(W_RECIP_ROM, wrecip);

    reg [PAW:0] prom_addr;
    wire [2*RCW-1:0] wword = wrecip[prom_addr[PAW-1:0]];
    wire signed [RCW-1:0] Wr = $signed(wword[RCW-1:0]);
    wire signed [RCW-1:0] Wi = $signed(wword[2*RCW-1:RCW]);

    always @(posedge clk) begin
        if (!rst_n) begin
            prom_addr <= 0;
        end else if (pilot_tready) begin
            if (prom_addr == PROM_DEPTH-1) prom_addr <= 0;   // wrap per slot
            else                           prom_addr <= prom_addr + 1'b1;
        end
    end

    // CE complex MULTIPLY:  Hp = round( rx * W ) >>> RCF   (rx carries Q15 scale,
    // W is dimensionless at 2^RCF -> Hp comes out at Q15 scale, same as the old
    // divide). 2-STAGE PIPELINE so each clock is a single short op (the divide's
    // 655-level/77ns combinational path is gone; pipelining the multiply keeps
    // the ROM-read->DSP->round->write path < one 250 MHz period):
    //   stage CE1 : register the complex products pr_i/pr_q (one DSP multiply)
    //   stage CE2 : round (>>>RCF) + saturate -> write hp_i/hp_q[bank][k]
    // Only 32 of 256 bins are pilots, so the 2-cycle CE latency is free: the
    // last pilot (bin 249) writes its Hp at bin 249+2; sym_ready still fires one
    // cycle after tlast (bin 255), >= 6 beats later, so the bank is fully
    // populated before the interp engine starts reading it (see sym_ready below).
    localparam integer MULW = DW + RCW + 1;
    localparam signed [MULW-1:0] RND = (1 <<< (RCF-1));
    localparam signed [HW-1:0] HP_MAX =  (1 <<< (HW-1)) - 1;
    localparam signed [HW-1:0] HP_MIN = -(1 <<< (HW-1));

    // ---- CE stage 1 : complex products (single DSP multiply depth) ----
    reg                  ce1_v;
    reg                  ce1_buf;
    reg  [PLW-1:0]       ce1_k;
    reg  signed [MULW-1:0] ce1_pr_i, ce1_pr_q;

    // ---- CE stage 2 : round + saturate + write target tag ----
    reg                  ce2_v;
    reg                  ce2_buf;
    reg  [PLW-1:0]       ce2_k;
    reg  signed [HW-1:0] ce2_hp_i, ce2_hp_q;

    wire pilot_fire = in_fire & this_pilot;

    wire signed [MULW-1:0] hp_i_sh = (ce1_pr_i + RND) >>> RCF;
    wire signed [MULW-1:0] hp_q_sh = (ce1_pr_q + RND) >>> RCF;
    wire signed [HW-1:0] hp_i_full =
        (hp_i_sh >  HP_MAX) ? HP_MAX : (hp_i_sh < HP_MIN) ? HP_MIN : hp_i_sh[HW-1:0];
    wire signed [HW-1:0] hp_q_full =
        (hp_q_sh >  HP_MAX) ? HP_MAX : (hp_q_sh < HP_MIN) ? HP_MIN : hp_q_sh[HW-1:0];

    always @(posedge clk) begin
        if (!rst_n) begin
            ce1_v <= 1'b0; ce2_v <= 1'b0;
        end else begin
            // CE1 : products
            ce1_v   <= pilot_fire;
            ce1_buf <= in_buf;
            ce1_k   <= pl_k;
            ce1_pr_i <= rxI*Wr - rxQ*Wi;
            ce1_pr_q <= rxI*Wi + rxQ*Wr;
            // CE2 : round + saturate
            ce2_v   <= ce1_v;
            ce2_buf <= ce1_buf;
            ce2_k   <= ce1_k;
            ce2_hp_i <= hp_i_full;
            ce2_hp_q <= hp_q_full;
            // write Hp into the ping-pong bank (2 cycles after the pilot beat)
            if (ce2_v) begin
                hp_i[ce2_buf][ce2_k] <= ce2_hp_i;
                hp_q[ce2_buf][ce2_k] <= ce2_hp_q;
            end
        end
    end

    // back-pressure: only stall on the symbol's last beat if the buffer we'd
    // flip into is still being read by the interp engine.
    wire next_buf = ~in_buf;
    assign s_axis_tready = ~(s_axis_tlast & eng_busy[next_buf]);
    assign pilot_tready  = in_fire & this_pilot;

    // sym_ready : 1-cycle pulse the cycle AFTER the tlast (bin 255) beat, tagged
    // with the just-completed bank. This is unchanged from the divide version
    // and is still safe: the last pilot is bin 249, so its Hp write (which now
    // lags the pilot beat by CE_LAT=2 cycles) lands at least 6 accepted beats
    // (bins 250..255) before tlast -> the bank is fully populated before the
    // interp engine starts. (Bubbles only insert idle cycles, never reduce the
    // 6-beat 249->255 separation.)
    always @(posedge clk) begin
        if (!rst_n) begin
            in_bin        <= {PW{1'b0}};
            in_buf        <= 1'b0;
            sym_ready     <= 1'b0;
            sym_ready_buf <= 1'b0;
        end else begin
            sym_ready <= 1'b0;
            if (in_fire) begin
                if (s_axis_tlast) begin
                    sym_ready     <= 1'b1;
                    sym_ready_buf <= in_buf;
                    in_buf        <= ~in_buf;
                    in_bin        <= {PW{1'b0}};
                end else
                    in_bin <= in_bin + 1'b1;
            end
        end
    end

    // ========================================================================
    // INTERP MAC engine : issues k=0..253, produces H_fft[k], writes hbuf[k+1].
    // 9-stage fixed-latency pipeline, 1 bin/clk.
    // ========================================================================
    (* rom_style = "block" *)
    reg [CWORD-1:0] wrom [0:NSC*NUM_PILOTS-1];
    initial $readmemh(W_ROM, wrom);

    localparam ST_IDLE = 2'd0, ST_RUN = 2'd1;
    reg          e_state;
    reg          e_buf;
    reg  [PW-1:0] e_k;            // issue index 0..253
    reg          pending;
    reg          pending_buf;

    localparam integer KMAX = NSC-2;   // 254 outputs (k=0..253)

    // pending latch + busy tracking
    wire issue = (e_state==ST_RUN) & out_ready_pipe;
    wire last_issue = issue & (e_k==KMAX-1);

    always @(posedge clk) begin
        if (!rst_n) begin
            pending<=0; pending_buf<=0; eng_busy[0]<=0; eng_busy[1]<=0;
        end else begin
            if (sym_ready) begin
                pending     <= 1'b1;
                pending_buf <= sym_ready_buf;
                eng_busy[sym_ready_buf] <= 1'b1;
            end
            if (e_state==ST_IDLE && pending)
                pending <= 1'b0;
            if (last_issue)
                eng_busy[e_buf] <= 1'b0;
        end
    end

    // ---- stage 1 : registered ROM + Hp read for issue index e_k ----
    reg signed [CW-1:0] coef_r [0:NUM_PILOTS-1];
    reg signed [CW-1:0] coef_i [0:NUM_PILOTS-1];
    reg signed [HW-1:0] hp_i_r [0:NUM_PILOTS-1];
    reg signed [HW-1:0] hp_q_r [0:NUM_PILOTS-1];
    integer m;
    always @(posedge clk) begin
        for (m=0;m<NUM_PILOTS;m=m+1) begin
            coef_r[m] <= $signed(wrom[e_k*NUM_PILOTS+m][CW-1:0]);
            coef_i[m] <= $signed(wrom[e_k*NUM_PILOTS+m][CWORD-1:CW]);
            hp_i_r[m] <= hp_i[e_buf][m];
            hp_q_r[m] <= hp_q[e_buf][m];
        end
    end

    // ---- stage 2 : 32 complex multiplies ----
    localparam integer PWMUL = CW + HW + 1;
    reg signed [PWMUL-1:0] mul_re [0:NUM_PILOTS-1];
    reg signed [PWMUL-1:0] mul_im [0:NUM_PILOTS-1];
    always @(posedge clk) begin
        for (m=0;m<NUM_PILOTS;m=m+1) begin
            mul_re[m] <= coef_r[m]*hp_i_r[m] - coef_i[m]*hp_q_r[m];
            mul_im[m] <= coef_r[m]*hp_q_r[m] + coef_i[m]*hp_i_r[m];
        end
    end

    // ---- stages 3..7 : 5-level adder tree ----
    localparam integer AW = PWMUL + 5;
    reg signed [AW-1:0] t16_re[0:15], t16_im[0:15];
    reg signed [AW-1:0] t8_re [0:7],  t8_im [0:7];
    reg signed [AW-1:0] t4_re [0:3],  t4_im [0:3];
    reg signed [AW-1:0] t2_re [0:1],  t2_im [0:1];
    reg signed [AW-1:0] t1_re,        t1_im;
    integer t;
    always @(posedge clk) begin
        for (t=0;t<16;t=t+1) begin
            t16_re[t] <= mul_re[2*t] + mul_re[2*t+1];
            t16_im[t] <= mul_im[2*t] + mul_im[2*t+1];
        end
        for (t=0;t<8;t=t+1) begin
            t8_re[t] <= t16_re[2*t]+t16_re[2*t+1];
            t8_im[t] <= t16_im[2*t]+t16_im[2*t+1];
        end
        for (t=0;t<4;t=t+1) begin
            t4_re[t] <= t8_re[2*t]+t8_re[2*t+1];
            t4_im[t] <= t8_im[2*t]+t8_im[2*t+1];
        end
        for (t=0;t<2;t=t+1) begin
            t2_re[t] <= t4_re[2*t]+t4_re[2*t+1];
            t2_im[t] <= t4_im[2*t]+t4_im[2*t+1];
        end
        t1_re <= t2_re[0]+t2_re[1];
        t1_im <= t2_im[0]+t2_im[1];
    end

    // ---- stage 8 : scale >> CF with rounding ----
    wire signed [AW-1:0] round_bias = (64'sd1 <<< (CF-1));
    reg signed [AW-1:0] sc_re, sc_im;
    always @(posedge clk) begin
        sc_re <= (t1_re + round_bias) >>> CF;
        sc_im <= (t1_im + round_bias) >>> CF;
    end

    // ---- valid + bin-tag pipeline (LAT stages, lock-step, no internal stall) ----
    localparam integer LAT = 8;   // stage1..stage8 == sc_* valid after 8 regs
    reg [LAT-1:0]  v_pipe;
    reg [PW-1:0]   bin_pipe [0:LAT-1];

    always @(posedge clk) begin
        if (!rst_n) begin
            e_state<=ST_IDLE; e_buf<=0; e_k<=0; v_pipe<=0;
        end else begin
            // shift the whole valid/tag pipe every clock the engine runs OR drains
            v_pipe <= {v_pipe[LAT-2:0], issue};
            bin_pipe[0] <= e_k;
            for (t=1;t<LAT;t=t+1) bin_pipe[t] <= bin_pipe[t-1];

            case (e_state)
              ST_IDLE: if (pending) begin
                           e_state<=ST_RUN; e_buf<=pending_buf; e_k<=0;
                       end
              ST_RUN:  if (issue) begin
                           if (e_k==KMAX-1) e_state<=ST_IDLE;
                           else             e_k<=e_k+1'b1;
                       end
            endcase
        end
    end

    // ========================================================================
    // OUTPUT : write H_fft[k] into hbuf[k+1]; zero bins 0/255; stream 0..255.
    // ========================================================================
    function automatic signed [DW-1:0] sat16(input signed [AW-1:0] v);
        if (v >  32767)       sat16 = 16'sd32767;
        else if (v < -32768)  sat16 = -16'sd32768;
        else                  sat16 = v[DW-1:0];
    endfunction

    wire          res_valid = v_pipe[LAT-1];
    wire [PW-1:0] res_k     = bin_pipe[LAT-1];   // 0..253
    wire [PW-1:0] res_bin   = res_k + 1'b1;       // output bin 1..254

    reg signed [DW-1:0] hbuf_i [0:1][0:NSC-1];
    reg signed [DW-1:0] hbuf_q [0:1][0:NSC-1];
    // Zero-init the interpolated-H output banks so silicon powers up KNOWN
    // (written-then-read ping-pong; reads 0 in sim but RANDOM on silicon).
    integer hbuf_init_b, hbuf_init_k;
    initial begin
        for (hbuf_init_b = 0; hbuf_init_b < 2; hbuf_init_b = hbuf_init_b + 1)
            for (hbuf_init_k = 0; hbuf_init_k < NSC; hbuf_init_k = hbuf_init_k + 1) begin
                hbuf_i[hbuf_init_b][hbuf_init_k] = {DW{1'b0}};
                hbuf_q[hbuf_init_b][hbuf_init_k] = {DW{1'b0}};
            end
    end
    reg                 fill_buf;

    // start of a new result fill = first valid result of a symbol (res_k==0)
    wire fill_start = res_valid & (res_k==0);

    // RACE-FREE hbuf_full[] UPDATE (same deterministic-stall class as the
    // rx_fft_frontend filled[] fix).  hbuf_full had THREE separate NBA writes
    // to the same 2-bit reg in one block: SET hbuf_full[fill_buf] (last result
    // of a symbol), CLEAR hbuf_full[~fill_buf] (fill_start re-arm), and CLEAR
    // hbuf_full[o_buf] (output sequencer finishing a bank).  If the SET and the
    // output CLEAR ever hit the SAME bank on the SAME cycle, Verilog source
    // order lets the CLEAR win and the SET is LOST -> the just-filled H bank is
    // marked empty -> the output sequencer never streams it and the interp
    // engine's out_ready_pipe (=~(both full)) mis-tracks -> H stream stops ->
    // rxbuf inflight saturates -> fft-frontend readout stalls -> STALL_TIMEOUT.
    // Fix: SET-dominant, order-independent per-bank next-state.  RAM writes are
    // unchanged; only the flag bookkeeping is made race-free.
    wire        hf_set  = (res_valid & ~fill_start) & (res_k==KMAX-1);
    wire [0:0]  hf_setb = fill_buf;
    wire        hf_clr1 = fill_start;               // re-arm the newly targeted bank
    wire [0:0]  hf_clr1b= ~fill_buf;
    wire        hf_clr2 = o_active & o_fire & (o_bin==NSC-1);  // output drained a bank
    wire [0:0]  hf_clr2b= o_buf;

    reg  [1:0] hbuf_full_nxt;
    integer hb;
    always @(*) begin
        hbuf_full_nxt = hbuf_full;
        for (hb = 0; hb < 2; hb = hb + 1) begin
            // clears first, then set -> SET dominates on a same-bank collision
            if (hf_clr1 && (hf_clr1b == hb[0])) hbuf_full_nxt[hb] = 1'b0;
            if (hf_clr2 && (hf_clr2b == hb[0])) hbuf_full_nxt[hb] = 1'b0;
            if (hf_set  && (hf_setb  == hb[0])) hbuf_full_nxt[hb] = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            hbuf_full[0]<=0; hbuf_full[1]<=0; fill_buf<=0;
        end else begin
            hbuf_full <= hbuf_full_nxt;         // race-free (set-dominant)
            if (fill_start) begin
                fill_buf <= ~fill_buf;
                hbuf_i[~fill_buf][0]     <= 0; hbuf_q[~fill_buf][0]     <= 0;
                hbuf_i[~fill_buf][NSC-1] <= 0; hbuf_q[~fill_buf][NSC-1] <= 0;
                // write this first result too
                hbuf_i[~fill_buf][1]     <= sat16(sc_re);
                hbuf_q[~fill_buf][1]     <= sat16(sc_im);
            end else if (res_valid) begin
                hbuf_i[fill_buf][res_bin] <= sat16(sc_re);
                hbuf_q[fill_buf][res_bin] <= sat16(sc_im);
            end
        end
    end

    // ---- M_AXIS sequencer : stream bins 0..255 from a full hbuf ----
    assign o_fire = m_axis_tvalid & m_axis_tready;

    always @(posedge clk) begin
        if (!rst_n) begin
            o_active<=0; o_buf<=0; o_bin<=0;
        end else begin
            if (!o_active) begin
                if (hbuf_full[o_buf])      begin o_active<=1; o_bin<=0; end
                else if (hbuf_full[~o_buf])begin o_active<=1; o_buf<=~o_buf; o_bin<=0; end
            end else if (o_fire) begin
                if (o_bin==NSC-1) begin
                    o_active<=0; o_buf<=~o_buf;
                end else
                    o_bin<=o_bin+1'b1;
            end
        end
    end

    assign m_axis_tvalid = o_active;
    assign m_axis_tdata  = { hbuf_q[o_buf][o_bin], hbuf_i[o_buf][o_bin] };
    assign m_axis_tlast  = o_active & (o_bin==NSC-1);

endmodule
`default_nettype wire
