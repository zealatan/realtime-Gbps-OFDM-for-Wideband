`timescale 1ns/1ps

module iq_frame_buffer_tb;

    // -----------------------------------------------------------------------
    // DUT parameters — use small DEPTH so fill-to-full runs quickly
    // -----------------------------------------------------------------------
    localparam int DW       = 32;   // DATA_WIDTH
    localparam int AW       = 6;    // ADDR_WIDTH → DEPTH = 64
    localparam int DEPTH    = 64;   // = 2^AW
    localparam int CLK_HALF = 5;    // half-period (ns)
    localparam int TIMEOUT  = 4096;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic              aclk, aresetn;
    logic              capture_start_d;
    logic [DW-1:0]     s_axis_tdata_d;
    logic              s_axis_tvalid_d;
    wire               s_axis_tready;
    logic              s_axis_tlast_d;
    logic              wb_en_d;
    logic [AW-1:0]     wb_addr_d;
    logic [DW-1:0]     wb_data_d;
    logic              rd_en_d;
    logic [AW-1:0]     rd_addr_d;

    wire  [DW-1:0]     rd_data;
    wire  [AW-1:0]     wr_ptr;
    wire  [AW:0]       sample_count;
    wire               capture_done;
    wire               busy;
    wire               full;

    iq_frame_buffer #(
        .DATA_WIDTH (DW),
        .ADDR_WIDTH (AW),
        .DEPTH      (DEPTH)
    ) dut (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .capture_start (capture_start_d),
        .s_axis_tdata  (s_axis_tdata_d),
        .s_axis_tvalid (s_axis_tvalid_d),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast_d),
        .wb_en         (wb_en_d),
        .wb_addr       (wb_addr_d),
        .wb_data       (wb_data_d),
        .rd_en         (rd_en_d),
        .rd_addr       (rd_addr_d),
        .rd_data       (rd_data),
        .wr_ptr        (wr_ptr),
        .sample_count  (sample_count),
        .capture_done  (capture_done),
        .busy          (busy),
        .full          (full)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // Scoreboard helpers
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp) begin $display("[PASS] %s", nm); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0b  exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_data(input string nm, input logic [DW-1:0] got, input logic [DW-1:0] exp);
        if (got === exp) begin $display("[PASS] %s  =0x%08h", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got=0x%08h  exp=0x%08h", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_cnt(input string nm, input logic [AW:0] got, input logic [AW:0] exp);
        if (got === exp) begin $display("[PASS] %s  =%0d", nm, got); pass_cnt++; end
        else begin $display("[FAIL] %s  got=%0d  exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // PRNG
    // -----------------------------------------------------------------------
    function automatic [31:0] xorshift32(input [31:0] s);
        logic [31:0] x;
        x = s ^ (s << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
        return x;
    endfunction

    // -----------------------------------------------------------------------
    // Helper: fill n samples via AXI-Stream (capture_start then data).
    // Returns the posedge at which capture_done fires (caller checks immediately).
    // The negedge before data[0] is separated from capture_start by one clock.
    // -----------------------------------------------------------------------
    task automatic fill(
        input logic [DW-1:0] data[],
        input int            n
    );
        // Pulse capture_start
        @(negedge aclk); capture_start_d = 1'b1;
        @(negedge aclk); capture_start_d = 1'b0;
        // Stream data — drive on negedge; module accepts on next posedge
        for (int i = 0; i < n; i++) begin
            @(negedge aclk);
            s_axis_tdata_d  = data[i];
            s_axis_tvalid_d = 1'b1;
            s_axis_tlast_d  = (i == n - 1) ? 1'b1 : 1'b0;
        end
        // capture_done fires on the posedge that processes data_last
        @(posedge aclk); #1;
        // Deassert stream
        @(negedge aclk);
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Helper: read n consecutive locations starting at base; store in got[].
    // Returns on the posedge after the nth read (1-clock latency per read).
    // -----------------------------------------------------------------------
    task automatic read_n(
        input  int           base,
        input  int           n,
        output logic [DW-1:0] got[]
    );
        got = new[n];
        for (int i = 0; i < n; i++) begin
            @(negedge aclk);
            rd_en_d   = 1'b1;
            rd_addr_d = AW'(unsigned'(base + i));
            @(posedge aclk); #1;
            got[i] = rd_data;
        end
        @(negedge aclk); rd_en_d = 1'b0;
    endtask

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [DW-1:0] data_a[], data_b[], got[];
    logic [31:0] prng;

    initial begin
        // Default inputs
        aresetn         = 1'b0;
        capture_start_d = 1'b0;
        s_axis_tdata_d  = '0;
        s_axis_tvalid_d = 1'b0;
        s_axis_tlast_d  = 1'b0;
        wb_en_d         = 1'b0;
        wb_addr_d       = '0;
        wb_data_d       = '0;
        rd_en_d         = 1'b0;
        rd_addr_d       = '0;
        pass_cnt = 0; fail_cnt = 0;

        // ----------------------------------------------------------------
        // T1: reset state
        // ----------------------------------------------------------------
        repeat(3) @(negedge aclk);
        chk     ("T1 busy=0 in reset",          busy,         1'b0);
        chk     ("T1 full=0 in reset",           full,         1'b0);
        chk     ("T1 capture_done=0 in reset",   capture_done, 1'b0);
        chk_cnt ("T1 sample_count=0 in reset",   sample_count, '0);

        @(negedge aclk); aresetn = 1'b1;

        // ----------------------------------------------------------------
        // T2: single sample (tlast on first beat)
        // ----------------------------------------------------------------
        data_a = new[1]; data_a[0] = 32'hDEAD_BEEF;
        fill(data_a, 1);
        chk    ("T2 capture_done",          capture_done, 1'b1);
        chk    ("T2 busy=0 after done",     busy,         1'b0);
        chk_cnt("T2 sample_count=1",        sample_count, (AW+1)'(1));

        // ----------------------------------------------------------------
        // T3: 4-sample fill
        // ----------------------------------------------------------------
        data_a = new[4];
        data_a[0]=32'h0000_0001; data_a[1]=32'h0000_0002;
        data_a[2]=32'h0000_0003; data_a[3]=32'h0000_0004;
        fill(data_a, 4);
        chk    ("T3 capture_done",          capture_done, 1'b1);
        chk_cnt("T3 sample_count=4",        sample_count, (AW+1)'(4));
        chk    ("T3 not full",              full,         1'b0);

        // ----------------------------------------------------------------
        // T4: read all 4 samples back (1-clock latency)
        // ----------------------------------------------------------------
        got = new[4];
        read_n(0, 4, got);
        for (int i = 0; i < 4; i++)
            chk_data($sformatf("T4 rd_data[%0d]", i), got[i], data_a[i]);

        // ----------------------------------------------------------------
        // T5: read latency = exactly 1 clock
        //     Present rd_addr on negedge; rd_data valid on following posedge+#1.
        // ----------------------------------------------------------------
        // Re-use data from T3 in the buffer.
        @(negedge aclk); rd_en_d = 1'b1; rd_addr_d = AW'(2);  // address 2 → data_a[2]=3
        @(posedge aclk); #1;
        chk_data("T5 rd_data valid 1 clock after rd_addr", rd_data, data_a[2]);
        // Change address immediately; old rd_data must still hold until next posedge
        @(negedge aclk); rd_addr_d = AW'(3);  // address 3 → data_a[3]=4
        @(posedge aclk); #1;
        chk_data("T5 consecutive read addr 3", rd_data, data_a[3]);
        @(negedge aclk); rd_en_d = 1'b0;

        // ----------------------------------------------------------------
        // T6: fill to DEPTH (all 64 entries) — tests full flag
        // ----------------------------------------------------------------
        data_b = new[DEPTH];
        for (int i = 0; i < DEPTH; i++) data_b[i] = 32'(unsigned'(i * 7 + 1));
        // Send DEPTH samples WITHOUT tlast; buffer terminates on full condition
        @(negedge aclk); capture_start_d = 1'b1;
        @(negedge aclk); capture_start_d = 1'b0;
        for (int i = 0; i < DEPTH; i++) begin
            @(negedge aclk);
            s_axis_tdata_d  = data_b[i];
            s_axis_tvalid_d = 1'b1;
            s_axis_tlast_d  = 1'b0;  // no tlast — buffer self-terminates on full
        end
        @(posedge aclk); #1;
        chk    ("T6 capture_done on full",    capture_done, 1'b1);
        chk    ("T6 full=1",                  full,         1'b1);
        chk_cnt("T6 sample_count=DEPTH",      sample_count, (AW+1)'(unsigned'(DEPTH)));
        @(negedge aclk); s_axis_tvalid_d = 1'b0;

        // ----------------------------------------------------------------
        // T7: tready=0 when full (no capture running)
        // ----------------------------------------------------------------
        @(posedge aclk); #1;
        chk("T7 tready=0 when full (no capture)", s_axis_tready, 1'b0);

        // ----------------------------------------------------------------
        // T8: verify all DEPTH samples readable after full fill
        // ----------------------------------------------------------------
        got = new[DEPTH];
        read_n(0, DEPTH, got);
        begin
            int mismatches = 0;
            for (int i = 0; i < DEPTH; i++) begin
                if (got[i] !== data_b[i]) mismatches++;
            end
            if (mismatches == 0) begin
                $display("[PASS] T8 full read-back: all %0d samples correct", DEPTH);
                pass_cnt++;
            end else begin
                $display("[FAIL] T8 full read-back: %0d mismatches out of %0d", mismatches, DEPTH);
                fail_cnt++;
            end
        end

        // ----------------------------------------------------------------
        // T9: write-back (wb_en) overwrites a location; verify read returns new value
        // ----------------------------------------------------------------
        @(negedge aclk);
        wb_en_d   = 1'b1;
        wb_addr_d = AW'(10);
        wb_data_d = 32'hCAFE_BABE;
        @(negedge aclk);
        wb_en_d = 1'b0;
        // Read it back (1-clock latency)
        @(negedge aclk); rd_en_d = 1'b1; rd_addr_d = AW'(10);
        @(posedge aclk); #1;
        chk_data("T9 wb overwrites addr 10", rd_data, 32'hCAFE_BABE);
        @(negedge aclk); rd_en_d = 1'b0;

        // ----------------------------------------------------------------
        // T10: tready=0 while wb_en is asserted (busy=1 case)
        //      Start a capture but hold valid=0, then assert wb_en.
        // ----------------------------------------------------------------
        @(negedge aclk); capture_start_d = 1'b1;
        @(negedge aclk); capture_start_d = 1'b0;
        // busy=1 now, no stream data yet
        @(posedge aclk); #1;
        chk("T10 tready=1 when busy and no wb", s_axis_tready, 1'b1);
        // Assert wb_en → tready should fall
        @(negedge aclk); wb_en_d = 1'b1; wb_addr_d = AW'(5); wb_data_d = 32'h5555_5555;
        @(posedge aclk); #1;
        chk("T10 tready=0 while wb_en active", s_axis_tready, 1'b0);
        @(negedge aclk); wb_en_d = 1'b0;
        @(posedge aclk); #1;
        chk("T10 tready=1 after wb_en deasserted", s_axis_tready, 1'b1);
        // Abort capture cleanly: send 1 sample with tlast
        @(negedge aclk); s_axis_tdata_d=32'h1; s_axis_tvalid_d=1; s_axis_tlast_d=1;
        @(posedge aclk); #1;
        @(negedge aclk); s_axis_tvalid_d=0; s_axis_tlast_d=0;

        // ----------------------------------------------------------------
        // T11: capture_done is exactly 1-clock wide
        // ----------------------------------------------------------------
        data_a = new[2]; data_a[0]=32'hAAAA; data_a[1]=32'hBBBB;
        fill(data_a, 2);
        // capture_done=1 has been sampled inside fill(); check it deasserts next clock
        @(posedge aclk); #1;
        chk("T11 capture_done=0 one clock after done", capture_done, 1'b0);

        // ----------------------------------------------------------------
        // T12: multiple consecutive captures
        //      Each capture should reset wr_ptr and allow fresh fill.
        // ----------------------------------------------------------------
        for (int cap = 0; cap < 4; cap++) begin
            int n; logic [DW-1:0] d[];
            n = cap + 2;  // 2, 3, 4, 5 samples
            d = new[n];
            foreach (d[i]) d[i] = 32'(unsigned'(cap * 100 + i + 1));
            fill(d, n);
            chk    ($sformatf("T12 cap[%0d] done",      cap), capture_done, 1'b1);
            chk_cnt($sformatf("T12 cap[%0d] count=%0d", cap, n), sample_count, (AW+1)'(unsigned'(n)));
        end

        // ----------------------------------------------------------------
        // T13: wb_en during idle (not busy) writes memory correctly
        // ----------------------------------------------------------------
        // Write three locations, then read back
        for (int i = 0; i < 3; i++) begin
            @(negedge aclk);
            wb_en_d   = 1'b1;
            wb_addr_d = AW'(unsigned'(i * 5));
            wb_data_d = DW'(32'hF0F0_F0F0 + i);
            @(negedge aclk); wb_en_d = 1'b0;
        end
        for (int i = 0; i < 3; i++) begin
            @(negedge aclk); rd_en_d = 1'b1; rd_addr_d = AW'(unsigned'(i * 5));
            @(posedge aclk); #1;
            chk_data($sformatf("T13 wb-idle addr %0d", i*5), rd_data, DW'(32'hF0F0_F0F0 + i));
        end
        @(negedge aclk); rd_en_d = 1'b0;

        // ----------------------------------------------------------------
        // T14: capture_start while busy is silently ignored (no error);
        //      ongoing capture completes normally.
        // ----------------------------------------------------------------
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        // Start a 6-sample capture
        @(negedge aclk); capture_start_d = 1'b1;
        @(negedge aclk); capture_start_d = 1'b0;
        // Send 2 samples
        for (int i = 0; i < 2; i++) begin
            @(negedge aclk);
            s_axis_tdata_d  = 32'(unsigned'(i + 1));
            s_axis_tvalid_d = 1'b1;
            s_axis_tlast_d  = 1'b0;
        end
        @(negedge aclk); s_axis_tvalid_d = 1'b0;
        // Now send capture_start while busy
        @(negedge aclk); capture_start_d = 1'b1;
        @(negedge aclk); capture_start_d = 1'b0;
        @(posedge aclk); #1;
        chk("T14 still busy after spurious start", busy, 1'b1);
        // Finish original capture
        for (int i = 2; i < 6; i++) begin
            @(negedge aclk);
            s_axis_tdata_d  = 32'(unsigned'(i + 1));
            s_axis_tvalid_d = 1'b1;
            s_axis_tlast_d  = (i == 5) ? 1'b1 : 1'b0;
        end
        @(posedge aclk); #1;
        chk    ("T14 original capture completed", capture_done, 1'b1);
        chk_cnt("T14 sample_count=6",             sample_count, (AW+1)'(6));
        @(negedge aclk); s_axis_tvalid_d = 1'b0; s_axis_tlast_d = 1'b0;

        // ----------------------------------------------------------------
        // T15: PRNG smoke — fill 32 samples, verify all reads match
        // ----------------------------------------------------------------
        @(negedge aclk); aresetn = 1'b0;
        @(negedge aclk); aresetn = 1'b1;
        prng = 32'hFEED_FACE;
        begin
            int smoke_n = 32;
            logic [DW-1:0] smoke_data[], smoke_got[];
            int mismatches;

            smoke_data = new[smoke_n];
            smoke_got  = new[smoke_n];
            for (int i = 0; i < smoke_n; i++) begin
                prng = xorshift32(prng);
                smoke_data[i] = prng;
            end

            fill(smoke_data, smoke_n);
            chk    ("T15 smoke fill done",           capture_done, 1'b1);
            chk_cnt("T15 smoke count=32",             sample_count, (AW+1)'(32));

            read_n(0, smoke_n, smoke_got);
            mismatches = 0;
            for (int i = 0; i < smoke_n; i++) begin
                if (smoke_got[i] !== smoke_data[i]) mismatches++;
            end
            if (mismatches == 0) begin
                $display("[PASS] T15 PRNG smoke: 32/32 samples match");
                pass_cnt++;
            end else begin
                $display("[FAIL] T15 PRNG smoke: %0d mismatches", mismatches);
                fail_cnt++;
            end
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
