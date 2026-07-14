`timescale 1ns/1ps
// =============================================================
//  p5_functional_cov.sv  -  B2 functional coverage
//
//  Bind module that attaches SystemVerilog covergroups to the
//  new core. Each covergroup samples at meaningful RTL events
//  (cfo_valid, AXI handshake, FSM transition).
//
//  Coverpoints:
//    1. k_int sweep — all of [-8..+8] hit at least once
//    2. peak_idx range bins — low/mid/high quarters of [0,2N-1]
//    3. AXI-Stream handshake — back-to-back / stalled
//    4. cfo_int sign — positive / negative / zero
//    5. Cross k_int × backpressure pattern
//
//  Hit when bound to:
//    bind meyr_cfo_top p5_functional_cov_meyr u_cov (.*);
// =============================================================

module p5_functional_cov_meyr #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,
    input  wire        rom_we,
    input  wire [12:0] rom_waddr,
    input  wire [63:0] rom_wdata,
    input  wire [31:0] s_tdata,
    input  wire        s_tvalid,
    input  wire        s_tready,
    input  wire signed [31:0]   cfo_int,
    input  wire [N_LOG2_MAX:0]  peak_idx,
    input  wire                 cfo_valid,
    input  wire [63:0] dbg_ifft_tdata,
    input  wire        dbg_ifft_tvalid,
    input  wire        dbg_ifft_tlast
);

    // Sample on cfo_valid: capture the resolved k_int + peak_idx
    covergroup cg_cfo_result @(posedge clk iff (cfo_valid && rst_n));
        cp_k_int: coverpoint cfo_int {
            bins neg8 = {-8}; bins neg7 = {-7}; bins neg6 = {-6};
            bins neg5 = {-5}; bins neg4 = {-4}; bins neg3 = {-3};
            bins neg2 = {-2}; bins neg1 = {-1};
            bins zero = {0};
            bins pos1 = {1}; bins pos2 = {2}; bins pos3 = {3};
            bins pos4 = {4}; bins pos5 = {5}; bins pos6 = {6};
            bins pos7 = {7}; bins pos8 = {8};
            bins beyond = default;
        }
        cp_peak_quad: coverpoint peak_idx {
            bins q1_low      = {[0:127]};
            bins q2_mid_low  = {[128:255]};
            bins q3_mid_high = {[256:383]};
            bins q4_high     = {[384:511]};
        }
        cp_sign: coverpoint cfo_int {
            bins negative = {[-2147483648:-1]};
            bins zero     = {0};
            bins positive = {[1:2147483647]};
        }
        cx_k_x_quad: cross cp_k_int, cp_peak_quad;
    endgroup

    // AXI-Stream handshake coverage
    covergroup cg_axi @(posedge clk iff rst_n);
        cp_valid_ready: coverpoint {s_tvalid, s_tready} {
            bins idle      = {2'b00};
            bins stalled   = {2'b10};      // valid but not ready
            bins back_to_back = {2'b11};   // accepted
            illegal_bins   bad = {2'b01};  // ready alone is fine, but record
        }
    endgroup

    cg_cfo_result cg_cfo_inst = new;
    cg_axi        cg_axi_inst = new;
endmodule
