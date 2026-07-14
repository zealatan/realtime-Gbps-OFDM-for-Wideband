`timescale 1ns/1ps

// frame_frac_cfo_top: CP timing synchronization + fractional CFO estimation.
//
// Frozen-architecture wrapper encapsulating:
//   timing_sync_top    — Schmidl-Cox autocorr peak detection (streaming_cp_autocorr + peak_detector)
//   frac_cfo_estimator — CORDIC atan2 for fractional CFO phase
//
// External interface is identical to timing_frac_cfo_top; frac_cfo_frame_corrector_top
// instantiates this module as u_tfc.
//
// FSM: S_IDLE → S_TIMING → S_FRAC_CFO → S_DONE

module frame_frac_cfo_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32,
    parameter integer PHASE_WIDTH  = 16
) (
    input  wire                              aclk,
    input  wire                              aresetn,

    // Control
    input  wire                              start,
    input  wire [ADDR_WIDTH-1:0]             base_addr,
    output reg                               done,
    output reg                               busy,

    // Buffer read port (driven by timing_sync_top during S_TIMING)
    output wire [ADDR_WIDTH-1:0]             buf_rd_addr,
    output wire                              buf_rd_en,
    input  wire signed [15:0]                buf_rd_data_I,
    input  wire signed [15:0]                buf_rd_data_Q,

    // Timing outputs (stable after done)
    output wire [INDEX_WIDTH-1:0]            peak_lag,
    output wire [METRIC_WIDTH-1:0]           peak_metric,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_i,
    output wire signed [RESULT_WIDTH-1:0]    peak_corr_q,
    output wire        [RESULT_WIDTH-1:0]    peak_energy,

    // Fractional CFO output
    output wire [PHASE_WIDTH-1:0]            frac_phase,
    output wire                              frac_phase_valid
);

    localparam [1:0]
        S_IDLE     = 2'd0,
        S_TIMING   = 2'd1,
        S_FRAC_CFO = 2'd2,
        S_DONE     = 2'd3;

    reg [1:0] state;

    // -----------------------------------------------------------------------
    // timing_sync_top
    // -----------------------------------------------------------------------
    reg                            tst_start_r;
    wire                           tst_done;
    wire [ADDR_WIDTH-1:0]          tst_buf_rd_addr;
    wire                           tst_buf_rd_en;
    wire [INDEX_WIDTH-1:0]         tst_peak_lag;
    wire [METRIC_WIDTH-1:0]        tst_peak_metric;
    wire signed [RESULT_WIDTH-1:0] tst_peak_corr_i;
    wire signed [RESULT_WIDTH-1:0] tst_peak_corr_q;
    wire        [RESULT_WIDTH-1:0] tst_peak_energy;

    timing_sync_top #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ACC_WIDTH   (ACC_WIDTH),
        .METRIC_WIDTH(METRIC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH)
    ) u_tst (
        .aclk         (aclk),
        .aresetn      (aresetn),
        .start        (tst_start_r),
        .base_addr    (base_addr),
        .done         (tst_done),
        .busy         (),
        .buf_rd_addr  (tst_buf_rd_addr),
        .buf_rd_en    (tst_buf_rd_en),
        .buf_rd_data_I(buf_rd_data_I),
        .buf_rd_data_Q(buf_rd_data_Q),
        .peak_lag     (tst_peak_lag),
        .peak_metric  (tst_peak_metric),
        .peak_corr_i  (tst_peak_corr_i),
        .peak_corr_q  (tst_peak_corr_q),
        .peak_energy  (tst_peak_energy)
    );

    // Buffer read port: passthrough from timing_sync_top during S_TIMING, idle otherwise
    assign buf_rd_en   = (state == S_TIMING) ? tst_buf_rd_en   : 1'b0;
    assign buf_rd_addr = (state == S_TIMING) ? tst_buf_rd_addr : {ADDR_WIDTH{1'b0}};

    // -----------------------------------------------------------------------
    // Latched timing results (stable from tst_done until next start)
    // -----------------------------------------------------------------------
    reg [INDEX_WIDTH-1:0]         peak_lag_r;
    reg [METRIC_WIDTH-1:0]        peak_metric_r;
    reg signed [RESULT_WIDTH-1:0] peak_corr_i_r;
    reg signed [RESULT_WIDTH-1:0] peak_corr_q_r;
    reg        [RESULT_WIDTH-1:0] peak_energy_r;

    assign peak_lag    = peak_lag_r;
    assign peak_metric = peak_metric_r;
    assign peak_corr_i = peak_corr_i_r;
    assign peak_corr_q = peak_corr_q_r;
    assign peak_energy = peak_energy_r;

    // -----------------------------------------------------------------------
    // frac_cfo_estimator
    // -----------------------------------------------------------------------
    reg  fce_start_r;
    wire fce_done;

    frac_cfo_estimator #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) u_fce (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .start           (fce_start_r),
        .peak_lag        (peak_lag_r),
        .result_rd_addr  (),
        .autocorr_I      (peak_corr_i_r),
        .autocorr_Q      (peak_corr_q_r),
        .frac_phase      (frac_phase),
        .frac_phase_valid(frac_phase_valid),
        .done            (fce_done),
        .busy            ()
    );

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            tst_start_r   <= 1'b0;
            fce_start_r   <= 1'b0;
            peak_lag_r    <= {INDEX_WIDTH{1'b0}};
            peak_metric_r <= {METRIC_WIDTH{1'b0}};
            peak_corr_i_r <= {RESULT_WIDTH{1'b0}};
            peak_corr_q_r <= {RESULT_WIDTH{1'b0}};
            peak_energy_r <= {RESULT_WIDTH{1'b0}};
        end else begin
            done        <= 1'b0;
            tst_start_r <= 1'b0;
            fce_start_r <= 1'b0;

            case (state)

                S_IDLE: begin
                    if (start && !busy) begin
                        busy        <= 1'b1;
                        tst_start_r <= 1'b1;
                        state       <= S_TIMING;
                    end
                end

                S_TIMING: begin
                    if (tst_done) begin
                        // Latch timing results and start fractional CFO estimation
                        peak_lag_r    <= tst_peak_lag;
                        peak_metric_r <= tst_peak_metric;
                        peak_corr_i_r <= tst_peak_corr_i;
                        peak_corr_q_r <= tst_peak_corr_q;
                        peak_energy_r <= tst_peak_energy;
                        fce_start_r   <= 1'b1;
                        state         <= S_FRAC_CFO;
                    end
                end

                S_FRAC_CFO: begin
                    if (fce_done) begin
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

`ifdef TIMING_PROBE
    always @(posedge aclk) begin
        if ($time > 8540000 && $time < 8600000) begin
            $display("[FFCT] t=%0t state=%0d tst_start_r=%0b tst_buf_rd_en=%0b buf_rd_en=%0b buf_rd_addr=%0d",
                     $time, state, tst_start_r, tst_buf_rd_en, buf_rd_en, buf_rd_addr);
        end
    end
`endif

endmodule
