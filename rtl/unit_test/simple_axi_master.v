`timescale 1ns/1ps

// Single-beat AXI4 master: on each 'start' pulse, writes write_data to addr,
// reads it back, and asserts done for one cycle.
// Sets error if bresp or rresp != OKAY, or if read_data != write_data.
//
// FSM:
//   IDLE    : wait for start; latch addr and write_data
//   WR_ADDR : drive AW+W simultaneously; wait for awready && wready
//   WR_RESP : drive bready; wait for bvalid; capture bresp
//   RD_ADDR : drive arvalid; wait for arready
//   RD_DATA : drive rready; wait for rvalid; capture rdata/rresp
//   DONE    : assert done and error for one cycle; return to IDLE
module simple_axi_master (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        start,
    input  wire [31:0] addr,
    input  wire [31:0] write_data,

    output wire [31:0] read_data,
    output wire        done,
    output wire        error,

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
    output wire        bready,

    // Read address channel
    output wire [31:0] araddr,
    output wire        arvalid,
    input  wire        arready,

    // Read data channel
    input  wire [31:0] rdata,
    input  wire [ 1:0] rresp,
    input  wire        rlast,
    input  wire        rvalid,
    output wire        rready
);

    localparam IDLE    = 3'd0;
    localparam WR_ADDR = 3'd1;
    localparam WR_RESP = 3'd2;
    localparam RD_ADDR = 3'd3;
    localparam RD_DATA = 3'd4;
    localparam DONE    = 3'd5;

    reg [ 2:0] state;
    reg [31:0] addr_lat;
    reg [31:0] wdata_lat;
    reg [31:0] rdata_lat;
    reg        write_err;
    reg        read_err;
    reg        data_err;
    reg        done_r;
    reg        error_r;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            state     <= IDLE;
            addr_lat  <= 32'h0;
            wdata_lat <= 32'h0;
            rdata_lat <= 32'h0;
            write_err <= 1'b0;
            read_err  <= 1'b0;
            data_err  <= 1'b0;
            done_r    <= 1'b0;
            error_r   <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    done_r    <= 1'b0;
                    error_r   <= 1'b0;
                    write_err <= 1'b0;
                    read_err  <= 1'b0;
                    data_err  <= 1'b0;
                    if (start) begin
                        addr_lat  <= addr;
                        wdata_lat <= write_data;
                        state     <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (awready && wready)
                        state <= WR_RESP;
                end

                WR_RESP: begin
                    if (bvalid) begin
                        write_err <= (bresp != 2'b00);
                        state     <= RD_ADDR;
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
                        data_err  <= (rdata != wdata_lat);
                        state     <= DONE;
                    end
                end

                DONE: begin
                    done_r  <= 1'b1;
                    error_r <= write_err | read_err | data_err;
                    state   <= IDLE;
                end

                default: state <= IDLE;

            endcase
        end
    end

    // AXI outputs driven combinatorially from FSM state
    assign awvalid = (state == WR_ADDR);
    assign awaddr  = addr_lat;
    assign wvalid  = (state == WR_ADDR);
    assign wdata   = wdata_lat;
    assign wstrb   = 4'hF;
    assign wlast   = 1'b1;
    assign bready  = (state == WR_RESP);
    assign arvalid = (state == RD_ADDR);
    assign araddr  = addr_lat;
    assign rready  = (state == RD_DATA);

    assign read_data = rdata_lat;
    assign done      = done_r;
    assign error     = error_r;

endmodule
