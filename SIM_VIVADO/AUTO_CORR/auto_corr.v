`timescale 1ns/1ps

module auto_corr #(
    parameter integer WINDOW_SHIFT = 5,   // CP_LEN = 32
    parameter integer DELAY_SHIFT  = 8,   // delay = 256
    parameter integer FFT_SIZE     = 256,
    parameter integer CNT_WIDTH    = 8,
    parameter integer PEAK_WIDTH   = 24,
    parameter integer IQ_WIDTH     = 16,
    parameter integer SHIFT_BITS   = 40
)(
    input  wire                           clock,
    input  wire                           reset,
    input  wire                           enable,

    input  wire [31:0]                    sample_in,
    input  wire                           sample_in_strobe,

    output wire                           start_index,

    output wire signed [31:0]             debug_metric_I,
    output wire                           debug_metric_I_strobe,
    output wire signed [31:0]             debug_metric_Q,
    output wire                           debug_metric_Q_strobe,
    output wire        [32:0]             debug_metric_Norm,
    output wire                           debug_metric_Norm_strobe,
    output wire        [64:0]             debug_metric_absC,
    output wire                           debug_metric_absC_strobe,

    output reg  signed [PEAK_WIDTH-1:0]   peak_I,
    output reg  signed [PEAK_WIDTH-1:0]   peak_Q,
    output reg  [CNT_WIDTH-1:0]           debug_peak_idx,
    output wire [CNT_WIDTH-1:0]           raddr,
    output reg                            peak_found_stb,
    output wire signed [33:0] debug_vdb_metric,
    output wire               debug_vdb_metric_stb,

    input  wire                           set_stb,
    input  wire [7:0]                     set_addr,
    input  wire [31:0]                    set_data
);

    localparam ADDR_THRESHOLD_ENABLE = 8'h00;
    localparam ADDR_MAG_THRESHOLD_L  = 8'h01;
    localparam ADDR_MAG_THRESHOLD_H  = 8'h02;

    //--------------------------------------------------------------------------
    // control registers
    //--------------------------------------------------------------------------
    reg         threshold_enable;
    reg [64:0]  mag_sq_threshold;

    //--------------------------------------------------------------------------
    // delay line
    //--------------------------------------------------------------------------
    wire [31:0] sample_in_delay;
    wire        sample_in_delay_strobe;

    delay_sample #(
        .DATA_WIDTH (32),
        .DELAY_SHIFT(DELAY_SHIFT)
    ) delay_inst (
        .clock         (clock),
        .enable        (enable),
        .reset         (reset),
        .data_in       (sample_in),
        .input_strobe  (sample_in_strobe),
        .data_out      (sample_in_delay),
        .output_strobe (sample_in_delay_strobe)
    );

    //--------------------------------------------------------------------------
    // current conjugate path
    //--------------------------------------------------------------------------
    wire [15:0] q_part_neg;
    wire [31:0] sample_in_conj_comb;

    reg  [31:0] sample_in_conj_reg;
    reg         conj_stb_reg;

    assign q_part_neg          = (~sample_in[15:0]) + 16'd1;
    assign sample_in_conj_comb = {sample_in[31:16], q_part_neg};

    always @(posedge clock) begin
        if (reset) begin
            sample_in_conj_reg <= 32'd0;
            conj_stb_reg       <= 1'b0;
        end else if (enable) begin
            if (sample_in_strobe) begin
                sample_in_conj_reg <= sample_in_conj_comb;
                conj_stb_reg       <= 1'b1;
            end else begin
                conj_stb_reg       <= 1'b0;
            end
        end else begin
            conj_stb_reg <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // complex multiplication: x[n-D] * conj(x[n])
    //--------------------------------------------------------------------------
    wire [31:0] Mul_out_I;
    wire [31:0] Mul_out_Q;
    wire        Mul_out_strobe;

    complex_mult complex_mult_inst (
        .clock         (clock),
        .enable        (enable),
        .reset         (reset),
        .a_i           (sample_in_delay[31:16]),
        .a_q           (sample_in_delay[15:0]),
        .b_i           (sample_in_conj_reg[31:16]),
        .b_q           (sample_in_conj_reg[15:0]),
        .input_strobe  (sample_in_delay_strobe),
        .p_i           (Mul_out_I),
        .p_q           (Mul_out_Q),
        .output_strobe (Mul_out_strobe)
    );

    //--------------------------------------------------------------------------
    // power path (33-bit, pipelined)
    //--------------------------------------------------------------------------
    wire [32:0] pwr_cur;
    wire        pwr_cur_stb;
    wire [32:0] pwr_dly;
    wire        pwr_dly_stb;

    sample_power_sq #(
        .IQ_WIDTH (IQ_WIDTH),
        .OUT_WIDTH(33)
    ) pwr_cur_inst (
        .clock       (clock),
        .enable      (enable),
        .reset       (reset),
        .sample_in   (sample_in),
        .input_strobe(sample_in_strobe),
        .power_out   (pwr_cur),
        .power_out_stb(pwr_cur_stb)
    );

    sample_power_sq #(
        .IQ_WIDTH (IQ_WIDTH),
        .OUT_WIDTH(33)
    ) pwr_dly_inst (
        .clock       (clock),
        .enable      (enable),
        .reset       (reset),
        .sample_in   (sample_in_delay),
        .input_strobe(sample_in_delay_strobe),
        .power_out   (pwr_dly),
        .power_out_stb(pwr_dly_stb)
    );

    // align current power to delayed power path if needed
    wire [32:0] pwr_cur_aligned;
    wire        pwr_sum_stb;
    reg  [32:0] pwr_sum_reg;

    delayT #(
        .DATA_WIDTH(33),
        .DELAY((1<<DELAY_SHIFT)+1)
    ) pwr_cur_align_inst (
        .clock   (clock),
        .reset   (reset),
        .data_in (pwr_cur),
        .data_out(pwr_cur_aligned)
    );

    assign pwr_sum_stb = pwr_dly_stb;

    always @(posedge clock) begin
        if (reset) begin
            pwr_sum_reg <= 33'd0;
        end else if (enable && pwr_dly_stb) begin
            pwr_sum_reg <= pwr_dly + pwr_cur_aligned;
        end
    end

    //--------------------------------------------------------------------------
    // moving average
    //--------------------------------------------------------------------------
    wire [63:0] AVG_out_I;
    wire [63:0] AVG_out_Q;
    wire [64:0] AVG_out_Norm;

    moving_avg_optimized #(
        .DATA_WIDTH  (32),
        .WINDOW_SHIFT(WINDOW_SHIFT)
    ) moving_avg_i_inst (
        .clock         (clock),
        .reset         (reset),
        .enable        (enable),
        .data_in       (Mul_out_I),
        .input_strobe  (Mul_out_strobe),
        .data_out      (AVG_out_I),
        .output_strobe (debug_metric_I_strobe)
    );

    moving_avg_optimized #(
        .DATA_WIDTH  (32),
        .WINDOW_SHIFT(WINDOW_SHIFT)
    ) moving_avg_q_inst (
        .clock         (clock),
        .reset         (reset),
        .enable        (enable),
        .data_in       (Mul_out_Q),
        .input_strobe  (Mul_out_strobe),
        .data_out      (AVG_out_Q),
        .output_strobe (debug_metric_Q_strobe)
    );

    moving_avg_optimized #(
        .DATA_WIDTH  (33),
        .WINDOW_SHIFT(WINDOW_SHIFT)
    ) moving_avg_n_inst (
        .clock         (clock),
        .reset         (reset),
        .enable        (enable),
        .data_in       (pwr_sum_reg),
        .input_strobe  (pwr_sum_stb),
        .data_out      (AVG_out_Norm),
        .output_strobe (debug_metric_Norm_strobe)
    );

    //--------------------------------------------------------------------------
    // debug outputs
    //--------------------------------------------------------------------------
    //assign debug_metric_I    = $signed(AVG_out_I) >>> 12;
    //assign debug_metric_Q    = $signed(AVG_out_Q) >>> 12;
    
    assign debug_metric_I    = AVG_out_I;
    assign debug_metric_Q    = AVG_out_Q;    
    assign debug_metric_Norm = AVG_out_Norm;
 //--------------------------------------------------------------------------
    // |C| path using complex_to_mag
    //--------------------------------------------------------------------------
    wire [31:0] mag_out;
    wire        mag_out_stb;

    complex_to_mag #(
        .DATA_WIDTH(32)
    ) complex_to_mag_inst (
        .clock        (clock),
        .enable       (enable),
        .reset        (reset),
        .i            (debug_metric_I),
        .q            (debug_metric_Q),
        .input_strobe (debug_metric_I_strobe),
        .mag          (mag_out),
        .mag_stb      (mag_out_stb)
    );

    assign debug_metric_absC        = mag_out;
    assign debug_metric_absC_strobe = mag_out_stb;

    //--------------------------------------------------------------------------
    // Align norm / AVG_out_I / AVG_out_Q to |C| path
    // complex_to_mag has 3-cycle latency
    //--------------------------------------------------------------------------
    wire [32:0] metric_norm_aligned;
    wire [63:0] AVG_out_I_aligned;
    wire [63:0] AVG_out_Q_aligned;

    delayT #(
        .DATA_WIDTH(33),
        .DELAY(3)
    ) norm_align_inst (
        .clock   (clock),
        .reset   (reset),
        .data_in (AVG_out_Norm),
        .data_out(metric_norm_aligned)
    );

    delayT #(
        .DATA_WIDTH(64),
        .DELAY(3)
    ) avg_i_align_inst (
        .clock   (clock),
        .reset   (reset),
        .data_in (AVG_out_I),
        .data_out(AVG_out_I_aligned)
    );

    delayT #(
        .DATA_WIDTH(64),
        .DELAY(3)
    ) avg_q_align_inst (
        .clock   (clock),
        .reset   (reset),
        .data_in (AVG_out_Q),
        .data_out(AVG_out_Q_aligned)
    );

    wire signed [PEAK_WIDTH-1:0] avg_i_reduced;
    wire signed [PEAK_WIDTH-1:0] avg_q_reduced;

    assign avg_i_reduced = $signed(AVG_out_I_aligned) >>> SHIFT_BITS;
    assign avg_q_reduced = $signed(AVG_out_Q_aligned) >>> SHIFT_BITS;

    //--------------------------------------------------------------------------
    // Van de Beek metric
    // S[m] = 2*|C[m]| - P[m]
    //--------------------------------------------------------------------------
    reg  signed [33:0] vdb_metric;
    reg                vdb_metric_stb;

    always @(posedge clock) begin
        if (reset) begin
            vdb_metric     <= 34'sd0;
            vdb_metric_stb <= 1'b0;
        end else if (enable) begin
            vdb_metric_stb <= mag_out_stb;
            if (mag_out_stb) begin
                vdb_metric <= $signed({1'b0, mag_out, 1'b0}) - $signed({1'b0, metric_norm_aligned});
            end
        end else begin
            vdb_metric_stb <= 1'b0;
        end
    end

    assign debug_metric_S        = vdb_metric[31:0];
    assign debug_metric_S_strobe = vdb_metric_stb;
    
    assign debug_vdb_metric     = vdb_metric;
    assign debug_vdb_metric_stb = vdb_metric_stb;

    //--------------------------------------------------------------------------
    // Peak search over FFT window using Van de Beek metric
    //--------------------------------------------------------------------------
    reg [CNT_WIDTH-1:0]  sym_cnt;
    reg signed [33:0]    peak_metric;
    reg                  peak_valid;
    reg                  start_index_reg;

    assign raddr       = FFT_SIZE - 1 - debug_peak_idx;
    assign start_index = start_index_reg;
    
    /*
    always @(posedge clock) begin
        if (reset) begin
            threshold_enable <= 1'b0;
            s_threshold      <= 32'sd0;

            sym_cnt         <= {CNT_WIDTH{1'b0}};
            peak_metric     <= 34'sd0;
            peak_I          <= {PEAK_WIDTH{1'b0}};
            peak_Q          <= {PEAK_WIDTH{1'b0}};
            debug_peak_idx  <= {CNT_WIDTH{1'b0}};
            peak_found_stb  <= 1'b0;
            peak_valid      <= 1'b0;
            start_index_reg <= 1'b0;
        end else begin
            if (set_stb) begin
                case (set_addr)
                    ADDR_THRESHOLD_ENABLE: threshold_enable <= set_data[0];
                    ADDR_S_THRESHOLD     : s_threshold      <= $signed(set_data);
                    default: begin end
                endcase
            end

            peak_found_stb  <= 1'b0;
            start_index_reg <= 1'b0;

            if (enable && vdb_metric_stb) begin
                if ((!threshold_enable) || (vdb_metric > $signed({s_threshold[31], s_threshold}))) begin
                    if (!peak_valid || (sym_cnt == 0)) begin
                        peak_metric    <= vdb_metric;
                        peak_I         <= avg_i_reduced;
                        peak_Q         <= avg_q_reduced;
                        debug_peak_idx <= sym_cnt;
                        peak_valid     <= 1'b1;
                    end else if (vdb_metric > peak_metric) begin
                        peak_metric    <= vdb_metric;
                        peak_I         <= avg_i_reduced;
                        peak_Q         <= avg_q_reduced;
                        debug_peak_idx <= sym_cnt;
                    end
                end

                if (sym_cnt == FFT_SIZE-1) begin
                    peak_found_stb  <= peak_valid;
                    start_index_reg <= peak_valid;

                    sym_cnt         <= {CNT_WIDTH{1'b0}};
                    peak_metric     <= 34'sd0;
                    peak_valid      <= 1'b0;
                end else begin
                    sym_cnt <= sym_cnt + 1'b1;
                end
            end
        end
    end
    */
    
endmodule

