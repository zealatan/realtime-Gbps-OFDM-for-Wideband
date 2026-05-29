`timescale 1ns/1ps

// reference_style_frame_detector — streaming OFDM frame-start detector.
//
// Implements C receiver.c frame_detector() (Toan's version, lines 327-382):
//   envelopeBlock[j] = (1/WND_LEN) * sum(I[j..j+WND-1]^2 + Q[j..j+WND-1]^2)
//   Case A (window[0] < threshold): find CONFIRM_LEN consecutive above-threshold windows.
//   Case B (window[0] >= threshold): find first window below threshold (startIndex),
//     then apply Case A counting from startIndex.
//   frame_index = sample address of first window in the CONFIRM_LEN-consecutive run.
//
// RTL avoids division: compares running window SUM vs threshold port.
// Caller must supply threshold = C_threshold * IQ_scale^2 * WND_LEN.
//
// Per-sample power delegated to sample_power_sq (rtl/phase2_legacy/, 2-cycle latency).
// Sliding window uses WND_LEN-stage shift register; moving_avg_optimized is not used
// because WND_LEN=25 is not a power of 2.
//
// IQ word format: {Q[2*IQ_W-1:IQ_W], I[IQ_W-1:0]}
// (power = I^2+Q^2 is symmetric; IQ order passed directly to sample_power_sq).
//
// End-of-stream: s_tlast sets eos_armed; the 2-stage sample_power_sq pipeline
// drains via drain_cnt (initialized to 2).  When drain_cnt==1 on a pwr_stb the
// module transitions to S_DONE if no frame has been found.

module reference_style_frame_detector #(
    parameter integer IQ_W        = 16,
    parameter integer POWER_W     = 33,    // must equal 2*IQ_W + 1
    parameter integer SUM_W       = 48,    // must hold WND_LEN * max_power
    parameter integer INDEX_W     = 16,
    parameter integer WND_LEN     = 25,
    parameter integer CONFIRM_LEN = 10
) (
    input  wire              aclk,
    input  wire              aresetn,

    // AXI-Stream input — one sample per valid clock
    input  wire [2*IQ_W-1:0] s_tdata,    // {Q[2*IQ_W-1:IQ_W], I[IQ_W-1:0]}
    input  wire              s_tvalid,
    output wire              s_tready,   // = busy
    input  wire              s_tlast,    // last sample in buffer

    // Window-sum threshold: C_threshold * IQ_scale^2 * WND_LEN
    input  wire [SUM_W-1:0]  threshold,

    // Control
    input  wire              start,
    output reg               done,       // 1-cycle pulse
    output reg               busy,
    output reg               frame_found,
    output reg [INDEX_W-1:0] frame_index // stable after done; valid only when frame_found
);

    // ──────────────────────────────────────────────────────────────────────
    // Localparams
    // ──────────────────────────────────────────────────────────────────────
    localparam [1:0] S_IDLE        = 2'd0,
                     S_SEARCH_RISE = 2'd1,
                     S_SEARCH_FALL = 2'd2,
                     S_DONE        = 2'd3;

    localparam integer            FILL_W   = $clog2(WND_LEN + 1);
    localparam [FILL_W-1:0]       WND_W    = WND_LEN;       // WND_LEN in FILL_W bits
    localparam [FILL_W-1:0]       WND_M1_F = WND_LEN - 1;   // for fill comparison
    localparam [INDEX_W-1:0]      WND_M1_I = WND_LEN - 1;   // for index subtraction
    localparam [3:0]              CONF_LAST = CONFIRM_LEN - 1; // consec value at last hit

    // ──────────────────────────────────────────────────────────────────────
    // sample_power_sq (phase2_legacy): computes I^2+Q^2, 2-cycle latency
    // ──────────────────────────────────────────────────────────────────────
    wire              pwr_stb;
    wire [POWER_W-1:0] pwr_val;

    sample_power_sq #(
        .IQ_WIDTH  (IQ_W),
        .OUT_WIDTH (POWER_W)
    ) u_pow (
        .clock         (aclk),
        .enable        (busy),
        .reset         (~aresetn),
        .sample_in     (s_tdata),
        .input_strobe  (s_tvalid & s_tready),
        .power_out     (pwr_val),
        .power_out_stb (pwr_stb)
    );

    assign s_tready = busy;

    // ──────────────────────────────────────────────────────────────────────
    // Sliding-window shift register (WND_LEN stages)
    // delay_sr[WND_LEN-1] holds the oldest power value being evicted
    // ──────────────────────────────────────────────────────────────────────
    reg [POWER_W-1:0]   delay_sr [0:WND_LEN-1];
    reg [SUM_W-1:0]     running_sum;
    reg [FILL_W-1:0]    fill_cnt;            // 0 .. WND_LEN
    wire                win_full = (fill_cnt >= WND_W);

    // ──────────────────────────────────────────────────────────────────────
    // Scan state
    // ──────────────────────────────────────────────────────────────────────
    reg [INDEX_W-1:0]   pwr_cnt;    // count of powers processed (0-indexed before increment)
    reg                 first_done; // 1 once first window result evaluated (Case A/B set)
    reg [3:0]           consec;     // consecutive above-threshold windows in current run
    reg [INDEX_W-1:0]   hit_start;  // win_start at first hit of current run

    // ──────────────────────────────────────────────────────────────────────
    // End-of-stream
    // eos_armed is set (NBA) at posedge L where s_tlast & input_strobe fire.
    // The 2-stage pipeline means two more pwr_stbs will fire after posedge L:
    //   posedge L+1: pwr_stb for sample L-1  (drain_cnt: 2→1)
    //   posedge L+2: pwr_stb for sample L    (drain_cnt: 1 → fire S_DONE)
    // drain_cnt counts down from 2; S_DONE fires when drain_cnt==1 (last stb).
    // ──────────────────────────────────────────────────────────────────────
    reg       eos_armed;
    reg [1:0] drain_cnt;

    // ──────────────────────────────────────────────────────────────────────
    // FSM register
    // ──────────────────────────────────────────────────────────────────────
    reg [1:0] state;

    // ──────────────────────────────────────────────────────────────────────
    // Blocking (wire-like) temporaries used within the always block
    // ──────────────────────────────────────────────────────────────────────
    reg [SUM_W-1:0]   nsum;       // next running_sum value
    reg               nwin;       // window becomes valid after this pwr_stb
    reg               above;      // nsum > threshold
    reg [INDEX_W-1:0] wstart;     // start sample index of current window
    reg               found_flag; // set if frame found in this pwr_stb cycle
    integer           ii;

    always @(posedge aclk) begin
        if (!aresetn) begin
            state       <= S_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            frame_found <= 1'b0;
            frame_index <= {INDEX_W{1'b0}};
            running_sum <= {SUM_W{1'b0}};
            fill_cnt    <= {FILL_W{1'b0}};
            pwr_cnt     <= {INDEX_W{1'b0}};
            first_done  <= 1'b0;
            consec      <= 4'd0;
            hit_start   <= {INDEX_W{1'b0}};
            eos_armed   <= 1'b0;
            drain_cnt   <= 2'd2;
            for (ii = 0; ii < WND_LEN; ii = ii + 1)
                delay_sr[ii] <= {POWER_W{1'b0}};
        end else begin
            done <= 1'b0; // default: no pulse

            case (state)

                // ──────────────────────────────────────────────────────────
                S_IDLE: begin
                    if (start) begin
                        busy        <= 1'b1;
                        frame_found <= 1'b0;
                        running_sum <= {SUM_W{1'b0}};
                        fill_cnt    <= {FILL_W{1'b0}};
                        pwr_cnt     <= {INDEX_W{1'b0}};
                        first_done  <= 1'b0;
                        consec      <= 4'd0;
                        eos_armed   <= 1'b0;
                        drain_cnt   <= 2'd2;
                        for (ii = 0; ii < WND_LEN; ii = ii + 1)
                            delay_sr[ii] <= {POWER_W{1'b0}};
                        state <= S_SEARCH_RISE;
                    end
                end

                // ──────────────────────────────────────────────────────────
                // SEARCH_RISE: filling window + Case A consecutive-hit scan.
                // Also entered from SEARCH_FALL once the first drop is found.
                // ──────────────────────────────────────────────────────────
                S_SEARCH_RISE: begin
                    if (s_tvalid & s_tready & s_tlast)
                        eos_armed <= 1'b1;

                    if (pwr_stb) begin
                        found_flag = 1'b0; // reset each cycle

                        // ── Sliding-window update ──────────────────────────
                        if (!win_full) begin
                            nsum = running_sum + {{(SUM_W-POWER_W){1'b0}}, pwr_val};
                            nwin = (fill_cnt == WND_M1_F); // last fill sample
                            fill_cnt <= fill_cnt + 1;
                        end else begin
                            nsum = running_sum + {{(SUM_W-POWER_W){1'b0}}, pwr_val}
                                 - {{(SUM_W-POWER_W){1'b0}}, delay_sr[WND_LEN-1]};
                            nwin = 1'b1;
                        end
                        running_sum <= nsum;

                        // Shift delay register (oldest at index WND_LEN-1)
                        for (ii = WND_LEN-1; ii > 0; ii = ii - 1)
                            delay_sr[ii] <= delay_sr[ii-1];
                        delay_sr[0] <= pwr_val;

                        // ── Threshold and index ────────────────────────────
                        above  = (nsum > threshold);
                        // pwr_cnt is the OLD count (pre-increment); window ends here
                        wstart = pwr_cnt - WND_M1_I;
                        pwr_cnt <= pwr_cnt + 1;

                        // ── Case A / B determination + counting ────────────
                        if (nwin) begin
                            if (!first_done) begin
                                // First window result: determine Case A vs B
                                first_done <= 1'b1;
                                if (above)
                                    state <= S_SEARCH_FALL; // Case B
                                // Case A: stay, counting begins on next window
                            end else begin
                                // Case A consecutive-hit counting
                                if (above) begin
                                    if (consec == 4'd0)
                                        hit_start <= wstart;
                                    if (consec == CONF_LAST) begin
                                        frame_index <= hit_start;
                                        frame_found <= 1'b1;
                                        found_flag  = 1'b1;
                                        state       <= S_DONE;
                                    end else
                                        consec <= consec + 1;
                                end else
                                    consec <= 4'd0;
                            end
                        end

                        // ── End-of-stream: drain_cnt==1 on the second pwr_stb
                        //    after eos_armed fires = last pwr_stb in the stream.
                        if (eos_armed && !found_flag) begin
                            if (drain_cnt == 2'd1)
                                state <= S_DONE;
                            drain_cnt <= drain_cnt - 1;
                        end
                    end
                end

                // ──────────────────────────────────────────────────────────
                // SEARCH_FALL: Case B — scanning for first window below threshold.
                // Window is guaranteed full when we enter this state.
                // ──────────────────────────────────────────────────────────
                S_SEARCH_FALL: begin
                    if (s_tvalid & s_tready & s_tlast)
                        eos_armed <= 1'b1;

                    if (pwr_stb) begin
                        found_flag = 1'b0;

                        // Slide window forward (always full here)
                        nsum = running_sum + {{(SUM_W-POWER_W){1'b0}}, pwr_val}
                             - {{(SUM_W-POWER_W){1'b0}}, delay_sr[WND_LEN-1]};
                        running_sum <= nsum;

                        for (ii = WND_LEN-1; ii > 0; ii = ii - 1)
                            delay_sr[ii] <= delay_sr[ii-1];
                        delay_sr[0] <= pwr_val;

                        pwr_cnt <= pwr_cnt + 1;
                        above = (nsum > threshold);

                        if (!above) begin
                            // Found startIndex — switch to Case A scan
                            consec <= 4'd0;
                            state  <= S_SEARCH_RISE;
                        end
                        // eos_armed: drain 2 more pwr_stbs then go to S_DONE
                        if (eos_armed) begin
                            if (drain_cnt == 2'd1)
                                state <= S_DONE;
                            drain_cnt <= drain_cnt - 1;
                        end
                    end
                end

                // ──────────────────────────────────────────────────────────
                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
