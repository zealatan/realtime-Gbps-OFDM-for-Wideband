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
    // Behavioral memory. P5-04 Iter 3: ram_style="block" hint was IGNORED
    // by Vivado (still RAMD64E). Iter 4 instead breaks the wr_ptr →
    // memory write path with an explicit 1-cycle staging register so
    // the high-fanout wr_ptr is no longer in the same clock path as
    // the 4096-entry distributed-RAM decoder.
    // -----------------------------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Accept condition: AXI-Stream write accepted on this clock
    wire accept = busy && s_axis_tvalid && !full && !wb_en;

    // Back-pressure: only ready when actively capturing and not blocked
    assign s_axis_tready = busy && !full && !wb_en;

    // -----------------------------------------------------------------------
    // Write staging register (P5-04 Iter 4 timing cut)
    // mem write is now 1 cycle later than wr_ptr/accept. capture_done is
    // delayed below to keep downstream reads from racing the last write.
    // -----------------------------------------------------------------------
    reg                  wr_en_q;
    reg [ADDR_WIDTH-1:0] wr_addr_q;
    reg [DATA_WIDTH-1:0] wr_data_q;
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_en_q   <= 1'b0;
            wr_addr_q <= {ADDR_WIDTH{1'b0}};
            wr_data_q <= {DATA_WIDTH{1'b0}};
        end else begin
            wr_en_q <= wb_en || accept;
            if (wb_en) begin
                wr_addr_q <= wb_addr;
                wr_data_q <= wb_data;
            end else if (accept) begin
                wr_addr_q <= wr_ptr;
                wr_data_q <= s_axis_tdata;
            end
        end
    end

    always @(posedge aclk) begin
        if (wr_en_q) mem[wr_addr_q] <= wr_data_q;
    end

    // -----------------------------------------------------------------------
    // Read port — synchronous registered output, 1-clock latency
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (rd_en)
            rd_data <= mem[rd_addr];
    end

    // -----------------------------------------------------------------------
    // Capture control. P5-04 Iter 4: capture_done is 1 cycle delayed so
    // downstream FSMs only observe it after the last sample has been
    // written through the wr_*_q staging registers into mem.
    // -----------------------------------------------------------------------
    reg capture_done_raw;
    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wr_ptr           <= {ADDR_WIDTH{1'b0}};
            sample_count     <= {(ADDR_WIDTH+1){1'b0}};
            capture_done_raw <= 1'b0;
            capture_done     <= 1'b0;
            busy             <= 1'b0;
            full             <= 1'b0;
        end else begin
            capture_done_raw <= 1'b0;
            capture_done     <= capture_done_raw;  // 1-cycle delay

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
                    capture_done_raw <= 1'b1;
                    busy             <= 1'b0;
                    if (&wr_ptr) full <= 1'b1;
                end
            end
        end
    end

`ifdef TIMING_PROBE
    integer buf_hi_cnt;
    integer buf_wr_cnt;
    initial buf_hi_cnt = 0;
    initial buf_wr_cnt = 0;
    always @(posedge aclk) begin
        // Log first 60 fill writes (accept=1) showing address, data, and tvalid
        if (accept && buf_wr_cnt < 60) begin
            $display("[BUF_WR] t=%0t wr[%0d]: wr_ptr=%0d tdata=%08x tvalid=%0b tready=%0b",
                     $time, buf_wr_cnt, wr_ptr, s_axis_tdata, s_axis_tvalid, s_axis_tready);
            buf_wr_cnt = buf_wr_cnt + 1;
        end
        // Show everything in the window around TST scan start
        if ($time >= 8540 && $time <= 8580)
            $display("[BUF_TW] t=%0t rd_en=%0b rd_addr=%0d rd_data=%08x", $time, rd_en, rd_addr, rd_data);
        // First 30 reads after TST scan starts
        if (rd_en && $time > 8540 && buf_hi_cnt < 30) begin
            $display("[BUF_HI] t=%0t hi[%0d]: rd_addr=%0d mem=%08x rd_data=%08x",
                     $time, buf_hi_cnt, rd_addr, mem[rd_addr], rd_data);
            buf_hi_cnt = buf_hi_cnt + 1;
        end
    end
`endif

endmodule
