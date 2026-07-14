`timescale 1ns/1ps
// =============================================================
//  meyr_sync_capture.v
//
//  PURPOSE:
//    Bridge between meyr_slot_frontend (continuous payload stream)
//    and meyr_cfo_top (AXI-Stream consumer that occasionally
//    deasserts s_tready while reconfiguring its non-realtime FFTs).
//    Buffers 2N samples (PSS payload + SSS payload), then streams
//    them into the core with proper handshake.
//
//  GUARANTEES:
//    - Write side ALWAYS accepts (downstream never drops a sample);
//      slot_frontend output is gated to land inside the buffer.
//    - Read side honors core.out_tready strictly.
//    - PSS-then-SSS order preserved by linear write addressing.
//    - r1_pending is driven from a SINGLE always-block (this module's
//      capture FSM) — no race between estimator-side and ingest-side.
//
//  STORAGE / READ-PATH:
//    Inferred small RAM (2N x DATA_W). Read is combinational so a
//    single output register on the consumer side delivers 1 beat /
//    cycle without an internal skid buffer. For 256-subcarrier
//    config 2N x 32 = 16 Kbit which Vivado maps to distributed RAM
//    (LUTRAM). Switch the ram_style attribute to "block" if the
//    parameter pushes the capacity past LUTRAM density.
//
//  OVERRUN POLICY:
//    If pss_first_beat fires while a previous capture has not been
//    drained, overrun_event pulses for one cycle and the new
//    capture replaces the in-flight one. Documented "newest-PSS
//    wins" policy: guarantees forward progress on bursty slot
//    starts and keeps the integer-CFO estimate aligned to the most
//    recent slot.
// =============================================================
module meyr_sync_capture #(
    parameter integer N         = 256,
    parameter integer DATA_W    = 32
)(
    input  wire              clk,
    input  wire              rst_n,

    // ---- Ingest from meyr_slot_frontend ----
    input  wire [DATA_W-1:0] in_tdata,
    input  wire              in_tvalid,
    // First-PSS-beat marker. Sampled when in_tvalid is high.
    input  wire              pss_first_beat,
    // First-SSS-beat marker. When it fires mid-FILL, SSS sample 0 is force-
    // pinned to mem[N] so the SSS window is immune to PSS-region beat-count
    // drift (the integer-CFO +60 bug: SSS landed a few samples off mem[N]).
    input  wire              sss_first_beat,

    // ---- Egress to meyr_cfo_top ----
    output wire [DATA_W-1:0] out_tdata,
    output wire              out_tvalid,
    input  wire              out_tready,

    // ---- Diagnostics ----
    output reg               overrun_event,
    output reg               capture_done
);

    localparam integer DEPTH   = 2*N;
    localparam integer A_WIDTH = $clog2(DEPTH);

    // P5-10 timing cut: BRAM-backed with registered read so Vivado
    // infers the BRAM hard output register. Adds 1 cycle to the
    // read path (mem → out_tdata).
    (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:DEPTH-1];

    // FSM:
    //   IDLE    : waiting for pss_first_beat
    //   FILL    : writing 2N samples
    //   STREAM  : presenting beats while out_tready is sampled high
    //   DRAIN   : final beat handed off; return to IDLE next cycle
    //
    // r1_pending is asserted while STREAM|DRAIN and cleared on
    // completion. Driven only inside this single always-block.
    localparam [1:0] S_IDLE   = 2'd0;
    localparam [1:0] S_FILL   = 2'd1;
    localparam [1:0] S_STREAM = 2'd2;
    localparam [1:0] S_DRAIN  = 2'd3;

    reg [1:0]         state;
    reg [A_WIDTH-1:0] wr_addr;
    reg [A_WIDTH-1:0] rd_addr;
    reg               r1_pending;

    // P5-10 registered read for BRAM inference + AXIS backpressure.
    // out_tdata_r is a registered (synchronous) read of mem[rd_addr]; it
    // doubles as the AXIS output holding register. It is loaded ONLY when
    // the output slot is free or the current beat is being accepted
    // (!out_tvalid_r || out_tready); rd_addr advances in lockstep with the
    // load. This makes the read path honor out_tready strictly — a stalled
    // consumer can never drop or duplicate a beat. (Previously these were
    // driven unconditionally every cycle, which dropped beats under
    // backpressure and duplicated the first beat.) All driven from the
    // single capture FSM below.
    reg [DATA_W-1:0] out_tdata_r;
    reg              out_tvalid_r;
    assign out_tdata  = out_tdata_r;
    assign out_tvalid = out_tvalid_r;

    wire fill_accept = (state == S_FILL) && in_tvalid;
    wire start_accept = (state == S_IDLE) && pss_first_beat && in_tvalid;
    wire overrun_kick = pss_first_beat && in_tvalid && (state != S_IDLE);
    // SSS re-pin: first SSS payload beat during FILL → force it to mem[N],
    // making the SSS window position independent of the PSS-region beat count.
    wire sss_repin    = (state == S_FILL) && sss_first_beat && in_tvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            wr_addr       <= {A_WIDTH{1'b0}};
            rd_addr       <= {A_WIDTH{1'b0}};
            r1_pending    <= 1'b0;
            overrun_event <= 1'b0;
            capture_done  <= 1'b0;
            out_tdata_r   <= {DATA_W{1'b0}};
            out_tvalid_r  <= 1'b0;
        end else begin
            overrun_event <= 1'b0;
            capture_done  <= 1'b0;

            // -- Overrun takes priority and resets the egress -------------
            if (overrun_kick) begin
                overrun_event <= 1'b1;
                state         <= S_FILL;
                mem[0]        <= in_tdata;
                wr_addr       <= {{(A_WIDTH-1){1'b0}}, 1'b1};
                rd_addr       <= {A_WIDTH{1'b0}};
                r1_pending    <= 1'b0;
                out_tvalid_r  <= 1'b0;   // drop any in-flight egress beat
            end else begin
                // -- Write side -------------------------------------------
                if (start_accept) begin
                    state   <= S_FILL;
                    mem[0]  <= in_tdata;
                    wr_addr <= {{(A_WIDTH-1){1'b0}}, 1'b1};
                end else if (sss_repin) begin
                    // Force SSS payload sample 0 to land at mem[N] (mirrors the
                    // PSS mem[0] pin). Immune to PSS-region beat-count drift.
                    mem[N]  <= in_tdata;
                    wr_addr <= N[A_WIDTH-1:0] + 1'b1;
                end else if (fill_accept) begin
                    mem[wr_addr] <= in_tdata;
                    if (wr_addr == DEPTH-1) begin
                        state      <= S_STREAM;
                        r1_pending <= 1'b1;
                        wr_addr    <= {A_WIDTH{1'b0}};
                        rd_addr    <= {A_WIDTH{1'b0}};
                    end else begin
                        wr_addr <= wr_addr + 1'b1;
                    end
                end

                // -- Read / stream side: registered-output AXIS with
                //    strict backpressure. Load the output holding register
                //    (and advance rd_addr) ONLY when the slot is free or the
                //    held beat is being accepted this cycle.
                if (state == S_STREAM) begin
                    if (!out_tvalid_r || out_tready) begin
                        out_tdata_r  <= mem[rd_addr]; // sync read of current addr
                        out_tvalid_r <= 1'b1;
                        if (rd_addr == DEPTH-1)
                            state <= S_DRAIN;          // last beat now loaded
                        else
                            rd_addr <= rd_addr + 1'b1;
                    end
                end else if (state == S_DRAIN) begin
                    // Hold the final beat until the consumer accepts it,
                    // then retire the capture.
                    if (!out_tvalid_r || out_tready) begin
                        out_tvalid_r <= 1'b0;
                        r1_pending   <= 1'b0;
                        capture_done <= 1'b1;
                        state        <= S_IDLE;
                    end
                end
            end
        end
    end

endmodule
