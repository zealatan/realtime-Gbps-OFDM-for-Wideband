`timescale 1ns/1ps
`default_nettype none
// =====================================================================
// rx_full_board_tb.sv
// ---------------------------------------------------------------------
// Verifies rx_full_board_top (the STAGE-1 board DUT): the frozen full RX
// chain + INTERNAL pilot ROM + the m_axis bit->beat adapter.  Drives the
// sync-capable 4160-sample golden frame into s_axis exactly like the
// dut_player would, captures the m_axis 32-bit beats exactly like
// dut_capture would (one nibble/beat in [3:0]), unpacks the demod bits,
// and checks END-TO-END BER vs golden/rx_downstream/tx_bits.txt.
//
// This is the SAME pass criterion as the rx_full_chain gate (BER==0) but
// through the board-integration wrapper, with NO external pilot feed —
// proving the design is self-contained before the long Vivado build.
// =====================================================================
module rx_full_board_tb;

    localparam int IQ_WIDTH   = 16;
    localparam int NUM_DATA   = 12;
    localparam int NDATA_SC   = 221;
    localparam int STIM_BEATS = 4160;
    localparam int NBEATS     = NUM_DATA * NDATA_SC;   // 2652 m_axis beats
    localparam int NBITS      = NBEATS * 4;            // 10608 bits
    localparam int DRAIN_CYCLES = 200000;
    // PHASE2 continuous-stream: number of back-to-back frames to feed the HW
    // BER checker per rot_off sweep step. >=3 so >=1 frame is counted after the
    // 1-frame warm-up. Kept small (sweep is 12 iters) to bound sim time.
    localparam int LOOP_FRAMES   = 4;

    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;

    // AXI-Lite (driven via force on internal enables, like the chain TB)
    logic  [6:0] s_axi_awaddr  = 0;  logic s_axi_awvalid = 0; wire s_axi_awready;
    logic [31:0] s_axi_wdata   = 0;  logic [3:0] s_axi_wstrb = 4'hF;
    logic        s_axi_wvalid  = 0;  wire s_axi_wready;
    wire   [1:0] s_axi_bresp;         wire s_axi_bvalid;  logic s_axi_bready = 1'b1;
    logic  [6:0] s_axi_araddr  = 0;  logic s_axi_arvalid = 0; wire s_axi_arready;
    wire  [31:0] s_axi_rdata;         wire [1:0] s_axi_rresp; wire s_axi_rvalid;
    logic        s_axi_rready  = 1'b1;

    // S_AXIS raw IQ
    logic [2*IQ_WIDTH-1:0] s_axis_tdata  = 0;
    logic                  s_axis_tvalid = 0;
    wire                   s_axis_tready;
    logic                  s_axis_tlast  = 0;

    // M_AXIS packed demod bits (one nibble/beat) -> captured like dut_capture
    wire [2*IQ_WIDTH-1:0] m_axis_tdata;
    wire                  m_axis_tvalid;
    logic                 m_axis_tready = 1'b1;
    wire                  m_axis_tlast;

    wire [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                  dbg_frac_m_tvalid, dbg_frac_m_tready, dbg_frac_m_tlast;

    // on-chip HW BER checker control/status (additive tap)
    logic [31:0] ber_ctrl = 32'd0;
    wire  [31:0] ber_status;

    rx_full_board_top #(
        .IQ_WIDTH(IQ_WIDTH), .THRESHOLD(40000),
        .PILOT_ROM_FILE("pilot_rom.hex"),
        .EQ_LUT_FILE("rx_equalizer_recip_lut.hex"),
        .CE_W_ROM("rtl/rx_ch_est_rom/ce_interp_W.hex"),
        .BER_REF_ROM("rx_ber_ref_rom.hex")
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid), .s_axis_tready(s_axis_tready), .s_axis_tlast(s_axis_tlast),
        .m_axis_tdata(m_axis_tdata), .m_axis_tvalid(m_axis_tvalid), .m_axis_tready(m_axis_tready), .m_axis_tlast(m_axis_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready), .dbg_frac_m_tlast(dbg_frac_m_tlast),
        .ber_ctrl(ber_ctrl), .ber_status(ber_status)
    );

    // persisted rot_off so reads/clears preserve it (mirror the firmware).
    logic [3:0] tb_rot = 4'd0;

    // read a BER counter word by selecting status_sel and sampling ber_status,
    // preserving rot_off (ber_ctrl[11:8]) and clr=0.
    task automatic ber_read(input logic [3:0] sel, output logic [31:0] val);
        ber_ctrl = {20'd0, tb_rot, sel, 4'd0};
        #1 val = ber_status;        // combinational mux settle
    endtask

    // set the firmware-settable whole-symbol reference rotation (0..11)
    task automatic ber_set_rot(input logic [3:0] rot);
        tb_rot = rot;
        ber_ctrl = {20'd0, tb_rot, 4'd0, 4'd0};
        #1;
    endtask

    // soft-clear the checker (level pulse on ber_ctrl[0]), preserving rot_off.
    task automatic ber_clear();
        ber_ctrl = {20'd0, tb_rot, 4'd0, 4'b0001};   // clr=1
        repeat (3) @(posedge clk);
        ber_ctrl = {20'd0, tb_rot, 4'd0, 4'd0};       // clr=0
        repeat (3) @(posedge clk);
    endtask

    // ---- stim + golden ----
    logic [31:0] stim_mem [0:STIM_BEATS-1];
    byte         txbit [0:NBITS-1];
    byte         rxbit [0:NBITS-1];
    initial $readmemh("../../../golden/rx_downstream/tx_slot_iq.hex", stim_mem);
    integer fd, ch, ib;
    initial begin
        fd = $fopen("../../../golden/rx_downstream/tx_bits.txt", "r");
        if (fd == 0) begin $display("FATAL: no tx_bits.txt"); $finish; end
        ib = 0; ch = $fgetc(fd);
        while (ch != -1 && ib < NBITS) begin
            if (ch == "0" || ch == "1") begin txbit[ib] = ch[7:0]; ib = ib + 1; end
            ch = $fgetc(fd);
        end
        $fclose(fd);
    end

    // B[k] ROM for the sync correlator (hierarchical, like the chain TB)
    initial begin
        repeat (4) @(posedge clk);
        force dut.u_chain.u_sync.int_enable        = 1'b1;
        force dut.u_chain.u_sync.int_bypass_en     = 1'b0;
        force dut.u_chain.u_sync.int_force_tlast   = 1'b0;
        force dut.u_chain.u_sync.int_counter_clear = 1'b0;
        force dut.u_chain.u_sync.int_frame_len     = 12'd4032;
        $readmemh("../../../vectors/bk_conj_fft512_rom.txt",
                  dut.u_chain.u_sync.u_dut.u_meyr.u_rm_dut.rom);
    end

    // ---- capture m_axis beats (mirror dut_capture: store full 32b word) ----
    int beat_cnt, cyc, first_beat_cyc;
    bit frame_locked;
    initial begin beat_cnt = 0; cyc = 0; first_beat_cyc = -1; frame_locked = 0; end
    always @(posedge clk) if (aresetn) begin
        cyc <= cyc + 1;
        if (m_axis_tvalid && m_axis_tready) begin
            if (first_beat_cyc < 0) first_beat_cyc = cyc;
            if (beat_cnt < NBEATS) begin
                // word = {28'b0, b0,b1,b2,b3}; b0 is bit[3]
                rxbit[beat_cnt*4 + 0] <= (m_axis_tdata[3]) ? "1" : "0";
                rxbit[beat_cnt*4 + 1] <= (m_axis_tdata[2]) ? "1" : "0";
                rxbit[beat_cnt*4 + 2] <= (m_axis_tdata[1]) ? "1" : "0";
                rxbit[beat_cnt*4 + 3] <= (m_axis_tdata[0]) ? "1" : "0";
            end
            beat_cnt <= beat_cnt + 1;
        end
        if (dut.u_chain.u_sync.u_dut.dbg_frame_start_valid) frame_locked <= 1'b1;
    end

    task automatic drive_input(input int n);
        for (int i = 0; i < n; i++) begin
            @(posedge clk);
            s_axis_tdata  <= stim_mem[i];
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (i == n-1);
            while (!s_axis_tready) @(posedge clk);
        end
        @(posedge clk); s_axis_tvalid <= 1'b0; s_axis_tlast <= 1'b0;
    endtask

    // Continuous loop driver: stream NF copies of the 4160-word frame back-to-
    // back (mirrors dut_player loop_en) with tlast per frame, honoring tready.
    task automatic drive_loop(input int nf);
        for (int f = 0; f < nf; f++) begin
            for (int i = 0; i < STIM_BEATS; i++) begin
                @(posedge clk);
                s_axis_tdata  <= stim_mem[i];
                s_axis_tvalid <= 1'b1;
                s_axis_tlast  <= (i == STIM_BEATS-1);
                while (!s_axis_tready) @(posedge clk);
            end
        end
        @(posedge clk); s_axis_tvalid <= 1'b0; s_axis_tlast <= 1'b0;
    endtask

    int errors, fails, waited;
    initial begin : main
        fails = 0;
        aresetn <= 1'b0; repeat (40) @(posedge clk);
        aresetn <= 1'b1; repeat (20) @(posedge clk);

        $display("[BOARD-TB] driving %0d-sample frame (internal pilot ROM)", STIM_BEATS);
        drive_input(STIM_BEATS);

        waited = 0;
        while (beat_cnt < NBEATS && waited < DRAIN_CYCLES) begin
            @(posedge clk); waited++;
        end
        repeat (10) @(posedge clk);

        $display("[BOARD-TB] frame_locked=%0b  m_axis beats=%0d (exp %0d)  tlast_seen_at_beat=%0d",
                 frame_locked, beat_cnt, NBEATS, NBEATS-1);
        if (!frame_locked) begin $display("[BOARD-TB] FAIL: no sync lock"); fails++; end

        if (beat_cnt >= NBEATS) begin
            errors = 0;
            for (int i = 0; i < NBITS; i++)
                if (rxbit[i] !== txbit[i]) errors++;
            $display("================================================================");
            $display("[BOARD-TB] END-TO-END BER vs tx_bits.txt : %0d / %0d", errors, NBITS);
            $display("[BOARD-TB] m_axis beats=%0d first_beat_cyc=%0d run_cyc=%0d",
                     beat_cnt, first_beat_cyc, cyc);
            if (errors != 0) begin
                $display("[BOARD-TB] BER FAIL"); fails++;
            end else begin
                $display("[BOARD-TB] BER PASS: 0 / %0d", NBITS);
            end
        end else begin
            $display("[BOARD-TB] FAIL: only %0d/%0d beats (drain timeout)", beat_cnt, NBEATS);
            fails++;
        end

        // =============================================================
        // PHASE 2: CONTINUOUS-STREAMING on-chip HW BER checker validation
        //          with the ROBUST rot_off rotation SEARCH.
        // For each rot_off 0..11: clear the checker, stream a couple frames
        // back-to-back (like dut_player loop_en), read total_bit_errors +
        // frames_checked. EXACTLY ONE rot_off must yield 0 bit errors; all
        // others ~50%. This proves the rotation mechanism the firmware uses.
        // =============================================================
        // SINGLE-ANCHOR DELTA SWEEP: clear the checker ONCE so its frame phase is
        // anchored stably, then for each rot_off stream a fixed window and measure
        // the bit-error DELTA over that window. rot_off rotates the REFERENCE
        // combinationally (no re-clear, anchor never moves), so EXACTLY ONE rot_off
        // produces a zero-error window; every other ~50%. This is the mechanism the
        // firmware uses on silicon (re-clearing per rot is unstable because clr is
        // async to the continuous demod stream).
        begin
            logic [31:0] be, fc, ef, tn, wu;
            logic [31:0] be0, fc0;
            int aligned_rot, zero_count;
            int rot;
            aligned_rot = -1;
            zero_count  = 0;
            $display("================================================================");
            $display("[BOARD-TB] PHASE2: rot_off DELTA SWEEP (0..11), single anchor, %0d frames/window",
                     LOOP_FRAMES);
            // anchor once (warm-up absorbed), keep player streaming continuously.
            ber_set_rot(4'd0);
            ber_clear();
            drive_loop(LOOP_FRAMES);          // burn the warm-up frame
            repeat (200) @(posedge clk);
            $display("[BOARD-TB] rot_off | d_frames | d_bit_errors | err_flags");
            for (rot = 0; rot < 12; rot++) begin
                ber_set_rot(rot[3:0]);
                repeat (50) @(posedge clk);   // let the new rot propagate
                ber_read(4'h0, be0);
                ber_read(4'h1, fc0);
                drive_loop(LOOP_FRAMES);       // streaming window at this rot
                repeat (200) @(posedge clk);
                ber_read(4'h0, be);
                ber_read(4'h1, fc);
                ber_read(4'h3, ef);
                $display("[BOARD-TB]   rot=%0d | d_frames=%0d | d_bit_errors=%0d | flags=0x%08x",
                         rot, (fc-fc0), (be-be0), ef);
                if ((fc-fc0) >= 1 && (be-be0) == 0) begin
                    aligned_rot = rot;
                    zero_count++;
                end
            end
            $display("[BOARD-TB] SWEEP: aligned_rot=%0d  zero-error rotations=%0d (expect EXACTLY 1)",
                     aligned_rot, zero_count);
            if (aligned_rot < 0) begin
                $display("[BOARD-TB] CHECKER FAIL: NO rot_off aligned (all >0 errors)");
                fails++;
            end else if (zero_count != 1) begin
                $display("[BOARD-TB] CHECKER FAIL: %0d rotations gave 0 errors (must be exactly 1)",
                         zero_count);
                fails++;
            end else begin
                // LONG-RUN at the aligned rot_off WITHOUT re-clearing (a fresh clr
                // would re-anchor to a different async phase, invalidating the rot
                // we just found). The stable anchor from the sweep is kept; we just
                // lock rot=aligned_rot and measure the bit-error DELTA over a long
                // streaming window. d_bit_errors must be 0.
                ber_set_rot(aligned_rot[3:0]);
                repeat (50) @(posedge clk);
                ber_read(4'h0, be0);
                ber_read(4'h1, fc0);
                // long window (several sweep windows worth of frames)
                drive_loop(LOOP_FRAMES);
                drive_loop(LOOP_FRAMES);
                drive_loop(LOOP_FRAMES);
                repeat (4000) @(posedge clk);
                ber_read(4'h0, be);
                ber_read(4'h1, fc);
                ber_read(4'h2, tn);
                ber_read(4'h3, ef);
                ber_read(4'h4, wu);
                $display("[BOARD-TB] LONG-RUN rot_off=%0d: d_frames=%0d d_bit_errors=%0d (cum frames=%0d nibbles=%0d errs=%0d)",
                         aligned_rot, (fc-fc0), (be-be0), fc, tn, be);
                $display("[BOARD-TB] LONG-RUN err_flags=0x%08x warmup_word=0x%08x (warmup_frames=%0d done=%0d)",
                         ef, wu, wu[15:0], wu[16]);
                if ((fc-fc0) < 1) begin
                    $display("[BOARD-TB] CHECKER FAIL: no complete frame counted in long-run");
                    fails++;
                end else if ((be-be0) != 0) begin
                    $display("[BOARD-TB] CHECKER FAIL: %0d bit errors in long-run window", (be-be0));
                    fails++;
                end else if (ef != 0) begin
                    $display("[BOARD-TB] CHECKER FAIL: alignment err_flags=0x%08x", ef);
                    fails++;
                end else begin
                    $display("[BOARD-TB] CHECKER PASS: BER=0 over %0d streamed frames at aligned rot_off=%0d",
                             (fc-fc0), aligned_rot);
                end
            end
        end

        $display("================================================================");
        if (fails == 0) $display("GATE: PASS_RX_FULL_BOARD (BER=0, internal pilot ROM, bit-beat adapter)");
        else            $display("GATE: FAIL_RX_FULL_BOARD (%0d failures)", fails);
        $finish;
    end

    initial begin
        #400_000_000;   // 400 ms: room for the 12-step rot_off sweep
        $display("GATE: FAIL_RX_FULL_BOARD (hard timeout)");
        $finish;
    end

endmodule
`default_nettype wire
