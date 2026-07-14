`timescale 1ns/1ps
// Unit-sim for meyr_slot_frontend (NUM_SYN=2, NUM_DATA=5):
//   - slot_start aligns the slot counter so CP suppression and
//     PSS/SSS routing land on the right ranges.
//   - pss_first_beat fires exactly once per slot, on the first
//     PSS payload sample (slot_cnt = CP_LEN).
//   - data_sym_idx wraps 0..NUM_DATA-1 across data symbols.
//
// GATE:  PASS_P5_D_SLOT_FRONTEND | FAIL_P5_D_SLOT_FRONTEND
module p5_d_meyr_slot_frontend_tb;

    localparam int N        = 256;
    localparam int CP_LEN   = 32;
    localparam int NUM_SYN  = 2;
    localparam int NUM_DATA = 5;
    localparam int SYM_LEN  = CP_LEN + N;
    localparam int SLOT_LEN = (NUM_SYN + NUM_DATA) * SYM_LEN;

    logic clk = 0;
    always #2 clk = ~clk;
    logic rst_n = 0;

    logic [31:0] s_tdata = 0;
    logic        s_tvalid = 0;
    logic        slot_start = 0;
    logic [31:0] meyr_tdata;
    logic        meyr_tvalid;
    logic        pss_first_beat;
    logic        meyr_tready = 1'b1;
    logic [31:0] data_tdata;
    logic        data_tvalid;
    logic  [3:0] data_sym_idx;

    meyr_slot_frontend #(.N(N), .CP_LEN(CP_LEN), .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_tdata(s_tdata), .s_tvalid(s_tvalid), .slot_start(slot_start),
        .meyr_tdata(meyr_tdata), .meyr_tvalid(meyr_tvalid),
        .pss_first_beat(pss_first_beat), .meyr_tready(meyr_tready),
        .data_tdata(data_tdata), .data_tvalid(data_tvalid), .data_sym_idx(data_sym_idx)
    );

    int fails = 0;
    int meyr_beats = 0;
    int data_beats = 0;
    int pss_first_beat_count = 0;

    always @(posedge clk) begin
        if (meyr_tvalid) meyr_beats <= meyr_beats + 1;
        if (data_tvalid) data_beats <= data_beats + 1;
        if (pss_first_beat) pss_first_beat_count <= pss_first_beat_count + 1;
    end

    initial begin
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (3) @(posedge clk);

        // Run two full back-to-back slots.
        for (int slot = 0; slot < 2; slot = slot + 1) begin
            for (int n = 0; n < SLOT_LEN; n = n + 1) begin
                @(posedge clk);
                s_tdata    <= 32'(1000*(slot+1) + n);
                s_tvalid   <= 1'b1;
                slot_start <= (n == 0);
            end
        end
        @(posedge clk);
        s_tvalid <= 1'b0;
        slot_start <= 1'b0;
        repeat (10) @(posedge clk);

        // Expected: meyr_beats per slot = NUM_SYN * N
        //           data_beats per slot = NUM_DATA * N
        //           pss_first_beat = 1 per slot
        if (meyr_beats != 2 * NUM_SYN * N) begin
            $display("FAIL meyr_beats=%0d want=%0d", meyr_beats, 2*NUM_SYN*N); fails++;
        end
        if (data_beats != 2 * NUM_DATA * N) begin
            $display("FAIL data_beats=%0d want=%0d", data_beats, 2*NUM_DATA*N); fails++;
        end
        if (pss_first_beat_count != 2) begin
            $display("FAIL pss_first_beat_count=%0d want=2", pss_first_beat_count); fails++;
        end

        if (fails == 0) $display("GATE: PASS_P5_D_SLOT_FRONTEND  meyr=%0d data=%0d pss_first=%0d",
                                  meyr_beats, data_beats, pss_first_beat_count);
        else            $display("GATE: FAIL_P5_D_SLOT_FRONTEND fails=%0d", fails);
        $finish;
    end

    initial begin #1_000_000; $display("GATE: FAIL_P5_D_SLOT_FRONTEND (timeout)"); $finish; end
endmodule
