`timescale 1ns/1ps
// P2-02 (refactored P2-08b): Streaming sliding-window CP autocorrelation
// Uses legacy primitives from rtl/phase2_legacy/:
//   delay_sample      — NSC-sample RAM delay
//   complex_mult      — 3-cycle pipelined complex multiply
//   moving_avg_optimized — CP_LEN-window sliding sum (x2 for P_i/P_q, x1 for E)
//   sample_power_sq   — 2-cycle |x|² computation
//   complex_to_mag    — alpha-max-beta-min magnitude (debug internal path)
//
// Phase2 IQ convention: s_data[15:0]=I, s_data[31:16]=Q
// Legacy modules expect upper=I, lower=Q — convention-handled in wiring below.
//
// Pipeline: delay_sample(1cy) → complex_mult(3cy) → moving_avg(4cy) = 8cy total
// Energy path: sample_power_sq(2cy) + 2cy align-delay → moving_avg(4cy) = 8cy total
module streaming_cp_autocorr #(
    parameter integer SAMPLE_W = 16,
    parameter integer NSC      = 256,
    parameter integer CP_LEN   = 32,
    parameter integer ACC_W    = 48
) (
    input  wire                    clk,
    input  wire                    aresetn,
    input  wire                    s_valid,
    input  wire [2*SAMPLE_W-1:0]   s_data,
    output reg  signed [ACC_W-1:0] p_i,
    output reg  signed [ACC_W-1:0] p_q,
    output reg         [ACC_W-1:0] energy,
    output reg                     out_valid,
    output reg  [31:0]             sample_index
);

    // Derived parameters — NSC and CP_LEN must be powers of 2
    localparam integer DELAY_SHIFT = $clog2(NSC);    // 8 for NSC=256
    localparam integer WIN_SHIFT   = $clog2(CP_LEN); // 5 for CP_LEN=32

    wire rst = ~aresetn;

    // ─────────────────────────────────────────────────────────────────────────
    // 1. delay_sample: NSC-cycle RAM delay
    //    DATA_WIDTH=32 (packed IQ), DELAY_SHIFT=8 (256-sample delay)
    //    output_strobe fires from the 257th input onward (once full flag set)
    // ─────────────────────────────────────────────────────────────────────────
    wire [2*SAMPLE_W-1:0] delayed_data;
    wire                  delayed_strobe;

    delay_sample #(
        .DATA_WIDTH  (2*SAMPLE_W),
        .DELAY_SHIFT (DELAY_SHIFT)
    ) u_delay (
        .clock         (clk),
        .enable        (1'b1),
        .reset         (rst),
        .data_in       (s_data),
        .input_strobe  (s_valid),
        .data_out      (delayed_data),
        .output_strobe (delayed_strobe)
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Register current sample for alignment with delay_sample's registered output
    //    After posedge i: delayed_data = data[i-NSC], s_data_reg = data[i] — both aligned
    // ─────────────────────────────────────────────────────────────────────────
    reg [2*SAMPLE_W-1:0] s_data_reg;

    always @(posedge clk or negedge aresetn) begin
        if (!aresetn)
            s_data_reg <= {(2*SAMPLE_W){1'b0}};
        else if (s_valid)
            s_data_reg <= s_data;
    end

    // ─────────────────────────────────────────────────────────────────────────
    // 3. complex_mult: compute conj(delayed) × current = standard Schmidl-Cox
    //    Phase2 convention: s_data[15:0]=I, s_data[31:16]=Q
    //    complex_mult expects individual 16-bit a_i, a_q, b_i, b_q ports
    //    conj(delayed): a_i = delayed_I = delayed_data[15:0]
    //                   a_q = -delayed_Q = -(delayed_data[31:16])
    //    current:       b_i = current_I  = s_data_reg[15:0]
    //                   b_q = current_Q  = s_data_reg[31:16]
    // ─────────────────────────────────────────────────────────────────────────
    wire signed [SAMPLE_W-1:0] cm_a_i = $signed(delayed_data[SAMPLE_W-1:0]);
    wire signed [SAMPLE_W-1:0] cm_a_q = -$signed(delayed_data[2*SAMPLE_W-1:SAMPLE_W]);
    wire signed [SAMPLE_W-1:0] cm_b_i = $signed(s_data_reg[SAMPLE_W-1:0]);
    wire signed [SAMPLE_W-1:0] cm_b_q = $signed(s_data_reg[2*SAMPLE_W-1:SAMPLE_W]);

    wire signed [31:0] mult_p_i;
    wire signed [31:0] mult_p_q;
    wire               mult_strobe;

    complex_mult u_cmult (
        .clock         (clk),
        .enable        (1'b1),
        .reset         (rst),
        .a_i           (cm_a_i),
        .a_q           (cm_a_q),
        .b_i           (cm_b_i),
        .b_q           (cm_b_q),
        .input_strobe  (delayed_strobe),
        .p_i           (mult_p_i),
        .p_q           (mult_p_q),
        .output_strobe (mult_strobe)
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 4. moving_avg_optimized x2: sliding CP_LEN-window sum for P_i and P_q
    //    WINDOW_SHIFT=5 → WINDOW_SIZE=32 = CP_LEN
    //    DATA_WIDTH=32 (matches complex_mult 32-bit outputs)
    //    64-bit data_out; we take ACC_W=48 LSBs
    // ─────────────────────────────────────────────────────────────────────────
    wire signed [63:0] avg_pi_out;
    wire               avg_pi_stb;

    moving_avg_optimized #(
        .DATA_WIDTH   (32),
        .WINDOW_SHIFT (WIN_SHIFT),
        .RAM_LATENCY  (2)
    ) u_avg_pi (
        .clock         (clk),
        .reset         (rst),
        .enable        (1'b1),
        .data_in       (mult_p_i),
        .input_strobe  (mult_strobe),
        .data_out      (avg_pi_out),
        .output_strobe (avg_pi_stb)
    );

    wire signed [63:0] avg_pq_out;
    wire               avg_pq_stb;

    moving_avg_optimized #(
        .DATA_WIDTH   (32),
        .WINDOW_SHIFT (WIN_SHIFT),
        .RAM_LATENCY  (2)
    ) u_avg_pq (
        .clock         (clk),
        .reset         (rst),
        .enable        (1'b1),
        .data_in       (mult_p_q),
        .input_strobe  (mult_strobe),
        .data_out      (avg_pq_out),
        .output_strobe (avg_pq_stb)
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 5. sample_power_sq: |s[n]|² = I² + Q²
    //    Legacy convention: sample_in[31:16]=I, sample_in[15:0]=Q
    //    Phase2 is opposite, so swap: {s_data[15:0], s_data[31:16]}
    //    input_strobe = s_valid (every accepted sample)
    //    2-cycle latency: power_out, power_out_stb valid after posedge i+1
    // ─────────────────────────────────────────────────────────────────────────
    wire [2*SAMPLE_W-1:0] s_data_swapped = {s_data[SAMPLE_W-1:0], s_data[2*SAMPLE_W-1:SAMPLE_W]};

    wire [32:0] pwr_out;
    wire        pwr_stb;

    sample_power_sq #(
        .IQ_WIDTH  (SAMPLE_W),
        .OUT_WIDTH (33)
    ) u_pwr (
        .clock         (clk),
        .enable        (1'b1),
        .reset         (rst),
        .sample_in     (s_data_swapped),
        .input_strobe  (s_valid),
        .power_out     (pwr_out),
        .power_out_stb (pwr_stb)
    );

    // 2-cycle pipeline delay to align energy path with P path
    // P path: delay_sample(1cy) + complex_mult stage-1 latch(1cy) = 2cy before mult_strobe
    // E path: sample_power_sq(2cy) → already at same point; add 2cy to match complex_mult(3cy total)
    reg [32:0] pwr_d1, pwr_d2;
    reg        pwr_stb_d1, pwr_stb_d2;

    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            pwr_d1 <= 33'b0; pwr_d2 <= 33'b0;
            pwr_stb_d1 <= 1'b0; pwr_stb_d2 <= 1'b0;
        end else begin
            pwr_d1 <= pwr_out;    pwr_d2 <= pwr_d1;
            pwr_stb_d1 <= pwr_stb; pwr_stb_d2 <= pwr_stb_d1;
        end
    end

    // ─────────────────────────────────────────────────────────────────────────
    // 6. moving_avg_optimized: sliding CP_LEN-window energy sum
    //    DATA_WIDTH=33 (sample_power_sq is 33-bit unsigned)
    //    input_strobe = pwr_stb_d2 (aligned with P pipeline)
    // ─────────────────────────────────────────────────────────────────────────
    wire signed [63:0] avg_e_out;
    wire               avg_e_stb;

    moving_avg_optimized #(
        .DATA_WIDTH   (33),
        .WINDOW_SHIFT (WIN_SHIFT),
        .RAM_LATENCY  (2)
    ) u_avg_e (
        .clock         (clk),
        .reset         (rst),
        .enable        (1'b1),
        .data_in       ($signed(pwr_d2)),
        .input_strobe  (pwr_stb_d2),
        .data_out      (avg_e_out),
        .output_strobe (avg_e_stb)
    );

    // ─────────────────────────────────────────────────────────────────────────
    // 7. complex_to_mag: debug-only internal path; output not wired to ports
    //    Takes complex_mult output, computes alpha-max-beta-min magnitude
    //    Included to preserve legacy hierarchy: streaming_cp_autocorr → complex_to_mag
    // ─────────────────────────────────────────────────────────────────────────
    wire [31:0] mag_out;
    wire        mag_stb;

    complex_to_mag #(
        .DATA_WIDTH (32)
    ) u_mag (
        .clock         (clk),
        .enable        (1'b1),
        .reset         (rst),
        .i             (mult_p_i),
        .q             (mult_p_q),
        .input_strobe  (mult_strobe),
        .mag           (mag_out),
        .mag_stb       (mag_stb)
    );
    // mag_out / mag_stb: debug wires, not connected to external ports

    // ─────────────────────────────────────────────────────────────────────────
    // 8. Output capture and valid/index tracking
    //    Latch p_i/p_q/energy from moving_avg data_out on strobe
    //    out_valid: permanently asserted once avg_pi_stb fires for the first time
    //    sample_index: running counter of accepted input samples
    // ─────────────────────────────────────────────────────────────────────────
    reg out_valid_latch;

    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            p_i             <= {ACC_W{1'b0}};
            p_q             <= {ACC_W{1'b0}};
            energy          <= {ACC_W{1'b0}};
            out_valid       <= 1'b0;
            out_valid_latch <= 1'b0;
            sample_index    <= 32'd0;
        end else begin
            if (avg_pi_stb) begin
                p_i <= avg_pi_out[ACC_W-1:0];
                p_q <= avg_pq_out[ACC_W-1:0];
            end
            if (avg_e_stb) begin
                energy <= avg_e_out[ACC_W-1:0];
            end
            // out_valid: latch permanently on first strobe
            if (avg_pi_stb)
                out_valid_latch <= 1'b1;
            out_valid <= out_valid_latch;
            // sample_index: tracks current accepted input sample
            if (s_valid)
                sample_index <= sample_index + 32'd1;
        end
    end

endmodule
