`timescale 1ns/1ps

module complex_mult
(
    input clock,
    input enable,
    input reset,

    input  signed [15:0] a_i, // Real part of A
    input  signed [15:0] a_q, // Imag part of A
    input  signed [15:0] b_i, // Real part of B
    input  signed [15:0] b_q, // Imag part of B
    input  input_strobe,

    output reg signed [31:0] p_i, // Real part of Result
    output reg signed [31:0] p_q, // Imag part of Result
    output output_strobe
);


    localparam integer LAT = 3;


    reg signed [15:0] ar, ai, br, bi;
    

    reg signed [31:0] mult_rr, mult_ii, mult_ri, mult_ir;


    reg [LAT-1:0] stb_pipe;


    assign output_strobe = stb_pipe[LAT-1];

    always @(posedge clock) begin
        if (reset) begin
            ar <= 0; ai <= 0; br <= 0; bi <= 0;
            mult_rr <= 0; mult_ii <= 0; mult_ri <= 0; mult_ir <= 0;
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

