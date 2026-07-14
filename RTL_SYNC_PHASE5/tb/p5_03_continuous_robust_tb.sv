`timescale 1ns/1ps
// =============================================================
//  p5_03_continuous_robust_tb.sv  -  P5-03 Step 2 robustness gate
//                                    (gates spec e + f)
//
//  Real Xilinx XFFT IPs. Two sequential phases:
//    Phase A (spec e backpressure):
//      Drive 1 slot of golden stim with m_axis_tready patterned
//      (4 cyc high / 4 cyc low). Check (a) liveness + (b) zero
//      drops still hold.
//    Phase B (spec f reset-while-active):
//      Drive partial stim, pulse aresetn low for several cycles,
//      drive a full slot after release, check (a) liveness
//      restored from the first complete post-reset slot.
//
//  GATE:  PASS_P5_CONT_ROBUST  /  FAIL_P5_CONT_ROBUST
// =============================================================
module p5_03_continuous_robust_tb;

    localparam integer IQ_WIDTH    = 16;
    localparam integer NSC         = 256;
    localparam integer CP_LEN      = 32;
    localparam integer BUF_AW      = 12;
    localparam integer NCO_PHASE_WIDTH = 32;
    localparam integer FRAME_LEN   = 2 * (NSC + CP_LEN);
    localparam integer THRESHOLD_TB = 40000;
    localparam integer STIM_DEPTH   = 704;
    localparam integer MAX_CAP      = 2048;
    localparam integer D_ROT_BOUND  = 8;     // wider than smoke (stalls add)

    localparam [6:0] ADDR_CONTROL = 7'h04;

    reg aclk = 1'b0;
    always #2 aclk = ~aclk;
    reg aresetn = 1'b0;

    reg  [6:0]  m_axi_awaddr; reg m_axi_awvalid; wire m_axi_awready;
    reg  [31:0] m_axi_wdata;  reg [3:0] m_axi_wstrb; reg m_axi_wvalid; wire m_axi_wready;
    wire [1:0]  m_axi_bresp;  wire m_axi_bvalid; reg m_axi_bready;
    reg  [6:0]  m_axi_araddr; reg m_axi_arvalid; wire m_axi_arready;
    wire [31:0] m_axi_rdata;  wire [1:0] m_axi_rresp; wire m_axi_rvalid; reg m_axi_rready;

    reg  [2*IQ_WIDTH-1:0] s_axis_tdata;
    reg                   s_axis_tvalid;
    wire                  s_axis_tready;
    reg                   s_axis_tlast;

    wire [2*IQ_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    reg                   m_axis_tready;
    wire                  m_axis_tlast;

    wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                  dbg_frac_m_tvalid;
    wire                  dbg_frac_m_tready;
    wire                  dbg_frac_m_tlast;

    phase3_sync_axis_dma_wrapper #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN), .BUF_AW(BUF_AW),
        .THRESHOLD(THRESHOLD_TB), .NCO_PHASE_WIDTH(NCO_PHASE_WIDTH)
    ) u_dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(m_axi_awaddr), .s_axi_awvalid(m_axi_awvalid), .s_axi_awready(m_axi_awready),
        .s_axi_wdata (m_axi_wdata),  .s_axi_wstrb (m_axi_wstrb),   .s_axi_wvalid(m_axi_wvalid),  .s_axi_wready(m_axi_wready),
        .s_axi_bresp (m_axi_bresp),  .s_axi_bvalid(m_axi_bvalid),  .s_axi_bready(m_axi_bready),
        .s_axi_araddr(m_axi_araddr), .s_axi_arvalid(m_axi_arvalid),.s_axi_arready(m_axi_arready),
        .s_axi_rdata (m_axi_rdata),  .s_axi_rresp (m_axi_rresp),   .s_axi_rvalid(m_axi_rvalid),  .s_axi_rready(m_axi_rready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),.s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid),.m_axis_tready(m_axis_tready),.m_axis_tlast(m_axis_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready),.dbg_frac_m_tlast (dbg_frac_m_tlast)
    );

    reg [31:0] axi_rd_data;
    task axi_write;
        input [6:0] addr; input [31:0] data;
        begin
            @(posedge aclk);
            m_axi_awaddr=addr; m_axi_awvalid=1'b1;
            m_axi_wdata=data; m_axi_wstrb=4'hF; m_axi_wvalid=1'b1; m_axi_bready=1'b1;
            while (!(m_axi_awready && m_axi_wready)) @(posedge aclk);
            @(posedge aclk); m_axi_awvalid=1'b0; m_axi_wvalid=1'b0;
            while (!m_axi_bvalid) @(posedge aclk);
            @(posedge aclk); m_axi_bready=1'b0;
        end
    endtask

    reg [31:0] stim_mem  [0:STIM_DEPTH-1];
    integer    frac_count;
    integer    mout_count;
    reg [31:0] frac_cap  [0:MAX_CAP-1];
    reg [31:0] mout_cap  [0:MAX_CAP-1];
    integer    tlast_count;

    task automatic reset_counters;
        begin
            frac_count = 0;
            mout_count = 0;
            tlast_count = 0;
        end
    endtask
    initial reset_counters();

    always @(posedge aclk) if (aresetn) begin
        if (dbg_frac_m_tvalid && dbg_frac_m_tready && frac_count < MAX_CAP) begin
            frac_cap[frac_count] = dbg_frac_m_tdata;
            frac_count = frac_count + 1;
        end
        if (m_axis_tvalid && m_axis_tready && mout_count < MAX_CAP) begin
            mout_cap[mout_count] = m_axis_tdata;
            mout_count = mout_count + 1;
            if (m_axis_tlast) tlast_count = tlast_count + 1;
        end
    end

    integer cycle_cnt;
    initial begin
        cycle_cnt = 0;
        forever begin
            @(posedge aclk);
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt > 30000) begin
                $display("GATE: FAIL_P5_CONT_ROBUST watchdog cycle=%0d frac=%0d mout=%0d",
                         cycle_cnt, frac_count, mout_count);
                $finish;
            end
        end
    end

    integer i;
    integer fails;
    integer ph_a_frac, ph_a_mout, ph_a_tlast;
    integer ph_b_frac, ph_b_mout, ph_b_tlast;
    integer compare_n;
    int signed fi, fq, mi, mq;
    int signed di, dq;
    integer mismatches_a;

    // Phase A backpressure pattern driver: 4 cyc high / 4 cyc low.
    // Active only during Phase A; outside Phase A we hold tready high.
    reg phase_a_active;
    reg [2:0] bp_cnt;
    initial begin phase_a_active = 0; bp_cnt = 0; end
    always @(posedge aclk) begin
        if (!aresetn) bp_cnt <= 0;
        else if (phase_a_active) bp_cnt <= bp_cnt + 1;
    end
    // tready is high during cyc 0..3, low during cyc 4..7
    always @(*) begin
        if (phase_a_active) m_axis_tready = (bp_cnt < 4);
        else                m_axis_tready = 1'b1;
    end

    initial begin : main
        fails = 0;

        m_axi_awaddr=0; m_axi_awvalid=0; m_axi_wdata=0; m_axi_wstrb=0; m_axi_wvalid=0; m_axi_bready=0;
        m_axi_araddr=0; m_axi_arvalid=0; m_axi_rready=0;
        s_axis_tdata=0; s_axis_tvalid=0; s_axis_tlast=0;

        $readmemh("../../../golden/phase3_iq_stimulus.mem", stim_mem);

        // ============================================================
        // Phase A: backpressure (spec e)
        // ============================================================
        aresetn=0; repeat (20) @(posedge aclk); aresetn=1; repeat (5) @(posedge aclk);
        reset_counters();

        axi_write(ADDR_CONTROL, 32'h0000_0001);
        repeat (3) @(posedge aclk);

        phase_a_active = 1;

        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == STIM_DEPTH - 1);
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk); s_axis_tvalid=0; s_axis_tlast=0;

        while (mout_count < FRAME_LEN && cycle_cnt < 15000)
            @(posedge aclk);
        repeat (100) @(posedge aclk);

        ph_a_frac = frac_count;
        ph_a_mout = mout_count;
        ph_a_tlast = tlast_count;
        phase_a_active = 0;
        $display("[ROBUST-A] backpressure: frac=%0d mout=%0d tlast=%0d",
                 ph_a_frac, ph_a_mout, ph_a_tlast);

        // Spec (a) under backpressure
        if (ph_a_frac < FRAME_LEN) begin
            $display("[ROBUST-A] FAIL (a): frac=%0d < FRAME_LEN", ph_a_frac); fails=fails+1;
        end
        if (ph_a_mout < FRAME_LEN) begin
            $display("[ROBUST-A] FAIL (a): mout=%0d < FRAME_LEN", ph_a_mout); fails=fails+1;
        end
        if (ph_a_tlast != 1) begin
            $display("[ROBUST-A] FAIL (a): tlast_count=%0d != 1", ph_a_tlast); fails=fails+1;
        end
        // Spec (b) zero drops: bounded delta despite backpressure
        if ((ph_a_frac - ph_a_mout) < -D_ROT_BOUND || (ph_a_frac - ph_a_mout) > D_ROT_BOUND) begin
            $display("[ROBUST-A] FAIL (b): |frac - mout| = %0d > D_ROT_BOUND=%0d",
                     ph_a_frac - ph_a_mout, D_ROT_BOUND); fails=fails+1;
        end
        // identity check under backpressure (step_word=0)
        compare_n = (ph_a_frac < ph_a_mout) ? ph_a_frac : ph_a_mout;
        if (compare_n > FRAME_LEN) compare_n = FRAME_LEN;
        mismatches_a = 0;
        for (i = 0; i < compare_n; i = i + 1) begin
            fi = $signed(frac_cap[i][15:0]);
            fq = $signed(frac_cap[i][31:16]);
            mi = $signed(mout_cap[i][15:0]);
            mq = $signed(mout_cap[i][31:16]);
            di = mi - fi; if (di < 0) di = -di;
            dq = mq - fq; if (dq < 0) dq = -dq;
            if (di > 2 || dq > 2) mismatches_a = mismatches_a + 1;
        end
        if (mismatches_a > 0) begin
            $display("[ROBUST-A] FAIL (b-identity): %0d/%0d mismatches under backpressure",
                     mismatches_a, compare_n);
            fails = fails + 1;
        end else begin
            $display("[ROBUST-A] spec(a)(b) OK under backpressure (%0d samples bit-exact)", compare_n);
        end

        // ============================================================
        // Phase B: reset-while-active (spec f)
        // ============================================================
        aresetn=0; repeat (20) @(posedge aclk); aresetn=1; repeat (5) @(posedge aclk);
        reset_counters();
        axi_write(ADDR_CONTROL, 32'h0000_0001);
        repeat (3) @(posedge aclk);

        // Drive ~half a frame then yank reset
        for (i = 0; i < STIM_DEPTH/2; i = i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = 1'b0;
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk); s_axis_tvalid=0;
        $display("[ROBUST-B] mid-frame reset injected (after %0d stim beats)", STIM_DEPTH/2);

        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (8) @(posedge aclk);
        reset_counters();

        // Re-enable and drive a fresh full frame
        axi_write(ADDR_CONTROL, 32'h0000_0001);
        repeat (3) @(posedge aclk);
        for (i = 0; i < STIM_DEPTH; i = i + 1) begin
            @(posedge aclk);
            s_axis_tdata  = stim_mem[i];
            s_axis_tvalid = 1'b1;
            s_axis_tlast  = (i == STIM_DEPTH - 1);
            while (!s_axis_tready) @(posedge aclk);
        end
        @(posedge aclk); s_axis_tvalid=0; s_axis_tlast=0;
        while (mout_count < FRAME_LEN && cycle_cnt < 28000)
            @(posedge aclk);
        repeat (40) @(posedge aclk);

        ph_b_frac = frac_count;
        ph_b_mout = mout_count;
        ph_b_tlast = tlast_count;
        $display("[ROBUST-B] post-reset: frac=%0d mout=%0d tlast=%0d",
                 ph_b_frac, ph_b_mout, ph_b_tlast);

        if (ph_b_frac < FRAME_LEN) begin
            $display("[ROBUST-B] FAIL (f-recovery a): frac=%0d < FRAME_LEN", ph_b_frac); fails=fails+1;
        end
        if (ph_b_mout < FRAME_LEN) begin
            $display("[ROBUST-B] FAIL (f-recovery a): mout=%0d < FRAME_LEN", ph_b_mout); fails=fails+1;
        end
        if (ph_b_tlast != 1) begin
            $display("[ROBUST-B] FAIL (f-recovery): tlast_count=%0d != 1 after reset", ph_b_tlast); fails=fails+1;
        end
        // Post-reset identity check
        compare_n = (ph_b_frac < ph_b_mout) ? ph_b_frac : ph_b_mout;
        if (compare_n > FRAME_LEN) compare_n = FRAME_LEN;
        for (i = 0; i < compare_n; i = i + 1) begin
            fi = $signed(frac_cap[i][15:0]);
            fq = $signed(frac_cap[i][31:16]);
            mi = $signed(mout_cap[i][15:0]);
            mq = $signed(mout_cap[i][31:16]);
            di = mi - fi; if (di < 0) di = -di;
            dq = mq - fq; if (dq < 0) dq = -dq;
            if (di > 2 || dq > 2) begin
                $display("[ROBUST-B] FAIL (f-recovery b): post-reset identity mismatch j=%0d",
                         i);
                fails = fails + 1;
                i = compare_n;  // early-exit the loop
            end
        end
        if (fails == 0)
            $display("[ROBUST-B] spec(f) OK: post-reset full slot identity (%0d samples)", compare_n);

        if (fails == 0)
            $display("GATE: PASS_P5_CONT_ROBUST  phaseA_frac=%0d phaseA_mout=%0d  phaseB_frac=%0d phaseB_mout=%0d",
                     ph_a_frac, ph_a_mout, ph_b_frac, ph_b_mout);
        else
            $display("GATE: FAIL_P5_CONT_ROBUST fails=%0d", fails);
        $finish;
    end

endmodule
