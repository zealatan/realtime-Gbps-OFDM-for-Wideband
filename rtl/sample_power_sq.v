`timescale 1ns/1ps

// sample_power_sq: combinatorial per-sample power I^2 + Q^2.
//
// IQ packing convention (matches iq_frame_buffer and frac_cfo_frame_corrector_top):
//   32-bit word = {Q[31:16], I[15:0]}
//   i_in = bits[15:0]  (I component)
//   q_in = bits[31:16] (Q component)
//
// Maximum output: 2 * 32767^2 = 2,147,352,578 < 2^31, fits in POWER_WIDTH=33.
// No registered latency — power_out is valid combinatorially from i_in/q_in.

module sample_power_sq #(
    parameter integer DATA_WIDTH  = 16,
    parameter integer POWER_WIDTH = 33
) (
    input  wire signed [DATA_WIDTH-1:0]  i_in,
    input  wire signed [DATA_WIDTH-1:0]  q_in,
    output wire        [POWER_WIDTH-1:0] power_out
);
    wire [2*DATA_WIDTH-1:0] i_sq = i_in * i_in;
    wire [2*DATA_WIDTH-1:0] q_sq = q_in * q_in;

    assign power_out = {{(POWER_WIDTH - 2*DATA_WIDTH){1'b0}}, i_sq}
                     + {{(POWER_WIDTH - 2*DATA_WIDTH){1'b0}}, q_sq};

endmodule
