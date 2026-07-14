`timescale 1ns/1ps

// rfdc_deser - RFDC DDC -> DUT gearbox (read side).
//
// The RFDC ADC DDC emits m20_axis = 160-bit = 5 complex samples/beat, each lane
// already packed {Q[31:16], I[15:0]} (== the DUT s_axis format). Lane 0 = [31:0]
// ... lane 4 = [159:128]. Word rate 30.72 MHz, 5 samples/beat = 153.6 Msps.
//
// This module deserializes 160-bit -> 32-bit, 5:1, BUBBLE-FREE (loads the next
// word on the same cycle the last lane is consumed), so the 153.6 Msps complex
// stream flows 1 sample/clock at pl_clk0=153.6 MHz into the DUT s_axis.
//
// CDC (clk_adc2 307.2 -> pl_clk0 153.6) is done UPSTREAM by an async
// axis_data_fifo (160-bit) in the BD; this module is single-clock (pl_clk0).
module rfdc_deser (
    input  wire         aclk,           // pl_clk0 = 153.6 MHz
    input  wire         aresetn,
    // 160-bit input (from async FIFO m_axis)
    input  wire [159:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    // 32-bit output to DUT s_axis (packed {Q,I})
    output wire [31:0]  m_axis_tdata,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready
);
    reg [159:0] hold = 160'd0;
    reg         has  = 1'b0;
    reg [2:0]   cnt  = 3'd0;             // current lane 0..4

    // grab a new 160-bit word when empty, or when the last lane is being consumed
    assign s_axis_tready = (!has) || (cnt == 3'd4 && m_axis_tready);
    assign m_axis_tvalid = has;
    assign m_axis_tdata  = hold[32*cnt +: 32];

    always @(posedge aclk) begin
        if (!aresetn) begin
            hold <= 160'd0;
            has  <= 1'b0;
            cnt  <= 3'd0;
        end else if (has && m_axis_tready) begin
            // a lane was accepted this cycle
            if (cnt == 3'd4) begin
                if (s_axis_tvalid) begin    // bubble-free reload
                    hold <= s_axis_tdata;
                    cnt  <= 3'd0;
                    has  <= 1'b1;
                end else begin
                    has  <= 1'b0;            // FIFO empty -> stall (will reload below)
                    cnt  <= 3'd0;
                end
            end else begin
                cnt <= cnt + 3'd1;
            end
        end else if (!has && s_axis_tvalid) begin
            hold <= s_axis_tdata;
            has  <= 1'b1;
            cnt  <= 3'd0;
        end
    end
endmodule
