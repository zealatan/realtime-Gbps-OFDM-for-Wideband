`timescale 1ns/1ps
// =============================================================
//  meyr_cfo_top.v
//
//  Complete Meyr Integer CFO Estimation Pipeline
//
//  DATAPATH (all pipelined, no FSM):
//    PSS/SSS time-domain input
//      → meyr_feeder → xfft_N (N-pt FFT, BFP)
//      → meyr_Rm_dut
//          → meyr_FFT_ak_dut (A[k] + zero-pad)
//          → xfft_2N (2N-pt FFT, BFP)
//          → ROM × (conj(FFT(B[k])))
//      → meyr_ifft_peak_dut
//          → xfft_IFFT (2N-pt IFFT, BFP)
//          → Peak power search
//      → cfo_int output
//
//  CONFIG:
//    All three FFT IPs are configured by one-shot latches
//    immediately after reset. No external config interface
//    needed - the module is self-initializing.
//
//  ROM:
//    conj(FFT(B[k])) is stored in inferred BRAM inside
//    meyr_Rm_dut. For simulation, load via hierarchical
//    $readmemh from the TB. For synthesis, add
//      initial $readmemh("bk_conj_fft512_rom.txt", rom);
//    inside meyr_Rm_dut, or replace with BRAM IP + .coe.
//
//  PARAMETERS:
//    N      : subcarrier count (PSS/SSS length)
//    FFT_2N : correlation FFT size (2*N)
//
//  TIMING at 250 MHz, N=256:
//    End-to-end latency: ~3742 cycles = ~14.97 µs
// =============================================================
module meyr_cfo_top #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,

    // Runtime ROM loader for conj(FFT(B[k])).
    input  wire        rom_we,
    input  wire [12:0] rom_waddr,
    input  wire [63:0] rom_wdata,

    // ---- Input: PSS/SSS time-domain AXI-Stream ----
    // PSS frame (N samples) followed by SSS frame (N samples)
    // {im[15:0], re[15:0]} packed 32-bit
    input  wire [31:0] s_tdata,
    input  wire        s_tvalid,
    output wire        s_tready,

    // ---- Output: Integer CFO ----
    output wire signed [31:0]              cfo_int,
    output wire [N_LOG2_MAX:0]             peak_idx,
    output wire                            cfo_valid,

    // ---- Debug: IFFT stream (optional, can leave unconnected) ----
    output wire [63:0] dbg_ifft_tdata,
    output wire        dbg_ifft_tvalid,
    output wire        dbg_ifft_tlast
);

    // =========================================================
    // 0. Transform-length re-init on runtime N change.
    //    The Xilinx FFT latches NFFT at (re)configuration and does NOT
    //    switch transform length on the fly. Whenever n_log2 changes we
    //    hold the FFT cores + feeder + config one-shots in reset for a few
    //    cycles so they re-initialize and reload the new NFFT. The B[k] ROM
    //    write is not gated by this reset, so a loaded ROM survives.
    // =========================================================
    // Reset-hold length after an n_log2 change. Xilinx FFT aresetn needs only
    // >=2 cycles; everything after reset is AXI-handshake gated, so the exact
    // value is not timing-critical. Held generously (N-changes are rare).
    localparam RST_HOLD = 64;
    reg  [4:0] n_log2_q;
    reg  [7:0] nlog2_hold;
    wire       n_log2_changed = (n_log2 != n_log2_q);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_log2_q   <= 5'd31;            // force a re-init on first valid n_log2
            nlog2_hold <= RST_HOLD[7:0];
        end else begin
            n_log2_q <= n_log2;
            if (n_log2_changed)       nlog2_hold <= RST_HOLD[7:0];
            else if (nlog2_hold != 0) nlog2_hold <= nlog2_hold - 1'b1;
        end
    end
    wire fft_rst_n = rst_n & (nlog2_hold == 8'd0);

    // =========================================================
    // 1. FFT_N: PSS/SSS Time → Frequency
    //    meyr_feeder handles config + tlast insertion
    // =========================================================
    wire        fftN_cfg_tvalid;
    wire        fftN_cfg_tready;
    wire [15:0] fftN_cfg_tdata;

    wire        fftN_din_tvalid;
    wire        fftN_din_tready;
    wire [31:0] fftN_din_tdata;
    wire        fftN_din_tlast;

    wire        fftN_dout_tvalid;
    wire [31:0] fftN_dout_tdata;
    wire        fftN_dout_tlast;

    meyr_feeder #(
        .N_LOG2_MAX(N_LOG2_MAX),
        .CFG_FWD_INV(1'b1), // forward FFT
        .DATA_W  (32)       // 16-bit I/Q
    ) u_feed_fftN (
        .clk       (clk),
        .rst_n     (fft_rst_n),
        .n_log2    (n_log2),
        .s_tdata   (s_tdata),
        .s_tvalid  (s_tvalid),
        .s_tready  (s_tready),
        .cfg_tvalid(fftN_cfg_tvalid),
        .cfg_tready(fftN_cfg_tready),
        .cfg_tdata (fftN_cfg_tdata),
        .fft_tvalid(fftN_din_tvalid),
        .fft_tready(fftN_din_tready),
        .fft_tdata (fftN_din_tdata),
        .fft_tlast (fftN_din_tlast)
    );

    xfft_N u_fft_N (
        .aclk                        (clk),
        .aresetn                     (fft_rst_n),
        .s_axis_config_tvalid        (fftN_cfg_tvalid),
        .s_axis_config_tready        (fftN_cfg_tready),
        // IP's C_S_AXIS_CONFIG_TDATA_WIDTH = 8; only FWD_INV[0] is meaningful.
        .s_axis_config_tdata         (fftN_cfg_tdata[7:0]),
        .s_axis_data_tvalid          (fftN_din_tvalid),
        .s_axis_data_tready          (fftN_din_tready),
        .s_axis_data_tdata           (fftN_din_tdata),
        .s_axis_data_tlast           (fftN_din_tlast),
        .m_axis_data_tvalid          (fftN_dout_tvalid),
        .m_axis_data_tready          (1'b1),
        .m_axis_data_tdata           (fftN_dout_tdata),
        .m_axis_data_tlast           (fftN_dout_tlast),
        .m_axis_status_tready        (1'b1),
        .event_frame_started         (),
        .event_tlast_unexpected      (),
        .event_tlast_missing         (),
        .event_status_channel_halt   (),
        .event_data_in_channel_halt  (),
        .event_data_out_channel_halt ()
    );

    // =========================================================
    // 2. meyr_Rm_dut: A[k] + ZeroPad + FFT_2N + ROM Multiply
    //    One-shot config for internal xfft_2N (forward)
    // =========================================================
    reg       cfg2N_done;
    reg [4:0] cfg2N_n_log2_seen;
    wire cfg2N_tready;

    always @(posedge clk or negedge fft_rst_n) begin
        if (!fft_rst_n) begin
            cfg2N_done <= 1'b0;
            cfg2N_n_log2_seen <= 5'd0;
        end else if (cfg2N_n_log2_seen != n_log2) begin
            cfg2N_done <= 1'b0;
            cfg2N_n_log2_seen <= n_log2;
        end else if (!cfg2N_done && cfg2N_tready) begin
            cfg2N_done <= 1'b1;
        end
    end

    wire [63:0] rm_tdata;
    wire        rm_tvalid, rm_tlast;

    meyr_Rm_dut #(
        .N_LOG2_MAX(N_LOG2_MAX)
    ) u_rm_dut (
        .clk        (clk),
        .rst_n      (fft_rst_n),
        .n_log2     (n_log2),
        // forward 2N FFT: FWD_INV=1 at bit 0 (HAS_NFFT=0 IP; see meyr_feeder note).
        .cfg2N_tdata ({15'b0, 1'b1}),
        .cfg2N_tvalid(~cfg2N_done),    // one-shot: active until accepted
        .cfg2N_tready(cfg2N_tready),
        .rom_we     (rom_we),
        .rom_waddr  (rom_waddr),
        .rom_wdata  (rom_wdata),
        .din_tdata   (fftN_dout_tdata),
        .din_tvalid  (fftN_dout_tvalid),
        .din_tlast   (fftN_dout_tlast),
        .rm_tdata    (rm_tdata),
        .rm_tvalid   (rm_tvalid),
        .rm_tlast    (rm_tlast)
    );

    // =========================================================
    // 3. meyr_ifft_peak_dut: IFFT + Peak Search + CFO
    //    One-shot config for internal xfft_IFFT (inverse)
    // =========================================================
    reg       cfg_ifft_done;
    reg [4:0] cfg_ifft_n_log2_seen;
    wire cfg_ifft_tready;

    always @(posedge clk or negedge fft_rst_n) begin
        if (!fft_rst_n) begin
            cfg_ifft_done <= 1'b0;
            cfg_ifft_n_log2_seen <= 5'd0;
        end else if (cfg_ifft_n_log2_seen != n_log2) begin
            cfg_ifft_done <= 1'b0;
            cfg_ifft_n_log2_seen <= n_log2;
        end else if (!cfg_ifft_done && cfg_ifft_tready) begin
            cfg_ifft_done <= 1'b1;
        end
    end

    meyr_ifft_peak_dut #(
        .N_LOG2_MAX(N_LOG2_MAX)
    ) u_ifft_peak (
        .clk           (clk),
        .rst_n         (fft_rst_n),
        .n_log2        (n_log2),
        // inverse 2N FFT: FWD_INV=0 at bit 0 (HAS_NFFT=0 IP; see meyr_feeder note).
        .cfg_ifft_tdata({15'b0, 1'b0}),
        .cfg_ifft_tvalid(~cfg_ifft_done),    // one-shot: active until accepted
        .cfg_ifft_tready(cfg_ifft_tready),
        .rm_tdata       (rm_tdata),
        .rm_tvalid      (rm_tvalid),
        .rm_tlast       (rm_tlast),
        .ifft_tdata     (dbg_ifft_tdata),
        .ifft_tvalid    (dbg_ifft_tvalid),
        .ifft_tlast     (dbg_ifft_tlast),
        .peak_idx       (peak_idx),
        .cfo_int        (cfo_int),
        .cfo_valid      (cfo_valid)
    );

endmodule
