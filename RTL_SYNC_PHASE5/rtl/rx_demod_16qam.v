// =====================================================================
// rx_demod_16qam.v
// ---------------------------------------------------------------------
// OFDM RX downstream chain: 16-QAM hard-decision demodulator.
//
// Ports decode_16qam() from ref/receiver.c. For every equalized data
// subcarrier (12 symbols x 221 data carriers, in dataIndx order) it
// hard-slices the complex sample into 4 bits {b0,b1,b2,b3}:
//   - b0,b1 from the I axis (real)
//   - b2,b3 from the Q axis (imag)
// via three threshold comparators d = {-2,0,+2}*SCALE_16QAM.
//
// ---------------------------------------------------------------------
// EXACT THRESHOLDS / BIT MAPPING (matches CONTRACT.md sec 3.4 / 4)
// ---------------------------------------------------------------------
//   SCALE_16QAM = 1/sqrt(10) = 0.316227766
//   Q15 scale   = 5090.697374  (RMS-matched to fc_kp0; CONTRACT sec 1)
//
//   d0 = -2*SCALE*Q15 = -3219.64  -> rounded integer threshold  -3220
//   d1 =  0
//   d2 = +2*SCALE*Q15 = +3219.64  -> rounded integer threshold  +3220
//
//   TX map16QAM = {-1,-3,+1,+3}*SCALE  (index = b*2+b1):
//       00 -> -1 , 01 -> -3 , 10 -> +1 , 11 -> +3   (per axis, xSCALE)
//   The demod (its exact inverse), per axis with input v (signed):
//       v < -TH :  (b_hi,b_lo) = (0,1)   // nearest -3  region
//       v <  0  :  (b_hi,b_lo) = (0,0)   // nearest -1  region
//       v < +TH :  (b_hi,b_lo) = (1,0)   // nearest +1  region
//       else    :  (b_hi,b_lo) = (1,1)   // nearest +3  region
//   I axis -> (b0,b1) ; Q axis -> (b2,b3). Output bit order [b0 b1 b2 b3]
//   per carrier; carriers in dataIndx order, symbols 0..11 consecutive.
//
// Verified in scripts/rx_downstream_ref.py terms: slicing the golden
// eq_out.hex with TH=3220 reproduces tx_bits.txt exactly -> BER = 0.
//
// ---------------------------------------------------------------------
// THROUGHPUT / TIMING
// ---------------------------------------------------------------------
//   * 1 complex sample / clock, AXI-Stream, honors tready (no internal
//     buffering, no rate change -> sampling rate preserved).
//   * Comparator-only (no multiplies). The 4 decision bits AND the
//     passed-through control (tlast/tuser) are REGISTERED before the
//     master interface -> single pipeline stage, high Fmax.
//   * Backpressure: the pipeline register is only advanced when the
//     downstream can accept (m_ready) or the stage is empty, so a
//     stalled m_axis correctly back-pressures s_axis (skid-free,
//     standard single-stage valid/ready handshake).
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_demod_16qam #(
    parameter integer DATA_W   = 16,    // signed I/Q sample width (Q15)
    // Integer decision threshold |d| = round(2*SCALE_16QAM*Q15_SCALE).
    // SCALE_16QAM=1/sqrt(10)=0.316227766, Q15_SCALE=5090.697374
    //   -> 2*0.316227766*5090.697374 = 3219.64 -> 3220
    parameter integer THRESH   = 3220
) (
    input  wire                       clk,
    input  wire                       rst_n,      // active-low sync reset

    // ---- slave : equalized data subcarriers, one complex sample/beat ----
    input  wire                       s_valid,
    output wire                       s_ready,
    input  wire signed [DATA_W-1:0]   s_i,        // real  (Q15)
    input  wire signed [DATA_W-1:0]   s_q,        // imag  (Q15)
    input  wire                       s_last,     // pass-through (e.g. symbol end)
    input  wire                       s_user,     // pass-through (spare / SOF)

    // ---- master : 4 demodulated bits/beat ------------------------------
    output wire                       m_valid,
    input  wire                       m_ready,
    output wire [3:0]                 m_bits,     // {b0,b1,b2,b3}
    output wire                       m_last,
    output wire                       m_user
);

    // Signed threshold constants
    localparam signed [DATA_W:0] POS_TH = THRESH;      // +TH
    localparam signed [DATA_W:0] NEG_TH = -THRESH;     // -TH

    // -----------------------------------------------------------------
    // Combinational hard-slice of one axis -> 2 bits {b_hi, b_lo}
    //   v < -TH : 01 ; v < 0 : 00 ; v < +TH : 10 ; else : 11
    // (use a sign-extended compare so the full int16 range is covered)
    // -----------------------------------------------------------------
    function [1:0] slice_axis;
        input signed [DATA_W-1:0] v;
        reg signed [DATA_W:0] ve;
        begin
            ve = {v[DATA_W-1], v};       // sign-extend by 1 bit
            if (ve <= NEG_TH)       slice_axis = 2'b01;   // -> -3 region (C: v < -2*SCALE => v_int <= -THRESH)
            else if (ve < 0)        slice_axis = 2'b00;   // -> -1 region
            else if (ve < POS_TH)   slice_axis = 2'b10;   // -> +1 region
            else                    slice_axis = 2'b11;   // -> +3 region
        end
    endfunction

    wire [1:0] iq_bits_i = slice_axis(s_i);   // {b0,b1}
    wire [1:0] iq_bits_q = slice_axis(s_q);   // {b2,b3}
    wire [3:0] bits_comb = {iq_bits_i, iq_bits_q};  // [b0 b1 b2 b3]

    // -----------------------------------------------------------------
    // Single registered output stage with standard valid/ready handshake.
    // The stage can accept a new beat when it is empty OR being drained.
    // -----------------------------------------------------------------
    reg        v_q;
    reg [3:0]  bits_q;
    reg        last_q;
    reg        user_q;

    wire stage_ready = ~v_q | m_ready;   // can load when empty or draining

    assign s_ready = stage_ready;
    assign m_valid = v_q;
    assign m_bits  = bits_q;
    assign m_last  = last_q;
    assign m_user  = user_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            v_q    <= 1'b0;
            bits_q <= 4'b0;
            last_q <= 1'b0;
            user_q <= 1'b0;
        end else begin
            if (stage_ready) begin
                v_q    <= s_valid;
                bits_q <= bits_comb;
                last_q <= s_last;
                user_q <= s_user;
            end
            // else: hold (downstream stalled while stage occupied)
        end
    end

endmodule

`default_nettype wire
