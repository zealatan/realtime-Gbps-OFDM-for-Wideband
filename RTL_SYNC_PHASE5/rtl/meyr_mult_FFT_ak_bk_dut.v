`timescale 1ns/1ps
// =============================================================
//  meyr_mult_FFT_ak_bk_dut.v
//
//  PURPOSE:
//    R[m] = FFT_2N(A[k]) × conj(FFT_2N(B[k]))
//
//  ARCHITECTURE:
//    - Inferred BRAM stores precomputed conj(FFT_2N(B[k]))
//      (loaded by TB via $readmemh for simulation,
//       replaced by BRAM IP with .coe for synthesis)
//    - 1-cycle BRAM read latency, FFT data delayed to align
//    - complex_mult_32: 32×32 → 64-bit, 3-cycle pipeline
//    - Arithmetic right-shift >>31 for Q1.31 normalization
//
//  PIPELINE LATENCY:
//    1 (BRAM read align) + 3 (complex_mult_32) = 4 cycles
//
//  DATA FORMAT (matches C reference):
//    ROM entry:  {conj_im[31:0], re[31:0]}  (64-bit)
//    Input:      {im[31:0], re[31:0]}        (64-bit from xfft_2N)
//    Output:     {rm_im[31:0], rm_re[31:0]}  (64-bit, >>31 truncated)
// =============================================================
module meyr_mult_FFT_ak_bk_dut #(
    parameter N_2N = 512
)(
    input  wire        clk,
    input  wire        rst_n,

    // Input: FFT_2N output stream (FFT of zero-padded A[k])
    input  wire [63:0] din_tdata,
    input  wire        din_tvalid,
    input  wire        din_tlast,

    // Output: R[m] = FFT(A[k]) * conj(FFT(B[k])), >>31
    output wire [63:0] rm_tdata,
    output wire        rm_tvalid,
    output wire        rm_tlast
);

    // ---------------------------------------------------------
    // ROM: conj(FFT_2N(B[k])), inferred BRAM
    //   Loaded by TB: $readmemh(fname, u_bk_mult.rom)
    //   For synthesis: replace with BRAM IP + .coe
    // ---------------------------------------------------------
    (* ram_style = "block" *) reg [63:0] rom [0:N_2N-1];

    // ---------------------------------------------------------
    // ROM Address Counter
    // ---------------------------------------------------------
    reg [$clog2(N_2N)-1:0] rom_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rom_addr <= 0;
        else if (din_tvalid)
            rom_addr <= din_tlast ? {$clog2(N_2N){1'b0}} : rom_addr + 1;
    end

    // ---------------------------------------------------------
    // BRAM Registered Read (1-cycle latency)
    // ---------------------------------------------------------
    reg [63:0] rom_q;

    always @(posedge clk) begin
        rom_q <= rom[rom_addr];
    end

    // ---------------------------------------------------------
    // 1-Cycle Delay: Align FFT data with BRAM output
    // ---------------------------------------------------------
    reg signed [31:0] fft_re_d1, fft_im_d1;
    reg               valid_d1;
    reg               tlast_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fft_re_d1 <= 0;
            fft_im_d1 <= 0;
            valid_d1  <= 0;
            tlast_d1  <= 0;
        end else begin
            fft_re_d1 <= $signed(din_tdata[31:0]);
            fft_im_d1 <= $signed(din_tdata[63:32]);
            valid_d1  <= din_tvalid;
            tlast_d1  <= din_tvalid & din_tlast;
        end
    end

    // ---------------------------------------------------------
    // Complex Multiplier (32×32 → 64-bit, 3-cycle pipeline)
    //   A = FFT_2N(A[k]),  B = conj(FFT_2N(B[k])) from ROM
    // ---------------------------------------------------------
    wire signed [63:0] mult_pi, mult_pq;
    wire               mult_strobe;

    complex_mult_32 u_mult (
        .clock         (clk),
        .enable        (1'b1),
        .rst_n         (rst_n),
        .a_i           (fft_re_d1),
        .a_q           (fft_im_d1),
        .b_i           ($signed(rom_q[31:0])),
        .b_q           ($signed(rom_q[63:32])),
        .input_strobe  (valid_d1),
        .p_i           (mult_pi),
        .p_q           (mult_pq),
        .output_strobe (mult_strobe)
    );

    // ---------------------------------------------------------
    // >>31 Truncation (Q1.31 × Q1.31 → Q2.31, keep 32 bits)
    //   Matches C: rm_re_32 = (int32_t)(r_re_64 >> 31)
    // ---------------------------------------------------------
    wire signed [63:0] rm_re_shifted = mult_pi >>> 31;
    wire signed [63:0] rm_im_shifted = mult_pq >>> 31;

    assign rm_tdata  = {rm_im_shifted[31:0], rm_re_shifted[31:0]};
    assign rm_tvalid = mult_strobe;

    // ---------------------------------------------------------
    // tlast Pipeline (3 stages to match multiplier latency)
    // ---------------------------------------------------------
    reg [2:0] tlast_sr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tlast_sr <= 3'b0;
        else
            tlast_sr <= {tlast_sr[1:0], tlast_d1};
    end

    assign rm_tlast = tlast_sr[2] & mult_strobe;

endmodule