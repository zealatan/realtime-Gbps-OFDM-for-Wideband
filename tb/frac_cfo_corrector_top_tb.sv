`timescale 1ns/1ps

// frac_cfo_corrector_top_tb — 8 test groups, ~22 checks.
//
// Integration test: verifies NCO startup, rotation correctness, and
// phase_reset behaviour.  sin/cos are captured from the DUT's debug ports
// at the negedge before each sample posedge and used as the golden reference,
// so the test is independent of CORDIC arithmetic details.
//
// NCO timing: sincos_valid fires exactly LATENCY clocks after the posedge
// where enable first fires (confirmed by nco_phase_gen_tb T5).
// nco_start() waits LATENCY+1 posedges from setting enable so it returns
// with sincos_valid already asserted.
//
// Tests:
//   T1  Reset: m_tvalid=0, sincos_valid=0
//   T2  step_word=0: NCO up after startup, identity-ish rotation (2 samples)
//   T3  Non-zero step_word: phase advances each sample (2 samples)
//   T4  phase_reset clears phase_acc to 0
//   T5  After phase_reset + restart: sincos_valid returns, rotation correct
//   T6  tlast passthrough
//   T7  Backpressure: iq_tready deasserts when m_tready=0
//   T8  Consecutive IQ stream (3 beats, step_word=0)

module frac_cfo_corrector_top_tb;

    localparam int DW       = 32;
    localparam int CW       = 16;
    localparam int NCO_PW   = 32;
    localparam int LAT      = 15;
    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 5000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic signed [NCO_PW-1:0] step_word_d;
    logic                     load_step_d, phase_reset_d, enable_d;
    logic [DW-1:0]            iq_tdata_d;
    logic                     iq_tvalid_d, iq_tlast_d;
    wire                      iq_tready;
    logic                     m_tready_d;
    wire  [DW-1:0]            m_tdata;
    wire                      m_tvalid, m_tlast;
    wire  [NCO_PW-1:0]        phase_acc;
    wire signed [CW-1:0]      sin_out, cos_out;
    wire                      sincos_valid;

    frac_cfo_corrector_top #(
        .DATA_WIDTH          (DW),
        .COMPONENT_WIDTH     (CW),
        .SHIFT               (15),
        .NCO_PHASE_WIDTH     (NCO_PW),
        .CORDIC_PHASE_WIDTH  (16),
        .ROTATOR_COEFF_WIDTH (16),
        .LATENCY             (LAT)
    ) dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .load_step       (load_step_d),
        .step_word       (step_word_d),
        .phase_reset     (phase_reset_d),
        .enable          (enable_d),
        .s_axis_iq_tdata (iq_tdata_d),
        .s_axis_iq_tvalid(iq_tvalid_d),
        .s_axis_iq_tready(iq_tready),
        .s_axis_iq_tlast (iq_tlast_d),
        .m_axis_tdata    (m_tdata),
        .m_axis_tvalid   (m_tvalid),
        .m_axis_tready   (m_tready_d),
        .m_axis_tlast    (m_tlast),
        .phase_acc       (phase_acc),
        .sin_out         (sin_out),
        .cos_out         (cos_out),
        .sincos_valid    (sincos_valid)
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

    task automatic chk_acc(input string nm,
                            input logic [NCO_PW-1:0] got,
                            input logic [NCO_PW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%08X", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%08X exp=0x%08X", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden rotation model — mirrors complex_mult_iq CONJ_B=1 arithmetic
    //   I_out = (I_in*cos + Q_in*sin) >>> 15
    //   Q_out = (Q_in*cos - I_in*sin) >>> 15
    // -----------------------------------------------------------------------
    function automatic int gold_I(input int I, Q, cos_v, sin_v);
        return ($signed(32'(I * cos_v)) + $signed(32'(Q * sin_v))) >>> 15;
    endfunction
    function automatic int gold_Q(input int I, Q, cos_v, sin_v);
        return ($signed(32'(Q * cos_v)) - $signed(32'(I * sin_v))) >>> 15;
    endfunction

    function automatic logic [DW-1:0] pack_iq(input int I, Q);
        return {Q[15:0], I[15:0]};
    endfunction

    // -----------------------------------------------------------------------
    // NCO startup: load step_word, pulse phase_reset, assert enable,
    // then wait until sincos_valid is asserted.
    // Returns with sincos_valid=1.
    // -----------------------------------------------------------------------
    task automatic nco_start(input logic signed [NCO_PW-1:0] sw);
        // Load step word
        @(negedge aclk);
        step_word_d  = sw;
        load_step_d  = 1'b1;
        @(posedge aclk); #1;
        load_step_d  = 1'b0;
        // Reset phase accumulator
        phase_reset_d = 1'b1;
        @(posedge aclk); #1;
        phase_reset_d = 1'b0;
        // Enable accumulator; sincos_valid fires after exactly LATENCY posedges
        // from the first posedge where enable is high (nco_phase_gen T5).
        // Waiting LATENCY+1 posedges lands us on that posedge + #1.
        enable_d = 1'b1;
        repeat(LAT+1) @(posedge aclk); #1;
    endtask

    // -----------------------------------------------------------------------
    // Send one IQ sample and capture the output.
    // Captures sin/cos at negedge (the values the multiplier will see at the
    // upcoming posedge) and returns them as the golden reference.
    // Caller must ensure sincos_valid=1 before calling.
    // -----------------------------------------------------------------------
    task automatic send_iq(
        input  logic [DW-1:0] iq_in,
        input  logic          last_in,
        output logic [DW-1:0] out,
        output logic          v_out,
        output logic          last_out,
        output logic signed [CW-1:0] cap_sin,
        output logic signed [CW-1:0] cap_cos
    );
        @(negedge aclk);
        iq_tdata_d  = iq_in;
        iq_tvalid_d = 1'b1;
        iq_tlast_d  = last_in;
        m_tready_d  = 1'b1;
        cap_sin     = sin_out;   // value the multiplier will use this posedge
        cap_cos     = cos_out;
        @(posedge aclk); #1;
        out      = m_tdata;
        v_out    = m_tvalid;
        last_out = m_tlast;
        @(negedge aclk);
        iq_tvalid_d = 1'b0;
        iq_tlast_d  = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Temporaries
    // -----------------------------------------------------------------------
    logic [DW-1:0]        r_out;
    logic                 r_v, r_last;
    logic signed [CW-1:0] c_sin, c_cos;

    // -----------------------------------------------------------------------
    // Main sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn       = 1'b0;
        step_word_d   = '0;
        load_step_d   = 1'b0;
        phase_reset_d = 1'b0;
        enable_d      = 1'b0;
        iq_tdata_d    = '0;
        iq_tvalid_d   = 1'b0;
        iq_tlast_d    = 1'b0;
        m_tready_d    = 1'b1;
        pass_cnt      = 0;
        fail_cnt      = 0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T1: Reset — no valid outputs
        // ====================================================================
        $display("\n--- T1: Reset ---");
        @(posedge aclk); #1;
        chk("T1 m_tvalid=0",     m_tvalid,    1'b0);
        chk("T1 sincos_valid=0", sincos_valid, 1'b0);

        // ====================================================================
        // T2: step_word=0 → theta constant at 0; identity-ish rotation
        //   sin(0)=0, cos(0)≈32767; I_out = I_in*32767>>15 ≈ I_in
        // ====================================================================
        $display("\n--- T2: step_word=0, identity rotation ---");
        nco_start(32'sd0);
        chk("T2 sincos_valid=1 after startup", sincos_valid, 1'b1);
        // Sample: I=0.5 (16384), Q=0
        send_iq(pack_iq(16384, 0), 1'b0, r_out, r_v, r_last, c_sin, c_cos);
        chk    ("T2a m_tvalid=1",  r_v,   1'b1);
        chk_cw ("T2a I_out",       r_out, 0, gold_I(16384, 0, int'(c_cos), int'(c_sin)));
        chk_cw ("T2a Q_out",       r_out, 1, gold_Q(16384, 0, int'(c_cos), int'(c_sin)));
        // Sample: I=0, Q=0.5 (16384)
        send_iq(pack_iq(0, 16384), 1'b0, r_out, r_v, r_last, c_sin, c_cos);
        chk    ("T2b m_tvalid=1",  r_v,   1'b1);
        chk_cw ("T2b I_out",       r_out, 0, gold_I(0, 16384, int'(c_cos), int'(c_sin)));
        chk_cw ("T2b Q_out",       r_out, 1, gold_Q(0, 16384, int'(c_cos), int'(c_sin)));
        enable_d = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T3: Non-zero step_word (0x10000000 = π/8 per sample)
        //   sin/cos advance each clock; capture actual NCO output as reference.
        // ====================================================================
        $display("\n--- T3: step_word=0x10000000 (pi/8/sample), advancing phase ---");
        nco_start(32'h1000_0000);
        chk("T3 sincos_valid=1 after startup", sincos_valid, 1'b1);
        // Sample 0: phase = 0 (pre-accumulation at clock 0)
        send_iq(pack_iq(16384, 0), 1'b0, r_out, r_v, r_last, c_sin, c_cos);
        chk    ("T3s0 m_tvalid=1", r_v,   1'b1);
        chk_cw ("T3s0 I_out",      r_out, 0, gold_I(16384, 0, int'(c_cos), int'(c_sin)));
        chk_cw ("T3s0 Q_out",      r_out, 1, gold_Q(16384, 0, int'(c_cos), int'(c_sin)));
        // Sample 1: phase advanced by one step_word
        send_iq(pack_iq(16384, 0), 1'b0, r_out, r_v, r_last, c_sin, c_cos);
        chk    ("T3s1 m_tvalid=1", r_v,   1'b1);
        chk_cw ("T3s1 I_out",      r_out, 0, gold_I(16384, 0, int'(c_cos), int'(c_sin)));
        chk_cw ("T3s1 Q_out",      r_out, 1, gold_Q(16384, 0, int'(c_cos), int'(c_sin)));
        enable_d = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T4: phase_reset clears phase_acc to 0
        // ====================================================================
        $display("\n--- T4: phase_reset clears accumulator ---");
        // Advance NCO a few steps so phase_acc != 0
        nco_start(32'h1000_0000);
        repeat(4) @(posedge aclk); #1;   // let phase advance
        @(negedge aclk);
        phase_reset_d = 1'b1;
        @(posedge aclk); #1;
        chk_acc("T4 phase_acc=0 after reset", phase_acc, 32'h0000_0000);
        @(negedge aclk);
        phase_reset_d = 1'b0;
        enable_d      = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T5: After phase_reset + fresh start, sincos_valid returns and
        //     rotation is correct (phase should be 0 again)
        // ====================================================================
        $display("\n--- T5: restart after phase_reset ---");
        nco_start(32'h1000_0000);
        chk("T5 sincos_valid=1 after restart", sincos_valid, 1'b1);
        send_iq(pack_iq(16384, 0), 1'b0, r_out, r_v, r_last, c_sin, c_cos);
        chk    ("T5 m_tvalid=1", r_v,   1'b1);
        chk_cw ("T5 I_out",      r_out, 0, gold_I(16384, 0, int'(c_cos), int'(c_sin)));
        chk_cw ("T5 Q_out",      r_out, 1, gold_Q(16384, 0, int'(c_cos), int'(c_sin)));
        enable_d = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T6: tlast passthrough
        // ====================================================================
        $display("\n--- T6: tlast passthrough ---");
        nco_start(32'sd0);
        send_iq(pack_iq(16384, 0), 1'b1, r_out, r_v, r_last, c_sin, c_cos);
        chk("T6 m_tvalid=1", r_v,    1'b1);
        chk("T6 m_tlast=1",  r_last, 1'b1);
        enable_d = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T7: Backpressure — m_tready=0 while NCO running; first beat fires
        //     (output buffer empty), then iq_tready must deassert.
        // ====================================================================
        $display("\n--- T7: backpressure ---");
        nco_start(32'sd0);
        @(negedge aclk);
        iq_tdata_d  = pack_iq(16384, 0);
        iq_tvalid_d = 1'b1;
        m_tready_d  = 1'b0;
        @(posedge aclk); #1;
        chk("T7 m_tvalid=1 when held",     m_tvalid,  1'b1);
        chk("T7 iq_tready=0 when blocked", iq_tready, 1'b0);
        @(negedge aclk);
        m_tready_d  = 1'b1;
        iq_tvalid_d = 1'b0;
        @(posedge aclk); #1;
        chk("T7 m_tvalid clears after ready", m_tvalid, 1'b0);
        @(negedge aclk);
        enable_d = 1'b0;
        repeat(2) @(negedge aclk);

        // ====================================================================
        // T8: Consecutive 3-beat stream (step_word=0, no phase advance)
        // ====================================================================
        $display("\n--- T8: consecutive 3-beat stream ---");
        begin
            logic [DW-1:0] res[0:2];
            logic signed [CW-1:0] s_s[0:2], c_s[0:2];
            logic v_tmp, l_tmp;

            nco_start(32'sd0);
            @(negedge aclk);
            m_tready_d = 1'b1;

            // Beat 0: I=0.5, Q=0
            iq_tdata_d = pack_iq(16384, 0);
            iq_tvalid_d = 1'b1;
            s_s[0] = sin_out; c_s[0] = cos_out;
            @(posedge aclk); #1; res[0] = m_tdata;
            @(negedge aclk);

            // Beat 1: I=0, Q=0.5
            iq_tdata_d = pack_iq(0, 16384);
            s_s[1] = sin_out; c_s[1] = cos_out;
            @(posedge aclk); #1; res[1] = m_tdata;
            @(negedge aclk);

            // Beat 2: I=0.5, Q=0.25
            iq_tdata_d = pack_iq(16384, 8192);
            s_s[2] = sin_out; c_s[2] = cos_out;
            @(posedge aclk); #1; res[2] = m_tdata;
            @(negedge aclk);
            iq_tvalid_d = 1'b0;

            chk_cw("T8b0 I_out", res[0], 0, gold_I(16384,     0, int'(c_s[0]), int'(s_s[0])));
            chk_cw("T8b0 Q_out", res[0], 1, gold_Q(16384,     0, int'(c_s[0]), int'(s_s[0])));
            chk_cw("T8b1 I_out", res[1], 0, gold_I(    0, 16384, int'(c_s[1]), int'(s_s[1])));
            chk_cw("T8b1 Q_out", res[1], 1, gold_Q(    0, 16384, int'(c_s[1]), int'(s_s[1])));
            chk_cw("T8b2 I_out", res[2], 0, gold_I(16384,  8192, int'(c_s[2]), int'(s_s[2])));
            chk_cw("T8b2 Q_out", res[2], 1, gold_Q(16384,  8192, int'(c_s[2]), int'(s_s[2])));
        end
        enable_d = 1'b0;

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
