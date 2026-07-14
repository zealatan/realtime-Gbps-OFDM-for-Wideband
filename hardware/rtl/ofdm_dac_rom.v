`timescale 1ns/1ps

// ofdm_dac_rom - OFDM DAC-TX waveform player (RF 6b).
//
// Drop-in replacement for zcu216_dac_tone_axis: same 256-bit s32_axis interface
// @ clk_dac3 (430.08 MHz), but instead of generating a square wave it streams a
// PRE-COMPUTED full-rate (6.88128 GSPS) real OFDM passband waveform from BRAM,
// 16 samples/beat ([15:0]=sample0 .. [255:240]=sample15), looping continuously.
//
// The waveform (IF + 44.8x upsampling baked in) is generated offline by
// scripts/gen_ofdm_dac_waveform.py and loaded via $readmemh(INIT_FILE). This
// eliminates the PL resampler and the DAC DUC: DAC runs Interp=1, real mode.
//
// ctrl[0] = enable (mirror tone block). Address free-runs (wraps) while enabled
// and m_axis_tready; deasserting enable rewinds to beat 0.
module ofdm_dac_rom #(
    parameter integer NBEATS    = 5824,             // 256-bit beats (RF-6d real-bypass,
                                                    // lane 3.44064G interp x2; was 11648)
    parameter         INIT_FILE = "ofdm_dac_fckp0.hex"
) (
    input  wire          aclk,
    input  wire          aresetn,
    input  wire [31:0]   ctrl,
    output wire [255:0]  m_axis_tdata,
    output wire          m_axis_tvalid,
    input  wire          m_axis_tready
);
    localparam integer AW = (NBEATS <= 1) ? 1 : $clog2(NBEATS);

    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;

    (* ram_style = "block" *) reg [255:0] mem [0:NBEATS-1];
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    reg [AW-1:0] addr = {AW{1'b0}};
    reg [255:0]  rd_data = 256'd0;

    wire enable = ctrl_sync[0];

    assign m_axis_tvalid = enable;
    assign m_axis_tdata  = rd_data;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta <= 32'd0;
            ctrl_sync <= 32'd0;
            addr      <= {AW{1'b0}};
            rd_data   <= 256'd0;
        end else begin
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            rd_data   <= mem[addr];          // 1-cycle registered read
            if (!enable) begin
                addr <= {AW{1'b0}};
            end else if (m_axis_tready) begin
                addr <= (addr == NBEATS-1) ? {AW{1'b0}} : addr + 1'b1;
            end
        end
    end
endmodule
