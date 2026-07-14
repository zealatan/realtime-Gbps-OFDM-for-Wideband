`timescale 1ns/1ps
// Phase 3 — Reference C vs RTL Verification Testbench
//
// DUT: phase3_sync_top (rtl/phase3_sync_top.v)
//
// Streams IQ samples from golden/phase3_iq_stimulus_q15.hex into phase3_sync_top.
// Waits for the done pulse, capturing all dbg_* debug outputs along the way.
//
// Outputs:
//   logs/phase3_sync_rtl_dump.csv   — per-event CSV trace (all debug fields)
//   sim_out/rtl_results.txt         — key=value summary for compare_golden_rtl.py
//
// All file paths are relative to the project root (run simulation from there).
//
// IQ packing convention (Q15 hex file):
//   One 32-bit word per line: upper 16 bits = Q, lower 16 bits = I
//   Matches s_axis_tdata[31:16]=Q, s_axis_tdata[15:0]=I
//
// Run sequence:
//   1. Reset (aresetn=0 for 4 cycles)
//   2. De-assert reset, stabilize 4 cycles
//   3. Pulse start=1 for 1 cycle (phase3_sync_top FSM: S_IDLE -> S_RUN)
//   4. Stream IQ (AXI-S handshake, backpressure from DUT)
//   5. Wait for done or TIMEOUT
//   6. Write results

module phase3_sync_reference_compare_tb;

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

    localparam real CLK_HALF    = 5.0;       // 100 MHz
    localparam int  MAX_IQ      = 65536;     // IQ memory depth
    localparam int  TIMEOUT_CYC = 2000000;   // 2M cycle timeout (covers full Meyr pipeline)

    // -----------------------------------------------------------------------
    // Clock / reset
    // -----------------------------------------------------------------------
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    always #(CLK_HALF) aclk = ~aclk;

    // -----------------------------------------------------------------------
    // AXI-Stream IQ input
    // -----------------------------------------------------------------------
    logic        s_valid = 1'b0;
    wire         s_ready;
    logic [31:0] s_data  = 32'b0;

    // -----------------------------------------------------------------------
    // Control
    // -----------------------------------------------------------------------
    logic start = 1'b0;
    wire  done_out, busy_out, error_out;
    wire  [3:0] error_code_out;

    // Config — tied to phase3_sync_top parameter defaults
    localparam logic [ENERGY_W-1:0] THRESHOLD_VAL  = 40'd40000; // matches C golden_dump threshold for amplitude-3000 stimulus
    localparam logic [6:0]          WINDOW_LEN_VAL = 7'd25;
    localparam logic [3:0]          HIT_COUNT_VAL  = 4'd10;

    // -----------------------------------------------------------------------
    // Phase 3 DUT debug outputs
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

    // -----------------------------------------------------------------------
    // DUT — phase3_sync_top
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
        .s_axis_tlast         (1'b0),          // continuous stream, no frame boundary
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
        .dbg_error_code       (dbg_error_code)
    );

    // -----------------------------------------------------------------------
    // IQ stimulus memory
    // -----------------------------------------------------------------------
    logic [31:0] iq_mem [0:MAX_IQ-1];

    // -----------------------------------------------------------------------
    // Capture registers (updated by always block with blocking assignments)
    // -----------------------------------------------------------------------
    integer cycle_cnt;
    logic   frame_start_seen, peak_seen, slot_start_seen;
    logic   frac_cfo_seen, integer_cfo_seen, done_seen;

    logic [BUF_AW-1:0]         cap_frame_start_idx;
    logic [INDEX_W-1:0]        cap_peak_idx;
    logic [BUF_AW-1:0]         cap_slot_start_idx;
    logic signed [PHASE_W-1:0] cap_frac_cfo;
    logic signed [NCO_PW-1:0]  cap_int_cfo;
    logic [BUF_AW-1:0]         cap_pss_start;
    logic [BUF_AW-1:0]         cap_sss_start;
    logic [3:0]                 cap_error_code;

    // P3-07: PSS/SSS extraction monitoring
    integer      pss_sample_count;
    integer      sss_sample_count;
    logic        pss_ext_started;
    logic        sss_ext_started;
    logic [15:0] cap_pss_first_i, cap_pss_first_q;
    logic [15:0] cap_pss_last_i,  cap_pss_last_q;
    logic [15:0] cap_sss_first_i, cap_sss_first_q;
    logic [15:0] cap_sss_last_i,  cap_sss_last_q;
    integer      cap_meyr_peak_idx;

    // -----------------------------------------------------------------------
    // File handles
    // -----------------------------------------------------------------------
    integer csv_fd, res_fd;

    // -----------------------------------------------------------------------
    // Initialization + main flow
    // -----------------------------------------------------------------------
    initial begin : tb_main
        integer i;

        // Load IQ hex stimulus
        $readmemh("golden/phase3_iq_stimulus_q15.hex", iq_mem, 0, MAX_IQ-1);

        // Open output files (logs/ and sim_out/ must exist before simulation)
        csv_fd = $fopen("logs/phase3_sync_rtl_dump.csv", "w");
        if (csv_fd == 0) begin
            $display("[TB] FATAL: Cannot open logs/phase3_sync_rtl_dump.csv");
            $finish;
        end
        res_fd = $fopen("sim_out/rtl_results.txt", "w");
        if (res_fd == 0) begin
            $display("[TB] FATAL: Cannot open sim_out/rtl_results.txt");
            $finish;
        end

        // CSV header
        $fdisplay(csv_fd, "cycle,frame_start_valid,frame_start_index,peak_valid,peak_index,slot_start_valid,slot_start_index,frac_cfo_valid,frac_cfo_word,pss_start,sss_start,integer_cfo_valid,integer_cfo_word,done,error_code");

        // Init capture state
        cycle_cnt        = 0;
        frame_start_seen = 0;
        peak_seen        = 0;
        slot_start_seen  = 0;
        frac_cfo_seen    = 0;
        integer_cfo_seen = 0;
        done_seen        = 0;
        cap_frame_start_idx = '0;
        cap_peak_idx        = '0;
        cap_slot_start_idx  = '0;
        cap_frac_cfo        = '0;
        cap_int_cfo         = '0;
        cap_pss_start       = '0;
        cap_sss_start       = '0;
        cap_error_code      = '0;
        pss_sample_count  = 0;
        sss_sample_count  = 0;
        pss_ext_started   = 0;
        sss_ext_started   = 0;
        cap_pss_first_i   = '0;
        cap_pss_first_q   = '0;
        cap_pss_last_i    = '0;
        cap_pss_last_q    = '0;
        cap_sss_first_i   = '0;
        cap_sss_first_q   = '0;
        cap_sss_last_i    = '0;
        cap_sss_last_q    = '0;
        cap_meyr_peak_idx = -1;

        // Reset sequence
        aresetn = 1'b0;
        repeat(4) @(posedge aclk);
        aresetn = 1'b1;
        repeat(4) @(posedge aclk);

        // Start + stream IQ (forked: stream and done-detector run concurrently)
        fork
            // Thread A: stream IQ samples
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
                // Pipeline drain: wait for DUT to process buffered samples
                repeat(NSC + CP_LEN + 64) @(posedge aclk);
            end

            // Thread B: wait for done (set by always block)
            begin : done_thread
                wait (done_seen);
            end

            // Thread C: timeout watchdog
            begin : timeout_thread
                repeat(TIMEOUT_CYC) @(posedge aclk);
                $display("[TB] TIMEOUT: no done within %0d cycles", TIMEOUT_CYC);
            end

        join_any
        disable fork;

        // One extra tick so always-block NBAs complete before we read captures
        @(posedge aclk);
        s_valid <= 1'b0;

        write_results();
    end

    // -----------------------------------------------------------------------
    // Capture + CSV event logger (always block)
    // Always block uses blocking assignments so capture values are immediately
    // visible to the initial block and write_results task.
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (aresetn) begin
            cycle_cnt = cycle_cnt + 1;

            // Frame start + peak + frac CFO fire simultaneously on frac_phase_valid
            if (dbg_frame_start_valid && !frame_start_seen) begin
                frame_start_seen    = 1;
                cap_frame_start_idx = dbg_frame_start_index;
                $display("[TB] @%0d frame_start_valid: index=%0d",
                         cycle_cnt, dbg_frame_start_index);
            end
            if (dbg_peak_valid && !peak_seen) begin
                peak_seen   = 1;
                cap_peak_idx = dbg_peak_index;
            end
            if (dbg_frac_cfo_valid && !frac_cfo_seen) begin
                frac_cfo_seen = 1;
                cap_frac_cfo  = $signed(dbg_frac_cfo_word);
                $display("[TB] @%0d frac_cfo_valid: word=%0d (Q1.15 = %f pi-rad)",
                         cycle_cnt, $signed(dbg_frac_cfo_word),
                         $signed(dbg_frac_cfo_word) * 3.14159265 / 32768.0);
            end

            // Slot start fires on frac_done (slightly after frac_phase_valid)
            if (dbg_slot_start_valid && !slot_start_seen) begin
                slot_start_seen    = 1;
                cap_slot_start_idx = dbg_slot_start_index;
                cap_pss_start      = dbg_pss_start;
                cap_sss_start      = dbg_sss_start;
                $display("[TB] @%0d slot_start_valid: slot=%0d  pss_start=%0d  sss_start=%0d",
                         cycle_cnt, dbg_slot_start_index, dbg_pss_start, dbg_sss_start);
            end

            // Integer CFO fires after Meyr FFT estimation
            if (dbg_integer_cfo_valid && !integer_cfo_seen) begin
                integer_cfo_seen  = 1;
                cap_int_cfo       = $signed(dbg_integer_cfo_word);
                cap_meyr_peak_idx = u_dut.u_meyr_fft.peak_index_r;
                $display("[TB] @%0d integer_cfo_valid: step_word=%0d  meyr_peak_idx=%0d (informational)",
                         cycle_cnt, $signed(dbg_integer_cfo_word), u_dut.u_meyr_fft.peak_index_r);
            end

            // Done — fires 1 cycle after Meyr completes or on error
            if (done_out && !done_seen) begin
                done_seen      = 1;
                cap_error_code = error_code_out;
                $display("[TB] @%0d DONE: error=%0b  error_code=%0d",
                         cycle_cnt, error_out, error_code_out);
            end

            // P3-07: PSS/SSS extraction sample counting via hierarchy access
            if (u_dut.ext_m_tvalid && u_dut.ext_m_tready) begin
                if (!u_dut.ext_m_symbol_sel) begin
                    pss_sample_count = pss_sample_count + 1;
                    if (!pss_ext_started) begin
                        cap_pss_first_i = u_dut.ext_m_tdata[15:0];
                        cap_pss_first_q = u_dut.ext_m_tdata[31:16];
                        pss_ext_started = 1;
                        $display("[TB] @%0d PSS first sample: I=%0d Q=%0d",
                                 cycle_cnt, $signed(u_dut.ext_m_tdata[15:0]),
                                 $signed(u_dut.ext_m_tdata[31:16]));
                    end
                    cap_pss_last_i = u_dut.ext_m_tdata[15:0];
                    cap_pss_last_q = u_dut.ext_m_tdata[31:16];
                    if (pss_sample_count == NSC)
                        $display("[TB] @%0d PSS window done: %0d samples",
                                 cycle_cnt, pss_sample_count);
                end else begin
                    sss_sample_count = sss_sample_count + 1;
                    if (!sss_ext_started) begin
                        cap_sss_first_i = u_dut.ext_m_tdata[15:0];
                        cap_sss_first_q = u_dut.ext_m_tdata[31:16];
                        sss_ext_started = 1;
                        $display("[TB] @%0d SSS first sample: I=%0d Q=%0d",
                                 cycle_cnt, $signed(u_dut.ext_m_tdata[15:0]),
                                 $signed(u_dut.ext_m_tdata[31:16]));
                    end
                    cap_sss_last_i = u_dut.ext_m_tdata[15:0];
                    cap_sss_last_q = u_dut.ext_m_tdata[31:16];
                    if (sss_sample_count == NSC)
                        $display("[TB] @%0d SSS window done: %0d samples",
                                 cycle_cnt, sss_sample_count);
                end
            end

            // CSV row: write on any event cycle
            if (dbg_frame_start_valid || dbg_peak_valid || dbg_slot_start_valid ||
                dbg_frac_cfo_valid || dbg_integer_cfo_valid || done_out) begin
                $fdisplay(csv_fd,
                    "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                    cycle_cnt,
                    dbg_frame_start_valid, dbg_frame_start_index,
                    dbg_peak_valid,        dbg_peak_index,
                    dbg_slot_start_valid,  dbg_slot_start_index,
                    dbg_frac_cfo_valid,    $signed(dbg_frac_cfo_word),
                    dbg_pss_start,         dbg_sss_start,
                    dbg_integer_cfo_valid, $signed(dbg_integer_cfo_word),
                    done_out,              error_code_out);
            end
        end
    end

    // -----------------------------------------------------------------------
    // write_results: write sim_out/rtl_results.txt summary for compare script
    // -----------------------------------------------------------------------
    task automatic write_results();
        // Detection OK: done fired with no error code
        automatic int det_ok = (done_seen && (cap_error_code == 4'd0)) ? 1 : 0;

        $fdisplay(res_fd, "# Phase 3 RTL Simulation Results");
        $fdisplay(res_fd, "# DUT: phase3_sync_top");
        $fdisplay(res_fd, "# Cycles simulated: %0d", cycle_cnt);
        $fdisplay(res_fd, "# done_seen=%0d  frame_start_seen=%0d  peak_seen=%0d",
                  done_seen, frame_start_seen, peak_seen);
        $fdisplay(res_fd, "DETECTION_STATUS %0d", det_ok);
        $fdisplay(res_fd, "RTL_FRAME_START_INDEX %0d",
                  frame_start_seen ? cap_frame_start_idx : -1);
        $fdisplay(res_fd, "RTL_PEAK_INDEX %0d",
                  peak_seen ? cap_peak_idx : -1);
        $fdisplay(res_fd, "RTL_SLOT_START_INDEX %0d",
                  slot_start_seen ? cap_slot_start_idx : -1);
        $fdisplay(res_fd, "RTL_FRAC_CFO_WORD %0d",
                  frac_cfo_seen ? $signed(cap_frac_cfo) : -99999);
        $fdisplay(res_fd, "RTL_PSS_START %0d",
                  slot_start_seen ? cap_pss_start : CP_LEN);
        $fdisplay(res_fd, "RTL_SSS_START %0d",
                  slot_start_seen ? cap_sss_start : (2*CP_LEN + NSC));
        $fdisplay(res_fd, "RTL_INTEGER_CFO_WORD %0d",
                  integer_cfo_seen ? $signed(cap_int_cfo) : -99999);
        $fdisplay(res_fd, "RTL_DONE %0d", done_seen);
        $fdisplay(res_fd, "RTL_ERROR_CODE %0d", cap_error_code);
        $fdisplay(res_fd, "RTL_PSS_SAMPLE_COUNT %0d", pss_sample_count);
        $fdisplay(res_fd, "RTL_SSS_SAMPLE_COUNT %0d", sss_sample_count);
        $fdisplay(res_fd, "RTL_PSS_FIRST_I %0d", $signed(cap_pss_first_i));
        $fdisplay(res_fd, "RTL_PSS_FIRST_Q %0d", $signed(cap_pss_first_q));
        $fdisplay(res_fd, "RTL_PSS_LAST_I %0d",  $signed(cap_pss_last_i));
        $fdisplay(res_fd, "RTL_PSS_LAST_Q %0d",  $signed(cap_pss_last_q));
        $fdisplay(res_fd, "RTL_SSS_FIRST_I %0d", $signed(cap_sss_first_i));
        $fdisplay(res_fd, "RTL_SSS_FIRST_Q %0d", $signed(cap_sss_first_q));
        $fdisplay(res_fd, "RTL_SSS_LAST_I %0d",  $signed(cap_sss_last_i));
        $fdisplay(res_fd, "RTL_SSS_LAST_Q %0d",  $signed(cap_sss_last_q));
        $fdisplay(res_fd, "RTL_MEYR_PEAK_INDEX %0d", cap_meyr_peak_idx);

        $fclose(csv_fd);
        $fclose(res_fd);
        $display("[TB] Results  → sim_out/rtl_results.txt");
        $display("[TB] CSV trace → logs/phase3_sync_rtl_dump.csv");
        $finish;
    endtask

    // -----------------------------------------------------------------------
    // VCD waveform dump
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("sim_out/phase3_sim.vcd");
        $dumpvars(0, phase3_sync_reference_compare_tb);
    end

endmodule
