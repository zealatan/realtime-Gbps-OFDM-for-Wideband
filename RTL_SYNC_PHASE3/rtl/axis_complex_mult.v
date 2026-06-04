module axis_complex_mult #(
    parameter DATA_WIDTH      = 32,
    parameter COMPONENT_WIDTH = 16,
    parameter SHIFT           = 15
) (
    input  wire                   aclk,
    input  wire                   aresetn,

    input  wire [DATA_WIDTH-1:0]  s_axis_a_tdata,
    input  wire                   s_axis_a_tvalid,
    output wire                   s_axis_a_tready,
    input  wire                   s_axis_a_tlast,

    input  wire [DATA_WIDTH-1:0]  s_axis_b_tdata,
    input  wire                   s_axis_b_tvalid,
    output wire                   s_axis_b_tready,
    input  wire                   s_axis_b_tlast,

    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast
);
    localparam CW = COMPONENT_WIDTH;

    wire buf_ready = !m_axis_tvalid || m_axis_tready;

    assign s_axis_a_tready = s_axis_b_tvalid && buf_ready;
    assign s_axis_b_tready = s_axis_a_tvalid && buf_ready;
    wire accept = s_axis_a_tvalid && s_axis_b_tvalid && buf_ready;

    wire signed [CW-1:0] a_real = s_axis_a_tdata[DATA_WIDTH-1 : CW];
    wire signed [CW-1:0] a_imag = s_axis_a_tdata[CW-1         : 0];
    wire signed [CW-1:0] b_real = s_axis_b_tdata[DATA_WIDTH-1 : CW];
    wire signed [CW-1:0] b_imag = s_axis_b_tdata[CW-1         : 0];

    wire signed [2*CW-1:0] prod_rr = a_real * b_real;
    wire signed [2*CW-1:0] prod_ii = a_imag * b_imag;
    wire signed [2*CW-1:0] prod_ri = a_real * b_imag;
    wire signed [2*CW-1:0] prod_ir = a_imag * b_real;

    // 33-bit accumulation prevents carry loss when sum/difference overflows 32 bits
    wire signed [2*CW:0] full_real = {prod_rr[2*CW-1], prod_rr} - {prod_ii[2*CW-1], prod_ii};
    wire signed [2*CW:0] full_imag = {prod_ri[2*CW-1], prod_ri} + {prod_ir[2*CW-1], prod_ir};

    wire signed [CW-1:0] out_real = full_real[2*CW-2 : SHIFT];
    wire signed [CW-1:0] out_imag = full_imag[2*CW-2 : SHIFT];

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tlast  <= 1'b0;
        end else if (accept) begin
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= {out_real, out_imag};
            m_axis_tlast  <= s_axis_a_tlast | s_axis_b_tlast;
        end else if (m_axis_tready) begin
            m_axis_tvalid <= 1'b0;
        end
    end
endmodule
