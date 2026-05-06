`timescale 1ns/1ps

module simple_dma_add_ctrl_tb;

    // Clock / reset
    logic aclk = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;

    // AXI-lite slave port (TB → DUT control)
    logic [31:0] s_awaddr = '0; logic s_awvalid = '0; logic s_awready;
    logic [31:0] s_wdata  = '0; logic [3:0] s_wstrb = '0;
    logic        s_wvalid = '0; logic s_wready;
    logic [1:0]  s_bresp;       logic s_bvalid; logic s_bready = '0;
    logic [31:0] s_araddr = '0; logic s_arvalid = '0; logic s_arready;
    logic [31:0] s_rdata;       logic [1:0] s_rresp;
    logic        s_rvalid;      logic s_rready = '0;

    // AXI4 master port (DUT memory → slave)
    wire [31:0] m_araddr; wire m_arvalid; wire m_arready;
    wire [31:0] m_rdata;  wire [1:0] m_rresp; wire m_rlast;
    wire        m_rvalid; wire m_rready;
    wire [31:0] m_awaddr; wire m_awvalid; wire m_awready;
    wire [31:0] m_wdata;  wire [3:0] m_wstrb_dut; wire m_wlast;
    wire        m_wvalid; wire m_wready;
    wire [1:0]  m_bresp;  wire m_bvalid; wire m_bready;

    simple_dma_add_ctrl dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata(s_wdata),   .s_wstrb(s_wstrb),     .s_wvalid(s_wvalid),  .s_wready(s_wready),
        .s_bresp(s_bresp),   .s_bvalid(s_bvalid),   .s_bready(s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata(s_rdata),   .s_rresp(s_rresp),     .s_rvalid(s_rvalid),  .s_rready(s_rready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata),   .m_rresp(m_rresp),     .m_rlast(m_rlast),
        .m_rvalid(m_rvalid), .m_rready(m_rready),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata),   .m_wstrb(m_wstrb_dut), .m_wlast(m_wlast),
        .m_wvalid(m_wvalid), .m_wready(m_wready),
        .m_bresp(m_bresp),   .m_bvalid(m_bvalid),   .m_bready(m_bready)
    );

    axi_mem_model #(.MEM_DEPTH(1024), .MEM_BASE(32'h0)) slave (
        .aclk(aclk), .aresetn(aresetn),
        .araddr(m_araddr), .arvalid(m_arvalid), .arready(m_arready),
        .rdata(m_rdata),   .rresp(m_rresp),     .rlast(m_rlast),
        .rvalid(m_rvalid), .rready(m_rready),
        .awaddr(m_awaddr), .awvalid(m_awvalid), .awready(m_awready),
        .wdata(m_wdata),   .wstrb(m_wstrb_dut), .wlast(m_wlast),
        .wvalid(m_wvalid), .wready(m_wready),
        .bresp(m_bresp),   .bvalid(m_bvalid),   .bready(m_bready)
    );

    int pass_count = 0;
    int fail_count = 0;

    // ------------------------------------------------------------------
    // Check helpers
    // ------------------------------------------------------------------
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

    task automatic check_resp(input logic [1:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-52s  resp=2'b%02b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-52s  got=2'b%02b  exp=2'b%02b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_resp failed: %s", label);
        end
    endtask

    // ------------------------------------------------------------------
    // AXI-lite write (simultaneous AW+W)
    // ------------------------------------------------------------------
    task automatic axil_write32(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        output logic [1:0]  got_resp
    );
        int timeout;
        @(negedge aclk);
        s_awaddr  = addr; s_awvalid = 1'b1;
        s_wdata   = data; s_wstrb   = 4'hF; s_wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!(s_awready && s_wready)) begin
            if (++timeout > 200) $fatal(1, "[FATAL] axil_write32 aw/w ready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid = 1'b0; s_wvalid = 1'b0; s_bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_bvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] axil_write32 bvalid timeout");
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // AXI-lite write — AW-before-W (W_WAIT_W path)
    // ------------------------------------------------------------------
    task automatic axil_write_aw_first(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        output logic [1:0]  got_resp
    );
        int timeout;
        // Phase 1: drive AW only
        @(negedge aclk);
        s_awaddr = addr; s_awvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_awready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] aw_first: awready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid = 1'b0;
        // Phase 2: drive W
        s_wdata = data; s_wstrb = 4'hF; s_wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_wready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] aw_first: wready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_wvalid = 1'b0; s_bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_bvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] aw_first: bvalid timeout");
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // AXI-lite write — W-before-AW (W_WAIT_A path)
    // ------------------------------------------------------------------
    task automatic axil_write_w_first(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        output logic [1:0]  got_resp
    );
        int timeout;
        // Phase 1: drive W only
        @(negedge aclk);
        s_wdata = data; s_wstrb = 4'hF; s_wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_wready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] w_first: wready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_wvalid = 1'b0;
        // Phase 2: drive AW
        s_awaddr = addr; s_awvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_awready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] w_first: awready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid = 1'b0; s_bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_bvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] w_first: bvalid timeout");
            @(posedge aclk);
        end
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // AXI-lite write — simultaneous AW+W with delayed bready
    //   Holds bready=0 for delay_cycles after bvalid appears, verifying
    //   bvalid stays asserted at each cycle before acceptance.
    // ------------------------------------------------------------------
    task automatic axil_write_bready_delay(
        input  logic [31:0] addr,
        input  logic [31:0] data,
        input  int          delay_cycles,
        output logic [1:0]  got_resp
    );
        int timeout;
        @(negedge aclk);
        s_awaddr = addr; s_awvalid = 1'b1;
        s_wdata  = data; s_wstrb   = 4'hF; s_wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!(s_awready && s_wready)) begin
            if (++timeout > 200) $fatal(1, "[FATAL] bready_delay: aw/w ready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_awvalid = 1'b0; s_wvalid = 1'b0;
        // bready intentionally stays 0; wait for bvalid
        timeout = 0;
        @(posedge aclk);
        while (!s_bvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] bready_delay: bvalid timeout");
            @(posedge aclk);
        end
        // bvalid=1; verify it is held for delay_cycles posedges while bready=0
        for (int d = 0; d < delay_cycles; d++) begin
            check_bit(s_bvalid, 1'b1, $sformatf("bready_delay: bvalid held cycle %0d", d+1));
            @(negedge aclk);
            @(posedge aclk);
        end
        // Final check then accept
        check_bit(s_bvalid, 1'b1, "bready_delay: bvalid before accept");
        got_resp = s_bresp;
        @(negedge aclk);
        s_bready = 1'b1;
        @(posedge aclk);   // DUT sees bready → clears bvalid
        @(negedge aclk);
        s_bready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // AXI-lite read
    // ------------------------------------------------------------------
    task automatic axil_read32(
        input  logic [31:0] addr,
        output logic [31:0] rdata_out,
        output logic [1:0]  got_resp
    );
        int timeout;
        @(negedge aclk);
        s_araddr = addr; s_arvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_arready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] axil_read32 arready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_arvalid = 1'b0; s_rready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_rvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] axil_read32 rvalid timeout");
            @(posedge aclk);
        end
        rdata_out = s_rdata;
        got_resp  = s_rresp;
        @(negedge aclk);
        s_rready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // AXI-lite read with deliberately delayed rready
    //   Completes AR handshake, waits for rvalid, holds rready=0 for
    //   delay_cycles, verifies rvalid/rdata/rresp stable each cycle,
    //   then accepts the transaction.
    // ------------------------------------------------------------------
    task automatic axil_read_rready_delay(
        input  logic [31:0] addr,
        input  logic [1:0]  exp_resp,
        input  int          delay_cycles,
        output logic [31:0] data_out
    );
        logic [31:0] snap_rdata;
        logic [1:0]  snap_rresp;
        int timeout;
        // AR handshake
        @(negedge aclk);
        s_araddr = addr; s_arvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!s_arready) begin
            if (++timeout > 200) $fatal(1, "[FATAL] rready_delay: arready timeout");
            @(posedge aclk);
        end
        @(negedge aclk);
        s_arvalid = 1'b0;
        // rready intentionally stays 0; wait for rvalid
        timeout = 0;
        @(posedge aclk);
        while (!s_rvalid) begin
            if (++timeout > 200) $fatal(1, "[FATAL] rready_delay: rvalid timeout");
            @(posedge aclk);
        end
        // Capture stable rdata/rresp at first rvalid posedge
        snap_rdata = s_rdata;
        snap_rresp = s_rresp;
        // Verify rvalid/rdata/rresp all held stable for delay_cycles while rready=0
        for (int d = 0; d < delay_cycles; d++) begin
            check_bit (s_rvalid, 1'b1,       $sformatf("rready_delay: rvalid held cycle %0d", d+1));
            check_eq  (s_rdata,  snap_rdata,  $sformatf("rready_delay: rdata  stable cycle %0d", d+1));
            check_resp(s_rresp,  snap_rresp,  $sformatf("rready_delay: rresp  stable cycle %0d", d+1));
            @(negedge aclk);
            @(posedge aclk);
        end
        // Final pre-accept checks
        check_bit (s_rvalid, 1'b1,    "rready_delay: rvalid before accept");
        data_out = s_rdata;
        check_resp(s_rresp, exp_resp, "rready_delay: rresp  final");
        // Accept the transaction
        @(negedge aclk);
        s_rready = 1'b1;
        @(posedge aclk);   // DUT sees rready → clears rvalid
        @(negedge aclk);
        s_rready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // Poll STATUS.done without counting (raw bus transactions)
    // ------------------------------------------------------------------
    task automatic poll_done(input int timeout_cycles);
        logic [31:0] st; logic [1:0] r; int cnt;
        cnt = 0;
        do begin
            axil_read32(32'h14, st, r);
            if (st[0]) break;
            if (++cnt > timeout_cycles)
                $fatal(1, "[FATAL] poll_done timeout after %0d polls", timeout_cycles);
        end while (1);
    endtask

    // ------------------------------------------------------------------
    // start_transfer: program and kick off one DMA add transfer
    // ------------------------------------------------------------------
    task automatic start_transfer(
        input logic [31:0] src, dst, add_val,
        input logic [15:0] len
    );
        logic [1:0] r;
        axil_write32(32'h04, src,          r); check_resp(r, 2'b00, "start: SRC write");
        axil_write32(32'h08, dst,          r); check_resp(r, 2'b00, "start: DST write");
        axil_write32(32'h0C, {16'h0, len}, r); check_resp(r, 2'b00, "start: LEN write");
        axil_write32(32'h10, add_val,      r); check_resp(r, 2'b00, "start: ADD write");
        axil_write32(32'h00, 32'h1,        r); check_resp(r, 2'b00, "start: CTRL write");
    endtask

    logic [31:0] rval;
    logic [1:0]  resp;

    initial begin
        $dumpfile("../logs/simple_dma_add_ctrl_tb.vcd");
        $dumpvars(0, simple_dma_add_ctrl_tb);

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);

        // Seed source memory
        slave.mem[0]    = 32'h0000_0010;   // T2 src byte 0x000
        slave.mem[4]    = 32'h1000_0001;   // T3 src[0] byte 0x010
        slave.mem[5]    = 32'h2000_0002;
        slave.mem[6]    = 32'h3000_0003;
        slave.mem[7]    = 32'h4000_0004;
        slave.mem[8]    = 32'hAAAA_0001;   // T4 src[0] byte 0x020
        slave.mem[9]    = 32'hBBBB_0002;
        slave.mem[10]   = 32'hCCCC_0003;
        slave.mem[11]   = 32'hDDDD_0004;
        slave.mem[12]   = 32'hFFFF_FFFF;   // T5 overflow src byte 0x030
        slave.mem[80]   = 32'hFACE_B00C;   // T6 dst canary byte 0x140
        slave.mem[1022] = 32'hBBBB_2222;   // T7 src[0] byte 0xFF8
        slave.mem[1023] = 32'hCCCC_3333;   // T7 src[1] byte 0xFFC
        slave.mem[128]  = 32'h1111_AAAA;   // T8 src[0] byte 0x200
        slave.mem[129]  = 32'h2222_BBBB;
        slave.mem[130]  = 32'h3333_CCCC;
        slave.mem[200]  = 32'hA0A0_A0A0;   // T9 src[0] byte 0x320
        slave.mem[201]  = 32'hA1A1_A1A1;
        slave.mem[202]  = 32'hA2A2_A2A2;
        slave.mem[203]  = 32'hA3A3_A3A3;
        slave.mem[204]  = 32'hA4A4_A4A4;
        slave.mem[205]  = 32'hA5A5_A5A5;
        slave.mem[206]  = 32'hA6A6_A6A6;
        slave.mem[207]  = 32'hA7A7_A7A7;
        slave.mem[300]  = 32'h1234_5678;   // T10 recovery src[0] byte 0x4B0
        slave.mem[301]  = 32'h8765_4321;
        slave.mem[450]  = 32'hDEAD_0001;   // T11 src[0] byte 0x708
        slave.mem[451]  = 32'hDEAD_0002;   // T11 src[1] byte 0x70C
        slave.mem[452]  = 32'hDEAD_0003;   // T11 src[2] byte 0x710
        slave.mem[516]  = 32'h1122_3344;   // T12 src[0] byte 0x810
        slave.mem[517]  = 32'h5566_7788;   // T12 src[1] byte 0x814
        slave.mem[520]  = 32'h0A0B_0C0D;   // T13 src[0] byte 0x820
        slave.mem[521]  = 32'h1A1B_1C1D;   // T13 src[1] byte 0x824
        slave.mem[522]  = 32'h2A2B_2C2D;   // T13 src[2] byte 0x828
        slave.mem[523]  = 32'h3A3B_3C3D;   // T13 src[3] byte 0x82C
        slave.mem[639]  = 32'hBEEF_CAFE;   // T14 canary before dst byte 0x9FC
        slave.mem[704]  = 32'hF0F0_0001;   // T14a src[0]  byte 0xB00
        slave.mem[705]  = 32'hF0F0_0002;   // T14a src[1]  byte 0xB04
        slave.mem[706]  = 32'hF0F0_0003;
        slave.mem[707]  = 32'hF0F0_0004;
        slave.mem[708]  = 32'hF0F0_0005;
        slave.mem[709]  = 32'hF0F0_0006;
        slave.mem[710]  = 32'hF0F0_0007;
        slave.mem[711]  = 32'hF0F0_0008;
        slave.mem[712]  = 32'hF0F0_0009;
        slave.mem[713]  = 32'hF0F0_000A;
        slave.mem[714]  = 32'hF0F0_000B;
        slave.mem[715]  = 32'hF0F0_000C;
        slave.mem[716]  = 32'hF0F0_000D;
        slave.mem[717]  = 32'hF0F0_000E;
        slave.mem[718]  = 32'hF0F0_000F;
        slave.mem[719]  = 32'hF0F0_0010;   // T14a src[15] byte 0xB3C
        slave.mem[656]  = 32'hDECA_FBAD;   // T14 canary after dst end byte 0xA40
        slave.mem[768]  = 32'h0001_1001;   // T14b src[0] byte 0xC00
        slave.mem[769]  = 32'h0002_2002;   // T14b src[1] byte 0xC04
        slave.mem[770]  = 32'h0003_3003;   // T14b src[2] byte 0xC08
        slave.mem[771]  = 32'h0004_4004;   // T14b src[3] byte 0xC0C
        // T15 repeated restart: src mem[836..847] / dst mem[850..861]
        slave.mem[836]  = 32'hAAAA_0001;   // T15 run1 src[0] byte 0xD10
        slave.mem[837]  = 32'hBBBB_0001;   // T15 run2 src[0] byte 0xD14
        slave.mem[838]  = 32'hBBBB_0002;   // T15 run2 src[1] byte 0xD18
        slave.mem[839]  = 32'hCCCC_0001;   // T15 run3 src[0] byte 0xD1C
        slave.mem[840]  = 32'hCCCC_0002;   // T15 run3 src[1] byte 0xD20
        slave.mem[841]  = 32'hCCCC_0003;   // T15 run3 src[2] byte 0xD24
        slave.mem[842]  = 32'hDDDD_0001;   // T15 run4 src[0] byte 0xD28
        slave.mem[843]  = 32'hDDDD_0002;   // T15 run4 src[1] byte 0xD2C
        slave.mem[844]  = 32'hEEEE_0001;   // T15 run5 src[0] byte 0xD30
        slave.mem[845]  = 32'hEEEE_0002;   // T15 run5 src[1] byte 0xD34
        slave.mem[846]  = 32'hEEEE_0003;   // T15 run5 src[2] byte 0xD38
        slave.mem[847]  = 32'hEEEE_0004;   // T15 run5 src[3] byte 0xD3C
        slave.mem[862]  = 32'hA1B2_C3D4;   // T15 canary after last dst byte 0xD78
        // T16 random smoke: src window mem[864..871] / dst window mem[872..879] (seeded per iter)
        slave.mem[880]  = 32'hCAFE_BABE;   // T16 canary after dst window byte 0xDC0
        // T17 busy config write policy
        slave.mem[900]  = 32'hA0A0_0001;   // T17 orig src[0]  byte 0xE10
        slave.mem[901]  = 32'hA0A0_0002;
        slave.mem[902]  = 32'hA0A0_0003;
        slave.mem[903]  = 32'hA0A0_0004;
        slave.mem[904]  = 32'hA0A0_0005;
        slave.mem[905]  = 32'hA0A0_0006;
        slave.mem[906]  = 32'hA0A0_0007;
        slave.mem[907]  = 32'hA0A0_0008;
        slave.mem[908]  = 32'hA0A0_0009;
        slave.mem[909]  = 32'hA0A0_000A;
        slave.mem[910]  = 32'hA0A0_000B;
        slave.mem[911]  = 32'hA0A0_000C;
        slave.mem[912]  = 32'hA0A0_000D;
        slave.mem[913]  = 32'hA0A0_000E;
        slave.mem[914]  = 32'hA0A0_000F;
        slave.mem[915]  = 32'hA0A0_0010;   // T17 orig src[15] byte 0xE3C
        slave.mem[920]  = 32'hB0B0_0001;   // T17 new  src[0]  byte 0xE60
        slave.mem[921]  = 32'hB0B0_0002;
        slave.mem[922]  = 32'hB0B0_0003;
        slave.mem[923]  = 32'hB0B0_0004;
        slave.mem[924]  = 32'hB0B0_0005;   // T17 new  src[4]  byte 0xE70
        slave.mem[959]  = 32'hB1B1_B1B1;   // T17 canary before orig dst byte 0xEFC
        slave.mem[976]  = 32'hB2B2_B2B2;   // T17 canary after  orig dst byte 0xF40
        slave.mem[979]  = 32'hB3B3_B3B3;   // T17 canary before new  dst byte 0xF4C
        slave.mem[985]  = 32'hB4B4_B4B4;   // T17 canary after  new  dst byte 0xF64

        // T18 reset during transfer
        slave.mem[986]  = 32'hC8C8_0001;   // T18 orig src[0]  byte 0xF68
        slave.mem[987]  = 32'hC8C8_0002;
        slave.mem[988]  = 32'hC8C8_0003;
        slave.mem[989]  = 32'hC8C8_0004;
        slave.mem[990]  = 32'hC8C8_0005;
        slave.mem[991]  = 32'hC8C8_0006;
        slave.mem[992]  = 32'hC8C8_0007;
        slave.mem[993]  = 32'hC8C8_0008;   // T18 orig src[7]  byte 0xF84
        slave.mem[994]  = 32'hF8F8_AABB;   // T18 canary before orig dst  byte 0xF88
        slave.mem[995]  = 32'hDEAD_1111;   // T18 orig dst sentinel[0]   byte 0xF8C
        slave.mem[996]  = 32'hDEAD_1111;
        slave.mem[997]  = 32'hDEAD_1111;
        slave.mem[998]  = 32'hDEAD_1111;
        slave.mem[999]  = 32'hDEAD_1111;
        slave.mem[1000] = 32'hDEAD_1111;
        slave.mem[1001] = 32'hDEAD_1111;
        slave.mem[1002] = 32'hDEAD_1111;   // T18 orig dst sentinel[7]   byte 0xFA8
        slave.mem[1003] = 32'hF8F8_CCDD;   // T18 canary after  orig dst  byte 0xFAC
        slave.mem[1004] = 32'hD9D9_0001;   // T18 new  src[0]  byte 0xFB0
        slave.mem[1005] = 32'hD9D9_0002;
        slave.mem[1006] = 32'hD9D9_0003;   // T18 new  src[2]  byte 0xFB8
        slave.mem[1007] = 32'hF8F8_EEFF;   // T18 canary before new dst   byte 0xFBC
        // slave.mem[1008..1010] new dst — start as 0, no init needed
        slave.mem[1011] = 32'hF8F8_0011;   // T18 canary after  new dst   byte 0xFCC

        // ============================================================
        // Test 1: Register R/W sanity + invalid address SLVERR
        // ============================================================
        $display("[INFO] Test 1: register R/W sanity + SLVERR");
        axil_write32(32'h04, 32'hDEAD_BEEF, resp); check_resp(resp, 2'b00, "T1 SRC write");
        axil_write32(32'h08, 32'hCAFE_F00D, resp); check_resp(resp, 2'b00, "T1 DST write");
        axil_write32(32'h0C, 32'h0000_0007, resp); check_resp(resp, 2'b00, "T1 LEN write");
        axil_write32(32'h10, 32'h0000_0042, resp); check_resp(resp, 2'b00, "T1 ADD write");
        axil_read32(32'h04, rval, resp); check_resp(resp, 2'b00, "T1 SRC read");
        check_eq(rval, 32'hDEAD_BEEF, "T1 SRC readback");
        axil_read32(32'h08, rval, resp); check_resp(resp, 2'b00, "T1 DST read");
        check_eq(rval, 32'hCAFE_F00D, "T1 DST readback");
        axil_read32(32'h0C, rval, resp); check_resp(resp, 2'b00, "T1 LEN read");
        check_eq(rval, 32'h0000_0007, "T1 LEN readback");
        axil_read32(32'h10, rval, resp); check_resp(resp, 2'b00, "T1 ADD read");
        check_eq(rval, 32'h0000_0042, "T1 ADD readback");
        axil_write32(32'h30, 32'hDEAD_DEAD, resp); check_resp(resp, 2'b10, "T1 invalid write SLVERR");
        axil_read32(32'h30, rval, resp);            check_resp(resp, 2'b10, "T1 invalid read SLVERR");
        check_eq(rval, 32'h0000_0000, "T1 invalid rdata=0");
        // T1: 4 write + 4 (read_resp+val)×4 + 1 inv_write + 2 inv_read = 15 checks

        // ============================================================
        // Test 2: 1-word add (0x10 + 0x05 = 0x15)
        // ============================================================
        $display("[INFO] Test 2: 1-word add transfer");
        start_transfer(32'h0000_0000, 32'h0000_0040, 32'h0000_0005, 16'h1);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T2 STATUS read");
        check_bit(rval[0], 1'b1, "T2 STATUS.done");
        check_bit(rval[1], 1'b0, "T2 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T2 COUNT read");
        check_eq(rval, 32'h0000_0001, "T2 PROCESSED_COUNT=1");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T2 LAST_IN read");
        check_eq(rval, 32'h0000_0010, "T2 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T2 LAST_OUT read");
        check_eq(rval, 32'h0000_0015, "T2 LAST_OUTPUT_DATA");
        check_eq(slave.mem[16], 32'h0000_0015, "T2 dst mem[0x40>>2]");
        // T2: 5(start) + 3(STATUS) + 2(COUNT) + 2(LAST_IN) + 2(LAST_OUT) + 1(dst) = 15

        // ============================================================
        // Test 3: 4-word add (add=0x100)
        // ============================================================
        $display("[INFO] Test 3: 4-word add transfer (add=0x100)");
        start_transfer(32'h0000_0010, 32'h0000_0080, 32'h0000_0100, 16'h4);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T3 STATUS read");
        check_bit(rval[0], 1'b1, "T3 STATUS.done");
        check_bit(rval[1], 1'b0, "T3 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T3 COUNT read");
        check_eq(rval, 32'h0000_0004, "T3 PROCESSED_COUNT=4");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T3 LAST_IN read");
        check_eq(rval, 32'h4000_0004, "T3 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T3 LAST_OUT read");
        check_eq(rval, 32'h4000_0104, "T3 LAST_OUTPUT_DATA");
        check_eq(slave.mem[32], 32'h1000_0101, "T3 dst[0]");
        check_eq(slave.mem[33], 32'h2000_0102, "T3 dst[1]");
        check_eq(slave.mem[34], 32'h3000_0103, "T3 dst[2]");
        check_eq(slave.mem[35], 32'h4000_0104, "T3 dst[3]");
        // T3: 5 + 3 + 2 + 2 + 2 + 4 = 18

        // ============================================================
        // Test 4: Identity mode (add=0)
        // ============================================================
        $display("[INFO] Test 4: identity mode (add=0)");
        start_transfer(32'h0000_0020, 32'h0000_00C0, 32'h0000_0000, 16'h4);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T4 STATUS read");
        check_bit(rval[0], 1'b1, "T4 STATUS.done");
        check_bit(rval[1], 1'b0, "T4 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T4 COUNT read");
        check_eq(rval, 32'h0000_0004, "T4 PROCESSED_COUNT=4");
        check_eq(slave.mem[48], 32'hAAAA_0001, "T4 dst[0]");
        check_eq(slave.mem[49], 32'hBBBB_0002, "T4 dst[1]");
        check_eq(slave.mem[50], 32'hCCCC_0003, "T4 dst[2]");
        check_eq(slave.mem[51], 32'hDDDD_0004, "T4 dst[3]");
        // T4: 5 + 3 + 2 + 4 = 14

        // ============================================================
        // Test 5: Overflow (0xFFFF_FFFF + 1 wraps to 0)
        // ============================================================
        $display("[INFO] Test 5: 32-bit overflow (no error)");
        start_transfer(32'h0000_0030, 32'h0000_0100, 32'h0000_0001, 16'h1);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T5 STATUS read");
        check_bit(rval[0], 1'b1, "T5 STATUS.done");
        check_bit(rval[1], 1'b0, "T5 STATUS.error=0");
        check_eq(slave.mem[64], 32'h0000_0000, "T5 dst wrapped to 0");
        // T5: 5 + 3 + 1 = 9

        // ============================================================
        // Test 6: Zero-length transfer
        // ============================================================
        $display("[INFO] Test 6: zero-length transfer");
        start_transfer(32'h0000_0000, 32'h0000_0140, 32'h0000_0010, 16'h0);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T6 STATUS read");
        check_bit(rval[0], 1'b1, "T6 STATUS.done");
        check_bit(rval[1], 1'b0, "T6 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T6 COUNT read");
        check_eq(rval, 32'h0000_0000, "T6 PROCESSED_COUNT=0");
        check_eq(slave.mem[80], 32'hFACE_B00C, "T6 canary mem[0x140>>2] unchanged");
        // T6: 5 + 3 + 2 + 1 = 11

        // ============================================================
        // Test 7: Invalid source mid-transfer
        //   src=0xFF8 (mem[1022]=0xBBBB_2222, mem[1023]=0xCCCC_3333, word2 OOB)
        //   dst=0x180 (mem[96..98]), len=3, add=0x10
        //   count=2, error=1; dst[2] canary unchanged
        // ============================================================
        $display("[INFO] Test 7: invalid src mid-transfer (word 2 OOB)");
        slave.mem[98] = 32'hDECA_F0CA;
        start_transfer(32'h0000_0FF8, 32'h0000_0180, 32'h0000_0010, 16'h3);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T7 STATUS read");
        check_bit(rval[0], 1'b1, "T7 STATUS.done");
        check_bit(rval[1], 1'b1, "T7 STATUS.error=1");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T7 COUNT read");
        check_eq(rval, 32'h0000_0002, "T7 PROCESSED_COUNT=2");
        check_eq(slave.mem[96],  32'hBBBB_2232, "T7 dst[0]");
        check_eq(slave.mem[97],  32'hCCCC_3343, "T7 dst[1]");
        check_eq(slave.mem[98],  32'hDECA_F0CA, "T7 dst[2] canary unchanged");
        // T7: 5 + 3 + 2 + 3 = 13

        // ============================================================
        // Test 8: Invalid destination mid-transfer
        //   src=0x200 (mem[128..130]), dst=0xFF8 (words 0,1 valid, word 2 OOB)
        //   len=3, add=0x20
        //   count=2, error=1; src unchanged
        // ============================================================
        $display("[INFO] Test 8: invalid dst mid-transfer (word 2 OOB)");
        start_transfer(32'h0000_0200, 32'h0000_0FF8, 32'h0000_0020, 16'h3);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T8 STATUS read");
        check_bit(rval[0], 1'b1, "T8 STATUS.done");
        check_bit(rval[1], 1'b1, "T8 STATUS.error=1");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T8 COUNT read");
        check_eq(rval, 32'h0000_0002, "T8 PROCESSED_COUNT=2");
        check_eq(slave.mem[1022], 32'h1111_AACA, "T8 dst[0] mem[0xFF8>>2]");
        check_eq(slave.mem[1023], 32'h2222_BBDB, "T8 dst[1] mem[0xFFC>>2]");
        check_eq(slave.mem[128],  32'h1111_AAAA, "T8 src[0] unchanged");
        // T8: 5 + 3 + 2 + 3 = 13

        // ============================================================
        // Test 9: Busy-state behavior
        //   Start 8-word transfer; read STATUS immediately (busy=1);
        //   write CONTROL.start again (silently ignored);
        //   wait; verify all 8 dst words correct.
        // ============================================================
        $display("[INFO] Test 9: busy-state reads and re-trigger guard");
        axil_write32(32'h04, 32'h0000_0320, resp); check_resp(resp, 2'b00, "T9 SRC write");
        axil_write32(32'h08, 32'h0000_0500, resp); check_resp(resp, 2'b00, "T9 DST write");
        axil_write32(32'h0C, 32'h0000_0008, resp); check_resp(resp, 2'b00, "T9 LEN write");
        axil_write32(32'h10, 32'h0000_0001, resp); check_resp(resp, 2'b00, "T9 ADD write");
        axil_write32(32'h00, 32'h0000_0001, resp); check_resp(resp, 2'b00, "T9 CTRL start");
        axil_read32(32'h14, rval, resp);            check_resp(resp, 2'b00, "T9 STATUS read (busy)");
        check_bit(rval[2], 1'b1, "T9 STATUS.busy=1 while running");
        axil_write32(32'h00, 32'h0000_0001, resp); check_resp(resp, 2'b00, "T9 CTRL re-start (no-op)");
        poll_done(2000);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T9 STATUS read (done)");
        check_bit(rval[0], 1'b1, "T9 STATUS.done");
        check_bit(rval[1], 1'b0, "T9 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T9 COUNT read");
        check_eq(rval, 32'h0000_0008, "T9 PROCESSED_COUNT=8");
        check_eq(slave.mem[320], 32'hA0A0_A0A1, "T9 dst[0]");
        check_eq(slave.mem[321], 32'hA1A1_A1A2, "T9 dst[1]");
        check_eq(slave.mem[322], 32'hA2A2_A2A3, "T9 dst[2]");
        check_eq(slave.mem[323], 32'hA3A3_A3A4, "T9 dst[3]");
        check_eq(slave.mem[324], 32'hA4A4_A4A5, "T9 dst[4]");
        check_eq(slave.mem[325], 32'hA5A5_A5A6, "T9 dst[5]");
        check_eq(slave.mem[326], 32'hA6A6_A6A7, "T9 dst[6]");
        check_eq(slave.mem[327], 32'hA7A7_A7A8, "T9 dst[7]");
        // T9: 5+1+1+1+3+2+8 = 21

        // ============================================================
        // Test 10: Restart after error
        //   T10a: src=0xFFC (mem[1023]=0x2222_BBDB after T8), len=2, add=3
        //     word0 written; word1 src OOB → error, count=1
        //   T10b: fresh valid transfer, src=0x4B0, dst=0x680, len=2, add=0x0F
        // ============================================================
        $display("[INFO] Test 10: restart after error");
        start_transfer(32'h0000_0FFC, 32'h0000_0600, 32'h0000_0003, 16'h2);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T10a STATUS read");
        check_bit(rval[0], 1'b1, "T10a STATUS.done");
        check_bit(rval[1], 1'b1, "T10a STATUS.error=1");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T10a COUNT read");
        check_eq(rval, 32'h0000_0001, "T10a PROCESSED_COUNT=1");
        // Recovery transfer
        start_transfer(32'h0000_04B0, 32'h0000_0680, 32'h0000_000F, 16'h2);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T10b STATUS read");
        check_bit(rval[0], 1'b1, "T10b STATUS.done");
        check_bit(rval[1], 1'b0, "T10b STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T10b COUNT read");
        check_eq(rval, 32'h0000_0002, "T10b PROCESSED_COUNT=2");
        check_eq(slave.mem[416], 32'h1234_5687, "T10b dst[0] mem[0x680>>2]");
        check_eq(slave.mem[417], 32'h8765_4330, "T10b dst[1] mem[0x684>>2]");
        // T10: 5+3+2 + 5+3+2+2 = 22

        // ============================================================
        // Test 11: Mixed write-ordering (AW-before-W and W-before-AW)
        //   Programs all registers via alternating orderings, then runs
        //   a 3-word transfer to prove registers were written correctly.
        //   Also tests invalid address via both orderings → SLVERR.
        //   src=0x708 (mem[450..452]), dst=0x800 (mem[512..514])
        //   len=3, add=0x10
        //   Expected dst: 0xDEAD_0011 / 0xDEAD_0012 / 0xDEAD_0013
        // ============================================================
        $display("[INFO] Test 11: mixed write ordering (AW-first and W-first)");
        axil_write_aw_first(32'h40, 32'hDEAD_DEAD, resp);
        check_resp(resp, 2'b10, "T11 invalid addr AW-first SLVERR");
        axil_write_w_first(32'h50, 32'hDEAD_DEAD, resp);
        check_resp(resp, 2'b10, "T11 invalid addr W-first SLVERR");
        axil_write_aw_first(32'h04, 32'h0000_0708, resp);
        check_resp(resp, 2'b00, "T11 SRC via AW-first");
        axil_write_w_first(32'h08, 32'h0000_0800, resp);
        check_resp(resp, 2'b00, "T11 DST via W-first");
        axil_write_aw_first(32'h0C, 32'h0000_0003, resp);
        check_resp(resp, 2'b00, "T11 LEN via AW-first");
        axil_write_w_first(32'h10, 32'h0000_0010, resp);
        check_resp(resp, 2'b00, "T11 ADD via W-first");
        axil_write_aw_first(32'h00, 32'h0000_0001, resp);
        check_resp(resp, 2'b00, "T11 CTRL start via AW-first");
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T11 STATUS read");
        check_bit(rval[0], 1'b1, "T11 STATUS.done");
        check_bit(rval[1], 1'b0, "T11 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T11 COUNT read");
        check_eq(rval, 32'h0000_0003, "T11 PROCESSED_COUNT=3");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T11 LAST_IN read");
        check_eq(rval, 32'hDEAD_0003, "T11 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T11 LAST_OUT read");
        check_eq(rval, 32'hDEAD_0013, "T11 LAST_OUTPUT_DATA");
        check_eq(slave.mem[512], 32'hDEAD_0011, "T11 dst[0] mem[0x800>>2]");
        check_eq(slave.mem[513], 32'hDEAD_0012, "T11 dst[1] mem[0x804>>2]");
        check_eq(slave.mem[514], 32'hDEAD_0013, "T11 dst[2] mem[0x808>>2]");
        // T11: 2(invalid) + 5(reg writes) + 3+2+2+2+3 = 19 checks

        // ============================================================
        // Test 12: B-channel backpressure (delayed bready, 3-cycle hold)
        //   Programs SRC/DST/LEN/ADD via axil_write_bready_delay,
        //   verifying bvalid is held asserted during each delay cycle.
        //   Invalid address also tested under backpressure → SLVERR.
        //   src=0x810 (mem[516..517]), dst=0x900 (mem[576..577])
        //   len=2, add=5
        //   Expected dst: 0x1122_3349 / 0x5566_778D
        // ============================================================
        $display("[INFO] Test 12: B-channel backpressure (3-cycle bready delay)");
        axil_write_bready_delay(32'h04, 32'h0000_0810, 3, resp);
        check_resp(resp, 2'b00, "T12 SRC bready_delay OKAY");
        axil_write_bready_delay(32'h08, 32'h0000_0900, 3, resp);
        check_resp(resp, 2'b00, "T12 DST bready_delay OKAY");
        axil_write_bready_delay(32'h0C, 32'h0000_0002, 3, resp);
        check_resp(resp, 2'b00, "T12 LEN bready_delay OKAY");
        axil_write_bready_delay(32'h10, 32'h0000_0005, 3, resp);
        check_resp(resp, 2'b00, "T12 ADD bready_delay OKAY");
        axil_write_bready_delay(32'h44, 32'h0000_0000, 3, resp);
        check_resp(resp, 2'b10, "T12 invalid addr bready_delay SLVERR");
        axil_write32(32'h00, 32'h0000_0001, resp); check_resp(resp, 2'b00, "T12 CTRL start");
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T12 STATUS read");
        check_bit(rval[0], 1'b1, "T12 STATUS.done");
        check_bit(rval[1], 1'b0, "T12 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T12 COUNT read");
        check_eq(rval, 32'h0000_0002, "T12 PROCESSED_COUNT=2");
        check_eq(slave.mem[576], 32'h1122_3349, "T12 dst[0] mem[0x900>>2]");
        check_eq(slave.mem[577], 32'h5566_778D, "T12 dst[1] mem[0x904>>2]");
        // T12: 5×(3+1) bvalid + 5 resp + 1 ctrl + 3 + 2 + 2 = 33 checks

        // ============================================================
        // Test 13: R-channel backpressure (delayed rready, 3-cycle hold)
        //   Programs SRC/DST/LEN/ADD via start_transfer, runs 4-word add,
        //   then reads all 9 register addresses (SRC/DST/LEN/ADD/STATUS/
        //   COUNT/LAST_IN/LAST_OUT) and one invalid address (0x44) each
        //   with a 3-cycle rready delay, verifying rvalid/rdata/rresp are
        //   held stable at every delay cycle.
        //   src=0x820 (mem[520..523]), dst=0x940 (mem[592..595])
        //   len=4, add=0x07
        //   Expected dst: +7 per word; LAST_IN=0x3A3B_3C3D, LAST_OUT=0x3A3B_3C44
        // ============================================================
        $display("[INFO] Test 13: R-channel backpressure (3-cycle rready delay)");
        start_transfer(32'h0000_0820, 32'h0000_0940, 32'h0000_0007, 16'h4);
        poll_done(500);
        axil_read_rready_delay(32'h04, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0820, "T13 SRC_ADDR readback");
        axil_read_rready_delay(32'h08, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0940, "T13 DST_ADDR readback");
        axil_read_rready_delay(32'h0C, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0004, "T13 LEN readback");
        axil_read_rready_delay(32'h10, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0007, "T13 ADD_VALUE readback");
        axil_read_rready_delay(32'h14, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0001, "T13 STATUS (done=1 error=0 busy=0)");
        axil_read_rready_delay(32'h18, 2'b00, 3, rval);
        check_eq(rval, 32'h0000_0004, "T13 PROCESSED_COUNT=4");
        axil_read_rready_delay(32'h1C, 2'b00, 3, rval);
        check_eq(rval, 32'h3A3B_3C3D, "T13 LAST_INPUT_DATA");
        axil_read_rready_delay(32'h20, 2'b00, 3, rval);
        check_eq(rval, 32'h3A3B_3C44, "T13 LAST_OUTPUT_DATA");
        axil_read_rready_delay(32'h44, 2'b10, 3, rval);
        check_eq(rval, 32'h0000_0000, "T13 invalid addr rdata=0");
        // T13: 5(start) + 9×(3×3 loop + 1 rvalid_final + 1 rresp_final) + 9(data checks)
        //    = 5 + 9×11 + 9 = 5 + 99 + 9 = 113 checks

        // ============================================================
        // Test 14a: Reset during active DMA add transfer
        //   Starts a 16-word add transfer (src=0xB00/mem[704..719],
        //   dst=0xA00/mem[640..655], len=16, add=0x10), waits 10 cycles
        //   while the DMA is actively running, then asserts aresetn=0
        //   for 8 cycles.  After reset:
        //   - All DUT AXI-lite visible registers must read 0 (reset default).
        //   - Canary mem[639] (before dst) and mem[656] (after dst end)
        //     must be unchanged.
        //   - Some dst words (mem[640..655]) may have been partially
        //     written before reset — this is acceptable and expected;
        //     they are not checked here.
        // ============================================================
        $display("[INFO] Test 14a: reset during active DMA add transfer");
        start_transfer(32'h0000_0B00, 32'h0000_0A00, 32'h0000_0010, 16'h10);
        // Wait 10 cycles — transfer is actively in-flight before we reset
        repeat(10) @(posedge aclk);
        // Assert reset mid-transfer
        @(negedge aclk); aresetn = 1'b0;
        repeat(8) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        repeat(4) @(posedge aclk);   // let FSMs settle after reset deassert
        // Verify all AXI-lite visible registers are at reset defaults (all 0)
        axil_read32(32'h00, rval, resp); check_resp(resp, 2'b00, "T14a CONTROL read");
        check_eq(rval, 32'h0000_0000, "T14a CONTROL=0 (busy_r=0)");
        axil_read32(32'h04, rval, resp); check_resp(resp, 2'b00, "T14a SRC_ADDR read");
        check_eq(rval, 32'h0000_0000, "T14a SRC_ADDR=0");
        axil_read32(32'h08, rval, resp); check_resp(resp, 2'b00, "T14a DST_ADDR read");
        check_eq(rval, 32'h0000_0000, "T14a DST_ADDR=0");
        axil_read32(32'h0C, rval, resp); check_resp(resp, 2'b00, "T14a LEN read");
        check_eq(rval, 32'h0000_0000, "T14a LENGTH_WORDS=0");
        axil_read32(32'h10, rval, resp); check_resp(resp, 2'b00, "T14a ADD_VALUE read");
        check_eq(rval, 32'h0000_0000, "T14a ADD_VALUE=0");
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T14a STATUS read");
        check_eq(rval, 32'h0000_0000, "T14a STATUS=0 (done=0 error=0 busy=0)");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T14a COUNT read");
        check_eq(rval, 32'h0000_0000, "T14a PROCESSED_COUNT=0");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T14a LAST_IN read");
        check_eq(rval, 32'h0000_0000, "T14a LAST_INPUT_DATA=0");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T14a LAST_OUT read");
        check_eq(rval, 32'h0000_0000, "T14a LAST_OUTPUT_DATA=0");
        // Canary checks: no write should have reached addresses outside [0xA00..0xA3C]
        check_eq(slave.mem[639], 32'hBEEF_CAFE, "T14a canary mem[639] 0x9FC unchanged");
        check_eq(slave.mem[656], 32'hDECA_FBAD, "T14a canary mem[656] 0xA40 unchanged");
        // T14a: 5(start) + 9×2 (reg reads) + 2 (canary) = 25 checks

        // ============================================================
        // Test 14b: Fresh valid transfer after mid-transfer reset
        //   Verifies DMA add operates correctly after a reset recovery.
        //   src=0xC00 (mem[768..771]), dst=0xD00 (mem[832..835])
        //   len=4, add=3
        //   Expected: dst[i] = src[i] + 3
        // ============================================================
        $display("[INFO] Test 14b: fresh valid transfer after reset");
        start_transfer(32'h0000_0C00, 32'h0000_0D00, 32'h0000_0003, 16'h4);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T14b STATUS read");
        check_bit(rval[0], 1'b1, "T14b STATUS.done");
        check_bit(rval[1], 1'b0, "T14b STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T14b COUNT read");
        check_eq(rval, 32'h0000_0004, "T14b PROCESSED_COUNT=4");
        check_eq(slave.mem[832], 32'h0001_1004, "T14b dst[0] mem[0xD00>>2]");
        check_eq(slave.mem[833], 32'h0002_2005, "T14b dst[1] mem[0xD04>>2]");
        check_eq(slave.mem[834], 32'h0003_3006, "T14b dst[2] mem[0xD08>>2]");
        check_eq(slave.mem[835], 32'h0004_4007, "T14b dst[3] mem[0xD0C>>2]");
        // T14b: 5(start) + 3(STATUS) + 2(COUNT) + 4(dst) = 14 checks

        // ============================================================
        // Test 15: Repeated normal restart (5 back-to-back transfers)
        //   Five sequential DMA add transfers with distinct src/dst/len/add
        //   values.  Verifies that each run uses freshly programmed register
        //   values and produces correct STATUS/COUNT/LAST_IN/LAST_OUT/dst.
        //   src layout: mem[836..847] byte 0xD10, dst layout: mem[850..861] byte 0xD48
        //   Canary: mem[862] byte 0xD78 must remain unchanged.
        // ============================================================
        $display("[INFO] Test 15: repeated normal restart (5 back-to-back transfers)");

        $display("[INFO] T15 run1 src=0xD10 dst=0xD48 len=1 add=0xAA");
        start_transfer(32'h0000_0D10, 32'h0000_0D48, 32'h0000_00AA, 16'h1);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T15r1 STATUS resp");
        check_bit(rval[0], 1'b1, "T15r1 STATUS.done");
        check_bit(rval[1], 1'b0, "T15r1 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T15r1 COUNT resp");
        check_eq(rval, 32'h0000_0001, "T15r1 PROCESSED_COUNT=1");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T15r1 LAST_IN resp");
        check_eq(rval, 32'hAAAA_0001, "T15r1 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T15r1 LAST_OUT resp");
        check_eq(rval, 32'hAAAA_00AB, "T15r1 LAST_OUTPUT_DATA");
        check_eq(slave.mem[850], 32'hAAAA_00AB, "T15r1 dst[0] mem[0xD48>>2]");
        // run1: 5+3+2+2+2+1=15

        $display("[INFO] T15 run2 src=0xD14 dst=0xD4C len=2 add=0xBB");
        start_transfer(32'h0000_0D14, 32'h0000_0D4C, 32'h0000_00BB, 16'h2);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T15r2 STATUS resp");
        check_bit(rval[0], 1'b1, "T15r2 STATUS.done");
        check_bit(rval[1], 1'b0, "T15r2 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T15r2 COUNT resp");
        check_eq(rval, 32'h0000_0002, "T15r2 PROCESSED_COUNT=2");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T15r2 LAST_IN resp");
        check_eq(rval, 32'hBBBB_0002, "T15r2 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T15r2 LAST_OUT resp");
        check_eq(rval, 32'hBBBB_00BD, "T15r2 LAST_OUTPUT_DATA");
        check_eq(slave.mem[851], 32'hBBBB_00BC, "T15r2 dst[0] mem[0xD4C>>2]");
        check_eq(slave.mem[852], 32'hBBBB_00BD, "T15r2 dst[1] mem[0xD50>>2]");
        // run2: 5+3+2+2+2+2=16

        $display("[INFO] T15 run3 src=0xD1C dst=0xD54 len=3 add=0xCC");
        start_transfer(32'h0000_0D1C, 32'h0000_0D54, 32'h0000_00CC, 16'h3);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T15r3 STATUS resp");
        check_bit(rval[0], 1'b1, "T15r3 STATUS.done");
        check_bit(rval[1], 1'b0, "T15r3 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T15r3 COUNT resp");
        check_eq(rval, 32'h0000_0003, "T15r3 PROCESSED_COUNT=3");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T15r3 LAST_IN resp");
        check_eq(rval, 32'hCCCC_0003, "T15r3 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T15r3 LAST_OUT resp");
        check_eq(rval, 32'hCCCC_00CF, "T15r3 LAST_OUTPUT_DATA");
        check_eq(slave.mem[853], 32'hCCCC_00CD, "T15r3 dst[0] mem[0xD54>>2]");
        check_eq(slave.mem[854], 32'hCCCC_00CE, "T15r3 dst[1] mem[0xD58>>2]");
        check_eq(slave.mem[855], 32'hCCCC_00CF, "T15r3 dst[2] mem[0xD5C>>2]");
        // run3: 5+3+2+2+2+3=17

        $display("[INFO] T15 run4 src=0xD28 dst=0xD60 len=2 add=0xDD");
        start_transfer(32'h0000_0D28, 32'h0000_0D60, 32'h0000_00DD, 16'h2);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T15r4 STATUS resp");
        check_bit(rval[0], 1'b1, "T15r4 STATUS.done");
        check_bit(rval[1], 1'b0, "T15r4 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T15r4 COUNT resp");
        check_eq(rval, 32'h0000_0002, "T15r4 PROCESSED_COUNT=2");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T15r4 LAST_IN resp");
        check_eq(rval, 32'hDDDD_0002, "T15r4 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T15r4 LAST_OUT resp");
        check_eq(rval, 32'hDDDD_00DF, "T15r4 LAST_OUTPUT_DATA");
        check_eq(slave.mem[856], 32'hDDDD_00DE, "T15r4 dst[0] mem[0xD60>>2]");
        check_eq(slave.mem[857], 32'hDDDD_00DF, "T15r4 dst[1] mem[0xD64>>2]");
        // run4: 5+3+2+2+2+2=16

        $display("[INFO] T15 run5 src=0xD30 dst=0xD68 len=4 add=0xEE");
        start_transfer(32'h0000_0D30, 32'h0000_0D68, 32'h0000_00EE, 16'h4);
        poll_done(500);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T15r5 STATUS resp");
        check_bit(rval[0], 1'b1, "T15r5 STATUS.done");
        check_bit(rval[1], 1'b0, "T15r5 STATUS.error=0");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T15r5 COUNT resp");
        check_eq(rval, 32'h0000_0004, "T15r5 PROCESSED_COUNT=4");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T15r5 LAST_IN resp");
        check_eq(rval, 32'hEEEE_0004, "T15r5 LAST_INPUT_DATA");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T15r5 LAST_OUT resp");
        check_eq(rval, 32'hEEEE_00F2, "T15r5 LAST_OUTPUT_DATA");
        check_eq(slave.mem[858], 32'hEEEE_00EF, "T15r5 dst[0] mem[0xD68>>2]");
        check_eq(slave.mem[859], 32'hEEEE_00F0, "T15r5 dst[1] mem[0xD6C>>2]");
        check_eq(slave.mem[860], 32'hEEEE_00F1, "T15r5 dst[2] mem[0xD70>>2]");
        check_eq(slave.mem[861], 32'hEEEE_00F2, "T15r5 dst[3] mem[0xD74>>2]");
        check_eq(slave.mem[862], 32'hA1B2_C3D4, "T15 canary mem[862] 0xD78 unchanged");
        // run5: 5+3+2+2+2+4=18; canary: 1
        // T15 total: 15+16+17+16+18+1 = 83 checks

        // ============================================================
        // Test 16: Lightweight random valid-transfer smoke
        //   10 iterations, deterministic pseudo-random parameters
        //   (fixed seed: len cycles 1..8 then 1,2; add = iter+1).
        //   src window: 0xD80 (mem[864..871], 8 words)
        //   dst window: 0xDA0 (mem[872..879], 8 words)
        //   src[j] = (iter+1)*0x1000 + (j+1); dst[j] = src[j] + add
        //   Canary: mem[880] byte 0xDC0 must remain unchanged after all iters.
        // ============================================================
        $display("[INFO] Test 16: lightweight random valid-transfer smoke (10 iters, fixed seed)");
        begin : t16_body
            integer t16_k, t16_j;
            integer t16_len_i;
            integer t16_add_i;
            logic [31:0] t16_src_w;
            logic [31:0] t16_exp_w;

            for (t16_k = 0; t16_k < 10; t16_k = t16_k + 1) begin
                t16_len_i = (t16_k < 8) ? (t16_k + 1) : (t16_k - 7);
                t16_add_i = t16_k + 1;
                $display("[INFO] T16 iter=%0d len=%0d add=%0d src=0xD80 dst=0xDA0",
                         t16_k, t16_len_i, t16_add_i);
                // Seed source window: src[j] = (iter+1)*0x1000 + (j+1)
                for (t16_j = 0; t16_j < t16_len_i; t16_j = t16_j + 1)
                    slave.mem[864 + t16_j] = (t16_k + 1) * 32'h0000_1000 + (t16_j + 1);
                // Run transfer
                start_transfer(32'h0000_0D80, 32'h0000_0DA0,
                               t16_add_i, t16_len_i[15:0]);
                poll_done(1000);
                // Verify STATUS
                axil_read32(32'h14, rval, resp);
                check_resp(resp, 2'b00, $sformatf("T16[%0d] STATUS resp", t16_k));
                check_bit(rval[0], 1'b1, $sformatf("T16[%0d] STATUS.done", t16_k));
                check_bit(rval[1], 1'b0, $sformatf("T16[%0d] STATUS.error=0", t16_k));
                // Verify COUNT
                axil_read32(32'h18, rval, resp);
                check_resp(resp, 2'b00, $sformatf("T16[%0d] COUNT resp", t16_k));
                check_eq(rval, t16_len_i, $sformatf("T16[%0d] COUNT=%0d", t16_k, t16_len_i));
                // Verify all dst words: dst[j] == src[j] + add
                for (t16_j = 0; t16_j < t16_len_i; t16_j = t16_j + 1) begin
                    t16_src_w = (t16_k + 1) * 32'h0000_1000 + (t16_j + 1);
                    t16_exp_w = t16_src_w + t16_add_i;
                    check_eq(slave.mem[872 + t16_j], t16_exp_w,
                             $sformatf("T16[%0d] dst[%0d]", t16_k, t16_j));
                end
            end
        end : t16_body
        check_eq(slave.mem[880], 32'hCAFE_BABE, "T16 canary mem[880] 0xDC0 unchanged");
        // T16: 10×(5+3+2) + sum_lens(1+2+..+8+1+2=39) + canary(1) = 100+39+1 = 140 checks

        // ============================================================
        // Test 17: busy config write policy
        // orig: src=0xE10 (mem[900..915]), dst=0xF00 (mem[960..975]), add=0x1234, len=16
        // new:  src=0xE60 (mem[920..924]), dst=0xF50 (mem[980..984]), add=0x5678, len=5
        // ============================================================
        $display("[INFO] Test 17: busy config write policy");

        // Phase 1: start orig transfer (5 checks)
        start_transfer(32'h0000_0E10, 32'h0000_0F00, 32'h0000_1234, 16'h10);

        // Phase 2: verify busy immediately after start (3 checks)
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T17 STATUS read while busy");
        check_bit(rval[2], 1'b1, "T17 STATUS.busy=1");
        check_bit(rval[0], 1'b0, "T17 STATUS.done=0 while busy");

        // Phase 3: write new config while DMA busy (4 checks)
        axil_write32(32'h04, 32'h0000_0E60, resp); check_resp(resp, 2'b00, "T17 busy write SRC=new");
        axil_write32(32'h08, 32'h0000_0F50, resp); check_resp(resp, 2'b00, "T17 busy write DST=new");
        axil_write32(32'h0C, 32'h0000_0005, resp); check_resp(resp, 2'b00, "T17 busy write LEN=5");
        axil_write32(32'h10, 32'h0000_5678, resp); check_resp(resp, 2'b00, "T17 busy write ADD=new");

        // Phase 4: wait for orig transfer to finish (no checks)
        poll_done(1000);

        // Phase 5: verify orig transfer result (9 status/count/last checks)
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T17 STATUS after orig");
        check_bit(rval[0], 1'b1, "T17 STATUS.done=1 after orig");
        check_bit(rval[1], 1'b0, "T17 STATUS.error=0 after orig");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T17 COUNT after orig");
        check_eq(rval, 32'h0000_0010, "T17 PROCESSED_COUNT=16 orig");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T17 LAST_IN after orig");
        check_eq(rval, 32'hA0A0_0010, "T17 LAST_INPUT_DATA orig");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T17 LAST_OUT after orig");
        check_eq(rval, 32'hA0A0_1244, "T17 LAST_OUTPUT_DATA orig");

        // orig dst words: mem[960..975] = src[i] + 0x1234 (16 checks)
        begin : t17_orig_dst_check
            integer t17_i;
            for (t17_i = 0; t17_i < 16; t17_i = t17_i + 1)
                check_eq(slave.mem[960 + t17_i],
                         32'hA0A0_1235 + t17_i,
                         $sformatf("T17 orig dst[%0d]", t17_i));
        end : t17_orig_dst_check

        // canaries around orig dst (2 checks)
        check_eq(slave.mem[959], 32'hB1B1_B1B1, "T17 canary before orig dst mem[959] unchanged");
        check_eq(slave.mem[976], 32'hB2B2_B2B2, "T17 canary after  orig dst mem[976] unchanged");

        // new dst not written yet — orig transfer went to mem[960..975] (1 check)
        check_eq(slave.mem[980], 32'h0000_0000, "T17 new dst mem[980] not yet written");

        // Phase 6: verify config registers show new values (8 checks)
        axil_read32(32'h04, rval, resp); check_resp(resp, 2'b00, "T17 SRC reg read");
        check_eq(rval, 32'h0000_0E60, "T17 SRC readback=new");
        axil_read32(32'h08, rval, resp); check_resp(resp, 2'b00, "T17 DST reg read");
        check_eq(rval, 32'h0000_0F50, "T17 DST readback=new");
        axil_read32(32'h0C, rval, resp); check_resp(resp, 2'b00, "T17 LEN reg read");
        check_eq(rval, 32'h0000_0005, "T17 LEN readback=5");
        axil_read32(32'h10, rval, resp); check_resp(resp, 2'b00, "T17 ADD reg read");
        check_eq(rval, 32'h0000_5678, "T17 ADD readback=new");

        // Phase 7: second transfer using new register values (17 checks)
        axil_write32(32'h00, 32'h0000_0001, resp); check_resp(resp, 2'b00, "T17 second CTRL.start");
        poll_done(1000);
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T17 STATUS after new xfer");
        check_bit(rval[0], 1'b1, "T17 STATUS.done=1 new xfer");
        check_bit(rval[1], 1'b0, "T17 STATUS.error=0 new xfer");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T17 COUNT after new xfer");
        check_eq(rval, 32'h0000_0005, "T17 PROCESSED_COUNT=5 new xfer");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T17 LAST_IN after new xfer");
        check_eq(rval, 32'hB0B0_0005, "T17 LAST_INPUT_DATA new xfer");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T17 LAST_OUT after new xfer");
        check_eq(rval, 32'hB0B0_567D, "T17 LAST_OUTPUT_DATA new xfer");

        // new dst words: mem[980..984] = src[i] + 0x5678 (5 checks)
        begin : t17_new_dst_check
            integer t17_j;
            for (t17_j = 0; t17_j < 5; t17_j = t17_j + 1)
                check_eq(slave.mem[980 + t17_j],
                         32'hB0B0_5679 + t17_j,
                         $sformatf("T17 new dst[%0d]", t17_j));
        end : t17_new_dst_check

        // canaries around new dst (2 checks)
        check_eq(slave.mem[979], 32'hB3B3_B3B3, "T17 canary before new dst mem[979] unchanged");
        check_eq(slave.mem[985], 32'hB4B4_B4B4, "T17 canary after  new dst mem[985] unchanged");
        // T17: 5+3+4+9+16+2+1+8+17 = 65 checks

        // ============================================================
        // Test 18: reset during transfer
        //   Phase A: start 8-word transfer (src=0xF68/mem[986..993],
        //            dst=0xF8C/mem[995..1002], add=0x2468, len=8);
        //            verify STATUS.busy=1 immediately after start;
        //            wait 10 cycles then assert reset mid-flight.
        //   Phase B: verify all 9 AXI-lite registers at reset defaults (all 0);
        //            verify canaries mem[994] (before dst 0xF88) and
        //            mem[1003] (after dst 0xFAC) unchanged.
        //            orig dst words may be partially written — not checked.
        //   Phase C: recovery 3-word transfer (src=0xFB0, dst=0xFC0,
        //            add=0x100, len=3); verify full result.
        // ============================================================
        $display("[INFO] Test 18: reset during transfer");

        // Phase A: start original 8-word transfer (5 checks)
        start_transfer(32'h0000_0F68, 32'h0000_0F8C, 32'h0000_2468, 16'h8);

        // Verify STATUS.busy=1 immediately after start (3 checks)
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T18 STATUS read while busy");
        check_bit(rval[2], 1'b1, "T18 STATUS.busy=1");
        check_bit(rval[0], 1'b0, "T18 STATUS.done=0 while busy");

        // Assert reset while DMA is in-flight
        repeat(10) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b0;
        repeat(8) @(posedge aclk);
        @(negedge aclk); aresetn = 1'b1;
        repeat(4) @(posedge aclk);   // let DUT settle after reset release

        // Phase B: verify all AXI-lite registers at reset defaults (18 checks)
        axil_read32(32'h00, rval, resp); check_resp(resp, 2'b00, "T18 CONTROL read");
        check_eq(rval, 32'h0000_0000, "T18 CONTROL=0 (busy_r=0 after reset)");
        axil_read32(32'h04, rval, resp); check_resp(resp, 2'b00, "T18 SRC_ADDR read");
        check_eq(rval, 32'h0000_0000, "T18 SRC_ADDR=0 after reset");
        axil_read32(32'h08, rval, resp); check_resp(resp, 2'b00, "T18 DST_ADDR read");
        check_eq(rval, 32'h0000_0000, "T18 DST_ADDR=0 after reset");
        axil_read32(32'h0C, rval, resp); check_resp(resp, 2'b00, "T18 LEN read");
        check_eq(rval, 32'h0000_0000, "T18 LENGTH_WORDS=0 after reset");
        axil_read32(32'h10, rval, resp); check_resp(resp, 2'b00, "T18 ADD_VALUE read");
        check_eq(rval, 32'h0000_0000, "T18 ADD_VALUE=0 after reset");
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T18 STATUS read");
        check_eq(rval, 32'h0000_0000, "T18 STATUS=0 (done=0 error=0 busy=0)");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T18 COUNT read");
        check_eq(rval, 32'h0000_0000, "T18 PROCESSED_COUNT=0 after reset");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T18 LAST_IN read");
        check_eq(rval, 32'h0000_0000, "T18 LAST_INPUT_DATA=0 after reset");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T18 LAST_OUT read");
        check_eq(rval, 32'h0000_0000, "T18 LAST_OUTPUT_DATA=0 after reset");

        // Canary checks: no writes outside [0xF8C..0xFA8] (2 checks)
        check_eq(slave.mem[994],  32'hF8F8_AABB, "T18 canary before orig dst mem[994] 0xF88 unchanged");
        check_eq(slave.mem[1003], 32'hF8F8_CCDD, "T18 canary after  orig dst mem[1003] 0xFAC unchanged");
        // orig dst mem[995..1002] may have been partially written before reset — not checked

        // Phase C: recovery transfer (5 checks for start_transfer)
        $display("[INFO] Test 18: recovery transfer after reset");
        start_transfer(32'h0000_0FB0, 32'h0000_0FC0, 32'h0000_0100, 16'h3);
        poll_done(500);
        // STATUS/COUNT/LAST_IN/LAST_OUT (4+2+2+2 = 10 checks)
        axil_read32(32'h14, rval, resp); check_resp(resp, 2'b00, "T18 STATUS after recovery");
        check_bit(rval[0], 1'b1, "T18 STATUS.done=1 recovery");
        check_bit(rval[1], 1'b0, "T18 STATUS.error=0 recovery");
        check_bit(rval[2], 1'b0, "T18 STATUS.busy=0 recovery");
        axil_read32(32'h18, rval, resp); check_resp(resp, 2'b00, "T18 COUNT after recovery");
        check_eq(rval, 32'h0000_0003, "T18 PROCESSED_COUNT=3 recovery");
        axil_read32(32'h1C, rval, resp); check_resp(resp, 2'b00, "T18 LAST_IN after recovery");
        check_eq(rval, 32'hD9D9_0003, "T18 LAST_INPUT_DATA recovery");
        axil_read32(32'h20, rval, resp); check_resp(resp, 2'b00, "T18 LAST_OUT after recovery");
        check_eq(rval, 32'hD9D9_0103, "T18 LAST_OUTPUT_DATA recovery");
        // 3 new dst words + 2 canaries (5 checks)
        check_eq(slave.mem[1008], 32'hD9D9_0101, "T18 new dst[0] mem[1008] 0xFC0");
        check_eq(slave.mem[1009], 32'hD9D9_0102, "T18 new dst[1] mem[1009] 0xFC4");
        check_eq(slave.mem[1010], 32'hD9D9_0103, "T18 new dst[2] mem[1010] 0xFC8");
        check_eq(slave.mem[1007], 32'hF8F8_EEFF, "T18 canary before new dst mem[1007] 0xFBC unchanged");
        check_eq(slave.mem[1011], 32'hF8F8_0011, "T18 canary after  new dst mem[1011] 0xFCC unchanged");
        // T18: 5+3+18+2+5+4+2+2+2+3+2 = 48 checks

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0)
            $display("[PASS] simple_dma_add_ctrl_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        else
            $display("[FAIL] simple_dma_add_ctrl_tb  %0d/%0d checks passed (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
