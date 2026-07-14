`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// p5_complex_rotator_unit_tb
//
// Self-contained unit testbench for rtl/complex_rotator.v.
//
// DUT files (compiled by scripts/run_p5_rotator_unit.sh):
//   - rtl/complex_rotator.v   (wraps complex_mult_iq with CONJ_B=1)
//   - rtl/complex_mult_iq.v
//
// What the DUT does (see complex_rotator.v header):
//
//     (I_out + j*Q_out) = (I_in + j*Q_in) * (cos_in - j*sin_in)
//
// The DUT takes raw Q1.15 sin_in/cos_in samples (16-bit signed), so the
// phase->sincos conversion happens inside this TB. We use the same
// convention as golden/p5_rotator_golden.csv:
//
//     theta = phase_word / 32768 * pi          (phase_word is signed int16)
//     cos_drive = round( cos(theta) * 32767)
//     sin_drive = round(-sin(theta) * 32767)    (sign flip => DUT outputs
//                                                exp(+j*theta) per spec)
//
// Per-case TOL is 64 LSB on each of I and Q (Q15 truncating shift +
// Q15 rounding of cos/sin can easily eat a few LSB per multiply; 64 is a
// comfortable cushion that still catches gross arithmetic errors).
//
// Gate output (the runner greps for exactly one):
//   GATE_P5_ROT_UNIT: PASS
//   GATE_P5_ROT_UNIT: FAIL
//
// Note: iverilog -g2012 — no SV-only constructs (no `logic`, no
// dynamic arrays, no string regex). We use plain `reg`/`integer` and
// $fscanf for CSV parsing.
// -----------------------------------------------------------------------------

module p5_complex_rotator_unit_tb;

    // --------------------------------------------------------------------- //
    // Parameters
    // --------------------------------------------------------------------- //
    localparam integer DATA_WIDTH      = 32;
    localparam integer COMPONENT_WIDTH = 16;
    localparam integer SHIFT           = 15;

    localparam integer MAX_CASES       = 128;
    localparam integer TOL             = 64;

    localparam real    CLK_HALF        = 5.0;     // 100 MHz
    localparam integer WDG_CYCLES      = 200000;

    // --------------------------------------------------------------------- //
    // Clock / reset
    // --------------------------------------------------------------------- //
    reg aclk    = 1'b0;
    reg aresetn = 1'b0;
    always #(CLK_HALF) aclk = ~aclk;

    // --------------------------------------------------------------------- //
    // Stimulus storage (loaded from CSV)
    // --------------------------------------------------------------------- //
    integer in_I_arr      [0:MAX_CASES-1];
    integer in_Q_arr      [0:MAX_CASES-1];
    integer phase_arr     [0:MAX_CASES-1];
    integer exp_outI_arr  [0:MAX_CASES-1];
    integer exp_outQ_arr  [0:MAX_CASES-1];
    integer num_cases;

    // --------------------------------------------------------------------- //
    // DUT I/O
    // --------------------------------------------------------------------- //
    reg  [DATA_WIDTH-1:0]             iq_tdata;
    reg                               iq_tvalid;
    wire                              iq_tready;
    reg                               iq_tlast;

    reg  signed [COMPONENT_WIDTH-1:0] sin_in;
    reg  signed [COMPONENT_WIDTH-1:0] cos_in;
    reg                               sincos_valid;

    wire [DATA_WIDTH-1:0]             m_tdata;
    wire                              m_tvalid;
    reg                               m_tready;
    wire                              m_tlast;

    complex_rotator #(
        .DATA_WIDTH      (DATA_WIDTH),
        .COMPONENT_WIDTH (COMPONENT_WIDTH),
        .SHIFT           (SHIFT)
    ) u_dut (
        .aclk             (aclk),
        .aresetn          (aresetn),

        .s_axis_iq_tdata  (iq_tdata),
        .s_axis_iq_tvalid (iq_tvalid),
        .s_axis_iq_tready (iq_tready),
        .s_axis_iq_tlast  (iq_tlast),

        .sin_in           (sin_in),
        .cos_in           (cos_in),
        .sincos_valid     (sincos_valid),

        .m_axis_tdata     (m_tdata),
        .m_axis_tvalid    (m_tvalid),
        .m_axis_tready    (m_tready),
        .m_axis_tlast     (m_tlast)
    );

    // --------------------------------------------------------------------- //
    // CSV loader  (iverilog -g2012 friendly: $fscanf with %d only)
    // --------------------------------------------------------------------- //
    integer fh;
    integer rc;
    integer ic;
    reg [8*256-1:0] line_buf;     // for skipping comment lines
    integer ch;

    // Trick: read whole lines, skip those starting with '#'. iverilog's $fgets
    // returns the line including a trailing newline.
    task automatic load_csv(input [8*256-1:0] path);
        begin : load_blk
            num_cases = 0;
            fh = $fopen(path, "r");
            if (fh == 0) begin
                $display("[P5-ROT] ERROR: cannot open %0s", path);
                $finish;
            end
            while (!$feof(fh)) begin
                rc = $fgets(line_buf, fh);
                if (rc == 0) begin
                    // nothing more to read
                end
                else if (line_buf[8*255 +: 8] == "#") begin
                    // comment line; skip (the first byte after fgets sits in
                    // the highest-index byte slot in iverilog string regs)
                end
                else begin
                    // Try to parse: %d,%d,%d,%d,%d
                    rc = $sscanf(line_buf, "%d,%d,%d,%d,%d",
                                 in_I_arr[num_cases],
                                 in_Q_arr[num_cases],
                                 phase_arr[num_cases],
                                 exp_outI_arr[num_cases],
                                 exp_outQ_arr[num_cases]);
                    if (rc == 5) begin
                        num_cases = num_cases + 1;
                        if (num_cases >= MAX_CASES) begin
                            $display("[P5-ROT] WARN: case limit %0d hit", MAX_CASES);
                            num_cases = MAX_CASES;
                        end
                    end
                end
            end
            $fclose(fh);
            $display("[P5-ROT] loaded %0d cases from %0s", num_cases, path);
        end
    endtask

    // --------------------------------------------------------------------- //
    // Phase -> Q1.15 (cos, sin) conversion (computed in TB)
    // --------------------------------------------------------------------- //
    // We use $cos / $sin (real-valued built-ins available in iverilog).
    // Result: cos_q15  = round( cos(theta) * 32767 ), clamp to int16
    //         sin_q15n = round(-sin(theta) * 32767 ), clamp to int16
    // Drive cos_in = cos_q15, sin_in = sin_q15n so that DUT's
    // (cos - j*sin) = (cos(theta) + j*sin(theta)) = exp(+j*theta).
    real    theta_r;
    real    cosv_r;
    real    sinv_r;
    integer cos_q15_i;
    integer sin_q15_i;

    function automatic integer clamp16(input integer v);
        begin
            if (v >  32767) clamp16 =  32767;
            else if (v < -32768) clamp16 = -32768;
            else clamp16 = v;
        end
    endfunction

    task automatic phase_to_sincos(input integer phase_word);
        begin
            theta_r   = (phase_word / 32768.0) * 3.14159265358979323846;
            cosv_r    =  $cos(theta_r);
            sinv_r    = -$sin(theta_r);   // sign flip
            // round-half-away-from-zero
            if (cosv_r >= 0.0)
                cos_q15_i = $rtoi(cosv_r * 32767.0 + 0.5);
            else
                cos_q15_i = $rtoi(cosv_r * 32767.0 - 0.5);
            if (sinv_r >= 0.0)
                sin_q15_i = $rtoi(sinv_r * 32767.0 + 0.5);
            else
                sin_q15_i = $rtoi(sinv_r * 32767.0 - 0.5);
            cos_q15_i = clamp16(cos_q15_i);
            sin_q15_i = clamp16(sin_q15_i);
        end
    endtask

    // --------------------------------------------------------------------- //
    // Sign-extending decoders for 16-bit fields packed into 32-bit tdata
    // --------------------------------------------------------------------- //
    function automatic signed [15:0] s16_of_lo(input [31:0] w);
        begin
            s16_of_lo = w[15:0];
        end
    endfunction
    function automatic signed [15:0] s16_of_hi(input [31:0] w);
        begin
            s16_of_hi = w[31:16];
        end
    endfunction

    // --------------------------------------------------------------------- //
    // Watchdog
    // --------------------------------------------------------------------- //
    integer wdg;
    always @(posedge aclk) begin
        if (!aresetn) wdg <= 0;
        else          wdg <= wdg + 1;
        if (wdg > WDG_CYCLES) begin
            $display("WDG: TIMEOUT at %0t (%0d cycles)", $time, WDG_CYCLES);
            $display("GATE_P5_ROT_UNIT: FAIL");
            $finish;
        end
    end

    // --------------------------------------------------------------------- //
    // Main stimulus / check
    // --------------------------------------------------------------------- //
    integer i;
    integer wait_cnt;
    integer rtl_I;
    integer rtl_Q;
    integer exp_I;
    integer exp_Q;
    integer diff_I;
    integer diff_Q;
    integer abs_diff_I;
    integer abs_diff_Q;
    integer max_err_I;
    integer max_err_Q;
    integer pass_cnt;
    integer fail_cnt;
    reg     case_pass;

    initial begin
        // ---- VCD (optional, small) ----
        if ($test$plusargs("dump")) begin
            $dumpfile("sim_out/p5_rotator_unit/p5_rotator_unit.vcd");
            $dumpvars(0, p5_complex_rotator_unit_tb);
        end

        // ---- init ----
        iq_tdata     = 32'd0;
        iq_tvalid    = 1'b0;
        iq_tlast     = 1'b0;
        sin_in       = 16'sd0;
        cos_in       = 16'sd0;
        sincos_valid = 1'b0;
        m_tready     = 1'b1;     // always ready to consume
        pass_cnt     = 0;
        fail_cnt     = 0;
        max_err_I    = 0;
        max_err_Q    = 0;

        // ---- load CSV ----
        load_csv("golden/p5_rotator_golden.csv");
        if (num_cases <= 0) begin
            $display("[P5-ROT] ERROR: no cases loaded");
            $display("GATE_P5_ROT_UNIT: FAIL");
            $finish;
        end

        // ---- reset ----
        aresetn = 1'b0;
        repeat (8) @(posedge aclk);
        aresetn = 1'b1;
        repeat (4) @(posedge aclk);

        // ---- per-case loop: drive, wait, capture ----
        for (i = 0; i < num_cases; i = i + 1) begin
            // Compute Q1.15 sin/cos drives for this phase_word
            phase_to_sincos(phase_arr[i]);

            // Apply the sample for one cycle (single-beat)
            @(negedge aclk);
            iq_tdata     = {in_Q_arr[i][15:0], in_I_arr[i][15:0]};
            iq_tvalid    = 1'b1;
            iq_tlast     = 1'b1;
            cos_in       = cos_q15_i[15:0];
            sin_in       = sin_q15_i[15:0];
            sincos_valid = 1'b1;

            // Wait for handshake (tvalid && tready)
            wait_cnt = 0;
            while (!(iq_tvalid && iq_tready)) begin
                @(posedge aclk);
                wait_cnt = wait_cnt + 1;
                if (wait_cnt > 100) begin
                    $display("[P5-ROT] ERROR: never saw s_axis_iq_tready for case %0d", i);
                    $display("GATE_P5_ROT_UNIT: FAIL");
                    $finish;
                end
            end
            @(posedge aclk);
            @(negedge aclk);
            iq_tvalid    = 1'b0;
            iq_tlast     = 1'b0;

            // Wait for m_axis_tvalid (2-cycle pipe; allow generous slack)
            wait_cnt = 0;
            while (!m_tvalid) begin
                @(posedge aclk);
                wait_cnt = wait_cnt + 1;
                if (wait_cnt > 100) begin
                    $display("[P5-ROT] ERROR: never saw m_axis_tvalid for case %0d", i);
                    $display("GATE_P5_ROT_UNIT: FAIL");
                    $finish;
                end
            end

            // Sample at the active m_tvalid cycle
            @(negedge aclk);
            rtl_I = $signed(s16_of_lo(m_tdata));
            rtl_Q = $signed(s16_of_hi(m_tdata));
            exp_I = exp_outI_arr[i];
            exp_Q = exp_outQ_arr[i];

            diff_I = rtl_I - exp_I;
            diff_Q = rtl_Q - exp_Q;
            abs_diff_I = (diff_I < 0) ? -diff_I : diff_I;
            abs_diff_Q = (diff_Q < 0) ? -diff_Q : diff_Q;
            if (abs_diff_I > max_err_I) max_err_I = abs_diff_I;
            if (abs_diff_Q > max_err_Q) max_err_Q = abs_diff_Q;

            case_pass = (abs_diff_I <= TOL) && (abs_diff_Q <= TOL);
            if (case_pass) pass_cnt = pass_cnt + 1;
            else           fail_cnt = fail_cnt + 1;

            $display("[P5-ROT] case[%0d] phase=%0d in=(%0d,%0d) rtl=(%0d,%0d) exp=(%0d,%0d) diff=(%0d,%0d) %s",
                     i, phase_arr[i],
                     in_I_arr[i], in_Q_arr[i],
                     rtl_I, rtl_Q,
                     exp_I, exp_Q,
                     diff_I, diff_Q,
                     case_pass ? "PASS" : "FAIL");

            // Drain: hold m_tready=1, wait for tvalid to drop so next case
            // starts cleanly. complex_mult_iq pulls tvalid back down once
            // the downstream consumes (m_tready=1 already).
            @(posedge aclk);
        end

        // ---- gate ----
        $display("");
        $display("[P5-ROT] summary: cases=%0d pass=%0d fail=%0d max_err_I=%0d max_err_Q=%0d TOL=%0d",
                 num_cases, pass_cnt, fail_cnt, max_err_I, max_err_Q, TOL);
        if (fail_cnt == 0) begin
            $display("GATE_P5_ROT_UNIT: PASS");
        end else begin
            $display("GATE_P5_ROT_UNIT: FAIL");
        end
        $finish;
    end

endmodule
