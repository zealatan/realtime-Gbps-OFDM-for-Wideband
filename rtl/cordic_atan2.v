`timescale 1ns/1ps

// cordic_atan2: Behavioral simulation model of Xilinx CORDIC IP v6.0, translate mode.
// Computes atan2(Q, I) → 16-bit signed phase: 0x7FFF = +π.
// Fully pipelined: tready always 1, LATENCY clocks from input to output.
// Synthesis target: replace with cordic_v6_0 IP instantiation.

module cordic_atan2 #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer PHASE_WIDTH = 16,
    parameter integer LATENCY     = 15
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    // AXI-Stream Cartesian input: tdata[INPUT_WIDTH-1:0]=I, tdata[2*INPUT_WIDTH-1:INPUT_WIDTH]=Q
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,

    // AXI-Stream phase output
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);

    // Fully pipelined: always accepts input
    assign s_axis_cartesian_tready = 1'b1;

    wire signed [INPUT_WIDTH-1:0] cart_I =
        s_axis_cartesian_tdata[INPUT_WIDTH-1:0];
    wire signed [INPUT_WIDTH-1:0] cart_Q =
        s_axis_cartesian_tdata[2*INPUT_WIDTH-1:INPUT_WIDTH];

    // LATENCY-stage shift-register pipeline
    reg [PHASE_WIDTH-1:0] pipe_data  [0:LATENCY-1];
    reg                   pipe_valid [0:LATENCY-1];

    // Behavioral atan2 — simulation only; synthesis replaces this module with CORDIC IP
    real    r_I, r_Q, r_angle;
    integer ph_int;
    reg [PHASE_WIDTH-1:0] ph_comb;

    always @(*) begin
        r_I     = $itor(cart_I);
        r_Q     = $itor(cart_Q);
        r_angle = $atan2(r_Q, r_I) / 3.14159265358979323846;
        // Scale to ±(2^(PHASE_WIDTH-1) - 1), truncate toward zero
        ph_int  = $rtoi(r_angle * ((1 << (PHASE_WIDTH-1)) - 1));
        ph_comb = ph_int[PHASE_WIDTH-1:0];
    end

    integer k;
    always @(posedge aclk) begin
        if (!aresetn) begin
            for (k = 0; k < LATENCY; k = k + 1) begin
                pipe_data [k] <= {PHASE_WIDTH{1'b0}};
                pipe_valid[k] <= 1'b0;
            end
            m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
            m_axis_dout_tvalid <= 1'b0;
        end else begin
            pipe_data [0] <= ph_comb;
            pipe_valid[0] <= s_axis_cartesian_tvalid;
            for (k = 1; k < LATENCY; k = k + 1) begin
                pipe_data [k] <= pipe_data [k-1];
                pipe_valid[k] <= pipe_valid[k-1];
            end
            m_axis_dout_tdata  <= pipe_data [LATENCY-1];
            m_axis_dout_tvalid <= pipe_valid[LATENCY-1];
        end
    end

endmodule
