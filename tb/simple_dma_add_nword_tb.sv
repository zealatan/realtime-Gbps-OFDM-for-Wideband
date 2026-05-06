`timescale 1ns/1ps

// Testbench: simple_dma_add_nword (DUT) connected to axi_mem_model (slave).
// Drive control inputs on negedge; sample DUT outputs on posedge.
module simple_dma_add_nword_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // Testbench control inputs to DMA
    // ---------------------------------------------------------------
    logic        start_tb = 1'b0;
    logic [31:0] src_tb   = '0;
    logic [31:0] dst_tb   = '0;
    logic [15:0] len_tb   = '0;
    logic [31:0] add_tb   = '0;

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
    wire [31:0] last_input_data;
    wire [31:0] last_output_data;
    wire [15:0] processed_count;
    wire        done;
    wire        error;

    // ---------------------------------------------------------------
    // DUT — N-word DMA add engine
    // ---------------------------------------------------------------
    simple_dma_add_nword dut (
        .aclk             (aclk),         .aresetn          (aresetn),
        .start            (start_tb),     .src_addr         (src_tb),
        .dst_addr         (dst_tb),       .length_words     (len_tb),
        .add_value        (add_tb),
        .last_input_data  (last_input_data),
        .last_output_data (last_output_data),
        .processed_count  (processed_count),
        .done             (done),         .error            (error),
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
    // run_dma — pulse start for one negedge cycle, wait for done
    // ---------------------------------------------------------------
    task automatic run_dma(
        input logic [31:0] tsrc,
        input logic [31:0] tdst,
        input logic [15:0] tlen,
        input logic [31:0] tadd
    );
        int timeout;
        @(negedge aclk);
        src_tb   = tsrc;
        dst_tb   = tdst;
        len_tb   = tlen;
        add_tb   = tadd;
        start_tb = 1'b1;
        @(negedge aclk);
        start_tb = 1'b0;
        timeout  = 0;
        @(posedge aclk);
        while (!done) begin
            if (++timeout > 1000)
                $fatal(1, "[FATAL] run_dma timeout src=0x%08X dst=0x%08X len=%0d add=0x%08X",
                       tsrc, tdst, tlen, tadd);
            @(posedge aclk);
        end
    endtask

    // ---------------------------------------------------------------
    // Check helpers
    // ---------------------------------------------------------------
    task automatic check_eq(input logic [31:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=0x%08X", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=0x%08X  exp=0x%08X", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq failed: %s", label);
        end
    endtask

    task automatic check_eq16(input logic [15:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=%0d", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=%0d  exp=%0d", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq16 failed: %s", label);
        end
    endtask

    task automatic check_bit(input logic got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  got=1'b%0b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=1'b%0b  exp=1'b%0b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_bit failed: %s", label);
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("../logs/simple_dma_add_nword_tb.vcd");
        $dumpvars(0, simple_dma_add_nword_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // Seed source memory
        slave.mem[0] = 32'h0000_0010;   // T2 source        (byte 0x00)
        slave.mem[4] = 32'h1000_0001;   // T3 source[0]     (byte 0x10)
        slave.mem[5] = 32'h2000_0002;   // T3 source[1]     (byte 0x14)
        slave.mem[6] = 32'h3000_0003;   // T3 source[2]     (byte 0x18)
        slave.mem[7] = 32'h4000_0004;   // T3 source[3]     (byte 0x1C)
        slave.mem[8] = 32'hFFFF_FFFF;   // T4 source        (byte 0x20)
        // T5 source words near end of valid range
        slave.mem[1021] = 32'hAAAA_1111; // byte 0xFF4
        slave.mem[1022] = 32'hBBBB_2222; // byte 0xFF8
        slave.mem[1023] = 32'hCCCC_3333; // byte 0xFFC
        // T6 source words
        slave.mem[128] = 32'h1111_AAAA;  // byte 0x200
        slave.mem[129] = 32'h2222_BBBB;  // byte 0x204
        slave.mem[130] = 32'h3333_CCCC;  // byte 0x208
        slave.mem[131] = 32'h4444_DDDD;  // byte 0x20C
        // T7 source (identity mode, add_value=0)
        slave.mem[200] = 32'h5555_AAAA;  // byte 0x320
        slave.mem[201] = 32'h6666_BBBB;  // byte 0x324
        slave.mem[202] = 32'h7777_CCCC;  // byte 0x328
        slave.mem[203] = 32'h8888_DDDD;  // byte 0x32C
        // T8 canary and recovery source
        slave.mem[386] = 32'hFACE_5678;  // T8a dst[2] canary byte 0x608
        slave.mem[250] = 32'h1234_5678;  // T8b src[0] byte 0x3E8
        slave.mem[251] = 32'h8765_4321;  // T8b src[1] byte 0x3EC
        // T9 source words
        slave.mem[260] = 32'hABCD_EF01;  // T9a src[0] byte 0x410
        slave.mem[261] = 32'hFEDC_BA98;  // T9a src[1] byte 0x414
        slave.mem[262] = 32'h1357_9BDF;  // T9a src[2] byte 0x418
        slave.mem[264] = 32'hDEAD_BEEF;  // T9b src[0] byte 0x420
        slave.mem[265] = 32'hCAFE_F00D;  // T9b src[1] byte 0x424
        slave.mem[266] = 32'hA0B1_C2D3;  // T9b src[2] byte 0x428

        // ============================================================
        // Test 1: length_words=0 — done immediately, no AXI transactions
        //   src=0x00, dst=0xD0, add=0x10
        //   Canary at dst[0] and dst[1] must remain unchanged.
        // ============================================================
        $display("[INFO] Test 1: length_words=0 — expect done, no error, processed_count=0");
        slave.mem[52] = 32'hABCD_EF01;   // canary at dst[0] (byte 0xD0)
        slave.mem[53] = 32'hFEDC_BA98;   // canary at dst[1] (byte 0xD4)
        run_dma(32'h0000_0000, 32'h0000_00D0, 16'h0, 32'h0000_0010);
        check_bit(done,            1'b1,          "T1 done");
        check_bit(error,           1'b0,          "T1 no error");
        check_eq16(processed_count, 16'd0,        "T1 processed_count=0");
        check_eq(slave.mem[52], 32'hABCD_EF01,    "T1 canary dst[0] mem[0xD0>>2] unchanged");

        // ============================================================
        // Test 2: length_words=1, add constant
        //   src[0]=0x0000_0010, add=0x0000_0005 → dst[0]=0x0000_0015
        //   Verify processed_count, last_input_data, last_output_data.
        // ============================================================
        $display("[CHK] t=%0t  phase=test2", $time);
        $display("[INFO] Test 2: length_words=1, 0x10 + 0x5 = 0x15");
        run_dma(32'h0000_0000, 32'h0000_0040, 16'h1, 32'h0000_0005);
        check_bit(done,            1'b1,           "T2 done");
        check_bit(error,           1'b0,           "T2 no error");
        check_eq16(processed_count, 16'd1,         "T2 processed_count=1");
        check_eq(last_input_data,  32'h0000_0010,  "T2 last_input_data");
        check_eq(last_output_data, 32'h0000_0015,  "T2 last_output_data");
        check_eq(slave.mem[16],    32'h0000_0015,  "T2 dst[0] mem[0x40>>2]");

        // ============================================================
        // Test 3: length_words=4, add 0x100 to each word
        //   src[0..3]=0x1000_0001/2/3/4, add=0x100
        //   Verify all four dst words, last_input, last_output, count.
        // ============================================================
        $display("[CHK] t=%0t  phase=test3", $time);
        $display("[INFO] Test 3: length_words=4, add 0x100 to four words");
        run_dma(32'h0000_0010, 32'h0000_0080, 16'h4, 32'h0000_0100);
        check_bit(done,            1'b1,           "T3 done");
        check_bit(error,           1'b0,           "T3 no error");
        check_eq16(processed_count, 16'd4,         "T3 processed_count=4");
        check_eq(last_input_data,  32'h4000_0004,  "T3 last_input_data");
        check_eq(last_output_data, 32'h4000_0104,  "T3 last_output_data");
        check_eq(slave.mem[32],    32'h1000_0101,  "T3 dst[0] mem[0x80>>2]");
        check_eq(slave.mem[33],    32'h2000_0102,  "T3 dst[1] mem[0x84>>2]");
        check_eq(slave.mem[34],    32'h3000_0103,  "T3 dst[2] mem[0x88>>2]");
        check_eq(slave.mem[35],    32'h4000_0104,  "T3 dst[3] mem[0x8C>>2]");

        // ============================================================
        // Test 4: 32-bit overflow — 0xFFFF_FFFF + 1 wraps to 0x0000_0000
        //   No error should be generated for arithmetic overflow.
        // ============================================================
        $display("[CHK] t=%0t  phase=test4", $time);
        $display("[INFO] Test 4: overflow — 0xFFFF_FFFF + 0x1 = 0x0 (wraps)");
        run_dma(32'h0000_0020, 32'h0000_00C0, 16'h1, 32'h0000_0001);
        check_bit(done,            1'b1,           "T4 done");
        check_bit(error,           1'b0,           "T4 no error (overflow is not an error)");
        check_eq16(processed_count, 16'd1,         "T4 processed_count=1");
        check_eq(slave.mem[48],    32'h0000_0000,  "T4 dst[0] mem[0xC0>>2] wrapped to 0");

        // ============================================================
        // Test 5: invalid source mid-processing
        //   src=0xFF4, dst=0x100, len=4, add=0x0000_0010
        //   MEM_DEPTH=1024 → valid byte range 0x000-0xFFC
        //   word 0: src 0xFF4 → valid (mem[1021]=0xAAAA_1111) → dst[0]=0xAAAA_1121
        //   word 1: src 0xFF8 → valid (mem[1022]=0xBBBB_2222) → dst[1]=0xBBBB_2232
        //   word 2: src 0xFFC → valid (mem[1023]=0xCCCC_3333) → dst[2]=0xCCCC_3343
        //   word 3: src 0x1000 → OOB → SLVERR on read → abort before write
        //   processed_count=3, error=1, dst[3] (mem[67]) unchanged
        // ============================================================
        $display("[CHK] t=%0t  phase=test5", $time);
        $display("[INFO] Test 5: invalid src mid-processing src=0xFF4 len=4");
        run_dma(32'h0000_0FF4, 32'h0000_0100, 16'h4, 32'h0000_0010);
        check_bit(done,            1'b1,           "T5 done");
        check_bit(error,           1'b1,           "T5 error (OOB src word 3)");
        check_eq16(processed_count, 16'd3,         "T5 processed_count=3");
        check_eq(slave.mem[64],    32'hAAAA_1121,  "T5 dst[0] mem[0x100>>2]");
        check_eq(slave.mem[65],    32'hBBBB_2232,  "T5 dst[1] mem[0x104>>2]");
        check_eq(slave.mem[66],    32'hCCCC_3343,  "T5 dst[2] mem[0x108>>2]");
        check_eq(slave.mem[67],    32'h0000_0000,  "T5 dst[3] mem[0x10C>>2] unchanged (no write)");
        // RTL always latches rdata into input_lat in RD_DATA, even on SLVERR.
        // The memory model returns rdata=0 for OOB reads, so after the failed
        // word-3 read: input_lat=0x0, last_output_data = 0x0 + add_lat = 0x10.
        check_eq(last_input_data,  32'h0000_0000,  "T5 last_input_data = OOB rdata (0x0)");
        check_eq(last_output_data, 32'h0000_0010,  "T5 last_output_data = OOB rdata + add_value");

        // ============================================================
        // Test 6: invalid destination mid-processing
        //   src=0x200, dst=0xFF4, len=4, add=0x0000_0020
        //   word 0: dst 0xFF4 (mem[1021]) → valid → 0x1111_AAAA + 0x20 = 0x1111_AACA
        //   word 1: dst 0xFF8 (mem[1022]) → valid → 0x2222_BBBB + 0x20 = 0x2222_BBDB
        //   word 2: dst 0xFFC (mem[1023]) → valid → 0x3333_CCCC + 0x20 = 0x3333_CCEC
        //   word 3: dst 0x1000 → OOB → SLVERR on write → abort
        //   processed_count=3, error=1
        //   src mem[128] (0x200) must remain unchanged
        // ============================================================
        $display("[CHK] t=%0t  phase=test6", $time);
        $display("[INFO] Test 6: invalid dst mid-processing src=0x200 dst=0xFF4 len=4");
        run_dma(32'h0000_0200, 32'h0000_0FF4, 16'h4, 32'h0000_0020);
        check_bit(done,            1'b1,           "T6 done");
        check_bit(error,           1'b1,           "T6 error (OOB dst word 3)");
        check_eq16(processed_count, 16'd3,         "T6 processed_count=3");
        check_eq(slave.mem[1021],  32'h1111_AACA,  "T6 dst[0] mem[0xFF4>>2]");
        check_eq(slave.mem[1022],  32'h2222_BBDB,  "T6 dst[1] mem[0xFF8>>2]");
        check_eq(slave.mem[1023],  32'h3333_CCEC,  "T6 dst[2] mem[0xFFC>>2]");
        check_eq(slave.mem[128],   32'h1111_AAAA,  "T6 src mem[0x200>>2] unchanged");
        // Word 3 is read successfully before the write fails (OOB dst).
        // input_lat is latched with word 3's read data (0x4444_DDDD).
        // last_output_data = input_lat + add_lat = 0x4444_DDDD + 0x20 = 0x4444_DDFD.
        check_eq(last_input_data,  32'h4444_DDDD,  "T6 last_input_data = failed-write input word");
        check_eq(last_output_data, 32'h4444_DDFD,  "T6 last_output_data = failed-write processed word");

        // ============================================================
        // Test 7: identity mode — add_value=0 acts as a pure copy
        //   src 0x320-0x32C (mem[200-203]) → dst 0x500-0x50C (mem[320-323])
        //   Verify each dst word equals its source word.
        //   Verify last_input_data and last_output_data both equal the last source word.
        // ============================================================
        $display("[CHK] t=%0t  phase=test7", $time);
        $display("[INFO] Test 7: identity mode (add_value=0), 4-word copy");
        run_dma(32'h0000_0320, 32'h0000_0500, 16'h4, 32'h0000_0000);
        check_bit(done,            1'b1,           "T7 done");
        check_bit(error,           1'b0,           "T7 no error");
        check_eq16(processed_count, 16'd4,         "T7 processed_count=4");
        check_eq(last_input_data,  32'h8888_DDDD,  "T7 last_input_data = last src word");
        check_eq(last_output_data, 32'h8888_DDDD,  "T7 last_output_data = last src word (add=0)");
        check_eq(slave.mem[320],   32'h5555_AAAA,  "T7 dst[0] mem[0x500>>2]");
        check_eq(slave.mem[321],   32'h6666_BBBB,  "T7 dst[1] mem[0x504>>2]");
        check_eq(slave.mem[322],   32'h7777_CCCC,  "T7 dst[2] mem[0x508>>2]");
        check_eq(slave.mem[323],   32'h8888_DDDD,  "T7 dst[3] mem[0x50C>>2]");

        // ============================================================
        // Test 8: restart after read error
        //   Step 8a: src=0xFF8 (mem[1022,1023] from T6), dst=0x600, len=3, add=0x50
        //     word 0: read mem[1022]=0x2222_BBDB → write mem[384]=0x2222_BC2B
        //     word 1: read mem[1023]=0x3333_CCEC → write mem[385]=0x3333_CD3C
        //     word 2: src=0x1000 OOB → SLVERR on read → abort, no write
        //     processed_count=2, error=1; dst[2] canary unchanged
        //   Step 8b: src=0x3E8, dst=0x700, len=2, add=0x0F — fresh valid transfer
        // ============================================================
        $display("[CHK] t=%0t  phase=test8a", $time);
        $display("[INFO] Test 8a: read-error transfer (3 words, word 2 src OOB)");
        run_dma(32'h0000_0FF8, 32'h0000_0600, 16'h3, 32'h0000_0050);
        check_bit(done,             1'b1,           "T8a done");
        check_bit(error,            1'b1,           "T8a error (OOB src word 2)");
        check_eq16(processed_count, 16'd2,          "T8a processed_count=2");
        check_eq(slave.mem[384],    32'h2222_BC2B,  "T8a dst[0] mem[0x600>>2]");
        check_eq(slave.mem[385],    32'h3333_CD3C,  "T8a dst[1] mem[0x604>>2]");
        check_eq(slave.mem[386],    32'hFACE_5678,  "T8a dst[2] canary mem[0x608>>2] unchanged");
        check_eq(last_input_data,   32'h0000_0000,  "T8a last_input_data = OOB rdata (0x0)");
        check_eq(last_output_data,  32'h0000_0050,  "T8a last_output_data = OOB rdata + add");

        $display("[CHK] t=%0t  phase=test8b", $time);
        $display("[INFO] Test 8b: valid recovery after read error");
        run_dma(32'h0000_03E8, 32'h0000_0700, 16'h2, 32'h0000_000F);
        check_bit(done,             1'b1,           "T8b done");
        check_bit(error,            1'b0,           "T8b no error");
        check_eq16(processed_count, 16'd2,          "T8b processed_count=2");
        check_eq(last_input_data,   32'h8765_4321,  "T8b last_input_data = last src word");
        check_eq(last_output_data,  32'h8765_4330,  "T8b last_output_data = last src + add");
        check_eq(slave.mem[448],    32'h1234_5687,  "T8b dst[0] mem[0x700>>2]");
        check_eq(slave.mem[449],    32'h8765_4330,  "T8b dst[1] mem[0x704>>2]");

        // ============================================================
        // Test 9: restart after write error
        //   Step 9a: src=0x410, dst=0xFF8 (mem[1022,1023,1024]), len=3, add=0x03
        //     word 0: read mem[260]=0xABCD_EF01 → write mem[1022]=0xABCD_EF04
        //     word 1: read mem[261]=0xFEDC_BA98 → write mem[1023]=0xFEDC_BA9B
        //     word 2: read mem[262]=0x1357_9BDF → try write mem[1024] OOB → SLVERR → abort
        //     processed_count=2, error=1; src mem[260] unchanged
        //   Step 9b: src=0x420, dst=0x780, len=3, add=0x04 — fresh valid transfer
        // ============================================================
        $display("[CHK] t=%0t  phase=test9a", $time);
        $display("[INFO] Test 9a: write-error transfer (3 words, word 2 dst OOB)");
        run_dma(32'h0000_0410, 32'h0000_0FF8, 16'h3, 32'h0000_0003);
        check_bit(done,             1'b1,           "T9a done");
        check_bit(error,            1'b1,           "T9a error (OOB dst word 2)");
        check_eq16(processed_count, 16'd2,          "T9a processed_count=2");
        check_eq(slave.mem[1022],   32'hABCD_EF04,  "T9a dst[0] mem[0xFF8>>2]");
        check_eq(slave.mem[1023],   32'hFEDC_BA9B,  "T9a dst[1] mem[0xFFC>>2]");
        check_eq(slave.mem[260],    32'hABCD_EF01,  "T9a src mem[0x410>>2] unchanged");
        check_eq(last_input_data,   32'h1357_9BDF,  "T9a last_input_data = word 2 read data");
        check_eq(last_output_data,  32'h1357_9BE2,  "T9a last_output_data = word 2 processed");

        $display("[CHK] t=%0t  phase=test9b", $time);
        $display("[INFO] Test 9b: valid recovery after write error");
        run_dma(32'h0000_0420, 32'h0000_0780, 16'h3, 32'h0000_0004);
        check_bit(done,             1'b1,           "T9b done");
        check_bit(error,            1'b0,           "T9b no error");
        check_eq16(processed_count, 16'd3,          "T9b processed_count=3");
        check_eq(last_input_data,   32'hA0B1_C2D3,  "T9b last_input_data = last src word");
        check_eq(last_output_data,  32'hA0B1_C2D7,  "T9b last_output_data = last src + add");
        check_eq(slave.mem[480],    32'hDEAD_BEF3,  "T9b dst[0] mem[0x780>>2]");
        check_eq(slave.mem[481],    32'hCAFE_F011,  "T9b dst[1] mem[0x784>>2]");
        check_eq(slave.mem[482],    32'hA0B1_C2D7,  "T9b dst[2] mem[0x788>>2]");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] simple_dma_add_nword_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] simple_dma_add_nword_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
