`timescale 1ns/1ps

// cordic_atan2_tb — 13 test groups, ~42 checks.
//
// Drives the behavioral cordic_atan2 model and verifies:
//   - Pipeline latency = exactly LATENCY clocks
//   - tready always asserted
//   - tvalid propagates through pipeline
//   - Known-angle correctness (0°, ±90°, 180°, ±45°, ±135°)
//   - Back-to-back streaming (5 samples)
//   - Reset clears pipeline mid-stream
//   - Golden model matches DUT for PRNG inputs

module cordic_atan2_tb;

    localparam int IW       = 32;
    localparam int PW       = 16;
    localparam int LAT      = 15;
    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 2000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic [2*IW-1:0] s_axis_cartesian_tdata_d;
    logic            s_axis_cartesian_tvalid_d;
    wire             s_axis_cartesian_tready;
    wire  [PW-1:0]   m_axis_dout_tdata;
    wire             m_axis_dout_tvalid;

    cordic_atan2 #(
        .INPUT_WIDTH(IW),
        .PHASE_WIDTH(PW),
        .LATENCY    (LAT)
    ) dut (
        .aclk                     (aclk),
        .aresetn                  (aresetn),
        .s_axis_cartesian_tdata   (s_axis_cartesian_tdata_d),
        .s_axis_cartesian_tvalid  (s_axis_cartesian_tvalid_d),
        .s_axis_cartesian_tready  (s_axis_cartesian_tready),
        .m_axis_dout_tdata        (m_axis_dout_tdata),
        .m_axis_dout_tvalid       (m_axis_dout_tvalid)
    );

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);                             pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_phase(input string nm,
                              input logic [PW-1:0] got,
                              input logic [PW-1:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%04X (%0d)",
                           nm, got, $signed(got)); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%04X(%0d) exp=0x%04X(%0d)",
                           nm, got, $signed(got), exp, $signed(exp)); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden model — mirrors RTL atan2 computation
    // -----------------------------------------------------------------------
    function automatic logic [PW-1:0] gold_atan2(
        input logic signed [IW-1:0] I_in,
        input logic signed [IW-1:0] Q_in
    );
        real r_I_g, r_Q_g, r_ang_g;
        integer ph_g;
        r_I_g   = $itor(I_in);
        r_Q_g   = $itor(Q_in);
        r_ang_g = $atan2(r_Q_g, r_I_g) / 3.14159265358979323846;
        ph_g    = $rtoi(r_ang_g * ((1 << (PW-1)) - 1));
        return ph_g[PW-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Module-level capture buffer (for streaming tests)
    // -----------------------------------------------------------------------
    logic [PW-1:0] cap_data [0:31];
    int cap_cnt;

    // Capture the next n valid outputs (does NOT send any inputs)
    task automatic capture_n(input int n);
        int tout;
        cap_cnt = 0;
        tout    = 0;
        while (cap_cnt < n && tout < TIMEOUT) begin
            @(posedge aclk); #1;
            if (m_axis_dout_tvalid && cap_cnt < 32) begin
                cap_data[cap_cnt] = m_axis_dout_tdata;
                cap_cnt++;
            end
            tout++;
        end
        if (tout >= TIMEOUT) $display("[FAIL] TIMEOUT in capture_n");
    endtask

    // Send one sample, then wait LATENCY clocks for output
    task automatic send_and_wait(
        input logic signed [IW-1:0] I_v,
        input logic signed [IW-1:0] Q_v
    );
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {Q_v, I_v};
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1;          // posedge T: pipe[0] captures
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT) @(posedge aclk);  // wait LATENCY more clocks
        #1;                           // settle after posedge T+LAT
        // m_axis_dout_tdata/tvalid now reflect the submitted sample
    endtask

    // Wait LATENCY+2 clocks with no input (pipeline flush)
    task automatic flush();
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT + 2) @(posedge aclk);
        #1;
    endtask

    // -----------------------------------------------------------------------
    // Test temporaries (all declared at module level per Vivado xvlog rules)
    // -----------------------------------------------------------------------
    int            tctr_l;
    logic [PW-1:0] exp_ph;
    // T10 streaming arrays
    logic signed [IW-1:0] t10_I [0:4];
    logic signed [IW-1:0] t10_Q [0:4];
    int i10;
    // T13 PRNG
    logic [31:0] prng;
    logic signed [IW-1:0] t13_I [0:7];
    logic signed [IW-1:0] t13_Q [0:7];
    int i13;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn                   = 1'b0;
        s_axis_cartesian_tdata_d  = '0;
        s_axis_cartesian_tvalid_d = 1'b0;
        prng                      = 32'hDEAD_C0DE;
        pass_cnt                  = 0;
        fail_cnt                  = 0;

        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;

        // ====================================================================
        // T1: Reset state
        // ====================================================================
        $display("\n--- T1: Reset state ---");
        chk("T1 tready=1",    s_axis_cartesian_tready, 1'b1);
        chk("T1 dout_valid=0", m_axis_dout_tvalid,     1'b0);

        // ====================================================================
        // T2: Angle = 0  (I=+100000, Q=0) → phase = 0x0000
        // ====================================================================
        $display("\n--- T2: Angle=0 ---");
        send_and_wait(32'sd100000, 32'sd0);
        chk("T2 valid", m_axis_dout_tvalid, 1'b1);
        chk_phase("T2 angle=0", m_axis_dout_tdata, gold_atan2(32'sd100000, 32'sd0));

        // ====================================================================
        // T3: Angle = +π/2  (I=0, Q=+100000) → phase ≈ 0x3FFF (16383)
        // ====================================================================
        $display("\n--- T3: Angle=+pi/2 ---");
        send_and_wait(32'sd0, 32'sd100000);
        chk("T3 valid", m_axis_dout_tvalid, 1'b1);
        chk_phase("T3 angle=+pi/2", m_axis_dout_tdata, gold_atan2(32'sd0, 32'sd100000));

        // ====================================================================
        // T4: Angle = -π/2  (I=0, Q=-100000) → phase ≈ 0xC001 (-16383)
        // ====================================================================
        $display("\n--- T4: Angle=-pi/2 ---");
        send_and_wait(32'sd0, -32'sd100000);
        chk("T4 valid", m_axis_dout_tvalid, 1'b1);
        chk_phase("T4 angle=-pi/2", m_axis_dout_tdata, gold_atan2(32'sd0, -32'sd100000));

        // ====================================================================
        // T5: Angle = +π  (I=-100000, Q=0) → phase = 0x7FFF (32767)
        // ====================================================================
        $display("\n--- T5: Angle=+pi ---");
        send_and_wait(-32'sd100000, 32'sd0);
        chk("T5 valid", m_axis_dout_tvalid, 1'b1);
        chk_phase("T5 angle=+pi", m_axis_dout_tdata, gold_atan2(-32'sd100000, 32'sd0));

        // ====================================================================
        // T6: Angle = +π/4  (I=Q=+100000) → phase ≈ 0x1FFF (8191)
        // ====================================================================
        $display("\n--- T6: Angle=+pi/4 ---");
        send_and_wait(32'sd100000, 32'sd100000);
        chk("T6 valid", m_axis_dout_tvalid, 1'b1);
        chk_phase("T6 angle=+pi/4", m_axis_dout_tdata,
                  gold_atan2(32'sd100000, 32'sd100000));

        // ====================================================================
        // T7: Latency = exactly LAT clocks: not valid at T+14, valid at T+15
        // ====================================================================
        $display("\n--- T7: Latency verification ---");
        flush();
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {32'sd0, 32'sd200000};  // I=200000, Q=0
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1;            // posedge T: pipe[0] latched
        s_axis_cartesian_tvalid_d = 1'b0;
        // After posedge T+14: pipe[14] just got data, output not yet updated
        repeat(LAT-1) @(posedge aclk); #1;
        chk("T7 not valid at T+14", m_axis_dout_tvalid, 1'b0);
        // After posedge T+15: output gets pipe[14]
        @(posedge aclk); #1;
        chk("T7 valid at T+15", m_axis_dout_tvalid, 1'b1);
        chk_phase("T7 angle=0 at T+15", m_axis_dout_tdata,
                  gold_atan2(32'sd200000, 32'sd0));

        // ====================================================================
        // T8: tvalid=0 input — no valid output after LATENCY clocks
        // ====================================================================
        $display("\n--- T8: tvalid=0 gap ---");
        flush();
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {32'sd100000, 32'sd100000};
        s_axis_cartesian_tvalid_d = 1'b0;   // keep invalid
        repeat(LAT+2) @(posedge aclk); #1;
        chk("T8 no valid output", m_axis_dout_tvalid, 1'b0);

        // ====================================================================
        // T9: tready always 1 (before, during, after a run)
        // ====================================================================
        $display("\n--- T9: tready always 1 ---");
        chk("T9 tready before", s_axis_cartesian_tready, 1'b1);
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {32'sd0, 32'sd50000};
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1;
        chk("T9 tready during", s_axis_cartesian_tready, 1'b1);
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT) @(posedge aclk); #1;
        chk("T9 tready after", s_axis_cartesian_tready, 1'b1);

        // ====================================================================
        // T10: 5 back-to-back streaming samples
        // ====================================================================
        $display("\n--- T10: Streaming 5 back-to-back ---");
        flush();
        t10_I[0] = 32'sd100000;  t10_Q[0] = 32'sd0;
        t10_I[1] = 32'sd0;       t10_Q[1] = 32'sd100000;
        t10_I[2] = 32'sd0;       t10_Q[2] = -32'sd100000;
        t10_I[3] = -32'sd100000; t10_Q[3] = 32'sd0;
        t10_I[4] = 32'sd100000;  t10_Q[4] = 32'sd100000;
        // Drive 5 consecutive samples
        for (i10 = 0; i10 < 5; i10 = i10 + 1) begin
            @(negedge aclk);
            s_axis_cartesian_tdata_d  = {t10_Q[i10], t10_I[i10]};
            s_axis_cartesian_tvalid_d = 1'b1;
        end
        @(negedge aclk);
        s_axis_cartesian_tvalid_d = 1'b0;
        // Capture 5 valid outputs
        capture_n(5);
        for (i10 = 0; i10 < 5; i10 = i10 + 1)
            chk_phase($sformatf("T10 sample%0d", i10), cap_data[i10],
                      gold_atan2(t10_I[i10], t10_Q[i10]));

        // ====================================================================
        // T11: Reset mid-stream clears pipeline
        // ====================================================================
        $display("\n--- T11: Reset mid-stream ---");
        flush();
        // Send 3 samples
        for (i10 = 0; i10 < 3; i10 = i10 + 1) begin
            @(negedge aclk);
            s_axis_cartesian_tdata_d  = {32'sd50000, 32'sd50000};
            s_axis_cartesian_tvalid_d = 1'b1;
        end
        @(negedge aclk);
        s_axis_cartesian_tvalid_d = 1'b0;
        // Assert reset 5 clocks in (before any output)
        repeat(5) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b0;
        @(posedge aclk); #1;
        chk("T11 valid=0 during reset", m_axis_dout_tvalid, 1'b0);
        // Release reset and wait for pipeline to fill with zeros
        @(negedge aclk); aresetn = 1'b1;
        repeat(LAT+2) @(posedge aclk); #1;
        chk("T11 valid=0 after reset", m_axis_dout_tvalid, 1'b0);

        // ====================================================================
        // T12: All 4 quadrants — exact golden model for each
        // ====================================================================
        $display("\n--- T12: All 4 quadrants ---");
        flush();
        // Q1: I=+, Q=+ → +π/4
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {32'sd60000, 32'sd60000};
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1; s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT) @(posedge aclk); #1;
        chk_phase("T12 Q1 +pi/4", m_axis_dout_tdata,
                  gold_atan2(32'sd60000, 32'sd60000));
        // Q2: I=-, Q=+ → +3π/4
        send_and_wait(-32'sd60000, 32'sd60000);
        chk_phase("T12 Q2 +3pi/4", m_axis_dout_tdata,
                  gold_atan2(-32'sd60000, 32'sd60000));
        // Q3: I=-, Q=- → -3π/4
        send_and_wait(-32'sd60000, -32'sd60000);
        chk_phase("T12 Q3 -3pi/4", m_axis_dout_tdata,
                  gold_atan2(-32'sd60000, -32'sd60000));
        // Q4: I=+, Q=- → -π/4
        send_and_wait(32'sd60000, -32'sd60000);
        chk_phase("T12 Q4 -pi/4", m_axis_dout_tdata,
                  gold_atan2(32'sd60000, -32'sd60000));

        // ====================================================================
        // T13: PRNG smoke test — 8 random samples
        // ====================================================================
        $display("\n--- T13: PRNG smoke ---");
        flush();
        for (i13 = 0; i13 < 8; i13 = i13 + 1) begin
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            t13_I[i13] = $signed(prng);
            prng = {prng[30:0], 1'b0} ^ (prng[31] ? 32'hB000_0001 : 32'h0);
            t13_Q[i13] = $signed(prng);
        end
        // Drive 8 samples
        for (i13 = 0; i13 < 8; i13 = i13 + 1) begin
            @(negedge aclk);
            s_axis_cartesian_tdata_d  = {t13_Q[i13], t13_I[i13]};
            s_axis_cartesian_tvalid_d = 1'b1;
        end
        @(negedge aclk);
        s_axis_cartesian_tvalid_d = 1'b0;
        capture_n(8);
        for (i13 = 0; i13 < 8; i13 = i13 + 1)
            chk_phase($sformatf("T13 prng%0d", i13), cap_data[i13],
                      gold_atan2(t13_I[i13], t13_Q[i13]));

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

endmodule
