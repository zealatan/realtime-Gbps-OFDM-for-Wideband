`timescale 1ns/1ps

// timing_frac_cfo_top: CP timing synchronization + fractional CFO estimation.
//
// P3-24A: Replaced broken timing_sync_top+cp_autocorr_core dependency with
// streaming_cp_autocorr.  Streams STREAM_TOTAL samples from the IQ frame
// buffer, detects the Schmidl-Cox autocorrelation peak, then runs
// frac_cfo_estimator (CORDIC atan2) on the latched peak phasor.
//
// FSM: IDLE -> STREAM -> FRAC_CFO -> DONE
//
//   STREAM_TOTAL  = 2*NSC + CP_LEN           (544 defaults)
//   STREAM_OFFSET = NSC + CP_LEN + 3         (291 defaults)
//   peak_lag      = peak_sample_index - STREAM_OFFSET
//
// Buffer read latency: 1 cycle registered.  sca_s_valid_r is the 1-cycle
// delayed buf_rd_en so sample data and s_valid are aligned.

module timing_frac_cfo_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,     // interface-compat only (unused)
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

    // Buffer read port (driven by internal FSM; changed from wire to reg)
    output reg  [ADDR_WIDTH-1:0]             buf_rd_addr,
    output reg                               buf_rd_en,
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

    localparam integer STREAM_OFFSET = NSC + CP_LEN + 9;         // 297: delay_sample(+1)+cmult(3)+avg_fill(CP_LEN-1)+avg_pipe(4)+out_valid_prop(2)
    localparam integer STREAM_TOTAL  = STREAM_OFFSET + NSC;      // 553: covers lags 0..NSC-1
    localparam integer PIPE_DRAIN    = 12;                        // cycles after last s_valid for pipeline to flush
    localparam integer STREAM_DONE   = STREAM_TOTAL + PIPE_DRAIN + 2;
    localparam integer SCA_ACC_W     = 48;

    localparam [1:0]
        S_IDLE     = 2'd0,
        S_STREAM   = 2'd1,
        S_FRAC_CFO = 2'd2,
        S_DONE     = 2'd3;

    reg [1:0] state;

    // -----------------------------------------------------------------------
    // streaming_cp_autocorr wires
    // -----------------------------------------------------------------------
    reg                          sca_aresetn_r;
    reg                          sca_s_valid_r;
    wire [31:0]                  sca_s_data;
    wire signed [SCA_ACC_W-1:0]  sca_p_i;
    wire signed [SCA_ACC_W-1:0]  sca_p_q;
    wire        [SCA_ACC_W-1:0]  sca_energy;
    wire                         sca_out_valid;
    wire [31:0]                  sca_sample_index;

    // Convention: s_data[15:0]=I, s_data[31:16]=Q
    assign sca_s_data = {buf_rd_data_Q, buf_rd_data_I};

    streaming_cp_autocorr #(
        .SAMPLE_W (16),
        .NSC      (NSC),
        .CP_LEN   (CP_LEN),
        .ACC_W    (SCA_ACC_W)
    ) u_sca (
        .clk          (aclk),
        .aresetn      (sca_aresetn_r),
        .s_valid      (sca_s_valid_r),
        .s_data       (sca_s_data),
        .p_i          (sca_p_i),
        .p_q          (sca_p_q),
        .energy       (sca_energy),
        .out_valid    (sca_out_valid),
        .sample_index (sca_sample_index)
    );

    // -----------------------------------------------------------------------
    // Peak detection
    // -----------------------------------------------------------------------
    reg [31:0]              rd_ptr;
    reg [ADDR_WIDTH-1:0]    base_addr_r;
    reg [32:0]              peak_metric_r;
    reg [31:0]              peak_si_r;
    reg signed [SCA_ACC_W-1:0] peak_pi_r;
    reg signed [SCA_ACC_W-1:0] peak_pq_r;
    reg        [SCA_ACC_W-1:0] peak_en_r;
    reg [INDEX_WIDTH-1:0]   peak_lag_r;

    // Manhattan metric using upper 32 bits of 48-bit accumulator
    wire signed [31:0] pi_hi     = sca_p_i[SCA_ACC_W-1:SCA_ACC_W-32];
    wire signed [31:0] pq_hi     = sca_p_q[SCA_ACC_W-1:SCA_ACC_W-32];
    wire [31:0]        abs_pi    = pi_hi[31] ? (~pi_hi + 32'd1) : pi_hi;
    wire [31:0]        abs_pq    = pq_hi[31] ? (~pq_hi + 32'd1) : pq_hi;
    wire [32:0]        metric_now = {1'b0, abs_pi} + {1'b0, abs_pq};

    wire [31:0] lag_raw = (peak_si_r >= STREAM_OFFSET) ?
                          (peak_si_r - STREAM_OFFSET) : 32'd0;

    // Reduce 48-bit accumulators to RESULT_WIDTH bits for outputs and fce
    wire signed [RESULT_WIDTH-1:0] fce_autocorr_I;
    wire signed [RESULT_WIDTH-1:0] fce_autocorr_Q;
    assign fce_autocorr_I = peak_pi_r[SCA_ACC_W-1 -: RESULT_WIDTH];
    assign fce_autocorr_Q = peak_pq_r[SCA_ACC_W-1 -: RESULT_WIDTH];

    assign peak_lag    = peak_lag_r;
    assign peak_metric = peak_metric_r[METRIC_WIDTH-1:0];
    assign peak_corr_i = fce_autocorr_I;
    assign peak_corr_q = fce_autocorr_Q;
    assign peak_energy = peak_en_r[SCA_ACC_W-1 -: RESULT_WIDTH];

    // -----------------------------------------------------------------------
    // frac_cfo_estimator
    // -----------------------------------------------------------------------
    reg  fce_start_r;
    wire fce_done;

    frac_cfo_estimator #(
        .PHASE_WIDTH(PHASE_WIDTH)
    ) u_fce (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (fce_start_r),
        .peak_lag         (peak_lag_r),
        .result_rd_addr   (),
        .autocorr_I       (fce_autocorr_I),
        .autocorr_Q       (fce_autocorr_Q),
        .frac_phase       (frac_phase),
        .frac_phase_valid (frac_phase_valid),
        .done             (fce_done),
        .busy             ()
    );

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            buf_rd_en     <= 1'b0;
            buf_rd_addr   <= {ADDR_WIDTH{1'b0}};
            sca_aresetn_r <= 1'b0;
            sca_s_valid_r <= 1'b0;
            rd_ptr        <= 32'd0;
            base_addr_r   <= {ADDR_WIDTH{1'b0}};
            peak_metric_r <= 33'd0;
            peak_si_r     <= 32'd0;
            peak_pi_r     <= {SCA_ACC_W{1'b0}};
            peak_pq_r     <= {SCA_ACC_W{1'b0}};
            peak_en_r     <= {SCA_ACC_W{1'b0}};
            peak_lag_r    <= {INDEX_WIDTH{1'b0}};
            fce_start_r   <= 1'b0;
        end else begin
            done        <= 1'b0;
            fce_start_r <= 1'b0;

            // 1-cycle delayed buf_rd_en: aligns s_valid with registered buffer data
            sca_s_valid_r <= buf_rd_en;

            case (state)

                S_IDLE: begin
                    buf_rd_en <= 1'b0;
                    if (start && !busy) begin
                        busy          <= 1'b1;
                        base_addr_r   <= base_addr;
                        sca_aresetn_r <= 1'b1;    // release sca from reset
                        peak_metric_r <= 33'd0;
                        peak_si_r     <= 32'd0;
                        peak_pi_r     <= {SCA_ACC_W{1'b0}};
                        peak_pq_r     <= {SCA_ACC_W{1'b0}};
                        peak_en_r     <= {SCA_ACC_W{1'b0}};
                        buf_rd_en     <= 1'b1;
                        buf_rd_addr   <= base_addr;
                        rd_ptr        <= 32'd1;    // sample 0 read issued
                        state         <= S_STREAM;
                    end
                end

                S_STREAM: begin
                    // Issue sequential reads for samples 1..STREAM_TOTAL-1
                    if (rd_ptr < STREAM_TOTAL) begin
                        buf_rd_en   <= 1'b1;
                        buf_rd_addr <= base_addr_r + rd_ptr[ADDR_WIDTH-1:0];
                        rd_ptr      <= rd_ptr + 32'd1;
                    end else begin
                        buf_rd_en <= 1'b0;
                        rd_ptr    <= rd_ptr + 32'd1;
                    end

                    // Continuous peak capture (runs through pipeline drain cycles too)
                    if (sca_out_valid && (metric_now > peak_metric_r)) begin
                        peak_metric_r <= metric_now;
                        peak_si_r     <= sca_sample_index;
                        peak_pi_r     <= sca_p_i;
                        peak_pq_r     <= sca_p_q;
                        peak_en_r     <= sca_energy;
                    end

                    // Transition after all reads and pipeline drain
                    if (rd_ptr >= STREAM_DONE) begin
                        peak_lag_r  <= lag_raw[INDEX_WIDTH-1:0];
                        fce_start_r <= 1'b1;
                        state       <= S_FRAC_CFO;
                    end
                end

                S_FRAC_CFO: begin
                    if (fce_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done          <= 1'b1;
                    busy          <= 1'b0;
                    sca_aresetn_r <= 1'b0;    // reset sca for next transaction
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
