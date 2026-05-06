`timescale 1ns/1ps

// frame_detector_tb: 16 test groups, ~55 checks.
//
// DUT parameters (small values for fast simulation):
//   ADDR_WIDTH = 8  → buffer up to 256 samples
//   ENERGY_WIDTH = 40, POWER_WIDTH = 33
//
// The testbench instantiates a small iq_frame_buffer model (reg-array)
// and drives buf_rd_data_I/Q with the correct 1-clock-latency response.
//
// All hex literals use Verilog notation (32'hXXXX), not C-style 0xXXXX.

module frame_detector_tb;

    // -----------------------------------------------------------------------
    // DUT parameters
    // -----------------------------------------------------------------------
    localparam int DW  = 32;
    localparam int AW  = 8;       // ADDR_WIDTH
    localparam int IW  = 8;       // INDEX_WIDTH
    localparam int PW  = 33;      // POWER_WIDTH
    localparam int EW  = 40;      // ENERGY_WIDTH
    localparam int DEP = 256;     // 2^AW
    localparam int CLK_HALF = 5;  // ns
    localparam int TIMEOUT  = 200000;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk, aresetn;
    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    logic               start_d;
    logic [EW-1:0]      threshold_d;
    logic [6:0]         window_len_d;
    logic [3:0]         hit_count_d;
    logic [AW-1:0]      search_base_d;
    logic [AW:0]        search_len_d;

    wire  [AW-1:0]      buf_rd_addr;
    wire                buf_rd_en;
    logic [15:0]        buf_rd_data_I_d;
    logic [15:0]        buf_rd_data_Q_d;

    wire  [IW-1:0]      frame_index;
    wire                frame_found;
    wire                done;
    wire                busy;

    frame_detector #(
        .DATA_WIDTH  (DW),
        .ADDR_WIDTH  (AW),
        .INDEX_WIDTH (IW),
        .POWER_WIDTH (PW),
        .ENERGY_WIDTH(EW),
        .WINDOW_LEN  (4),   // small default (overridden per test via window_len_d)
        .HIT_COUNT   (3),
        .THRESHOLD   (100)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .start          (start_d),
        .threshold_in   (threshold_d),
        .window_len_in  (window_len_d),
        .hit_count_in   (hit_count_d),
        .search_base    (search_base_d),
        .search_len     (search_len_d),
        .buf_rd_addr    (buf_rd_addr),
        .buf_rd_en      (buf_rd_en),
        .buf_rd_data_I  (buf_rd_data_I_d),
        .buf_rd_data_Q  (buf_rd_data_Q_d),
        .frame_index    (frame_index),
        .frame_found    (frame_found),
        .done           (done),
        .busy           (busy)
    );

    // -----------------------------------------------------------------------
    // Behavioral memory model: 1-clock registered read (matches iq_frame_buffer)
    // -----------------------------------------------------------------------
    logic [DW-1:0] mem [0:DEP-1];

    always @(posedge aclk) begin
        if (buf_rd_en)
            {buf_rd_data_Q_d, buf_rd_data_I_d} <= mem[buf_rd_addr];
    end

    // -----------------------------------------------------------------------
    // Helpers: scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp) begin $display("[PASS] %s", nm);           pass_cnt++; end
        else             begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_idx(input string nm, input logic [IW-1:0] got, input int exp);
        if (got === exp[IW-1:0])
            begin $display("[PASS] %s  =%0d", nm, got); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d", nm, got, exp); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Helper: fill mem[base..base+n-1] with packed {Q[15:0], I[15:0]}
    //   lo_energy:  I=Q=10  → I^2+Q^2 = 200  (well below any threshold we use)
    //   hi_energy:  I=Q=200 → I^2+Q^2 = 80000
    // -----------------------------------------------------------------------
    localparam logic [15:0] I_LO = 16'sd10;
    localparam logic [15:0] Q_LO = 16'sd10;
    localparam logic [15:0] I_HI = 16'sd200;
    localparam logic [15:0] Q_HI = 16'sd200;
    localparam logic [DW-1:0] SAMPLE_LO = {Q_LO, I_LO};
    localparam logic [DW-1:0] SAMPLE_HI = {Q_HI, I_HI};
    // Per-sample energy constants (for threshold math in tests):
    //   E_LO = 10^2 + 10^2  = 200
    //   E_HI = 200^2 + 200^2 = 80000
    localparam int E_LO = 200;
    localparam int E_HI = 80000;

    task automatic fill_lo(input int base, input int n);
        for (int i = 0; i < n; i++) mem[base+i] = SAMPLE_LO;
    endtask

    task automatic fill_hi(input int base, input int n);
        for (int i = 0; i < n; i++) mem[base+i] = SAMPLE_HI;
    endtask

    // -----------------------------------------------------------------------
    // Helper: run a scan and wait for done; time-out on hang.
    // -----------------------------------------------------------------------
    task automatic run_scan(
        input [EW-1:0]  thr,
        input [6:0]     wlen,
        input [3:0]     hcnt,
        input [AW-1:0]  sbase,
        input [AW:0]    slen
    );
        int timeout_ctr;
        @(negedge aclk);
        threshold_d   = thr;
        window_len_d  = wlen;
        hit_count_d   = hcnt;
        search_base_d = sbase;
        search_len_d  = slen;
        start_d       = 1'b1;
        @(negedge aclk);
        start_d = 1'b0;
        // Wait for done pulse
        timeout_ctr = 0;
        @(posedge aclk); #1;
        while (!done && timeout_ctr < TIMEOUT) begin
            @(posedge aclk); #1;
            timeout_ctr++;
        end
        if (timeout_ctr >= TIMEOUT)
            $display("[FAIL] TIMEOUT waiting for done");
    endtask

    // -----------------------------------------------------------------------
    // Threshold helpers
    // The DUT compares energy_acc (sum of WLEN powers) vs threshold_in * wlen.
    // To make a threshold that sits between LO and HI:
    //   thr_sum = threshold_in * wlen
    //   We want: WLEN*E_LO < thr_sum < WLEN*E_HI
    //   e.g. threshold_in = (E_LO + E_HI)/2 = (200+80000)/2 = 40100
    // -----------------------------------------------------------------------
    localparam int THR_MID = (E_LO + E_HI) / 2;   // 40100

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    logic [31:0] prng;

    function automatic [31:0] xorshift32(input [31:0] s);
        logic [31:0] x;
        x = s ^ (s << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
        return x;
    endfunction

    initial begin
        aresetn       = 1'b0;
        start_d       = 1'b0;
        threshold_d   = '0;
        window_len_d  = 7'd4;
        hit_count_d   = 4'd3;
        search_base_d = '0;
        search_len_d  = '0;
        pass_cnt = 0; fail_cnt = 0;
        for (int i = 0; i < DEP; i++) mem[i] = '0;

        repeat(4) @(negedge aclk);
        aresetn = 1'b1;
        repeat(2) @(negedge aclk);

        // ----------------------------------------------------------------
        // T1: reset outputs clear
        // ----------------------------------------------------------------
        @(posedge aclk); #1;
        chk("T1 busy=0 in reset",       busy,        1'b0);
        chk("T1 done=0 in reset",       done,        1'b0);
        chk("T1 frame_found=0 in reset",frame_found, 1'b0);

        // ----------------------------------------------------------------
        // T2: no frame found — all samples below threshold
        //   mem[0..19] = SAMPLE_LO, wlen=4, hcnt=2, thr=THR_MID
        //   Each window sum = 4*E_LO = 800 < THR_MID*4 = 160400 → Case A
        //   No above-threshold windows → frame_found=0
        // ----------------------------------------------------------------
        fill_lo(0, 20);
        run_scan(EW'(THR_MID), 7'd4, 4'd2, 8'd0, 9'd20);
        chk    ("T2 done fires",        done,        1'b1);
        chk    ("T2 frame_found=0",     frame_found, 1'b0);
        chk    ("T2 busy=0 after done", busy,        1'b0);

        // ----------------------------------------------------------------
        // T3: Case A — frame found mid-way
        //   mem[0..4] = LO (first window below threshold → Case A)
        //   mem[5..9] = HI (5 consecutive high-energy samples)
        //   wlen=3, hcnt=2, thr=THR_MID
        //   Window sums:
        //     j=0 [0..2]: 3*E_LO = 600 < THR_MID*3 → Case A
        //     j=1 [1..3]: 3*E_LO = 600 < thr → no hit
        //     j=2 [2..4]: 3*E_LO = 600 < thr → no hit
        //     j=3 [3..5]: 2*E_LO+E_HI > thr? 400+80000=80400 vs 120300 → above → hit_ctr=1
        //     Hmm, 2*200+80000 = 80400 vs THR_MID*3 = 120300 → actually 80400 < 120300 → NO hit
        //   Let me use wlen=1 for simplicity so each window = one sample energy
        //   wlen=1, hcnt=2, thr=THR_MID (=40100)
        //   j=0: E_LO=200 < 40100*1 → Case A
        //   j=1..4: E_LO → no hit
        //   j=5: E_HI=80000 > 40100 → hit_ctr=1, first_hit=5
        //   j=6: E_HI → hit_ctr=2 >= hcnt=2 → FOUND, frame_index=5
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        fill_hi(5, 5);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T3 done fires",        done,        1'b1);
        chk    ("T3 frame_found=1",     frame_found, 1'b1);
        chk_idx("T3 frame_index=5",     frame_index, 5);

        // ----------------------------------------------------------------
        // T4: Case A — hit count exactly satisfied (hcnt=1)
        //   wlen=1, hcnt=1, thr=THR_MID
        //   First above-threshold sample at index 3 → frame_index=3
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        fill_hi(3, 5);
        run_scan(EW'(THR_MID), 7'd1, 4'd1, 8'd0, 9'd10);
        chk    ("T4 done fires",        done,        1'b1);
        chk    ("T4 frame_found=1",     frame_found, 1'b1);
        chk_idx("T4 frame_index=3",     frame_index, 3);

        // ----------------------------------------------------------------
        // T5: Case A — broken run resets counter; second run succeeds
        //   wlen=1, hcnt=3, thr=THR_MID
        //   mem: LO LO HI HI LO HI HI HI LO LO (indices 0..9)
        //   Window 0: LO → Case A
        //   Windows 1: LO → no hit
        //   Window 2: HI → hit_ctr=1, first_hit=2
        //   Window 3: HI → hit_ctr=2
        //   Window 4: LO → hit_ctr=0 (reset)
        //   Window 5: HI → hit_ctr=1, first_hit=5
        //   Window 6: HI → hit_ctr=2
        //   Window 7: HI → hit_ctr=3 >= 3 → FOUND at frame_index=5
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        mem[2] = SAMPLE_HI; mem[3] = SAMPLE_HI;
        mem[5] = SAMPLE_HI; mem[6] = SAMPLE_HI; mem[7] = SAMPLE_HI;
        run_scan(EW'(THR_MID), 7'd1, 4'd3, 8'd0, 9'd10);
        chk    ("T5 done fires",        done,        1'b1);
        chk    ("T5 frame_found=1",     frame_found, 1'b1);
        chk_idx("T5 frame_index=5",     frame_index, 5);

        // ----------------------------------------------------------------
        // T6: Case B — initial region above threshold; scan after drop
        //   wlen=1, hcnt=2, thr=THR_MID
        //   mem: HI HI LO HI HI LO LO (indices 0..6)
        //   Window 0: HI → Case B, skip_phase=1
        //   Window 1: HI → still in skip_phase
        //   Window 2: LO → skip_phase ends (but this window doesn't count as a hit)
        //   Window 3: HI → scanning: hit_ctr=1, first_hit=3
        //   Window 4: HI → hit_ctr=2 >= 2 → FOUND, frame_index=3
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        mem[0] = SAMPLE_HI; mem[1] = SAMPLE_HI;
        mem[3] = SAMPLE_HI; mem[4] = SAMPLE_HI;
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T6 done fires",        done,        1'b1);
        chk    ("T6 frame_found=1",     frame_found, 1'b1);
        chk_idx("T6 frame_index=3",     frame_index, 3);

        // ----------------------------------------------------------------
        // T7: Case B — all above threshold; never drops → not found
        //   wlen=1, hcnt=2, thr=THR_MID
        //   mem: all HI (skip_phase never clears) → frame_found=0
        // ----------------------------------------------------------------
        fill_hi(0, 20);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd20);
        chk    ("T7 done fires",        done,        1'b1);
        chk    ("T7 frame_found=0",     frame_found, 1'b0);

        // ----------------------------------------------------------------
        // T8: window_len=4 (multi-sample window)
        //   wlen=4, hcnt=2, thr chosen so 4*E_LO < thr*4 < 4*E_HI
        //   → threshold_d = THR_MID (per sample)
        //   Sum for all-LO window = 4*200 = 800 < THR_MID*4 = 160400 → below
        //   Sum for all-HI window = 4*80000 = 320000 > 160400 → above
        //   mem: LO×5, HI×8 (indices 0..12)
        //   First window [0..3]: 4*E_LO = 800 < thr*4 → Case A
        //   Windows slide: first all-HI window is [5..8]
        //     j=5 new=HI, old=LO[0] → acc tracks transition
        //   Let me compute: windows [0..3]=LO → Case A
        //   [1..4]=LO → no hit
        //   [2..5]=3LO+HI: 3*200+80000=80600 vs 160400 → below
        //   [3..6]=2LO+2HI: 2*200+2*80000=160400 vs 160400 → NOT above (equal, not >)
        //   [4..7]=LO+3HI: 200+3*80000=240200 > 160400 → hit_ctr=1, first_hit=4
        //   [5..8]=4HI: 320000 > 160400 → hit_ctr=2 >= 2 → FOUND, frame_index=4
        // ----------------------------------------------------------------
        fill_lo(0, 5);
        fill_hi(5, 8);
        run_scan(EW'(THR_MID), 7'd4, 4'd2, 8'd0, 9'd13);
        chk    ("T8 done fires",        done,        1'b1);
        chk    ("T8 frame_found=1",     frame_found, 1'b1);
        chk_idx("T8 frame_index=4",     frame_index, 4);

        // ----------------------------------------------------------------
        // T9: non-zero search_base
        //   mem[16..25] = LO×3, HI×5, LO×2
        //   wlen=1, hcnt=3, thr=THR_MID
        //   search_base=16, search_len=10
        //   Windows: 16=LO (Case A), 17=LO, 18=LO, 19=HI(hit1,first=19),
        //            20=HI(hit2), 21=HI(hit3>=3) → FOUND, frame_index=19
        // ----------------------------------------------------------------
        fill_lo(16, 10);
        mem[19] = SAMPLE_HI; mem[20] = SAMPLE_HI; mem[21] = SAMPLE_HI;
        mem[22] = SAMPLE_HI; mem[23] = SAMPLE_HI;
        run_scan(EW'(THR_MID), 7'd1, 4'd3, 8'd16, 9'd10);
        chk    ("T9 done fires",        done,        1'b1);
        chk    ("T9 frame_found=1",     frame_found, 1'b1);
        chk_idx("T9 frame_index=19",    frame_index, 19);

        // ----------------------------------------------------------------
        // T10: done is exactly 1-clock wide
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        fill_hi(5, 3);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T10 done fires",                   done, 1'b1);
        @(posedge aclk); #1;
        chk    ("T10 done deasserts next clock",    done, 1'b0);
        chk    ("T10 busy=0 after done",            busy, 1'b0);

        // ----------------------------------------------------------------
        // T11: busy deasserts on the same clock as done
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        fill_hi(7, 3);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T11 done=1",  done, 1'b1);
        chk    ("T11 busy=0 simultaneous with done", busy, 1'b0);

        // ----------------------------------------------------------------
        // T12: scan_len = window_len exactly (single window, no slides)
        //   wlen=3, hcnt=1, thr=THR_MID, search_len=3
        //   Window [0..2]: 3*E_LO=600 < thr*3=120300 → Case A, first window only
        //   No slides possible → not found
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        run_scan(EW'(THR_MID), 7'd3, 4'd1, 8'd0, 9'd3);
        chk    ("T12 done fires",       done,        1'b1);
        chk    ("T12 frame_found=0 (no slides)", frame_found, 1'b0);

        // ----------------------------------------------------------------
        // T13: scan_len = window_len + 1 (one slide)
        //   wlen=3, hcnt=1, thr=THR_MID, mem[0..3]=LO LO LO HI
        //   First window [0..2]: LO→ Case A
        //   Slide: window [1..3]: 2LO+HI=400+80000=80400 vs thr*3=120300 → below (no hit)
        //   → not found
        // ----------------------------------------------------------------
        fill_lo(0, 4);
        mem[3] = SAMPLE_HI;
        run_scan(EW'(THR_MID), 7'd3, 4'd1, 8'd0, 9'd4);
        chk    ("T13 done fires",       done,        1'b1);
        chk    ("T13 frame_found=0",    frame_found, 1'b0);

        // ----------------------------------------------------------------
        // T14: back-to-back scans, frame_found resets on new start
        //   Scan 1: all LO → not found
        //   Scan 2: HI at [2..3] → found
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T14 scan1 frame_found=0", frame_found, 1'b0);
        fill_hi(2, 2);
        run_scan(EW'(THR_MID), 7'd1, 4'd2, 8'd0, 9'd10);
        chk    ("T14 scan2 frame_found=1", frame_found, 1'b1);
        chk_idx("T14 scan2 frame_index=2", frame_index, 2);

        // ----------------------------------------------------------------
        // T15: hit count = 1 (immediate detection on first above-threshold window)
        //   wlen=1, hcnt=1, first HI at index 0 → Case B check
        //   Actually: first window [0]=HI → Case B (above threshold)
        //   Skip: no below-threshold window exists → not found
        //   Use LO at start to trigger Case A with hcnt=1:
        //   mem: LO HI LO LO → frame_index=1
        // ----------------------------------------------------------------
        fill_lo(0, 10);
        mem[1] = SAMPLE_HI;
        run_scan(EW'(THR_MID), 7'd1, 4'd1, 8'd0, 9'd10);
        chk    ("T15 done fires",         done,        1'b1);
        chk    ("T15 frame_found=1",      frame_found, 1'b1);
        chk_idx("T15 frame_index=1",      frame_index, 1);

        // ----------------------------------------------------------------
        // T16: PRNG smoke test — 5 random scans, each verifying frame_found
        //      consistency: if all-LO, must be not-found.
        // ----------------------------------------------------------------
        prng = 32'hDEAD_CAFE;
        begin
            int smoke_pass;
            smoke_pass = 1;
            for (int t = 0; t < 5; t++) begin
                // Fill mem with LO
                fill_lo(0, 30);
                // Insert HI at a known position
                prng = xorshift32(prng);
                begin
                    int pos;
                    pos = (prng[4:0] > 3) ? prng[4:0] : 3;  // at least index 3
                    if (pos > 25) pos = 25;
                    fill_hi(pos, 4);
                    run_scan(EW'(THR_MID), 7'd1, 4'd3, 8'd0, 9'd30);
                    // frame should be found and index should be in [pos, pos+3]
                    if (!frame_found) begin
                        $display("[FAIL] T16 smoke t=%0d: not found (pos=%0d)", t, pos);
                        fail_cnt++;
                        smoke_pass = 0;
                    end else if (frame_index < pos || frame_index > pos + 1) begin
                        $display("[FAIL] T16 smoke t=%0d: frame_index=%0d not in [%0d,%0d]",
                                 t, frame_index, pos, pos+1);
                        fail_cnt++;
                        smoke_pass = 0;
                    end
                end
            end
            if (smoke_pass) begin
                $display("[PASS] T16 PRNG smoke: 5/5 scans correct");
                pass_cnt++;
            end
        end

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
