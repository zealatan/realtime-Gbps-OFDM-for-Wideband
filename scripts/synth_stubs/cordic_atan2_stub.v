// cordic_atan2_stub.v — Synthesis stub for Step 22 OOC check.
// Replaces the simulation-only behavioral model (real/$atan2) with a black-box
// declaration that matches all ports exactly.
// In production synthesis, replace this stub with the Xilinx cordic_v6_0 IP
// generated in Vivado IP Catalog (translate mode, 16-bit phase output).
`timescale 1ns/1ps

(* black_box *)
module cordic_atan2 #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer PHASE_WIDTH = 16,
    parameter integer LATENCY     = 15
) (
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);
    assign s_axis_cartesian_tready = 1'b1;
    // Outputs tied to 0 for black-box synthesis check.
    // Replace with cordic_v6_0 IP before production FPGA build.
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
            m_axis_dout_tvalid <= 1'b0;
        end
    end
endmodule
