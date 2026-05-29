`timescale 1ns/1ps

module and2 (
    input  wire a,
    input  wire b,
    output wire y
);

    assign y = a & b;

endmodule
