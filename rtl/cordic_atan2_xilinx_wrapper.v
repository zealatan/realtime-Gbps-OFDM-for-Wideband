`timescale 1ns/1ps

// cordic_atan2_xilinx_wrapper — IP-ready atan2 wrapper for Xilinx CORDIC IP replacement.
//
// Provides the same AXI-Stream interface as the project's existing cordic_atan2.v
// for drop-in replacement in frac_cfo_estimator.v once the real IP is available.
//
// USE_BEHAVIORAL_MODEL=1 (default, simulation only):
//   Behavioral atan2 using $atan2/$itor with a LATENCY-deep shift-register
//   pipeline for valid and data propagation.
//   THIS BRANCH IS FOR SIMULATION AND IP INTERFACE PREPARATION ONLY.
//   Production synthesis must replace this with the Xilinx CORDIC IP
//   (USE_BEHAVIORAL_MODEL=0 with cordic_v6_0 instantiation).
//
// USE_BEHAVIORAL_MODEL=0 (production placeholder):
//   Shell for future cordic_v6_0 instantiation. Outputs held low pending IP.
//   See scripts/create_cordic_atan2_ip.tcl for IP generation guidance.
//
// Interface: identical to cordic_atan2.v for drop-in compatibility with
//            frac_cfo_estimator.v (cordic_atan2 instance u_cordic).
//
// Phase convention (matches cordic_atan2.v):
//   atan2(Q, I) / pi * 32767, signed PHASE_WIDTH-bit.
//   pi  -> +32767 (0x7FFF)
//   0   ->  0     (0x0000)
//   -pi/2 -> -16383 (0xC001)
//   +pi/2 -> +16383 (0x3FFF)
//   Range: [-32767, +32767] (signed 16-bit)
//
// Latency: exactly LATENCY=15 clock cycles from s_axis_cartesian_tvalid
//          rising to m_axis_dout_tvalid rising.
// tready:  always 1 — fully pipelined, no backpressure.

module cordic_atan2_xilinx_wrapper #(
    parameter integer INPUT_WIDTH          = 32,
    parameter integer PHASE_WIDTH          = 16,
    parameter integer LATENCY             = 15,
    parameter integer USE_BEHAVIORAL_MODEL = 1
) (
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire [2*INPUT_WIDTH-1:0]   s_axis_cartesian_tdata,
    input  wire                       s_axis_cartesian_tvalid,
    output wire                       s_axis_cartesian_tready,
    output reg  [PHASE_WIDTH-1:0]     m_axis_dout_tdata,
    output reg                        m_axis_dout_tvalid
);

    // Fully pipelined: always ready to accept new input
    assign s_axis_cartesian_tready = 1'b1;

    generate

        if (USE_BEHAVIORAL_MODEL == 1) begin : gen_behavioral

            // ----------------------------------------------------------------
            // SIMULATION-ONLY behavioral atan2 pipeline.
            // This branch is for simulation and IP interface preparation only.
            // Production synthesis must replace with Xilinx CORDIC IP.
            // ----------------------------------------------------------------

            // synthesis translate_off

            reg [PHASE_WIDTH-1:0] beh_data_pipe  [0:LATENCY-1];
            reg                   beh_valid_pipe  [0:LATENCY-1];
            integer               beh_k;
            real                  beh_r_I;
            real                  beh_r_Q;
            real                  beh_r_ang;
            integer               beh_ph;

            always @(posedge aclk) begin : beh_pipeline
                if (!aresetn) begin
                    for (beh_k = 0; beh_k < LATENCY; beh_k = beh_k + 1) begin
                        beh_data_pipe[beh_k]  <= {PHASE_WIDTH{1'b0}};
                        beh_valid_pipe[beh_k] <= 1'b0;
                    end
                    m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
                    m_axis_dout_tvalid <= 1'b0;
                end else begin
                    // Compute atan2(Q, I) scaled to PHASE_WIDTH-bit fixed-point
                    beh_r_I   = $itor($signed(s_axis_cartesian_tdata[INPUT_WIDTH-1:0]));
                    beh_r_Q   = $itor($signed(s_axis_cartesian_tdata[2*INPUT_WIDTH-1:INPUT_WIDTH]));
                    beh_r_ang = $atan2(beh_r_Q, beh_r_I) / 3.14159265358979323846;
                    beh_ph    = $rtoi(beh_r_ang * 32767.0);

                    // Stage 0: capture current sample into pipe[0]
                    beh_data_pipe[0]  <= beh_ph[PHASE_WIDTH-1:0];
                    beh_valid_pipe[0] <= s_axis_cartesian_tvalid;

                    // Stages 1..LATENCY-1: cascade shift register
                    for (beh_k = 1; beh_k < LATENCY; beh_k = beh_k + 1) begin
                        beh_data_pipe[beh_k]  <= beh_data_pipe[beh_k-1];
                        beh_valid_pipe[beh_k] <= beh_valid_pipe[beh_k-1];
                    end

                    // Output reads the registered pipe[LATENCY-1] from the previous
                    // clock, so m_axis_dout_tvalid rises exactly LATENCY cycles
                    // after s_axis_cartesian_tvalid.
                    m_axis_dout_tdata  <= beh_data_pipe[LATENCY-1];
                    m_axis_dout_tvalid <= beh_valid_pipe[LATENCY-1];
                end
            end

            // synthesis translate_on

        end else begin : gen_ip_placeholder

            // ----------------------------------------------------------------
            // PRODUCTION PLACEHOLDER for Xilinx CORDIC IP (cordic_v6_0).
            //
            // TODO: Replace this always block with actual cordic_v6_0 instantiation.
            //
            // Expected Xilinx CORDIC IP configuration:
            //   IP core:           cordic_v6_0 (Vivado IP Catalog)
            //   Functional mode:   Translate (Vectoring — computes atan2)
            //   Input format:      s_axis_cartesian_tdata = {Q[INPUT_WIDTH-1:0],
            //                                                 I[INPUT_WIDTH-1:0]}
            //   Input width:       INPUT_WIDTH bits per component (default 32)
            //   Output:            m_axis_dout_tdata = signed phase, PHASE_WIDTH=16 bits
            //   Output phase:      pi -> +32767 (0x7FFF), signed, range [-pi, +pi)
            //   Pipeline stages:   LATENCY=15 (match frac_cfo_estimator CORD_LAT)
            //   AXI-Stream reset:  aresetn active-low
            //   tready:            always asserted (fully pipelined, no throttle)
            //
            // See scripts/create_cordic_atan2_ip.tcl for the Vivado TCL skeleton.
            // ----------------------------------------------------------------

            always @(posedge aclk) begin : ip_placeholder
                if (!aresetn) begin
                    m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
                    m_axis_dout_tvalid <= 1'b0;
                end else begin
                    // TODO: Connect cordic_v6_0 IP outputs here.
                    // Remove these tie-zero assignments and instantiate the IP.
                    m_axis_dout_tdata  <= {PHASE_WIDTH{1'b0}};
                    m_axis_dout_tvalid <= 1'b0;
                end
            end

        end

    endgenerate

endmodule
