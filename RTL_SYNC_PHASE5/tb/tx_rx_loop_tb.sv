// =====================================================================
// tx_rx_loop_tb.sv
// ---------------------------------------------------------------------
// END-TO-END TX -> RX LOOP self-check (the headline TX deliverable).
//
//   tx_ofdm_top  (RTL transmitter)
//        |  m_axis : 4032-sample slot {Q,I} Q15
//        v          (identity channel, sample-for-sample)
//   rx_downstream_top  (the existing, silicon-validated RX:
//                       FFT -> CE -> EQ -> 16-QAM demod)
//        |  m_bits : 4 bits / data carrier
//        v
//   BER check vs the SAME data bits fed into the TX.
//
// The TX produces the synchronizer's 4032-sample corrected-M_AXIS frame
// (2 REAL PSS/SSS sync symbols + 12 data symbols).  The RX's FFT front-
// end internally skips the 576-sample sync region, so the slot streams
// straight through with NO sync hardware needed in this loop -- the data
// path is what is being proven.  PASS <=> BER == 0 over all 10608 bits.
//
//   Gate line: "RESULT: PASS" / "RESULT: FAIL"  +  "TXRX_LOOP: PASS|FAIL"
//
// Both blocks use the REAL xfft_N IP under xsim (TX inverse instance +
// RX forward instance), or the behavioral inverse stub under iverilog.
// AXI-Stream tready is honored end to end (the RX back-pressures the TX
// via s_ready, and the demod output is back-pressured by m_ready).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_rx_loop_tb;
    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer NUM_SYN  = 2;
    localparam integer NUM_DATA = 12;
    localparam integer NPIL     = 32;
    localparam integer NDATA_SC = 221;
    localparam integer BPC_MAX  = 8;
    localparam integer NBEATS   = NUM_DATA*NDATA_SC;   // 2652 data carriers
    localparam integer NPLT     = NUM_DATA*NPIL;       // 384 pilots

    // ---- runtime modulation select : +MOD=<0|1|2|3> (default 1=16QAM) ----
    integer MOD;
    integer K;                                         // bits/axis
    integer BPS;                                       // bits/sym = 2*K
    integer NBITS;                                     // NBEATS*BPS
    reg [1:0] mod_sel;
    reg [1023:0] gdir;                                 // per-mod golden dir

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
        .s_valid(tx_m_valid), .s_ready(rx_s_ready), .s_tdata(tx_m_tdata),
        .pilot_tdata(rx_pilot_tdata), .pilot_tready(rx_pilot_tready),
        .m_valid(rx_m_valid), .m_ready(rx_m_ready),
        .m_bits(rx_m_bits), .m_last(rx_m_last), .m_user(rx_m_user)
    );

    // TX master <-> RX slave handshake (identity channel)
    assign tx_m_ready = rx_s_ready;

    // ---- pilot ROM (shared by TX + RX, symbol-major z*32+p) ----
    reg [31:0] plt_mem [0:NPLT-1];
    initial $readmemh("golden/rx_downstream/pilot_rom.hex", plt_mem);
    // TX : addressed read (z_map*32 + p)
    always @(*) tx_pilot_tdata = plt_mem[tx_pilot_addr];
    // RX : streamed (advance on pilot_tready)
    integer plt_ptr;
    always @(*) rx_pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!rst_n) plt_ptr <= 0;
        else if (rx_pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- per-mod data bits : golden/rx_downstream/<mod>/tx_data_bits_bpc8.txt
    //      (12 lines x NDATA_SC*8 chars : 8 bits/carrier, low BPS used, the
    //      first BPS bits = [I-sign I-gray.. Q-sign Q-gray..] MSB-first.) ----
    reg [7:0] cbits [0:NUM_DATA*NDATA_SC*8-1];   // raw 8-bit/carrier chars
    reg [7:0] txbit [0:NBEATS*BPC_MAX-1];        // active bits/carrier, file order
    reg [7:0] rxbit [0:NBEATS*BPC_MAX-1];
    integer fbits, c, di, b, z, n;
    reg pa_ok;
    initial begin
        // resolve modulation from +MOD plusarg (default 1 = 16-QAM).
        // NOTE: read the plusarg into a temp FIRST, then derive everything,
        // so K/BPS/NBITS always track the resolved MOD value.
        MOD = 1;
        pa_ok = $value$plusargs("MOD=%d", MOD);
        if (pa_ok === 1'bx) MOD = 1;     // (use pa_ok so it is not optimized away)
        mod_sel = MOD[1:0];
        K   = MOD + 1;
        BPS = 2*K;
        NBITS = NBEATS*BPS;
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

        // pack flat TX bus (BPC_MAX bits/carrier) + remember active bits/carrier
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

    // ---- collect RX bits.  m_bits packs the symbol MSB-FIRST in the low BPS
    //      bits (I axis high K, Q axis low K, sign = axis MSB); the file bit
    //      order is also MSB-first, so file-bit b maps to m_bits[BPS-1-b]. ----
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
            $display("TXRX_LOOP: FAIL"); $display("RESULT: FAIL"); $finish;
        end
        errors = 0;
        for (n = 0; n < NBEATS; n = n + 1)
            for (b = 0; b < BPS; b = b + 1)
                if (rxbit[n*BPC_MAX + b] !== txbit[n*BPC_MAX + b]) errors = errors + 1;
        $display("==================================================");
        $display(" TX -> RX LOOP self-check (end-to-end)  MOD=%0d (BPS=%0d)", MOD, BPS);
        $display("   data carriers    = %0d (exp %0d)", rx_cnt, NBEATS);
        $display("   total bits       = %0d", NBITS);
        $display("   bit errors       = %0d", errors);
        $display("   BER              = %0d / %0d", errors, NBITS);
        $display("   first-bit cycle  = %0d", first_bit_cyc);
        $display("   total run cycle  = %0d", cyc);
        if (rx_cnt == NBEATS && errors == 0) begin
            $display("TXRX_LOOP: PASS  (BER = 0 -- RTL TX demodulates to 0 errors through the RX)");
            $display("RESULT: PASS");
        end else begin
            $display("TXRX_LOOP: FAIL  (BER != 0)");
            $display("RESULT: FAIL");
        end
        $display("==================================================");
        $finish;
    end

    initial begin #80_000_000; $display("FATAL: global timeout"); $display("TXRX_LOOP: FAIL"); $display("RESULT: FAIL"); $finish; end
endmodule
`default_nettype wire
