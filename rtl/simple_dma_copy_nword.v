`timescale 1ns/1ps

// N-word DMA copy engine: reads length_words 32-bit words starting at
// src_addr and writes them to dst_addr (word-sequential, no overlap check).
//
// FSM (read-first, loops per word):
//   IDLE    : wait for start; if length_words==0 → DONE; else latch addrs/len
//   RD_ADDR : drive arvalid; wait for arready
//   RD_DATA : drive rready; wait for rvalid; latch rdata/rresp
//             if rresp != OKAY → read_err=1, DONE (abort, no write)
//   WR_ADDR : drive awvalid+wvalid simultaneously; wait for awready&&wready
//   WR_RESP : drive bready; wait for bvalid; latch bresp
//             if bresp != OKAY → write_err=1, DONE (abort)
//             else copied_count_r++; last word → DONE; else word_idx++, RD_ADDR
//   DONE    : assert done=1, error=read_err|write_err; → IDLE
module simple_dma_copy_nword (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        start,
    input  wire [31:0] src_addr,
    input  wire [31:0] dst_addr,
    input  wire [15:0] length_words,

    output wire [31:0] last_copied_data,
    output wire [15:0] copied_count,
    output wire        done,
    output wire        error,

    // Read address channel
    output wire [31:0] araddr,
    output wire        arvalid,
    input  wire        arready,

    // Read data channel
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready,

    // Write address channel
    output wire [31:0] awaddr,
    output wire        awvalid,
    input  wire        awready,

    // Write data channel
    output wire [31:0] wdata,
    output wire [ 3:0] wstrb,
    output wire        wlast,
    output wire        wvalid,
    input  wire        wready,

    // Write response channel
    input  wire [ 1:0] bresp,
    input  wire        bvalid,
    output wire        bready
);

    localparam IDLE    = 3'd0;
    localparam RD_ADDR = 3'd1;
    localparam RD_DATA = 3'd2;
    localparam WR_ADDR = 3'd3;
    localparam WR_RESP = 3'd4;
    localparam DONE    = 3'd5;

    reg [2:0]  state;
    reg [31:0] src_lat;
    reg [31:0] dst_lat;
    reg [15:0] len_lat;
    reg [15:0] word_idx;
    reg [31:0] rdata_lat;
    reg [15:0] copied_count_r;
    reg        read_err;
    reg        write_err;
    reg        done_r;
    reg        error_r;

    // Current word byte addresses (combinatorial)
    wire [31:0] cur_raddr = src_lat + {16'b0, word_idx} * 4;
    wire [31:0] cur_waddr = dst_lat + {16'b0, word_idx} * 4;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state           <= IDLE;
            src_lat         <= 32'h0;
            dst_lat         <= 32'h0;
            len_lat         <= 16'h0;
            word_idx        <= 16'h0;
            rdata_lat       <= 32'h0;
            copied_count_r  <= 16'h0;
            read_err        <= 1'b0;
            write_err       <= 1'b0;
            done_r          <= 1'b0;
            error_r         <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    done_r         <= 1'b0;
                    error_r        <= 1'b0;
                    read_err       <= 1'b0;
                    write_err      <= 1'b0;
                    word_idx       <= 16'h0;
                    copied_count_r <= 16'h0;
                    if (start) begin
                        src_lat <= src_addr;
                        dst_lat <= dst_addr;
                        len_lat <= length_words;
                        state   <= (length_words == 16'h0) ? DONE : RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (arready)
                        state <= RD_DATA;
                end

                RD_DATA: begin
                    if (rvalid) begin
                        rdata_lat <= rdata;
                        read_err  <= (rresp != 2'b00);
                        state     <= (rresp != 2'b00) ? DONE : WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (awready && wready)
                        state <= WR_RESP;
                end

                WR_RESP: begin
                    if (bvalid) begin
                        if (bresp != 2'b00) begin
                            write_err <= 1'b1;
                            state     <= DONE;
                        end else begin
                            copied_count_r <= copied_count_r + 16'h1;
                            if (word_idx == len_lat - 16'h1) begin
                                state <= DONE;
                            end else begin
                                word_idx <= word_idx + 16'h1;
                                state    <= RD_ADDR;
                            end
                        end
                    end
                end

                DONE: begin
                    done_r  <= 1'b1;
                    error_r <= read_err | write_err;
                    state   <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // AXI outputs driven combinatorially from FSM state
    assign arvalid = (state == RD_ADDR);
    assign araddr  = cur_raddr;
    assign rready  = (state == RD_DATA);
    assign awvalid = (state == WR_ADDR);
    assign awaddr  = cur_waddr;
    assign wvalid  = (state == WR_ADDR);
    assign wdata   = rdata_lat;
    assign wstrb   = 4'hF;
    assign wlast   = 1'b1;
    assign bready  = (state == WR_RESP);

    assign last_copied_data = rdata_lat;
    assign copied_count     = copied_count_r;
    assign done             = done_r;
    assign error            = error_r;

endmodule
