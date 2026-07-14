/*
`timescale 1ns/1ps

module complex_to_mag
#(
    parameter DATA_WIDTH = 16
)
(
    input clock,
    input enable,
    input reset,

    input signed [DATA_WIDTH-1:0] i,
    input signed [DATA_WIDTH-1:0] q,
    input input_strobe,

    output reg [DATA_WIDTH-1:0] mag,
    output mag_stb
);

reg [DATA_WIDTH-1:0] abs_i;
reg [DATA_WIDTH-1:0] abs_q;

reg [DATA_WIDTH-1:0] max;
reg[ DATA_WIDTH-1:0] min;

delayT #(.DATA_WIDTH(1), .DELAY(3)) stb_delay_inst (
    .clock(clock),
    .reset(reset),

    .data_in(input_strobe),
    .data_out(mag_stb)
);


// http://dspguru.com/dsp/tricks/magnitude-estimator
// alpha = 1, beta = 1/4
// avg err 0.006
always @(posedge clock) begin
    if (reset) begin
        mag <= 0;
        abs_i <= 0;
        abs_q <= 0;
        max <= 0;
        min <= 0;
    end else if (enable) begin
        abs_i <= i[DATA_WIDTH-1]? (~i+1): i;
        abs_q <= q[DATA_WIDTH-1]? (~q+1): q;

        max <= abs_i > abs_q? abs_i: abs_q;
        min <= abs_i > abs_q? abs_q: abs_i;

        mag <= max + (min>>2);
    end
end

endmodule
*/


`timescale 1ns/1ps

module complex_to_mag
#(
    parameter DATA_WIDTH = 16
)
(
    input  wire                          clock,
    input  wire                          enable,
    input  wire                          reset,

    input  wire signed [DATA_WIDTH-1:0]  i,
    input  wire signed [DATA_WIDTH-1:0]  q,
    input  wire                          input_strobe,

    output reg  [DATA_WIDTH-1:0]         mag,
    output wire                          mag_stb
);

    reg [DATA_WIDTH-1:0] abs_i;
    reg [DATA_WIDTH-1:0] abs_q;

    reg [DATA_WIDTH-1:0] max_v;
    reg [DATA_WIDTH-1:0] min_v;

    delayT #(
        .DATA_WIDTH(1),
        .DELAY(3)
    ) stb_delay_inst (
        .clock   (clock),
        .reset   (reset),
        .data_in (input_strobe),
        .data_out(mag_stb)
    );

    // magnitude ~= max(|I|,|Q|) + 1/4*min(|I|,|Q|)
    always @(posedge clock) begin
        if (reset) begin
            mag   <= {DATA_WIDTH{1'b0}};
            abs_i <= {DATA_WIDTH{1'b0}};
            abs_q <= {DATA_WIDTH{1'b0}};
            max_v <= {DATA_WIDTH{1'b0}};
            min_v <= {DATA_WIDTH{1'b0}};
        end else if (enable) begin
            abs_i <= i[DATA_WIDTH-1] ? (~i + 1'b1) : i;
            abs_q <= q[DATA_WIDTH-1] ? (~q + 1'b1) : q;

            max_v <= (abs_i > abs_q) ? abs_i : abs_q;
            min_v <= (abs_i > abs_q) ? abs_q : abs_i;

            mag   <= max_v + (min_v >> 2);
        end
    end

endmodule

