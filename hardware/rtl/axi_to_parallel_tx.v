`timescale 1ns/1ps
`default_nettype none
// =====================================================================
// axi_to_parallel_tx.v
// ---------------------------------------------------------------------
// AXI-Stream SLAVE -> parallel TX-payload bridge for the OFDM transceiver.
//
// Accumulates an MM2S AXI-Stream payload (from an AXI DMA reading DDR)
// into the 10608-bit `data_bits_flat4` parallel vector that feeds the
// frozen tx_ofdm_top modulator (12 sym x 221 data-SC x 4 bits = 10608).
//
// BIT-ORDER CONTRACT (matches tx_data_bits_packed.hex EXACTLY, and the
// on-chip ROM, verified 0-diff vs golden tx_bits.txt):
//     data_bits_flat4[gw*32 +: 32] = payload_word[gw]     (gw = 0..331)
// The Nth accepted 32-bit beat is stored at word slot N. The final (332nd)
// beat contributes only its low 16 bits (10608 = 331*32 + 16).
//
// IMPLEMENTATION NOTE (why WORD ARRAYS, not one wide reg):
//   The banks are 332x32 WORD register arrays (word-addressed write, full
//   combinational read reassembled into the flat vector) — structurally the
//   SAME shape as the golden db_rom. An earlier version used a single
//   monolithic 10608-bit reg with a VARIABLE BIT part-select for the write;
//   that inferred a 10608-wide barrel shifter + 21k-FF register and blew up
//   synthesis memory (OOM). Word arrays keep the write a simple word decode.
//
// DOUBLE-BUFFER:
//   Two 332-word banks. The stream writes the "fill" bank; on the final beat
//   the fill bank becomes "active" (feeds the modulator) and load_done pulses.
//   tx_ofdm_top reads data_bits_flat4 combinationally per symbol across the
//   whole slot, so the active bank stays stable for the entire slot. The host
//   can stage the NEXT frame into the fill bank while the current one emits.
//
// FALLBACK / SELECT:
//   use_dma=0            -> data_bits_flat4 = rom_flat4 (golden, pre-DMA-exact)
//   use_dma=1, no frame  -> rom_flat4 (bank_valid=0 safe start)
//   use_dma=1, bank valid-> the active DMA bank (arbitrary payload)
//
// Synthesizable Verilog-2001 (no SystemVerilog).
// =====================================================================
module axi_to_parallel_tx #(
    parameter integer NDATA_BITS = 10608,          // 12*221*4
    parameter integer SW         = 32,             // stream width (match ROM word)
    parameter integer WORDS      = (NDATA_BITS + SW - 1) / SW   // 332
)(
    input  wire                     aclk,
    input  wire                     aresetn,

    input  wire [NDATA_BITS-1:0]    rom_flat4,     // golden fallback (combinational)
    input  wire                     use_dma,

    input  wire [SW-1:0]            s_axis_tdata,
    input  wire                     s_axis_tvalid,
    output wire                     s_axis_tready,
    input  wire                     s_axis_tlast,

    output wire [NDATA_BITS-1:0]    data_bits_flat4,
    output wire                     load_done,
    output wire [15:0]              beat_count,
    output wire [15:0]              frame_count,

    // debug readback: word `dbg_rdaddr` of the ACTIVE bank (what the TX emits),
    // so firmware can verify the DMA delivered correct bytes into the bank.
    input  wire [8:0]               dbg_rdaddr,
    output wire [SW-1:0]            dbg_rdword
);
    localparam integer AW = 9;   // ceil(log2(332))

    assign s_axis_tready = 1'b1; // short payload; bridge never back-pressures

    wire beat = s_axis_tvalid & s_axis_tready;

    reg [AW-1:0] widx;           // fill word pointer 0..WORDS-1
    reg          fill_bank;
    reg          active_bank;
    reg          bank_valid;
    reg [15:0]   frames;
    reg          load_done_r;

    // 332x32 word banks (distributed/register-file; same shape as the ROM).
    reg [SW-1:0] bank0 [0:WORDS-1];
    reg [SW-1:0] bank1 [0:WORDS-1];

    // FRAME BOUNDARY = s_axis_tlast (the AXI DMA asserts tlast on the final beat
    // of every LENGTH-bounded MM2S transfer). Keying the swap/pointer-reset on
    // tlast RE-SYNCS the bridge to the DMA framing on EVERY transfer, so a stray
    // beat or a prior partial fill can no longer desync later frames (bug2). widx
    // is CLAMPED at WORDS-1 as a pure overflow guard (drop extra beats past the
    // bank) -- the boundary is tlast, never the count. For the fixed 332-beat
    // payload tlast lands exactly at widx==WORDS-1, so a full bank is captured.
    wire ovf = (widx == WORDS[AW-1:0]-1'b1);

    assign load_done   = load_done_r;
    assign beat_count  = {{(16-AW){1'b0}}, widx};
    assign frame_count = frames;

    always @(posedge aclk) begin
        if (!aresetn) begin
            widx        <= {AW{1'b0}};
            fill_bank   <= 1'b0;
            active_bank <= 1'b0;
            bank_valid  <= 1'b0;
            frames      <= 16'd0;
            load_done_r <= 1'b0;
        end else begin
            load_done_r <= 1'b0;
            if (beat) begin
                // word-addressed write (no bit part-select -> cheap decode)
                if (!fill_bank) bank0[widx] <= s_axis_tdata;
                else            bank1[widx] <= s_axis_tdata;
                if (s_axis_tlast) begin
                    active_bank <= fill_bank;   // just-filled bank goes active
                    fill_bank   <= ~fill_bank;
                    widx        <= {AW{1'b0}};  // resync pointer every transfer
                    frames      <= frames + 16'd1;
                    bank_valid  <= 1'b1;
                    load_done_r <= 1'b1;
                end else if (!ovf) begin
                    widx <= widx + 1'b1;
                end
                // else (ovf & !tlast): hold widx at WORDS-1, drop the extra beat
            end
        end
    end

    // Combinational reassembly of the active bank into the flat vector,
    // IDENTICAL to how the golden ROM builds rom_flat4 from db_rom.
    wire [NDATA_BITS-1:0] dma_flat4;
    genvar gw;
    localparam integer LAST_BITS = NDATA_BITS - (WORDS-1)*SW;   // 16
    generate
        for (gw = 0; gw < WORDS; gw = gw + 1) begin : g_reassemble
            wire [SW-1:0] wsel = active_bank ? bank1[gw] : bank0[gw];
            if ((gw*SW + SW) <= NDATA_BITS) begin : g_full
                assign dma_flat4[gw*SW +: SW] = wsel;
            end else begin : g_part
                assign dma_flat4[gw*SW +: LAST_BITS] = wsel[LAST_BITS-1:0];
            end
        end
    endgenerate

    assign data_bits_flat4 = (use_dma && bank_valid) ? dma_flat4 : rom_flat4;

    // debug readback of the active bank (combinational; firmware selects addr)
    assign dbg_rdword = active_bank ? bank1[dbg_rdaddr] : bank0[dbg_rdaddr];

endmodule

`default_nettype wire
