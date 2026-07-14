`timescale 1ns/1ps
`default_nettype none

module phase_rotator_9b #
(
    parameter LUT_DEPTH = 512,
    parameter DELAY_T   = 2
)
(
    input  wire               clk,
    input  wire               rst_n,

    input  wire [8:0]         phase_cordic_9bit,
    input  wire               phase_strobe,

    input  wire signed [15:0] in_I,
    input  wire signed [15:0] in_Q,

    output reg  signed [63:0] rot_out_I,
    output reg  signed [63:0] rot_out_Q,
    output reg                output_strobe
);

    // ----------------------------------------------------------------
    // LUT memory
    // rot_data = {rot_I, rot_Q}
    // ----------------------------------------------------------------
    reg [31:0] rot_lut [0:LUT_DEPTH-1];

    initial begin
        $readmemb("rot_lut.mif", rot_lut);
    end

    // ----------------------------------------------------------------
    // Phase accumulator / rotator address
    // ----------------------------------------------------------------
    reg [8:0] phase_acc;
    reg [8:0] rot_addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_acc <= 9'd0;
            rot_addr  <= 9'd0;
        end
        else if (phase_strobe) begin
            phase_acc <= phase_acc + phase_cordic_9bit;
            rot_addr  <= phase_acc + phase_cordic_9bit;
        end
    end

    // ----------------------------------------------------------------
    // LUT output
    // ----------------------------------------------------------------
    reg [31:0] rot_data;
    reg signed [15:0] rot_I;
    reg signed [15:0] rot_Q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rot_data <= 32'd0;
            rot_I    <= 16'sd0;
            rot_Q    <= 16'sd0;
        end
        else begin
            rot_data <= rot_lut[rot_addr];
            rot_I    <= rot_lut[rot_addr][31:16];
            rot_Q    <= rot_lut[rot_addr][15:0];
        end
    end

    // ----------------------------------------------------------------
    // delayT for input I/Q
    // ----------------------------------------------------------------
    reg signed [15:0] in_I_d [0:DELAY_T-1];
    reg signed [15:0] in_Q_d [0:DELAY_T-1];
    reg               strobe_d [0:DELAY_T-1];

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < DELAY_T; k = k + 1) begin
                in_I_d[k]  <= 16'sd0;
                in_Q_d[k]  <= 16'sd0;
                strobe_d[k] <= 1'b0;
            end
        end
        else begin
            in_I_d[0]   <= in_I;
            in_Q_d[0]   <= in_Q;
            strobe_d[0] <= phase_strobe;

            for (k = 1; k < DELAY_T; k = k + 1) begin
                in_I_d[k]   <= in_I_d[k-1];
                in_Q_d[k]   <= in_Q_d[k-1];
                strobe_d[k] <= strobe_d[k-1];
            end
        end
    end

    wire signed [15:0] in_I_delayed;
    wire signed [15:0] in_Q_delayed;
    wire               input_valid_delayed;

    assign in_I_delayed      = in_I_d[DELAY_T-1];
    assign in_Q_delayed      = in_Q_d[DELAY_T-1];
    assign input_valid_delayed = strobe_d[DELAY_T-1];

    // ----------------------------------------------------------------
    // Complex multiply
    // (in_I + j*in_Q) * (rot_I + j*rot_Q)
    //
    // out_I = in_I*rot_I - in_Q*rot_Q
    // out_Q = in_I*rot_Q + in_Q*rot_I
    // ----------------------------------------------------------------
    reg signed [31:0] mult_ii;
    reg signed [31:0] mult_qq;
    reg signed [31:0] mult_iq;
    reg signed [31:0] mult_qi;

    reg               mult_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mult_ii    <= 32'sd0;
            mult_qq    <= 32'sd0;
            mult_iq    <= 32'sd0;
            mult_qi    <= 32'sd0;
            mult_valid <= 1'b0;
        end
        else begin
            mult_ii    <= $signed(in_I_delayed) * $signed(rot_I);
            mult_qq    <= $signed(in_Q_delayed) * $signed(rot_Q);
            mult_iq    <= $signed(in_I_delayed) * $signed(rot_Q);
            mult_qi    <= $signed(in_Q_delayed) * $signed(rot_I);
            mult_valid <= input_valid_delayed;
        end
    end

    // ----------------------------------------------------------------
    // Output register
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rot_out_I    <= 64'sd0;
            rot_out_Q    <= 64'sd0;
            output_strobe <= 1'b0;
        end
        else begin
            rot_out_I    <= $signed(mult_ii) - $signed(mult_qq);
            rot_out_Q    <= $signed(mult_iq) + $signed(mult_qi);
            output_strobe <= mult_valid;
        end
    end

endmodule

`default_nettype wire
