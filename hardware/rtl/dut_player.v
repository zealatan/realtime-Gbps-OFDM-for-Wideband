`timescale 1ns/1ps
// =============================================================
//  dut_player.v
//
//  PURPOSE:
//    BRAM-fed AXI4-Stream MASTER that plays a stored OFDM stimulus
//    frame into the DUT's s_axis. It is a DMA-free replacement for
//    the AXI DMA MM2S engine: the stimulus frame is loaded into an
//    on-chip BRAM (either at synthesis time via $readmemh, or at
//    runtime word-by-word over a GPIO load port), then streamed out
//    on demand.
//
//  STIMULUS LAYOUT (default PLAY_LEN=4160):
//    64 pre-zero + 4032 slot + 64 post-zero = 4160 words. BRAM depth
//    is 8192 (AW=13) which comfortably holds the frame.
//
//  CTRL bit layout (shared contract — MUST match the integrator):
//    ctrl[14]    = play_en   (start playback on RISING edge)
//    ctrl[15]    = load_en   (BRAM write strobe; one word / rising edge)
//    ctrl[28:16] = load_addr[12:0] (BRAM write address, 13-bit)
//
//  READ-PATH / BACKPRESSURE (mirrors the fixed meyr_sync_capture.v):
//    out_tdata_r is a SYNCHRONOUS (registered) read of stim_mem[raddr];
//    it doubles as the AXIS output holding register. It is loaded — and
//    raddr/out_count advance — ONLY when the output slot is free or the
//    held beat is being accepted this cycle (!m_axis_tvalid||m_axis_tready).
//    This honors m_axis_tready strictly: a stalled consumer can never
//    cause a beat to be dropped or duplicated, and the 1-cycle BRAM read
//    latency is absorbed by the holding register.
//
//  Synthesizable Verilog-2001 (no SystemVerilog).
// =============================================================
module dut_player #(
    parameter integer DW        = 32,
    parameter integer AW        = 13,
    parameter integer PLAY_LEN  = 4160,
    parameter integer TLAST_IDX = 4159,
    parameter integer LEAD_IN   = 0,   // warmup zero-beats streamed BEFORE the
                                       // frame so the DUT sync pipeline is primed
                                       // regardless of a vector's own pre-padding
                                       // (fixes early-frame mis-detect on HW)
    parameter         INIT_FILE = ""
)(
    input  wire             aclk,
    input  wire             aresetn,

    input  wire [31:0]      ctrl,        // loop_ctrl_gpio (async) — 2-FF sync
    input  wire [31:0]      stim_wdata,  // stim_load_gpio (BRAM write data)

    output wire [DW-1:0]    m_axis_tdata,
    output wire             m_axis_tvalid,
    input  wire             m_axis_tready,
    output wire             m_axis_tlast,

    output wire [31:0]      status       // {done, running, ..., out_count[15:0]}
);

    localparam integer CW = (PLAY_LEN > 65536) ? 32 : 17; // out_count width

    // ---------------------------------------------------------
    //  BRAM stimulus store. Depth 1<<AW (8192 for AW=13).
    // ---------------------------------------------------------
    (* ram_style = "block" *) reg [DW-1:0] stim_mem [0:(1<<AW)-1];

    // Optional synthesis-time init (guarded; iverilog-friendly).
    initial begin
        if (INIT_FILE != "") $readmemh(INIT_FILE, stim_mem);
    end

    // ---------------------------------------------------------
    //  Control synchronizer (2-FF ASYNC_REG) + rising-edge detect.
    // ---------------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_meta;
    (* ASYNC_REG = "TRUE" *) reg [31:0] ctrl_sync;
    reg                                  play_en_d; // delayed for edge detect
    reg                                  load_en_d;

    wire        play_en   = ctrl_sync[14];
    wire        load_en   = ctrl_sync[15];
    wire        loop_en   = ctrl_sync[29]; // continuous: replay the frame forever
                                            // (bit29 free: avoids capture rd_index[13:2])
    wire [AW-1:0] load_addr = ctrl_sync[16 +: AW]; // ctrl[28:16] for AW=13

    wire play_rise = play_en & ~play_en_d;
    wire load_rise = load_en & ~load_en_d;

    // ---------------------------------------------------------
    //  Playback state.
    // ---------------------------------------------------------
    reg [AW-1:0]   raddr;
    reg [CW-1:0]   out_count;
    reg [15:0]     lead_cnt;     // counts the LEAD_IN warmup zero-beats
    reg            in_lead;      // high while streaming the warmup zeros
    reg            running;
    reg            done;

    // Registered-output AXIS holding register (1-cycle BRAM read).
    reg [DW-1:0]   out_tdata_r;
    reg            out_tvalid_r;
    reg            out_tlast_r;

    assign m_axis_tdata  = out_tdata_r;
    assign m_axis_tvalid = out_tvalid_r;
    assign m_axis_tlast  = out_tlast_r;

    assign status = {done, running, {(30-16){1'b0}}, out_count[15:0]};

    // Slot is free to load when no beat is held, or the held beat is
    // being accepted this cycle.
    wire load_slot = (!out_tvalid_r) || m_axis_tready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            ctrl_meta    <= 32'd0;
            ctrl_sync    <= 32'd0;
            play_en_d    <= 1'b0;
            load_en_d    <= 1'b0;
            raddr        <= {AW{1'b0}};
            out_count    <= {CW{1'b0}};
            lead_cnt     <= 16'd0;
            in_lead      <= 1'b0;
            running      <= 1'b0;
            done         <= 1'b0;
            out_tdata_r  <= {DW{1'b0}};
            out_tvalid_r <= 1'b0;
            out_tlast_r  <= 1'b0;
        end else begin
            // -- Control sync + edge-detect delay regs --------------
            ctrl_meta <= ctrl;
            ctrl_sync <= ctrl_meta;
            play_en_d <= play_en;
            load_en_d <= load_en;

            // -- Runtime BRAM load (one word per load_en rising edge) --
            if (load_rise) begin
                stim_mem[load_addr] <= stim_wdata;
            end

            // -- Start playback on play_en rising edge -------------
            //    (ignored while a playback is in flight).
            if (play_rise && !running) begin
                raddr        <= {AW{1'b0}};
                out_count    <= {CW{1'b0}};
                lead_cnt     <= 16'd0;
                in_lead      <= (LEAD_IN != 0); // prime the warmup phase
                running      <= 1'b1;
                done         <= 1'b0;
                out_tvalid_r <= 1'b0;
                out_tlast_r  <= 1'b0;
            end else if (running) begin
                // -- Stream side: registered read + strict backpressure.
                //    Load holding reg / advance address ONLY when the
                //    output slot is free or being accepted this cycle.
                if (load_slot) begin
                    if (in_lead) begin
                        // -- Warmup phase: stream LEAD_IN zero beats to prime the
                        //    DUT sync pipeline before any frame data arrives.
                        out_tdata_r  <= {DW{1'b0}};
                        out_tvalid_r <= 1'b1;
                        out_tlast_r  <= 1'b0;
                        if (lead_cnt == LEAD_IN-1) in_lead <= 1'b0;
                        lead_cnt     <= lead_cnt + 1'b1;
                    end else if (out_count < PLAY_LEN) begin
                        out_tdata_r  <= stim_mem[raddr]; // sync read
                        out_tvalid_r <= 1'b1;
                        out_tlast_r  <= (out_count == TLAST_IDX);

                        if (out_count == PLAY_LEN-1) begin
                            // Last beat (with tlast) is being presented.
                            if (loop_en) begin
                                // Continuous mode: wrap back to sample 0 so the
                                // DUT sees an uninterrupted stream of repeated
                                // frames (mirrors the P5-CONT sim streaming that
                                // the sync chain needs; one-shot starves it).
                                raddr     <= {AW{1'b0}};
                                out_count <= {CW{1'b0}};
                            end else begin
                                // One-shot: advance to PLAY_LEN -> retire next.
                                out_count <= out_count + 1'b1;
                            end
                        end else begin
                            raddr     <= raddr + 1'b1;
                            out_count <= out_count + 1'b1;
                        end
                    end else begin
                        // All PLAY_LEN beats have been loaded AND the last
                        // one has just been accepted (load_slot true with
                        // a valid held beat ⇒ acceptance). Retire one-shot.
                        out_tvalid_r <= 1'b0;
                        out_tlast_r  <= 1'b0;
                        running      <= 1'b0;
                        done         <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
