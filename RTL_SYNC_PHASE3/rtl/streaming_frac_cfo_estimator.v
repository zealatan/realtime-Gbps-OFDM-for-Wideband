`timescale 1ns/1ps

// streaming_frac_cfo_estimator — P2-05
// On timing_lock: latch p_i/p_q, truncate to PHASE_TRUNC_W bits (MSBs),
// feed into cordic_atan2, output frac_phase = atan2(p_q, p_i).
// frac_phase format: signed Q1.15 (0x7FFF = +pi, 0xC000 = -pi/2).
// timing_lock while busy is silently ignored.
// Total latency from timing_lock to frac_phase_valid: CORDIC_LATENCY + 3 clocks.

module streaming_frac_cfo_estimator #(
    parameter integer PHASE_IN_W     = 48,   // width of p_i, p_q inputs
    parameter integer PHASE_TRUNC_W  = 32,   // CORDIC input width (top bits kept)
    parameter integer CORDIC_LATENCY = 15    // must match cordic_atan2 LATENCY
) (
    input  wire                          clk,
    input  wire                          aresetn,

    input  wire                          timing_lock,
    input  wire signed [PHASE_IN_W-1:0]  p_i,
    input  wire signed [PHASE_IN_W-1:0]  p_q,

    output reg                           busy,
    output reg                           frac_phase_valid,
    output reg  [15:0]                   frac_phase,
    output wire [1:0]                    state_dbg
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_SEND = 2'd1,
                     S_WAIT = 2'd2,
                     S_DONE = 2'd3;

    reg [1:0] state;
    reg [4:0] cnt;
    reg signed [PHASE_TRUNC_W-1:0] pi_r;
    reg signed [PHASE_TRUNC_W-1:0] pq_r;

    assign state_dbg = state;

    // CORDIC tvalid is high exactly during S_SEND (combinatorial)
    wire cordic_tvalid = (state == S_SEND);

    wire [15:0] cordic_phase;
    wire        cordic_valid;

    cordic_atan2 #(
        .INPUT_WIDTH (PHASE_TRUNC_W),
        .PHASE_WIDTH (16),
        .LATENCY     (CORDIC_LATENCY)
    ) u_cordic (
        .aclk                    (clk),
        .aresetn                 (aresetn),
        .s_axis_cartesian_tdata  ({pq_r, pi_r}),   // Q in upper, I in lower
        .s_axis_cartesian_tvalid (cordic_tvalid),
        .s_axis_cartesian_tready (),
        .m_axis_dout_tdata       (cordic_phase),
        .m_axis_dout_tvalid      (cordic_valid)
    );

    always @(posedge clk) begin
        if (!aresetn) begin
            state            <= S_IDLE;
            busy             <= 1'b0;
            frac_phase_valid <= 1'b0;
            frac_phase       <= 16'h0;
            cnt              <= 5'd0;
            pi_r             <= {PHASE_TRUNC_W{1'b0}};
            pq_r             <= {PHASE_TRUNC_W{1'b0}};
        end else begin
            frac_phase_valid <= 1'b0;   // default: pulse

            case (state)
                S_IDLE: begin
                    if (timing_lock) begin
                        // Truncate: keep top PHASE_TRUNC_W bits (MSBs) of 48-bit input
                        pi_r  <= p_i[PHASE_IN_W-1 : PHASE_IN_W-PHASE_TRUNC_W];
                        pq_r  <= p_q[PHASE_IN_W-1 : PHASE_IN_W-PHASE_TRUNC_W];
                        busy  <= 1'b1;
                        state <= S_SEND;
                    end
                end

                S_SEND: begin
                    // CORDIC tvalid=1 this cycle (combinatorial); latch will happen at next posedge
                    cnt   <= 5'd0;
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (cnt == CORDIC_LATENCY - 1) begin
                        state <= S_DONE;
                    end else begin
                        cnt <= cnt + 5'd1;
                    end
                end

                S_DONE: begin
                    // CORDIC output stable; cordic_valid=1 this cycle
                    frac_phase       <= cordic_phase;
                    frac_phase_valid <= 1'b1;
                    busy             <= 1'b0;
                    state            <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
