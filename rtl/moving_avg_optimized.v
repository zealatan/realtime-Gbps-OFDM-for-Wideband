`timescale 1ns/1ps

module moving_avg_optimized
#(
    parameter DATA_WIDTH = 32,
    parameter WINDOW_SHIFT = 2,   
    parameter RAM_LATENCY = 2     
)
(
    input  wire                   clock,
    input  wire                   reset,
    input  wire                   enable,
    
    input  wire signed [DATA_WIDTH-1:0] data_in,
    input  wire                   input_strobe,

    output reg  signed [63:0]     data_out,
    output reg                    output_strobe
);

localparam WINDOW_SIZE = 1 << WINDOW_SHIFT;
localparam SUM_WIDTH   = DATA_WIDTH + WINDOW_SHIFT;

reg signed [DATA_WIDTH-1:0] data_in_pipe [0:RAM_LATENCY];
reg                         strobe_pipe  [0:RAM_LATENCY];

integer p;
always @(posedge clock) begin
    if (reset) begin
        for (p = 0; p <= RAM_LATENCY; p = p + 1) begin
            data_in_pipe[p] <= 0;
            strobe_pipe[p]  <= 0;
        end
    end else if (enable) begin
        data_in_pipe[0] <= data_in;
        strobe_pipe[0]  <= input_strobe;
        for (p = 1; p <= RAM_LATENCY; p = p + 1) begin
            data_in_pipe[p] <= data_in_pipe[p-1];
            strobe_pipe[p]  <= strobe_pipe[p-1];
        end
    end
end


reg [WINDOW_SHIFT-1:0] addr;
wire signed [DATA_WIDTH-1:0] old_data;

always @(posedge clock) begin
    if (reset) begin
        addr <= 0;
    end else if (enable && input_strobe) begin
        addr <= addr + 1;
    end
end


ram_2port #(.DWIDTH(DATA_WIDTH), .AWIDTH(WINDOW_SHIFT)) delay_line (
    .clka  (clock),
    .ena   (enable),
    .wea   (input_strobe),
    .addra (addr),
    .dia   (data_in),
    .doa   (),
    .clkb  (clock),
    .enb   (enable),
    .web   (1'b0),
    .addrb (addr),
    .dob   (old_data)
);

reg signed [DATA_WIDTH:0]    diff_reg;    
reg signed [SUM_WIDTH-1:0]   running_sum; 
reg                          calc_en;



always @(posedge clock) begin

    if (reset) begin

        diff_reg    <= 0;

        running_sum <= 0;

        calc_en     <= 0;

    end else if (enable) begin

        if (strobe_pipe[RAM_LATENCY-1]) begin

            diff_reg <= data_in_pipe[RAM_LATENCY-1] - old_data;

        end



        calc_en <= strobe_pipe[RAM_LATENCY-1];

        if (calc_en) begin

            running_sum <= running_sum + diff_reg;

        end

    end

end

always @(posedge clock) begin
    if (reset) begin
        data_out <= 0;
        output_strobe <= 0;
    end else if (enable) begin
        data_out <= $signed(running_sum);
//        data_out <= $signed(running_sum + 64'sd2048) >>> 12;  //round
        output_strobe <= calc_en;
    end
end


endmodule
