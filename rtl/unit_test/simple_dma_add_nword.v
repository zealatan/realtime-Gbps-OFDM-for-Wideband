`timescale 1ns/1ps

// N-word DMA processing engine: reads each word, adds a programmable constant,
// and writes the result.  Identical FSM structure to simple_dma_copy_nword;
// the only datapath difference is the combinatorial adder between read and write.
//
// FSM (read-first, one word at a time):
//   IDLE    : wait for start; if length_words==0 → DONE; else latch inputs
//   RD_ADDR : drive arvalid; wait for arready
//   RD_DATA : drive rready; wait for rvalid; latch input word
//             if rresp != OKAY → read_err=1, DONE (abort before write)
//   WR_ADDR : drive awvalid+wvalid; wdata = input_lat + add_lat (comb);
//             wait for awready&&wready
//   WR_RESP : drive bready; wait for bvalid
//             if bresp != OKAY → write_err=1, DONE (abort)
//             else processed_count++; last word → DONE; else word_idx++, RD_ADDR
//   DONE    : assert done=1, error=read_err|write_err; → IDLE
module simple_dma_add_nword (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        start,
    input  wire [31:0] src_addr,
    input  wire [31:0] dst_addr,
    input  wire [15:0] length_words,
    input  wire [31:0] add_value,

    output wire [31:0] last_input_data,
    output wire [31:0] last_output_data,
    output wire [15:0] processed_count,
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
    reg [31:0] add_lat;
    reg [15:0] word_idx;
    reg [31:0] input_lat;           // latched read data
    reg [15:0] processed_count_r;
    reg        read_err;
    reg        write_err;
    reg        done_r;
    reg        error_r;

    // Current word byte addresses (combinatorial)
    wire [31:0] cur_raddr = src_lat + {16'b0, word_idx} * 4;
    wire [31:0] cur_waddr = dst_lat + {16'b0, word_idx} * 4;

    // Processing datapath — purely combinatorial
    wire [31:0] processed_data = input_lat + add_lat;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state             <= IDLE;
            src_lat           <= 32'h0;
            dst_lat           <= 32'h0;
            len_lat           <= 16'h0;
            add_lat           <= 32'h0;
            word_idx          <= 16'h0;
            input_lat         <= 32'h0;
            processed_count_r <= 16'h0;
            read_err          <= 1'b0;
            write_err         <= 1'b0;
            done_r            <= 1'b0;
            error_r           <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    done_r            <= 1'b0;
                    error_r           <= 1'b0;
                    read_err          <= 1'b0;
                    write_err         <= 1'b0;
                    word_idx          <= 16'h0;
                    processed_count_r <= 16'h0;
                    if (start) begin
                        src_lat <= src_addr;
                        dst_lat <= dst_addr;
                        len_lat <= length_words;
                        add_lat <= add_value;
                        state   <= (length_words == 16'h0) ? DONE : RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (arready)
                        state <= RD_DATA;
                end

                RD_DATA: begin
                    if (rvalid) begin
                        input_lat <= rdata;
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
                            processed_count_r <= processed_count_r + 16'h1;
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
    assign wdata   = processed_data;   // input + add_value (combinatorial)
    assign wstrb   = 4'hF;
    assign wlast   = 1'b1;
    assign bready  = (state == WR_RESP);

    assign last_input_data  = input_lat;
    assign last_output_data = processed_data;
    assign processed_count  = processed_count_r;
    assign done             = done_r;
    assign error            = error_r;

endmodule
