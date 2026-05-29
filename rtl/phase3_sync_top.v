`timescale 1ns/1ps

// phase3_sync_top — Phase 3 OFDM synchronizer orchestration top
//
// Implements the full C reference synchronization() flow (ref/receiver.c):
//   Step 1: frame_detector()           → frac_cfo_frame_corrector_top internal
//   Step 2: VanDeBeekAutoCorrelation() → frac_cfo_frame_corrector_top internal
//   Step 3: slotStartIndex = f+peak   → slot_start_controller
//   Step 4: frac CFO est + correction → frac_cfo_frame_corrector_top internal
//   Step 5: Meyr integer CFO est.     → meyr_integer_cfo_fft_frontend_top
//   Step 5: integer CFO correction    → CONNECTION POINT (see note below)
//
// INTEGER CFO CORRECTOR CONNECTION POINT:
//   When dbg_integer_cfo_valid pulses, dbg_integer_cfo_word holds the NCO step
//   word for integer CFO removal:  step = -int_cfo * 2^(32 - log2(NSC)).
//   A replay buffer is needed to re-feed the frac-corrected IQ through a second
//   frac_cfo_corrector_top instance.  This is a future Phase 3 work item.
//
// Stream datapath:
//   s_axis ──► frac_cfo_frame_corrector_top  (OUTPUT_SAMPLES = FRAME_LEN)
//                   │  frac-corrected IQ  (FRAME_LEN = 2*(NSC+CP_LEN) samples)
//                   ▼
//              pss_sss_symbol_extractor
//                   │  PSS (m_symbol_sel=0)  then SSS (m_symbol_sel=1)
//                   ▼
//              meyr_integer_cfo_fft_frontend_top
//                   │  int_cfo → dbg_integer_cfo_word
//
// ERROR RECOVERY:
//   On frame_error the extractor/Meyr remain in their waiting states.
//   A full aresetn toggle is needed before the next valid start.
//
// FSM:
//   S_IDLE → on start: pulse frac+extractor+meyr starts simultaneously → S_RUN
//   S_RUN  → frac_frame_error fires:  assert error → S_DONE
//             meyr_done fires:         latch step word → S_DONE
//   S_DONE → done=1 for 1 cycle → S_IDLE

module phase3_sync_top #(
    // OFDM timing
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
    // Buffer address width; 2^BUF_AW must exceed the total slot length
    parameter integer BUF_AW          = 12,
    // Internal synchronizer widths
    parameter integer ACC_WIDTH       = 40,
    parameter integer METRIC_WIDTH    = 32,
    parameter integer INDEX_WIDTH     = 9,
    parameter integer RESULT_WIDTH    = 32,
    parameter integer PHASE_WIDTH     = 16,
    parameter integer POWER_WIDTH     = 33,
    parameter integer ENERGY_WIDTH    = 40,
    // Frame detector defaults (overridable at run-time via *_in ports)
    parameter integer WINDOW_LEN      = 25,
    parameter integer HIT_COUNT       = 10,
    parameter integer THRESHOLD       = 10240000,   // 40000 * 256  (Q1.15-scaled)
    // NCO / CORDIC
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer CORDIC_LATENCY  = 15,
    // IQ component width
    parameter integer IQ_WIDTH        = 16
) (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI-Stream IQ input
    input  wire [2*IQ_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    // Frame detector run-time configuration (sampled at start)
    input  wire [ENERGY_WIDTH-1:0]  threshold_in,
    input  wire [6:0]               window_len_in,
    input  wire [3:0]               hit_count_in,

    // Control
    input  wire        start,
    output reg         done,
    output reg         busy,
    output reg         error,
    output reg  [3:0]  error_code,

    // -----------------------------------------------------------------------
    // Debug / verification outputs
    // -----------------------------------------------------------------------

    // Step 1+2: frame start and timing peak
    // Both pulse simultaneously when frac_phase_valid fires (CORDIC done).
    // At that point frame_index and peak_lag are both stable.
    output wire                    dbg_frame_start_valid,
    output wire [BUF_AW-1:0]       dbg_frame_start_index,
    output wire                    dbg_peak_valid,
    output wire [INDEX_WIDTH-1:0]  dbg_peak_index,

    // Step 3: slotStartIndex = frame_index + peak_lag  (fires on frac_corr.done)
    output wire                    dbg_slot_start_valid,
    output wire [BUF_AW-1:0]       dbg_slot_start_index,

    // Step 4: fractional CFO  (1-cycle pulse, same as frame_start_valid)
    output wire                    dbg_frac_cfo_valid,
    output wire [PHASE_WIDTH-1:0]  dbg_frac_cfo_word,

    // PSS/SSS window offsets (constants, parameter-derived)
    output wire [BUF_AW-1:0]       dbg_pss_start,   // = CP_LEN
    output wire [BUF_AW-1:0]       dbg_sss_start,   // = 2*CP_LEN + NSC

    // Step 5: Meyr integer CFO  (1-cycle valid pulse)
    output wire                    dbg_integer_cfo_valid,
    output wire [NCO_PHASE_WIDTH-1:0] dbg_integer_cfo_word,  // NCO step word

    output wire                    dbg_done,
    output wire [3:0]              dbg_error_code,

    // P3-14B: Frac-corrected stream tap (for replay buffer in wrapper)
    output wire [2*IQ_WIDTH-1:0]   dbg_frac_m_tdata,
    output wire                    dbg_frac_m_tvalid,
    output wire                    dbg_frac_m_tready,
    output wire                    dbg_frac_m_tlast,

    // P3-14B: Meyr peak index (latched when meyr_done fires)
    output wire [INDEX_WIDTH-1:0]  dbg_meyr_peak_index
);

    // -----------------------------------------------------------------------
    // Derived frame parameters — no hardcoded 32 / 320 / 576
    // -----------------------------------------------------------------------
    localparam integer PSS_OFFSET    = CP_LEN;
    localparam integer SSS_OFFSET    = 2 * CP_LEN + NSC;
    localparam integer FRAME_LEN     = 2 * (NSC + CP_LEN);
    // Integer CFO NCO step shift: valid when NSC is a power of 2.
    localparam integer NSC_LOG2      = $clog2(NSC);        // 8  for NSC=256
    localparam integer INT_CFO_SHIFT = 32 - NSC_LOG2;      // 24 for NSC=256

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_RUN  = 2'd1,
                     S_DONE = 2'd2;
    reg [1:0] state;

    reg frac_start_r;
    reg ext_start_r;
    reg meyr_start_r;

    // -----------------------------------------------------------------------
    // frac_cfo_frame_corrector_top wires
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0]  frac_m_tdata;
    wire                   frac_m_tvalid;
    wire                   frac_m_tready;
    wire                   frac_m_tlast;
    wire                   frac_done;
    wire                   frac_frame_error;
    wire [3:0]             frac_error_code;
    wire [BUF_AW-1:0]      frac_frame_index;
    wire [INDEX_WIDTH-1:0] frac_peak_lag;
    wire [PHASE_WIDTH-1:0] frac_frac_phase;
    wire                   frac_frac_phase_valid;

    // -----------------------------------------------------------------------
    // slot_start_controller wires
    // -----------------------------------------------------------------------
    wire [BUF_AW-1:0]  ssc_slot_start;
    wire               ssc_slot_valid;
    wire [BUF_AW-1:0]  ssc_pss_fft_start;
    wire [BUF_AW-1:0]  ssc_sss_fft_start;
    wire [BUF_AW-1:0]  ssc_frame_len;

    // -----------------------------------------------------------------------
    // pss_sss_symbol_extractor wires
    // -----------------------------------------------------------------------
    wire               ext_m_tvalid;
    wire               ext_m_tready;
    wire [2*IQ_WIDTH-1:0] ext_m_tdata;
    wire               ext_m_tlast;
    wire               ext_m_symbol_sel;
    wire [7:0]         ext_m_symbol_index;

    // -----------------------------------------------------------------------
    // meyr_integer_cfo_fft_frontend_top wires
    // -----------------------------------------------------------------------
    wire               meyr_done;
    wire               meyr_error;
    wire signed [15:0] meyr_int_cfo;

    // -----------------------------------------------------------------------
    // Integer CFO step word:  step = -int_cfo * 2^INT_CFO_SHIFT
    // Latched on meyr_done so downstream sees a stable value.
    // -----------------------------------------------------------------------
    wire signed [NCO_PHASE_WIDTH-1:0] int_cfo_ext =
        {{(NCO_PHASE_WIDTH-16){meyr_int_cfo[15]}}, meyr_int_cfo};

    wire signed [NCO_PHASE_WIDTH-1:0] int_cfo_step_word =
        (-int_cfo_ext) << INT_CFO_SHIFT;

    reg signed [NCO_PHASE_WIDTH-1:0] int_cfo_step_word_r;
    reg                              int_cfo_valid_r;

    // -----------------------------------------------------------------------
    // Debug output assignments
    // -----------------------------------------------------------------------
    assign dbg_frame_start_valid  = frac_frac_phase_valid;
    assign dbg_frame_start_index  = frac_frame_index;
    assign dbg_peak_valid         = frac_frac_phase_valid;
    assign dbg_peak_index         = frac_peak_lag;
    assign dbg_slot_start_valid   = ssc_slot_valid;
    assign dbg_slot_start_index   = ssc_slot_start;
    assign dbg_frac_cfo_valid     = frac_frac_phase_valid;
    assign dbg_frac_cfo_word      = frac_frac_phase;
    assign dbg_pss_start          = ssc_pss_fft_start;
    assign dbg_sss_start          = ssc_sss_fft_start;
    assign dbg_integer_cfo_valid  = int_cfo_valid_r;
    assign dbg_integer_cfo_word   = int_cfo_step_word_r;
    assign dbg_done               = done;
    assign dbg_error_code         = error_code;

    // P3-14B: expose frac-corrected stream (between frac corrector and extractor)
    assign dbg_frac_m_tdata  = frac_m_tdata;
    assign dbg_frac_m_tvalid = frac_m_tvalid;
    assign dbg_frac_m_tready = frac_m_tready;
    assign dbg_frac_m_tlast  = frac_m_tlast;

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state               <= S_IDLE;
            done                <= 1'b0;
            busy                <= 1'b0;
            error               <= 1'b0;
            error_code          <= 4'd0;
            frac_start_r        <= 1'b0;
            ext_start_r         <= 1'b0;
            meyr_start_r        <= 1'b0;
            int_cfo_step_word_r <= {NCO_PHASE_WIDTH{1'b0}};
            int_cfo_valid_r     <= 1'b0;
        end else begin
            done            <= 1'b0;
            frac_start_r    <= 1'b0;
            ext_start_r     <= 1'b0;
            meyr_start_r    <= 1'b0;
            int_cfo_valid_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    error      <= 1'b0;
                    error_code <= 4'd0;
                    if (start && !busy) begin
                        busy         <= 1'b1;
                        frac_start_r <= 1'b1;
                        ext_start_r  <= 1'b1;
                        meyr_start_r <= 1'b1;
                        state        <= S_RUN;
                    end
                end

                // Wait for error or Meyr completion.
                // frac_frame_error becomes 1 before frac_done when frame det fails;
                // meyr_done fires after the full FFT+correlation sequence.
                S_RUN: begin
                    if (frac_frame_error) begin
                        error      <= 1'b1;
                        error_code <= frac_error_code;
                        state      <= S_DONE;
                    end else if (meyr_done) begin
                        int_cfo_step_word_r <= int_cfo_step_word;
                        int_cfo_valid_r     <= 1'b1;
                        state               <= S_DONE;
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

    // =======================================================================
    // u_frac_corr — frac_cfo_frame_corrector_top  (Steps 1-4)
    //
    // OUTPUT_SAMPLES = FRAME_LEN overrides the default of NSC+CP_LEN so that
    // both PSS and SSS symbols are included in the corrected output stream.
    //   PSS: output sample offset [CP_LEN .. CP_LEN+NSC-1]       = [32..287]
    //   SSS: output sample offset [2*CP_LEN+NSC .. FRAME_LEN-1]  = [320..575]
    // =======================================================================
    frac_cfo_frame_corrector_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .OUTPUT_SAMPLES  (FRAME_LEN),
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
        .LATENCY         (CORDIC_LATENCY)
    ) u_frac_corr (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .s_axis_tdata     (s_axis_tdata),
        .s_axis_tvalid    (s_axis_tvalid),
        .s_axis_tready    (s_axis_tready),
        .s_axis_tlast     (s_axis_tlast),
        .start            (frac_start_r),
        .done             (frac_done),
        .busy             (),
        .frame_error      (frac_frame_error),
        .error_code       (frac_error_code),
        .threshold_in     (threshold_in),
        .window_len_in    (window_len_in),
        .hit_count_in     (hit_count_in),
        .frame_index      (frac_frame_index),
        .frame_found      (),
        .peak_lag         (frac_peak_lag),
        .peak_metric      (),
        .frac_phase       (frac_frac_phase),
        .frac_phase_valid (frac_frac_phase_valid),
        .m_axis_tdata     (frac_m_tdata),
        .m_axis_tvalid    (frac_m_tvalid),
        .m_axis_tready    (frac_m_tready),
        .m_axis_tlast     (frac_m_tlast)
    );

    // =======================================================================
    // u_ssc — slot_start_controller  (Step 3 observable)
    //
    // Latches slotStartIndex = frame_index + peak_lag on frac_done.
    // Provides constant PSS/SSS window offsets (wires, always valid).
    // =======================================================================
    slot_start_controller #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .BUF_AW      (BUF_AW),
        .INDEX_WIDTH (INDEX_WIDTH)
    ) u_ssc (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .done_in        (frac_done),
        .frame_index_in (frac_frame_index),
        .peak_lag_in    (frac_peak_lag),
        .slot_start     (ssc_slot_start),
        .slot_valid     (ssc_slot_valid),
        .pss_fft_start  (ssc_pss_fft_start),
        .sss_fft_start  (ssc_sss_fft_start),
        .frame_len      (ssc_frame_len)
    );

    // =======================================================================
    // u_extractor — pss_sss_symbol_extractor
    //
    // Receives FRAME_LEN frac-corrected IQ samples from u_frac_corr.
    // Extracts:
    //   PSS window: input samples [CP_LEN .. CP_LEN+NSC-1]
    //   SSS window: input samples [2*CP_LEN+NSC .. FRAME_LEN-1]
    // Emits PSS first (m_symbol_sel=0) then SSS (m_symbol_sel=1).
    // Backpressure applied to u_frac_corr via frac_m_tready.
    //
    // start is pulsed simultaneously with frac_start_r.  The extractor enters
    // S_STREAM immediately and waits for s_axis_tvalid, which only rises after
    // u_frac_corr completes its internal buffer-fill + detection sequence
    // (thousands of cycles) — no first-sample loss.
    // =======================================================================
    pss_sss_symbol_extractor #(
        .NSC               (NSC),
        .CP_LEN            (CP_LEN),
        .IQ_WIDTH          (IQ_WIDTH),
        .FRAME_INDEX_WIDTH (BUF_AW)
    ) u_extractor (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .start           (ext_start_r),
        .pss_fft_start   (ssc_pss_fft_start),
        .sss_fft_start   (ssc_sss_fft_start),
        .frame_len       (ssc_frame_len),
        .s_axis_tvalid   (frac_m_tvalid),
        .s_axis_tready   (frac_m_tready),
        .s_axis_tdata    (frac_m_tdata),
        .s_axis_tlast    (frac_m_tlast),
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

    // =======================================================================
    // u_meyr_fft — meyr_integer_cfo_fft_frontend_top  (Step 5)
    //
    // Accepts time-domain PSS samples (s_symbol_sel=0) from u_extractor,
    // then SSS samples (s_symbol_sel=1).  Internally:
    //   fft256_dual_symbol_frontend: buffers both symbols, applies FFT.
    //   meyr_integer_cfo_freq_estimator_top: term1=FFT(PSS)×conj(FFT(SSS)),
    //     cross-correlates with synthetic term2, peak → int_cfo.
    //
    // IQ packing: m_axis_tdata = {Q[31:16], I[15:0]} (project convention).
    // =======================================================================
    meyr_integer_cfo_fft_frontend_top #(
        .FFT_LEN    (NSC),
        .IQ_WIDTH   (IQ_WIDTH),
        .PROD_WIDTH (32),
        .ACC_WIDTH  (56),
        .SCORE_WIDTH(64),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_meyr_fft (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .start        (meyr_start_r),
        .s_valid      (ext_m_tvalid),
        .s_ready      (ext_m_tready),
        .s_symbol_sel (ext_m_symbol_sel),
        .s_index      (ext_m_symbol_index),
        .s_i          ($signed(ext_m_tdata[IQ_WIDTH-1:0])),
        .s_q          ($signed(ext_m_tdata[2*IQ_WIDTH-1:IQ_WIDTH])),
        .busy         (),
        .done         (meyr_done),
        .error        (meyr_error),
        .int_cfo      (meyr_int_cfo),
        .peak_index   (dbg_meyr_peak_index),
        .peak_score   ()
    );

endmodule
