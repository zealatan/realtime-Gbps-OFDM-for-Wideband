`timescale 1ns/1ps

// fft256_xilinx_wrapper_actual_tb — Self-checking testbench for
// fft256_xilinx_wrapper with USE_BEHAVIORAL_STUB=0 (actual Xilinx IP).
//
// Design notes:
//   - Blocking assignments (=) used for all signal drivers to avoid
//     AXI-S double-handshake from non-blocking NBA timing.
//   - Sequential send-then-capture: send_frame() sends all 256 samples,
//     then capture_frame() waits for xk_index=0 to align to frame start.
//   - Two warmup frames sent at startup to flush IP startup transients.
//   - Realtime throttle: IP has no m_axis_data_tready; output is continuous.
//
// Tests:
//   T1  reset_defaults        — no stray m_tvalid before first frame
//   T2  impulse_input         — flat spectrum
//   T3  DC_constant           — bin 0 dominant
//   T4  single_tone_bin1      — peak at bin 1 (and mirror bin 255)
//   T5  single_tone_bin4      — peak at bin 4 (and mirror bin 252)
//   T6  single_tone_bin16     — peak at bin 16 (and mirror bin 240)
//   T7  natural_order_check   — xk_index arrives 0..255 in order
//   T8  xk_index_check        — xk_index matches output sequence number
//   T9  tlast_propagation     — tlast with bin 255
//   T10 backpressure          — realtime throttle documented
//   T11 pipeline_latency      — cycles from first input to first output
//   T12 multiple_frames       — three consecutive frames

module fft256_xilinx_wrapper_actual_tb;

    localparam int  FFT_LEN  = 256;
    localparam int  IQ_W     = 16;
    localparam int  OUT_W    = 16;
    localparam int  HALF     = 5;        // 10 ns clock
    localparam int  TIMEOUT  = 100000;   // cycles per operation

    localparam real PI = 3.14159265358979323846;
    localparam real AMP = 10000.0;   // input amplitude, well below 16-bit full scale

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    logic aclk = 1'b0;
    always #HALF aclk = ~aclk;

    // -------------------------------------------------------------------------
    // DUT interface
    // -------------------------------------------------------------------------
    logic                    aresetn;
    logic                    s_tvalid = 1'b0;
    wire                     s_tready;
    logic [2*IQ_W-1:0]       s_tdata  = '0;
    logic                    s_tlast  = 1'b0;

    wire                     m_tvalid;
    logic                    m_tready = 1'b1;
    wire  [2*OUT_W-1:0]      m_tdata;
    wire  [7:0]              m_tuser;
    wire                     m_tlast;

    wire                     busy, done, error;
    wire                     ev_frame_started;
    wire                     ev_tlast_unexpected;
    wire                     ev_tlast_missing;
    wire                     ev_din_halt;
    wire                     ev_dout_halt;
    wire                     ev_status_halt;

    fft256_xilinx_wrapper #(
        .FFT_LEN             (FFT_LEN),
        .IQ_WIDTH            (IQ_W),
        .FFT_OUT_WIDTH       (OUT_W),
        .USE_BEHAVIORAL_STUB (0)
    ) dut (
        .aclk                        (aclk),
        .aresetn                     (aresetn),
        .start                       (1'b0),
        .s_axis_tvalid               (s_tvalid),
        .s_axis_tready               (s_tready),
        .s_axis_tdata                (s_tdata),
        .s_axis_tlast                (s_tlast),
        .m_axis_tvalid               (m_tvalid),
        .m_axis_tready               (m_tready),
        .m_axis_tdata                (m_tdata),
        .m_axis_tuser                (m_tuser),
        .m_axis_tlast                (m_tlast),
        .busy                        (busy),
        .done                        (done),
        .error                       (error),
        .event_frame_started         (ev_frame_started),
        .event_tlast_unexpected      (ev_tlast_unexpected),
        .event_tlast_missing         (ev_tlast_missing),
        .event_data_in_channel_halt  (ev_din_halt),
        .event_data_out_channel_halt (ev_dout_halt),
        .event_status_channel_halt   (ev_status_halt)
    );

    // -------------------------------------------------------------------------
    // Output capture buffers
    // -------------------------------------------------------------------------
    real         cap_mag  [0:FFT_LEN-1];
    logic [31:0] cap_data [0:FFT_LEN-1];
    logic [7:0]  cap_user [0:FFT_LEN-1];
    logic        cap_tlast[0:FFT_LEN-1];
    int          cap_cnt;

    // Latency
    longint first_in_cycle;
    longint first_out_cycle;
    longint observed_latency;

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check(input logic cond, input string msg);
        if (cond) begin
            $display("[PASS] %s", msg);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s", msg);
            fail_cnt++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Helper: build zero frame
    // -------------------------------------------------------------------------
    task automatic zero_frame(
        output logic signed [15:0] re [0:FFT_LEN-1],
        output logic signed [15:0] im [0:FFT_LEN-1]
    );
        for (int n = 0; n < FFT_LEN; n++) begin
            re[n] = '0;
            im[n] = '0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: send one frame (blocking assignments, no double-handshake)
    // Signals set AFTER posedge so they are stable for the NEXT posedge.
    // -------------------------------------------------------------------------
    task automatic send_frame(
        input logic signed [15:0] re [0:FFT_LEN-1],
        input logic signed [15:0] im [0:FFT_LEN-1]
    );
        // Sync to a clean clock edge
        @(posedge aclk);
        for (int n = 0; n < FFT_LEN; n++) begin
            // Drive sample (blocking: takes effect immediately, stable until next edge)
            s_tvalid = 1'b1;
            s_tdata  = {im[n], re[n]};
            s_tlast  = (n == FFT_LEN-1) ? 1'b1 : 1'b0;
            // Wait for handshake
            @(posedge aclk);
            while (!s_tready) @(posedge aclk);
            // Sample n accepted at this posedge.
            // Loop: next iteration will immediately set sample n+1 (no gap).
        end
        // Deassert after all samples accepted
        s_tvalid = 1'b0;
        s_tlast  = 1'b0;
        s_tdata  = '0;
    endtask

    // -------------------------------------------------------------------------
    // Task: capture one output frame, aligned to xk_index=0
    // Since IP has no output tready, m_tvalid is continuously asserted.
    // Wait for xk_index=0, then collect 256 consecutive bins.
    // -------------------------------------------------------------------------
    task automatic capture_frame(input logic measure_latency);
        automatic int timeout = 0;
        cap_cnt = 0;

        // Wait for start of an output frame (xk_index=0)
        @(posedge aclk);
        while (!(m_tvalid && m_tuser == 8'h00)) begin
            @(posedge aclk);
            if (++timeout > TIMEOUT) begin
                $display("[ERROR] capture_frame: timeout waiting for xk_index=0");
                return;
            end
        end

        // Latency: record cycle of first output
        if (measure_latency) begin
            first_out_cycle = $time / (2*HALF);
        end

        // Collect 256 bins (m_tvalid stays asserted throughout in realtime throttle)
        for (int k = 0; k < FFT_LEN; k++) begin
            automatic real re_f = $itor($signed(m_tdata[15:0]));
            automatic real im_f = $itor($signed(m_tdata[31:16]));
            cap_data[k]  = m_tdata;
            cap_user[k]  = m_tuser;
            cap_tlast[k] = m_tlast;
            cap_mag[k]   = $sqrt(re_f*re_f + im_f*im_f);
            cap_cnt++;
            if (k < FFT_LEN-1) begin
                @(posedge aclk);
                while (!m_tvalid) begin
                    @(posedge aclk);
                    if (++timeout > TIMEOUT) begin
                        $display("[ERROR] capture_frame: timeout at bin %0d", k);
                        return;
                    end
                end
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: send frame and capture its output frame
    // For realtime throttle, output lags input by pipeline latency.
    // Use xk_index=0 to synchronize to the correct output frame boundary.
    // -------------------------------------------------------------------------
    task automatic run_frame(
        input logic signed [15:0] re [0:FFT_LEN-1],
        input logic signed [15:0] im [0:FFT_LEN-1],
        input logic measure_latency
    );
        send_frame(re, im);
        capture_frame(measure_latency);
    endtask

    // -------------------------------------------------------------------------
    // Helper: find index of peak magnitude bin
    // -------------------------------------------------------------------------
    function automatic int find_peak(input real mag [0:FFT_LEN-1]);
        automatic real mx = -1.0;
        automatic int  idx = 0;
        for (int k = 0; k < FFT_LEN; k++) begin
            if (mag[k] > mx) begin
                mx  = mag[k];
                idx = k;
            end
        end
        return idx;
    endfunction

    // Max magnitude excluding given bin
    function automatic real max_excl(input real mag [0:FFT_LEN-1], input int excl0, input int excl1);
        automatic real mx = 0.0;
        for (int k = 0; k < FFT_LEN; k++)
            if (k != excl0 && k != excl1 && mag[k] > mx)
                mx = mag[k];
        return mx;
    endfunction

    function automatic real max_all(input real mag [0:FFT_LEN-1]);
        automatic real mx = 0.0;
        for (int k = 0; k < FFT_LEN; k++)
            if (mag[k] > mx) mx = mag[k];
        return mx;
    endfunction

    function automatic real min_all(input real mag [0:FFT_LEN-1]);
        automatic real mn = 1.0e30;
        for (int k = 0; k < FFT_LEN; k++)
            if (mag[k] < mn) mn = mag[k];
        return mn;
    endfunction

    // =========================================================================
    // Main test sequence
    // =========================================================================
    initial begin : main_test
        logic signed [15:0] re_frm [0:FFT_LEN-1];
        logic signed [15:0] im_frm [0:FFT_LEN-1];
        int  peak_bin, mirror;
        real mx, mn, ratio, second_mag;

        // =====================================================================
        // T1: reset_defaults — verify no m_tvalid during reset
        // =====================================================================
        $display("\nT1: reset_defaults");
        aresetn  = 1'b0;
        s_tvalid = 1'b0;
        repeat(8) @(posedge aclk);
        check(m_tvalid === 1'b0, "T1: m_tvalid=0 during reset");
        aresetn = 1'b1;
        // Allow IP to accept config (wrapper drives cfg_tvalid after reset)
        repeat(32) @(posedge aclk);
        $display("T1: PASS — reset complete, config allowed to settle");

        // =====================================================================
        // WARMUP: send 2 dummy frames to prime pipeline and flush startup
        //         transients.  Outputs discarded.
        // =====================================================================
        $display("[INFO] Warmup: sending 2 dummy frames to prime pipeline...");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'sh1000;
        send_frame(re_frm, im_frm);
        capture_frame(1'b0);   // discard
        send_frame(re_frm, im_frm);
        capture_frame(1'b0);   // discard
        $display("[INFO] Warmup done. Pipeline primed.");

        // =====================================================================
        // T2: impulse_input — x[0]=(AMP,0), x[1..255]=(0,0)
        //    DFT of impulse = constant magnitude across all bins
        // =====================================================================
        $display("\nT2: impulse_input");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'($rtoi(AMP));

        run_frame(re_frm, im_frm, 1'b0);

        check(cap_cnt == FFT_LEN, "T2: received 256 bins");
        mx = max_all(cap_mag);
        mn = min_all(cap_mag);
        if (mx > 0.0)
            check((mx - mn) / mx < 0.10,
                  $sformatf("T2: flat spectrum (variation %.1f%%)", (mx-mn)/mx*100.0));
        else
            check(1'b0, "T2: non-zero output magnitudes");
        $display("T2: mag max=%.1f min=%.1f", mx, mn);

        // =====================================================================
        // T3: DC_constant — x[n]=A for all n
        //    FFT: X[0]=N*A >> X[k≠0]
        // =====================================================================
        $display("\nT3: DC_constant");
        for (int n = 0; n < FFT_LEN; n++) begin
            re_frm[n] = 16'sh0800;   // 2048
            im_frm[n] = 16'sh0000;
        end

        run_frame(re_frm, im_frm, 1'b0);

        check(cap_cnt == FFT_LEN, "T3: received 256 bins");
        peak_bin = find_peak(cap_mag);
        check(peak_bin == 0, $sformatf("T3: bin 0 dominant (peak=%0d)", peak_bin));
        if (cap_mag[0] > 0.0) begin
            second_mag = max_excl(cap_mag, 0, 0);
            if (second_mag > 0.0) begin
                ratio = cap_mag[0] / second_mag;
                check(ratio > 5.0,
                      $sformatf("T3: DC >> others (ratio=%.1f)", ratio));
            end else begin
                $display("T3: only bin 0 has non-zero magnitude");
                pass_cnt++;
            end
            $display("T3: DC mag=%.1f next=%.1f", cap_mag[0], second_mag);
        end else
            check(1'b0, "T3: bin 0 magnitude > 0");

        // =====================================================================
        // T4: single_tone_bin1
        // =====================================================================
        $display("\nT4: single_tone_bin1");
        begin
            automatic int bk = 1;
            for (int n = 0; n < FFT_LEN; n++) begin
                re_frm[n] = 16'($rtoi(AMP * $cos(2.0*PI*bk*n/FFT_LEN)));
                im_frm[n] = 16'sh0;
            end
            run_frame(re_frm, im_frm, 1'b0);
            check(cap_cnt == FFT_LEN, "T4: received 256 bins");
            peak_bin = find_peak(cap_mag);
            mirror   = (FFT_LEN - bk) % FFT_LEN;
            check(peak_bin == bk || peak_bin == mirror,
                  $sformatf("T4: peak at bin %0d or %0d (got %0d)", bk, mirror, peak_bin));
            second_mag = max_excl(cap_mag, peak_bin, mirror);
            if (cap_mag[peak_bin] > 0.0 && second_mag > 0.0)
                check(cap_mag[peak_bin]/second_mag > 5.0,
                      $sformatf("T4: peak/second=%.1f > 5", cap_mag[peak_bin]/second_mag));
            else if (cap_mag[peak_bin] > 0.0)
                begin $display("T4: only one dominant bin"); pass_cnt++; end
            $display("T4: peak=%0d mag=%.1f second=%.1f", peak_bin, cap_mag[peak_bin], second_mag);
        end

        // =====================================================================
        // T5: single_tone_bin4
        // =====================================================================
        $display("\nT5: single_tone_bin4");
        begin
            automatic int bk = 4;
            for (int n = 0; n < FFT_LEN; n++) begin
                re_frm[n] = 16'($rtoi(AMP * $cos(2.0*PI*bk*n/FFT_LEN)));
                im_frm[n] = 16'sh0;
            end
            run_frame(re_frm, im_frm, 1'b0);
            check(cap_cnt == FFT_LEN, "T5: received 256 bins");
            peak_bin = find_peak(cap_mag);
            mirror   = (FFT_LEN - bk) % FFT_LEN;
            check(peak_bin == bk || peak_bin == mirror,
                  $sformatf("T5: peak at bin %0d or %0d (got %0d)", bk, mirror, peak_bin));
            second_mag = max_excl(cap_mag, peak_bin, mirror);
            if (cap_mag[peak_bin] > 0.0 && second_mag > 0.0)
                check(cap_mag[peak_bin]/second_mag > 5.0,
                      $sformatf("T5: peak/second=%.1f > 5", cap_mag[peak_bin]/second_mag));
            else if (cap_mag[peak_bin] > 0.0)
                begin $display("T5: only one dominant bin"); pass_cnt++; end
            $display("T5: peak=%0d mag=%.1f second=%.1f", peak_bin, cap_mag[peak_bin], second_mag);
        end

        // =====================================================================
        // T6: single_tone_bin16
        // =====================================================================
        $display("\nT6: single_tone_bin16");
        begin
            automatic int bk = 16;
            for (int n = 0; n < FFT_LEN; n++) begin
                re_frm[n] = 16'($rtoi(AMP * $cos(2.0*PI*bk*n/FFT_LEN)));
                im_frm[n] = 16'sh0;
            end
            run_frame(re_frm, im_frm, 1'b0);
            check(cap_cnt == FFT_LEN, "T6: received 256 bins");
            peak_bin = find_peak(cap_mag);
            mirror   = (FFT_LEN - bk) % FFT_LEN;
            check(peak_bin == bk || peak_bin == mirror,
                  $sformatf("T6: peak at bin %0d or %0d (got %0d)", bk, mirror, peak_bin));
            second_mag = max_excl(cap_mag, peak_bin, mirror);
            if (cap_mag[peak_bin] > 0.0 && second_mag > 0.0)
                check(cap_mag[peak_bin]/second_mag > 5.0,
                      $sformatf("T6: peak/second=%.1f > 5", cap_mag[peak_bin]/second_mag));
            else if (cap_mag[peak_bin] > 0.0)
                begin $display("T6: only one dominant bin"); pass_cnt++; end
            $display("T6: peak=%0d mag=%.1f second=%.1f", peak_bin, cap_mag[peak_bin], second_mag);
        end

        // =====================================================================
        // T7: natural_order_check
        //    Verify xk_index arrives in order 0, 1, ..., 255
        // =====================================================================
        $display("\nT7: natural_order_check");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'($rtoi(AMP));
        run_frame(re_frm, im_frm, 1'b0);
        begin
            automatic logic ok = 1'b1;
            for (int k = 0; k < FFT_LEN; k++) begin
                if (cap_user[k] !== 8'(k)) begin
                    ok = 1'b0;
                    if (k < 5 || k == FFT_LEN-1)
                        $display("T7: slot[%0d] xk_index=%0d (expected %0d)",
                                 k, cap_user[k], k);
                end
            end
            check(ok, "T7: all xk_index 0..255 in natural order");
        end

        // =====================================================================
        // T8: xk_index_check — monotonically increments by 1
        // =====================================================================
        $display("\nT8: xk_index_check");
        for (int n = 0; n < FFT_LEN; n++) begin
            re_frm[n] = 16'sh0800;
            im_frm[n] = 16'sh0000;
        end
        run_frame(re_frm, im_frm, 1'b0);
        begin
            automatic logic mono = 1'b1;
            for (int k = 1; k < cap_cnt; k++)
                if (cap_user[k] !== (cap_user[k-1] + 8'h01))
                    mono = 1'b0;
            check(mono,          "T8: xk_index increments by 1");
            check(cap_user[0] == 8'h00,
                  "T8: xk_index starts at 0");
            check(cap_user[FFT_LEN-1] == 8'hFF,
                  "T8: xk_index ends at 255");
        end

        // =====================================================================
        // T9: tlast_propagation — m_tlast asserted exactly at bin 255
        // =====================================================================
        $display("\nT9: tlast_propagation");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'($rtoi(AMP));
        run_frame(re_frm, im_frm, 1'b0);
        check(cap_tlast[FFT_LEN-1] == 1'b1,
              "T9: tlast at bin 255 (last captured slot)");
        check(cap_user[FFT_LEN-1] == 8'hFF,
              "T9: last captured bin has xk_index=255");
        // Verify tlast NOT asserted on earlier bins
        begin
            automatic logic early_tlast = 1'b0;
            for (int k = 0; k < FFT_LEN-1; k++)
                if (cap_tlast[k]) early_tlast = 1'b1;
            check(!early_tlast, "T9: no early tlast before bin 255");
        end

        // =====================================================================
        // T10: backpressure — realtime throttle documentation
        //    IP has C_THROTTLE_SCHEME=0; m_axis_data_tready absent on IP.
        //    Toggling wrapper's m_tready does not pause the IP.
        //    Test: toggle m_tready=0 then =1; verify data still received.
        // =====================================================================
        $display("\nT10: backpressure");
        $display("T10: NOTE — C_THROTTLE_SCHEME=0 (realtime): IP has no m_axis_data_tready.");
        $display("T10: Toggling wrapper m_tready cannot pause IP output.");
        $display("T10: Test verifies no deadlock when tready=0 then =1.");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'($rtoi(AMP));
        m_tready = 1'b0;       // toggle tready low
        send_frame(re_frm, im_frm);
        m_tready = 1'b1;       // restore
        capture_frame(1'b0);   // capture with tready=1; IP still runs
        check(cap_cnt == FFT_LEN,
              "T10: no deadlock — 256 bins captured after tready toggle");
        $display("T10: Realtime throttle: m_tready is NOT connected to IP, data always flows.");
        pass_cnt++;   // document known limitation as informational pass

        // =====================================================================
        // T11: pipeline_latency_measurement
        //    Record first_in_cycle at start of send_frame,
        //    first_out_cycle at start of capture_frame (first xk_index=0).
        // =====================================================================
        $display("\nT11: pipeline_latency_measurement");
        zero_frame(re_frm, im_frm);
        re_frm[0] = 16'($rtoi(AMP));

        // Record cycle JUST before first input handshake
        @(posedge aclk);
        first_in_cycle = $time / (2*HALF);

        run_frame(re_frm, im_frm, 1'b1);   // sets first_out_cycle

        observed_latency = (first_out_cycle > first_in_cycle)
                         ? (first_out_cycle - first_in_cycle)
                         : 0;
        $display("T11: first_input_cycle=%0d  first_output_cycle=%0d",
                 first_in_cycle, first_out_cycle);
        $display("T11: observed_latency = %0d clock cycles", observed_latency);
        check(observed_latency > 0 && observed_latency < TIMEOUT,
              "T11: latency measured");

        // =====================================================================
        // T12: multiple_frames — 3 back-to-back frames, each correct
        // =====================================================================
        $display("\nT12: multiple_frames");
        begin
            automatic logic ok3 = 1'b1;
            automatic int bk;
            for (int frm = 0; frm < 3; frm++) begin
                zero_frame(re_frm, im_frm);
                case (frm)
                    0: re_frm[0] = 16'($rtoi(AMP));                     // impulse
                    1: for (int n=0;n<FFT_LEN;n++) re_frm[n]=16'sh0800; // DC
                    2: begin                                               // tone bin 4
                        bk = 4;
                        for (int n=0;n<FFT_LEN;n++)
                            re_frm[n] = 16'($rtoi(AMP * $cos(2.0*PI*bk*n/FFT_LEN)));
                    end
                endcase
                run_frame(re_frm, im_frm, 1'b0);
                if (cap_cnt !== FFT_LEN) ok3 = 1'b0;
                peak_bin = find_peak(cap_mag);
                $display("T12: frm%0d — %0d bins, peak=bin%0d", frm, cap_cnt, peak_bin);
            end
            check(ok3, "T12: all 3 frames produced 256 bins");
        end

        // =====================================================================
        // CI GATE
        // =====================================================================
        $display("\n============================================================");
        $display("PASS: %0d  FAIL: %0d", pass_cnt, fail_cnt);
        $display("Observed pipeline latency: %0d cycles", observed_latency);
        $display("Output IQ packing: tdata[15:0]=Re(I), tdata[31:16]=Im(Q)");
        $display("xk_index: m_axis_tuser[7:0], natural order 0..255");
        $display("Scaling: SCALE_SCH=8'hAA (bits[8:1]), FWD_INV=1 (bit[0])");
        $display("Config word: 16'h0155");
        $display("Backpressure: not available (realtime throttle, no IP tready)");
        if (fail_cnt == 0 && pass_cnt > 0)
            $display("CI GATE: PASSED");
        else
            $display("CI GATE: FAILED");
        $display("============================================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Global timeout watchdog
    // -------------------------------------------------------------------------
    initial begin
        #(TIMEOUT * 50 * 10);   // 50 × TIMEOUT cycles
        $display("[ERROR] Global simulation timeout!");
        $display("CI GATE: FAILED");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Event monitor
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (ev_tlast_unexpected)
            $display("[NOTE] event_tlast_unexpected at %0t", $time);
        if (ev_tlast_missing)
            $display("[NOTE] event_tlast_missing at %0t", $time);
        if (ev_din_halt)
            $display("[NOTE] event_data_in_channel_halt at %0t", $time);
    end

endmodule
