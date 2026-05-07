`timescale 1ns/1ps

// cordic_atan2 — synthesizable 15-stage CORDIC vectoring pipeline.
// Computes atan2(Q, I) → PHASE_WIDTH-bit signed phase.
// Convention: 0x7FFF = +pi, 0x0000 = 0, 0xC000 = -pi/2.
// Latency: LATENCY clock cycles from input tvalid to output tvalid.
// Quadrant preprocessing: handles full ±pi range.
// Internal arithmetic: 35-bit signed x/y, 18-bit signed z.

module cordic_atan2 #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer PHASE_WIDTH = 16,
    parameter integer LATENCY     = 15
) (
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);

    // Fully pipelined: always accepts new input
    assign s_axis_cartesian_tready = 1'b1;

    // --- Input decomposition ---
    wire signed [INPUT_WIDTH-1:0] cart_I =
        s_axis_cartesian_tdata[INPUT_WIDTH-1:0];
    wire signed [INPUT_WIDTH-1:0] cart_Q =
        s_axis_cartesian_tdata[2*INPUT_WIDTH-1:INPUT_WIDTH];

    // --- CORDIC ATAN table (atan(2^-k) / pi * 32767, k=0..14) ---
    localparam signed [17:0] ATAN00 = 18'sd8192;
    localparam signed [17:0] ATAN01 = 18'sd4836;
    localparam signed [17:0] ATAN02 = 18'sd2555;
    localparam signed [17:0] ATAN03 = 18'sd1297;
    localparam signed [17:0] ATAN04 = 18'sd651;
    localparam signed [17:0] ATAN05 = 18'sd326;
    localparam signed [17:0] ATAN06 = 18'sd163;
    localparam signed [17:0] ATAN07 = 18'sd81;
    localparam signed [17:0] ATAN08 = 18'sd41;
    localparam signed [17:0] ATAN09 = 18'sd20;
    localparam signed [17:0] ATAN10 = 18'sd10;
    localparam signed [17:0] ATAN11 = 18'sd5;
    localparam signed [17:0] ATAN12 = 18'sd3;
    localparam signed [17:0] ATAN13 = 18'sd1;
    localparam signed [17:0] ATAN14 = 18'sd1;

    // --- Quadrant preprocessing (combinatorial) ---
    wire neg_I   = cart_I[INPUT_WIDTH-1];
    wire neg_Q   = cart_Q[INPUT_WIDTH-1];
    wire zero_I  = (cart_I == {INPUT_WIDTH{1'b0}});
    wire preproc = neg_I || (zero_I && neg_Q);

    wire signed [34:0] I_ext = {{(35-INPUT_WIDTH){cart_I[INPUT_WIDTH-1]}}, cart_I};
    wire signed [34:0] Q_ext = {{(35-INPUT_WIDTH){cart_Q[INPUT_WIDTH-1]}}, cart_Q};

    wire signed [34:0] x_pre = preproc ? (-I_ext) : I_ext;
    wire signed [34:0] y_pre = preproc ? (-Q_ext) : Q_ext;
    wire signed [17:0] z_pre = preproc ?
        (neg_Q ? -18'sd32767 : 18'sd32767) : 18'sd0;

    // --- Pipeline registers ---
    reg signed [34:0] xr [0:LATENCY-1];
    reg signed [34:0] yr [0:LATENCY-1];
    reg signed [17:0] zr [0:LATENCY-1];
    reg               vr [0:LATENCY-1];

    // --- Stage 0 combinatorial (iteration 0, shift by 0) ---
    wire d0 = ~y_pre[34];
    wire signed [34:0] x1_c = x_pre + (d0 ? y_pre     : -y_pre);
    wire signed [34:0] y1_c = y_pre - (d0 ? x_pre     : -x_pre);
    wire signed [17:0] z1_c = z_pre - (d0 ? -ATAN00   : ATAN00);

    // --- Stage 1..14 combinatorial decisions (outside always block) ---
    wire d1  = ~yr[0][34];
    wire d2  = ~yr[1][34];
    wire d3  = ~yr[2][34];
    wire d4  = ~yr[3][34];
    wire d5  = ~yr[4][34];
    wire d6  = ~yr[5][34];
    wire d7  = ~yr[6][34];
    wire d8  = ~yr[7][34];
    wire d9  = ~yr[8][34];
    wire d10 = ~yr[9][34];
    wire d11 = ~yr[10][34];
    wire d12 = ~yr[11][34];
    wire d13 = ~yr[12][34];
    wire d14 = ~yr[13][34];

    integer k;
    always @(posedge aclk) begin
        if (!aresetn) begin
            for (k = 0; k < LATENCY; k = k + 1) begin
                xr[k] <= 35'sd0; yr[k] <= 35'sd0;
                zr[k] <= 18'sd0; vr[k] <= 1'b0;
            end
            m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
            m_axis_dout_tvalid <= 1'b0;
        end else begin
            // Stage 0: load preprocessed input after iteration 0
            xr[0] <= x1_c;
            yr[0] <= y1_c;
            zr[0] <= z1_c;
            vr[0] <= s_axis_cartesian_tvalid;

            // Stage 1: iteration 1, shift by 1
            xr[1] <= xr[0] + (d1 ? (yr[0]  >>> 1) : -(yr[0]  >>> 1));
            yr[1] <= yr[0] - (d1 ? (xr[0]  >>> 1) : -(xr[0]  >>> 1));
            zr[1] <= zr[0] - (d1 ? -ATAN01 : ATAN01);
            vr[1] <= vr[0];

            // Stage 2: iteration 2, shift by 2
            xr[2] <= xr[1] + (d2 ? (yr[1]  >>> 2) : -(yr[1]  >>> 2));
            yr[2] <= yr[1] - (d2 ? (xr[1]  >>> 2) : -(xr[1]  >>> 2));
            zr[2] <= zr[1] - (d2 ? -ATAN02 : ATAN02);
            vr[2] <= vr[1];

            // Stage 3: iteration 3, shift by 3
            xr[3] <= xr[2] + (d3 ? (yr[2]  >>> 3) : -(yr[2]  >>> 3));
            yr[3] <= yr[2] - (d3 ? (xr[2]  >>> 3) : -(xr[2]  >>> 3));
            zr[3] <= zr[2] - (d3 ? -ATAN03 : ATAN03);
            vr[3] <= vr[2];

            // Stage 4: iteration 4, shift by 4
            xr[4] <= xr[3] + (d4 ? (yr[3]  >>> 4) : -(yr[3]  >>> 4));
            yr[4] <= yr[3] - (d4 ? (xr[3]  >>> 4) : -(xr[3]  >>> 4));
            zr[4] <= zr[3] - (d4 ? -ATAN04 : ATAN04);
            vr[4] <= vr[3];

            // Stage 5: iteration 5, shift by 5
            xr[5] <= xr[4] + (d5 ? (yr[4]  >>> 5) : -(yr[4]  >>> 5));
            yr[5] <= yr[4] - (d5 ? (xr[4]  >>> 5) : -(xr[4]  >>> 5));
            zr[5] <= zr[4] - (d5 ? -ATAN05 : ATAN05);
            vr[5] <= vr[4];

            // Stage 6: iteration 6, shift by 6
            xr[6] <= xr[5] + (d6 ? (yr[5]  >>> 6) : -(yr[5]  >>> 6));
            yr[6] <= yr[5] - (d6 ? (xr[5]  >>> 6) : -(xr[5]  >>> 6));
            zr[6] <= zr[5] - (d6 ? -ATAN06 : ATAN06);
            vr[6] <= vr[5];

            // Stage 7: iteration 7, shift by 7
            xr[7] <= xr[6] + (d7 ? (yr[6]  >>> 7) : -(yr[6]  >>> 7));
            yr[7] <= yr[6] - (d7 ? (xr[6]  >>> 7) : -(xr[6]  >>> 7));
            zr[7] <= zr[6] - (d7 ? -ATAN07 : ATAN07);
            vr[7] <= vr[6];

            // Stage 8: iteration 8, shift by 8
            xr[8] <= xr[7] + (d8 ? (yr[7]  >>> 8) : -(yr[7]  >>> 8));
            yr[8] <= yr[7] - (d8 ? (xr[7]  >>> 8) : -(xr[7]  >>> 8));
            zr[8] <= zr[7] - (d8 ? -ATAN08 : ATAN08);
            vr[8] <= vr[7];

            // Stage 9: iteration 9, shift by 9
            xr[9] <= xr[8] + (d9 ? (yr[8]  >>> 9) : -(yr[8]  >>> 9));
            yr[9] <= yr[8] - (d9 ? (xr[8]  >>> 9) : -(xr[8]  >>> 9));
            zr[9] <= zr[8] - (d9 ? -ATAN09 : ATAN09);
            vr[9] <= vr[8];

            // Stage 10: iteration 10, shift by 10
            xr[10] <= xr[9]  + (d10 ? (yr[9]  >>> 10) : -(yr[9]  >>> 10));
            yr[10] <= yr[9]  - (d10 ? (xr[9]  >>> 10) : -(xr[9]  >>> 10));
            zr[10] <= zr[9]  - (d10 ? -ATAN10 : ATAN10);
            vr[10] <= vr[9];

            // Stage 11: iteration 11, shift by 11
            xr[11] <= xr[10] + (d11 ? (yr[10] >>> 11) : -(yr[10] >>> 11));
            yr[11] <= yr[10] - (d11 ? (xr[10] >>> 11) : -(xr[10] >>> 11));
            zr[11] <= zr[10] - (d11 ? -ATAN11 : ATAN11);
            vr[11] <= vr[10];

            // Stage 12: iteration 12, shift by 12
            xr[12] <= xr[11] + (d12 ? (yr[11] >>> 12) : -(yr[11] >>> 12));
            yr[12] <= yr[11] - (d12 ? (xr[11] >>> 12) : -(xr[11] >>> 12));
            zr[12] <= zr[11] - (d12 ? -ATAN12 : ATAN12);
            vr[12] <= vr[11];

            // Stage 13: iteration 13, shift by 13
            xr[13] <= xr[12] + (d13 ? (yr[12] >>> 13) : -(yr[12] >>> 13));
            yr[13] <= yr[12] - (d13 ? (xr[12] >>> 13) : -(xr[12] >>> 13));
            zr[13] <= zr[12] - (d13 ? -ATAN13 : ATAN13);
            vr[13] <= vr[12];

            // Stage 14: iteration 14, shift by 14
            xr[14] <= xr[13] + (d14 ? (yr[13] >>> 14) : -(yr[13] >>> 14));
            yr[14] <= yr[13] - (d14 ? (xr[13] >>> 14) : -(xr[13] >>> 14));
            zr[14] <= zr[13] - (d14 ? -ATAN14 : ATAN14);
            vr[14] <= vr[13];

            // Output: z after 15 iterations
            m_axis_dout_tdata  <= zr[14][PHASE_WIDTH-1:0];
            m_axis_dout_tvalid <= vr[14];
        end
    end

endmodule
