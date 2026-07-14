`timescale 1ns/1ps

module tb_moving_avg();

    // 1. 파라미터 및 신호 정의
    parameter DATA_WIDTH   = 32;
    parameter WINDOW_SHIFT = 5;   // N = 2^5 = 32
    parameter WINDOW_SIZE  = 1 << WINDOW_SHIFT;
    parameter RAM_LATENCY  = 2;
    parameter CLK_PERIOD   = 4.07; // 245.76MHz 기준

    reg                     clock;
    reg                     reset;
    reg                     enable;
    reg  signed [DATA_WIDTH-1:0] data_in;
    reg                     input_strobe;

    wire signed [63:0]      data_out;
    wire                    output_strobe;

    // 2. 검증용 내부 변수
    reg signed [DATA_WIDTH-1:0] golden_buffer [0:WINDOW_SIZE-1]; 
    integer                     buf_ptr;
    reg signed [63:0]           expected_sum;
    reg signed [63:0]           expected_avg;
    integer                     error_cnt;
    integer                     i;

    // 3. DUT 인스턴스화
    moving_avg_optimized #(
        .DATA_WIDTH(DATA_WIDTH),
        .WINDOW_SHIFT(WINDOW_SHIFT),
        .RAM_LATENCY(RAM_LATENCY)
    ) dut (
        .clock(clock), .reset(reset), .enable(enable),
        .data_in(data_in), .input_strobe(input_strobe),
        .data_out(data_out), .output_strobe(output_strobe)
    );

    // 4. 클럭 생성
    initial clock = 0;
    always #(CLK_PERIOD/2) clock = ~clock;

    // 5. Golden Model 로직
    always @(posedge clock) begin
        if (reset) begin
            expected_sum <= 0;
            buf_ptr      <= 0;
            for (i=0; i<WINDOW_SIZE; i=i+1) golden_buffer[i] = 0;
        end else if (input_strobe && enable) begin
            expected_sum <= expected_sum + $signed(data_in) - $signed(golden_buffer[buf_ptr]);
            golden_buffer[buf_ptr] <= data_in;
            buf_ptr <= (buf_ptr + 1) % WINDOW_SIZE;
        end
    end

    // 6. 메인 테스트 시나리오
    initial begin
        // 초기화
        reset = 1; enable = 0; data_in = 0; input_strobe = 0; error_cnt = 0;
        #(CLK_PERIOD * 20);
        reset = 0; enable = 1;
        #(CLK_PERIOD * 10);

        // [TC1] 계단 입력
        $display("\n[TC1] Constant Input: 100");
        repeat(64) send_data(32'd100);

        // [TC2] 경사 입력
        $display("\n[TC2] Ramp Input: 10, 20, 30...");
        for (i=1; i<=40; i=i+1) send_data(i * 10);

        // [TC3] 랜덤 부호
        $display("\n[TC3] Random Signed Input");
        repeat(100) send_data($random);

        // [TC4] 큰 음수 값
        $display("\n[TC4] Large Negative Peak: -10000");
        repeat(32) send_data(-32'd10000);

        #(CLK_PERIOD * 100);

        // 최종 결과 보고
        if (error_cnt == 0) begin
            $display("\n**************************************");
            $display("   VERIFICATION SUCCESSFUL! (12-bit)  ");
            $display("**************************************");
        end else begin
            $display("\n**************************************");
            $display("   VERIFICATION FAILED! Errors: %d    ", error_cnt);
            $display("**************************************");
        end

        $finish;
    end

    // 7. 자동 비교 및 에러 체크 (수정된 부분)
    always @(posedge clock) begin
        if (output_strobe) begin
            expected_avg = expected_sum >>> 12; 
            
            // 비교 로직: 오차가 1보다 크면 에러 출력
            if (abs_diff(data_out, expected_avg) > 64'd1) begin
                $display("[ERR] Time:%t | RTL:%d | Exp:%d | Diff:%d", 
                          $time, $signed(data_out), expected_avg, $signed(data_out) - expected_avg);
                error_cnt = error_cnt + 1;
            end else begin
                $display("[OK]  Time:%t | RTL:%d | Exp:%d", $time, $signed(data_out), expected_avg);
            end
        end
    end

    // 데이터 주입 태스크
    task send_data(input signed [DATA_WIDTH-1:0] val);
        begin
            @(posedge clock);
            input_strobe = 1; data_in = val;
            @(posedge clock);
            input_strobe = 0; data_in = 0;
            repeat(1) @(posedge clock);
        end
    endtask

    // 절대값 차이 계산 함수
    function [63:0] abs_diff(input signed [63:0] a, input signed [63:0] b);
        begin
            if (a > b) abs_diff = a - b;
            else abs_diff = b - a;
        end
    endfunction

endmodule
