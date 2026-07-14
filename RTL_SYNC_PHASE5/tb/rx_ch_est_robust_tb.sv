// ============================================================================
// rx_ch_est_robust_tb.sv  --  ROBUST self-checking TB for rx_ch_est
//
// Loads golden/rx_ch_est_robust/{fft_out,pilot_rom,hest}.hex (N concatenated
// NON-IDENTITY frequency-selective channel cases: flat/steep/null/multipath +
// jittered QPSK pilots + random 16-QAM data). Drives the DUT one complex
// sample/clock (with AXIS backpressure toggling on BOTH S and M), captures
// M_AXIS H[k], and compares to the reference-model hest golden (computed with
// the IDENTICAL CE + interp_fft algorithm). Reports per-case and global
// max abs LSB error and WHICH case is worst.
//
// PASS: max abs error per I/Q component <= ERR_TOL LSB across all N*256 bins.
// The golden hest.hex is itself a float->Q15 rounding of the reference; the
// fused fixed-point datapath reproduces it to ~3 LSB (offline predicted).
// ERR_TOL=4 (same budget as the identity TB).
// ============================================================================
`timescale 1ns/1ps

module rx_ch_est_robust_tb #(
    parameter W_ROM       = "rtl/rx_ch_est_rom/ce_interp_W.hex",
    parameter W_RECIP_ROM = "golden/rx_ch_est_robust/ce_pilot_recip.hex",
    parameter integer NCASE = 24            // must match meta.txt N
);
    localparam integer NSC   = 256;
    localparam integer NP    = 32;
    localparam integer ERR_TOL = 4;

    string GOLD;
    initial if (!$value$plusargs("GOLD=%s", GOLD)) GOLD = "golden/rx_ch_est_robust";

    // ---- clock / reset ----
    reg clk = 0; always #2 clk = ~clk;   // 250 MHz
    reg rst_n = 0;

    // ---- golden memories (N cases) ----
    reg [31:0] fft_mem  [0:NSC*NCASE-1];
    reg [31:0] plt_mem  [0:NP*NCASE-1];
    reg [31:0] hest_mem [0:NSC*NCASE-1];

    // ---- DUT I/O ----
    reg  [31:0] s_tdata;  reg s_tvalid; wire s_tready; reg s_tlast;
    reg  [31:0] plt_tdata; wire plt_tready;
    wire [31:0] m_tdata;  wire m_tvalid; reg m_tready; wire m_tlast;

    rx_ch_est #(.NSC(NSC), .NUM_PILOTS(NP), .NUM_DATA(NCASE),
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
        else if (plt_tready && plt_ptr < NP*NCASE-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- signed helpers ----
    function signed [15:0] lo16(input [31:0] w); lo16 = w[15:0];  endfunction
    function signed [15:0] hi16(input [31:0] w); hi16 = w[31:16]; endfunction
    function integer iabs(input integer v); iabs = (v<0)? -v : v; endfunction

    // ---- input driver (random S-AXIS bubbles; index advances on accept) ----
    integer in_idx;
    reg     driving_done;
    reg     bubble;
    integer seed = 32'hC0FFEE;

    wire [31:0] cur_data = fft_mem[in_idx];
    wire        cur_last = ((in_idx % NSC) == NSC-1);

    always @(*) begin
        s_tdata  = cur_data;
        s_tlast  = cur_last & ~driving_done;
        // AXIS rule: never assert TVALID during reset. (The original identity
        // rx_ch_est_tb.sv omits the rst_n gate -> the DUT consumes a phantom
        // beat at the reset-deassertion edge, shifting symbol-0 bins by one;
        // there it was masked by a broken golden load. Keep the gate here.)
        s_tvalid = rst_n & ~driving_done & ~bubble;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            in_idx<=0; driving_done<=0; bubble<=0;
        end else if (!driving_done) begin
            if (s_tvalid && s_tready) begin
                if (in_idx==NSC*NCASE-1) driving_done<=1;
                else                     in_idx<=in_idx+1;
            end
            bubble <= (($random(seed) % 5) == 0);
        end
    end

    // ---- output capture + check ----
    integer out_case, out_bin;
    integer errI, errQ, maxerr, caseerr, maxcase;
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
            out_case<=0; out_bin<=0; maxerr<=0; maxcase<=-1;
            total_beats<=0; fails<=0; caseerr<=0;
        end else if (m_tvalid && m_tready) begin
            g_idx = out_case*NSC + out_bin;
            got_i = lo16(m_tdata);  got_q = hi16(m_tdata);
            exp_i = lo16(hest_mem[g_idx]); exp_q = hi16(hest_mem[g_idx]);
            errI = iabs(got_i - exp_i);
            errQ = iabs(got_q - exp_q);
            if (errI>maxerr) begin maxerr<=errI; maxcase<=out_case; end
            if (errQ>maxerr) begin maxerr<=errQ; maxcase<=out_case; end
            if (errI>caseerr) caseerr<=errI;
            if (errQ>caseerr) caseerr<=errQ;
            if (errI>ERR_TOL || errQ>ERR_TOL) begin
                fails <= fails+1;
                if (fails < 30)
                  $display("  MISMATCH case=%0d bin=%0d got=(%0d,%0d) exp=(%0d,%0d) err=(%0d,%0d)",
                           out_case,out_bin,got_i,got_q,exp_i,exp_q,errI,errQ);
            end
            total_beats <= total_beats+1;
            if (m_tlast !== (out_bin==NSC-1))
                $display("  TLAST ERROR case=%0d bin=%0d tlast=%b",out_case,out_bin,m_tlast);
            if (out_bin==NSC-1) begin
                $display("  case %2d done: max|err| = %0d LSB", out_case, caseerr);
                caseerr<=0;
                out_bin<=0;
                out_case<=out_case+1;
            end else out_bin<=out_bin+1;
        end
    end

    // ---- run ----
    initial begin
        // NOTE: xsim 2021.1 silently fails to load when the filename is a
        // {string_var, "literal"} concatenation (memory stays X -> iabs(X-X)=0
        // -> false PASS). $sformatf builds the path reliably. (The identity
        // rx_ch_est_tb.sv has the same latent concat bug.)
        $readmemh($sformatf("%s/fft_out.hex",  GOLD), fft_mem);
        $readmemh($sformatf("%s/pilot_rom.hex",GOLD), plt_mem);
        $readmemh($sformatf("%s/hest.hex",     GOLD), hest_mem);
        if (fft_mem[0] === 32'hxxxxxxxx) begin
            $display("FATAL: golden not loaded from %s -- aborting", GOLD);
            $display("CI GATE: FAILED");
            $finish;
        end
        s_tvalid=0; s_tlast=0; m_tready=0;
        rst_n=0; repeat(8) @(posedge clk); rst_n=1;

        wait (out_case==NCASE);
        repeat(20) @(posedge clk);

        $display("============================================================");
        $display("rx_ch_est_robust_tb RESULTS");
        $display("  cases checked   : %0d / %0d", out_case, NCASE);
        $display("  beats checked   : %0d (expect %0d)", total_beats, NSC*NCASE);
        $display("  global max|err| : %0d LSB (tol %0d), worst case = %0d",
                 maxerr, ERR_TOL, maxcase);
        $display("  mismatches      : %0d", fails);
        if (out_case==NCASE && total_beats==NSC*NCASE && fails==0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("============================================================");
        $finish;
    end

    // global timeout
    initial begin
        #4000000;
        $display("TIMEOUT: out_case=%0d beats=%0d",out_case,total_beats);
        $display("CI GATE: FAILED");
        $finish;
    end
endmodule
