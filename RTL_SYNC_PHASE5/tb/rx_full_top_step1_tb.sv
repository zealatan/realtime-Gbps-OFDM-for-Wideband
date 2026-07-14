// =====================================================================
// rx_full_top_step1_tb.sv
// ---------------------------------------------------------------------
// FULL-RX INTEGRATION — STEP 1 SELF-CHECKING GATE : SYNC -> FFT
// ---------------------------------------------------------------------
// Proves the SYNC -> FFT FRONT-END seam on rx_full_top.
//
// FLOW (mirrors the P5-D continuous-wrapper gate that drives the frozen
// synchronizer with the real Xilinx xfft IPs):
//   1. Load the B[k] conj-FFT ROM via hierarchical $readmemh (the wrapper
//      does not expose a ROM-write port; the sim patches it exactly like
//      p5_d_continuous_wrapper_tb does).
//   2. Configure the sync wrapper like the P5-CORRECTED / P5-D gate:
//        - enable = 1
//        - bypass = 0
//        - frame_len (0x0C) = 4032
//        - THRESHOLD (build param + 0x68 default) low enough that the
//          sync-capable frame's CP-autocorr peak (832,982,221, identical
//          to fc_kp0) crosses it.  (fc_kp0 detects at THRESHOLD=40000.)
//      enable/bypass/frame_len are force'd post-reset, the same shortcut
//      the existing wrapper gates use.
//   3. Stream golden/rx_downstream/tx_slot_iq.hex — the FULL 4160-sample
//      sync-capable frame (64 PRE_ZEROS + real PSS/SSS sync region +
//      12 data symbols + 64 POST_ZEROS) — into S_AXIS, honoring tready.
//   4. The sync detects+corrects and emits the 4032-sample corrected slot
//      on its M_AXIS; rx_fft_frontend consumes it and emits 12x256 freq
//      bins.  Capture the FFT bins.
//
// VERIFY
//   (a) the sync LOCKS: dbg_frame_start_valid / peak / slot-start fire and
//       the corrected M_AXIS produces the expected 4032 beats (seam tap).
//   (b) the FFT output matches golden/rx_downstream/fft_out.hex within the
//       fixed-point (BFP truncation) budget — because tx_slot_iq is the
//       k_int=0 (zero integer-CFO) case the correction is ~identity on the
//       data symbols, so the FFT of the corrected data symbols == the FFT
//       of the TX data symbols == fft_out golden.  Any residual constant
//       rotation is REPORTED, not masked.
//
// Real xfft 9.1 IPs are used (xsim).  GATE line:
//   GATE: PASS_RX_FULL_STEP1     on success
//   GATE: FAIL_RX_FULL_STEP1     on any failed check or timeout
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_top_step1_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int STIM_BEATS = 4160;                               // full frame
    localparam int NBINS     = NUM_DATA * NSC;                      // 3072

    // FFT-bin tolerance (LSB) vs the golden Q15 view — same budget as the
    // standalone rx_fft_frontend gate (BFP truncation -> a handful of LSB;
    // golden bin magnitudes run to ~6800 LSB so 64 is < 1%).
    localparam int TOL = 64;

    // Drive/drain budget: the meyr core runs ~300 cyc/s in xsim; one slot is
    // ~4000-6000 cyc, plus replay + FFT drain.  Scaled generously.
    localparam int DRAIN_CYCLES = 80000;
    localparam int HARD_TIMEOUT = 6000000;

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

    // ---- M_AXIS FFT bins ----
    wire  [2*IQ_WIDTH-1:0] m_axis_fft_tdata;
    wire                   m_axis_fft_tvalid;
    logic                  m_axis_fft_tready = 1'b1;
    wire                   m_axis_fft_tlast;

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

    // THRESHOLD=40000: same value the P5-D wrapper gate uses; the
    // sync-capable frame's CP-autocorr peak (832,982,221, byte-identical to
    // fc_kp0 in the sync region) is far above it, so the frame detects.
    rx_full_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA), .SCALE_SH(4),
        .THRESHOLD(40000)
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata (s_axi_wdata),  .s_axi_wstrb (s_axi_wstrb),   .s_axi_wvalid(s_axi_wvalid),  .s_axi_wready(s_axi_wready),
        .s_axi_bresp (s_axi_bresp),  .s_axi_bvalid(s_axi_bvalid),  .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),.s_axi_arready(s_axi_arready),
        .s_axi_rdata (s_axi_rdata),  .s_axi_rresp (s_axi_rresp),   .s_axi_rvalid(s_axi_rvalid),  .s_axi_rready(s_axi_rready),
        .s_axis_tdata(s_axis_tdata), .s_axis_tvalid(s_axis_tvalid),.s_axis_tready(s_axis_tready),.s_axis_tlast(s_axis_tlast),
        .m_axis_fft_tdata(m_axis_fft_tdata), .m_axis_fft_tvalid(m_axis_fft_tvalid),
        .m_axis_fft_tready(m_axis_fft_tready),.m_axis_fft_tlast(m_axis_fft_tlast),
        .dbg_sync_m_tdata(dbg_sync_m_tdata), .dbg_sync_m_tvalid(dbg_sync_m_tvalid),
        .dbg_sync_m_tready(dbg_sync_m_tready),.dbg_sync_m_tlast(dbg_sync_m_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready),.dbg_frac_m_tlast(dbg_frac_m_tlast)
    );

    // ---- force enable/bypass/frame_len (same shortcut as wrapper gates) ----
    // Force EARLY (cycle 4, well before the reset release at cycle 40) so that
    // the wrapper's start-arm FSM sees int_enable HIGH at the reset_done_w edge.
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
    logic [31:0] gold_mem [0:NBINS-1];
    initial begin
        $readmemh("../../../golden/rx_downstream/tx_slot_iq.hex", stim_mem);
        $readmemh("../../../golden/rx_downstream/fft_out.hex",     gold_mem);
    end

    // ---- counters / observation ----
    int in_count, sync_out_count, fft_out_count;
    bit frame_locked;
    initial begin
        in_count = 0; sync_out_count = 0; fft_out_count = 0;
        frame_locked = 1'b0;
    end

    // FFT output capture
    logic [31:0] got_mem [0:NBINS-1];

    // seam (sync corrected M_AXIS) capture + golden 4032 reference
    logic [31:0] seam_mem [0:SLOT_LEN-1];
    logic [31:0] slot4032 [0:SLOT_LEN-1];
    initial $readmemh("../../../golden/rx_downstream/tx_slot_iq_4032.hex", slot4032);

    // diagnostic pulse counters (declared before use)
    int diag_wrap_start, diag_frac_start, diag_slot_pulse, diag_fsv_pulse;
    int diag_sfe_beats, diag_cap_done, diag_frac_done, diag_cfo_valid, diag_frac_err;
    initial begin
        diag_wrap_start=0; diag_frac_start=0; diag_slot_pulse=0; diag_fsv_pulse=0;
        diag_sfe_beats=0; diag_cap_done=0; diag_frac_done=0; diag_cfo_valid=0; diag_frac_err=0;
    end

    always @(posedge clk) if (aresetn) begin
        if (s_axis_tvalid && s_axis_tready)             in_count       <= in_count + 1;
        if (dbg_sync_m_tvalid && dbg_sync_m_tready) begin
            if (sync_out_count < SLOT_LEN) seam_mem[sync_out_count] <= dbg_sync_m_tdata;
            sync_out_count <= sync_out_count + 1;
        end
        if (m_axis_fft_tvalid && m_axis_fft_tready) begin
            if (fft_out_count < NBINS) got_mem[fft_out_count] <= m_axis_fft_tdata;
            fft_out_count <= fft_out_count + 1;
        end
        // frame lock indication: frame-detector found the PSS peak
        if (dut.u_sync.u_dut.dbg_frame_start_valid)     frame_locked <= 1'b1;

        // ---- diagnostic pulse counters (mirror p5_d_continuous_wrapper_tb) ----
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

    // ---- drive S_AXIS (honor tready; tvalid stays high, no random gaps so
    //      the sync sees a clean contiguous frame like the wrapper gate) ----
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
            $display("[STEP1] @%0t in=%0d sync_out=%0d fft_out=%0d locked=%0b",
                     $time, in_count, sync_out_count, fft_out_count, frame_locked);
            tick <= 0;
        end
    end

    // ---- main ----
    integer i, sym, k;
    integer gi, gq, ri, rq, ei, eq;
    integer maxerr, errcnt;
    integer fails;
    logic signed [15:0] gi16, gq16, ri16, rq16;

    // residual-rotation probe: average angle (in atan2 LSB-free form) is hard
    // in pure Verilog; instead detect a constant rotation by checking whether
    // a large fraction of bins fail by a SIMILAR magnitude even though the
    // per-bin magnitude |got| ~= |gold|.  We report the magnitude-match rate.
    integer magmatch, magtotal;

    initial begin : main
        fails = 0;
        tick  = 0;

        // Reset sequence — MUST use NON-BLOCKING (<=) on aresetn, exactly like
        // p5_d_continuous_wrapper_tb.  A BLOCKING (=) assignment right after
        // @(posedge clk) races with the wrapper's own @(posedge aclk) sampling:
        // dut_aresetn_prev can capture the NEW value at the SAME edge, so the
        // rising-edge detector reset_done_w never pulses -> start_armed_r stays 0
        // -> start never fires (root cause of the earlier wrap_start=0 stall).
        // Non-blocking defers the update to the NBA region, giving the DUT a
        // clean 0->1 edge across two distinct clocks.
        aresetn <= 1'b0;
        repeat (40) @(posedge clk);   // hold low; force-initial (cycle 4) applies
        aresetn <= 1'b1;              // clean rising edge -> reset_done_w -> arm
        repeat (20) @(posedge clk);   // let arming + start fire

        // ---- ARMING PROBE (diagnose why start may not fire) ----
        $display("[ARM] dut_aresetn=%0b soft_reset_r=%0b int_enable=%0b int_soft_reset=%0b reset_done_w=%0b dut_aresetn_prev=%0b",
                 dut.u_sync.dut_aresetn, dut.u_sync.soft_reset_r,
                 dut.u_sync.int_enable, dut.u_sync.int_soft_reset,
                 dut.u_sync.reset_done_w, dut.u_sync.dut_aresetn_prev);
        $display("[ARM] start_armed_r=%0b dut_busy=%0b start_r=%0b wrap_start(cnt)=%0d sync_top.state=%0d",
                 dut.u_sync.start_armed_r, dut.u_sync.dut_busy,
                 dut.u_sync.start_r, diag_wrap_start, dut.u_sync.u_dut.state);

        // FAST-EXIT diagnostic: if start never fired, the seam never produces
        // data -> skip the long drain and finish so we can iterate quickly.
        if (diag_wrap_start == 0) begin
            $display("[ARM] DIAGNOSTIC EARLY-EXIT: start never fired; aborting drive.");
            $display("GATE: FAIL_RX_FULL_STEP1 (start never armed - arming diag)");
            $finish;
        end

        $display("================================================================");
        $display("[STEP1] SYNC -> FFT integration : driving %0d-sample frame", STIM_BEATS);
        $display("================================================================");

        drive_input(STIM_BEATS);

        // wait for the FFT to drain all bins (or drain budget)
        begin
            int waited;
            waited = 0;
            while (fft_out_count < NBINS && waited < DRAIN_CYCLES) begin
                @(posedge clk);
                waited = waited + 1;
            end
            repeat (10) @(posedge clk);
        end

        // ---- (a) sync lock report ----
        $display("----------------------------------------------------------------");
        $display("[STEP1] SYNC LOCK REPORT");
        $display("   frame_detect_valid seen : %0b", frame_locked);
        $display("   dbg_frame_start_index   : %0d", dut.u_sync.u_dut.dbg_frame_start_index);
        $display("   dbg_peak_index          : %0d", dut.u_sync.u_dut.dbg_peak_index);
        $display("   dbg_slot_start_index    : %0d", dut.u_sync.u_dut.dbg_slot_start_index);
        $display("   dbg_meyr_peak_index     : %0d", dut.u_sync.u_dut.dbg_meyr_peak_index);
        $display("   frac_cfo_word (Q1.15)   : %0d", $signed(dut.u_sync.u_dut.dbg_frac_cfo_word));
        $display("   int_cfo_step_word       : 0x%08x  (k_int=%0d)",
                 dut.u_sync.u_dut.dbg_integer_cfo_word,
                 -($signed(dut.u_sync.u_dut.dbg_integer_cfo_word) >>> 24));
        $display("   sync corrected beats     : %0d (expect %0d)", sync_out_count, SLOT_LEN);
        $display("   fft bins captured        : %0d (expect %0d)", fft_out_count, NBINS);
        $display("   [DIAG] wrap_start=%0d frac_start=%0d slot_pulse=%0d fsv_pulse=%0d",
                 diag_wrap_start, diag_frac_start, diag_slot_pulse, diag_fsv_pulse);
        $display("   [DIAG] sfe_beats=%0d cap_done=%0d frac_done=%0d cfo_valid=%0d frac_err=%0d",
                 diag_sfe_beats, diag_cap_done, diag_frac_done, diag_cfo_valid, diag_frac_err);
        $display("   [DIAG] s_axis_tready(now)=%0b dut_busy=%0b int_enable(forced)=%0b",
                 s_axis_tready, dut.u_sync.dut_busy, dut.u_sync.int_enable);

        if (!frame_locked) begin
            $display("[STEP1] FAIL: synchronizer never asserted frame_start_valid");
            fails = fails + 1;
        end
        if (sync_out_count == 0) begin
            $display("[STEP1] FAIL: sync produced 0 corrected M_AXIS beats");
            fails = fails + 1;
        end
        if (fft_out_count < NBINS) begin
            $display("[STEP1] FAIL: only %0d/%0d FFT bins captured (drain timeout)",
                     fft_out_count, NBINS);
            fails = fails + 1;
        end

        // ---- (a2) SEAM ALIGNMENT SCAN : sync corrected M_AXIS vs golden 4032 ----
        // The standalone fft_frontend gate (fed tx_slot_iq_4032.hex directly)
        // passes; if the seam stream is shifted by a few samples vs that golden,
        // it explains a per-bin linear phase ramp in the FFT (magnitudes match,
        // I/Q rotate).  Scan small offsets and report the best alignment + the
        // exact-match count at offset 0.
        if (sync_out_count >= SLOT_LEN) begin
            int best_off, best_err; longint acc;
            int off, j, exact0;
            int si, sq, ti, tq, di, dq;
            logic signed [15:0] s16i, s16q, t16i, t16q;
            best_off = 0; best_err = 32'h7fffffff;
            for (off = -4; off <= 4; off = off + 1) begin
                acc = 0;
                for (j = 64; j < 64 + 512; j = j + 1) begin   // 1st data sym region
                    if ((j+off) >= 0 && (j+off) < SLOT_LEN) begin
                        s16i = seam_mem[j][15:0];   s16q = seam_mem[j][31:16];
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
            // exact-equal beat count at offset 0
            exact0 = 0;
            for (j = 0; j < SLOT_LEN; j = j + 1)
                if (seam_mem[j] === slot4032[j]) exact0 = exact0 + 1;
            $display("   [SEAM] best-align offset = %0d (min sum|d|=%0d); exact-equal beats @off0 = %0d / %0d",
                     best_off, best_err, exact0, SLOT_LEN);
            $display("   [SEAM] seam[64..67]  = %08x %08x %08x %08x",
                     seam_mem[64], seam_mem[65], seam_mem[66], seam_mem[67]);
            $display("   [SEAM] gold4032[64..67]= %08x %08x %08x %08x",
                     slot4032[64], slot4032[65], slot4032[66], slot4032[67]);
            $display("   [SEAM] seam[0..3]     = %08x %08x %08x %08x",
                     seam_mem[0], seam_mem[1], seam_mem[2], seam_mem[3]);
            $display("   [SEAM] gold4032[0..3]  = %08x %08x %08x %08x",
                     slot4032[0], slot4032[1], slot4032[2], slot4032[3]);
        end

        // ---- (b) FFT vs golden compare (only if we got a full set) ----
        if (fft_out_count >= NBINS) begin
            maxerr = 0; errcnt = 0; magmatch = 0; magtotal = 0;
            for (i = 0; i < NBINS; i = i + 1) begin
                gi16 = gold_mem[i][15:0];   gq16 = gold_mem[i][31:16];
                ri16 = got_mem[i][15:0];    rq16 = got_mem[i][31:16];
                gi = gi16; gq = gq16; ri = ri16; rq = rq16;
                ei = (ri > gi) ? (ri - gi) : (gi - ri);
                eq = (rq > gq) ? (rq - gq) : (gq - rq);
                if (ei > maxerr) maxerr = ei;
                if (eq > maxerr) maxerr = eq;
                if (ei > TOL || eq > TOL) begin
                    errcnt = errcnt + 1;
                    if (errcnt <= 12) begin
                        sym = i / NSC; k = i % NSC;
                        $display("   MISMATCH bin %0d (sym %0d k %0d): got(%0d,%0d) gold(%0d,%0d) err(%0d,%0d)",
                                 i, sym, k, ri, rq, gi, gq, ei, eq);
                    end
                end
                // magnitude-match probe (|got|^2 vs |gold|^2 within ~6%): if
                // magnitudes match but I/Q error is large, that signals a
                // residual CONSTANT ROTATION (phase) rather than a scale/order bug.
                begin
                    int unsigned pg, pr, hi, lo;
                    pg = gi*gi + gq*gq;
                    pr = ri*ri + rq*rq;
                    hi = (pg > pr) ? pg : pr;
                    lo = (pg > pr) ? pr : pg;
                    if (hi > 100) begin              // ignore ~zero bins
                        magtotal = magtotal + 1;
                        if (lo*16 >= hi*15) magmatch = magmatch + 1;  // |.|^2 within ~6%
                    end
                end
            end

            $display("----------------------------------------------------------------");
            $display("[STEP1] FFT vs golden fft_out.hex");
            $display("   bins compared        : %0d", NBINS);
            $display("   per-bin tol (LSB)    : %0d", TOL);
            $display("   max abs err (LSB)    : %0d", maxerr);
            $display("   bins over tol        : %0d", errcnt);
            $display("   magnitude-match rate : %0d / %0d  (|.|^2 within ~6%%)",
                     magmatch, magtotal);
            if (errcnt > 0 && magtotal > 0 && magmatch*100 >= magtotal*95) begin
                $display("   NOTE: |got|~=|gold| on >=95%% of bins but I/Q differ -> the");
                $display("         residual at the seam is a CONSTANT ROTATION (phase),");
                $display("         not a scale / ordering / timing error.  Reported, not masked.");
            end

            if (errcnt != 0) begin
                $display("[STEP1] FFT compare FAIL: %0d bins exceed %0d LSB (max err %0d)",
                         errcnt, TOL, maxerr);
                fails = fails + 1;
            end else begin
                $display("[STEP1] FFT compare PASS: all %0d bins within %0d LSB (max err %0d)",
                         NBINS, TOL, maxerr);
            end
        end

        $display("================================================================");
        if (fails == 0)
            $display("GATE: PASS_RX_FULL_STEP1  (sync locked, fft matches golden, max err %0d LSB)", maxerr);
        else
            $display("GATE: FAIL_RX_FULL_STEP1  (%0d failed checks)", fails);
        $display("================================================================");
        $finish;
    end

    // hard watchdog
    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[STEP1] HARD TIMEOUT @%0t in=%0d sync_out=%0d fft_out=%0d locked=%0b",
                 $time, in_count, sync_out_count, fft_out_count, frame_locked);
        $display("GATE: FAIL_RX_FULL_STEP1 (hard timeout)");
        $finish;
    end

endmodule

`default_nettype wire
