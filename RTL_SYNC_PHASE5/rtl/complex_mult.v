`timescale 1ns/1ps

module complex_mult
(
    input clock,
    input enable,
    input reset,

    input  signed [15:0] a_i, // Real part of A
    input  signed [15:0] a_q, // Imag part of A
    input  signed [15:0] b_i, // Real part of B
    input  signed [15:0] b_q, // Imag part of B
    input  input_strobe,

    output reg signed [31:0] p_i, // Real part of Result
    output reg signed [31:0] p_q, // Imag part of Result
    output output_strobe
);

    // Pipeline Latency 설정
    // 1(Input Reg) + 1(Mult Reg) + 1(Add/Sub Reg) = 3 cycles
    localparam integer LAT = 3;

    // 1단계: 입력 래칭 레지스터
    reg signed [15:0] ar, ai, br, bi;
    
    // 2단계: 곱셈 결과 저장 레지스터 (DSP 내부 파이프라인 활용 유도)
    reg signed [31:0] mult_rr, mult_ii, mult_ri, mult_ir;

    // Strobe 신호 지연 파이프라인
    reg [LAT-1:0] stb_pipe;

    // 출력 Strobe는 파이프라인의 마지막 비트
    assign output_strobe = stb_pipe[LAT-1];

    always @(posedge clock) begin
        if (reset) begin
            ar <= 0; ai <= 0; br <= 0; bi <= 0;
            mult_rr <= 0; mult_ii <= 0; mult_ri <= 0; mult_ir <= 0;
            p_i <= 0; p_q <= 0;
            stb_pipe <= 0;
        end else if (enable) begin
            // 1. Strobe Pipeline
            stb_pipe <= {stb_pipe[LAT-2:0], input_strobe};

            // 2. Stage 1: Input Latch (Strobe가 뜰 때만 갱신하거나 항상 갱신 가능)
            // 245MHz에서는 항상 갱신하는 것이 Fan-out 관리에 더 유리할 수 있습니다.
            if (input_strobe) begin
                ar <= a_i;
                ai <= a_q;
                br <= b_i;
                bi <= b_q;
            end

            // 3. Stage 2: Multiplication
            // (ar+jai)*(br+jbi)의 각 항을 계산하여 레지스터에 저장
            mult_rr <= ar * br;
            mult_ii <= ai * bi;
            mult_ri <= ar * bi;
            mult_ir <= ai * br;

            // 4. Stage 3: Addition / Subtraction (Final Output)
            // 이전 단계의 결과를 더하고 빼서 최종 결과 산출
            p_i <= mult_rr - mult_ii;
            p_q <= mult_ri + mult_ir;
        end
    end

endmodule
