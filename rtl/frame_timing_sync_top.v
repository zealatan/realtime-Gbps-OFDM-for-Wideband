`timescale 1ns/1ps

// frame_timing_sync_top: AXI-Stream capture → frame detection → CP timing sync
//                        + fractional CFO estimation.
//
// Integrates:
//   1. iq_frame_buffer  — AXI-Stream fill, random-access read port
//   2. frame_detector   — sliding-window energy frame start detector
//   3. timing_frac_cfo_top — CP autocorr + timing metric + peak + CORDIC atan2
//
// C reference (synchronization()):
//   indexFrame      = frame_detector(...)
//   peakIndexAuto   = VanDeBeekAutoCorrelation(...)
//   fracfreqOffset  = -atan2(autoCorrOutQ[peak], autoCorrOutI[peak]) / (2*PI)
//
// Buffer read port arbitration:
//   S_FRAME_DET  → frame_detector      drives buf_rd_addr/en
//   S_TIMING_CFO → timing_frac_cfo_top drives buf_rd_addr/en
//   Otherwise    → rd_en=0
//
// frame_error is asserted when frame_detector completes with frame_found=0.
// In that case the module skips timing_frac_cfo_top and asserts done immediately.
//
// FSM: IDLE → FILL → FRAME_DET → TIMING_CFO → DONE

module frame_timing_sync_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer BUF_AW       = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32,
    parameter integer PHASE_WIDTH  = 16,
    parameter integer POWER_WIDTH  = 33,
    parameter integer ENERGY_WIDTH = 40,
    parameter integer WINDOW_LEN   = 25,
    parameter integer HIT_COUNT    = 10,
    parameter integer THRESHOLD    = 10240000
) (
    input  wire                              aclk,
    input  wire                              aresetn,

    // AXI-Stream IQ input → iq_frame_buffer
    input  wire [31:0]                       s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,

    // Control
    input  wire                              start,
    output reg                               done,
    output reg                               busy,
    output reg                               frame_error,

    // frame_detector run-time config (sampled at start)
    input  wire [ENERGY_WIDTH-1:0]           threshold_in,
    input  wire [6:0]                        window_len_in,
    input  wire [3:0]                        hit_count_in,

    // Outputs (registered in sub-modules; stable after done)
    output wire [BUF_AW-1:0]                 frame_index,
    output wire                              frame_found,
    output wire [INDEX_WIDTH-1:0]            peak_lag,
    output wire [METRIC_WIDTH-1:0]           peak_metric,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_i,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_q,
    output wire        [RESULT_WIDTH-1:0]    peak_energy,
    output wire [PHASE_WIDTH-1:0]            frac_phase,
    output wire                              frac_phase_valid
);

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_FILL       = 3'd1,
        S_FRAME_DET  = 3'd2,
        S_TIMING_CFO = 3'd3,
        S_DONE       = 3'd4;

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // iq_frame_buffer — internal sample memory
    // -----------------------------------------------------------------------
    reg                 buf_capture_start;
    wire                buf_capture_done;
    wire [BUF_AW:0]     buf_sample_count;

    wire [BUF_AW-1:0]   buf_rd_addr;
    wire                buf_rd_en;
    wire [31:0]         buf_rd_data;
    wire [15:0]         buf_rd_data_I;
    wire [15:0]         buf_rd_data_Q;

    assign buf_rd_data_I = buf_rd_data[15:0];
    assign buf_rd_data_Q = buf_rd_data[31:16];

    iq_frame_buffer #(
        .DATA_WIDTH (32),
        .ADDR_WIDTH (BUF_AW),
        .DEPTH      (1 << BUF_AW)
    ) u_buf (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .capture_start (buf_capture_start),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .wb_en         (1'b0),
        .wb_addr       ({BUF_AW{1'b0}}),
        .wb_data       (32'd0),
        .rd_en         (buf_rd_en),
        .rd_addr       (buf_rd_addr),
        .rd_data       (buf_rd_data),
        .wr_ptr        (),
        .sample_count  (buf_sample_count),
        .capture_done  (buf_capture_done),
        .busy          (),
        .full          ()
    );

    // -----------------------------------------------------------------------
    // frame_detector
    // -----------------------------------------------------------------------
    reg               fd_start_r;
    wire              fd_done;
    wire [BUF_AW-1:0] fd_buf_rd_addr;
    wire              fd_buf_rd_en;

    frame_detector #(
        .DATA_WIDTH  (32),
        .ADDR_WIDTH  (BUF_AW),
        .INDEX_WIDTH (BUF_AW),
        .POWER_WIDTH (POWER_WIDTH),
        .ENERGY_WIDTH(ENERGY_WIDTH),
        .WINDOW_LEN  (WINDOW_LEN),
        .HIT_COUNT   (HIT_COUNT),
        .THRESHOLD   (THRESHOLD)
    ) u_fd (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .start         (fd_start_r),
        .threshold_in  (threshold_in),
        .window_len_in (window_len_in),
        .hit_count_in  (hit_count_in),
        .search_base   ({BUF_AW{1'b0}}),
        .search_len    (buf_sample_count),
        .buf_rd_addr   (fd_buf_rd_addr),
        .buf_rd_en     (fd_buf_rd_en),
        .buf_rd_data_I (buf_rd_data_I),
        .buf_rd_data_Q (buf_rd_data_Q),
        .frame_index   (frame_index),
        .frame_found   (frame_found),
        .done          (fd_done),
        .busy          ()
    );

    // -----------------------------------------------------------------------
    // timing_frac_cfo_top
    //   base_addr driven by frame_detector's registered frame_index output.
    // -----------------------------------------------------------------------
    reg               tfc_start_r;
    wire              tfc_done;
    wire [BUF_AW-1:0] tfc_buf_rd_addr;
    wire              tfc_buf_rd_en;

    timing_frac_cfo_top #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .ADDR_WIDTH  (BUF_AW),
        .ACC_WIDTH   (ACC_WIDTH),
        .METRIC_WIDTH(METRIC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH),
        .PHASE_WIDTH (PHASE_WIDTH)
    ) u_tfc (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (tfc_start_r),
        .base_addr        (frame_index),
        .done             (tfc_done),
        .busy             (),
        .buf_rd_addr      (tfc_buf_rd_addr),
        .buf_rd_en        (tfc_buf_rd_en),
        .buf_rd_data_I    ($signed(buf_rd_data_I)),
        .buf_rd_data_Q    ($signed(buf_rd_data_Q)),
        .peak_lag         (peak_lag),
        .peak_metric      (peak_metric),
        .peak_corr_i      (peak_corr_i),
        .peak_corr_q      (peak_corr_q),
        .peak_energy      (peak_energy),
        .frac_phase       (frac_phase),
        .frac_phase_valid (frac_phase_valid)
    );

    // -----------------------------------------------------------------------
    // Buffer read-port mux: one driver active per state
    // -----------------------------------------------------------------------
    assign buf_rd_en   = (state == S_FRAME_DET)  ? fd_buf_rd_en   :
                         (state == S_TIMING_CFO) ? tfc_buf_rd_en  : 1'b0;

    assign buf_rd_addr = (state == S_FRAME_DET)  ? fd_buf_rd_addr :
                         (state == S_TIMING_CFO) ? tfc_buf_rd_addr : {BUF_AW{1'b0}};

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state             <= S_IDLE;
            done              <= 1'b0;
            busy              <= 1'b0;
            frame_error       <= 1'b0;
            buf_capture_start <= 1'b0;
            fd_start_r        <= 1'b0;
            tfc_start_r       <= 1'b0;
        end else begin
            done              <= 1'b0;
            buf_capture_start <= 1'b0;
            fd_start_r        <= 1'b0;
            tfc_start_r       <= 1'b0;

            case (state)

                S_IDLE: begin
                    frame_error <= 1'b0;
                    if (start && !busy) begin
                        busy              <= 1'b1;
                        buf_capture_start <= 1'b1;
                        state             <= S_FILL;
                    end
                end

                S_FILL: begin
                    if (buf_capture_done) begin
                        fd_start_r <= 1'b1;
                        state      <= S_FRAME_DET;
                    end
                end

                S_FRAME_DET: begin
                    if (fd_done) begin
                        if (frame_found) begin
                            tfc_start_r <= 1'b1;
                            state       <= S_TIMING_CFO;
                        end else begin
                            frame_error <= 1'b1;
                            state       <= S_DONE;
                        end
                    end
                end

                S_TIMING_CFO: begin
                    if (tfc_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
