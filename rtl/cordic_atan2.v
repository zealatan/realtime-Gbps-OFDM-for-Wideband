`timescale 1ns/1ps

// cordic_atan2: Behavioral LATENCY-stage pipeline atan2 for simulation.
//
// Computes phase = atan2(Q, I) encoded as Q1.15 signed fixed-point:
//   0x7FFF = +π, 0x8000 = -π, 0x0000 = 0
//   value = round(atan2(Q,I) / π × 32768), clamped to [-32768, 32767]
//
// AXI-Stream interface: always-ready slave, LATENCY-cycle latency from
// valid input to valid output.
//
// Instantiated by frac_cfo_estimator:
//   tdata = {autocorr_Q[31:0], autocorr_I[31:0]}  (64-bit, Q in upper half)
//   tdata output = frac_phase [PHASE_WIDTH-1:0]

module cordic_atan2 #(
    parameter integer INPUT_WIDTH = 32,
    parameter integer PHASE_WIDTH = 16,
    parameter integer LATENCY     = 15
) (
    input  wire aclk,
    input  wire aresetn,

    input  wire [2*INPUT_WIDTH-1:0] s_axis_cartesian_tdata,    // {Q, I}
    input  wire                     s_axis_cartesian_tvalid,
    output wire                     s_axis_cartesian_tready,

    output reg  [PHASE_WIDTH-1:0]   m_axis_dout_tdata,
    output reg                      m_axis_dout_tvalid
);
    assign s_axis_cartesian_tready = 1'b1;

    // LATENCY-stage shift register
    reg [2*INPUT_WIDTH-1:0] data_pipe  [0:LATENCY-1];
    reg                     valid_pipe [0:LATENCY-1];

    integer k;

    always @(posedge aclk) begin
        if (!aresetn) begin
            for (k = 0; k < LATENCY; k = k + 1) begin
                data_pipe[k]  <= {(2*INPUT_WIDTH){1'b0}};
                valid_pipe[k] <= 1'b0;
            end
            m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
            m_axis_dout_tvalid <= 1'b0;
        end else begin
            data_pipe[0]  <= s_axis_cartesian_tdata;
            valid_pipe[0] <= s_axis_cartesian_tvalid;
            for (k = 1; k < LATENCY; k = k + 1) begin
                data_pipe[k]  <= data_pipe[k-1];
                valid_pipe[k] <= valid_pipe[k-1];
            end

            m_axis_dout_tvalid <= valid_pipe[LATENCY-1];

            if (valid_pipe[LATENCY-1]) begin
                // Behavioral atan2: split {Q,I} from 64-bit pipeline output
                begin : atan2_compute
                    real I_r, Q_r, angle_r;
                    integer angle_i;
                    integer phase_clamped;
                    Q_r = $itor($signed(data_pipe[LATENCY-1][2*INPUT_WIDTH-1:INPUT_WIDTH]));
                    I_r = $itor($signed(data_pipe[LATENCY-1][INPUT_WIDTH-1:0]));
                    angle_r = $atan2(Q_r, I_r);
                    // Q1.15: map [-π,+π] to [-32768,+32767]
                    angle_i = $rtoi(angle_r / 3.14159265358979323846 * 32768.0);
                    if (angle_i >  32767) phase_clamped =  32767;
                    else if (angle_i < -32768) phase_clamped = -32768;
                    else                   phase_clamped =  angle_i;
                    m_axis_dout_tdata <= phase_clamped[PHASE_WIDTH-1:0];
                end
            end
        end
    end

endmodule
