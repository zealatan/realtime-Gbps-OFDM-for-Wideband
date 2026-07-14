`timescale 1ns/1ps

// slot_start_controller — Phase 3 glue
//
// Latches slotStartIndex = frame_index + peak_lag from frac_cfo_frame_corrector_top
// when its done pulse fires.  Provides the constant PSS and SSS FFT window
// start addresses (relative to the corrected output stream) for
// pss_sss_symbol_extractor.
//
// C reference (receiver.c:291):
//   slotStartIndex = peakIndexAuto + frameStart
//
// RTL mapping:
//   frame_index  = frameStart     (BUF_AW-bit buffer address)
//   peak_lag     = peakIndexAuto  (INDEX_WIDTH-bit offset from frameStart)
//   slot_start   = frame_index + peak_lag
//
// Corrected IQ output from frac_cfo_frame_corrector_top starts at slot_start.
// Therefore, within that output stream, the PSS and SSS FFT windows are:
//   pss_fft_start = CP_LEN
//   sss_fft_start = 2*CP_LEN + NSC
//   frame_len     = 2*(NSC + CP_LEN)   (required OUTPUT_SAMPLES of corrector)
//
// All three PSS/SSS parameters are constants derived from NSC/CP_LEN and are
// provided as registered outputs for clean fanout.
//
// slot_valid is a 1-cycle pulse synchronized to done_in; it remains asserted
// for exactly one clock and is re-armed on each done_in pulse.

module slot_start_controller #(
    parameter integer NSC         = 256,
    parameter integer CP_LEN      = 32,
    parameter integer BUF_AW      = 12,
    parameter integer INDEX_WIDTH = 9
) (
    input  wire                    aclk,
    input  wire                    aresetn,

    // From frac_cfo_frame_corrector_top
    input  wire                    done_in,           // 1-cycle done pulse
    input  wire [BUF_AW-1:0]       frame_index_in,    // buffer address of frame start
    input  wire [INDEX_WIDTH-1:0]  peak_lag_in,       // CP autocorr peak offset

    // slotStartIndex (absolute buffer address)
    output reg  [BUF_AW-1:0]       slot_start,
    output reg                      slot_valid,        // 1-cycle pulse on latch

    // Constant PSS/SSS window descriptors (relative to corrected output stream)
    // Connect directly to pss_sss_symbol_extractor ports:
    //   pss_fft_start → pss_fft_start
    //   sss_fft_start → sss_fft_start
    //   frame_len     → frame_len
    output wire [BUF_AW-1:0]       pss_fft_start,
    output wire [BUF_AW-1:0]       sss_fft_start,
    output wire [BUF_AW-1:0]       frame_len
);

    // Static offsets: synthesize as constants (tools will flatten to wires)
    localparam integer PSS_OFFSET  = CP_LEN;                    // 32
    localparam integer SSS_OFFSET  = 2 * CP_LEN + NSC;          // 320
    // ISS-27/08: 14-symbol slot = 2 sync (PSS,SSS) + 12 data = 14*(NSC+CP_LEN) = 4032
    localparam integer FRAME_TOTAL = 14 * (NSC + CP_LEN);       // 4032

    assign pss_fft_start = PSS_OFFSET[BUF_AW-1:0];
    assign sss_fft_start = SSS_OFFSET[BUF_AW-1:0];
    assign frame_len     = FRAME_TOTAL[BUF_AW-1:0];

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            slot_start <= {BUF_AW{1'b0}};
            slot_valid <= 1'b0;
        end else begin
            slot_valid <= 1'b0;
            if (done_in) begin
                slot_start <= frame_index_in + {{(BUF_AW-INDEX_WIDTH){1'b0}}, peak_lag_in};
                slot_valid <= 1'b1;
            end
        end
    end

endmodule
