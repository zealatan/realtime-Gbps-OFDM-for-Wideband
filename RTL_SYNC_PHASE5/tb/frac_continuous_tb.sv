`timescale 1ns/1ps
// Isolate the 2x-processing artifact: drive 3 frames back-to-back into the
// (ping-pong-integrated) frac corrector, re-arm start per done like the wrapper,
// count done pulses. Expect 3 (one per input frame), NOT 6.
module frac_continuous_tb;
    localparam integer NSC=256, CP_LEN=32, BUF_AW=12, INDEX_WIDTH=9, PHASE_WIDTH=16, ENERGY_WIDTH=40;
    localparam integer CFG_THRESHOLD=40000, CFG_WINDOW=25, CFG_HITCOUNT=10;
    localparam integer NSAMP=4160, NFRAMES=10;

    reg aclk=0, aresetn=0; always #5 aclk=~aclk;
    reg  [31:0] s_tdata; reg s_tvalid, s_tlast; wire s_tready;
    reg  start; wire done, busy, frame_error; wire [3:0] error_code;
    reg  [ENERGY_WIDTH-1:0] threshold_in; reg [6:0] window_len_in; reg [3:0] hit_count_in;
    wire [BUF_AW-1:0] frame_index; wire frame_found;
    wire [INDEX_WIDTH-1:0] peak_lag; wire [31:0] peak_metric;
    wire [PHASE_WIDTH-1:0] frac_phase; wire frac_phase_valid;
    wire [31:0] m_tdata; wire m_tvalid; reg m_tready; wire m_tlast;

    frac_cfo_frame_corrector_top #(
        .NSC(NSC), .CP_LEN(CP_LEN), .BUF_AW(BUF_AW),
        .OUTPUT_SAMPLES(4032),   // match the board full-slot output
        .INDEX_WIDTH(INDEX_WIDTH), .PHASE_WIDTH(PHASE_WIDTH), .ENERGY_WIDTH(ENERGY_WIDTH),
        .WINDOW_LEN(CFG_WINDOW), .HIT_COUNT(CFG_HITCOUNT), .THRESHOLD(CFG_THRESHOLD)
    ) dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axis_tdata(s_tdata), .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready), .s_axis_tlast(s_tlast),
        .start(start), .done(done), .busy(busy), .frame_error(frame_error), .error_code(error_code),
        .threshold_in(threshold_in), .window_len_in(window_len_in), .hit_count_in(hit_count_in),
        .frame_index(frame_index), .frame_found(frame_found),
        .peak_lag(peak_lag), .peak_metric(peak_metric),
        .frac_phase(frac_phase), .frac_phase_valid(frac_phase_valid),
        .m_axis_tdata(m_tdata), .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready), .m_axis_tlast(m_tlast)
    );

    // [BP] m_axis back-pressure generator (repro NIGHTLY's drop): ready 3/4 cycles
    reg [3:0] bp_cnt=0;
    always @(posedge aclk) begin
        if (!aresetn) begin m_tready <= 1'b1; bp_cnt <= 0; end
        else begin bp_cnt <= bp_cnt + 1; m_tready <= (bp_cnt[1:0] != 2'b00); end
    end

    reg [31:0] stim [0:NSAMP-1];
    integer done_cnt=0, ff_cnt=0, ferr_cnt=0, mbeats=0;
    integer slot_beats [0:11];   // m_axis beats per output slot (detect mout<4032)
    integer meas_cyc=0, in_acc=0; reg measuring=0;
    integer st_cyc [0:6];  // per-FSM-state cycle count (S_IDLE..S_DONE)
    integer si;
    initial begin for (si=0; si<7; si=si+1) st_cyc[si]=0; for (si=0; si<12; si=si+1) slot_beats[si]=0; end

    // [ISOLATE] per-slot output checksum — same input each slot => identical output.
    // If slot1 != slot0, the frac corrector (H1b) corrupts continuous output.
    integer slot_idx=0, slot_beat=0; integer slot_sum [0:11];
    initial for (si=0; si<12; si=si+1) slot_sum[si]=0;
    always @(posedge aclk) if (aresetn) begin
        if (m_tvalid && m_tready) begin
            if (slot_idx < 12) begin
                slot_sum[slot_idx]   = slot_sum[slot_idx] + $signed(m_tdata[15:0]) + $signed(m_tdata[31:16]);
                slot_beats[slot_idx] = slot_beats[slot_idx] + 1;
            end
            slot_beat = slot_beat + 1;
            if (m_tlast) begin slot_idx = slot_idx + 1; slot_beat = 0; end
        end
    end

    // [NCODBG] frac_phase estimate loaded per slot (same input => must match)
    reg [2:0] last_st;
    always @(posedge aclk) if (aresetn) begin
        last_st <= dut.state;
        if (dut.state==5 && last_st!=5)
            $display("[NCO] slot~%0d frac_phase_r=%0d  autocorr_I=%0d autocorr_Q=%0d  peak_lag=%0d",
                     slot_idx, $signed(dut.frac_phase_r),
                     $signed(dut.u_tfc.peak_corr_i_r), $signed(dut.u_tfc.peak_corr_q_r), dut.peak_lag_r);
    end

    // [RDDBG] compare slot0 vs slot2 readout (same buffer A, same input)
    integer dbg0=0, dbg2=0;
    always @(posedge aclk) if (aresetn && dut.state==5 && dut.buf_rd_en) begin
        if (slot_idx==0 && dbg0<6) begin $display("[RD0] addr=%0d data=%08x", dut.buf_rd_addr, dut.buf_rd_data); dbg0=dbg0+1; end
        if (slot_idx==2 && dbg2<6) begin $display("[RD2] addr=%0d data=%08x", dut.buf_rd_addr, dut.buf_rd_data); dbg2=dbg2+1; end
    end
    // [ACORR] autocorr stream first valid outputs: slot0 vs slot1 (shift vs value?)
    integer a0=0, a1=0;
    always @(posedge aclk) if (aresetn && dut.state==3 && dut.u_tfc.u_tst.full_win_valid) begin
        if (slot_idx==0 && a0<8) begin $display("[AC0] #%0d I=%0d Q=%0d", a0, $signed(dut.u_tfc.u_tst.sca_p_i), $signed(dut.u_tfc.u_tst.sca_p_q)); a0=a0+1; end
        if (slot_idx==1 && a1<8) begin $display("[AC1] #%0d I=%0d Q=%0d", a1, $signed(dut.u_tfc.u_tst.sca_p_i), $signed(dut.u_tfc.u_tst.sca_p_q)); a1=a1+1; end
    end

    // [TSTDBG] tst read CHECKSUM during S_TIMING_CFO (state 3) per slot — all reads
    integer tsum [0:11]; integer tcnt [0:11];
    initial for (si=0; si<12; si=si+1) begin tsum[si]=0; tcnt[si]=0; end
    always @(posedge aclk) if (aresetn && dut.state==3 && dut.buf_rd_en && slot_idx<12) begin
        tsum[slot_idx] = tsum[slot_idx] + $signed(dut.buf_rd_data[15:0]) + $signed(dut.buf_rd_data[31:16]);
        tcnt[slot_idx] = tcnt[slot_idx] + 1;
    end

    always @(posedge aclk) if (aresetn) begin
        if (done)        done_cnt = done_cnt + 1;
        if (frame_error) ferr_cnt = ferr_cnt + 1;
        if (m_tvalid && m_tready) mbeats = mbeats + 1;
        if (measuring) begin
            meas_cyc = meas_cyc + 1;
            if (s_tvalid && s_tready) in_acc = in_acc + 1;  // input duty numerator
            st_cyc[dut.state] = st_cyc[dut.state] + 1;       // where the cycles go
        end
        if (done && done_cnt == NFRAMES) measuring = 1'b0;  // stop at last frac_done
    end

    // wrapper-style start re-arm: armed at reset, re-arm on done, fire when idle
    reg armed;
    always @(posedge aclk) begin
        if (!aresetn) begin start<=1'b0; armed<=1'b1; end
        else begin
            start <= 1'b0;
            if (done) armed <= 1'b1;
            if (armed && !busy) begin start <= 1'b1; armed <= 1'b0; end
        end
    end

    // canonical AXI-S producer: NFRAMES frames continuous, tlast per frame
    integer f, i;
    initial begin
        $readmemh("vectors/shared_bitacc/tc0000/input.hex", stim);
        s_tdata=0; s_tvalid=0; s_tlast=0;
        threshold_in=CFG_THRESHOLD; window_len_in=CFG_WINDOW; hit_count_in=CFG_HITCOUNT;
        repeat(6) @(posedge aclk); aresetn=1'b1; repeat(3) @(posedge aclk);
        measuring=1'b1;          // start duty measurement
        f=0; i=0;
        s_tdata<=stim[i]; s_tvalid<=1'b1; s_tlast<=(i==NSAMP-1);
        while (f < NFRAMES) begin
            @(posedge aclk);
            if (s_tready) begin
                i=i+1; if (i==NSAMP) begin i=0; f=f+1; end
                if (f<NFRAMES) begin s_tdata<=stim[i]; s_tlast<=(i==NSAMP-1); end
                else begin s_tvalid<=1'b0; s_tlast<=1'b0; end
            end
        end
        // drain
        repeat(20000) @(posedge aclk);
        $display("==== frac_continuous_tb ====");
        $display("  NFRAMES driven = %0d", NFRAMES);
        $display("  done_cnt   = %0d (expect %0d)", done_cnt, NFRAMES);
        $display("  frame_err  = %0d (expect 0)", ferr_cnt);
        $display("  m_axis beats = %0d", mbeats);
        $display("  INPUT DUTY = %0d accepted / %0d cycles = %0d%%",
                 in_acc, meas_cyc, (meas_cyc>0)?(in_acc*100/meas_cyc):0);
        $display("  per-state cycles (over %0d frames): IDLE=%0d FILL/WAITBUF=%0d FRAME_DET=%0d TIMING_CFO=%0d LOAD_NCO=%0d CORRECT=%0d DONE=%0d",
                 NFRAMES, st_cyc[0], st_cyc[1], st_cyc[2], st_cyc[3], st_cyc[4], st_cyc[5], st_cyc[6]);
        $display("  [BEATS] m_axis beats/slot (expect ALL=4032 under back-pressure): s0=%0d s1=%0d s2=%0d s3=%0d s4=%0d s5=%0d",
                 slot_beats[0],slot_beats[1],slot_beats[2],slot_beats[3],slot_beats[4],slot_beats[5]);
        $display("  [TSTSUM] tst read checksum/count per slot: s0=%0d/%0d s1=%0d/%0d s2=%0d/%0d",
                 tsum[0],tcnt[0], tsum[1],tcnt[1], tsum[2],tcnt[2]);
        $display("  [ISOLATE] per-slot output checksums (should ALL be equal — same input):");
        $display("    slot0=%0d slot1=%0d slot2=%0d slot3=%0d slot4=%0d",
                 slot_sum[0], slot_sum[1], slot_sum[2], slot_sum[3], slot_sum[4]);
        if (slot_sum[0]==slot_sum[1] && slot_sum[1]==slot_sum[2])
             $display("    => SLOTS IDENTICAL: frac corrector output OK (bug is downstream/full-chain)");
        else $display("    => SLOTS DIFFER: H1b frac corrector corrupts continuous output (THIS is the bug)");
        if (done_cnt==NFRAMES && ferr_cnt==0) $display("RESULT: PASS");
        else $display("RESULT: FAIL (done_cnt=%0d expect %0d)", done_cnt, NFRAMES);
        $finish;
    end
    initial begin #5000000; $display("RESULT: FAIL (timeout) done_cnt=%0d", done_cnt); $finish; end
endmodule
