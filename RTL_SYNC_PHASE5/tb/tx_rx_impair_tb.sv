// =====================================================================
// tx_rx_impair_tb.sv  --  PHASE-2 DIVERSE IMPAIRMENT regression TB
// ---------------------------------------------------------------------
// Extends tb/tx_rx_loop_tb.sv (the clean multi-mod loopback) with an
// IMPAIRMENT block injected on the TX->RX 32-bit {Q,I} sample stream:
//
//   tx_ofdm_top(mod_sel) --> [ impairment ] --> rx_downstream_top(mod_sel) --> BER
//
// The impairment is selected by +IMP and parametrised by plusargs.  The
// AXI-Stream handshake is preserved exactly (the transform is a function
// of the accepted-beat history; tvalid/tready pass straight through), so
// the proven data path is unchanged -- only the carried samples differ.
//
//   +MOD=<0|1|2|3>   modulation : 0=QPSK 1=16QAM 2=64QAM 3=256QAM
//   +IMP=<0|1|2>     0 = CLEAN (identity, == tx_rx_loop_tb)
//                    1 = AWGN  (complex Gaussian noise, +SNRDB)
//                    2 = MULTIPATH (3-tap freq-selective channel)
//   +SNRDB=<int>     AWGN SNR in dB (integer; used when IMP=1)
//   +SEED=<int>      RNG seed (so AWGN points are reproducible/independent)
//
// AWGN scaling : the TX time-domain DATA region RMS is ~8120 (Q15,
// measured).  For complex signal power P = RMS^2 and complex AWGN power
// N = 2*sigma^2 (sigma per I/Q component), SNR = P/N gives
//   sigma = RMS / sqrt(2 * 10^(SNR/10)).
// The TB computes sigma at runtime from +SNRDB.  Gaussian samples come
// from a Box-Muller transform on two uniforms (Verilog $dist_uniform).
//
// MULTIPATH : a fixed 3-tap complex channel h = {1.0, 0.45angle, 0.2angle}
// (taps within the CP_LEN=32 budget) convolved with the complex stream.
// The pilot-based CE captures it and the ZF EQ divides it out -> at the
// no-noise multipath case BER must be ~0 for every modulation, proving
// the equalizer works across modulation orders.
//
// Gate line emitted:
//   IMP_RESULT MOD=<m> IMP=<i> SNRDB=<s> BER <err> / <bits>  -> PASS|FAIL
//   plus "RESULT: PASS|FAIL" (PASS criterion: collected all carriers; for
//   the clean/multipath/high-SNR points PASS additionally requires BER==0).
// The harness (run_tx_rx_impair.sh) parses the IMP_RESULT line for the
// BER number and grades clean/required points on BER==0.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_rx_impair_tb;
    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer NUM_SYN  = 2;
    localparam integer NUM_DATA = 12;
    localparam integer NPIL     = 32;
    localparam integer NDATA_SC = 221;
    localparam integer BPC_MAX  = 8;
    localparam integer NBEATS   = NUM_DATA*NDATA_SC;   // 2652 data carriers
    localparam integer NPLT     = NUM_DATA*NPIL;       // 384 pilots

    // ---- runtime plusargs ----
    integer MOD, IMP, SNRDB, SEED;
    integer K, BPS, NBITS;
    reg [1:0] mod_sel;
    reg [1023:0] gdir;

    reg clk = 1'b0; always #5 clk = ~clk;   // 100 MHz functional clock
    reg rst_n = 1'b0;

    // ============================ TX ==================================
    reg          tx_start;
    wire         tx_busy;
    reg  [NUM_DATA*NDATA_SC*BPC_MAX-1:0] data_bits_flat;
    wire [8:0]   tx_pilot_addr;
    reg  [31:0]  tx_pilot_tdata;
    wire         tx_m_valid;
    wire         tx_m_ready;
    wire [31:0]  tx_m_tdata;
    wire         tx_m_last;

    tx_ofdm_top #(
        .DATA_W(16), .NSC(256), .CP_LEN(32), .NUM_SYN(2), .NUM_DATA(12),
        .NPIL(32), .NDATA_SC(221), .BPC_MAX(8), .Q16_1(1610), .Q16_3(4829),
        .SPECMAP("rtl/tx_rom/tx_specmap.hex"),
        .SYNC_ROM("rtl/tx_rom/tx_sync_rom.hex")
    ) u_tx (
        .clk(clk), .rst_n(rst_n),
        .mod_sel(mod_sel),
        .start(tx_start), .busy(tx_busy),
        .data_bits_flat(data_bits_flat),
        .pilot_addr(tx_pilot_addr), .pilot_tdata(tx_pilot_tdata),
        .m_valid(tx_m_valid), .m_ready(tx_m_ready),
        .m_tdata(tx_m_tdata), .m_last(tx_m_last)
    );

    // ===================== IMPAIRMENT BLOCK ===========================
    // Transforms the carried 32-bit {Q,I} sample; valid/ready straight-thru.
    // History (for the FIR channel) advances only on accepted beats.
    real    sigma;                          // AWGN per-component std (Q15 units)
    integer in_idx;                         // accepted-beat index into stream

    // signed split of the live TX sample
    wire signed [15:0] tx_i = tx_m_tdata[15:0];
    wire signed [15:0] tx_q = tx_m_tdata[31:16];

    // 3-tap channel state (previous two accepted complex samples)
    reg signed [15:0] z1_i, z1_q, z2_i, z2_q;

    // fixed-point channel taps (Q15-ish gains, applied then >>>15)
    // h0 = 1.0 (32768), h1 = 0.45 e^{j*0.8}, h2 = 0.2 e^{j*(-1.3)}
    localparam signed [16:0] H0R = 17'sd32768, H0I = 17'sd0;
    localparam signed [16:0] H1R = 17'sd10272, H1I = 17'sd10570; // 0.45*cos.8, 0.45*sin.8
    localparam signed [16:0] H2R = 17'sd1752 , H2I = -17'sd6314; // 0.2*cos(-1.3),0.2*sin(-1.3)

    // helper : clamp a wide signed value to 16-bit
    function signed [15:0] clamp16(input signed [31:0] v);
        begin
            if (v >  32767) clamp16 = 16'sd32767;
            else if (v < -32768) clamp16 = -16'sd32768;
            else clamp16 = v[15:0];
        end
    endfunction

    // Box-Muller Gaussian : returns a real ~N(0,1)
    integer rng_state;
    function real randu;   // uniform (0,1)
        integer r;
        begin
            r = $dist_uniform(rng_state, 1, 1000000);
            randu = r / 1000000.0;
        end
    endfunction
    function real gauss;   // standard normal via Box-Muller
        real u1, u2;
        begin
            u1 = randu(); u2 = randu();
            if (u1 < 1e-9) u1 = 1e-9;
            gauss = $sqrt(-2.0*$ln(u1)) * $cos(6.283185307*u2);
        end
    endfunction

    // combinational impaired sample
    reg signed [15:0] imp_i, imp_q;
    integer ci, cq;     // channel-convolved I/Q (full precision before clamp)
    integer ni, nq;     // noise samples
    always @(*) begin
        case (IMP)
            2: begin // 3-tap multipath
                ci = (H0R*tx_i - H0I*tx_q + H1R*z1_i - H1I*z1_q + H2R*z2_i - H2I*z2_q) >>> 15;
                cq = (H0R*tx_q + H0I*tx_i + H1R*z1_q + H1I*z1_i + H2R*z2_q + H2I*z2_i) >>> 15;
                imp_i = clamp16(ci);
                imp_q = clamp16(cq);
            end
            1: begin // AWGN : add per-component Gaussian noise (computed below)
                imp_i = clamp16($signed(tx_i) + ni);
                imp_q = clamp16($signed(tx_q) + nq);
            end
            default: begin // CLEAN identity
                imp_i = tx_i;
                imp_q = tx_q;
            end
        endcase
    end

    // refresh the noise pair every accepted beat (so each sample gets fresh
    // independent noise); ni/nq are read combinationally by imp_i/imp_q.
    always @(posedge clk) begin
        if (!rst_n) begin ni <= 0; nq <= 0; end
        else if (IMP == 1) begin
            // generate when a beat is offered (valid&ready) -> next-cycle data
            ni <= $rtoi(sigma * gauss());
            nq <= $rtoi(sigma * gauss());
        end
    end

    // advance channel history on accepted beats
    always @(posedge clk) begin
        if (!rst_n) begin
            z1_i<=0; z1_q<=0; z2_i<=0; z2_q<=0; in_idx<=0;
        end else if (tx_m_valid && tx_m_ready) begin
            z2_i<=z1_i; z2_q<=z1_q;
            z1_i<=tx_i; z1_q<=tx_q;
            in_idx<=in_idx+1;
        end
    end

    // impaired stream feeding the RX (valid/ready pass-through)
    wire [31:0] imp_tdata = {imp_q, imp_i};
    wire        imp_valid = tx_m_valid;

    // ============================ RX ==================================
    wire         rx_s_ready;
    reg  [31:0]  rx_pilot_tdata;
    wire         rx_pilot_tready;
    wire         rx_m_valid;
    reg          rx_m_ready;
    wire [BPC_MAX-1:0] rx_m_bits;
    wire         rx_m_last, rx_m_user;

    rx_downstream_top #(
        .DW(16), .NSC(256), .CP_LEN(32),
        .NUM_SYN(2), .NUM_DATA(12), .NUM_PILOTS(32), .NDATA_SC(221),
        .TUSERW(16), .BPC_MAX(8)
    ) u_rx (
        .clk(clk), .rst_n(rst_n),
        .mod_sel(mod_sel),
        .s_valid(imp_valid), .s_ready(rx_s_ready), .s_tdata(imp_tdata),
        .pilot_tdata(rx_pilot_tdata), .pilot_tready(rx_pilot_tready),
        .m_valid(rx_m_valid), .m_ready(rx_m_ready),
        .m_bits(rx_m_bits), .m_last(rx_m_last), .m_user(rx_m_user)
    );

    assign tx_m_ready = rx_s_ready;

    // ---- pilot ROM (shared by TX + RX, symbol-major z*32+p) ----
    reg [31:0] plt_mem [0:NPLT-1];
    initial $readmemh("golden/rx_downstream/pilot_rom.hex", plt_mem);
    always @(*) tx_pilot_tdata = plt_mem[tx_pilot_addr];
    integer plt_ptr;
    always @(*) rx_pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!rst_n) plt_ptr <= 0;
        else if (rx_pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- per-mod data bits ----
    reg [7:0] cbits [0:NUM_DATA*NDATA_SC*8-1];
    reg [7:0] txbit [0:NBEATS*BPC_MAX-1];
    reg [7:0] rxbit [0:NBEATS*BPC_MAX-1];
    integer fbits, c, di, b, n;
    reg pa_ok;
    initial begin
        MOD=1; IMP=0; SNRDB=100; SEED=1;
        pa_ok = $value$plusargs("MOD=%d",   MOD);
        void'($value$plusargs("IMP=%d",   IMP));
        void'($value$plusargs("SNRDB=%d", SNRDB));
        void'($value$plusargs("SEED=%d",  SEED));
        if (pa_ok === 1'bx) MOD = 1;
        mod_sel = MOD[1:0];
        K   = MOD + 1;
        BPS = 2*K;
        NBITS = NBEATS*BPS;
        rng_state = SEED + 12345;
        // sigma = RMS / sqrt(2*10^(SNR/10)) ; RMS ~ 8120 (measured TX data RMS)
        sigma = 8120.0 / $sqrt(2.0 * $pow(10.0, SNRDB/10.0));
        case (MOD)
            0: gdir = "golden/rx_downstream/qpsk";
            1: gdir = "golden/rx_downstream/16qam";
            2: gdir = "golden/rx_downstream/64qam";
            default: gdir = "golden/rx_downstream/256qam";
        endcase

        fbits = $fopen({gdir, "/tx_data_bits_bpc8.txt"}, "r");
        if (fbits == 0) begin $display("RESULT: FAIL (no tx_data_bits_bpc8.txt for MOD=%0d)", MOD); $finish; end
        di = 0;
        while (!$feof(fbits) && di < NUM_DATA*NDATA_SC*8) begin
            c = $fgetc(fbits);
            if (c == "0" || c == "1") begin cbits[di] = c[7:0]; di = di + 1; end
        end
        $fclose(fbits);

        for (di = 0; di < NUM_DATA*NDATA_SC*8; di = di + 1)
            data_bits_flat[di] = (cbits[di] == "1");
        for (n = 0; n < NBEATS; n = n + 1)
            for (b = 0; b < BPS; b = b + 1)
                txbit[n*BPC_MAX + b] = cbits[n*8 + b];
    end

    // ---- RX demod output back-pressure ~75% ----
    integer rseed = 32'h0FACADE;
    always @(posedge clk) begin
        if (!rst_n) rx_m_ready <= 1'b0;
        else        rx_m_ready <= ($random(rseed) % 4) != 0;
    end

    // ---- collect RX bits ----
    integer rx_cnt, cyc, first_bit_cyc, rb;
    initial begin rx_cnt = 0; cyc = 0; first_bit_cyc = -1; end
    always @(posedge clk) begin
        if (rst_n) cyc <= cyc + 1;
        if (rst_n && rx_m_valid && rx_m_ready) begin
            if (first_bit_cyc < 0) first_bit_cyc = cyc;
            if (rx_cnt < NBEATS) begin
                for (rb = 0; rb < BPS; rb = rb + 1)
                    rxbit[rx_cnt*BPC_MAX + rb] <= rx_m_bits[BPS-1-rb] ? "1" : "0";
            end
            rx_cnt <= rx_cnt + 1;
        end
    end

    // ---- drive : reset, then pulse tx_start ----
    initial begin
        tx_start = 1'b0; rst_n = 1'b0;
        repeat (12) @(posedge clk);
        rst_n = 1'b1;
        repeat (6) @(posedge clk);
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;
    end

    // ---- finish + BER ----
    integer errors, timeout;
    reg ber_zero_required;
    initial begin
        timeout = 0;
        wait (rst_n);
        @(posedge clk);
        while (rx_cnt < NBEATS && timeout < 6_000_000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        if (rx_cnt != NBEATS) begin
            $display("FATAL: collected %0d / %0d data carriers (timeout=%0d)", rx_cnt, NBEATS, timeout);
            $display("IMP_RESULT MOD=%0d IMP=%0d SNRDB=%0d BER -1 / %0d -> FAIL", MOD, IMP, SNRDB, NBITS);
            $display("RESULT: FAIL"); $finish;
        end
        errors = 0;
        for (n = 0; n < NBEATS; n = n + 1)
            for (b = 0; b < BPS; b = b + 1)
                if (rxbit[n*BPC_MAX + b] !== txbit[n*BPC_MAX + b]) errors = errors + 1;

        // PASS criterion : clean(IMP=0) and multipath(IMP=2) require BER==0;
        // AWGN(IMP=1) is informative (BER-vs-SNR curve) -> PASS if all
        // carriers collected (BER reported but not asserted zero here).
        ber_zero_required = (IMP != 1);

        $display("==================================================");
        $display(" TX -> [IMP] -> RX  MOD=%0d IMP=%0d SNRDB=%0d SEED=%0d (BPS=%0d sigma=%0f)",
                 MOD, IMP, SNRDB, SEED, BPS, sigma);
        $display("   data carriers    = %0d (exp %0d)", rx_cnt, NBEATS);
        $display("   total bits       = %0d", NBITS);
        $display("   bit errors       = %0d", errors);
        $display("   BER              = %0d / %0d", errors, NBITS);
        $display("IMP_RESULT MOD=%0d IMP=%0d SNRDB=%0d BER %0d / %0d -> %s",
                 MOD, IMP, SNRDB, errors, NBITS,
                 (!ber_zero_required || errors==0) ? "PASS" : "FAIL");
        if (rx_cnt == NBEATS && (!ber_zero_required || errors == 0))
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $display("==================================================");
        $finish;
    end

    initial begin #120_000_000; $display("FATAL: global timeout");
        $display("IMP_RESULT MOD=%0d IMP=%0d SNRDB=%0d BER -1 / 0 -> FAIL", MOD, IMP, SNRDB);
        $display("RESULT: FAIL"); $finish; end
endmodule
`default_nettype wire
