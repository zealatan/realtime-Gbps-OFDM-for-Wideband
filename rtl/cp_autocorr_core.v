`timescale 1ns/1ps

// cp_autocorr_core: Van De Beek CP autocorrelation engine.
//
// For each lag m in [0, NSC-1], accumulates CP_LEN taps:
//   P_I[m] += I_a*I_b + Q_a*Q_b        (Re(conj(r[m+k]) * r[m+k+NSC]))
//   P_Q[m] += -I_a*Q_b + Q_a*I_b       (Im(conj(r[m+k]) * r[m+k+NSC]))
//   E[m]   += I_a^2 + Q_a^2 + I_b^2 + Q_b^2
// where A = r[base+m+k], B = r[base+m+k+NSC].
//
// Buffer read latency: 1-clock registered (matches iq_frame_buffer rd_en/rd_addr/rd_data).
// Each tap requires 4 clock cycles (FETCH_A + LATCH_A + FETCH_B + ACCUM).
// Total cycles: 4 * CP_LEN * NSC + 1 (~32769 at defaults).
//
// Results are stored in three 32-bit register arrays (NSC entries each).
// result_rd_addr is read combinatorially.
//
// Parameters:
//   NSC          Number of lags (= FFT size, default 256)
//   CP_LEN       Cyclic prefix length / taps per lag (default 32)
//   ADDR_WIDTH   Buffer address width (default 12)
//   ACC_WIDTH    Internal accumulator width (default 40)
//   INDEX_WIDTH  Lag index width, must be >= log2(NSC) (default 9)
//   RESULT_WIDTH Result word width — lower RESULT_WIDTH bits of accumulator (default 32)

module cp_autocorr_core #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32
) (
    input  wire                            aclk,
    input  wire                            aresetn,

    // ---- Control ----
    input  wire                            start,
    input  wire [ADDR_WIDTH-1:0]           base_addr,
    output reg                             done,
    output reg                             busy,

    // ---- Buffer read port (1-clock registered latency) ----
    output reg  [ADDR_WIDTH-1:0]           buf_rd_addr,
    output reg                             buf_rd_en,
    input  wire signed [15:0]              buf_rd_data_I,
    input  wire signed [15:0]              buf_rd_data_Q,

    // ---- Result read port (combinatorial, zero-latency) ----
    input  wire [INDEX_WIDTH-1:0]          result_rd_addr,
    output wire signed [RESULT_WIDTH-1:0]  result_autocorr_I,
    output wire signed [RESULT_WIDTH-1:0]  result_autocorr_Q,
    output wire        [RESULT_WIDTH-1:0]  result_norm_E
);

    // -----------------------------------------------------------------------
    // States
    // -----------------------------------------------------------------------
    localparam [2:0]
        S_IDLE    = 3'd0,
        S_FETCH_A = 3'd1,   // wait 1 cycle: buffer registers addr_A
        S_LATCH_A = 3'd2,   // A valid; latch A; present addr_B
        S_FETCH_B = 3'd3,   // wait 1 cycle: buffer registers addr_B
        S_ACCUM   = 3'd4,   // B valid; compute MAC; advance tap/lag
        S_DONE    = 3'd5;

    // Verilog-2001: ADDR_WIDTH'(NSC) is SystemVerilog-only cast syntax.
    // Use a sized localparam instead so packaged IP synthesis accepts Verilog type.
    localparam [ADDR_WIDTH-1:0] LP_NSC_B = NSC;

    reg [2:0]             state;
    reg [INDEX_WIDTH-1:0] lag;   // current lag index  m: 0..NSC-1
    reg [5:0]             tap;   // current tap index  k: 0..CP_LEN-1

    // Latched sample A = r[base + m + k]
    reg signed [15:0] a_I, a_Q;

    // Per-lag accumulators (reset at the start of each lag)
    reg signed [ACC_WIDTH-1:0] acc_P_I;
    reg signed [ACC_WIDTH-1:0] acc_P_Q;
    reg        [ACC_WIDTH-1:0] acc_E;

    // Result storage: NSC entries × RESULT_WIDTH bits
    reg signed [RESULT_WIDTH-1:0] mem_P_I [0:NSC-1];
    reg signed [RESULT_WIDTH-1:0] mem_P_Q [0:NSC-1];
    reg        [RESULT_WIDTH-1:0] mem_E   [0:NSC-1];

    // Blocking temporaries — synthesize as combinatorial wires inside always
    reg signed [32:0]          prod_PI;  // 33-bit to prevent overflow on sum of two 32-bit products
    reg signed [32:0]          prod_PQ;
    reg        [32:0]          prod_E;   // sum of 4 squares; max 4*(2^15)^2 = 2^32 needs 33 bits
    reg signed [ACC_WIDTH-1:0] new_P_I;
    reg signed [ACC_WIDTH-1:0] new_P_Q;
    reg        [ACC_WIDTH-1:0] new_E;

    // Address of A and B for the current lag/tap (combinatorial)
    wire [ADDR_WIDTH-1:0] addr_A =
        base_addr
        + {{(ADDR_WIDTH-INDEX_WIDTH){1'b0}}, lag}
        + {{(ADDR_WIDTH-6){1'b0}},           tap};
    wire [ADDR_WIDTH-1:0] addr_B = addr_A + LP_NSC_B;

    // Combinatorial result read
    assign result_autocorr_I = mem_P_I[result_rd_addr];
    assign result_autocorr_Q = mem_P_Q[result_rd_addr];
    assign result_norm_E     = mem_E[result_rd_addr];

    integer i;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            buf_rd_en   <= 1'b0;
            buf_rd_addr <= {ADDR_WIDTH{1'b0}};
            lag         <= {INDEX_WIDTH{1'b0}};
            tap         <= 6'd0;
            a_I         <= 16'sd0;
            a_Q         <= 16'sd0;
            acc_P_I     <= {ACC_WIDTH{1'b0}};
            acc_P_Q     <= {ACC_WIDTH{1'b0}};
            acc_E       <= {ACC_WIDTH{1'b0}};
            for (i = 0; i < NSC; i = i + 1) begin
                mem_P_I[i] <= {RESULT_WIDTH{1'b0}};
                mem_P_Q[i] <= {RESULT_WIDTH{1'b0}};
                mem_E[i]   <= {RESULT_WIDTH{1'b0}};
            end
        end else begin
            done <= 1'b0;

            case (state)

                // --------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy) begin
                        lag     <= {INDEX_WIDTH{1'b0}};
                        tap     <= 6'd0;
                        acc_P_I <= {ACC_WIDTH{1'b0}};
                        acc_P_Q <= {ACC_WIDTH{1'b0}};
                        acc_E   <= {ACC_WIDTH{1'b0}};
                        busy        <= 1'b1;
                        buf_rd_addr <= base_addr;   // addr_A for lag=0, tap=0
                        buf_rd_en   <= 1'b1;
                        state       <= S_FETCH_A;
                    end
                end

                // --------------------------------------------------------
                // Wait 1 cycle so the buffer can register addr_A.
                // --------------------------------------------------------
                S_FETCH_A: begin
                    state <= S_LATCH_A;
                end

                // --------------------------------------------------------
                // buf_rd_data now holds r[base + m + k] = sample A.
                // Latch A and issue the read for sample B.
                // --------------------------------------------------------
                S_LATCH_A: begin
                    a_I         <= buf_rd_data_I;
                    a_Q         <= buf_rd_data_Q;
                    buf_rd_addr <= addr_B;
                    state       <= S_FETCH_B;
                end

                // --------------------------------------------------------
                // Wait 1 cycle so the buffer can register addr_B.
                // --------------------------------------------------------
                S_FETCH_B: begin
                    state <= S_ACCUM;
                end

                // --------------------------------------------------------
                // buf_rd_data now holds r[base + m + k + NSC] = sample B.
                // Compute conj(A)*B MAC and power normalization.
                // --------------------------------------------------------
                S_ACCUM: begin
                    // Products (blocking: combinatorial within this clock)
                    prod_PI = ($signed(a_I) * $signed(buf_rd_data_I))
                            + ($signed(a_Q) * $signed(buf_rd_data_Q));
                    prod_PQ = -($signed(a_I) * $signed(buf_rd_data_Q))
                            + ($signed(a_Q) * $signed(buf_rd_data_I));
                    prod_E  = ($signed(a_I)           * $signed(a_I))
                            + ($signed(a_Q)           * $signed(a_Q))
                            + ($signed(buf_rd_data_I) * $signed(buf_rd_data_I))
                            + ($signed(buf_rd_data_Q) * $signed(buf_rd_data_Q));

                    // Sign-extend 33-bit products to ACC_WIDTH and accumulate
                    new_P_I = acc_P_I + {{(ACC_WIDTH-33){prod_PI[32]}}, prod_PI};
                    new_P_Q = acc_P_Q + {{(ACC_WIDTH-33){prod_PQ[32]}}, prod_PQ};
                    new_E   = acc_E   + {{(ACC_WIDTH-33){1'b0}},        prod_E};

                    if (tap == (CP_LEN - 1)) begin
                        // Last tap for this lag — store result
                        mem_P_I[lag] <= new_P_I[RESULT_WIDTH-1:0];
                        mem_P_Q[lag] <= new_P_Q[RESULT_WIDTH-1:0];
                        mem_E[lag]   <= new_E[RESULT_WIDTH-1:0];

                        acc_P_I <= {ACC_WIDTH{1'b0}};
                        acc_P_Q <= {ACC_WIDTH{1'b0}};
                        acc_E   <= {ACC_WIDTH{1'b0}};
                        tap     <= 6'd0;

                        if (lag == (NSC - 1)) begin
                            // All lags done
                            buf_rd_en <= 1'b0;
                            state     <= S_DONE;
                        end else begin
                            // Advance to first tap of next lag.
                            // Next addr_A = base + (lag+1) + 0 = base + lag + 1
                            // (lag still has its old value at this NB point)
                            lag         <= lag + 1;
                            buf_rd_addr <= base_addr
                                         + {{(ADDR_WIDTH-INDEX_WIDTH){1'b0}}, lag}
                                         + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                            state       <= S_FETCH_A;
                        end
                    end else begin
                        // Advance to next tap of same lag
                        acc_P_I <= new_P_I;
                        acc_P_Q <= new_P_Q;
                        acc_E   <= new_E;
                        tap         <= tap + 1;
                        // Next addr_A = addr_A + 1 (base + lag + tap + 1)
                        buf_rd_addr <= addr_A + {{(ADDR_WIDTH-1){1'b0}}, 1'b1};
                        state       <= S_FETCH_A;
                    end
                end

                // --------------------------------------------------------
                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
