`timescale 1ns/1ps

// phase1_ofdm_synchronizer_top — Step 40
//
// Full Phase 1 synchronization pipeline:
//   Raw IQ → frac_cfo_frame_corrector_top (OUTPUT_SAMPLES=576)
//           → pss_sss_symbol_extractor (pss_fft_start=CP_LEN, sss_fft_start=NSC+2*CP_LEN)
//           → meyr_fft256_actual_integration_top (FFT × 2, Meyr integer CFO)
//
// All three sub-modules are pulsed start simultaneously.  The corrector spends
// hundreds of cycles in FILL/FRAME_DET/TIMING_CFO/LOAD_NCO before producing output,
// so the extractor and meyr safely wait in their respective input states.
//
// Corrected frame layout (576 samples):
//   [0..31]   CP_PSS  (CP_LEN=32, skipped by extractor)
//   [32..287]  PSS_time (NSC=256, → FFT)
//   [288..319] CP_SSS  (CP_LEN=32, skipped by extractor)
//   [320..575] SSS_time (NSC=256, → FFT)

module phase1_ofdm_synchronizer_top #(
    parameter integer NSC            = 256,
    parameter integer CP_LEN         = 32,
    parameter integer OUTPUT_SAMPLES = 576,    // 2*(NSC+CP_LEN)
    parameter integer PSS_FFT_START  = 32,     // = CP_LEN
    parameter integer SSS_FFT_START  = 320,    // = NSC + 2*CP_LEN

    // frac_cfo_frame_corrector_top parameters
    parameter integer BUF_AW          = 12,
    parameter integer ACC_WIDTH       = 40,
    parameter integer METRIC_WIDTH    = 32,
    parameter integer INDEX_WIDTH     = 9,
    parameter integer RESULT_WIDTH    = 32,
    parameter integer PHASE_WIDTH     = 16,
    parameter integer POWER_WIDTH     = 33,
    parameter integer ENERGY_WIDTH    = 40,
    parameter integer WINDOW_LEN      = 25,
    parameter integer HIT_COUNT       = 10,
    parameter integer THRESHOLD       = 10240000,
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer LATENCY         = 15,

    // meyr / FFT parameters
    parameter integer IQ_WIDTH        = 16,
    parameter integer PROD_WIDTH      = 32,
    parameter integer MACC_WIDTH      = 56,
    parameter integer SCORE_WIDTH     = 64,
    parameter integer MEYR_IDX_WIDTH  = 9,

    // extractor frame-index width
    parameter integer FIX_WIDTH       = 12,

    // Passthrough to meyr_fft256_actual_integration_top (simulation/testing)
    parameter integer USE_BEHAVIORAL_STUB = 2,   // 2=seq-stub (default for sim)
    parameter integer STUB_TLAST_AT       = 255,
    parameter integer STUB_STOP_AT        = 255,
    parameter integer FLUSH_COUNT         = 0,
    parameter integer WATCHDOG_CYCLES     = 2047,

    // Acquisition watchdog for frac_cfo_frame_corrector_top (Step 43)
    parameter integer ACQ_WATCHDOG_CYCLES = 0
)(
    input  wire                        aclk,
    input  wire                        aresetn,
    input  wire                        start,

    // Raw IQ input (to corrector buffer)
    input  wire [31:0]                 s_axis_tdata,
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire                        s_axis_tlast,

    // Frame detector runtime config
    input  wire [ENERGY_WIDTH-1:0]     threshold_in,
    input  wire [6:0]                  window_len_in,
    input  wire [3:0]                  hit_count_in,

    // Corrector status outputs (stable after done)
    output wire [BUF_AW-1:0]           frame_index,
    output wire [INDEX_WIDTH-1:0]      peak_lag,
    output wire [PHASE_WIDTH-1:0]      frac_phase,
    output wire                        frame_found,
    output wire                        frac_phase_valid,

    // Meyr integer CFO outputs (stable after done)
    output wire signed [15:0]          int_cfo,
    output wire [MEYR_IDX_WIDTH-1:0]   peak_index,
    output wire [SCORE_WIDTH-1:0]      peak_score,

    // Control
    output reg                         done,
    output reg                         busy,
    output reg                         frame_error,
    output reg                         meyr_error,

    // Datapath error code: OR of corrector (error_code=6) and Meyr (codes 1-5).
    // Only one sub-module can generate a non-zero code per transaction.
    // Stable after done; cleared on next transaction start.
    output wire [3:0]                  meyr_error_code
);

    // =========================================================================
    // FSM
    // =========================================================================
    localparam [1:0]
        S_IDLE = 2'd0,
        S_RUN  = 2'd1,
        S_DONE = 2'd2;

    reg [1:0] state;

    // =========================================================================
    // Sub-module start strobes (one-cycle pulses)
    // =========================================================================
    reg corr_start_r;
    reg ext_start_r;
    reg meyr_start_r;

    // =========================================================================
    // Inter-module AXI-Stream wires
    // =========================================================================
    // corrector → extractor
    wire [31:0]            corr_m_tdata;
    wire                   corr_m_tvalid;
    wire                   corr_m_tready;
    wire                   corr_m_tlast;

    // extractor → meyr
    wire [2*IQ_WIDTH-1:0]  ext_m_tdata;
    wire                   ext_m_tvalid;
    wire                   ext_m_tready;
    wire                   ext_m_tlast;
    wire                   ext_m_symbol_sel;
    wire [7:0]             ext_m_symbol_index;

    // Sub-module done / error signals
    wire                   corr_done;
    wire                   corr_frame_error;
    wire                   meyr_done;
    wire                   meyr_err;

    // Error code wires: ORed together since only one fires per transaction.
    wire [3:0]             corr_err_code_w;   // from corrector (0 or 6)
    wire [3:0]             meyr_err_code_w;   // from Meyr FSM (0-5)
    assign meyr_error_code = corr_err_code_w | meyr_err_code_w;

    // Extractor frame start constants (FIX_WIDTH-bit wires)
    wire [FIX_WIDTH-1:0]   w_pss_start = PSS_FFT_START;
    wire [FIX_WIDTH-1:0]   w_sss_start = SSS_FFT_START;
    wire [FIX_WIDTH-1:0]   w_frame_len = OUTPUT_SAMPLES;

    // =========================================================================
    // frac_cfo_frame_corrector_top
    // =========================================================================
    frac_cfo_frame_corrector_top #(
        .NSC                 (NSC),
        .CP_LEN              (CP_LEN),
        .OUTPUT_SAMPLES      (OUTPUT_SAMPLES),
        .BUF_AW              (BUF_AW),
        .ACC_WIDTH           (ACC_WIDTH),
        .METRIC_WIDTH        (METRIC_WIDTH),
        .INDEX_WIDTH         (INDEX_WIDTH),
        .RESULT_WIDTH        (RESULT_WIDTH),
        .PHASE_WIDTH         (PHASE_WIDTH),
        .POWER_WIDTH         (POWER_WIDTH),
        .ENERGY_WIDTH        (ENERGY_WIDTH),
        .WINDOW_LEN          (WINDOW_LEN),
        .HIT_COUNT           (HIT_COUNT),
        .THRESHOLD           (THRESHOLD),
        .NCO_PHASE_WIDTH     (NCO_PHASE_WIDTH),
        .LATENCY             (LATENCY),
        .ACQ_WATCHDOG_CYCLES (ACQ_WATCHDOG_CYCLES)
    ) u_corr (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_tdata    (s_axis_tdata),
        .s_axis_tvalid   (s_axis_tvalid),
        .s_axis_tready   (s_axis_tready),
        .s_axis_tlast    (s_axis_tlast),
        .start           (corr_start_r),
        .done            (corr_done),
        .busy            (),
        .frame_error     (corr_frame_error),
        .error_code      (corr_err_code_w),
        .threshold_in    (threshold_in),
        .window_len_in   (window_len_in),
        .hit_count_in    (hit_count_in),
        .frame_index     (frame_index),
        .frame_found     (frame_found),
        .peak_lag        (peak_lag),
        .peak_metric     (),
        .frac_phase      (frac_phase),
        .frac_phase_valid(frac_phase_valid),
        .m_axis_tdata    (corr_m_tdata),
        .m_axis_tvalid   (corr_m_tvalid),
        .m_axis_tready   (corr_m_tready),
        .m_axis_tlast    (corr_m_tlast)
    );

    // =========================================================================
    // pss_sss_symbol_extractor
    // =========================================================================
    pss_sss_symbol_extractor #(
        .NSC               (NSC),
        .CP_LEN            (CP_LEN),
        .IQ_WIDTH          (IQ_WIDTH),
        .FRAME_INDEX_WIDTH (FIX_WIDTH)
    ) u_ext (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .start           (ext_start_r),
        .pss_fft_start   (w_pss_start),
        .sss_fft_start   (w_sss_start),
        .frame_len       (w_frame_len),
        .s_axis_tvalid   (corr_m_tvalid),
        .s_axis_tready   (corr_m_tready),
        .s_axis_tdata    (corr_m_tdata),
        .s_axis_tlast    (corr_m_tlast),
        .m_axis_tvalid   (ext_m_tvalid),
        .m_axis_tready   (ext_m_tready),
        .m_axis_tdata    (ext_m_tdata),
        .m_axis_tlast    (ext_m_tlast),
        .m_symbol_sel    (ext_m_symbol_sel),
        .m_symbol_index  (ext_m_symbol_index),
        .busy            (),
        .done            (),
        .error           (),
        .error_code      ()
    );

    // =========================================================================
    // meyr_fft256_actual_integration_top
    // =========================================================================
    meyr_fft256_actual_integration_top #(
        .NSC                 (NSC),
        .IQ_WIDTH            (IQ_WIDTH),
        .PROD_WIDTH          (PROD_WIDTH),
        .ACC_WIDTH           (MACC_WIDTH),
        .SCORE_WIDTH         (SCORE_WIDTH),
        .INDEX_WIDTH         (MEYR_IDX_WIDTH),
        .USE_BEHAVIORAL_STUB (USE_BEHAVIORAL_STUB),
        .STUB_TLAST_AT       (STUB_TLAST_AT),
        .STUB_STOP_AT        (STUB_STOP_AT),
        .FLUSH_COUNT         (FLUSH_COUNT),
        .WATCHDOG_CYCLES     (WATCHDOG_CYCLES)
    ) u_meyr (
        .aclk                  (aclk),
        .aresetn               (aresetn),
        .start                 (meyr_start_r),
        .s_axis_tvalid         (ext_m_tvalid),
        .s_axis_tready         (ext_m_tready),
        .s_axis_tdata          (ext_m_tdata),
        .s_axis_tlast          (ext_m_tlast),
        .s_symbol_sel          (ext_m_symbol_sel),
        .done                  (meyr_done),
        .busy                  (),
        .error                 (meyr_err),
        .error_code            (meyr_err_code_w),
        .ev_tlast_missing_o    (),
        .ev_tlast_unexpected_o (),
        .ev_data_in_halt_o     (),
        .ev_data_out_halt_o    (),
        .ev_status_halt_o      (),
        .int_cfo               (int_cfo),
        .peak_index            (peak_index),
        .peak_score            (peak_score)
    );

    // =========================================================================
    // Top-level FSM
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            busy         <= 1'b0;
            frame_error  <= 1'b0;
            meyr_error   <= 1'b0;
            corr_start_r <= 1'b0;
            ext_start_r  <= 1'b0;
            meyr_start_r <= 1'b0;
        end else begin
            done         <= 1'b0;
            corr_start_r <= 1'b0;
            ext_start_r  <= 1'b0;
            meyr_start_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    frame_error <= 1'b0;
                    meyr_error  <= 1'b0;
                    if (start && !busy) begin
                        busy         <= 1'b1;
                        corr_start_r <= 1'b1;
                        ext_start_r  <= 1'b1;
                        meyr_start_r <= 1'b1;
                        state        <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (corr_frame_error) begin
                        frame_error <= 1'b1;
                        state       <= S_DONE;
                    end else if (meyr_done) begin
                        if (meyr_err) meyr_error <= 1'b1;
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
