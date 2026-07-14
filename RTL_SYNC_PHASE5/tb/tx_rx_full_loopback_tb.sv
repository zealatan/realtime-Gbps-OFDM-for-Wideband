// =====================================================================
// tx_rx_full_loopback_tb.sv
// ---------------------------------------------------------------------
// COMPLETE OFDM TRANSCEIVER LOOPBACK (DIGITAL) -- TX -> FULL RX (sync).
// ---------------------------------------------------------------------
// Proves the WHOLE chain end to end in ONE simulation:
//
//   golden/tx/tx_data_bits.txt (12*884 = 10608 data bits)
//        |
//   +----v---------------------------------------------+
//   | tx_ofdm_top  (LIVE TX RTL)                       |
//   |   tx_subcarrier_map (16-QAM + pilots + fftshift) |
//   |   tx_ifft_frontend  (256-IDFT xfft_N + CP)       |
//   |   + REAL PSS/SSS sync ROM (2 syms, 576 samples)  |
//   +----v---------------------------------------------+
//        | 4032-sample slot, {Q,I} Q15, m_last on 4031
//        |
//   wrap with 64 lead-in zeros + 4032 slot + 64 trailing zeros
//   = the 4160-sample sync-capable frame the synchronizer expects
//   (byte-identical framing to golden/rx_downstream/tx_slot_iq.hex,
//    but generated LIVE by the TX RTL rather than a pre-baked BRAM)
//        |
//   +----v---------------------------------------------+
//   | rx_full_chain_top  (FROZEN FULL RX)              |
//   |   phase3_sync_axis_dma_wrapper (frame detect +   |
//   |        timing + integer/frac CFO correction)     |
//   |   rx_downstream_top (FFT -> CE -> EQ -> 16QAM    |
//   |        demod) -> 12*884 = 10608 bits             |
//   +----v---------------------------------------------+
//        | m_bits
//        v
//   BER  vs the SAME 10608 input data bits.
//
// This is the digital TX->RX transceiver loopback INCLUDING the
// synchronizer.  The TX emits real PSS/SSS so the sync frame-detects +
// locks; CE/EQ absorb the 1-sample timing quantization (see seam note in
// rx_full_chain_top.v).  PASS <=> sync locks AND BER == 0 / 10608.
//
//   GATE: PASS_TX_RX_LOOPBACK   /  GATE: FAIL_TX_RX_LOOPBACK
//
// Real Xilinx xfft 9.1 IPs (xsim).  The TX IDFT and RX FFT both use the
// real xfft cores.  Nothing in the frozen TX / sync / RX is modified --
// this TB is the only vehicle.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module tx_rx_full_loopback_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int NUM_PLT   = 32;
    localparam int NDATA_SC  = 221;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int LEAD_IN   = 64;                                  // sync lead-in zeros
    localparam int TRAILER   = 64;                                  // trailing zeros
    localparam int STIM_BEATS = LEAD_IN + SLOT_LEN + TRAILER;       // 4160 full frame
    localparam int NBEATS    = NUM_DATA * NDATA_SC;                 // 2652
    localparam int NBITS     = NBEATS * 4;                          // 10608
    localparam int NPLT      = NUM_DATA * NUM_PLT;                  // 384
    localparam int NDATA_BITS = NUM_DATA * NDATA_SC * 4;            // 10608

    localparam int DRAIN_CYCLES = 200000;
    localparam int HARD_TIMEOUT = 12000000;

    // ---- clock / reset ----
    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;

    // =================================================================
    // STAGE 1 -- LIVE TX : tx_ofdm_top generates the 4032-sample slot
    // =================================================================
    logic        tx_start = 1'b0;
    wire         tx_busy;
    logic [NDATA_BITS-1:0] data_bits_flat;
    wire  [8:0]  tx_pilot_addr;
    logic [31:0] tx_pilot_tdata;
    wire         tx_m_valid;
    logic        tx_m_ready = 1'b1;       // TB always ready to capture TX
    wire  [31:0] tx_m_tdata;
    wire         tx_m_last;

    tx_ofdm_top #(
        .DATA_W(16), .NSC(256), .CP_LEN(32), .NUM_SYN(2), .NUM_DATA(12),
        .NPIL(32), .NDATA_SC(221), .Q16_1(1610), .Q16_3(4829),
        .SPECMAP("rtl/tx_rom/tx_specmap.hex"),
        .SYNC_ROM("rtl/tx_rom/tx_sync_rom.hex")
    ) u_tx (
        .clk(clk), .rst_n(aresetn),
        .start(tx_start), .busy(tx_busy),
        .data_bits_flat(data_bits_flat),
        .pilot_addr(tx_pilot_addr), .pilot_tdata(tx_pilot_tdata),
        .m_valid(tx_m_valid), .m_ready(tx_m_ready),
        .m_tdata(tx_m_tdata), .m_last(tx_m_last)
    );

    // TX data bits + TX pilot ROM (symbol-major 384 words)
    logic [7:0]  txbit_chars [0:NDATA_BITS-1];
    logic [31:0] tx_pilot_mem [0:NPLT-1];
    integer fbits, ch0, di0, zz, bb;
    initial begin
        $readmemh("../../../golden/rx_downstream/pilot_rom.hex", tx_pilot_mem);
        fbits = $fopen("../../../golden/tx/tx_data_bits.txt", "r");
        if (fbits == 0) begin
            $display("FATAL: cannot open tx_data_bits.txt");
            $display("GATE: FAIL_TX_RX_LOOPBACK (no tx_data_bits.txt)"); $finish;
        end
        di0 = 0;
        ch0 = $fgetc(fbits);
        while (ch0 != -1 && di0 < NDATA_BITS) begin
            if (ch0 == "0" || ch0 == "1") begin txbit_chars[di0] = ch0[7:0]; di0 = di0 + 1; end
            ch0 = $fgetc(fbits);
        end
        $fclose(fbits);
        if (di0 != NDATA_BITS) $display("WARN: read %0d TX bits, expected %0d", di0, NDATA_BITS);
        for (zz = 0; zz < NUM_DATA; zz = zz + 1)
            for (bb = 0; bb < NDATA_SC*4; bb = bb + 1)
                data_bits_flat[zz*NDATA_SC*4 + bb] = (txbit_chars[zz*NDATA_SC*4 + bb] == "1");
    end
    // pilot ROM addressed read (symbol-major z*32 + p)
    always @(*) tx_pilot_tdata = tx_pilot_mem[tx_pilot_addr];

    // ---- capture TX slot into slot_gen[0:4031] ----
    logic [31:0] slot_gen [0:SLOT_LEN-1];
    int tx_out_cnt;
    bit tx_slot_done;
    initial begin tx_out_cnt = 0; tx_slot_done = 1'b0; end
    always @(posedge clk) if (aresetn) begin
        if (tx_m_valid && tx_m_ready) begin
            if (tx_out_cnt < SLOT_LEN) slot_gen[tx_out_cnt] <= tx_m_tdata;
            tx_out_cnt <= tx_out_cnt + 1;
            if (tx_m_last) tx_slot_done <= 1'b1;
        end
    end

    // =================================================================
    // STAGE 2 -- FULL RX : rx_full_chain_top (sync + downstream)
    // =================================================================
    // ---- AXI-Lite (unused beyond defaults; force shortcut used) ----
    logic  [6:0] s_axi_awaddr  = 0;
    logic        s_axi_awvalid = 0;
    wire         s_axi_awready;
    logic [31:0] s_axi_wdata   = 0;
    logic  [3:0] s_axi_wstrb   = 4'hF;
    logic        s_axi_wvalid  = 0;
    wire         s_axi_wready;
    wire   [1:0] s_axi_bresp;
    wire         s_axi_bvalid;
    logic        s_axi_bready  = 1'b1;
    logic  [6:0] s_axi_araddr  = 0;
    logic        s_axi_arvalid = 0;
    wire         s_axi_arready;
    wire  [31:0] s_axi_rdata;
    wire   [1:0] s_axi_rresp;
    wire         s_axi_rvalid;
    logic        s_axi_rready  = 1'b1;

    // ---- RX S_AXIS raw IQ ----
    logic [2*IQ_WIDTH-1:0] s_axis_tdata  = 0;
    logic                  s_axis_tvalid = 0;
    wire                   s_axis_tready;
    logic                  s_axis_tlast  = 0;

    // ---- RX pilot ROM stream (pulled one word per captured pilot bin) ----
    logic [2*IQ_WIDTH-1:0] rx_pilot_tdata = 0;
    wire                   rx_pilot_tready;

    // ---- M_AXIS bits ----
    wire  [3:0]            m_bits_tdata;
    wire                   m_bits_tvalid;
    logic                  m_bits_tready = 1'b1;
    wire                   m_bits_tlast;
    wire                   m_bits_tuser;

    // ---- seam taps ----
    wire  [2*IQ_WIDTH-1:0] dbg_sync_m_tdata;
    wire                   dbg_sync_m_tvalid;
    wire                   dbg_sync_m_tready;
    wire                   dbg_sync_m_tlast;
    wire  [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                   dbg_frac_m_tvalid;
    wire                   dbg_frac_m_tready;
    wire                   dbg_frac_m_tlast;

    rx_full_chain_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NUM_PILOTS(NUM_PLT), .NDATA_SC(NDATA_SC), .SCALE_SH(4),
        .THRESHOLD(40000)
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata (s_axi_wdata),  .s_axi_wstrb (s_axi_wstrb),   .s_axi_wvalid(s_axi_wvalid),  .s_axi_wready(s_axi_wready),
        .s_axi_bresp (s_axi_bresp),  .s_axi_bvalid(s_axi_bvalid),  .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rdata (s_axi_rdata),  .s_axi_rresp (s_axi_rresp),   .s_axi_rvalid(s_axi_rvalid),  .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),.s_axis_tlast(s_axis_tlast),
        .pilot_tdata(rx_pilot_tdata), .pilot_tready(rx_pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .dbg_sync_m_tdata(dbg_sync_m_tdata), .dbg_sync_m_tvalid(dbg_sync_m_tvalid),
        .dbg_sync_m_tready(dbg_sync_m_tready),.dbg_sync_m_tlast(dbg_sync_m_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready),.dbg_frac_m_tlast(dbg_frac_m_tlast)
    );

    // ---- force enable/bypass/frame_len (same shortcut as the rx_full_chain gate) ----
    initial begin
        repeat (4) @(posedge clk);
        force dut.u_sync.int_enable        = 1'b1;
        force dut.u_sync.int_bypass_en     = 1'b0;
        force dut.u_sync.int_force_tlast   = 1'b0;
        force dut.u_sync.int_counter_clear = 1'b0;
        force dut.u_sync.int_frame_len     = 12'd4032;
    end

    // ---- load B[k] conj-FFT ROM (hierarchical; wrapper exposes no ROM port) ----
    initial begin
        $readmemh("../../../vectors/bk_conj_fft512_rom.txt",
                  dut.u_sync.u_dut.u_meyr.u_rm_dut.rom);
    end

    // ---- RX pilot ROM golden + golden bits for BER ----
    logic [31:0] plt_mem  [0:NPLT-1];
    logic [7:0]  txbit    [0:NBITS-1];   // '0'/'1' ASCII per data bit
    logic [7:0]  rxbit    [0:NBITS-1];
    initial begin
        $readmemh("../../../golden/rx_downstream/pilot_rom.hex", plt_mem);
    end
    integer fd, ch, ib;
    initial begin
        fd = $fopen("../../../golden/tx/tx_data_bits.txt", "r");
        if (fd == 0) begin $display("FATAL: cannot open tx_data_bits.txt (BER ref)"); $finish; end
        ib = 0;
        ch = $fgetc(fd);
        while (ch != -1 && ib < NBITS) begin
            if (ch == "0" || ch == "1") begin txbit[ib] = ch[7:0]; ib = ib + 1; end
            ch = $fgetc(fd);
        end
        $fclose(fd);
        if (ib != NBITS) $display("WARN: read %0d golden BER bits, expected %0d", ib, NBITS);
    end

    // ---- RX pilot ROM feeder ----
    integer plt_ptr;
    always @(*) rx_pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!aresetn) plt_ptr <= 0;
        else if (rx_pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- counters / observation ----
    int in_count, sync_out_count, bit_out_count;
    bit frame_locked;
    int cyc, first_bit_cyc;
    initial begin
        in_count = 0; sync_out_count = 0; bit_out_count = 0;
        frame_locked = 1'b0; cyc = 0; first_bit_cyc = -1;
    end

    logic [31:0] seam_mem [0:SLOT_LEN-1];

    int diag_wrap_start, diag_frac_start, diag_slot_pulse, diag_fsv_pulse;
    int diag_sfe_beats, diag_cap_done, diag_frac_done, diag_cfo_valid, diag_frac_err;
    initial begin
        diag_wrap_start=0; diag_frac_start=0; diag_slot_pulse=0; diag_fsv_pulse=0;
        diag_sfe_beats=0; diag_cap_done=0; diag_frac_done=0; diag_cfo_valid=0; diag_frac_err=0;
    end

    always @(posedge clk) if (aresetn) begin
        cyc <= cyc + 1;
        if (s_axis_tvalid && s_axis_tready) in_count <= in_count + 1;
        if (dbg_sync_m_tvalid && dbg_sync_m_tready) begin
            if (sync_out_count < SLOT_LEN) seam_mem[sync_out_count] <= dbg_sync_m_tdata;
            sync_out_count <= sync_out_count + 1;
        end
        if (m_bits_tvalid && m_bits_tready) begin
            if (first_bit_cyc < 0) first_bit_cyc = cyc;
            if (bit_out_count < NBEATS) begin
                rxbit[bit_out_count*4 + 0] <= (m_bits_tdata[3]) ? "1" : "0"; // b0
                rxbit[bit_out_count*4 + 1] <= (m_bits_tdata[2]) ? "1" : "0"; // b1
                rxbit[bit_out_count*4 + 2] <= (m_bits_tdata[1]) ? "1" : "0"; // b2
                rxbit[bit_out_count*4 + 3] <= (m_bits_tdata[0]) ? "1" : "0"; // b3
            end
            bit_out_count <= bit_out_count + 1;
        end
        if (dut.u_sync.u_dut.dbg_frame_start_valid) frame_locked <= 1'b1;

        if (dut.u_sync.start_r)                  diag_wrap_start  <= diag_wrap_start + 1;
        if (dut.u_sync.u_dut.frac_start_r)       diag_frac_start  <= diag_frac_start + 1;
        if (dut.u_sync.u_dut.slot_start_pulse)   diag_slot_pulse  <= diag_slot_pulse + 1;
        if (dut.u_sync.u_dut.dbg_frame_start_valid) diag_fsv_pulse <= diag_fsv_pulse + 1;
        if (dut.u_sync.u_dut.sfe_meyr_tvalid)    diag_sfe_beats   <= diag_sfe_beats + 1;
        if (dut.u_sync.u_dut.cap_done)           diag_cap_done    <= diag_cap_done + 1;
        if (dut.u_sync.u_dut.frac_done)          diag_frac_done   <= diag_frac_done + 1;
        if (dut.u_sync.dut_int_cfo_valid)        diag_cfo_valid   <= diag_cfo_valid + 1;
        if (dut.u_sync.u_dut.frac_frame_error)   diag_frac_err    <= diag_frac_err + 1;
    end

    // ---- drive RX S_AXIS : LEAD_IN zeros, then the LIVE TX slot, then trailer.
    //      Identical framing to golden/rx_downstream/tx_slot_iq.hex but the
    //      4032 body comes from the TX RTL (slot_gen). Contiguous, honor tready.
    task automatic drive_input();
        for (int i = 0; i < STIM_BEATS; i = i + 1) begin
            @(posedge clk);
            if (i < LEAD_IN || i >= LEAD_IN + SLOT_LEN)
                s_axis_tdata <= 32'h0000_0000;                 // lead-in / trailer zeros
            else
                s_axis_tdata <= slot_gen[i - LEAD_IN];          // LIVE TX slot
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (i == STIM_BEATS-1);
            while (!s_axis_tready) @(posedge clk);
        end
        @(posedge clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
    endtask

    // progress beacon
    int tick;
    always @(posedge clk) if (aresetn) begin
        tick <= tick + 1;
        if (tick == 5000) begin
            $display("[LOOP] @%0t tx_out=%0d in=%0d sync_out=%0d bits=%0d locked=%0b",
                     $time, tx_out_cnt, in_count, sync_out_count, bit_out_count, frame_locked);
            tick <= 0;
        end
    end

    // ---- main ----
    integer i, errors, fails;

    initial begin : main
        fails = 0;
        tick  = 0;

        // Reset NON-BLOCKING (<=) -- the rx_full_chain reset_done_w edge-race fix.
        aresetn <= 1'b0;
        repeat (40) @(posedge clk);
        aresetn <= 1'b1;
        repeat (20) @(posedge clk);

        // ---------------------------------------------------------------
        // STAGE 1 : kick the LIVE TX, capture its 4032-sample slot
        // ---------------------------------------------------------------
        $display("================================================================");
        $display("[LOOP] STAGE 1 : LIVE TX (tx_ofdm_top) generating 4032 slot");
        $display("================================================================");
        @(posedge clk);
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;

        // wait for the TX slot to be fully emitted (4032 samples)
        begin
            int waited;
            waited = 0;
            while (!(tx_slot_done && tx_out_cnt >= SLOT_LEN) && waited < DRAIN_CYCLES) begin
                @(posedge clk);
                waited = waited + 1;
            end
        end
        $display("[LOOP] TX emitted %0d / %0d slot samples (slot_done=%0b) after %0d cyc",
                 tx_out_cnt, SLOT_LEN, tx_slot_done, cyc);
        if (tx_out_cnt < SLOT_LEN) begin
            $display("[LOOP] FAIL: TX did not emit a full slot");
            $display("GATE: FAIL_TX_RX_LOOPBACK (TX slot incomplete: %0d/%0d)", tx_out_cnt, SLOT_LEN);
            $finish;
        end
        // sanity: sync region (sample 0) must match the known PSS first word
        $display("[LOOP] TX slot[0]=0x%08x (expect 0xFAC111BD)  slot[575]=0x%08x  slot[576]=0x%08x",
                 slot_gen[0], slot_gen[575], slot_gen[576]);
        if (slot_gen[0] !== 32'hFAC111BD)
            $display("[LOOP] WARN: TX sync sample 0 != golden PSS word (sync ROM mismatch?)");

        // ---------------------------------------------------------------
        // ARMING PROBE (sync wrapper start must have armed at reset)
        // ---------------------------------------------------------------
        $display("[ARM] dut_aresetn=%0b int_enable=%0b reset_done_w=%0b start_armed_r=%0b start_r=%0b wrap_start(cnt)=%0d",
                 dut.u_sync.dut_aresetn, dut.u_sync.int_enable,
                 dut.u_sync.reset_done_w, dut.u_sync.start_armed_r,
                 dut.u_sync.start_r, diag_wrap_start);
        if (diag_wrap_start == 0) begin
            $display("[ARM] DIAGNOSTIC EARLY-EXIT: start never fired; aborting drive.");
            $display("GATE: FAIL_TX_RX_LOOPBACK (start never armed)");
            $finish;
        end

        // ---------------------------------------------------------------
        // STAGE 2 : drive the LIVE-generated frame into the FULL RX
        // ---------------------------------------------------------------
        $display("================================================================");
        $display("[LOOP] STAGE 2 : driving LIVE TX frame (%0d samples) into FULL RX",
                 STIM_BEATS);
        $display("================================================================");
        drive_input();

        // wait for all demod bits to drain
        begin
            int waited;
            waited = 0;
            while (bit_out_count < NBEATS && waited < DRAIN_CYCLES) begin
                @(posedge clk);
                waited = waited + 1;
            end
            repeat (10) @(posedge clk);
        end

        // ---- (a) sync lock report ----
        $display("----------------------------------------------------------------");
        $display("[LOOP] SYNC LOCK REPORT");
        $display("   frame_detect_valid seen : %0b", frame_locked);
        $display("   dbg_frame_start_index   : %0d", dut.u_sync.u_dut.dbg_frame_start_index);
        $display("   dbg_peak_index          : %0d", dut.u_sync.u_dut.dbg_peak_index);
        $display("   dbg_slot_start_index    : %0d  (golden 64; +/-1 = absorbed ramp)",
                 dut.u_sync.u_dut.dbg_slot_start_index);
        $display("   frac_cfo_word (Q1.15)   : %0d", $signed(dut.u_sync.u_dut.dbg_frac_cfo_word));
        $display("   int_cfo_step_word       : 0x%08x  (k_int=%0d)",
                 dut.u_sync.u_dut.dbg_integer_cfo_word,
                 -($signed(dut.u_sync.u_dut.dbg_integer_cfo_word) >>> 24));
        $display("   sync corrected beats     : %0d (expect %0d)", sync_out_count, SLOT_LEN);
        $display("   demod bits collected     : %0d (expect %0d)", bit_out_count*4, NBITS);
        $display("   [DIAG] wrap_start=%0d frac_start=%0d slot_pulse=%0d fsv_pulse=%0d",
                 diag_wrap_start, diag_frac_start, diag_slot_pulse, diag_fsv_pulse);
        $display("   [DIAG] sfe_beats=%0d cap_done=%0d frac_done=%0d cfo_valid=%0d frac_err=%0d",
                 diag_sfe_beats, diag_cap_done, diag_frac_done, diag_cfo_valid, diag_frac_err);

        if (!frame_locked) begin
            $display("[LOOP] FAIL: synchronizer never asserted frame_start_valid");
            fails = fails + 1;
        end
        if (sync_out_count == 0) begin
            $display("[LOOP] FAIL: sync produced 0 corrected M_AXIS beats");
            fails = fails + 1;
        end

        // ---- (b) END-TO-END BER vs the SAME input data bits ----
        if (bit_out_count >= NBEATS) begin
            int per_sym [0:NUM_DATA-1];
            int per_bit [0:3];
            int s, c, b, bitpos;
            for (b=0;b<4;b=b+1) per_bit[b]=0;
            for (s=0;s<NUM_DATA;s=s+1) per_sym[s]=0;

            errors = 0;
            for (i = 0; i < NBITS; i = i + 1)
                if (rxbit[i] !== txbit[i]) errors = errors + 1;

            for (s=0;s<NUM_DATA;s=s+1)
                for (c=0;c<NDATA_SC;c=c+1)
                    for (b=0;b<4;b=b+1) begin
                        bitpos = (s*NDATA_SC + c)*4 + b;
                        if (rxbit[bitpos] !== txbit[bitpos]) begin
                            per_sym[s] = per_sym[s] + 1;
                            per_bit[b] = per_bit[b] + 1;
                        end
                    end

            $display("----------------------------------------------------------------");
            $display("[LOOP] END-TO-END BER : RX demod vs TX input data bits");
            $display("   data carriers        : %0d (exp %0d)", bit_out_count, NBEATS);
            $display("   total bits           : %0d", NBITS);
            $display("   bit errors           : %0d", errors);
            $display("   BER                  : %0d / %0d", errors, NBITS);
            $display("   first-bit cycle      : %0d", first_bit_cyc);
            $display("   total run cycle      : %0d", cyc);
            for (s=0;s<NUM_DATA;s=s+1)
                $display("   per-sym err sym %0d : %0d / %0d", s, per_sym[s], NDATA_SC*4);
            $display("   per-bit-pos err      : b0=%0d b1=%0d b2=%0d b3=%0d",
                     per_bit[0], per_bit[1], per_bit[2], per_bit[3]);

            if (errors != 0) begin
                $display("[LOOP] BER FAIL: %0d / %0d bit errors", errors, NBITS);
                fails = fails + 1;
            end else begin
                $display("[LOOP] BER PASS: 0 / %0d bit errors -> TX->sync->RX->demod end to end",
                         NBITS);
            end
        end else begin
            $display("[LOOP] FAIL: only %0d/%0d data carriers collected (drain timeout)",
                     bit_out_count, NBEATS);
            fails = fails + 1;
        end

        $display("================================================================");
        if (fails == 0)
            $display("GATE: PASS_TX_RX_LOOPBACK  (LIVE TX -> sync lock -> RX demod, BER=0/%0d)", NBITS);
        else
            $display("GATE: FAIL_TX_RX_LOOPBACK  (%0d failed checks)", fails);
        $display("================================================================");
        $finish;
    end

    // hard watchdog
    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[LOOP] HARD TIMEOUT @%0t tx_out=%0d in=%0d sync_out=%0d bits=%0d locked=%0b",
                 $time, tx_out_cnt, in_count, sync_out_count, bit_out_count, frame_locked);
        $display("GATE: FAIL_TX_RX_LOOPBACK (hard timeout)");
        $finish;
    end

endmodule

`default_nettype wire
