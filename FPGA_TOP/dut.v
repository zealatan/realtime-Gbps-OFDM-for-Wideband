`default_nettype none
`timescale 1ns/1ps

module dut #(
    parameter integer C_AXIS_TDATA_WIDTH = 32,
    parameter integer C_ADDER_BIT_WIDTH  = 32,
    parameter integer C_AXIS_TID_WIDTH   = 1,
    parameter integer C_AXIS_TDEST_WIDTH = 1,
    parameter integer C_AXIS_TUSER_WIDTH = 1,
    parameter integer FIFO_DEPTH         = 2048,
    parameter integer FIFO_ADDR_W        = 11,
    parameter integer OUTPUT_FRAME_LEN   = 2048
)(
    input  wire                             aclk,
    input  wire                             aresetn,
    input  wire [C_ADDER_BIT_WIDTH-1:0]     ctrl_constant,

    // -------------------------------------------------------------------------
    // AXI-Stream Slave Interface
    // -------------------------------------------------------------------------
    input  wire                             s_axis_tvalid,
    output wire                             s_axis_tready,
    input  wire [C_AXIS_TDATA_WIDTH-1:0]    s_axis_tdata,
    input  wire [C_AXIS_TDATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  wire [C_AXIS_TDATA_WIDTH/8-1:0]  s_axis_tstrb,
    input  wire                             s_axis_tlast,
    input  wire [C_AXIS_TID_WIDTH-1:0]      s_axis_tid,
    input  wire [C_AXIS_TDEST_WIDTH-1:0]    s_axis_tdest,
    input  wire [C_AXIS_TUSER_WIDTH-1:0]    s_axis_tuser,

    // -------------------------------------------------------------------------
    // AXI-Stream Master Interface
    // -------------------------------------------------------------------------
    output wire                             m_axis_tvalid,
    input  wire                             m_axis_tready,
    output wire [C_AXIS_TDATA_WIDTH-1:0]    m_axis_tdata,
    output wire [C_AXIS_TDATA_WIDTH/8-1:0]  m_axis_tkeep,
    output wire [C_AXIS_TDATA_WIDTH/8-1:0]  m_axis_tstrb,
    output wire                             m_axis_tlast,
    output wire [C_AXIS_TID_WIDTH-1:0]      m_axis_tid,
    output wire [C_AXIS_TDEST_WIDTH-1:0]    m_axis_tdest,
    output wire [C_AXIS_TUSER_WIDTH-1:0]    m_axis_tuser
);

    // =========================================================================
    // Unused input tie-off
    // =========================================================================
    wire _unused_tieoff;

    assign _unused_tieoff = ^{
        1'b0,
        ctrl_constant,
        s_axis_tkeep,
        s_axis_tstrb,
        s_axis_tlast,
        s_axis_tid,
        s_axis_tdest,
        s_axis_tuser
    };

    // =========================================================================
    // AXI-Stream input -> auto_corr input
    // =========================================================================
    wire [31:0] sync_sample_in;
    wire        sync_sample_stb;

    generate
        if (C_AXIS_TDATA_WIDTH >= 32) begin : g_input_sample_ge_32
            assign sync_sample_in = s_axis_tdata[31:0];
        end
        else begin : g_input_sample_lt_32
            assign sync_sample_in = {{(32-C_AXIS_TDATA_WIDTH){1'b0}},
                                     s_axis_tdata};
        end
    endgenerate

    // =========================================================================
    // auto_corr outputs
    // =========================================================================
    wire               start_index;

    wire signed [31:0] debug_metric_I;
    wire               debug_metric_I_strobe;

    wire signed [31:0] debug_metric_Q;
    wire               debug_metric_Q_strobe;

    wire        [32:0] debug_metric_Norm;
    wire               debug_metric_Norm_strobe;

    wire        [64:0] debug_metric_absC;
    wire               debug_metric_absC_strobe;

    wire signed [23:0] peak_I;
    wire signed [23:0] peak_Q;

    wire        [7:0]  debug_peak_idx;
    wire        [7:0]  raddr;
    wire               peak_found_stb;

    wire signed [33:0] debug_vdb_metric;
    wire               debug_vdb_metric_stb;

    // =========================================================================
    // Output FIFO declarations
    // =========================================================================
    localparam integer FIFO_WORD_W = 1 + C_AXIS_TDATA_WIDTH;

    reg  [FIFO_WORD_W-1:0] fifo_mem [0:FIFO_DEPTH-1];

    reg  [FIFO_ADDR_W-1:0] wr_ptr;
    reg  [FIFO_ADDR_W-1:0] rd_ptr;
    reg  [FIFO_ADDR_W:0]   fifo_count;

    wire                   fifo_full;
    wire                   fifo_empty;
    wire                   fifo_almost_full;

    wire                   fifo_push;
    wire                   fifo_pop;
    wire                   fifo_push_last;

    wire [FIFO_WORD_W-1:0] fifo_push_word;
    wire [FIFO_WORD_W-1:0] fifo_head_word;
    wire                   fifo_head_last;
    wire [C_AXIS_TDATA_WIDTH-1:0] fifo_head_data;

    // Keep some margin because auto_corr may still produce delayed output
    // after input backpressure is asserted.
    localparam integer FIFO_READY_MARGIN = 16;
    localparam integer FIFO_READY_LEVEL  =
        (FIFO_DEPTH > FIFO_READY_MARGIN) ?
        (FIFO_DEPTH - FIFO_READY_MARGIN) :
        FIFO_DEPTH;

    assign fifo_full        = (fifo_count == FIFO_DEPTH);
    assign fifo_empty       = (fifo_count == 0);
    assign fifo_almost_full = (fifo_count >= FIFO_READY_LEVEL);

    // Backpressure to RDMA-side AXI-Stream source.
    assign s_axis_tready   = ~fifo_almost_full;
    assign sync_sample_stb = s_axis_tvalid & s_axis_tready;

    // =========================================================================
    // auto_corr instance
    // =========================================================================
    auto_corr u_auto_corr (
        .clock                    (aclk),
        .reset                    (~aresetn),
        .enable                   (1'b1),

        .sample_in                (sync_sample_in),
        .sample_in_strobe         (sync_sample_stb),

        .start_index              (start_index),

        .debug_metric_I           (debug_metric_I),
        .debug_metric_I_strobe    (debug_metric_I_strobe),

        .debug_metric_Q           (debug_metric_Q),
        .debug_metric_Q_strobe    (debug_metric_Q_strobe),

        .debug_metric_Norm        (debug_metric_Norm),
        .debug_metric_Norm_strobe (debug_metric_Norm_strobe),

        .debug_metric_absC        (debug_metric_absC),
        .debug_metric_absC_strobe (debug_metric_absC_strobe),

        .peak_I                   (peak_I),
        .peak_Q                   (peak_Q),

        .debug_peak_idx           (debug_peak_idx),
        .raddr                    (raddr),
        .peak_found_stb           (peak_found_stb),

        .debug_vdb_metric         (debug_vdb_metric),
        .debug_vdb_metric_stb     (debug_vdb_metric_stb),

        .set_stb                  (1'b0),
        .set_addr                 (8'd0),
        .set_data                 (32'd0)
    );

    // =========================================================================
    // Convert 34-bit metric to AXI data width
    // =========================================================================
    wire signed [31:0] debug_vdb_metric_s32;
    wire [C_AXIS_TDATA_WIDTH-1:0] metric_axis_data;

    assign debug_vdb_metric_s32 = debug_vdb_metric[33:2];

    generate
        if (C_AXIS_TDATA_WIDTH > 32) begin : g_metric_sign_extend
            assign metric_axis_data =
                {{(C_AXIS_TDATA_WIDTH-32){debug_vdb_metric_s32[31]}},
                 debug_vdb_metric_s32};
        end
        else if (C_AXIS_TDATA_WIDTH == 32) begin : g_metric_equal_32
            assign metric_axis_data = debug_vdb_metric_s32;
        end
        else begin : g_metric_truncate
            assign metric_axis_data = debug_vdb_metric_s32[C_AXIS_TDATA_WIDTH-1:0];
        end
    endgenerate

    // =========================================================================
    // Fixed-length TLAST generation
    // =========================================================================
    reg [31:0] out_frame_count;

    assign fifo_push      = debug_vdb_metric_stb & ~fifo_full;
    assign fifo_pop       = (~fifo_empty) & m_axis_tready;
    assign fifo_push_last = fifo_push &&
                            (out_frame_count == OUTPUT_FRAME_LEN-1);

    always @(posedge aclk) begin
        if (!aresetn) begin
            out_frame_count <= 32'd0;
        end
        else if (fifo_push) begin
            if (out_frame_count == OUTPUT_FRAME_LEN-1)
                out_frame_count <= 32'd0;
            else
                out_frame_count <= out_frame_count + 1'b1;
        end
    end

    // =========================================================================
    // Output FIFO
    //
    // FIFO word format:
    //   [FIFO_WORD_W-1]              : TLAST
    //   [C_AXIS_TDATA_WIDTH-1:0]     : TDATA
    // =========================================================================
    assign fifo_push_word = {fifo_push_last, metric_axis_data};

    assign fifo_head_word = fifo_mem[rd_ptr];
    assign fifo_head_last = fifo_head_word[FIFO_WORD_W-1];
    assign fifo_head_data = fifo_head_word[C_AXIS_TDATA_WIDTH-1:0];

    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_ptr     <= {FIFO_ADDR_W{1'b0}};
            rd_ptr     <= {FIFO_ADDR_W{1'b0}};
            fifo_count <= {(FIFO_ADDR_W+1){1'b0}};
        end
        else begin
            if (fifo_push) begin
                fifo_mem[wr_ptr] <= fifo_push_word;
                wr_ptr           <= wr_ptr + 1'b1;
            end

            if (fifo_pop) begin
                rd_ptr <= rd_ptr + 1'b1;
            end

            case ({fifo_push, fifo_pop})
                2'b10: fifo_count <= fifo_count + 1'b1;
                2'b01: fifo_count <= fifo_count - 1'b1;
                default: fifo_count <= fifo_count;
            endcase
        end
    end

    // =========================================================================
    // Debug sticky flags
    // =========================================================================
    reg overflow_sticky;
    reg dbg_seen_fifo_push_last;

    always @(posedge aclk) begin
        if (!aresetn) begin
            overflow_sticky         <= 1'b0;
            dbg_seen_fifo_push_last <= 1'b0;
        end
        else begin
            if (debug_vdb_metric_stb && fifo_full)
                overflow_sticky <= 1'b1;

            if (fifo_push_last)
                dbg_seen_fifo_push_last <= 1'b1;
        end
    end

    // =========================================================================
    // AXI-Stream master output
    // =========================================================================
    assign m_axis_tvalid = ~fifo_empty;
    assign m_axis_tdata  = fifo_head_data;
    assign m_axis_tkeep  = {C_AXIS_TDATA_WIDTH/8{1'b1}};
    assign m_axis_tstrb  = {C_AXIS_TDATA_WIDTH/8{1'b1}};
    assign m_axis_tlast  = fifo_head_last;

    assign m_axis_tid    = {C_AXIS_TID_WIDTH{1'b0}};
    assign m_axis_tdest  = {C_AXIS_TDEST_WIDTH{1'b0}};
    assign m_axis_tuser  = {C_AXIS_TUSER_WIDTH{1'b0}};

endmodule

`default_nettype wire
