`timescale 1ns/1ps
// =============================================================
//  meyr_ifft_peak_dut.v
//
//  PURPOSE:
//    Step 5: IFFT of R[m] -> time domain
//    Step 6: Peak power search -> integer CFO
//
//  ARCHITECTURE:
//    R[m] input -> xfft_IFFT (2N-pt, inverse, BFP) -> peak search
//
//  PEAK SEARCH (pipelined, matches C exactly):
//    power[i] = re[i]^2 + im[i]^2   (32x32 -> 64-bit, no overflow)
//    Track running max and its index.
//    After 2N bins: output best_idx and hw_cfo_int.
//
//  CFO CALCULATION (matches C):
//    if (best_idx < N)
//        hw_cfo_int = best_idx;
//    else
//        hw_cfo_int = best_idx - 2*N;
//
//  OUTPUTS:
//    ifft_tdata/tvalid/tlast : raw IFFT stream (for TB verification)
//    peak_idx                : index of maximum power bin
//    cfo_int                 : signed integer CFO estimate
//    cfo_valid               : pulses 1 cycle when peak search completes
// =============================================================
module meyr_ifft_peak_dut #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,

    // Config for IFFT IP (xfft v9.1 16-bit runtime config word)
    input  wire [15:0] cfg_ifft_tdata,
    input  wire        cfg_ifft_tvalid,
    output wire        cfg_ifft_tready,

    // Input: R[m] stream from meyr_Rm_dut
    input  wire [63:0] rm_tdata,
    input  wire        rm_tvalid,
    input  wire        rm_tlast,

    // IFFT output stream (for TB verification)
    output wire [63:0] ifft_tdata,
    output wire        ifft_tvalid,
    output wire        ifft_tlast,

    // Peak search result
    output reg  [N_LOG2_MAX:0]       peak_idx,
    output reg  signed [31:0]        cfo_int,
    output reg                       cfo_valid
);

    wire [N_LOG2_MAX:0] n_runtime =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << n_log2);
    wire [N_LOG2_MAX:0] fft2n_last =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << (n_log2 + 1'b1)) - 1'b1;
    wire signed [31:0] fft2n_runtime_s =
        $signed({19'd0, fft2n_last}) + 32'sd1;

    // =========================================================
    // 1. IFFT (2N-point, inverse, BFP)
    //    Requires xfft_IFFT IP in Vivado (same config as xfft_2N)
    //    Config word: 8'h00 (bit[0]=0 for inverse)
    // =========================================================
    wire        ifft_out_tvalid;
    wire [63:0] ifft_out_tdata;
    wire        ifft_out_tlast;

    xfft_IFFT u_ifft (
        .aclk                        (clk),
        .aresetn                     (rst_n),
        .s_axis_config_tvalid        (cfg_ifft_tvalid),
        .s_axis_config_tready        (cfg_ifft_tready),
        // IP's C_S_AXIS_CONFIG_TDATA_WIDTH = 8 (HAS_NFFT=0, BFP).
        .s_axis_config_tdata         (cfg_ifft_tdata[7:0]),
        .s_axis_data_tvalid          (rm_tvalid),
        .s_axis_data_tready          (),           // R[m] streams freely
        .s_axis_data_tdata           (rm_tdata),
        .s_axis_data_tlast           (rm_tlast),
        .m_axis_data_tvalid          (ifft_out_tvalid),
        .m_axis_data_tready          (1'b1),
        .m_axis_data_tdata           (ifft_out_tdata),
        .m_axis_data_tlast           (ifft_out_tlast),
        .m_axis_status_tready        (1'b1),
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_status_channel_halt   (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt ()
    );

    // Pass-through for TB verification
    assign ifft_tdata  = ifft_out_tdata;
    assign ifft_tvalid = ifft_out_tvalid;
    assign ifft_tlast  = ifft_out_tlast;

    // =========================================================
    // 2. PIPELINED PEAK POWER SEARCH
    //    Pipeline: Stage1(square) -> Stage2(add+compare) -> Stage3(update)
    // =========================================================

    wire signed [31:0] ifft_re = $signed(ifft_out_tdata[31:0]);
    wire signed [31:0] ifft_im = $signed(ifft_out_tdata[63:32]);

    // --- Stage 1: Square (registered DSP48 multiply) ---
    reg signed [63:0] re_sq, im_sq;
    reg               s1_valid;
    reg [N_LOG2_MAX:0] s1_idx;

    // Bin counter at IFFT output
    reg [N_LOG2_MAX:0] bin_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bin_cnt <= 0;
        end else if (ifft_out_tvalid) begin
            bin_cnt <= ifft_out_tlast ? {(N_LOG2_MAX+1){1'b0}} : bin_cnt + 1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            re_sq    <= 0;
            im_sq    <= 0;
            s1_valid <= 0;
            s1_idx   <= 0;
        end else begin
            s1_valid <= ifft_out_tvalid;
            s1_idx   <= bin_cnt;
            if (ifft_out_tvalid) begin
                re_sq <= ifft_re * ifft_re;
                im_sq <= ifft_im * ifft_im;
            end
        end
    end

    // --- Stage 2: Add + Compare ---
    reg [63:0] power;
    reg        s2_valid;
    reg [N_LOG2_MAX:0] s2_idx;
    reg        s2_is_first; // first bin of frame

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power    <= 0;
            s2_valid <= 0;
            s2_idx   <= 0;
            s2_is_first <= 0;
        end else begin
            s2_valid    <= s1_valid;
            s2_idx      <= s1_idx;
            s2_is_first <= (s1_idx == 0) & s1_valid;
            if (s1_valid) begin
                power <= re_sq + im_sq;
            end
        end
    end

    // --- Stage 3: Running Max Tracker ---
    reg [63:0] max_power;
    reg [N_LOG2_MAX:0] max_idx;

    // Detect end of frame (last valid bin processed through pipeline)
    reg s2_is_last;
    reg s3_is_last;
    always @(posedge clk) begin
        s2_is_last <= (s1_idx == fft2n_last) & s1_valid;
        s3_is_last <= s2_is_last;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            max_power <= 0;
            max_idx   <= 0;
            peak_idx  <= 0;
            cfo_int   <= 0;
            cfo_valid <= 0;
        end else begin
            cfo_valid <= 0; // default: pulse

            if (s2_valid) begin
                if (s2_is_first) begin
                    // Reset for new frame
                    max_power <= power;
                    max_idx   <= s2_idx;
                end else if ((power > max_power) && (s2_idx != n_runtime)) begin
                    // Exclude the Nyquist bin (s2_idx == N) from the running
                    // max: C's fft_correlation_Meyr reorder drops natural bin
                    // N entirely (lines 480-488 of ref/receiver.c skip i==N-1
                    // in the reordered index, which is natural bin N).
                    // Decode mapping otherwise: bin<N -> cfo=bin, bin>N ->
                    // cfo=bin-2N, bin==N would decode to -N which C never
                    // emits.
                    //
                    // Residual tie-order note (does NOT affect a clean single
                    // peak): C is first-wins in *reordered* order, RTL is
                    // first-wins in *natural* order.
                    max_power <= power;
                    max_idx   <= s2_idx;
                end
            end

            if (s3_is_last) begin
                // Latch final result
                peak_idx  <= max_idx;
                // CFO calculation (matches C exactly)
                if (max_idx < n_runtime)
                    cfo_int <= $signed({19'd0, max_idx});
                else
                    cfo_int <= $signed({19'd0, max_idx}) - fft2n_runtime_s;
                cfo_valid <= 1;
            end
        end
    end

endmodule
