// =====================================================================
// rx_cfo_allmods_tb.sv  --  PHASE-2 CFO robustness, ALL MODULATIONS
// ---------------------------------------------------------------------
// Proves the FROZEN synchronizer's fractional + integer CFO correction
// recovers a carrier frequency offset for every modulation order, end to
// end through rx_full_chain_top (sync -> FFT -> CE -> EQ -> demod).
//
// FRAME SOURCE : the per-mod golden tx_slot_iq.hex files have ZEROED sync
// symbols (downstream-only), so they CANNOT drive the real sync chain.
// Instead this TB instantiates the REAL transmitter (tx_ofdm_top, the same
// block the TX-TOP gate proves produces a sync-EXACT 4032 slot) to generate
// a proper sync-capable slot for the selected modulation, captures it, then:
//
//   captured 4032 slot (2 REAL PSS/SSS sync + 12 data)
//     wrapped to 4160  (64 leading + 64 trailing zeros)
//     x  e^{ j 2*pi * EPS * n / NSC }            (carrier frequency offset)
//   --> rx_full_chain_top(mod_sel) --> demod bits --> BER vs the SAME bits
//                                                      fed into the TX.
//
// CFO model : EPS is the offset in SUBCARRIER-SPACING units (EPS=0.25 -> a
// quarter-subcarrier fractional CFO).  Passed as integer milli-units via
// +CFO_MILLI.  Phase increment per sample = 2*pi*EPS/NSC, applied to the
// WHOLE stream -- exactly what a real RF CFO does -- so the synchronizer
// must estimate AND correct it for the demod to recover the bits.
//
//   +MOD=<0|1|2|3>      modulation (default 1=16QAM)
//   +CFO_MILLI=<int>    EPS*1000 in subcarrier-spacing units (default 250)
//
// PASS  <=>  sync locks AND all carriers collected AND BER == 0.
// Gate line: CFO_RESULT MOD=<m> CFO_MILLI=<c> BER <e> / <n> -> PASS|FAIL
//            plus GATE: PASS_RX_CFO / GATE: FAIL_RX_CFO
//
// Real xfft 9.1 IPs (xsim) : the TX inverse-FFT instance + the sync/RX
// forward instances all use the real IP.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_cfo_allmods_tb;

    localparam int IQ_WIDTH  = 16;
    localparam int NSC       = 256;
    localparam int CP_LEN    = 32;
    localparam int NUM_SYN   = 2;
    localparam int NUM_DATA  = 12;
    localparam int NUM_PLT   = 32;
    localparam int NDATA_SC  = 221;
    localparam int SLOT_LEN  = (NUM_SYN + NUM_DATA)*(NSC + CP_LEN); // 4032
    localparam int LEAD      = 64;
    localparam int STIM_BEATS = 4160;                              // wrapped frame
    localparam int NBEATS    = NUM_DATA * NDATA_SC;                // 2652
    localparam int NPLT      = NUM_DATA * NUM_PLT;                 // 384
    localparam int BPC_MAX   = 8;

    localparam int DRAIN_CYCLES = 200000;
    localparam int HARD_TIMEOUT = 12000000;

    // ---- runtime plusargs ----
    integer MOD, CFO_MILLI, BPS;
    reg [1:0] mod_sel;
    reg [1023:0] gdir;
    real eps, dphi;

    // ---- clock / reset ----
    // The DUT (sync chain) auto-arms on the aresetn rising edge, then expects
    // the frame to arrive promptly.  So we hold aresetn LOW while the TX
    // generates its slot (TX has its OWN reset, tx_rst_n, released early), and
    // only release aresetn once the slot is captured -- then drive immediately,
    // exactly like the known-good rx_full_chain_tb timing.
    logic clk = 0;
    always #2 clk = ~clk;          // 250 MHz
    logic aresetn = 0;             // DUT (sync) reset, released after TX capture
    logic tx_rst_n = 0;            // TX reset, released early
    wire  rst_n = tx_rst_n;        // TX uses its own reset

    // ================= TRANSMITTER (slot generator) ==================
    reg          tx_start;
    wire         tx_busy;
    reg  [NUM_DATA*NDATA_SC*BPC_MAX-1:0] data_bits_flat;
    wire [8:0]   tx_pilot_addr;
    reg  [31:0]  tx_pilot_tdata;
    wire         tx_m_valid;
    reg          tx_m_ready;
    wire [31:0]  tx_m_tdata;
    wire         tx_m_last;

    tx_ofdm_top #(
        .DATA_W(16), .NSC(256), .CP_LEN(32), .NUM_SYN(2), .NUM_DATA(12),
        .NPIL(32), .NDATA_SC(221), .BPC_MAX(8), .Q16_1(1610), .Q16_3(4829),
        .SPECMAP("rtl/tx_rom/tx_specmap.hex"),
        .SYNC_ROM("rtl/tx_rom/tx_sync_rom.hex")
    ) u_tx (
        .clk(clk), .rst_n(rst_n),
        .mod_sel(mod_sel),
        .start(tx_start), .busy(tx_busy),
        .data_bits_flat(data_bits_flat),
        .pilot_addr(tx_pilot_addr), .pilot_tdata(tx_pilot_tdata),
        .m_valid(tx_m_valid), .m_ready(tx_m_ready),
        .m_tdata(tx_m_tdata), .m_last(tx_m_last)
    );

    // ---- capture the TX 4032 slot into slot4032[] ----
    logic [31:0] slot4032 [0:SLOT_LEN-1];
    int tx_cap;
    always @(posedge clk) begin
        if (!rst_n) tx_cap <= 0;
        else if (tx_m_valid && tx_m_ready && tx_cap < SLOT_LEN) begin
            slot4032[tx_cap] <= tx_m_tdata;
            tx_cap <= tx_cap + 1;
        end
    end
    wire tx_slot_done = (tx_cap >= SLOT_LEN);

    // ================= DUT : sync -> downstream ======================
    logic  [6:0] s_axi_awaddr=0;  logic s_axi_awvalid=0;  wire s_axi_awready;
    logic [31:0] s_axi_wdata=0;   logic [3:0] s_axi_wstrb=4'hF; logic s_axi_wvalid=0; wire s_axi_wready;
    wire   [1:0] s_axi_bresp;     wire s_axi_bvalid;       logic s_axi_bready=1'b1;
    logic  [6:0] s_axi_araddr=0;  logic s_axi_arvalid=0;   wire s_axi_arready;
    wire  [31:0] s_axi_rdata;     wire [1:0] s_axi_rresp;  wire s_axi_rvalid; logic s_axi_rready=1'b1;

    logic [2*IQ_WIDTH-1:0] s_axis_tdata=0;  logic s_axis_tvalid=0; wire s_axis_tready; logic s_axis_tlast=0;
    logic [2*IQ_WIDTH-1:0] pilot_tdata=0;   wire pilot_tready;
    wire  [BPC_MAX-1:0] m_bits_tdata;  wire m_bits_tvalid; logic m_bits_tready=1'b1;
    wire  m_bits_tlast; wire m_bits_tuser;
    wire  [2*IQ_WIDTH-1:0] dbg_sync_m_tdata; wire dbg_sync_m_tvalid, dbg_sync_m_tready, dbg_sync_m_tlast;
    wire  [2*IQ_WIDTH-1:0] dbg_frac_m_tdata; wire dbg_frac_m_tvalid, dbg_frac_m_tready, dbg_frac_m_tlast;

    rx_full_chain_top #(
        .IQ_WIDTH(IQ_WIDTH), .NSC(NSC), .CP_LEN(CP_LEN),
        .NUM_SYN(NUM_SYN), .NUM_DATA(NUM_DATA),
        .NUM_PILOTS(NUM_PLT), .NDATA_SC(NDATA_SC), .BPC_MAX(BPC_MAX), .SCALE_SH(4),
        .THRESHOLD(40000)
    ) dut (
        .aclk(clk), .aresetn(aresetn),
        .mod_sel(mod_sel),
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

    // ---- force enable/bypass/frame_len (step-1 shortcut) ----
    initial begin
        repeat (4) @(posedge clk);
        force dut.u_sync.int_enable        = 1'b1;
        force dut.u_sync.int_bypass_en     = 1'b0;
        force dut.u_sync.int_force_tlast   = 1'b0;
        force dut.u_sync.int_counter_clear = 1'b0;
        force dut.u_sync.int_frame_len     = 12'd4032;
    end

    // ---- B[k] conj-FFT ROM (hierarchical) ----
    initial $readmemh("../../../vectors/bk_conj_fft512_rom.txt",
                      dut.u_sync.u_dut.u_meyr.u_rm_dut.rom);

    // ---- shared pilot ROM (TX addressed + RX/DUT streamed) ----
    logic [31:0] plt_mem [0:NPLT-1];
    initial $readmemh("../../../golden/rx_downstream/pilot_rom.hex", plt_mem);
    always @(*) tx_pilot_tdata = plt_mem[tx_pilot_addr];
    integer plt_ptr;
    always @(*) pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!aresetn) plt_ptr <= 0;
        else if (pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---- per-mod data bits (same file order as the loop TB) ----
    logic [7:0] cbits [0:NUM_DATA*NDATA_SC*8-1];
    logic [7:0] txbit [0:NBEATS*BPC_MAX-1];
    logic [7:0] rxbit [0:NBEATS*BPC_MAX-1];
    integer fbits, c, di, b, nn;
    reg pa_ok;
    initial begin
        MOD = 1; CFO_MILLI = 250;
        pa_ok = $value$plusargs("MOD=%d", MOD);
        void'($value$plusargs("CFO_MILLI=%d", CFO_MILLI));
        if (pa_ok === 1'bx) MOD = 1;
        mod_sel = MOD[1:0];
        BPS  = 2*(MOD+1);
        eps  = CFO_MILLI / 1000.0;
        dphi = 6.283185307179586 * eps / NSC;
        case (MOD)
            0: gdir = "../../../golden/rx_downstream/qpsk";
            1: gdir = "../../../golden/rx_downstream/16qam";
            2: gdir = "../../../golden/rx_downstream/64qam";
            default: gdir = "../../../golden/rx_downstream/256qam";
        endcase

        fbits = $fopen({gdir,"/tx_data_bits_bpc8.txt"}, "r");
        if (fbits == 0) begin
            $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER -1 / 0 -> FAIL (no tx_data_bits_bpc8.txt)", MOD, CFO_MILLI);
            $display("GATE: FAIL_RX_CFO (no bits file)"); $finish;
        end
        di = 0;
        while (!$feof(fbits) && di < NUM_DATA*NDATA_SC*8) begin
            c = $fgetc(fbits);
            if (c == "0" || c == "1") begin cbits[di] = c[7:0]; di = di + 1; end
        end
        $fclose(fbits);
        for (di = 0; di < NUM_DATA*NDATA_SC*8; di = di + 1)
            data_bits_flat[di] = (cbits[di] == "1");
        for (nn = 0; nn < NBEATS; nn = nn + 1)
            for (b = 0; b < BPS; b = b + 1)
                txbit[nn*BPC_MAX + b] = cbits[nn*8 + b];
    end

    // ---- counters ----
    int in_count, sync_out_count, bit_out_count, cyc, first_bit_cyc, diag_wrap_start;
    bit frame_locked;
    integer rb2;
    initial begin
        in_count=0; sync_out_count=0; bit_out_count=0; cyc=0; first_bit_cyc=-1;
        frame_locked=0; diag_wrap_start=0;
    end

    always @(posedge clk) if (aresetn) begin
        cyc <= cyc + 1;
        if (s_axis_tvalid && s_axis_tready) in_count <= in_count + 1;
        if (dbg_sync_m_tvalid && dbg_sync_m_tready) sync_out_count <= sync_out_count + 1;
        if (m_bits_tvalid && m_bits_tready) begin
            if (first_bit_cyc < 0) first_bit_cyc = cyc;
            if (bit_out_count < NBEATS)
                for (rb2 = 0; rb2 < BPS; rb2 = rb2 + 1)
                    rxbit[bit_out_count*BPC_MAX + rb2] <= m_bits_tdata[BPS-1-rb2] ? "1" : "0";
            if (bit_out_count < 4 && $test$plusargs("DUMP"))
                $display("[DUMP] beat=%0d m_bits=0x%02x tx=%c%c%c%c", bit_out_count, m_bits_tdata,
                         txbit[bit_out_count*BPC_MAX+0], txbit[bit_out_count*BPC_MAX+1],
                         txbit[bit_out_count*BPC_MAX+2], txbit[bit_out_count*BPC_MAX+3]);
            bit_out_count <= bit_out_count + 1;
        end
        if (dut.u_sync.u_dut.dbg_frame_start_valid) frame_locked <= 1'b1;
        if (dut.u_sync.start_r) diag_wrap_start <= diag_wrap_start + 1;
    end

    // ---- build the CFO-rotated 4160 frame from the captured TX slot ----
    logic [31:0] stim_mem [0:STIM_BEATS-1];
    task automatic build_frame;
        int ii;
        real s_i, s_q, ph, r_i, r_q;
        logic signed [15:0] qi, qq;     // 16-bit packed I/Q (sign-correct)
        for (ii = 0; ii < STIM_BEATS; ii = ii + 1) begin
            if (ii >= LEAD && ii < LEAD+SLOT_LEN) begin
                s_i = $itor($signed(slot4032[ii-LEAD][15:0]));
                s_q = $itor($signed(slot4032[ii-LEAD][31:16]));
            end else begin
                s_i = 0.0; s_q = 0.0;
            end
            ph  = dphi * ii;
            r_i = s_i*$cos(ph) - s_q*$sin(ph);
            r_q = s_i*$sin(ph) + s_q*$cos(ph);
            // pack as {Q[31:16], I[15:0]} -- slice each rotated component to a
            // 16-bit signed field (the earlier {32b,32b} concat dropped Q).
            qi = $rtoi(r_i);
            qq = $rtoi(r_q);
            stim_mem[ii] = {qq, qi};
        end
    endtask

    // ---- drive S_AXIS into the sync chain ----
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

    integer i, errors, fails;
    initial begin : main
        fails = 0;
        tx_start = 1'b0;
        tx_m_ready = 1'b1;       // always accept TX during capture

        // ---- hold BOTH resets; release the TX reset early ----
        aresetn  <= 1'b0;        // DUT (sync) stays in reset (NOT armed yet)
        tx_rst_n <= 1'b0;
        repeat (40) @(posedge clk);
        tx_rst_n <= 1'b1;        // TX out of reset; sync still held
        repeat (6) @(posedge clk);

        // ---- STAGE 1 : run the TX to generate + capture the per-mod slot ----
        // (the sync chain is still in reset, so it does not free-run on idle
        //  input and mis-arm before the real frame arrives.)
        if (!$test$plusargs("NOTX")) begin
            tx_start <= 1'b1; @(posedge clk); tx_start <= 1'b0;
            begin int w; w = 0;
                while (!tx_slot_done && w < 200000) begin @(posedge clk); w = w + 1; end
            end
            if (!tx_slot_done) begin
                $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER -1 / 0 -> FAIL (TX slot capture timeout, got %0d)",
                         MOD, CFO_MILLI, tx_cap);
                $display("GATE: FAIL_RX_CFO (TX capture timeout)"); $finish;
            end
            $display("[CFO] captured TX slot : %0d samples (MOD=%0d)", tx_cap, MOD);
        end else begin
            $display("[CFO] DIAG: NOTX -> not running TX; slot from golden");
        end
        // DIAGNOSTIC : +USEGOLD=1 overrides the captured slot with the known-good
        // 16qam golden 4032 slot (sync-capable), to isolate frame-source issues.
        if ($test$plusargs("USEGOLD")) begin
            $readmemh("../../../golden/rx_downstream/tx_slot_iq_4032.hex", slot4032);
            $display("[CFO] DIAG: overrode captured slot with golden tx_slot_iq_4032.hex");
        end
        if ($test$plusargs("GOLD4160")) begin
            // load the golden 4160 frame DIRECTLY into stim_mem (bypass build_frame)
            $readmemh("../../../golden/rx_downstream/tx_slot_iq.hex", stim_mem);
            $display("[CFO] DIAG: loaded golden tx_slot_iq.hex(4160) directly into stim_mem");
        end else begin
            build_frame();
        end

        // ---- now release the DUT (sync) reset : clean rising edge -> arm ----
        repeat (4) @(posedge clk);
        aresetn <= 1'b1;
        repeat (20) @(posedge clk);   // let arming + start fire

        if (diag_wrap_start == 0) begin
            $display("[CFO] start never armed; aborting.");
            $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER -1 / 0 -> FAIL", MOD, CFO_MILLI);
            $display("GATE: FAIL_RX_CFO (start never armed)"); $finish;
        end

        // ---- STAGE 2 : drive the CFO-rotated frame into the sync chain ----
        $display("================================================================");
        $display("[CFO] MOD=%0d (BPS=%0d) EPS=%0f (%0d milli-subcarrier) : driving %0d-sample frame",
                 MOD, BPS, eps, CFO_MILLI, STIM_BEATS);
        $display("================================================================");
        drive_input(STIM_BEATS);

        begin int waited; waited = 0;
            while (bit_out_count < NBEATS && waited < DRAIN_CYCLES) begin
                @(posedge clk); waited = waited + 1;
            end
            repeat (10) @(posedge clk);
        end

        $display("[CFO] frame_locked=%0b slot_start_index=%0d frac_cfo=%0d int_cfo=0x%08x bits=%0d/%0d",
                 frame_locked,
                 dut.u_sync.u_dut.dbg_slot_start_index,
                 $signed(dut.u_sync.u_dut.dbg_frac_cfo_word),
                 dut.u_sync.u_dut.dbg_integer_cfo_word,
                 bit_out_count*BPS, NBEATS*BPS);

        if (!frame_locked) begin $display("[CFO] FAIL: sync never locked"); fails = fails + 1; end

        if (bit_out_count >= NBEATS) begin
            errors = 0;
            for (i = 0; i < NBEATS; i = i + 1)
                for (int bx = 0; bx < BPS; bx = bx + 1)
                    if (rxbit[i*BPC_MAX+bx] !== txbit[i*BPC_MAX+bx]) errors = errors + 1;
            // ---- DIAGNOSTIC : per-bit-position + per-symbol + first mismatches ----
            begin
                int pbit[0:7]; int psym[0:NUM_DATA-1]; int shown; int car, sy;
                for (int z=0;z<8;z++) pbit[z]=0;
                for (int z=0;z<NUM_DATA;z++) psym[z]=0;
                shown=0;
                for (i = 0; i < NBEATS; i = i + 1) begin
                    sy = i / NDATA_SC;
                    for (int bx = 0; bx < BPS; bx = bx + 1)
                        if (rxbit[i*BPC_MAX+bx] !== txbit[i*BPC_MAX+bx]) begin
                            pbit[bx]=pbit[bx]+1; psym[sy]=psym[sy]+1;
                            if (shown < 8) begin
                                $display("[DIAG] mismatch carrier=%0d sym=%0d bit=%0d rx=%c tx=%c",
                                         i, sy, bx, rxbit[i*BPC_MAX+bx], txbit[i*BPC_MAX+bx]);
                                shown=shown+1;
                            end
                        end
                end
                $display("[DIAG] per-bit b0=%0d b1=%0d b2=%0d b3=%0d", pbit[0],pbit[1],pbit[2],pbit[3]);
                for (int z=0;z<NUM_DATA;z++) $display("[DIAG] sym %0d err=%0d/%0d", z, psym[z], NDATA_SC*BPS);
            end
            $display("[CFO] BER = %0d / %0d", errors, NBEATS*BPS);
            $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER %0d / %0d -> %s",
                     MOD, CFO_MILLI, errors, NBEATS*BPS, (errors==0)?"PASS":"FAIL");
            if (errors != 0) fails = fails + 1;
        end else begin
            $display("[CFO] FAIL: only %0d/%0d carriers collected", bit_out_count, NBEATS);
            $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER -1 / %0d -> FAIL", MOD, CFO_MILLI, NBEATS*BPS);
            fails = fails + 1;
        end

        $display("================================================================");
        if (fails == 0) $display("GATE: PASS_RX_CFO  (sync corrected CFO, BER=0, MOD=%0d)", MOD);
        else            $display("GATE: FAIL_RX_CFO  (%0d failed checks, MOD=%0d)", fails, MOD);
        $display("================================================================");
        $finish;
    end

    initial begin
        repeat (HARD_TIMEOUT) @(posedge clk);
        $display("[CFO] HARD TIMEOUT in=%0d bits=%0d locked=%0b", in_count, bit_out_count, frame_locked);
        $display("CFO_RESULT MOD=%0d CFO_MILLI=%0d BER -1 / 0 -> FAIL", MOD, CFO_MILLI);
        $display("GATE: FAIL_RX_CFO (hard timeout)"); $finish;
    end
endmodule
`default_nettype wire
