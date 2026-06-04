`timescale 1ns/1ps

// Meyr PSS/SSS product generator — Step 32
//
// Computes term1[j] = PSS_FFT[j] * conj(SSS_FFT[j])
//
// C-reference (ref/receiver.c lines 523-525):
//   crossCorrTerm1I[j] = signalPSSfftI[j]*signalSSSfftI[j] + signalPSSfftQ[j]*signalSSSfftQ[j]
//   crossCorrTerm1Q[j] = -signalPSSfftI[j]*signalSSSfftQ[j] + signalPSSfftQ[j]*signalSSSfftI[j]
//
// Arithmetic: PSS=a+jb, SSS=c+jd, conj(SSS)=c-jd
//   term1_i = a*c + b*d
//   term1_q = b*c - a*d
//
// Pipeline: 1-clock latency; inputs registered, products computed combinatorially, output registered.
// Backpressure: s_ready deasserts when output is stalled (m_valid && !m_ready).

module meyr_pss_sss_product_gen #(
    parameter integer IQ_WIDTH   = 16,
    parameter integer PROD_WIDTH = 32
)(
    input  wire                          aclk,
    input  wire                          aresetn,

    input  wire                          s_valid,
    output wire                          s_ready,
    input  wire [7:0]                    s_index,
    input  wire signed [IQ_WIDTH-1:0]    pss_i,
    input  wire signed [IQ_WIDTH-1:0]    pss_q,
    input  wire signed [IQ_WIDTH-1:0]    sss_i,
    input  wire signed [IQ_WIDTH-1:0]    sss_q,

    output reg                           m_valid,
    input  wire                          m_ready,
    output reg  [7:0]                    m_index,
    output reg  signed [PROD_WIDTH-1:0]  term1_i,
    output reg  signed [PROD_WIDTH-1:0]  term1_q
);

    // s_ready: can accept when output slot is free or being consumed
    assign s_ready = !m_valid || m_ready;

    // Registered input stage
    reg signed [IQ_WIDTH-1:0] pss_i_r, pss_q_r;
    reg signed [IQ_WIDTH-1:0] sss_i_r, sss_q_r;
    reg [7:0]                 idx_r;
    reg                       pipe_valid_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            pipe_valid_r <= 1'b0;
            pss_i_r <= {IQ_WIDTH{1'b0}};
            pss_q_r <= {IQ_WIDTH{1'b0}};
            sss_i_r <= {IQ_WIDTH{1'b0}};
            sss_q_r <= {IQ_WIDTH{1'b0}};
            idx_r   <= 8'd0;
        end else begin
            if (s_valid && s_ready) begin
                pipe_valid_r <= 1'b1;
                pss_i_r <= pss_i;
                pss_q_r <= pss_q;
                sss_i_r <= sss_i;
                sss_q_r <= sss_q;
                idx_r   <= s_index;
            end else begin
                pipe_valid_r <= 1'b0;
            end
        end
    end

    // Combinatorial products from registered stage
    // Use 33-bit intermediates to avoid overflow when adding two 16bx16b products.
    wire signed [31:0] prd_ac = $signed(pss_i_r) * $signed(sss_i_r);
    wire signed [31:0] prd_bd = $signed(pss_q_r) * $signed(sss_q_r);
    wire signed [31:0] prd_bc = $signed(pss_q_r) * $signed(sss_i_r);
    wire signed [31:0] prd_ad = $signed(pss_i_r) * $signed(sss_q_r);

    wire signed [32:0] t1_i_full = {prd_ac[31], prd_ac} + {prd_bd[31], prd_bd};
    wire signed [32:0] t1_q_full = {prd_bc[31], prd_bc} - {prd_ad[31], prd_ad};

    // Output register
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_valid <= 1'b0;
            m_index <= 8'd0;
            term1_i <= {PROD_WIDTH{1'b0}};
            term1_q <= {PROD_WIDTH{1'b0}};
        end else begin
            if (pipe_valid_r && (!m_valid || m_ready)) begin
                m_valid <= 1'b1;
                m_index <= idx_r;
                // Truncate to PROD_WIDTH (lower bits); safe for 8-bit synthetic data.
                // For full 16-bit inputs near extremes, consider wider PROD_WIDTH.
                term1_i <= t1_i_full[PROD_WIDTH-1:0];
                term1_q <= t1_q_full[PROD_WIDTH-1:0];
            end else if (m_ready) begin
                m_valid <= 1'b0;
            end
        end
    end

endmodule
