// =====================================================================
// rx_demod_16qam_tb.sv
// ---------------------------------------------------------------------
// Self-checking TB for rx_demod_16qam.
//
//  * Loads golden/rx_downstream/eq_out.hex (12*221 = 2652 lines, each a
//    32-bit word {Q[31:16],I[15:0]} Q15) and streams it into the DUT,
//    1 complex sample/clock, exercising tready back-pressure.
//  * Collects the 4-bit/beat demod output, packs to a bit string per
//    symbol (884 bits) in the SAME order the reference uses
//    ([b0 b1 b2 b3] per carrier, carriers in dataIndx order).
//  * Compares against golden/rx_downstream/tx_bits.txt (== rx_bits.txt)
//    and reports BER. PASS requires BER == 0 / 10608.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_demod_16qam_tb;

    localparam integer NSYM     = 12;
    localparam integer NDATA_SC = 221;
    localparam integer NBEATS   = NSYM * NDATA_SC;   // 2652
    localparam integer NBITS    = NBEATS * 4;        // 10608
    localparam integer BITS_PER_SYM = NDATA_SC * 4;  // 884

    // ---- clock / reset ----
    reg clk = 1'b0;
    always #5 clk = ~clk;           // 100 MHz functional clock
    reg rst_n = 1'b0;

    // ---- DUT wiring ----
    reg                 s_valid;
    wire                s_ready;
    reg  signed [15:0]  s_i, s_q;
    reg                 s_last, s_user;

    wire                m_valid;
    reg                 m_ready;
    wire [3:0]          m_bits;
    wire                m_last, m_user;

    rx_demod_16qam #(.DATA_W(16), .THRESH(3220)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_i(s_i), .s_q(s_q), .s_last(s_last), .s_user(s_user),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_bits(m_bits), .m_last(m_last), .m_user(m_user)
    );

    // ---- golden storage ----
    reg [31:0] eq_mem  [0:NBEATS-1];
    reg [7:0]  txbit   [0:NBITS-1];   // '0'/'1' ASCII per data bit

    // collected output bits (one ascii char per bit, in arrival order)
    reg [7:0]  rxbit   [0:NBITS-1];
    integer    rx_cnt;

    integer i;
    integer fd;
    integer ch;

    // ---------------------------------------------------------------
    // load eq_out.hex
    // ---------------------------------------------------------------
    initial begin
        $readmemh("golden/rx_downstream/eq_out.hex", eq_mem);
    end

    // ---------------------------------------------------------------
    // load tx_bits.txt char-by-char ($fgetc is unambiguous re: byte
    // order). Keep only '0'/'1' chars, skipping newlines/whitespace.
    // ---------------------------------------------------------------
    initial begin
        fd = $fopen("golden/rx_downstream/tx_bits.txt", "r");
        if (fd == 0) begin
            $display("FATAL: cannot open tx_bits.txt");
            $finish;
        end
        i  = 0;
        ch = $fgetc(fd);
        while (ch != -1 && i < NBITS) begin
            if (ch == "0" || ch == "1") begin
                txbit[i] = ch[7:0];
                i = i + 1;
            end
            ch = $fgetc(fd);
        end
        $fclose(fd);
        if (i != NBITS)
            $display("WARN: read %0d golden bits, expected %0d", i, NBITS);
    end

    // ---------------------------------------------------------------
    // stimulus: drive eq samples with toggling back-pressure scenarios
    // ---------------------------------------------------------------
    integer in_idx;
    initial begin
        s_valid = 1'b0; s_i = 0; s_q = 0; s_last = 0; s_user = 0;
        m_ready = 1'b0;
        rst_n   = 1'b0;
        repeat (5) @(posedge clk);
        rst_n   = 1'b1;
        @(posedge clk);

        for (in_idx = 0; in_idx < NBEATS; in_idx = in_idx + 1) begin
            s_valid <= 1'b1;
            s_i     <= eq_mem[in_idx][15:0];
            s_q     <= eq_mem[in_idx][31:16];
            // mark symbol boundary on last carrier of each symbol
            s_last  <= ((in_idx % NDATA_SC) == (NDATA_SC-1));
            s_user  <= ((in_idx % NDATA_SC) == 0);  // SOF on first carrier
            // wait for handshake
            @(posedge clk);
            while (!s_ready) @(posedge clk);
        end
        s_valid <= 1'b0;
        s_last  <= 1'b0;
        s_user  <= 1'b0;
    end

    // ---------------------------------------------------------------
    // back-pressure generator on m_ready (pseudo-random stall)
    // ---------------------------------------------------------------
    integer seed = 32'hC0FFEE;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(seed) % 4) != 0;  // ~75% ready
    end

    // ---------------------------------------------------------------
    // collect output bits  (b0 first, then b1,b2,b3)
    // ---------------------------------------------------------------
    initial rx_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            rxbit[rx_cnt*4 + 0] <= (m_bits[3]) ? "1" : "0"; // b0
            rxbit[rx_cnt*4 + 1] <= (m_bits[2]) ? "1" : "0"; // b1
            rxbit[rx_cnt*4 + 2] <= (m_bits[1]) ? "1" : "0"; // b2
            rxbit[rx_cnt*4 + 3] <= (m_bits[0]) ? "1" : "0"; // b3
            rx_cnt <= rx_cnt + 1;
        end
    end

    // ---------------------------------------------------------------
    // finish + compare
    // ---------------------------------------------------------------
    integer errors;
    integer timeout;
    initial begin
        // wait until all beats collected (or timeout)
        timeout = 0;
        wait (rst_n);
        while (rx_cnt < NBEATS && timeout < 200000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);

        if (rx_cnt != NBEATS) begin
            $display("FATAL: collected %0d beats, expected %0d (timeout=%0d)",
                     rx_cnt, NBEATS, timeout);
            $display("RESULT: FAIL");
            $finish;
        end

        errors = 0;
        for (i = 0; i < NBITS; i = i + 1) begin
            if (rxbit[i] !== txbit[i]) errors = errors + 1;
        end

        $display("==================================================");
        $display(" rx_demod_16qam self-check");
        $display("   beats         = %0d", rx_cnt);
        $display("   total bits    = %0d", NBITS);
        $display("   bit errors    = %0d", errors);
        $display("   BER           = %0d / %0d", errors, NBITS);
        $display("   THRESH        = %0d (+/- 2*SCALE16QAM*Q15)", 3220);
        if (errors == 0)
            $display("RESULT: PASS  (BER = 0, matches golden tx_bits.txt)");
        else
            $display("RESULT: FAIL  (BER != 0)");
        $display("==================================================");
        $finish;
    end

    // global watchdog
    initial begin
        #5_000_000;
        $display("FATAL: global timeout");
        $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
