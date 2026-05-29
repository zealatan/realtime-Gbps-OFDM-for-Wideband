`timescale 1ns/1ps

// session_A_p3_12c_full_phase3_regression_tb
//
// Session A / P3-12C: Full Phase3 regression closure for the modular frame_detector.
// Drives phase3_sync_top through the full pipeline and checks:
//
//   C1  frame_found == 1              (dbg_frame_start_valid asserted)
//   C2  frame_index == 41 (±1)        (dbg_frame_start_index)
//   C3  peak_lag == 23 (±1)           (dbg_peak_index)
//   C4  slot_start_index == 64 (±1)   (dbg_slot_start_index)
//   C5  slot_start == frame_index + peak_lag (±1)
//   C6  done eventually asserts
//   C7  error_code == 0
//   C8  modular frame_detector FSM hierarchy probe (u_frac_corr.u_fd.u_fsm.frame_found)
//   C9  PSS/SSS activity: dbg_slot_start_valid observed (slot windows computed)
//   C10 Meyr pipeline: dbg_integer_cfo_valid observed (integer CFO valid)
//
// IQ stimulus: golden/phase3_iq_stimulus_q15.hex (704 IQ pairs, Q15 hex)

module session_A_p3_12c_full_phase3_regression_tb;

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam int NSC      = 256;
    localparam int CP_LEN   = 32;
    localparam int BUF_AW   = 12;
    localparam int INDEX_W  = 9;
    localparam int PHASE_W  = 16;
    localparam int NCO_PW   = 32;
    localparam int ENERGY_W = 40;

    localparam real CLK_HALF    = 5.0;      // 100 MHz
    localparam int  MAX_IQ      = 65536;
    localparam int  TIMEOUT_CYC = 2000000;

    // Golden expected values (same as P3-05C / P3-12B)
    localparam int GOLDEN_FRAME_IDX  = 41;
    localparam int GOLDEN_PEAK_LAG   = 23;
    localparam int GOLDEN_SLOT_START = 64;
    localparam int FRAME_TOL         = 1;
    localparam int PEAK_TOL          = 1;
    localparam int SLOT_TOL          = 1;

    // Frame detector config (matches P3-05C golden)
    localparam logic [ENERGY_W-1:0] THRESHOLD_VAL  = 40'd40000;
    localparam logic [6:0]          WINDOW_LEN_VAL = 7'd25;
    localparam logic [3:0]          HIT_COUNT_VAL  = 4'd10;

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_HALF) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // AXI-Stream IQ
    // -----------------------------------------------------------------------
    logic        s_valid = 1'b0;
    wire         s_ready;
    logic [31:0] s_data  = 32'b0;

    // -----------------------------------------------------------------------
    // DUT control/status
    // -----------------------------------------------------------------------
    logic start = 1'b0;
    wire  done_out, busy_out, error_out;
    wire  [3:0] error_code_out;

    // -----------------------------------------------------------------------
    // DUT debug outputs
    // -----------------------------------------------------------------------
    wire                dbg_frame_start_valid;
    wire [BUF_AW-1:0]   dbg_frame_start_index;
    wire                dbg_peak_valid;
    wire [INDEX_W-1:0]  dbg_peak_index;
    wire                dbg_slot_start_valid;
    wire [BUF_AW-1:0]   dbg_slot_start_index;
    wire                dbg_frac_cfo_valid;
    wire [PHASE_W-1:0]  dbg_frac_cfo_word;
    wire [BUF_AW-1:0]   dbg_pss_start;
    wire [BUF_AW-1:0]   dbg_sss_start;
    wire                dbg_integer_cfo_valid;
    wire [NCO_PW-1:0]   dbg_integer_cfo_word;
    wire                dbg_done;
    wire [3:0]          dbg_error_code;
    wire [31:0]         dbg_frac_m_tdata;
    wire                dbg_frac_m_tvalid;
    wire                dbg_frac_m_tready;
    wire                dbg_frac_m_tlast;
    wire [INDEX_W-1:0]  dbg_meyr_peak_index;

    // -----------------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------------
    phase3_sync_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .INDEX_WIDTH     (INDEX_W),
        .PHASE_WIDTH     (PHASE_W),
        .NCO_PHASE_WIDTH (NCO_PW)
    ) u_dut (
        .aclk                 (aclk),
        .aresetn              (aresetn),
        .s_axis_tdata         (s_data),
        .s_axis_tvalid        (s_valid),
        .s_axis_tready        (s_ready),
        .s_axis_tlast         (1'b0),
        .threshold_in         (THRESHOLD_VAL),
        .window_len_in        (WINDOW_LEN_VAL),
        .hit_count_in         (HIT_COUNT_VAL),
        .start                (start),
        .done                 (done_out),
        .busy                 (busy_out),
        .error                (error_out),
        .error_code           (error_code_out),
        .dbg_frame_start_valid(dbg_frame_start_valid),
        .dbg_frame_start_index(dbg_frame_start_index),
        .dbg_peak_valid       (dbg_peak_valid),
        .dbg_peak_index       (dbg_peak_index),
        .dbg_slot_start_valid (dbg_slot_start_valid),
        .dbg_slot_start_index (dbg_slot_start_index),
        .dbg_frac_cfo_valid   (dbg_frac_cfo_valid),
        .dbg_frac_cfo_word    (dbg_frac_cfo_word),
        .dbg_pss_start        (dbg_pss_start),
        .dbg_sss_start        (dbg_sss_start),
        .dbg_integer_cfo_valid(dbg_integer_cfo_valid),
        .dbg_integer_cfo_word (dbg_integer_cfo_word),
        .dbg_done             (dbg_done),
        .dbg_error_code       (dbg_error_code),
        .dbg_frac_m_tdata     (dbg_frac_m_tdata),
        .dbg_frac_m_tvalid    (dbg_frac_m_tvalid),
        .dbg_frac_m_tready    (dbg_frac_m_tready),
        .dbg_frac_m_tlast     (dbg_frac_m_tlast),
        .dbg_meyr_peak_index  (dbg_meyr_peak_index)
    );

    // -----------------------------------------------------------------------
    // Hierarchy probe: modular frame_detector FSM (C8)
    // Accessing u_dut.u_frac_corr.u_fd.u_fsm.frame_found confirms modular
    // architecture is intact. Only works if frame_detect_fsm is instantiated.
    // -----------------------------------------------------------------------
    wire modular_fsm_frame_found = u_dut.u_frac_corr.u_fd.u_fsm.frame_found;

    // -----------------------------------------------------------------------
    // IQ stimulus
    // -----------------------------------------------------------------------
    logic [31:0] iq_mem [0:MAX_IQ-1];

    // -----------------------------------------------------------------------
    // Capture registers
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    logic   frame_start_seen, peak_seen, slot_start_seen, done_seen;
    logic   int_cfo_valid_seen;
    logic   fsm_frame_found_seen;

    logic [BUF_AW-1:0]  cap_frame_index;
    logic [INDEX_W-1:0] cap_peak_lag;
    logic [BUF_AW-1:0]  cap_slot_start;
    logic [3:0]         cap_error_code;

    always @(posedge aclk) begin
        if (aresetn) begin
            cycle_cnt = cycle_cnt + 1;

            if (dbg_frame_start_valid && !frame_start_seen) begin
                frame_start_seen = 1;
                cap_frame_index  = dbg_frame_start_index;
                $display("[TB] @%0d frame_start_valid: index=%0d",
                         cycle_cnt, dbg_frame_start_index);
            end
            if (dbg_peak_valid && !peak_seen) begin
                peak_seen    = 1;
                cap_peak_lag = dbg_peak_index;
                $display("[TB] @%0d peak_valid: peak_lag=%0d", cycle_cnt, dbg_peak_index);
            end
            if (dbg_slot_start_valid && !slot_start_seen) begin
                slot_start_seen = 1;
                cap_slot_start  = dbg_slot_start_index;
                $display("[TB] @%0d slot_start_valid: slot=%0d",
                         cycle_cnt, dbg_slot_start_index);
            end
            if (dbg_integer_cfo_valid && !int_cfo_valid_seen) begin
                int_cfo_valid_seen = 1;
                $display("[TB] @%0d integer_cfo_valid: word=0x%08h",
                         cycle_cnt, dbg_integer_cfo_word);
            end
            // C8 probe: sample modular FSM frame_found each cycle
            if (modular_fsm_frame_found && !fsm_frame_found_seen) begin
                fsm_frame_found_seen = 1;
                $display("[TB] @%0d modular_fsm_frame_found asserted", cycle_cnt);
            end
            if (done_out && !done_seen) begin
                done_seen      = 1;
                cap_error_code = error_code_out;
                $display("[TB] @%0d DONE: error=%0b error_code=%0d",
                         cycle_cnt, error_out, error_code_out);
            end
        end
    end

    // -----------------------------------------------------------------------
    // Scoreboard
    // -----------------------------------------------------------------------
    int pass_cnt, fail_cnt;

    task automatic chk(input string nm, input logic got, input logic exp);
        if (got === exp)
            begin $display("[PASS] %s", nm); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0b exp=%0b", nm, got, exp); fail_cnt++; end
    endtask

    task automatic chk_int(input string nm, input int got, input int exp, input int tol);
        int delta;
        delta = (got >= exp) ? got - exp : exp - got;
        if (delta <= tol)
            begin $display("[PASS] %s  got=%0d exp=%0d tol=±%0d", nm, got, exp, tol); pass_cnt++; end
        else
            begin $display("[FAIL] %s  got=%0d exp=%0d delta=%0d tol=±%0d",
                           nm, got, exp, delta, tol); fail_cnt++; end
    endtask

    // -----------------------------------------------------------------------
    // Main test
    // -----------------------------------------------------------------------
    initial begin : tb_main
        integer i;

        $readmemh("golden/phase3_iq_stimulus_q15.hex", iq_mem, 0, MAX_IQ-1);

        cycle_cnt            = 0;
        frame_start_seen     = 0;
        peak_seen            = 0;
        slot_start_seen      = 0;
        done_seen            = 0;
        int_cfo_valid_seen   = 0;
        fsm_frame_found_seen = 0;
        cap_frame_index      = '0;
        cap_peak_lag         = '0;
        cap_slot_start       = '0;
        cap_error_code       = '0;
        pass_cnt = 0;
        fail_cnt = 0;

        aresetn = 1'b0;
        repeat(4) @(posedge aclk);
        aresetn = 1'b1;
        repeat(4) @(posedge aclk);

        fork
            begin : stream_thread
                start = 1'b1;
                @(posedge aclk);
                start = 1'b0;
                for (i = 0; i < MAX_IQ; i++) begin
                    s_valid <= 1'b1;
                    s_data  <= iq_mem[i];
                    @(posedge aclk);
                    while (!s_ready) @(posedge aclk);
                    if (done_seen) begin
                        s_valid <= 1'b0;
                        disable stream_thread;
                    end
                end
                s_valid <= 1'b0;
                repeat(NSC + CP_LEN + 64) @(posedge aclk);
            end

            begin : done_thread
                wait (done_seen);
            end

            begin : timeout_thread
                repeat(TIMEOUT_CYC) @(posedge aclk);
                $display("[FAIL] C6 TIMEOUT: done not seen within %0d cycles", TIMEOUT_CYC);
                fail_cnt++;
                disable tb_main;
            end
        join_any
        disable fork;

        @(posedge aclk);
        s_valid <= 1'b0;

        // --------------------------------------------------------------------
        // Evaluate
        // --------------------------------------------------------------------
        $display("");
        $display("=== Session A / P3-12C Full Phase3 Regression Checks ===");
        $display("    DUT: phase3_sync_top + modular frame_detector (P3-12A)");
        $display("");

        // C1: frame_found
        chk("C1 frame_found==1 (frame_start_valid observed)",
            logic'(frame_start_seen), 1'b1);

        // C2: frame_index == 41
        chk_int("C2 frame_index==41",
                int'(cap_frame_index), GOLDEN_FRAME_IDX, FRAME_TOL);

        // C3: peak_lag == 23
        chk_int("C3 peak_lag==23",
                int'(cap_peak_lag), GOLDEN_PEAK_LAG, PEAK_TOL);

        // C4: slot_start == 64
        chk_int("C4 slot_start==64",
                int'(cap_slot_start), GOLDEN_SLOT_START, SLOT_TOL);

        // C5: slot_start == frame_index + peak_lag
        if (frame_start_seen && peak_seen && slot_start_seen) begin
            chk_int("C5 slot_start==frame_index+peak_lag",
                    int'(cap_slot_start),
                    int'(cap_frame_index) + int'(cap_peak_lag),
                    SLOT_TOL);
        end else begin
            $display("[FAIL] C5 SKIP — frame/peak/slot not all captured");
            fail_cnt++;
        end

        // C6: done asserted
        chk("C6 done asserted", logic'(done_seen), 1'b1);

        // C7: error_code == 0
        chk("C7 error_code==0", logic'(cap_error_code == 4'h0), 1'b1);

        // C8: modular FSM hierarchy probe
        chk("C8 modular_fsm_frame_found observed (modular hierarchy intact)",
            logic'(fsm_frame_found_seen), 1'b1);

        // C9: slot_start_valid => PSS/SSS window computation active
        chk("C9 slot_start_valid observed (PSS/SSS windows computed)",
            logic'(slot_start_seen), 1'b1);

        // C10: integer_cfo_valid => Meyr pipeline completed
        chk("C10 integer_cfo_valid observed (Meyr pipeline reached done)",
            logic'(int_cfo_valid_seen), 1'b1);

        // --------------------------------------------------------------------
        // Summary
        // --------------------------------------------------------------------
        $display("");
        $display("  frame_index  = %0d  (golden=%0d)", cap_frame_index, GOLDEN_FRAME_IDX);
        $display("  peak_lag     = %0d  (golden=%0d)", cap_peak_lag, GOLDEN_PEAK_LAG);
        $display("  slot_start   = %0d  (golden=%0d)", cap_slot_start, GOLDEN_SLOT_START);
        $display("  cycles       = %0d", cycle_cnt);
        $display("");
        $display("--- P3-12C: %0d PASS  %0d FAIL ---", pass_cnt, fail_cnt);

        if (fail_cnt == 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");

        $finish;
    end

endmodule
