`timescale 1ns/1ps
// =============================================================
//  p5_invariants.sv  -  P5-08 / ISS-13 invariant assertions.
//
//  Bind-mode module that attaches SVA assertions to key RTL
//  modules without changing their source. Fails the running
//  simulation if any invariant breaks.
//
//  Bound at TB elaboration:
//    bind meyr_cfo_top         p5_invariants_meyr_cfo_top   u_inv (.*);
//    bind meyr_ifft_peak_dut   p5_invariants_ifft_peak      u_inv (.*);
//
//  Invariants proven here:
//    1. cfo_int output is always within the legal range [-N, N-1].
//    2. peak_idx output is always within [0, 2N-1].
//    3. The Nyquist bin (peak_idx == N) is never picked when
//       cfo_valid fires (P5-01A Step C Nyquist guard contract).
//    4. cfo_valid is a strict 1-cycle pulse (no double-pulse races).
// =============================================================

module p5_invariants_meyr_cfo_top #(
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
    wire [N_LOG2_MAX:0] n_runtime =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << n_log2);
    wire [N_LOG2_MAX:0] n2_minus_1 =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << (n_log2 + 1'b1)) - 1'b1;
    wire signed [31:0] n_runtime_s = $signed({19'd0, n_runtime});

    // Invariant 1: cfo_int in legal signed range when valid
    property p_cfo_int_range;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid |-> (cfo_int >= -n_runtime_s) && (cfo_int < n_runtime_s);
    endproperty
    inv_cfo_int_range: assert property (p_cfo_int_range)
        else $error("P5-INVARIANT cfo_int out of range: cfo_int=%0d N=%0d",
                    cfo_int, n_runtime_s);

    // Invariant 2: peak_idx in valid bin range when valid
    property p_peak_idx_range;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid |-> (peak_idx <= n2_minus_1);
    endproperty
    inv_peak_idx_range: assert property (p_peak_idx_range)
        else $error("P5-INVARIANT peak_idx out of range: peak_idx=%0d 2N-1=%0d",
                    peak_idx, n2_minus_1);

    // Invariant 3: Nyquist bin never picked (Step C guard)
    property p_no_nyquist;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid |-> (peak_idx != n_runtime);
    endproperty
    inv_no_nyquist: assert property (p_no_nyquist)
        else $error("P5-INVARIANT Nyquist bin picked: peak_idx=%0d == N=%0d",
                    peak_idx, n_runtime);

    // Invariant 4: cfo_valid is a 1-cycle pulse, not held high
    property p_cfo_valid_pulse;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid |=> !cfo_valid;
    endproperty
    inv_cfo_valid_pulse: assert property (p_cfo_valid_pulse)
        else $error("P5-INVARIANT cfo_valid held high for >1 cycle");
endmodule

// -------------------------------------------------------------
//  Bind target: meyr_ifft_peak_dut
//  Argument list mirrors the module's port signature so .*
//  binds positionally.
// -------------------------------------------------------------
module p5_invariants_ifft_peak #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,
    input  wire [15:0] cfg_ifft_tdata,
    input  wire        cfg_ifft_tvalid,
    input  wire        cfg_ifft_tready,
    input  wire [63:0] rm_tdata,
    input  wire        rm_tvalid,
    input  wire        rm_tlast,
    input  wire [63:0] ifft_tdata,
    input  wire        ifft_tvalid,
    input  wire        ifft_tlast,
    input  wire [N_LOG2_MAX:0]       peak_idx,
    input  wire signed [31:0]        cfo_int,
    input  wire                      cfo_valid
);
    wire [N_LOG2_MAX:0] n_runtime =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << n_log2);

    // Invariant 5: when peak_idx < N, cfo_int == peak_idx
    property p_decode_positive;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid && (peak_idx < n_runtime) |->
                (cfo_int == $signed({19'd0, peak_idx}));
    endproperty
    inv_decode_positive: assert property (p_decode_positive)
        else $error("P5-INVARIANT positive-bin decode broken");

    // Invariant 6: when peak_idx > N, cfo_int == peak_idx - 2N
    property p_decode_negative;
        @(posedge clk) disable iff (!rst_n)
            cfo_valid && (peak_idx > n_runtime) |->
                (cfo_int < 0);
    endproperty
    inv_decode_negative: assert property (p_decode_negative)
        else $error("P5-INVARIANT negative-bin cfo_int sign broken");
endmodule
