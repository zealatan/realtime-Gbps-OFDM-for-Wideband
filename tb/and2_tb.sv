`timescale 1ns/1ps

module and2_tb;

    logic a;
    logic b;
    wire  y;

    and2 dut (
        .a(a),
        .b(b),
        .y(y)
    );

    task automatic check;
        input logic ta;
        input logic tb;
        input logic expected;
        begin
            a = ta;
            b = tb;
            #10;

            $display("[TEST] a=%0b b=%0b y=%0b expected=%0b", a, b, y, expected);

            if (y !== expected) begin
                $display("[FAIL] a=%0b b=%0b y=%0b expected=%0b", a, b, y, expected);
                $finish;
            end
        end
    endtask

    initial begin
        $display("[INFO] AND2 simulation started");

        check(1'b0, 1'b0, 1'b0);
        check(1'b0, 1'b1, 1'b0);
        check(1'b1, 1'b0, 1'b0);
        check(1'b1, 1'b1, 1'b1);

        $display("[PASS] AND2 simulation passed");
        $finish;
    end

endmodule
