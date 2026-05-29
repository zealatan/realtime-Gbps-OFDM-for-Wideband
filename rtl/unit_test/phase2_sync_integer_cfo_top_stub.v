`timescale 1ns/1ps

// phase2_sync_integer_cfo_top_stub — P2-17
//
// Wires the corrected IQ stream from phase2_streaming_sync_top into
// phase2_integer_cfo_stub.  Both modules share the same clock/reset.
//
// The corrected stream (m_valid/m_data) from the sync top fans out to:
//   1. the downstream consumer (m_valid / m_ready / m_data top-level ports)
//   2. phase2_integer_cfo_stub (sideband; stub ignores backpressure from consumer)
//
// integer_cfo_valid and integer_cfo_estimate[15:0] are exported for
// downstream use (e.g. NCO integer-bin correction).  Both are 0 until
// P2-18+ connects the real Meyr estimator.

module phase2_sync_integer_cfo_top_stub #(
    parameter integer SAMPLE_W  = 16,
    parameter integer NSC       = 256,
    parameter integer CP_LEN    = 32,
    parameter integer ACC_W     = 48,
    parameter integer METRIC_W  = 32
)(
    input  wire        clk,
    input  wire        aresetn,

    // AXI-Stream IQ input
    input  wire        s_valid,
    output wire        s_ready,
    input  wire [31:0] s_data,

    // AXI-Stream corrected IQ output
    output wire        m_valid,
    input  wire        m_ready,
    output wire [31:0] m_data,

    // Debug / status from sync top
    output wire                  timing_lock,
    output wire [31:0]           lock_index,
    output wire [METRIC_W-1:0]   metric_dbg,
    output wire [15:0]           frac_phase_dbg,
    output wire                  nco_locked,
    output wire [3:0]            state_dbg,

    // Integer CFO estimate (stub: always 0 until P2-18)
    output wire                  integer_cfo_valid,
    output wire signed [15:0]    integer_cfo_estimate
);

    // -----------------------------------------------------------------------
    // phase2_streaming_sync_top — fractional CFO correction chain
    // -----------------------------------------------------------------------
    wire        sync_m_valid;
    wire        sync_m_ready;
    wire [31:0] sync_m_data;

    phase2_streaming_sync_top #(
        .SAMPLE_W (SAMPLE_W),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .ACC_W    (ACC_W),
        .METRIC_W (METRIC_W)
    ) u_sync_top (
        .clk          (clk),
        .aresetn      (aresetn),
        .s_valid      (s_valid),
        .s_ready      (s_ready),
        .s_data       (s_data),
        .m_valid      (sync_m_valid),
        .m_ready      (sync_m_ready),
        .m_data       (sync_m_data),
        .timing_lock  (timing_lock),
        .lock_index   (lock_index),
        .metric_dbg   (metric_dbg),
        .frac_phase_dbg(frac_phase_dbg),
        .nco_locked   (nco_locked),
        .state_dbg    (state_dbg)
    );

    // Pass corrected stream through to top-level output
    assign m_valid      = sync_m_valid;
    assign sync_m_ready = m_ready;
    assign m_data       = sync_m_data;

    // -----------------------------------------------------------------------
    // phase2_integer_cfo_stub — integer CFO estimator placeholder
    // Taps the corrected stream; stub is always-ready so it never stalls it.
    // -----------------------------------------------------------------------
    wire        icfo_s_tready;

    phase2_integer_cfo_stub #(
        .IQ_WIDTH  (SAMPLE_W),
        .CFO_WIDTH (16)
    ) u_icfo_stub (
        .aclk                (clk),
        .aresetn             (aresetn),
        .s_axis_tvalid       (sync_m_valid),
        .s_axis_tready       (icfo_s_tready),
        .s_axis_tdata        (sync_m_data),
        .s_axis_tlast        (1'b0),
        .integer_cfo_valid   (integer_cfo_valid),
        .integer_cfo_estimate(integer_cfo_estimate)
    );

    // icfo_s_tready is always 1 (stub); no backpressure fed back to sync_top.
    wire _unused = icfo_s_tready;

endmodule
