`timescale 1ns/1ps

// frac_cfo_sync_bram_test_wrapper_tb
// T1  — STATUS=0 after reset
// T2  — Write enable=1, read CONTROL back
// T3  — INPUT_LEN / OUTPUT_MAX_LEN write/read
// T4  — CFG register byte strobe
// T5  — input_mem write/read
// T6  — output_mem reads 0 before run
// T7  — Known-vector run: 8 quiet + 20 active, check done/counts/no_error
// T8  — Write to output_mem returns SLVERR
// T9  — Read unmapped address returns SLVERR
// T10 — Output overflow: OUTPUT_MAX_LEN=5, overflow_sticky set
// T11 — Soft reset clears all status and counters
// T12 — clr_status_pulse clears done_sticky without full reset

module frac_cfo_sync_bram_test_wrapper_tb;

    // -----------------------------------------------------------------------
    // DUT parameters (small, fast simulation)
    // -----------------------------------------------------------------------
    localparam integer NSC             = 16;
    localparam integer CP_LEN          = 4;
    localparam integer BUF_AW          = 10;
    localparam integer ACC_WIDTH       = 40;
    localparam integer METRIC_WIDTH    = 32;
    localparam integer INDEX_WIDTH     = 9;
    localparam integer RESULT_WIDTH    = 32;
    localparam integer PHASE_WIDTH     = 16;
    localparam integer POWER_WIDTH     = 33;
    localparam integer ENERGY_WIDTH    = 40;
    localparam integer WINDOW_LEN      = 4;
    localparam integer HIT_COUNT       = 2;
    localparam integer THRESHOLD       = 1;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer LATENCY         = 15;
    localparam integer MEM_ADDR_WIDTH  = 10;
    localparam integer TIMEOUT_CYCLES  = 50000;

    localparam integer TOTAL_SAMPLES   = NSC + CP_LEN; // 20

    // -----------------------------------------------------------------------
    // Register byte addresses
    // -----------------------------------------------------------------------
    localparam [15:0] ADDR_CONTROL    = 16'h0000; // [3]=enable [2]=clr_status [1]=soft_reset [0]=start_pulse
    localparam [15:0] ADDR_STATUS     = 16'h0004; // [8]=frm_err [7,1]=done_sticky [6]=overflow [4]=out_done [3]=in_done [2]=running [0]=busy
    localparam [15:0] ADDR_CFG_CFO    = 16'h0008;
    localparam [15:0] ADDR_CFG_TIMING = 16'h000C;
    localparam [15:0] ADDR_CFG_FRAME  = 16'h0010;
    localparam [15:0] ADDR_INPUT_LEN  = 16'h0014;
    localparam [15:0] ADDR_OUT_MAX    = 16'h0018;
    localparam [15:0] ADDR_INPUT_CNT  = 16'h001C;
    localparam [15:0] ADDR_OUTPUT_CNT = 16'h0020;
    localparam [15:0] ADDR_DEBUG      = 16'h0024;
    localparam [15:0] ADDR_ERROR_STAT = 16'h0028;

    // -----------------------------------------------------------------------
    // DUT I/O
    // -----------------------------------------------------------------------
    reg  aclk;
    reg  aresetn;

    reg  [15:0] s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [15:0] s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    // -----------------------------------------------------------------------
    // Task temporaries (module-level — xsim rule: no locals in tasks)
    // -----------------------------------------------------------------------
    reg [31:0] rd_data;
    reg [1:0]  rd_resp;
    reg [1:0]  wr_resp;
    integer    pass_count;
    integer    fail_count;
    integer    poll_cnt;
    integer    i;

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 0;
    always #5 aclk = ~aclk; // 100 MHz

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    frac_cfo_sync_bram_test_wrapper #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .ACC_WIDTH       (ACC_WIDTH),
        .METRIC_WIDTH    (METRIC_WIDTH),
        .INDEX_WIDTH     (INDEX_WIDTH),
        .RESULT_WIDTH    (RESULT_WIDTH),
        .PHASE_WIDTH     (PHASE_WIDTH),
        .POWER_WIDTH     (POWER_WIDTH),
        .ENERGY_WIDTH    (ENERGY_WIDTH),
        .WINDOW_LEN      (WINDOW_LEN),
        .HIT_COUNT       (HIT_COUNT),
        .THRESHOLD       (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .LATENCY         (LATENCY),
        .MEM_ADDR_WIDTH  (MEM_ADDR_WIDTH),
        .TIMEOUT_CYCLES  (TIMEOUT_CYCLES)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready)
    );

    // -----------------------------------------------------------------------
    // AXI-Lite write task (simultaneous AW+W)
    // -----------------------------------------------------------------------
    task axi_write;
        input [15:0] addr;
        input [31:0] data;
        input [3:0]  strb;
        begin
            @(posedge aclk); #1;
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = strb;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            fork
                begin
                    wait (s_axi_awready);
                    @(posedge aclk); #1;
                    s_axi_awvalid = 1'b0;
                end
                begin
                    wait (s_axi_wready);
                    @(posedge aclk); #1;
                    s_axi_wvalid = 1'b0;
                end
            join
            wait (s_axi_bvalid);
            wr_resp = s_axi_bresp;
            @(posedge aclk); #1;
            s_axi_bready = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // AXI-Lite read task (result in rd_data, response in rd_resp)
    // -----------------------------------------------------------------------
    task axi_read;
        input [15:0] addr;
        begin
            @(posedge aclk); #1;
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;
            wait (s_axi_arready);
            @(posedge aclk); #1;
            s_axi_arvalid = 1'b0;
            wait (s_axi_rvalid);
            rd_data = s_axi_rdata;
            rd_resp = s_axi_rresp;
            @(posedge aclk); #1;
            s_axi_rready = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Check helpers
    // -----------------------------------------------------------------------
    task check;
        input [63:0]  got;
        input [63:0]  exp;
        input [255:0] label;
        begin
            if (got === exp) begin
                $display("PASS  %0s: got=%0d exp=%0d", label, got, exp);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  %0s: got=%0d exp=%0d", label, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_hex;
        input [31:0]  got;
        input [31:0]  exp;
        input [255:0] label;
        begin
            if (got === exp) begin
                $display("PASS  %0s: got=0x%08x exp=0x%08x", label, got, exp);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL  %0s: got=0x%08x exp=0x%08x", label, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Soft reset helper: issues soft_reset_pulse (bit[1]=1, all others 0)
    // -----------------------------------------------------------------------
    task do_soft_reset;
        begin
            axi_write(ADDR_CONTROL, 32'h00000002, 4'hF); // bit[1]=soft_reset_pulse
            repeat(4) @(posedge aclk);
        end
    endtask

    // -----------------------------------------------------------------------
    // Load known-vector into input_mem via AXI:
    //   first QUIET_LEN words = 0  (quiet)
    //   next  ACTIVE_LEN words = {Q=0, I=100}
    // -----------------------------------------------------------------------
    task load_known_vector;
        input integer QUIET_LEN;
        input integer ACTIVE_LEN;
        begin
            for (i = 0; i < QUIET_LEN; i = i + 1)
                axi_write(16'h1000 + (i << 2), 32'h00000000, 4'hF);
            for (i = 0; i < ACTIVE_LEN; i = i + 1)
                axi_write(16'h1000 + ((QUIET_LEN + i) << 2),
                          {16'd0, 16'd100}, 4'hF);
        end
    endtask

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        pass_count    = 0;
        fail_count    = 0;
        aresetn       = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axi_awaddr  = 16'd0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'hF;
        s_axi_araddr  = 16'd0;
        rd_data       = 32'd0;
        rd_resp       = 2'd0;
        wr_resp       = 2'd0;
        poll_cnt      = 0;

        repeat(8) @(posedge aclk);
        aresetn = 1'b1;
        repeat(4) @(posedge aclk);

        // ===================================================================
        // T1: STATUS=0 after reset
        // ===================================================================
        $display("\n--- T1: STATUS=0 after reset ---");
        axi_read(ADDR_STATUS);
        check(rd_data, 32'd0, "T1_STATUS_after_reset");

        // ===================================================================
        // T2: Write enable=1, read CONTROL back
        // ===================================================================
        $display("\n--- T2: Write enable=1, read CONTROL ---");
        axi_write(ADDR_CONTROL, 32'h00000008, 4'hF); // bit[3]=enable
        check(wr_resp, 2'd0, "T2_bresp_OKAY");
        axi_read(ADDR_CONTROL);
        check(rd_data[3], 1'b1, "T2_enable_readback");

        // ===================================================================
        // T3: INPUT_LEN and OUTPUT_MAX_LEN write/read
        // ===================================================================
        $display("\n--- T3: INPUT_LEN / OUTPUT_MAX_LEN write/read ---");
        axi_write(ADDR_INPUT_LEN, 32'd28, 4'hF);
        axi_read(ADDR_INPUT_LEN);
        check(rd_data, 32'd28, "T3_INPUT_LEN");
        axi_write(ADDR_OUT_MAX, 32'd20, 4'hF);
        axi_read(ADDR_OUT_MAX);
        check(rd_data, 32'd20, "T3_OUTPUT_MAX_LEN");

        // ===================================================================
        // T4: CFG register byte strobe
        // ===================================================================
        $display("\n--- T4: CFG_CFO_STEP byte strobe ---");
        axi_write(ADDR_CFG_CFO, 32'hDEADBEEF, 4'hF);
        axi_read(ADDR_CFG_CFO);
        check_hex(rd_data, 32'hDEADBEEF, "T4_CFG_CFO_full_write");
        // Write only byte[3] (strb[3]=1 → bits[31:24] only)
        axi_write(ADDR_CFG_CFO, 32'hFF000000, 4'h8);
        axi_read(ADDR_CFG_CFO);
        check_hex(rd_data, 32'hFFADBEEF, "T4_CFG_CFO_byte_strobe");

        // ===================================================================
        // T5: input_mem write/read
        // ===================================================================
        $display("\n--- T5: input_mem write/read ---");
        axi_write(16'h1000, 32'h12345678, 4'hF);
        axi_read(16'h1000);
        check_hex(rd_data, 32'h12345678, "T5_input_mem_rw");

        // ===================================================================
        // T6: output_mem = 0 before run
        // ===================================================================
        $display("\n--- T6: output_mem[0] = 0 before run ---");
        axi_read(16'h2000);
        check(rd_data, 32'd0, "T6_output_mem_before_run");

        // ===================================================================
        // T7: Known-vector run
        //     8 quiet (I=Q=0) + 20 active (I=100, Q=0) = 28 samples
        //     INPUT_LEN=28, OUTPUT_MAX_LEN=20
        //     Expect: done_sticky=1, no frame_error, INPUT_CNT=28, OUTPUT_CNT=20
        // ===================================================================
        $display("\n--- T7: Known-vector run ---");
        do_soft_reset;
        load_known_vector(8, 20);
        axi_write(ADDR_INPUT_LEN, 32'd28, 4'hF);
        axi_write(ADDR_OUT_MAX,   32'd20, 4'hF);
        // Enable + start_pulse in one write
        axi_write(ADDR_CONTROL, 32'h00000009, 4'hF); // bit[3]=enable, bit[0]=start_pulse

        // Poll STATUS.done_sticky (bit[1]) with limit
        poll_cnt = 0;
        rd_data  = 32'h0;
        while (!rd_data[1] && poll_cnt < 20000) begin
            repeat(10) @(posedge aclk);
            axi_read(ADDR_STATUS);
            poll_cnt = poll_cnt + 1;
        end
        $display("T7: STATUS=0x%08x polls=%0d", rd_data, poll_cnt);

        check(rd_data[1], 1'b1, "T7_done_sticky");
        check(rd_data[8], 1'b0, "T7_no_frame_error");

        axi_read(ADDR_INPUT_CNT);
        check(rd_data, 32'd28, "T7_INPUT_COUNT");

        axi_read(ADDR_OUTPUT_CNT);
        check(rd_data, 32'd20, "T7_OUTPUT_COUNT");

        // Verify output_mem read is accessible (OKAY response)
        axi_read(16'h2000);
        check(rd_resp, 2'd0, "T7_output_mem_read_OKAY");

        // ===================================================================
        // T8: Write to output_mem → SLVERR
        // ===================================================================
        $display("\n--- T8: Write output_mem → SLVERR ---");
        axi_write(16'h2000, 32'hDEAD, 4'hF);
        check(wr_resp, 2'b10, "T8_output_mem_write_SLVERR");

        // ===================================================================
        // T9: Read unmapped address → SLVERR
        // ===================================================================
        $display("\n--- T9: Read unmapped address → SLVERR ---");
        axi_read(16'h3000);
        check(rd_resp, 2'b10, "T9_unmapped_read_SLVERR");

        // ===================================================================
        // T10: Output overflow
        //      Same vector but OUTPUT_MAX_LEN=5 → overflow_sticky=1,
        //      output_count capped at 5
        // ===================================================================
        $display("\n--- T10: Output overflow ---");
        do_soft_reset;
        load_known_vector(8, 20);
        axi_write(ADDR_INPUT_LEN, 32'd28, 4'hF);
        axi_write(ADDR_OUT_MAX,   32'd5,  4'hF);
        axi_write(ADDR_CONTROL, 32'h00000009, 4'hF);

        poll_cnt = 0;
        rd_data  = 32'h0;
        while (!rd_data[1] && poll_cnt < 20000) begin
            repeat(10) @(posedge aclk);
            axi_read(ADDR_STATUS);
            poll_cnt = poll_cnt + 1;
        end
        $display("T10: STATUS=0x%08x polls=%0d", rd_data, poll_cnt);

        check(rd_data[6], 1'b1, "T10_overflow_sticky");
        axi_read(ADDR_OUTPUT_CNT);
        check(rd_data, 32'd5, "T10_output_count_capped");

        // ===================================================================
        // T11: Soft reset clears all status and counters
        // ===================================================================
        $display("\n--- T11: Soft reset clears status ---");
        do_soft_reset;
        axi_read(ADDR_STATUS);
        check(rd_data, 32'd0, "T11_STATUS_after_softreset");
        axi_read(ADDR_INPUT_CNT);
        check(rd_data, 32'd0, "T11_INPUT_CNT_after_softreset");
        axi_read(ADDR_OUTPUT_CNT);
        check(rd_data, 32'd0, "T11_OUTPUT_CNT_after_softreset");

        // ===================================================================
        // T12: clr_status_pulse clears done_sticky (without DUT reset)
        // ===================================================================
        $display("\n--- T12: clr_status_pulse clears done_sticky ---");
        // Run again to get done_sticky=1
        load_known_vector(8, 20);
        axi_write(ADDR_INPUT_LEN, 32'd28, 4'hF);
        axi_write(ADDR_OUT_MAX,   32'd20, 4'hF);
        axi_write(ADDR_CONTROL, 32'h00000009, 4'hF);

        poll_cnt = 0;
        rd_data  = 32'h0;
        while (!rd_data[1] && poll_cnt < 20000) begin
            repeat(10) @(posedge aclk);
            axi_read(ADDR_STATUS);
            poll_cnt = poll_cnt + 1;
        end
        check(rd_data[1], 1'b1, "T12_done_sticky_before_clr");

        // Issue clr_status_pulse (bit[2]=1, enable=0)
        axi_write(ADDR_CONTROL, 32'h00000004, 4'hF);
        repeat(4) @(posedge aclk);

        axi_read(ADDR_STATUS);
        check(rd_data[1], 1'b0, "T12_done_sticky_after_clr");

        // ===================================================================
        // Summary
        // ===================================================================
        repeat(4) @(posedge aclk);
        $display("\n=========================");
        $display("PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("=========================");
        $finish;
    end

    // Watchdog: 50 ms simulation limit
    initial begin
        #50000000;
        $display("WATCHDOG TIMEOUT at %0t ns", $time);
        $finish;
    end

endmodule
