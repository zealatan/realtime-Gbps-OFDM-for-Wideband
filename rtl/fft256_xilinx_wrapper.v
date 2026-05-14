`timescale 1ns/1ps

// fft256_xilinx_wrapper — Project-local wrapper around the Xilinx FFT IP.
//
// USE_BEHAVIORAL_STUB=1  compile-only passthrough stub (NOT an FFT).
// USE_BEHAVIORAL_STUB=0  actual Xilinx xfft_v9_1_8 IP via fft256_xilinx.v.
//
// Port interface (stable across modes):
//   s_axis_tdata = {Im[15:0], Re[15:0]} — Xilinx FFT native packing
//   m_axis_tdata = {Im[15:0], Re[15:0]} — same packing on output
//   m_axis_tuser = xk_index[7:0]        — bin index (natural order)
//
// Config channel (USE_BEHAVIORAL_STUB=0 only):
//   s_axis_config_tdata[0]   = FWD_INV  : 1 = forward FFT
//   s_axis_config_tdata[8:1] = SCALE_SCH: 8 bits, 1 bit per radix-2 stage
//                              0xAA = scale at alternating stages (conservative)
//   Config is driven continuously with tvalid=1 after reset deasserts.
//   IP latches config at the accepted handshake before each frame.
//
// Realtime throttle constraints (USE_BEHAVIORAL_STUB=0):
//   - C_THROTTLE_SCHEME=0: output has no m_axis_data_tready port.
//   - m_axis_tready input is accepted but NOT connected to the IP.
//   - Data flows at full rate; downstream must always be ready to consume.
//   - See T10 test notes for observed behavior.
//
// C_HAS_ARESETN=0: the underlying IP has no reset port.  aresetn is used
//   only to gate the config state machine in this wrapper.
//
// Verified port names: ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.veo
// Verified parameters: ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.xci

module fft256_xilinx_wrapper #(
    parameter integer FFT_LEN             = 256,
    parameter integer IQ_WIDTH            = 16,
    parameter integer FFT_OUT_WIDTH       = 16,
    parameter integer USE_BEHAVIORAL_STUB = 1
)(
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire                       start,        // sideband compat; unused internally

    // AXI4-Stream input  {Im[IQ_WIDTH-1:0], Re[IQ_WIDTH-1:0]}
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]      s_axis_tdata,
    input  wire                       s_axis_tlast,

    // AXI4-Stream output {Im[FFT_OUT_WIDTH-1:0], Re[FFT_OUT_WIDTH-1:0]}
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,
    output wire [2*FFT_OUT_WIDTH-1:0] m_axis_tdata,
    output wire [7:0]                 m_axis_tuser,   // xk_index bin index
    output wire                       m_axis_tlast,

    // Status
    output wire                       busy,
    output wire                       done,
    output wire                       error,

    // IP event outputs
    output wire                       event_frame_started,
    output wire                       event_tlast_unexpected,
    output wire                       event_tlast_missing,
    output wire                       event_data_in_channel_halt,
    output wire                       event_data_out_channel_halt,
    output wire                       event_status_channel_halt
);

    // Config word: FWD_INV=1 (bit 0), SCALE_SCH=0xAA (bits[8:1])
    localparam [15:0] CFG_TDATA = 16'h0155;

    wire _unused = start;

    generate

        // =====================================================================
        // STUB MODE — compile-only passthrough, NOT an FFT
        // =====================================================================
        if (USE_BEHAVIORAL_STUB == 1) begin : gen_stub

            // synthesis translate_off
            initial begin
                $display("[WARNING] fft256_xilinx_wrapper: USE_BEHAVIORAL_STUB=1");
                $display("[WARNING] Passthrough stub only — NOT an FFT.");
            end
            // synthesis translate_on

            assign s_axis_tready = m_axis_tready;
            assign m_axis_tvalid = s_axis_tvalid;
            assign m_axis_tdata  = {{FFT_OUT_WIDTH{1'b0}}, s_axis_tdata[IQ_WIDTH-1:0]};
            assign m_axis_tuser  = 8'h00;
            assign m_axis_tlast  = s_axis_tlast;

            reg done_r;
            always @(posedge aclk) begin
                if (!aresetn)
                    done_r <= 1'b0;
                else
                    done_r <= m_axis_tvalid & m_axis_tready & m_axis_tlast;
            end

            assign busy  = s_axis_tvalid & ~m_axis_tlast;
            assign done  = done_r;
            assign error = 1'b0;

            assign event_frame_started         = 1'b0;
            assign event_tlast_unexpected      = 1'b0;
            assign event_tlast_missing         = 1'b0;
            assign event_data_in_channel_halt  = 1'b0;
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        // =====================================================================
        // PRODUCTION MODE — actual Xilinx xfft IP
        // =====================================================================
        end else begin : gen_production

            // Config channel wires
            wire        cfg_tready;
            // Drive config continuously after reset; IP latches on handshake
            wire        cfg_tvalid = aresetn;
            wire [15:0] cfg_tdata  = CFG_TDATA;

            // IP data wires
            wire [31:0] ip_m_tdata;
            wire [7:0]  ip_m_tuser;
            wire        ip_m_tvalid;
            wire        ip_m_tlast;
            wire        ip_ev_frame_started;
            wire        ip_ev_tlast_unexpected;
            wire        ip_ev_tlast_missing;
            wire        ip_ev_din_halt;

            fft256_xilinx u_fft (
                .aclk                        (aclk),
                .s_axis_config_tdata         (cfg_tdata),
                .s_axis_config_tvalid        (cfg_tvalid),
                .s_axis_config_tready        (cfg_tready),
                .s_axis_data_tdata           (s_axis_tdata),
                .s_axis_data_tvalid          (s_axis_tvalid),
                .s_axis_data_tready          (s_axis_tready),
                .s_axis_data_tlast           (s_axis_tlast),
                .m_axis_data_tdata           (ip_m_tdata),
                .m_axis_data_tuser           (ip_m_tuser),
                .m_axis_data_tvalid          (ip_m_tvalid),
                .m_axis_data_tlast           (ip_m_tlast),
                .event_frame_started         (ip_ev_frame_started),
                .event_tlast_unexpected      (ip_ev_tlast_unexpected),
                .event_tlast_missing         (ip_ev_tlast_missing),
                .event_data_in_channel_halt  (ip_ev_din_halt)
            );

            assign m_axis_tvalid = ip_m_tvalid;
            assign m_axis_tdata  = ip_m_tdata;
            assign m_axis_tuser  = ip_m_tuser;
            assign m_axis_tlast  = ip_m_tlast;

            // busy: high from first input handshake through last output
            reg frame_active;
            always @(posedge aclk) begin
                if (!aresetn)
                    frame_active <= 1'b0;
                else if (s_axis_tvalid && s_axis_tready)
                    frame_active <= 1'b1;
                else if (ip_m_tvalid && ip_m_tlast)
                    frame_active <= 1'b0;
            end

            assign busy  = frame_active;
            assign done  = ip_m_tvalid & ip_m_tlast;
            assign error = ip_ev_tlast_unexpected | ip_ev_tlast_missing | ip_ev_din_halt;

            assign event_frame_started         = ip_ev_frame_started;
            assign event_tlast_unexpected      = ip_ev_tlast_unexpected;
            assign event_tlast_missing         = ip_ev_tlast_missing;
            assign event_data_in_channel_halt  = ip_ev_din_halt;
            // Not present in realtime-throttle IP boundary; tie low
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        end

    endgenerate

endmodule
