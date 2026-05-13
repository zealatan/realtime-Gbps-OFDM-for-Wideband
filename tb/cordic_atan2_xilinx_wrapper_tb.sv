`timescale 1ns/1ps

// cordic_atan2_xilinx_wrapper_tb — 14 test groups, ~36 checks.
//
// Exercises cordic_atan2_xilinx_wrapper with USE_BEHAVIORAL_MODEL=1.
// Tests the shift-register pipeline timing, valid alignment, phase values,
// and quadrant coverage against a golden $atan2 model.
//
// Phase convention: atan2(Q,I)/pi * 32767, signed 16-bit.
//   pi  -> +32767 (0x7FFF)  0 -> 0x0000  -pi/2 -> -16383 (0xC001)
//
// Tolerance: PHASE_TOL=2 LSBs (both wrapper and golden use identical formula).

module cordic_atan2_xilinx_wrapper_tb;

    localparam int IW        = 32;
    localparam int PW        = 16;
    localparam int LAT       = 15;
    localparam int CLK_HALF  = 5;
    localparam int TIMEOUT   = 4000;
    localparam int PHASE_TOL = 2;

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

    cordic_atan2_xilinx_wrapper #(
        .INPUT_WIDTH         (IW),
        .PHASE_WIDTH         (PW),
        .LATENCY             (LAT),
        .USE_BEHAVIORAL_MODEL(1)
    ) dut (
        .aclk                    (aclk),
        .aresetn                 (aresetn),
        .s_axis_cartesian_tdata  (s_axis_cartesian_tdata_d),
        .s_axis_cartesian_tvalid (s_axis_cartesian_tvalid_d),
        .s_axis_cartesian_tready (s_axis_cartesian_tready),
        .m_axis_dout_tdata       (m_axis_dout_tdata),
        .m_axis_dout_tvalid      (m_axis_dout_tvalid)
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
                              input logic [PW-1:0] got_bits,
                              input logic [PW-1:0] exp_bits);
        int diff;
        diff = int'($signed(got_bits)) - int'($signed(exp_bits));
        if (diff < 0) diff = -diff;
        if (diff <= PHASE_TOL)
            begin $display("[PASS] %s = 0x%04X (%0d, exp=%0d)",
                           nm, got_bits, $signed(got_bits), $signed(exp_bits));
                  pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%04X(%0d) exp=0x%04X(%0d) diff=%0d",
                           nm, got_bits, $signed(got_bits), exp_bits, $signed(exp_bits), diff);
                  fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Golden model — identical formula to wrapper behavioral model
    // atan2(Q, I) / pi * 32767, truncated to integer.
    // -----------------------------------------------------------------------
    function automatic logic [PW-1:0] gold_atan2(
        input logic signed [IW-1:0] I_in,
        input logic signed [IW-1:0] Q_in
    );
        real r_I, r_Q, r_ang;
        integer ph;
        r_I   = $itor(I_in);
        r_Q   = $itor(Q_in);
        r_ang = $atan2(r_Q, r_I) / 3.14159265358979323846;
        ph    = $rtoi(r_ang * 32767.0);
        return ph[PW-1:0];
    endfunction

    // -----------------------------------------------------------------------
    // Module-level capture buffer (streaming tests)
    // -----------------------------------------------------------------------
    logic [PW-1:0] cap_data [0:31];
    int cap_cnt;

    task automatic capture_n(input int n);
        int tout;
        cap_cnt = 0; tout = 0;
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

    // Send one sample and wait exactly LAT clocks for output
    task automatic send_and_wait(
        input logic signed [IW-1:0] I_v,
        input logic signed [IW-1:0] Q_v
    );
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {Q_v, I_v};
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1;           // posedge T: pipe[0] captures
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT) @(posedge aclk);   // wait LAT more clocks
        #1;                            // settle after posedge T+LAT
    endtask

    // Flush pipeline — LAT+2 idle clocks
    task automatic flush();
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT + 2) @(posedge aclk);
        #1;
    endtask

    // -----------------------------------------------------------------------
    // Test temporaries (module-level per Vivado xvlog rules)
    // -----------------------------------------------------------------------
    logic [PW-1:0] exp_ph;
    // T12 streaming arrays
    logic signed [IW-1:0] t12_I [0:5];
    logic signed [IW-1:0] t12_Q [0:5];
    int i12;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        aresetn                   = 1'b0;
        s_axis_cartesian_tdata_d  = '0;
        s_axis_cartesian_tvalid_d = 1'b0;
        pass_cnt                  = 0;
        fail_cnt                  = 0;

        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        @(posedge aclk); #1;

        // ====================================================================
        // T1: Reset defaults
        // ====================================================================
        $display("\n--- T1: reset_defaults ---");
        chk("T1 tready=1",   s_axis_cartesian_tready, 1'b1);
        chk("T1 m_valid=0",  m_axis_dout_tvalid,      1'b0);

        // ====================================================================
        // T2: positive_x_zero_y (I=+100000, Q=0) -> phase = 0
        // ====================================================================
        $display("\n--- T2: positive_x_zero_y ---");
        send_and_wait(32'sd100000, 32'sd0);
        chk("T2 m_valid",       m_axis_dout_tvalid, 1'b1);
        chk_phase("T2 phase=0", m_axis_dout_tdata,
                  gold_atan2(32'sd100000, 32'sd0));

        // ====================================================================
        // T3: zero_x_positive_y (I=0, Q=+100000) -> phase ~ +16383 (+pi/2)
        // ====================================================================
        $display("\n--- T3: zero_x_positive_y ---");
        send_and_wait(32'sd0, 32'sd100000);
        chk("T3 m_valid",           m_axis_dout_tvalid, 1'b1);
        chk_phase("T3 phase=+pi/2", m_axis_dout_tdata,
                  gold_atan2(32'sd0, 32'sd100000));

        // ====================================================================
        // T4: negative_x_zero_y (I=-100000, Q=0) -> phase ~ +32767 (+pi)
        // Convention: $aton2(+0.0, negative_x) = +pi in IEEE 754.
        // ====================================================================
        $display("\n--- T4: negative_x_zero_y ---");
        send_and_wait(-32'sd100000, 32'sd0);
        chk("T4 m_valid",          m_axis_dout_tvalid, 1'b1);
        chk_phase("T4 phase=+pi",  m_axis_dout_tdata,
                  gold_atan2(-32'sd100000, 32'sd0));

        // ====================================================================
        // T5: zero_x_negative_y (I=0, Q=-100000) -> phase ~ -16383 (-pi/2)
        // ====================================================================
        $display("\n--- T5: zero_x_negative_y ---");
        send_and_wait(32'sd0, -32'sd100000);
        chk("T5 m_valid",            m_axis_dout_tvalid, 1'b1);
        chk_phase("T5 phase=-pi/2",  m_axis_dout_tdata,
                  gold_atan2(32'sd0, -32'sd100000));

        // ====================================================================
        // T6: quadrant_I (I=+60000, Q=+60000) -> phase ~ +8191 (+pi/4)
        // ====================================================================
        $display("\n--- T6: quadrant_I ---");
        send_and_wait(32'sd60000, 32'sd60000);
        chk("T6 m_valid",           m_axis_dout_tvalid, 1'b1);
        chk_phase("T6 phase=+pi/4", m_axis_dout_tdata,
                  gold_atan2(32'sd60000, 32'sd60000));

        // ====================================================================
        // T7: quadrant_II (I=-60000, Q=+60000) -> phase ~ +24575 (+3pi/4)
        // ====================================================================
        $display("\n--- T7: quadrant_II ---");
        send_and_wait(-32'sd60000, 32'sd60000);
        chk("T7 m_valid",             m_axis_dout_tvalid, 1'b1);
        chk_phase("T7 phase=+3pi/4",  m_axis_dout_tdata,
                  gold_atan2(-32'sd60000, 32'sd60000));

        // ====================================================================
        // T8: quadrant_III (I=-60000, Q=-60000) -> phase ~ -24575 (-3pi/4)
        // ====================================================================
        $display("\n--- T8: quadrant_III ---");
        send_and_wait(-32'sd60000, -32'sd60000);
        chk("T8 m_valid",             m_axis_dout_tvalid, 1'b1);
        chk_phase("T8 phase=-3pi/4",  m_axis_dout_tdata,
                  gold_atan2(-32'sd60000, -32'sd60000));

        // ====================================================================
        // T9: quadrant_IV (I=+60000, Q=-60000) -> phase ~ -8191 (-pi/4)
        // ====================================================================
        $display("\n--- T9: quadrant_IV ---");
        send_and_wait(32'sd60000, -32'sd60000);
        chk("T9 m_valid",             m_axis_dout_tvalid, 1'b1);
        chk_phase("T9 phase=-pi/4",   m_axis_dout_tdata,
                  gold_atan2(32'sd60000, -32'sd60000));

        // ====================================================================
        // T10: small_values (low-magnitude vectors)
        // ====================================================================
        $display("\n--- T10: small_values ---");
        flush();
        send_and_wait(32'sd50, 32'sd50);
        chk("T10 m_valid_a",            m_axis_dout_tvalid, 1'b1);
        chk_phase("T10 small_pi/4",     m_axis_dout_tdata,
                  gold_atan2(32'sd50, 32'sd50));
        send_and_wait(32'sd100, -32'sd50);
        chk_phase("T10 small_neg_angle", m_axis_dout_tdata,
                  gold_atan2(32'sd100, -32'sd50));

        // ====================================================================
        // T11: large_values (near max signed 32-bit)
        // ====================================================================
        $display("\n--- T11: large_values ---");
        flush();
        send_and_wait(32'sd2000000000, 32'sd1000000000);
        chk("T11 m_valid_a",          m_axis_dout_tvalid, 1'b1);
        chk_phase("T11 large_Q1",     m_axis_dout_tdata,
                  gold_atan2(32'sd2000000000, 32'sd1000000000));
        send_and_wait(-32'sd1500000000, 32'sd1500000000);
        chk_phase("T11 large_Q2",     m_axis_dout_tdata,
                  gold_atan2(-32'sd1500000000, 32'sd1500000000));

        // ====================================================================
        // T12: back_to_back_valids — 6 consecutive samples
        // Verifies output order and phase sequence through full pipeline.
        // ====================================================================
        $display("\n--- T12: back_to_back_valids ---");
        flush();
        t12_I[0] =  32'sd100000;  t12_Q[0] =  32'sd0;
        t12_I[1] =  32'sd0;       t12_Q[1] =  32'sd100000;
        t12_I[2] = -32'sd100000;  t12_Q[2] =  32'sd0;
        t12_I[3] =  32'sd0;       t12_Q[3] = -32'sd100000;
        t12_I[4] =  32'sd100000;  t12_Q[4] =  32'sd100000;
        t12_I[5] = -32'sd60000;   t12_Q[5] = -32'sd60000;
        for (i12 = 0; i12 < 6; i12 = i12 + 1) begin
            @(negedge aclk);
            s_axis_cartesian_tdata_d  = {t12_Q[i12], t12_I[i12]};
            s_axis_cartesian_tvalid_d = 1'b1;
        end
        @(negedge aclk);
        s_axis_cartesian_tvalid_d = 1'b0;
        capture_n(6);
        for (i12 = 0; i12 < 6; i12 = i12 + 1)
            chk_phase($sformatf("T12 sample%0d", i12), cap_data[i12],
                      gold_atan2(t12_I[i12], t12_Q[i12]));

        // ====================================================================
        // T13: zero_vector (I=0, Q=0)
        // Expected: $atan2(0.0, 0.0) = 0.0 in most simulators -> phase = 0.
        // ====================================================================
        $display("\n--- T13: zero_vector ---");
        flush();
        send_and_wait(32'sd0, 32'sd0);
        chk("T13 m_valid",        m_axis_dout_tvalid, 1'b1);
        chk_phase("T13 zero_vec", m_axis_dout_tdata,
                  gold_atan2(32'sd0, 32'sd0));

        // ====================================================================
        // T14: pipeline_latency — not valid at T+LAT-1, valid at T+LAT
        // ====================================================================
        $display("\n--- T14: pipeline_latency ---");
        flush();
        @(negedge aclk);
        s_axis_cartesian_tdata_d  = {32'sd0, 32'sd300000};  // I=300000, Q=0
        s_axis_cartesian_tvalid_d = 1'b1;
        @(posedge aclk); #1;                    // posedge T: pipe[0] captures
        s_axis_cartesian_tvalid_d = 1'b0;
        repeat(LAT-1) @(posedge aclk); #1;      // posedge T+(LAT-1)
        chk("T14 not valid at T+LAT-1", m_axis_dout_tvalid, 1'b0);
        @(posedge aclk); #1;                    // posedge T+LAT
        chk("T14 valid at T+LAT",       m_axis_dout_tvalid, 1'b1);
        chk_phase("T14 phase=0 at T+LAT", m_axis_dout_tdata,
                  gold_atan2(32'sd300000, 32'sd0));

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
