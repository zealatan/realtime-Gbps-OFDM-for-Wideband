`timescale 1ns/1ps

module zcu216_adc_activity_stats #(
    parameter integer CAPTURE_WORDS = 32768
) (
    input  wire         aclk,
    input  wire         aresetn,
    input  wire [31:0]  ctrl,
    input  wire [127:0] s_axis_tdata,
    input  wire         s_axis_tvalid,
    output wire         s_axis_tready,
    output wire [31:0]  status0,
    output wire [31:0]  status1,
    output wire [31:0]  status2,
    output wire [31:0]  status3
);
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta = 32'd0;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync = 32'd0;
    reg        cap_en_d = 1'b0;
    reg [31:0] count = 32'd0;
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

    wire cap_en = ctrl_sync[1];
    wire start = cap_en && !cap_en_d;
    wire take_sample = active && s_axis_tvalid;
    wire signed [15:0] sample = s_axis_tdata[15:0];

    assign s_axis_tready = active;
    assign status0 = {done, active, saw_nonzero, overflow, saw_sign_change,
                      clipping, 10'd0, count[15:0]};
    assign status1 = {max_abs, first_sample};
    assign status2 = sign_changes;
    assign status3 = {min_sample[15:0], max_sample[15:0]};

    function [15:0] abs16;
        input signed [15:0] value;
        begin
            abs16 = value[15] ? (~value + 16'd1) : value;
        end
    endfunction

    wire [15:0] sample_abs = abs16(sample);

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
                if (count == 32'd0) begin
                    first_sample <= sample;
                end
                if (sample_abs > max_abs) begin
                    max_abs <= sample_abs;
                end
                if (sample < min_sample) begin
                    min_sample <= sample;
                end
                if (sample > max_sample) begin
                    max_sample <= sample;
                end
                if (sample_abs != 16'd0) begin
                    saw_nonzero <= 1'b1;
                end
                if (sample_abs >= 16'd32000) begin
                    clipping <= 1'b1;
                end
                if (sample[15]) begin
                    if (neg_count != 16'hffff) begin
                        neg_count <= neg_count + 16'd1;
                    end
                end else begin
                    if (pos_count != 16'hffff) begin
                        pos_count <= pos_count + 16'd1;
                    end
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

                if (count == CAPTURE_WORDS - 1) begin
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
