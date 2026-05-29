`timescale 1ns/1ps
// P2-04: Window-based streaming peak detector
// Divides the valid-sample stream into windows of (NSC+CP_LEN) samples.
// At the end of each window, emits a 1-cycle timing_lock pulse with the
// index and P value of the sample that had the highest metric in that window.
module streaming_peak_detector #(
    parameter integer ACC_W    = 48,
    parameter integer METRIC_W = 32,
    parameter integer NSC      = 256,
    parameter integer CP_LEN   = 32
) (
    input  wire                     clk,
    input  wire                     aresetn,
    input  wire  [METRIC_W-1:0]     metric,
    input  wire                     in_valid,
    input  wire  [31:0]             sample_index,
    input  wire  signed [ACC_W-1:0] p_i,
    input  wire  signed [ACC_W-1:0] p_q,
    output reg                      timing_lock,
    output reg   [31:0]             lock_index,
    output reg   signed [ACC_W-1:0] peak_p_i,
    output reg   signed [ACC_W-1:0] peak_p_q
);

    localparam integer WINDOW = NSC + CP_LEN; // 288 with defaults

    // Window sample counter (counts valid samples, 0..WINDOW-1)
    reg [8:0]             win_cnt;

    // Running maximum state within current window
    reg [METRIC_W-1:0]    max_metric;
    reg [31:0]            max_index;
    reg signed [ACC_W-1:0] max_p_i;
    reg signed [ACC_W-1:0] max_p_q;

    // Set when at least one non-zero metric sample has been seen this window
    reg has_peak;

    always @(posedge clk or negedge aresetn) begin
        if (!aresetn) begin
            timing_lock <= 1'b0;
            lock_index  <= 32'd0;
            peak_p_i    <= {ACC_W{1'b0}};
            peak_p_q    <= {ACC_W{1'b0}};
            win_cnt     <= 9'd0;
            max_metric  <= {METRIC_W{1'b0}};
            max_index   <= 32'd0;
            max_p_i     <= {ACC_W{1'b0}};
            max_p_q     <= {ACC_W{1'b0}};
            has_peak    <= 1'b0;
        end else begin
            // Default: deassert timing_lock every cycle
            timing_lock <= 1'b0;

            if (in_valid) begin
                // -----------------------------------------------------------------
                // Step a: update running maximum (unsigned metric comparison)
                // -----------------------------------------------------------------
                if (metric > max_metric) begin
                    max_metric <= metric;
                    max_index  <= sample_index;
                    max_p_i    <= p_i;
                    max_p_q    <= p_q;
                end

                // Track whether any positive metric has been seen
                if (metric > {METRIC_W{1'b0}}) begin
                    has_peak <= 1'b1;
                end

                // -----------------------------------------------------------------
                // Step b/c: check for end of window
                // -----------------------------------------------------------------
                if (win_cnt == (WINDOW - 1)) begin
                    // End of window: emit timing lock if we had a valid peak
                    if (has_peak || (metric > {METRIC_W{1'b0}})) begin
                        timing_lock <= 1'b1;
                        // If the current sample is better than tracked max, use it
                        if (metric > max_metric) begin
                            lock_index <= sample_index;
                            peak_p_i   <= p_i;
                            peak_p_q   <= p_q;
                        end else begin
                            lock_index <= max_index;
                            peak_p_i   <= max_p_i;
                            peak_p_q   <= max_p_q;
                        end
                    end
                    // Reset window state
                    win_cnt    <= 9'd0;
                    max_metric <= {METRIC_W{1'b0}};
                    max_index  <= 32'd0;
                    max_p_i    <= {ACC_W{1'b0}};
                    max_p_q    <= {ACC_W{1'b0}};
                    has_peak   <= 1'b0;
                end else begin
                    // -----------------------------------------------------------------
                    // Step d: advance counter
                    // -----------------------------------------------------------------
                    win_cnt <= win_cnt + 9'd1;
                end
            end
        end
    end

endmodule
