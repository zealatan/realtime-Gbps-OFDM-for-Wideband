// =====================================================================
// tx_subcarrier_map_tb.sv
// ---------------------------------------------------------------------
// Self-checking TB for tx_subcarrier_map (16-QAM map + pilot insert +
// subcarrier assembly + fftshift).  Drives the 12 data symbols' data
// bits (golden/tx/tx_data_bits.txt) and the pilot ROM
// (golden/rx_downstream/pilot_rom.hex), and compares the 12*256 emitted
// spectrum bins (fftshift order) against golden/tx/tx_spec_in.hex.
//
// This stage is pure integer mapping/placement -> EXACT match expected
// (TOL = 0).  Exercises m_ready back-pressure.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_subcarrier_map_tb;
    localparam integer NSC      = 256;
    localparam integer NPIL     = 32;
    localparam integer NDATA_SC = 221;
    localparam integer NUM_DATA = 12;
    localparam integer NBINS    = NUM_DATA*NSC;     // 3072
    localparam integer NBITS    = NDATA_SC*4;       // 884

    reg clk = 1'b0; always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg          sym_start;
    reg  [NBITS-1:0] data_bits;
    wire [4:0]   pilot_addr;
    reg  [31:0]  pilot_tdata;
    wire         m_valid;
    reg          m_ready;
    wire [31:0]  m_tdata;
    wire         m_last;

    tx_subcarrier_map #(
        .DATA_W(16), .NSC(256), .NPIL(32), .NDATA_SC(221),
        .Q16_1(1610), .Q16_3(4829),
        .SPECMAP("rtl/tx_rom/tx_specmap.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .sym_start(sym_start), .data_bits(data_bits),
        .pilot_addr(pilot_addr), .pilot_tdata(pilot_tdata),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_tdata(m_tdata), .m_last(m_last)
    );

    // current symbol index being driven (for pilot ROM addressing)
    integer cur_z;

    // ---- golden ----
    reg [31:0] gold_mem  [0:NBINS-1];
    reg [31:0] pilot_mem [0:NUM_DATA*NPIL-1];   // 384 pilot words
    // data bits : 12 lines x 884 ASCII '0'/'1'
    reg [7:0]  bit_chars [0:NUM_DATA*NBITS-1];
    integer fbits, c, idx, di;

    initial begin
        $readmemh("golden/tx/tx_spec_in.hex",        gold_mem);
        $readmemh("golden/rx_downstream/pilot_rom.hex", pilot_mem);
        // read tx_data_bits.txt as a stream of '0'/'1' (skip newlines)
        fbits = $fopen("golden/tx/tx_data_bits.txt", "r");
        if (fbits == 0) begin $display("RESULT: FAIL (no tx_data_bits.txt)"); $finish; end
        di = 0;
        while (!$feof(fbits) && di < NUM_DATA*NBITS) begin
            c = $fgetc(fbits);
            if (c == "0" || c == "1") begin
                bit_chars[di] = c[7:0];
                di = di + 1;
            end
        end
        $fclose(fbits);
    end

    // build the 884-bit bus for symbol z (bit 4*k+b)
    integer b;
    task load_bits_for;
        input integer z;
        begin
            for (b = 0; b < NBITS; b = b + 1)
                data_bits[b] = (bit_chars[z*NBITS + b] == "1");
        end
    endtask

    // pilot ROM addressed by {symbol, pilot index}
    always @(*) pilot_tdata = pilot_mem[cur_z*NPIL + pilot_addr];

    // collect output
    integer out_cnt;
    reg [31:0] got_mem [0:NBINS-1];
    initial out_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            if (out_cnt < NBINS) got_mem[out_cnt] <= m_tdata;
            out_cnt <= out_cnt + 1;
        end
    end

    // m_ready back-pressure ~80%
    integer rseed = 32'hC0FFEE;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(rseed) % 5) != 0;
    end

    // ---- drive: 12 symbols ----
    integer z;
    initial begin
        sym_start = 1'b0; data_bits = {NBITS{1'b0}};
        rst_n = 1'b0; m_ready = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        cur_z = 0;
        for (z = 0; z < NUM_DATA; z = z + 1) begin
            cur_z = z;
            load_bits_for(z);
            // wait until DUT idle (m_valid low) before starting next symbol
            while (m_valid) @(posedge clk);
            sym_start <= 1'b1;
            @(posedge clk);
            sym_start <= 1'b0;
            // wait for this symbol's last bin to be accepted
            @(posedge clk);
            while (!(m_valid && m_ready && m_last)) @(posedge clk);
            @(posedge clk);
        end
    end

    // ---- finish + compare ----
    integer i, gi, gq, ri, rq, ei, eq, maxerr, errcnt, timeout;
    reg signed [15:0] g16i, g16q, r16i, r16q;
    initial begin
        timeout = 0;
        wait (rst_n);
        while (out_cnt < NBINS && timeout < 4_000_000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        if (out_cnt < NBINS) begin
            $display("FATAL: collected %0d bins, expected %0d", out_cnt, NBINS);
            $display("RESULT: FAIL"); $finish;
        end
        maxerr = 0; errcnt = 0;
        for (i = 0; i < NBINS; i = i + 1) begin
            g16i = gold_mem[i][15:0]; g16q = gold_mem[i][31:16];
            r16i = got_mem[i][15:0];  r16q = got_mem[i][31:16];
            gi = g16i; gq = g16q; ri = r16i; rq = r16q;
            ei = (ri>gi)?(ri-gi):(gi-ri);
            eq = (rq>gq)?(rq-gq):(gq-rq);
            if (ei>maxerr) maxerr=ei; if (eq>maxerr) maxerr=eq;
            if (ei!=0 || eq!=0) begin
                errcnt = errcnt + 1;
                if (errcnt<=10)
                    $display("  MISMATCH bin %0d (sym %0d k %0d): got(%0d,%0d) gold(%0d,%0d)",
                             i, i/NSC, i%NSC, ri, rq, gi, gq);
            end
        end
        $display("==================================================");
        $display(" tx_subcarrier_map self-check");
        $display("   bins collected = %0d / %0d", out_cnt, NBINS);
        $display("   max abs err    = %0d (LSB)", maxerr);
        $display("   bins mismatch  = %0d", errcnt);
        if (out_cnt==NBINS && errcnt==0)
            $display("RESULT: PASS  (all %0d spectrum bins EXACT vs tx_spec_in.hex)", NBINS);
        else
            $display("RESULT: FAIL  (%0d mismatches, max err %0d)", errcnt, maxerr);
        $display("==================================================");
        $finish;
    end

    initial begin #30_000_000; $display("FATAL: global timeout"); $display("RESULT: FAIL"); $finish; end
endmodule
`default_nettype wire
