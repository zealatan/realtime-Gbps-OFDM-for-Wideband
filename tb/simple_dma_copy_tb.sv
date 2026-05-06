`timescale 1ns/1ps

// Testbench: simple_dma_copy (DUT) connected to axi_mem_model (slave).
// Drive control inputs on negedge; sample DUT outputs on posedge.
module simple_dma_copy_tb;

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
    wire [31:0] copied_data;
    wire        done;
    wire        error;

    // ---------------------------------------------------------------
    // DUT — DMA copy engine
    // ---------------------------------------------------------------
    simple_dma_copy dut (
        .aclk        (aclk),       .aresetn     (aresetn),
        .start       (start_tb),   .src_addr    (src_tb),
        .dst_addr    (dst_tb),
        .copied_data (copied_data), .done       (done),    .error (error),
        .araddr  (axi_araddr),  .arvalid (axi_arvalid), .arready (axi_arready),
        .rdata   (axi_rdata),   .rresp   (axi_rresp),   .rlast   (axi_rlast),
        .rvalid  (axi_rvalid),  .rready  (axi_rready),
        .awaddr  (axi_awaddr),  .awvalid (axi_awvalid), .awready (axi_awready),
        .wdata   (axi_wdata),   .wstrb   (axi_wstrb),   .wlast   (axi_wlast),
        .wvalid  (axi_wvalid),  .wready  (axi_wready),
        .bresp   (axi_bresp),   .bvalid  (axi_bvalid),  .bready  (axi_bready)
    );

    // ---------------------------------------------------------------
    // Slave — AXI memory model (1 KB at base 0x0)
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
    //   Leaves simulation time at the posedge where done=1.
    // ---------------------------------------------------------------
    task automatic run_dma(
        input logic [31:0] tsrc,
        input logic [31:0] tdst
    );
        int timeout;
        @(negedge aclk);
        src_tb   = tsrc;
        dst_tb   = tdst;
        start_tb = 1'b1;
        @(negedge aclk);
        start_tb = 1'b0;
        timeout  = 0;
        @(posedge aclk);
        while (!done) begin
            if (++timeout > 200)
                $fatal(1, "[FATAL] run_dma timeout src=0x%08X dst=0x%08X",
                       tsrc, tdst);
            @(posedge aclk);
        end
    endtask

    // ---------------------------------------------------------------
    // check helpers — hard: $fatal on mismatch
    // ---------------------------------------------------------------
    task automatic check_eq(input logic [31:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-46s  got=0x%08X", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-46s  got=0x%08X  exp=0x%08X", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq failed");
        end
    endtask

    task automatic check_bit(input logic got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-46s  got=1'b%0b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-46s  got=1'b%0b  exp=1'b%0b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_bit failed");
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("../logs/simple_dma_copy_tb.vcd");
        $dumpvars(0, simple_dma_copy_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // Seed source memory via hierarchical access (simulation only)
        slave.mem[0] = 32'hDEAD_BEEF;   // byte addr 0x00
        slave.mem[1] = 32'hCAFE_F00D;   // byte addr 0x04
        slave.mem[2] = 32'hA5A5_A5A5;   // byte addr 0x08

        // ============================================================
        // Test 1: copy word 0x00 → 0x10
        // ============================================================
        $display("[INFO] Test 1: copy 0x00 -> 0x10");
        run_dma(32'h0000_0000, 32'h0000_0010);
        check_bit(done,        1'b1,          "T1 done");
        check_bit(error,       1'b0,          "T1 no error");
        check_eq(copied_data,  32'hDEAD_BEEF, "T1 copied_data");
        check_eq(slave.mem[4], 32'hDEAD_BEEF, "T1 dst mem[0x10>>2]");

        // ============================================================
        // Test 2: copy word 0x04 → 0x20
        // ============================================================
        $display("[CHK] t=%0t  phase=copy2", $time);
        $display("[INFO] Test 2: copy 0x04 -> 0x20");
        run_dma(32'h0000_0004, 32'h0000_0020);
        check_bit(done,        1'b1,          "T2 done");
        check_bit(error,       1'b0,          "T2 no error");
        check_eq(copied_data,  32'hCAFE_F00D, "T2 copied_data");
        check_eq(slave.mem[8], 32'hCAFE_F00D, "T2 dst mem[0x20>>2]");

        // ============================================================
        // Test 3: invalid src address (OOB) — expect error, no write
        //   MEM_DEPTH=1024 → valid range 0x000–0xFFC; 0x1000 is OOB.
        //   Memory model returns SLVERR on read; DMA aborts at DONE,
        //   write phase is skipped → dst mem[0x30>>2] must stay 0x0.
        // ============================================================
        $display("[CHK] t=%0t  phase=invalid_src", $time);
        $display("[INFO] Test 3: invalid src=0x1000 -> dst=0x30 — expect error, dst unchanged");
        run_dma(32'h0000_1000, 32'h0000_0030);
        check_bit(done,         1'b1, "T3 done (OOB src)");
        check_bit(error,        1'b1, "T3 error asserted (SLVERR on read)");
        check_eq(slave.mem[12], 32'h0, "T3 dst mem[0x30>>2] unchanged (write skipped)");

        // ============================================================
        // Test 4: invalid dst address (OOB) — expect error; src and
        //         canary unchanged; no in-range word modified.
        //   src=0x08 is valid, holds 0xA5A5_A5A5 (seeded above).
        //   dst=0x2000 is OOB (MEM_END = MEM_BASE + 1024*4 = 0x1000).
        //   Read succeeds (rresp=OKAY); write is issued, slave returns
        //   SLVERR and leaves all in-range memory untouched.
        //   Canary at word index 100 (byte addr 0x190, within valid
        //   range 0x000–0xFFC) is planted before the DMA run and
        //   checked afterwards to confirm no accidental in-range write.
        // ============================================================
        $display("[CHK] t=%0t  phase=invalid_dst", $time);
        $display("[INFO] Test 4: src=0x08, invalid dst=0x2000 — error, src/canary unchanged");

        slave.mem[100] = 32'hFEED_FACE;   // canary at byte addr 0x190

        run_dma(32'h0000_0008, 32'h0000_2000);
        check_bit(done,          1'b1,          "T4 done (OOB dst)");
        check_bit(error,         1'b1,          "T4 error asserted (SLVERR on write)");
        check_eq(copied_data,    32'hA5A5_A5A5, "T4 copied_data matches src");
        check_eq(slave.mem[2],   32'hA5A5_A5A5, "T4 src mem[0x08>>2] unchanged");
        check_eq(slave.mem[100], 32'hFEED_FACE, "T4 canary mem[100] (0x190) unchanged");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] simple_dma_copy_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] simple_dma_copy_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
