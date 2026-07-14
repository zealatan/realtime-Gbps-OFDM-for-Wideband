`timescale 1ns/1ps
// Pass-through AXI4-Stream that injects TLAST every PKT_BEATS beats. The RFDC
// ADC master has no TLAST, but an AXI DMA S2MM channel needs packet boundaries
// to complete a transfer. Placing this between the ADC and the DMA turns the
// free-running ADC stream into fixed PKT_BEATS-beat packets so each S2MM
// transfer of (PKT_BEATS * DW/8) bytes terminates cleanly. Standard s_axis_* /
// m_axis_* port names so Vivado infers S_AXIS / M_AXIS interfaces.
module adc_tlast_gen #(
    parameter integer DW        = 128,
    parameter integer PKT_BEATS = 8192
) (
    input  wire           aclk,
    input  wire           aresetn,
    input  wire [DW-1:0]  s_axis_tdata,
    input  wire           s_axis_tvalid,
    output wire           s_axis_tready,
    output wire [DW-1:0]  m_axis_tdata,
    output wire           m_axis_tvalid,
    output wire           m_axis_tlast,
    input  wire           m_axis_tready
);
    reg [31:0] cnt = 32'd0;
    wire beat = s_axis_tvalid & m_axis_tready;

    assign s_axis_tready = m_axis_tready;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tlast  = (cnt == PKT_BEATS - 1);

    always @(posedge aclk) begin
        if (!aresetn)
            cnt <= 32'd0;
        else if (beat)
            cnt <= (cnt == PKT_BEATS - 1) ? 32'd0 : (cnt + 32'd1);
    end
endmodule
