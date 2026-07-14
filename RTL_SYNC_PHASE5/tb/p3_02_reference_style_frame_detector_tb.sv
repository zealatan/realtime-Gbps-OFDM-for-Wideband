`timescale 1ns/1ps
//
// p3_02_reference_style_frame_detector_tb.sv  — P3-02 test suite
//
// Threshold design (SUM_THRESH = 249000, WND_LEN=25):
//   HI_VAL = 100  → power = 10000/sample; 25 HI → sum = 250000 > 249000  (above)
//   LO_VAL = 0    → power = 0;            any mix with LO → sum ≤ 240000  (below)
//   BD_VAL = 99   → power = 9801/sample;  25 BD → sum = 245025 < 249000   (below — T08)
//
//   N consecutive all-HI windows: send_samples(N+WND_LEN-1, HI) at start S
//     → windows j=S .. S+N-1 above threshold; frame_index = S.
//
// Test inventory:
//   T01  Case A:  25 LO + 34 HI           → found,     frame_index=25
//   T02  Case B:  25 HI + 25 LO + 34 HI   → found,     frame_index=50
//   T03  Too few: 25 LO + 33 HI           → not found
//   T04  Minimal: 1 LO  + 34 HI           → found,     frame_index=1
//   T05  Break:   25 LO + 33 HI + 25 LO + 34 HI → found, frame_index=83
//   T06  Case B long: 40 HI + 25 LO + 34 HI     → found, frame_index=65
//   T07  All-zero input                    → not found
//   T08  At-boundary (I=99): power=9801×25=245025 < 249000 → not found

`define FAIL_IF(label, cond) \
    if (cond) begin \
        $display("FAIL  %-30s  t=%0t", label, $time); \
        fail_count = fail_count + 1; \
    end else \
        $display("PASS  %s", label);

module p3_02_reference_style_frame_detector_tb;

    // ── Parameters matching DUT ───────────────────────────────────────────
    localparam integer IQ_W        = 16;
    localparam integer POWER_W     = 33;
    localparam integer SUM_W       = 48;
    localparam integer INDEX_W     = 16;
    localparam integer WND_LEN     = 25;
    localparam integer CONFIRM_LEN = 10;

    // ── Test stimulus constants ───────────────────────────────────────────
    localparam signed [IQ_W-1:0] HI_VAL = 100;
    localparam signed [IQ_W-1:0] LO_VAL = 0;
    localparam signed [IQ_W-1:0] BD_VAL = 99;   // at-boundary
    localparam [SUM_W-1:0] SUM_THRESH   = 249000;
    // N+WND_LEN-1 HI samples gives exactly N above-threshold windows
    localparam integer HI_FOR_10 = WND_LEN + CONFIRM_LEN - 1; // = 34  → 10 hits
    localparam integer HI_FOR_9  = WND_LEN + CONFIRM_LEN - 2; // = 33  → 9 hits

    // ── Clock ─────────────────────────────────────────────────────────────
    logic aclk = 0;
    always #5 aclk = ~aclk; // 100 MHz

    // ── DUT signals ───────────────────────────────────────────────────────
    logic              aresetn;
    logic [2*IQ_W-1:0] s_tdata;
    logic              s_tvalid;
    wire               s_tready;
    logic              s_tlast;
    logic [SUM_W-1:0]  threshold;
    logic              start;
    wire               done;
    wire               busy;
    wire               frame_found;
    wire [INDEX_W-1:0] frame_index;

    // ── DUT ───────────────────────────────────────────────────────────────
    reference_style_frame_detector #(
        .IQ_W        (IQ_W),
        .POWER_W     (POWER_W),
        .SUM_W       (SUM_W),
        .INDEX_W     (INDEX_W),
        .WND_LEN     (WND_LEN),
        .CONFIRM_LEN (CONFIRM_LEN)
    ) dut (
        .aclk       (aclk),
        .aresetn    (aresetn),
        .s_tdata    (s_tdata),
        .s_tvalid   (s_tvalid),
        .s_tready   (s_tready),
        .s_tlast    (s_tlast),
        .threshold  (threshold),
        .start      (start),
        .done       (done),
        .busy       (busy),
        .frame_found(frame_found),
        .frame_index(frame_index)
    );

    // ── Scoreboard ────────────────────────────────────────────────────────
    integer fail_count = 0;

    // ── pack IQ ──────────────────────────────────────────────────────────
    function automatic logic [2*IQ_W-1:0] pack_iq(
        input logic signed [IQ_W-1:0] i_v,
        input logic signed [IQ_W-1:0] q_v
    );
        pack_iq = {q_v, i_v};
    endfunction

    // ── send_n: drive N samples; last one gets s_tlast if final_group ─────
    task automatic send_n(
        input integer                  n,
        input logic signed [IQ_W-1:0] i_v,
        input logic signed [IQ_W-1:0] q_v,
        input logic                    final_group
    );
        integer j;
        for (j = 0; j < n; j++) begin
            @(negedge aclk);    // drive before rising edge
            s_tdata  = pack_iq(i_v, q_v);
            s_tvalid = 1'b1;
            s_tlast  = final_group && (j == n-1);
        end
        @(negedge aclk);
        s_tvalid = 1'b0;
        s_tlast  = 1'b0;
    endtask

    // ── wait for done pulse (with timeout) ───────────────────────────────
    // Waits for done, then one extra posedge so the NBA-captured cap_found/
    // cap_index registers are stable before the caller's assertions run.
    task automatic wait_done_pulse(input integer timeout_cyc);
        integer t;
        for (t = 0; t < timeout_cyc; t = t + 1) begin
            @(posedge aclk);
            if (done) t = timeout_cyc; // force loop exit
        end
        @(posedge aclk); // let always-block NBAs settle into cap_found/cap_index
    endtask

    // ── full reset ───────────────────────────────────────────────────────
    task automatic reset_dut;
        aresetn  <= 1'b0;
        s_tvalid <= 1'b0;
        s_tlast  <= 1'b0;
        s_tdata  <= '0;
        start    <= 1'b0;
        threshold<= SUM_THRESH;
        repeat(4) @(posedge aclk);
        aresetn <= 1'b1;
        repeat(2) @(posedge aclk);
    endtask

    // ── fire start for one cycle ──────────────────────────────────────────
    task automatic fire_start;
        @(negedge aclk); start = 1'b1;
        @(negedge aclk); start = 1'b0;
    endtask

    // ── capture result latched at done pulse ─────────────────────────────
    logic cap_found;
    logic [INDEX_W-1:0] cap_index;
    always @(posedge aclk)
        if (done) begin
            cap_found <= frame_found;
            cap_index <= frame_index;
        end

    // ─────────────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("p3_02_reference_style_frame_detector_tb.vcd");
        $dumpvars(0, p3_02_reference_style_frame_detector_tb);

        // =================================================================
        // T01 — Case A: low start, exactly 10 consecutive HI windows → found
        // Stream: 25 LO + 34 HI (tlast on last)
        // Window j=0 all-LO → Case A.
        // First all-HI window: j=25. Hit 10 at j=34. frame_index=25.
        // =================================================================
        reset_dut;
        $display("=== T01: Case A basic ===");
        fire_start;
        fork
            begin
                send_n(WND_LEN,  LO_VAL, 0, 1'b0);
                send_n(HI_FOR_10, HI_VAL, 0, 1'b1);
            end
            wait_done_pulse(1000);
        join
        `FAIL_IF("T01_not_found",     cap_found !== 1'b1)
        `FAIL_IF("T01_index_ne_25",   cap_index !== 16'd25)

        // =================================================================
        // T02 — Case B: high start, WND_LEN low, then 10 HI windows → found
        // Stream: 25 HI + 25 LO + 34 HI (tlast on last)
        // j=0 all-HI → Case B. First below-thresh window: j=1 (24HI+1LO).
        // After fall at j=1: SEARCH_RISE. Second HI block starts at idx 50.
        // frame_index=50.
        // =================================================================
        reset_dut;
        $display("=== T02: Case B basic ===");
        fire_start;
        fork
            begin
                send_n(WND_LEN,   HI_VAL, 0, 1'b0); // 25 HI
                send_n(WND_LEN,   LO_VAL, 0, 1'b0); // 25 LO
                send_n(HI_FOR_10, HI_VAL, 0, 1'b1); // 34 HI, tlast
            end
            wait_done_pulse(1000);
        join
        `FAIL_IF("T02_not_found",     cap_found !== 1'b1)
        `FAIL_IF("T02_index_ne_50",   cap_index !== 16'd50)

        // =================================================================
        // T03 — Not found: only 9 consecutive HI windows, then stream ends
        // Stream: 25 LO + 33 HI (tlast on last)
        // 9 hits (j=25..33) < CONFIRM_LEN=10 → not found.
        // =================================================================
        reset_dut;
        $display("=== T03: Not found (9 hits) ===");
        fire_start;
        fork
            begin
                send_n(WND_LEN,  LO_VAL, 0, 1'b0);
                send_n(HI_FOR_9, HI_VAL, 0, 1'b1);
            end
            wait_done_pulse(1000);
        join
        `FAIL_IF("T03_found_incorrectly", cap_found !== 1'b0)

        // =================================================================
        // T04 — Minimum: 1 LO prefix, then 34 HI (10 exact windows) → found
        // Stream: 1 LO + 34 HI (tlast on last)
        // j=0 window [0..24]: 1 LO + 24 HI → sum=240000 < 249000. Case A.
        // First all-HI window: j=1. frame_index=1.
        // =================================================================
        reset_dut;
        $display("=== T04: Minimal 1-sample low prefix ===");
        fire_start;
        fork
            begin
                send_n(1,         LO_VAL, 0, 1'b0);
                send_n(HI_FOR_10, HI_VAL, 0, 1'b1);
            end
            wait_done_pulse(1000);
        join
        `FAIL_IF("T04_not_found",    cap_found !== 1'b1)
        `FAIL_IF("T04_index_ne_1",   cap_index !== 16'd1)

        // =================================================================
        // T05 — Run interrupted: 9 HI windows, gap, then 10 HI windows → found
        // Stream: 25 LO + 33 HI + 25 LO + 34 HI (tlast on last)
        // First run: 9 hits at j=25..33. j=34 breaks (24HI+1LO < thresh).
        // consec resets. Second run at idx 83: 10 hits. frame_index=83.
        // =================================================================
        reset_dut;
        $display("=== T05: Run interrupted ===");
        fire_start;
        fork
            begin
                send_n(WND_LEN,  LO_VAL, 0, 1'b0); // 25 LO
                send_n(HI_FOR_9, HI_VAL, 0, 1'b0); // 33 HI (9 wins)
                send_n(WND_LEN,  LO_VAL, 0, 1'b0); // 25 LO (gap)
                send_n(HI_FOR_10,HI_VAL, 0, 1'b1); // 34 HI, tlast
            end
            wait_done_pulse(2000);
        join
        // Second run starts at idx 25+33+25 = 83
        `FAIL_IF("T05_not_found",    cap_found !== 1'b1)
        `FAIL_IF("T05_index_ne_83",  cap_index !== 16'd83)

        // =================================================================
        // T06 — Case B with long high prefix: 40 HI, 25 LO, 34 HI → found
        // Stream: 40 HI + 25 LO + 34 HI (tlast on last)
        // j=0 all-HI → Case B.
        // First below-threshold window: j=16 (24HI+1LO after idx 39+1=40).
        // Second HI block at idx 65: frame_index=65.
        // =================================================================
        reset_dut;
        $display("=== T06: Case B long high prefix ===");
        fire_start;
        fork
            begin
                send_n(WND_LEN+15, HI_VAL, 0, 1'b0); // 40 HI
                send_n(WND_LEN,    LO_VAL, 0, 1'b0); // 25 LO
                send_n(HI_FOR_10,  HI_VAL, 0, 1'b1); // 34 HI, tlast
            end
            wait_done_pulse(2000);
        join
        // Second run starts at idx 40+25 = 65
        `FAIL_IF("T06_not_found",    cap_found !== 1'b1)
        `FAIL_IF("T06_index_ne_65",  cap_index !== 16'd65)

        // =================================================================
        // T07 — All-zero input → never above threshold → not found
        // =================================================================
        reset_dut;
        $display("=== T07: All-zero input ===");
        fire_start;
        fork
            send_n(200, LO_VAL, 0, 1'b1);
            wait_done_pulse(1000);
        join
        `FAIL_IF("T07_found_incorrectly", cap_found !== 1'b0)

        // =================================================================
        // T08 — Boundary: I=99 → power=9801; sum=245025 < 249000 → not found
        // =================================================================
        reset_dut;
        $display("=== T08: At-boundary samples (I=99) ===");
        fire_start;
        fork
            send_n(200, BD_VAL, 0, 1'b1);
            wait_done_pulse(1000);
        join
        `FAIL_IF("T08_found_incorrectly", cap_found !== 1'b0)

        // =================================================================
        // Summary
        // =================================================================
        repeat(4) @(posedge aclk);
        $display("");
        $display("=== P3-02 test complete: %0d FAIL ===", fail_count);
        if (fail_count == 0)
            $display("RESULT: PASS 8 FAIL 0");
        else
            $display("RESULT: PASS %0d FAIL %0d", 8-fail_count, fail_count);

        $finish;
    end

    // ── Timeout watchdog ─────────────────────────────────────────────────
    initial begin
        #500000;
        $display("FATAL: global simulation timeout");
        $finish;
    end

endmodule
