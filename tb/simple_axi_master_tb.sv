`timescale 1ns/1ps

// Testbench: simple_axi_master (DUT) connected to axi_mem_model (slave).
// Drive control inputs on negedge; sample DUT outputs on posedge.
module simple_axi_master_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // Testbench control inputs to master
    // ---------------------------------------------------------------
    logic        start_tb      = 1'b0;
    logic [31:0] addr_tb       = '0;
    logic [31:0] write_data_tb = '0;

    // ---------------------------------------------------------------
    // AXI4 wires — master output → slave input
    // ---------------------------------------------------------------
    wire [31:0] axi_awaddr;  wire axi_awvalid; wire axi_awready;
    wire [31:0] axi_wdata;   wire [3:0] axi_wstrb; wire axi_wlast;
    wire        axi_wvalid;  wire axi_wready;
    wire [1:0]  axi_bresp;   wire axi_bvalid;  wire axi_bready;
    wire [31:0] axi_araddr;  wire axi_arvalid; wire axi_arready;
    wire [31:0] axi_rdata;   wire [1:0] axi_rresp; wire axi_rlast;
    wire        axi_rvalid;  wire axi_rready;

    // ---------------------------------------------------------------
    // Master status outputs
    // ---------------------------------------------------------------
    wire [31:0] read_data;
    wire        done;
    wire        error;

    // ---------------------------------------------------------------
    // DUT — AXI master
    // ---------------------------------------------------------------
    simple_axi_master dut (
        .aclk       (aclk),          .aresetn    (aresetn),
        .start      (start_tb),      .addr       (addr_tb),
        .write_data (write_data_tb),
        .read_data  (read_data),     .done       (done),      .error (error),
        .awaddr  (axi_awaddr),  .awvalid (axi_awvalid), .awready (axi_awready),
        .wdata   (axi_wdata),   .wstrb   (axi_wstrb),   .wlast   (axi_wlast),
        .wvalid  (axi_wvalid),  .wready  (axi_wready),
        .bresp   (axi_bresp),   .bvalid  (axi_bvalid),  .bready  (axi_bready),
        .araddr  (axi_araddr),  .arvalid (axi_arvalid), .arready (axi_arready),
        .rdata   (axi_rdata),   .rresp   (axi_rresp),   .rlast   (axi_rlast),
        .rvalid  (axi_rvalid),  .rready  (axi_rready)
    );

    // ---------------------------------------------------------------
    // Slave — AXI memory model (1 KB at base 0x0)
    // ---------------------------------------------------------------
    axi_mem_model #(
        .MEM_DEPTH (1024),
        .MEM_BASE  (32'h0000_0000)
    ) slave (
        .aclk    (aclk),         .aresetn  (aresetn),
        .awaddr  (axi_awaddr),   .awvalid  (axi_awvalid),  .awready (axi_awready),
        .wdata   (axi_wdata),    .wstrb    (axi_wstrb),    .wlast   (axi_wlast),
        .wvalid  (axi_wvalid),   .wready   (axi_wready),
        .bresp   (axi_bresp),    .bvalid   (axi_bvalid),   .bready  (axi_bready),
        .araddr  (axi_araddr),   .arvalid  (axi_arvalid),  .arready (axi_arready),
        .rdata   (axi_rdata),    .rresp    (axi_rresp),    .rlast   (axi_rlast),
        .rvalid  (axi_rvalid),   .rready   (axi_rready)
    );

    int pass_count = 0;
    int fail_count = 0;

    // ---------------------------------------------------------------
    // run_txn — pulse start for one cycle, wait for done
    //   Leaves simulation time at the posedge where done=1.
    // ---------------------------------------------------------------
    task automatic run_txn(
        input logic [31:0] taddr,
        input logic [31:0] tdata
    );
        int timeout;
        @(negedge aclk);
        addr_tb       = taddr;
        write_data_tb = tdata;
        start_tb      = 1'b1;
        @(negedge aclk);
        start_tb = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!done) begin
            if (++timeout > 200)
                $fatal(1, "[FATAL] run_txn timeout addr=0x%08X data=0x%08X",
                       taddr, tdata);
            @(posedge aclk);
        end
    endtask

    // ---------------------------------------------------------------
    // check_eq — hard: $fatal on mismatch
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

    // ---------------------------------------------------------------
    // check_bit — hard: $fatal on mismatch (1-bit signals)
    // ---------------------------------------------------------------
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
        $dumpfile("../logs/simple_axi_master_tb.vcd");
        $dumpvars(0, simple_axi_master_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // ============================================================
        // Test 1 — single write/readback
        // ============================================================
        $display("[INFO] Test 1: single write/readback");

        run_txn(32'h0000_0000, 32'hDEAD_BEEF);
        check_bit(done,      1'b1,          "T1 done");
        check_bit(error,     1'b0,          "T1 no error");
        check_eq (read_data, 32'hDEAD_BEEF, "T1 readback addr=0x00");

        // ============================================================
        // Test 2 — multiple addresses and data values
        // ============================================================
        $display("[CHK] t=%0t  phase=multi_addr", $time);
        $display("[INFO] Test 2: multiple addresses / data values");

        run_txn(32'h0000_0004, 32'hCAFE_F00D);
        check_bit(done,      1'b1,          "T2 done addr=0x04");
        check_bit(error,     1'b0,          "T2 no error addr=0x04");
        check_eq (read_data, 32'hCAFE_F00D, "T2 readback addr=0x04");

        run_txn(32'h0000_0008, 32'hA5A5_A5A5);
        check_bit(done,      1'b1,          "T2 done addr=0x08");
        check_bit(error,     1'b0,          "T2 no error addr=0x08");
        check_eq (read_data, 32'hA5A5_A5A5, "T2 readback addr=0x08");

        run_txn(32'h0000_000C, 32'h0000_0001);
        check_bit(done,      1'b1,          "T2 done addr=0x0C");
        check_bit(error,     1'b0,          "T2 no error addr=0x0C");
        check_eq (read_data, 32'h0000_0001, "T2 readback addr=0x0C");

        // ============================================================
        // Test 3 — out-of-range address: expect error=1
        //   MEM_DEPTH=1024 → valid range 0x000–0xFFC; 0x1000 is OOB.
        //   Memory model returns SLVERR on both write and read.
        //   Master sets error from bresp, rresp, and data mismatch.
        // ============================================================
        $display("[CHK] t=%0t  phase=oob_error", $time);
        $display("[INFO] Test 3: out-of-range address 0x1000 — expect error");

        run_txn(32'h0000_1000, 32'h1234_5678);
        check_bit(done,  1'b1, "T3 done (OOB addr)");
        check_bit(error, 1'b1, "T3 error asserted (SLVERR)");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] simple_axi_master_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] simple_axi_master_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
