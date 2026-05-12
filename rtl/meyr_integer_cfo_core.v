`timescale 1ns/1ps

// Meyr-based integer CFO estimator core — Step 31
//
// Consumes NSC term1 samples streamed by the host (representing
// PSS_FFT[j]*conj(SSS_FFT[j]) in the full pipeline), correlates them
// against an internal static term2 reference ROM, and reports the
// argmax peak index and its implied intCFO.
//
// term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])   (C reference formula)
//
// STEP 31 LIMITATION: term2 is a synthetic XOR-shift32 PRNG ROM (seed
// 32'hCAFE_B0BB).  The testbench mirrors the same sequence.  Replace with
// the real mU/goldU-derived ROM in Step 32.
//
// Correlation (linear, direct-lag):
//   For lag p in 0..LAG_COUNT-1:
//     corr[p] = sum_{n=n_start..n_end} term1[n+lag] * conj(term2[n])
//   where lag = p - (NSC-1) = p - 255.
//
// Peak decode:  intCFO = peak_index - (NSC-1) = peak_index - 255
//
// Score is computed as |corr_i|^2 + |corr_q|^2.
// Step 31 note: lower 32 bits of 56-bit accumulator used for squaring;
// safe for synthetic 8-bit-in-32-bit data.  Scale for real FFT data.
//
// Protocol (matches project convention):
//   - Pulse start=1 one clock to begin.  start while busy sets error.
//   - Stream NSC term1 samples with term1_valid=1; term1_ready gates writes.
//   - term1_index is used as the RAM write address.
//   - After all NSC samples are accepted, correlation runs automatically.
//   - done pulses for exactly one clock at completion.
//   - busy deasserts simultaneously with done.
//   - error is sticky; cleared only by aresetn.

module meyr_integer_cfo_core #(
    parameter integer NSC         = 256,
    parameter integer IQ_WIDTH    = 16,
    parameter integer PROD_WIDTH  = 32,
    parameter integer ACC_WIDTH   = 56,
    parameter integer SCORE_WIDTH = 64,
    parameter integer INDEX_WIDTH = 9
)(
    input  wire                          aclk,
    input  wire                          aresetn,      // active-low synchronous reset

    input  wire                          start,

    // Streamed term1 input (NSC beats, then core proceeds automatically)
    input  wire                          term1_valid,
    input  wire [7:0]                    term1_index,  // write address 0..NSC-1
    input  wire signed [PROD_WIDTH-1:0]  term1_i,
    input  wire signed [PROD_WIDTH-1:0]  term1_q,

    output wire                          term1_ready,

    output reg                           busy,
    output reg                           done,
    output reg                           error,

    output reg signed [15:0]             int_cfo,
    output reg [INDEX_WIDTH-1:0]         peak_index,
    output reg [SCORE_WIDTH-1:0]         peak_score
);

    // ---------------------------------------------------------------------------
    // Derived constants
    // ---------------------------------------------------------------------------
    localparam integer LAG_COUNT = 2 * NSC - 1;   // 511 for NSC=256
    localparam integer CENTER    = NSC - 1;        // 255: zero-CFO peak index

    // ---------------------------------------------------------------------------
    // State encoding
    // ---------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE     = 3'd0,
        S_LOAD     = 3'd1,
        S_PD_START = 3'd2,
        S_CORR     = 3'd3,
        S_LAG_END  = 3'd4,
        S_WAIT_PD  = 3'd5,
        S_DONE     = 3'd6;

    reg [2:0] state;

    // ---------------------------------------------------------------------------
    // term1 sample RAM (NSC × PROD_WIDTH each I/Q)
    // ---------------------------------------------------------------------------
    reg signed [PROD_WIDTH-1:0] term1_i_ram [0:NSC-1];
    reg signed [PROD_WIDTH-1:0] term1_q_ram [0:NSC-1];

    // ---------------------------------------------------------------------------
    // term2 reference ROM — Step 31 synthetic PRNG placeholder
    // Testbench must use the same seed (32'hCAFE_B0BB) and XOR-shift sequence.
    // ---------------------------------------------------------------------------
    reg signed [PROD_WIDTH-1:0] term2_i_rom [0:NSC-1];
    reg signed [PROD_WIDTH-1:0] term2_q_rom [0:NSC-1];

    integer _j;
    reg [31:0] _seed;
    initial begin
        _seed = 32'hCAFE_B0BB;
        for (_j = 0; _j < NSC; _j = _j + 1) begin
            _seed = _seed ^ (_seed << 13);
            _seed = _seed ^ (_seed >> 17);
            _seed = _seed ^ (_seed << 5);
            term2_i_rom[_j] = {{(PROD_WIDTH-8){_seed[7]}}, _seed[7:0]};  // sign-extend 8-bit
            _seed = _seed ^ (_seed << 13);
            _seed = _seed ^ (_seed >> 17);
            _seed = _seed ^ (_seed << 5);
            term2_q_rom[_j] = {{(PROD_WIDTH-8){_seed[7]}}, _seed[7:0]};
        end
    end

    // ---------------------------------------------------------------------------
    // Correlation registers
    // ---------------------------------------------------------------------------
    reg [INDEX_WIDTH-1:0]      lag_p;      // current lag index 0..510
    reg [7:0]                  n_cnt;      // accumulation index for current lag
    reg [7:0]                  n_end_r;    // registered n_end for current lag
    reg [7:0]                  load_cnt;   // counts accepted term1 samples (0..NSC-1)

    reg signed [ACC_WIDTH-1:0] acc_i;      // 56-bit accumulator I
    reg signed [ACC_WIDTH-1:0] acc_q;      // 56-bit accumulator Q

    // ---------------------------------------------------------------------------
    // peak_detector instantiation
    // ---------------------------------------------------------------------------
    wire                    pd_start;
    wire [INDEX_WIDTH-1:0]  pd_peak_index;
    wire [SCORE_WIDTH-1:0]  pd_peak_value;
    wire                    pd_done;
    wire                    pd_busy;

    reg                     pd_start_r;
    reg [SCORE_WIDTH-1:0]   pd_data_in_r;
    reg                     pd_data_valid_r;
    reg                     pd_data_last_r;

    assign pd_start = pd_start_r;

    peak_detector #(
        .METRIC_WIDTH (SCORE_WIDTH),
        .INDEX_WIDTH  (INDEX_WIDTH),
        .COUNT_WIDTH  (10)
    ) u_peak (
        .aclk       (aclk),
        .aresetn    (aresetn),
        .start      (pd_start),
        .max_count  (10'd0),          // no overflow limit; data_last terminates scan
        .data_in    (pd_data_in_r),
        .data_valid (pd_data_valid_r),
        .data_last  (pd_data_last_r),
        .peak_index (pd_peak_index),
        .peak_value (pd_peak_value),
        .done       (pd_done),
        .busy       (pd_busy),
        .error      ()
    );

    // ---------------------------------------------------------------------------
    // Combinatorial: n_start and n_end for current lag_p
    //   if lag_p >= CENTER (lag >= 0): n_start=0, n_end=510-lag_p
    //   if lag_p <  CENTER (lag < 0):  n_start=255-lag_p, n_end=255
    // ---------------------------------------------------------------------------
    wire [INDEX_WIDTH-1:0] lag_p_nxt  = lag_p + 1'b1;

    // Verilog-2001: expression slicing not allowed; use intermediate wires.
    wire [8:0] n_end_cur_9 = 9'd510 - lag_p;
    wire [8:0] n_end_nxt_9 = 9'd510 - lag_p_nxt;

    wire [7:0] n_start_cur = (lag_p >= CENTER) ? 8'd0 : (8'd255 - lag_p[7:0]);
    wire [7:0] n_end_cur   = (lag_p >= CENTER) ? n_end_cur_9[7:0] : 8'd255;

    wire [7:0] n_start_nxt = (lag_p_nxt >= CENTER) ? 8'd0 : (8'd255 - lag_p_nxt[7:0]);
    wire [7:0] n_end_nxt   = (lag_p_nxt >= CENTER) ? n_end_nxt_9[7:0] : 8'd255;

    // ---------------------------------------------------------------------------
    // t1 index: t1_idx = n_cnt + lag_p - 255
    // Always 0..255 for valid (lag_p, n_cnt) loop iterations.
    // ---------------------------------------------------------------------------
    wire [9:0] t1_sum  = {2'b00, n_cnt} + {1'b0, lag_p};
    wire [9:0] t1_idx_10 = t1_sum - 10'd255;
    wire [7:0] t1_idx  = t1_idx_10[7:0];

    // ---------------------------------------------------------------------------
    // MAC operands (read from RAM / ROM using current n_cnt / t1_idx)
    // ---------------------------------------------------------------------------
    wire signed [PROD_WIDTH-1:0] t1_i_w = term1_i_ram[t1_idx];
    wire signed [PROD_WIDTH-1:0] t1_q_w = term1_q_ram[t1_idx];
    wire signed [PROD_WIDTH-1:0] t2_i_w = term2_i_rom[n_cnt];
    wire signed [PROD_WIDTH-1:0] t2_q_w = term2_q_rom[n_cnt];

    // product = term1 * conj(term2) = (a+jb)(c-jd)
    //   real = ac + bd
    //   imag = bc - ad
    // For synthetic 8-bit data: max product magnitude ≈ 127*127 ≈ 16K, no 32-bit overflow.
    wire signed [PROD_WIDTH-1:0] mac_i_w = t1_i_w * t2_i_w + t1_q_w * t2_q_w;
    wire signed [PROD_WIDTH-1:0] mac_q_w = t1_q_w * t2_i_w - t1_i_w * t2_q_w;

    // Sign-extend 32-bit product to ACC_WIDTH=56 for accumulation
    wire signed [ACC_WIDTH-1:0] mac_i = {{(ACC_WIDTH-PROD_WIDTH){mac_i_w[PROD_WIDTH-1]}}, mac_i_w};
    wire signed [ACC_WIDTH-1:0] mac_q = {{(ACC_WIDTH-PROD_WIDTH){mac_q_w[PROD_WIDTH-1]}}, mac_q_w};

    // ---------------------------------------------------------------------------
    // Score: |acc|^2 — uses lower 32 bits of 56-bit accumulator.
    // Safe for Step 31 synthetic 8-bit data (max |acc| ≈ 2^22 << 2^31).
    // For real FFT data (16-bit IQ, 32-bit products): scale accumulators first.
    // ---------------------------------------------------------------------------
    wire signed [31:0] si_s    = acc_i[31:0];
    wire signed [31:0] sq_s    = acc_q[31:0];
    wire [31:0]        si_abs  = si_s[31] ? ~si_s + 32'd1 : si_s;
    wire [31:0]        sq_abs  = sq_s[31] ? ~sq_s + 32'd1 : sq_s;
    wire [SCORE_WIDTH-1:0] score_w = {32'd0, si_abs} * {32'd0, si_abs}
                                   + {32'd0, sq_abs} * {32'd0, sq_abs};

    // ---------------------------------------------------------------------------
    // term1_ready: high only while loading term1
    // ---------------------------------------------------------------------------
    assign term1_ready = (state == S_LOAD);

    // ---------------------------------------------------------------------------
    // Main FSM
    // ---------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state          <= S_IDLE;
            busy           <= 1'b0;
            done           <= 1'b0;
            error          <= 1'b0;
            int_cfo        <= 16'sd0;
            peak_index     <= {INDEX_WIDTH{1'b0}};
            peak_score     <= {SCORE_WIDTH{1'b0}};
            lag_p          <= {INDEX_WIDTH{1'b0}};
            n_cnt          <= 8'd0;
            n_end_r        <= 8'd0;
            load_cnt       <= 8'd0;
            acc_i          <= {ACC_WIDTH{1'b0}};
            acc_q          <= {ACC_WIDTH{1'b0}};
            pd_start_r     <= 1'b0;
            pd_data_in_r   <= {SCORE_WIDTH{1'b0}};
            pd_data_valid_r <= 1'b0;
            pd_data_last_r  <= 1'b0;
        end else begin
            // Default one-cycle pulses
            done           <= 1'b0;
            pd_start_r     <= 1'b0;
            pd_data_valid_r <= 1'b0;
            pd_data_last_r  <= 1'b0;

            // Global start-while-busy guard (any state)
            if (start && busy)
                error <= 1'b1;

            case (state)

                // -----------------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy) begin
                        busy     <= 1'b1;
                        load_cnt <= 8'd0;
                        state    <= S_LOAD;
                    end
                end

                // -----------------------------------------------------------------
                S_LOAD: begin
                    if (term1_valid) begin
                        term1_i_ram[term1_index] <= term1_i;
                        term1_q_ram[term1_index] <= term1_q;
                        if (load_cnt == NSC - 1) begin
                            state <= S_PD_START;
                        end else begin
                            load_cnt <= load_cnt + 8'd1;
                        end
                    end
                end

                // -----------------------------------------------------------------
                S_PD_START: begin
                    pd_start_r <= 1'b1;
                    lag_p      <= {INDEX_WIDTH{1'b0}};
                    n_cnt      <= n_start_cur;    // n_start for lag_p=0
                    n_end_r    <= n_end_cur;       // n_end for lag_p=0
                    acc_i      <= {ACC_WIDTH{1'b0}};
                    acc_q      <= {ACC_WIDTH{1'b0}};
                    state      <= S_CORR;
                end

                // -----------------------------------------------------------------
                // One MAC per cycle for current (lag_p, n_cnt).
                // Transition to S_LAG_END when n_cnt reaches n_end_r.
                // -----------------------------------------------------------------
                S_CORR: begin
                    acc_i <= acc_i + mac_i;
                    acc_q <= acc_q + mac_q;
                    if (n_cnt == n_end_r) begin
                        state <= S_LAG_END;
                    end else begin
                        n_cnt <= n_cnt + 8'd1;
                    end
                end

                // -----------------------------------------------------------------
                // Feed current lag score to peak_detector; advance to next lag.
                // -----------------------------------------------------------------
                S_LAG_END: begin
                    pd_data_valid_r <= 1'b1;
                    pd_data_in_r    <= score_w;
                    pd_data_last_r  <= (lag_p == LAG_COUNT - 1);

                    acc_i <= {ACC_WIDTH{1'b0}};
                    acc_q <= {ACC_WIDTH{1'b0}};

                    if (lag_p == LAG_COUNT - 1) begin
                        state <= S_WAIT_PD;
                    end else begin
                        lag_p   <= lag_p_nxt;
                        n_cnt   <= n_start_nxt;
                        n_end_r <= n_end_nxt;
                        state   <= S_CORR;
                    end
                end

                // -----------------------------------------------------------------
                S_WAIT_PD: begin
                    if (pd_done) begin
                        peak_index <= pd_peak_index;
                        peak_score <= pd_peak_value;
                        int_cfo    <= $signed({7'b0, pd_peak_index}) - 16'sd255;
                        state      <= S_DONE;
                    end
                end

                // -----------------------------------------------------------------
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
