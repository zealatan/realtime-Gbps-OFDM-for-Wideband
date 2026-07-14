// =====================================================================
// rx_fft_frontend_tb.sv
// ---------------------------------------------------------------------
// Self-checking TB for rx_fft_frontend (FFT front-end of the OFDM RX
// downstream chain).
//
//  * Loads golden/rx_downstream/tx_slot_iq_4032.hex (4032 lines, each a
//    32-bit word {Q[31:16],I[15:0]} Q15) = the synchronizer's corrected
//    M_AXIS, beat0 = PSS CP start. Streams it into the DUT 1 complex
//    sample/clock with pseudo-random s_valid gaps AND m_ready stalls, so
//    AXI-Stream tready is exercised in both directions.
//  * Collects the 12*256 = 3072 output freq bins (fftshift order, symbol
//    major) and compares against golden/rx_downstream/fft_out.hex.
//  * Because the real xfft uses block-floating-point with truncation,
//    a few-LSB error vs the golden Q15 view is expected. PASS requires
//    every bin within TOL LSB on BOTH I and Q, and reports max error.
//
//  Works with the REAL xfft_N IP (xsim) or the behavioral stub
//  tb/xfft_N_bfp_stub.v (iverilog). Same gate string either way.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_fft_frontend_tb;

    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer NUM_SYN  = 2;
    localparam integer NUM_DATA = 12;
    localparam integer SLOT_LEN = (NUM_SYN + NUM_DATA)*(NSC+CP_LEN); // 4032
    localparam integer NBINS    = NUM_DATA * NSC;                    // 3072

    // Per-bin tolerance (LSB) on I and Q vs the golden Q15 hex view.
    // BFP truncation in the IP -> a handful of LSB; 64 is generous head-
    // room while still catching any real ordering/scale/shift bug (golden
    // bin magnitudes run to ~6800 LSB, so 64 is < 1%).
    localparam integer TOL = 64;

    // ---- clock / reset ----
    reg clk = 1'b0;
    always #5 clk = ~clk;           // 100 MHz functional clock
    reg rst_n = 1'b0;

    // ---- DUT wiring ----
    reg          s_valid;
    wire         s_ready;
    reg  [31:0]  s_tdata;

    wire         m_valid;
    reg          m_ready;
    wire [31:0]  m_tdata;
    wire         m_last;

    rx_fft_frontend #(
        .DATA_W(16), .NSC(256), .CP_LEN(32),
        .NUM_SYN(2), .NUM_DATA(12), .SCALE_SH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_tdata(s_tdata),
        .m_valid(m_valid), .m_ready(m_ready), .m_tdata(m_tdata), .m_last(m_last)
    );

    // ---- golden storage ----
    reg [31:0] slot_mem [0:SLOT_LEN-1];
    reg [31:0] gold_mem [0:NBINS-1];

    initial begin
        $readmemh("golden/rx_downstream/tx_slot_iq_4032.hex", slot_mem);
        $readmemh("golden/rx_downstream/fft_out.hex",          gold_mem);
    end

    // ---------------------------------------------------------------
    // stimulus: stream the 4032-sample slot with random valid gaps
    // ---------------------------------------------------------------
    integer in_idx;
    integer vseed = 32'hBEEF1234;
    initial begin
        s_valid = 1'b0; s_tdata = 32'd0;
        m_ready = 1'b0;
        rst_n   = 1'b0;
        repeat (8) @(posedge clk);
        rst_n   = 1'b1;
        @(posedge clk);

        in_idx = 0;
        while (in_idx < SLOT_LEN) begin
            // randomly insert idle (valid low) cycles ~20%
            if (($random(vseed) % 5) == 0) begin
                s_valid <= 1'b0;
                @(posedge clk);
            end else begin
                s_valid <= 1'b1;
                s_tdata <= slot_mem[in_idx];
                @(posedge clk);
                if (s_valid && s_ready)
                    in_idx = in_idx + 1;
            end
        end
        s_valid <= 1'b0;
    end

    // ---------------------------------------------------------------
    // m_ready back-pressure (pseudo-random ~75% ready)
    // ---------------------------------------------------------------
    integer rseed = 32'h0FACADE;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(rseed) % 4) != 0;
    end

    // ---------------------------------------------------------------
    // collect output bins
    // ---------------------------------------------------------------
    integer out_cnt;
    reg [31:0] got_mem [0:NBINS-1];
    initial out_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            if (out_cnt < NBINS) got_mem[out_cnt] <= m_tdata;
            out_cnt <= out_cnt + 1;
        end
    end

    // ---------------------------------------------------------------
    // finish + compare
    // ---------------------------------------------------------------
    integer i;
    integer gi, gq, ri, rq, ei, eq;
    integer maxerr, errcnt;
    integer timeout;
    reg signed [15:0] gi16, gq16, ri16, rq16;

    initial begin
        timeout = 0;
        wait (rst_n);
        while (out_cnt < NBINS && timeout < 2_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);

        if (out_cnt < NBINS) begin
            $display("FATAL: collected %0d bins, expected %0d (timeout)",
                     out_cnt, NBINS);
            $display("RESULT: FAIL");
            $finish;
        end

        maxerr = 0; errcnt = 0;
        for (i = 0; i < NBINS; i = i + 1) begin
            gi16 = gold_mem[i][15:0];   gq16 = gold_mem[i][31:16];
            ri16 = got_mem[i][15:0];    rq16 = got_mem[i][31:16];
            gi = gi16; gq = gq16; ri = ri16; rq = rq16;
            ei = (ri > gi) ? (ri - gi) : (gi - ri);
            eq = (rq > gq) ? (rq - gq) : (gq - rq);
            if (ei > maxerr) maxerr = ei;
            if (eq > maxerr) maxerr = eq;
            if (ei > TOL || eq > TOL) begin
                errcnt = errcnt + 1;
                if (errcnt <= 10)
                    $display("  MISMATCH bin %0d (sym %0d k %0d): got(%0d,%0d) gold(%0d,%0d) err(%0d,%0d)",
                             i, i/NSC, i%NSC, ri, rq, gi, gq, ei, eq);
            end
        end

        $display("==================================================");
        $display(" rx_fft_frontend self-check");
        $display("   bins collected     = %0d / %0d", out_cnt, NBINS);
        $display("   per-bin tol (LSB)  = %0d", TOL);
        $display("   max abs err (LSB)  = %0d", maxerr);
        $display("   bins over tol      = %0d", errcnt);
        if (out_cnt == NBINS && errcnt == 0)
            $display("RESULT: PASS  (all %0d bins within %0d LSB of golden fft_out.hex, max err %0d)",
                     NBINS, TOL, maxerr);
        else
            $display("RESULT: FAIL  (%0d bins exceed tol, max err %0d)", errcnt, maxerr);
        $display("==================================================");
        $finish;
    end

    // global watchdog
    initial begin
        #20_000_000;
        $display("FATAL: global timeout");
        $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
