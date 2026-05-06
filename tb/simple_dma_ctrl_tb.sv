`timescale 1ns/1ps

// Testbench: simple_dma_ctrl (DUT) + axi_mem_model (AXI4 slave).
// AXI-lite tasks: negedge-drive, posedge-sample.
module simple_dma_ctrl_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // AXI-lite slave TB drivers
    // ---------------------------------------------------------------
    logic [31:0] s_awaddr_tb  = '0;
    logic        s_awvalid_tb = 1'b0;
    logic [31:0] s_wdata_tb   = '0;
    logic [ 3:0] s_wstrb_tb   = '0;
    logic        s_wvalid_tb  = 1'b0;
    logic        s_bready_tb  = 1'b0;
    logic [31:0] s_araddr_tb  = '0;
    logic        s_arvalid_tb = 1'b0;
    logic        s_rready_tb  = 1'b0;

    // ---------------------------------------------------------------
    // AXI-lite slave DUT outputs (read by TB)
    // ---------------------------------------------------------------
    wire        s_awready;
    wire        s_wready;
    wire [ 1:0] s_bresp;
    wire        s_bvalid;
    wire        s_arready;
    wire [31:0] s_rdata;
    wire [ 1:0] s_rresp;
    wire        s_rvalid;

    // ---------------------------------------------------------------
    // AXI4 master wires — DUT ↔ mem slave
    // ---------------------------------------------------------------
    wire [31:0] m_araddr;  wire m_arvalid; wire m_arready;
    wire [31:0] m_rdata;   wire [1:0] m_rresp; wire m_rlast;
    wire        m_rvalid;  wire m_rready;
    wire [31:0] m_awaddr;  wire m_awvalid; wire m_awready;
    wire [31:0] m_wdata;   wire [3:0] m_wstrb; wire m_wlast;
    wire        m_wvalid;  wire m_wready;
    wire [ 1:0] m_bresp;   wire m_bvalid; wire m_bready;

    // ---------------------------------------------------------------
    // DUT — AXI-lite DMA controller
    // ---------------------------------------------------------------
    simple_dma_ctrl dut (
        .aclk       (aclk),         .aresetn    (aresetn),
        .s_awaddr   (s_awaddr_tb),  .s_awvalid  (s_awvalid_tb), .s_awready (s_awready),
        .s_wdata    (s_wdata_tb),   .s_wstrb    (s_wstrb_tb),
        .s_wvalid   (s_wvalid_tb),  .s_wready   (s_wready),
        .s_bresp    (s_bresp),      .s_bvalid   (s_bvalid),    .s_bready  (s_bready_tb),
        .s_araddr   (s_araddr_tb),  .s_arvalid  (s_arvalid_tb),.s_arready (s_arready),
        .s_rdata    (s_rdata),      .s_rresp    (s_rresp),
        .s_rvalid   (s_rvalid),     .s_rready   (s_rready_tb),
        .m_araddr   (m_araddr),     .m_arvalid  (m_arvalid),   .m_arready (m_arready),
        .m_rdata    (m_rdata),      .m_rresp    (m_rresp),     .m_rlast   (m_rlast),
        .m_rvalid   (m_rvalid),     .m_rready   (m_rready),
        .m_awaddr   (m_awaddr),     .m_awvalid  (m_awvalid),   .m_awready (m_awready),
        .m_wdata    (m_wdata),      .m_wstrb    (m_wstrb),     .m_wlast   (m_wlast),
        .m_wvalid   (m_wvalid),     .m_wready   (m_wready),
        .m_bresp    (m_bresp),      .m_bvalid   (m_bvalid),    .m_bready  (m_bready)
    );

    // ---------------------------------------------------------------
    // AXI4 memory slave (4 KB at base 0x0)
    // ---------------------------------------------------------------
    axi_mem_model #(.MEM_DEPTH(1024), .MEM_BASE(32'h0)) mem_slave (
        .aclk    (aclk),         .aresetn  (aresetn),
        .araddr  (m_araddr),     .arvalid  (m_arvalid),  .arready (m_arready),
        .rdata   (m_rdata),      .rresp    (m_rresp),    .rlast   (m_rlast),
        .rvalid  (m_rvalid),     .rready   (m_rready),
        .awaddr  (m_awaddr),     .awvalid  (m_awvalid),  .awready (m_awready),
        .wdata   (m_wdata),      .wstrb    (m_wstrb),    .wlast   (m_wlast),
        .wvalid  (m_wvalid),     .wready   (m_wready),
        .bresp   (m_bresp),      .bvalid   (m_bvalid),   .bready  (m_bready)
    );

    int pass_count = 0;
    int fail_count = 0;

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
    // check_le32 — verifies got <= max_val
    // ---------------------------------------------------------------
    task automatic check_le32(input logic [31:0] got, max_val, input string label);
        if (got <= max_val) begin
            $display("[PASS] %-52s  got=0x%08X  max=0x%08X", label, got, max_val);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=0x%08X  max=0x%08X", label, got, max_val);
            fail_count++;
            $fatal(1, "[FATAL] check_le32 failed: %s", label);
        end
    endtask

    // ---------------------------------------------------------------
    // axil_write32 — simultaneous AW+W, checks bresp
    // ---------------------------------------------------------------
    task automatic axil_write32(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 1:0] exp_resp
    );
        logic [1:0] got_resp;
        int         timeout;
        @(negedge aclk);
        s_awaddr_tb  = addr;
        s_awvalid_tb = 1'b1;
        s_wdata_tb   = data;
        s_wstrb_tb   = 4'hF;
        s_wvalid_tb  = 1'b1;
        s_bready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_awready && s_awvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write32 AW timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid_tb = 1'b0;
        s_wvalid_tb  = 1'b0;
        s_bready_tb  = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_bvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write32 B timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("bresp @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // axil_write_aw_first — AW arrives, then W (W_WAIT_W path), checks bresp
    // ---------------------------------------------------------------
    task automatic axil_write_aw_first(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 1:0] exp_resp
    );
        logic [1:0] got_resp;
        int         timeout;
        // Phase 1: drive AW only
        @(negedge aclk);
        s_awaddr_tb  = addr;
        s_awvalid_tb = 1'b1;
        s_wvalid_tb  = 1'b0;
        s_bready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_awready && s_awvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_aw_first AW timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 2: deassert AW, drive W one negedge later
        @(negedge aclk);
        s_awvalid_tb = 1'b0;
        s_wdata_tb   = data;
        s_wstrb_tb   = 4'hF;
        s_wvalid_tb  = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!(s_wready && s_wvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_aw_first W timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 3: deassert W, assert bready, wait for B
        @(negedge aclk);
        s_wvalid_tb = 1'b0;
        s_bready_tb = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_bvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_aw_first B timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("bresp_aw_first @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // axil_write_w_first — W arrives, then AW (W_WAIT_A path), checks bresp
    // ---------------------------------------------------------------
    task automatic axil_write_w_first(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 1:0] exp_resp
    );
        logic [1:0] got_resp;
        int         timeout;
        // Phase 1: drive W only
        @(negedge aclk);
        s_wdata_tb   = data;
        s_wstrb_tb   = 4'hF;
        s_wvalid_tb  = 1'b1;
        s_awvalid_tb = 1'b0;
        s_bready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_wready && s_wvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_w_first W timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 2: deassert W, drive AW one negedge later
        @(negedge aclk);
        s_wvalid_tb  = 1'b0;
        s_awaddr_tb  = addr;
        s_awvalid_tb = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!(s_awready && s_awvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_w_first AW timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 3: deassert AW, assert bready, wait for B
        @(negedge aclk);
        s_awvalid_tb = 1'b0;
        s_bready_tb  = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_bvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_w_first B timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("bresp_w_first @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // axil_write_bready_delay — simultaneous AW+W, keeps bready=0 for
    //   delay_cycles posedges after bvalid asserts, then completes B.
    //   Checks bvalid held=1 at each delay posedge; checks bresp at end.
    // ---------------------------------------------------------------
    task automatic axil_write_bready_delay(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 1:0] exp_resp,
        input int          delay_cycles
    );
        logic [1:0] got_resp;
        int         timeout;
        int         d;
        // Phase 1: simultaneous AW+W, bready=0
        @(negedge aclk);
        s_awaddr_tb  = addr;
        s_awvalid_tb = 1'b1;
        s_wdata_tb   = data;
        s_wstrb_tb   = 4'hF;
        s_wvalid_tb  = 1'b1;
        s_bready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_awready && s_awvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_bready_delay AW timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid_tb = 1'b0;
        s_wvalid_tb  = 1'b0;
        // bready stays 0 — deliberate backpressure
        // Phase 2: wait for bvalid, then hold bready=0 for delay_cycles,
        //   verifying bvalid stays asserted each cycle
        @(posedge aclk);
        timeout = 0;
        while (!s_bvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_bready_delay bvalid timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        for (d = 0; d < delay_cycles; d++) begin
            check_bit(s_bvalid, 1'b1,
                      $sformatf("bvalid_held[%0d] bready_delay @ 0x%08X", d, addr));
            @(posedge aclk);
        end
        // Phase 3: assert bready, complete B handshake
        @(negedge aclk);
        s_bready_tb = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_bvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_write_bready_delay B final timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("bresp_delayed @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // axil_read_rready_delay — AR handshake normally, then keeps rready=0
    //   for delay_cycles after rvalid appears.
    //   At each delay posedge: checks rvalid held=1, rdata stable, rresp stable.
    //   Asserts rready after delay, captures rdata/rresp, checks rresp.
    // ---------------------------------------------------------------
    task automatic axil_read_rready_delay(
        input  logic [31:0] addr,
        input  logic [ 1:0] exp_resp,
        input  int          delay_cycles,
        output logic [31:0] data
    );
        logic [31:0] rdata_snap;
        logic [ 1:0] rresp_snap;
        logic [ 1:0] got_resp;
        int          timeout;
        int          d;
        // Phase 1: AR handshake normally, rready stays 0
        @(negedge aclk);
        s_araddr_tb  = addr;
        s_arvalid_tb = 1'b1;
        s_rready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_arready && s_arvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_read_rready_delay AR timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        s_arvalid_tb = 1'b0;
        // rready stays 0 — deliberate backpressure
        // Phase 2: wait for rvalid, snapshot stable values, hold rready=0 for delay_cycles
        @(posedge aclk);
        timeout = 0;
        while (!s_rvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_read_rready_delay rvalid timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        rdata_snap = s_rdata;
        rresp_snap = s_rresp;
        for (d = 0; d < delay_cycles; d++) begin
            check_bit(s_rvalid, 1'b1,
                      $sformatf("rvalid_held[%0d] rready_delay @ 0x%08X", d, addr));
            check_eq(s_rdata, rdata_snap,
                     $sformatf("rdata_stable[%0d] rready_delay @ 0x%08X", d, addr));
            check_eq({30'b0, s_rresp}, {30'b0, rresp_snap},
                     $sformatf("rresp_stable[%0d] rready_delay @ 0x%08X", d, addr));
            @(posedge aclk);
        end
        // Phase 3: assert rready, complete R handshake
        @(negedge aclk);
        s_rready_tb = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_rvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_read_rready_delay R final timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        data     = s_rdata;
        got_resp = s_rresp;
        @(negedge aclk);
        s_rready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("rresp_delayed @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // axil_raw_read — no check (used for polling)
    // ---------------------------------------------------------------
    task automatic axil_raw_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        int timeout;
        @(negedge aclk);
        s_araddr_tb  = addr;
        s_arvalid_tb = 1'b1;
        s_rready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_arready && s_arvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_raw_read AR timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        s_arvalid_tb = 1'b0;
        s_rready_tb  = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_rvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_raw_read R timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        data = s_rdata;
        @(negedge aclk);
        s_rready_tb = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axil_read32 — checks rresp
    // ---------------------------------------------------------------
    task automatic axil_read32(
        input  logic [31:0] addr,
        input  logic [ 1:0] exp_resp,
        output logic [31:0] data
    );
        logic [1:0] got_resp;
        int         timeout;
        @(negedge aclk);
        s_araddr_tb  = addr;
        s_arvalid_tb = 1'b1;
        s_rready_tb  = 1'b0;
        @(posedge aclk);
        timeout = 0;
        while (!(s_arready && s_arvalid_tb)) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_read32 AR timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        s_arvalid_tb = 1'b0;
        s_rready_tb  = 1'b1;
        @(posedge aclk);
        timeout = 0;
        while (!s_rvalid) begin
            if (++timeout > 100)
                $fatal(1, "[FATAL] axil_read32 R timeout addr=0x%08X", addr);
            @(posedge aclk);
        end
        data     = s_rdata;
        got_resp = s_rresp;
        @(negedge aclk);
        s_rready_tb = 1'b0;
        check_eq({30'b0, got_resp}, {30'b0, exp_resp},
                 $sformatf("rresp @ 0x%08X", addr));
    endtask

    // ---------------------------------------------------------------
    // poll_done — poll STATUS (0x10) until bit0=1 with timeout
    // ---------------------------------------------------------------
    task automatic poll_done(output logic [31:0] status_out);
        logic [31:0] rd;
        int          timeout;
        timeout = 0;
        do begin
            axil_raw_read(32'h10, rd);
            if (++timeout > 5000)
                $fatal(1, "[FATAL] poll_done timeout (STATUS never set done=1)");
        end while (!rd[0]);
        status_out = rd;
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    logic [31:0] rdata, status;
    logic [31:0] OKAY = 32'h0;
    logic [31:0] SLVERR_32 = 32'h2;

    initial begin
        $dumpfile("../logs/simple_dma_ctrl_tb.vcd");
        $dumpvars(0, simple_dma_ctrl_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // Seed source memory via hierarchical access
        mem_slave.mem[0] = 32'hDEAD_BEEF;   // byte addr 0x00
        mem_slave.mem[1] = 32'hCAFE_F00D;   // byte addr 0x04
        mem_slave.mem[2] = 32'hA5A5_A5A5;   // byte addr 0x08
        mem_slave.mem[3] = 32'h1234_5678;   // byte addr 0x0C
        // Test 4 src: near-end-of-range words
        mem_slave.mem[1021] = 32'hAAAA_1111; // byte addr 0xFF4
        mem_slave.mem[1022] = 32'hBBBB_2222; // byte addr 0xFF8
        mem_slave.mem[1023] = 32'hCCCC_3333; // byte addr 0xFFC
        // Test 5 src: words 128-131
        mem_slave.mem[128] = 32'h1111_AAAA;  // byte addr 0x200
        mem_slave.mem[129] = 32'h2222_BBBB;  // byte addr 0x204
        mem_slave.mem[130] = 32'h3333_CCCC;  // byte addr 0x208
        mem_slave.mem[131] = 32'h4444_DDDD;  // byte addr 0x20C

        // ============================================================
        // Test 1: program and run a 4-word copy (0x00–0x0C → 0x80–0x8C)
        // ============================================================
        $display("[INFO] Test 1: 4-word copy 0x00-0x0C -> 0x80-0x8C");
        axil_write32(32'h04, 32'h0000_0000, 2'b00);  // SRC_ADDR
        axil_write32(32'h08, 32'h0000_0080, 2'b00);  // DST_ADDR
        axil_write32(32'h0C, 32'h0000_0004, 2'b00);  // LENGTH_WORDS
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start

        poll_done(status);
        check_bit(status[0], 1'b1, "T1 STATUS.done");
        check_bit(status[1], 1'b0, "T1 STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd4, "T1 copied_count=4");
        check_eq(mem_slave.mem[32], 32'hDEAD_BEEF, "T1 dst[0] mem[0x80>>2]");
        check_eq(mem_slave.mem[33], 32'hCAFE_F00D, "T1 dst[1] mem[0x84>>2]");
        check_eq(mem_slave.mem[34], 32'hA5A5_A5A5, "T1 dst[2] mem[0x88>>2]");
        check_eq(mem_slave.mem[35], 32'h1234_5678, "T1 dst[3] mem[0x8C>>2]");

        // ============================================================
        // Test 2: single-word copy, re-program registers
        //   src=0x04 (CAFE_F00D) → dst=0xC0
        // ============================================================
        $display("[CHK] t=%0t  phase=test2", $time);
        $display("[INFO] Test 2: single-word copy 0x04 -> 0xC0");
        axil_write32(32'h04, 32'h0000_0004, 2'b00);
        axil_write32(32'h08, 32'h0000_00C0, 2'b00);
        axil_write32(32'h0C, 32'h0000_0001, 2'b00);
        axil_write32(32'h00, 32'h0000_0001, 2'b00);

        poll_done(status);
        check_bit(status[0], 1'b1, "T2 STATUS.done");
        check_bit(status[1], 1'b0, "T2 STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd1, "T2 copied_count=1");
        check_eq(mem_slave.mem[48], 32'hCAFE_F00D, "T2 dst mem[0xC0>>2]");

        // ============================================================
        // Test 3: invalid AXI-lite address returns SLVERR
        // ============================================================
        $display("[CHK] t=%0t  phase=test3", $time);
        $display("[INFO] Test 3: invalid AXI-lite addr 0x20 -> SLVERR");
        axil_write32(32'h20, 32'hDEAD_BEEF, 2'b10);
        axil_read32 (32'h20, 2'b10, rdata);

        // ============================================================
        // Test 4: invalid src mid-copy
        //   src=0xFF4, dst=0x300, len=4
        //   words 0-2: src 0xFF4/8/C (valid), dst 0x300/04/08 (valid)
        //   word  3:   src 0x1000 (OOB) → read SLVERR → abort
        //   copied_count=3, dst[3]=0x30C unchanged
        // ============================================================
        $display("[CHK] t=%0t  phase=test4", $time);
        $display("[INFO] Test 4: OOB src mid-copy src=0xFF4 dst=0x300 len=4");
        axil_write32(32'h04, 32'h0000_0FF4, 2'b00);
        axil_write32(32'h08, 32'h0000_0300, 2'b00);
        axil_write32(32'h0C, 32'h0000_0004, 2'b00);
        axil_write32(32'h00, 32'h0000_0001, 2'b00);

        poll_done(status);
        check_bit(status[0], 1'b1, "T4 STATUS.done");
        check_bit(status[1], 1'b1, "T4 STATUS.error=1");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd3, "T4 copied_count=3");
        check_eq(mem_slave.mem[192], 32'hAAAA_1111, "T4 dst[0] mem[0x300>>2]");
        check_eq(mem_slave.mem[193], 32'hBBBB_2222, "T4 dst[1] mem[0x304>>2]");
        check_eq(mem_slave.mem[194], 32'hCCCC_3333, "T4 dst[2] mem[0x308>>2]");
        check_eq(mem_slave.mem[195], 32'h0,         "T4 dst[3] mem[0x30C>>2] unchanged");

        // ============================================================
        // Test 5: invalid dst mid-copy
        //   src=0x200, dst=0xFF4, len=4
        //   words 0-2: src valid (mem[128-130]), dst 0xFF4/8/C (valid)
        //   word  3:   dst 0x1000 (OOB) → write SLVERR → abort
        //   copied_count=3; canary at mem[256] (0x400) unchanged
        // ============================================================
        $display("[CHK] t=%0t  phase=test5", $time);
        $display("[INFO] Test 5: OOB dst mid-copy src=0x200 dst=0xFF4 len=4");
        mem_slave.mem[256] = 32'hFEED_FACE;   // canary at byte 0x400

        axil_write32(32'h04, 32'h0000_0200, 2'b00);
        axil_write32(32'h08, 32'h0000_0FF4, 2'b00);
        axil_write32(32'h0C, 32'h0000_0004, 2'b00);
        axil_write32(32'h00, 32'h0000_0001, 2'b00);

        poll_done(status);
        check_bit(status[0], 1'b1,  "T5 STATUS.done");
        check_bit(status[1], 1'b1,  "T5 STATUS.error=1");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd3,         "T5 copied_count=3");
        check_eq(mem_slave.mem[1021], 32'h1111_AAAA, "T5 dst[0] mem[0xFF4>>2]");
        check_eq(mem_slave.mem[1022], 32'h2222_BBBB, "T5 dst[1] mem[0xFF8>>2]");
        check_eq(mem_slave.mem[1023], 32'h3333_CCCC, "T5 dst[2] mem[0xFFC>>2]");
        check_eq(mem_slave.mem[256],  32'hFEED_FACE, "T5 canary mem[256] (0x400) unchanged");

        // ============================================================
        // Test 6: mixed write ordering — program registers with AW-first
        //         and W-first, then run a 3-word copy.
        //   SRC_ADDR    : AW-first (W_WAIT_W path)
        //   DST_ADDR    : W-first  (W_WAIT_A path)
        //   LENGTH_WORDS: AW-first (W_WAIT_W path)
        //   CONTROL     : W-first  (W_WAIT_A path) — starts DMA
        //   src 0x10-0x18 (mem[4-6]) → dst 0x500-0x508 (mem[320-322])
        // ============================================================
        $display("[CHK] t=%0t  phase=test6", $time);
        $display("[INFO] Test 6: mixed write ordering, 3-word copy 0x10-0x18 -> 0x500-0x508");

        mem_slave.mem[4] = 32'hBEEF_CAFE;   // byte addr 0x10
        mem_slave.mem[5] = 32'hF00D_DEAD;   // byte addr 0x14
        mem_slave.mem[6] = 32'h5A5A_5A5A;   // byte addr 0x18

        axil_write_aw_first(32'h04, 32'h0000_0010, 2'b00);  // SRC_ADDR via W_WAIT_W
        axil_write_w_first (32'h08, 32'h0000_0500, 2'b00);  // DST_ADDR via W_WAIT_A
        axil_write_aw_first(32'h0C, 32'h0000_0003, 2'b00);  // LENGTH_WORDS via W_WAIT_W
        axil_write_w_first (32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start via W_WAIT_A

        poll_done(status);
        check_bit(status[0], 1'b1, "T6 STATUS.done");
        check_bit(status[1], 1'b0, "T6 STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd3,         "T6 copied_count=3");
        check_eq(mem_slave.mem[320], 32'hBEEF_CAFE, "T6 dst[0] mem[0x500>>2]");
        check_eq(mem_slave.mem[321], 32'hF00D_DEAD, "T6 dst[1] mem[0x504>>2]");
        check_eq(mem_slave.mem[322], 32'h5A5A_5A5A, "T6 dst[2] mem[0x508>>2]");

        // ============================================================
        // Test 7: invalid AXI-lite address via AW-first and W-first
        //   Both must return SLVERR and leave all registers unchanged.
        // ============================================================
        $display("[CHK] t=%0t  phase=test7", $time);
        $display("[INFO] Test 7: invalid addr SLVERR via AW-first (0x40) and W-first (0x50)");
        axil_write_aw_first(32'h40, 32'hDEAD_BEEF, 2'b10);
        axil_write_w_first (32'h50, 32'hCAFE_F00D, 2'b10);

        // ============================================================
        // Test 8: B-channel backpressure — program SRC/DST/LENGTH with
        //   3-cycle delayed bready; verify bvalid held each delay cycle;
        //   invalid addr with delayed bready returns SLVERR;
        //   then start DMA and verify 2-word copy result.
        //   src 0x1C-0x20 (mem[7-8]) → dst 0x600-0x604 (mem[384-385])
        // ============================================================
        $display("[CHK] t=%0t  phase=test8", $time);
        $display("[INFO] Test 8: B-channel backpressure (3-cycle delay), 2-word copy 0x1C-0x20 -> 0x600-0x604");

        mem_slave.mem[7] = 32'h6B6B_6B6B;   // byte addr 0x1C
        mem_slave.mem[8] = 32'h9C9C_9C9C;   // byte addr 0x20

        axil_write_bready_delay(32'h04, 32'h0000_001C, 2'b00, 3);  // SRC_ADDR
        axil_write_bready_delay(32'h08, 32'h0000_0600, 2'b00, 3);  // DST_ADDR
        axil_write_bready_delay(32'h0C, 32'h0000_0002, 2'b00, 3);  // LENGTH_WORDS
        axil_write_bready_delay(32'h60, 32'hDEAD_BEEF, 2'b10, 3);  // invalid addr → SLVERR
        axil_write32           (32'h00, 32'h0000_0001, 2'b00);       // CONTROL.start

        poll_done(status);
        check_bit(status[0], 1'b1, "T8 STATUS.done");
        check_bit(status[1], 1'b0, "T8 STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd2,         "T8 copied_count=2");
        check_eq(mem_slave.mem[384], 32'h6B6B_6B6B, "T8 dst[0] mem[0x600>>2]");
        check_eq(mem_slave.mem[385], 32'h9C9C_9C9C, "T8 dst[1] mem[0x604>>2]");

        // ============================================================
        // Test 9: R-channel backpressure — read all six register addresses
        //   with a 3-cycle rready delay; verify rvalid/rdata/rresp stable
        //   at each delay cycle; invalid address returns SLVERR with rdata=0.
        //
        //   Register state going into T9 (set by T8):
        //     SRC_ADDR     = 0x0000_001C
        //     DST_ADDR     = 0x0000_0600
        //     LENGTH_WORDS = 0x0000_0002
        //     STATUS       = 0x0000_0001  (done=1, error=0)
        //     COPIED_COUNT = 0x0000_0002
        // ============================================================
        $display("[CHK] t=%0t  phase=test9", $time);
        $display("[INFO] Test 9: R-channel backpressure (3-cycle delay) on all register reads");

        begin
            logic [31:0] rd9;

            axil_read_rready_delay(32'h04, 2'b00, 3, rd9);
            check_eq(rd9, 32'h0000_001C, "T9 SRC_ADDR readback");

            axil_read_rready_delay(32'h08, 2'b00, 3, rd9);
            check_eq(rd9, 32'h0000_0600, "T9 DST_ADDR readback");

            axil_read_rready_delay(32'h0C, 2'b00, 3, rd9);
            check_eq(rd9, 32'h0000_0002, "T9 LENGTH_WORDS readback");

            axil_read_rready_delay(32'h10, 2'b00, 3, rd9);
            check_eq(rd9, 32'h0000_0001, "T9 STATUS (done=1, error=0)");

            axil_read_rready_delay(32'h14, 2'b00, 3, rd9);
            check_eq(rd9, 32'h0000_0002, "T9 COPIED_COUNT=2");

            axil_read_rready_delay(32'h30, 2'b10, 3, rd9);
            check_eq(rd9, 32'h0000_0000, "T9 invalid addr rdata=0");
        end

        // ============================================================
        // Test 10: busy-state register reads
        //   An 8-word copy gives ~40 clock cycles of DMA run time.
        //   Three immediate AXI-lite reads after CONTROL.start verify:
        //     CONTROL reads busy=1, STATUS.done=0/error=0, COPIED_COUNT
        //     remains at the previous run's stale value (2 from T8) and
        //     is within [0, LENGTH_WORDS].
        //   src 0x40-0x5C (mem[16-23]) → dst 0x700-0x71C (mem[448-455])
        // ============================================================
        $display("[CHK] t=%0t  phase=test10", $time);
        $display("[INFO] Test 10: busy-state reads — CONTROL/STATUS/COPIED_COUNT while DMA running");

        mem_slave.mem[16] = 32'hA0A0_A0A0;   // byte addr 0x40
        mem_slave.mem[17] = 32'hA1A1_A1A1;   // byte addr 0x44
        mem_slave.mem[18] = 32'hA2A2_A2A2;   // byte addr 0x48
        mem_slave.mem[19] = 32'hA3A3_A3A3;   // byte addr 0x4C
        mem_slave.mem[20] = 32'hA4A4_A4A4;   // byte addr 0x50
        mem_slave.mem[21] = 32'hA5A5_A5A5;   // byte addr 0x54
        mem_slave.mem[22] = 32'hA6A6_A6A6;   // byte addr 0x58
        mem_slave.mem[23] = 32'hA7A7_A7A7;   // byte addr 0x5C

        axil_write32(32'h04, 32'h0000_0040, 2'b00);  // SRC_ADDR=0x40
        axil_write32(32'h08, 32'h0000_0700, 2'b00);  // DST_ADDR=0x700
        axil_write32(32'h0C, 32'h0000_0008, 2'b00);  // LENGTH_WORDS=8
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start

        // Immediately read registers while DMA is in flight
        axil_read32(32'h00, 2'b00, rdata);
        check_bit(rdata[0], 1'b1, "T10 CONTROL busy=1");

        axil_read32(32'h10, 2'b00, rdata);
        check_bit(rdata[0], 1'b0, "T10 STATUS.done=0 while busy");
        check_bit(rdata[1], 1'b0, "T10 STATUS.error=0 while busy");

        // COPIED_COUNT holds the stale count from T8 (2 words) during this run;
        // verify it is within [0, LENGTH_WORDS=8].
        axil_read32(32'h14, 2'b00, rdata);
        check_le32(rdata, 32'h0000_0008, "T10 COPIED_COUNT <= LENGTH_WORDS while busy");

        poll_done(status);
        check_bit(status[0], 1'b1, "T10 STATUS.done=1 after completion");
        check_bit(status[1], 1'b0, "T10 STATUS.error=0 after completion");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd8,          "T10 COPIED_COUNT=8");
        check_eq(mem_slave.mem[448], 32'hA0A0_A0A0, "T10 dst[0] mem[0x700>>2]");
        check_eq(mem_slave.mem[449], 32'hA1A1_A1A1, "T10 dst[1] mem[0x704>>2]");
        check_eq(mem_slave.mem[450], 32'hA2A2_A2A2, "T10 dst[2] mem[0x708>>2]");
        check_eq(mem_slave.mem[451], 32'hA3A3_A3A3, "T10 dst[3] mem[0x70C>>2]");
        check_eq(mem_slave.mem[452], 32'hA4A4_A4A4, "T10 dst[4] mem[0x710>>2]");
        check_eq(mem_slave.mem[453], 32'hA5A5_A5A5, "T10 dst[5] mem[0x714>>2]");
        check_eq(mem_slave.mem[454], 32'hA6A6_A6A6, "T10 dst[6] mem[0x718>>2]");
        check_eq(mem_slave.mem[455], 32'hA7A7_A7A7, "T10 dst[7] mem[0x71C>>2]");

        // ============================================================
        // Test 11: busy re-trigger guard
        //   Start an 8-word copy, then — while the DMA is still in
        //   flight — write corrupted SRC/DST/LENGTH and attempt a
        //   second CONTROL.start.  The second start must be absorbed
        //   with OKAY but must not restart, corrupt, or truncate the
        //   active transfer.
        //   src 0x800-0x81C (mem[512-519]) → dst 0xA00-0xA1C (mem[640-647])
        //   canary_before mem[639] (0x9FC), canary_after mem[648] (0xA20)
        // ============================================================
        $display("[CHK] t=%0t  phase=test11", $time);
        $display("[INFO] Test 11: busy re-trigger guard — second start ignored, transfer unaffected");

        mem_slave.mem[512] = 32'hB0B0_B0B0;   // byte addr 0x800
        mem_slave.mem[513] = 32'hB1B1_B1B1;   // byte addr 0x804
        mem_slave.mem[514] = 32'hB2B2_B2B2;   // byte addr 0x808
        mem_slave.mem[515] = 32'hB3B3_B3B3;   // byte addr 0x80C
        mem_slave.mem[516] = 32'hB4B4_B4B4;   // byte addr 0x810
        mem_slave.mem[517] = 32'hB5B5_B5B5;   // byte addr 0x814
        mem_slave.mem[518] = 32'hB6B6_B6B6;   // byte addr 0x818
        mem_slave.mem[519] = 32'hB7B7_B7B7;   // byte addr 0x81C
        mem_slave.mem[639] = 32'hC0DE_C0DE;   // canary before dst (0x9FC)
        mem_slave.mem[648] = 32'hDECA_F0CA;   // canary after dst  (0xA20)

        axil_write32(32'h04, 32'h0000_0800, 2'b00);  // SRC_ADDR=0x800
        axil_write32(32'h08, 32'h0000_0A00, 2'b00);  // DST_ADDR=0xA00
        axil_write32(32'h0C, 32'h0000_0008, 2'b00);  // LENGTH_WORDS=8
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start (first — DMA begins)

        // Confirm busy before the second attempt
        axil_read32(32'h00, 2'b00, rdata);
        check_bit(rdata[0], 1'b1, "T11 CONTROL busy=1 before retrigger");

        // While busy: overwrite SRC/DST/LENGTH with corrupted values.
        // These writes are accepted (OKAY) but the running DMA uses its
        // latched src_lat/dst_lat/len_lat — register changes have no effect.
        axil_write32(32'h04, 32'hDEAD_0000, 2'b00);  // SRC_ADDR corrupted
        axil_write32(32'h08, 32'hBEEF_0000, 2'b00);  // DST_ADDR corrupted
        axil_write32(32'h0C, 32'h0000_00FF, 2'b00);  // LENGTH_WORDS corrupted

        // Second CONTROL.start while busy: AXI-lite returns OKAY but
        // do_reg_write sees busy_r=1 so dma_start_r is never pulsed.
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start (second — must be no-op)

        // Transfer must still complete normally using the original parameters
        poll_done(status);
        check_bit(status[0], 1'b1, "T11 STATUS.done=1 after completion");
        check_bit(status[1], 1'b0, "T11 STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd8,              "T11 COPIED_COUNT=8 (original length)");
        check_eq(mem_slave.mem[640], 32'hB0B0_B0B0, "T11 dst[0] mem[0xA00>>2]");
        check_eq(mem_slave.mem[641], 32'hB1B1_B1B1, "T11 dst[1] mem[0xA04>>2]");
        check_eq(mem_slave.mem[642], 32'hB2B2_B2B2, "T11 dst[2] mem[0xA08>>2]");
        check_eq(mem_slave.mem[643], 32'hB3B3_B3B3, "T11 dst[3] mem[0xA0C>>2]");
        check_eq(mem_slave.mem[644], 32'hB4B4_B4B4, "T11 dst[4] mem[0xA10>>2]");
        check_eq(mem_slave.mem[645], 32'hB5B5_B5B5, "T11 dst[5] mem[0xA14>>2]");
        check_eq(mem_slave.mem[646], 32'hB6B6_B6B6, "T11 dst[6] mem[0xA18>>2]");
        check_eq(mem_slave.mem[647], 32'hB7B7_B7B7, "T11 dst[7] mem[0xA1C>>2]");
        check_eq(mem_slave.mem[639], 32'hC0DE_C0DE, "T11 canary_before mem[0x9FC>>2] unchanged");
        check_eq(mem_slave.mem[648], 32'hDECA_F0CA, "T11 canary_after  mem[0xA20>>2] unchanged");

        // ============================================================
        // Test 12a: zero-length DMA transfer
        //   LENGTH_WORDS=0 → DMA core goes IDLE→DONE in ~3 cycles with
        //   no AXI4 transactions; STATUS.done=1, error=0, count=0.
        //   src 0xB00 (mem[704]) — never written, stays 0.
        //   dst 0xB80 (mem[736]) — canary words must be unchanged.
        // ============================================================
        $display("[CHK] t=%0t  phase=test12a", $time);
        $display("[INFO] Test 12a: zero-length DMA transfer — no reads/writes, done=1 count=0");

        mem_slave.mem[736] = 32'hFACE_B00C;   // canary: would be dst[0] if len>0 (0xB80)
        mem_slave.mem[737] = 32'hD0D0_D0D0;   // canary: would be dst[1] if len>0 (0xB84)

        axil_write32(32'h04, 32'h0000_0B00, 2'b00);  // SRC_ADDR=0xB00
        axil_write32(32'h08, 32'h0000_0B80, 2'b00);  // DST_ADDR=0xB80
        axil_write32(32'h0C, 32'h0000_0000, 2'b00);  // LENGTH_WORDS=0
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start

        poll_done(status);
        check_bit(status[0], 1'b1, "T12a STATUS.done=1");
        check_bit(status[1], 1'b0, "T12a STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd0,              "T12a COPIED_COUNT=0");
        check_eq(mem_slave.mem[704], 32'h0000_0000, "T12a src mem[0xB00>>2] unchanged");
        check_eq(mem_slave.mem[736], 32'hFACE_B00C, "T12a canary dst[0] mem[0xB80>>2] unchanged");
        check_eq(mem_slave.mem[737], 32'hD0D0_D0D0, "T12a canary dst[1] mem[0xB84>>2] unchanged");

        // ============================================================
        // Test 12b: normal restart after zero-length transfer
        //   Verifies busy_r is cleared after a zero-length done and
        //   a fresh DMA start is accepted normally.
        //   src 0xB00-0xB08 (mem[704-706]) → dst 0xC00-0xC08 (mem[768-770])
        // ============================================================
        $display("[CHK] t=%0t  phase=test12b", $time);
        $display("[INFO] Test 12b: 3-word restart after zero-length — normal transfer completes");

        mem_slave.mem[704] = 32'hC0C0_C0C0;   // byte addr 0xB00
        mem_slave.mem[705] = 32'hC1C1_C1C1;   // byte addr 0xB04
        mem_slave.mem[706] = 32'hC2C2_C2C2;   // byte addr 0xB08

        axil_write32(32'h04, 32'h0000_0B00, 2'b00);  // SRC_ADDR=0xB00
        axil_write32(32'h08, 32'h0000_0C00, 2'b00);  // DST_ADDR=0xC00
        axil_write32(32'h0C, 32'h0000_0003, 2'b00);  // LENGTH_WORDS=3
        axil_write32(32'h00, 32'h0000_0001, 2'b00);  // CONTROL.start

        poll_done(status);
        check_bit(status[0], 1'b1, "T12b STATUS.done=1");
        check_bit(status[1], 1'b0, "T12b STATUS.error=0");
        axil_raw_read(32'h14, rdata);
        check_eq16(rdata[15:0], 16'd3,              "T12b COPIED_COUNT=3");
        check_eq(mem_slave.mem[768], 32'hC0C0_C0C0, "T12b dst[0] mem[0xC00>>2]");
        check_eq(mem_slave.mem[769], 32'hC1C1_C1C1, "T12b dst[1] mem[0xC04>>2]");
        check_eq(mem_slave.mem[770], 32'hC2C2_C2C2, "T12b dst[2] mem[0xC08>>2]");

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] simple_dma_ctrl_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] simple_dma_ctrl_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
