`timescale 1ns/1ps

// phase2_streaming_sync_top — P2-07
// First integrated Phase2 streaming synchronizer.
// Connects P2-02..P2-06 in a streaming chain:
//
//   IQ stream → [autocorr P2-02] → [metric P2-03] → [peak P2-04]
//                                                      → timing_lock
//                                                      → [frac_cfo_est P2-05]
//                                                              → frac_phase
//   IQ stream ──────────────────────────────────────→ [cfo_corr P2-06] → corrected IQ
//
// The main IQ stream fans out to both autocorr and corrector.
// Top s_ready = corrector s_ready; autocorr sees accepted (s_valid & s_ready).
//
// Pre-lock policy: corrector passes through with step_word=0 (identity rotation).
// Re-lock policy: new frac_phase_valid loads step_word with no phase reset (no dead-time).
//
// timing_lock alignment: streaming_peak_detector stores peak_p_i/p_q internally
// (updating on each new maximum within the window). On timing_lock the stored
// peak_p_i/p_q are latched out and forwarded directly to frac_cfo_estimator.
// No explicit delay line needed: alignment is guaranteed by the peak detector.

module phase2_streaming_sync_top #(
    parameter integer SAMPLE_W  = 16,
    parameter integer NSC       = 256,
    parameter integer CP_LEN    = 32,
    parameter integer ACC_W     = 48,
    parameter integer METRIC_W  = 32
) (
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

    // Debug / status outputs
    output wire                  timing_lock,
    output wire [31:0]           lock_index,
    output wire [METRIC_W-1:0]   metric_dbg,
    output wire [15:0]           frac_phase_dbg,
    output wire                  nco_locked,
    output wire [3:0]            state_dbg
);

    // -----------------------------------------------------------------------
    // Internal wires
    // -----------------------------------------------------------------------

    // From corrector to top s_ready
    wire cfo_s_ready;
    assign s_ready = cfo_s_ready;

    // Accepted beat (sample consumed by both autocorr and corrector)
    wire accepted = s_valid & cfo_s_ready;

    // --- P2-02 autocorr outputs ---
    wire signed [ACC_W-1:0] autocorr_p_i;
    wire signed [ACC_W-1:0] autocorr_p_q;
    wire        [ACC_W-1:0] autocorr_energy;
    wire                    autocorr_valid;
    wire [31:0]             autocorr_index;

    // --- P2-03 metric outputs ---
    wire [METRIC_W-1:0]     metric_out;
    wire                    metric_valid;
    wire [31:0]             metric_index;
    wire signed [ACC_W-1:0] metric_p_i;
    wire signed [ACC_W-1:0] metric_p_q;

    // --- P2-04 peak detector outputs ---
    wire                    pk_timing_lock;
    wire [31:0]             pk_lock_index;
    wire signed [ACC_W-1:0] pk_p_i;
    wire signed [ACC_W-1:0] pk_p_q;

    // --- P2-05 estimator outputs ---
    wire                    est_frac_valid;
    wire [15:0]             est_frac_phase;
    wire                    est_busy;
    wire [1:0]              est_state;

    // -----------------------------------------------------------------------
    // P2-02: streaming_cp_autocorr
    // Processes every accepted sample (s_valid & cfo_s_ready)
    // -----------------------------------------------------------------------
    streaming_cp_autocorr #(
        .SAMPLE_W (SAMPLE_W),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .ACC_W    (ACC_W)
    ) u_autocorr (
        .clk          (clk),
        .aresetn      (aresetn),
        .s_valid      (accepted),       // only when corrector also accepts
        .s_data       (s_data),
        .p_i          (autocorr_p_i),
        .p_q          (autocorr_p_q),
        .energy       (autocorr_energy),
        .out_valid    (autocorr_valid),
        .sample_index (autocorr_index)
    );

    // -----------------------------------------------------------------------
    // P2-03: streaming_timing_metric
    // Converts p_i/p_q/energy into timing metric; passes p_i/p_q through
    // -----------------------------------------------------------------------
    streaming_timing_metric #(
        .ACC_W    (ACC_W),
        .METRIC_W (METRIC_W)
    ) u_metric (
        .clk           (clk),
        .aresetn       (aresetn),
        .p_i           (autocorr_p_i),
        .p_q           (autocorr_p_q),
        .energy        (autocorr_energy),
        .in_valid      (autocorr_valid),
        .sample_index  (autocorr_index),
        .metric        (metric_out),
        .m_valid       (metric_valid),
        .m_sample_index(metric_index),
        .m_p_i         (metric_p_i),
        .m_p_q         (metric_p_q)
    );

    // -----------------------------------------------------------------------
    // P2-04: streaming_peak_detector
    // Window-based peak detection; emits timing_lock with aligned peak_p_i/p_q
    // -----------------------------------------------------------------------
    streaming_peak_detector #(
        .ACC_W    (ACC_W),
        .METRIC_W (METRIC_W),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN)
    ) u_peak (
        .clk          (clk),
        .aresetn      (aresetn),
        .metric       (metric_out),
        .in_valid     (metric_valid),
        .sample_index (metric_index),
        .p_i          (metric_p_i),
        .p_q          (metric_p_q),
        .timing_lock  (pk_timing_lock),
        .lock_index   (pk_lock_index),
        .peak_p_i     (pk_p_i),
        .peak_p_q     (pk_p_q)
    );

    // Connect peak outputs to top-level ports
    assign timing_lock = pk_timing_lock;
    assign lock_index  = pk_lock_index;

    // -----------------------------------------------------------------------
    // P2-05: streaming_frac_cfo_estimator
    // Receives timing_lock + aligned peak_p_i/p_q; outputs frac_phase
    // -----------------------------------------------------------------------
    streaming_frac_cfo_estimator #(
        .PHASE_IN_W     (ACC_W),   // 48-bit p_i/p_q from peak detector
        .PHASE_TRUNC_W  (32),      // truncate to 32-bit for CORDIC
        .CORDIC_LATENCY (15)
    ) u_estimator (
        .clk             (clk),
        .aresetn         (aresetn),
        .timing_lock     (pk_timing_lock),
        .p_i             (pk_p_i),
        .p_q             (pk_p_q),
        .busy            (est_busy),
        .frac_phase_valid(est_frac_valid),
        .frac_phase      (est_frac_phase),
        .state_dbg       (est_state)
    );

    assign frac_phase_dbg = est_frac_phase;

    // -----------------------------------------------------------------------
    // P2-06: streaming_cfo_corrector
    // Applies fractional CFO correction to the live IQ stream
    // -----------------------------------------------------------------------
    streaming_cfo_corrector #(
        .SAMPLE_W (SAMPLE_W),
        .STEP_W   (32),
        .PHASE_W  (16)
    ) u_corrector (
        .clk             (clk),
        .aresetn         (aresetn),
        .s_valid         (s_valid),
        .s_ready         (cfo_s_ready),
        .s_data          (s_data),
        .frac_phase_valid(est_frac_valid),
        .frac_phase      (est_frac_phase),
        .m_valid         (m_valid),
        .m_ready         (m_ready),
        .m_data          (m_data),
        .nco_locked      (nco_locked),
        .state_dbg       ()
    );

    // -----------------------------------------------------------------------
    // Debug outputs
    // -----------------------------------------------------------------------
    assign metric_dbg = metric_out;

    // state_dbg[0] = nco_locked
    // state_dbg[1] = autocorr out_valid
    // state_dbg[2] = frac_phase_valid (estimator output)
    // state_dbg[3] = est_busy
    assign state_dbg = {est_busy, est_frac_valid, autocorr_valid, nco_locked};

endmodule
