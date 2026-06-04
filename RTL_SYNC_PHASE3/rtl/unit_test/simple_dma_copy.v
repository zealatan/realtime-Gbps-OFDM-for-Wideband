`timescale 1ns/1ps

// Simple DMA copy engine: reads one 32-bit word from src_addr, writes it to dst_addr.
//
// FSM (read-first):
//   IDLE    : wait for start; latch src_addr, dst_addr
//   RD_ADDR : drive arvalid; wait for arready
//   RD_DATA : drive rready; wait for rvalid; latch rdata and rresp
//             if rresp != OKAY → skip write, go directly to DONE
//   WR_ADDR : drive awvalid+wvalid simultaneously; wait for awready&&wready
//   WR_RESP : drive bready; wait for bvalid; latch bresp
//   DONE    : assert done and error for one cycle; return to IDLE
module simple_dma_copy (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        start,
    input  wire [31:0] src_addr,
    input  wire [31:0] dst_addr,

    output wire [31:0] copied_data,
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
    reg [31:0] rdata_lat;
    reg        read_err;
    reg        write_err;
    reg        done_r;
    reg        error_r;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state     <= IDLE;
            src_lat   <= 32'h0;
            dst_lat   <= 32'h0;
            rdata_lat <= 32'h0;
            read_err  <= 1'b0;
            write_err <= 1'b0;
            done_r    <= 1'b0;
            error_r   <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    done_r    <= 1'b0;
                    error_r   <= 1'b0;
                    read_err  <= 1'b0;
                    write_err <= 1'b0;
                    if (start) begin
                        src_lat <= src_addr;
                        dst_lat <= dst_addr;
                        state   <= RD_ADDR;
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
                        // Read error: abort write, jump straight to DONE
                        state     <= (rresp != 2'b00) ? DONE : WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (awready && wready)
                        state <= WR_RESP;
                end

                WR_RESP: begin
                    if (bvalid) begin
                        write_err <= (bresp != 2'b00);
                        state     <= DONE;
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
    assign araddr  = src_lat;
    assign rready  = (state == RD_DATA);
    assign awvalid = (state == WR_ADDR);
    assign awaddr  = dst_lat;
    assign wvalid  = (state == WR_ADDR);
    assign wdata   = rdata_lat;
    assign wstrb   = 4'hF;
    assign wlast   = 1'b1;
    assign bready  = (state == WR_RESP);

    assign copied_data = rdata_lat;
    assign done        = done_r;
    assign error       = error_r;

endmodule
