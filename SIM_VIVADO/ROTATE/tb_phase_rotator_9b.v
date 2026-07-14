`timescale 1ns/1ps
`default_nettype none

module tb_phase_rotator_9b;

    reg                clk;
    reg                rst_n;

    reg  [8:0]         phase_cordic_9bit;
    reg                phase_strobe;

    reg  signed [15:0] in_I;
    reg  signed [15:0] in_Q;

    wire signed [63:0] rot_out_I;
    wire signed [63:0] rot_out_Q;
    wire               output_strobe;

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    phase_rotator_9b #
    (
        .LUT_DEPTH(512),
        .DELAY_T(2)
    )
    dut
    (
        .clk              (clk),
        .rst_n            (rst_n),
        .phase_cordic_9bit(phase_cordic_9bit),
        .phase_strobe     (phase_strobe),
        .in_I             (in_I),
        .in_Q             (in_Q),
        .rot_out_I        (rot_out_I),
        .rot_out_Q        (rot_out_Q),
        .output_strobe    (output_strobe)
    );

    // ----------------------------------------------------------------
    // clock
    // ----------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;   // 100 MHz
    end

    // ----------------------------------------------------------------
    // stimulus
    // ----------------------------------------------------------------
    integer fout;
    integer n;

    initial begin
        fout = $fopen("rotator_out.txt", "w");
        if (fout == 0) begin
            $display("[ERROR] failed to open rotator_out.txt");
            $finish;
        end
    end

    initial begin
        $dumpfile("tb_phase_rotator_9b.vcd");
        $dumpvars(0, tb_phase_rotator_9b);

        rst_n             = 1'b0;
        phase_cordic_9bit = 9'd0;
        phase_strobe      = 1'b0;
        in_I              = 16'sd0;
        in_Q              = 16'sd0;

        #100;
        rst_n = 1'b1;
        #20;

        // ------------------------------------------------------------
        // Case 1: constant input, small phase increment
        // ------------------------------------------------------------
        $display("=== Case 1: constant complex input, small phase increment ===");

        phase_cordic_9bit = 9'd1;

        for (n = 0; n < 40; n = n + 1) begin
            @(posedge clk);
            phase_strobe <= 1'b1;
            in_I         <= 16'sd1000;
            in_Q         <= 16'sd0;
        end

        @(posedge clk);
        phase_strobe <= 1'b0;
        in_I         <= 16'sd0;
        in_Q         <= 16'sd0;

        repeat (10) @(posedge clk);

        // ------------------------------------------------------------
        // Case 2: bigger phase increment
        // ------------------------------------------------------------
        $display("=== Case 2: constant complex input, larger phase increment ===");

        phase_cordic_9bit = 9'd4;

        for (n = 0; n < 40; n = n + 1) begin
            @(posedge clk);
            phase_strobe <= 1'b1;
            in_I         <= 16'sd1000;
            in_Q         <= 16'sd500;
        end

        @(posedge clk);
        phase_strobe <= 1'b0;
        in_I         <= 16'sd0;
        in_Q         <= 16'sd0;

        repeat (10) @(posedge clk);

        // ------------------------------------------------------------
        // Case 3: negative rotation using 9-bit two's complement
        // -1 => 9'h1FF
        // ------------------------------------------------------------
        $display("=== Case 3: negative phase increment ===");

        phase_cordic_9bit = 9'h1FF;

        for (n = 0; n < 40; n = n + 1) begin
            @(posedge clk);
            phase_strobe <= 1'b1;
            in_I         <= 16'sd1200;
            in_Q         <= -16'sd300;
        end

        @(posedge clk);
        phase_strobe <= 1'b0;
        in_I         <= 16'sd0;
        in_Q         <= 16'sd0;

        repeat (20) @(posedge clk);

        $fclose(fout);
        $finish;
    end

    // ----------------------------------------------------------------
    // monitor
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (output_strobe) begin
            $display("[OUT] t=%0t, outI=%0d, outQ=%0d",
                     $time, rot_out_I, rot_out_Q);

            $fwrite(fout, "%0t %0d %0d\n",
                    $time, rot_out_I, rot_out_Q);
        end
    end

endmodule

`default_nettype wire
