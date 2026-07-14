`timescale 1ns/1ps

// complex_mult_iq: 2-cycle pipelined AXI-Stream complex multiplier.
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
// TWO-cycle latency (P5-04 timing pipeline cut):
//   Cycle 1: multiplier stage — register p_II / p_QQ / p_IQ / p_QI
//   Cycle 2: adder + shift + output register
// This breaks the DSP chain (mult → add → shift → register) that
// previously needed 2 cascaded DSP48E2 stages combinationally,
// targeting 250 MHz on xczu9eg.

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

    wire signed [PROD_W-1:0] p_II_c = Ia * Ib;
    wire signed [PROD_W-1:0] p_QQ_c = Qa_eff * Qb_eff;
    wire signed [PROD_W-1:0] p_IQ_c = Ia * Qb_eff;
    wire signed [PROD_W-1:0] p_QI_c = Qa_eff * Ib;

    // -------- Stage 1: register multiplier outputs + valid/last --------
    reg signed [PROD_W-1:0] p_II_r, p_QQ_r, p_IQ_r, p_QI_r;
    reg                     s1_valid;
    reg                     s1_last;

    always @(posedge aclk) begin
        if (!aresetn) begin
            p_II_r   <= {PROD_W{1'b0}};
            p_QQ_r   <= {PROD_W{1'b0}};
            p_IQ_r   <= {PROD_W{1'b0}};
            p_QI_r   <= {PROD_W{1'b0}};
            s1_valid <= 1'b0;
            s1_last  <= 1'b0;
        end else if (can_accept) begin
            p_II_r   <= p_II_c;
            p_QQ_r   <= p_QQ_c;
            p_IQ_r   <= p_IQ_c;
            p_QI_r   <= p_QI_c;
            s1_valid <= s_axis_a_tvalid && s_axis_b_tvalid;
            s1_last  <= s_axis_a_tlast  && s_axis_b_tvalid;
        end
    end

    // -------- Stage 2: add + shift + output register --------
    wire signed [SUM_W-1:0] sum_I = {p_II_r[PROD_W-1], p_II_r} - {p_QQ_r[PROD_W-1], p_QQ_r};
    wire signed [SUM_W-1:0] sum_Q = {p_IQ_r[PROD_W-1], p_IQ_r} + {p_QI_r[PROD_W-1], p_QI_r};

    wire signed [SUM_W-1:0] out_I_shifted = sum_I >>> SHIFT;
    wire signed [SUM_W-1:0] out_Q_shifted = sum_Q >>> SHIFT;

    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else if (can_accept) begin
            m_axis_tvalid <= s1_valid;
            m_axis_tlast  <= s1_last;
            m_axis_tdata  <= {out_Q_shifted[COMPONENT_WIDTH-1:0],
                              out_I_shifted[COMPONENT_WIDTH-1:0]};
        end
    end

endmodule
