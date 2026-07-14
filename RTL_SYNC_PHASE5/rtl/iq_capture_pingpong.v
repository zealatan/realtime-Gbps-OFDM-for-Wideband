`timescale 1ns/1ps
// =============================================================================
//  iq_capture_pingpong.v   (H1a — continuous multi-slot front-end)
//
//  PURPOSE
//    Decouple AXI-Stream acquisition from the (slow) frac+meyr processing so the
//    sync chain can run CONTINUOUS back-to-back slots without going deaf. Owns
//    the AXI ingest port and TWO iq_frame_buffer instances (A/B) in ping-pong:
//    one buffer captures slot N+1 while the other is being processed for slot N.
//
//    s_axis_tready stays HIGH as long as at least one buffer is free; it drops
//    only when BOTH buffers hold un-processed frames (processing fell behind —
//    the expected ~50% duty backpressure, since frac S_CORRECT is ~2 clk/sample).
//
//  ALIGNMENT
//    Each capture ends on s_axis_tlast (NOT buffer-full) because DEPTH (2^CAP_AW
//    = 8192) >= the stim frame (4160). So every buffer holds exactly one whole,
//    correctly-bounded frame -> the downstream frame_detector / slot arithmetic
//    line up identically slot-to-slot.
//
//  HANDOFF PROTOCOL (to the processing FSM in frac_cfo_frame_corrector_top)
//    buf_ready : level — the next-in-order captured buffer is waiting + proc idle
//    buf_len   : sample_count of that ready buffer
//    proc_take : 1-cyc — processor claims the ready buffer (latches proc_sel)
//    proc_free : 1-cyc — processor done; buffer returns to the free pool
//    rd_en/rd_addr/rd_data : random-access read of the buffer the processor owns
//
//  Capture order (A,B,A,B,...) == process order (A,B,A,B,...) so the two
//  cap_sel / proc_next pointers each just toggle; with 2 buffers this is FIFO.
//
//  Synthesizable Verilog-2001.
// =============================================================================
module iq_capture_pingpong #(
    parameter integer DATA_WIDTH = 32,
    parameter integer CAP_AW     = 13,         // DEPTH = 2^CAP_AW = 8192 >= 4160
    // CAP_LEN: frame-boundary sample count. When > 0 the active capture is
    //   forced to end (synthetic tlast) after exactly CAP_LEN accepted samples,
    //   so every buffer holds exactly ONE input frame EVEN WHEN the upstream
    //   omits a per-frame s_axis_tlast (continuous multi-frame streaming). A
    //   real s_axis_tlast that arrives EARLIER still terminates the capture.
    //   0 = disabled (legacy: capture ends only on tlast or buffer-full).
    //   Default 4160 = INPUT_PERIOD (one 4032-sample slot + 128 guard).
    parameter integer CAP_LEN    = 4160
)(
    input  wire                   aclk,
    input  wire                   aresetn,

    // ---- AXI-Stream ingest (continuous) ----
    input  wire [DATA_WIDTH-1:0]  s_axis_tdata,
    input  wire                   s_axis_tvalid,
    output wire                   s_axis_tready,
    input  wire                   s_axis_tlast,

    // ---- Handoff to processing FSM ----
    output wire                   buf_ready,
    output wire [CAP_AW:0]        buf_len,
    input  wire                   proc_take,
    input  wire                   proc_free,

    // ---- Read port for the processing FSM (addresses the owned buffer) ----
    input  wire                   rd_en,
    input  wire [CAP_AW-1:0]      rd_addr,
    output wire [DATA_WIDTH-1:0]  rd_data,

    // ---- Status / diagnostics ----
    output wire                   both_full,
    output reg                    cap_overflow
);
    localparam integer DEPTH = (1 << CAP_AW);

    // ---- ping-pong / occupancy state ----
    localparam [1:0] CAP_IDLE = 2'd0, CAP_A = 2'd1, CAP_B = 2'd2;
    reg [1:0]    cstate;       // capture FSM
    reg          last_cap;     // 0=A was last captured, 1=B — used to alternate
    reg          proc_next;    // which buffer is processed next (FIFO order)
    reg          proc_sel;     // which buffer the processor currently owns
    reg          proc_busy;    // processor holds a buffer
    reg          occ_a, occ_b; // buffer holds a captured, un-processed frame
    reg [CAP_AW:0] len_a, len_b;

    // ---- per-buffer wires ----
    wire             tready_a, tready_b;
    wire             cdone_a,  cdone_b;
    wire             busy_a,   busy_b;
    wire             full_a,   full_b;
    wire [CAP_AW:0]  scnt_a,   scnt_b;
    wire [CAP_AW-1:0] wrp_a,   wrp_b;
    wire [DATA_WIDTH-1:0] rdd_a, rdd_b;

    // A buffer is available to ARM for capture when not occupied and not the one
    // currently being processed.
    wire a_avail = !occ_a && !(proc_busy && (proc_sel == 1'b0));
    wire b_avail = !occ_b && !(proc_busy && (proc_sel == 1'b1));

    // capture_start pulses (1-cyc), issued by the capture FSM on IDLE->CAP_x.
    reg  cs_a, cs_b;

    // s_axis routed to BOTH buffers; only the buffer being captured sees tvalid,
    // so only it accepts. tready is that buffer's tready (0 while IDLE).
    wire vld_a = s_axis_tvalid && (cstate == CAP_A);
    wire vld_b = s_axis_tvalid && (cstate == CAP_B);
    assign s_axis_tready = (cstate == CAP_A) ? tready_a :
                           (cstate == CAP_B) ? tready_b : 1'b0;

    // -------------------------------------------------------------------------
    //  Frame-boundary capture termination (CAP_LEN > 0)
    //
    //  Counts samples ACCEPTED into the active capture buffer and forces a
    //  synthetic tlast on the CAP_LEN-th one. This makes each buffer hold one
    //  whole frame even when the upstream stream has NO per-frame tlast (the
    //  continuous multi-frame case) -> the ping-pong stays frame-aligned slot
    //  to slot and never glues two frames into one buffer (the bug-B stall).
    //  A real, earlier s_axis_tlast still ends the capture first.
    // -------------------------------------------------------------------------
    wire             cap_accept = s_axis_tvalid && s_axis_tready;  // active-buffer beat
    reg  [CAP_AW:0]  cap_cnt;                                      // 0..CAP_LEN
    localparam [CAP_AW:0] CAP_LEN_M1 = CAP_LEN[CAP_AW:0] - { {CAP_AW{1'b0}}, 1'b1 };
    wire             force_last = (CAP_LEN > 0) &&
                                  (cstate != CAP_IDLE) &&
                                  (cap_cnt == CAP_LEN_M1);
    wire             eff_tlast  = s_axis_tlast || force_last;      // into both buffers

    always @(posedge aclk) begin
        if (!aresetn) begin
            cap_cnt <= {(CAP_AW+1){1'b0}};
        end else if (cstate == CAP_IDLE) begin
            cap_cnt <= {(CAP_AW+1){1'b0}};   // reset between captures
        end else if (cap_accept) begin
            if (eff_tlast) cap_cnt <= {(CAP_AW+1){1'b0}};
            else           cap_cnt <= cap_cnt + 1'b1;
        end
    end

    // read port mux -> the processor-owned buffer
    wire rden_a = rd_en && (proc_sel == 1'b0);
    wire rden_b = rd_en && (proc_sel == 1'b1);
    assign rd_data = (proc_sel == 1'b0) ? rdd_a : rdd_b;

    assign both_full = occ_a && occ_b;
    assign buf_ready = !proc_busy && (proc_next == 1'b0 ? occ_a : occ_b);
    assign buf_len   = (proc_next == 1'b0) ? len_a : len_b;

    // -------------------------------------------------------------------------
    //  Ping-pong control
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            cstate       <= CAP_IDLE;
            last_cap     <= 1'b1;          // so the first pick is buffer A
            proc_next    <= 1'b0;
            proc_sel     <= 1'b0;
            proc_busy    <= 1'b0;
            occ_a        <= 1'b0;
            occ_b        <= 1'b0;
            len_a        <= {(CAP_AW+1){1'b0}};
            len_b        <= {(CAP_AW+1){1'b0}};
            cs_a         <= 1'b0;
            cs_b         <= 1'b0;
            cap_overflow <= 1'b0;
        end else begin
            cs_a         <= 1'b0;
            cs_b         <= 1'b0;
            cap_overflow <= 1'b0;

            // -- Capture FSM: one frame at a time into a free buffer, ping-pong.
            //    IDLE is entered AFTER capture_done (occ already updated), so the
            //    just-filled buffer is seen as occupied -> no same-cycle re-arm.
            case (cstate)
                CAP_IDLE: begin
                    // pick a free buffer, alternating (prefer not-last-captured)
                    if (a_avail && (last_cap == 1'b1 || !b_avail)) begin
                        cs_a   <= 1'b1;
                        cstate <= CAP_A;
                    end else if (b_avail) begin
                        cs_b   <= 1'b1;
                        cstate <= CAP_B;
                    end
                end
                CAP_A: begin
                    if (cdone_a) begin
                        occ_a    <= 1'b1;
                        len_a    <= scnt_a;
                        last_cap <= 1'b0;
                        cstate   <= CAP_IDLE;
                    end
                end
                CAP_B: begin
                    if (cdone_b) begin
                        occ_b    <= 1'b1;
                        len_b    <= scnt_b;
                        last_cap <= 1'b1;
                        cstate   <= CAP_IDLE;
                    end
                end
                default: cstate <= CAP_IDLE;
            endcase

            // -- Processor handoff --------------------------------------------
            if (proc_take && !proc_busy) begin
                proc_busy <= 1'b1;
                proc_sel  <= proc_next;
            end
            if (proc_free && proc_busy) begin
                proc_busy <= 1'b0;
                if (proc_sel == 1'b0) occ_a <= 1'b0;
                else                  occ_b <= 1'b0;
                proc_next <= ~proc_next;   // next time process the other buffer
            end
        end
    end

    // -------------------------------------------------------------------------
    //  Two capture buffers
    // -------------------------------------------------------------------------
    iq_frame_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (CAP_AW),
        .DEPTH      (DEPTH)
    ) u_buf_a (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .capture_start (cs_a),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (vld_a),
        .s_axis_tready (tready_a),
        .s_axis_tlast  (eff_tlast),
        .wb_en         (1'b0),
        .wb_addr       ({CAP_AW{1'b0}}),
        .wb_data       ({DATA_WIDTH{1'b0}}),
        .rd_en         (rden_a),
        .rd_addr       (rd_addr),
        .rd_data       (rdd_a),
        .wr_ptr        (wrp_a),
        .sample_count  (scnt_a),
        .capture_done  (cdone_a),
        .busy          (busy_a),
        .full          (full_a)
    );

    iq_frame_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (CAP_AW),
        .DEPTH      (DEPTH)
    ) u_buf_b (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .capture_start (cs_b),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (vld_b),
        .s_axis_tready (tready_b),
        .s_axis_tlast  (eff_tlast),
        .wb_en         (1'b0),
        .wb_addr       ({CAP_AW{1'b0}}),
        .wb_data       ({DATA_WIDTH{1'b0}}),
        .rd_en         (rden_b),
        .rd_addr       (rd_addr),
        .rd_data       (rdd_b),
        .wr_ptr        (wrp_b),
        .sample_count  (scnt_b),
        .capture_done  (cdone_b),
        .busy          (busy_b),
        .full          (full_b)
    );

endmodule
