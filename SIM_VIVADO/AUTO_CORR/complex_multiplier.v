// 간단 complex multiply: (ar + j*ai) * (br + j*bi)
// pr = Re, pi = Im
module complex_multiplier (
    input              clk,
    input      signed [15:0] ar,
    input      signed [15:0] ai,
    input      signed [15:0] br,
    input      signed [15:0] bi,
    output reg signed [31:0] pr,
    output reg signed [31:0] pi
);

    always @(posedge clk) begin
        // (ar + jai) * (br + jbi)
        // = (ar*br - ai*bi) + j(ar*bi + ai*br)
        pr <= ar * br - ai * bi;
        pi <= ar * bi + ai * br;
    end

endmodule

