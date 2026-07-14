`timescale 1ns/1ps

module tb_cordic_arctan_wrapper;

  // =========================================================
  // Parameters
  // =========================================================
  parameter integer AVG_W            = 64;
  parameter integer CORDIC_W         = 24;
  parameter integer FIFO_DEPTH       = 4096;
  parameter integer TOL_LSB          = 512;   // relaxed slightly for fixed-point corner cases
  parameter integer HEADROOM_BITS    = 2;
  parameter integer ROUND_EN         = 1;
  parameter integer RUN_FILE_TEST    = 1;     // 1: run file regression if file exists
  parameter integer FILE_BUBBLE_CYC  = 0;     // bubble cycles between file vectors
  parameter integer CLK_HALF_NS      = 5;     // 100 MHz
  parameter integer RESET_IGNORE_CYC = 40;    // ignore output after reset release
  parameter integer TINY_THRESH      = 1;     // skip compare if max(|x|,|y|) <= TINY_THRESH

  // =========================================================
  // DUT signals
  // =========================================================
  reg  clk;
  reg  rst;
  reg  en;

  reg  signed [AVG_W-1:0] avg_i;
  reg  signed [AVG_W-1:0] avg_q;
  reg                     avg_stb;

  wire signed [CORDIC_W-1:0] phase;
  wire                       phase_strobe;

  // expected-tag sideband for scoreboard only
  reg  signed [CORDIC_W-1:0] exp_tag_code;
  reg                        exp_tag_valid;
  reg                        exp_tag_skip;

  // =========================================================
  // DUT
  // =========================================================
  cordic_arctan_strobe_wrapper_full #(
    .AVG_W         (AVG_W),
    .CORDIC_W      (CORDIC_W),
    .HEADROOM_BITS (HEADROOM_BITS),
    .ROUND_EN      (ROUND_EN)
  ) dut (
    .clock          (clk),
    .reset          (rst),
    .enable         (en),
    .avg_out_i      (avg_i),
    .avg_out_q      (avg_q),
    .avg_out_strobe (avg_stb),
    .phase_cordic   (phase),
    .phase_strobe   (phase_strobe)
  );

  // =========================================================
  // Clock / Reset
  // =========================================================
  initial clk = 1'b0;
  always #(CLK_HALF_NS) clk = ~clk;

  // =========================================================
  // Real constants
  // =========================================================
  real PI;
  initial begin
    PI = 3.14159265358979323846;
  end

  // =========================================================
  // Helpers
  // =========================================================
  function integer abs_int;
    input integer x;
    begin
      if (x < 0) abs_int = -x;
      else       abs_int = x;
    end
  endfunction

  function integer max_int;
    input integer a;
    input integer b;
    begin
      if (a >= b) max_int = a;
      else        max_int = b;
    end
  endfunction

  // wrap-aware error in signed 24-bit phase code space
  function integer phase_err_wrap;
    input integer got;
    input integer exp;
    integer d;
    integer period;
    integer half;
    begin
      period = (1 << CORDIC_W);
      half   = (1 << (CORDIC_W-1));

      d = got - exp;

      if (d >= half)
        d = d - period;
      else if (d < -half)
        d = d + period;

      phase_err_wrap = abs_int(d);
    end
  endfunction

  // =========================================================
  // Xilinx CORDIC phase reference
  //
  // IMPORTANT:
  // Xilinx CORDIC atan/phase output here matches:
  //   code ~= angle[rad] * 2^(W-1) / 4
  //
  // Special policy:
  //   (-X, 0) -> use -PI branch to match DUT behavior
  // =========================================================
  function signed [CORDIC_W-1:0] ref_phase24;
    input signed [CORDIC_W-1:0] xi;
    input signed [CORDIC_W-1:0] yi;
    real xr, yr;
    real ang;
    real scaled;
    integer code;
    begin
      xr = xi;
      yr = yi;

      if ((xi == 0) && (yi == 0)) begin
        code = 0;
      end else begin
        if ((xr < 0.0) && (yr == 0.0))
          ang = -PI;
        else if (xr > 0.0)
          ang = $atan(yr / xr);
        else if ((xr < 0.0) && (yr > 0.0))
          ang = $atan(yr / xr) + PI;
        else if ((xr < 0.0) && (yr < 0.0))
          ang = $atan(yr / xr) - PI;
        else if ((xr == 0.0) && (yr > 0.0))
          ang = PI / 2.0;
        else if ((xr == 0.0) && (yr < 0.0))
          ang = -PI / 2.0;
        else
          ang = 0.0;

        // Xilinx CORDIC output encoding
        scaled = ang * ((1 << (CORDIC_W-1)) / 4.0);

        // symmetric rounding
        if (scaled >= 0.0)
          code = $rtoi(scaled + 0.5);
        else
          code = $rtoi(scaled - 0.5);
      end

      ref_phase24 = code[CORDIC_W-1:0];
    end
  endfunction

  function signed [AVG_W-1:0] sext24_to_avg;
    input signed [CORDIC_W-1:0] x;
    begin
      sext24_to_avg = {{(AVG_W-CORDIC_W){x[CORDIC_W-1]}}, x};
    end
  endfunction

  function integer should_skip_compare;
    input signed [CORDIC_W-1:0] xi;
    input signed [CORDIC_W-1:0] yi;
    integer ax, ay, mv;
    begin
      ax = (xi < 0) ? -xi : xi;
      ay = (yi < 0) ? -yi : yi;
      mv = max_int(ax, ay);

      if ((xi == 0) && (yi == 0))
        should_skip_compare = 1;
      else if (mv <= TINY_THRESH)
        should_skip_compare = 1;
      else
        should_skip_compare = 0;
    end
  endfunction

  // =========================================================
  // Scoreboard state
  // =========================================================
  integer cyc;

  integer wr_ptr;
  integer rd_ptr;
  integer fifo_count;

  integer exp_fifo  [0:FIFO_DEPTH-1];
  integer cyc_fifo  [0:FIFO_DEPTH-1];
  integer skip_fifo [0:FIFO_DEPTH-1];

  integer got_tmp;
  integer exp_tmp;
  integer err_tmp;
  integer in_cyc_tmp;
  integer lat_tmp;
  integer skip_tmp;

  // reset-ignore window after rst deassert
  integer ignore_output_cycles;

  // total counters (NOT cleared by mid-run reset)
  integer pass_count_total;
  integer fail_count_total;
  integer warn_count_total;
  integer sample_count_total;
  integer output_count_total;
  integer skip_count_total;

  // =========================================================
  // Initialization for totals
  // =========================================================
  initial begin
    pass_count_total   = 0;
    fail_count_total   = 0;
    warn_count_total   = 0;
    sample_count_total = 0;
    output_count_total = 0;
    skip_count_total   = 0;
  end

  // =========================================================
  // Scoreboard
  // FIFO ownership is ONLY here
  // =========================================================
  always @(posedge clk) begin
    if (rst) begin
      cyc                  <= 0;
      wr_ptr               <= 0;
      rd_ptr               <= 0;
      fifo_count           <= 0;
      ignore_output_cycles <= RESET_IGNORE_CYC;
    end else begin
      cyc <= cyc + 1;

      if (ignore_output_cycles > 0)
        ignore_output_cycles <= ignore_output_cycles - 1;

      // enqueue expected only when DUT really accepts a valid input
      if (avg_stb && exp_tag_valid && en) begin
        if (fifo_count < FIFO_DEPTH) begin
          exp_fifo[wr_ptr]  <= $signed(exp_tag_code);
          cyc_fifo[wr_ptr]  <= cyc;
          skip_fifo[wr_ptr] <= exp_tag_skip;
          wr_ptr            <= (wr_ptr + 1) % FIFO_DEPTH;
          fifo_count        <= fifo_count + 1;
          sample_count_total <= sample_count_total + 1;
        end else begin
          warn_count_total <= warn_count_total + 1;
          $display("[TB][WARN] Expected FIFO overflow attempt at cyc=%0d", cyc);
        end
      end

      // ignore outputs for a while after reset release
      if (phase_strobe && (ignore_output_cycles > 0)) begin
        $display("[TB][INFO] Ignored phase_strobe during reset-settle window at cyc=%0d", cyc);
      end
      else if (phase_strobe) begin
        output_count_total <= output_count_total + 1;

        if (fifo_count > 0) begin
          exp_tmp    = exp_fifo[rd_ptr];
          in_cyc_tmp = cyc_fifo[rd_ptr];
          skip_tmp   = skip_fifo[rd_ptr];

          got_tmp = $signed(phase);
          err_tmp = phase_err_wrap(got_tmp, exp_tmp);
          lat_tmp = cyc - in_cyc_tmp;

          if (skip_tmp != 0) begin
            skip_count_total <= skip_count_total + 1;
            $display("[TB][SKIP] out@%0d in@%0d lat=%0d exp=%0d got=%0d",
                     cyc, in_cyc_tmp, lat_tmp, exp_tmp, got_tmp);
          end else begin
            $display("[TB] out@%0d in@%0d lat=%0d exp=%0d got=%0d |err|=%0d",
                     cyc, in_cyc_tmp, lat_tmp, exp_tmp, got_tmp, err_tmp);

            if (err_tmp > TOL_LSB) begin
              fail_count_total <= fail_count_total + 1;
              $display("[TB][FAIL] cyc=%0d |err|=%0d > tol=%0d", cyc, err_tmp, TOL_LSB);
            end else begin
              pass_count_total <= pass_count_total + 1;
            end
          end

          rd_ptr     <= (rd_ptr + 1) % FIFO_DEPTH;
          fifo_count <= fifo_count - 1;
        end else begin
          warn_count_total <= warn_count_total + 1;
          $display("[TB][WARN] phase_strobe asserted but expected FIFO is empty at cyc=%0d", cyc);
        end
      end
    end
  end

  // =========================================================
  // Drive helpers
  // =========================================================
  task clear_inputs;
    begin
      avg_i         = {AVG_W{1'b0}};
      avg_q         = {AVG_W{1'b0}};
      avg_stb       = 1'b0;
      exp_tag_code  = {CORDIC_W{1'b0}};
      exp_tag_valid = 1'b0;
      exp_tag_skip  = 1'b0;
    end
  endtask

  task idle_posedges;
    input integer n;
    integer k;
    begin
      for (k = 0; k < n; k = k + 1)
        @(posedge clk);
    end
  endtask

  task drive_sample;
    input signed [AVG_W-1:0]     I;
    input signed [AVG_W-1:0]     Q;
    input signed [CORDIC_W-1:0]  EXP;
    input integer                EXPECT_OUTPUT;
    input integer                SKIP_COMPARE;
    input integer                KEEP_VALID_AFTER;
    begin
      @(negedge clk);
      avg_i         = I;
      avg_q         = Q;
      avg_stb       = 1'b1;
      exp_tag_code  = EXP;
      exp_tag_valid = EXPECT_OUTPUT;
      exp_tag_skip  = SKIP_COMPARE;

      @(posedge clk);

      if (KEEP_VALID_AFTER == 0) begin
        @(negedge clk);
        avg_stb       = 1'b0;
        exp_tag_valid = 1'b0;
        exp_tag_skip  = 1'b0;
        exp_tag_code  = {CORDIC_W{1'b0}};
      end
    end
  endtask

  task insert_bubbles;
    input integer n;
    integer k;
    begin
      @(negedge clk);
      avg_stb       = 1'b0;
      exp_tag_valid = 1'b0;
      exp_tag_skip  = 1'b0;
      exp_tag_code  = {CORDIC_W{1'b0}};
      for (k = 0; k < n; k = k + 1)
        @(posedge clk);
    end
  endtask

  task wait_fifo_empty_or_timeout;
    input integer timeout_cycles;
    integer t;
    begin
      t = 0;
      while ((fifo_count != 0) && (t < timeout_cycles)) begin
        @(posedge clk);
        t = t + 1;
      end

      if (fifo_count != 0) begin
        $display("[TB][WARN] wait_fifo_empty_or_timeout hit timeout with fifo_count=%0d", fifo_count);
      end else begin
        $display("[TB] FIFO drained after %0d cycle(s)", t);
      end
    end
  endtask

  task pulse_reset;
    input integer ncycles;
    integer k;
    begin
      @(negedge clk);
      rst = 1'b1;
      clear_inputs();

      for (k = 0; k < ncycles; k = k + 1)
        @(posedge clk);

      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  // =========================================================
  // Tests
  // =========================================================
  task test_smoke_axes_and_quadrants;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 1: smoke / axes / quadrants");
      $display("=========================================================");

      x24 =  24'sd4000000; y24 =  24'sd0;       p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 =  24'sd0;       y24 =  24'sd4000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = -24'sd4000000; y24 =  24'sd0;       p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 =  24'sd0;       y24 = -24'sd4000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 =  24'sd3000000; y24 =  24'sd3000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = -24'sd3000000; y24 =  24'sd3000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = -24'sd3000000; y24 = -24'sd3000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 =  24'sd3000000; y24 = -24'sd3000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_zero_and_near_axis;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 2: zero / tiny / near-axis");
      $display("=========================================================");

      x24 = 24'sd0;        y24 = 24'sd0;        p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd1;        y24 = 24'sd0;        p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd0;        y24 = 24'sd1;        p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd5000000;  y24 = 24'sd1;        p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd1;        y24 = 24'sd5000000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = -24'sd5000000; y24 = 24'sd1;        p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd1;        y24 = -24'sd5000000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_scale_invariance;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 3: scale invariance");
      $display("=========================================================");

      x24 = 24'sd100;      y24 = 24'sd200;      p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd1000;     y24 = 24'sd2000;     p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd10000;    y24 = 24'sd20000;    p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      x24 = 24'sd1000000;  y24 = 24'sd2000000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0); insert_bubbles(1);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_back_to_back_stream;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 4: back-to-back stream (no bubbles)");
      $display("=========================================================");

      x24 =  24'sd100000;  y24 =  24'sd50000;   p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 =  24'sd200000;  y24 =  24'sd150000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 = -24'sd300000;  y24 =  24'sd250000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 = -24'sd350000;  y24 = -24'sd100000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 =  24'sd500000;  y24 = -24'sd400000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 =  24'sd1;       y24 =  24'sd1;       p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 = -24'sd1;       y24 =  24'sd1;       p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 1);

      x24 =  24'sd123456;  y24 = -24'sd654321;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_enable_masking;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 5: enable masking");
      $display("=========================================================");

      wait_fifo_empty_or_timeout(2000);

      @(negedge clk);
      en = 1'b0;
      $display("[TB] enable -> 0");

      x24 =  24'sd400000;  y24 =  24'sd100000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 0, sk, 0);

      x24 = -24'sd400000;  y24 =  24'sd200000;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 0, sk, 0);

      idle_posedges(50);

      @(negedge clk);
      en = 1'b1;
      $display("[TB] enable -> 1");

      x24 = 24'sd700000; y24 = -24'sd333333; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_midrun_reset;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 6: mid-run reset");
      $display("=========================================================");

      wait_fifo_empty_or_timeout(2000);

      x24 = 24'sd1000000; y24 = 24'sd222222; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0);

      idle_posedges(2);

      pulse_reset(6);
      idle_posedges(10);

      x24 = -24'sd500000; y24 = -24'sd600000; p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0);

      x24 = 24'sd765432;  y24 = 24'sd123456;  p24 = ref_phase24(x24, y24); sk = should_skip_compare(x24, y24);
      drive_sample(sext24_to_avg(x24), sext24_to_avg(y24), p24, 1, sk, 0);

      wait_fifo_empty_or_timeout(2000);
    end
  endtask

  task test_file_regression;
    integer fd;
    integer ret;
    integer rx, ry, rp;
    reg signed [CORDIC_W-1:0] x24, y24, p24;
    reg signed [AVG_W-1:0]    I64, Q64;
    integer line_count;
    integer sk;
    begin
      $display("");
      $display("=========================================================");
      $display("[TB] TEST 7: file-driven regression");
      $display("=========================================================");

      fd = $fopen("cordic_tc_24b.hex", "r");
      if (fd == 0) begin
        $display("[TB][INFO] cordic_tc_24b.hex not found -> file regression skipped");
      end else begin
        line_count = 0;
        wait_fifo_empty_or_timeout(2000);

        while (!$feof(fd)) begin
          ret = $fscanf(fd, "%h %h %h\n", rx, ry, rp);
          if (ret == 3) begin
            x24 = rx[CORDIC_W-1:0];
            y24 = ry[CORDIC_W-1:0];
            p24 = rp[CORDIC_W-1:0];
            sk  = should_skip_compare(x24, y24);

            I64 = sext24_to_avg(x24);
            Q64 = sext24_to_avg(y24);

            drive_sample(I64, Q64, p24, 1, sk, 0);

            if (FILE_BUBBLE_CYC > 0)
              insert_bubbles(FILE_BUBBLE_CYC);

            line_count = line_count + 1;
          end
        end

        $fclose(fd);
        $display("[TB] file regression vectors applied = %0d", line_count);

        wait_fifo_empty_or_timeout(4000);
      end
    end
  endtask

  // =========================================================
  // Main
  // =========================================================
  initial begin
    rst = 1'b1;
    en  = 1'b1;
    clear_inputs();

    repeat (20) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    idle_posedges(10);

    test_smoke_axes_and_quadrants();
    test_zero_and_near_axis();
    test_scale_invariance();
    test_back_to_back_stream();
    test_enable_masking();
    test_midrun_reset();

    if (RUN_FILE_TEST != 0)
      test_file_regression();

    wait_fifo_empty_or_timeout(4000);
    idle_posedges(20);

    $display("");
    $display("=========================================================");
    $display("[TB] FINAL SUMMARY");
    $display("=========================================================");
    $display("[TB] sample_count_total = %0d", sample_count_total);
    $display("[TB] output_count_total = %0d", output_count_total);
    $display("[TB] pass_count_total   = %0d", pass_count_total);
    $display("[TB] fail_count_total   = %0d", fail_count_total);
    $display("[TB] skip_count_total   = %0d", skip_count_total);
    $display("[TB] warn_count_total   = %0d", warn_count_total);
    $display("=========================================================");

    if ((fail_count_total == 0) && (warn_count_total == 0))
      $display("[TB] RESULT: PASS");
    else if (fail_count_total == 0)
      $display("[TB] RESULT: PASS with WARNINGS");
    else
      $display("[TB] RESULT: FAIL");

    $finish;
  end

endmodule
