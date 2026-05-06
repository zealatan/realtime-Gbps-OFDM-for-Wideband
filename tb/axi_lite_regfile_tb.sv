`timescale 1ns/1ps

// Drive AXI master signals on negedge; sample DUT ready/valid on posedge.
// check_resp_note() is a soft check used for RTL-limitation cases: it logs
// [FAIL] and increments fail_count but does NOT call $fatal, so the simulation
// runs to completion and the full picture is visible.
module axi_lite_regfile_tb;

    // ---------------------------------------------------------------
    // Clock / reset
    // ---------------------------------------------------------------
    logic aclk   = 1'b0;
    logic aresetn;
    always #5 aclk = ~aclk;   // 100 MHz

    // ---------------------------------------------------------------
    // AXI-lite wires
    // ---------------------------------------------------------------
    logic [31:0] awaddr;  logic        awvalid; wire         awready;
    logic [31:0] wdata;   logic [ 3:0] wstrb;   logic        wvalid;  wire  wready;
    wire  [ 1:0] bresp;   wire         bvalid;  logic        bready;
    logic [31:0] araddr;  logic        arvalid; wire         arready;
    wire  [31:0] rdata;   wire  [ 1:0] rresp;   wire         rvalid;  logic rready;

    // ---------------------------------------------------------------
    // DUT
    // ---------------------------------------------------------------
    axi_lite_regfile dut (
        .aclk    (aclk),    .aresetn (aresetn),
        .awaddr  (awaddr),  .awvalid (awvalid), .awready (awready),
        .wdata   (wdata),   .wstrb   (wstrb),   .wvalid  (wvalid),  .wready  (wready),
        .bresp   (bresp),   .bvalid  (bvalid),  .bready  (bready),
        .araddr  (araddr),  .arvalid (arvalid), .arready (arready),
        .rdata   (rdata),   .rresp   (rresp),   .rvalid  (rvalid),  .rready  (rready)
    );

    int        pass_count = 0;
    int        fail_count = 0;
    logic [1:0] last_bresp;
    logic [1:0] last_rresp;

    // ---------------------------------------------------------------
    // axi_write — simultaneous AW + W
    // ---------------------------------------------------------------
    task automatic axi_write(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 3:0] wstrb_in
    );
        int timeout;
        @(negedge aclk);
        awaddr = addr;  awvalid = 1'b1;
        wdata  = data;  wstrb   = wstrb_in; wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!awready || !wready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write awready/wready addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        awvalid = 1'b0; wvalid = 1'b0; bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!bvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write bvalid addr=0x%08X", addr);
            @(posedge aclk);
        end
        last_bresp = bresp;
        @(negedge aclk);
        bready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_write_aw_first — AW channel only, then W channel
    //   Tests W_IDLE -> W_WAIT_W -> W_BRESP path in the RTL FSM.
    // ---------------------------------------------------------------
    task automatic axi_write_aw_first(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 3:0] wstrb_in
    );
        int timeout;
        // Phase 1: drive AW only
        @(negedge aclk);
        awaddr = addr; awvalid = 1'b1; wvalid = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!awready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] aw_first awready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 2: drive W only — DUT is in W_WAIT_W, wready is still 1
        @(negedge aclk);
        awvalid = 1'b0; wdata = data; wstrb = wstrb_in; wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!wready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] aw_first wready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 3: collect response
        @(negedge aclk);
        wvalid = 1'b0; bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!bvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] aw_first bvalid addr=0x%08X", addr);
            @(posedge aclk);
        end
        last_bresp = bresp;
        @(negedge aclk);
        bready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_write_w_first — W channel only, then AW channel
    //   Tests W_IDLE -> W_WAIT_A -> W_BRESP path in the RTL FSM.
    // ---------------------------------------------------------------
    task automatic axi_write_w_first(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 3:0] wstrb_in
    );
        int timeout;
        // Phase 1: drive W only
        @(negedge aclk);
        wdata = data; wstrb = wstrb_in; wvalid = 1'b1; awvalid = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!wready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] w_first wready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 2: drive AW only — DUT is in W_WAIT_A, awready is still 1
        @(negedge aclk);
        wvalid = 1'b0; awaddr = addr; awvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!awready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] w_first awready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Phase 3: collect response
        @(negedge aclk);
        awvalid = 1'b0; bready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!bvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] w_first bvalid addr=0x%08X", addr);
            @(posedge aclk);
        end
        last_bresp = bresp;
        @(negedge aclk);
        bready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_read
    // ---------------------------------------------------------------
    task automatic axi_read(input logic [31:0] addr, output logic [31:0] rd);
        int timeout;
        @(negedge aclk);
        araddr = addr; arvalid = 1'b1; rready = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!arready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read arready addr=0x%08X", addr);
            @(posedge aclk);
        end
        @(negedge aclk);
        arvalid = 1'b0; rready = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!rvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read rvalid addr=0x%08X", addr);
            @(posedge aclk);
        end
        rd = rdata; last_rresp = rresp;
        @(negedge aclk);
        rready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_write_bp — simultaneous AW+W with deliberate B-channel backpressure
    //   Holds bready=0 for bp_cycles posedges after bvalid is first seen,
    //   then accepts. Verifies the slave holds bvalid and does not corrupt
    //   state while the master stalls the response channel.
    // ---------------------------------------------------------------
    task automatic axi_write_bp(
        input logic [31:0] addr,
        input logic [31:0] data,
        input logic [ 3:0] wstrb_in,
        input int          bp_cycles
    );
        int timeout;
        @(negedge aclk);
        awaddr = addr;  awvalid = 1'b1;
        wdata  = data;  wstrb   = wstrb_in; wvalid = 1'b1;
        timeout = 0;
        @(posedge aclk);
        while (!awready || !wready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write_bp awready/wready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Deassert; keep bready=0 to apply backpressure on B channel
        @(negedge aclk);
        awvalid = 1'b0; wvalid = 1'b0; bready = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!bvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_write_bp bvalid wait addr=0x%08X", addr);
            @(posedge aclk);
        end
        // bvalid=1, bready=0: stall for bp_cycles more posedges
        repeat (bp_cycles) @(posedge aclk);
        // Accept response
        @(negedge aclk);
        bready = 1'b1;
        @(posedge aclk);
        last_bresp = bresp;
        @(negedge aclk);
        bready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // axi_read_bp — read with deliberate R-channel backpressure
    //   Holds rready=0 for bp_cycles posedges after rvalid is first seen,
    //   then accepts. Verifies the slave holds rvalid/rdata stable while
    //   the master stalls the read-data channel.
    // ---------------------------------------------------------------
    task automatic axi_read_bp(
        input  logic [31:0] addr,
        output logic [31:0] rd,
        input  int          bp_cycles
    );
        int timeout;
        @(negedge aclk);
        araddr = addr; arvalid = 1'b1; rready = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!arready) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read_bp arready addr=0x%08X", addr);
            @(posedge aclk);
        end
        // Deassert arvalid; keep rready=0
        @(negedge aclk);
        arvalid = 1'b0; rready = 1'b0;
        timeout = 0;
        @(posedge aclk);
        while (!rvalid) begin
            if (++timeout > 100) $fatal(1, "[FATAL] axi_read_bp rvalid wait addr=0x%08X", addr);
            @(posedge aclk);
        end
        // rvalid=1, rready=0: stall for bp_cycles more posedges
        repeat (bp_cycles) @(posedge aclk);
        // Accept data
        @(negedge aclk);
        rready = 1'b1;
        @(posedge aclk);
        rd = rdata; last_rresp = rresp;
        @(negedge aclk);
        rready = 1'b0;
    endtask

    // ---------------------------------------------------------------
    // check_eq — hard: $fatal on mismatch
    // ---------------------------------------------------------------
    task automatic check_eq(input logic [31:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-42s  got=0x%08X", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-42s  got=0x%08X  exp=0x%08X", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_eq failed");
        end
    endtask

    // ---------------------------------------------------------------
    // check_resp — hard: $fatal on mismatch
    // ---------------------------------------------------------------
    task automatic check_resp(input logic [1:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-42s  resp=2'b%02b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-42s  got=2'b%02b  exp=2'b%02b", label, got, exp);
            fail_count++;
            $fatal(1, "[FATAL] check_resp failed");
        end
    endtask

    // ---------------------------------------------------------------
    // check_resp_note — soft: increments fail_count but no $fatal.
    // Used only for known RTL limitations so the sim runs to completion.
    // ---------------------------------------------------------------
    task automatic check_resp_note(input logic [1:0] got, exp, input string label);
        if (got === exp) begin
            $display("[PASS] %-42s  resp=2'b%02b", label, got);
            pass_count++;
        end else begin
            $display("[FAIL] %-42s  got=2'b%02b  exp=2'b%02b  [RTL_LIMITATION]",
                     label, got, exp);
            fail_count++;
            // intentionally no $fatal — RTL limitation, simulation continues
        end
    endtask

    // ---------------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------------
    logic [31:0] rd;

    initial begin
        $dumpfile("../logs/axi_lite_regfile_tb.vcd");
        $dumpvars(0, axi_lite_regfile_tb);

        awvalid = 1'b0; awaddr = '0;
        wvalid  = 1'b0; wdata  = '0; wstrb = '0;
        bready  = 1'b0;
        arvalid = 1'b0; araddr = '0;
        rready  = 1'b0;

        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (2) @(posedge aclk);
        $display("[CHK] t=%0t  phase=reset_release", $time);

        // ============================================================
        // Test 1 – reset defaults + rresp (regression)
        // ============================================================
        $display("[INFO] Test 1: reset defaults");
        for (int i = 0; i < 4; i++) begin
            axi_read(i * 4, rd);
            check_eq  (rd,          32'h0,   $sformatf("reset_default reg[%0d]",    i));
            check_resp(last_rresp,  2'b00,   $sformatf("rresp OKAY reset reg[%0d]", i));
        end

        // ============================================================
        // Test 2 – write all-ones, check bresp + rresp (regression)
        // ============================================================
        $display("[CHK] t=%0t  phase=write_allones", $time);
        $display("[INFO] Test 2: write all-ones + bresp/rresp");
        for (int i = 0; i < 4; i++) begin
            axi_write(i * 4, 32'hFFFF_FFFF, 4'hF);
            check_resp(last_bresp, 2'b00, $sformatf("bresp OKAY allones reg[%0d]", i));
            axi_read (i * 4, rd);
            check_eq  (rd,         32'hFFFF_FFFF, $sformatf("allones reg[%0d]",         i));
            check_resp(last_rresp, 2'b00,          $sformatf("rresp OKAY allones reg[%0d]", i));
        end

        // ============================================================
        // Test 3 – unique values + bresp/rresp (regression)
        // ============================================================
        $display("[CHK] t=%0t  phase=write_unique", $time);
        $display("[INFO] Test 3: unique values");
        for (int i = 0; i < 4; i++) begin
            axi_write(i * 4, 32'hA5A5_0000 | i, 4'hF);
            check_resp(last_bresp, 2'b00, $sformatf("bresp OKAY unique reg[%0d]", i));
        end
        for (int i = 0; i < 4; i++) begin
            axi_read(i * 4, rd);
            check_eq  (rd,         32'hA5A5_0000 | i, $sformatf("unique reg[%0d]",         i));
            check_resp(last_rresp, 2'b00,              $sformatf("rresp OKAY unique reg[%0d]", i));
        end

        // ============================================================
        // Test 4 – write all-zeros + bresp/rresp (regression)
        // ============================================================
        $display("[CHK] t=%0t  phase=write_allzeros", $time);
        $display("[INFO] Test 4: write all-zeros");
        for (int i = 0; i < 4; i++) begin
            axi_write(i * 4, 32'h0, 4'hF);
            check_resp(last_bresp, 2'b00, $sformatf("bresp OKAY allzeros reg[%0d]", i));
            axi_read (i * 4, rd);
            check_eq  (rd,         32'h0, $sformatf("allzeros reg[%0d]",              i));
            check_resp(last_rresp, 2'b00, $sformatf("rresp OKAY allzeros reg[%0d]",   i));
        end

        // ============================================================
        // Test 5 – partial WSTRB byte-lane writes
        // Byte mapping: wstrb[0]→bits[7:0], [1]→[15:8], [2]→[23:16], [3]→[31:24]
        // ============================================================
        $display("[CHK] t=%0t  phase=wstrb", $time);
        $display("[INFO] Test 5: partial WSTRB byte-lane writes on reg[0]");

        axi_write(32'h00, 32'hFFFF_FFFF, 4'hF);   // seed: all-ones
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb seed");

        // wstrb=0001 clears byte0 → expect 0xFFFF_FF00
        axi_write(32'h00, 32'h0000_0000, 4'b0001);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb=0001");
        axi_read(32'h00, rd);
        check_eq  (rd,         32'hFFFF_FF00, "wstrb=0001: byte0 cleared");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb=0001 read");

        // wstrb=1000 sets byte3 to 0xAB → expect 0xABFF_FF00
        axi_write(32'h00, 32'hAB00_0000, 4'b1000);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb=1000");
        axi_read(32'h00, rd);
        check_eq  (rd,         32'hABFF_FF00, "wstrb=1000: byte3 set to 0xAB");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb=1000 read");

        // wstrb=0110 updates bytes 1+2 → expect 0xAB34_1200
        // data=0x0034_1200: byte2=0x34, byte1=0x12
        axi_write(32'h00, 32'h0034_1200, 4'b0110);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb=0110");
        axi_read(32'h00, rd);
        check_eq  (rd,         32'hAB34_1200, "wstrb=0110: bytes1+2 updated");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb=0110 read");

        axi_write(32'h00, 32'h0, 4'hF);   // clean up reg[0]

        // ============================================================
        // Test 5b – individual byte-lane isolation on reg[2]
        // Each byte lane written independently to confirm no cross-byte
        // contamination from WSTRB masking. Accumulates 0x44332211.
        // ============================================================
        $display("[CHK] t=%0t  phase=wstrb_isolation", $time);
        $display("[INFO] Test 5b: individual byte-lane isolation on reg[2]");

        axi_write(32'h08, 32'hFFFF_FFFF, 4'hF);   // seed: all-ones
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb_isolation seed");

        // byte 0 only (wstrb=0001): reg[2] = 0xFFFFFF11
        axi_write(32'h08, 32'h0000_0011, 4'b0001);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb_b0_only");
        axi_read(32'h08, rd);
        check_eq  (rd,         32'hFFFF_FF11, "wstrb_b0_only: byte0=0x11 others=0xFF");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb_b0_only");

        // byte 1 only (wstrb=0010): reg[2] = 0xFFFF2211
        axi_write(32'h08, 32'h0000_2200, 4'b0010);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb_b1_only");
        axi_read(32'h08, rd);
        check_eq  (rd,         32'hFFFF_2211, "wstrb_b1_only: byte1=0x22 others unchanged");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb_b1_only");

        // byte 2 only (wstrb=0100): reg[2] = 0xFF332211
        axi_write(32'h08, 32'h0033_0000, 4'b0100);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb_b2_only");
        axi_read(32'h08, rd);
        check_eq  (rd,         32'hFF33_2211, "wstrb_b2_only: byte2=0x33 others unchanged");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb_b2_only");

        // byte 3 only (wstrb=1000): reg[2] = 0x44332211
        axi_write(32'h08, 32'h4400_0000, 4'b1000);
        check_resp(last_bresp, 2'b00, "bresp OKAY wstrb_b3_only");
        axi_read(32'h08, rd);
        check_eq  (rd,         32'h4433_2211, "wstrb_b3_only: byte3=0x44 others unchanged");
        check_resp(last_rresp, 2'b00,         "rresp OKAY wstrb_b3_only");

        axi_write(32'h08, 32'h0, 4'hF);   // clean up reg[2]

        // ============================================================
        // Test 6 – AW-before-W: exercises W_IDLE → W_WAIT_W → W_BRESP
        // ============================================================
        $display("[CHK] t=%0t  phase=aw_before_w", $time);
        $display("[INFO] Test 6: AW-before-W transaction (W_WAIT_W path)");

        axi_write_aw_first(32'h04, 32'hDEAD_BEEF, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY aw_before_w reg[1]");
        axi_read(32'h04, rd);
        check_eq  (rd,         32'hDEAD_BEEF, "aw_before_w readback reg[1]");
        check_resp(last_rresp, 2'b00,         "rresp OKAY aw_before_w reg[1]");
        axi_write(32'h04, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY aw_before_w cleanup");

        // ============================================================
        // Test 7 – W-before-AW: exercises W_IDLE → W_WAIT_A → W_BRESP
        // ============================================================
        $display("[CHK] t=%0t  phase=w_before_aw", $time);
        $display("[INFO] Test 7: W-before-AW transaction (W_WAIT_A path)");

        axi_write_w_first(32'h08, 32'hCAFE_F00D, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY w_before_aw reg[2]");
        axi_read(32'h08, rd);
        check_eq  (rd,         32'hCAFE_F00D, "w_before_aw readback reg[2]");
        check_resp(last_rresp, 2'b00,         "rresp OKAY w_before_aw reg[2]");
        axi_write(32'h08, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY w_before_aw cleanup");

        // ============================================================
        // Test 8 – invalid address 0x10 (hard checks after RTL fix)
        //
        // RTL now checks awaddr[31:4]==0 / araddr[31:4]==0 before committing
        // a write or read. Out-of-range accesses return SLVERR (2'b10) and
        // do not modify any register or leak register data.
        //
        // 0x10 → awaddr[31:4] = 0x01 ≠ 0 → SLVERR, no alias to reg[0].
        // ============================================================
        $display("[CHK] t=%0t  phase=invalid_addr", $time);
        $display("[INFO] Test 8: invalid address 0x10 — BRESP/RRESP=SLVERR, no alias");

        // Seed reg[0] with a canary value; an alias would overwrite it
        axi_write(32'h00, 32'hAAAA_AAAA, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY pre-seed reg[0]");

        // Write to unmapped 0x10 — must return SLVERR, must not touch reg[0]
        axi_write(32'h10, 32'h1234_5678, 4'hF);
        check_resp(last_bresp, 2'b10, "0x10 write: BRESP=SLVERR");

        // Read from unmapped 0x10 — must return SLVERR, rdata must be 0
        axi_read(32'h10, rd);
        check_resp(last_rresp, 2'b10, "0x10 read: RRESP=SLVERR");
        check_eq  (rd,         32'h0, "0x10 read: rdata=0x0 (no register leak)");

        // Canary readback — reg[0] must still hold 0xAAAAAAAA (not aliased)
        axi_read(32'h00, rd);
        check_eq  (rd, 32'hAAAA_AAAA, "0x10 write did not alias to reg[0]");

        axi_write(32'h00, 32'h0, 4'hF);   // clean up reg[0]

        // ============================================================
        // Test 9 – simultaneous AW+W (same-cycle)
        // Exercises the W_IDLE branch: awvalid && wvalid both asserted on
        // the same posedge, skipping W_WAIT_x states entirely.
        // ============================================================
        $display("[CHK] t=%0t  phase=same_cycle_aw_w", $time);
        $display("[INFO] Test 9: simultaneous AW+W same-cycle, W_IDLE->W_BRESP direct");

        axi_write(32'h0C, 32'hBEEF_CAFE, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY same_cycle reg[3]");
        axi_read(32'h0C, rd);
        check_eq  (rd,         32'hBEEF_CAFE, "same_cycle readback reg[3]");
        check_resp(last_rresp, 2'b00,         "rresp OKAY same_cycle reg[3]");
        axi_write(32'h0C, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY same_cycle cleanup");

        // ============================================================
        // Test 10 – B-channel backpressure
        // Writes with bready held low for N cycles after bvalid rises.
        // Verifies: slave holds bvalid, does not corrupt data or FSM state.
        //   bp=3: reg[0] ← 0xBA5EB000
        //   bp=7: reg[1] ← 0xC0DEF00D
        // ============================================================
        $display("[CHK] t=%0t  phase=b_backpressure", $time);
        $display("[INFO] Test 10: B-channel backpressure (bp=3 and bp=7)");

        axi_write_bp(32'h00, 32'hBA5E_B000, 4'hF, 3);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_write bp3 reg[0]");

        axi_write_bp(32'h04, 32'hC0DE_F00D, 4'hF, 7);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_write bp7 reg[1]");

        axi_read(32'h00, rd);
        check_eq  (rd,         32'hBA5E_B000, "bp_write readback reg[0]");
        check_resp(last_rresp, 2'b00,         "rresp OKAY bp_write readback reg[0]");

        axi_read(32'h04, rd);
        check_eq  (rd,         32'hC0DE_F00D, "bp_write readback reg[1]");
        check_resp(last_rresp, 2'b00,         "rresp OKAY bp_write readback reg[1]");

        axi_write(32'h00, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_write cleanup reg[0]");
        axi_write(32'h04, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_write cleanup reg[1]");

        // ============================================================
        // Test 11 – R-channel backpressure
        // Reads with rready held low for N cycles after rvalid rises.
        // Verifies: slave holds rvalid and rdata stable during stall.
        //   bp=3: read reg[2] = 0xF00DCAFE
        //   bp=5: read reg[3] = 0xDEAD0001
        // ============================================================
        $display("[CHK] t=%0t  phase=r_backpressure", $time);
        $display("[INFO] Test 11: R-channel backpressure (bp=3 and bp=5)");

        axi_write(32'h08, 32'hF00D_CAFE, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_read setup reg[2]");

        axi_write(32'h0C, 32'hDEAD_0001, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_read setup reg[3]");

        axi_read_bp(32'h08, rd, 3);
        check_eq  (rd,         32'hF00D_CAFE, "bp_read bp3 reg[2] data");
        check_resp(last_rresp, 2'b00,         "rresp OKAY bp_read bp3 reg[2]");

        axi_read_bp(32'h0C, rd, 5);
        check_eq  (rd,         32'hDEAD_0001, "bp_read bp5 reg[3] data");
        check_resp(last_rresp, 2'b00,         "rresp OKAY bp_read bp5 reg[3]");

        axi_write(32'h08, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_read cleanup reg[2]");
        axi_write(32'h0C, 32'h0, 4'hF);
        check_resp(last_bresp, 2'b00, "bresp OKAY bp_read cleanup reg[3]");

        // ============================================================
        // Test 12 – invalid-address sweep via simultaneous AW+W (W_IDLE path)
        //
        // Tests three new out-of-range addresses: 0x14, 0xFF, 0x8000_0000.
        // For each: BRESP=SLVERR, RRESP=SLVERR, rdata=0, canary register
        // is seeded in the register that would have been aliased before the
        // RTL fix (awaddr[3:2] target):
        //   0x14        → reg[1]  (0x14[3:2]=2'b01)
        //   0xFF        → reg[3]  (0xFF[3:2]=2'b11)
        //   0x8000_0000 → reg[0]  (0x8000_0000[3:2]=2'b00)
        // ============================================================
        $display("[CHK] t=%0t  phase=inv_addr_sweep", $time);
        $display("[INFO] Test 12: invalid-address sweep, W_IDLE simultaneous path");

        // -- 0x14 (would have aliased to reg[1]) --
        axi_write(32'h04, 32'h5A5A_1400, 4'hF);
        check_resp(last_bresp, 2'b00, "inv 0x14: seed bresp OKAY reg[1]");
        axi_write(32'h14, 32'hBAD1_4000, 4'hF);
        check_resp(last_bresp, 2'b10, "inv 0x14: BRESP=SLVERR");
        axi_read(32'h14, rd);
        check_resp(last_rresp, 2'b10, "inv 0x14: RRESP=SLVERR");
        check_eq  (rd,         32'h0, "inv 0x14: rdata=0x0");
        axi_read(32'h04, rd);
        check_eq  (rd, 32'h5A5A_1400, "inv 0x14: reg[1] unmodified");
        axi_write(32'h04, 32'h0, 4'hF);

        // -- 0xFF (would have aliased to reg[3]) --
        axi_write(32'h0C, 32'h5A5A_FF00, 4'hF);
        check_resp(last_bresp, 2'b00, "inv 0xFF: seed bresp OKAY reg[3]");
        axi_write(32'hFF, 32'hBAD0_FF00, 4'hF);
        check_resp(last_bresp, 2'b10, "inv 0xFF: BRESP=SLVERR");
        axi_read(32'hFF, rd);
        check_resp(last_rresp, 2'b10, "inv 0xFF: RRESP=SLVERR");
        check_eq  (rd,         32'h0, "inv 0xFF: rdata=0x0");
        axi_read(32'h0C, rd);
        check_eq  (rd, 32'h5A5A_FF00, "inv 0xFF: reg[3] unmodified");
        axi_write(32'h0C, 32'h0, 4'hF);

        // -- 0x8000_0000 (would have aliased to reg[0]) --
        axi_write(32'h00, 32'h5A5A_8000, 4'hF);
        check_resp(last_bresp, 2'b00, "inv 0x80000000: seed bresp OKAY reg[0]");
        axi_write(32'h8000_0000, 32'hBAD8_0000, 4'hF);
        check_resp(last_bresp, 2'b10, "inv 0x80000000: BRESP=SLVERR");
        axi_read(32'h8000_0000, rd);
        check_resp(last_rresp, 2'b10, "inv 0x80000000: RRESP=SLVERR");
        check_eq  (rd,          32'h0, "inv 0x80000000: rdata=0x0");
        axi_read(32'h00, rd);
        check_eq  (rd, 32'h5A5A_8000, "inv 0x80000000: reg[0] unmodified");
        axi_write(32'h00, 32'h0, 4'hF);

        // ============================================================
        // Test 13 – AW-before-W at invalid addresses (W_WAIT_W SLVERR)
        //
        // Drives invalid AW first (latched into aw_latch), then W data.
        // RTL guard checks aw_latch[31:4] in W_WAIT_W state → SLVERR.
        // No register must be written; canary must survive unchanged.
        // ============================================================
        $display("[CHK] t=%0t  phase=inv_addr_aw_first", $time);
        $display("[INFO] Test 13: AW-before-W at invalid addresses (W_WAIT_W path)");

        // -- 0x14 AW-before-W (reg[1] canary) --
        axi_write(32'h04, 32'h5A5A_1413, 4'hF);
        check_resp(last_bresp, 2'b00, "aw_first inv 0x14: seed bresp OKAY");
        axi_write_aw_first(32'h14, 32'hBAD1_4013, 4'hF);
        check_resp(last_bresp, 2'b10, "aw_first inv 0x14: BRESP=SLVERR");
        axi_read(32'h04, rd);
        check_eq  (rd, 32'h5A5A_1413, "aw_first inv 0x14: reg[1] unmodified");
        axi_write(32'h04, 32'h0, 4'hF);

        // -- 0xFF AW-before-W (reg[3] canary) --
        axi_write(32'h0C, 32'h5A5A_FF13, 4'hF);
        check_resp(last_bresp, 2'b00, "aw_first inv 0xFF: seed bresp OKAY");
        axi_write_aw_first(32'hFF, 32'hBAD0_FF13, 4'hF);
        check_resp(last_bresp, 2'b10, "aw_first inv 0xFF: BRESP=SLVERR");
        axi_read(32'h0C, rd);
        check_eq  (rd, 32'h5A5A_FF13, "aw_first inv 0xFF: reg[3] unmodified");
        axi_write(32'h0C, 32'h0, 4'hF);

        // -- 0x8000_0000 AW-before-W (reg[0] canary) --
        axi_write(32'h00, 32'h5A5A_8013, 4'hF);
        check_resp(last_bresp, 2'b00, "aw_first inv 0x80000000: seed bresp OKAY");
        axi_write_aw_first(32'h8000_0000, 32'hBAD8_0013, 4'hF);
        check_resp(last_bresp, 2'b10, "aw_first inv 0x80000000: BRESP=SLVERR");
        axi_read(32'h00, rd);
        check_eq  (rd, 32'h5A5A_8013, "aw_first inv 0x80000000: reg[0] unmodified");
        axi_write(32'h00, 32'h0, 4'hF);

        // ============================================================
        // Test 14 – W-before-AW at invalid addresses (W_WAIT_A SLVERR)
        //
        // Drives W data first (latched into wd_latch/ws_latch), then
        // invalid AW address. RTL guard checks awaddr[31:4] in W_WAIT_A
        // state → SLVERR. No register must be written.
        // ============================================================
        $display("[CHK] t=%0t  phase=inv_addr_w_first", $time);
        $display("[INFO] Test 14: W-before-AW at invalid addresses (W_WAIT_A path)");

        // -- 0x14 W-before-AW (reg[1] canary) --
        axi_write(32'h04, 32'h5A5A_1414, 4'hF);
        check_resp(last_bresp, 2'b00, "w_first inv 0x14: seed bresp OKAY");
        axi_write_w_first(32'h14, 32'hBAD1_4014, 4'hF);
        check_resp(last_bresp, 2'b10, "w_first inv 0x14: BRESP=SLVERR");
        axi_read(32'h04, rd);
        check_eq  (rd, 32'h5A5A_1414, "w_first inv 0x14: reg[1] unmodified");
        axi_write(32'h04, 32'h0, 4'hF);

        // -- 0xFF W-before-AW (reg[3] canary) --
        axi_write(32'h0C, 32'h5A5A_FF14, 4'hF);
        check_resp(last_bresp, 2'b00, "w_first inv 0xFF: seed bresp OKAY");
        axi_write_w_first(32'hFF, 32'hBAD0_FF14, 4'hF);
        check_resp(last_bresp, 2'b10, "w_first inv 0xFF: BRESP=SLVERR");
        axi_read(32'h0C, rd);
        check_eq  (rd, 32'h5A5A_FF14, "w_first inv 0xFF: reg[3] unmodified");
        axi_write(32'h0C, 32'h0, 4'hF);

        // -- 0x8000_0000 W-before-AW (reg[0] canary) --
        axi_write(32'h00, 32'h5A5A_8014, 4'hF);
        check_resp(last_bresp, 2'b00, "w_first inv 0x80000000: seed bresp OKAY");
        axi_write_w_first(32'h8000_0000, 32'hBAD8_0014, 4'hF);
        check_resp(last_bresp, 2'b10, "w_first inv 0x80000000: BRESP=SLVERR");
        axi_read(32'h00, rd);
        check_eq  (rd, 32'h5A5A_8014, "w_first inv 0x80000000: reg[0] unmodified");
        axi_write(32'h00, 32'h0, 4'hF);

        // ============================================================
        // Summary
        // ============================================================
        if (fail_count == 0) begin
            $display("[PASS] axi_lite_regfile_tb  %0d/%0d checks passed",
                     pass_count, pass_count);
        end else begin
            $display("[FAIL] axi_lite_regfile_tb  %0d/%0d checks passed  (%0d failure(s))",
                     pass_count, pass_count + fail_count, fail_count);
        end
        $display("[DONE] simulation complete at t=%0t", $time);
        $finish;
    end

endmodule
