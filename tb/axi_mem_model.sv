`timescale 1ns/1ps

// AXI4 slave memory model — 32-bit data, single-beat transactions only.
// No burst, no ID, no AxPROT/AxCACHE/AxLEN/AxSIZE signals.
// Out-of-range addresses return SLVERR and leave memory unchanged.
// Lower 2 address bits are ignored (word-aligned access assumed).
//
// Parameters:
//   MEM_DEPTH : number of 32-bit words  (default 1024 = 4 KB)
//   MEM_BASE  : base byte address       (default 0x0000_0000)
module axi_mem_model #(
    parameter integer MEM_DEPTH = 1024,
    parameter [31:0]  MEM_BASE  = 32'h0000_0000
) (
    input  wire        aclk,
    input  wire        aresetn,

    // Write address channel
    input  wire [31:0] awaddr,
    input  wire        awvalid,
    output reg         awready,

    // Write data channel
    input  wire [31:0] wdata,
    input  wire [ 3:0] wstrb,
    input  wire        wlast,    // accepted but not checked; single-beat only
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
    output reg         rlast,
    output reg         rvalid,
    input  wire        rready
);

    localparam [31:0] MEM_END = MEM_BASE + (MEM_DEPTH * 4);

    reg [31:0] mem [0:MEM_DEPTH-1];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < MEM_DEPTH; init_i = init_i + 1)
            mem[init_i] = 32'h0;
    end

    // ---------------------------------------------------------------
    // Address validity check
    // ---------------------------------------------------------------
    function automatic addr_in_range;
        input [31:0] a;
        addr_in_range = (a >= MEM_BASE) && (a < MEM_END);
    endfunction

    // ---------------------------------------------------------------
    // Byte-lane write helper
    // ---------------------------------------------------------------
    task do_write;
        input [31:0] a;
        input [31:0] d;
        input [ 3:0] s;
        integer idx;
        begin
            idx = (a - MEM_BASE) >> 2;
            if (s[0]) mem[idx][ 7: 0] <= d[ 7: 0];
            if (s[1]) mem[idx][15: 8] <= d[15: 8];
            if (s[2]) mem[idx][23:16] <= d[23:16];
            if (s[3]) mem[idx][31:24] <= d[31:24];
        end
    endtask

    // ---------------------------------------------------------------
    // Write path — 4-state FSM
    //   W_IDLE   : ready for new transaction
    //   W_WAIT_W : AW accepted, waiting for W
    //   W_WAIT_A : W accepted, waiting for AW
    //   W_BRESP  : sending write response
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

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate  <= W_IDLE;
            awready <= 1'b1;
            wready  <= 1'b1;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
        end else begin
            case (wstate)

                W_IDLE: begin
                    if (awvalid && wvalid) begin
                        if (addr_in_range(awaddr))
                            do_write(awaddr, wdata, wstrb);
                        bresp   <= addr_in_range(awaddr) ? 2'b00 : 2'b10;
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
                        if (addr_in_range(aw_latch))
                            do_write(aw_latch, wdata, wstrb);
                        bresp  <= addr_in_range(aw_latch) ? 2'b00 : 2'b10;
                        wready <= 1'b0;
                        bvalid <= 1'b1;
                        wstate <= W_BRESP;
                    end
                end

                W_WAIT_A: begin
                    if (awvalid) begin
                        if (addr_in_range(awaddr))
                            do_write(awaddr, wd_latch, ws_latch);
                        bresp   <= addr_in_range(awaddr) ? 2'b00 : 2'b10;
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
    // Read path — 2-state FSM
    //   R_IDLE   : ready for new read
    //   R_RVALID : holding rdata until rready
    // ---------------------------------------------------------------
    localparam R_IDLE   = 1'b0;
    localparam R_RVALID = 1'b1;

    reg rstate;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate  <= R_IDLE;
            arready <= 1'b1;
            rvalid  <= 1'b0;
            rlast   <= 1'b0;
            rdata   <= 32'h0;
            rresp   <= 2'b00;
        end else begin
            case (rstate)

                R_IDLE: begin
                    if (arvalid) begin
                        if (addr_in_range(araddr)) begin
                            rdata <= mem[(araddr - MEM_BASE) >> 2];
                            rresp <= 2'b00;
                        end else begin
                            rdata <= 32'h0;
                            rresp <= 2'b10;
                        end
                        rlast   <= 1'b1;
                        rvalid  <= 1'b1;
                        arready <= 1'b0;
                        rstate  <= R_RVALID;
                    end
                end

                R_RVALID: begin
                    if (rready) begin
                        rvalid  <= 1'b0;
                        rlast   <= 1'b0;
                        rresp   <= 2'b00;
                        arready <= 1'b1;
                        rstate  <= R_IDLE;
                    end
                end

            endcase
        end
    end

endmodule
