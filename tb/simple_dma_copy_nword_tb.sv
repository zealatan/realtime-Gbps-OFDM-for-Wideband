`timescale 1ns/1ps

// Testbench: simple_dma_copy_nword (DUT) connected to axi_mem_model (slave).
// Drive control inputs on negedge; sample DUT outputs on posedge.
module simple_dma_copy_nword_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // Testbench control inputs to DMA
    // ---------------------------------------------------------------
    logic        start_tb  = 1'b0;
    logic [31:0] src_tb    = '0;
    logic [31:0] dst_tb    = '0;
    logic [15:0] len_tb    = '0;

    // ---------------------------------------------------------------
    // AXI4 wires — DMA ↔ slave
    // ---------------------------------------------------------------
    wire [31:0] axi_araddr;  wire axi_arvalid; wire axi_arready;
    wire [31:0] axi_rdata;   wire [1:0] axi_rresp; wire axi_rlast;
    wire        axi_rvalid;  wire axi_rready;
    wire [31:0] axi_awaddr;  wire axi_awvalid; wire axi_awready;
    wire [31:0] axi_wdata;   wire [3:0] axi_wstrb;  wire axi_wlast;
    wire        axi_wvalid;  wire axi_wready;
    wire [1:0]  axi_bresp;   wire axi_bvalid;   wire axi_bready;

    // ---------------------------------------------------------------
    // DMA outputs
    // ---------------------------------------------------------------
    wire [31:0] last_copied_data;
    wire [15:0] copied_count;
    wire        done;
    wire        error;

    // ---------------------------------------------------------------
    // DUT — N-word DMA copy engine
    // ---------------------------------------------------------------
    simple_dma_copy_nword dut (
        .aclk             (aclk),        .aresetn          (aresetn),
        .start            (start_tb),    .src_addr         (src_tb),
        .dst_addr         (dst_tb),      .length_words     (len_tb),
        .last_copied_data (last_copied_data),
        .copied_count     (copied_count), .done            (done), .error (error),
        .araddr  (axi_araddr),  .arvalid (axi_arvalid), .arready (axi_arready),
        .rdata   (axi_rdata),   .rresp   (axi_rresp),   .rlast   (axi_rlast),
        .rvalid  (axi_rvalid),  .rready  (axi_rready),
        .awaddr  (axi_awaddr),  .awvalid (axi_awvalid), .awready (axi_awready),
        .wdata   (axi_wdata),   .wstrb   (axi_wstrb),   .wlast   (axi_wlast),
        .wvalid  (axi_wvalid),  .wready  (axi_wready),
        .bresp   (axi_bresp),   .bvalid  (axi_bvalid),  .bready  (axi_bready)
    );

    // ---------------------------------------------------------------
    // Slave — AXI memory model (4 KB at base 0x0)
    // ---------------------------------------------------------------
    axi_mem_model #(
        .MEM_DEPTH (1024),
        .MEM_BASE  (32'h0000_0000)
    ) slave (
        .aclk    (aclk),         .aresetn  (aresetn),
        .araddr  (axi_araddr),   .arvalid  (axi_arvalid),  .arready (axi_arready),
        .rdata   (axi_rdata),    .rresp    (axi_rresp),    .rlast   (axi_rlast),
        .rvalid  (axi_rvalid),   .rready   (axi_rready),
        .awaddr  (axi_awaddr),   .awvalid  (axi_awvalid),  .awready (axi_awready),
        .wdata   (axi_wdata),    .wstrb    (axi_wstrb),    .wlast   (axi_wlast),
        .wvalid  (axi_wvalid),   .wready   (axi_wready),
        .bresp   (axi_bresp),    .bvalid   (axi_bvalid),   .bready  (axi_bready)
    );

    int pass_count = 0;
    int fail_count = 0;

    // ---------------------------------------------------------------
    // run_dma — pulse start for one cycle, wait for done
    // ---------------------------------------------------------------
    task automatic run_dma(
        input logic [31:0] tsrc,
        input logic [31:0] tdst,
        input logic [15:0] tlen
    );
        int timeout;
        @(negedge aclk);
        src_tb   = tsrc;
        dst_tb   = tdst;
        len_tb   = tlen;
        start_tb = 1'b1;
        @(negedge aclk);
        start_tb = 1'b0;
        timeout  = 0;
        @(posedge aclk);
        while (!done) begin
            if (++timeout > 1000)
                $fatal(1, "[FATAL] run_dma timeout src=0x%08X dst=0x%08X len=%0d",
                       tsrc, tdst, tlen);
            @(posedge aclk);
        end
    endtask

    // ---------------------------------------------------------------
    // check helpers
    // ---------------------------------------------------------------
    task automatic check_eq(input logic [31:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=0x%08X", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=0x%08X  exp=0x%08X", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq failed");
        end
    endtask

    task automatic check_eq16(input logic [15:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=%0d", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=%0d  exp=%0d", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq16 failed");
        end
    endtask

    task automatic check_bit(input logic got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=1'b%0b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=1'b%0b  exp=1'b%0b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_bit failed");
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("../logs/simple_dma_copy_nword_tb.vcd");
        $dumpvars(0, simple_dma_copy_nword_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // Seed source memory
        //   words 0-3 at byte addrs 0x00-0x0C
        slave.mem[0] = 32'hDEAD_BEEF;
        slave.mem[1] = 32'hCAFE_F00D;
        slave.mem[2] = 32'hA5A5_A5A5;
        slave.mem[3] = 32'h1234_5678;
        //   words 128-131 at byte addrs 0x200-0x20C (for Test 5 src)
        slave.mem[128] = 32'h1111_AAAA;
        slave.mem[129] = 32'h2222_BBBB;
        slave.mem[130] = 32'h3333_CCCC;
        slave.mem[131] = 32'h4444_DDDD;
        //   words near end of valid range for Test 4 src
        //   MEM_DEPTH=1024 → last word idx=1023 at byte 0xFFC
        slave.mem[1021] = 32'hAAAA_1111;
        slave.mem[1022] = 32'hBBBB_2222;
        slave.mem[1023] = 32'hCCCC_3333;

        // ============================================================
        // Test 1: length_words=0 — done immediately, no transfers
        // ============================================================
        $display("[INFO] Test 1: length_words=0 — expect done, no error, copied_count=0");
        run_dma(32'h0000_0000, 32'h0000_0040, 16'h0);
        check_bit(done,        1'b1, "T1 done");
        check_bit(error,       1'b0, "T1 no error");
        check_eq16(copied_count, 16'd0, "T1 copied_count=0");
        check_eq(slave.mem[16], 32'h0, "T1 dst mem[0x40>>2] unchanged");

        // ============================================================
        // Test 2: length_words=1, src=0x00 → dst=0x40
        // ============================================================
        $display("[CHK] t=%0t  phase=test2", $time);
        $display("[INFO] Test 2: length_words=1, copy 0x00 -> 0x40");
        run_dma(32'h0000_0000, 32'h0000_0040, 16'h1);
        check_bit(done,          1'b1,          "T2 done");
        check_bit(error,         1'b0,          "T2 no error");
        check_eq16(copied_count, 16'd1,         "T2 copied_count=1");
        check_eq(last_copied_data, 32'hDEAD_BEEF, "T2 last_copied_data");
        check_eq(slave.mem[16], 32'hDEAD_BEEF,  "T2 dst mem[0x40>>2]");

        // ============================================================
        // Test 3: length_words=4, src=0x00-0x0C → dst=0x80-0x8C
        // ============================================================
        $display("[CHK] t=%0t  phase=test3", $time);
        $display("[INFO] Test 3: length_words=4, copy 0x00-0x0C -> 0x80-0x8C");
        run_dma(32'h0000_0000, 32'h0000_0080, 16'h4);
        check_bit(done,          1'b1,          "T3 done");
        check_bit(error,         1'b0,          "T3 no error");
        check_eq16(copied_count, 16'd4,         "T3 copied_count=4");
        check_eq(slave.mem[32], 32'hDEAD_BEEF,  "T3 dst[0] mem[0x80>>2]");
        check_eq(slave.mem[33], 32'hCAFE_F00D,  "T3 dst[1] mem[0x84>>2]");
        check_eq(slave.mem[34], 32'hA5A5_A5A5,  "T3 dst[2] mem[0x88>>2]");
        check_eq(slave.mem[35], 32'h1234_5678,  "T3 dst[3] mem[0x8C>>2]");

        // ============================================================
        // Test 4: invalid src mid-copy — src=0xFF4, len=4, dst=0x100
        //   MEM_DEPTH=1024 → valid byte range 0x000–0xFFC (word 0x3FF)
        //   word_idx=0: src byte 0xFF4 = word 0x3FD → valid (mem[1021]=0xAAAA_1111)
        //   word_idx=1: src byte 0xFF8 = word 0x3FE → valid (mem[1022]=0xBBBB_2222)
        //   word_idx=2: src byte 0xFFC = word 0x3FF → valid (mem[1023]=0xCCCC_3333)
        //   word_idx=3: src byte 0x1000 → OOB → SLVERR on read → abort
        //   copied_count=3, error=1, dst words 0-2 written, dst word 3 unchanged
        // ============================================================
        $display("[CHK] t=%0t  phase=test4", $time);
        $display("[INFO] Test 4: invalid src mid-copy src=0xFF4 len=4 dst=0x100");
        run_dma(32'h0000_0FF4, 32'h0000_0100, 16'h4);
        check_bit(done,          1'b1,          "T4 done");
        check_bit(error,         1'b1,          "T4 error (OOB src word 3)");
        check_eq16(copied_count, 16'd3,         "T4 copied_count=3");
        check_eq(slave.mem[64], 32'hAAAA_1111,  "T4 dst[0] mem[0x100>>2]");
        check_eq(slave.mem[65], 32'hBBBB_2222,  "T4 dst[1] mem[0x104>>2]");
        check_eq(slave.mem[66], 32'hCCCC_3333,  "T4 dst[2] mem[0x108>>2]");
        check_eq(slave.mem[67], 32'h0,          "T4 dst[3] mem[0x10C>>2] unchanged");

        // ============================================================
        // Test 5: invalid dst mid-copy — src=0x200, dst=0xFF4, len=4
        //   src words 128-131 are valid (seeded above)
        //   word_idx=0: dst byte 0xFF4 = word 0x3FD → valid
        //   word_idx=1: dst byte 0xFF8 = word 0x3FE → valid
        //   word_idx=2: dst byte 0xFFC = word 0x3FF → valid
        //   word_idx=3: dst byte 0x1000 → OOB → SLVERR on write → abort
        //   copied_count=3, error=1
        //   Canary at mem[256] (byte 0x400) must remain 0x0
        // ============================================================
        $display("[CHK] t=%0t  phase=test5", $time);
        $display("[INFO] Test 5: invalid dst mid-copy src=0x200 dst=0xFF4 len=4");
        // canary at word 256 (byte 0x400) — well within valid range
        slave.mem[256] = 32'hFEED_FACE;
        run_dma(32'h0000_0200, 32'h0000_0FF4, 16'h4);
        check_bit(done,           1'b1,          "T5 done");
        check_bit(error,          1'b1,          "T5 error (OOB dst word 3)");
        check_eq16(copied_count,  16'd3,         "T5 copied_count=3");
        check_eq(slave.mem[1021], 32'h1111_AAAA,  "T5 dst[0] mem[0xFF4>>2]");
        check_eq(slave.mem[1022], 32'h2222_BBBB,  "T5 dst[1] mem[0xFF8>>2]");
        check_eq(slave.mem[1023], 32'h3333_CCCC,  "T5 dst[2] mem[0xFFC>>2]");
        check_eq(slave.mem[256], 32'hFEED_FACE,  "T5 canary mem[256] (0x400) unchanged");
        check_eq(slave.mem[128], 32'h1111_AAAA,  "T5 src mem[0x200>>2] unchanged");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] simple_dma_copy_nword_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] simple_dma_copy_nword_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
