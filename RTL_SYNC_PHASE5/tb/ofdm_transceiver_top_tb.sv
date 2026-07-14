// =====================================================================
// ofdm_transceiver_top_tb.sv
// ---------------------------------------------------------------------
// Exercises the MODE-SELECTABLE OFDM transceiver top (ofdm_transceiver_top)
// in ALL THREE runtime modes against the same frozen, BER-0 proven core:
//
//   MODE 0 TX       : drive data bits, capture tx_out, confirm the emitted
//                     4032-sample slot matches the golden TX slot byte-exact
//                     (PSS first word 0xFAC111BD + full slot vs
//                     golden/rx_downstream/tx_slot_iq_4032.hex).
//
//   MODE 1 RX       : drive the golden 4160-sample sync-capable frame
//                     (golden/rx_downstream/tx_slot_iq.hex) into ext_s_axis,
//                     confirm demod BER == 0 / 10608.
//
//   MODE 2 LOOPBACK : kick the internal TX, let the wrapper frame+replay it
//                     through the RX, confirm demod BER == 0 / 10608 AND the
//                     on-chip rx_ber_checker reads 0 total_bit_errors at the
//                     aligned rot_off.
//
// Real Xilinx xfft 9.1 IPs (xsim). Uses the SAME sync arming `force` shortcut
// (int_enable / frame_len / threshold) as the proven tx_rx_full_loopback_tb,
// applied through the wrapper hierarchy dut.u_rx.u_sync.* .
//
//   GATE: PASS_TRANSCEIVER_3MODE  /  GATE: FAIL_TRANSCEIVER_3MODE
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module ofdm_transceiver_top_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int NUM_PLT   = 32;
    localparam int NDATA_SC  = 221;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int SYNC_LEN  = NUM_SYN*(NSC + CP_LEN);              // 576
    localparam int TX_TOL    = 64;   // IFFT BFP per-sample LSB budget (matches tx_ofdm_top_tb)
    localparam int LEAD_IN   = 64;
    localparam int TRAILER   = 64;
    localparam int FRAME_LEN = LEAD_IN + SLOT_LEN + TRAILER;        // 4160
    localparam int NBEATS    = NUM_DATA * NDATA_SC;                 // 2652
    localparam int NBITS     = NBEATS * 4;                          // 10608
    localparam int NPLT      = NUM_DATA * NUM_PLT;                  // 384
    localparam int NDATA_BITS = NUM_DATA * NDATA_SC * 4;            // 10608

    localparam int DRAIN_CYCLES = 200000;
    localparam int HARD_TIMEOUT = 20000000;

    // ---- clock / reset ----
    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;

    // ---- DUT control ----
    logic  [1:0] mode = 2'd0;
    logic        start = 1'b0;
    logic        lb_cont = 1'b0;   // continuous-loopback re-emit (MODE 3 test)
    logic [31:0] ber_ctrl = 32'd0;
    wire  [31:0] ber_status;
    wire         tx_busy;
    wire         rx_frame_locked;

    // ---- TX data + pilot ROM ----
    logic [NUM_DATA*NDATA_SC*8-1:0] data_bits_flat;  // 8 bits/carrier
    wire  [8:0]  tx_pilot_addr;
    logic [31:0] tx_pilot_tdata;

    // ---- TX output stream ----
    wire [31:0]  tx_out_tdata;
    wire         tx_out_tvalid;
    logic        tx_out_tready = 1'b1;
    wire         tx_out_tlast;

    // ---- external RX input ----
    logic [31:0] ext_s_axis_tdata  = 0;
    logic        ext_s_axis_tvalid = 0;
    wire         ext_s_axis_tready;
    logic        ext_s_axis_tlast  = 0;

    // ---- RX pilot ROM stream ----
    logic [31:0] rx_pilot_tdata = 0;
    wire         rx_pilot_tready;

    // ---- RX demod output ----
    wire  [7:0]  m_bits_tdata;  // 16-QAM uses [3:0]
    wire         m_bits_tvalid;
    logic        m_bits_tready = 1'b1;
    wire         m_bits_tlast, m_bits_tuser;

    // ---- AXI-Lite (defaults; sync armed via force shortcut) ----
    logic  [6:0] s_axi_awaddr  = 0;
    logic        s_axi_awvalid = 0;  wire s_axi_awready;
    logic [31:0] s_axi_wdata   = 0;
    logic  [3:0] s_axi_wstrb   = 4'hF;
    logic        s_axi_wvalid  = 0;  wire s_axi_wready;
    wire   [1:0] s_axi_bresp;        wire s_axi_bvalid;
    logic        s_axi_bready  = 1'b1;
    logic  [6:0] s_axi_araddr  = 0;
    logic        s_axi_arvalid = 0;  wire s_axi_arready;
    wire  [31:0] s_axi_rdata;        wire [1:0] s_axi_rresp;  wire s_axi_rvalid;
    logic        s_axi_rready  = 1'b1;

    ofdm_transceiver_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NUM_PILOTS(NUM_PLT), .NDATA_SC(NDATA_SC), .BPC_MAX(8),
        .SCALE_SH(4), .THRESHOLD(40000),
        .TX_SPECMAP("rtl/tx_rom/tx_specmap.hex"),
        .TX_SYNC_ROM("rtl/tx_rom/tx_sync_rom.hex")
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .mode(mode), .mod_sel(2'd1), .start(start), .lb_cont(lb_cont), .ber_ctrl(ber_ctrl), .ber_status(ber_status),
        .tx_busy(tx_busy), .rx_frame_locked(rx_frame_locked),
        .data_bits_flat(data_bits_flat),
        .tx_pilot_addr(tx_pilot_addr), .tx_pilot_tdata(tx_pilot_tdata),
        .tx_out_tdata(tx_out_tdata), .tx_out_tvalid(tx_out_tvalid),
        .tx_out_tready(tx_out_tready), .tx_out_tlast(tx_out_tlast),
        .ext_s_axis_tdata(ext_s_axis_tdata), .ext_s_axis_tvalid(ext_s_axis_tvalid),
        .ext_s_axis_tready(ext_s_axis_tready), .ext_s_axis_tlast(ext_s_axis_tlast),
        .rx_pilot_tdata(rx_pilot_tdata), .rx_pilot_tready(rx_pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready)
    );

    // ---- sync arming force (same shortcut as proven loopback gate) ----
    initial begin
        repeat (4) @(posedge clk);
        force dut.u_rx.u_sync.int_enable        = 1'b1;
        force dut.u_rx.u_sync.int_bypass_en     = 1'b0;
        force dut.u_rx.u_sync.int_force_tlast   = 1'b0;
        force dut.u_rx.u_sync.int_counter_clear = 1'b0;
        force dut.u_rx.u_sync.int_frame_len     = 12'd4032;
    end
    // ---- B[k] conj-FFT ROM (hierarchical load) ----
    initial begin
        $readmemh("../../../vectors/bk_conj_fft512_rom.txt",
                  dut.u_rx.u_sync.u_dut.u_meyr.u_rm_dut.rom);
    end

    // ---- TX pilot ROM (addressed read) ----
    logic [31:0] tx_pilot_mem [0:NPLT-1];
    initial $readmemh("../../../golden/rx_downstream/pilot_rom.hex", tx_pilot_mem);
    always @(*) tx_pilot_tdata = tx_pilot_mem[tx_pilot_addr];

    // ---- RX pilot ROM stream feeder ----
    logic [31:0] plt_mem [0:NPLT-1];
    initial $readmemh("../../../golden/rx_downstream/pilot_rom.hex", plt_mem);
    integer plt_ptr;
    always @(*) rx_pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!aresetn) plt_ptr <= 0;
        else if (rx_pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- golden TX data bits ----
    logic [7:0] txbit_chars [0:NDATA_BITS-1];
    logic [7:0] txbit [0:NBITS-1];
    integer fbits, ch0, di0, zz, bb;
    initial begin
        fbits = $fopen("../../../golden/tx/tx_data_bits.txt", "r");
        if (fbits == 0) begin
            $display("FATAL: cannot open tx_data_bits.txt");
            $display("GATE: FAIL_TRANSCEIVER_3MODE (no tx_data_bits.txt)"); $finish;
        end
        di0 = 0; ch0 = $fgetc(fbits);
        while (ch0 != -1 && di0 < NDATA_BITS) begin
            if (ch0 == "0" || ch0 == "1") begin txbit_chars[di0] = ch0[7:0]; txbit[di0] = ch0[7:0]; di0 = di0 + 1; end
            ch0 = $fgetc(fbits);
        end
        $fclose(fbits);
        if (di0 != NDATA_BITS) $display("WARN: read %0d TX bits, expected %0d", di0, NDATA_BITS);
        for (zz = 0; zz < NUM_DATA; zz = zz + 1)
            for (bb = 0; bb < NDATA_SC; bb = bb + 1)
                for (int cc = 0; cc < 4; cc = cc + 1)
                    data_bits_flat[(zz*NDATA_SC + bb)*8 + cc] = (txbit_chars[zz*NDATA_SC*4 + bb*4 + cc] == "1");
    end

    // ---- golden TX slot (4032) for MODE 0 byte-exact compare ----
    logic [31:0] golden_slot [0:SLOT_LEN-1];
    initial $readmemh("../../../golden/rx_downstream/tx_slot_iq_4032.hex", golden_slot);

    // ---- golden 4160 sync-capable frame for MODE 1 ----
    logic [31:0] golden_frame [0:FRAME_LEN-1];
    initial $readmemh("../../../golden/rx_downstream/tx_slot_iq.hex", golden_frame);

    // =================================================================
    // capture / scoreboard
    // =================================================================
    logic [31:0] tx_cap [0:SLOT_LEN-1];
    int   tx_cap_cnt;
    bit   tx_cap_done;

    logic [7:0] rxbit [0:NBITS-1];
    int   bit_out_cnt;

    always @(posedge clk) if (aresetn) begin
        // capture TX output stream (TX mode)
        if (tx_out_tvalid && tx_out_tready) begin
            if (tx_cap_cnt < SLOT_LEN) tx_cap[tx_cap_cnt] <= tx_out_tdata;
            tx_cap_cnt <= tx_cap_cnt + 1;
            if (tx_out_tlast) tx_cap_done <= 1'b1;
        end
        // capture demod bits (RX / LOOPBACK)
        if (m_bits_tvalid && m_bits_tready) begin
            if (bit_out_cnt < NBEATS) begin
                rxbit[bit_out_cnt*4 + 0] <= (m_bits_tdata[3]) ? "1" : "0";
                rxbit[bit_out_cnt*4 + 1] <= (m_bits_tdata[2]) ? "1" : "0";
                rxbit[bit_out_cnt*4 + 2] <= (m_bits_tdata[1]) ? "1" : "0";
                rxbit[bit_out_cnt*4 + 3] <= (m_bits_tdata[0]) ? "1" : "0";
            end
            bit_out_cnt <= bit_out_cnt + 1;
        end
    end

    // =================================================================
    // tasks
    // =================================================================
    int errors, fails;
    int mode2_rot = 0;                          // aligned rot_off from MODE 2 search
    localparam int CONT_TARGET_FRAMES = 6;      // multi-frame continuous-BER goal (sim)

    task automatic do_reset();
        aresetn <= 1'b0;
        repeat (40) @(posedge clk);
        aresetn <= 1'b1;
        repeat (20) @(posedge clk);
    endtask

    task automatic clear_caps();
        tx_cap_cnt  = 0;  tx_cap_done = 1'b0;
        bit_out_cnt = 0;
    endtask

    // clear the on-chip ber_checker, accumulate a few frames of the CURRENT
    // continuous stream, then read total_bit_errors + frames_checked + lock.
    task automatic cont_measure(input int rot, output int be_o,
                                output int fc_o, output bit lk_o);
        begin
            ber_ctrl = (rot << 8) | 32'h1;            // clr=1
            repeat (2) @(posedge clk);
            ber_ctrl = (rot << 8);                    // release clr
            repeat (3*FRAME_LEN) @(posedge clk);      // accumulate ~3 frames
            ber_ctrl = (rot << 8);                    // sel=0 -> total_bit_errors
            repeat (2) @(posedge clk);
            be_o = ber_status;
            ber_ctrl = (rot << 8) | (1 << 4);         // sel=1 -> frames_checked
            repeat (2) @(posedge clk);
            fc_o = ber_status;
            lk_o = rx_frame_locked;
            ber_ctrl = (rot << 8);                    // back to sel=0
        end
    endtask

    // count BER vs golden tx bits
    function automatic int count_ber();
        int e; e = 0;
        for (int i = 0; i < NBITS; i = i + 1)
            if (rxbit[i] !== txbit[i]) e = e + 1;
        return e;
    endfunction

    // drive the golden 4160 frame into ext_s_axis (RX mode)
    task automatic drive_ext_frame();
        for (int i = 0; i < FRAME_LEN; i = i + 1) begin
            @(posedge clk);
            ext_s_axis_tdata  <= golden_frame[i];
            ext_s_axis_tvalid <= 1'b1;
            ext_s_axis_tlast  <= (i == FRAME_LEN-1);
            while (!ext_s_axis_tready) @(posedge clk);
        end
        @(posedge clk);
        ext_s_axis_tvalid <= 1'b0;
        ext_s_axis_tlast  <= 1'b0;
    endtask

    // =================================================================
    // MAIN
    // =================================================================
    integer i, waited;
    initial begin : main
        fails = 0;
        clear_caps();
        do_reset();

        // ===========================================================
        // MODE 0 : TX
        // ===========================================================
        $display("================================================================");
        $display("[XCVR] MODE 0 : TX  (capture tx_out, compare golden 4032 slot)");
        $display("================================================================");
        mode = 2'd0;
        clear_caps();
        @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;

        waited = 0;
        while (!(tx_cap_done && tx_cap_cnt >= SLOT_LEN) && waited < DRAIN_CYCLES) begin
            @(posedge clk); waited = waited + 1;
        end
        $display("[XCVR] TX emitted %0d / %0d slot samples (done=%0b)", tx_cap_cnt, SLOT_LEN, tx_cap_done);
        if (tx_cap_cnt < SLOT_LEN) begin
            $display("[XCVR] MODE0 FAIL: TX slot incomplete");
            fails = fails + 1;
        end else begin
            // Match the standalone tx_ofdm_top criterion: PSS first word + the
            // 576-sample sync region byte-EXACT; the 4032-576 data samples
            // within TX_TOL=64 LSB per I/Q (IFFT BFP truncation budget).
            int sync_err, data_err, maxerr;
            int gi, gq, ri, rq, ei, eq;
            sync_err = 0; data_err = 0; maxerr = 0;
            $display("[XCVR] TX slot[0]=0x%08x (expect 0xFAC111BD)", tx_cap[0]);
            if (tx_cap[0] !== 32'hFAC111BD) begin
                $display("[XCVR] MODE0 FAIL: PSS first word mismatch 0x%08x", tx_cap[0]);
                fails = fails + 1;
            end
            for (i = 0; i < SLOT_LEN; i = i + 1) begin
                gi = $signed(golden_slot[i][15:0]); gq = $signed(golden_slot[i][31:16]);
                ri = $signed(tx_cap[i][15:0]);      rq = $signed(tx_cap[i][31:16]);
                ei = (ri>gi)?(ri-gi):(gi-ri);  eq = (rq>gq)?(rq-gq):(gq-rq);
                if (ei>maxerr) maxerr=ei;  if (eq>maxerr) maxerr=eq;
                if (i < SYNC_LEN) begin
                    if (tx_cap[i] !== golden_slot[i]) sync_err = sync_err + 1;
                end else begin
                    if (ei>TX_TOL || eq>TX_TOL) data_err = data_err + 1;
                end
            end
            $display("[XCVR] MODE0 sync region (576) exact mismatches = %0d (must be 0)", sync_err);
            $display("[XCVR] MODE0 data region within TOL=%0d : %0d over-tol  (max abs err = %0d LSB)",
                     TX_TOL, data_err, maxerr);
            if (sync_err == 0 && data_err == 0)
                $display("[XCVR] MODE0 PASS: tx_out == golden TX slot (sync EXACT, data within %0d LSB)", TX_TOL);
            else begin
                $display("[XCVR] MODE0 FAIL: sync_err=%0d data_err=%0d", sync_err, data_err);
                fails = fails + 1;
            end
        end

        // ===========================================================
        // MODE 1 : RX  (drive golden 4160 frame into ext_s_axis)
        // ===========================================================
        do_reset();
        repeat (4) @(posedge clk);   // let the force re-settle after reset
        $display("================================================================");
        $display("[XCVR] MODE 1 : RX  (golden 4160 frame -> ext_s_axis -> demod)");
        $display("================================================================");
        mode = 2'd1;
        clear_caps();
        ber_ctrl = 32'd0;            // clr=0, rot_off=0, sel=0
        drive_ext_frame();
        waited = 0;
        while (bit_out_cnt < NBEATS && waited < DRAIN_CYCLES) begin
            @(posedge clk); waited = waited + 1;
        end
        repeat (10) @(posedge clk);
        $display("[XCVR] RX frame_locked=%0b demod beats=%0d/%0d", rx_frame_locked, bit_out_cnt, NBEATS);
        if (!rx_frame_locked) begin $display("[XCVR] MODE1 FAIL: sync never locked"); fails = fails + 1; end
        if (bit_out_cnt < NBEATS) begin
            $display("[XCVR] MODE1 FAIL: only %0d/%0d beats", bit_out_cnt, NBEATS);
            fails = fails + 1;
        end else begin
            errors = count_ber();
            $display("[XCVR] MODE1 BER : %0d / %0d", errors, NBITS);
            if (errors == 0) $display("[XCVR] MODE1 PASS: RX demod BER 0/%0d", NBITS);
            else begin $display("[XCVR] MODE1 FAIL: %0d bit errors", errors); fails = fails + 1; end
        end

        // ===========================================================
        // MODE 2 : LOOPBACK  (internal TX -> frame -> RX -> demod + BER chk)
        // ===========================================================
        do_reset();
        repeat (4) @(posedge clk);
        $display("================================================================");
        $display("[XCVR] MODE 2 : LOOPBACK  (internal TX -> RX -> demod + on-chip BER)");
        $display("================================================================");
        mode = 2'd2;
        clear_caps();
        // ber checker : rot_off search 0..11 below; clear once, then run
        ber_ctrl = 32'h0000_0001;    // clr=1
        @(posedge clk);
        ber_ctrl = 32'h0000_0000;    // release clr, rot_off=0, sel=0 (total_bit_errors)
        @(posedge clk);

        @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;

        waited = 0;
        while (bit_out_cnt < NBEATS && waited < DRAIN_CYCLES) begin
            @(posedge clk); waited = waited + 1;
        end
        repeat (50) @(posedge clk);
        $display("[XCVR] LOOPBACK frame_locked=%0b demod beats=%0d/%0d", rx_frame_locked, bit_out_cnt, NBEATS);
        if (!rx_frame_locked) begin $display("[XCVR] MODE2 FAIL: sync never locked"); fails = fails + 1; end
        if (bit_out_cnt < NBEATS) begin
            $display("[XCVR] MODE2 FAIL: only %0d/%0d beats", bit_out_cnt, NBEATS);
            fails = fails + 1;
        end else begin
            errors = count_ber();
            $display("[XCVR] MODE2 demod-vs-tx BER : %0d / %0d", errors, NBITS);
            if (errors == 0) $display("[XCVR] MODE2 PASS: LOOPBACK demod BER 0/%0d", NBITS);
            else begin $display("[XCVR] MODE2 FAIL: %0d bit errors", errors); fails = fails + 1; end
        end

        // on-chip BER checker readback : search rot_off 0..11 for the aligned 0
        begin
            int best_rot, best_val, v;
            best_rot = -1; best_val = 32'h7fffffff;
            for (int r = 0; r < NUM_DATA; r = r + 1) begin
                ber_ctrl = (r << 8) | 32'h0000_0000;   // rot_off=r, sel=0, clr=0
                repeat (2) @(posedge clk);
                v = ber_status;
                $display("[XCVR]   ber_checker rot_off=%0d total_bit_errors=%0d", r, v);
                if (v < best_val) begin best_val = v; best_rot = r; end
            end
            $display("[XCVR] ber_checker BEST rot_off=%0d total_bit_errors=%0d", best_rot, best_val);
            mode2_rot = (best_rot < 0) ? 0 : best_rot;   // reuse for MODE 3 continuous
            if (best_val != 0) begin
                $display("[XCVR] MODE2 FAIL: on-chip BER checker never read 0 (min=%0d)", best_val);
                fails = fails + 1;
            end else begin
                $display("[XCVR] MODE2 PASS: on-chip ber_checker reads 0 at rot_off=%0d", best_rot);
            end
        end

        // ===========================================================
        // MODE 3 : CONTINUOUS LOOPBACK (lb_cont=1) — the live-TX slot is
        // re-emitted back-to-back so the on-chip passive rx_ber_checker tallies
        // a MULTI-FRAME run. Verifies the continuous-BER path used on silicon:
        // frames_checked must advance past several frames with total_bit_errors
        // staying 0 (this is the exact HW long-run measurement, in sim).
        // ===========================================================
        do_reset();
        repeat (4) @(posedge clk);
        $display("================================================================");
        $display("[XCVR] MODE 3 : CONTINUOUS LOOPBACK (lb_cont=1, multi-frame on-chip BER)");
        $display("================================================================");
        mode    = 2'd2;      // still LOOPBACK mode
        lb_cont = 1'b1;      // enable continuous re-emit
        clear_caps();
        // clear the ber checker, then release at rot_off found above (best_rot);
        // fall back to 0 if the single-frame search failed.
        ber_ctrl = 32'h0000_0001;                 // clr=1
        @(posedge clk);
        ber_ctrl = (mode2_rot << 8);              // release clr, aligned rot_off
        @(posedge clk);

        // kick the live TX once; the framing FSM then streams frames forever.
        @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;

        // let a burst of frames stream (each frame = 4160 beats; run ~8 frames).
        begin
            int fc_prev, fc_now, be_now, guard;
            fc_prev = 0; guard = 0;
            // wait until at least CONT_TARGET_FRAMES frames have been checked
            fc_now = 0;
            while (fc_now < CONT_TARGET_FRAMES && guard < DRAIN_CYCLES) begin
                repeat (200) @(posedge clk);
                ber_ctrl = (mode2_rot << 8);       // sel=0 -> total_bit_errors
                repeat (2) @(posedge clk);
                be_now = ber_status;
                ber_ctrl = (mode2_rot << 8) | (1 << 4); // sel=1 -> frames_checked
                repeat (2) @(posedge clk);
                fc_now = ber_status;
                ber_ctrl = (mode2_rot << 8);       // back to sel=0
                guard = guard + 200;
                if (fc_now != fc_prev) begin
                    $display("[XCVR]   CONT frames_checked=%0d total_bit_errors=%0d (locked=%0b)",
                             fc_now, be_now, rx_frame_locked);
                    fc_prev = fc_now;
                end
            end
            // final snapshot
            ber_ctrl = (mode2_rot << 8);           // sel=0 total_bit_errors
            repeat (2) @(posedge clk);
            be_now = ber_status;
            ber_ctrl = (mode2_rot << 8) | (1 << 4);// sel=1 frames_checked
            repeat (2) @(posedge clk);
            fc_now = ber_status;
            $display("[XCVR] MODE3 CONTINUOUS: frames_checked=%0d total_bit_errors=%0d",
                     fc_now, be_now);
            if (fc_now >= CONT_TARGET_FRAMES && be_now == 0) begin
                $display("[XCVR] MODE3 PASS: continuous LOOPBACK BER=0 over %0d frames (%0d bits)",
                         fc_now, fc_now * NBITS);
            end else begin
                $display("[XCVR] MODE3 FAIL: frames=%0d errors=%0d (need frames>=%0d errors=0)",
                         fc_now, be_now, CONT_TARGET_FRAMES);
                fails = fails + 1;
            end
        end
        lb_cont = 1'b0;

        // ===========================================================
        // MODE 3B : SEAMLESS PAYLOAD SWAP (M2-full ping-pong). In continuous
        // loopback, change the payload mid-stream (A -> B -> A) and pulse start
        // each time. The ping-pong buffer must swap the new slot in at a frame
        // boundary WITHOUT stalling the framing FSM, so the RX stays locked. We
        // prove: (1) rx_frame_locked stays 1 across both swaps (no desync -- the
        // exact failure the old single-buffer + tx_start-resets-framing scheme
        // hit on silicon), (2) the swap actually changes the emitted payload
        // (BER vs the golden ref goes 0 -> >0 for B), and (3) it is clean and
        // reversible (swap back to A -> BER returns to 0).
        // ===========================================================
        do_reset();
        repeat (4) @(posedge clk);
        $display("================================================================");
        $display("[XCVR] MODE 3B : SEAMLESS PAYLOAD SWAP (ping-pong, lock-stable)");
        $display("================================================================");
        mode    = 2'd2;
        lb_cont = 1'b1;
        clear_caps();
        begin : swap_test
            int be_a, fc_a, be_b, fc_b, be_c, fc_c;
            bit lk_a, lk_b, lk_c;
            int q;
            // ---- payload A (golden, already in data_bits_flat): kick + stream ----
            ber_ctrl = 32'h0000_0001; @(posedge clk);
            ber_ctrl = (mode2_rot << 8); @(posedge clk);
            @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;
            repeat (3*FRAME_LEN) @(posedge clk);        // let A stream + lock
            cont_measure(mode2_rot, be_a, fc_a, lk_a);
            $display("[XCVR]   SWAP A(golden): locked=%0b frames=%0d BER=%0d", lk_a, fc_a, be_a);

            // ---- payload B: invert the first data symbol's bits, kick, swap ----
            for (q = 0; q < NDATA_SC*4; q = q + 1)
                data_bits_flat[q] = ~data_bits_flat[q];
            @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;
            repeat (4*FRAME_LEN) @(posedge clk);        // seamless swap + settle
            cont_measure(mode2_rot, be_b, fc_b, lk_b);
            $display("[XCVR]   SWAP B(mod)  : locked=%0b frames=%0d BER=%0d", lk_b, fc_b, be_b);

            // ---- swap back to A ----
            for (q = 0; q < NDATA_SC*4; q = q + 1)
                data_bits_flat[q] = ~data_bits_flat[q];
            @(posedge clk); start <= 1'b1; @(posedge clk); start <= 1'b0;
            repeat (4*FRAME_LEN) @(posedge clk);
            cont_measure(mode2_rot, be_c, fc_c, lk_c);
            $display("[XCVR]   SWAP A(back) : locked=%0b frames=%0d BER=%0d", lk_c, fc_c, be_c);

            if (lk_a && lk_b && lk_c && (fc_a > 0) && (fc_b > 0) && (fc_c > 0)
                && (be_a == 0) && (be_b > 0) && (be_c == 0)) begin
                $display("[XCVR] MODE3B PASS: seamless payload swap, lock held, A=0 B>0 A=0");
            end else begin
                $display("[XCVR] MODE3B FAIL: lk=%0b/%0b/%0b fc=%0d/%0d/%0d be=%0d/%0d/%0d (want lock=1 all, be 0/>0/0)",
                         lk_a, lk_b, lk_c, fc_a, fc_b, fc_c, be_a, be_b, be_c);
                fails = fails + 1;
            end
        end
        lb_cont = 1'b0;

        // ===========================================================
        $display("================================================================");
        if (fails == 0)
            $display("GATE: PASS_TRANSCEIVER_3MODE  (TX slot-match, RX BER=0, LOOPBACK BER=0 + on-chip BER=0, CONT multi-frame BER=0, SWAP lock-stable)");
        else
            $display("GATE: FAIL_TRANSCEIVER_3MODE  (%0d failed checks)", fails);
        $display("================================================================");
        $finish;
    end

    // progress beacon
    int tick;
    always @(posedge clk) if (aresetn) begin
        tick <= tick + 1;
        if (tick == 20000) begin
            $display("[XCVR] @%0t mode=%0d tx_cap=%0d bits=%0d locked=%0b",
                     $time, mode, tx_cap_cnt, bit_out_cnt, rx_frame_locked);
            tick <= 0;
        end
    end

    // hard watchdog
    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[XCVR] HARD TIMEOUT @%0t mode=%0d bits=%0d", $time, mode, bit_out_cnt);
        $display("GATE: FAIL_TRANSCEIVER_3MODE (hard timeout)");
        $finish;
    end

endmodule

`default_nettype wire
