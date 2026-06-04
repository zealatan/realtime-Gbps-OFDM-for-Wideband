`timescale 1ns/1ps

// phase2_integer_cfo_stub — P2-17
//
// Stub placeholder for the integer CFO estimator block.
// Accepts the corrected IQ stream (AXIS 32-bit) and exposes
// integer_cfo_valid / integer_cfo_estimate outputs for downstream wiring.
//
// No algorithm is implemented here; outputs are tied to zero.
// Full implementation (FFT + Meyr correlator) is deferred to P2-18+.

module phase2_integer_cfo_stub #(
    parameter integer IQ_WIDTH    = 16,
    parameter integer CFO_WIDTH   = 16
)(
    input  wire                     aclk,
    input  wire                     aresetn,

    // AXI-Stream corrected IQ input  {Q[IQ_WIDTH-1:0], I[IQ_WIDTH-1:0]}
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]    s_axis_tdata,
    input  wire                     s_axis_tlast,

    // Integer CFO estimate output
    output reg                      integer_cfo_valid,
    output reg  signed [CFO_WIDTH-1:0] integer_cfo_estimate
);

    // Stub: always ready; never asserts valid output
    assign s_axis_tready = 1'b1;

    // Suppress unused-input warnings
    wire _unused = s_axis_tvalid | (|s_axis_tdata) | s_axis_tlast;

    always @(posedge aclk) begin
        if (!aresetn) begin
            integer_cfo_valid    <= 1'b0;
            integer_cfo_estimate <= {CFO_WIDTH{1'b0}};
        end else begin
            integer_cfo_valid    <= 1'b0;
            integer_cfo_estimate <= {CFO_WIDTH{1'b0}};
        end
    end

endmodule
