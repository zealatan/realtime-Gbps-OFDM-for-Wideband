`timescale 1ns/1ps

module axis_add_one_tb;

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    logic aclk   = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    logic [31:0] s_axis_tdata;
    logic        s_axis_tvalid;
    wire         s_axis_tready;
    logic        s_axis_tlast;

    wire  [31:0] m_axis_tdata;
    wire         m_axis_tvalid;
    logic        m_axis_tready;
    wire         m_axis_tlast;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    axis_add_one #(.DATA_WIDTH(32)) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    // ----------------------------------------------------------------
    // Check infrastructure
    // ----------------------------------------------------------------
    integer check_count = 0;
    integer fail_count  = 0;

    task check_eq;
        input [31:0] actual;
        input [31:0] expected;
        input [127:0] label;
        begin
            check_count = check_count + 1;
            if (actual !== expected) begin
                $display("[FAIL] %s: expected 0x%08X got 0x%08X", label, expected, actual);
                fail_count = fail_count + 1;
            end else
                $display("[PASS] %s: 0x%08X", label, actual);
        end
    endtask

    task check_bit1;
        input actual;
        input expected;
        input [127:0] label;
        begin
            check_count = check_count + 1;
            if (actual !== expected) begin
                $display("[FAIL] %s: expected %0b got %0b", label, expected, actual);
                fail_count = fail_count + 1;
            end else
                $display("[PASS] %s: %0b", label, actual);
        end
    endtask

    // ----------------------------------------------------------------
    // Scoreboard: simple array FIFO; push on input acceptance,
    //             pop+compare on output beat.
    // ----------------------------------------------------------------
    logic [31:0] sb_data [0:255];
    logic        sb_last [0:255];
    integer      sb_wr = 0;
    integer      sb_rd = 0;

    task sb_push;
        input [31:0] data;
        input        last;
        begin
            sb_data[sb_wr & 8'hFF] = data;
            sb_last[sb_wr & 8'hFF] = last;
            sb_wr = sb_wr + 1;
        end
    endtask

    // Compare output beat against scoreboard head, dequeue.
    task sb_check_beat;
        input integer beat_idx;
        begin : sb_chk
            logic [31:0] exp_d;
            logic        exp_l;
            if (sb_rd === sb_wr) begin
                $display("[FAIL] scoreboard empty at output beat %0d", beat_idx);
                fail_count = fail_count + 1;
            end else begin
                exp_d = sb_data[sb_rd & 8'hFF];
                exp_l = sb_last[sb_rd & 8'hFF];
                sb_rd = sb_rd + 1;
                check_count = check_count + 1;
                if (m_axis_tdata !== exp_d) begin
                    $display("[FAIL] beat %0d tdata: expected 0x%08X got 0x%08X",
                             beat_idx, exp_d, m_axis_tdata);
                    fail_count = fail_count + 1;
                end else
                    $display("[PASS] beat %0d tdata: 0x%08X", beat_idx, m_axis_tdata);
                check_count = check_count + 1;
                if (m_axis_tlast !== exp_l) begin
                    $display("[FAIL] beat %0d tlast: expected %0b got %0b",
                             beat_idx, exp_l, m_axis_tlast);
                    fail_count = fail_count + 1;
                end else
                    $display("[PASS] beat %0d tlast: %0b", beat_idx, m_axis_tlast);
            end
        end
    endtask

    // ----------------------------------------------------------------
    // Task: do_reset
    // ----------------------------------------------------------------
    task do_reset;
        begin
            @(negedge aclk);
            aresetn       = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 32'h0;
            s_axis_tlast  = 1'b0;
            m_axis_tready = 1'b1;
            repeat(4) @(posedge aclk);
            @(negedge aclk);
            aresetn = 1'b1;
            repeat(2) @(posedge aclk);
            sb_wr = 0; sb_rd = 0;
        end
    endtask

    // ----------------------------------------------------------------
    // Task: send_beat
    //   Drive one beat on slave input. Waits for handshake on posedge.
    //   Pushes expected output (data+1, tlast) to scoreboard.
    //   Returns at negedge after deassert.
    //   CONTRACT: caller must read output BEFORE calling send_beat again
    //             when m_tready=1, to avoid missing the 1-cycle output window.
    // ----------------------------------------------------------------
    task send_beat;
        input [31:0] data;
        input        last;
        begin : sb_task
            integer timeout;
            @(negedge aclk);
            s_axis_tdata  = data;
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = last;
            timeout = 0;
            @(posedge aclk);
            while (!s_axis_tready) begin
                timeout = timeout + 1;
                if (timeout > 200)
                    $fatal(1, "[FATAL] send_beat tready timeout data=0x%08X", data);
                @(posedge aclk);
            end
            // Handshake complete: push expected output to scoreboard
            sb_push(data + 32'h1, last);
            @(negedge aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = 32'h0;
            s_axis_tlast  = 1'b0;
        end
    endtask

    // ----------------------------------------------------------------
    // Task: wait_output_beat
    //   Waits for m_axis_tvalid=1 then checks against scoreboard.
    //   Call immediately after send_beat when m_tready=1 to catch the
    //   1-cycle output window.
    // ----------------------------------------------------------------
    task wait_output_beat;
        input integer beat_idx;
        begin : wob_task
            integer timeout;
            timeout = 0;
            @(posedge aclk);
            while (!m_axis_tvalid) begin
                timeout = timeout + 1;
                if (timeout > 200)
                    $fatal(1, "[FATAL] wait_output_beat timeout beat=%0d", beat_idx);
                @(posedge aclk);
            end
            sb_check_beat(beat_idx);
        end
    endtask

    // ================================================================
    // Loop variables (declared at module level for xsim compatibility)
    // ================================================================
    integer t3_i, t4_bi, t6_i, t8_i;
    integer t10_iter, t10_j, t10_len, t10_beat_cnt;
    integer t5_timeout_v;
    logic [31:0] t5_saved_tdata;
    logic        t5_saved_tlast;
    logic [31:0] lfsr;

    function automatic [31:0] lfsr_next;
        input [31:0] s;
        lfsr_next = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
    endfunction

    // ================================================================
    // MAIN
    // ================================================================
    initial begin

        do_reset();

        // ============================================================
        // TEST 1 — reset defaults (3 checks)
        // ============================================================
        $display("[INFO] Test 1: reset defaults");
        @(posedge aclk);
        check_bit1(m_axis_tvalid, 1'b0, "T1 m_tvalid=0 after reset");
        check_eq  (m_axis_tdata,  32'h0, "T1 m_tdata=0 after reset");
        check_bit1(m_axis_tlast,  1'b0,  "T1 m_tlast=0 after reset");

        // ============================================================
        // TEST 2 — single-beat transfer (2 checks)
        // ============================================================
        $display("[INFO] Test 2: single-beat transfer");
        m_axis_tready = 1'b1;
        send_beat(32'hDEAD_BEEF, 1'b1);
        wait_output_beat(0);

        // ============================================================
        // TEST 3 — multi-beat packet, interleaved send+check (8 checks)
        // ============================================================
        $display("[INFO] Test 3: multi-beat packet (4 beats)");
        m_axis_tready = 1'b1;
        for (t3_i = 0; t3_i < 4; t3_i = t3_i + 1) begin
            send_beat(32'hAAAA_0000 + t3_i, (t3_i == 3) ? 1'b1 : 1'b0);
            wait_output_beat(t3_i);
        end

        // ============================================================
        // TEST 4 — continuous back-to-back throughput (18 checks)
        // Tests simultaneous consume+accept (branch 2 of DUT fires with
        // m_tvalid=1 AND m_tready=1 AND s_tvalid=1 AND s_tready=1).
        // ============================================================
        $display("[INFO] Test 4: back-to-back throughput (6 beats)");
        m_axis_tready = 1'b1;
        @(negedge aclk);
        s_axis_tvalid = 1'b1;
        s_axis_tdata  = 32'hCCCC_0000;
        s_axis_tlast  = 1'b0;
        @(posedge aclk);  // beat 0 accepted; no output visible yet
        if (!s_axis_tready)
            $fatal(1, "[FATAL] T4 s_tready deasserted at beat 0");

        for (t4_bi = 1; t4_bi <= 5; t4_bi = t4_bi + 1) begin
            @(negedge aclk);
            s_axis_tdata = 32'hCCCC_0000 + t4_bi;
            s_axis_tlast = (t4_bi == 5) ? 1'b1 : 1'b0;
            @(posedge aclk);
            // Output of beat t4_bi-1 now visible (1-cycle registered latency)
            check_bit1(m_axis_tvalid, 1'b1, "T4 m_tvalid during pipeline");
            // expected tdata = 0xCCCC_0000 + (t4_bi-1) + 1 = 0xCCCC_0000 + t4_bi
            check_eq(m_axis_tdata, 32'hCCCC_0000 + t4_bi, "T4 tdata");
            check_bit1(m_axis_tlast, 1'b0, "T4 tlast=0 (not last)");
            if (!s_axis_tready)
                $fatal(1, "[FATAL] T4 s_tready deasserted at beat %0d", t4_bi);
        end
        @(negedge aclk);
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 32'h0;
        s_axis_tlast  = 1'b0;
        @(posedge aclk);  // output of beat 5 (last)
        check_bit1(m_axis_tvalid, 1'b1,         "T4 m_tvalid last beat");
        check_eq  (m_axis_tdata,  32'hCCCC_0006, "T4 tdata last beat");
        check_bit1(m_axis_tlast,  1'b1,          "T4 tlast=1 last beat");

        // ============================================================
        // TEST 5 — output backpressure (11 checks)
        // ============================================================
        $display("[INFO] Test 5: output backpressure");
        // Drive m_tready=0 at negedge to avoid a race condition where the
        // DUT's always @posedge evaluates m_tready=0 before firing branch 3
        // (which would leave m_tvalid stuck at 1, stalling s_tready).
        @(negedge aclk);
        m_axis_tready = 1'b0;
        send_beat(32'hBBBB_1234, 1'b1);
        // Output valid one cycle after acceptance
        @(posedge aclk);
        begin : t5_wait_valid
            t5_timeout_v = 0;
            while (!m_axis_tvalid) begin
                t5_timeout_v = t5_timeout_v + 1;
                if (t5_timeout_v > 50)
                    $fatal(1, "[FATAL] T5 m_tvalid never asserted");
                @(posedge aclk);
            end
        end
        t5_saved_tdata = m_axis_tdata;
        t5_saved_tlast = m_axis_tlast;
        // Verify DUT holds output stable for 3 additional cycles (9 checks)
        repeat(3) begin
            @(posedge aclk);
            check_bit1(m_axis_tvalid, 1'b1,           "T5 m_tvalid held");
            check_eq  (m_axis_tdata,  t5_saved_tdata,  "T5 m_tdata stable");
            check_bit1(m_axis_tlast,  t5_saved_tlast,  "T5 m_tlast stable");
        end
        // Release backpressure and consume (2 checks via scoreboard)
        @(negedge aclk);
        m_axis_tready = 1'b1;
        @(posedge aclk);
        sb_check_beat(0);

        // ============================================================
        // TEST 6 — input stall: idle cycles between beats (6 checks)
        // ============================================================
        $display("[INFO] Test 6: input stall");
        m_axis_tready = 1'b1;
        for (t6_i = 0; t6_i < 3; t6_i = t6_i + 1) begin
            // Insert 2 idle cycles before beats 1 and 2
            if (t6_i > 0) begin
                @(negedge aclk); repeat(2) @(posedge aclk);
            end
            send_beat(32'hEEEE_0010 * (t6_i + 1), (t6_i == 2) ? 1'b1 : 1'b0);
            wait_output_beat(t6_i);
        end

        // ============================================================
        // TEST 7 — wraparound: 0xFFFFFFFF + 1 = 0 (2 checks)
        // ============================================================
        $display("[INFO] Test 7: wraparound");
        m_axis_tready = 1'b1;
        send_beat(32'hFFFF_FFFF, 1'b1);
        wait_output_beat(0);

        // ============================================================
        // TEST 8 — tlast propagation across three packets (12 checks)
        // ============================================================
        $display("[INFO] Test 8: tlast propagation");
        m_axis_tready = 1'b1;
        begin : t8_blk
            // Packet A: single-beat packet (tlast=1)
            send_beat(32'h1111_0001, 1'b1); wait_output_beat(0);
            // Packet B: 3-beat packet (tlast on beat 2)
            for (t8_i = 0; t8_i < 3; t8_i = t8_i + 1) begin
                send_beat(32'h2222_0000 + t8_i, (t8_i == 2) ? 1'b1 : 1'b0);
                wait_output_beat(t8_i);
            end
            // Packet C: 2-beat packet (tlast on beat 1)
            send_beat(32'h3333_0001, 1'b0); wait_output_beat(0);
            send_beat(32'h3333_0002, 1'b1); wait_output_beat(1);
        end

        // ============================================================
        // TEST 9 — reset mid-packet (6 checks)
        // ============================================================
        $display("[INFO] Test 9: reset mid-packet");
        @(negedge aclk);  // drive m_tready at negedge (avoid posedge race)
        m_axis_tready = 1'b0;
        send_beat(32'hF00D_0001, 1'b0);
        // Buffer now holds the output (m_tready=0, output stalled)
        repeat(2) @(posedge aclk);
        // Assert reset mid-packet
        @(negedge aclk); aresetn = 1'b0;
        repeat(4) @(posedge aclk);
        // Discard stale scoreboard entry
        sb_rd = sb_wr;
        // Verify reset cleared the buffer (3 checks)
        @(posedge aclk);
        check_bit1(m_axis_tvalid, 1'b0, "T9 m_tvalid=0 after reset");
        check_eq  (m_axis_tdata,  32'h0, "T9 m_tdata=0 after reset");
        check_bit1(m_axis_tlast,  1'b0,  "T9 m_tlast=0 after reset");
        // Release reset
        @(negedge aclk); aresetn = 1'b1;
        repeat(2) @(posedge aclk);
        // s_tready should be 1 (buffer empty) (1 check)
        @(posedge aclk);
        check_bit1(s_axis_tready, 1'b1, "T9 s_tready=1 after reset");
        // Recovery: fresh packet must work correctly (2 checks)
        @(negedge aclk);
        m_axis_tready = 1'b1;
        send_beat(32'hF00D_CAFE, 1'b1);
        wait_output_beat(0);

        // ============================================================
        // TEST 10 — smoke: 10 packets, LFSR data, occasional input idles
        //           Lengths: 1,2,3,4,5,6,7,8,1,2 → 39 beats → 78 checks
        // ============================================================
        $display("[INFO] Test 10: LFSR smoke test");
        m_axis_tready = 1'b1;
        lfsr = 32'hA5A5_1234;
        t10_beat_cnt = 0;

        for (t10_iter = 0; t10_iter < 10; t10_iter = t10_iter + 1) begin
            t10_len = (t10_iter % 8) + 1;  // 1,2,3,4,5,6,7,8,1,2
            for (t10_j = 0; t10_j < t10_len; t10_j = t10_j + 1) begin
                // Occasional input idle: every 3rd beat of a packet
                if (t10_j > 0 && (t10_j % 3) == 0) begin
                    @(negedge aclk); repeat(2) @(posedge aclk);
                end
                lfsr = lfsr_next(lfsr);
                send_beat(lfsr, (t10_j == t10_len - 1) ? 1'b1 : 1'b0);
                wait_output_beat(t10_beat_cnt);
                t10_beat_cnt = t10_beat_cnt + 1;
            end
        end

        // ============================================================
        // SUMMARY
        // ============================================================
        $display("[INFO] ===== SIMULATION COMPLETE =====");
        $display("[INFO] Total checks: %0d", check_count);
        $display("[INFO] Failures:     %0d", fail_count);
        if (fail_count == 0)
            $display("[PASS] All checks passed.");
        else
            $display("[FAIL] %0d check(s) failed.", fail_count);

        $finish;
    end

endmodule
