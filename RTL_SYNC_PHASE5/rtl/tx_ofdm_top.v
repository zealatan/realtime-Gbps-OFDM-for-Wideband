// =====================================================================
// tx_ofdm_top.v
// ---------------------------------------------------------------------
// OFDM TRANSMITTER integration TOP.  Builds ONE complete 4032-sample
// transmit slot (the synchronizer's frame, minus the 64 pre/post zeros):
//
//      [ 2 REAL PSS/SSS sync symbols : 576 samples ]   (from sync ROM)
//      [ 12 data symbols x 288       : 3456 samples]   (TX chain below)
//      ----------------------------------------------
//                                       4032 samples   {Q,I} Q15
//
//   data path per symbol:
//        data bits (884) + pilot ROM (32 QPSK)
//             |
//   +---------v-----------+   16-QAM map + pilot insert + subcarrier
//   | tx_subcarrier_map   |   assembly + fftshift  -> 256 spectrum bins
//   +---------+-----------+
//             |  (fftshift-ordered spectrum, {Q,I})
//   +---------v-----------+   256-pt IDFT (xfft_N inverse, BFP) + 1/16
//   | tx_ifft_frontend    |   recover + CP insert  -> 288 time samples
//   +---------+-----------+
//             |  (288-sample data symbol, {Q,I} Q15)
//             v
//   +-------------------------------------------------------------+
//   |  OUTPUT MUX : emit 576 sync ROM samples, then stream the 12 |
//   |  data symbols' 288-sample outputs back-to-back.             |
//   +-------------------------------------------------------------+
//             v  m_axis  (4032 {Q,I} Q15, m_last on sample 4031)
//
//   Reproduces ref/transmitter.c generate_transmit_slot for the 14-symbol
//   slot and matches golden/rx_downstream/tx_slot_iq_4032.hex (the sync
//   region is byte-identical, the 12 data symbols within the IFFT BFP
//   truncation budget).
//
// ---------------------------------------------------------------------
// CONTROL / SEQUENCING
// ---------------------------------------------------------------------
//   start (1-cycle pulse) kicks off a slot.  An FSM:
//     1. streams 576 sync ROM words to the master (SYNC phase),
//     2. for z = 0..11 : pulses sym_start to tx_subcarrier_map with the
//        z-th symbol's 884 data bits, lets the chain produce a 288-sample
//        symbol, and forwards those samples to the master (DATA phase).
//   The two stages of the data chain are pipelined-streaming, so once
//   started a symbol's spectrum bins flow continuously into the IFFT and
//   its time samples flow out; the FSM pulses sym_start for symbol z+1 as
//   soon as the mapper is free (it is double-buffered downstream).
//
//   Data bits source: a flat 12x884 bit memory `data_bits_flat`, provided
//   by the caller (TB loads golden tx_bits).  Pilot ROM: a 384-word
//   {Q,I} ROM streamed in pilot order (32/symbol) via pilot_tdata.
//
//   1 sample/clock, full AXI-Stream tready on the master.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_ofdm_top #(
    parameter integer DATA_W   = 16,
    parameter integer NSC      = 256,
    parameter integer CP_LEN   = 32,
    parameter integer NUM_SYN  = 2,
    parameter integer NUM_DATA = 12,
    parameter integer NPIL     = 32,
    parameter integer NDATA_SC = 221,
    parameter integer BPC_MAX  = 8,     // max data bits/carrier (256-QAM)
    parameter integer Q16_1    = 1610,
    parameter integer Q16_3    = 4829,
    parameter         SPECMAP  = "rtl/tx_rom/tx_specmap.hex",
    parameter         SYNC_ROM = "rtl/tx_rom/tx_sync_rom.hex"
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // ---- modulation select for the data map (pilots stay QPSK) ----
    input  wire [1:0]              mod_sel,    // 0=QPSK 1=16QAM 2=64QAM 3=256QAM

    // ---- control ----
    input  wire                    start,      // 1-cycle pulse: emit a slot
    output wire                    busy,

    // ---- data bits : flat 12 * NDATA_SC * BPC_MAX bit memory ----
    //   bit (z*NDATA_SC*BPC_MAX + k*BPC_MAX + b) = bit b of data carrier k
    //   of symbol z. Active bits/carrier = 2*(mod_sel+1); high bits ignored.
    //   The FSM presents the active symbol's window to the mapper.
    input  wire [NUM_DATA*NDATA_SC*BPC_MAX-1:0] data_bits_flat,

    // ---- pilot ROM : 384 {Q,I} Q15 words (symbol-major: z*32 + p).
    //      The top exposes a {symbol, pilot-index} read address; the
    //      caller returns the addressed QPSK pilot word. ----
    output wire [8:0]              pilot_addr,          // z_map*32 + p (0..383)
    input  wire [2*DATA_W-1:0]     pilot_tdata,

    // ---- master : 4032-sample slot, {Q,I} Q15 ----
    output wire                    m_valid,
    input  wire                    m_ready,
    output wire [2*DATA_W-1:0]     m_tdata,
    output wire                    m_last      // sample 4031 of the slot
);
    localparam integer SYNC_LEN = NUM_SYN * (NSC + CP_LEN);      // 576
    localparam integer SYM_LEN  = NSC + CP_LEN;                  // 288
    localparam integer SLOT_LEN = (NUM_SYN + NUM_DATA) * SYM_LEN; // 4032

    // =================================================================
    // sync ROM (576 words, {Q,I} Q15) -- the 2 REAL PSS/SSS symbols
    // =================================================================
    reg [31:0] sync_rom [0:SYNC_LEN-1];
    initial $readmemh(SYNC_ROM, sync_rom);

    // =================================================================
    // FSM
    // =================================================================
    localparam [1:0] S_IDLE = 2'd0,
                     S_SYNC = 2'd1,
                     S_DATA = 2'd2;
    reg [1:0]  state;
    reg [9:0]  sync_pos;      // 0..575
    reg [3:0]  z;             // data symbol index 0..11
    reg        slot_done;     // emitted last slot sample

    assign busy = (state != S_IDLE);

    // ---- mapper input symbol index (the symbol being STARTED), distinct
    //      from `z` which tracks the symbol being OUTPUT (pipeline skew) ----
    reg [3:0] z_map;          // 0..11 : data symbol currently fed to mapper

    // ---- active symbol's data-bit window to the mapper ----
    reg [NDATA_SC*BPC_MAX-1:0] bits_win;
    integer bw;
    always @(*) begin
        for (bw = 0; bw < NDATA_SC*BPC_MAX; bw = bw + 1)
            bits_win[bw] = data_bits_flat[z_map*NDATA_SC*BPC_MAX + bw];
    end

    // ---- subcarrier mapper ----
    reg          map_start;
    wire         spec_valid;
    wire         spec_ready;
    wire [31:0]  spec_tdata;
    wire         spec_last;

    wire [4:0] map_pilot_idx;     // 0..31 from the mapper
    // symbol-major pilot ROM address = z_map*32 + pilot_idx
    assign pilot_addr = {z_map, 5'd0} + {4'd0, map_pilot_idx};

    tx_subcarrier_map #(
        .DATA_W(DATA_W), .NSC(NSC), .NPIL(NPIL), .NDATA_SC(NDATA_SC),
        .BPC_MAX(BPC_MAX), .Q16_1(Q16_1), .Q16_3(Q16_3), .SPECMAP(SPECMAP)
    ) u_map (
        .clk(clk), .rst_n(rst_n),
        .mod_sel(mod_sel),
        .sym_start(map_start),
        .data_bits(bits_win),
        .pilot_addr(map_pilot_idx),
        .pilot_tdata(pilot_tdata),
        .m_valid(spec_valid), .m_ready(spec_ready),
        .m_tdata(spec_tdata), .m_last(spec_last)
    );

    // ---- IFFT + CP front-end ----
    wire         dsym_valid;
    wire         dsym_ready;
    wire [31:0]  dsym_tdata;
    wire         dsym_last;     // sample 287 of a data symbol

    tx_ifft_frontend #(
        .DATA_W(DATA_W), .NSC(NSC), .CP_LEN(CP_LEN), .SCALE_SH(4)
    ) u_ifft (
        .clk(clk), .rst_n(rst_n),
        .s_valid(spec_valid), .s_ready(spec_ready),
        .s_tdata(spec_tdata), .s_last(spec_last),
        .m_valid(dsym_valid), .m_ready(dsym_ready),
        .m_tdata(dsym_tdata), .m_last(dsym_last)
    );

    // =================================================================
    // OUTPUT MUX + slot sample counter
    // =================================================================
    reg  [12:0] slot_pos;     // 0..4031
    wire        in_sync = (slot_pos < SYNC_LEN);

    // master beat
    reg         m_valid_r;
    reg  [31:0] m_data_r;
    reg         m_last_r;
    wire        m_fire = m_valid_r && m_ready;
    wire        out_room = (!m_valid_r) || m_ready;

    // data-symbol stream is consumed by the mux only in DATA phase
    assign dsym_ready = (state == S_DATA) && !in_sync && out_room;

    // which source supplies the next sample
    wire        have_sync = (state == S_SYNC) || ((state == S_DATA) && in_sync);
    wire        have_data = (state == S_DATA) && !in_sync && dsym_valid;
    wire [31:0] src_word  = have_sync ? sync_rom[sync_pos] : dsym_tdata;
    wire        have_smp  = have_sync || have_data;

    // ---- mapper / symbol dispatch : track how many data symbols started ----
    reg [3:0] z_started;      // count of sym_start pulses issued (0..12)

    // shadow of the mapper's busy state: tx_subcarrier_map asserts m_valid
    // while busy; busy falls the cycle after its last bin is accepted.
    reg u_map_busy;
    wire      map_free = !u_map_busy;     // mapper idle -> can start next symbol

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) u_map_busy <= 1'b0;
        else begin
            if (map_start)            u_map_busy <= 1'b1;
            else if (spec_valid && spec_ready && spec_last) u_map_busy <= 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            sync_pos  <= 10'd0;
            slot_pos  <= 13'd0;
            z         <= 4'd0;
            z_map     <= 4'd0;
            z_started <= 4'd0;
            map_start <= 1'b0;
            slot_done <= 1'b0;
            m_valid_r <= 1'b0;
            m_data_r  <= 32'd0;
            m_last_r  <= 1'b0;
        end else begin
            map_start <= 1'b0;
            slot_done <= 1'b0;

            case (state)
                S_IDLE: begin
                    // drain the final beat of a completed slot: clear valid
                    // once the last presented sample has been accepted.
                    if (m_valid_r && m_ready) begin
                        m_valid_r <= 1'b0;
                        m_last_r  <= 1'b0;
                    end
                    if (start && !m_valid_r) begin
                        state     <= S_SYNC;
                        sync_pos  <= 10'd0;
                        slot_pos  <= 13'd0;
                        z         <= 4'd0;
                        z_started <= 4'd0;
                        // kick the FIRST data symbol's mapper immediately so
                        // its 288 samples are ready by the time sync drains.
                        map_start <= 1'b1;
                        z_map     <= 4'd0;     // mapper latches symbol 0 next cyc
                        z_started <= 4'd1;
                    end
                end

                S_SYNC: begin
                    // (data symbol 0 is being produced in the background)
                    // start subsequent data symbols as the mapper frees up
                    if (map_free && !map_start && (z_started < NUM_DATA)) begin
                        map_start <= 1'b1;
                        z_map     <= z_started;          // latch this symbol next cyc
                        z_started <= z_started + 4'd1;
                    end
                    if (out_room) begin
                        m_data_r  <= src_word;     // have_sync guaranteed here
                        m_valid_r <= 1'b1;
                        m_last_r  <= 1'b0;
                        sync_pos  <= sync_pos + 10'd1;
                        slot_pos  <= slot_pos + 13'd1;
                        if (slot_pos == SYNC_LEN-1) begin
                            state <= S_DATA;
                        end
                    end else if (!have_smp) begin
                        m_valid_r <= m_valid_r & ~m_ready;
                    end
                end

                S_DATA: begin
                    // keep launching data symbols until all 12 are started
                    if (map_free && !map_start && (z_started < NUM_DATA)) begin
                        map_start <= 1'b1;
                        z_map     <= z_started;          // latch this symbol next cyc
                        z_started <= z_started + 4'd1;
                    end
                    if (out_room) begin
                        if (have_data) begin
                            m_data_r  <= dsym_tdata;
                            m_valid_r <= 1'b1;
                            m_last_r  <= (slot_pos == SLOT_LEN-1);
                            slot_pos  <= slot_pos + 13'd1;
                            // advance active data symbol on each 288-boundary
                            if (dsym_last) z <= z + 4'd1;
                            if (slot_pos == SLOT_LEN-1) begin
                                state     <= S_IDLE;
                                slot_done <= 1'b1;
                            end
                        end else begin
                            // bubble: data symbol not ready yet
                            m_valid_r <= 1'b0;
                        end
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign m_valid = m_valid_r;
    assign m_tdata = m_data_r;
    assign m_last  = m_last_r;

    wire _unused = &{1'b0, slot_done, m_fire};

endmodule

`default_nettype wire
