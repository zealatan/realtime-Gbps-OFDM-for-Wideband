// =====================================================================
// xfft_N_bfp_stub.v   (SIMULATION-ONLY behavioral model of xfft_N)
// ---------------------------------------------------------------------
// A *sanity* behavioral stand-in for the real Xilinx xfft_N 9.1 core, so
// the rx_fft_frontend FSM / BFP-recover / fftshift datapath can be
// exercised under plain iverilog WITHOUT Vivado. It is NOT the gate:
// the acceptance run instantiates the REAL xfft_N IP under xsim (see
// scripts/run_rx_fft_frontend_xsim.sh). This stub reproduces the IP's
// AXI-Stream data interface and BFP semantics:
//   * 256-pt forward DFT (exp(-j2pi kn/N)) of each frame of 256 samples,
//   * natural output order 0..255,
//   * block-floating-point: right-shift the whole frame by the minimum
//     `blk_exp` so max(|re|,|im|) fits signed-16b; report blk_exp on
//     m_axis_data_tuser (matches the recover math the wrapper inverts).
//   * 1 sample/clk in, 1 bin/clk out, honors s_axis_data_tready (always
//     ready here) and m_axis_data_tready back-pressure.
// Truncation (round-to-zero) on the BFP shift, like the IP.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module xfft_N (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        s_axis_config_tvalid,
    output wire        s_axis_config_tready,
    input  wire [7:0]  s_axis_config_tdata,
    input  wire        s_axis_data_tvalid,
    output wire        s_axis_data_tready,
    input  wire [31:0] s_axis_data_tdata,
    input  wire        s_axis_data_tlast,
    output reg         m_axis_data_tvalid,
    input  wire        m_axis_data_tready,
    output reg  [31:0] m_axis_data_tdata,
    output reg         m_axis_data_tlast,
    output reg  [7:0]  m_axis_data_tuser,
    input  wire        m_axis_status_tready,
    output wire        event_frame_started,
    output wire        event_tlast_unexpected,
    output wire        event_tlast_missing,
    output wire        event_status_channel_halt,
    output wire        event_data_in_channel_halt,
    output wire        event_data_out_channel_halt
);
    localparam integer N = 256;

    assign s_axis_config_tready = 1'b1;
    assign s_axis_data_tready   = 1'b1;   // stub never back-pressures input
    assign event_frame_started        = 1'b0;
    assign event_tlast_unexpected     = 1'b0;
    assign event_tlast_missing        = 1'b0;
    assign event_status_channel_halt  = 1'b0;
    assign event_data_in_channel_halt = 1'b0;
    assign event_data_out_channel_halt= 1'b0;

    // input frame accumulation
    real    in_re [0:N-1];
    real    in_im [0:N-1];
    integer in_cnt;

    // output frame (natural order), as integers after BFP shift
    integer out_re [0:N-1];
    integer out_im [0:N-1];
    integer out_blk;
    integer out_cnt;
    integer out_have;     // 1 when a computed frame is waiting to stream

    // twiddle
    real PI; initial PI = 3.141592653589793;

    integer k, n;
    real    acc_re, acc_im, ang, c, s, xr, xi;
    real    maxmag, av;
    integer be;

    task compute_fft;
        begin
            // forward DFT
            maxmag = 0.0;
            for (k = 0; k < N; k = k + 1) begin
                acc_re = 0.0; acc_im = 0.0;
                for (n = 0; n < N; n = n + 1) begin
                    ang = -2.0*PI*k*n/N;
                    c = $cos(ang); s = $sin(ang);
                    xr = in_re[n]; xi = in_im[n];
                    acc_re = acc_re + xr*c - xi*s;
                    acc_im = acc_im + xr*s + xi*c;
                end
                // store full-precision in temporaries via out arrays (rounded later)
                out_re[k] = $rtoi(acc_re >= 0 ? acc_re+0.5 : acc_re-0.5);
                out_im[k] = $rtoi(acc_im >= 0 ? acc_im+0.5 : acc_im-0.5);
                av = (out_re[k] < 0 ? -out_re[k] : out_re[k]);
                if (av > maxmag) maxmag = av;
                av = (out_im[k] < 0 ? -out_im[k] : out_im[k]);
                if (av > maxmag) maxmag = av;
            end
            // block exponent: min right-shift so maxmag <= 32767
            be = 0;
            while ((maxmag / (1<<be)) > 32767.0) be = be + 1;
            out_blk = be;
            for (k = 0; k < N; k = k + 1) begin
                // arithmetic right shift (truncation toward -inf like >>>),
                // matches a signed shift of the integer DFT result.
                out_re[k] = out_re[k] >>> be;
                out_im[k] = out_im[k] >>> be;
            end
        end
    endtask

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            in_cnt   <= 0;
            out_cnt  <= 0;
            out_have <= 0;
            m_axis_data_tvalid <= 1'b0;
            m_axis_data_tlast  <= 1'b0;
            m_axis_data_tdata  <= 32'd0;
            m_axis_data_tuser  <= 8'd0;
        end else begin
            // ---- accept input samples, build a frame ----
            if (s_axis_data_tvalid && s_axis_data_tready) begin
                in_re[in_cnt] = $signed(s_axis_data_tdata[15:0]);
                in_im[in_cnt] = $signed(s_axis_data_tdata[31:16]);
                if (in_cnt == N-1) begin
                    in_cnt <= 0;
                    compute_fft;      // blocking: fills out_re/out_im/out_blk
                    out_cnt  <= 0;
                    out_have <= 1;
                end else begin
                    in_cnt <= in_cnt + 1;
                end
            end

            // ---- stream output frame, honoring back-pressure ----
            if (out_have) begin
                if (!m_axis_data_tvalid || m_axis_data_tready) begin
                    m_axis_data_tdata  <= { out_im[out_cnt][15:0],
                                            out_re[out_cnt][15:0] };
                    m_axis_data_tuser  <= out_blk[7:0];
                    m_axis_data_tlast  <= (out_cnt == N-1);
                    m_axis_data_tvalid <= 1'b1;
                    if (out_cnt == N-1) begin
                        out_cnt  <= 0;
                        out_have <= 0;
                    end else begin
                        out_cnt <= out_cnt + 1;
                    end
                end
            end else if (m_axis_data_tready) begin
                m_axis_data_tvalid <= 1'b0;
                m_axis_data_tlast  <= 1'b0;
            end
        end
    end
endmodule

`default_nettype wire
