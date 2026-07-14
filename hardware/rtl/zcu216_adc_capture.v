`timescale 1ns/1ps

// ADC complex-baseband capture buffer (RF bringup 6c-1, DDC mode).
//
// After the RFDC ADC tile2/blk0 DDC (fine mixer NCO -300 MHz, I/Q, decimation
// 16) the m20_axis bus is 160 bits and carries FIVE complex samples per AXIS
// beat (Xilinx RFDC IQ packing, per sample lane = {Q[15:0], I[15:0]};
// samples 0..4 ascending):
//   s_axis_tdata[ 31:  0] = sample0 = {Q0, I0}
//   s_axis_tdata[ 63: 32] = sample1 = {Q1, I1}
//   s_axis_tdata[ 95: 64] = sample2 = {Q2, I2}
//   s_axis_tdata[127: 96] = sample3 = {Q3, I3}
//   s_axis_tdata[159:128] = sample4 = {Q4, I4}
// Complex rate = 2457.6/16 = 153.6 Msps; AXIS word rate (ADC2_Fabric_Freq)
// = 30.72 MHz, so tvalid is intermittent on the 307.2 MHz clk_adc2.
//
// Storage: FIVE independent single-port BRAM banks (one per complex-sample
// lane), each written once per valid beat at address = beat counter. This is
// fully BRAM-inferrable (single write port, simple incrementing address) and
// records all 5 lanes in the same cycle with no draining FSM.
//
// Readback (32-bit GPIO status_capture): the index ctrl[2 +: AW] is split
//   bank = index[BANK_AW +: 3]   (lane 0..4)
//   addr = index[0 +: BANK_AW]   (beat 0..BEATS-1)
// with BANK_AW = 10 (BEATS = 1024, power of 2 so HW uses bit-slicing, no
// divide). status_capture returns the {Q,I} word for (bank, addr). Offline:
//   complex sample s = I + jQ  at time index (addr*SPB + bank)
// reconstructed at fs = 153.6 Msps over the contiguous +/-76.8 MHz baseband.
//
// 1024 beats * 5 = 5120 complex samples captured (~33 us at 153.6 Msps), ample
// for an OFDM-band FFT. The legacy real-only status0..3 stats track lane0's I.
module zcu216_adc_capture #(
    parameter integer DEPTH = 8192,                 // legacy (unused); kept so
                                                    // the BD wrapper's named
                                                    // override still resolves
    parameter integer AW    = 13                    // readback index width
) (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  ctrl,
    input  wire [159:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    output wire [31:0]  status0,
    output wire [31:0]  status1,
    output wire [31:0]  status2,
    output wire [31:0]  status3,
    output wire [31:0]  status_capture
);
    localparam integer SPB     = 5;                 // complex samples per beat
    localparam integer BANK_AW = 10;                // beats per bank = 1024
    localparam integer BEATS   = (1 << BANK_AW);    // 1024 beats stored

    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;
    reg        cap_en_d = 1'b0;
    reg [31:0] count = 32'd0;        // beats captured
    reg [15:0] max_abs = 16'd0;
    reg [15:0] first_sample = 16'd0;
    reg signed [15:0] min_sample = 16'sh7fff;
    reg signed [15:0] max_sample = -16'sh8000;
    reg [15:0] pos_count = 16'd0;
    reg [15:0] neg_count = 16'd0;
    reg [31:0] sign_changes = 32'd0;
    reg        active = 1'b0;
    reg        done = 1'b0;
    reg        saw_nonzero = 1'b0;
    reg        overflow = 1'b0;
    reg        saw_sign_change = 1'b0;
    reg        clipping = 1'b0;
    reg        last_sign = 1'b0;
    reg        last_sign_valid = 1'b0;

    // Five BRAM banks (one per complex-sample lane).
    (* ram_style = "block" *) reg [31:0] bank0 [0:BEATS-1];
    (* ram_style = "block" *) reg [31:0] bank1 [0:BEATS-1];
    (* ram_style = "block" *) reg [31:0] bank2 [0:BEATS-1];
    (* ram_style = "block" *) reg [31:0] bank3 [0:BEATS-1];
    (* ram_style = "block" *) reg [31:0] bank4 [0:BEATS-1];
    reg [31:0] rd_data = 32'd0;

    wire cap_en = ctrl_sync[1];
    wire start = cap_en && !cap_en_d;
    wire take_sample = active && s_axis_tvalid;
    wire signed [15:0] sample = s_axis_tdata[15:0];   // lane0 I, for stats

    wire [AW-1:0]      rd_index = ctrl_sync[2 +: AW];
    wire [2:0]         rd_bank  = rd_index[BANK_AW +: 3];
    wire [BANK_AW-1:0] rd_addr  = rd_index[0 +: BANK_AW];
    wire [BANK_AW-1:0] wr_addr  = count[BANK_AW-1:0];

    assign s_axis_tready = active;
    assign status0 = {done, active, saw_nonzero, overflow, saw_sign_change,
                      clipping, 10'd0, count[15:0]};
    assign status1 = {max_abs, first_sample};
    assign status2 = sign_changes;
    assign status3 = {min_sample[15:0], max_sample[15:0]};
    assign status_capture = rd_data;

    function [15:0] abs16;
        input signed [15:0] value;
        begin
            abs16 = value[15] ? (~value + 16'd1) : value;
        end
    endfunction
    wire [15:0] sample_abs = abs16(sample);

    wire wr_en = take_sample && (count < BEATS);

    // Write the five lanes in one cycle to their respective banks.
    always @(posedge aclk) begin
        if (wr_en) begin
            bank0[wr_addr] <= s_axis_tdata[ 31:  0];
            bank1[wr_addr] <= s_axis_tdata[ 63: 32];
            bank2[wr_addr] <= s_axis_tdata[ 95: 64];
            bank3[wr_addr] <= s_axis_tdata[127: 96];
            bank4[wr_addr] <= s_axis_tdata[159:128];
        end
    end

    // Registered readback mux over the five banks.
    reg [31:0] rd0, rd1, rd2, rd3, rd4;
    always @(posedge aclk) begin
        rd0 <= bank0[rd_addr];
        rd1 <= bank1[rd_addr];
        rd2 <= bank2[rd_addr];
        rd3 <= bank3[rd_addr];
        rd4 <= bank4[rd_addr];
    end
    reg [2:0] rd_bank_d;
    always @(posedge aclk) rd_bank_d <= rd_bank;
    always @(*) begin
        case (rd_bank_d)
            3'd0:    rd_data = rd0;
            3'd1:    rd_data = rd1;
            3'd2:    rd_data = rd2;
            3'd3:    rd_data = rd3;
            default: rd_data = rd4;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta <= 32'd0;
            ctrl_sync <= 32'd0;
            cap_en_d <= 1'b0;
            count <= 32'd0;
            max_abs <= 16'd0;
            first_sample <= 16'd0;
            min_sample <= 16'sh7fff;
            max_sample <= -16'sh8000;
            pos_count <= 16'd0;
            neg_count <= 16'd0;
            sign_changes <= 32'd0;
            active <= 1'b0;
            done <= 1'b0;
            saw_nonzero <= 1'b0;
            overflow <= 1'b0;
            saw_sign_change <= 1'b0;
            clipping <= 1'b0;
            last_sign <= 1'b0;
            last_sign_valid <= 1'b0;
        end else begin
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            cap_en_d <= cap_en;

            if (start) begin
                count <= 32'd0;
                max_abs <= 16'd0;
                first_sample <= 16'd0;
                min_sample <= 16'sh7fff;
                max_sample <= -16'sh8000;
                pos_count <= 16'd0;
                neg_count <= 16'd0;
                sign_changes <= 32'd0;
                active <= 1'b1;
                done <= 1'b0;
                saw_nonzero <= 1'b0;
                overflow <= 1'b0;
                saw_sign_change <= 1'b0;
                clipping <= 1'b0;
                last_sign <= 1'b0;
                last_sign_valid <= 1'b0;
            end else if (!cap_en) begin
                active <= 1'b0;
            end else if (take_sample) begin
                if (count == 32'd0)      first_sample <= sample;
                if (sample_abs > max_abs) max_abs <= sample_abs;
                if (sample < min_sample) min_sample <= sample;
                if (sample > max_sample) max_sample <= sample;
                if (sample_abs != 16'd0) saw_nonzero <= 1'b1;
                if (sample_abs >= 16'd32000) clipping <= 1'b1;
                if (sample[15]) begin
                    if (neg_count != 16'hffff) neg_count <= neg_count + 16'd1;
                end else begin
                    if (pos_count != 16'hffff) pos_count <= pos_count + 16'd1;
                end
                if (last_sign_valid && sample[15] != last_sign) begin
                    saw_sign_change <= 1'b1;
                    if (sign_changes != 32'hffff_ffff) begin
                        sign_changes <= sign_changes + 32'd1;
                    end else begin
                        overflow <= 1'b1;
                    end
                end
                last_sign <= sample[15];
                last_sign_valid <= 1'b1;

                if (count == BEATS - 1) begin
                    active <= 1'b0;
                    done <= 1'b1;
                end
                if (count != 32'hffff_ffff) begin
                    count <= count + 32'd1;
                end else begin
                    overflow <= 1'b1;
                end
            end
        end
    end
endmodule
