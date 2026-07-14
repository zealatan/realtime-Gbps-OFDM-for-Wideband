`timescale 1ns/1ps
// =============================================================
//  phase3_sync_top.v  (P5-02 L2 rewire)
//
//  Replaces the old serial-Meyr pipeline with the new FFT-corr core.
//
//  Internal pipeline (all live on the frac-corrected stream — no
//  internal replay path):
//
//      s_axis_*
//         │
//         ▼
//    frac_cfo_frame_corrector_top  (u_frac_corr)
//         │  frac_m_*  (frac-corrected IQ + tlast)
//         ▼
//    slot_start_controller         (u_ssc)
//         │  slot_start pulse + PSS/SSS offsets
//         ▼
//    meyr_slot_frontend            (u_slot_fe) — NUM_SYN=2, NUM_DATA=5
//         │  meyr_tdata + pss_first_beat
//         ▼
//    meyr_sync_capture             (u_capture) — 2N buffer, no drops
//         │  out_tdata → s_tdata
//         ▼
//    meyr_cfo_top                  (u_meyr) — cfo_valid + cfo_int + peak_idx
//
//  Outputs retain the original interface (start/done/error +
//  dbg_*) so the legacy AXI wrapper, axi-lite regs, and existing
//  TBs that consume this module's surface continue to wire up.
// =============================================================
module phase3_sync_top #(
    // OFDM timing
    parameter integer NSC             = 256,
    parameter integer CP_LEN          = 32,
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
    parameter integer CORDIC_LATENCY  = 15,
    parameter integer IQ_WIDTH        = 16,
    // ISS-27/08: TX slot = 2 sync + 12 data = 14 symbols (pluto.h NUM_DATA_BLOCKS=12).
    parameter integer NUM_SYN         = 2,
    parameter integer NUM_DATA        = 12
) (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [2*IQ_WIDTH-1:0] s_axis_tdata,
    input  wire                  s_axis_tvalid,
    output wire                  s_axis_tready,
    input  wire                  s_axis_tlast,

    input  wire [ENERGY_WIDTH-1:0]  threshold_in,
    input  wire [6:0]               window_len_in,
    input  wire [3:0]               hit_count_in,

    input  wire        start,
    output reg         done,
    output reg         busy,
    output reg         error,
    output reg  [3:0]  error_code,

    output wire                    dbg_frame_start_valid,
    output wire [BUF_AW-1:0]       dbg_frame_start_index,
    output wire                    dbg_peak_valid,
    output wire [INDEX_WIDTH-1:0]  dbg_peak_index,

    output wire                    dbg_slot_start_valid,
    output wire [BUF_AW-1:0]       dbg_slot_start_index,

    output wire                    dbg_frac_cfo_valid,
    output wire [PHASE_WIDTH-1:0]  dbg_frac_cfo_word,

    output wire [BUF_AW-1:0]       dbg_pss_start,
    output wire [BUF_AW-1:0]       dbg_sss_start,

    output wire                    dbg_integer_cfo_valid,
    output wire [NCO_PHASE_WIDTH-1:0] dbg_integer_cfo_word,

    output wire                    dbg_done,
    output wire [3:0]              dbg_error_code,

    output wire [2*IQ_WIDTH-1:0]   dbg_frac_m_tdata,
    output wire                    dbg_frac_m_tvalid,
    output wire                    dbg_frac_m_tready,
    output wire                    dbg_frac_m_tlast,

    output wire [INDEX_WIDTH-1:0]  dbg_meyr_peak_index
);

    // -----------------------------------------------------------------------
    // Derived parameters
    // -----------------------------------------------------------------------
    localparam integer PSS_OFFSET    = CP_LEN;
    localparam integer SSS_OFFSET    = 2 * CP_LEN + NSC;
    // ISS-27/08: replay all 14 symbols = (NUM_SYN+NUM_DATA)*(NSC+CP_LEN) = 4032
    localparam integer FRAME_LEN     = (NUM_SYN + NUM_DATA) * (NSC + CP_LEN);
    localparam integer NSC_LOG2      = $clog2(NSC);
    localparam integer INT_CFO_SHIFT = 32 - NSC_LOG2;
    localparam integer NLOG2_W       = 5;

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    localparam [1:0] S_IDLE = 2'd0,
                     S_RUN  = 2'd1,
                     S_DONE = 2'd2;
    reg [1:0] state;

    reg frac_start_r;

    // -----------------------------------------------------------------------
    // frac_cfo_frame_corrector_top wires
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0]  frac_m_tdata;
    wire                   frac_m_tvalid;
    wire                   frac_m_tready;
    wire                   frac_m_tlast;

    // ISS-19/22 root cause (2026-06-17 night debug): meyr_slot_frontend
    // (u_slot_fe) consumes frac_m_* without a tready output (it's an always-
    // ready sink). Without this assign frac_m_tready was floating (X/Z),
    // which made corr_accept undriven, halted the frac_corrector FSM at
    // play_rd_ptr=2 in S_CORRECT, and caused 7221 spurious "beats" on
    // m_axis (X-evaluated as 1 in the TB counter). End-to-end consequence:
    // slot_start_controller.done_in never pulsed -> meyr_cfo_top never ran.
    assign frac_m_tready = 1'b1;

    // ISS-19 secondary architectural fix: slot_start_controller's done_in
    // is gated by frac_done (= corrector's S_DONE = AFTER last corrected
    // beat). By that cycle the corrector is back in S_IDLE and frac_m_tvalid
    // has dropped. meyr_slot_frontend gates its activation on
    // (slot_start && s_tvalid) -- a condition that can never co-occur with
    // the original wiring. To align slot_start with sample 0 of the slot,
    // emit a 1-cycle pulse on the FIRST frac_m_tvalid beat after the
    // wrapper-level frac_start_r kicks the corrector. This replaces the
    // ssc-derived slot_start_pulse for slot_frontend driving only.
    reg frac_m_tvalid_q;
    reg frac_m_seen_in_frame;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            frac_m_tvalid_q      <= 1'b0;
            frac_m_seen_in_frame <= 1'b0;
        end else begin
            frac_m_tvalid_q <= frac_m_tvalid;
            if (frac_start_r)
                frac_m_seen_in_frame <= 1'b0;
            else if (frac_m_tvalid)
                frac_m_seen_in_frame <= 1'b1;
        end
    end
    wire frac_m_first_beat = frac_m_tvalid && !frac_m_seen_in_frame;
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
    // New core wires
    // -----------------------------------------------------------------------
    wire [2*IQ_WIDTH-1:0] sfe_meyr_tdata;
    wire                  sfe_meyr_tvalid;
    wire                  sfe_pss_first_beat;
    wire [2*IQ_WIDTH-1:0] sfe_data_tdata;
    wire                  sfe_data_tvalid;
    wire  [3:0]           sfe_data_sym_idx;

    wire [2*IQ_WIDTH-1:0] cap_out_tdata;
    wire                  cap_out_tvalid;
    wire                  cap_out_tready;
    wire                  cap_overrun;
    wire                  cap_done;

    wire signed [31:0]    meyr_cfo_int;
    wire [12:0]           meyr_peak_idx;       // N_LOG2_MAX (12) + 1
    wire                  meyr_cfo_valid;

    // slot_start_controller produces an INDEX, not a one-cycle pulse aligned
    // with the live stream. The slot_frontend wants a single-cycle pulse on
    // the sample 0 of the slot. Generate that pulse by triggering on
    // ssc_slot_valid edge gated by frac_m_tvalid.
    reg ssc_slot_valid_q;
    wire slot_start_pulse;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) ssc_slot_valid_q <= 1'b0;
        else          ssc_slot_valid_q <= ssc_slot_valid;
    end
    assign slot_start_pulse = ssc_slot_valid & ~ssc_slot_valid_q;

    // -----------------------------------------------------------------------
    // Integer CFO step word and latch on cfo_valid
    // -----------------------------------------------------------------------
    wire signed [15:0] meyr_int_cfo = meyr_cfo_int[15:0];
    wire signed [NCO_PHASE_WIDTH-1:0] int_cfo_ext =
        {{(NCO_PHASE_WIDTH-16){meyr_int_cfo[15]}}, meyr_int_cfo};
    wire signed [NCO_PHASE_WIDTH-1:0] int_cfo_step_word =
        (-int_cfo_ext) << INT_CFO_SHIFT;

    reg signed [NCO_PHASE_WIDTH-1:0] int_cfo_step_word_r;
    reg                              int_cfo_valid_r;
    reg [INDEX_WIDTH-1:0]            meyr_peak_index_r;

    // -----------------------------------------------------------------------
    // Debug output assigns
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

    assign dbg_frac_m_tdata  = frac_m_tdata;
    assign dbg_frac_m_tvalid = frac_m_tvalid;
    assign dbg_frac_m_tready = frac_m_tready;
    assign dbg_frac_m_tlast  = frac_m_tlast;
    assign dbg_meyr_peak_index = meyr_peak_index_r;

    // -----------------------------------------------------------------------
    // Main FSM — preserves the legacy start/done contract while the new
    // core runs continuously underneath: done pulses on cfo_valid.
    // -----------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state               <= S_IDLE;
            done                <= 1'b0;
            busy                <= 1'b0;
            error               <= 1'b0;
            error_code          <= 4'd0;
            frac_start_r        <= 1'b0;
            int_cfo_step_word_r <= {NCO_PHASE_WIDTH{1'b0}};
            int_cfo_valid_r     <= 1'b0;
            meyr_peak_index_r   <= {INDEX_WIDTH{1'b0}};
        end else begin
            done            <= 1'b0;
            frac_start_r    <= 1'b0;
            int_cfo_valid_r <= 1'b0;

            case (state)
                S_IDLE: begin
                    error      <= 1'b0;
                    error_code <= 4'd0;
                    if (start && !busy) begin
                        busy         <= 1'b1;
                        frac_start_r <= 1'b1;
                        state        <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (frac_frame_error) begin
                        error      <= 1'b1;
                        error_code <= frac_error_code;
                        state      <= S_DONE;
                    end else if (meyr_cfo_valid) begin
                        int_cfo_step_word_r <= int_cfo_step_word;
                        int_cfo_valid_r     <= 1'b1;
                        meyr_peak_index_r   <= meyr_peak_idx[INDEX_WIDTH-1:0];
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
    // u_frac_corr — UNCHANGED (frac_cfo_frame_corrector_top)
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
    // u_ssc — UNCHANGED (slot_start_controller)
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
    // u_slot_fe — meyr_slot_frontend (new): consumes the frac-corrected
    // stream and routes PSS+SSS payload to the new core via sync_capture.
    // =======================================================================
    meyr_slot_frontend #(
        .N        (NSC),
        .CP_LEN   (CP_LEN),
        .NUM_SYN  (NUM_SYN),
        .NUM_DATA (NUM_DATA)
    ) u_slot_fe (
        .clk            (aclk),
        .rst_n          (aresetn),
        .s_tdata        (frac_m_tdata),
        .s_tvalid       (frac_m_tvalid),
        // ISS-19: was slot_start_pulse (= ssc edge, fires after corrector done).
        // Switched to frac_m_first_beat which fires on sample 0 of corrected
        // stream so meyr_slot_frontend's (slot_start && s_tvalid) condition is
        // satisfied. ssc-derived slot_start_pulse is still kept for
        // dbg_slot_start_valid which downstream consumers may use.
        .slot_start     (frac_m_first_beat),
        .meyr_tdata     (sfe_meyr_tdata),
        .meyr_tvalid    (sfe_meyr_tvalid),
        .pss_first_beat (sfe_pss_first_beat),
        .meyr_tready    (1'b1),
        .data_tdata     (sfe_data_tdata),
        .data_tvalid    (sfe_data_tvalid),
        .data_sym_idx   (sfe_data_sym_idx)
    );

    // =======================================================================
    // u_capture — meyr_sync_capture: 2N buffer between slot_frontend and core
    // =======================================================================
    meyr_sync_capture #(
        .N      (NSC),
        .DATA_W (2*IQ_WIDTH)
    ) u_capture (
        .clk            (aclk),
        .rst_n          (aresetn),
        .in_tdata       (sfe_meyr_tdata),
        .in_tvalid      (sfe_meyr_tvalid),
        .pss_first_beat (sfe_pss_first_beat),
        .out_tdata      (cap_out_tdata),
        .out_tvalid     (cap_out_tvalid),
        .out_tready     (cap_out_tready),
        .overrun_event  (cap_overrun),
        .capture_done   (cap_done)
    );

    // =======================================================================
    // u_meyr — meyr_cfo_top: the new FFT-correlation integer-CFO core.
    // ROM is loaded at runtime through the wrapper-level rom_* interface
    // (exposed by phase3_sync_axis_dma_wrapper); here we tie rom_we low and
    // expect the wrapper to drive ROM writes prior to the first frame.
    // =======================================================================
    meyr_cfo_top #(
        .N_LOG2_MAX(12)
    ) u_meyr (
        .clk          (aclk),
        .rst_n        (aresetn),
        .n_log2       (NSC_LOG2[NLOG2_W-1:0]),
        .rom_we       (1'b0),
        .rom_waddr    (13'b0),
        .rom_wdata    (64'b0),
        .s_tdata      (cap_out_tdata),
        .s_tvalid     (cap_out_tvalid),
        .s_tready     (cap_out_tready),
        .cfo_int      (meyr_cfo_int),
        .peak_idx     (meyr_peak_idx),
        .cfo_valid    (meyr_cfo_valid),
        .dbg_ifft_tdata (),
        .dbg_ifft_tvalid(),
        .dbg_ifft_tlast ()
    );

    // Silence currently-unused signals (slot frontend data path is
    // exposed via dbg taps in a follow-up; ROM load lives at wrapper).
    wire _u_data_tdata    = |sfe_data_tdata;
    wire _u_data_tvalid   = sfe_data_tvalid;
    wire _u_data_sym_idx  = |sfe_data_sym_idx;
    wire _u_cap_overrun   = cap_overrun;
    wire _u_cap_done      = cap_done;

endmodule
