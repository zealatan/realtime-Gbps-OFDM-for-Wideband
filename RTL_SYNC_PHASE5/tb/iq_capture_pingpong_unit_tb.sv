`timescale 1ns/1ps
// Unit TB for iq_capture_pingpong: drive N frames continuously (backpressured),
// model a SLOW processor (forces both_full), and check every frame is captured +
// handed off with no loss/overflow and correct read-back.
module iq_capture_pingpong_unit_tb;
    localparam integer DW       = 32;
    localparam integer CAP_AW   = 5;     // DEPTH=32 >= FRAME_LEN
    localparam integer FRAME_LEN= 16;
    localparam integer N_FRAMES = 3;

    reg              clk = 0, rstn = 0;
    always #5 clk = ~clk;

    reg  [DW-1:0]    s_tdata;
    reg              s_tvalid, s_tlast;
    wire             s_tready;
    wire             buf_ready;
    wire [CAP_AW:0]  buf_len;
    reg              proc_take, proc_free;
    reg              rd_en;
    reg  [CAP_AW-1:0] rd_addr;
    wire [DW-1:0]    rd_data;
    wire             both_full;
    wire             cap_overflow;

    iq_capture_pingpong #(.DATA_WIDTH(DW), .CAP_AW(CAP_AW)) dut (
        .aclk(clk), .aresetn(rstn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .buf_ready(buf_ready), .buf_len(buf_len),
        .proc_take(proc_take), .proc_free(proc_free),
        .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
        .both_full(both_full), .cap_overflow(cap_overflow)
    );

    integer errors = 0;
    integer frames_processed = 0;
    integer overflow_seen = 0;
    integer both_full_seen = 0;

    always @(posedge clk) begin
        if (rstn && cap_overflow) overflow_seen = overflow_seen + 1;
        if (rstn && both_full)    both_full_seen = both_full_seen + 1;
    end

    // ---- Producer: N frames, continuous tvalid, backpressured ----
    integer f, i;
    initial begin
        s_tdata=0; s_tvalid=0; s_tlast=0; rstn=0;
        repeat(4) @(posedge clk); rstn=1;
        repeat(3) @(posedge clk);
        // Canonical AXI-S master: present a beat, advance ONLY when accepted
        // (s_tready high at the posedge). Continuous across frames, tlast per frame.
        f = 0; i = 0;
        s_tdata  <= (f*256) + i;
        s_tvalid <= 1'b1;
        s_tlast  <= (i==FRAME_LEN-1);
        while (f < N_FRAMES) begin
            @(posedge clk);
            if (s_tready) begin
                i = i + 1;
                if (i == FRAME_LEN) begin i = 0; f = f + 1; end
                if (f < N_FRAMES) begin
                    s_tdata <= (f*256) + i;
                    s_tlast <= (i==FRAME_LEN-1);
                end else begin
                    s_tvalid <= 1'b0;
                    s_tlast  <= 1'b0;
                end
            end
        end
    end

    // ---- Slow processor model: take ready buffer, read it, dwell, free ----
    integer k, expf;
    reg [DW-1:0] got;
    initial begin
        proc_take=0; proc_free=0; rd_en=0; rd_addr=0;
        @(posedge clk); wait(rstn);
        for (expf=0; expf<N_FRAMES; expf=expf+1) begin
            // wait for a captured buffer
            while (!buf_ready) @(posedge clk);
            if (buf_len !== FRAME_LEN) begin
                $display("[FAIL] frame %0d buf_len=%0d expected %0d", expf, buf_len, FRAME_LEN);
                errors = errors + 1;
            end
            @(posedge clk); proc_take<=1'b1;
            @(posedge clk); proc_take<=1'b0;
            @(posedge clk);                       // let proc_sel settle
            // read all beats: per-addr present + 2-cycle settle (robust to the
            // registered read latency + mux), sample mem[k].
            rd_en<=1'b1;
            for (k=0; k<FRAME_LEN; k=k+1) begin
                rd_addr <= k[CAP_AW-1:0];
                @(posedge clk); @(posedge clk);
                got = rd_data;                    // = mem[k]
                if (got !== ((expf*256)+k)) begin
                    $display("[FAIL] frame %0d addr %0d got %0d exp %0d", expf, k, got, (expf*256)+k);
                    errors = errors + 1;
                end
            end
            rd_en<=1'b0;
            // SLOW processing: dwell ~2.5 frames so the other buffer fills -> both_full
            repeat (FRAME_LEN*2 + 8) @(posedge clk);
            @(posedge clk); proc_free<=1'b1;
            @(posedge clk); proc_free<=1'b0;
            frames_processed = frames_processed + 1;
        end
        repeat(20) @(posedge clk);
        $display("==== iq_capture_pingpong unit TB ====");
        $display("  frames_processed = %0d / %0d", frames_processed, N_FRAMES);
        $display("  cap_overflow events = %0d (expect 0)", overflow_seen);
        $display("  both_full observed  = %0d cycles (expect >0, proves backpressure path)", both_full_seen);
        $display("  data/len errors     = %0d", errors);
        if (frames_processed==N_FRAMES && overflow_seen==0 && both_full_seen>0 && errors==0)
            $display("RESULT: PASS");
        else
            $display("RESULT: FAIL");
        $finish;
    end

    // event trace
    always @(posedge clk) if (rstn) begin
        if (dut.cs_a)     $display("@%0t armA cstate=%0d occ=%b%b proc_busy=%b psel=%b", $time, dut.cstate, dut.occ_a, dut.occ_b, dut.proc_busy, dut.proc_sel);
        if (dut.cs_b)     $display("@%0t armB cstate=%0d occ=%b%b proc_busy=%b psel=%b", $time, dut.cstate, dut.occ_a, dut.occ_b, dut.proc_busy, dut.proc_sel);
        if (dut.cdone_a)  $display("@%0t CAPdoneA scnt=%0d", $time, dut.scnt_a);
        if (dut.cdone_b)  $display("@%0t CAPdoneB scnt=%0d", $time, dut.scnt_b);
        if (proc_take)    $display("@%0t TAKE proc_next=%b (occ=%b%b)", $time, dut.proc_next, dut.occ_a, dut.occ_b);
        if (proc_free)    $display("@%0t FREE proc_sel=%b", $time, dut.proc_sel);
    end

    // watchdog
    initial begin #200000; $display("RESULT: FAIL (timeout)"); $finish; end
endmodule
