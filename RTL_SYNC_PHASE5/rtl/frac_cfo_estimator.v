`timescale 1ns/1ps

// frac_cfo_estimator: Reads the autocorrelation peak at peak_lag and computes
// its phase angle via the internal cordic_atan2 instance.
//
// Output: frac_phase = atan2(autocorr_Q[peak_lag], autocorr_I[peak_lag])
// encoded as signed PHASE_WIDTH-bit: 0x7FFF = +π.
//
// Timeline (CORDIC LATENCY=L):
//   posedge P   : S_IDLE → S_SEND (latch peak_lag_r); CORDIC tvalid driven high
//   posedge P+1 : S_SEND → S_WAIT (cnt=0); CORDIC pipe[0] captures data
//   posedge P+2..P+L: S_WAIT cnt increments; CORDIC pipeline propagates
//   posedge P+L+1 : S_WAIT cnt=L-1 → S_DONE; CORDIC output regs update simultaneously
//   posedge P+L+2 : S_DONE reads stable CORDIC output; asserts frac_phase_valid, done; → S_IDLE
//
// Total latency start→frac_phase_valid: L+2 clocks (default 17 with L=15).

module frac_cfo_estimator #(
    parameter integer PHASE_WIDTH = 16
) (
    input  wire                    aclk,
    input  wire                    aresetn,

    // Control
    input  wire                    start,
    input  wire [8:0]              peak_lag,

    // cp_autocorr_core result read port (combinatorial, zero-latency)
    output wire [8:0]              result_rd_addr,
    input  wire signed [31:0]      autocorr_I,
    input  wire signed [31:0]      autocorr_Q,

    // Output
    output reg  [PHASE_WIDTH-1:0]  frac_phase,
    output reg                     frac_phase_valid,
    output reg                     done,
    output reg                     busy
);

    localparam [1:0] S_IDLE = 2'd0,
                     S_SEND = 2'd1,
                     S_WAIT = 2'd2,
                     S_DONE = 2'd3;

    localparam integer CORD_LAT = 15;   // must match cordic_atan2 LATENCY parameter

    reg [1:0] state;
    reg [8:0] peak_lag_r;
    reg [4:0] cnt;          // counts 0..CORD_LAT-1 in S_WAIT

    // Drive the autocorr read address with the latched lag (combinatorial)
    assign result_rd_addr = peak_lag_r;

    // CORDIC submodule
    wire [PHASE_WIDTH-1:0] cordic_phase;
    wire                   cordic_valid;
    wire                   cordic_tvalid_w;

    assign cordic_tvalid_w = (state == S_SEND);

    cordic_atan2 #(
        .INPUT_WIDTH(32),
        .PHASE_WIDTH(PHASE_WIDTH),
        .LATENCY    (CORD_LAT)
    ) u_cordic (
        .aclk                    (aclk),
        .aresetn                 (aresetn),
        .s_axis_cartesian_tdata  ({autocorr_Q, autocorr_I}),
        .s_axis_cartesian_tvalid (cordic_tvalid_w),
        .s_axis_cartesian_tready (),
        .m_axis_dout_tdata       (cordic_phase),
        .m_axis_dout_tvalid      (cordic_valid)
    );

    // -----------------------------------------------------------------------
    // FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state            <= S_IDLE;
            done             <= 1'b0;
            busy             <= 1'b0;
            frac_phase       <= {PHASE_WIDTH{1'b0}};
            frac_phase_valid <= 1'b0;
            peak_lag_r       <= 9'd0;
            cnt              <= 5'd0;
        end else begin
            done             <= 1'b0;   // default: pulse
            frac_phase_valid <= 1'b0;   // default: pulse

            case (state)

                S_IDLE: begin
                    if (start && !busy) begin
                        peak_lag_r <= peak_lag;
                        busy       <= 1'b1;
                        state      <= S_SEND;
                    end
                end

                S_SEND: begin
                    // CORDIC tvalid=1 this cycle (driven combinatorially from state==S_SEND)
                    // CORDIC will capture at the next posedge
                    cnt   <= 5'd0;
                    state <= S_WAIT;
                end

                S_WAIT: begin
                    if (cnt == CORD_LAT - 1) begin
                        state <= S_DONE;
                        // CORDIC output registers update simultaneously; read them in S_DONE
                    end else begin
                        cnt <= cnt + 5'd1;
                    end
                end

                S_DONE: begin
                    // CORDIC output (cordic_phase) is stable: updated one posedge ago
                    frac_phase       <= cordic_phase;
                    frac_phase_valid <= 1'b1;
                    done             <= 1'b1;
                    busy             <= 1'b0;
                    state            <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
