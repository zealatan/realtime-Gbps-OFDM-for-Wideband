// =====================================================================
// rx_eq_complex_div_tb.sv  — self-checking TB for the ZF equalizer core
// ---------------------------------------------------------------------
// Drives all 12 symbols x 256 bins back-to-back (1 complex sample/clk)
// from the golden fft_out.hex (RX) and hest.hex (H). Uses tuser to carry
// the linear bin index so the scoreboard knows the {symbol,bin}. For the
// 221 dataIndx bins of each symbol it compares the equalizer output
// against the golden eq_out.hex (12 x 221, ascending dataIndx order).
//
// GATE OUTPUT (exactly one):
//   GATE_RX_EQ_DIV_UNIT: PASS
//   GATE_RX_EQ_DIV_UNIT: FAIL
//
// PASS criterion: per-component |err| <= ERR_TOL LSB for every one of the
// 2652 equalized data carriers (golden was float->Q15-quantized; the
// fixed-point reciprocal datapath must match within the rounding budget).
// =====================================================================
`timescale 1ns/1ps

module rx_eq_complex_div_tb;

    localparam integer NSYM     = 12;
    localparam integer NBIN     = 256;
    localparam integer NDATA    = 221;
    localparam integer DW       = 16;
    localparam integer HW       = 18;
    localparam integer OW       = 16;
    localparam integer UW       = 16;
    localparam integer ERR_TOL  = 3;     // LSB; model showed worst-case 2

    // ---- golden storage (packed {Q[31:16], I[15:0]}) ----
    reg [31:0] fft_mem  [0:NSYM*NBIN-1];
    reg [31:0] hest_mem [0:NSYM*NBIN-1];
    reg [31:0] eq_mem   [0:NSYM*NDATA-1];
    integer    data_indx [0:NDATA-1];
    // per-bin flag: is this bin a data carrier? and its position in eq_out
    reg        is_data   [0:NBIN-1];
    integer    data_pos  [0:NBIN-1];

    // ---- DUT I/O ----
    reg                 clk, rst_n;
    reg                 in_valid;
    reg  signed [DW-1:0] rx_i, rx_q;
    reg  signed [HW-1:0] h_i,  h_q;
    reg         [UW-1:0] in_user;
    wire                out_valid;
    wire signed [OW-1:0] eq_i, eq_q;
    wire        [UW-1:0] out_user;

    rx_eq_complex_div #(
        .DW(DW), .HW(HW), .OW(OW), .UW(UW),
        .LUT_FILE("golden_lut/rx_equalizer_recip_lut.hex")
    ) dut (
        .clk(clk), .rst_n(rst_n), .ce(1'b1),
        .in_valid(in_valid), .rx_i(rx_i), .rx_q(rx_q),
        .h_i(h_i), .h_q(h_q), .in_user(in_user),
        .out_valid(out_valid), .eq_i(eq_i), .eq_q(eq_q),
        .out_user(out_user)
    );

    // clock
    initial clk = 0;
    always #5 clk = ~clk;

    // sign-extend a 16-bit two's-complement value into 18 bits
    function signed [HW-1:0] sx18; input [15:0] v; sx18 = $signed(v); endfunction
    function signed [15:0]   sx16; input [15:0] v; sx16 = $signed(v); endfunction

    integer i, k, sym, bin, errcnt, checked;
    integer worst_i, worst_q;

    // scoreboard: a flat queue of expected outputs keyed by drive-order.
    // We drive in linear order (sym*256+bin). The DUT preserves order, so
    // outputs arrive in the same order. We track which were data carriers.
    integer drive_cnt;
    integer recv_cnt;

    // expected eq for current output (looked up via out_user = linear idx)
    reg signed [OW-1:0] exp_i, exp_q;

    initial begin
        // load goldens
        $readmemh("golden_in/fft_out.hex",  fft_mem);
        $readmemh("golden_in/hest.hex",     hest_mem);
        $readmemh("golden_in/eq_out.hex",   eq_mem);
    end

    // build data carrier tables from a plain mem file of indices (one per line)
    integer fd, idx, n;
    initial begin
        for (bin=0; bin<NBIN; bin=bin+1) begin is_data[bin]=0; data_pos[bin]=-1; end
        fd = $fopen("golden_in/data_indx_lines.txt", "r");
        if (fd == 0) begin $display("GATE_RX_EQ_DIV_UNIT: FAIL (no data_indx)"); $finish; end
        n = 0;
        while (!$feof(fd) && n < NDATA) begin
            if ($fscanf(fd, "%d\n", idx) == 1) begin
                data_indx[n] = idx;
                is_data[idx] = 1;
                data_pos[idx] = n;
                n = n + 1;
            end
        end
        $fclose(fd);
        if (n != NDATA) begin
            $display("GATE_RX_EQ_DIV_UNIT: FAIL (data_indx count %0d != %0d)", n, NDATA);
            $finish;
        end
    end

    // ---- output scoreboard ----
    initial begin
        errcnt = 0; checked = 0; recv_cnt = 0; worst_i = 0; worst_q = 0;
    end

    integer o_sym, o_bin;   // scoreboard-private (must NOT alias stimulus sym/bin)
    always @(posedge clk) begin
        if (rst_n && out_valid) begin
            o_sym = out_user / NBIN;
            o_bin = out_user % NBIN;
            if (is_data[o_bin]) begin
                // expected from eq_mem at sym*NDATA + data_pos[bin]
                exp_i = sx16(eq_mem[o_sym*NDATA + data_pos[o_bin]][15:0]);
                exp_q = sx16(eq_mem[o_sym*NDATA + data_pos[o_bin]][31:16]);
                checked = checked + 1;
                if (($signed(eq_i) - exp_i) >  worst_i) worst_i =  ($signed(eq_i)-exp_i);
                if ((exp_i - $signed(eq_i)) >  worst_i) worst_i =  (exp_i-$signed(eq_i));
                if (($signed(eq_q) - exp_q) >  worst_q) worst_q =  ($signed(eq_q)-exp_q);
                if ((exp_q - $signed(eq_q)) >  worst_q) worst_q =  (exp_q-$signed(eq_q));
                if ((($signed(eq_i)-exp_i) >  ERR_TOL) || ((exp_i-$signed(eq_i)) > ERR_TOL) ||
                    (($signed(eq_q)-exp_q) >  ERR_TOL) || ((exp_q-$signed(eq_q)) > ERR_TOL)) begin
                    if (errcnt < 20)
                        $display("  MISMATCH sym=%0d bin=%0d got=(%0d,%0d) exp=(%0d,%0d)",
                                 o_sym, o_bin, $signed(eq_i), $signed(eq_q), exp_i, exp_q);
                    errcnt = errcnt + 1;
                end
            end
            recv_cnt = recv_cnt + 1;
        end
    end

    // ---- stimulus ----
    initial begin
        rst_n = 0; in_valid = 0; rx_i=0; rx_q=0; h_i=0; h_q=0; in_user=0;
        drive_cnt = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (sym=0; sym<NSYM; sym=sym+1) begin
            for (bin=0; bin<NBIN; bin=bin+1) begin
                @(negedge clk);
                in_valid <= 1'b1;
                rx_i    <= sx16(fft_mem [sym*NBIN+bin][15:0]);
                rx_q    <= sx16(fft_mem [sym*NBIN+bin][31:16]);
                h_i     <= sx18(hest_mem[sym*NBIN+bin][15:0]);
                h_q     <= sx18(hest_mem[sym*NBIN+bin][31:16]);
                in_user <= sym*NBIN + bin;
                drive_cnt = drive_cnt + 1;
            end
        end
        @(negedge clk);
        in_valid <= 1'b0;

        // flush pipeline
        repeat (32) @(posedge clk);

        // ---- verdict ----
        $display("----------------------------------------------------------");
        $display("[rx_eq_div] drove %0d bins, received %0d outputs, checked %0d data carriers",
                 drive_cnt, recv_cnt, checked);
        $display("[rx_eq_div] worst |err|: I=%0d LSB  Q=%0d LSB  (tol=%0d)", worst_i, worst_q, ERR_TOL);
        if (checked != NSYM*NDATA) begin
            $display("GATE_RX_EQ_DIV_UNIT: FAIL (checked %0d != %0d)", checked, NSYM*NDATA);
        end else if (errcnt != 0) begin
            $display("GATE_RX_EQ_DIV_UNIT: FAIL (%0d mismatches)", errcnt);
        end else begin
            $display("GATE_RX_EQ_DIV_UNIT: PASS");
        end
        $finish;
    end

    // watchdog
    initial begin
        #2000000;
        $display("GATE_RX_EQ_DIV_UNIT: FAIL (timeout)");
        $finish;
    end

endmodule
