`timescale 1ns/1ps

// frac_cfo_frame_corrector_top: AXI-Stream capture → frame detection →
//   CP timing sync → fractional CFO estimation → fractional CFO correction.
//
// Integrates (all sharing one iq_frame_buffer via FSM-muxed read port):
//   iq_frame_buffer      — AXI-Stream fill + random-access read
//   frame_detector       — sliding-window energy frame start
//   timing_frac_cfo_top  — CP autocorr + timing metric + CORDIC atan2
//   frac_cfo_corrector_top — NCO + complex_rotator (frac CFO removal)
//
// C reference (synchronization()):
//   frame_index  = frame_detector(...)
//   peak_lag     = VanDeBeekAutoCorrelation(...)
//   frac_phase   = -atan2(Q[peak_lag], I[peak_lag]) / (2π) [Q1.15]
//   corrected[n] = raw[slot_start+n] × exp(-j·2π·frac_phase·n)
//
// slot_start = frame_index + peak_lag (CP start, timing-corrected)
// Output: TOTAL_SAMPLES = NSC+CP_LEN corrected IQ samples, tlast on last.
//
// NCO step word: step = -frac_phase × 2^8  [A-FIX2]
//   frac_phase Q1.15: per-symbol total phase. Per-sample step = phase / NSC (NSC=256=2^8).
//   step = sign_ext({-frac_phase, 8'b0})
//
// NCO sequencing in S_LOAD_NCO (counted by nco_cnt, combinatorial decode):
//   nco_cnt=0: load_step=1 (latch step_word into NCO)
//   nco_cnt=1: phase_reset=1 (clear NCO accumulator)
//   nco_cnt=2..LATENCY+1: enable=1, wait for sincos_valid
//   nco_cnt=LATENCY+2: sincos_valid high → enter S_CORRECT
//
// Buffer playback (S_CORRECT): 1-cycle registered read latency, 1-deep hold
//   FIFO with back-pressure from m_axis.  can_issue fires when hold is free
//   (or being freed) and a pending read is not outstanding.
//   Throughput: 1 sample per 2 clocks (limited by buffer latency pipeline).
//
// done fires 1 clock after last corrector-input sample is accepted.
//   Since axis_complex_mult has 1-cycle output latency, m_axis_tlast fires
//   at the same clock as done (when m_axis_tready=1 throughout S_CORRECT).
//
// FSM: IDLE → FILL → FRAME_DET → TIMING_CFO → LOAD_NCO → CORRECT → DONE

module frac_cfo_frame_corrector_top #(
    parameter integer NSC          = 256,
    parameter integer CP_LEN       = 32,
    parameter integer OUTPUT_SAMPLES = 0,   // 0 = default to NSC+CP_LEN
    parameter integer BUF_AW       = 12,
    parameter integer ACC_WIDTH    = 40,
    parameter integer METRIC_WIDTH = 32,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer RESULT_WIDTH = 32,
    parameter integer PHASE_WIDTH  = 16,
    parameter integer POWER_WIDTH  = 33,
    parameter integer ENERGY_WIDTH = 40,
    parameter integer WINDOW_LEN   = 25,
    parameter integer HIT_COUNT    = 10,
    parameter integer THRESHOLD    = 10240000,
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer LATENCY         = 15,
    // Acquisition watchdog: counts cycles with no accepted sample during S_FILL.
    // 0 = disabled (default, preserves backward compatibility).
    // Non-zero N: if N consecutive cycles pass without a valid IQ sample accepted,
    // frame_error=1 and error_code=6 (INPUT_ACQ_TIMEOUT) are asserted and the FSM
    // exits to a safe terminal state.
    parameter integer ACQ_WATCHDOG_CYCLES = 0
) (
    input  wire                       aclk,
    input  wire                       aresetn,

    // AXI-Stream IQ input → iq_frame_buffer
    input  wire [31:0]                s_axis_tdata,
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,
    input  wire                       s_axis_tlast,

    // Control
    input  wire                       start,
    output reg                        done,
    output reg                        busy,
    output reg                        frame_error,
    // error_code: 0=none, 6=INPUT_ACQ_TIMEOUT (Step 43).
    // Stable after done; cleared when next transaction starts.
    output wire [3:0]                 error_code,

    // Frame detector run-time config (sampled at start)
    input  wire [ENERGY_WIDTH-1:0]    threshold_in,
    input  wire [6:0]                 window_len_in,
    input  wire [3:0]                 hit_count_in,

    // Status outputs (stable after done)
    output wire [BUF_AW-1:0]          frame_index,
    output wire                       frame_found,
    output wire [INDEX_WIDTH-1:0]     peak_lag,
    output wire [METRIC_WIDTH-1:0]    peak_metric,
    output wire [PHASE_WIDTH-1:0]     frac_phase,
    output wire                       frac_phase_valid,

    // Corrected IQ output: NSC+CP_LEN samples, tlast on last
    output wire [31:0]                m_axis_tdata,
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,
    output wire                       m_axis_tlast
);

    localparam integer TOTAL_SAMPLES = (OUTPUT_SAMPLES > 0) ? OUTPUT_SAMPLES : (NSC + CP_LEN);
    localparam integer PLAY_CNT_W    = $clog2(TOTAL_SAMPLES + 1);
    localparam integer NCO_WAIT      = LATENCY + 2; // nco_cnt value at sincos_valid

    localparam [2:0]
        S_IDLE       = 3'd0,
        S_FILL       = 3'd1,
        S_FRAME_DET  = 3'd2,
        S_TIMING_CFO = 3'd3,
        S_LOAD_NCO   = 3'd4,
        S_CORRECT    = 3'd5,
        S_DONE       = 3'd6;

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // Acquisition watchdog (Step 43)
    // -----------------------------------------------------------------------
    // iq_accept_w: AXI handshake — one sample accepted this cycle.
    // acq_wdog_r : inactivity counter; counts cycles with no accepted sample in S_FILL.
    // acq_timeout_w: fires when counter reaches ACQ_WATCHDOG_CYCLES-1 and no sample
    //   is being accepted. (ACQ_WATCHDOG_CYCLES>0) is a constant, so when disabled
    //   the entire expression elaborates to 0 (dead code eliminated).
    wire       iq_accept_w   = s_axis_tvalid && s_axis_tready;
    reg [15:0] acq_wdog_r;
    reg [3:0]  error_code_r;
    wire       acq_timeout_w = (ACQ_WATCHDOG_CYCLES > 0) &&
                                (state == S_FILL) &&
                                !iq_accept_w &&
                                (acq_wdog_r == ACQ_WATCHDOG_CYCLES[15:0] - 16'd1);

    assign error_code = error_code_r;

    // Counter: resets outside S_FILL and on accepted sample; counts idle cycles.
    always @(posedge aclk) begin
        if (!aresetn) begin
            acq_wdog_r <= 16'd0;
        end else if (state == S_FILL) begin
            if (iq_accept_w || acq_timeout_w)
                acq_wdog_r <= 16'd0;
            else if (ACQ_WATCHDOG_CYCLES > 0)
                acq_wdog_r <= acq_wdog_r + 16'd1;
        end else begin
            acq_wdog_r <= 16'd0;
        end
    end

    // -----------------------------------------------------------------------
    // iq_capture_pingpong control (H1a: continuous dual-buffer front-end —
    // capture runs continuously; the FSM consumes whole-frame buffers via the
    // buf_ready/proc_take/proc_free handoff, so the chain no longer goes deaf
    // during processing and can run back-to-back slots.)
    // -----------------------------------------------------------------------
    localparam integer CAP_AW = (BUF_AW < 13) ? 13 : BUF_AW; // hold full frame (<=4160) until tlast
    wire               cap_buf_ready;
    wire [CAP_AW:0]    cap_buf_len;
    reg                proc_take_r;
    reg                proc_free_r;

    // Shared buffer read port (muxed by FSM)
    // BUGFIX (multi-frame seam): the S_CORRECT read address slot_start_r+play_rd_ptr
    //   can reach the frame TAIL near physical address 4159, which exceeds the
    //   12-bit BUF_AW range and WRAPPED back to low addresses -> last-127-sample
    //   corruption on every frame whose slot_start pushed the tail past 4095.
    //   The capture buffer is CAP_AW (13b, 8192-deep) and the frame physically
    //   lives in [0..4159], so the FSM's shared read-address path is widened to
    //   CAP_AW. The fd/tfc sub-cores and the frame_index OUTPUT port stay BUF_AW
    //   (frame is always detected within the first 4096 since capture writes from
    //   address 0); their addresses are zero-extended into this wider bus.
    reg  [CAP_AW-1:0] buf_rd_addr;
    reg                buf_rd_en;
    wire [31:0]        buf_rd_data;
    wire signed [15:0] buf_rd_data_I = $signed(buf_rd_data[15:0]);
    wire signed [15:0] buf_rd_data_Q = $signed(buf_rd_data[31:16]);

    // -----------------------------------------------------------------------
    // frame_detector wires
    // -----------------------------------------------------------------------
    reg               fd_start_r;
    wire [BUF_AW-1:0] fd_buf_rd_addr;
    wire              fd_buf_rd_en;
    wire              fd_done;
    wire [BUF_AW-1:0] fd_frame_index;
    wire              fd_frame_found;

    // -----------------------------------------------------------------------
    // timing_frac_cfo_top wires
    // -----------------------------------------------------------------------
    reg               tfc_start_r;
    wire [BUF_AW-1:0] tfc_buf_rd_addr;
    wire              tfc_buf_rd_en;
    wire              tfc_done;

    // -----------------------------------------------------------------------
    // Latched results
    // -----------------------------------------------------------------------
    reg [BUF_AW-1:0]     frame_index_r;  // detected start, within first 4096 (->u_tfc base_addr)
    reg [INDEX_WIDTH-1:0] peak_lag_r;
    reg [PHASE_WIDTH-1:0] frac_phase_r;
    reg [CAP_AW-1:0]     slot_start_r;   // frame_index_r + peak_lag_r (13b: tail may exceed 4095)

    // -----------------------------------------------------------------------
    // NCO / corrector control (combinatorial decode from nco_cnt)
    // -----------------------------------------------------------------------
    reg [4:0] nco_cnt;   // declared first; used in combinatorial wires below

    wire nco_load_step_w   = (state == S_LOAD_NCO) && (nco_cnt == 5'd0);
    wire nco_phase_reset_w = (state == S_LOAD_NCO) && (nco_cnt == 5'd1);
    wire nco_enable_w      = ((state == S_LOAD_NCO) && (nco_cnt >= 5'd2)) ||
                              (state == S_CORRECT);

    // step_word = +frac_phase × 2^8: frac_phase = atan2(P_Q,P_I)/π×2^15, so
    // +frac_phase×256/2^32 = frac_cfo/NSC cycles/sample (correct removal direction).
    wire signed [31:0] step_word_w = {{8{frac_phase_r[PHASE_WIDTH-1]}}, frac_phase_r, 8'h00};

    wire               sincos_valid;
    wire               corr_tready;

    // -----------------------------------------------------------------------
    // Correction playback state
    // -----------------------------------------------------------------------
    // H1b: pipelined readout — issue a buffer read EVERY cycle (1 sample/clock)
    // into a 2-deep output FIFO (head=play_hold, 2nd=play_hold2). 1-cycle BRAM
    // read latency + corrector back-pressure absorbed by the FIFO. (The int-rotator
    // input skid in the wrapper absorbs the NCO warm-up so this gap-free feed no
    // longer drops M_AXIS beats — P5-CONT-NIGHTLY mout=4032.)
    // -----------------------------------------------------------------------
    reg [PLAY_CNT_W-1:0] play_rd_ptr;    // next sample index to issue (0..TOTAL_SAMPLES)
    reg                  play_rd_pend;   // read issued last cycle -> data valid this cycle
    reg                  play_rd_last;   // the in-flight read is for the last sample
    reg                  play_hold_valid; // FIFO head (-> corrector)
    reg [31:0]           play_hold_data;
    reg                  play_hold_last;
    reg                  play_hold2_valid; // FIFO 2nd entry
    reg [31:0]           play_hold2_data;
    reg                  play_hold2_last;

    wire corr_accept = play_hold_valid && corr_tready;          // deq head
    wire fifo_enq    = play_rd_pend;                            // read data arriving
    wire [1:0] fifo_occ_now = {1'b0, play_hold_valid} + {1'b0, play_hold2_valid};
    wire [2:0] fifo_occ_next = {1'b0, fifo_occ_now}
                               + {2'b0, (fifo_enq    ? 1'b1 : 1'b0)}
                               - {2'b0, (corr_accept ? 1'b1 : 1'b0)};
    wire can_issue   = (state == S_CORRECT) &&
                       (play_rd_ptr < TOTAL_SAMPLES) &&
                       (fifo_occ_next < 3'd2);

    // =========================================================================
    // iq_frame_buffer
    // =========================================================================
    iq_capture_pingpong #(
        .DATA_WIDTH(32),
        .CAP_AW    (CAP_AW)
    ) u_cap (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),
        .buf_ready     (cap_buf_ready),
        .buf_len       (cap_buf_len),
        .proc_take     (proc_take_r),
        .proc_free     (proc_free_r),
        .rd_en         (buf_rd_en),
        .rd_addr       (buf_rd_addr),     // CAP_AW-wide read address (reaches full frame tail)
        .rd_data       (buf_rd_data),
        .both_full     (),
        .cap_overflow  ()
    );

    // =========================================================================
    // frame_detector
    // =========================================================================
    frame_detector #(
        .DATA_WIDTH   (32),
        .ADDR_WIDTH   (BUF_AW),
        .INDEX_WIDTH  (BUF_AW),
        .POWER_WIDTH  (POWER_WIDTH),
        .ENERGY_WIDTH (ENERGY_WIDTH),
        .WINDOW_LEN   (WINDOW_LEN),
        .HIT_COUNT    (HIT_COUNT),
        .THRESHOLD    (THRESHOLD)
    ) u_fd (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .start         (fd_start_r),
        .threshold_in  (threshold_in),
        .window_len_in (window_len_in),
        .hit_count_in  (hit_count_in),
        .search_base   ({BUF_AW{1'b0}}),
        .search_len    ({1'b1, {BUF_AW{1'b0}}}),
        .buf_rd_addr   (fd_buf_rd_addr),
        .buf_rd_en     (fd_buf_rd_en),
        .buf_rd_data_I (buf_rd_data[15:0]),
        .buf_rd_data_Q (buf_rd_data[31:16]),
        .frame_index   (fd_frame_index),
        .frame_found   (fd_frame_found),
        .done          (fd_done),
        .busy          ()
    );

    assign frame_index = fd_frame_index;
    assign frame_found = fd_frame_found;

    // =========================================================================
    // frame_frac_cfo_top
    // =========================================================================
    frame_frac_cfo_top #(
        .NSC         (NSC),
        .CP_LEN      (CP_LEN),
        .ADDR_WIDTH  (BUF_AW),
        .ACC_WIDTH   (ACC_WIDTH),
        .METRIC_WIDTH(METRIC_WIDTH),
        .INDEX_WIDTH (INDEX_WIDTH),
        .RESULT_WIDTH(RESULT_WIDTH),
        .PHASE_WIDTH (PHASE_WIDTH)
    ) u_tfc (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .start           (tfc_start_r),
        .base_addr       (frame_index_r),
        .done            (tfc_done),
        .busy            (),
        .buf_rd_addr     (tfc_buf_rd_addr),
        .buf_rd_en       (tfc_buf_rd_en),
        .buf_rd_data_I   (buf_rd_data_I),
        .buf_rd_data_Q   (buf_rd_data_Q),
        .peak_lag        (peak_lag),
        .peak_metric     (peak_metric),
        .peak_corr_i     (),
        .peak_corr_q     (),
        .peak_energy     (),
        .frac_phase      (frac_phase),
        .frac_phase_valid(frac_phase_valid)
    );

    // =========================================================================
    // frac_cfo_corrector_top
    // =========================================================================
    frac_cfo_corrector_top #(
        .DATA_WIDTH         (32),
        .COMPONENT_WIDTH    (16),
        .SHIFT              (15),
        .NCO_PHASE_WIDTH    (NCO_PHASE_WIDTH),
        .CORDIC_PHASE_WIDTH (PHASE_WIDTH),
        .ROTATOR_COEFF_WIDTH(16),
        .LATENCY            (LATENCY)
    ) u_corr (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .load_step        (nco_load_step_w),
        .step_word        (step_word_w),
        .phase_reset      (nco_phase_reset_w),
        .enable           (nco_enable_w),
        .s_axis_iq_tdata  (play_hold_data),
        .s_axis_iq_tvalid (play_hold_valid),
        .s_axis_iq_tready (corr_tready),
        .s_axis_iq_tlast  (play_hold_last),
        .m_axis_tdata     (m_axis_tdata),
        .m_axis_tvalid    (m_axis_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tlast     (m_axis_tlast),
        .phase_acc        (),
        .sin_out          (),
        .cos_out          (),
        .sincos_valid     (sincos_valid)
    );

    // =========================================================================
    // Buffer read-port mux
    // =========================================================================
    always @(*) begin
        case (state)
            S_FRAME_DET: begin
                buf_rd_en   = fd_buf_rd_en;
                buf_rd_addr = {{(CAP_AW-BUF_AW){1'b0}}, fd_buf_rd_addr};  // 12b -> 13b zero-ext
            end
            S_TIMING_CFO: begin
                buf_rd_en   = tfc_buf_rd_en;
                buf_rd_addr = {{(CAP_AW-BUF_AW){1'b0}}, tfc_buf_rd_addr}; // 12b -> 13b zero-ext
            end
            S_CORRECT: begin
                buf_rd_en   = can_issue;
                // 13b sum: slot_start_r (CAP_AW) + play_rd_ptr reaches the frame tail
                // (up to ~4159) WITHOUT wrapping at 4095 (the multi-frame bug).
                buf_rd_addr = slot_start_r + {{(CAP_AW-PLAY_CNT_W){1'b0}}, play_rd_ptr};
            end
            default: begin
                buf_rd_en   = 1'b0;
                buf_rd_addr = {CAP_AW{1'b0}};
            end
        endcase
    end

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge aclk) begin
        if (!aresetn) begin
            state             <= S_IDLE;
            done              <= 1'b0;
            busy              <= 1'b0;
            frame_error       <= 1'b0;
            error_code_r      <= 4'd0;
            proc_take_r       <= 1'b0;
            proc_free_r       <= 1'b0;
            fd_start_r        <= 1'b0;
            tfc_start_r       <= 1'b0;
            frame_index_r     <= {BUF_AW{1'b0}};
            peak_lag_r        <= {INDEX_WIDTH{1'b0}};
            frac_phase_r      <= {PHASE_WIDTH{1'b0}};
            slot_start_r      <= {CAP_AW{1'b0}};
            nco_cnt           <= 5'd0;
            play_rd_ptr       <= {PLAY_CNT_W{1'b0}};
            play_rd_pend      <= 1'b0;
            play_rd_last      <= 1'b0;
            play_hold_valid   <= 1'b0;
            play_hold_data    <= 32'b0;
            play_hold_last    <= 1'b0;
            play_hold2_valid  <= 1'b0;
            play_hold2_data   <= 32'b0;
            play_hold2_last   <= 1'b0;
        end else begin
            done              <= 1'b0;
            proc_take_r       <= 1'b0;
            proc_free_r       <= 1'b0;
            fd_start_r        <= 1'b0;
            tfc_start_r       <= 1'b0;

            case (state)

                S_IDLE: begin
                    frame_error <= 1'b0;
                    if (start && !busy) begin
                        busy              <= 1'b1;
                        error_code_r      <= 4'd0;  // clear previous error code
                        state             <= S_FILL;  // = S_WAIT_BUF: capture is
                                                      //   continuous in u_cap now
                    end
                end

                // S_FILL repurposed as S_WAIT_BUF: capture runs continuously in
                // u_cap; here we wait for a whole-frame buffer and claim it.
                S_FILL: begin
                    if (acq_timeout_w) begin
                        // Inactivity watchdog expired waiting for a frame
                        frame_error  <= 1'b1;
                        error_code_r <= 4'd6;   // INPUT_ACQ_TIMEOUT
                        state        <= S_DONE;
                    end else if (cap_buf_ready) begin
                        proc_take_r <= 1'b1;    // claim the captured buffer
                        fd_start_r  <= 1'b1;
                        state       <= S_FRAME_DET;
                    end
                end

                S_FRAME_DET: begin
                    if (fd_done) begin
                        if (fd_frame_found) begin
                            frame_index_r <= fd_frame_index;
                            tfc_start_r   <= 1'b1;
                            state         <= S_TIMING_CFO;
                        end else begin
                            frame_error   <= 1'b1;
                            state         <= S_DONE;
                        end
                    end
                end

                S_TIMING_CFO: begin
                    if (tfc_done) begin
                        peak_lag_r   <= peak_lag;
                        frac_phase_r <= frac_phase;
                        // CAP_AW-wide sum: explicit zero-extension so the slot start
                        // is carried at 13b (frame tail can exceed 4095 -> no wrap).
                        slot_start_r <= {{(CAP_AW-BUF_AW){1'b0}}, frame_index_r}
                                        + {{(CAP_AW-INDEX_WIDTH){1'b0}}, peak_lag};
                        nco_cnt      <= 5'd0;
                        state        <= S_LOAD_NCO;
                    end
                end

                S_LOAD_NCO: begin
                    if (nco_cnt == NCO_WAIT) begin
                        // sincos_valid is now asserted; initialize playback
                        play_rd_ptr      <= {PLAY_CNT_W{1'b0}};
                        play_rd_pend     <= 1'b0;
                        play_rd_last     <= 1'b0;
                        play_hold_valid  <= 1'b0;
                        play_hold_data   <= 32'b0;
                        play_hold_last   <= 1'b0;
                        play_hold2_valid <= 1'b0;
                        play_hold2_data  <= 32'b0;
                        play_hold2_last  <= 1'b0;
                        state            <= S_CORRECT;
                    end else begin
                        nco_cnt <= nco_cnt + 1;
                    end
                end

                S_CORRECT: begin
                    // ---------------------------------------------------
                    // H1b 2-deep output FIFO (head=play_hold, 2nd=play_hold2).
                    // enq = play_rd_pend (read data arriving), deq = corr_accept.
                    // A read is issued every cycle the FIFO has room (1 sample/clk).
                    // ---------------------------------------------------
                    if (corr_accept && fifo_enq) begin
                        if (play_hold2_valid) begin
                            play_hold_data  <= play_hold2_data;  // head <= 2nd
                            play_hold_last  <= play_hold2_last;
                            play_hold2_data <= buf_rd_data;      // 2nd <= new
                            play_hold2_last <= play_rd_last;
                        end else begin
                            play_hold_data  <= buf_rd_data;      // head <= new
                            play_hold_last  <= play_rd_last;
                        end
                    end else if (corr_accept) begin
                        play_hold_data   <= play_hold2_data;     // pop head: head <= 2nd
                        play_hold_last   <= play_hold2_last;
                        play_hold_valid  <= play_hold2_valid;
                        play_hold2_valid <= 1'b0;
                    end else if (fifo_enq) begin
                        if (play_hold_valid) begin               // push new -> 2nd
                            play_hold2_data  <= buf_rd_data;
                            play_hold2_last  <= play_rd_last;
                            play_hold2_valid <= 1'b1;
                        end else begin                           // push new -> head
                            play_hold_data   <= buf_rd_data;
                            play_hold_last   <= play_rd_last;
                            play_hold_valid  <= 1'b1;
                        end
                    end

                    if (can_issue) begin
                        play_rd_pend <= 1'b1;
                        play_rd_last <= (play_rd_ptr == TOTAL_SAMPLES - 1);
                        play_rd_ptr  <= play_rd_ptr + 1;
                    end else begin
                        play_rd_pend <= 1'b0;
                    end

                    // Last corrector-input sample accepted → done
                    if (corr_accept && play_hold_last) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done        <= 1'b1;
                    busy        <= 1'b0;
                    proc_free_r <= 1'b1;   // release the processed buffer to u_cap
                    state       <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

`ifdef TIMING_PROBE
    integer fcfc_probe_cnt;
    always @(posedge aclk) begin
        if (!aresetn) begin
            fcfc_probe_cnt <= 0;
        end else if (fcfc_probe_cnt < 12 && tfc_start_r) begin
            // start of timing scan
            $display("[FCFC] t=%0t tfc_start fired: state=%0d", $time, state);
            fcfc_probe_cnt <= fcfc_probe_cnt + 1;
        end else if (fcfc_probe_cnt >= 1 && fcfc_probe_cnt < 30) begin
            $display("[FCFC] t=%0t state=%0d buf_rd_en=%0b buf_rd_addr=%0d tfc_buf_rd_en=%0b",
                     $time, state, buf_rd_en, buf_rd_addr, tfc_buf_rd_en);
            fcfc_probe_cnt <= fcfc_probe_cnt + 1;
        end
    end
`endif

endmodule
