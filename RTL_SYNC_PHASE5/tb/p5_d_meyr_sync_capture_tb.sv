`timescale 1ns/1ps
// Unit-sim for meyr_sync_capture:
//   - 2N=512 samples land back-to-back from the slot frontend
//   - core stalls (out_tready low) for stretches > 0 — no drops on
//     the write side, no extra beats handed to the core
//   - PSS-then-SSS order preserved (beat 0 == sample 0)
//   - overrun policy: a second pss_first_beat while pending fires
//     overrun_event AND resets the buffer to the new capture
//
// GATE line:
//   PASS_P5_D_SYNC_CAPTURE  /  FAIL_P5_D_SYNC_CAPTURE
module p5_d_meyr_sync_capture_tb;

    localparam int N      = 256;
    localparam int N2     = 2*N;
    localparam int DATA_W = 32;

    logic clk = 0;
    always #2 clk = ~clk;  // 250 MHz
    logic rst_n = 0;

    logic [DATA_W-1:0] in_tdata;
    logic              in_tvalid;
    logic              pss_first_beat;
    logic [DATA_W-1:0] out_tdata;
    logic              out_tvalid;
    logic              out_tready;
    logic              overrun_event;
    logic              capture_done;

    meyr_sync_capture #(.N(N), .DATA_W(DATA_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_tdata(in_tdata), .in_tvalid(in_tvalid),
        .pss_first_beat(pss_first_beat),
        .out_tdata(out_tdata), .out_tvalid(out_tvalid), .out_tready(out_tready),
        .overrun_event(overrun_event), .capture_done(capture_done)
    );

    int fails = 0;
    int captured_beats = 0;
    int overrun_count = 0;

    task automatic reset_dut();
        in_tdata = '0; in_tvalid = 0; pss_first_beat = 0;
        out_tready = 0;
        rst_n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
    endtask

    // Drive 2N samples with values = (offset + n).
    task automatic drive_capture(input int offset, input bit start_pulse);
        for (int n = 0; n < N2; n = n + 1) begin
            @(posedge clk);
            in_tdata       <= 32'(offset + n);
            in_tvalid      <= 1'b1;
            pss_first_beat <= (n == 0) && start_pulse;
        end
        @(posedge clk);
        in_tvalid      <= 1'b0;
        pss_first_beat <= 1'b0;
    endtask

    // Drain with intermittent stalls.
    task automatic drain_capture(input int offset, input int stall_every);
        int got = 0;
        int expected;
        int loops = 0;
        // Run until N2 beats observed or a long timeout.
        while (got < N2 && loops < 5000) begin
            @(posedge clk);
            // Apply stall pattern on out_tready
            if (stall_every > 0 && ((loops % stall_every) == 0))
                out_tready <= 1'b0;
            else
                out_tready <= 1'b1;
            if (out_tvalid && out_tready) begin
                expected = offset + got;
                if (out_tdata !== expected) begin
                    $display("[CAP] FAIL beat %0d: got %0d want %0d", got, out_tdata, expected);
                    fails++;
                end
                got = got + 1;
            end
            loops = loops + 1;
        end
        out_tready <= 1'b0;
        if (got != N2) begin
            $display("[CAP] FAIL: only %0d/%0d beats drained", got, N2);
            fails++;
        end else begin
            $display("[CAP] PASS: drained %0d beats, stall_every=%0d", got, stall_every);
        end
        captured_beats = captured_beats + got;
    endtask

    initial begin : main
        reset_dut();

        // ------------------------------------------------------------------
        // 1) Clean back-to-back capture + steady read
        // ------------------------------------------------------------------
        fork
            drive_capture(/*offset=*/100,  /*start_pulse=*/1);
            drain_capture(/*offset=*/100,  /*stall_every=*/0);
        join

        // ------------------------------------------------------------------
        // 2) Capture + bursty read (stall every other cycle)
        // ------------------------------------------------------------------
        reset_dut();
        fork
            drive_capture(/*offset=*/2000, /*start_pulse=*/1);
            drain_capture(/*offset=*/2000, /*stall_every=*/3);
        join

        // ------------------------------------------------------------------
        // 3) Overrun: second pss_first_beat while pending
        // ------------------------------------------------------------------
        reset_dut();
        // First capture: drive fully, do NOT drain yet
        in_tvalid <= 1'b1;
        pss_first_beat <= 1'b1;
        in_tdata <= 32'd9000;
        @(posedge clk);
        pss_first_beat <= 1'b0;
        for (int n = 1; n < N2; n = n + 1) begin
            in_tdata <= 32'(9000 + n);
            @(posedge clk);
        end
        in_tvalid <= 1'b0;
        // Now overrun: a fresh pss_first_beat with new data
        repeat (4) @(posedge clk);
        @(posedge clk);
        in_tvalid <= 1'b1;
        pss_first_beat <= 1'b1;
        in_tdata <= 32'd500;
        @(posedge clk);
        pss_first_beat <= 1'b0;
        for (int n = 1; n < N2; n = n + 1) begin
            in_tdata <= 32'(500 + n);
            @(posedge clk);
        end
        in_tvalid <= 1'b0;
        // Drain the second capture (offset=500)
        drain_capture(/*offset=*/500, /*stall_every=*/0);
        if (overrun_count == 0) begin
            $display("[CAP] FAIL: overrun_event never fired");
            fails++;
        end else begin
            $display("[CAP] PASS: overrun_event fired (%0d times)", overrun_count);
        end

        if (fails == 0) $display("GATE: PASS_P5_D_SYNC_CAPTURE");
        else            $display("GATE: FAIL_P5_D_SYNC_CAPTURE (fails=%0d)", fails);
        $finish;
    end

    // Count overrun pulses.
    always @(posedge clk) if (overrun_event) overrun_count = overrun_count + 1;

    // Safety timeout.
    initial begin
        #2_000_000;
        $display("[CAP] FAIL: top-level timeout");
        $display("GATE: FAIL_P5_D_SYNC_CAPTURE (timeout)");
        $finish;
    end

endmodule
