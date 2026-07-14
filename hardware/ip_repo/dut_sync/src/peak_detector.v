`timescale 1ns/1ps

// Streaming unsigned argmax with start/done control protocol.
//
// Scans a sequence of METRIC_WIDTH-wide unsigned values (one per clock
// while data_valid=1) and reports the index and value of the maximum.
// Tie-break: first occurrence wins (strict > comparison).
//
// Control protocol:
//   - Pulse start=1 for one clock to begin a new scan.  The module latches
//     max_count on the same edge and clears all internal state.
//   - Feed data_in/data_valid/data_last.  data_last terminates the scan on
//     the clock it is accepted (data_valid && data_last).
//   - done pulses high for exactly one clock after the last value is accepted.
//   - peak_index and peak_value are stable from done until the next start.
//
// Constraints:
//   COUNT_WIDTH >= INDEX_WIDTH
//   max_count <= 2^COUNT_WIDTH - 1; set to 0 to disable the overflow check.
//
// Error (sticky, cleared only by aresetn):
//   - start asserted while busy
//   - data_valid without data_last after count reaches max_count (when max_count != 0)

module peak_detector #(
    parameter integer METRIC_WIDTH = 64,
    parameter integer INDEX_WIDTH  = 9,
    parameter integer COUNT_WIDTH  = 10
) (
    input  wire                      aclk,
    input  wire                      aresetn,      // active-low synchronous reset

    // Control
    input  wire                      start,        // 1-clock pulse; ignored while busy
    input  wire [COUNT_WIDTH-1:0]    max_count,    // expected number of values; 0 = no limit check

    // Streaming input (valid-gated; may be non-contiguous)
    input  wire [METRIC_WIDTH-1:0]   data_in,
    input  wire                      data_valid,
    input  wire                      data_last,    // terminates scan when data_valid=1

    // Outputs
    output reg  [INDEX_WIDTH-1:0]    peak_index,   // 0-based index of maximum
    output reg  [METRIC_WIDTH-1:0]   peak_value,   // maximum value seen
    output reg                       done,         // 1-clock pulse on scan completion
    output reg                       busy,         // high from start until done
    output reg                       error         // sticky flag
);

    reg [COUNT_WIDTH-1:0]  count;        // samples accepted this scan
    reg [METRIC_WIDTH-1:0] running_max;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            peak_index  <= {INDEX_WIDTH{1'b0}};
            peak_value  <= {METRIC_WIDTH{1'b0}};
            running_max <= {METRIC_WIDTH{1'b0}};
            count       <= {COUNT_WIDTH{1'b0}};
            done        <= 1'b0;
            busy        <= 1'b0;
            error       <= 1'b0;
        end else begin
            done <= 1'b0;   // default: done is a 1-clock pulse

            // --- start handling (checked first; does not process data on same clock) ---
            if (start) begin
                if (!busy) begin
                    busy        <= 1'b1;
                    count       <= {COUNT_WIDTH{1'b0}};
                    running_max <= {METRIC_WIDTH{1'b0}};
                    peak_index  <= {INDEX_WIDTH{1'b0}};
                    peak_value  <= {METRIC_WIDTH{1'b0}};
                end else begin
                    error <= 1'b1;   // start while busy
                end
            end

            // --- data processing (runs independently; both blocks may fire if start=0) ---
            if (!start && busy && data_valid) begin
                // Update peak on strict improvement → first occurrence wins on ties
                if (data_in > running_max) begin
                    running_max <= data_in;
                    peak_value  <= data_in;
                    peak_index  <= count[INDEX_WIDTH-1:0];
                end

                if (data_last) begin
                    done <= 1'b1;
                    busy <= 1'b0;
                end else begin
                    // Overflow check: if we are about to exceed max_count, set error.
                    // Condition: count is about to become max_count (i.e. count == max_count-1)
                    // and data_last has not been seen.  Skip when max_count==0.
                    if (|max_count && (count == max_count - 1'b1)) begin
                        error <= 1'b1;
                    end
                    count <= count + 1'b1;
                end
            end
        end
    end

endmodule
