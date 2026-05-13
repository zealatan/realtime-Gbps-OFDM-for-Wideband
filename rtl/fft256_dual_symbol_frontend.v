`timescale 1ns/1ps

// FFT256 dual-symbol frontend — Step 34 interface skeleton.
//
// Accepts PSS (symbol_sel=0) and SSS (symbol_sel=1) time-domain samples,
// buffers them internally, and streams frequency-domain bins after "computation".
//
// FFT PLACEHOLDER: S_COMPUTE currently copies input buffers unchanged to the
// output buffers.  This is the bypass/stub for simulation testing.  Replace
// S_COMPUTE with an FFT IP instantiation (e.g. Xilinx FFT v9.1) for production.
//
// Since the production FFT is a placeholder, the testbench validates shift
// recovery by injecting frequency-domain test vectors as the "time-domain"
// input (bypass mode).  See docs/step34_fft256_frontend_behavioral_integration.md.
//
// FFT bin order convention (for production replacement):
//   Natural order: bin k=0 = DC, k=1..127 = positive frequencies,
//   k=128..255 = negative frequencies.  No fftshift applied.
//
// Streaming protocol:
//   Input:  s_valid/s_ready handshake; s_symbol_sel selects PSS(0) or SSS(1);
//           s_index is the time-domain sample index (0..FFT_LEN-1).
//   Output: m_valid/m_ready handshake; m_symbol_sel selects PSS(0) or SSS(1);
//           m_index is the frequency bin index (0..FFT_LEN-1).
//   PSS samples accepted first (256), then SSS samples (256).
//   Output streams PSS FFT bins (0..255) then SSS FFT bins (0..255).
//
// Synthesizable: Yes (no real/sin/cos).  Production FFT IP connects in S_COMPUTE.

module fft256_dual_symbol_frontend #(
    parameter integer FFT_LEN  = 256,
    parameter integer IQ_WIDTH = 16
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    input  wire                         start,

    // Time-domain input stream
    input  wire                         s_valid,
    output wire                         s_ready,
    input  wire                         s_symbol_sel,   // 0=PSS 1=SSS
    input  wire [7:0]                   s_index,
    input  wire signed [IQ_WIDTH-1:0]   s_i,
    input  wire signed [IQ_WIDTH-1:0]   s_q,

    // Frequency-domain output stream
    output reg                          m_valid,
    input  wire                         m_ready,
    output reg                          m_symbol_sel,   // 0=PSS_FFT 1=SSS_FFT
    output reg  [7:0]                   m_index,
    output reg  signed [IQ_WIDTH-1:0]   m_i,
    output reg  signed [IQ_WIDTH-1:0]   m_q,

    output reg                          busy,
    output reg                          done,
    output reg                          error
);

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_FILL       = 3'd1,
        S_COMPUTE    = 3'd2,
        S_STREAM_PSS = 3'd3,
        S_STREAM_SSS = 3'd4,
        S_DONE       = 3'd5;

    reg [2:0] state;

    // Input time-domain buffers
    reg signed [IQ_WIDTH-1:0] pss_buf_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] pss_buf_q [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] sss_buf_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] sss_buf_q [0:FFT_LEN-1];

    // FFT output buffers (populated in S_COMPUTE)
    // FFT PLACEHOLDER: filled by copying input buffers.
    // Replace S_COMPUTE logic with FFT IP output for production.
    reg signed [IQ_WIDTH-1:0] fft_pss_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_pss_q [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_sss_i [0:FFT_LEN-1];
    reg signed [IQ_WIDTH-1:0] fft_sss_q [0:FFT_LEN-1];

    reg [8:0] pss_cnt;    // PSS samples accepted
    reg [8:0] sss_cnt;    // SSS samples accepted
    reg [7:0] stream_ptr; // output stream position

    integer _k; // unroll index for S_COMPUTE for-loop

    // s_ready: accept PSS when pss_cnt < FFT_LEN, SSS when sss_cnt < FFT_LEN
    assign s_ready = (state == S_FILL) &&
                     ((!s_symbol_sel && pss_cnt < FFT_LEN) ||
                      ( s_symbol_sel && sss_cnt < FFT_LEN));

    always @(posedge aclk) begin
        if (!aresetn) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            error      <= 1'b0;
            pss_cnt    <= 9'd0;
            sss_cnt    <= 9'd0;
            stream_ptr <= 8'd0;
            m_valid    <= 1'b0;
            m_symbol_sel <= 1'b0;
            m_index    <= 8'd0;
            m_i        <= {IQ_WIDTH{1'b0}};
            m_q        <= {IQ_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;
            if (start && busy) error <= 1'b1;

            case (state)

                // ---------------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy) begin
                        busy    <= 1'b1;
                        pss_cnt <= 9'd0;
                        sss_cnt <= 9'd0;
                        state   <= S_FILL;
                    end
                end

                // ---------------------------------------------------------------
                // Buffer PSS and SSS time-domain samples.
                // Route to pss_buf or sss_buf based on s_symbol_sel.
                // Transition after both buffers are full.
                // ---------------------------------------------------------------
                S_FILL: begin
                    if (s_valid && s_ready) begin
                        if (!s_symbol_sel && pss_cnt < FFT_LEN) begin
                            pss_buf_i[s_index] <= s_i;
                            pss_buf_q[s_index] <= s_q;
                            pss_cnt            <= pss_cnt + 9'd1;
                        end else if (s_symbol_sel && sss_cnt < FFT_LEN) begin
                            sss_buf_i[s_index] <= s_i;
                            sss_buf_q[s_index] <= s_q;
                            sss_cnt            <= sss_cnt + 9'd1;
                        end
                    end
                    // Transition when both buffers full (checked next cycle via NBA)
                    if (pss_cnt == FFT_LEN && sss_cnt == FFT_LEN)
                        state <= S_COMPUTE;
                end

                // ---------------------------------------------------------------
                // FFT PLACEHOLDER: copy time-domain buffers to FFT output buffers.
                // Production: instantiate FFT IP here and wait for its done signal.
                // The for-loop unrolls to 256 parallel NBA assignments at synthesis.
                // ---------------------------------------------------------------
                S_COMPUTE: begin
                    for (_k = 0; _k < FFT_LEN; _k = _k + 1) begin
                        fft_pss_i[_k] <= pss_buf_i[_k];
                        fft_pss_q[_k] <= pss_buf_q[_k];
                        fft_sss_i[_k] <= sss_buf_i[_k];
                        fft_sss_q[_k] <= sss_buf_q[_k];
                    end
                    stream_ptr <= 8'd0;
                    state      <= S_STREAM_PSS;
                end

                // ---------------------------------------------------------------
                // Stream PSS FFT bins (symbol_sel=0), index 0..FFT_LEN-1.
                // Advance on each m_ready handshake.
                // ---------------------------------------------------------------
                S_STREAM_PSS: begin
                    m_valid      <= 1'b1;
                    m_symbol_sel <= 1'b0;
                    m_index      <= stream_ptr;
                    m_i          <= fft_pss_i[stream_ptr];
                    m_q          <= fft_pss_q[stream_ptr];
                    if (m_ready) begin
                        if (stream_ptr == FFT_LEN - 1) begin
                            stream_ptr <= 8'd0;
                            state      <= S_STREAM_SSS;
                        end else begin
                            stream_ptr <= stream_ptr + 8'd1;
                        end
                    end
                end

                // ---------------------------------------------------------------
                // Stream SSS FFT bins (symbol_sel=1), index 0..FFT_LEN-1.
                // ---------------------------------------------------------------
                S_STREAM_SSS: begin
                    m_valid      <= 1'b1;
                    m_symbol_sel <= 1'b1;
                    m_index      <= stream_ptr;
                    m_i          <= fft_sss_i[stream_ptr];
                    m_q          <= fft_sss_q[stream_ptr];
                    if (m_ready) begin
                        if (stream_ptr == FFT_LEN - 1) begin
                            state <= S_DONE;
                        end else begin
                            stream_ptr <= stream_ptr + 8'd1;
                        end
                    end
                end

                // ---------------------------------------------------------------
                S_DONE: begin
                    m_valid <= 1'b0;
                    done    <= 1'b1;
                    busy    <= 1'b0;
                    state   <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
