`timescale 1ns/1ps

// Testbench for meyr_pss_sss_product_gen
//
// Verifies the complex multiply: term1 = PSS * conj(SSS)
//   term1_i = pss_i*sss_i + pss_q*sss_q
//   term1_q = pss_q*sss_i - pss_i*sss_q
//
// Uses explicit golden values; no PRNG or file I/O.

module meyr_pss_sss_product_gen_tb;

    localparam integer IQ_WIDTH   = 16;
    localparam integer PROD_WIDTH = 32;
    localparam real    CLK_PERIOD = 10.0;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                          aclk;
    logic                          aresetn;
    logic                          s_valid;
    logic                          s_ready;
    logic [7:0]                    s_index;
    logic signed [IQ_WIDTH-1:0]    pss_i, pss_q;
    logic signed [IQ_WIDTH-1:0]    sss_i, sss_q;
    logic                          m_valid;
    logic                          m_ready;
    logic [7:0]                    m_index;
    logic signed [PROD_WIDTH-1:0]  term1_i;
    logic signed [PROD_WIDTH-1:0]  term1_q;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    meyr_pss_sss_product_gen #(
        .IQ_WIDTH  (IQ_WIDTH),
        .PROD_WIDTH(PROD_WIDTH)
    ) dut (
        .aclk   (aclk),
        .aresetn(aresetn),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_index(s_index),
        .pss_i  (pss_i),
        .pss_q  (pss_q),
        .sss_i  (sss_i),
        .sss_q  (sss_q),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_index(m_index),
        .term1_i(term1_i),
        .term1_q(term1_q)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 0;
    always #(CLK_PERIOD/2) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Test counters
    // -----------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;

    // -----------------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------------
    task reset_dut;
        aresetn = 0;
        s_valid = 0;
        s_index = 0;
        pss_i   = 0;  pss_q = 0;
        sss_i   = 0;  sss_q = 0;
        m_ready = 1;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1;
        @(posedge aclk);
    endtask

    // Drive one sample and wait for m_valid output.
    // Returns term1_i/q in out_i/out_q and m_index in out_idx.
    task send_and_wait(
        input  [7:0]                  idx,
        input  signed [IQ_WIDTH-1:0]  pi, pq, si, sq,
        output signed [PROD_WIDTH-1:0] out_i, out_q,
        output [7:0]                  out_idx
    );
        @(negedge aclk);
        wait (s_ready);
        @(negedge aclk);
        s_valid = 1;
        s_index = idx;
        pss_i   = pi;  pss_q = pq;
        sss_i   = si;  sss_q = sq;
        @(posedge aclk);
        @(negedge aclk);
        s_valid = 0;
        // Wait for m_valid (pipeline latency = 1 clock after acceptance)
        @(posedge aclk);
        while (!m_valid) @(posedge aclk);
        out_i   = term1_i;
        out_q   = term1_q;
        out_idx = m_index;
        @(negedge aclk);
    endtask

    task chk(input logic cond, input string msg);
        if (cond) begin
            pass_cnt++;
        end else begin
            $display("FAIL: %s", msg);
            fail_cnt++;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic signed [PROD_WIDTH-1:0] got_i, got_q;
    logic [7:0]                   got_idx;
    integer grp_fail_snap;

    initial begin
        $display("=== meyr_pss_sss_product_gen_tb ===");

        reset_dut();

        // ------------------------------------------------------------------
        // T1: Reset defaults — m_valid=0 after reset
        // ------------------------------------------------------------------
        $display("T1: reset_defaults");
        grp_fail_snap = fail_cnt;
        chk(!m_valid, "T1 m_valid=0 after reset");
        if (fail_cnt == grp_fail_snap) $display("T1: PASS");

        // ------------------------------------------------------------------
        // T2: Real multiply: PSS=2+j0, SSS=3+j0 → term1=6+j0
        //   a=2,b=0,c=3,d=0: i=2*3+0*0=6, q=0*3-2*0=0
        // ------------------------------------------------------------------
        $display("T2: real_multiply PSS=2+j0, SSS=3+j0");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd10, 16'sd2, 16'sd0, 16'sd3, 16'sd0, got_i, got_q, got_idx);
        chk(got_i == 32'sd6, "T2 term1_i=6");
        chk(got_q == 32'sd0, "T2 term1_q=0");
        if (fail_cnt == grp_fail_snap) $display("T2: PASS");

        // ------------------------------------------------------------------
        // T3: Conjugate: PSS=1+j2, SSS=3+j4 → term1=(1+j2)*(3-j4)=11+j2
        //   i=1*3+2*4=11, q=2*3-1*4=2
        // ------------------------------------------------------------------
        $display("T3: conjugate PSS=1+j2, SSS=3+j4");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd20, 16'sd1, 16'sd2, 16'sd3, 16'sd4, got_i, got_q, got_idx);
        chk(got_i == 32'sd11, "T3 term1_i=11");
        chk(got_q == 32'sd2,  "T3 term1_q=2");
        if (fail_cnt == grp_fail_snap) $display("T3: PASS");

        // ------------------------------------------------------------------
        // T4: Negative inputs: PSS=-3+j0, SSS=2+j0 → term1=-6+j0
        //   i=-3*2+0*0=-6, q=0*2-(-3)*0=0
        // ------------------------------------------------------------------
        $display("T4: negative PSS=-3+j0, SSS=2+j0");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd30, -16'sd3, 16'sd0, 16'sd2, 16'sd0, got_i, got_q, got_idx);
        chk(got_i == -32'sd6, "T4 term1_i=-6");
        chk(got_q == 32'sd0,  "T4 term1_q=0");
        if (fail_cnt == grp_fail_snap) $display("T4: PASS");

        // ------------------------------------------------------------------
        // T5: Index preservation: index=77 passes through
        // ------------------------------------------------------------------
        $display("T5: index_preservation (index=77)");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd77, 16'sd5, 16'sd0, 16'sd1, 16'sd0, got_i, got_q, got_idx);
        chk(got_idx == 8'd77, "T5 m_index=77");
        if (fail_cnt == grp_fail_snap) $display("T5: PASS");

        // ------------------------------------------------------------------
        // T6: Unit SSS (1+j0): term1 = PSS
        //   PSS=7+j5, SSS=1+j0: i=7*1+5*0=7, q=5*1-7*0=5
        // ------------------------------------------------------------------
        $display("T6: unit_sss PSS=7+j5, SSS=1+j0");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd0, 16'sd7, 16'sd5, 16'sd1, 16'sd0, got_i, got_q, got_idx);
        chk(got_i == 32'sd7, "T6 term1_i=7");
        chk(got_q == 32'sd5, "T6 term1_q=5");
        if (fail_cnt == grp_fail_snap) $display("T6: PASS");

        // ------------------------------------------------------------------
        // T7: SSS=0+j1: conj(SSS)=0-j1, term1=PSS*(0-j1)
        //   PSS=3+j4: i=3*0+4*1=4, q=4*0-3*1=-3
        // ------------------------------------------------------------------
        $display("T7: sss_imaginary PSS=3+j4, SSS=0+j1");
        grp_fail_snap = fail_cnt;
        send_and_wait(8'd5, 16'sd3, 16'sd4, 16'sd0, 16'sd1, got_i, got_q, got_idx);
        chk(got_i == 32'sd4,  "T7 term1_i=4");
        chk(got_q == -32'sd3, "T7 term1_q=-3");
        if (fail_cnt == grp_fail_snap) $display("T7: PASS");

        // ------------------------------------------------------------------
        // T8: Backpressure — hold m_ready=0, check s_ready deasserts
        // ------------------------------------------------------------------
        $display("T8: backpressure");
        grp_fail_snap = fail_cnt;
        begin
            // Send one sample with m_ready=0 initially
            @(negedge aclk);
            m_ready = 0;
            wait(s_ready);
            @(negedge aclk);
            s_valid = 1;
            s_index = 8'd50;
            pss_i   = 16'sd4; pss_q = 16'sd0;
            sss_i   = 16'sd1; sss_q = 16'sd0;
            @(posedge aclk);
            @(negedge aclk);
            s_valid = 0;
            // Wait for m_valid to assert (output pending)
            @(posedge aclk);
            while (!m_valid) @(posedge aclk);
            // With m_ready=0, s_ready should be 0 (output slot occupied)
            @(negedge aclk);
            chk(!s_ready, "T8 s_ready=0 while m_valid && !m_ready");
            // Release backpressure
            m_ready = 1;
            @(posedge aclk);
            @(negedge aclk);
        end
        if (fail_cnt == grp_fail_snap) $display("T8: PASS");

        // ------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------
        $display("");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

endmodule
