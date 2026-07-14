// ============================================================================
// rx_ch_est_tb.sv  --  self-checking TB for rx_ch_est (CE + interp_fft)
//
// Loads golden/rx_downstream/fft_out.hex (12x256 freq-domain symbols) and
// pilot_rom.hex (12x32 QPSK pilots), drives the DUT one complex sample/clock
// (with AXIS backpressure toggling), captures M_AXIS H[k], and compares to
// golden hest.hex (12x256). Reports per-symbol and global max abs error.
//
// PASS criterion: max abs error per I/Q component <= ERR_TOL LSB.  The golden
// hest.hex is itself a float->Q15 rounding of the reference; the fused fixed-
// point datapath reproduces it to ~2-3 LSB (predicted offline). ERR_TOL=4.
// ============================================================================
`timescale 1ns/1ps

module rx_ch_est_tb #(
    parameter W_ROM       = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    parameter W_RECIP_ROM = "golden/rx_downstream/ce_pilot_recip.hex"
);
    localparam integer NSC   = 256;
    localparam integer NP    = 32;
    localparam integer NSYM  = 12;
    localparam integer ERR_TOL = 4;

    // Golden dir: overridable via +GOLD=<path> (default = relative).
    string GOLD;
    initial if (!$value$plusargs("GOLD=%s", GOLD)) GOLD = "golden/rx_downstream";

    // ---- clock / reset ----
    reg clk = 0; always #2 clk = ~clk;   // 250 MHz
    reg rst_n = 0;

    // ---- golden memories ----
    reg [31:0] fft_mem  [0:NSC*NSYM-1];
    reg [31:0] plt_mem  [0:NP*NSYM-1];
    reg [31:0] hest_mem [0:NSC*NSYM-1];

    // ---- DUT I/O ----
    reg  [31:0] s_tdata;  reg s_tvalid; wire s_tready; reg s_tlast;
    reg  [31:0] plt_tdata; wire plt_tready;
    wire [31:0] m_tdata;  wire m_tvalid; reg m_tready; wire m_tlast;

    rx_ch_est #(.NSC(NSC), .NUM_PILOTS(NP), .NUM_DATA(NSYM),
                .W_ROM(W_ROM), .W_RECIP_ROM(W_RECIP_ROM)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .pilot_tdata(plt_tdata), .pilot_tready(plt_tready),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .m_axis_tlast(m_tlast)
    );

    // ---- pilot ROM feeder : present plt_mem[plt_ptr]; advance on plt_tready ----
    integer plt_ptr;
    always @(*) plt_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!rst_n) plt_ptr <= 0;
        else if (plt_tready && plt_ptr < NP*NSYM-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- signed helpers ----
    function signed [15:0] lo16(input [31:0] w); lo16 = w[15:0];  endfunction
    function signed [15:0] hi16(input [31:0] w); hi16 = w[31:16]; endfunction
    function integer iabs(input integer v); iabs = (v<0)? -v : v; endfunction

    // ---- input driver ----
    // index of the NEXT beat to deliver (0 .. NSC*NSYM-1). Data and tlast are
    // driven *combinationally* from this index so they always match. tvalid is
    // pulsed/dropped with a pseudo-random bubble; the index only advances on an
    // accepted beat (tvalid & tready). This decouples backpressure from data.
    integer in_idx;
    reg     driving_done;
    reg     bubble;
    integer seed = 32'hC0FFEE;

    wire [31:0] cur_data = fft_mem[in_idx];
    wire        cur_last = ((in_idx % NSC) == NSC-1);

    always @(*) begin
        s_tdata  = cur_data;
        s_tlast  = cur_last & ~driving_done;
        s_tvalid = ~driving_done & ~bubble;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            in_idx<=0; driving_done<=0; bubble<=0;
        end else if (!driving_done) begin
            // pick a fresh bubble decision each cycle a beat could start
            if (s_tvalid && s_tready) begin
                if (in_idx==NSC*NSYM-1) driving_done<=1;
                else                    in_idx<=in_idx+1;
            end
            bubble <= (($random(seed) % 5) == 0);
        end
    end

    // ---- output capture + check ----
    integer out_sym, out_bin;
    integer errI, errQ, maxerr, symerr;
    integer total_beats;
    integer g_idx;
    reg signed [15:0] got_i, got_q, exp_i, exp_q;
    integer fails;

    // random backpressure on M_AXIS
    integer seed2 = 32'hBEEF;
    always @(posedge clk) begin
        if (!rst_n) m_tready <= 0;
        else        m_tready <= (($random(seed2) % 4) != 0);
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            out_sym<=0; out_bin<=0; maxerr<=0; total_beats<=0; fails<=0; symerr<=0;
        end else if (m_tvalid && m_tready) begin
            g_idx = out_sym*NSC + out_bin;
            got_i = lo16(m_tdata);  got_q = hi16(m_tdata);
            exp_i = lo16(hest_mem[g_idx]); exp_q = hi16(hest_mem[g_idx]);
            errI = iabs(got_i - exp_i);
            errQ = iabs(got_q - exp_q);
            if (errI>maxerr) maxerr<=errI;
            if (errQ>maxerr) maxerr<=errQ;
            if (errI>symerr) symerr<=errI;
            if (errQ>symerr) symerr<=errQ;
            if (errI>ERR_TOL || errQ>ERR_TOL) begin
                fails <= fails+1;
                if (fails < 20)
                  $display("  MISMATCH sym=%0d bin=%0d got=(%0d,%0d) exp=(%0d,%0d) err=(%0d,%0d)",
                           out_sym,out_bin,got_i,got_q,exp_i,exp_q,errI,errQ);
            end
            total_beats <= total_beats+1;
            // tlast must coincide with bin 255
            if (m_tlast !== (out_bin==NSC-1))
                $display("  TLAST ERROR sym=%0d bin=%0d tlast=%b",out_sym,out_bin,m_tlast);
            if (out_bin==NSC-1) begin
                $display("  symbol %0d done: max|err| this sym = %0d LSB", out_sym, symerr);
                symerr<=0;
                out_bin<=0;
                out_sym<=out_sym+1;
            end else out_bin<=out_bin+1;
        end
    end

    // ---- run ----
    initial begin
        $readmemh({GOLD,"/fft_out.hex"},  fft_mem);
        $readmemh({GOLD,"/pilot_rom.hex"},plt_mem);
        $readmemh({GOLD,"/hest.hex"},     hest_mem);
        s_tvalid=0; s_tlast=0; m_tready=0;
        rst_n=0; repeat(8) @(posedge clk); rst_n=1;

        // wait for all 12 symbols out, or timeout
        wait (out_sym==NSYM);
        repeat(20) @(posedge clk);

        $display("============================================================");
        $display("rx_ch_est_tb RESULTS");
        $display("  symbols checked : %0d / %0d", out_sym, NSYM);
        $display("  beats checked   : %0d (expect %0d)", total_beats, NSC*NSYM);
        $display("  global max|err| : %0d LSB (tol %0d)", maxerr, ERR_TOL);
        $display("  mismatches      : %0d", fails);
        if (out_sym==NSYM && total_beats==NSC*NSYM && fails==0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("============================================================");
        $finish;
    end

    // global timeout
    initial begin
        #2000000;
        $display("TIMEOUT: out_sym=%0d beats=%0d",out_sym,total_beats);
        $display("CI GATE: FAILED");
        $finish;
    end
endmodule
