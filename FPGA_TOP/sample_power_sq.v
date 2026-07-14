`timescale 1ns/1ps

module sample_power_sq #(
    parameter IQ_WIDTH  = 16,
    parameter OUT_WIDTH = 33
)(
    input  wire                         clock,
    input  wire                         enable,
    input  wire                         reset,

    input  wire [2*IQ_WIDTH-1:0]        sample_in,
    input  wire                         input_strobe,

    output reg  [OUT_WIDTH-1:0]         power_out,
    output wire                         power_out_stb
);

    wire signed [IQ_WIDTH-1:0] in_i = sample_in[2*IQ_WIDTH-1:IQ_WIDTH];
    wire signed [IQ_WIDTH-1:0] in_q = sample_in[IQ_WIDTH-1:0];

    reg signed [2*IQ_WIDTH-1:0] i_sq_reg;
    reg signed [2*IQ_WIDTH-1:0] q_sq_reg;

    reg                         stb_d1;
    reg                         stb_d2;

    always @(posedge clock) begin
        if (reset) begin
            i_sq_reg  <= {(2*IQ_WIDTH){1'b0}};
            q_sq_reg  <= {(2*IQ_WIDTH){1'b0}};
            power_out <= {OUT_WIDTH{1'b0}};
            stb_d1    <= 1'b0;
            stb_d2    <= 1'b0;
        end else if (enable) begin
            // stage 1
            i_sq_reg <= in_i * in_i;
            q_sq_reg <= in_q * in_q;

            // stage 2
            power_out <= {{1{i_sq_reg[2*IQ_WIDTH-1]}}, i_sq_reg} + {{1{q_sq_reg[2*IQ_WIDTH-1]}}, q_sq_reg};

            stb_d1 <= input_strobe;
            stb_d2 <= stb_d1;
        end else begin
            stb_d1 <= 1'b0;
            stb_d2 <= 1'b0;
        end
    end

    assign power_out_stb = stb_d2;

endmodule

