`timescale 1ns/1ps

// zcu216_dac_tone_axis - DAC TX source (256-bit s32_axis @ clk_dac3 430.08 MHz).
//
// TWO modes (selected by ctrl[14], ports UNCHANGED so the 08 BD module_ref is
// unaffected -- no BD edit needed):
//   ctrl[1]=0 : original square-wave tone (~107.5 MHz) for the XM655 loopback
//               sanity (bringup 6a). All 16 sub-samples carry the same value.
//   ctrl[1]=1 : OFDM mode (bringup 6b) -- stream a PRE-COMPUTED full-rate
//               (6.88128 GSPS) real OFDM passband from internal BRAM, 16
//               samples/beat, looping. The waveform (IF+44.8x upsampling baked
//               in) comes from scripts/gen_ofdm_dac_waveform.py -> INIT_FILE.
// ctrl[0]=enable, ctrl[31:16]=tone amplitude (tone mode only).
module zcu216_dac_tone_axis (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  ctrl,
    output wire [255:0] m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);
    // OFDM BRAM (bringup 6b). Hardcoded localparams keep the module PORTS
    // identical to the original, so the BD module_ref needs no refresh.
    localparam integer NBEATS    = 5824;             // beats in ofdm_dac_fckp0.hex
                                                     // (RF-6d real-bypass: lane rate
                                                     // 3.44064G, DAC interp x2; was 11648
                                                     // @6.88128G under broken C2R path)
    localparam         INIT_FILE = "ofdm_dac_fckp0.hex";
    localparam integer AW = 14;                       // ceil(log2(5824))=13; 14 safe

    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;
    reg [15:0] phase = 16'd0;

    wire enable    = ctrl_sync[0];
    // ctrl[1] is CAP_EN on the shared loop_ctrl_gpio (drives adc capture too) -
    // use a FREE bit for OFDM-mode select. bits 2-13=cap index, 16-31=amp,
    // 14/15 free -> use ctrl[14].
    wire ofdm_mode = ctrl_sync[14];
    wire [15:0] configured_amp = ctrl_sync[31:16];
    wire signed [15:0] amp = (configured_amp == 16'd0) ? 16'sd128 : configured_amp;
    wire signed [15:0] tone_sample = phase[1] ? -amp : amp;
    wire [255:0] tone_data = {
        tone_sample, tone_sample, tone_sample, tone_sample,
        tone_sample, tone_sample, tone_sample, tone_sample,
        tone_sample, tone_sample, tone_sample, tone_sample,
        tone_sample, tone_sample, tone_sample, tone_sample
    };

    // OFDM waveform BRAM
    (* ram_style = "block" *) reg [255:0] ofdm_mem [0:NBEATS-1];
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, ofdm_mem);
    end
    reg [AW-1:0] ofdm_addr = {AW{1'b0}};
    reg [255:0]  ofdm_rd   = 256'd0;   // BRAM embedded output register
    reg [255:0]  ofdm_rd2  = 256'd0;   // extra pipeline stage -> closes timing @430MHz

    assign m_axis_tvalid = enable;
    assign m_axis_tdata  = ofdm_mode ? ofdm_rd2 : tone_data;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta <= 32'd0;
            ctrl_sync <= 32'd0;
            phase     <= 16'd0;
            ofdm_addr <= {AW{1'b0}};
            ofdm_rd   <= 256'd0;
            ofdm_rd2  <= 256'd0;
        end else begin
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            ofdm_rd   <= ofdm_mem[ofdm_addr];        // BRAM read (embedded out reg)
            ofdm_rd2  <= ofdm_rd;                     // pipeline -> m_axis_tdata
            if (!enable) begin
                phase     <= 16'd0;
                ofdm_addr <= {AW{1'b0}};
            end else if (m_axis_tready) begin
                phase     <= phase + 16'd1;
                ofdm_addr <= (ofdm_addr == NBEATS-1) ? {AW{1'b0}} : ofdm_addr + 1'b1;
            end
        end
    end
endmodule
