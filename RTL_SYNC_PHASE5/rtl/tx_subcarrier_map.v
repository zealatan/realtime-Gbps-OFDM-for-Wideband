// =====================================================================
// tx_subcarrier_map.v
// ---------------------------------------------------------------------
// OFDM TX front: runtime-selectable QAM data map + QPSK pilot insert +
// subcarrier assembly + fftshift (rearrange_spectrum), producing the
// 256-bin frequency-domain spectrum (in IFFT-input / fftshift order)
// for ONE data OFDM symbol, 1 bin / clock, AXI-Stream.
//
// MULTI-MODULATION (mod_sel[1:0]):
//     0 = QPSK   (2 bits/sym, 1 bit/axis,  2 levels/axis: +/-1)
//     1 = 16-QAM (4 bits/sym, 2 bits/axis, 4 levels/axis: +/-1,3)
//     2 = 64-QAM (6 bits/sym, 3 bits/axis, 8 levels/axis: +/-1,3,5,7)
//     3 = 256QAM (8 bits/sym, 4 bits/axis, 16 levels/axis:+/-1..15)
//   k = bits/axis = mod_sel + 1 ;  nlev = 2^k levels/axis.
//
// Per axis the k bits are FOLDED-GRAY coded:
//     bit[k-1] (MSB) = sign  (1 = positive amplitude)
//     bits[k-2:0]    = Gray code of the magnitude rank m (0 = innermost)
//   axis value = (+/- (2*m+1)) * SCALE_mod  ->  pre-scaled Q15 magnitude
//   taken from QAM_LVL[mod_sel][m] (exact rounded round((2m+1)*S*Q15)).
// For mod_sel=1 (16-QAM) this is BIT-EXACT identical to the previous
// fixed 16-QAM map (levels {1610,4829} = old Q16_1,Q16_3; axis code
// {b_hi=sign, b_lo=gray(m)} = old tmp = b_hi*2+b_lo).
//
// Per-mod SCALE = {1/sqrt(2),1/sqrt(10),1/sqrt(42),1/sqrt(170)} gives all
// four constellations the SAME average symbol power (RMS-matched), with
// the project Q15 spectrum scale 5090.697374.
//
// ---------------------------------------------------------------------
// DATA BITS INTERFACE
// ---------------------------------------------------------------------
//   The caller presents the CURRENT symbol's data bits as a flat bus
//   `data_bits[NDATA_SC*BPC_MAX-1:0]` sized for the WIDEST mod (8 bits/
//   carrier).  For carrier k the BITS_PER_SYM = 2*k_axis bits live at
//   data_bits[k*BPC_MAX + b], b = 0 .. BITS_PER_SYM-1, in order
//   [a0 a1 .. a(K-1) | aq0 aq1 .. aq(K-1)] : first K bits = I axis
//   (a0 = MSB = sign), next K bits = Q axis. Unused high bits ignored.
//   Held stable for the whole symbol; latched at sym_start.
//
//   (For 16-QAM, BITS_PER_SYM=4, layout [b0 b1 b2 b3] = exactly the old
//   contract: b0,b1 = I axis (b0=sign), b2,b3 = Q axis.)
//
//   data bits / frame = NDATA_SC * (2*k) * NUM_DATA  (handled by caller).
// ---------------------------------------------------------------------
// Pilots STAY QPSK always (used by CE), streamed from the pilot ROM,
// unchanged.
// ---------------------------------------------------------------------
`timescale 1ns/1ps
`default_nettype none

module tx_subcarrier_map #(
    parameter integer DATA_W   = 16,
    parameter integer NSC      = 256,
    parameter integer NPIL     = 32,
    parameter integer NDATA_SC = 221,
    parameter integer BPC_MAX  = 8,      // max data bits / carrier (256-QAM)
    // legacy 16-QAM level constants (kept for back-compat instantiation;
    // the generalized path uses the QAM_LVL table below, whose mod_sel=1
    // entries equal {Q16_1,Q16_3}).
    parameter integer Q16_1    = 1610,   // round(1*SCALE_16QAM*Q15)
    parameter integer Q16_3    = 4829,   // round(3*SCALE_16QAM*Q15)
    parameter         SPECMAP  = "rtl/tx_rom/tx_specmap.hex"
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- modulation select (latched per symbol) ----
    input  wire [1:0]              mod_sel,             // 0..3

    // ---- control : start a new symbol, latch its data bits ----
    input  wire                    sym_start,           // 1-cycle pulse
    input  wire [NDATA_SC*BPC_MAX-1:0] data_bits,       // BPC_MAX bits/carrier, stable

    // ---- pilot ROM read, ADDRESSED by pilot index (src) ----
    output wire [4:0]              pilot_addr,          // 0..31 pilot index
    input  wire [2*DATA_W-1:0]     pilot_tdata,

    // ---- master : 256 spectrum bins, fftshift order, {Q,I} Q15 ----
    output wire                    m_valid,
    input  wire                    m_ready,
    output wire [2*DATA_W-1:0]     m_tdata,
    output wire                    m_last               // bin 255
);
    localparam integer NSC_LOG2 = 8;

    // ---- spectrum-map ROM : {src[9:2], kind[1:0]} ----
    reg [11:0] specmap [0:NSC-1];
    initial $readmemh(SPECMAP, specmap);

    // =================================================================
    // Per-mod amplitude level magnitude table QAM_LVL[mod_sel][m]
    //   value magnitude (Q15) = round((2*m+1) * SCALE_mod * Q15_SCALE)
    //   Q15_SCALE = 5090.697374
    //   QPSK  S=1/sqrt(2)  : {3600}
    //   16QAM S=1/sqrt(10) : {1610,4829}            (== Q16_1,Q16_3)
    //   64QAM S=1/sqrt(42) : {786,2357,3928,5499}
    //   256QAM S=1/sqrt(170): {390,1171,1952,2733,3514,4295,5076,5857}
    // m index range per mod: 0..(nlev/2 - 1), nlev = 2^(mod_sel+1).
    // =================================================================
    function signed [DATA_W-1:0] qam_level;   // magnitude (>=0)
        input [1:0] ms;
        input [2:0] m;                         // 0..7
        begin
            case (ms)
                2'd0: qam_level = 16'sd3600;                    // QPSK (m=0 only)
                2'd1: qam_level = (m==3'd0) ? 16'sd1610 : 16'sd4829;
                2'd2: case (m[1:0])
                          2'd0: qam_level = 16'sd786;
                          2'd1: qam_level = 16'sd2357;
                          2'd2: qam_level = 16'sd3928;
                          default: qam_level = 16'sd5499;
                      endcase
                default: case (m)              // 256-QAM
                          3'd0: qam_level = 16'sd390;
                          3'd1: qam_level = 16'sd1171;
                          3'd2: qam_level = 16'sd1952;
                          3'd3: qam_level = 16'sd2733;
                          3'd4: qam_level = 16'sd3514;
                          3'd5: qam_level = 16'sd4295;
                          3'd6: qam_level = 16'sd5076;
                          default: qam_level = 16'sd5857;
                      endcase
            endcase
        end
    endfunction

    // Gray->binary (ungray) for up to 3 magnitude bits (k-1<=3)
    function [2:0] ungray3;
        input [2:0] g;
        begin
            ungray3[2] = g[2];
            ungray3[1] = g[2] ^ g[1];
            ungray3[0] = g[2] ^ g[1] ^ g[0];
        end
    endfunction

    // map one axis of K bits (K = mod_sel+1) -> signed Q15 sample.
    //   Bit order is MSB-FIRST within the axis (matches the legacy 16-QAM
    //   contract): axis_bits[0] = sign (1=pos); axis_bits[1..K-1] = Gray(m)
    //   from gray-MSB (axis_bits[1]) down to gray-LSB (axis_bits[K-1]).
    function signed [DATA_W-1:0] qam_axis;
        input [1:0]       ms;
        input [BPC_MAX/2-1:0] axis_bits;   // up to 4 bits, MSB-first (bit0=sign)
        reg               sign_pos;
        reg [2:0]         graybits;
        reg [2:0]         m;
        reg signed [DATA_W-1:0] mag;
        begin
            case (ms)
                2'd0: begin sign_pos = axis_bits[0]; graybits = 3'd0;                  end // K=1
                2'd1: begin sign_pos = axis_bits[0]; graybits = {2'b0, axis_bits[1]};  end // K=2
                2'd2: begin sign_pos = axis_bits[0]; graybits = {1'b0, axis_bits[1], axis_bits[2]}; end // K=3
                default: begin sign_pos = axis_bits[0]; graybits = {axis_bits[1], axis_bits[2], axis_bits[3]}; end // K=4
            endcase
            m   = ungray3(graybits);
            mag = qam_level(ms, m);
            qam_axis = sign_pos ? mag : -mag;
        end
    endfunction

    // ---- per-symbol state ----
    reg                  busy;       // emitting a symbol
    reg [NSC_LOG2-1:0]   bin;        // 0..255 current IFFT-input index
    reg [NDATA_SC*BPC_MAX-1:0] bits_l;   // latched data bits for this symbol
    reg [1:0]            mod_l;      // latched modulation

    // current ROM word for `bin`
    wire [11:0] mw   = specmap[bin];
    wire [1:0]  kind = mw[1:0];
    wire [9:0]  src  = mw[11:2];

    // extract this carrier's BPC_MAX bits, split into I (low K) / Q (next K)
    wire [BPC_MAX-1:0] carrier_bits = bits_l[src*BPC_MAX +: BPC_MAX];
    // K = mod_l+1 ; I axis = carrier_bits[K-1:0], Q axis = carrier_bits[2K-1:K]
    reg [BPC_MAX/2-1:0] ax_i, ax_q;
    always @(*) begin
        case (mod_l)
            2'd0: begin ax_i = carrier_bits[0 +: 1]; ax_q = carrier_bits[1 +: 1]; end
            2'd1: begin ax_i = carrier_bits[0 +: 2]; ax_q = carrier_bits[2 +: 2]; end
            2'd2: begin ax_i = carrier_bits[0 +: 3]; ax_q = carrier_bits[3 +: 3]; end
            default: begin ax_i = carrier_bits[0 +: 4]; ax_q = carrier_bits[4 +: 4]; end
        endcase
    end
    wire signed [DATA_W-1:0] qam_i = qam_axis(mod_l, ax_i);
    wire signed [DATA_W-1:0] qam_q = qam_axis(mod_l, ax_q);

    // pilot ROM addressed by the current bin's pilot index (src)
    assign pilot_addr = src[4:0];
    wire signed [DATA_W-1:0] pil_i = pilot_tdata[DATA_W-1:0];
    wire signed [DATA_W-1:0] pil_q = pilot_tdata[2*DATA_W-1:DATA_W];

    // selected bin value
    reg signed [DATA_W-1:0] sel_i, sel_q;
    always @(*) begin
        case (kind)
            2'd1: begin sel_i = pil_i;  sel_q = pil_q;  end   // pilot (QPSK)
            2'd2: begin sel_i = qam_i;  sel_q = qam_q;  end   // data (mod_l QAM)
            default: begin sel_i = {DATA_W{1'b0}}; sel_q = {DATA_W{1'b0}}; end
        endcase
    end

    wire beat = m_valid && m_ready;

    assign m_valid = busy;
    assign m_tdata = { sel_q, sel_i };
    assign m_last  = busy && (bin == NSC-1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy   <= 1'b0;
            bin    <= {NSC_LOG2{1'b0}};
            bits_l <= {(NDATA_SC*BPC_MAX){1'b0}};
            mod_l  <= 2'd1;
        end else begin
            if (sym_start && !busy) begin
                busy   <= 1'b1;
                bin    <= {NSC_LOG2{1'b0}};
                bits_l <= data_bits;
                mod_l  <= mod_sel;
            end else if (beat) begin
                if (bin == NSC-1) begin
                    busy <= 1'b0;
                    bin  <= {NSC_LOG2{1'b0}};
                end else begin
                    bin <= bin + 1'b1;
                end
            end
        end
    end

    wire _unused = &{1'b0, Q16_1[0], Q16_3[0]};

endmodule

`default_nettype wire
