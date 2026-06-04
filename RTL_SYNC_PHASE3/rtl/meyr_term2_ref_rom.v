`timescale 1ns/1ps

// Meyr term2 reference ROM — Step 32
//
// Provides term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])  for j=0..NSC-1.
//
// C-reference (ref/receiver.c lines 527-528):
//   crossCorrTerm2I[j] = mUI[j+CP_LEN]*goldUI[j+CP_LEN] + mUQ[j+CP_LEN]*goldUQ[j+CP_LEN]
//   crossCorrTerm2Q[j] = -mUI[j+CP_LEN]*goldUQ[j+CP_LEN] + mUQ[j+CP_LEN]*goldUI[j+CP_LEN]
//
// STEP 32 STATUS:
//   Real mU/goldU-derived term2 ROM: PENDING.
//   In ref/receiver.c, mUI/mUQ/goldUI/goldUQ are passed as external parameters to
//   synchronization() and carrierFreqOffsetEstMeyr(). Their generation code is not present
//   in ref/receiver.c. Extracting exact values requires the full transmitter/generator
//   source, which is outside the current scope.
//
//   USE_SYNTHETIC_FALLBACK=1 (default): uses the same XOR-shift32 PRNG ROM as
//   meyr_integer_cfo_core.v (seed 32'hCAFE_B0BB). This ensures that the Step 32
//   estimator top and testbench are internally consistent for shift-recovery tests.
//
//   To replace with real mU/goldU data (Step 33+):
//     1. Generate rom_i[] and rom_q[] from the actual PSS/SSS sequences using a
//        Python/C script: term2_i[j] = mU_i[j+CP_LEN]*goldU_i[j+CP_LEN] + mU_q*goldU_q
//     2. Load via $readmemh or localparam array.
//     3. Set USE_SYNTHETIC_FALLBACK=0 and remove the PRNG initial block.
//
// Read latency: 1 clock (registered output).

module meyr_term2_ref_rom #(
    parameter integer NSC                   = 256,
    parameter integer PROD_WIDTH            = 32,
    parameter integer USE_SYNTHETIC_FALLBACK = 1
)(
    input  wire                          aclk,
    input  wire [7:0]                    addr,
    output reg  signed [PROD_WIDTH-1:0]  term2_i,
    output reg  signed [PROD_WIDTH-1:0]  term2_q
);

    reg signed [PROD_WIDTH-1:0] rom_i [0:NSC-1];
    reg signed [PROD_WIDTH-1:0] rom_q [0:NSC-1];

    // Synthetic fallback: XOR-shift32 PRNG, seed 32'hCAFE_B0BB.
    // Sequence matches meyr_integer_cfo_core.v internal term2 ROM exactly.
    generate
        if (USE_SYNTHETIC_FALLBACK) begin : gen_prng
            integer _j;
            reg [31:0] _seed;
            initial begin
                _seed = 32'hCAFE_B0BB;
                for (_j = 0; _j < NSC; _j = _j + 1) begin
                    _seed = _seed ^ (_seed << 13);
                    _seed = _seed ^ (_seed >> 17);
                    _seed = _seed ^ (_seed << 5);
                    rom_i[_j] = {{(PROD_WIDTH-8){_seed[7]}}, _seed[7:0]};
                    _seed = _seed ^ (_seed << 13);
                    _seed = _seed ^ (_seed >> 17);
                    _seed = _seed ^ (_seed << 5);
                    rom_q[_j] = {{(PROD_WIDTH-8){_seed[7]}}, _seed[7:0]};
                end
            end
        end
    endgenerate

    // Registered read (1-clock latency)
    always @(posedge aclk) begin
        term2_i <= rom_i[addr];
        term2_q <= rom_q[addr];
    end

endmodule
