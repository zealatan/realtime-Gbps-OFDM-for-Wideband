// =====================================================================
// rx_full_chain_multiframe_tb.sv
// ---------------------------------------------------------------------
// MULTI-FRAME CONTINUOUS-STREAMING robustness gate for rx_full_chain_top.
//
// Loops the SINGLE proven sync-capable golden frame
// (golden/rx_downstream/tx_slot_iq.hex, 4160 samples, INPUT_PERIOD) N
// times BACK-TO-BACK (no idle, no reset between frames) into S_AXIS and
// checks the FULL-RX demod BER PER FRAME vs golden/rx_downstream/tx_bits.txt.
//
// Because every frame is byte-identical, each frame's expected demod bits
// are the SAME 10608-bit golden vector -> per-frame BER must be 0 if the
// receiver streams continuously without dropping/corrupting samples.
//
// TWO source modes (select with +FREERUN=1):
//   (a) DEFAULT (backpressure-honoring): the driver waits while
//       !s_axis_tready (re-presents the beat) -> AXI-correct. This is the
//       SAME contract the on-board dut_player.v enforces.
//   (b) +FREERUN=1 (free-running): tvalid held high, advance EVERY cycle
//       regardless of s_axis_tready -> beats presented while tready=0 are
//       SILENTLY DROPPED (models a non-backpressuring DMA/BRAM player).
//       Counts dropped beats.
//
// The downstream pilot ROM is the 384-word golden pilot set, wrapped per
// slot (same pilots every frame, since every frame is identical). Bits are
// collected for ALL N frames and scored per-frame.
//
// Plusargs:
//   +NFRAMES=<n>   number of contiguous frames (default 5)
//   +FREERUN=<0|1> source mode (default 0 = backpressure-honoring)
//
// GATE line:
//   GATE: PASS_RX_MULTIFRAME nframes=<n> mode=<bp|freerun> ok=<k>/<n>
//   GATE: FAIL_RX_MULTIFRAME ...
// Per-frame:
//   MFRAME mode=<..> FRAME=<f> LOCKED=<0|1> BITS=<n> ERRORS=<n> RESULT=<..>
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_full_chain_multiframe_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int NUM_PLT   = 32;
    localparam int NDATA_SC  = 221;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int STIM_BEATS = 4160;                              // full frame
    localparam int NBEATS    = NUM_DATA * NDATA_SC;                // 2652 / frame
    localparam int NBITS     = NBEATS * 4;                         // 10608 / frame
    localparam int NPLT      = NUM_DATA * NUM_PLT;                 // 384 / frame
    localparam int MAXF      = 16;                                 // capacity cap

    localparam int DRAIN_CYCLES = 300000;
    localparam int HARD_TIMEOUT = 60000000;

    // ---- clock / reset ----
    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;

    // ---- AXI-Lite (force shortcut, like the proven single-frame gate) ----
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
        .pilot_tdata(pilot_tdata), .pilot_tready(pilot_tready),
        .m_bits_tdata(m_bits_tdata), .m_bits_tvalid(m_bits_tvalid),
        .m_bits_tready(m_bits_tready), .m_bits_tlast(m_bits_tlast), .m_bits_tuser(m_bits_tuser),
        .dbg_sync_m_tdata(dbg_sync_m_tdata), .dbg_sync_m_tvalid(dbg_sync_m_tvalid),
        .dbg_sync_m_tready(dbg_sync_m_tready),.dbg_sync_m_tlast(dbg_sync_m_tlast),
        .dbg_frac_m_tdata(dbg_frac_m_tdata), .dbg_frac_m_tvalid(dbg_frac_m_tvalid),
        .dbg_frac_m_tready(dbg_frac_m_tready),.dbg_frac_m_tlast(dbg_frac_m_tlast)
    );

    // ---- force enable/bypass/frame_len (same shortcut as the proven gate) ----
    initial begin
        repeat (4) @(posedge clk);
        force dut.u_sync.int_enable        = 1'b1;
        force dut.u_sync.int_bypass_en     = 1'b0;
        force dut.u_sync.int_force_tlast   = 1'b0;
        force dut.u_sync.int_counter_clear = 1'b0;
        force dut.u_sync.int_frame_len     = 12'd4032;
    end

    // ---- load B[k] conj-FFT ROM (hierarchical) ----
    initial begin
        $readmemh("bk_conj_fft512_rom.txt",
                  dut.u_sync.u_dut.u_meyr.u_rm_dut.rom);
    end

    // ---- golden vectors ----
    logic [31:0] stim_mem [0:STIM_BEATS-1];
    logic [31:0] plt_mem  [0:NPLT-1];
    logic [7:0]  txbit    [0:NBITS-1];               // golden bits (same per frame)
    logic [7:0]  rxbit    [0:MAXF*NBITS-1];          // collected bits across frames
    initial begin
        $readmemh("tx_slot_iq.hex", stim_mem);
        $readmemh("pilot_rom.hex",  plt_mem);
    end

    integer fd, ch, ib;
    initial begin
        fd = $fopen("tx_bits.txt", "r");
        if (fd == 0) begin $display("FATAL: cannot open tx_bits.txt"); $finish; end
        ib = 0; ch = $fgetc(fd);
        while (ch != -1 && ib < NBITS) begin
            if (ch == "0" || ch == "1") begin txbit[ib] = ch[7:0]; ib = ib + 1; end
            ch = $fgetc(fd);
        end
        $fclose(fd);
        if (ib != NBITS) $display("WARN: read %0d golden bits, expected %0d", ib, NBITS);
    end

    // ---- pilot ROM feeder: present plt_mem[plt_ptr]; wrap per slot ----
    integer plt_ptr;
    always @(*) pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!aresetn) plt_ptr <= 0;
        else if (pilot_tready) begin
            if (plt_ptr == NPLT-1) plt_ptr <= 0;     // wrap per frame (identical pilots)
            else                   plt_ptr <= plt_ptr + 1;
        end
    end

    // ---- config / counters ----
    int  nframes;
    bit  freerun;
    int  in_count, bit_out_count, dropped_beats;
    int  cyc, first_bit_cyc;
    int  lock_pulses;
    initial begin in_count=0; bit_out_count=0; dropped_beats=0; cyc=0; first_bit_cyc=-1; lock_pulses=0; end

    always @(posedge clk) if (aresetn) begin
        cyc <= cyc + 1;
        if (s_axis_tvalid && s_axis_tready) in_count <= in_count + 1;
        if (dut.u_sync.u_dut.dbg_frame_start_valid) lock_pulses <= lock_pulses + 1;
        if (m_bits_tvalid && m_bits_tready) begin
            if (first_bit_cyc < 0) first_bit_cyc = cyc;
            if (bit_out_count < nframes*NBEATS) begin
                rxbit[bit_out_count*4 + 0] <= (m_bits_tdata[3]) ? "1" : "0"; // b0
                rxbit[bit_out_count*4 + 1] <= (m_bits_tdata[2]) ? "1" : "0"; // b1
                rxbit[bit_out_count*4 + 2] <= (m_bits_tdata[1]) ? "1" : "0"; // b2
                rxbit[bit_out_count*4 + 3] <= (m_bits_tdata[0]) ? "1" : "0"; // b3
            end
            bit_out_count <= bit_out_count + 1;
        end
    end

    // ---- backpressure-honoring contiguous driver (mode a) ----
    task automatic drive_bp(input int nf);
        for (int f = 0; f < nf; f = f + 1) begin
            $display("[DRIVE-BP] t=%0t frame %0d START (in=%0d)", $time, f, in_count);
            for (int i = 0; i < STIM_BEATS; i = i + 1) begin
                @(posedge clk);
                s_axis_tdata  <= stim_mem[i];
                s_axis_tvalid <= 1'b1;
                s_axis_tlast  <= (f == nf-1) && (i == STIM_BEATS-1);
                while (!s_axis_tready) @(posedge clk);   // strict backpressure
            end
        end
        @(posedge clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
    endtask

    // ---- free-running contiguous driver (mode b): drop on !tready ----
    task automatic drive_freerun(input int nf);
        dropped_beats = 0;
        for (int f = 0; f < nf; f = f + 1) begin
            $display("[DRIVE-FR] t=%0t frame %0d START (in=%0d drop=%0d)", $time, f, in_count, dropped_beats);
            for (int i = 0; i < STIM_BEATS; i = i + 1) begin
                s_axis_tdata  <= stim_mem[i];
                s_axis_tvalid <= 1'b1;
                s_axis_tlast  <= (f == nf-1) && (i == STIM_BEATS-1);
                @(posedge clk);
                if (!s_axis_tready) dropped_beats = dropped_beats + 1; // advance regardless -> drop
            end
        end
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
        @(posedge clk);
    endtask

    // progress beacon
    int tick;
    always @(posedge clk) if (aresetn) begin
        tick <= tick + 1;
        if (tick == 20000) begin
            $display("[MF] @%0t in=%0d bits=%0d locks=%0d drop=%0d",
                     $time, in_count, bit_out_count*4, lock_pulses, dropped_beats);
            tick <= 0;
        end
    end

    integer i, f, frame_err, ok_frames;
    string  modestr;
    initial begin : main
        tick = 0;
        if (!$value$plusargs("NFRAMES=%d", nframes)) nframes = 5;
        if (!$value$plusargs("FREERUN=%d", freerun)) freerun = 0;
        if (nframes > MAXF) nframes = MAXF;
        modestr = freerun ? "freerun" : "bp";

        aresetn <= 1'b0;
        repeat (40) @(posedge clk);
        aresetn <= 1'b1;
        repeat (20) @(posedge clk);

        $display("================================================================");
        $display("[MF] MULTI-FRAME STREAMING : %0d contiguous IDENTICAL golden frames, mode=%s",
                 nframes, modestr);
        $display("================================================================");

        if (freerun) drive_freerun(nframes);
        else         drive_bp(nframes);

        if (freerun)
            $display("[MF] free-run dropped_beats(total) = %0d", dropped_beats);

        // drain : exit on completion, DRAIN_CYCLES budget, OR a long stall
        // (no new demod bit for STALL_GAP cycles => the chain has gone quiet;
        //  print the table instead of burning the whole budget).
        begin
            int waited; int last_bits; int stall;
            localparam int STALL_GAP = 60000;   // > 1 slot of meyr processing
            waited = 0; last_bits = bit_out_count; stall = 0;
            while (bit_out_count < nframes*NBEATS && waited < DRAIN_CYCLES) begin
                @(posedge clk); waited = waited + 1;
                if (bit_out_count != last_bits) begin last_bits = bit_out_count; stall = 0; end
                else stall = stall + 1;
                if (stall >= STALL_GAP) begin
                    $display("[MF] DRAIN stall: no new bit for %0d cyc (bits=%0d) -> chain quiet, scoring now",
                             STALL_GAP, bit_out_count*4);
                    waited = DRAIN_CYCLES;  // break
                end
            end
            repeat (20) @(posedge clk);
        end

        $display("----------------------------------------------------------------");
        $display("[MF] nframes=%0d mode=%s lock_pulses=%0d total_bits=%0d/%0d first_bit_cyc=%0d in=%0d drop=%0d",
                 nframes, modestr, lock_pulses, bit_out_count*4, nframes*NBITS,
                 first_bit_cyc, in_count, dropped_beats);

        ok_frames = 0;
        for (f = 0; f < nframes; f = f + 1) begin
            frame_err = 0;
            if ((f+1)*NBEATS <= bit_out_count) begin
                for (i = 0; i < NBITS; i = i + 1)
                    if (rxbit[f*NBITS + i] !== txbit[i]) frame_err = frame_err + 1;
            end else begin
                frame_err = NBITS;  // not collected
            end
            if (frame_err == 0) ok_frames = ok_frames + 1;
            $display("MFRAME mode=%s FRAME=%0d LOCKED=%0d BITS=%0d ERRORS=%0d RESULT=%s",
                     modestr, f, (lock_pulses > f),
                     ((f+1)*NBEATS <= bit_out_count) ? NBITS : 0,
                     frame_err, (frame_err==0) ? "PASS" : "FAIL");
        end

        $display("================================================================");
        if (ok_frames == nframes && bit_out_count >= nframes*NBEATS)
            $display("GATE: PASS_RX_MULTIFRAME nframes=%0d mode=%s ok=%0d/%0d",
                     nframes, modestr, ok_frames, nframes);
        else
            $display("GATE: FAIL_RX_MULTIFRAME nframes=%0d mode=%s ok=%0d/%0d",
                     nframes, modestr, ok_frames, nframes);
        $display("================================================================");
        $finish;
    end

    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[MF] HARD TIMEOUT in=%0d bits=%0d locks=%0d", in_count, bit_out_count*4, lock_pulses);
        $display("GATE: FAIL_RX_MULTIFRAME (hard timeout)");
        $finish;
    end

endmodule

`default_nettype wire
