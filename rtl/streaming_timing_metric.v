`timescale 1ns/1ps
// P2-03: Streaming timing metric computation
// Converts P_I/P_Q/energy from P2-02 into a timing metric using a
// magnitude approximation and computes: metric = 2*|P| - energy (clamped >= 0).
module streaming_timing_metric #(
    parameter integer ACC_W    = 48,
    parameter integer METRIC_W = 32
) (
    input  wire                       clk,
    input  wire                       aresetn,
    input  wire signed [ACC_W-1:0]    p_i,
    input  wire signed [ACC_W-1:0]    p_q,
    input  wire        [ACC_W-1:0]    energy,
    input  wire                       in_valid,
    input  wire [31:0]                sample_index,
    output reg         [METRIC_W-1:0] metric,
    output reg                        m_valid,
    output reg  [31:0]                m_sample_index,
    output reg  signed [ACC_W-1:0]    m_p_i,
    output reg  signed [ACC_W-1:0]    m_p_q
);

    // -----------------------------------------------------------------------
    // Combinatorial: magnitude approximation and metric formation
    // -----------------------------------------------------------------------

    // Step 1: absolute values
    wire [ACC_W-1:0] abs_pi = p_i[ACC_W-1] ? (-p_i) : p_i;
    wire [ACC_W-1:0] abs_pq = p_q[ACC_W-1] ? (-p_q) : p_q;

    // Step 2: max / min
    wire [ACC_W-1:0] p_max = (abs_pi > abs_pq) ? abs_pi : abs_pq;
    wire [ACC_W-1:0] p_min = (abs_pi > abs_pq) ? abs_pq : abs_pi;

    // Step 3: 3/8 alpha-max-beta-min approximation
    //   mag_approx = p_max + (p_min >> 2) + (p_min >> 3)
    wire [ACC_W-1:0] mag_approx = p_max + (p_min >> 2) + (p_min >> 3);

    // Step 4: full metric (ACC_W+2 bits to avoid overflow)
    //   m_full = 2*mag_approx - energy
    wire signed [ACC_W+1:0] m_full = {2'b00, mag_approx} + {2'b00, mag_approx}
                                   - {2'b00, energy};

    // Step 5: clamp to non-negative; truncate to METRIC_W bits
    wire [METRIC_W-1:0] metric_w = m_full[ACC_W+1] ? {METRIC_W{1'b0}}
                                                    : m_full[METRIC_W-1:0];

    // -----------------------------------------------------------------------
    // 1-cycle registered pipeline
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            metric         <= {METRIC_W{1'b0}};
            m_valid        <= 1'b0;
            m_sample_index <= 32'd0;
            m_p_i          <= {ACC_W{1'b0}};
            m_p_q          <= {ACC_W{1'b0}};
        end else begin
            m_valid        <= in_valid;
            m_sample_index <= sample_index;
            m_p_i          <= p_i;
            m_p_q          <= p_q;
            if (in_valid) begin
                metric <= metric_w;
            end
        end
    end

endmodule
