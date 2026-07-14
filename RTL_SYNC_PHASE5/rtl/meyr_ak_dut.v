`timescale 1ns/1ps
module meyr_ak_dut #(
    parameter N = 256
)(
    input  wire        clk,
    input  wire        rst_n,

    // Input from N-point FFT
    input  wire [31:0] din_tdata,
    input  wire        din_tvalid,
    input  wire        din_tlast,

    // Result Ak (32-bit complex)
    output wire [63:0] ak_tdata,
    output wire        ak_tvalid
);

    wire [15:0] sss_re, sss_im, pss_conj_re, pss_conj_im;
    wire        strobe_to_mult;
    wire [31:0] prod_re, prod_im;

    // 1. Buffer
    meyr_ak_buf #(.MAX_N(N)) u_buf (
        .clk(clk), .rst_n(rst_n),
        .fft_tdata(din_tdata), .fft_tvalid(din_tvalid), .fft_tlast(din_tlast),
        .a_i(sss_re), .a_q(sss_im),
        .b_i(pss_conj_re), .b_q(pss_conj_im),
        .mult_strobe(strobe_to_mult)
    );

    // 2. Multiplier
    // complex_mult uses an active-high 'reset' port, not active-low 'rst_n'.
    complex_mult u_mult (
        .clock(clk), .enable(1'b1), .reset(~rst_n),
        .a_i(sss_re), .a_q(sss_im),
        .b_i(pss_conj_re), .b_q(pss_conj_im),
        .input_strobe(strobe_to_mult),
        .p_i(prod_re), .p_q(prod_im),
        .output_strobe(ak_tvalid)
    );

    assign ak_tdata = {prod_im, prod_re};

endmodule