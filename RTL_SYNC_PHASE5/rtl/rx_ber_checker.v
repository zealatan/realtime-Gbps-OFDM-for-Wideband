`timescale 1ns/1ps
`default_nettype none
// =====================================================================
// rx_ber_checker.v   (ROBUST, FIRMWARE-ALIGNABLE rewrite)
// ---------------------------------------------------------------------
// ON-CHIP HARDWARE BIT-ERROR COUNTER for the full-RX demod output.
//
// PURPOSE
//   Additive, NON-INTRUSIVE tap on rx_full_board_top's m_bits stream
//   (one 4-bit demod nibble per data subcarrier). It holds the known
//   2652-nibble golden reference for ONE frame in a ROM (loaded from
//   rx_ber_ref_rom.hex, generated from golden/rx_downstream/tx_bits.txt
//   with the SAME packing the demod emits: nibble = {b0,b1,b2,b3},
//   bit3=b0 .. bit0=b3), tracks the within-frame nibble position by
//   FREE-RUNNING from the first nibble after clear, compares each demod
//   nibble against ref[pos_eff], and accumulates:
//       total_bit_errors  - count of differing BITS across all checked frames
//       frames_checked    - number of COMPLETE frames checked (after warm-up)
//       total_nibbles     - number of nibbles checked (after warm-up)
//   plus an error-flag word (alignment / position sanity).
//
//   It is a pure passive monitor: it does NOT drive m_bits_tready or
//   touch any datapath signal. It snoops (m_bits_tvalid && m_bits_tready)
//   accepted beats only, so it is transparent to the verified RX chain.
//
// POSITION / FRAME ALIGNMENT (ROBUST, firmware-search based)
//   The demod emits NDATA_SC (221) nibbles per OFDM symbol and NUM_DATA
//   (12) symbols per frame, in order, repeating every TOTAL_NIBBLES
//   (2652) nibbles. m_bits_tuser flags carrier 0 of a symbol;
//   m_bits_tlast flags carrier 220 of a symbol (symbol end).
//
//   The checker ANCHORS its OWN frame position at the FIRST m_bits beat
//   after clr -> that beat is symbol 0, carrier 0. It then FREE-RUNS:
//       - tuser  : carrier 0 of a symbol (resync nib_in_sym -> 0)
//       - tlast  : carrier 220 (symbol end); advance to next symbol,
//                  wrapping symbol 11 -> 0 (the checker's frame boundary)
//       - else   : carrier++
//   pos_raw = sym_in_frame*NDATA_SC + nib_in_sym   (0..2651).
//
//   There is NO fragile pilot-ROM-wrap anchor anymore. The frame phase
//   relative to the golden reference frame is unknown (pipeline latency /
//   enable phase shift it by a whole number of symbols), so firmware sets
//   `rot_off` [3:0] (0..11) to ROTATE the REFERENCE index by whole symbols:
//       pos_eff = (pos_raw + rot_off*NDATA_SC) mod TOTAL_NIBBLES
//   One conditional subtract suffices because (pos_raw + rot_off*221) is
//   always < 2*2652. ref_nib = ref_rom[pos_eff]; the firmware simply
//   SEARCHES rot_off = 0..11 and the aligned value yields ~0 errors while
//   every other yields ~50%. This makes alignment immune to pipeline
//   latency / enable phase.
//
//   WARM-UP: the first frame seen after clr may be partial (the tap was
//   cleared mid-stream and the very first counted nibble might not be the
//   checker's frame-pos 0). We therefore do NOT count the first (warm-up)
//   frame: counting begins at the first FRAME BOUNDARY (symbol 11 -> 0)
//   after clr. frames_checked / total_nibbles / total_bit_errors only
//   accumulate from the first full frame onward. warmup_done / warmup_frames
//   are exposed so firmware can report the excluded frame.
//
// STATUS / READBACK
//   All counters are exposed via a status_sel mux on status_data so one
//   32-bit input GPIO channel reads ALL counters.
// =====================================================================
module rx_ber_checker #(
    parameter integer NDATA_SC      = 221,
    parameter integer NUM_DATA      = 12,
    parameter         REF_ROM_FILE  = "rx_ber_ref_rom.hex"
)(
    input  wire        aclk,
    input  wire        aresetn,

    // ---- snoop tap on the demod nibble stream (read-only) ----
    input  wire        m_bits_tvalid,
    input  wire        m_bits_tready,
    input  wire  [3:0] m_bits_tdata,
    input  wire        m_bits_tuser,   // carrier 0 of a symbol
    input  wire        m_bits_tlast,   // carrier 220 of a symbol

    // ---- firmware-settable whole-symbol reference rotation (0..11) ----
    //   pos_eff = (pos_raw + rot_off*NDATA_SC) mod TOTAL_NIBBLES.
    //   Firmware searches rot_off 0..11; the aligned one gives ~0 errors.
    input  wire  [3:0] rot_off,

    // ---- control: bit0 = soft clear (sync, level) ----
    input  wire        clr,

    // ---- status readback ----
    input  wire  [3:0] status_sel,     // selects which counter word to present
    output reg  [31:0] status_data
);
    localparam integer TOTAL_NIBBLES = NUM_DATA * NDATA_SC;   // 2652
    localparam integer POSW = 13;                              // 0..(2*2652-1) -> 13 bits
    localparam integer SYMW = 4;                               // 0..11   -> 4 bits
    localparam integer CARW = 8;                               // 0..220  -> 8 bits

    // -----------------------------------------------------------------
    // reference ROM : TOTAL_NIBBLES words of 4 bits, packed {b0,b1,b2,b3}
    // -----------------------------------------------------------------
    (* rom_style = "block" *) reg [3:0] ref_rom [0:TOTAL_NIBBLES-1];
    initial $readmemh(REF_ROM_FILE, ref_rom);

    // -----------------------------------------------------------------
    // free-running position / frame tracking (anchored at first beat post-clr)
    // -----------------------------------------------------------------
    reg [CARW-1:0] nib_in_sym;     // 0..220
    reg [SYMW-1:0] sym_in_frame;   // 0..11
    reg            started;        // first beat after clr seen -> position valid

    // warm-up / alignment
    reg            warmup_done;    // first frame boundary crossed -> count
    reg [15:0]     warmup_frames;  // frames skipped before counting began

    // accumulators (only advance once warmup_done)
    reg [31:0]     total_bit_errors;
    reg [31:0]     frames_checked;
    reg [31:0]     total_nibbles;

    // error / sanity flags (sticky)
    //   bit0 CARRIER_MISMATCH : tlast asserted but nib_in_sym != NDATA_SC-1
    //   bit1 SYMBOL_OVERRUN   : nib_in_sym == NDATA_SC-1 but no tlast
    reg [31:0]     err_flags;

    wire beat = m_bits_tvalid & m_bits_tready;

    // ---- raw within-frame position of the CURRENT beat ----
    // On the very first beat after clr we FORCE pos to (0,0) regardless of the
    // (stale/reset) counters, so the anchor is exact even if the cleared
    // counters happen to read 0 anyway (kept explicit for clarity).
    wire [POSW-1:0] pos_raw = started ? (sym_in_frame * NDATA_SC + nib_in_sym)
                                      : {POSW{1'b0}};

    // ---- whole-symbol reference rotation: pos_eff = (pos_raw + rot_off*221) mod 2652
    //   rot_off in 0..11 -> rot_off*221 in 0..2431; sum < 2*2652=5304, so a
    //   single conditional subtract of TOTAL_NIBBLES reduces it. ----
    wire [POSW-1:0] rot_nib = rot_off * NDATA_SC;            // 0..2431
    wire [POSW-1:0] pos_sum = pos_raw + rot_nib;             // 0..5083
    wire [POSW-1:0] pos_eff = (pos_sum >= TOTAL_NIBBLES) ? (pos_sum - TOTAL_NIBBLES)
                                                         : pos_sum;

    // reference nibble for the CURRENT effective position
    wire [3:0] ref_nib = ref_rom[pos_eff[11:0]];
    wire [3:0] diff_bits = m_bits_tdata ^ ref_nib;
    // popcount of a 4-bit value
    wire [2:0] nbit_err = diff_bits[0] + diff_bits[1] + diff_bits[2] + diff_bits[3];

    // is THIS beat the checker's frame boundary (symbol 11 -> 0)?
    wire frame_boundary = beat & m_bits_tlast & started & (sym_in_frame == NUM_DATA-1);

    // -----------------------------------------------------------------
    // FRAME-PHASE PERSISTS ACROSS clr (fix for the continuous-stream PHASE3
    // "bug").  The demod datapath is order-preserving and emits EXACTLY
    // NUM_DATA(12) symbols x NDATA_SC(221) carriers per frame, forever, with a
    // FIXED phase relative to the input frames (verified: the align-buffer /
    // CE ping-pong counters and pilot ROMs stay locked over 16+ gapless frames
    // -- no symbol is ever dropped, added, or reordered).  The checker's frame
    // ANCHOR (which output symbol is "frame symbol 0") is therefore established
    // ONCE, at the first m_bits beat after global reset, and is STABLE for the
    // whole run.
    //
    // The OLD code re-anchored `sym_in_frame`/`nib_in_sym`/`started` on every
    // `clr`.  A `clr` issued MID-STREAM (as PHASE3 does: ber_clear() right
    // before a gapless 16-frame window) then re-anchored symbol-0 to whatever
    // symbol happened to be flowing -> an ARBITRARY whole-symbol rotation of
    // the reference -> ~50% "errors" (78413/148512 ~= 53%) at the firmware's
    // fixed rot_off=0, even though the demod bits are BIT-EXACT.  (The
    // LONG-RUN path already worked around this by NOT re-clearing.)
    //
    // FIX: keep the frame-phase tracking (nib_in_sym / sym_in_frame / started /
    // warmup_done) across `clr`; `clr` now resets ONLY the measurement
    // accumulators + sticky flags.  The anchor stays where global-reset put it
    // (rot_off=0 aligned, per PHASE1/PHASE2), so a mid-stream re-clear no longer
    // rotates the reference -> PHASE3 gapless streaming reads BER=0.  Purely a
    // snoop-side bookkeeping change; it never touches m_bits or the datapath.
    // -----------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            // full reset: drop the anchor, clear everything.
            nib_in_sym       <= {CARW{1'b0}};
            sym_in_frame     <= {SYMW{1'b0}};
            started          <= 1'b0;
            warmup_done      <= 1'b0;
            warmup_frames    <= 16'd0;
            total_bit_errors <= 32'd0;
            frames_checked   <= 32'd0;
            total_nibbles    <= 32'd0;
            err_flags        <= 32'd0;
        end else begin
            // -----------------------------------------------------------------
            // MEASUREMENT reset on clr : clr re-arms the warm-up and zeroes the
            // accumulators / sticky flags.  It does NOT touch the FRAME-PHASE
            // (nib_in_sym / sym_in_frame / started) -- the anchor established at
            // global reset persists so rot_off stays valid across a mid-stream
            // re-clear (see header note).  A fresh warm-up frame is still
            // excluded so the first counted frame after clr is whole.
            // -----------------------------------------------------------------
            if (clr) begin
                warmup_done      <= 1'b0;
                warmup_frames    <= 16'd0;
                total_bit_errors <= 32'd0;
                frames_checked   <= 32'd0;
                total_nibbles    <= 32'd0;
                err_flags        <= 32'd0;
            end

            // -----------------------------------------------------------------
            // FRAME-PHASE tracking + measurement.  Phase advances on EVERY beat
            // (even during the clr window) so the anchor never slips; only the
            // accumulate/flag actions are gated by (!clr && warmup_done).
            // -----------------------------------------------------------------
            if (beat) begin
                // ---- sanity flags (only when counting: warm-up done and not clr) ----
                if (!clr && started && warmup_done) begin
                    if (m_bits_tlast && (nib_in_sym != NDATA_SC-1))
                        err_flags[0] <= 1'b1;              // tlast off carrier-count
                    if (!m_bits_tlast && (nib_in_sym == NDATA_SC-1))
                        err_flags[1] <= 1'b1;              // overrun: no tlast at 220
                end

                // ---- count this nibble (after warm-up, not during clr) ----
                if (!clr && started && warmup_done) begin
                    total_nibbles    <= total_nibbles + 32'd1;
                    total_bit_errors <= total_bit_errors + nbit_err;
                end

                // =====================================================
                // POSITION free-run + frame-boundary bookkeeping (ALWAYS on a
                // beat, regardless of clr, so the anchor phase never slips).
                // The one-time anchor is taken at the first beat after GLOBAL
                // reset (started 0->1); clr no longer re-anchors.
                // =====================================================
                if (!started) begin
                    // FIRST beat after global reset = frame symbol 0, carrier 0.
                    started      <= 1'b1;
                    sym_in_frame <= {SYMW{1'b0}};
                    if (m_bits_tlast) begin
                        nib_in_sym   <= {CARW{1'b0}};
                        sym_in_frame <= {SYMW{1'b0}} + 1'b1;
                    end else begin
                        nib_in_sym <= 8'd1;
                    end
                end else if (m_bits_tlast) begin
                    // symbol completed -> next symbol, wrapping 11 -> 0 (mod 12).
                    nib_in_sym <= {CARW{1'b0}};
                    if (sym_in_frame == NUM_DATA-1) begin
                        sym_in_frame <= {SYMW{1'b0}};
                        // FRAME BOUNDARY.  warmup_done / frames_checked advance
                        // only when NOT in the clr window (clr owns those regs
                        // this cycle via the block above).
                        if (!clr) begin
                            if (!warmup_done) begin
                                warmup_done   <= 1'b1;      // begin counting next frame
                                warmup_frames <= warmup_frames + 16'd1;
                            end else begin
                                frames_checked <= frames_checked + 32'd1;
                            end
                        end
                    end else begin
                        sym_in_frame <= sym_in_frame + 1'b1;
                    end
                end else if (m_bits_tuser) begin
                    nib_in_sym <= 8'd1;                 // symbol-0 carrier resync
                end else begin
                    nib_in_sym <= nib_in_sym + 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------------------
    // status mux : one 32-bit input GPIO reads any counter via status_sel
    // -----------------------------------------------------------------
    always @(*) begin
        case (status_sel)
            4'h0: status_data = total_bit_errors;
            4'h1: status_data = frames_checked;
            4'h2: status_data = total_nibbles;
            4'h3: status_data = err_flags;
            4'h4: status_data = {15'd0, warmup_done, warmup_frames};
            4'h5: status_data = {16'hBE11, 8'd0, rot_off, 2'b00, started, warmup_done}; // signature/liveness
            default: status_data = 32'hDEAD_BE11;
        endcase
    end

endmodule
`default_nettype wire
