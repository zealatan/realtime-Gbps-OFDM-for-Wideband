`timescale 1ns/1ps

// Testbench for pss_sss_symbol_extractor — Step 36C
// 14 deterministic test groups (T1-T14).
// Test data: I = frame_index[15:0], Q = ~frame_index[15:0]
//
// Sampling rule: both s_fire and m_fire are determined PRE-clock (between
// posedges) because m_axis_tvalid and s_axis_tready are combinatorial wires
// from hold_valid that change AT the posedge NBA update.

module pss_sss_symbol_extractor_tb;

    localparam integer NSC               = 256;
    localparam integer CP_LEN            = 32;
    localparam integer IQ_WIDTH          = 16;
    localparam integer FRAME_INDEX_WIDTH = 12;
    localparam integer DATA_W            = 2*IQ_WIDTH;
    localparam real    CLK_PERIOD        = 10.0;

    localparam integer FRAME_LEN_STD  = 640;
    localparam integer PSS_START_STD  = 32;
    localparam integer SSS_START_STD  = 320;

    // -----------------------------------------------------------------------
    // DUT ports
    // -----------------------------------------------------------------------
    logic                              aclk;
    logic                              aresetn;
    logic                              start;
    logic [FRAME_INDEX_WIDTH-1:0]      pss_fft_start;
    logic [FRAME_INDEX_WIDTH-1:0]      sss_fft_start;
    logic [FRAME_INDEX_WIDTH-1:0]      frame_len;
    logic                              s_axis_tvalid;
    wire                               s_axis_tready;
    logic [DATA_W-1:0]                 s_axis_tdata;
    logic                              s_axis_tlast;
    wire                               m_axis_tvalid;
    logic                              m_axis_tready;
    wire  [DATA_W-1:0]                 m_axis_tdata;
    wire                               m_axis_tlast;
    wire                               m_symbol_sel;
    wire  [7:0]                        m_symbol_index;
    wire                               busy;
    wire                               done;
    wire                               error;
    wire  [3:0]                        error_code;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    pss_sss_symbol_extractor #(
        .NSC               (NSC),
        .CP_LEN            (CP_LEN),
        .IQ_WIDTH          (IQ_WIDTH),
        .FRAME_INDEX_WIDTH (FRAME_INDEX_WIDTH)
    ) dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .start          (start),
        .pss_fft_start  (pss_fft_start),
        .sss_fft_start  (sss_fft_start),
        .frame_len      (frame_len),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tlast   (s_axis_tlast),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tlast   (m_axis_tlast),
        .m_symbol_sel   (m_symbol_sel),
        .m_symbol_index (m_symbol_index),
        .busy           (busy),
        .done           (done),
        .error          (error),
        .error_code     (error_code)
    );

    // -----------------------------------------------------------------------
    // Clock
    // -----------------------------------------------------------------------
    initial aclk = 0;
    always #(CLK_PERIOD/2.0) aclk = ~aclk;

    integer pass_count;
    integer fail_count;

    localparam integer MAX_BUF = 512;
    logic [DATA_W-1:0] pss_buf     [0:MAX_BUF-1];
    logic [DATA_W-1:0] sss_buf     [0:MAX_BUF-1];
    logic [7:0]        pss_idx_buf [0:MAX_BUF-1];
    logic [7:0]        sss_idx_buf [0:MAX_BUF-1];
    logic              pss_last_buf[0:MAX_BUF-1];
    logic              sss_last_buf[0:MAX_BUF-1];
    integer            pss_out_cnt;
    integer            sss_out_cnt;

    // Pre-clock sample registers (module-scope to avoid task output issues)
    logic              pre_s_fire;
    logic              pre_m_fire;
    logic [DATA_W-1:0] pre_m_data;
    logic              pre_m_sel;
    logic [7:0]        pre_m_idx;
    logic              pre_m_last;

    function automatic [DATA_W-1:0] frame_word(input integer idx);
        frame_word = {~idx[15:0], idx[15:0]};
    endfunction

    // -----------------------------------------------------------------------
    // Macro-like task: tick one clock cycle.
    // Drives signals, samples wires pre-clock, waits posedge.
    // -----------------------------------------------------------------------
    task tick(
        input logic          drv_valid,
        input logic [DATA_W-1:0] drv_data,
        input logic          drv_last,
        input logic          drv_mready
    );
        s_axis_tvalid = drv_valid;
        s_axis_tdata  = drv_data;
        s_axis_tlast  = drv_last;
        m_axis_tready = drv_mready;
        // Pre-clock sampling: read wires after driven signals settled,
        // before posedge. Wires depend on DUT regs (hold_valid, state) which
        // are stable between posedges.
        pre_s_fire = drv_valid   & s_axis_tready;
        pre_m_fire = m_axis_tvalid & drv_mready;
        pre_m_data = m_axis_tdata;
        pre_m_sel  = m_symbol_sel;
        pre_m_idx  = m_symbol_index;
        pre_m_last = m_axis_tlast;
        @(posedge aclk);
        // #1 separates the testbench's next signal update from the DUT's
        // posedge processing, eliminating the active-region race where the
        // initial block could overwrite s_axis_tdata before the always block
        // reads it in the same simulation timestep.
        #1;
    endtask

    // -----------------------------------------------------------------------
    // Task: capture output into buffers (uses pre_* registers)
    // -----------------------------------------------------------------------
    task do_capture();
        if (pre_m_fire) begin
            if (pre_m_sel == 1'b0 && pss_out_cnt < MAX_BUF) begin
                pss_buf[pss_out_cnt]      = pre_m_data;
                pss_idx_buf[pss_out_cnt]  = pre_m_idx;
                pss_last_buf[pss_out_cnt] = pre_m_last;
                pss_out_cnt++;
            end else if (pre_m_sel == 1'b1 && sss_out_cnt < MAX_BUF) begin
                sss_buf[sss_out_cnt]      = pre_m_data;
                sss_idx_buf[sss_out_cnt]  = pre_m_idx;
                sss_last_buf[sss_out_cnt] = pre_m_last;
                sss_out_cnt++;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // apply_reset
    // -----------------------------------------------------------------------
    task apply_reset();
        aresetn       = 1'b0;
        start         = 1'b0;
        s_axis_tvalid = 1'b0;
        s_axis_tdata  = {DATA_W{1'b0}};
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;
        pss_fft_start = '0;
        sss_fft_start = '0;
        frame_len     = '0;
        repeat(4) @(posedge aclk);
        aresetn = 1'b1;
        @(posedge aclk);
        pss_out_cnt = 0;
        sss_out_cnt = 0;
    endtask

    task check_pass(input string name, input logic cond);
        if (cond) begin
            $display("[PASS] %s", name);
            pass_count++;
        end else begin
            $display("[FAIL] %s", name);
            fail_count++;
        end
    endtask

    // -----------------------------------------------------------------------
    // run_extract:
    //   Drives a complete extraction run using tick().
    //   gap_period: insert 1-cycle gap after every gap_period real samples.
    //   bp_period:  hold m_axis_tready=0 for 1 cycle every bp_period cycles.
    // -----------------------------------------------------------------------
    task automatic run_extract(
        input integer p_fft,
        input integer s_fft,
        input integer flen,
        input integer early_tlast_at,
        input integer gap_period,
        input integer bp_period
    );
        integer cyc, drive_idx, tlast_at, bp_ctr;
        logic   in_gap, mready;

        pss_out_cnt = 0;
        sss_out_cnt = 0;

        pss_fft_start = p_fft[FRAME_INDEX_WIDTH-1:0];
        sss_fft_start = s_fft[FRAME_INDEX_WIDTH-1:0];
        frame_len     = flen[FRAME_INDEX_WIDTH-1:0];

        tick(1'b0, '0, 1'b0, 1'b1);   // one idle cycle with new config
        start = 1'b1;
        tick(1'b0, '0, 1'b0, 1'b1);   // start asserted for one cycle
        start = 1'b0;

        tlast_at  = (early_tlast_at >= 0) ? early_tlast_at : (flen - 1);
        drive_idx = 0;
        bp_ctr    = 0;
        in_gap    = 1'b0;

        for (cyc = 0; cyc < flen * 20 + 500; cyc++) begin
            // Backpressure
            if (bp_period > 0) begin
                bp_ctr++;
                mready = (bp_ctr >= bp_period) ? 1'b0 : 1'b1;
                if (bp_ctr >= bp_period) bp_ctr = 0;
            end else begin
                mready = 1'b1;
            end

            // Clock tick with current drive state
            if (in_gap || drive_idx > tlast_at || done || error) begin
                tick(1'b0, {DATA_W{1'b0}}, 1'b0, mready);
            end else begin
                tick(1'b1, frame_word(drive_idx),
                     (drive_idx == tlast_at) ? 1'b1 : 1'b0,
                     mready);
            end

            // Process results from this clock cycle
            do_capture();

            if (in_gap) begin
                in_gap = 1'b0;   // exit gap unconditionally after 1 idle cycle
            end else if (pre_s_fire) begin
                drive_idx++;
                // Schedule gap after every gap_period real samples
                if (gap_period > 0 && drive_idx > 0
                    && (drive_idx % gap_period) == 0
                    && drive_idx <= tlast_at)
                    in_gap = 1'b1;
            end

            if (done || error) break;
        end

        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b1;
        repeat(10) @(posedge aclk);
    endtask

    // -----------------------------------------------------------------------
    // MAIN TEST SEQUENCE
    // -----------------------------------------------------------------------
    initial begin
        pass_count = 0;
        fail_count = 0;

        apply_reset();

        // -------------------------------------------------------------------
        // T1: reset_defaults
        // -------------------------------------------------------------------
        $display("T1: reset_defaults");
        check_pass("T1_busy_low",          busy          == 1'b0);
        check_pass("T1_done_low",          done          == 1'b0);
        check_pass("T1_error_low",         error         == 1'b0);
        check_pass("T1_m_axis_tvalid_low", m_axis_tvalid == 1'b0);

        // -------------------------------------------------------------------
        // T2: basic_extract
        // -------------------------------------------------------------------
        $display("T2: basic_extract");
        apply_reset();
        run_extract(PSS_START_STD, SSS_START_STD, FRAME_LEN_STD, -1, 0, 0);
        check_pass("T2_pss_count", pss_out_cnt == NSC);
        check_pass("T2_sss_count", sss_out_cnt == NSC);
        check_pass("T2_no_error",  error       == 1'b0);

        // -------------------------------------------------------------------
        // T3: pss_data_exact
        // -------------------------------------------------------------------
        $display("T3: pss_data_exact");
        begin
            integer i, mm;
            mm = 0;
            for (i = 0; i < NSC; i++)
                if (pss_buf[i] !== frame_word(PSS_START_STD + i)) mm++;
            check_pass("T3_pss_data", mm == 0);
        end

        // -------------------------------------------------------------------
        // T4: sss_data_exact
        // -------------------------------------------------------------------
        $display("T4: sss_data_exact");
        begin
            integer i, mm;
            mm = 0;
            for (i = 0; i < NSC; i++)
                if (sss_buf[i] !== frame_word(SSS_START_STD + i)) mm++;
            check_pass("T4_sss_data", mm == 0);
        end

        // -------------------------------------------------------------------
        // T5: tlast_positions
        // -------------------------------------------------------------------
        $display("T5: tlast_positions");
        begin
            integer i, bp, bs;
            bp = 0; bs = 0;
            for (i = 0; i < NSC; i++) begin
                if (i == NSC-1) begin
                    if (pss_last_buf[i] !== 1'b1) bp++;
                    if (sss_last_buf[i] !== 1'b1) bs++;
                end else begin
                    if (pss_last_buf[i] !== 1'b0) bp++;
                    if (sss_last_buf[i] !== 1'b0) bs++;
                end
            end
            check_pass("T5_pss_tlast", bp == 0);
            check_pass("T5_sss_tlast", bs == 0);
        end

        // -------------------------------------------------------------------
        // T6: output_backpressure
        // -------------------------------------------------------------------
        $display("T6: output_backpressure");
        apply_reset();
        run_extract(PSS_START_STD, SSS_START_STD, FRAME_LEN_STD, -1, 0, 3);
        check_pass("T6_pss_count", pss_out_cnt == NSC);
        check_pass("T6_sss_count", sss_out_cnt == NSC);
        check_pass("T6_no_error",  error       == 1'b0);
        begin
            integer i, mm;
            mm = 0;
            for (i = 0; i < NSC; i++) begin
                if (pss_buf[i] !== frame_word(PSS_START_STD + i)) mm++;
                if (sss_buf[i] !== frame_word(SSS_START_STD + i)) mm++;
            end
            check_pass("T6_data_integrity", mm == 0);
        end

        // -------------------------------------------------------------------
        // T7: input_gaps
        // -------------------------------------------------------------------
        $display("T7: input_gaps");
        apply_reset();
        run_extract(PSS_START_STD, SSS_START_STD, FRAME_LEN_STD, -1, 5, 0);
        check_pass("T7_pss_count", pss_out_cnt == NSC);
        check_pass("T7_sss_count", sss_out_cnt == NSC);
        check_pass("T7_no_error",  error       == 1'b0);

        // -------------------------------------------------------------------
        // T8: different_offsets
        // -------------------------------------------------------------------
        $display("T8: different_offsets");
        apply_reset();
        run_extract(16, 400, 700, -1, 0, 0);
        check_pass("T8_pss_count", pss_out_cnt == NSC);
        check_pass("T8_sss_count", sss_out_cnt == NSC);
        check_pass("T8_no_error",  error       == 1'b0);
        begin
            integer i, mm;
            mm = 0;
            for (i = 0; i < NSC; i++) begin
                if (pss_buf[i] !== frame_word(16 + i)) mm++;
                if (sss_buf[i] !== frame_word(400 + i)) mm++;
            end
            check_pass("T8_data_exact", mm == 0);
        end

        // -------------------------------------------------------------------
        // T9: invalid_config — pss out of range
        // -------------------------------------------------------------------
        $display("T9: invalid_config_pss_out_of_range");
        apply_reset();
        pss_fft_start = 12'd100;
        sss_fft_start = 12'd0;
        frame_len     = 12'd300;
        tick(1'b0, '0, 1'b0, 1'b1);
        start = 1'b1; tick(1'b0, '0, 1'b0, 1'b1); start = 1'b0;
        repeat(5) @(posedge aclk);
        check_pass("T9_error",      error      == 1'b1);
        check_pass("T9_error_code", error_code == 4'd1);
        check_pass("T9_not_busy",   busy       == 1'b0);

        // -------------------------------------------------------------------
        // T10: invalid_config — sss out of range
        // -------------------------------------------------------------------
        $display("T10: invalid_config_sss_out_of_range");
        apply_reset();
        pss_fft_start = 12'd0;
        sss_fft_start = 12'd200;
        frame_len     = 12'd400;
        tick(1'b0, '0, 1'b0, 1'b1);
        start = 1'b1; tick(1'b0, '0, 1'b0, 1'b1); start = 1'b0;
        repeat(5) @(posedge aclk);
        check_pass("T10_error",      error      == 1'b1);
        check_pass("T10_error_code", error_code == 4'd1);

        // -------------------------------------------------------------------
        // T11: early_tlast
        // -------------------------------------------------------------------
        $display("T11: early_tlast");
        apply_reset();
        run_extract(PSS_START_STD, SSS_START_STD, FRAME_LEN_STD, 100, 0, 0);
        check_pass("T11_error",      error      == 1'b1);
        check_pass("T11_error_code", error_code == 4'd2);

        // -------------------------------------------------------------------
        // T12: start_while_busy
        // -------------------------------------------------------------------
        $display("T12: start_while_busy");
        apply_reset();
        pss_fft_start = PSS_START_STD;
        sss_fft_start = SSS_START_STD;
        frame_len     = FRAME_LEN_STD;
        tick(1'b0, '0, 1'b0, 1'b1);
        start = 1'b1; tick(1'b0, '0, 1'b0, 1'b1); start = 1'b0;
        // Idle a few cycles then pulse start again
        repeat(5) @(posedge aclk);
        start = 1'b1; tick(1'b0, '0, 1'b0, 1'b1); start = 1'b0;
        check_pass("T12_still_busy", busy == 1'b1);
        // Now feed samples and collect (DUT is in S_STREAM, already a few frames in)
        begin : T12_feed
            integer di, cyc2;
            pss_out_cnt = 0;
            sss_out_cnt = 0;
            di = 0;
            for (cyc2 = 0; cyc2 < FRAME_LEN_STD * 20; cyc2++) begin
                tick(
                    (di < FRAME_LEN_STD) ? 1'b1 : 1'b0,
                    frame_word(di),
                    (di == FRAME_LEN_STD - 1) ? 1'b1 : 1'b0,
                    1'b1
                );
                do_capture();
                if (pre_s_fire && di < FRAME_LEN_STD) di++;
                if (done) break;  // start_while_busy (ec=4) is non-fatal; only stop on done
            end
        end
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        repeat(10) @(posedge aclk);
        check_pass("T12_completed", busy == 1'b0);
        check_pass("T12_extracted", pss_out_cnt == NSC && sss_out_cnt == NSC);

        // -------------------------------------------------------------------
        // T13: overlap_invalid
        // -------------------------------------------------------------------
        $display("T13: overlap_invalid");
        apply_reset();
        pss_fft_start = 12'd100;
        sss_fft_start = 12'd200;
        frame_len     = 12'd700;
        tick(1'b0, '0, 1'b0, 1'b1);
        start = 1'b1; tick(1'b0, '0, 1'b0, 1'b1); start = 1'b0;
        repeat(5) @(posedge aclk);
        check_pass("T13_error",      error      == 1'b1);
        check_pass("T13_error_code", error_code == 4'd1);

        // -------------------------------------------------------------------
        // T14: exact_minimum_frame — frame_len == sss_fft_start + NSC = 576
        // -------------------------------------------------------------------
        $display("T14: exact_minimum_frame");
        apply_reset();
        run_extract(PSS_START_STD, SSS_START_STD, SSS_START_STD + NSC, -1, 0, 0);
        check_pass("T14_pss_count", pss_out_cnt == NSC);
        check_pass("T14_sss_count", sss_out_cnt == NSC);
        check_pass("T14_no_error",  error       == 1'b0);

        // -------------------------------------------------------------------
        // Summary
        // -------------------------------------------------------------------
        $display("");
        $display("PASS: %0d  FAIL: %0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

    initial begin
        #(CLK_PERIOD * 500000);
        $display("[FAIL] TIMEOUT — watchdog fired");
        $display("CI GATE: FAILED");
        $finish;
    end

endmodule
