// =====================================================================
// rx_demod_qam.v
// ---------------------------------------------------------------------
// OFDM RX downstream chain: runtime-selectable QAM hard-decision
// demodulator (QPSK / 16-QAM / 64-QAM / 256-QAM).  Generalizes the old
// rx_demod_16qam.v threshold slicer to 2^(k) levels per axis.
//
// MULTI-MODULATION (mod_sel[1:0]):
//     0 = QPSK   (1 bit/axis,  2 levels/axis)
//     1 = 16-QAM (2 bits/axis, 4 levels/axis)   <- bit-exact to old core
//     2 = 64-QAM (3 bits/axis, 8 levels/axis)
//     3 = 256QAM (4 bits/axis,16 levels/axis)
//   K = bits/axis = mod_sel+1 ; nlev = 2^K levels/axis.
//
// Per axis (input v, signed Q15):
//     sign = (v >= 0)                  -> axis MSB
//     m    = min( |v| / STEP_mod , nlev/2-1 )   (magnitude rank)
//     axis bits = { sign , gray(m) }   (folded-Gray; exact inverse of
//                  tx_subcarrier_map qam_axis).
//   STEP_mod = round(2*SCALE_mod*Q15) = level spacing in Q15:
//     QPSK 7199 , 16QAM 3220 , 64QAM 1571 , 256QAM 781.
//   |v|/STEP is done with a small unrolled comparator ladder (no divide).
//
// 16-QAM (mod_sel=1) reproduces the old rx_demod_16qam EXACTLY:
//   per axis v<=-TH:01 v<0:00 v<+TH:10 else:11  (TH=STEP=3220), and
//   m_bits[3:0] = {I_axis(b0,b1), Q_axis(b2,b3)}.
//
// Output bit packing m_bits[BPC_MAX-1:0] (BPC_MAX=8):
//   m_bits[K-1:0]   = I axis bits  (m_bits[K-1] = MSB = sign)
//   m_bits[2K-1:K]  = Q axis bits  (m_bits[2K-1] = MSB = sign)
//   high unused bits = 0. Active bit count BITS_PER_SYM = 2*K.
//   (For 16-QAM: m_bits[3:0] = [b0 b1 b2 b3] identical to old port.)
//
// THROUGHPUT/TIMING: identical single registered stage / valid-ready
// handshake / back-pressure as the old core (comparator-only, no mult).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_demod_qam #(
    parameter integer DATA_W  = 16,    // signed I/Q sample width (Q15)
    parameter integer BPC_MAX = 8      // max bits/carrier (256-QAM)
) (
    input  wire                       clk,
    input  wire                       rst_n,      // active-low sync reset

    input  wire [1:0]                 mod_sel,    // 0..3

    // ---- slave : equalized data subcarriers, one complex sample/beat ----
    input  wire                       s_valid,
    output wire                       s_ready,
    input  wire signed [DATA_W-1:0]   s_i,        // real  (Q15)
    input  wire signed [DATA_W-1:0]   s_q,        // imag  (Q15)
    input  wire                       s_last,     // pass-through
    input  wire                       s_user,     // pass-through

    // ---- master : up to BPC_MAX demodulated bits/beat ------------------
    output wire                       m_valid,
    input  wire                       m_ready,
    output wire [BPC_MAX-1:0]         m_bits,     // {Q axis, I axis}
    output wire                       m_last,
    output wire                       m_user
);
    // -----------------------------------------------------------------
    // Per-mod level spacing STEP (= 2*SCALE_mod*Q15, rounded).
    //   The magnitude rank m = number of STEP-multiples below |v|,
    //   clamped to nlev/2-1.  Boundaries between adjacent levels (odd
    //   multiples of SCALE*Q15) sit at even multiples = m*STEP.
    // -----------------------------------------------------------------
    function [12:0] step_of;
        input [1:0] ms;
        begin
            case (ms)
                2'd0: step_of = 13'd7199;  // QPSK
                2'd1: step_of = 13'd3220;  // 16-QAM
                2'd2: step_of = 13'd1571;  // 64-QAM
                default: step_of = 13'd781; // 256-QAM
            endcase
        end
    endfunction

    function [2:0] nlev_half_m1;   // (nlev/2 - 1) = max m
        input [1:0] ms;
        begin
            case (ms)
                2'd0: nlev_half_m1 = 3'd0;  // QPSK  : 1 magnitude
                2'd1: nlev_half_m1 = 3'd1;  // 16QAM : 2
                2'd2: nlev_half_m1 = 3'd3;  // 64QAM : 4
                default: nlev_half_m1 = 3'd7; // 256QAM: 8
            endcase
        end
    endfunction

    // binary -> Gray
    function [2:0] gray3;
        input [2:0] b;
        begin
            gray3 = b ^ {1'b0, b[2:1]};
        end
    endfunction

    // slice one axis -> K-bit folded-Gray code in low bits (sign at bit K-1)
    function [BPC_MAX/2-1:0] slice_axis;
        input [1:0]              ms;
        input signed [DATA_W-1:0] v;
        reg                      sign_pos;
        reg signed [DATA_W:0]    vs;      // sign-extended v
        reg [DATA_W:0]           av;      // |v| (one extra bit, magnitude)
        reg [12:0]               step;
        reg [2:0]                mmax;
        reg [2:0]                m;
        reg [DATA_W+3:0]         acc;     // running multiple of step
        integer                  i;
        reg [2:0]                kbits;
        begin
            sign_pos = (v >= 0);
            vs   = {v[DATA_W-1], v};            // sign-extend to DATA_W+1
            av   = sign_pos ? vs[DATA_W:0] : (-vs);  // magnitude (signed negate)
            step = step_of(ms);
            mmax = nlev_half_m1(ms);
            // count how many full STEPs fit in |v|, clamp to mmax.
            m   = 3'd0;
            acc = step;                       // boundary for m>=1
            for (i = 1; i <= 7; i = i + 1) begin
                if ((i <= mmax) && (av >= acc)) m = i[2:0];
                acc = acc + step;
            end
            kbits = gray3(m);
            // assemble the K-bit axis code MSB-FIRST (right-aligned in the
            // K-bit field): bit (K-1) = sign, then gray(m) MSB..LSB down to
            // bit 0.  gray3(m) yields a (K-1)-bit code; gray MSB is kbits[K-2].
            case (ms)
                2'd0: slice_axis = { {(BPC_MAX/2-1){1'b0}}, sign_pos };                       // K=1: [0]=sign
                2'd1: slice_axis = { {(BPC_MAX/2-2){1'b0}}, sign_pos, kbits[0] };             // K=2: [1]=sign [0]=g
                2'd2: slice_axis = { {(BPC_MAX/2-3){1'b0}}, sign_pos, kbits[1], kbits[0] };   // K=3: [2]=sign [1:0]=g(MSB..LSB)
                default: slice_axis = { sign_pos, kbits[2], kbits[1], kbits[0] };             // K=4: [3]=sign [2:0]=g
            endcase
        end
    endfunction

    wire [BPC_MAX/2-1:0] axb_i = slice_axis(mod_sel, s_i);
    wire [BPC_MAX/2-1:0] axb_q = slice_axis(mod_sel, s_q);

    // pack m_bits MSB-FIRST across the symbol (legacy 16-QAM contract):
    //   I axis = high K bits, Q axis = low K bits, sign = axis MSB.
    //   For 16-QAM: m_bits[3:0] = {I_sign,I_g, Q_sign,Q_g} = [b0 b1 b2 b3].
    reg [BPC_MAX-1:0] bits_comb;
    always @(*) begin
        case (mod_sel)
            2'd0: bits_comb = { {(BPC_MAX-2){1'b0}}, axb_i[0],   axb_q[0]   };  // K=1
            2'd1: bits_comb = { {(BPC_MAX-4){1'b0}}, axb_i[1:0], axb_q[1:0] };  // K=2
            2'd2: bits_comb = { {(BPC_MAX-6){1'b0}}, axb_i[2:0], axb_q[2:0] };  // K=3
            default: bits_comb = { axb_i[3:0], axb_q[3:0] };                    // K=4
        endcase
    end

    // -----------------------------------------------------------------
    // Single registered output stage (same handshake as old core).
    // -----------------------------------------------------------------
    reg                v_q;
    reg [BPC_MAX-1:0]  bits_q;
    reg                last_q;
    reg                user_q;

    wire stage_ready = ~v_q | m_ready;

    assign s_ready = stage_ready;
    assign m_valid = v_q;
    assign m_bits  = bits_q;
    assign m_last  = last_q;
    assign m_user  = user_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            v_q    <= 1'b0;
            bits_q <= {BPC_MAX{1'b0}};
            last_q <= 1'b0;
            user_q <= 1'b0;
        end else begin
            if (stage_ready) begin
                v_q    <= s_valid;
                bits_q <= bits_comb;
                last_q <= s_last;
                user_q <= s_user;
            end
        end
    end

endmodule

`default_nettype wire
