/*
`timescale 1ns/1ps
module complex_to_mag_sq (
    input clock,
    input enable,
    input reset,

    input signed [15:0] i,
    input signed [15:0] q,
    input input_strobe,

    output [31:0] mag_sq,
    output mag_sq_strobe
);

reg valid_in;
reg [15:0] input_i;
reg [15:0] input_q;
reg [15:0] input_q_neg;

complex_mult mult_inst (
    .clock(clock),
    .reset(reset),
    .enable(enable),
    
    .a_i(input_i),
    .a_q(input_q),
    .b_i(input_i),
    .b_q(input_q_neg),
    .input_strobe(valid_in),

    .p_i(mag_sq),
    .output_strobe(mag_sq_strobe)
);

always @(posedge clock) begin
    if (reset) begin
        input_i <= 0;
        input_q <= 0;
        input_q_neg <= 0;
        valid_in <= 0;
    end else if (enable) begin
        valid_in <= input_strobe;
        input_i <= i;
        input_q <= q;
        input_q_neg <= ~q+1;
    end
end
endmodule
*/


`timescale 1ns/1ps

module complex_to_mag_sq #(
    parameter DATA_WIDTH = 32,
    parameter OUT_WIDTH  = (2*DATA_WIDTH+1)
)(
    input  wire                           clock,
    input  wire                           enable,
    input  wire                           reset,

    input  wire signed [DATA_WIDTH-1:0]   i,
    input  wire signed [DATA_WIDTH-1:0]   q,
    input  wire                           input_strobe,

    output reg  [OUT_WIDTH-1:0]           mag_sq,
    output wire                           mag_sq_stb
);

    reg signed [2*DATA_WIDTH-1:0] i_sq_reg;
    reg signed [2*DATA_WIDTH-1:0] q_sq_reg;

    reg                           stb_d1;
    reg                           stb_d2;

    always @(posedge clock) begin
        if (reset) begin
            i_sq_reg <= {(2*DATA_WIDTH){1'b0}};
            q_sq_reg <= {(2*DATA_WIDTH){1'b0}};
            mag_sq   <= {OUT_WIDTH{1'b0}};
            stb_d1   <= 1'b0;
            stb_d2   <= 1'b0;
        end else if (enable) begin
            // stage 1: squares
            i_sq_reg <= i * i;
            q_sq_reg <= q * q;

            // stage 2: sum
            mag_sq   <= {{1{i_sq_reg[2*DATA_WIDTH-1]}}, i_sq_reg} + {{1{q_sq_reg[2*DATA_WIDTH-1]}}, q_sq_reg};
            stb_d1   <= input_strobe;
            stb_d2   <= stb_d1;
        end else begin
            stb_d1   <= 1'b0;
            stb_d2   <= 1'b0;
        end
    end

    assign mag_sq_stb = stb_d2;

endmodule
