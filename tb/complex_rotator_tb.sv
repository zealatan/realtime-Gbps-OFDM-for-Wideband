`timescale 1ns/1ps

// complex_rotator_tb — 10 test groups, ~35 checks.
//
// Verifies r_out[n] = r_in[n] * exp(-j theta[n]):
//   I_out = (I_in*cos + Q_in*sin) >>> 15
//   Q_out = (Q_in*cos - I_in*sin) >>> 15
//
// All Q1.15: 16384=0.5, 32767≈+1.0, -32768≈-1.0, 23170≈0.707
//
// Tests:
//   T1   Reset: m_tvalid=0
//   T2   theta=0, I=0.5, Q=0    → near-identity passthrough
//   T3   theta=0, I=0, Q=0.5    → near-identity passthrough
//   T4   theta=pi/2, I=0.5, Q=0 → −90° rotation
//   T5   theta=pi/2, I=0, Q=0.5 → −90° rotation
//   T6   theta=pi, I=0.5, Q=0.25 → negate
//   T7   theta=pi/4, I=0.5, Q=0  → −45° rotation
//   T8   tlast passthrough
//   T9   Backpressure (m_tready=0)
//   T10  Consecutive stream (3 beats, varying NCO phase)

module complex_rotator_tb;

    localparam int DW       = 32;
    localparam int CW       = 16;
    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 1000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic [DW-1:0]        iq_tdata_d;
    logic                 iq_tvalid_d, iq_tlast_d;
    wire                  iq_tready;
    logic signed [CW-1:0] sin_d, cos_d;
    logic                 sc_valid_d;
    logic                 m_tready_d;
    wire  [DW-1:0]        m_tdata;
    wire                  m_tvalid, m_tlast;

    complex_rotator #(
        .DATA_WIDTH      (DW),
        .COMPONENT_WIDTH (CW),
        .SHIFT           (15)
    ) dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_iq_tdata (iq_tdata_d),
        .s_axis_iq_tvalid(iq_tvalid_d),
        .s_axis_iq_tready(iq_tready),
        .s_axis_iq_tlast (iq_tlast_d),
        .sin_in          (sin_d),
        .cos_in          (cos_d),
        .sincos_valid    (sc_valid_d),
        .m_axis_tdata    (m_tdata),
        .m_axis_tvalid   (m_tvalid),
        .m_axis_tready   (m_tready_d),
        .m_axis_tlast    (m_tlast)
    );

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp) begin $display("[PASS] %s", nm); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_cw(
        input string         nm,
        input logic [DW-1:0] tdata,
        input logic          is_Q,
        input int            exp
    );
        logic signed [CW-1:0] got;
        got = is_Q ? $signed(tdata[DW-1:CW]) : $signed(tdata[CW-1:0]);
        if (got === exp[CW-1:0])
            begin $display("[PASS] %s = %0d", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden model — mirrors complex_mult_iq CONJ_B=1 arithmetic
    //   I_out = (I_in*cos + Q_in*sin) >>> 15
    //   Q_out = (Q_in*cos - I_in*sin) >>> 15
    // -----------------------------------------------------------------------
    function automatic int gold_I(input int I_in, Q_in, cos_v, sin_v);
        return ($signed(32'(I_in * cos_v)) + $signed(32'(Q_in * sin_v))) >>> 15;
    endfunction

    function automatic int gold_Q(input int I_in, Q_in, cos_v, sin_v);
        return ($signed(32'(Q_in * cos_v)) - $signed(32'(I_in * sin_v))) >>> 15;
    endfunction

    // Pack {Q[31:16], I[15:0]}
    function automatic logic [DW-1:0] pack_iq(input int I, Q);
        return {Q[15:0], I[15:0]};
    endfunction

    // -----------------------------------------------------------------------
    // Drive one rotation, capture output (1-cycle latency)
    // -----------------------------------------------------------------------
    task automatic do_rotate(
        input  logic [DW-1:0] iq_in,
        input  int            cos_v, sin_v,
        input  logic          iq_last,
        output logic [DW-1:0] out,
        output logic          v_out,
        output logic          last_out
    );
        @(negedge aclk);
        iq_tdata_d  = iq_in;
        iq_tvalid_d = 1'b1;
        iq_tlast_d  = iq_last;
        cos_d       = 16'(cos_v);
        sin_d       = 16'(sin_v);
        sc_valid_d  = 1'b1;
        m_tready_d  = 1'b1;
        @(posedge aclk); #1;
        out      = m_tdata;
        v_out    = m_tvalid;
        last_out = m_tlast;
        @(negedge aclk);
        iq_tvalid_d = 1'b0;
        sc_valid_d  = 1'b0;
        iq_tlast_d  = 1'b0;
    endtask

    // Drive + check I and Q
    task automatic test_rot(
        input string label,
        input int    I_in, Q_in, cos_v, sin_v
    );
        logic [DW-1:0] out;
        logic v_out, last_out;
        do_rotate(pack_iq(I_in, Q_in), cos_v, sin_v, 1'b0, out, v_out, last_out);
        chk    ($sformatf("%s valid",  label), v_out,  1'b1);
        chk_cw ($sformatf("%s I_out",  label), out, 0, gold_I(I_in, Q_in, cos_v, sin_v));
        chk_cw ($sformatf("%s Q_out",  label), out, 1, gold_Q(I_in, Q_in, cos_v, sin_v));
    endtask

    // -----------------------------------------------------------------------
    // Temporaries
    // -----------------------------------------------------------------------
    logic [DW-1:0] r_out;
    logic          r_v, r_last;

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn    = 1'b0;
        iq_tdata_d = '0; iq_tvalid_d = 1'b0; iq_tlast_d = 1'b0;
        sin_d = '0; cos_d = '0; sc_valid_d = 1'b0;
        m_tready_d = 1'b1;
        pass_cnt = 0; fail_cnt = 0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T1: Reset — output not valid
        // ====================================================================
        $display("\n--- T1: Reset ---");
        @(posedge aclk); #1;
        chk("T1 m_tvalid=0", m_tvalid, 1'b0);

        // ====================================================================
        // T2: theta=0 (cos≈+1, sin=0), I=0.5, Q=0 → near-identity
        //   I_out = 16384*32767 >>> 15 = 16383
        //   Q_out = 0
        // ====================================================================
        $display("\n--- T2: theta=0, I=0.5, Q=0 ---");
        test_rot("T2", 16384, 0, 32767, 0);

        // ====================================================================
        // T3: theta=0, I=0, Q=0.5 → near-identity on Q channel
        //   I_out = 0,  Q_out = 16384*32767 >>> 15 = 16383
        // ====================================================================
        $display("\n--- T3: theta=0, I=0, Q=0.5 ---");
        test_rot("T3", 0, 16384, 32767, 0);

        // ====================================================================
        // T4: theta=pi/2 (cos=0, sin≈+1), I=0.5, Q=0 → −90° rotation
        //   exp(-j*pi/2) = -j  →  (0.5+0j)*(-j) = 0 - j*0.5
        //   I_out = 0,  Q_out = -16383
        // ====================================================================
        $display("\n--- T4: theta=pi/2, I=0.5, Q=0 ---");
        test_rot("T4", 16384, 0, 0, 32767);

        // ====================================================================
        // T5: theta=pi/2, I=0, Q=0.5 → −90° rotation
        //   (0+j*0.5)*(-j) = 0.5+0j
        //   I_out = 16383,  Q_out = 0
        // ====================================================================
        $display("\n--- T5: theta=pi/2, I=0, Q=0.5 ---");
        test_rot("T5", 0, 16384, 0, 32767);

        // ====================================================================
        // T6: theta=pi (cos=-32768, sin=0), I=0.5, Q=0.25 → negate both
        //   I_out = 16384*(-32768) >>> 15 = -16384
        //   Q_out = 8192*(-32768)  >>> 15 = -8192
        // ====================================================================
        $display("\n--- T6: theta=pi, I=0.5, Q=0.25 ---");
        test_rot("T6", 16384, 8192, -32768, 0);

        // ====================================================================
        // T7: theta=pi/4 (cos=sin=23170≈0.707), I=0.5, Q=0 → −45° rotation
        //   I_out = 16384*23170 >>> 15 = 11585
        //   Q_out = -(16384*23170 >>> 15) = -11585
        // ====================================================================
        $display("\n--- T7: theta=pi/4, I=0.5, Q=0 ---");
        test_rot("T7", 16384, 0, 23170, 23170);

        // ====================================================================
        // T8: tlast passthrough
        // ====================================================================
        $display("\n--- T8: tlast passthrough ---");
        @(negedge aclk);
        iq_tdata_d  = pack_iq(16384, 0);
        iq_tvalid_d = 1'b1;
        iq_tlast_d  = 1'b1;
        cos_d = 32767; sin_d = 0; sc_valid_d = 1'b1;
        m_tready_d  = 1'b1;
        @(posedge aclk); #1;
        chk("T8 m_tvalid=1",          m_tvalid, 1'b1);
        chk("T8 tlast passes through", m_tlast,  1'b1);
        @(negedge aclk);
        iq_tvalid_d = 1'b0; sc_valid_d = 1'b0; iq_tlast_d = 1'b0;

        // ====================================================================
        // T9: Backpressure (m_tready=0)
        //   First beat fires (buf_ready=1 since output initially empty).
        //   With output held and tready=0: iq_tready must deassert.
        // ====================================================================
        $display("\n--- T9: backpressure ---");
        @(negedge aclk);
        iq_tdata_d  = pack_iq(16384, 0);
        iq_tvalid_d = 1'b1;
        cos_d = 32767; sin_d = 0; sc_valid_d = 1'b1;
        m_tready_d  = 1'b0;
        @(posedge aclk); #1;
        chk("T9 m_tvalid=1 when held",     m_tvalid,  1'b1);
        chk("T9 iq_tready=0 when blocked", iq_tready, 1'b0);
        @(negedge aclk);
        m_tready_d  = 1'b1;
        iq_tvalid_d = 1'b0;
        sc_valid_d  = 1'b0;
        @(posedge aclk); #1;
        chk("T9 m_tvalid deasserts after ready", m_tvalid, 1'b0);
        @(negedge aclk);

        // ====================================================================
        // T10: Consecutive stream — 3 beats, varying NCO phase
        // ====================================================================
        $display("\n--- T10: consecutive stream ---");
        begin
            logic [DW-1:0] res [0:2];
            @(negedge aclk);
            m_tready_d = 1'b1;

            // Beat 0: theta=0, I=0.5, Q=0.25
            iq_tdata_d = pack_iq(16384, 8192);
            cos_d = 32767; sin_d = 0;
            iq_tvalid_d = 1'b1; sc_valid_d = 1'b1;
            @(posedge aclk); #1; res[0] = m_tdata;
            @(negedge aclk);

            // Beat 1: theta=pi/2, I=0.25, Q=0.5
            iq_tdata_d = pack_iq(8192, 16384);
            cos_d = 0; sin_d = 32767;
            @(posedge aclk); #1; res[1] = m_tdata;
            @(negedge aclk);

            // Beat 2: theta=pi/4, I=0.5, Q=0
            iq_tdata_d = pack_iq(16384, 0);
            cos_d = 23170; sin_d = 23170;
            @(posedge aclk); #1; res[2] = m_tdata;
            @(negedge aclk);
            iq_tvalid_d = 1'b0; sc_valid_d = 1'b0;

            chk_cw("T10b0 I_out", res[0], 0, gold_I(16384, 8192, 32767,     0));
            chk_cw("T10b0 Q_out", res[0], 1, gold_Q(16384, 8192, 32767,     0));
            chk_cw("T10b1 I_out", res[1], 0, gold_I( 8192,16384,     0, 32767));
            chk_cw("T10b1 Q_out", res[1], 1, gold_Q( 8192,16384,     0, 32767));
            chk_cw("T10b2 I_out", res[2], 0, gold_I(16384,    0, 23170, 23170));
            chk_cw("T10b2 Q_out", res[2], 1, gold_Q(16384,    0, 23170, 23170));
        end

        // ====================================================================
        // Summary
        // ====================================================================
        $display("\n========================================");
        $display("PASS: %0d   FAIL: %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("CI GATE: PASSED");
        else               $display("CI GATE: FAILED");
        $display("========================================\n");
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
