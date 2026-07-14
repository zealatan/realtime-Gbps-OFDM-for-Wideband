// =====================================================================
// rx_full_chain_tb.sv
// ---------------------------------------------------------------------
// FULL-RX INTEGRATION — STEP 2 SELF-CHECKING GATE : SYNC -> FULL DOWNSTREAM
// ---------------------------------------------------------------------
// Proves the COMPLETE rx_full_chain_top (frozen synchronizer DUT +
// frozen rx_downstream_top : FFT -> CE -> EQ -> DEMOD) end to end.
//
// FLOW  (reuses the step-1 sync-drive harness verbatim)
//   1. Load the B[k] conj-FFT ROM via hierarchical $readmemh (the wrapper
//      exposes no ROM-write port; patched exactly like step 1 / the P5-D
//      continuous-wrapper gate).
//   2. Configure the sync wrapper like step 1 :
//        - enable = 1, bypass = 0, force_tlast = 0, counter_clear = 0
//        - frame_len = 4032
//      force'd post-reset (cycle 4, before the cycle-40 reset release) so
//      the wrapper's start-arm FSM sees int_enable HIGH at reset_done_w.
//   3. Drive golden/rx_downstream/tx_slot_iq.hex — the FULL 4160-sample
//      sync-capable frame — into S_AXIS honoring tready.  (aresetn driven
//      NON-BLOCKING : the step-1 fix for the reset_done_w edge race.)
//   4. Feed golden/rx_downstream/pilot_rom.hex (12*32 QPSK pilots) on the
//      pilot ROM stream, advancing on pilot_tready (one word per pilot bin)
//      — exactly as the standalone rx_downstream_top gate does.
//   5. The sync detects+corrects and emits the 4032-sample corrected slot
//      on its M_AXIS; rx_downstream_top runs FFT/CE/EQ/demod and emits
//      12*884 = 10608 bits.  Collect them.
//
// VERIFY — END-TO-END ONLY
//   The MEANINGFUL seam check is demod BER vs golden/rx_downstream/
//   tx_bits.txt (10608 bits).  Because the sync emits slot-1 EARLY by 1
//   sample (slot_start_index 63 vs golden 64 — a within-tolerance timing
//   quantization), each FFT symbol carries a 1-sample cyclic rotation =
//   per-bin linear phase ramp.  Step 1 confirmed the per-stage FFT golden
//   therefore does NOT bit-match (magnitudes match, I/Q rotate).  That ramp
//   is absorbed by the pilot CE (captured as a 1-tap channel delay) and
//   divided out by the ZF EQ.  So we do NOT check fft_out/hest/eq_out at the
//   seam; the correct criterion is END-TO-END BER after CE/EQ absorb it.
//
//   PASS  <=>  all 10608 bits collected AND BER == 0 (or near 0).
//   GATE line:  GATE: PASS_RX_FULL_CHAIN   /  GATE: FAIL_RX_FULL_CHAIN
//
// Real xfft 9.1 IPs are used (xsim).  Reports BER, the absorbed 1-sample
// offset (seam best-align scan), the first-bit / total-pipeline latency.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_chain_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int NUM_PLT   = 32;
    localparam int NDATA_SC  = 221;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int STIM_BEATS = 4160;                               // full frame
    localparam int NBEATS    = NUM_DATA * NDATA_SC;                 // 2652
    localparam int NBITS     = NBEATS * 4;                          // 10608
    localparam int NPLT      = NUM_DATA * NUM_PLT;                  // 384

    // Drive/drain budget: the meyr core runs ~300 cyc/s in xsim; one slot is
    // ~4000-6000 cyc, plus replay + FFT/CE/EQ/demod drain.  Scaled generously.
    localparam int DRAIN_CYCLES = 200000;
    localparam int HARD_TIMEOUT = 8000000;

    // ---- clock / reset ----
    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;

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

    // ---- S_AXIS raw IQ ----
    logic [2*IQ_WIDTH-1:0] s_axis_tdata  = 0;
    logic                  s_axis_tvalid = 0;
    wire                   s_axis_tready;
    logic                  s_axis_tlast  = 0;

    // ---- pilot ROM stream ----
    logic [2*IQ_WIDTH-1:0] pilot_tdata = 0;
    wire                   pilot_tready;

    // ---- M_AXIS bits ----
    wire  [3:0]            m_bits_tdata;
    wire                   m_bits_tvalid;
    logic                  m_bits_tready = 1'b1;
    wire                   m_bits_tlast;
    wire                   m_bits_tuser;

    // ---- seam tap ----
    wire  [2*IQ_WIDTH-1:0] dbg_sync_m_tdata;
    wire                   dbg_sync_m_tvalid;
    wire                   dbg_sync_m_tready;
    wire                   dbg_sync_m_tlast;

    // ---- frac tap ----
    wire  [2*IQ_WIDTH-1:0] dbg_frac_m_tdata;
    wire                   dbg_frac_m_tvalid;
    wire                   dbg_frac_m_tready;
    wire                   dbg_frac_m_tlast;

    // THRESHOLD=40000: same value the P5-D / step-1 gates use; the
    // sync-capable frame's CP-autocorr peak is far above it -> the frame
    // detects.  CE_W_ROM / EQ_LUT_FILE kept at their RELATIVE defaults; the
    // runner symlinks rtl/ + drops the LUT into the sim cwd so they resolve.
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
        .pilot_tdata(pilot_tdata), .pilot_tready(pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .dbg_sync_m_tdata(dbg_sync_m_tdata), .dbg_sync_m_tvalid(dbg_sync_m_tvalid),
        .dbg_sync_m_tready(dbg_sync_m_tready),.dbg_sync_m_tlast(dbg_sync_m_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready),.dbg_frac_m_tlast(dbg_frac_m_tlast)
    );

    // ---- force enable/bypass/frame_len (same shortcut as step 1 / wrapper gates) ----
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

    // ---- golden vectors ----
    logic [31:0] stim_mem [0:STIM_BEATS-1];
    logic [31:0] plt_mem  [0:NPLT-1];
    logic [31:0] slot4032 [0:SLOT_LEN-1];
    logic [7:0]  txbit    [0:NBITS-1];   // '0'/'1' ASCII per data bit
    logic [7:0]  rxbit    [0:NBITS-1];
    initial begin
        $readmemh("../../../golden/rx_downstream/tx_slot_iq.hex",      stim_mem);
        $readmemh("../../../golden/rx_downstream/pilot_rom.hex",       plt_mem);
        $readmemh("../../../golden/rx_downstream/tx_slot_iq_4032.hex", slot4032);
    end

    // load tx_bits.txt char-by-char (keep only '0'/'1')
    integer fd, ch, ib;
    initial begin
        fd = $fopen("../../../golden/rx_downstream/tx_bits.txt", "r");
        if (fd == 0) begin $display("FATAL: cannot open tx_bits.txt"); $finish; end
        ib = 0;
        ch = $fgetc(fd);
        while (ch != -1 && ib < NBITS) begin
            if (ch == "0" || ch == "1") begin txbit[ib] = ch[7:0]; ib = ib + 1; end
            ch = $fgetc(fd);
        end
        $fclose(fd);
        if (ib != NBITS) $display("WARN: read %0d golden bits, expected %0d", ib, NBITS);
    end

    // ---- pilot ROM feeder: present plt_mem[plt_ptr]; advance on pilot_tready ----
    integer plt_ptr;
    always @(*) pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!aresetn) plt_ptr <= 0;
        else if (pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- counters / observation ----
    int in_count, sync_out_count, bit_out_count;
    bit frame_locked;
    int cyc, first_bit_cyc;
    initial begin
        in_count = 0; sync_out_count = 0; bit_out_count = 0;
        frame_locked = 1'b0; cyc = 0; first_bit_cyc = -1;
    end

    // seam (sync corrected M_AXIS) capture for the absorbed-offset report
    logic [31:0] seam_mem [0:SLOT_LEN-1];

    // diagnostic pulse counters (mirror step 1)
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
        // demod bit collection (b0 first : m_bits[3..0] = b0,b1,b2,b3)
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

        // ---- diagnostic pulse counters ----
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

    // ---- drive S_AXIS (honor tready; clean contiguous frame like step 1) ----
    task automatic drive_input(input int n);
        for (int i = 0; i < n; i = i + 1) begin
            @(posedge clk);
            s_axis_tdata  <= stim_mem[i];
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (i == n-1);
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
            $display("[STEP2] @%0t in=%0d sync_out=%0d bits=%0d locked=%0b",
                     $time, in_count, sync_out_count, bit_out_count, frame_locked);
            tick <= 0;
        end
    end

    // ---- main ----
    integer i, errors, fails;

    initial begin : main
        fails = 0;
        tick  = 0;

        // Reset : NON-BLOCKING (<=) on aresetn — the step-1 fix.  A BLOCKING
        // assignment right after @(posedge clk) races with the wrapper's own
        // @(posedge aclk) sampling so reset_done_w never pulses -> start never
        // arms.  Non-blocking gives a clean 0->1 edge across the two clocks.
        aresetn <= 1'b0;
        repeat (40) @(posedge clk);   // hold low; force-initial (cycle 4) applies
        aresetn <= 1'b1;              // clean rising edge -> reset_done_w -> arm
        repeat (20) @(posedge clk);   // let arming + start fire

        // ---- ARMING PROBE ----
        $display("[ARM] dut_aresetn=%0b int_enable=%0b reset_done_w=%0b start_armed_r=%0b start_r=%0b wrap_start(cnt)=%0d",
                 dut.u_sync.dut_aresetn, dut.u_sync.int_enable,
                 dut.u_sync.reset_done_w, dut.u_sync.start_armed_r,
                 dut.u_sync.start_r, diag_wrap_start);

        if (diag_wrap_start == 0) begin
            $display("[ARM] DIAGNOSTIC EARLY-EXIT: start never fired; aborting drive.");
            $display("GATE: FAIL_RX_FULL_CHAIN (start never armed - arming diag)");
            $finish;
        end

        $display("================================================================");
        $display("[STEP2] SYNC -> FULL DOWNSTREAM : driving %0d-sample frame", STIM_BEATS);
        $display("================================================================");

        drive_input(STIM_BEATS);

        // wait for all demod bits to drain (or drain budget)
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
        $display("[STEP2] SYNC LOCK REPORT");
        $display("   frame_detect_valid seen : %0b", frame_locked);
        $display("   dbg_frame_start_index   : %0d", dut.u_sync.u_dut.dbg_frame_start_index);
        $display("   dbg_peak_index          : %0d", dut.u_sync.u_dut.dbg_peak_index);
        $display("   dbg_slot_start_index    : %0d  (golden 64; EARLY by 1 = absorbed ramp)",
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
            $display("[STEP2] FAIL: synchronizer never asserted frame_start_valid");
            fails = fails + 1;
        end
        if (sync_out_count == 0) begin
            $display("[STEP2] FAIL: sync produced 0 corrected M_AXIS beats");
            fails = fails + 1;
        end

        // ---- (a2) ABSORBED-OFFSET REPORT : sync corrected M_AXIS vs golden 4032 ----
        // Confirms the 1-sample EARLY emission that CE/EQ must absorb : the
        // seam best-aligns at offset -1 (essentially exact), proving the
        // residual is a pure 1-sample timing shift (linear phase ramp).
        if (sync_out_count >= SLOT_LEN) begin
            int best_off, off, j; longint acc, best_err;
            int si, sq, ti, tq, di, dq;
            logic signed [15:0] s16i, s16q, t16i, t16q;
            best_off = 0; best_err = 64'h7fffffffffffffff;
            for (off = -4; off <= 4; off = off + 1) begin
                acc = 0;
                for (j = 64; j < 64 + 512; j = j + 1) begin   // 1st data sym region
                    if ((j+off) >= 0 && (j+off) < SLOT_LEN) begin
                        s16i = seam_mem[j][15:0];     s16q = seam_mem[j][31:16];
                        t16i = slot4032[j+off][15:0]; t16q = slot4032[j+off][31:16];
                        si=s16i; sq=s16q; ti=t16i; tq=t16q;
                        di = (si>ti)?(si-ti):(ti-si);
                        dq = (sq>tq)?(sq-tq):(tq-sq);
                        acc = acc + di + dq;
                    end
                end
                if (acc < best_err) begin best_err = acc; best_off = off; end
                $display("   [SEAM] offset %0d : sum|d| over [64,576) = %0d", off, acc);
            end
            $display("   [SEAM] best-align offset = %0d (min sum|d|=%0d)  ", best_off, best_err);
            if (best_off == -1)
                $display("   [SEAM] -> sync emits slot 1 EARLY by 1 sample (per-bin linear");
            $display("   [SEAM]    phase ramp).  Absorbed by CE (1-tap delay) + ZF EQ.");
        end

        // ---- (b) END-TO-END BER vs golden tx_bits.txt (THE seam criterion) ----
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
            $display("[STEP2] END-TO-END BER vs golden tx_bits.txt");
            $display("   data carriers        : %0d (exp %0d)", bit_out_count, NBEATS);
            $display("   total bits           : %0d", NBITS);
            $display("   bit errors           : %0d", errors);
            $display("   BER                  : %0d / %0d", errors, NBITS);
            $display("   first-bit cycle      : %0d", first_bit_cyc);
            $display("   total run cycle      : %0d", cyc);
            $display("   pipeline latency     : ~%0d cycles (sync lock -> first bit)", first_bit_cyc);
            for (s=0;s<NUM_DATA;s=s+1)
                $display("   per-sym err sym %0d : %0d / %0d", s, per_sym[s], NDATA_SC*4);
            $display("   per-bit-pos err      : b0=%0d b1=%0d b2=%0d b3=%0d",
                     per_bit[0], per_bit[1], per_bit[2], per_bit[3]);

            if (errors != 0) begin
                $display("[STEP2] BER FAIL: %0d / %0d bit errors", errors, NBITS);
                fails = fails + 1;
            end else begin
                $display("[STEP2] BER PASS: 0 / %0d bit errors -> CE/EQ absorbed the 1-sample ramp",
                         NBITS);
            end
        end else begin
            $display("[STEP2] FAIL: only %0d/%0d data carriers collected (drain timeout)",
                     bit_out_count, NBEATS);
            fails = fails + 1;
        end

        $display("================================================================");
        if (fails == 0)
            $display("GATE: PASS_RX_FULL_CHAIN  (sync locked, BER=0 end-to-end, 1-sample ramp absorbed)");
        else
            $display("GATE: FAIL_RX_FULL_CHAIN  (%0d failed checks)", fails);
        $display("================================================================");
        $finish;
    end

    // hard watchdog
    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[STEP2] HARD TIMEOUT @%0t in=%0d sync_out=%0d bits=%0d locked=%0b",
                 $time, in_count, sync_out_count, bit_out_count, frame_locked);
        $display("GATE: FAIL_RX_FULL_CHAIN (hard timeout)");
        $finish;
    end

endmodule

`default_nettype wire
