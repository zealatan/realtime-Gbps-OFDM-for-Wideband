`timescale 1ns/1ps
// =============================================================
//  meyr_FFT_ak_dut.v
//  Phase 1: A[k] Generation + 2N Zero Padding
// =============================================================
module meyr_FFT_ak_dut #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,

    // Input from First FFT (N-point)
    input  wire [31:0] din_tdata,
    input  wire        din_tvalid,
    input  wire        din_tlast,

    // Output to Second FFT (2N-point)
    output wire [63:0] pad_tdata,
    output wire        pad_tvalid,
    output wire        pad_tlast,
    input  wire        pad_tready
);

    // --- Internal Interconnects ---
    wire [15:0] sss_re, sss_im, pss_conj_re, pss_conj_im;
    wire        strobe_to_mult;
    
    wire [31:0] prod_re, prod_im;
    wire        ak_tvalid;
    wire [63:0] ak_tdata;

    // 1. Instantiate Buffer (Aligns PSS and SSS)
    meyr_ak_buf #(.MAX_N(4096)) u_buf (
        .clk(clk), .rst_n(rst_n),
        .fft_tdata(din_tdata), .fft_tvalid(din_tvalid), .fft_tlast(din_tlast),
        .a_i(sss_re), .a_q(sss_im),
        .b_i(pss_conj_re), .b_q(pss_conj_im),
        .mult_strobe(strobe_to_mult)
    );

    // 2. Instantiate Complex Multiplier (A[k] = SSS * conj(PSS))
    // Note: This is purely pipelined (3 cycles), so we assume no backpressure from downstream
    // complex_mult uses an active-high 'reset' port, not 'rst_n'.
    complex_mult u_mult (
        .clock(clk), .enable(1'b1), .reset(~rst_n),
        .a_i(sss_re), .a_q(sss_im),
        .b_i(pss_conj_re), .b_q(pss_conj_im),
        .input_strobe(strobe_to_mult),
        .p_i(prod_re), .p_q(prod_im),
        .output_strobe(ak_tvalid)
    );

    assign ak_tdata = {prod_im, prod_re};

    // 3. Instantiate Ultra-Fast Zero Padder
    meyr_zeropad #(.N_LOG2_MAX(N_LOG2_MAX)) u_padder (
        .clk(clk), .rst_n(rst_n),
        .n_log2(n_log2),
        .s_tdata(ak_tdata), 
        .s_tvalid(ak_tvalid), 
        .s_tlast(1'b0), // Ignored by the pipelined padder
        .s_tready(),    // Ignored, multiplier doesn't need backpressure
        .m_tdata(pad_tdata), 
        .m_tvalid(pad_tvalid), 
        .m_tlast(pad_tlast), 
        .m_tready(pad_tready)
    );

endmodule
