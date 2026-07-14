// =====================================================================
// rx_eq_complex_div.v
// ---------------------------------------------------------------------
// Zero-forcing equalizer complex divider core (per-subcarrier).
//
//   eq[i] = RX[i] * conj(H[i]) / |H[i]|^2
//
//   num_i = Ri*Hi + Rq*Hq          (real part of RX*conj(H))
//   num_q = Rq*Hi - Ri*Hq          (imag part of RX*conj(H))
//   sc    = Hi*Hi + Hq*Hq          (= |H|^2)
//   eq    = (num_i + j*num_q) / sc
//
// All operands are signed Q15 integers at golden scale S = 5090.697374
// (float 1.0 -> 0x13E3). The golden output hex is eq_float * S, so the
// datapath computes:  eq_int = round( num / sc * S ).
//
// DIVIDER ARCHITECTURE (most timing-critical op in the chain):
//   * reciprocal of |H|^2 via normalize + 7-bit LUT seed + TWO
//     Newton-Raphson refinements  r <- r*(2 - x*r).
//   * |H|^2 is normalized into [2^30, 2^31) by a leading-zero shift
//     (sh = 31 - bitlength(sc)); reciprocal of the mantissa is computed
//     in Q18, then denormalized by the same shift in the final stage.
//   * Worst-case relative reciprocal error 3.8e-6 over the FULL 32-bit
//     |H|^2 dynamic range (verified) -> robust for small |H| as well.
//   * Fully registered, one complex sample per clock, back-to-back.
//
// Guard: sc == 0  ->  output 0 (band-edge / unpopulated bins).
//
// PIPELINE DEPTH: 12 stages (input reg -> output reg). LATENCY = 12 clk.
//   S1 input | S2 products | S3 sums(num,|H|^2) | S4 normalize+LUT seed |
//   S5a,S5b Newton iter-1 | S6a,S6b Newton iter-2 | S7 *S | S8 *recip |
//   S9a denorm-shift+round | S9b saturate+zero-guard.  Each NR iteration
//   is split so every clock does at most ONE DSP multiply, and the
//   variable barrel-shift is separated from saturation -- those two
//   structures were the Fmax limiters.
// A 12-deep "valid" shift register carries the strobe; tuser passes
// through for downstream bin/carrier tagging.
//
// Synthesizable Verilog-2001. No vendor primitives, no IP.
// Target part: xczu49dr-ffvf1760-2-e.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_eq_complex_div #(
    parameter integer DW       = 16,   // input I/Q width  (Q15)
    parameter integer HW       = 18,   // channel H width (>=18 per CONTRACT; sign-extended internally)
    parameter integer OW       = 16,   // output I/Q width (Q15)
    parameter integer UW       = 16,   // tuser width (carry bin index etc.)
    // fixed-point reciprocal parameters (locked, verified to 2 LSB vs golden)
    parameter integer PMANT    = 18,   // reciprocal mantissa fractional bits
    parameter integer SSHIFT   = 10,   // fractional bits of the S multiplier
    parameter integer SFIX     = 5212874, // round(5090.697374 * 2^10), 23-bit
    parameter         LUT_FILE = "rx_equalizer_recip_lut.hex"
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  ce,        // pipeline clock-enable (stall when low)

    input  wire                  in_valid,
    input  wire signed [DW-1:0]  rx_i,
    input  wire signed [DW-1:0]  rx_q,
    input  wire signed [HW-1:0]  h_i,
    input  wire signed [HW-1:0]  h_q,
    input  wire        [UW-1:0]  in_user,

    output wire                  out_valid,
    output wire signed [OW-1:0]  eq_i,
    output wire signed [OW-1:0]  eq_q,
    output wire        [UW-1:0]  out_user
);
    // Pipeline depth (input reg -> output reg):
    //   S1 S2 S3 S4 | S5a S5b S6a S6b | S7 S8 | S9a S9b  = 12 stages.
    localparam integer LAT = 12;

    // -----------------------------------------------------------------
    // valid + user pipeline (LAT deep)
    // -----------------------------------------------------------------
    reg                v_pipe [0:LAT-1];
    reg [UW-1:0]       u_pipe [0:LAT-1];
    integer pp;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (pp=0; pp<LAT; pp=pp+1) begin
                v_pipe[pp] <= 1'b0;
                u_pipe[pp] <= {UW{1'b0}};
            end
        end else if (ce) begin
            v_pipe[0] <= in_valid;
            u_pipe[0] <= in_user;
            for (pp=1; pp<LAT; pp=pp+1) begin
                v_pipe[pp] <= v_pipe[pp-1];
                u_pipe[pp] <= u_pipe[pp-1];
            end
        end
    end
    assign out_valid = v_pipe[LAT-1];
    assign out_user  = u_pipe[LAT-1];

    // -----------------------------------------------------------------
    // S1: register inputs (sign-extend H to a common signed width)
    // -----------------------------------------------------------------
    reg signed [DW-1:0] s1_ri, s1_rq;
    reg signed [HW-1:0] s1_hi, s1_hq;
    always @(posedge clk) if (ce) begin
        s1_ri <= rx_i; s1_rq <= rx_q;
        s1_hi <= h_i;  s1_hq <= h_q;
    end

    // -----------------------------------------------------------------
    // S2: products  (signed)
    //   RiHi RqHq RqHi RiHq   and   Hi^2 Hq^2
    // -----------------------------------------------------------------
    reg signed [DW+HW-1:0] s2_riHi, s2_rqHq, s2_rqHi, s2_riHq;
    reg        [2*HW-1:0]  s2_hi2,  s2_hq2;   // squares are non-negative
    always @(posedge clk) if (ce) begin
        s2_riHi <= s1_ri * s1_hi;
        s2_rqHq <= s1_rq * s1_hq;
        s2_rqHi <= s1_rq * s1_hi;
        s2_riHq <= s1_ri * s1_hq;
        s2_hi2  <= s1_hi * s1_hi;
        s2_hq2  <= s1_hq * s1_hq;
    end

    // -----------------------------------------------------------------
    // S3: sums -> num_i, num_q, sc(=|H|^2)
    // -----------------------------------------------------------------
    localparam integer NUMW = DW+HW+1;         // numerator width
    localparam integer SCW  = 2*HW+1;          // |H|^2 width
    reg signed [NUMW-1:0] s3_numi, s3_numq;
    reg        [SCW-1:0]  s3_sc;
    always @(posedge clk) if (ce) begin
        s3_numi <= s2_riHi + s2_rqHq;
        s3_numq <= s2_rqHi - s2_riHq;
        s3_sc   <= s2_hi2  + s2_hq2;
    end

    // -----------------------------------------------------------------
    // S4: normalize sc, LUT seed.
    //   find msb position n (1..SCW). sh = 31 - n. m = sc << sh  (or >> if
    //   sc has more than 31 significant bits). m lands in [2^30, 2^31).
    //   addr = top 8 bits of m (leading 1 included) -> LUT[addr-128].
    // -----------------------------------------------------------------
    // reciprocal seed ROM: 128 entries, value Q18 (max ~522248, 20-bit)
    reg [19:0] recip_lut [0:127];
    initial $readmemh(LUT_FILE, recip_lut);

    // leading-zero / bit-length detection over SCW bits
    function integer bitlen;
        input [SCW-1:0] x;
        integer k;
        begin
            bitlen = 0;
            for (k=0; k<SCW; k=k+1)
                if (x[k]) bitlen = k+1;
        end
    endfunction

    reg [31:0]            s4_m;      // normalized mantissa in [2^30,2^31)
    reg signed [7:0]      s4_sh;     // 31 - bitlen  (can be negative)
    reg [19:0]            s4_r0;     // Q18 seed
    reg                   s4_zero;   // sc == 0 guard
    reg signed [NUMW-1:0] s4_numi, s4_numq;

    reg [31:0] norm_m;
    integer    n_bits;
    reg signed [7:0] sh_v;
    reg [7:0]  addr8;
    always @(posedge clk) if (ce) begin
        s4_numi <= s3_numi;
        s4_numq <= s3_numq;
        s4_zero <= (s3_sc == {SCW{1'b0}});
        n_bits   = bitlen(s3_sc);
        sh_v     = 8'sd31 - n_bits[7:0];
        s4_sh   <= sh_v;
        // build normalized mantissa
        if (sh_v >= 0) norm_m = s3_sc << sh_v;
        else           norm_m = s3_sc >> (-sh_v);
        s4_m    <= norm_m;
        // norm_m is in [2^30, 2^31): its MSB is bit 30 (always 1). The
        // 8-bit LUT address is bits [30:23], so it spans [128,255]; the
        // ROM holds those 128 entries indexed by (addr-128).
        addr8    = norm_m[30:23];                  // top 8 bits, MSB(bit30)=1
        s4_r0   <= recip_lut[addr8 - 8'd128];
    end

    // -----------------------------------------------------------------
    // Newton-Raphson reciprocal, ONE MULTIPLY PER PIPELINE STAGE.
    // Each iteration  r <- r*(2 - x*r)  is split into:
    //   *a: mr = m * r            (single DSP multiply)
    //   *b: corr = two - (mr>>31);  r = r * corr >> PMANT   (single mult)
    // Two iterations -> 4 stages (S5a,S5b,S6a,S6b). This keeps the worst
    // path to a single DSP cascade and is what lifts Fmax above 300 MHz.
    // -----------------------------------------------------------------
    localparam [22:0] TWO_Q = (23'd1 << (PMANT+1));   // 2.0 in Q18

    // ---- S5a: mr = m * r0 ----
    reg [51:0]           s5a_mr;
    reg [19:0]           s5a_r0;
    reg [31:0]           s5a_m;
    reg signed [7:0]     s5a_sh;
    reg                  s5a_zero;
    reg signed [NUMW-1:0] s5a_numi, s5a_numq;
    always @(posedge clk) if (ce) begin
        s5a_mr   <= s4_m * s4_r0;       // 32b*20b
        s5a_r0   <= s4_r0;
        s5a_m    <= s4_m;
        s5a_sh   <= s4_sh; s5a_zero <= s4_zero;
        s5a_numi <= s4_numi; s5a_numq <= s4_numq;
    end

    // ---- S5b: corr = 2 - (mr>>31);  r1 = r0*corr >> P ----
    reg [20:0]           s5b_r;
    reg [31:0]           s5b_m;
    reg signed [7:0]     s5b_sh;
    reg                  s5b_zero;
    reg signed [NUMW-1:0] s5b_numi, s5b_numq;
    reg [19:0] xr5b; reg [20:0] corr5b; reg [40:0] prod5b;
    always @(posedge clk) if (ce) begin
        xr5b     = s5a_mr >> 31;                   // Q18
        corr5b   = TWO_Q[20:0] - {1'b0, xr5b};
        prod5b   = s5a_r0 * corr5b;               // 20b*21b
        s5b_r    <= prod5b >> PMANT;
        s5b_m    <= s5a_m;
        s5b_sh   <= s5a_sh; s5b_zero <= s5a_zero;
        s5b_numi <= s5a_numi; s5b_numq <= s5a_numq;
    end

    // ---- S6a: mr = m * r1 ----
    reg [52:0]           s6a_mr;
    reg [20:0]           s6a_r1;
    reg signed [7:0]     s6a_sh;
    reg                  s6a_zero;
    reg signed [NUMW-1:0] s6a_numi, s6a_numq;
    always @(posedge clk) if (ce) begin
        s6a_mr   <= s5b_m * s5b_r;       // 32b*21b
        s6a_r1   <= s5b_r;
        s6a_sh   <= s5b_sh; s6a_zero <= s5b_zero;
        s6a_numi <= s5b_numi; s6a_numq <= s5b_numq;
    end

    // ---- S6b: corr = 2 - (mr>>31);  r = r1*corr >> P  -> final reciprocal ----
    reg [21:0]           s6_r;
    reg signed [7:0]     s6_sh;
    reg                  s6_zero;
    reg signed [NUMW-1:0] s6_numi, s6_numq;
    reg [19:0] xr6b; reg [21:0] corr6b; reg [42:0] prod6b;
    always @(posedge clk) if (ce) begin
        xr6b     = s6a_mr >> 31;                   // Q18
        corr6b   = TWO_Q[21:0] - {2'b0, xr6b};
        prod6b   = s6a_r1 * corr6b;               // 21b*22b
        s6_r     <= prod6b >> PMANT;
        s6_sh    <= s6a_sh; s6_zero <= s6a_zero;
        s6_numi  <= s6a_numi; s6_numq <= s6a_numq;
    end

    // -----------------------------------------------------------------
    // S7: numerator * SFIX (the S-scale multiply), AND pre-align the
    //   reciprocal by the data-dependent normalize shift `sh`.
    //
    //   The denormalize factor of the reciprocal is 2^(sh-31). Doing this
    //   variable shift HERE on the narrow (22-bit) reciprocal -- instead
    //   of on the ~80-bit final product at the output -- is what keeps the
    //   final stage to a CONSTANT shift and lifts Fmax. The aligned
    //   reciprocal r_al = r << (sh + ALIGN) is at most RALW bits.
    //
    //   sh = 31 - bitlen(sc). For sc in [1, 2^SCW): bitlen in [1,SCW] ->
    //   sh in [31-SCW, 30]. We left-shift by (sh + SH_BIAS) keeping it
    //   non-negative, and remove the SH_BIAS as a constant at the output.
    // -----------------------------------------------------------------
    localparam integer NSW     = NUMW + 24;       // num*Sfix width
    // sh = 31 - bitlen(sc), bitlen in [1, SCW] -> sh in [31-SCW, 30].
    // SH_BIAS only needs to cancel the most-negative sh so the left-shift
    // amount stays non-negative; keep it minimal to bound the widths.
    localparam integer SH_MIN  = 31 - SCW;        // most negative sh
    localparam integer SH_BIAS = (SH_MIN < 0) ? -SH_MIN : 0;   // = SCW-31
    localparam integer SH_MAX  = 30 + SH_BIAS;    // max left-shift amount
    localparam integer RALW    = 22 + SH_MAX + 1; // aligned reciprocal width

    reg signed [NSW-1:0]  s7_nsi, s7_nsq;
    reg        [RALW-1:0] s7_ral;                 // r << (sh + SH_BIAS)
    reg                   s7_zero;
    reg [7:0] shamt7;
    always @(posedge clk) if (ce) begin
        s7_zero <= s6_zero;
        s7_nsi  <= s6_numi * $signed({1'b0, SFIX[22:0]});
        s7_nsq  <= s6_numq * $signed({1'b0, SFIX[22:0]});
        shamt7   = s6_sh + SH_BIAS;               // always >= 0
        s7_ral  <= {{(RALW-22){1'b0}}, s6_r} << shamt7;
    end

    // -----------------------------------------------------------------
    // S8: (num*SFIX) * r_aligned   -> big signed product. No shift here.
    // -----------------------------------------------------------------
    localparam integer FW = NSW + RALW;          // final product width
    reg signed [FW-1:0]   s8_pi, s8_pq;
    reg                   s8_zero;
    always @(posedge clk) if (ce) begin
        s8_zero <= s7_zero;
        s8_pi <= s7_nsi * $signed({1'b0, s7_ral});
        s8_pq <= s7_nsq * $signed({1'b0, s7_ral});
    end

    // -----------------------------------------------------------------
    // S9a: denormalize + round with a CONSTANT shift.
    //   Because the reciprocal was pre-aligned by 2^(sh+SH_BIAS) in S7,
    //   the remaining shift is fixed:
    //     FINAL_SH = (SSHIFT+PMANT+31-sh) + (sh+SH_BIAS) = 59 + SH_BIAS.
    //   A constant arithmetic shift is pure bit-select; rounding is one
    //   add of the half-LSB at the fixed split point. The clamp keeps the
    //   word at RW bits so S9b's saturation is trivial.
    // -----------------------------------------------------------------
    localparam integer BASE_SH  = SSHIFT + PMANT + 31; // 59
    localparam integer FINAL_SH = BASE_SH + SH_BIAS;   // constant total shift
    localparam integer RW       = OW + 4;              // rounded guard width

    // constant arithmetic round-shift-right, output kept to RW bits.
    //   round-half-up:  (v + 2^(FINAL_SH-1)) >>> FINAL_SH  (single signed
    //   add, no data-dependent negate branch). Differs from the golden's
    //   round-half-away-from-zero by at most 1 LSB on exact-half negatives,
    //   well inside the rounding budget (TB still 2 LSB). The shift is a
    //   CONSTANT (FINAL_SH) so it is free bit-select; the only logic is one
    //   add + the RW-range saturation compares.
    function signed [RW-1:0] crshift_round;
        input signed [FW-1:0] v;
        reg   signed [FW-1:0] r;
        begin
            r = (v + (1 <<< (FINAL_SH-1))) >>> FINAL_SH;
            if (r >  $signed({{(FW-RW){1'b0}},{1'b0,{(RW-1){1'b1}}}}))
                crshift_round = {1'b0,{(RW-1){1'b1}}};
            else if (r < $signed({{(FW-RW){1'b1}},{1'b1,{(RW-1){1'b0}}}}))
                crshift_round = {1'b1,{(RW-1){1'b0}}};
            else
                crshift_round = r[RW-1:0];
        end
    endfunction

    reg signed [RW-1:0] s9a_i, s9a_q;
    reg                 s9a_zero;
    always @(posedge clk) if (ce) begin
        s9a_zero <= s8_zero;
        s9a_i <= crshift_round(s8_pi);
        s9a_q <= crshift_round(s8_pq);
    end

    // -----------------------------------------------------------------
    // S9b: saturate RW -> OW and apply the |H|^2==0 guard.
    // -----------------------------------------------------------------
    reg signed [OW-1:0] s9_i, s9_q;
    function signed [OW-1:0] sat_ow;
        input signed [RW-1:0] v;
        begin
            if (v >  $signed({{(RW-OW){1'b0}},{1'b0,{(OW-1){1'b1}}}}))
                sat_ow = {1'b0,{(OW-1){1'b1}}};
            else if (v < $signed({{(RW-OW){1'b1}},{1'b1,{(OW-1){1'b0}}}}))
                sat_ow = {1'b1,{(OW-1){1'b0}}};
            else
                sat_ow = v[OW-1:0];
        end
    endfunction
    always @(posedge clk) if (ce) begin
        if (s9a_zero) begin
            s9_i <= {OW{1'b0}};
            s9_q <= {OW{1'b0}};
        end else begin
            s9_i <= sat_ow(s9a_i);
            s9_q <= sat_ow(s9a_q);
        end
    end

    assign eq_i = s9_i;
    assign eq_q = s9_q;

endmodule
`default_nettype wire
