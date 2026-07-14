`timescale 1ns/1ps
// =============================================================
//  p5_d_meyr_cfo_top_unit_tb.sv  -  P5-01A Step D Level-1 unit gate.
//
//  Drives meyr_cfo_top standalone with C-reference-derived PSS+SSS
//  stimulus for a sweep of integer CFOs and asserts the index-based
//  CFO decode matches the expected k_int.
//
//  The TB:
//    1. Reset.
//    2. Loads B[k] ROM via the runtime rom_we/rom_waddr/rom_wdata port,
//       reading vectors/bk_conj_fft512_rom.txt (512 x 64-bit hex).
//    3. For each k_int case, streams 256 PSS + 256 SSS samples from a
//       per-case .mem file (Q15 packed {im[15:0], re[15:0]}).
//    4. Waits for cfo_valid and checks cfo_int (index-based, not magnitude).
//
//  Run via the tcl runner: vivado_xsim/tcl/run_p5_d_meyr_cfo_top_unit.tcl
//
//  Pass line (parsed by the runner):  GATE: PASS_P5_D_LEVEL1
//  Fail line:                          GATE: FAIL_P5_D_LEVEL1
// =============================================================
module p5_d_meyr_cfo_top_unit_tb;

    // ------------------------------------------------------------------
    // Parameters - kept parameter-derived per P5-01A guardrail
    // ------------------------------------------------------------------
    localparam int N             = 256;
    localparam int N2            = 2 * N;
    localparam int N_LOG2        = 8;
    localparam int N_LOG2_MAX    = 12;
    localparam int ROM_DEPTH     = N2;
    // xsim cwd is vivado_xsim/logs/p5_d_build/ (set by the runner Tcl);
    // three levels up to reach the project root.
    localparam string ROM_HEX_PATH    = "../../../vectors/bk_conj_fft512_rom.txt";
    localparam string STIM_DIR        = "../../../vectors/p5_d";
    localparam int TIMEOUT_CYCLES = 200000;  // ~10x core latency

    // ------------------------------------------------------------------
    // Sweep cases - full k_int [-8..+8] sweep, 17 cases.
    // ------------------------------------------------------------------
    int  case_k_int  [0:16];
    int  case_peak   [0:16];
    int  case_cfoint [0:16];
    string case_tag  [0:16];
    int  num_cases;

    initial begin
        int idx;
        idx = 0;
        for (int k = -8; k <= 8; k = k + 1) begin
            case_k_int[idx]   = k;
            case_peak[idx]    = (k >= 0) ? k : (512 + k);
            case_cfoint[idx]  = k;
            case_tag[idx]     = (k >= 0) ? $sformatf("kp%02d", k) : $sformatf("km%02d", -k);
            idx = idx + 1;
        end
        num_cases = 17;
    end

    // ------------------------------------------------------------------
    // Clock + reset
    // ------------------------------------------------------------------
    logic clk = 0;
    logic rst_n = 0;
    always #2 clk = ~clk;  // 250 MHz

    // ------------------------------------------------------------------
    // DUT I/O
    // ------------------------------------------------------------------
    logic        rom_we;
    logic [12:0] rom_waddr;
    logic [63:0] rom_wdata;

    logic [31:0] s_tdata;
    logic        s_tvalid;
    logic        s_tready;

    logic signed [31:0]            cfo_int;
    logic [N_LOG2_MAX:0]           peak_idx;
    logic                          cfo_valid;

    logic [63:0] dbg_ifft_tdata;
    logic        dbg_ifft_tvalid;
    logic        dbg_ifft_tlast;

    meyr_cfo_top #(
        .N_LOG2_MAX(N_LOG2_MAX)
    ) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .n_log2         (N_LOG2[4:0]),
        .rom_we         (rom_we),
        .rom_waddr      (rom_waddr),
        .rom_wdata      (rom_wdata),
        .s_tdata        (s_tdata),
        .s_tvalid       (s_tvalid),
        .s_tready       (s_tready),
        .cfo_int        (cfo_int),
        .peak_idx       (peak_idx),
        .cfo_valid      (cfo_valid),
        .dbg_ifft_tdata (dbg_ifft_tdata),
        .dbg_ifft_tvalid(dbg_ifft_tvalid),
        .dbg_ifft_tlast (dbg_ifft_tlast)
    );

    // ------------------------------------------------------------------
    // P5-08 / ISS-13 invariant assertions (bind, no source change)
    // ------------------------------------------------------------------
    bind meyr_cfo_top       p5_invariants_meyr_cfo_top u_inv_top  (.*);
    bind meyr_ifft_peak_dut p5_invariants_ifft_peak    u_inv_ifft (.*);

    // ------------------------------------------------------------------
    // P5-08 B2 functional covergroups (bind, no source change)
    // ------------------------------------------------------------------
    bind meyr_cfo_top       p5_functional_cov_meyr     u_cov_top  (.*);

    // ------------------------------------------------------------------
    // ROM image (loaded once from file)
    // ------------------------------------------------------------------
    logic [63:0] rom_image [0:ROM_DEPTH-1];
    initial $readmemh(ROM_HEX_PATH, rom_image);

    // ------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------
    int fail_count;
    int pass_count;

    task automatic reset_dut();
        rom_we   = 1'b0;
        rom_waddr= '0;
        rom_wdata= '0;
        s_tdata  = '0;
        s_tvalid = 1'b0;
        rst_n    = 1'b0;
        repeat (16) @(posedge clk);
        rst_n    = 1'b1;
        // Wait out the fft_rst_n hold window (RST_HOLD = 64 cycles in DUT).
        repeat (100) @(posedge clk);
    endtask

    task automatic load_rom();
        integer a;
        @(posedge clk);
        for (a = 0; a < ROM_DEPTH; a = a + 1) begin
            rom_we    <= 1'b1;
            rom_waddr <= a[12:0];
            rom_wdata <= rom_image[a];
            @(posedge clk);
        end
        rom_we   <= 1'b0;
        rom_waddr<= '0;
        rom_wdata<= '0;
        @(posedge clk);
    endtask

    task automatic stream_stimulus(input string path);
        logic [31:0] stim [0:N2-1];
        integer n;
        for (n = 0; n < N2; n = n + 1) stim[n] = 32'h0;
        $readmemh(path, stim);
        // Wait for upstream ready (DUT lifts s_tready after one-shot config).
        while (!s_tready) @(posedge clk);
        for (n = 0; n < N2; n = n + 1) begin
            s_tdata  <= stim[n];
            s_tvalid <= 1'b1;
            @(posedge clk);
            while (!s_tready) @(posedge clk);
        end
        s_tvalid <= 1'b0;
        s_tdata  <= '0;
    endtask

    task automatic wait_for_cfo(output bit got, output int observed_peak, output int observed_cfo);
        int cyc;
        got = 1'b0;
        observed_peak = 0;
        observed_cfo  = 0;
        for (cyc = 0; cyc < TIMEOUT_CYCLES; cyc = cyc + 1) begin
            @(posedge clk);
            if (cfo_valid) begin
                got = 1'b1;
                observed_peak = peak_idx;
                observed_cfo  = cfo_int;
                return;
            end
        end
    endtask

    initial begin
        int  i;
        bit  ok;
        int  obs_peak;
        int  obs_cfo;
        string stim_path;

        fail_count = 0;
        pass_count = 0;

        $display("[P5-D] ROM hex source: %s", ROM_HEX_PATH);
        $display("[P5-D] Stimulus dir : %s", STIM_DIR);

        reset_dut();
        load_rom();

        for (i = 0; i < num_cases; i = i + 1) begin
            $display("[P5-D] === case %0d/%0d: tag=%s k_int=%0d ===",
                     i+1, num_cases, case_tag[i], case_k_int[i]);
            // Re-reset between cases to flush the pipeline cleanly.
            reset_dut();
            // ROM is held by inferred BRAM; needs re-load since rst_n drops
            // the BRAM read addr counter but rom contents persist (rom write
            // is unconditional on rst_n). Reload to be safe across resets.
            load_rom();

            stim_path = $sformatf("%s/p5_d_%s.mem", STIM_DIR, case_tag[i]);
            fork
                stream_stimulus(stim_path);
                wait_for_cfo(ok, obs_peak, obs_cfo);
            join

            if (!ok) begin
                $display("[P5-D] FAIL %s: timeout - no cfo_valid", case_tag[i]);
                fail_count++;
            end else if (obs_peak !== case_peak[i] || obs_cfo !== case_cfoint[i]) begin
                $display("[P5-D] FAIL %s: peak_idx=%0d (want %0d)  cfo_int=%0d (want %0d)",
                         case_tag[i], obs_peak, case_peak[i], obs_cfo, case_cfoint[i]);
                fail_count++;
            end else begin
                $display("[P5-D] PASS %s: peak_idx=%0d  cfo_int=%0d", case_tag[i], obs_peak, obs_cfo);
                pass_count++;
            end
        end

        $display("[P5-D] Summary: pass=%0d  fail=%0d  total=%0d", pass_count, fail_count, num_cases);
        if (fail_count == 0)
            $display("GATE: PASS_P5_D_LEVEL1");
        else
            $display("GATE: FAIL_P5_D_LEVEL1 (%0d/%0d failures)", fail_count, num_cases);
        $finish;
    end

endmodule
