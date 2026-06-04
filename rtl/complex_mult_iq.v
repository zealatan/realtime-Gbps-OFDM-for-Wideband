`timescale 1ns/1ps

// complex_mult_iq: 1-cycle pipelined AXI-Stream complex multiplier.
//
// Computes A × B (or A × conj(B) with CONJ_B=1, etc.)
// IQ packing: tdata[COMPONENT_WIDTH-1:0] = I, tdata[DATA_WIDTH-1:COMPONENT_WIDTH] = Q
//
// Result arithmetic (for CONJ_A=0, CONJ_B=0):
//   I_out = (Ia*Ib - Qa*Qb) >> SHIFT
//   Q_out = (Ia*Qb + Qa*Ib) >> SHIFT
//
// For CONJ_B=1 (used by complex_rotator for A × conj(B)):
//   I_out = (Ia*Ib + Qa*Qb) >> SHIFT
//   Q_out = (Qa*Ib - Ia*Qb) >> SHIFT
//
// One-cycle latency: outputs valid one cycle after inputs.

module complex_mult_iq #(
    parameter integer DATA_WIDTH      = 32,
    parameter integer COMPONENT_WIDTH = 16,
    parameter integer SHIFT           = 15,
    parameter         CONJ_A          = 0,
    parameter         CONJ_B          = 0
) (
    input  wire aclk,
    input  wire aresetn,

    input  wire [DATA_WIDTH-1:0] s_axis_a_tdata,
    input  wire                  s_axis_a_tvalid,
    output wire                  s_axis_a_tready,
    input  wire                  s_axis_a_tlast,

    input  wire [DATA_WIDTH-1:0] s_axis_b_tdata,
    input  wire                  s_axis_b_tvalid,
    output wire                  s_axis_b_tready,
    input  wire                  s_axis_b_tlast,

    output reg  [DATA_WIDTH-1:0] m_axis_tdata,
    output reg                   m_axis_tvalid,
    input  wire                  m_axis_tready,
    output reg                   m_axis_tlast
);

    wire can_accept = !m_axis_tvalid || m_axis_tready;
    assign s_axis_a_tready = can_accept;
    assign s_axis_b_tready = 1'b1;   // NCO source has no backpressure port

    // Split components
    wire signed [COMPONENT_WIDTH-1:0] Ia = $signed(s_axis_a_tdata[COMPONENT_WIDTH-1:0]);
    wire signed [COMPONENT_WIDTH-1:0] Qa = $signed(s_axis_a_tdata[DATA_WIDTH-1:COMPONENT_WIDTH]);
    wire signed [COMPONENT_WIDTH-1:0] Ib = $signed(s_axis_b_tdata[COMPONENT_WIDTH-1:0]);
    wire signed [COMPONENT_WIDTH-1:0] Qb = $signed(s_axis_b_tdata[DATA_WIDTH-1:COMPONENT_WIDTH]);

    // Apply conjugates (negate the imaginary part)
    wire signed [COMPONENT_WIDTH-1:0] Qa_eff = CONJ_A ? -Qa : Qa;
    wire signed [COMPONENT_WIDTH-1:0] Qb_eff = CONJ_B ? -Qb : Qb;

    // Products (sign-extended to avoid overflow)
    localparam integer PROD_W = 2 * COMPONENT_WIDTH;
    localparam integer SUM_W  = PROD_W + 1;

    wire signed [PROD_W-1:0] p_II = Ia * Ib;
    wire signed [PROD_W-1:0] p_QQ = Qa_eff * Qb_eff;
    wire signed [PROD_W-1:0] p_IQ = Ia * Qb_eff;
    wire signed [PROD_W-1:0] p_QI = Qa_eff * Ib;

    wire signed [SUM_W-1:0] sum_I = {p_II[PROD_W-1], p_II} - {p_QQ[PROD_W-1], p_QQ};
    wire signed [SUM_W-1:0] sum_Q = {p_IQ[PROD_W-1], p_IQ} + {p_QI[PROD_W-1], p_QI};

    // Arithmetic right shift
    wire signed [SUM_W-1:0] out_I_shifted = sum_I >>> SHIFT;
    wire signed [SUM_W-1:0] out_Q_shifted = sum_Q >>> SHIFT;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (can_accept) begin
            m_axis_tvalid <= s_axis_a_tvalid && s_axis_b_tvalid;
            m_axis_tlast  <= s_axis_a_tlast  && s_axis_b_tvalid;
            m_axis_tdata  <= {out_Q_shifted[COMPONENT_WIDTH-1:0],
                              out_I_shifted[COMPONENT_WIDTH-1:0]};
        end
    end

endmodule
