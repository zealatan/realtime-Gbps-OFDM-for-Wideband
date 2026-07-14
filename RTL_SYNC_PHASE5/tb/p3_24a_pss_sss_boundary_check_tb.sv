`timescale 1ns/1ps
// p3_24a_pss_sss_boundary_check_tb — DOC-001 PSS/SSS Extraction Boundary Gate
//
// Verifies that pss_sss_symbol_extractor.v correctly extracts:
//   PSS = input samples[32..287]  (NSC=256 samples starting at CP_LEN=32)
//   SSS = input samples[320..575] (NSC=256 samples starting at 2*CP_LEN+NSC=320)
//
// Test method: feed FRAME_LEN samples with I[n]=n, Q[n]=1000+n (uniquely
// identifiable). PSS/SSS windows are at fixed early offsets (32..287, 320..575)
// inside the slot; the rest of the 14-symbol slot is consumed but ignored.
// Exact sample-by-sample comparison: PSS samples must be {32..287, 1032..1287}.
//
// Tests:
//   T1: Full stream, tready always asserted (no backpressure)
//   T2: Full stream, tready randomly de-asserted (backpressure stress)
//   T3: Error check — overlapping PSS/SSS windows (expects error_code=1)
//
// Gate output:  DOC_001_PSS_SSS_BOUNDARY_GATE: PASS / FAIL

module p3_24a_pss_sss_boundary_check_tb;

// ── Parameters ────────────────────────────────────────────────────────────────
parameter integer NSC        = 256;
parameter integer CP_LEN     = 32;
parameter integer FRAME_LEN  = 4032;       // 14-symbol slot (NUM_BLOCKS_PER_SLOT=14)
parameter integer IQ_WIDTH   = 16;
parameter integer IDX_WIDTH  = 12;          // 12 bits holds [0..4095] (FRAME_LEN=4032 fits)
parameter integer PSS_START  = CP_LEN;                    // 32
parameter integer SSS_START  = 2*CP_LEN + NSC;            // 320

// ── Clock / Reset ─────────────────────────────────────────────────────────────
reg aclk    = 0;
reg aresetn = 0;
always #5 aclk = ~aclk;  // 100 MHz

// ── DUT ports ─────────────────────────────────────────────────────────────────
reg                     start_r         = 0;
reg  [IDX_WIDTH-1:0]    pss_fft_start_r;
reg  [IDX_WIDTH-1:0]    sss_fft_start_r;
reg  [IDX_WIDTH-1:0]    frame_len_r;

reg                     s_tvalid = 0;
wire                    s_tready;
reg  [2*IQ_WIDTH-1:0]   s_tdata  = 0;
reg                     s_tlast  = 0;

wire                    m_tvalid;
reg                     m_tready = 1;
wire [2*IQ_WIDTH-1:0]   m_tdata;
wire                    m_tlast;
wire                    m_sym_sel;
wire [7:0]              m_sym_idx;

wire busy, done, error;
wire [3:0] error_code;

pss_sss_symbol_extractor #(
    .NSC(NSC), .CP_LEN(CP_LEN),
    .IQ_WIDTH(IQ_WIDTH), .FRAME_INDEX_WIDTH(IDX_WIDTH)
) dut (
    .aclk(aclk), .aresetn(aresetn),
    .start(start_r),
    .pss_fft_start(pss_fft_start_r),
    .sss_fft_start(sss_fft_start_r),
    .frame_len(frame_len_r),
    .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
    .s_axis_tdata(s_tdata),   .s_axis_tlast(s_tlast),
    .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
    .m_axis_tdata(m_tdata),   .m_axis_tlast(m_tlast),
    .m_symbol_sel(m_sym_sel), .m_symbol_index(m_sym_idx),
    .busy(busy), .done(done), .error(error), .error_code(error_code)
);

// ── Helpers ───────────────────────────────────────────────────────────────────
integer total_pass = 0;
integer total_fail = 0;
integer test_id    = 0;

task check_int;
    input [63:0] got;
    input [63:0] exp;
    input [127:0] label;
    begin
        if (got === exp) begin
            total_pass = total_pass + 1;
        end else begin
            total_fail = total_fail + 1;
            $display("  FAIL [%s]: got=%0d  exp=%0d", label, got, exp);
        end
    end
endtask

// ── Reset sequence ────────────────────────────────────────────────────────────
task do_reset;
    begin
        aresetn = 0; start_r = 0; s_tvalid = 0;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1;
        repeat(2) @(posedge aclk);
    end
endtask

// ── Feed one frame, collect PSS+SSS ──────────────────────────────────────────
// backpressure_en: 1=random tready de-assert, 0=always ready
integer pss_out_cnt;
integer sss_out_cnt;
integer pss_errors;
integer sss_errors;

reg [2*IQ_WIDTH-1:0] pss_samples [0:NSC-1];
reg [2*IQ_WIDTH-1:0] sss_samples [0:NSC-1];
reg pss_tlast_seen;
reg sss_tlast_seen;
reg pss_sel_ok;
reg sss_sel_ok;
reg pss_idx_ok;
reg sss_idx_ok;

task feed_frame_and_collect;
    input backpressure_en;
    input [IDX_WIDTH-1:0] p_start;
    input [IDX_WIDTH-1:0] s_start;
    input [IDX_WIDTH-1:0] f_len;
    output got_error;
    output [3:0] got_error_code;
    integer n;
    integer iq_i, iq_q;
    reg [2*IQ_WIDTH-1:0] tdata_out;
    begin
        pss_out_cnt = 0; sss_out_cnt = 0;
        pss_errors = 0;  sss_errors = 0;
        pss_tlast_seen = 0; sss_tlast_seen = 0;
        pss_sel_ok = 1; sss_sel_ok = 1;
        pss_idx_ok = 1; sss_idx_ok = 1;
        got_error = 0; got_error_code = 0;

        pss_fft_start_r = p_start;
        sss_fft_start_r = s_start;
        frame_len_r     = f_len;

        // Pulse start
        @(posedge aclk); #1; start_r = 1;
        @(posedge aclk); #1; start_r = 0;

        // Wait for busy
        repeat(10) @(posedge aclk);

        // Fork: feed input stream while collecting output
        fork
            // ── Input driver ──────────────────────────────────────────────
            begin : input_driver
                for (n = 0; n < f_len; n = n+1) begin
                    iq_i = n;
                    iq_q = 1000 + n;
                    s_tdata  = {iq_q[IQ_WIDTH-1:0], iq_i[IQ_WIDTH-1:0]};
                    s_tlast  = (n == f_len-1) ? 1'b1 : 1'b0;
                    s_tvalid = 1'b1;
                    @(posedge aclk);
                    while (!s_tready) @(posedge aclk);
                    #1;
                end
                s_tvalid = 0; s_tlast = 0; s_tdata = 0;
            end

            // ── Output collector ──────────────────────────────────────────
            begin : output_collector
                while ((pss_out_cnt < NSC || sss_out_cnt < NSC) && !got_error) begin
                    // Drive tready after previous posedge so DUT sees stable value
                    // at the NEXT posedge. Capture at posedge (pre-NBA) so we read
                    // hold_valid before the m_fire NBA clears it to 0.
                    if (backpressure_en)
                        #1 m_tready = ($random % 3 != 0);  // 2/3 ready
                    else
                        #1 m_tready = 1;
                    @(posedge aclk);  // pre-NBA: hold_valid still 1 if valid

                    if (m_tvalid && m_tready) begin
                        tdata_out = m_tdata;
                        if (!m_sym_sel) begin
                            // PSS sample
                            if (pss_out_cnt < NSC) begin
                                pss_samples[pss_out_cnt] = tdata_out;
                                if (m_sym_sel !== 1'b0) pss_sel_ok = 0;
                                if (m_sym_idx !== pss_out_cnt[7:0]) begin
                                    pss_idx_ok = 0;
                                    $display("  PSS idx mismatch: got=%0d exp=%0d", m_sym_idx, pss_out_cnt);
                                end
                                if (m_tlast && pss_out_cnt != NSC-1)
                                    $display("  PSS early tlast at cnt=%0d", pss_out_cnt);
                                if (m_tlast && pss_out_cnt == NSC-1)
                                    pss_tlast_seen = 1;
                                pss_out_cnt = pss_out_cnt + 1;
                            end
                        end else begin
                            // SSS sample
                            if (sss_out_cnt < NSC) begin
                                sss_samples[sss_out_cnt] = tdata_out;
                                if (m_sym_sel !== 1'b1) sss_sel_ok = 0;
                                if (m_sym_idx !== sss_out_cnt[7:0]) begin
                                    sss_idx_ok = 0;
                                    $display("  SSS idx mismatch: got=%0d exp=%0d", m_sym_idx, sss_out_cnt);
                                end
                                if (m_tlast && sss_out_cnt != NSC-1)
                                    $display("  SSS early tlast at cnt=%0d", sss_out_cnt);
                                if (m_tlast && sss_out_cnt == NSC-1)
                                    sss_tlast_seen = 1;
                                sss_out_cnt = sss_out_cnt + 1;
                            end
                        end
                    end
                    if (error) begin
                        got_error = 1;
                        got_error_code = error_code;
                        disable output_collector;
                    end
                    if ((pss_out_cnt >= NSC) && (sss_out_cnt >= NSC))
                        disable output_collector;
                end
                m_tready = 1;
            end
        join

        // Extra cycles to let done propagate
        repeat(10) @(posedge aclk);
    end
endtask

// ── Verify collected samples ──────────────────────────────────────────────────
task verify_samples;
    input [IDX_WIDTH-1:0] p_start;
    input [IDX_WIDTH-1:0] s_start;
    integer k;
    reg [IQ_WIDTH-1:0] exp_i, exp_q;
    reg [IQ_WIDTH-1:0] got_i, got_q;
    integer pss_mismatch, sss_mismatch;
    begin
        pss_mismatch = 0; sss_mismatch = 0;

        for (k = 0; k < NSC; k = k+1) begin
            exp_i = p_start + k;
            exp_q = 1000 + p_start + k;
            got_i = pss_samples[k][IQ_WIDTH-1:0];
            got_q = pss_samples[k][2*IQ_WIDTH-1:IQ_WIDTH];
            if (got_i !== exp_i || got_q !== exp_q) begin
                pss_mismatch = pss_mismatch + 1;
                if (pss_mismatch <= 3)
                    $display("  PSS[%0d] got I=%0d Q=%0d  exp I=%0d Q=%0d",
                             k, got_i, got_q, exp_i, exp_q);
            end
        end

        for (k = 0; k < NSC; k = k+1) begin
            exp_i = s_start + k;
            exp_q = 1000 + s_start + k;
            got_i = sss_samples[k][IQ_WIDTH-1:0];
            got_q = sss_samples[k][2*IQ_WIDTH-1:IQ_WIDTH];
            if (got_i !== exp_i || got_q !== exp_q) begin
                sss_mismatch = sss_mismatch + 1;
                if (sss_mismatch <= 3)
                    $display("  SSS[%0d] got I=%0d Q=%0d  exp I=%0d Q=%0d",
                             k, got_i, got_q, exp_i, exp_q);
            end
        end

        if (pss_mismatch == 0)
            $display("  PASS PSS sample values (%0d samples correct)", NSC);
        else begin
            $display("  FAIL PSS sample values: %0d mismatches", pss_mismatch);
            total_fail = total_fail + 1;
        end

        if (sss_mismatch == 0)
            $display("  PASS SSS sample values (%0d samples correct)", NSC);
        else begin
            $display("  FAIL SSS sample values: %0d mismatches", sss_mismatch);
            total_fail = total_fail + 1;
        end

        if (pss_mismatch == 0 && sss_mismatch == 0)
            total_pass = total_pass + 2;
    end
endtask

// ── Main test sequence ────────────────────────────────────────────────────────
reg got_error_r;
reg [3:0] got_ec_r;

initial begin
    $display("============================================================");
    $display(" DOC-001 PSS/SSS Extraction Boundary Gate");
    $display("   NSC=%0d  CP_LEN=%0d  FRAME_LEN=%0d", NSC, CP_LEN, FRAME_LEN);
    $display("   PSS window: [%0d..%0d]  SSS window: [%0d..%0d]",
             PSS_START, PSS_START+NSC-1, SSS_START, SSS_START+NSC-1);
    $display("============================================================");

    // ─────────────────────────────────────────────────────────────
    // T1: No backpressure — standard pass
    // ─────────────────────────────────────────────────────────────
    $display("\n[T1] Full frame, tready=1 (no backpressure)");
    do_reset;
    m_tready = 1;
    feed_frame_and_collect(0, PSS_START, SSS_START, FRAME_LEN, got_error_r, got_ec_r);

    if (got_error_r) begin
        $display("  FAIL T1: DUT reported error_code=%0d", got_ec_r);
        total_fail = total_fail + 1;
    end else begin
        // Count
        check_int(pss_out_cnt, NSC, "T1 PSS count");
        check_int(sss_out_cnt, NSC, "T1 SSS count");
        check_int(pss_tlast_seen, 1, "T1 PSS tlast");
        check_int(sss_tlast_seen, 1, "T1 SSS tlast");
        check_int(pss_sel_ok, 1, "T1 PSS m_sym_sel=0");
        check_int(sss_sel_ok, 1, "T1 SSS m_sym_sel=1");
        check_int(pss_idx_ok, 1, "T1 PSS m_sym_index sequence");
        check_int(sss_idx_ok, 1, "T1 SSS m_sym_index sequence");
        verify_samples(PSS_START, SSS_START);
    end

    // ─────────────────────────────────────────────────────────────
    // T2: Random backpressure
    // ─────────────────────────────────────────────────────────────
    $display("\n[T2] Full frame, random tready (backpressure stress)");
    do_reset;
    feed_frame_and_collect(1, PSS_START, SSS_START, FRAME_LEN, got_error_r, got_ec_r);
    m_tready = 1;

    if (got_error_r) begin
        $display("  FAIL T2: DUT reported error_code=%0d", got_ec_r);
        total_fail = total_fail + 1;
    end else begin
        check_int(pss_out_cnt, NSC, "T2 PSS count under backpressure");
        check_int(sss_out_cnt, NSC, "T2 SSS count under backpressure");
        check_int(pss_tlast_seen, 1, "T2 PSS tlast");
        check_int(sss_tlast_seen, 1, "T2 SSS tlast");
        verify_samples(PSS_START, SSS_START);
    end

    // ─────────────────────────────────────────────────────────────
    // T3: Error injection — overlapping windows
    // ─────────────────────────────────────────────────────────────
    $display("\n[T3] Overlapping PSS/SSS windows — expect error_code=1");
    do_reset;
    pss_fft_start_r = 32;
    sss_fft_start_r = 32;  // overlapping
    frame_len_r     = FRAME_LEN;
    @(posedge aclk); #1; start_r = 1;
    @(posedge aclk); #1; start_r = 0;
    repeat(5) @(posedge aclk);
    if (error && error_code == 4'd1) begin
        $display("  PASS T3: error_code=1 on overlapping windows");
        total_pass = total_pass + 1;
    end else begin
        $display("  FAIL T3: expected error_code=1, got error=%0d error_code=%0d",
                 error, error_code);
        total_fail = total_fail + 1;
    end

    // ─────────────────────────────────────────────────────────────
    // Gate
    // ─────────────────────────────────────────────────────────────
    $display("\n============================================================");
    $display("  PASS count : %0d", total_pass);
    $display("  FAIL count : %0d", total_fail);
    $display("============================================================");
    if (total_fail == 0) begin
        $display("DOC_001_PSS_SSS_BOUNDARY_GATE: PASS");
    end else begin
        $display("DOC_001_PSS_SSS_BOUNDARY_GATE: FAIL (%0d check(s) failed)", total_fail);
    end
    $display("============================================================");
    $finish;
end

// Timeout watchdog — scaled 7x for the 4032-beat 14-symbol slot
initial begin
    #35_000_000;
    $display("DOC_001_PSS_SSS_BOUNDARY_GATE: FAIL (TIMEOUT)");
    $finish;
end

endmodule
