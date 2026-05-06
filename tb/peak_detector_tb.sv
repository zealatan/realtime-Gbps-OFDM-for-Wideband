`timescale 1ns/1ps

module peak_detector_tb;

    // -----------------------------------------------------------------------
    // DUT parameters
    // -----------------------------------------------------------------------
    localparam int MW       = 64;   // METRIC_WIDTH
    localparam int IW       = 9;    // INDEX_WIDTH
    localparam int CW       = 10;   // COUNT_WIDTH
    localparam int CLK_HALF = 5;    // half-period (ns)
    localparam int TIMEOUT  = 2048; // max clocks to wait for done

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic              aclk, aresetn;
    logic              start_d;
    logic [CW-1:0]     max_count_d;
    logic [MW-1:0]     data_in_d;
    logic              data_valid_d;
    logic              data_last_d;

    wire  [IW-1:0]     peak_index;
    wire  [MW-1:0]     peak_value;
    wire               done;
    wire               busy;
    wire               error;

    peak_detector #(
        .METRIC_WIDTH (MW),
        .INDEX_WIDTH  (IW),
        .COUNT_WIDTH  (CW)
    ) dut (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (start_d),
        .max_count   (max_count_d),
        .data_in     (data_in_d),
        .data_valid  (data_valid_d),
        .data_last   (data_last_d),
        .peak_index  (peak_index),
        .peak_value  (peak_value),
        .done        (done),
        .busy        (busy),
        .error       (error)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Golden model
    // -----------------------------------------------------------------------
    // Returns the 0-based index of the first occurrence of the maximum value.
    function automatic [IW-1:0] golden_idx(input logic [MW-1:0] v[], input int n);
        logic [MW-1:0] mx; logic [IW-1:0] idx;
        mx = '0; idx = '0;
        for (int i = 0; i < n; i++) begin
            if (v[i] > mx) begin mx = v[i]; idx = IW'(unsigned'(i)); end
        end
        return idx;
    endfunction

    function automatic [MW-1:0] golden_val(input logic [MW-1:0] v[], input int n);
        logic [MW-1:0] mx;
        mx = '0;
        for (int i = 0; i < n; i++) if (v[i] > mx) mx = v[i];
        return mx;
    endfunction

    // Xorshift32 PRNG
    function automatic [31:0] xorshift32(input [31:0] s);
        logic [31:0] x;
        x = s ^ (s << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
        return x;
    endfunction

    // -----------------------------------------------------------------------
    // Scan task: pulse start, feed n values, capture outputs on done clock.
    // Drives signals on negedge; samples outputs on posedge+#1.
    // -----------------------------------------------------------------------
    task automatic run_scan(
        input  logic [MW-1:0] vals[],
        input  int            n,
        input  logic [CW-1:0] mc,
        output logic [IW-1:0] out_idx,
        output logic [MW-1:0] out_val,
        output logic          out_done
    );
        int t;
        // --- pulse start ---
        @(negedge aclk);
        start_d     = 1'b1;
        max_count_d = mc;
        @(negedge aclk);
        start_d = 1'b0;
        // --- feed values ---
        for (int i = 0; i < n; i++) begin
            @(negedge aclk);
            data_in_d    = vals[i];
            data_valid_d = 1'b1;
            data_last_d  = (i == n - 1) ? 1'b1 : 1'b0;
        end
        // --- capture done on the posedge immediately after last negedge ---
        @(posedge aclk); #1;
        out_done = done;
        out_idx  = peak_index;
        out_val  = peak_value;
        // --- deassert stream ---
        @(negedge aclk);
        data_valid_d = 1'b0;
        data_last_d  = 1'b0;
        // --- guard: wait until not busy (absorbs pipeline latency if any) ---
        t = 0;
        while (busy) begin
            @(posedge aclk); #1;
            if (++t > TIMEOUT)
                $fatal(1, "[FATAL] run_scan: timeout waiting for busy to deassert");
        end
    endtask

    // -----------------------------------------------------------------------
    // Check helper
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic check(
        input string   nm,
        input logic    got,
        input logic    exp
    );
        if (got === exp) begin
            $display("[PASS] %s", nm);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s  got=%0b  exp=%0b", nm, got, exp);
            fail_cnt++;
        end
    endtask

    task automatic check_idx(input string nm, input logic [IW-1:0] got, input logic [IW-1:0] exp);
        if (got === exp) begin $display("[PASS] %s  idx=%0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got_idx=%0d  exp_idx=%0d", nm, got, exp); fail_cnt++; end
    endtask

    task automatic check_val(input string nm, input logic [MW-1:0] got, input logic [MW-1:0] exp);
        if (got === exp) begin $display("[PASS] %s  val=%0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got_val=%0d  exp_val=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [MW-1:0] vals[];
    logic [IW-1:0] got_idx;
    logic [MW-1:0] got_val;
    logic          got_done;
    logic [MW-1:0] done_clock_val;
    logic [IW-1:0] done_clock_idx;
    logic [31:0]   prng;
    int            smoke_pass, smoke_fail;

    initial begin
        aresetn      = 1'b0;
        start_d      = 1'b0;
        max_count_d  = '0;
        data_in_d    = '0;
        data_valid_d = 1'b0;
        data_last_d  = 1'b0;
        pass_cnt     = 0;
        fail_cnt     = 0;

        // ----------------------------------------------------------------
        // T1: reset state — all outputs clear before aresetn is deasserted
        // ----------------------------------------------------------------
        repeat(3) @(negedge aclk);
        check("T1 reset busy=0",  busy,        1'b0);
        check("T1 reset done=0",  done,        1'b0);
        check("T1 reset error=0", error,       1'b0);

        @(negedge aclk); aresetn = 1'b1;

        // ----------------------------------------------------------------
        // T2: single-element scan — peak at index 0
        // ----------------------------------------------------------------
        vals = new[1]; vals[0] = 64'd42;
        run_scan(vals, 1, 10'd1, got_idx, got_val, got_done);
        check    ("T2 done asserted",    got_done, 1'b1);
        check_idx("T2 peak_index=0",     got_idx,  golden_idx(vals,1));
        check_val("T2 peak_value=42",    got_val,  golden_val(vals,1));

        // ----------------------------------------------------------------
        // T3: maximum at first index
        // ----------------------------------------------------------------
        vals = new[5]; vals[0]=100; vals[1]=20; vals[2]=30; vals[3]=5; vals[4]=1;
        run_scan(vals, 5, 10'd5, got_idx, got_val, got_done);
        check    ("T3 done",      got_done, 1'b1);
        check_idx("T3 peak_index",got_idx,  golden_idx(vals,5));
        check_val("T3 peak_value",got_val,  golden_val(vals,5));

        // ----------------------------------------------------------------
        // T4: maximum at last index
        // ----------------------------------------------------------------
        vals = new[5]; vals[0]=1; vals[1]=5; vals[2]=3; vals[3]=10; vals[4]=999;
        run_scan(vals, 5, 10'd5, got_idx, got_val, got_done);
        check    ("T4 done",      got_done, 1'b1);
        check_idx("T4 peak_index",got_idx,  golden_idx(vals,5));
        check_val("T4 peak_value",got_val,  golden_val(vals,5));

        // ----------------------------------------------------------------
        // T5: maximum in the middle
        // ----------------------------------------------------------------
        vals = new[7]; vals[0]=10; vals[1]=20; vals[2]=5; vals[3]=500; vals[4]=3; vals[5]=8; vals[6]=2;
        run_scan(vals, 7, 10'd7, got_idx, got_val, got_done);
        check    ("T5 done",      got_done, 1'b1);
        check_idx("T5 peak_index",got_idx,  golden_idx(vals,7));
        check_val("T5 peak_value",got_val,  golden_val(vals,7));

        // ----------------------------------------------------------------
        // T6: all equal — tie-break: first occurrence wins (index 0)
        // ----------------------------------------------------------------
        vals = new[8];
        foreach (vals[i]) vals[i] = 64'd77;
        run_scan(vals, 8, 10'd8, got_idx, got_val, got_done);
        check    ("T6 done",             got_done, 1'b1);
        check_idx("T6 all-equal idx=0",  got_idx,  9'd0);
        check_val("T6 all-equal val=77", got_val,  64'd77);

        // ----------------------------------------------------------------
        // T7: strictly increasing — peak at last index (n-1)
        // ----------------------------------------------------------------
        begin
            int n = 10;
            vals = new[n];
            foreach (vals[i]) vals[i] = MW'(unsigned'(i + 1));
            run_scan(vals, n, CW'(unsigned'(n)), got_idx, got_val, got_done);
            check    ("T7 done",               got_done, 1'b1);
            check_idx("T7 increasing last idx",got_idx,  IW'(unsigned'(n-1)));
            check_val("T7 increasing last val",got_val,  MW'(unsigned'(n)));
        end

        // ----------------------------------------------------------------
        // T8: strictly decreasing — peak at first index (0)
        // ----------------------------------------------------------------
        begin
            int n = 10;
            vals = new[n];
            foreach (vals[i]) vals[i] = MW'(unsigned'(n - i));
            run_scan(vals, n, CW'(unsigned'(n)), got_idx, got_val, got_done);
            check    ("T8 done",                 got_done, 1'b1);
            check_idx("T8 decreasing first idx", got_idx,  9'd0);
            check_val("T8 decreasing first val", got_val,  MW'(unsigned'(n)));
        end

        // ----------------------------------------------------------------
        // T9: two equal maximums — first occurrence wins
        // ----------------------------------------------------------------
        vals = new[6]; vals[0]=1; vals[1]=500; vals[2]=3; vals[3]=500; vals[4]=2; vals[5]=1;
        run_scan(vals, 6, 10'd6, got_idx, got_val, got_done);
        check    ("T9 done",               got_done,  1'b1);
        check_idx("T9 tie first idx=1",    got_idx,   9'd1);   // first of the two 500s
        check_val("T9 tie val=500",         got_val,   64'd500);

        // ----------------------------------------------------------------
        // T10: done is exactly one clock wide
        // ----------------------------------------------------------------
        vals = new[3]; vals[0]=1; vals[1]=2; vals[2]=3;
        // Manual drive (don't use run_scan so we can sample clock-after-done)
        @(negedge aclk); start_d = 1'b1; max_count_d = 10'd3;
        @(negedge aclk); start_d = 1'b0;
        for (int i = 0; i < 3; i++) begin
            @(negedge aclk);
            data_in_d    = vals[i];
            data_valid_d = 1'b1;
            data_last_d  = (i == 2) ? 1'b1 : 1'b0;
        end
        // posedge after data_last negedge: done=1
        @(posedge aclk); #1;
        check("T10 done=1 on completion clock",  done, 1'b1);
        done_clock_idx = peak_index;
        done_clock_val = peak_value;
        // one clock later: done should have deasserted
        @(posedge aclk); #1;
        check("T10 done=0 one clock after completion", done, 1'b0);
        // values must still hold
        check_idx("T10 peak_index stable after done", peak_index, done_clock_idx);
        check_val("T10 peak_value stable after done", peak_value, done_clock_val);
        @(negedge aclk); data_valid_d = 0; data_last_d = 0;

        // ----------------------------------------------------------------
        // T11: busy deasserts on the done clock (same posedge as done=1)
        // ----------------------------------------------------------------
        vals = new[2]; vals[0]=9; vals[1]=3;
        @(negedge aclk); start_d = 1'b1; max_count_d = 10'd2;
        @(negedge aclk); start_d = 1'b0;
        for (int i = 0; i < 2; i++) begin
            @(negedge aclk);
            data_in_d    = vals[i];
            data_valid_d = 1'b1;
            data_last_d  = (i == 1) ? 1'b1 : 1'b0;
        end
        @(posedge aclk); #1;
        check("T11 done=1 at end",   done, 1'b1);
        check("T11 busy=0 at done",  busy, 1'b0);
        @(negedge aclk); data_valid_d = 0; data_last_d = 0;

        // ----------------------------------------------------------------
        // T12: start-while-busy sets error (sticky)
        // ----------------------------------------------------------------
        // Reset to clear error from any previous test, then run this test.
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;

        vals = new[6]; foreach (vals[i]) vals[i] = MW'(unsigned'(i + 1));
        // Start first scan
        @(negedge aclk); start_d = 1'b1; max_count_d = 10'd6;
        @(negedge aclk); start_d = 1'b0;
        // Send 2 values without last
        for (int i = 0; i < 2; i++) begin
            @(negedge aclk);
            data_in_d    = vals[i];
            data_valid_d = 1'b1;
            data_last_d  = 1'b0;
        end
        @(negedge aclk); data_valid_d = 0;
        // Mid-scan start pulse → should set error
        @(negedge aclk); start_d = 1'b1;
        @(negedge aclk); start_d = 1'b0;
        @(posedge aclk); #1;
        check("T12 error set by start-while-busy", error, 1'b1);
        // Finish the original scan cleanly
        for (int i = 2; i < 6; i++) begin
            @(negedge aclk);
            data_in_d    = vals[i];
            data_valid_d = 1'b1;
            data_last_d  = (i == 5) ? 1'b1 : 1'b0;
        end
        @(posedge aclk); #1; // consume done
        @(negedge aclk); data_valid_d = 0; data_last_d = 0;
        // Verify error is still sticky after scan completes
        @(posedge aclk); #1;
        check("T12 error sticky after done", error, 1'b1);

        // ----------------------------------------------------------------
        // T13: consecutive scans without gaps — done then immediately start
        // ----------------------------------------------------------------
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        begin
            logic [IW-1:0] prev_idx;
            logic [MW-1:0] prev_val;
            for (int scan_n = 0; scan_n < 4; scan_n++) begin
                vals = new[scan_n + 1];
                foreach (vals[i]) vals[i] = MW'(unsigned'((scan_n + 1) * 10 - i));
                run_scan(vals, scan_n + 1, CW'(unsigned'(scan_n + 1)),
                         got_idx, got_val, got_done);
                check    ($sformatf("T13 scan[%0d] done",      scan_n), got_done, 1'b1);
                check_idx($sformatf("T13 scan[%0d] peak_idx",  scan_n), got_idx,
                          golden_idx(vals, scan_n + 1));
                check_val($sformatf("T13 scan[%0d] peak_val",  scan_n), got_val,
                          golden_val(vals, scan_n + 1));
            end
        end

        // ----------------------------------------------------------------
        // T14: 256-element array (timing metric use case)
        // ----------------------------------------------------------------
        begin
            int n = 256;
            vals = new[n];
            foreach (vals[i]) vals[i] = MW'(unsigned'(i));
            // Make index 200 the maximum
            vals[200] = 64'hFF_FFFF_FFFF;
            run_scan(vals, n, CW'(unsigned'(n)), got_idx, got_val, got_done);
            check    ("T14 256-elem done",      got_done, 1'b1);
            check_idx("T14 256-elem peak_idx",  got_idx,  golden_idx(vals,n));
            check_val("T14 256-elem peak_val",  got_val,  golden_val(vals,n));
        end

        // ----------------------------------------------------------------
        // T15: 511-element array (Meyr correlation use case)
        // ----------------------------------------------------------------
        begin
            int n = 511;
            vals = new[n];
            foreach (vals[i]) vals[i] = MW'(unsigned'(i * 2 + 1));
            vals[255] = 64'hFFFF_FFFF_FFFF_FFFE; // peak at index 255
            run_scan(vals, n, CW'(unsigned'(n)), got_idx, got_val, got_done);
            check    ("T15 511-elem done",      got_done, 1'b1);
            check_idx("T15 511-elem peak_idx",  got_idx,  golden_idx(vals,n));
            check_val("T15 511-elem peak_val",  got_val,  golden_val(vals,n));
        end

        // ----------------------------------------------------------------
        // T16: value = 0 everywhere — peak at index 0, value = 0
        // ----------------------------------------------------------------
        vals = new[4]; foreach (vals[i]) vals[i] = '0;
        run_scan(vals, 4, 10'd4, got_idx, got_val, got_done);
        check    ("T16 all-zero done",         got_done, 1'b1);
        check_idx("T16 all-zero idx=0",        got_idx,  9'd0);
        check_val("T16 all-zero val=0",         got_val,  64'd0);

        // ----------------------------------------------------------------
        // T17: single max value at index 0 among zeros
        // ----------------------------------------------------------------
        vals = new[5]; foreach (vals[i]) vals[i] = '0; vals[0] = 64'd1;
        run_scan(vals, 5, 10'd5, got_idx, got_val, got_done);
        check    ("T17 done",           got_done,  1'b1);
        check_idx("T17 idx=0",          got_idx,   9'd0);
        check_val("T17 val=1",           got_val,   64'd1);

        // ----------------------------------------------------------------
        // T18: max at last index among zeros
        // ----------------------------------------------------------------
        vals = new[5]; foreach (vals[i]) vals[i] = '0; vals[4] = 64'd999;
        run_scan(vals, 5, 10'd5, got_idx, got_val, got_done);
        check    ("T18 done",           got_done,  1'b1);
        check_idx("T18 idx=4",          got_idx,   9'd4);
        check_val("T18 val=999",         got_val,   64'd999);

        // ----------------------------------------------------------------
        // T19: max_count=0 disables overflow check — no error on 10 values
        // ----------------------------------------------------------------
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        begin
            int n = 10;
            vals = new[n];
            foreach (vals[i]) vals[i] = MW'(unsigned'(i + 5));
            run_scan(vals, n, 10'd0, got_idx, got_val, got_done);
            check    ("T19 max_count=0 done",       got_done, 1'b1);
            check    ("T19 max_count=0 no error",   error,    1'b0);
            check_idx("T19 max_count=0 peak_idx",   got_idx,  IW'(unsigned'(n-1)));
        end

        // ----------------------------------------------------------------
        // T20: PRNG smoke — 30 random arrays of random length (1..64)
        //      Verify golden match on every scan; no false errors.
        // ----------------------------------------------------------------
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;

        prng = 32'hC0DE_CAFE;
        smoke_pass = 0; smoke_fail = 0;

        for (int scan_n = 0; scan_n < 30; scan_n++) begin
            int n;
            logic [IW-1:0] exp_idx;
            logic [MW-1:0] exp_val;

            prng = xorshift32(prng);
            n = int'(prng[5:0]) + 1;   // 1..64

            vals = new[n];
            for (int i = 0; i < n; i++) begin
                prng = xorshift32(prng);
                vals[i] = {prng, xorshift32(prng)};  // 64-bit value
            end

            exp_idx = golden_idx(vals, n);
            exp_val = golden_val(vals, n);

            run_scan(vals, n, CW'(unsigned'(n)), got_idx, got_val, got_done);

            if (got_done !== 1'b1 || got_idx !== exp_idx || got_val !== exp_val) begin
                $display("[FAIL] T20 scan[%0d] n=%0d  got_done=%b got_idx=%0d got_val=%0d  exp_idx=%0d exp_val=%0d",
                         scan_n, n, got_done, got_idx, got_val, exp_idx, exp_val);
                smoke_fail++;
            end else begin
                smoke_pass++;
            end

            if (scan_n % 10 == 9)
                $display("[INFO] T20 progress: %0d/30 scans done, %0d pass %0d fail",
                         scan_n+1, smoke_pass, smoke_fail);
        end

        if (smoke_fail == 0) begin
            $display("[PASS] T20 PRNG smoke: 30/30 scans correct");
            pass_cnt++;
        end else begin
            $display("[FAIL] T20 PRNG smoke: %0d failures", smoke_fail);
            fail_cnt++;
        end

        // ----------------------------------------------------------------
        // Final report
        // ----------------------------------------------------------------
        $display("--- %0d PASS  %0d FAIL ---", pass_cnt, fail_cnt);
        if (fail_cnt > 0) $fatal(1, "CI GATE: FAILED");
        $display("CI GATE: PASSED");
        $finish;
    end

endmodule
