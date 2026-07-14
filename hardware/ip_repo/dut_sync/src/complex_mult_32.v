`timescale 1ns/1ps
module complex_mult_32 (
    input  wire        clock,
    input  wire        enable,
    input  wire        rst_n,

    input  wire signed [31:0] a_i,
    input  wire signed [31:0] a_q,
    input  wire signed [31:0] b_i,
    input  wire signed [31:0] b_q,
    input  wire        input_strobe,

    output reg  signed [63:0] p_i,
    output reg  signed [63:0] p_q,
    output wire        output_strobe
);
    localparam integer LAT = 3;

    reg signed [31:0] ar, ai, br, bi;
    reg signed [63:0] mult_rr, mult_ii, mult_ri, mult_ir;

    reg [LAT-1:0] stb_pipe;
    assign output_strobe = stb_pipe[LAT-1];

    always @(posedge clock) begin
        if (!rst_n) begin
            ar <= 0; ai <= 0; br <= 0; bi <= 0;
            mult_rr <= 0; mult_ii <= 0;
            mult_ri <= 0; mult_ir <= 0;
            p_i <= 0; p_q <= 0;
            stb_pipe <= 0;
        end else if (enable) begin
            stb_pipe <= {stb_pipe[LAT-2:0], input_strobe};

            if (input_strobe) begin
                ar <= a_i;
                ai <= a_q;
                br <= b_i;
                bi <= b_q;
            end

            mult_rr <= ar * br;
            mult_ii <= ai * bi;
            mult_ri <= ar * bi;
            mult_ir <= ai * br;

            p_i <= mult_rr - mult_ii;
            p_q <= mult_ri + mult_ir;
        end
    end
endmodule