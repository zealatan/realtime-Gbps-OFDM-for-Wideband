`timescale 1ns/1ps
`default_nettype none

module tb_dma_wrapper;

    // =========================================================================
    // Parameters
    // =========================================================================
    localparam integer C_AXIS_TDATA_WIDTH = 32;
    localparam integer C_ADDER_BIT_WIDTH  = 32;
    localparam integer C_AXIS_TID_WIDTH   = 1;
    localparam integer C_AXIS_TDEST_WIDTH = 1;
    localparam integer C_AXIS_TUSER_WIDTH = 1;
    localparam integer FIFO_DEPTH         = 2048;
    localparam integer FIFO_ADDR_W        = 11;

    localparam integer INPUT_SAMPLE_NUM   = 2560;

    // =========================================================================
    // DUT I/O
    // =========================================================================
    reg                              aclk;
    reg                              aresetn;

    reg  [C_ADDER_BIT_WIDTH-1:0]     ctrl_constant;

    // AXIS Slave (IN)
    reg                              s_axis_tvalid;
    wire                             s_axis_tready;
    reg  [C_AXIS_TDATA_WIDTH-1:0]    s_axis_tdata;
    reg  [C_AXIS_TDATA_WIDTH/8-1:0]  s_axis_tkeep;
    reg  [C_AXIS_TDATA_WIDTH/8-1:0]  s_axis_tstrb;
    reg                              s_axis_tlast;
    reg  [C_AXIS_TID_WIDTH-1:0]      s_axis_tid;
    reg  [C_AXIS_TDEST_WIDTH-1:0]    s_axis_tdest;
    reg  [C_AXIS_TUSER_WIDTH-1:0]    s_axis_tuser;

    // AXIS Master (OUT)
    wire                             m_axis_tvalid;
    reg                              m_axis_tready;
    wire [C_AXIS_TDATA_WIDTH-1:0]    m_axis_tdata;
    wire [C_AXIS_TDATA_WIDTH/8-1:0]  m_axis_tkeep;
    wire [C_AXIS_TDATA_WIDTH/8-1:0]  m_axis_tstrb;
    wire                             m_axis_tlast;
    wire [C_AXIS_TID_WIDTH-1:0]      m_axis_tid;
    wire [C_AXIS_TDEST_WIDTH-1:0]    m_axis_tdest;
    wire [C_AXIS_TUSER_WIDTH-1:0]    m_axis_tuser;

    // =========================================================================
    // FILE HANDLE
    // =========================================================================
    integer fp_metric;

    // =========================================================================
    // DUT
    // =========================================================================
    dma_wrapper #(
        .C_AXIS_TDATA_WIDTH (C_AXIS_TDATA_WIDTH),
        .C_ADDER_BIT_WIDTH  (C_ADDER_BIT_WIDTH),
        .C_AXIS_TID_WIDTH   (C_AXIS_TID_WIDTH),
        .C_AXIS_TDEST_WIDTH (C_AXIS_TDEST_WIDTH),
        .C_AXIS_TUSER_WIDTH (C_AXIS_TUSER_WIDTH),
        .FIFO_DEPTH         (FIFO_DEPTH),
        .FIFO_ADDR_W        (FIFO_ADDR_W)
    ) dut (
        .aclk               (aclk),
        .aresetn            (aresetn),

        .ctrl_constant      (ctrl_constant),

        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tkeep       (s_axis_tkeep),
        .s_axis_tstrb       (s_axis_tstrb),
        .s_axis_tlast       (s_axis_tlast),
        .s_axis_tid         (s_axis_tid),
        .s_axis_tdest       (s_axis_tdest),
        .s_axis_tuser       (s_axis_tuser),

        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tkeep       (m_axis_tkeep),
        .m_axis_tstrb       (m_axis_tstrb),
        .m_axis_tlast       (m_axis_tlast),
        .m_axis_tid         (m_axis_tid),
        .m_axis_tdest       (m_axis_tdest),
        .m_axis_tuser       (m_axis_tuser)
    );

    // =========================================================================
    // Clock
    // =========================================================================
    initial begin
        aclk = 1'b0;
        forever #5 aclk = ~aclk;
    end

    // =========================================================================
    // FILE OPEN
    // =========================================================================
    initial begin
        fp_metric = $fopen("metric_dump.csv", "w");
        if (fp_metric == 0) begin
            $display("ERROR: cannot open file");
            $finish;
        end

        // CSV header
        $fwrite(fp_metric, "time,metric 32bit,metric 34bit \n");
    end

    // =========================================================================
    // Counters
    // =========================================================================
    integer in_count;
    integer out_count;

    always @(posedge aclk) begin
        if (!aresetn) begin
            in_count  <= 0;
            out_count <= 0;
        end else begin
            if (s_axis_tvalid && s_axis_tready) begin
                in_count <= in_count + 1;
            end

            if (m_axis_tvalid && m_axis_tready) begin
                out_count <= out_count + 1;
            end
        end
    end

    // =========================================================================
    // 🔥 METRIC DUMP (핵심)
    // =========================================================================
    always @(posedge aclk) begin
        if (aresetn) begin
            if (dut.debug_vdb_metric_stb) begin

                $display("[%0t] debug_vdb_metric_stb (32 bit) = %0d debug_vdb_metric_stb (34 bit) = %0d",
                         $time,
                         $signed(dut.debug_metric_absC),
                         $signed(dut.debug_metric_Norm));

                $fwrite(fp_metric, "%0t,%0d,%0d\n",
                        $time,
                        $signed(dut.debug_metric_absC),
                        $signed(dut.debug_metric_Norm));
            end
        end
    end

    // =========================================================================
    // AXIS source task
    // =========================================================================
    task automatic send_one_sample(
        input [31:0] din,
        input        din_last
    );
    begin
        @(posedge aclk);
        s_axis_tvalid <= 1'b1;
        s_axis_tdata  <= din;
        s_axis_tkeep  <= 4'hF;
        s_axis_tstrb  <= 4'hF;
        s_axis_tlast  <= din_last;
        s_axis_tid    <= 1'b0;
        s_axis_tdest  <= 1'b0;
        s_axis_tuser  <= 1'b0;

        while (!(s_axis_tvalid && s_axis_tready))
            @(posedge aclk);

        @(posedge aclk);
        s_axis_tvalid <= 1'b0;
    end
    endtask

    // =========================================================================
    // Stimulus
    // =========================================================================
    integer i;
    reg [15:0] i_part;
    reg [15:0] q_part;
    reg [31:0] sample_word;

    initial begin
        aresetn       = 1'b0;
        ctrl_constant = 32'd0;

        s_axis_tvalid = 0;
        s_axis_tdata  = 0;
        s_axis_tkeep  = 0;
        s_axis_tstrb  = 0;
        s_axis_tlast  = 0;

        m_axis_tready = 1;

        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);


        for (i = 0; i < INPUT_SAMPLE_NUM; i = i + 1) begin
            i_part      = i[15:0];
            q_part      = 16'h1000 + i[15:0];
            sample_word = {i_part, q_part};

            send_one_sample(sample_word, (i == INPUT_SAMPLE_NUM-1));
        end

        $display("All input sent");

        repeat (1000) @(posedge aclk);

        $fclose(fp_metric);

        $display("Simulation done");
        $display("IN=%0d OUT=%0d", in_count, out_count);

        $finish;
    end

    // =========================================================================
    // Wave dump
    // =========================================================================
    initial begin
        $dumpfile("tb_dma_wrapper.vcd");
        $dumpvars(0, tb_dma_wrapper);
    end

endmodule

`default_nettype wire
