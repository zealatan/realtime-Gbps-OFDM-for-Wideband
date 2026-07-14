`timescale 1ns/1ps

module moving_avg_optimized
#(
    parameter DATA_WIDTH = 32,
    parameter WINDOW_SHIFT = 5,   // N = 32
    parameter RAM_LATENCY = 2     // RAM 읽기 지연
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

// 1. 입력 파이프라인 (RAM 레이턴시 매칭)
// RAM에서 old_data가 나오는 타이밍에 맞춰 현재 data_in을 지연시킴
reg signed [DATA_WIDTH-1:0] data_in_pipe [0:RAM_LATENCY];
reg                         strobe_pipe  [0:RAM_LATENCY];

integer p;
always @(posedge clock) begin
    if (reset) begin
        for (p = 0; p <= RAM_LATENCY; p = p + 1) begin
            data_in_pipe[p] <= 0; strobe_pipe[p] <= 0;
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

// 2. RAM 주소 및 지연 라인
reg [WINDOW_SHIFT-1:0] addr;
wire signed [DATA_WIDTH-1:0] old_data;

always @(posedge clock) begin
    if (reset) addr <= 0;
    else if (enable && input_strobe) addr <= addr + 1;
end

// Dual-port RAM: 동일 주소 참조를 통해 32클럭 지연 구현
ram_2port #(.DWIDTH(DATA_WIDTH), .AWIDTH(WINDOW_SHIFT)) delay_line (
    .clka  (clock), .ena(enable), .wea(input_strobe), .addra(addr), .dia(data_in), .doa(),
    .clkb  (clock), .enb(enable), .web(1'b0),         .addrb(addr), .dob(old_data)
);

// 3. 누적 연산 (Accumulator)
reg signed [63:0] running_sum;
reg               calc_en_d1;



always @(posedge clock) begin
    if (reset) begin
        running_sum <= 64'd0;
        calc_en_d1  <= 1'b0;
    end else if (enable) begin
        // RAM 레이턴시에 맞춰 strobe_pipe[RAM_LATENCY] 시점에 연산 수행
        // old_data와 data_in_pipe[RAM_LATENCY]의 타이밍 동기화
        if (strobe_pipe[RAM_LATENCY-1]) begin
            running_sum <= running_sum + $signed(data_in_pipe[RAM_LATENCY-1]) - $signed(old_data);
        end
        calc_en_d1 <= strobe_pipe[RAM_LATENCY-1];
    end
end

// 4. 최종 출력 (12비트 시프트 적용)
always @(posedge clock) begin
    if (reset) begin
        data_out <= 64'd0;
        output_strobe <= 1'b0;
    end else if (enable) begin
        // 하위 12비트 무시 (오차 흡수 및 스케일 조정)
        data_out <= running_sum >>> 12; 
        output_strobe <= calc_en_d1;
    end
end

endmodule
