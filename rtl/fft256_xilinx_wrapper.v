`timescale 1ns/1ps

// fft256_xilinx_wrapper — Project-local wrapper around the Xilinx FFT IP.
//
// Hides vendor IP details (port names, config channel packing, tdata width)
// from the rest of RTL_SYNC.  The interface seen by RTL_SYNC callers is
// stable regardless of the underlying IP version.
//
// USE_BEHAVIORAL_STUB=1 (default — compile-only placeholder):
//   No FFT computation is performed.  Input samples are accepted and
//   immediately forwarded to the output with the same handshake, so that
//   the wrapper compiles and can be included in hierarchy checks.
//   THIS IS NOT AN FFT.  See warning in simulation output.
//   Suitable for: compile checks, interface wiring verification, CI stubs.
//
// USE_BEHAVIORAL_STUB=0 (production placeholder):
//   Contains a clearly marked TODO block for the actual xfft256_xilinx
//   instantiation once the XCI is generated (Step 37+).
//   Until the IP is instantiated, all outputs are held low.
//   Do NOT claim FFT correctness in this mode.
//
// Interface mapping to fft256_dual_symbol_frontend:
//   The Step 34 frontend uses a custom I/Q streaming interface with
//   symbol_sel and index sideband signals.  This wrapper uses a flat
//   AXI4-Stream tdata bus ({Q[IQ_WIDTH-1:0], I[IQ_WIDTH-1:0]}) matching
//   the Xilinx FFT IP input format.  The dual-symbol frontend wrapper
//   (future Step 37) will bridge between the two interfaces.
//
// Xilinx FFT AXI-Stream port names (pending XCI verification):
//   Input data  : s_axis_data_tdata / _tvalid / _tready / _tlast
//   Config      : s_axis_config_tdata / _tvalid / _tready
//   Output data : m_axis_data_tdata / _tvalid / _tready / _tlast / _tuser
//   Status      : m_axis_status_tdata / _tvalid
//   Events      : event_frame_started, event_tlast_unexpected,
//                 event_tlast_missing, event_data_in_channel_halt,
//                 event_data_out_channel_halt, event_status_channel_halt
//
// Config channel format (typical xfft v9.1 — verify from generated XCI):
//   s_axis_config_tdata[0]   = FWD_INV (1=forward FFT, 0=inverse FFT)
//   s_axis_config_tdata[8:1] = SCALE_SCH (scaling schedule, 2 bits per stage)
//   Frame: drive tvalid=1 before or with the first data sample; IP will
//   latch config on the accepted handshake.
//
// Output data packing (typical xfft v9.1 with 16-bit I/O — verify from XCI):
//   m_axis_data_tdata[15:0]  = Re (I component), signed Q15
//   m_axis_data_tdata[31:16] = Im (Q component), signed Q15
//   Width = 2 * FFT_OUT_WIDTH bits.
//
// Natural bin order (with output_ordering = natural_order):
//   k=0          DC
//   k=1..127     positive frequencies
//   k=128..255   negative frequencies
//   m_axis_data_tlast asserted with bin k=255 (last bin of each frame).
//
// Known limitations (Step 36A):
//   - No actual XCI generated yet (pending Windows Vivado execution).
//   - Property names in comments are preliminary; verify from XCI.
//   - Latency from first input to first output: TBD (run probe_fft256_ip_properties.tcl).
//   - Config channel must be driven deterministically; this wrapper drives a
//     static FWD_INV=1, SCALE_SCH=0xAA (conservative default — verify scaling!).
//
// See docs/step36A_fft256_xilinx_ip_audit.md and scripts/create_fft256_ip.tcl.

module fft256_xilinx_wrapper #(
    parameter integer FFT_LEN            = 256,
    parameter integer IQ_WIDTH           = 16,
    parameter integer FFT_OUT_WIDTH      = 16,
    parameter integer USE_BEHAVIORAL_STUB = 1
)(
    input  wire                          aclk,
    input  wire                          aresetn,

    // start pulse: optional — wrapper accepts frames as a continuous stream.
    // Kept for interface compatibility with fft256_dual_symbol_frontend caller.
    input  wire                          start,

    // AXI4-Stream input (time-domain samples)
    // tdata packing: {Q[IQ_WIDTH-1:0], I[IQ_WIDTH-1:0]}
    // tlast: assert with sample index 255 (last sample of the 256-sample frame)
    input  wire                          s_axis_tvalid,
    output wire                          s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]         s_axis_tdata,
    input  wire                          s_axis_tlast,

    // AXI4-Stream output (frequency-domain bins, natural order)
    // tdata packing: {Im[FFT_OUT_WIDTH-1:0], Re[FFT_OUT_WIDTH-1:0]}
    // tlast: asserted with bin k=255
    output wire                          m_axis_tvalid,
    input  wire                          m_axis_tready,
    output wire [2*FFT_OUT_WIDTH-1:0]    m_axis_tdata,
    output wire                          m_axis_tlast,

    // Status
    output wire                          busy,
    output wire                          done,
    output wire                          error,

    // Xilinx FFT event outputs (all zero in stub mode)
    output wire                          event_frame_started,
    output wire                          event_tlast_unexpected,
    output wire                          event_tlast_missing,
    output wire                          event_data_in_channel_halt,
    output wire                          event_data_out_channel_halt,
    output wire                          event_status_channel_halt
);

    // -------------------------------------------------------------------------
    // Xilinx FFT config channel: FWD_INV=1 (forward), SCALE_SCH=0xAA
    // Config data format (xfft v9.1, verify from XCI):
    //   [0]   = FWD_INV  : 1 = forward FFT
    //   [8:1] = SCALE_SCH: scaling schedule (2 bits per butterfly stage)
    //             0xAA = 10101010b → scale by 1/2 at alternating stages
    //             (conservative default; tune based on signal headroom)
    // TODO: Verify bit layout from reports/fft256_ip_config_summary.txt
    // -------------------------------------------------------------------------
    localparam [7:0] CFG_SCALE_SCH = 8'hAA;
    localparam [8:0] CFG_DATA      = {CFG_SCALE_SCH, 1'b1}; // FWD=1

    generate

        if (USE_BEHAVIORAL_STUB == 1) begin : gen_stub

            // -----------------------------------------------------------------
            // COMPILE-ONLY STUB.  NOT AN FFT.
            // Passes input stream directly to output stream.
            // Use only for compile/interface checks.
            // -----------------------------------------------------------------

            // synthesis translate_off
            initial begin
                $display("[WARNING] fft256_xilinx_wrapper: USE_BEHAVIORAL_STUB=1");
                $display("[WARNING] This is a passthrough stub — NOT an FFT.");
                $display("[WARNING] Step 36A: actual Xilinx FFT IP pending.");
                $display("[WARNING] Step 34 behavioral/bypass path remains the");
                $display("[WARNING]   verified simulation path for Meyr estimator.");
            end
            // synthesis translate_on

            assign s_axis_tready = m_axis_tready;
            assign m_axis_tvalid = s_axis_tvalid;
            assign m_axis_tdata  = {{(FFT_OUT_WIDTH){1'b0}},
                                     s_axis_tdata[IQ_WIDTH-1:0]};
            assign m_axis_tlast  = s_axis_tlast;

            // Status: passthrough has no meaningful busy/done tracking
            reg done_r;
            always @(posedge aclk) begin
                if (!aresetn)
                    done_r <= 1'b0;
                else
                    done_r <= m_axis_tvalid && m_axis_tready && m_axis_tlast;
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

        end else begin : gen_production

            // -----------------------------------------------------------------
            // PRODUCTION PLACEHOLDER for Xilinx xfft IP (xfft v9.1 / fft256_xilinx).
            //
            // TODO Step 37+: Replace everything below with actual fft256_xilinx
            //   instantiation after running scripts/create_fft256_ip.tcl in
            //   Windows Vivado and obtaining the .XCI output.
            //
            // Expected Xilinx FFT IP instantiation template (preliminary):
            //
            //   fft256_xilinx u_xfft (
            //       .aclk                        (aclk),
            //       .aresetn                     (aresetn),
            //       .s_axis_config_tdata         (CFG_DATA),
            //       .s_axis_config_tvalid        (cfg_tvalid),
            //       .s_axis_config_tready        (cfg_tready),
            //       .s_axis_data_tdata           (s_axis_tdata),
            //       .s_axis_data_tvalid          (s_axis_tvalid),
            //       .s_axis_data_tready          (s_axis_tready),
            //       .s_axis_data_tlast           (s_axis_tlast),
            //       .m_axis_data_tdata           (m_axis_tdata),
            //       .m_axis_data_tvalid          (m_axis_tvalid),
            //       .m_axis_data_tready          (m_axis_tready),
            //       .m_axis_data_tlast           (m_axis_tlast),
            //       .m_axis_data_tuser           (open),
            //       .m_axis_status_tdata         (open),
            //       .m_axis_status_tvalid        (open),
            //       .event_frame_started         (event_frame_started),
            //       .event_tlast_unexpected      (event_tlast_unexpected),
            //       .event_tlast_missing         (event_tlast_missing),
            //       .event_data_in_channel_halt  (event_data_in_channel_halt),
            //       .event_data_out_channel_halt (event_data_out_channel_halt),
            //       .event_status_channel_halt   (event_status_channel_halt)
            //   );
            //
            // TODO: Verify all port names from the generated instantiation
            //   template (ip/fft256_xilinx/fft256_xilinx_inst.v or *.vhd).
            //   Port names may differ between xfft versions.
            //
            // TODO: Config channel handshake — determine whether the IP expects
            //   a one-shot config transaction per frame or a persistent drive.
            //   For Realtime throttle: drive cfg_tvalid=1 continuously.
            //   For Non-realtime: pulse cfg_tvalid=1 once before each frame.
            //
            // TODO: m_axis_data_tuser — in natural order mode, tuser carries
            //   the bin index (xk_index). Width = log2(FFT_LEN)+1 = 9 bits.
            //   Can be used to verify bin alignment. Not forwarded here.
            //
            // TODO: Latency from s_axis_data_tvalid[0] to m_axis_data_tvalid[0]
            //   must be documented in this wrapper once known.
            //   Check reports/fft256_ip_properties.txt after IP generation.
            // -----------------------------------------------------------------

            // Until IP is instantiated, hold all outputs low
            assign s_axis_tready = 1'b0;
            assign m_axis_tvalid = 1'b0;
            assign m_axis_tdata  = {(2*FFT_OUT_WIDTH){1'b0}};
            assign m_axis_tlast  = 1'b0;
            assign busy          = 1'b0;
            assign done          = 1'b0;
            assign error         = 1'b0;

            assign event_frame_started         = 1'b0;
            assign event_tlast_unexpected      = 1'b0;
            assign event_tlast_missing         = 1'b0;
            assign event_data_in_channel_halt  = 1'b0;
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        end

    endgenerate

    // Suppress unused-signal warning for start (kept for interface compat)
    wire _unused_start = start;

endmodule
