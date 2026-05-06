`timescale 1ns/1ps

// IQ frame buffer: captures one AXI-Stream IQ frame into a reg-array memory
// and provides random-access read and write-back ports for downstream stages.
//
// Write sources (mutually exclusive; wb_en takes priority):
//   1. AXI-Stream fill:  sequential writes from address 0, address auto-increment.
//      Activated by capture_start.  Terminates on s_axis_tlast or when the last
//      address is written (full condition).  s_axis_tready is deasserted when
//      wb_en is high or when the buffer is full.
//   2. Write-back (wb_*): explicit address, used by complex_rotator during CFO
//      correction to overwrite samples with corrected values.  May be used at
//      any time regardless of busy/full state.
//
// Read port: synchronous registered output, 1-clock latency.
//   rd_data is updated when rd_en=1; holds last value otherwise.
//
// Constraints:
//   DEPTH must equal 2^ADDR_WIDTH.
//   wb_en and capture_start must not be asserted in the same clock.
//
// Parameters:
//   DATA_WIDTH  Width of each sample word (default 32 = {Q[31:16], I[15:0]})
//   ADDR_WIDTH  Address width; DEPTH = 2^ADDR_WIDTH (default 12 → 4096 entries)
//   DEPTH       Memory depth; must be 2^ADDR_WIDTH

module iq_frame_buffer #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 12,
    parameter integer DEPTH      = 4096
) (
    input  wire                    aclk,
    input  wire                    aresetn,        // active-low synchronous reset

    // ---- AXI-Stream fill port ----
    input  wire                    capture_start,  // 1-clock pulse: begin new capture
    input  wire [DATA_WIDTH-1:0]   s_axis_tdata,   // {Q[31:16], I[15:0]}
    input  wire                    s_axis_tvalid,
    output wire                    s_axis_tready,  // deasserted when !busy or full or wb_en
    input  wire                    s_axis_tlast,   // terminates capture

    // ---- Write-back port (raw; wb_en has priority over AXI-Stream) ----
    input  wire                    wb_en,
    input  wire [ADDR_WIDTH-1:0]   wb_addr,
    input  wire [DATA_WIDTH-1:0]   wb_data,

    // ---- Random-access read port (1-clock registered latency) ----
    input  wire                    rd_en,          // gate; tie high for continuous read
    input  wire [ADDR_WIDTH-1:0]   rd_addr,
    output reg  [DATA_WIDTH-1:0]   rd_data,

    // ---- Status ----
    output reg  [ADDR_WIDTH-1:0]   wr_ptr,         // next fill write address
    output reg  [ADDR_WIDTH:0]     sample_count,   // samples written this fill (0..DEPTH)
    output reg                     capture_done,    // 1-clock pulse: tlast received or full
    output reg                     busy,            // high from capture_start until capture_done
    output reg                     full             // high after DEPTH samples written
);

    // -----------------------------------------------------------------------
    // Behavioral memory (maps to distributed RAM or BRAM depending on synth)
    // -----------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Accept condition: AXI-Stream write accepted on this clock
    wire accept = busy && s_axis_tvalid && !full && !wb_en;

    // Back-pressure: only ready when actively capturing and not blocked
    assign s_axis_tready = busy && !full && !wb_en;

    // -----------------------------------------------------------------------
    // Write port — wb_en has priority over AXI-Stream fill
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (wb_en)
            mem[wb_addr] <= wb_data;
        else if (accept)
            mem[wr_ptr]  <= s_axis_tdata;
    end

    // -----------------------------------------------------------------------
    // Read port — synchronous registered output, 1-clock latency
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

    // -----------------------------------------------------------------------
    // Capture control
    // -----------------------------------------------------------------------
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr       <= {ADDR_WIDTH{1'b0}};
            sample_count <= {(ADDR_WIDTH+1){1'b0}};
            capture_done <= 1'b0;
            busy         <= 1'b0;
            full         <= 1'b0;
        end else begin
            capture_done <= 1'b0;   // default: 1-clock pulse

            if (capture_start && !busy) begin
                // Begin new capture; reset pointer and counters
                busy         <= 1'b1;
                wr_ptr       <= {ADDR_WIDTH{1'b0}};
                sample_count <= {(ADDR_WIDTH+1){1'b0}};
                full         <= 1'b0;
            end else if (accept) begin
                wr_ptr       <= wr_ptr + 1'b1;
                sample_count <= sample_count + 1'b1;

                // Terminate on tlast or when the last address is filled (&wr_ptr requires DEPTH=2^ADDR_WIDTH)
                if (s_axis_tlast || (&wr_ptr)) begin
                    capture_done <= 1'b1;
                    busy         <= 1'b0;
                    if (&wr_ptr) full <= 1'b1;
                end
            end
        end
    end

endmodule
