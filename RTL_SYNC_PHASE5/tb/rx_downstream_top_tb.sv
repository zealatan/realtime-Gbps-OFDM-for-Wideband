// =====================================================================
// rx_downstream_top_tb.sv
// ---------------------------------------------------------------------
// FULL-CHAIN self-checking TB for rx_downstream_top.
//
//   * Drives golden/rx_downstream/tx_slot_iq_4032.hex (4032 {Q,I} Q15
//     samples, beat0 = PSS CP start) into the top's s_axis, 1 sample/clk,
//     with pseudo-random s_valid gaps AND m_ready stalls so AXI-Stream
//     tready is exercised end to end.
//   * Feeds golden/rx_downstream/pilot_rom.hex (12*32 QPSK pilots) on the
//     pilot ROM stream, advancing on pilot_tready (one word per pilot bin).
//   * Collects the 4-bit/data-carrier demod output, packs to a bit string
//     in the reference order ([b0 b1 b2 b3] per carrier, dataIndx order),
//     and compares against golden/rx_downstream/tx_bits.txt.
//
//   PASS  <=>  all 10608 bits collected AND BER == 0.
//   Gate line: "RESULT: PASS" / "RESULT: FAIL"  +  "RXDS_FULLCHAIN: PASS|FAIL"
//
// Also reports the measured first-bit latency and total run cycles.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_downstream_top_tb;

    localparam integer NSC      = 256;
    localparam integer CP_LEN   = 32;
    localparam integer NUM_SYN  = 2;
    localparam integer NUM_DATA = 12;
    localparam integer NUM_PLT  = 32;
    localparam integer NDATA_SC = 221;
    localparam integer SLOT_LEN = (NUM_SYN + NUM_DATA)*(NSC+CP_LEN); // 4032
    localparam integer NBEATS   = NUM_DATA * NDATA_SC;               // 2652
    localparam integer NBITS    = NBEATS * 4;                        // 10608
    localparam integer NPLT     = NUM_DATA * NUM_PLT;                // 384

    // Golden files are loaded with LITERAL relative paths. The runner makes
    // them resolve by symlinking the repo `golden` tree into the sim cwd
    // (same convention as the per-module rx_fft_frontend gate). NOTE: a
    // SystemVerilog `string`-typed filename passed to $readmemh is NOT
    // reliably honored by xsim (it silently fails to load -> all-X memory),
    // so we use plain string literals here.

    // ---- clock / reset ----
    reg clk = 1'b0;
    always #5 clk = ~clk;            // 100 MHz functional clock
    reg rst_n = 1'b0;

    // ---- DUT wiring ----
    reg          s_valid;
    wire         s_ready;
    reg  [31:0]  s_tdata;

    reg  [31:0]  pilot_tdata;
    wire         pilot_tready;

    wire         m_valid;
    reg          m_ready;
    wire [3:0]   m_bits;
    wire         m_last, m_user;

    rx_downstream_top #(
        .DW(16), .NSC(256), .CP_LEN(32),
        .NUM_SYN(2), .NUM_DATA(12), .NUM_PILOTS(32), .NDATA_SC(221),
        .TUSERW(16)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready), .s_tdata(s_tdata),
        .pilot_tdata(pilot_tdata), .pilot_tready(pilot_tready),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_bits(m_bits), .m_last(m_last), .m_user(m_user)
    );

    // ---- golden storage ----
    reg [31:0] slot_mem [0:SLOT_LEN-1];
    reg [31:0] plt_mem  [0:NPLT-1];
    reg [7:0]  txbit    [0:NBITS-1];     // '0'/'1' ASCII per data bit
    reg [7:0]  rxbit    [0:NBITS-1];
    integer    rx_cnt;

    integer i, fd, ch;

    initial begin
        $readmemh("golden/rx_downstream/tx_slot_iq_4032.hex", slot_mem);
        $readmemh("golden/rx_downstream/pilot_rom.hex",       plt_mem);
`ifdef RXDS_DIAG
        #1 $display("   DIAG slot[0]=%08h slot[608]=%08h plt[0]=%08h",
                    slot_mem[0], slot_mem[608], plt_mem[0]);
`endif
    end

    // load tx_bits.txt char-by-char (keep only '0'/'1')
    initial begin
        fd = $fopen("golden/rx_downstream/tx_bits.txt", "r");
        if (fd == 0) begin $display("FATAL: cannot open tx_bits.txt"); $finish; end
        i  = 0;
        ch = $fgetc(fd);
        while (ch != -1 && i < NBITS) begin
            if (ch == "0" || ch == "1") begin txbit[i] = ch[7:0]; i = i + 1; end
            ch = $fgetc(fd);
        end
        $fclose(fd);
        if (i != NBITS) $display("WARN: read %0d golden bits, expected %0d", i, NBITS);
    end

    // ---------------------------------------------------------------
    // pilot ROM feeder: present plt_mem[plt_ptr]; advance on pilot_tready
    // (the top pulls one word per captured pilot bin).
    // ---------------------------------------------------------------
    integer plt_ptr;
    always @(*) pilot_tdata = plt_mem[plt_ptr];
    always @(posedge clk) begin
        if (!rst_n) plt_ptr <= 0;
        else if (pilot_tready && plt_ptr < NPLT-1) plt_ptr <= plt_ptr + 1;
    end

    // ---------------------------------------------------------------
    // stimulus: stream the 4032-sample slot with random valid gaps
    // ---------------------------------------------------------------
    integer in_idx;
    integer vseed = 32'hBEEF1234;
    initial begin
        s_valid = 1'b0; s_tdata = 32'd0;
        m_ready = 1'b0;
        rst_n   = 1'b0;
        repeat (8) @(posedge clk);
        rst_n   = 1'b1;
        @(posedge clk);

        in_idx = 0;
        while (in_idx < SLOT_LEN) begin
            if (($random(vseed) % 5) == 0) begin
                s_valid <= 1'b0;
                @(posedge clk);
            end else begin
                s_valid <= 1'b1;
                s_tdata <= slot_mem[in_idx];
                @(posedge clk);
                if (s_valid && s_ready) in_idx = in_idx + 1;
            end
        end
        s_valid <= 1'b0;
    end

    // ---------------------------------------------------------------
    // m_ready back-pressure (pseudo-random ~75% ready)
    // ---------------------------------------------------------------
    integer rseed = 32'h0FACADE;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(rseed) % 4) != 0;
    end

`ifdef RXDS_DIAG
    // ---- DIAG taps: capture FX/H/EQ streams to files, plus CE framing probes
    integer fH, fEQ, fFX, h_beats, eq_beats, fx_beats;
    integer ce_inbin, ce_last_cnt, ipin_cnt;
    initial begin
        h_beats=0; eq_beats=0; fx_beats=0; ce_last_cnt=0; ipin_cnt=0;
        fH=$fopen("diag_hest.txt","w"); fEQ=$fopen("diag_eqout.txt","w");
        fFX=$fopen("diag_fx.txt","w");
    end
    always @(posedge clk) begin
        if (rst_n && dut.fx_valid && dut.fx_ready) begin
            $fdisplay(fFX, "%0d last=%b %08h", fx_beats, dut.fx_last, dut.fx_tdata);
            if (dut.fx_last) ce_last_cnt = ce_last_cnt+1;
            fx_beats=fx_beats+1;
        end
        // raw IP output tap (inside the front-end)
        if (rst_n && dut.u_fft.fft_dout_tvalid && dut.u_fft.fft_dout_tready)
            $fdisplay(fFX, "  IPraw tuser=%02h data=%08h last=%b",
                      dut.u_fft.fft_dout_tuser, dut.u_fft.fft_dout_tdata, dut.u_fft.fft_dout_tlast);
        // raw IP INPUT tap (first 8 body samples) + config state
        if (rst_n && dut.u_fft.fft_din_tvalid && dut.u_fft.fft_din_tready && ipin_cnt < 8) begin
            $fdisplay(fFX, "  IPin#%0d cfg_done=%b cfg_rdy=%b data=%08h last=%b",
                      ipin_cnt, dut.u_fft.cfg_done, dut.u_fft.cfg_tready, dut.u_fft.fft_din_tdata, dut.u_fft.fft_din_tlast);
            ipin_cnt=ipin_cnt+1;
        end
        if (rst_n && dut.h_tvalid && dut.h_tready) begin
            $fdisplay(fH, "%0d %08h", h_beats, dut.h_tdata); h_beats=h_beats+1;
        end
        if (rst_n && dut.eq_m_valid && dut.eq_m_ready) begin
            $fdisplay(fEQ, "%0d bin=%0d %08h", eq_beats, dut.eq_bin, dut.eq_m_tdata); eq_beats=eq_beats+1;
        end
    end
    // report CE-input framing: total FX beats + how many fx_last pulses (should be 12)
    final $display("   DIAG fx_beats=%0d fx_last_pulses=%0d ce_in_busy0=%b busy1=%b",
                   fx_beats, ce_last_cnt, dut.u_ce.eng_busy[0], dut.u_ce.eng_busy[1]);
`endif

    // ---------------------------------------------------------------
    // collect output bits (b0 first, then b1,b2,b3)
    // m_bits = {b0,b1,b2,b3} = bits[3],bits[2],bits[1],bits[0]
    // ---------------------------------------------------------------
    integer cyc;
    integer first_bit_cyc;
    initial begin rx_cnt = 0; cyc = 0; first_bit_cyc = -1; end
    always @(posedge clk) begin
        if (rst_n) cyc <= cyc + 1;
        if (rst_n && m_valid && m_ready) begin
            if (first_bit_cyc < 0) first_bit_cyc = cyc;
            if (rx_cnt < NBEATS) begin
                rxbit[rx_cnt*4 + 0] <= (m_bits[3]) ? "1" : "0"; // b0
                rxbit[rx_cnt*4 + 1] <= (m_bits[2]) ? "1" : "0"; // b1
                rxbit[rx_cnt*4 + 2] <= (m_bits[1]) ? "1" : "0"; // b2
                rxbit[rx_cnt*4 + 3] <= (m_bits[0]) ? "1" : "0"; // b3
            end
            rx_cnt <= rx_cnt + 1;
        end
    end

    // ---------------------------------------------------------------
    // finish + compare
    // ---------------------------------------------------------------
    integer errors, timeout;
    initial begin
        timeout = 0;
        wait (rst_n);
        while (rx_cnt < NBEATS && timeout < 2_000_000) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);

        if (rx_cnt != NBEATS) begin
            $display("FATAL: collected %0d beats, expected %0d (timeout=%0d)",
                     rx_cnt, NBEATS, timeout);
            $display("RXDS_FULLCHAIN: FAIL");
            $display("RESULT: FAIL");
            $finish;
        end

        errors = 0;
        for (i = 0; i < NBITS; i = i + 1)
            if (rxbit[i] !== txbit[i]) errors = errors + 1;

`ifdef RXDS_DIAG
        // per-symbol error count + per-bit-position error count
        begin : diag
            integer s, c, b, se, bitpos, pe [0:3];
            for (b=0;b<4;b=b+1) pe[b]=0;
            for (s=0;s<NUM_DATA;s=s+1) begin
                se = 0;
                for (c=0;c<NDATA_SC;c=c+1)
                    for (b=0;b<4;b=b+1) begin
                        bitpos = (s*NDATA_SC + c)*4 + b;
                        if (rxbit[bitpos] !== txbit[bitpos]) begin
                            se = se+1; pe[b]=pe[b]+1;
                        end
                    end
                $display("   DIAG sym %0d : %0d/%0d bit errors", s, se, NDATA_SC*4);
            end
            $display("   DIAG per-bit-pos errors: b0=%0d b1=%0d b2=%0d b3=%0d", pe[0],pe[1],pe[2],pe[3]);
            // dump first 6 carriers of symbol 0: got vs golden (4 bits each)
            for (c=0;c<6;c=c+1) begin
                $display("   DIAG sym0 carrier %0d got=%c%c%c%c gold=%c%c%c%c", c,
                  rxbit[c*4],rxbit[c*4+1],rxbit[c*4+2],rxbit[c*4+3],
                  txbit[c*4],txbit[c*4+1],txbit[c*4+2],txbit[c*4+3]);
            end
        end
`endif

        $display("==================================================");
        $display(" rx_downstream_top FULL-CHAIN self-check");
        $display("   data carriers   = %0d (exp %0d)", rx_cnt, NBEATS);
        $display("   total bits      = %0d", NBITS);
        $display("   bit errors      = %0d", errors);
        $display("   BER             = %0d / %0d", errors, NBITS);
        $display("   first-bit cycle = %0d", first_bit_cyc);
        $display("   total run cycle = %0d", cyc);
        if (rx_cnt == NBEATS && errors == 0) begin
            $display("RXDS_FULLCHAIN: PASS  (BER = 0, matches golden tx_bits.txt)");
            $display("RESULT: PASS");
        end else begin
            $display("RXDS_FULLCHAIN: FAIL  (BER != 0)");
            $display("RESULT: FAIL");
        end
        $display("==================================================");
        $finish;
    end

    // global watchdog
    initial begin
        #50_000_000;
        $display("FATAL: global timeout");
        $display("RXDS_FULLCHAIN: FAIL");
        $display("RESULT: FAIL");
        $finish;
    end

endmodule

`default_nettype wire
