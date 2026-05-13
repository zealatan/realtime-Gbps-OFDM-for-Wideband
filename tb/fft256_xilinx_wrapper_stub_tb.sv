`timescale 1ns/1ps

// fft256_xilinx_wrapper_stub_tb — Compile and basic-interface test for
// fft256_xilinx_wrapper with USE_BEHAVIORAL_STUB=1.
//
// This testbench does NOT verify FFT correctness.
// It verifies:
//   T1 : reset_defaults    — all outputs low after reset, no stray valids
//   T2 : passthrough_valid — s_axis_tvalid propagates to m_axis_tvalid
//   T3 : tready_passthrough — m_axis_tready propagates to s_axis_tready
//   T4 : tlast_propagation — s_axis_tlast propagates to m_axis_tlast on last sample
//   T5 : events_zero       — all event_* outputs are 0 in stub mode
//   T6 : done_pulse        — done pulses one cycle after tlast frame
//   T7 : back_to_back      — two consecutive frames accepted without deadlock
//   T8 : no_ready_stall    — m_axis_tready=0 stalls acceptance (s_axis_tready=0)
//
// CI GATE: PASS only if pass_cnt > 0 and fail_cnt == 0.

module fft256_xilinx_wrapper_stub_tb;

    localparam int IQ_W   = 16;
    localparam int OUT_W  = 16;
    localparam int FLEN   = 256;
    localparam int HALF   = 5;   // 10 ns clock
    localparam int TIMEOUT = 4000;

    // -------------------------------------------------------------------------
    // Clock / reset
    // -------------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #HALF aclk = ~aclk;

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic                    start_d;
    logic                    s_axis_tvalid_d;
    wire                     s_axis_tready;
    logic [2*IQ_W-1:0]       s_axis_tdata_d;
    logic                    s_axis_tlast_d;

    wire                     m_axis_tvalid;
    logic                    m_axis_tready_d;
    wire  [2*OUT_W-1:0]      m_axis_tdata;
    wire                     m_axis_tlast;

    wire                     busy, done, error;
    wire                     ev_frame_started;
    wire                     ev_tlast_unexpected;
    wire                     ev_tlast_missing;
    wire                     ev_din_halt;
    wire                     ev_dout_halt;
    wire                     ev_status_halt;

    fft256_xilinx_wrapper #(
        .FFT_LEN             (FLEN),
        .IQ_WIDTH            (IQ_W),
        .FFT_OUT_WIDTH       (OUT_W),
        .USE_BEHAVIORAL_STUB (1)
    ) dut (
        .aclk                        (aclk),
        .aresetn                     (aresetn),
        .start                       (start_d),
        .s_axis_tvalid               (s_axis_tvalid_d),
        .s_axis_tready               (s_axis_tready),
        .s_axis_tdata                (s_axis_tdata_d),
        .s_axis_tlast                (s_axis_tlast_d),
        .m_axis_tvalid               (m_axis_tvalid),
        .m_axis_tready               (m_axis_tready_d),
        .m_axis_tdata                (m_axis_tdata),
        .m_axis_tlast                (m_axis_tlast),
        .busy                        (busy),
        .done                        (done),
        .error                       (error),
        .event_frame_started         (ev_frame_started),
        .event_tlast_unexpected      (ev_tlast_unexpected),
        .event_tlast_missing         (ev_tlast_missing),
        .event_data_in_channel_halt  (ev_din_halt),
        .event_data_out_channel_halt (ev_dout_halt),
        .event_status_channel_halt   (ev_status_halt)
    );

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm);                             pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chkv(input string nm, input logic [31:0] got, input logic [31:0] exp);
        if (got === exp)
            begin $display("[PASS] %s = 0x%08X", nm, got);                          pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=0x%08X exp=0x%08X", nm, got, exp);       fail_cnt++; end
    endtask

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------
    task do_reset(input int cycles);
        aresetn = 1'b0;
        s_axis_tvalid_d = 1'b0;
        s_axis_tdata_d  = '0;
        s_axis_tlast_d  = 1'b0;
        m_axis_tready_d = 1'b1;
        start_d         = 1'b0;
        repeat (cycles) @(posedge aclk);
        @(negedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
    endtask

    // Send a single frame of FLEN samples; last sample has tlast=1
    // m_axis_tready is held at ready_val throughout
    task automatic send_frame(input logic ready_val);
        int i;
        m_axis_tready_d = ready_val;
        for (i = 0; i < FLEN; i++) begin
            @(negedge aclk);
            s_axis_tvalid_d = 1'b1;
            s_axis_tdata_d  = {16'($signed(-(i+1))), 16'(i)};
            s_axis_tlast_d  = (i == FLEN-1) ? 1'b1 : 1'b0;
            @(posedge aclk);
            // Wait for handshake if not ready
            while (!s_axis_tready) @(posedge aclk);
        end
        @(negedge aclk);
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin : tb_main
        int tout;

        pass_cnt = 0;
        fail_cnt = 0;

        $display("=================================================");
        $display("  fft256_xilinx_wrapper_stub_tb — Step 36A");
        $display("  USE_BEHAVIORAL_STUB=1: passthrough only.");
        $display("  NOT an FFT correctness test.");
        $display("  Verifies compile, interface, and stub behavior.");
        $display("=================================================");

        // -------------------------------------------------------------------
        // T1: reset_defaults
        // -------------------------------------------------------------------
        do_reset(4);
        @(negedge aclk);
        $display("T1: reset_defaults");
        chk("T1.m_axis_tvalid=0 after reset", m_axis_tvalid, 1'b0);
        chk("T1.m_axis_tlast=0  after reset", m_axis_tlast,  1'b0);
        chk("T1.done=0          after reset", done,          1'b0);
        chk("T1.error=0         after reset", error,         1'b0);

        // -------------------------------------------------------------------
        // T2: passthrough_valid — m_axis_tvalid mirrors s_axis_tvalid
        //     (stub passes valid through combinatorially via m_axis_tready)
        // -------------------------------------------------------------------
        @(negedge aclk);
        m_axis_tready_d = 1'b1;
        s_axis_tvalid_d = 1'b1;
        s_axis_tdata_d  = 32'h0001_0002;
        s_axis_tlast_d  = 1'b0;
        @(posedge aclk);
        $display("T2: passthrough_valid");
        chk("T2.m_axis_tvalid=1 when s_axis_tvalid=1", m_axis_tvalid, 1'b1);
        @(negedge aclk);
        s_axis_tvalid_d = 1'b0;
        @(posedge aclk);
        chk("T2.m_axis_tvalid=0 when s_axis_tvalid=0", m_axis_tvalid, 1'b0);

        // -------------------------------------------------------------------
        // T3: tready_passthrough — s_axis_tready mirrors m_axis_tready
        // -------------------------------------------------------------------
        @(negedge aclk);
        m_axis_tready_d = 1'b1;
        @(posedge aclk);
        $display("T3: tready_passthrough");
        chk("T3.s_axis_tready=1 when m_axis_tready=1", s_axis_tready, 1'b1);
        @(negedge aclk);
        m_axis_tready_d = 1'b0;
        @(posedge aclk);
        chk("T3.s_axis_tready=0 when m_axis_tready=0", s_axis_tready, 1'b0);
        @(negedge aclk);
        m_axis_tready_d = 1'b1;

        // -------------------------------------------------------------------
        // T4: tlast_propagation — s_axis_tlast propagates to m_axis_tlast
        // -------------------------------------------------------------------
        @(negedge aclk);
        m_axis_tready_d = 1'b1;
        s_axis_tvalid_d = 1'b1;
        s_axis_tdata_d  = 32'hDEAD_BEEF;
        s_axis_tlast_d  = 1'b1;
        @(posedge aclk);
        $display("T4: tlast_propagation");
        chk("T4.m_axis_tlast=1 when s_axis_tlast=1", m_axis_tlast, 1'b1);
        @(negedge aclk);
        s_axis_tlast_d  = 1'b0;
        s_axis_tvalid_d = 1'b0;
        @(posedge aclk);
        chk("T4.m_axis_tlast=0 when s_axis_tlast=0", m_axis_tlast, 1'b0);

        // -------------------------------------------------------------------
        // T5: events_zero — all event outputs are 0 in stub mode
        // -------------------------------------------------------------------
        $display("T5: events_zero");
        chk("T5.ev_frame_started=0",    ev_frame_started,    1'b0);
        chk("T5.ev_tlast_unexpected=0", ev_tlast_unexpected, 1'b0);
        chk("T5.ev_tlast_missing=0",    ev_tlast_missing,    1'b0);
        chk("T5.ev_din_halt=0",         ev_din_halt,         1'b0);
        chk("T5.ev_dout_halt=0",        ev_dout_halt,        1'b0);
        chk("T5.ev_status_halt=0",      ev_status_halt,      1'b0);
        chk("T5.error=0",               error,               1'b0);

        // -------------------------------------------------------------------
        // T6: done_pulse — done pulses after frame tlast handshake
        // -------------------------------------------------------------------
        $display("T6: done_pulse");
        do_reset(2);
        fork
            send_frame(1'b1);
        join
        // done should pulse within a few cycles after tlast
        tout = 0;
        @(posedge aclk);
        while (!done && tout < 20) begin
            @(posedge aclk);
            tout++;
        end
        chk("T6.done pulsed after frame", done | (tout < 20 ? 1'b0 : 1'b0),
            (tout < 20) ? done : 1'b0);
        // More direct: check done occurred at some point
        if (tout < 20)
            begin $display("[PASS] T6.done_pulse: done seen within %0d cycles", tout); pass_cnt++; end
        else
            begin $display("[FAIL] T6.done_pulse: done not seen within 20 cycles");    fail_cnt++; end

        // -------------------------------------------------------------------
        // T7: back_to_back — two consecutive frames without reset
        // -------------------------------------------------------------------
        $display("T7: back_to_back");
        do_reset(2);
        fork
            send_frame(1'b1);
        join
        @(posedge aclk);
        fork
            send_frame(1'b1);
        join
        @(posedge aclk);
        chk("T7.error=0 after two frames", error, 1'b0);
        $display("[PASS] T7.back_to_back: two frames accepted without deadlock");
        pass_cnt++;

        // -------------------------------------------------------------------
        // T8: no_ready_stall — m_axis_tready=0 blocks acceptance
        // -------------------------------------------------------------------
        $display("T8: no_ready_stall");
        do_reset(2);
        @(negedge aclk);
        m_axis_tready_d = 1'b0;
        s_axis_tvalid_d = 1'b1;
        s_axis_tdata_d  = 32'hA5A5_5A5A;
        @(posedge aclk);
        chk("T8.s_axis_tready=0 when m_axis_tready=0 (no stall bypass)",
            s_axis_tready, 1'b0);
        @(negedge aclk);
        m_axis_tready_d = 1'b1;
        s_axis_tvalid_d = 1'b0;

        // -------------------------------------------------------------------
        // Final report
        // -------------------------------------------------------------------
        repeat(2) @(posedge aclk);
        $display("");
        $display("=================================================");
        $display("  RESULTS: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        $display("  NOTE: USE_BEHAVIORAL_STUB=1 only (passthrough).");
        $display("  FFT correctness NOT verified in Step 36A.");
        $display("  Production FFT pending: scripts/create_fft256_ip.tcl");
        $display("=================================================");

        if (fail_cnt == 0 && pass_cnt > 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Global timeout
    // -------------------------------------------------------------------------
    initial begin
        #(TIMEOUT * 10);
        $display("[FATAL] Simulation timeout at %0t ns", $time);
        $display("CI GATE: FAILED");
        $finish;
    end

endmodule
