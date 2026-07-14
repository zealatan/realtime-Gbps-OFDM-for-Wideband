`timescale 1ns/1ps

// timing_sync_top: Schmidl-Cox CP timing synchronization.
//
// Frozen-architecture module instantiating streaming_cp_autocorr and
// peak_detector (streaming argmax).
//
// Metric: Manhattan |P_I[47:16]| + |P_Q[47:16]| — matches working algorithm
// from timing_frac_cfo_top so peak_lag is consistent.
//
// The SCA fires out_valid permanently from the first avg_pi_stb onward,
// including for the initial CP_LEN-1 partial-window outputs.  Only outputs
// with sca_sample_index >= STREAM_OFFSET correspond to full windows (physical
// lag 0..NSC-1).  peak_detector is gated to receive only full-window samples;
// its 0-based peak_index maps directly to physical lag.
//
// FSM: S_IDLE → S_STREAM → S_DONE

module timing_sync_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,     // interface-compat only
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32
) (
    input  wire                           aclk,
    input  wire                           aresetn,

    input  wire                           start,
    input  wire [ADDR_WIDTH-1:0]          base_addr,
    output reg                            done,
    output reg                            busy,

    output reg  [ADDR_WIDTH-1:0]          buf_rd_addr,
    output reg                            buf_rd_en,
    input  wire signed [15:0]             buf_rd_data_I,
    input  wire signed [15:0]             buf_rd_data_Q,

    output reg  [INDEX_WIDTH-1:0]         peak_lag,
    output reg  [METRIC_WIDTH-1:0]        peak_metric,
    output reg  signed [RESULT_WIDTH-1:0] peak_corr_i,
    output reg  signed [RESULT_WIDTH-1:0] peak_corr_q,
    output reg         [RESULT_WIDTH-1:0] peak_energy
);

    localparam integer SCA_ACC_W     = 48;
    // Latency breakdown (matches timing_frac_cfo_top):
    //   delay_sample(+1)+cmult(3)+avg_fill(CP_LEN-1)+avg_pipe(4)+out_valid_prop(2)
    localparam integer STREAM_OFFSET = NSC + CP_LEN + 9;            // 297 default
    localparam integer STREAM_TOTAL  = STREAM_OFFSET + NSC;         // 553 default
    localparam integer PIPE_DRAIN    = 12;
    localparam integer STREAM_DONE   = STREAM_TOTAL + PIPE_DRAIN + 2; // 567 default
    localparam integer PD_CNT_W      = $clog2(NSC + 1);             // 9 default

    // Index of the last full-window sample (inclusive)
    localparam integer LAST_FULL_IDX = STREAM_OFFSET + NSC - 1;     // 552 default

    localparam [1:0]
        S_IDLE   = 2'd0,
        S_STREAM = 2'd1,
        S_DONE   = 2'd2;

    reg [1:0] state;

    // -----------------------------------------------------------------------
    // streaming_cp_autocorr
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
        .SAMPLE_W(16), .NSC(NSC), .CP_LEN(CP_LEN), .ACC_W(SCA_ACC_W)
    ) u_sca (
        .clk         (aclk),
        .aresetn     (sca_aresetn_r),
        .s_valid     (sca_s_valid_r),
        .s_data      (sca_s_data),
        .p_i         (sca_p_i),
        .p_q         (sca_p_q),
        .energy      (sca_energy),
        .out_valid   (sca_out_valid),
        .sample_index(sca_sample_index)
    );

    // -----------------------------------------------------------------------
    // Manhattan metric — identical to timing_frac_cfo_top
    // -----------------------------------------------------------------------
    wire signed [31:0] pi_hi      = sca_p_i[SCA_ACC_W-1:SCA_ACC_W-32];
    wire signed [31:0] pq_hi      = sca_p_q[SCA_ACC_W-1:SCA_ACC_W-32];
    wire [31:0]        abs_pi     = pi_hi[31] ? (~pi_hi + 32'd1) : pi_hi;
    wire [31:0]        abs_pq     = pq_hi[31] ? (~pq_hi + 32'd1) : pq_hi;
    wire [32:0]        metric_now = {1'b0, abs_pi} + {1'b0, abs_pq};

    // Full-window gate: only sample_index >= STREAM_OFFSET are complete windows
    wire full_win_valid = sca_out_valid &&
                          (sca_sample_index >= STREAM_OFFSET[31:0]);

    // -----------------------------------------------------------------------
    // peak_detector: receives NSC full-window metric values
    // peak_index is 0-based count of full-window outputs = physical lag
    // -----------------------------------------------------------------------
    reg                    pd_start_r;
    reg [PD_CNT_W-1:0]     full_win_cnt;    // count of full-window SCA outputs seen
    wire [INDEX_WIDTH-1:0] pd_peak_index;
    wire [32:0]            pd_peak_value;
    wire                   pd_done;

    // data_last fires on the NSCth full-window output
    wire pd_data_last = full_win_valid && (full_win_cnt == (NSC - 1));

    peak_detector #(
        .METRIC_WIDTH(33),
        .INDEX_WIDTH (INDEX_WIDTH),
        .COUNT_WIDTH (PD_CNT_W)
    ) u_pd (
        .aclk      (aclk),
        .aresetn   (aresetn),
        .start     (pd_start_r),
        .max_count ({PD_CNT_W{1'b0}}),   // 0 = no count limit
        .data_in   (metric_now),
        .data_valid(full_win_valid),
        .data_last (pd_data_last),
        .peak_index(pd_peak_index),
        .peak_value(pd_peak_value),
        .done      (pd_done),
        .busy      (),
        .error     ()
    );

    // -----------------------------------------------------------------------
    // Shadow phasor tracker: parallel strict-> comparison mirrors peak_detector
    // (gated to full-window outputs to match peak_detector's view)
    // -----------------------------------------------------------------------
    reg [32:0]                 shadow_max_r;
    reg signed [SCA_ACC_W-1:0] peak_pi_r;
    reg signed [SCA_ACC_W-1:0] peak_pq_r;
    reg        [SCA_ACC_W-1:0] peak_en_r;

    // -----------------------------------------------------------------------
    // Streaming read control
    // -----------------------------------------------------------------------
    reg [31:0]           rd_ptr;
    reg [ADDR_WIDTH-1:0] base_addr_r;
    reg                  pd_done_latch;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            buf_rd_en     <= 1'b0;
            buf_rd_addr   <= {ADDR_WIDTH{1'b0}};
            sca_aresetn_r <= 1'b0;
            sca_s_valid_r <= 1'b0;
            pd_start_r    <= 1'b0;
            full_win_cnt  <= {PD_CNT_W{1'b0}};
            rd_ptr        <= 32'd0;
            base_addr_r   <= {ADDR_WIDTH{1'b0}};
            peak_lag      <= {INDEX_WIDTH{1'b0}};
            peak_metric   <= {METRIC_WIDTH{1'b0}};
            peak_corr_i   <= {RESULT_WIDTH{1'b0}};
            peak_corr_q   <= {RESULT_WIDTH{1'b0}};
            peak_energy   <= {RESULT_WIDTH{1'b0}};
            shadow_max_r  <= 33'd0;
            peak_pi_r     <= {SCA_ACC_W{1'b0}};
            peak_pq_r     <= {SCA_ACC_W{1'b0}};
            peak_en_r     <= {SCA_ACC_W{1'b0}};
            pd_done_latch <= 1'b0;
        end else begin
            done       <= 1'b0;
            pd_start_r <= 1'b0;

            // 1-cycle delay aligns s_valid with registered buffer read data
            sca_s_valid_r <= buf_rd_en;

            // Sticky latch for pd_done
            if (pd_done)
                pd_done_latch <= 1'b1;

            // Shadow phasor tracking (full-window only, strict > matches peak_detector)
            if (full_win_valid && (metric_now > shadow_max_r)) begin
                shadow_max_r <= metric_now;
                peak_pi_r    <= sca_p_i;
                peak_pq_r    <= sca_p_q;
                peak_en_r    <= sca_energy;
            end

            case (state)

                S_IDLE: begin
                    buf_rd_en <= 1'b0;
                    if (start && !busy) begin
                        busy          <= 1'b1;
                        base_addr_r   <= base_addr;
                        sca_aresetn_r <= 1'b1;
                        pd_start_r    <= 1'b1;
                        full_win_cnt  <= {PD_CNT_W{1'b0}};
                        shadow_max_r  <= 33'd0;
                        pd_done_latch <= 1'b0;
                        buf_rd_en     <= 1'b1;
                        buf_rd_addr   <= base_addr;
                        rd_ptr        <= 32'd1;   // sample 0 read already issued
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

                    // Count full-window outputs only (stops at NSC-1 to prevent overflow)
                    if (full_win_valid && !pd_data_last)
                        full_win_cnt <= full_win_cnt + 1;

                    // After all reads and pipeline drain, latch results and exit
                    if (rd_ptr >= STREAM_DONE && (pd_done_latch || pd_done)) begin
                        peak_lag    <= pd_peak_index;
                        peak_metric <= pd_peak_value[METRIC_WIDTH-1:0];
                        peak_corr_i <= peak_pi_r[SCA_ACC_W-1 -: RESULT_WIDTH];
                        peak_corr_q <= peak_pq_r[SCA_ACC_W-1 -: RESULT_WIDTH];
                        peak_energy <= peak_en_r[SCA_ACC_W-1 -: RESULT_WIDTH];
                        state       <= S_DONE;
                    end
                end

                S_DONE: begin
                    done          <= 1'b1;
                    busy          <= 1'b0;
                    sca_aresetn_r <= 1'b0;
                    pd_done_latch <= 1'b0;
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

`ifdef TIMING_PROBE
    integer tst_rd_cnt;
    always @(posedge aclk) begin
        if (!aresetn) begin
            tst_rd_cnt <= 0;
        end else begin
            if (pd_start_r)
                $display("[TST] pd_start base_addr_r=%0d @%0t", base_addr_r, $time);
            if (buf_rd_en) begin
                if (tst_rd_cnt < 560) begin
                    $display("[TST] RD[%0d]: t=%0t addr=%0d rdI=%0d rdQ=%0d sca_sv=%0b si=%0d",
                             tst_rd_cnt, $time, buf_rd_addr,
                             $signed(buf_rd_data_I), $signed(buf_rd_data_Q),
                             sca_s_valid_r, sca_sample_index);
                    tst_rd_cnt <= tst_rd_cnt + 1;
                end
            end
            if (full_win_valid)
                $display("[TST] FWV: fwc=%0d si=%0d metric=%0d",
                         full_win_cnt, sca_sample_index, metric_now);
            if (state == S_DONE)
                $display("[TST] RESULT peak_lag=%0d peak_metric=%0d",
                         peak_lag, peak_metric);
        end
    end
`endif

endmodule
