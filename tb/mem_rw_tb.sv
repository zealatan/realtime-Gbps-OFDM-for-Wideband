`timescale 1ns/1ps

// Drive AXI master signals on negedge; sample DUT ready/valid on posedge.
module mem_rw_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // AXI4 wires
    // ---------------------------------------------------------------
    logic [31:0] awaddr;  logic        awvalid; wire         awready;
    logic [31:0] wdata;   logic [ 3:0] wstrb;   logic        wlast;
    logic        wvalid;  wire         wready;
    wire  [ 1:0] bresp;   wire         bvalid;  logic        bready;
    logic [31:0] araddr;  logic        arvalid; wire         arready;
    wire  [31:0] rdata;   wire  [ 1:0] rresp;   wire         rlast;
    wire         rvalid;  logic        rready;

    // ---------------------------------------------------------------
    // DUT — 1 KB memory at base 0x0000_0000
    // ---------------------------------------------------------------
    axi_mem_model #(
        .MEM_DEPTH (1024),
        .MEM_BASE  (32'h0000_0000)
    ) dut (
        .aclk    (aclk),    .aresetn (aresetn),
        .awaddr  (awaddr),  .awvalid (awvalid), .awready (awready),
        .wdata   (wdata),   .wstrb   (wstrb),   .wlast   (wlast),
        .wvalid  (wvalid),  .wready  (wready),
        .bresp   (bresp),   .bvalid  (bvalid),  .bready  (bready),
        .araddr  (araddr),  .arvalid (arvalid), .arready (arready),
        .rdata   (rdata),   .rresp   (rresp),   .rlast   (rlast),
        .rvalid  (rvalid),  .rready  (rready)
    );

    int        pass_count = 0;
    int        fail_count = 0;
    logic [1:0] last_bresp;
    logic [1:0] last_rresp;

    // ---------------------------------------------------------------
    // axi_write32 — simultaneous AW + W
    // ---------------------------------------------------------------
    task automatic axi_write32(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 3:0] strb
    );
        int timeout;
        @(negedge aclk);
        awaddr = addr;  awvalid = 1'b1;
        wdata  = data;  wstrb   = strb; wlast = 1'b1; wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!awready || !wready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write32 AW/W timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        awvalid = 1'b0; wvalid = 1'b0; bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!bvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write32 B timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        last_bresp = bresp;
        @(negedge aclk);
        bready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_read32
    // ---------------------------------------------------------------
    task automatic axi_read32(
        input  logic [31:0] addr,
        output logic [31:0] rd
    );
        int timeout;
        @(negedge aclk);
        araddr = addr; arvalid = 1'b1; rready = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!arready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read32 AR timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        arvalid = 1'b0; rready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!rvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read32 R timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        rd = rdata; last_rresp = rresp;
        @(negedge aclk);
        rready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // check_eq — hard: $fatal on mismatch
    // ---------------------------------------------------------------
    task automatic check_eq(input logic [31:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-44s  got=0x%08X", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-44s  got=0x%08X  exp=0x%08X", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq failed");
        end
    endtask

    // ---------------------------------------------------------------
    // check_resp — hard: $fatal on mismatch
    // ---------------------------------------------------------------
    task automatic check_resp(input logic [1:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-44s  resp=2'b%02b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-44s  got=2'b%02b  exp=2'b%02b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_resp failed");
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    logic [31:0] rd;

    initial begin
        $dumpfile("../logs/mem_rw_tb.vcd");
        $dumpvars(0, mem_rw_tb);

        awvalid = 1'b0; awaddr = '0;
        wvalid  = 1'b0; wdata  = '0; wstrb = '0; wlast = 1'b0;
        bready  = 1'b0;
        arvalid = 1'b0; araddr = '0;
        rready  = 1'b0;

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // ============================================================
        // Test 1 — full word write / readback
        // ============================================================
        $display("[INFO] Test 1: full word write/readback");

        axi_write32(32'h0000_0000, 32'hDEAD_BEEF, 4'hF);
        check_resp(last_bresp, 2'b00, "T1 bresp OKAY addr=0x00");
        axi_read32(32'h0000_0000, rd);
        check_eq  (rd,         32'hDEAD_BEEF, "T1 readback addr=0x00");
        check_resp(last_rresp, 2'b00,         "T1 rresp OKAY addr=0x00");

        axi_write32(32'h0000_0010, 32'hCAFE_F00D, 4'hF);
        check_resp(last_bresp, 2'b00, "T1 bresp OKAY addr=0x10");
        axi_read32(32'h0000_0010, rd);
        check_eq  (rd,         32'hCAFE_F00D, "T1 readback addr=0x10");
        check_resp(last_rresp, 2'b00,         "T1 rresp OKAY addr=0x10");

        // ============================================================
        // Test 2 — multiple addresses; unique values, independent cells
        // ============================================================
        $display("[CHK] t=%0t  phase=multiple_addr", $time);
        $display("[INFO] Test 2: multiple addresses");

        for (int i = 0; i < 4; i++) begin
            axi_write32(i * 4, 32'hA0B0_C000 | i, 4'hF);
            check_resp(last_bresp, 2'b00,
                       $sformatf("T2 bresp OKAY addr=0x%02X", i * 4));
        end
        for (int i = 0; i < 4; i++) begin
            axi_read32(i * 4, rd);
            check_eq  (rd,         32'hA0B0_C000 | i,
                       $sformatf("T2 readback addr=0x%02X", i * 4));
            check_resp(last_rresp, 2'b00,
                       $sformatf("T2 rresp OKAY addr=0x%02X", i * 4));
        end

        // ============================================================
        // Test 3 — byte-lane WSTRB writes on a single address
        // ============================================================
        $display("[CHK] t=%0t  phase=wstrb", $time);
        $display("[INFO] Test 3: byte-lane WSTRB writes");

        // Seed address 0x00 with all-ones
        axi_write32(32'h00, 32'hFFFF_FFFF, 4'hF);
        check_resp(last_bresp, 2'b00, "T3 seed bresp OKAY");

        // wstrb=0001: clear byte 0 → 0xFFFF_FF00
        axi_write32(32'h00, 32'h0000_0000, 4'b0001);
        check_resp(last_bresp, 2'b00, "T3 wstrb=0001 bresp OKAY");
        axi_read32(32'h00, rd);
        check_eq  (rd,         32'hFFFF_FF00, "T3 wstrb=0001 byte0 cleared");
        check_resp(last_rresp, 2'b00,         "T3 wstrb=0001 rresp OKAY");

        // wstrb=1000: set byte 3 to 0xAB → 0xABFF_FF00
        axi_write32(32'h00, 32'hAB00_0000, 4'b1000);
        check_resp(last_bresp, 2'b00, "T3 wstrb=1000 bresp OKAY");
        axi_read32(32'h00, rd);
        check_eq  (rd,         32'hABFF_FF00, "T3 wstrb=1000 byte3 set to 0xAB");
        check_resp(last_rresp, 2'b00,         "T3 wstrb=1000 rresp OKAY");

        // wstrb=0110: update bytes 1+2 → 0xAB34_1200
        axi_write32(32'h00, 32'h0034_1200, 4'b0110);
        check_resp(last_bresp, 2'b00, "T3 wstrb=0110 bresp OKAY");
        axi_read32(32'h00, rd);
        check_eq  (rd,         32'hAB34_1200, "T3 wstrb=0110 bytes1+2 updated");
        check_resp(last_rresp, 2'b00,         "T3 wstrb=0110 rresp OKAY");

        // ============================================================
        // Test 4 — read from never-written address; expect zero
        // ============================================================
        $display("[CHK] t=%0t  phase=unwritten_addr", $time);
        $display("[INFO] Test 4: read from unwritten address (expect 0x0)");

        axi_read32(32'h0000_0100, rd);   // word 64, never written
        check_eq  (rd,         32'h0000_0000, "T4 unwritten addr=0x100 reads zero");
        check_resp(last_rresp, 2'b00,         "T4 rresp OKAY unwritten");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] mem_rw_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] mem_rw_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
