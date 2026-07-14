`timescale 1ns/1ps
// =============================================================
//  meyr_zeropad.v
//  Ultra-Fast Pipelined Zero Padder (Counter-Based)
// =============================================================
module meyr_zeropad #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,

    // Input from A[k] Multiplier
    input  wire [63:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tlast, // Ignored: We rely strictly on counting N
    output wire        s_tready,

    // Output to xfft_2N IP
    output wire [63:0] m_tdata,
    output wire        m_tvalid,
    output wire        m_tlast,
    input  wire        m_tready
);

    // Dynamically sized counter
    reg [N_LOG2_MAX:0] cnt;
    wire [N_LOG2_MAX:0] n_runtime =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << n_log2);
    wire [N_LOG2_MAX:0] fft2n_last =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << (n_log2 + 1'b1)) - 1'b1;
    
    // Purely combinational phase detection (0 = Pass Data, 1 = Pad Zeros)
    wire is_pad_phase = (cnt >= n_runtime);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0;
        end else begin
            // Advance counter ONLY when the downstream FFT is ready to accept
            if (m_tready) begin
                // In data phase: advance only when upstream provides a valid sample
                if (!is_pad_phase && s_tvalid) begin
                    cnt <= cnt + 1;
                end 
                // In padding phase: continuously stream zeros at 1 sample/clock
                else if (is_pad_phase) begin
                    cnt <= (cnt == fft2n_last) ? 0 : cnt + 1;
                end
            end
        end
    end

    // --- Purely Combinational AXI-Stream Routing ---
    // Instantly switch interfaces without FSM overhead or clock latency

    // Only accept new data from the multiplier if we are NOT in the padding phase
    assign s_tready = m_tready & ~is_pad_phase;
    
    // Output is valid if we have real data OR if we are generating zeros
    assign m_tvalid = is_pad_phase | s_tvalid;
    
    // Multiplex the data: Zeros during pad phase, actual data otherwise
    assign m_tdata  = is_pad_phase ? 64'd0 : s_tdata;
    
    // Assert tlast exactly on the final zero of the 2N frame
    assign m_tlast  = is_pad_phase & (cnt == fft2n_last);

endmodule
