`timescale 1ns/1ps

// AXI-lite slave: 4 x 32-bit registers at byte offsets 0x00, 0x04, 0x08, 0x0C.
// Active-low synchronous reset (aresetn).
module axi_lite_regfile (
    input  wire        aclk,
    input  wire        aresetn,

    // Write address channel
    input  wire [31:0] awaddr,
    input  wire        awvalid,
    output reg         awready,

    // Write data channel
    input  wire [31:0] wdata,
    input  wire [ 3:0] wstrb,
    input  wire        wvalid,
    output reg         wready,

    // Write response channel
    output reg  [ 1:0] bresp,
    output reg         bvalid,
    input  wire        bready,

    // Read address channel
    input  wire [31:0] araddr,
    input  wire        arvalid,
    output reg         arready,

    // Read data channel
    output reg  [31:0] rdata,
    output reg  [ 1:0] rresp,
    output reg         rvalid,
    input  wire        rready
);

    reg [31:0] regs [0:3];

    // ---------------------------------------------------------------
    // Write path: 4-state FSM
    //   W_IDLE    – ready for new transaction
    //   W_WAIT_W  – have awaddr, waiting for wdata
    //   W_WAIT_A  – have wdata, waiting for awaddr
    //   W_BRESP   – sending write response
    // ---------------------------------------------------------------
    localparam W_IDLE   = 2'd0;
    localparam W_WAIT_W = 2'd1;
    localparam W_WAIT_A = 2'd2;
    localparam W_BRESP  = 2'd3;

    reg [ 1:0] wstate;
    reg [31:0] aw_latch;
    reg [31:0] wd_latch;
    reg [ 3:0] ws_latch;

    integer i;

    task do_write;
        input [1:0]  idx;
        input [31:0] d;
        input [3:0]  s;
        begin
            if (s[0]) regs[idx][ 7: 0] <= d[ 7: 0];
            if (s[1]) regs[idx][15: 8] <= d[15: 8];
            if (s[2]) regs[idx][23:16] <= d[23:16];
            if (s[3]) regs[idx][31:24] <= d[31:24];
        end
    endtask

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate  <= W_IDLE;
            awready <= 1'b1;
            wready  <= 1'b1;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
            for (i = 0; i < 4; i = i + 1) regs[i] <= 32'd0;
        end else begin
            case (wstate)

                W_IDLE: begin
                    if (awvalid && wvalid) begin
                        if (awaddr[31:4] == 28'h0) begin
                            do_write(awaddr[3:2], wdata, wstrb);
                            bresp <= 2'b00;
                        end else begin
                            bresp <= 2'b10;
                        end
                        awready <= 1'b0;
                        wready  <= 1'b0;
                        bvalid  <= 1'b1;
                        wstate  <= W_BRESP;
                    end else if (awvalid) begin
                        aw_latch <= awaddr;
                        awready  <= 1'b0;
                        wstate   <= W_WAIT_W;
                    end else if (wvalid) begin
                        wd_latch <= wdata;
                        ws_latch <= wstrb;
                        wready   <= 1'b0;
                        wstate   <= W_WAIT_A;
                    end
                end

                W_WAIT_W: begin
                    if (wvalid) begin
                        if (aw_latch[31:4] == 28'h0) begin
                            do_write(aw_latch[3:2], wdata, wstrb);
                            bresp <= 2'b00;
                        end else begin
                            bresp <= 2'b10;
                        end
                        wready <= 1'b0;
                        bvalid <= 1'b1;
                        wstate <= W_BRESP;
                    end
                end

                W_WAIT_A: begin
                    if (awvalid) begin
                        if (awaddr[31:4] == 28'h0) begin
                            do_write(awaddr[3:2], wd_latch, ws_latch);
                            bresp <= 2'b00;
                        end else begin
                            bresp <= 2'b10;
                        end
                        awready <= 1'b0;
                        bvalid  <= 1'b1;
                        wstate  <= W_BRESP;
                    end
                end

                W_BRESP: begin
                    if (bready) begin
                        bvalid  <= 1'b0;
                        bresp   <= 2'b00;
                        awready <= 1'b1;
                        wready  <= 1'b1;
                        wstate  <= W_IDLE;
                    end
                end

            endcase
        end
    end

    // ---------------------------------------------------------------
    // Read path: 2-state FSM
    //   R_IDLE   – ready for new read
    //   R_RVALID – holding rdata until rready
    // ---------------------------------------------------------------
    localparam R_IDLE   = 1'b0;
    localparam R_RVALID = 1'b1;

    reg rstate;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate  <= R_IDLE;
            arready <= 1'b1;
            rvalid  <= 1'b0;
            rdata   <= 32'd0;
            rresp   <= 2'b00;
        end else begin
            case (rstate)

                R_IDLE: begin
                    if (arvalid) begin
                        if (araddr[31:4] == 28'h0) begin
                            rdata <= regs[araddr[3:2]];
                            rresp <= 2'b00;
                        end else begin
                            rdata <= 32'h0;
                            rresp <= 2'b10;
                        end
                        rvalid  <= 1'b1;
                        arready <= 1'b0;
                        rstate  <= R_RVALID;
                    end
                end

                R_RVALID: begin
                    if (rready) begin
                        rvalid  <= 1'b0;
                        rresp   <= 2'b00;
                        arready <= 1'b1;
                        rstate  <= R_IDLE;
                    end
                end

            endcase
        end
    end

endmodule
