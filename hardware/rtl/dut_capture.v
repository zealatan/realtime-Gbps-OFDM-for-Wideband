`timescale 1ns/1ps

// DUT m_axis deterministic capture buffer (DMA-free DUT loopback).
//
// This is the zcu216_adc_capture variant adapted for capturing a 32-bit AXIS
// stream (the OFDM-sync DUT m_axis) instead of the 128-bit ADC stream. Each
// 32-bit beat carries one packed IQ word (e.g. [31:16]=Q, [15:0]=I) and is
// stored verbatim into an on-chip BRAM so software can read the captured slot
// back without any DMA.
//
// On a rising edge of ctrl[1] (capture enable) this module records DEPTH
// consecutive s_axis beats (s_axis_tdata, full 32-bit, one per accepted beat)
// into the BRAM, in order, then stops. Capture is count-based exactly like the
// ADC variant; s_axis_tlast is accepted but not required to terminate.
//
// The buffer is read back without DMA: software places a 12-bit sample index in
// ctrl[13:2], waits, then reads status_capture, which returns the captured
// 32-bit word at that index DIRECTLY (no sign-extension -- the data is already
// 32-bit and sign-extending would corrupt the upper IQ bits). As with the ADC
// variant the ctrl bus is double-registered (ASYNC_REG) so software does a
// dummy read followed by the real read to wait out the registered BRAM read.
// MULTI-FRAME readback note:
//   For the full-RX board build dut_capture stores DEMOD NIBBLES (one 32-bit
//   m_axis beat per data-subcarrier nibble; 2652 nibbles = one frame). To capture
//   N>=5 consecutive frames the DEPTH is bumped to 16384 (AW=14), which needs a
//   14-bit read index. The low 12 bits stay at ctrl[13:2] (unchanged contract);
//   the 2 extra MSBs come from ctrl[19:18]. Those two bits live INSIDE the
//   player's load_addr field (ctrl[28:16]) but the player only latches load_addr
//   on a load_en RISING edge, and readback holds load_en (ctrl[15]) and play_en
//   (ctrl[14]) LOW -- so driving ctrl[19:18] during readback cannot disturb the
//   (idle) player. ctrl[16]=circular is left clear during readback. This keeps
//   the single shared loop_ctrl_gpio with NO BD rewiring.
module dut_capture #(
    parameter integer DW = 32,
    parameter integer AW = 14
) (
    input  wire          aclk,
    input  wire          aresetn,
    input  wire [31:0]   ctrl,
    input  wire [DW-1:0] s_axis_tdata,
    input  wire          s_axis_tvalid,
    output wire          s_axis_tready,
    input  wire          s_axis_tlast,
    output wire [31:0]   status0,
    output wire [31:0]   status_capture
);
    // DEPTH = 1<<AW = 4096, >= the 4032-sample slot.
    localparam integer DEPTH = (1 << AW);

    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;
    reg        cap_en_d = 1'b0;
    reg [31:0] count = 32'd0;
    reg        active = 1'b0;
    reg        done = 1'b0;

    // Capture buffer (simple dual-port: one write port, one read port, aclk).
    // 32-bit wide BRAM: stores the full DUT m_axis word per beat.
    (* ram_style = "block" *) reg [DW-1:0] mem [0:DEPTH-1];
    reg [AW-1:0]  wr_addr = {AW{1'b0}};
    reg           wr_full = 1'b0;
    reg [DW-1:0]  rd_data = {DW{1'b0}};

    wire cap_en = ctrl_sync[1];
    wire start = cap_en && !cap_en_d;
    wire take_sample = active && s_axis_tvalid;
    wire [DW-1:0] sample = s_axis_tdata; // full 32-bit word, not just [15:0]
    // Read index: low 12 bits at ctrl[13:2] (unchanged), high (AW-12) bits at
    // ctrl[18 +: (AW-12)] (player-safe field; held during idle readback). For
    // AW<=12 this collapses back to the legacy contiguous ctrl[2 +: AW].
    wire [AW-1:0] rd_index = (AW <= 12)
        ? ctrl_sync[2 +: AW]
        : { ctrl_sync[18 +: (AW-12)], ctrl_sync[2 +: 12] };
    // ctrl[14]: CIRCULAR throughput-test mode — always-ready, wrap, never stop.
    // Lets the STREAM_TEST measure the TRUE datapath rate (finite mode fills the
    // 4096 BRAM once then back-pressures forever). Golden single-frame capture
    // leaves ctrl[14]=0 (finite, count-based, read-back unaffected).
    wire circular = ctrl_sync[16];   /* CIRCULAR throughput-test mode (free bit 16) */

    // tlast is part of the AXIS contract but capture is count-based; tie it off
    // so the tool does not flag it as unconnected.
    wire unused_tlast = s_axis_tlast;

    assign s_axis_tready = active || circular;
    assign status0 = {done, active, 14'b0, count[15:0]};
    // No sign-extension: data is already 32-bit IQ, return rd_data directly.
    assign status_capture = rd_data;

    // Capture write port and registered read port.
    always @(posedge aclk) begin
        if ((take_sample || (circular && s_axis_tvalid)) && (!wr_full || circular)) begin
            mem[wr_addr] <= sample;
            if (wr_addr == DEPTH - 1) begin
                if (circular) wr_addr <= {AW{1'b0}};  // wrap, keep writing
                else          wr_full <= 1'b1;         // finite: stop
            end else begin
                wr_addr <= wr_addr + 1'b1;
            end
        end
        if (start) begin
            wr_addr <= {AW{1'b0}};
            wr_full <= 1'b0;
        end
        rd_data <= mem[rd_index];
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta <= 32'd0;
            ctrl_sync <= 32'd0;
            cap_en_d <= 1'b0;
            count <= 32'd0;
            active <= 1'b0;
            done <= 1'b0;
        end else begin
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            cap_en_d <= cap_en;

            if (start) begin
                count <= 32'd0;
                active <= 1'b1;
                done <= 1'b0;
            end else if (!cap_en) begin
                active <= 1'b0;
            end else if (take_sample || (circular && s_axis_tvalid)) begin
                if (count == DEPTH - 1 && !circular) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end
                if (count != 32'hffff_ffff) begin
                    count <= count + 32'd1;
                end
            end
        end
    end
endmodule
