// =====================================================================
// tx_ifft_frontend_tb.sv
// ---------------------------------------------------------------------
// Self-checking TB for tx_ifft_frontend (256-pt IDFT via xfft_N inverse
// + BFP recover + CP insert).  Streams the 12 data symbols' spectrum
// (golden/tx/tx_spec_in.hex, 12*256 fftshift-ordered bins) into the DUT
// with random s_valid gaps + m_ready stalls, collects the 12*288 output
// time samples (CP+body) and compares against golden/tx/tx_dsym_out.hex
// (= the data region of golden tx_slot_iq_4032.hex).
//
// Block-floating-point truncation in the IFFT IP -> a few-LSB error vs
// the golden Q15 view.  PASS requires every sample within TOL LSB on
// BOTH I and Q.  Works with the REAL xfft_N IP (xsim) or the behavioral
// inverse stub tb/xfft_N_ifft_bfp_stub.v (iverilog).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_ifft_frontend_tb;
    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer SYM_LEN  = NSC + CP_LEN;     // 288
    localparam integer NUM_DATA = 12;
    localparam integer NSPEC    = NUM_DATA*NSC;     // 3072 input bins
    localparam integer NOUT     = NUM_DATA*SYM_LEN; // 3456 output samples
    localparam integer TOL      = 64;               // BFP truncation budget

    reg clk = 1'b0; always #5 clk = ~clk;
    reg rst_n = 1'b0;

    reg          s_valid;
    wire         s_ready;
    reg  [31:0]  s_tdata;
    reg          s_last;
    wire         m_valid;
    reg          m_ready;
    wire [31:0]  m_tdata;
    wire         m_last;

    tx_ifft_frontend #(
        .DATA_W(16), .NSC(256), .CP_LEN(32), .SCALE_SH(4)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_tdata(s_tdata), .s_last(s_last),
        .m_valid(m_valid), .m_ready(m_ready), .m_tdata(m_tdata), .m_last(m_last)
    );

    reg [31:0] spec_mem [0:NSPEC-1];
    reg [31:0] gold_mem [0:NOUT-1];
    initial begin
        $readmemh("golden/tx/tx_spec_in.hex",  spec_mem);
        $readmemh("golden/tx/tx_dsym_out.hex", gold_mem);
    end

    // ---- stimulus: stream 3072 spectrum bins, s_last on each 256th ----
    integer in_idx;
    integer vseed = 32'h1234BEEF;
    initial begin
        s_valid = 1'b0; s_tdata = 32'd0; s_last = 1'b0; m_ready = 1'b0;
        rst_n = 1'b0;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        in_idx = 0;
        while (in_idx < NSPEC) begin
            if (($random(vseed) % 5) == 0) begin
                s_valid <= 1'b0;
                @(posedge clk);
            end else begin
                s_valid <= 1'b1;
                s_tdata <= spec_mem[in_idx];
                s_last  <= ((in_idx % NSC) == NSC-1);
                @(posedge clk);
                if (s_valid && s_ready) in_idx = in_idx + 1;
            end
        end
        s_valid <= 1'b0; s_last <= 1'b0;
    end

    // ---- m_ready back-pressure ~75% ----
    integer rseed = 32'hFACADE0;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(rseed) % 4) != 0;
    end

    // ---- collect output ----
    integer out_cnt;
    reg [31:0] got_mem [0:NOUT-1];
    initial out_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            if (out_cnt < NOUT) got_mem[out_cnt] <= m_tdata;
            out_cnt <= out_cnt + 1;
        end
    end

    // ---- finish + compare ----
    integer i, gi, gq, ri, rq, ei, eq, maxerr, errcnt, timeout;
    reg signed [15:0] g16i, g16q, r16i, r16q;
    initial begin
        timeout = 0;
        wait (rst_n);
        while (out_cnt < NOUT && timeout < 4_000_000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);
        if (out_cnt < NOUT) begin
            $display("FATAL: collected %0d samples, expected %0d", out_cnt, NOUT);
            $display("RESULT: FAIL"); $finish;
        end
        maxerr = 0; errcnt = 0;
        for (i = 0; i < NOUT; i = i + 1) begin
            g16i = gold_mem[i][15:0]; g16q = gold_mem[i][31:16];
            r16i = got_mem[i][15:0];  r16q = got_mem[i][31:16];
            gi=g16i; gq=g16q; ri=r16i; rq=r16q;
            ei = (ri>gi)?(ri-gi):(gi-ri);
            eq = (rq>gq)?(rq-gq):(gq-rq);
            if (ei>maxerr) maxerr=ei; if (eq>maxerr) maxerr=eq;
            if (ei>TOL || eq>TOL) begin
                errcnt = errcnt + 1;
                if (errcnt<=10)
                    $display("  MISMATCH samp %0d (sym %0d off %0d): got(%0d,%0d) gold(%0d,%0d) err(%0d,%0d)",
                             i, i/SYM_LEN, i%SYM_LEN, ri, rq, gi, gq, ei, eq);
            end
        end
        $display("==================================================");
        $display(" tx_ifft_frontend self-check");
        $display("   samples collected = %0d / %0d", out_cnt, NOUT);
        $display("   per-samp tol (LSB) = %0d", TOL);
        $display("   max abs err (LSB)  = %0d", maxerr);
        $display("   samples over tol   = %0d", errcnt);
        if (out_cnt==NOUT && errcnt==0)
            $display("RESULT: PASS  (all %0d samples within %0d LSB of tx_dsym_out.hex, max err %0d)",
                     NOUT, TOL, maxerr);
        else
            $display("RESULT: FAIL  (%0d samples exceed tol, max err %0d)", errcnt, maxerr);
        $display("==================================================");
        $finish;
    end

    initial begin #40_000_000; $display("FATAL: global timeout"); $display("RESULT: FAIL"); $finish; end
endmodule
`default_nettype wire
