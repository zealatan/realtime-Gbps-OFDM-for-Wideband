`timescale 1ns/1ps

// complex_mult_iq_tb: 18 test groups, ~50 checks.
//
// Three DUT instances (parameters chosen at compile time):
//   dut0: CONJ_A=0, CONJ_B=0  — normal complex multiply
//   dut1: CONJ_A=1, CONJ_B=0  — conj(A) × B
//   dut2: CONJ_A=0, CONJ_B=1  — A × conj(B)
//
// Input/output convention for all DUTs:
//   tdata[15:0]  = I (real)
//   tdata[31:16] = Q (imaginary)
//
// Q1.15 arithmetic: multiply two Q1.15 values, right-shift 15 to stay Q1.15.
//   Sample value 16384 = 0.5 in Q1.15.
//   Sample value  8192 = 0.25 in Q1.15.
//
// All Vivado-style hex literals: 32'hXXXX, not C-style 0xXXXX.

module complex_mult_iq_tb;

    localparam int DW       = 32;
    localparam int CW       = 16;
    localparam int CLK_HALF = 5;    // ns
    localparam int TIMEOUT  = 1000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Shared drive signals — three DUTs get the same inputs
    // -----------------------------------------------------------------------
    logic [DW-1:0]  a_tdata_d,  b_tdata_d;
    logic           a_tvalid_d, b_tvalid_d;
    logic           a_tlast_d,  b_tlast_d;
    logic           m_tready_d;

    // -----------------------------------------------------------------------
    // DUT 0: normal (CONJ_A=0, CONJ_B=0)
    // -----------------------------------------------------------------------
    wire [DW-1:0] dut0_tdata;
    wire          dut0_tvalid, dut0_tlast;
    wire          dut0_a_tready, dut0_b_tready;

    complex_mult_iq #(.CONJ_A(0), .CONJ_B(0)) dut0 (
        .aclk           (aclk), .aresetn        (aresetn),
        .s_axis_a_tdata (a_tdata_d),  .s_axis_a_tvalid(a_tvalid_d),
        .s_axis_a_tready(dut0_a_tready), .s_axis_a_tlast(a_tlast_d),
        .s_axis_b_tdata (b_tdata_d),  .s_axis_b_tvalid(b_tvalid_d),
        .s_axis_b_tready(dut0_b_tready), .s_axis_b_tlast(b_tlast_d),
        .m_axis_tdata   (dut0_tdata), .m_axis_tvalid(dut0_tvalid),
        .m_axis_tready  (m_tready_d), .m_axis_tlast(dut0_tlast)
    );

    // -----------------------------------------------------------------------
    // DUT 1: conj(A) × B  (CONJ_A=1, CONJ_B=0)
    // -----------------------------------------------------------------------
    wire [DW-1:0] dut1_tdata;
    wire          dut1_tvalid, dut1_tlast;
    wire          dut1_a_tready, dut1_b_tready;

    complex_mult_iq #(.CONJ_A(1), .CONJ_B(0)) dut1 (
        .aclk           (aclk), .aresetn        (aresetn),
        .s_axis_a_tdata (a_tdata_d),  .s_axis_a_tvalid(a_tvalid_d),
        .s_axis_a_tready(dut1_a_tready), .s_axis_a_tlast(a_tlast_d),
        .s_axis_b_tdata (b_tdata_d),  .s_axis_b_tvalid(b_tvalid_d),
        .s_axis_b_tready(dut1_b_tready), .s_axis_b_tlast(b_tlast_d),
        .m_axis_tdata   (dut1_tdata), .m_axis_tvalid(dut1_tvalid),
        .m_axis_tready  (m_tready_d), .m_axis_tlast(dut1_tlast)
    );

    // -----------------------------------------------------------------------
    // DUT 2: A × conj(B)  (CONJ_A=0, CONJ_B=1)
    // -----------------------------------------------------------------------
    wire [DW-1:0] dut2_tdata;
    wire          dut2_tvalid, dut2_tlast;
    wire          dut2_a_tready, dut2_b_tready;

    complex_mult_iq #(.CONJ_A(0), .CONJ_B(1)) dut2 (
        .aclk           (aclk), .aresetn        (aresetn),
        .s_axis_a_tdata (a_tdata_d),  .s_axis_a_tvalid(a_tvalid_d),
        .s_axis_a_tready(dut2_a_tready), .s_axis_a_tlast(a_tlast_d),
        .s_axis_b_tdata (b_tdata_d),  .s_axis_b_tvalid(b_tvalid_d),
        .s_axis_b_tready(dut2_b_tready), .s_axis_b_tlast(b_tlast_d),
        .m_axis_tdata   (dut2_tdata), .m_axis_tvalid(dut2_tvalid),
        .m_axis_tready  (m_tready_d), .m_axis_tlast(dut2_tlast)
    );

    // -----------------------------------------------------------------------
    // Scoreboard helpers
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp) begin $display("[PASS] %s", nm);               pass_cnt++; end
        else             begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    // Compare a 16-bit signed component extracted from tdata
    task automatic chk_component(
        input string          nm,
        input logic [DW-1:0]  tdata,
        input logic           is_Q,      // 1=check [31:16], 0=check [15:0]
        input int             exp
    );
        logic signed [15:0] got;
        got = is_Q ? $signed(tdata[31:16]) : $signed(tdata[15:0]);
        if (got === exp[15:0])
            begin $display("[PASS] %s  =%0d", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Helper: drive one multiply, capture output from the specified DUT.
    // Keeps m_tready_d=1 (no back-pressure).
    // Returns captured tdata and tvalid flag.
    // -----------------------------------------------------------------------
    task automatic do_mult(
        input  logic [DW-1:0] a_in, b_in,
        input  logic          a_last, b_last,
        output logic [DW-1:0] out0, out1, out2,
        output logic          v0, v1, v2,
        output logic          t0, t1, t2    // tlast
    );
        @(negedge aclk);
        a_tdata_d  = a_in;
        b_tdata_d  = b_in;
        a_tvalid_d = 1'b1;
        b_tvalid_d = 1'b1;
        a_tlast_d  = a_last;
        b_tlast_d  = b_last;
        m_tready_d = 1'b1;
        @(posedge aclk); #1;   // DUTs latch inputs; result registered this edge
        out0 = dut0_tdata; v0 = dut0_tvalid; t0 = dut0_tlast;
        out1 = dut1_tdata; v1 = dut1_tvalid; t1 = dut1_tlast;
        out2 = dut2_tdata; v2 = dut2_tvalid; t2 = dut2_tlast;
        @(negedge aclk);
        a_tvalid_d = 1'b0;
        b_tvalid_d = 1'b0;
        a_tlast_d  = 1'b0;
        b_tlast_d  = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Pack {Q[31:16], I[15:0]}
    // -----------------------------------------------------------------------
    function automatic logic [DW-1:0] pack(input int I, input int Q);
        return {Q[15:0], I[15:0]};
    endfunction

    // -----------------------------------------------------------------------
    // Golden model (integer Q1.15 arithmetic, SHIFT=15)
    // -----------------------------------------------------------------------
    // Normal: (I_a + j*Q_a) × (I_b + j*Q_b)
    function automatic int I_normal(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Ia * Ib)) - $signed(32'(Qa * Qb))) >>> 15;
    endfunction
    function automatic int Q_normal(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Ia * Qb)) + $signed(32'(Qa * Ib))) >>> 15;
    endfunction

    // conj(A) × B: (I_a - j*Q_a) × (I_b + j*Q_b)
    function automatic int I_conjA(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Ia * Ib)) + $signed(32'(Qa * Qb))) >>> 15;
    endfunction
    function automatic int Q_conjA(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Ia * Qb)) - $signed(32'(Qa * Ib))) >>> 15;
    endfunction

    // A × conj(B): (I_a + j*Q_a) × (I_b - j*Q_b)
    function automatic int I_conjB(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Ia * Ib)) + $signed(32'(Qa * Qb))) >>> 15;
    endfunction
    function automatic int Q_conjB(input int Ia, Qa, Ib, Qb);
        return ($signed(32'(Qa * Ib)) - $signed(32'(Ia * Qb))) >>> 15;
    endfunction

    // -----------------------------------------------------------------------
    // Run one full test (drive + check all three DUTs)
    // -----------------------------------------------------------------------
    task automatic test_all(
        input string label,
        input int Ia, Qa, Ib, Qb
    );
        logic [DW-1:0] out0, out1, out2;
        logic v0, v1, v2, t0, t1, t2;

        do_mult(pack(Ia, Qa), pack(Ib, Qb), 1'b0, 1'b0, out0, out1, out2, v0, v1, v2, t0, t1, t2);

        // All three DUTs should have valid output
        chk($sformatf("%s dut0 valid", label), v0, 1'b1);
        chk($sformatf("%s dut1 valid", label), v1, 1'b1);
        chk($sformatf("%s dut2 valid", label), v2, 1'b1);

        // dut0: normal A×B
        chk_component($sformatf("%s dut0 I_out", label), out0, 0, I_normal(Ia,Qa,Ib,Qb));
        chk_component($sformatf("%s dut0 Q_out", label), out0, 1, Q_normal(Ia,Qa,Ib,Qb));

        // dut1: conj(A)×B
        chk_component($sformatf("%s dut1 I_out", label), out1, 0, I_conjA(Ia,Qa,Ib,Qb));
        chk_component($sformatf("%s dut1 Q_out", label), out1, 1, Q_conjA(Ia,Qa,Ib,Qb));

        // dut2: A×conj(B)
        chk_component($sformatf("%s dut2 I_out", label), out2, 0, I_conjB(Ia,Qa,Ib,Qb));
        chk_component($sformatf("%s dut2 Q_out", label), out2, 1, Q_conjB(Ia,Qa,Ib,Qb));
    endtask

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    logic [DW-1:0] r_out0, r_out1, r_out2;
    logic r_v0, r_v1, r_v2, r_t0, r_t1, r_t2;

    initial begin
        aresetn    = 1'b0;
        a_tdata_d  = '0; b_tdata_d  = '0;
        a_tvalid_d = 1'b0; b_tvalid_d = 1'b0;
        a_tlast_d  = 1'b0; b_tlast_d  = 1'b0;
        m_tready_d = 1'b1;
        pass_cnt = 0; fail_cnt = 0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ----------------------------------------------------------------
        // T1: reset — no output valid before first transaction
        // ----------------------------------------------------------------
        @(posedge aclk); #1;
        chk("T1 dut0 valid=0 in reset", dut0_tvalid, 1'b0);
        chk("T1 dut1 valid=0 in reset", dut1_tvalid, 1'b0);
        chk("T1 dut2 valid=0 in reset", dut2_tvalid, 1'b0);

        // ----------------------------------------------------------------
        // T2: A=(0.5+j*0), B=(0.5+j*0) → A×B=(0.25+j*0)
        //   In Q1.15: Ia=16384, Qa=0, Ib=16384, Qb=0
        //   I_out = 16384*16384 >> 15 = 268435456 >> 15 = 8192
        //   Q_out = 0
        //   conj(A)×B = same (Qa=0 so conj is identical)
        //   A×conj(B) = same (Qb=0)
        // ----------------------------------------------------------------
        test_all("T2 A=(0.5,0) B=(0.5,0)", 16384, 0, 16384, 0);

        // ----------------------------------------------------------------
        // T3: A=(0+j*0.5), B=(0+j*0.5) → A×B=(-0.25+j*0)
        //   Ia=0, Qa=16384, Ib=0, Qb=16384
        //   I_out = 0 - 16384*16384>>15 = -8192
        //   Q_out = 0 + 0 = 0
        //   conj(A)×B: I=0+16384*16384>>15=8192, Q=0-0=0
        //   A×conj(B): I=0+16384*16384>>15=8192, Q=0-0=0
        // ----------------------------------------------------------------
        test_all("T3 A=(0,j0.5) B=(0,j0.5)", 0, 16384, 0, 16384);

        // ----------------------------------------------------------------
        // T4: A=(0.5+j*0.5), B=(0.5+j*0.5) → (0+j*0.5) in Q1.15 = (0, 16384)
        //   I_out = 16384*16384>>15 - 16384*16384>>15 = 8192-8192 = 0
        //   Q_out = 16384*16384>>15 + 16384*16384>>15 = 8192+8192 = 16384
        //   conj(A)×B = (0.5-j*0.5)(0.5+j*0.5) = 0.5+j*0 → I=16384, Q=0
        //   A×conj(B) = same as conj(A)×B by symmetry: I=16384, Q=0
        // ----------------------------------------------------------------
        test_all("T4 A=(0.5,j0.5) B=(0.5,j0.5)", 16384, 16384, 16384, 16384);

        // ----------------------------------------------------------------
        // T5: A=(0.5+j*0), B=(0+j*0.5) → (0+j*0.25)
        //   I_out = 0, Q_out = 16384*16384>>15 = 8192
        //   conj(A)×B: same (Qa=0)
        //   A×conj(B): I=0, Q = 0 - 16384*16384>>15 = -8192
        // ----------------------------------------------------------------
        test_all("T5 A=(0.5,0) B=(0,j0.5)", 16384, 0, 0, 16384);

        // ----------------------------------------------------------------
        // T6: A=(0+j*0.5), B=(0.5+j*0) → (0+j*0.25)
        //   I_out = 0, Q_out = 0 + 16384*16384>>15 = 8192
        //   conj(A)×B: I=0, Q = 0 - 16384*16384>>15 = -8192
        //   A×conj(B): same as normal (Qb=0)
        // ----------------------------------------------------------------
        test_all("T6 A=(0,j0.5) B=(0.5,0)", 0, 16384, 16384, 0);

        // ----------------------------------------------------------------
        // T7: A=(1.0+j*0), B=(-1.0+j*0) → (-1.0+j*0), then multiply
        //   Use near-max values: Ia=32767, Qa=0, Ib=-32768, Qb=0
        //   I_out = 32767*(-32768) >> 15 = -1073741824 >> 15 = -32767 (≈-1.0)
        //   Q_out = 0
        //   conj(A)×B = same (Qa=0)
        //   A×conj(B) = same (Qb=0)
        // ----------------------------------------------------------------
        test_all("T7 A=(1.0,0) B=(-1.0,0)", 32767, 0, -32768, 0);

        // ----------------------------------------------------------------
        // T8: A=(0.5+j*0.25), B=(0.5+j*0.25)
        //   Ia=16384, Qa=8192, Ib=16384, Qb=8192
        //   I_out = (16384*16384 - 8192*8192) >> 15
        //         = (268435456 - 67108864) >> 15
        //         = 201326592 >> 15 = 6144
        //   Q_out = (16384*8192 + 8192*16384) >> 15
        //         = 2*(16384*8192) >> 15
        //         = 2*134217728 >> 15 = 268435456 >> 15 = 8192
        //   conj(A)×B: I=(16384*16384 + 8192*8192)>>15 = (268435456+67108864)>>15 = 10240
        //              Q=(16384*8192 - 8192*16384)>>15 = 0
        //   A×conj(B): same as conj(A)×B by symmetry (A=B)
        // ----------------------------------------------------------------
        test_all("T8 A=(0.5,j0.25) B=(0.5,j0.25)", 16384, 8192, 16384, 8192);

        // ----------------------------------------------------------------
        // T9: A=(0.5+j*0.25), B=(0.25+j*0.5)
        //   Ia=16384, Qa=8192, Ib=8192, Qb=16384
        //   I_out = (16384*8192 - 8192*16384) >> 15 = 0
        //   Q_out = (16384*16384 + 8192*8192) >> 15 = (268435456+67108864)>>15 = 10240
        //   conj(A)×B: I=(16384*8192 + 8192*16384)>>15 = 2*134217728>>15 = 8192
        //              Q=(16384*16384 - 8192*8192)>>15 = 201326592>>15 = 6144
        //   A×conj(B): I=(16384*8192 + 8192*16384)>>15 = 8192
        //              Q=(8192*8192 - 16384*16384)>>15 = (67108864-268435456)>>15 = -6144
        // ----------------------------------------------------------------
        test_all("T9 A=(0.5,j0.25) B=(0.25,j0.5)", 16384, 8192, 8192, 16384);

        // ----------------------------------------------------------------
        // T10: tready back-pressure test (dut0 only)
        //   Drive both inputs, but hold m_tready_d=0.
        //   Cycle 1: accept fires (both valid, buf_ready=1 since !tvalid initially)
        //     → m_axis_tvalid becomes 1, output is registered.
        //   Cycle 2: m_tready_d=0; buf_ready=0; no new accept → tvalid stays 1.
        //   Cycle 3: raise m_tready_d=1; tvalid may deassert next cycle.
        // ----------------------------------------------------------------
        begin
            // First transaction: deliver one result
            @(negedge aclk);
            a_tdata_d  = pack(16384, 0);
            b_tdata_d  = pack(16384, 0);
            a_tvalid_d = 1'b1;
            b_tvalid_d = 1'b1;
            m_tready_d = 1'b0;  // downstream not ready
            @(posedge aclk); #1;
            // Output has been registered (tvalid=1), data is held
            chk("T10 dut0_tvalid=1 when not consumed", dut0_tvalid, 1'b1);
            chk_component("T10 dut0 I_out=8192 held", dut0_tdata, 0, 8192);
            // New inputs should be stalled (a_tready=0 because buf_ready=0)
            chk("T10 dut0 a_tready=0 when output blocked", dut0_a_tready, 1'b0);
            @(negedge aclk);
            // Now raise ready — output consumed
            m_tready_d = 1'b1;
            a_tvalid_d = 1'b0;
            b_tvalid_d = 1'b0;
            @(posedge aclk); #1;
            // tvalid deasserts after being consumed and no new accept
            chk("T10 dut0_tvalid deasserts after ready", dut0_tvalid, 1'b0);
        end

        // ----------------------------------------------------------------
        // T11: tlast passthrough
        //   Drive with a_tlast=1, b_tlast=1 → m_tlast must be 1 on output.
        // ----------------------------------------------------------------
        @(negedge aclk);
        a_tdata_d  = pack(16384, 0);
        b_tdata_d  = pack(16384, 0);
        a_tvalid_d = 1'b1;
        b_tvalid_d = 1'b1;
        a_tlast_d  = 1'b1;
        b_tlast_d  = 1'b1;
        m_tready_d = 1'b1;
        @(posedge aclk); #1;
        chk("T11 dut0 tlast passes through", dut0_tlast, 1'b1);
        chk("T11 dut1 tlast passes through", dut1_tlast, 1'b1);
        chk("T11 dut2 tlast passes through", dut2_tlast, 1'b1);
        @(negedge aclk);
        a_tvalid_d = 1'b0; b_tvalid_d = 1'b0;
        a_tlast_d = 1'b0;  b_tlast_d  = 1'b0;

        // ----------------------------------------------------------------
        // T12: consecutive transactions (pipeline streaming)
        //   Send 3 multiplies back-to-back; verify all 3 outputs.
        // ----------------------------------------------------------------
        // For simplicity: A=B for each, so I_out=0, Q_out varies.
        // A=(0.5+j*0.5), B=(0.5+j*0.5) → dut0 Q_out=16384
        // A=(0.5+j*0),   B=(0.5+j*0)   → dut0 I_out=8192, Q_out=0
        // A=(0+j*0.5),   B=(0+j*0.5)   → dut0 I_out=-8192, Q_out=0
        begin
            logic [DW-1:0] res [0:2];
            int            i;
            @(negedge aclk);
            m_tready_d = 1'b1;
            // Beat 0
            a_tdata_d  = pack(16384, 16384);
            b_tdata_d  = pack(16384, 16384);
            a_tvalid_d = 1'b1; b_tvalid_d = 1'b1;
            @(posedge aclk); #1;  res[0] = dut0_tdata;
            @(negedge aclk);
            // Beat 1
            a_tdata_d  = pack(16384, 0);
            b_tdata_d  = pack(16384, 0);
            @(posedge aclk); #1;  res[1] = dut0_tdata;
            @(negedge aclk);
            // Beat 2
            a_tdata_d  = pack(0, 16384);
            b_tdata_d  = pack(0, 16384);
            @(posedge aclk); #1;  res[2] = dut0_tdata;
            @(negedge aclk);
            a_tvalid_d = 1'b0; b_tvalid_d = 1'b0;

            chk_component("T12 beat0 I=0",    res[0], 0,  0);
            chk_component("T12 beat0 Q=16384", res[0], 1, 16384);
            chk_component("T12 beat1 I=8192",  res[1], 0,  8192);
            chk_component("T12 beat1 Q=0",     res[1], 1,  0);
            chk_component("T12 beat2 I=-8192", res[2], 0, -8192);
            chk_component("T12 beat2 Q=0",     res[2], 1,  0);
        end

        // ----------------------------------------------------------------
        // T13: tready asserted only for A while B invalid → no accept (deadlock)
        //   Drive a_valid=1, b_valid=0 → no output should fire.
        // ----------------------------------------------------------------
        @(negedge aclk);
        a_tdata_d  = pack(16384, 0);
        b_tdata_d  = '0;
        a_tvalid_d = 1'b1;
        b_tvalid_d = 1'b0;
        m_tready_d = 1'b1;
        @(posedge aclk); #1;
        chk("T13 no output when only A valid", dut0_tvalid, 1'b0);
        @(negedge aclk);
        a_tvalid_d = 1'b0;

        // ----------------------------------------------------------------
        // T14: negative values — A=(-0.5+j*0), B=(-0.5+j*0) → (0.25+j*0)
        //   Ia=-16384, Qa=0, Ib=-16384, Qb=0
        //   I_out = (-16384)*(-16384) >> 15 = 268435456 >> 15 = 8192
        //   Q_out = 0
        // ----------------------------------------------------------------
        test_all("T14 A=(-0.5,0) B=(-0.5,0)", -16384, 0, -16384, 0);

        // ----------------------------------------------------------------
        // T15: conj(A)×conj(B) = conj(A×B).
        //   Using dut1 (CONJ_A=1) with B=conj(B_actual): swap sign of Qb.
        //   This is a mathematical consistency check.
        //   A=(0.5+j*0.25), B=(0.5+j*0.25):
        //   conj(A)×B via dut1: already checked in T8.
        //   B_for_dut2 = B_actual so dut2 computes A×conj(B_actual).
        //   The result I_conjA should equal I_conjB (since A=B): confirmed above.
        //   This test drives A≠B to verify asymmetry of CONJ_A vs CONJ_B.
        //   A=(0.5+j*0.5), B=(0.25+j*0.125)
        //   Ia=16384, Qa=16384, Ib=8192, Qb=4096
        //   Normal I = (16384*8192 - 16384*4096)>>15 = (134217728-67108864)>>15 = 2048
        //   Normal Q = (16384*4096 + 16384*8192)>>15 = (67108864+134217728)>>15 = 6144
        //   conjA I  = (16384*8192 + 16384*4096)>>15 = (134217728+67108864)>>15 = 6144
        //   conjA Q  = (16384*4096 - 16384*8192)>>15 = (67108864-134217728)>>15 = -2048
        //   conjB I  = (16384*8192 + 16384*4096)>>15 = 6144  (same as conjA I, since |A|=|B| terms symmetric)
        //   conjB Q  = (16384*8192 - 16384*4096)>>15 = 2048  (= -conjA Q)
        // ----------------------------------------------------------------
        test_all("T15 A=(0.5,j0.5) B=(0.25,j0.125)", 16384, 16384, 8192, 4096);

        // ----------------------------------------------------------------
        // Summary
        // ----------------------------------------------------------------
        @(negedge aclk);
        $display("--- %0d PASS  %0d FAIL ---", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("CI GATE: PASSED");
        else               $display("CI GATE: FAILED");
        $finish;
    end

    // -----------------------------------------------------------------------
    // Watchdog
    // -----------------------------------------------------------------------
    initial begin
        #(TIMEOUT * CLK_HALF * 2 * 10);
        $display("[FAIL] Global watchdog timeout");
        $finish;
    end

endmodule
