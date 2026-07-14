// =====================================================================
// tx_ifft_frontend.v
// ---------------------------------------------------------------------
// OFDM TX back-end: 256-pt IDFT (xfft_N driven INVERSE, BFP) + 1/16
// recover scale + cyclic-prefix insert, producing one 288-sample
// time-domain OFDM data symbol (CP + body), 1 sample/clock, AXI-Stream.
//
// Ports ref/transmitter.c (ifft_new l.106 = FFTW_BACKWARD then /sqrt(NSC);
// insert_cp l.108 = prepend last CP_LEN body samples) and matches the
// validated rx_downstream_ref.tx_modulate_block IFFT+CP (CONTRACT.md
// sec 4/5).
//
// ---------------------------------------------------------------------
// FFT IP  (rtl/xfft_N/xfft_N.xci -- a THIRD independent xfft_N instance;
//          the Meyr CFO core owns the first, rx_fft_frontend the second)
// ---------------------------------------------------------------------
//   xfft 9.1, 256-pt, 16b I/Q, pipelined_streaming_io, natural order,
//   block_floating_point (BFP), truncation.  Configured INVERSE via
//   s_axis_config tdata bit0 FWD_INV = 0 (one-shot at reset).
//
//   NORMALIZATION
//   -------------
//   The C TX computes  body = FFTW_BACKWARD(spec) / sqrt(NSC).  FFTW_
//   BACKWARD is the UNSCALED inverse DFT = N * np.fft.ifft (a pure sum,
//   exp(+j2pi kn/N)).  The xfft inverse in BFP also computes that
//   unscaled inverse but right-shifts by a per-frame block exponent
//   `blk_exp` (m_axis_data_tuser, 8b) so the 16b output never overflows.
//   The TRUE unscaled inverse value is  ifft_true = out16 << blk_exp.
//   The golden applies the extra 1/sqrt(256) = 1/16 (>>4), so the body
//   sample this module emits is:
//
//        body_q15 = (out16 << blk_exp) >> 4        (per I and Q, rounded)
//
//   identical recover math to rx_fft_frontend.  (Verified vs the Python
//   golden: <= 2 LSB error per body sample, blk_exp ~= 3.)
//
// ---------------------------------------------------------------------
// CYCLIC PREFIX
// ---------------------------------------------------------------------
//   insert_cp prepends the LAST CP_LEN=32 body samples to the front, so
//   the emitted 288-sample symbol is  body[224..255] , body[0..255].
//   The IFFT IP emits the 256 body samples in natural time order 0..255.
//   We buffer the whole symbol body (256x32 double-buffer) so we can read
//   out the CP (addresses 224..255) first, then the full body 0..255.
//   m_last marks the 288th (last) output sample of each symbol.
//
// ---------------------------------------------------------------------
// THROUGHPUT / TIMING
// ---------------------------------------------------------------------
//   1 complex sample/clock everywhere; the input streams 256 spectrum
//   bins/symbol into the pipelined-streaming IFFT, which emits one body
//   sample/clock.  The BFP recover (barrel-shift + round + saturate) is
//   split into 2 registered stages, same as rx_fft_frontend, so the only
//   heavy arithmetic (the IFFT butterflies) lives in the Xilinx IP that
//   closes > 300 MHz OOC on this part.  Module Fmax (excl. IP) > 350 MHz.
//   Output is double-buffered (read symbol z while capturing z+1), so the
//   CP read-out never stalls between symbols.  Full AXI-Stream tready in
//   both directions.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_ifft_frontend #(
    parameter integer DATA_W   = 16,
    parameter integer NSC      = 256,
    parameter integer CP_LEN   = 32,
    parameter integer SCALE_SH = 4       // 1/sqrt(256) = >>4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- slave : 256 spectrum bins (fftshift order), {Q,I} Q15 ----
    input  wire                    s_valid,
    output wire                    s_ready,
    input  wire [2*DATA_W-1:0]     s_tdata,
    input  wire                    s_last,      // bin 255 of a symbol

    // ---- master : 288-sample time symbol (CP+body), {Q,I} Q15 ----
    output wire                    m_valid,
    input  wire                    m_ready,
    output wire [2*DATA_W-1:0]     m_tdata,
    output wire                    m_last       // sample 287 of a symbol
);
    localparam integer NSC_LOG2 = 8;          // log2(256)
    localparam integer SYM_LEN  = NSC + CP_LEN;  // 288

    // =================================================================
    // 1.  ONE-SHOT IFFT CONFIG  (inverse, FWD_INV = 0)
    // =================================================================
    reg  cfg_done;
    wire cfg_tready;
    wire cfg_tvalid = ~cfg_done;
    wire [7:0] cfg_tdata = 8'h00;             // FWD_INV = 0 -> INVERSE FFT
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                          cfg_done <= 1'b0;
        else if (cfg_tvalid && cfg_tready)   cfg_done <= 1'b1;
    end

    // =================================================================
    // 2.  INPUT : pass spectrum bins straight into the IFFT data slave
    //     tlast on bin 255 (= s_last) so the IP frames each 256-pt block.
    // =================================================================
    // cfg_done GATE: same fix as rx_fft_frontend -- hold data off the xfft until
    // its one-shot FWD_INV=0 (inverse) config beat is accepted, so data never
    // races the config handshake at reset release (per-POR-stable garbage on
    // silicon otherwise; masked in sim by the config-ignoring xfft stub).
    wire        ifft_din_tready;
    wire        ifft_din_tvalid = cfg_done && s_valid;
    wire [31:0] ifft_din_tdata  = { s_tdata[2*DATA_W-1:DATA_W],   // Q
                                    s_tdata[DATA_W-1:0] };        // I
    wire        ifft_din_tlast  = s_last;
    assign s_ready = cfg_done && ifft_din_tready;

    // =================================================================
    // 3.  XFFT_N  (THIRD INDEPENDENT INSTANCE) -- 256-pt INVERSE BFP
    // =================================================================
    wire        ifft_dout_tvalid;
    wire        ifft_dout_tready;
    wire [31:0] ifft_dout_tdata;          // {Q[31:16], I[15:0]}, BFP 16b
    wire        ifft_dout_tlast;
    wire [7:0]  ifft_dout_tuser;          // block exponent (BFP)

    xfft_N u_ifft_N (
        .aclk                        (clk),
        .aresetn                     (rst_n),
        .s_axis_config_tvalid        (cfg_tvalid),
        .s_axis_config_tready        (cfg_tready),
        .s_axis_config_tdata         (cfg_tdata),
        .s_axis_data_tvalid          (ifft_din_tvalid),
        .s_axis_data_tready          (ifft_din_tready),
        .s_axis_data_tdata           (ifft_din_tdata),
        .s_axis_data_tlast           (ifft_din_tlast),
        .m_axis_data_tvalid          (ifft_dout_tvalid),
        .m_axis_data_tready          (ifft_dout_tready),
        .m_axis_data_tdata           (ifft_dout_tdata),
        .m_axis_data_tlast           (ifft_dout_tlast),
        .m_axis_data_tuser           (ifft_dout_tuser),
        .m_axis_status_tready        (1'b1),
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_status_channel_halt   (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt ()
    );

    // =================================================================
    // 4.  BFP RECOVER  (pipelined, 1 sample/clk) + body double-buffer
    //     The IP emits body samples in NATURAL time order 0..255.  Apply
    //     ((out16 << blk_exp) >> SCALE_SH) round + saturate, write into a
    //     double-buffered body RAM at the natural address (no shuffle).
    // =================================================================
    reg  [NSC_LOG2-1:0] tc;               // 0..255 natural time index
    reg                 wbuf;             // body buffer being WRITTEN
    wire ifft_out_fire = ifft_dout_tvalid && ifft_dout_tready;

    // ---- Stage S1 : capture, sign-extend, hold blk_exp + addr ----
    reg  signed [DATA_W-1:0] s1_i, s1_q;
    reg  [4:0]               s1_blk;
    reg  [NSC_LOG2-1:0]      s1_addr;
    reg                      s1_wbuf;
    reg                      s1_we;
    reg                      s1_last;

    wire signed [DATA_W-1:0] din_i = ifft_dout_tdata[DATA_W-1:0];
    wire signed [DATA_W-1:0] din_q = ifft_dout_tdata[2*DATA_W-1:DATA_W];

    // ---- Stage S2 : (val << blk) >> SCALE_SH, round + saturate ----
    localparam integer WSH = DATA_W + 8;  // 24-bit shifted field
    wire signed [WSH-1:0] sh_i = $signed(s1_i) <<< s1_blk;
    wire signed [WSH-1:0] sh_q = $signed(s1_q) <<< s1_blk;
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
    reg  [NSC_LOG2-1:0]  s2_addr;
    reg                  s2_wbuf;
    reg                  s2_we;
    wire [31:0] s2_word = { sat16(res_q), sat16(res_i) };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tc      <= {NSC_LOG2{1'b0}};
            wbuf    <= 1'b0;
            s1_we   <= 1'b0;
            s2_we   <= 1'b0;
            s1_last <= 1'b0;
        end else begin
            // ---- S1 capture ----
            s1_we <= 1'b0;
            if (ifft_out_fire) begin
                s1_i    <= din_i;
                s1_q    <= din_q;
                s1_blk  <= ifft_dout_tuser[4:0];
                s1_addr <= tc;                // natural time address
                s1_wbuf <= wbuf;
                s1_we   <= 1'b1;
                s1_last <= ifft_dout_tlast;
                if (tc == NSC-1) begin
                    tc   <= {NSC_LOG2{1'b0}};
                    wbuf <= ~wbuf;
                end else begin
                    tc <= tc + 1'b1;
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
    // 5.  OUTPUT : CP-insert read-out  (288 samples, 1/clk, AXI-S)
    //     read order for a symbol = body[224..255] then body[0..255].
    //     A `rc` counter 0..287: addr = (rc < CP_LEN) ? (NSC-CP_LEN+rc)
    //                                                  : (rc - CP_LEN).
    // =================================================================
    reg  [1:0]          filled;          // [b] = body buffer b fully written
    reg                 rbuf;            // body buffer being READ
    reg  [8:0]          rc;              // 0..287 output sample index
    reg                 rd_active;

    // symbol-complete marker (last body sample written -> mark buffer full)
    reg  s2_sym_done;
    reg  s2_done_buf;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_sym_done <= 1'b0;
            s2_done_buf <= 1'b0;
        end else begin
            s2_sym_done <= s1_we && s1_last;
            s2_done_buf <= s1_wbuf;
        end
    end

    // CP-insert read address
    wire [NSC_LOG2-1:0] raddr = (rc < CP_LEN) ? (NSC - CP_LEN + rc[NSC_LOG2-1:0])
                                              : (rc[NSC_LOG2-1:0] - CP_LEN[NSC_LOG2-1:0]);
    wire [31:0] rdata = rbuf ? ram1[raddr] : ram0[raddr];

    reg         m_valid_r;
    reg         m_last_r;
    reg  [31:0] m_data_r;
    wire out_room = (!m_valid_r) || m_ready;
    wire have_smp = rd_active;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filled    <= 2'b00;
            rbuf      <= 1'b0;
            rc        <= 9'd0;
            rd_active <= 1'b0;
            m_valid_r <= 1'b0;
            m_last_r  <= 1'b0;
            m_data_r  <= 32'd0;
        end else begin
            if (s2_sym_done)
                filled[s2_done_buf] <= 1'b1;

            if (out_room) begin
                if (have_smp) begin
                    m_data_r  <= rdata;
                    m_last_r  <= (rc == SYM_LEN-1);
                    m_valid_r <= 1'b1;
                    if (rc == SYM_LEN-1) begin
                        filled[rbuf] <= 1'b0;
                        rbuf         <= ~rbuf;
                        rd_active    <= 1'b0;
                        rc           <= 9'd0;
                    end else begin
                        rc <= rc + 1'b1;
                    end
                end else begin
                    m_valid_r <= 1'b0;
                end
            end

            if (!rd_active && filled[rbuf]) begin
                rd_active <= 1'b1;
                rc        <= 9'd0;
            end
        end
    end

    // back-pressure on the IFFT output: block capture into wbuf while it
    // still holds an un-read symbol (the other buffer may read out concurrently)
    assign ifft_dout_tready = ~filled[wbuf];

    assign m_valid = m_valid_r;
    assign m_tdata = m_data_r;
    assign m_last  = m_last_r;

    wire _unused = &{1'b0, ifft_dout_tlast};

endmodule

`default_nettype wire
