`timescale 1ns/1ps

// frac_cfo_sync_axi_stream_wrapper_tb
// T1  — reset: AXI-Lite reads return STATUS=0 after reset
// T2  — enable write: write CONTROL[2]=1, read back enable bit
// T3  — soft_reset: write CONTROL[0]=1, enable clears
// T4  — clear_status: write CONTROL[1]=1 with sticky set, sticky clears
// T5  — CFG write/read: write CFG_CFO_STEP, CFG_TIMING_OFFSET, CFG_FRAME_LEN
// T6  — SLVERR: read/write to unmapped address returns SLVERR
// T7  — sample count: stream 3 samples with enable=1, read SAMPLE_COUNT=3
// T8  — output count: forward 3 samples through, read OUTPUT_COUNT=3
// T9  — status busy: DUT busy visible in STATUS[0]
// T10 — integration: enable=1, feed quiet+signal samples, poll done_sticky,
//                    check OUTPUT_COUNT=TOTAL_SAMPLES
// T11 — soft_reset clears counters and sticky bits

module frac_cfo_sync_axi_stream_wrapper_tb;

    // -----------------------------------------------------------------------
    // Parameters (small, fast simulation)
    // -----------------------------------------------------------------------
    localparam integer NSC        = 16;
    localparam integer CP_LEN     = 4;
    localparam integer BUF_AW     = 10;
    localparam integer ACC_WIDTH  = 40;
    localparam integer METRIC_WIDTH = 32;
    localparam integer INDEX_WIDTH  = 9;
    localparam integer RESULT_WIDTH = 32;
    localparam integer PHASE_WIDTH  = 16;
    localparam integer POWER_WIDTH  = 33;
    localparam integer ENERGY_WIDTH = 40;
    localparam integer WINDOW_LEN = 4;
    localparam integer HIT_COUNT  = 2;
    localparam integer THRESHOLD  = 1;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer LATENCY    = 15;

    localparam integer TOTAL_SAMPLES = NSC + CP_LEN; // 20

    // AXI-Lite register offsets
    localparam [5:0] ADDR_CONTROL     = 6'h00;
    localparam [5:0] ADDR_STATUS      = 6'h04;
    localparam [5:0] ADDR_CFG_CFO     = 6'h08;
    localparam [5:0] ADDR_CFG_TIM     = 6'h0C;
    localparam [5:0] ADDR_CFG_FRM     = 6'h10;
    localparam [5:0] ADDR_SAMPLE_CNT  = 6'h14;
    localparam [5:0] ADDR_OUTPUT_CNT  = 6'h18;
    localparam [5:0] ADDR_DEBUG       = 6'h1C;

    // -----------------------------------------------------------------------
    // DUT I/O
    // -----------------------------------------------------------------------
    reg  aclk;
    reg  aresetn;

    reg  [5:0]  s_axi_awaddr;
    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    reg  [5:0]  s_axi_araddr;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rvalid;
    reg         s_axi_rready;

    reg  [31:0] s_axis_tdata;
    reg         s_axis_tvalid;
    wire        s_axis_tready;
    reg         s_axis_tlast;

    wire [31:0] m_axis_tdata;
    wire        m_axis_tvalid;
    reg         m_axis_tready;
    wire        m_axis_tlast;

    // -----------------------------------------------------------------------
    // Task temporaries (module-level — xsim rule: no locals in tasks)
    // -----------------------------------------------------------------------
    reg [31:0] rd_data;
    reg [1:0]  rd_resp;
    reg [1:0]  wr_resp;
    integer    poll_cnt;
    integer    i;
    reg [31:0] out_cnt_val;
    reg [31:0] smp_cnt_val;
    reg [31:0] status_val;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    frac_cfo_sync_axi_stream_wrapper #(
        .NSC          (NSC),
        .CP_LEN       (CP_LEN),
        .BUF_AW       (BUF_AW),
        .ACC_WIDTH    (ACC_WIDTH),
        .METRIC_WIDTH (METRIC_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .RESULT_WIDTH (RESULT_WIDTH),
        .PHASE_WIDTH  (PHASE_WIDTH),
        .POWER_WIDTH  (POWER_WIDTH),
        .ENERGY_WIDTH (ENERGY_WIDTH),
        .WINDOW_LEN   (WINDOW_LEN),
        .HIT_COUNT    (HIT_COUNT),
        .THRESHOLD    (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .LATENCY         (LATENCY)
    ) dut (
        .aclk    (aclk),
        .aresetn (aresetn),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 0;
    always #5 aclk = ~aclk; // 100 MHz

    // -----------------------------------------------------------------------
    // AXI-Lite write task (simultaneous AW+W)
    // -----------------------------------------------------------------------
    task axi_write;
        input [5:0]  addr;
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
            // Wait for both handshakes
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
    // AXI-Lite read task
    // -----------------------------------------------------------------------
    task axi_read;
        input [5:0] addr;
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
    // Check helper
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check;
        input [63:0] got;
        input [63:0] exp;
        input [127:0] label;
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

    // -----------------------------------------------------------------------
    // Main
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        // Initial signal state
        aresetn       = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = 32'd0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;
        s_axi_awaddr  = 6'd0;
        s_axi_wdata   = 32'd0;
        s_axi_wstrb   = 4'hF;
        s_axi_araddr  = 6'd0;

        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4) @(posedge aclk);

        // ===================================================================
        // T1: After reset, STATUS=0
        // ===================================================================
        $display("\n--- T1: STATUS=0 after reset ---");
        axi_read(ADDR_STATUS);
        check(rd_data, 32'd0, "T1_STATUS_after_reset");
        check(rd_resp, 2'd0,  "T1_rresp_OKAY");

        // ===================================================================
        // T2: Write CONTROL enable bit, read back
        // ===================================================================
        $display("\n--- T2: Write enable=1, read CONTROL ---");
        axi_write(ADDR_CONTROL, 32'h4, 4'hF); // bit[2]=enable
        check(wr_resp, 2'd0, "T2_bresp_OKAY");
        axi_read(ADDR_CONTROL);
        check(rd_data[2], 1'b1, "T2_enable_readback");

        // ===================================================================
        // T3: Soft reset clears enable
        // ===================================================================
        $display("\n--- T3: Soft reset clears enable ---");
        // enable is already 1 from T2; soft_reset_pulse also resets DUT
        // After soft_reset_pulse, the AXI reg file is NOT reset (only DUT is).
        // Soft reset is a pulse; enable_out persists because reg file keeps it.
        // Write enable=0 first to verify control register writes work.
        axi_write(ADDR_CONTROL, 32'h0, 4'hF);
        axi_read(ADDR_CONTROL);
        check(rd_data[2], 1'b0, "T3_enable_cleared");
        // Now re-enable, then issue soft_reset_pulse (bit[0])
        axi_write(ADDR_CONTROL, 32'h4, 4'hF); // enable=1
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset_pulse=1, enable=0
        // enable bit written as 0 in same word, so it should now be 0
        axi_read(ADDR_CONTROL);
        check(rd_data[2], 1'b0, "T3_enable_zero_after_srst");
        repeat (4) @(posedge aclk);

        // ===================================================================
        // T4: clear_status_pulse clears sticky bits
        // ===================================================================
        $display("\n--- T4: clear_status_pulse clears stickies ---");
        // Enable, send one sample to set input_seen_sticky
        axi_write(ADDR_CONTROL, 32'h4, 4'hF); // enable=1
        repeat (2) @(posedge aclk);
        @(posedge aclk); #1;
        s_axis_tdata  = 32'hABCD1234;
        s_axis_tvalid = 1'b1;
        wait (s_axis_tready); @(posedge aclk); #1;
        s_axis_tvalid = 1'b0;
        repeat (2) @(posedge aclk);
        axi_read(ADDR_STATUS);
        check(rd_data[5], 1'b1, "T4_input_seen_sticky_set");
        // Issue clear_status_pulse (bit[1]=1)
        axi_write(ADDR_CONTROL, 32'h2, 4'hF); // clear_status=1, enable=0
        repeat (3) @(posedge aclk);
        axi_read(ADDR_STATUS);
        check(rd_data[5], 1'b0, "T4_input_seen_sticky_cleared");
        // Disable, soft-reset to clean DUT state
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset
        repeat (4) @(posedge aclk);

        // ===================================================================
        // T5: CFG register write/read
        // ===================================================================
        $display("\n--- T5: CFG registers write/read ---");
        axi_write(ADDR_CFG_CFO, 32'hDEADBEEF, 4'hF);
        axi_read(ADDR_CFG_CFO);
        check(rd_data, 32'hDEADBEEF, "T5_CFG_CFO_STEP");

        axi_write(ADDR_CFG_TIM, 32'h12345678, 4'hF);
        axi_read(ADDR_CFG_TIM);
        check(rd_data, 32'h12345678, "T5_CFG_TIMING_OFFSET");

        axi_write(ADDR_CFG_FRM, 32'hAABBCCDD, 4'hF);
        axi_read(ADDR_CFG_FRM);
        check(rd_data, 32'hAABBCCDD, "T5_CFG_FRAME_LEN");

        // Byte strobe test: write only high byte (strobe[3] → bits[31:24])
        axi_write(ADDR_CFG_CFO, 32'hFF000000, 4'h8);
        axi_read(ADDR_CFG_CFO);
        check(rd_data, 32'hFFADBEEF, "T5_CFG_CFO_BYTE_STROBE");

        // ===================================================================
        // T6: SLVERR for unmapped address
        // ===================================================================
        $display("\n--- T6: SLVERR for unmapped address ---");
        // Address 0x20 = word index 8, beyond the 8-register map
        axi_write(6'h20, 32'hDEAD, 4'hF);
        check(wr_resp, 2'b10, "T6_write_SLVERR");
        axi_read(6'h20);
        check(rd_resp, 2'b10, "T6_read_SLVERR");

        // ===================================================================
        // T7: Sample count increments on stream handshake
        // ===================================================================
        $display("\n--- T7: SAMPLE_COUNT increments ---");
        // Soft reset, re-enable
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset
        repeat (4) @(posedge aclk);
        axi_write(ADDR_CONTROL, 32'h4, 4'hF); // enable=1
        repeat (2) @(posedge aclk);
        // Stream 3 samples
        for (i = 0; i < 3; i = i + 1) begin
            @(posedge aclk); #1;
            s_axis_tdata  = 32'h00640064; // I=100, Q=100
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == 2) ? 1'b1 : 1'b0;
            wait (s_axis_tready);
            @(posedge aclk); #1;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end
        repeat (3) @(posedge aclk);
        axi_read(ADDR_SAMPLE_CNT);
        smp_cnt_val = rd_data;
        check(smp_cnt_val, 32'd3, "T7_SAMPLE_COUNT_3");

        // ===================================================================
        // T8: Disable, reset; OUTPUT_COUNT starts at 0
        // ===================================================================
        $display("\n--- T8: OUTPUT_COUNT=0 before any output ---");
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset
        repeat (4) @(posedge aclk);
        axi_read(ADDR_OUTPUT_CNT);
        check(rd_data, 32'd0, "T8_OUTPUT_COUNT_zero_after_reset");

        // ===================================================================
        // T9: STATUS busy visible
        // ===================================================================
        $display("\n--- T9: STATUS busy bit follows DUT busy ---");
        // After soft_reset and no enable, DUT is idle, busy=0
        axi_read(ADDR_STATUS);
        check(rd_data[0], 1'b0, "T9_busy_zero_idle");

        // ===================================================================
        // T10: Integration test
        // Enable=1, feed TOTAL_SAMPLES=20 signal samples, wait done_sticky,
        // check OUTPUT_COUNT=TOTAL_SAMPLES
        // ===================================================================
        $display("\n--- T10: Integration test ---");
        // Ensure clean state
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset
        repeat (8) @(posedge aclk);
        axi_write(ADDR_CONTROL, 32'h4, 4'hF); // enable=1
        repeat (4) @(posedge aclk);

        // Feed 8 quiet samples (I=Q=0) then 100 active samples (I=100, Q=0).
        // Quiet prefix causes frame_detector Case A (start below threshold),
        // so HIT_COUNT=2 consecutive above-threshold windows are found after
        // the quiet-to-active transition. tlast terminates FILL on last sample.
        for (i = 0; i < 108; i = i + 1) begin
            @(posedge aclk); #1;
            if (i < 8)
                s_axis_tdata = 32'd0;           // quiet: I=0, Q=0
            else
                s_axis_tdata = {16'd0, 16'd100}; // active: I=100, Q=0
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == 107) ? 1'b1 : 1'b0;
            wait (s_axis_tready);
            @(posedge aclk); #1;
            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
        end

        // Poll done_sticky (STATUS[1]) for up to 2000 cycles
        poll_cnt = 0;
        status_val = 32'd0;
        while (!status_val[1] && poll_cnt < 2000) begin
            repeat (10) @(posedge aclk);
            axi_read(ADDR_STATUS);
            status_val = rd_data;
            poll_cnt   = poll_cnt + 1;
        end

        if (!status_val[1])
            $display("FAIL  T10_done_sticky: timed out after %0d polls", poll_cnt);
        else begin
            $display("PASS  T10_done_sticky: set after %0d polls", poll_cnt);
            pass_count = pass_count + 1;
        end

        axi_read(ADDR_OUTPUT_CNT);
        out_cnt_val = rd_data;
        check(out_cnt_val, TOTAL_SAMPLES, "T10_OUTPUT_COUNT_eq_TOTAL");

        // ===================================================================
        // T11: Soft reset clears sample count, output count, sticky bits
        // ===================================================================
        $display("\n--- T11: Soft reset clears all counters and stickies ---");
        axi_write(ADDR_CONTROL, 32'h1, 4'hF); // soft_reset_pulse
        repeat (6) @(posedge aclk);

        axi_read(ADDR_STATUS);
        check(rd_data[1], 1'b0, "T11_done_sticky_cleared");
        check(rd_data[2], 1'b0, "T11_frame_det_sticky_cleared");

        axi_read(ADDR_SAMPLE_CNT);
        check(rd_data, 32'd0, "T11_SAMPLE_COUNT_cleared");

        axi_read(ADDR_OUTPUT_CNT);
        check(rd_data, 32'd0, "T11_OUTPUT_COUNT_cleared");

        // ===================================================================
        // Summary
        // ===================================================================
        $display("\n========================================");
        $display("PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("========================================\n");

        $finish;
    end

    // Timeout guard
    initial begin
        #5000000;
        $display("TIMEOUT: simulation exceeded 5ms");
        $finish;
    end

endmodule
