`timescale 1ns/1ps

// axi_stream_checker — reusable AXI4-Stream protocol checker
// Compatible with iverilog -g2012 (no assert property; uses always-block monitors)
//
// Assertions:
//   A1  tdata stability  — tdata must not change during an ongoing stall
//   A2  tlast stability  — tlast must not change during an ongoing stall
//   A3  X propagation    — tvalid, tdata (when valid), tlast (when valid) must not be X/Z
//   A4  double TLAST     — two consecutive accepted beats must not both carry tlast=1
//   A5  long stall warn  — warning when stall duration exceeds STALL_WARN_THRESH cycles
//
// "Ongoing stall": consecutive cycles where tvalid=1, tready=0 for the SAME beat.
// A new stall started after a completed handshake (tvalid=1,tready=1) is a new
// transaction; the first cycle of that stall is not compared against the previous beat.
//
// Usage: instantiate once per AXI-Stream channel you wish to monitor.
// Drive enable=0 to quiesce (errors do not accumulate).

module axi_stream_checker #(
    parameter integer DATA_WIDTH        = 32,
    parameter integer STALL_WARN_THRESH = 1000
) (
    input wire                   aclk,
    input wire                   aresetn,

    input wire                   tvalid,
    input wire                   tready,
    input wire [DATA_WIDTH-1:0]  tdata,
    input wire                   tlast,
    input wire                   enable,

    output reg [31:0] err_tdata_stability,  // A1 violations
    output reg [31:0] err_tlast_stability,  // A2 violations
    output reg [31:0] err_x_tvalid,         // A3 tvalid-X cycles
    output reg [31:0] err_x_tdata,          // A3 tdata-X cycles (when valid)
    output reg [31:0] err_x_tlast,          // A3 tlast-X cycles (when valid)
    output reg [31:0] err_double_tlast,     // A4 violations
    output reg [31:0] warn_long_stall,      // A5 warning events
    output wire [31:0] total_errors         // sum of A1+A2+A3+A4 (not A5)
);

    // -----------------------------------------------------------------------
    // A1 + A2: stability during ongoing stall
    // Only compare tdata/tlast on the second and later cycles of a stall.
    // -----------------------------------------------------------------------
    reg                  stab_was_stalled;
    reg [DATA_WIDTH-1:0] stab_prev_tdata;
    reg                  stab_prev_tlast;

    always @(posedge aclk) begin
        if (!aresetn) begin
            stab_was_stalled    <= 1'b0;
            stab_prev_tdata     <= {DATA_WIDTH{1'b0}};
            stab_prev_tlast     <= 1'b0;
            err_tdata_stability <= 32'd0;
            err_tlast_stability <= 32'd0;
        end else if (enable) begin
            if (tvalid && !tready) begin
                if (stab_was_stalled) begin
                    if (tdata !== stab_prev_tdata) begin
                        err_tdata_stability <= err_tdata_stability + 32'd1;
                        $display("[CHK-A1 @%0t] tdata changed mid-stall: prev=0x%08X now=0x%08X",
                                 $time, stab_prev_tdata, tdata);
                    end
                    if (tlast !== stab_prev_tlast) begin
                        err_tlast_stability <= err_tlast_stability + 32'd1;
                        $display("[CHK-A2 @%0t] tlast changed mid-stall: prev=%0b now=%0b",
                                 $time, stab_prev_tlast, tlast);
                    end
                end
                stab_prev_tdata  <= tdata;
                stab_prev_tlast  <= tlast;
                stab_was_stalled <= 1'b1;
            end else begin
                stab_was_stalled <= 1'b0;
            end
        end else begin
            stab_was_stalled <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // A3: X / Z propagation check
    // Use === identity comparison which correctly distinguishes X/Z from 0/1.
    // -----------------------------------------------------------------------
    wire tvalid_is_x = (tvalid === 1'bx) || (tvalid === 1'bz);
    wire tdata_is_x  = (^tdata === 1'bx);   // XOR reduction: 1'bx if any bit is X/Z
    wire tlast_is_x  = (tlast  === 1'bx) || (tlast  === 1'bz);

    always @(posedge aclk) begin
        if (!aresetn) begin
            err_x_tvalid <= 32'd0;
            err_x_tdata  <= 32'd0;
            err_x_tlast  <= 32'd0;
        end else if (enable) begin
            if (tvalid_is_x) begin
                err_x_tvalid <= err_x_tvalid + 32'd1;
                $display("[CHK-A3 @%0t] tvalid is X/Z", $time);
            end
            if (tvalid && tdata_is_x) begin
                err_x_tdata <= err_x_tdata + 32'd1;
                $display("[CHK-A3 @%0t] tdata has X/Z when tvalid=1", $time);
            end
            if (tvalid && tlast_is_x) begin
                err_x_tlast <= err_x_tlast + 32'd1;
                $display("[CHK-A3 @%0t] tlast is X/Z when tvalid=1", $time);
            end
        end
    end

    // -----------------------------------------------------------------------
    // A4: double TLAST — two consecutive accepted beats both carry tlast=1
    // -----------------------------------------------------------------------
    reg a4_prev_tlast;   // tlast value on the most recent accepted beat

    always @(posedge aclk) begin
        if (!aresetn) begin
            a4_prev_tlast    <= 1'b0;
            err_double_tlast <= 32'd0;
        end else if (enable) begin
            if (tvalid && tready) begin
                if (tlast && a4_prev_tlast) begin
                    err_double_tlast <= err_double_tlast + 32'd1;
                    $display("[CHK-A4 @%0t] double TLAST: two consecutive accepted beats both have tlast=1",
                             $time);
                end
                a4_prev_tlast <= tlast;
            end
        end else begin
            a4_prev_tlast <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // A5: long stall warning
    // Counts and warns each time a stall run reaches STALL_WARN_THRESH cycles.
    // One warning event is issued per STALL_WARN_THRESH-cycle threshold crossing.
    // -----------------------------------------------------------------------
    reg [19:0] stall_run_len;
    reg        a5_armed;   // prevents repeated warnings within the same stall run

    always @(posedge aclk) begin
        if (!aresetn) begin
            stall_run_len   <= 20'd0;
            warn_long_stall <= 32'd0;
            a5_armed        <= 1'b1;
        end else if (enable) begin
            if (tvalid && !tready) begin
                if (stall_run_len < 20'hFFFFF)
                    stall_run_len <= stall_run_len + 20'd1;
                if (a5_armed && (stall_run_len >= STALL_WARN_THRESH[19:0] - 1)) begin
                    warn_long_stall <= warn_long_stall + 32'd1;
                    a5_armed        <= 1'b0;
                    $display("[CHK-A5 @%0t] stall duration exceeded %0d cycles",
                             $time, STALL_WARN_THRESH);
                end
            end else begin
                stall_run_len <= 20'd0;
                a5_armed      <= 1'b1;
            end
        end else begin
            stall_run_len <= 20'd0;
            a5_armed      <= 1'b1;
        end
    end

    assign total_errors = err_tdata_stability + err_tlast_stability +
                          err_x_tvalid + err_x_tdata + err_x_tlast +
                          err_double_tlast;

endmodule
