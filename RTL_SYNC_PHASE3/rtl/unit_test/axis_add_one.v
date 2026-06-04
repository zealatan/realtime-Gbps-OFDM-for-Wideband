// axis_add_one: AXI-Stream pass-through; adds 1 to each input word.
// One-entry output buffer; s_tready is combinatorial (skid-register pattern).
// See ai_context/interface_contract_axis_add_one.md for protocol contract.

module axis_add_one #(
    parameter DATA_WIDTH = 32
) (
    input  wire                   aclk,
    input  wire                   aresetn,

    // AXI-Stream slave (input)
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    // AXI-Stream master (output)
    output reg  [DATA_WIDTH-1:0]  m_axis_tdata,
    output reg                    m_axis_tvalid,
    input  wire                   m_axis_tready,
    output reg                    m_axis_tlast
);

    // Buffer is available when empty or being consumed this cycle.
    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tdata  <= {DATA_WIDTH{1'b0}};
            m_axis_tlast  <= 1'b0;
        end else if (s_axis_tvalid && s_axis_tready) begin
            // Accept input: store incremented word in output buffer.
            m_axis_tvalid <= 1'b1;
            m_axis_tdata  <= s_axis_tdata + {{(DATA_WIDTH-1){1'b0}}, 1'b1};
            m_axis_tlast  <= s_axis_tlast;
        end else if (m_axis_tready) begin
            // Output consumed; no new input this cycle — clear buffer.
            m_axis_tvalid <= 1'b0;
        end
    end

endmodule
