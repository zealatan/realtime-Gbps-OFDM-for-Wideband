`timescale 1ns/1ps

// nco_phase_gen_xilinx_wrapper — IP-ready shell for NCO sin/cos replacement.
//
// Interface is pin-compatible with nco_phase_gen (the existing 256-entry ROM module).
// USE_BEHAVIORAL_MODEL=1: uses an identical 256-entry Q1.15 ROM for simulation and
//   as an intermediate synthesizable path.  This is NOT the production target; it is
//   a validated placeholder that proves the interface and timing before real IP arrives.
// USE_BEHAVIORAL_MODEL=0: exposes the phase accumulator and a clearly-marked stub for
//   future Xilinx CORDIC rotate-mode IP instantiation.
//
// Production synthesis target:
//   Replace this wrapper's sin/cos path with cordic_v6_0 in Translate (rotate) mode:
//     - S_AXIS_PHASE.TDATA = {cordic_phase_in}  (16-bit signed Q1.15 = top 16 bits of acc)
//     - S_AXIS_PHASE.TVALID = enable && !phase_reset
//     - M_AXIS_DOUT.TDATA   = {sin[15:0], cos[15:0]} (after standard CORDIC scale correction)
//     - M_AXIS_DOUT.TVALID  = sincos_valid_r
//
// Phase convention (same as nco_phase_gen.v):
//   - 32-bit unsigned accumulator.  Full 2*pi cycle spans 2^32 counts.
//   - Top 8 bits (acc[31:24]) select one of 256 ROM entries.
//   - phase_acc is pre-accumulation: output at cycle T reflects the phase BEFORE
//     accumulation for that cycle.
//   - Natural 32-bit wrap is equivalent to a 2*pi phase wrap.
//
// Sin/cos output (Q1.15 unsigned-stored, signed interpretation):
//   0x7FFF (+32767) ≈ +1.0      Phase 0:   cos=+32767, sin=0
//   0x0000 (0)                  Phase 90°: cos=0,       sin=+32767
//   0x8001 (-32767) ≈ -1.0      Phase 180°:cos=-32767,  sin=0
//   0x0000 (0)                  Phase 270°:cos=0,        sin=-32767
//
// Latency: LATENCY clock cycles from enable to sincos_valid/sin_out/cos_out.
//   valid_pipe[0] <= enable && !phase_reset  (stage 0)
//   valid_pipe[k] <= valid_pipe[k-1]         (stages 1..LATENCY-1)
//   sincos_valid_r <= valid_pipe[LATENCY-1]  (output register)
//   Total = LATENCY posedge edges.

module nco_phase_gen_xilinx_wrapper #(
    parameter integer NCO_PHASE_WIDTH      = 32,
    parameter integer CORDIC_PHASE_WIDTH   = 16,
    parameter integer ROTATOR_COEFF_WIDTH  = 16,
    parameter integer LATENCY              = 15,
    parameter integer USE_BEHAVIORAL_MODEL = 1
) (
    input  wire                                      aclk,
    input  wire                                      aresetn,
    input  wire                                      load_step,
    input  wire signed [NCO_PHASE_WIDTH-1:0]         step_word,
    input  wire                                      phase_reset,
    input  wire                                      enable,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     sin_out,
    output wire signed [ROTATOR_COEFF_WIDTH-1:0]     cos_out,
    output wire                                      sincos_valid,
    output wire        [NCO_PHASE_WIDTH-1:0]         phase_acc
);

    // -------------------------------------------------------------------------
    // Phase accumulator (shared by both paths)
    // -------------------------------------------------------------------------
    reg [NCO_PHASE_WIDTH-1:0] step_word_r;
    reg [NCO_PHASE_WIDTH-1:0] phase_acc_r;

    assign phase_acc = phase_acc_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            step_word_r <= {NCO_PHASE_WIDTH{1'b0}};
            phase_acc_r <= {NCO_PHASE_WIDTH{1'b0}};
        end else begin
            if (load_step)
                step_word_r <= step_word;
            if (phase_reset)
                phase_acc_r <= {NCO_PHASE_WIDTH{1'b0}};
            else if (enable)
                phase_acc_r <= phase_acc_r + step_word_r;
        end
    end

    // -------------------------------------------------------------------------
    // Output signals driven by the selected implementation
    // -------------------------------------------------------------------------
    reg signed [ROTATOR_COEFF_WIDTH-1:0] sin_out_r;
    reg signed [ROTATOR_COEFF_WIDTH-1:0] cos_out_r;
    reg                                  sincos_valid_r;

    assign sin_out      = sin_out_r;
    assign cos_out      = cos_out_r;
    assign sincos_valid = sincos_valid_r;

    // -------------------------------------------------------------------------
    // Path A: behavioral / ROM model  (USE_BEHAVIORAL_MODEL = 1)
    // -------------------------------------------------------------------------
    generate
    if (USE_BEHAVIORAL_MODEL == 1) begin : gen_behavioral

        // This branch is for simulation and IP interface preparation only.
        // Production synthesis must replace this behavioral ROM path with
        // Xilinx CORDIC rotate-mode IP or DDS Compiler IP.
        //
        // The 256-entry ROM is technically synthesizable as LUTRAM in Vivado,
        // but it is not the intended production implementation.

        // synthesis translate_off
        // (no non-synthesizable constructs here; comment marks behavioral intent)
        // synthesis translate_on

        reg [ROTATOR_COEFF_WIDTH-1:0] SIN_ROM [0:255];
        reg [ROTATOR_COEFF_WIDTH-1:0] COS_ROM [0:255];

        initial begin
            COS_ROM[  0] = 16'h7FFF; SIN_ROM[  0] = 16'h0000;
            COS_ROM[  1] = 16'h7FF5; SIN_ROM[  1] = 16'h0324;
            COS_ROM[  2] = 16'h7FD8; SIN_ROM[  2] = 16'h0648;
            COS_ROM[  3] = 16'h7FA6; SIN_ROM[  3] = 16'h096A;
            COS_ROM[  4] = 16'h7F61; SIN_ROM[  4] = 16'h0C8C;
            COS_ROM[  5] = 16'h7F09; SIN_ROM[  5] = 16'h0FAB;
            COS_ROM[  6] = 16'h7E9C; SIN_ROM[  6] = 16'h12C8;
            COS_ROM[  7] = 16'h7E1D; SIN_ROM[  7] = 16'h15E2;
            COS_ROM[  8] = 16'h7D89; SIN_ROM[  8] = 16'h18F9;
            COS_ROM[  9] = 16'h7CE3; SIN_ROM[  9] = 16'h1C0B;
            COS_ROM[ 10] = 16'h7C29; SIN_ROM[ 10] = 16'h1F1A;
            COS_ROM[ 11] = 16'h7B5C; SIN_ROM[ 11] = 16'h2223;
            COS_ROM[ 12] = 16'h7A7C; SIN_ROM[ 12] = 16'h2528;
            COS_ROM[ 13] = 16'h7989; SIN_ROM[ 13] = 16'h2826;
            COS_ROM[ 14] = 16'h7884; SIN_ROM[ 14] = 16'h2B1F;
            COS_ROM[ 15] = 16'h776B; SIN_ROM[ 15] = 16'h2E11;
            COS_ROM[ 16] = 16'h7641; SIN_ROM[ 16] = 16'h30FB;
            COS_ROM[ 17] = 16'h7504; SIN_ROM[ 17] = 16'h33DF;
            COS_ROM[ 18] = 16'h73B5; SIN_ROM[ 18] = 16'h36BA;
            COS_ROM[ 19] = 16'h7254; SIN_ROM[ 19] = 16'h398C;
            COS_ROM[ 20] = 16'h70E2; SIN_ROM[ 20] = 16'h3C56;
            COS_ROM[ 21] = 16'h6F5E; SIN_ROM[ 21] = 16'h3F17;
            COS_ROM[ 22] = 16'h6DC9; SIN_ROM[ 22] = 16'h41CE;
            COS_ROM[ 23] = 16'h6C23; SIN_ROM[ 23] = 16'h447A;
            COS_ROM[ 24] = 16'h6A6D; SIN_ROM[ 24] = 16'h471C;
            COS_ROM[ 25] = 16'h68A6; SIN_ROM[ 25] = 16'h49B4;
            COS_ROM[ 26] = 16'h66CF; SIN_ROM[ 26] = 16'h4C3F;
            COS_ROM[ 27] = 16'h64E8; SIN_ROM[ 27] = 16'h4EBF;
            COS_ROM[ 28] = 16'h62F1; SIN_ROM[ 28] = 16'h5133;
            COS_ROM[ 29] = 16'h60EB; SIN_ROM[ 29] = 16'h539B;
            COS_ROM[ 30] = 16'h5ED7; SIN_ROM[ 30] = 16'h55F5;
            COS_ROM[ 31] = 16'h5CB3; SIN_ROM[ 31] = 16'h5842;
            COS_ROM[ 32] = 16'h5A82; SIN_ROM[ 32] = 16'h5A82;
            COS_ROM[ 33] = 16'h5842; SIN_ROM[ 33] = 16'h5CB3;
            COS_ROM[ 34] = 16'h55F5; SIN_ROM[ 34] = 16'h5ED7;
            COS_ROM[ 35] = 16'h539B; SIN_ROM[ 35] = 16'h60EB;
            COS_ROM[ 36] = 16'h5133; SIN_ROM[ 36] = 16'h62F1;
            COS_ROM[ 37] = 16'h4EBF; SIN_ROM[ 37] = 16'h64E8;
            COS_ROM[ 38] = 16'h4C3F; SIN_ROM[ 38] = 16'h66CF;
            COS_ROM[ 39] = 16'h49B4; SIN_ROM[ 39] = 16'h68A6;
            COS_ROM[ 40] = 16'h471C; SIN_ROM[ 40] = 16'h6A6D;
            COS_ROM[ 41] = 16'h447A; SIN_ROM[ 41] = 16'h6C23;
            COS_ROM[ 42] = 16'h41CE; SIN_ROM[ 42] = 16'h6DC9;
            COS_ROM[ 43] = 16'h3F17; SIN_ROM[ 43] = 16'h6F5E;
            COS_ROM[ 44] = 16'h3C56; SIN_ROM[ 44] = 16'h70E2;
            COS_ROM[ 45] = 16'h398C; SIN_ROM[ 45] = 16'h7254;
            COS_ROM[ 46] = 16'h36BA; SIN_ROM[ 46] = 16'h73B5;
            COS_ROM[ 47] = 16'h33DF; SIN_ROM[ 47] = 16'h7504;
            COS_ROM[ 48] = 16'h30FB; SIN_ROM[ 48] = 16'h7641;
            COS_ROM[ 49] = 16'h2E11; SIN_ROM[ 49] = 16'h776B;
            COS_ROM[ 50] = 16'h2B1F; SIN_ROM[ 50] = 16'h7884;
            COS_ROM[ 51] = 16'h2826; SIN_ROM[ 51] = 16'h7989;
            COS_ROM[ 52] = 16'h2528; SIN_ROM[ 52] = 16'h7A7C;
            COS_ROM[ 53] = 16'h2223; SIN_ROM[ 53] = 16'h7B5C;
            COS_ROM[ 54] = 16'h1F1A; SIN_ROM[ 54] = 16'h7C29;
            COS_ROM[ 55] = 16'h1C0B; SIN_ROM[ 55] = 16'h7CE3;
            COS_ROM[ 56] = 16'h18F9; SIN_ROM[ 56] = 16'h7D89;
            COS_ROM[ 57] = 16'h15E2; SIN_ROM[ 57] = 16'h7E1D;
            COS_ROM[ 58] = 16'h12C8; SIN_ROM[ 58] = 16'h7E9C;
            COS_ROM[ 59] = 16'h0FAB; SIN_ROM[ 59] = 16'h7F09;
            COS_ROM[ 60] = 16'h0C8C; SIN_ROM[ 60] = 16'h7F61;
            COS_ROM[ 61] = 16'h096A; SIN_ROM[ 61] = 16'h7FA6;
            COS_ROM[ 62] = 16'h0648; SIN_ROM[ 62] = 16'h7FD8;
            COS_ROM[ 63] = 16'h0324; SIN_ROM[ 63] = 16'h7FF5;
            COS_ROM[ 64] = 16'h0000; SIN_ROM[ 64] = 16'h7FFF;
            COS_ROM[ 65] = 16'hFCDC; SIN_ROM[ 65] = 16'h7FF5;
            COS_ROM[ 66] = 16'hF9B8; SIN_ROM[ 66] = 16'h7FD8;
            COS_ROM[ 67] = 16'hF696; SIN_ROM[ 67] = 16'h7FA6;
            COS_ROM[ 68] = 16'hF374; SIN_ROM[ 68] = 16'h7F61;
            COS_ROM[ 69] = 16'hF055; SIN_ROM[ 69] = 16'h7F09;
            COS_ROM[ 70] = 16'hED38; SIN_ROM[ 70] = 16'h7E9C;
            COS_ROM[ 71] = 16'hEA1E; SIN_ROM[ 71] = 16'h7E1D;
            COS_ROM[ 72] = 16'hE707; SIN_ROM[ 72] = 16'h7D89;
            COS_ROM[ 73] = 16'hE3F5; SIN_ROM[ 73] = 16'h7CE3;
            COS_ROM[ 74] = 16'hE0E6; SIN_ROM[ 74] = 16'h7C29;
            COS_ROM[ 75] = 16'hDDDD; SIN_ROM[ 75] = 16'h7B5C;
            COS_ROM[ 76] = 16'hDAD8; SIN_ROM[ 76] = 16'h7A7C;
            COS_ROM[ 77] = 16'hD7DA; SIN_ROM[ 77] = 16'h7989;
            COS_ROM[ 78] = 16'hD4E1; SIN_ROM[ 78] = 16'h7884;
            COS_ROM[ 79] = 16'hD1EF; SIN_ROM[ 79] = 16'h776B;
            COS_ROM[ 80] = 16'hCF05; SIN_ROM[ 80] = 16'h7641;
            COS_ROM[ 81] = 16'hCC21; SIN_ROM[ 81] = 16'h7504;
            COS_ROM[ 82] = 16'hC946; SIN_ROM[ 82] = 16'h73B5;
            COS_ROM[ 83] = 16'hC674; SIN_ROM[ 83] = 16'h7254;
            COS_ROM[ 84] = 16'hC3AA; SIN_ROM[ 84] = 16'h70E2;
            COS_ROM[ 85] = 16'hC0E9; SIN_ROM[ 85] = 16'h6F5E;
            COS_ROM[ 86] = 16'hBE32; SIN_ROM[ 86] = 16'h6DC9;
            COS_ROM[ 87] = 16'hBB86; SIN_ROM[ 87] = 16'h6C23;
            COS_ROM[ 88] = 16'hB8E4; SIN_ROM[ 88] = 16'h6A6D;
            COS_ROM[ 89] = 16'hB64C; SIN_ROM[ 89] = 16'h68A6;
            COS_ROM[ 90] = 16'hB3C1; SIN_ROM[ 90] = 16'h66CF;
            COS_ROM[ 91] = 16'hB141; SIN_ROM[ 91] = 16'h64E8;
            COS_ROM[ 92] = 16'hAECD; SIN_ROM[ 92] = 16'h62F1;
            COS_ROM[ 93] = 16'hAC65; SIN_ROM[ 93] = 16'h60EB;
            COS_ROM[ 94] = 16'hAA0B; SIN_ROM[ 94] = 16'h5ED7;
            COS_ROM[ 95] = 16'hA7BE; SIN_ROM[ 95] = 16'h5CB3;
            COS_ROM[ 96] = 16'hA57E; SIN_ROM[ 96] = 16'h5A82;
            COS_ROM[ 97] = 16'hA34D; SIN_ROM[ 97] = 16'h5842;
            COS_ROM[ 98] = 16'hA129; SIN_ROM[ 98] = 16'h55F5;
            COS_ROM[ 99] = 16'h9F15; SIN_ROM[ 99] = 16'h539B;
            COS_ROM[100] = 16'h9D0F; SIN_ROM[100] = 16'h5133;
            COS_ROM[101] = 16'h9B18; SIN_ROM[101] = 16'h4EBF;
            COS_ROM[102] = 16'h9931; SIN_ROM[102] = 16'h4C3F;
            COS_ROM[103] = 16'h975A; SIN_ROM[103] = 16'h49B4;
            COS_ROM[104] = 16'h9593; SIN_ROM[104] = 16'h471C;
            COS_ROM[105] = 16'h93DD; SIN_ROM[105] = 16'h447A;
            COS_ROM[106] = 16'h9237; SIN_ROM[106] = 16'h41CE;
            COS_ROM[107] = 16'h90A2; SIN_ROM[107] = 16'h3F17;
            COS_ROM[108] = 16'h8F1E; SIN_ROM[108] = 16'h3C56;
            COS_ROM[109] = 16'h8DAC; SIN_ROM[109] = 16'h398C;
            COS_ROM[110] = 16'h8C4B; SIN_ROM[110] = 16'h36BA;
            COS_ROM[111] = 16'h8AFC; SIN_ROM[111] = 16'h33DF;
            COS_ROM[112] = 16'h89BF; SIN_ROM[112] = 16'h30FB;
            COS_ROM[113] = 16'h8895; SIN_ROM[113] = 16'h2E11;
            COS_ROM[114] = 16'h877C; SIN_ROM[114] = 16'h2B1F;
            COS_ROM[115] = 16'h8677; SIN_ROM[115] = 16'h2826;
            COS_ROM[116] = 16'h8584; SIN_ROM[116] = 16'h2528;
            COS_ROM[117] = 16'h84A4; SIN_ROM[117] = 16'h2223;
            COS_ROM[118] = 16'h83D7; SIN_ROM[118] = 16'h1F1A;
            COS_ROM[119] = 16'h831D; SIN_ROM[119] = 16'h1C0B;
            COS_ROM[120] = 16'h8277; SIN_ROM[120] = 16'h18F9;
            COS_ROM[121] = 16'h81E3; SIN_ROM[121] = 16'h15E2;
            COS_ROM[122] = 16'h8164; SIN_ROM[122] = 16'h12C8;
            COS_ROM[123] = 16'h80F7; SIN_ROM[123] = 16'h0FAB;
            COS_ROM[124] = 16'h809F; SIN_ROM[124] = 16'h0C8C;
            COS_ROM[125] = 16'h805A; SIN_ROM[125] = 16'h096A;
            COS_ROM[126] = 16'h8028; SIN_ROM[126] = 16'h0648;
            COS_ROM[127] = 16'h800B; SIN_ROM[127] = 16'h0324;
            COS_ROM[128] = 16'h8001; SIN_ROM[128] = 16'h0000;
            COS_ROM[129] = 16'h800B; SIN_ROM[129] = 16'hFCDC;
            COS_ROM[130] = 16'h8028; SIN_ROM[130] = 16'hF9B8;
            COS_ROM[131] = 16'h805A; SIN_ROM[131] = 16'hF696;
            COS_ROM[132] = 16'h809F; SIN_ROM[132] = 16'hF374;
            COS_ROM[133] = 16'h80F7; SIN_ROM[133] = 16'hF055;
            COS_ROM[134] = 16'h8164; SIN_ROM[134] = 16'hED38;
            COS_ROM[135] = 16'h81E3; SIN_ROM[135] = 16'hEA1E;
            COS_ROM[136] = 16'h8277; SIN_ROM[136] = 16'hE707;
            COS_ROM[137] = 16'h831D; SIN_ROM[137] = 16'hE3F5;
            COS_ROM[138] = 16'h83D7; SIN_ROM[138] = 16'hE0E6;
            COS_ROM[139] = 16'h84A4; SIN_ROM[139] = 16'hDDDD;
            COS_ROM[140] = 16'h8584; SIN_ROM[140] = 16'hDAD8;
            COS_ROM[141] = 16'h8677; SIN_ROM[141] = 16'hD7DA;
            COS_ROM[142] = 16'h877C; SIN_ROM[142] = 16'hD4E1;
            COS_ROM[143] = 16'h8895; SIN_ROM[143] = 16'hD1EF;
            COS_ROM[144] = 16'h89BF; SIN_ROM[144] = 16'hCF05;
            COS_ROM[145] = 16'h8AFC; SIN_ROM[145] = 16'hCC21;
            COS_ROM[146] = 16'h8C4B; SIN_ROM[146] = 16'hC946;
            COS_ROM[147] = 16'h8DAC; SIN_ROM[147] = 16'hC674;
            COS_ROM[148] = 16'h8F1E; SIN_ROM[148] = 16'hC3AA;
            COS_ROM[149] = 16'h90A2; SIN_ROM[149] = 16'hC0E9;
            COS_ROM[150] = 16'h9237; SIN_ROM[150] = 16'hBE32;
            COS_ROM[151] = 16'h93DD; SIN_ROM[151] = 16'hBB86;
            COS_ROM[152] = 16'h9593; SIN_ROM[152] = 16'hB8E4;
            COS_ROM[153] = 16'h975A; SIN_ROM[153] = 16'hB64C;
            COS_ROM[154] = 16'h9931; SIN_ROM[154] = 16'hB3C1;
            COS_ROM[155] = 16'h9B18; SIN_ROM[155] = 16'hB141;
            COS_ROM[156] = 16'h9D0F; SIN_ROM[156] = 16'hAECD;
            COS_ROM[157] = 16'h9F15; SIN_ROM[157] = 16'hAC65;
            COS_ROM[158] = 16'hA129; SIN_ROM[158] = 16'hAA0B;
            COS_ROM[159] = 16'hA34D; SIN_ROM[159] = 16'hA7BE;
            COS_ROM[160] = 16'hA57E; SIN_ROM[160] = 16'hA57E;
            COS_ROM[161] = 16'hA7BE; SIN_ROM[161] = 16'hA34D;
            COS_ROM[162] = 16'hAA0B; SIN_ROM[162] = 16'hA129;
            COS_ROM[163] = 16'hAC65; SIN_ROM[163] = 16'h9F15;
            COS_ROM[164] = 16'hAECD; SIN_ROM[164] = 16'h9D0F;
            COS_ROM[165] = 16'hB141; SIN_ROM[165] = 16'h9B18;
            COS_ROM[166] = 16'hB3C1; SIN_ROM[166] = 16'h9931;
            COS_ROM[167] = 16'hB64C; SIN_ROM[167] = 16'h975A;
            COS_ROM[168] = 16'hB8E4; SIN_ROM[168] = 16'h9593;
            COS_ROM[169] = 16'hBB86; SIN_ROM[169] = 16'h93DD;
            COS_ROM[170] = 16'hBE32; SIN_ROM[170] = 16'h9237;
            COS_ROM[171] = 16'hC0E9; SIN_ROM[171] = 16'h90A2;
            COS_ROM[172] = 16'hC3AA; SIN_ROM[172] = 16'h8F1E;
            COS_ROM[173] = 16'hC674; SIN_ROM[173] = 16'h8DAC;
            COS_ROM[174] = 16'hC946; SIN_ROM[174] = 16'h8C4B;
            COS_ROM[175] = 16'hCC21; SIN_ROM[175] = 16'h8AFC;
            COS_ROM[176] = 16'hCF05; SIN_ROM[176] = 16'h89BF;
            COS_ROM[177] = 16'hD1EF; SIN_ROM[177] = 16'h8895;
            COS_ROM[178] = 16'hD4E1; SIN_ROM[178] = 16'h877C;
            COS_ROM[179] = 16'hD7DA; SIN_ROM[179] = 16'h8677;
            COS_ROM[180] = 16'hDAD8; SIN_ROM[180] = 16'h8584;
            COS_ROM[181] = 16'hDDDD; SIN_ROM[181] = 16'h84A4;
            COS_ROM[182] = 16'hE0E6; SIN_ROM[182] = 16'h83D7;
            COS_ROM[183] = 16'hE3F5; SIN_ROM[183] = 16'h831D;
            COS_ROM[184] = 16'hE707; SIN_ROM[184] = 16'h8277;
            COS_ROM[185] = 16'hEA1E; SIN_ROM[185] = 16'h81E3;
            COS_ROM[186] = 16'hED38; SIN_ROM[186] = 16'h8164;
            COS_ROM[187] = 16'hF055; SIN_ROM[187] = 16'h80F7;
            COS_ROM[188] = 16'hF374; SIN_ROM[188] = 16'h809F;
            COS_ROM[189] = 16'hF696; SIN_ROM[189] = 16'h805A;
            COS_ROM[190] = 16'hF9B8; SIN_ROM[190] = 16'h8028;
            COS_ROM[191] = 16'hFCDC; SIN_ROM[191] = 16'h800B;
            COS_ROM[192] = 16'h0000; SIN_ROM[192] = 16'h8001;
            COS_ROM[193] = 16'h0324; SIN_ROM[193] = 16'h800B;
            COS_ROM[194] = 16'h0648; SIN_ROM[194] = 16'h8028;
            COS_ROM[195] = 16'h096A; SIN_ROM[195] = 16'h805A;
            COS_ROM[196] = 16'h0C8C; SIN_ROM[196] = 16'h809F;
            COS_ROM[197] = 16'h0FAB; SIN_ROM[197] = 16'h80F7;
            COS_ROM[198] = 16'h12C8; SIN_ROM[198] = 16'h8164;
            COS_ROM[199] = 16'h15E2; SIN_ROM[199] = 16'h81E3;
            COS_ROM[200] = 16'h18F9; SIN_ROM[200] = 16'h8277;
            COS_ROM[201] = 16'h1C0B; SIN_ROM[201] = 16'h831D;
            COS_ROM[202] = 16'h1F1A; SIN_ROM[202] = 16'h83D7;
            COS_ROM[203] = 16'h2223; SIN_ROM[203] = 16'h84A4;
            COS_ROM[204] = 16'h2528; SIN_ROM[204] = 16'h8584;
            COS_ROM[205] = 16'h2826; SIN_ROM[205] = 16'h8677;
            COS_ROM[206] = 16'h2B1F; SIN_ROM[206] = 16'h877C;
            COS_ROM[207] = 16'h2E11; SIN_ROM[207] = 16'h8895;
            COS_ROM[208] = 16'h30FB; SIN_ROM[208] = 16'h89BF;
            COS_ROM[209] = 16'h33DF; SIN_ROM[209] = 16'h8AFC;
            COS_ROM[210] = 16'h36BA; SIN_ROM[210] = 16'h8C4B;
            COS_ROM[211] = 16'h398C; SIN_ROM[211] = 16'h8DAC;
            COS_ROM[212] = 16'h3C56; SIN_ROM[212] = 16'h8F1E;
            COS_ROM[213] = 16'h3F17; SIN_ROM[213] = 16'h90A2;
            COS_ROM[214] = 16'h41CE; SIN_ROM[214] = 16'h9237;
            COS_ROM[215] = 16'h447A; SIN_ROM[215] = 16'h93DD;
            COS_ROM[216] = 16'h471C; SIN_ROM[216] = 16'h9593;
            COS_ROM[217] = 16'h49B4; SIN_ROM[217] = 16'h975A;
            COS_ROM[218] = 16'h4C3F; SIN_ROM[218] = 16'h9931;
            COS_ROM[219] = 16'h4EBF; SIN_ROM[219] = 16'h9B18;
            COS_ROM[220] = 16'h5133; SIN_ROM[220] = 16'h9D0F;
            COS_ROM[221] = 16'h539B; SIN_ROM[221] = 16'h9F15;
            COS_ROM[222] = 16'h55F5; SIN_ROM[222] = 16'hA129;
            COS_ROM[223] = 16'h5842; SIN_ROM[223] = 16'hA34D;
            COS_ROM[224] = 16'h5A82; SIN_ROM[224] = 16'hA57E;
            COS_ROM[225] = 16'h5CB3; SIN_ROM[225] = 16'hA7BE;
            COS_ROM[226] = 16'h5ED7; SIN_ROM[226] = 16'hAA0B;
            COS_ROM[227] = 16'h60EB; SIN_ROM[227] = 16'hAC65;
            COS_ROM[228] = 16'h62F1; SIN_ROM[228] = 16'hAECD;
            COS_ROM[229] = 16'h64E8; SIN_ROM[229] = 16'hB141;
            COS_ROM[230] = 16'h66CF; SIN_ROM[230] = 16'hB3C1;
            COS_ROM[231] = 16'h68A6; SIN_ROM[231] = 16'hB64C;
            COS_ROM[232] = 16'h6A6D; SIN_ROM[232] = 16'hB8E4;
            COS_ROM[233] = 16'h6C23; SIN_ROM[233] = 16'hBB86;
            COS_ROM[234] = 16'h6DC9; SIN_ROM[234] = 16'hBE32;
            COS_ROM[235] = 16'h6F5E; SIN_ROM[235] = 16'hC0E9;
            COS_ROM[236] = 16'h70E2; SIN_ROM[236] = 16'hC3AA;
            COS_ROM[237] = 16'h7254; SIN_ROM[237] = 16'hC674;
            COS_ROM[238] = 16'h73B5; SIN_ROM[238] = 16'hC946;
            COS_ROM[239] = 16'h7504; SIN_ROM[239] = 16'hCC21;
            COS_ROM[240] = 16'h7641; SIN_ROM[240] = 16'hCF05;
            COS_ROM[241] = 16'h776B; SIN_ROM[241] = 16'hD1EF;
            COS_ROM[242] = 16'h7884; SIN_ROM[242] = 16'hD4E1;
            COS_ROM[243] = 16'h7989; SIN_ROM[243] = 16'hD7DA;
            COS_ROM[244] = 16'h7A7C; SIN_ROM[244] = 16'hDAD8;
            COS_ROM[245] = 16'h7B5C; SIN_ROM[245] = 16'hDDDD;
            COS_ROM[246] = 16'h7C29; SIN_ROM[246] = 16'hE0E6;
            COS_ROM[247] = 16'h7CE3; SIN_ROM[247] = 16'hE3F5;
            COS_ROM[248] = 16'h7D89; SIN_ROM[248] = 16'hE707;
            COS_ROM[249] = 16'h7E1D; SIN_ROM[249] = 16'hEA1E;
            COS_ROM[250] = 16'h7E9C; SIN_ROM[250] = 16'hED38;
            COS_ROM[251] = 16'h7F09; SIN_ROM[251] = 16'hF055;
            COS_ROM[252] = 16'h7F61; SIN_ROM[252] = 16'hF374;
            COS_ROM[253] = 16'h7FA6; SIN_ROM[253] = 16'hF696;
            COS_ROM[254] = 16'h7FD8; SIN_ROM[254] = 16'hF9B8;
            COS_ROM[255] = 16'h7FF5; SIN_ROM[255] = 16'hFCDC;
        end

        wire [7:0] lut_idx_beh = phase_acc_r[NCO_PHASE_WIDTH-1 -: 8];

        reg [ROTATOR_COEFF_WIDTH-1:0] sin_pipe_beh [0:LATENCY-1];
        reg [ROTATOR_COEFF_WIDTH-1:0] cos_pipe_beh [0:LATENCY-1];
        reg                           valid_pipe_beh[0:LATENCY-1];

        integer k;
        always @(posedge aclk) begin
            if (!aresetn) begin
                sin_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
                cos_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
                sincos_valid_r <= 1'b0;
                for (k = 0; k < LATENCY; k = k + 1) begin
                    sin_pipe_beh [k] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                    cos_pipe_beh [k] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                    valid_pipe_beh[k] <= 1'b0;
                end
            end else begin
                // pre-accumulation phase: lut_idx_beh uses OLD phase_acc_r (NBA semantics)
                sin_pipe_beh [0] <= SIN_ROM[lut_idx_beh];
                cos_pipe_beh [0] <= COS_ROM[lut_idx_beh];
                valid_pipe_beh[0] <= enable && !phase_reset;
                for (k = 1; k < LATENCY; k = k + 1) begin
                    sin_pipe_beh [k] <= sin_pipe_beh [k-1];
                    cos_pipe_beh [k] <= cos_pipe_beh [k-1];
                    valid_pipe_beh[k] <= valid_pipe_beh[k-1];
                end
                sin_out_r      <= sin_pipe_beh [LATENCY-1];
                cos_out_r      <= cos_pipe_beh [LATENCY-1];
                sincos_valid_r <= valid_pipe_beh[LATENCY-1];
            end
        end

    end else begin : gen_xilinx_ip_placeholder

        // =====================================================================
        // Xilinx CORDIC rotate-mode IP placeholder
        // =====================================================================
        // This section is intentionally left as a scaffold.
        // Production synthesis must replace it with a real cordic_v6_0 IP.
        // DO NOT instantiate a fake module and claim it is real Xilinx IP.
        //
        // When the real IP is ready, the instantiation will look like:
        //
        //   wire signed [CORDIC_PHASE_WIDTH-1:0] cordic_phase_in;
        //   wire [ROTATOR_COEFF_WIDTH*2-1:0]     cordic_dout_tdata;
        //   wire                                 cordic_dout_tvalid;
        //
        //   // Top 16 bits of 32-bit accumulator as signed Q1.15 = ±pi input.
        //   // acc[31:16] interpreted signed gives -32768..+32767 → -pi..+pi
        //   assign cordic_phase_in = $signed(phase_acc_r[NCO_PHASE_WIDTH-1 -: CORDIC_PHASE_WIDTH]);
        //
        //   cordic_v6_0 cordic_sincos_inst (
        //     .aclk                   (aclk),
        //     .aresetn                (aresetn),
        //     .s_axis_phase_tvalid    (enable && !phase_reset),
        //     .s_axis_phase_tdata     ({{(16-CORDIC_PHASE_WIDTH){cordic_phase_in[CORDIC_PHASE_WIDTH-1]}},
        //                              cordic_phase_in}),
        //     .m_axis_dout_tvalid     (cordic_dout_tvalid),
        //     .m_axis_dout_tdata      (cordic_dout_tdata)
        //   );
        //
        //   // CORDIC output: TDATA = {Y[15:0], X[15:0]} where X=cos, Y=sin.
        //   // Note: CORDIC rotate mode output has a gain factor ~1.6468.
        //   // If the IP is configured with compensation, output is scaled to ±32767 directly.
        //   assign sin_out_r      = cordic_dout_tdata[31:16];
        //   assign cos_out_r      = cordic_dout_tdata[15:0];
        //   assign sincos_valid_r = cordic_dout_tvalid;
        //
        // TODO: Generate cordic_v6_0 XCI using scripts/create_cordic_sincos_ip.tcl
        // TODO: Add generated XCI to xvlog compile list in simulation script
        // TODO: Verify latency matches LATENCY parameter; adjust pipeline if needed

        reg [ROTATOR_COEFF_WIDTH-1:0] sin_pipe_ph [0:LATENCY-1];
        reg [ROTATOR_COEFF_WIDTH-1:0] cos_pipe_ph [0:LATENCY-1];
        reg                           valid_pipe_ph[0:LATENCY-1];

        integer k2;
        always @(posedge aclk) begin
            if (!aresetn) begin
                sin_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
                cos_out_r      <= {ROTATOR_COEFF_WIDTH{1'b0}};
                sincos_valid_r <= 1'b0;
                for (k2 = 0; k2 < LATENCY; k2 = k2 + 1) begin
                    sin_pipe_ph [k2] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                    cos_pipe_ph [k2] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                    valid_pipe_ph[k2] <= 1'b0;
                end
            end else begin
                // Placeholder: propagate valid only, outputs remain 0.
                // Replace this block with actual CORDIC IP output capture.
                sin_pipe_ph [0] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                cos_pipe_ph [0] <= {ROTATOR_COEFF_WIDTH{1'b0}};
                valid_pipe_ph[0] <= enable && !phase_reset;
                for (k2 = 1; k2 < LATENCY; k2 = k2 + 1) begin
                    sin_pipe_ph [k2] <= sin_pipe_ph [k2-1];
                    cos_pipe_ph [k2] <= cos_pipe_ph [k2-1];
                    valid_pipe_ph[k2] <= valid_pipe_ph[k2-1];
                end
                sin_out_r      <= sin_pipe_ph [LATENCY-1];
                cos_out_r      <= cos_pipe_ph [LATENCY-1];
                sincos_valid_r <= valid_pipe_ph[LATENCY-1];
            end
        end

    end
    endgenerate

endmodule
