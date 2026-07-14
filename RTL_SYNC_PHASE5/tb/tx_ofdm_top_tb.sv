// =====================================================================
// tx_ofdm_top_tb.sv
// ---------------------------------------------------------------------
// Self-checking TB for tx_ofdm_top (the full OFDM transmitter).  Drives
// the 12 data symbols' data bits (golden/tx/tx_data_bits.txt) + the
// pilot ROM (golden/rx_downstream/pilot_rom.hex), collects the 4032-
// sample transmit slot and compares against golden/tx/tx_slot_4032.hex
// (= golden/rx_downstream/tx_slot_iq_4032.hex).
//
//   * sync region (samples 0..575)   : EXACT (byte-identical ROM copy)
//   * data region  (samples 576..4031): within TOL LSB (IFFT BFP budget)
//
// Exercises m_ready back-pressure.  Works with the REAL xfft_N IP (xsim)
// or the inverse stub (iverilog).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_ofdm_top_tb;
    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer NUM_SYN  = 2;
    localparam integer NUM_DATA = 12;
    localparam integer NPIL     = 32;
    localparam integer NDATA_SC = 221;
    localparam integer NBITS    = NDATA_SC*4;                 // 884
    localparam integer SYNC_LEN = NUM_SYN*(NSC+CP_LEN);       // 576
    localparam integer SLOT_LEN = (NUM_SYN+NUM_DATA)*(NSC+CP_LEN); // 4032
    localparam integer TOL      = 64;

    reg clk = 1'b0; always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg          start;
    wire         busy;
    reg  [NUM_DATA*NBITS-1:0] data_bits_flat;
    wire [8:0]   pilot_addr;
    reg  [31:0]  pilot_tdata;
    wire         m_valid;
    reg          m_ready;
    wire [31:0]  m_tdata;
    wire         m_last;

    tx_ofdm_top #(
        .DATA_W(16), .NSC(256), .CP_LEN(32), .NUM_SYN(2), .NUM_DATA(12),
        .NPIL(32), .NDATA_SC(221), .Q16_1(1610), .Q16_3(4829),
        .SPECMAP("rtl/tx_rom/tx_specmap.hex"),
        .SYNC_ROM("rtl/tx_rom/tx_sync_rom.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .busy(busy),
        .data_bits_flat(data_bits_flat),
        .pilot_addr(pilot_addr), .pilot_tdata(pilot_tdata),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_tdata(m_tdata), .m_last(m_last)
    );

    // ---- golden + pilot ROM + data bits ----
    reg [31:0] gold_mem  [0:SLOT_LEN-1];
    reg [31:0] pilot_mem [0:NUM_DATA*NPIL-1];
    reg [7:0]  bit_chars [0:NUM_DATA*NBITS-1];
    integer fbits, c, di, b, z;

    initial begin
        $readmemh("golden/tx/tx_slot_4032.hex",         gold_mem);
        $readmemh("golden/rx_downstream/pilot_rom.hex", pilot_mem);
        fbits = $fopen("golden/tx/tx_data_bits.txt", "r");
        if (fbits == 0) begin $display("RESULT: FAIL (no tx_data_bits.txt)"); $finish; end
        di = 0;
        while (!$feof(fbits) && di < NUM_DATA*NBITS) begin
            c = $fgetc(fbits);
            if (c == "0" || c == "1") begin bit_chars[di] = c[7:0]; di = di + 1; end
        end
        $fclose(fbits);
        // pack flat bit bus: bit (z*884 + k4 ...) order matches top's window
        for (z = 0; z < NUM_DATA; z = z + 1)
            for (b = 0; b < NBITS; b = b + 1)
                data_bits_flat[z*NBITS + b] = (bit_chars[z*NBITS + b] == "1");
    end

    // pilot ROM addressed read
    always @(*) pilot_tdata = pilot_mem[pilot_addr];

    // ---- m_ready back-pressure ~80% ----
    integer rseed = 32'hABCD12;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(rseed) % 5) != 0;
    end

    // ---- collect slot ----
    integer out_cnt;
    reg [31:0] got_mem [0:SLOT_LEN-1];
    initial out_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            if (out_cnt < SLOT_LEN) got_mem[out_cnt] <= m_tdata;
            out_cnt <= out_cnt + 1;
        end
    end

    // ---- drive ----
    initial begin
        start = 1'b0; m_ready = 1'b0; rst_n = 1'b0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;
    end

    // ---- finish + compare ----
    integer i, gi, gq, ri, rq, ei, eq, maxerr, errcnt, syncerr, timeout;
    reg signed [15:0] g16i, g16q, r16i, r16q;
    initial begin
        timeout = 0;
        wait (rst_n);
        @(posedge clk);
        while (out_cnt < SLOT_LEN && timeout < 6_000_000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        if (out_cnt < SLOT_LEN) begin
            $display("FATAL: collected %0d / %0d slot samples", out_cnt, SLOT_LEN);
            $display("RESULT: FAIL"); $finish;
        end
        maxerr = 0; errcnt = 0; syncerr = 0;
        for (i = 0; i < SLOT_LEN; i = i + 1) begin
            g16i = gold_mem[i][15:0]; g16q = gold_mem[i][31:16];
            r16i = got_mem[i][15:0];  r16q = got_mem[i][31:16];
            gi=g16i; gq=g16q; ri=r16i; rq=r16q;
            ei = (ri>gi)?(ri-gi):(gi-ri);
            eq = (rq>gq)?(rq-gq):(gq-rq);
            if (ei>maxerr) maxerr=ei; if (eq>maxerr) maxerr=eq;
            if (i < SYNC_LEN) begin
                if (ei!=0 || eq!=0) begin
                    syncerr = syncerr + 1;
                    if (syncerr<=5)
                        $display("  SYNC MISMATCH samp %0d: got(%0d,%0d) gold(%0d,%0d)", i, ri,rq,gi,gq);
                end
            end else begin
                if (ei>TOL || eq>TOL) begin
                    errcnt = errcnt + 1;
                    if (errcnt<=10)
                        $display("  DATA MISMATCH samp %0d (sym %0d): got(%0d,%0d) gold(%0d,%0d) err(%0d,%0d)",
                                 i, (i-SYNC_LEN)/288, ri,rq,gi,gq,ei,eq);
                end
            end
        end
        $display("==================================================");
        $display(" tx_ofdm_top self-check (full 4032 slot)");
        $display("   samples collected   = %0d / %0d", out_cnt, SLOT_LEN);
        $display("   sync region exact?   %0d mismatches (must be 0)", syncerr);
        $display("   data region tol=%0d : %0d over tol", TOL, errcnt);
        $display("   max abs err (LSB)   = %0d", maxerr);
        if (out_cnt==SLOT_LEN && syncerr==0 && errcnt==0)
            $display("RESULT: PASS  (sync EXACT, %0d data samples within %0d LSB, max err %0d)",
                     SLOT_LEN-SYNC_LEN, TOL, maxerr);
        else
            $display("RESULT: FAIL  (sync_err=%0d data_err=%0d max %0d)", syncerr, errcnt, maxerr);
        $display("==================================================");
        $finish;
    end

    initial begin #60_000_000; $display("FATAL: global timeout"); $display("RESULT: FAIL"); $finish; end
endmodule
`default_nettype wire
