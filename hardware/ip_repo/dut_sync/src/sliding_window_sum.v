`timescale 1ns/1ps

// sliding_window_sum: rolling energy accumulation window.
//
// On each sample_valid pulse:
//   - Appends sample_power to a circular ring buffer (depth = window_len).
//   - If window not yet full: accumulates sum, increments fill counter.
//   - Once window full: subtracts oldest entry, adds new entry (true sliding).
//   - Asserts window_valid for one cycle after each sample once the window is full.
//   - window_start_addr = sample_addr_in - window_len + 1 (monotonic scan assumed).
//
// Parameters:
//   POWER_WIDTH    per-sample I^2+Q^2 width  (default 33)
//   ENERGY_WIDTH   accumulator width          (default 40)
//   ADDR_WIDTH     sample address width       (default 12)
//   MAX_WINDOW     maximum supported window   (default 64, ring buffer depth)
//
// No Case1/Case2 logic, no frame detection, no buffer read logic.

module sliding_window_sum #(
    parameter integer POWER_WIDTH  = 33,
    parameter integer ENERGY_WIDTH = 40,
    parameter integer ADDR_WIDTH   = 12,
    parameter integer MAX_WINDOW   = 64
) (
    input  wire                         aclk,
    input  wire                         aresetn,
    input  wire                         clear,          // synchronous clear

    input  wire [POWER_WIDTH-1:0]       sample_power,
    input  wire                         sample_valid,
    input  wire [ADDR_WIDTH-1:0]        sample_addr_in, // buffer addr of this sample
    input  wire [6:0]                   window_len,     // 1..MAX_WINDOW

    output reg  [ENERGY_WIDTH-1:0]      window_energy,
    output reg                          window_valid,
    output reg  [ADDR_WIDTH-1:0]        window_start_addr
);

    localparam integer PTR_W = $clog2(MAX_WINDOW);

    reg [POWER_WIDTH-1:0]  ring [0:MAX_WINDOW-1];
    reg [PTR_W-1:0]        wr_ptr;
    reg [6:0]              win_fill;
    reg [ENERGY_WIDTH-1:0] energy_acc;

    integer i;

    always @(posedge aclk) begin
        if (!aresetn || clear) begin
            wr_ptr       <= {PTR_W{1'b0}};
            win_fill     <= 7'd0;
            energy_acc   <= {ENERGY_WIDTH{1'b0}};
            window_valid <= 1'b0;
            window_energy<= {ENERGY_WIDTH{1'b0}};
            window_start_addr <= {ADDR_WIDTH{1'b0}};
            for (i = 0; i < MAX_WINDOW; i = i + 1)
                ring[i] <= {POWER_WIDTH{1'b0}};
        end else begin
            window_valid <= 1'b0;   // default: deassert each cycle

            if (sample_valid) begin
                // Advance write pointer and store new power
                ring[wr_ptr] <= sample_power;
                wr_ptr <= (wr_ptr == window_len - 1) ? {PTR_W{1'b0}} : wr_ptr + 1;

                if (win_fill < window_len) begin
                    // Window still filling
                    energy_acc <= energy_acc
                                + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, sample_power};
                    win_fill   <= win_fill + 7'd1;

                    if (win_fill + 1 == window_len) begin
                        // First window just completed
                        window_energy     <= energy_acc
                                          + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, sample_power};
                        window_valid      <= 1'b1;
                        window_start_addr <= sample_addr_in
                                          - {{(ADDR_WIDTH-7){1'b0}}, window_len} + 1;
                    end
                end else begin
                    // Sliding: subtract oldest (currently at wr_ptr, before overwrite)
                    // Note: ring[wr_ptr] was read before write above — use a temp.
                    energy_acc <= energy_acc
                                + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, sample_power}
                                - {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, ring[wr_ptr]};
                    window_energy     <= energy_acc
                                      + {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, sample_power}
                                      - {{(ENERGY_WIDTH-POWER_WIDTH){1'b0}}, ring[wr_ptr]};
                    window_valid      <= 1'b1;
                    window_start_addr <= sample_addr_in
                                      - {{(ADDR_WIDTH-7){1'b0}}, window_len} + 1;
                end
            end
        end
    end

endmodule
