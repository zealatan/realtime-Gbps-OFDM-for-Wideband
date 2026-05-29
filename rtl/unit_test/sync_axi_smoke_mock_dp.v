`timescale 1ns/1ps

// sync_axi_smoke_mock_dp: Behavioral stub datapath for FV13 smoke integration TB.
//
// Matches the port signature expected by sync_axi_board_wrapper when
// USE_MOCK_DATAPATH=1.  On start pulse: asserts busy for BUSY_CYCLES,
// then fires done (or frame_error when INJECT_ERROR=1) for one cycle.
// Ignores start while already busy.

module sync_axi_smoke_mock_dp #(
    parameter integer BUSY_CYCLES  = 20,
    parameter integer INJECT_ERROR = 0,   // 1 → fire frame_error instead of done
    parameter integer BUF_AW         = 12,
    parameter integer MEYR_IDX_WIDTH = 9,
    parameter integer SCORE_WIDTH    = 64,
    parameter integer IQ_WIDTH       = 16,
    parameter integer ENERGY_WIDTH   = 40
)(
    input  wire                        aclk,
    input  wire                        aresetn,
    input  wire                        start,

    // AXI-Stream IQ (accepted but not processed)
    input  wire [31:0]                 s_axis_tdata,
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire                        s_axis_tlast,

    output wire [31:0]                 m_axis_tdata,
    output wire                        m_axis_tvalid,
    input  wire                        m_axis_tready,
    output wire                        m_axis_tlast,

    // Frame detector config (ignored)
    input  wire [ENERGY_WIDTH-1:0]     threshold_in,
    input  wire [6:0]                  window_len_in,
    input  wire [3:0]                  hit_count_in,

    // Status outputs
    output reg                         busy,
    output reg                         done,
    output reg                         frame_error,
    output wire                        meyr_error,

    // Debug outputs (stable constants for smoke)
    output wire [BUF_AW-1:0]           frame_index,
    output wire [MEYR_IDX_WIDTH-1:0]   peak_lag,
    output wire [31:0]                 peak_metric,
    output wire signed [15:0]          frac_phase,
    output wire                        frame_found,
    output wire                        frac_phase_valid,
    output wire signed [15:0]          int_cfo,
    output wire [MEYR_IDX_WIDTH-1:0]   peak_index,
    output wire [SCORE_WIDTH-1:0]      peak_score
);

    // Tie-off unused outputs
    assign s_axis_tready  = 1'b1;
    assign m_axis_tdata   = 32'd0;
    assign m_axis_tvalid  = 1'b0;
    assign m_axis_tlast   = 1'b0;
    assign meyr_error     = 1'b0;
    assign frame_index    = {BUF_AW{1'b0}};
    assign peak_lag       = {MEYR_IDX_WIDTH{1'b0}};
    assign peak_metric    = 32'd0;
    assign frac_phase     = 16'sd0;
    assign frame_found    = 1'b0;
    assign frac_phase_valid = 1'b0;
    assign int_cfo        = 16'sd0;
    assign peak_index     = {MEYR_IDX_WIDTH{1'b0}};
    assign peak_score     = {SCORE_WIDTH{1'b0}};

    // Counter-based FSM
    reg [$clog2(BUSY_CYCLES+2)-1:0] cnt;

    localparam CNT_W = $clog2(BUSY_CYCLES+2);

    always @(posedge aclk) begin
        if (!aresetn) begin
            busy        <= 1'b0;
            done        <= 1'b0;
            frame_error <= 1'b0;
            cnt         <= {CNT_W{1'b0}};
        end else begin
            done        <= 1'b0;
            frame_error <= 1'b0;

            if (!busy) begin
                if (start) begin
                    busy <= 1'b1;
                    cnt  <= BUSY_CYCLES[CNT_W-1:0] - 1;
                end
            end else begin
                if (cnt == {CNT_W{1'b0}}) begin
                    busy <= 1'b0;
                    if (INJECT_ERROR)
                        frame_error <= 1'b1;
                    else
                        done <= 1'b1;
                end else begin
                    cnt <= cnt - 1'b1;
                end
            end
        end
    end

endmodule
