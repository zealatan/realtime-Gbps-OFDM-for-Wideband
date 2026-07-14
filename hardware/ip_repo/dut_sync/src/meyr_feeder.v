`timescale 1ns/1ps
// =============================================================
//  meyr_feeder.v
//
//  Purely Pipelined FFT Feeder (No FSM)
//
//  ARCHITECTURE:
//    - One-shot config latch: fires config word immediately
//      after reset, latches done on acceptance. Does NOT block
//      the data path - just a single flip-flop.
//    - Data path: registered pass-through (1-cycle latency),
//      active as soon as config accepted.
//    - tlast counter: free-running, wraps every N samples.
//
//  LATENCY: 1 clock cycle (registered output stage)
//
//  USAGE:
//    meyr_feeder #(.N(256),  .CFG_WORD(8'h01), .DATA_W(32)) u_fftN  (...)
//    meyr_feeder #(.N(512),  .CFG_WORD(8'h01), .DATA_W(64)) u_fft2N (...)
//    meyr_feeder #(.N(512),  .CFG_WORD(8'h00), .DATA_W(64)) u_ifft  (...)
// =============================================================
module meyr_feeder #(
    parameter N_LOG2_MAX = 12,
    parameter CFG_FWD_INV = 1'b1,  // 1 = forward FFT, 0 = inverse FFT
    parameter DATA_W   = 32        // 32 for 16-bit I/Q, 64 for 32-bit I/Q
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [4:0]        n_log2,

    // ---- Upstream: continuous 1-sample/clock input ----
    input  wire [DATA_W-1:0] s_tdata,
    input  wire              s_tvalid,
    output wire              s_tready,

    // ---- FFT S_AXIS_CONFIG ----
    output wire              cfg_tvalid,
    input  wire              cfg_tready,
    output wire [15:0]       cfg_tdata,

    // ---- FFT S_AXIS_DATA ----
    output reg               fft_tvalid,
    input  wire              fft_tready,
    output reg  [DATA_W-1:0] fft_tdata,
    output reg               fft_tlast
);

    // ---------------------------------------------------------
    // 1. One-Shot Config (single flip-flop, not an FSM)
    //    Presents CFG_WORD immediately after reset.
    //    Latches cfg_done on first tvalid & tready handshake.
    //    After that, config lines go idle permanently.
    // ---------------------------------------------------------
    reg       cfg_done;
    reg [4:0] cfg_n_log2_seen;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_done <= 1'b0;
            cfg_n_log2_seen <= 5'd0;
        end else if (cfg_n_log2_seen != n_log2) begin
            cfg_done <= 1'b0;
            cfg_n_log2_seen <= n_log2;
        end else if (!cfg_done && cfg_tready) begin
            cfg_done <= 1'b1;
        end
    end

    // Config bus: active only until accepted, then permanently idle.
    // xfft v9.1 config word for the IPs in rtl/xfft_{N,2N,IFFT}/*.xci:
    //   C_S_AXIS_CONFIG_TDATA_WIDTH=8, C_HAS_NFFT=0, BFP (no SCALE_SCH), no CP.
    // Layout (LSB first per PG109): bit0 = FWD_INV[0]; remaining bits unused.
    // The 16-bit wire is truncated to the 8-bit IP port; only [7:0] reaches it.
    assign cfg_tvalid = ~cfg_done;
    assign cfg_tdata  = {15'b0, CFG_FWD_INV};
    // n_log2 is consumed by wrapper-side counters (tlast, ROM addressing); the
    // IP itself is fixed-NFFT and ignores any runtime length bits.

    // ---------------------------------------------------------
    // 2. Data Path: Registered Pass-Through (1-cycle pipeline)
    //    Active only after config accepted.
    //    Backpressure: hold when FFT deasserts fft_tready.
    // ---------------------------------------------------------
    wire data_active = cfg_done & fft_tready;

    // Upstream handshake: consume only when the selected FFT length has been
    // accepted on the config channel.
    assign s_tready = data_active;

    // ---------------------------------------------------------
    // 3. tlast Counter: Free-Running, Wraps Every N Samples
    // ---------------------------------------------------------
    reg [N_LOG2_MAX-1:0] cnt;
    wire [N_LOG2_MAX-1:0] n_last = ({{(N_LOG2_MAX-1){1'b0}}, 1'b1} << n_log2) - 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= {N_LOG2_MAX{1'b0}};
            fft_tvalid <= 1'b0;
            fft_tdata  <= {DATA_W{1'b0}};
            fft_tlast  <= 1'b0;
        end else if (cfg_n_log2_seen != n_log2) begin
            cnt        <= {N_LOG2_MAX{1'b0}};
            fft_tvalid <= 1'b0;
            fft_tlast  <= 1'b0;
        end else begin
            if (data_active) begin
                if (s_tvalid) begin
                    fft_tvalid <= 1'b1;
                    fft_tdata  <= s_tdata;
                    fft_tlast  <= (cnt == n_last);
                    cnt        <= (cnt == n_last) ? {N_LOG2_MAX{1'b0}} : cnt + 1'b1;
                end else begin
                    fft_tvalid <= 1'b0;
                    fft_tlast  <= 1'b0;
                end
            end else begin
                fft_tvalid <= 1'b0;
                fft_tlast  <= 1'b0;
            end
        end
    end

endmodule
