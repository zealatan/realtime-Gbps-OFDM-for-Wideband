// nco_phase_gen_stub.v — Synthesis stub for Step 22 OOC check.
// Replaces the simulation-only behavioral model (real/$sin/$cos) with a black-box
// declaration that matches all ports exactly.
// In production synthesis, replace this stub with the Xilinx cordic_v6_0 IP
// generated in Vivado IP Catalog (rotate/sincos mode, 16-bit coefficient output),
// wrapped with the NCO phase accumulator registers.
`timescale 1ns/1ps

(* black_box *)
module nco_phase_gen #(
    parameter integer NCO_PHASE_WIDTH     = 32,
    parameter integer CORDIC_PHASE_WIDTH  = 16,
    parameter integer ROTATOR_COEFF_WIDTH = 16,
    parameter integer LATENCY             = 15
) (
    input  wire                                      aclk,
    input  wire                                      aresetn,
    input  wire                                      load_step,
    input  wire signed [NCO_PHASE_WIDTH-1:0]         step_word,
    input  wire                                      phase_reset,
    input  wire                                      enable,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     sin_out,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     cos_out,
    output wire                                      sincos_valid,
    output wire        [NCO_PHASE_WIDTH-1:0]         phase_acc
);
    // Outputs tied to 0 for black-box synthesis check.
    // Replace with cordic_v6_0 IP + phase accumulator before production FPGA build.
    assign sin_out    = {ROTATOR_COEFF_WIDTH{1'b0}};
    assign cos_out    = {ROTATOR_COEFF_WIDTH{1'b0}};
    assign sincos_valid = 1'b0;
    assign phase_acc  = {NCO_PHASE_WIDTH{1'b0}};
endmodule
