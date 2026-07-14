`timescale 1ns/1ps

// Phase-B HOYA IF proof source.
//
// This source generates a low-frequency baseband square tone using a phase
// accumulator at the DAC sample granularity. The RFDC DAC fine mixer then
// places this baseband tone around the selected HOYA IF center.
//
// Future transceiver contract:
//   Complex baseband: 245.76 MSps
//   OFDM FFT:         1024
//   Bin spacing:      240 kHz
//   Occupied BW:      about 200 MHz
//
// Current pre-OFDM IF probe configuration:
//   DAC sample rate: 6.88128 GSPS
//   IF center:       3.0 GHz
//   OFDM-grid offset: 9.6 MHz = 40 * 240 kHz
//   Analog IF tone:  3009.6 MHz
//   PHASE_STEP:      round(3009.6e6 / 6.88128e9 * 2^32) = 1878449006
//
// The source is intentionally simple for first RF proof. Later, replace this
// with the real 245.76 MSps, FFT-1024 complex baseband adapter.
module zcu216_dac_if_tone_axis #(
    parameter [31:0] PHASE_STEP = 32'd1878449006
) (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  ctrl,
    output wire [255:0] m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;

    reg [31:0] phase0 = 32'd0;

    wire enable = ctrl_sync[0];
    wire [15:0] configured_amp = ctrl_sync[31:16];
    wire signed [15:0] amp = (configured_amp == 16'd0) ? 16'sd128
                                                        : configured_amp;

    wire [31:0] phase1  = phase0  + PHASE_STEP;
    wire [31:0] phase2  = phase1  + PHASE_STEP;
    wire [31:0] phase3  = phase2  + PHASE_STEP;
    wire [31:0] phase4  = phase3  + PHASE_STEP;
    wire [31:0] phase5  = phase4  + PHASE_STEP;
    wire [31:0] phase6  = phase5  + PHASE_STEP;
    wire [31:0] phase7  = phase6  + PHASE_STEP;
    wire [31:0] phase8  = phase7  + PHASE_STEP;
    wire [31:0] phase9  = phase8  + PHASE_STEP;
    wire [31:0] phase10 = phase9  + PHASE_STEP;
    wire [31:0] phase11 = phase10 + PHASE_STEP;
    wire [31:0] phase12 = phase11 + PHASE_STEP;
    wire [31:0] phase13 = phase12 + PHASE_STEP;
    wire [31:0] phase14 = phase13 + PHASE_STEP;
    wire [31:0] phase15 = phase14 + PHASE_STEP;
    wire [31:0] phase16 = phase15 + PHASE_STEP;

    wire signed [15:0] s0  = phase0[31]  ? -amp : amp;
    wire signed [15:0] s1  = phase1[31]  ? -amp : amp;
    wire signed [15:0] s2  = phase2[31]  ? -amp : amp;
    wire signed [15:0] s3  = phase3[31]  ? -amp : amp;
    wire signed [15:0] s4  = phase4[31]  ? -amp : amp;
    wire signed [15:0] s5  = phase5[31]  ? -amp : amp;
    wire signed [15:0] s6  = phase6[31]  ? -amp : amp;
    wire signed [15:0] s7  = phase7[31]  ? -amp : amp;
    wire signed [15:0] s8  = phase8[31]  ? -amp : amp;
    wire signed [15:0] s9  = phase9[31]  ? -amp : amp;
    wire signed [15:0] s10 = phase10[31] ? -amp : amp;
    wire signed [15:0] s11 = phase11[31] ? -amp : amp;
    wire signed [15:0] s12 = phase12[31] ? -amp : amp;
    wire signed [15:0] s13 = phase13[31] ? -amp : amp;
    wire signed [15:0] s14 = phase14[31] ? -amp : amp;
    wire signed [15:0] s15 = phase15[31] ? -amp : amp;

    assign m_axis_tvalid = enable;
    assign m_axis_tdata = {
        s15, s14, s13, s12,
        s11, s10, s9,  s8,
        s7,  s6,  s5,  s4,
        s3,  s2,  s1,  s0
    };

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta <= 32'd0;
            ctrl_sync <= 32'd0;
            phase0 <= 32'd0;
        end else begin
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            if (!enable) begin
                phase0 <= 32'd0;
            end else if (m_axis_tready) begin
                phase0 <= phase16;
            end
        end
    end
endmodule
