`timescale 1ns/1ps

// AXI-lite controlled DMA wrapper around simple_dma_copy_nword.
//
// Register map (AXI-lite slave, byte addresses):
//   0x00 CONTROL      : bit0=start (write-1-to-start); reads busy_r
//   0x04 SRC_ADDR     : source byte address (R/W)
//   0x08 DST_ADDR     : destination byte address (R/W)
//   0x0C LENGTH_WORDS : number of 32-bit words to copy, [15:0] (R/W)
//   0x10 STATUS       : bit0=done (sticky), bit1=error (read-only)
//   0x14 COPIED_COUNT : words successfully written, [15:0] (read-only)
//
// Writing CONTROL.start=1 launches one DMA transfer if not busy.
// STATUS.done is sticky; cleared when the next start is written.
// Addresses outside 0x00-0x14 return SLVERR.
module simple_dma_ctrl (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI-lite slave — control registers
    input  wire [31:0] s_awaddr,
    input  wire        s_awvalid,
    output reg         s_awready,

    input  wire [31:0] s_wdata,
    input  wire [ 3:0] s_wstrb,
    input  wire        s_wvalid,
    output reg         s_wready,

    output reg  [ 1:0] s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,

    input  wire [31:0] s_araddr,
    input  wire        s_arvalid,
    output reg         s_arready,

    output reg  [31:0] s_rdata,
    output reg  [ 1:0] s_rresp,
    output reg         s_rvalid,
    input  wire        s_rready,

    // AXI4 master — DMA memory port
    output wire [31:0] m_araddr,
    output wire        m_arvalid,
    input  wire        m_arready,

    input  wire [31:0] m_rdata,
    input  wire [ 1:0] m_rresp,
    input  wire        m_rlast,
    input  wire        m_rvalid,
    output wire        m_rready,

    output wire [31:0] m_awaddr,
    output wire        m_awvalid,
    input  wire        m_awready,

    output wire [31:0] m_wdata,
    output wire [ 3:0] m_wstrb,
    output wire        m_wlast,
    output wire        m_wvalid,
    input  wire        m_wready,

    input  wire [ 1:0] m_bresp,
    input  wire        m_bvalid,
    output wire        m_bready
);

    // ---------------------------------------------------------------
    // Address validity: 0x00–0x14 word-aligned (addr[4:2] in 0..5)
    // ---------------------------------------------------------------
    function automatic axil_addr_valid;
        input [31:0] a;
        axil_addr_valid = (a[31:5] == 27'h0) && (a[4:2] <= 3'd5) && (a[1:0] == 2'b00);
    endfunction

    // ---------------------------------------------------------------
    // Control / status registers
    // ---------------------------------------------------------------
    reg [31:0] src_addr_r;
    reg [31:0] dst_addr_r;
    reg [15:0] length_words_r;
    reg        busy_r;
    reg        done_r;
    reg        error_r;
    reg [15:0] copied_count_r;
    reg        dma_start_r;

    // ---------------------------------------------------------------
    // DMA core connections
    // ---------------------------------------------------------------
    wire        dma_done;
    wire        dma_error;
    wire [15:0] dma_copied_count;
    wire [31:0] dma_last_data;

    simple_dma_copy_nword dma_core (
        .aclk             (aclk),
        .aresetn          (aresetn),
        .start            (dma_start_r),
        .src_addr         (src_addr_r),
        .dst_addr         (dst_addr_r),
        .length_words     (length_words_r),
        .done             (dma_done),
        .error            (dma_error),
        .copied_count     (dma_copied_count),
        .last_copied_data (dma_last_data),
        .araddr  (m_araddr),  .arvalid (m_arvalid), .arready (m_arready),
        .rdata   (m_rdata),   .rresp   (m_rresp),   .rlast   (m_rlast),
        .rvalid  (m_rvalid),  .rready  (m_rready),
        .awaddr  (m_awaddr),  .awvalid (m_awvalid), .awready (m_awready),
        .wdata   (m_wdata),   .wstrb   (m_wstrb),   .wlast   (m_wlast),
        .wvalid  (m_wvalid),  .wready  (m_wready),
        .bresp   (m_bresp),   .bvalid  (m_bvalid),  .bready  (m_bready)
    );

    // ---------------------------------------------------------------
    // Register write helper (called from write FSM)
    //   NBA assignments allowed; called inside posedge always block.
    // ---------------------------------------------------------------
    task do_reg_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            case (addr[4:2])
                3'd0: begin  // CONTROL — write-1-to-start
                    if (data[0] && !busy_r) begin
                        dma_start_r <= 1'b1;
                        busy_r      <= 1'b1;
                        done_r      <= 1'b0;
                        error_r     <= 1'b0;
                    end
                end
                3'd1: src_addr_r     <= data;
                3'd2: dst_addr_r     <= data;
                3'd3: length_words_r <= data[15:0];
                // 3'd4 STATUS, 3'd5 COPIED_COUNT — read-only, ignore writes
                default: ;
            endcase
        end
    endtask

    // ---------------------------------------------------------------
    // AXI-lite Write FSM  (also owns ctrl/status registers + DMA start)
    // ---------------------------------------------------------------
    localparam W_IDLE   = 2'd0;
    localparam W_WAIT_W = 2'd1;
    localparam W_WAIT_A = 2'd2;
    localparam W_BRESP  = 2'd3;

    reg [1:0]  wstate;
    reg [31:0] aw_latch;
    reg [31:0] wd_latch;
    reg [ 3:0] ws_latch;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            wstate         <= W_IDLE;
            s_awready      <= 1'b1;
            s_wready       <= 1'b1;
            s_bvalid       <= 1'b0;
            s_bresp        <= 2'b00;
            aw_latch       <= 32'h0;
            wd_latch       <= 32'h0;
            ws_latch       <= 4'h0;
            src_addr_r     <= 32'h0;
            dst_addr_r     <= 32'h0;
            length_words_r <= 16'h0;
            busy_r         <= 1'b0;
            done_r         <= 1'b0;
            error_r        <= 1'b0;
            copied_count_r <= 16'h0;
            dma_start_r    <= 1'b0;
        end else begin
            dma_start_r <= 1'b0;  // default: clear start pulse each cycle

            // Capture DMA completion (sticky until next start)
            if (dma_done) begin
                busy_r         <= 1'b0;
                done_r         <= 1'b1;
                error_r        <= dma_error;
                copied_count_r <= dma_copied_count;
            end

            case (wstate)

                W_IDLE: begin
                    if (s_awvalid && s_wvalid) begin
                        if (axil_addr_valid(s_awaddr)) do_reg_write(s_awaddr, s_wdata);
                        s_bresp   <= axil_addr_valid(s_awaddr) ? 2'b00 : 2'b10;
                        s_awready <= 1'b0;
                        s_wready  <= 1'b0;
                        s_bvalid  <= 1'b1;
                        wstate    <= W_BRESP;
                    end else if (s_awvalid) begin
                        aw_latch  <= s_awaddr;
                        s_awready <= 1'b0;
                        wstate    <= W_WAIT_W;
                    end else if (s_wvalid) begin
                        wd_latch  <= s_wdata;
                        ws_latch  <= s_wstrb;
                        s_wready  <= 1'b0;
                        wstate    <= W_WAIT_A;
                    end
                end

                W_WAIT_W: begin
                    if (s_wvalid) begin
                        if (axil_addr_valid(aw_latch)) do_reg_write(aw_latch, s_wdata);
                        s_bresp  <= axil_addr_valid(aw_latch) ? 2'b00 : 2'b10;
                        s_wready <= 1'b0;
                        s_bvalid <= 1'b1;
                        wstate   <= W_BRESP;
                    end
                end

                W_WAIT_A: begin
                    if (s_awvalid) begin
                        if (axil_addr_valid(s_awaddr)) do_reg_write(s_awaddr, wd_latch);
                        s_bresp   <= axil_addr_valid(s_awaddr) ? 2'b00 : 2'b10;
                        s_awready <= 1'b0;
                        s_bvalid  <= 1'b1;
                        wstate    <= W_BRESP;
                    end
                end

                W_BRESP: begin
                    if (s_bready) begin
                        s_bvalid  <= 1'b0;
                        s_bresp   <= 2'b00;
                        s_awready <= 1'b1;
                        s_wready  <= 1'b1;
                        wstate    <= W_IDLE;
                    end
                end

            endcase
        end
    end

    // ---------------------------------------------------------------
    // Register read mux (function)
    // ---------------------------------------------------------------
    function [31:0] reg_rdata;
        input [31:0] addr;
        reg [31:0] d;
        begin
            case (addr[4:2])
                3'd0: d = {31'b0, busy_r};
                3'd1: d = src_addr_r;
                3'd2: d = dst_addr_r;
                3'd3: d = {16'b0, length_words_r};
                3'd4: d = {30'b0, error_r, done_r};
                3'd5: d = {16'b0, copied_count_r};
                default: d = 32'h0;
            endcase
            reg_rdata = d;
        end
    endfunction

    // ---------------------------------------------------------------
    // AXI-lite Read FSM
    // ---------------------------------------------------------------
    localparam R_IDLE   = 1'b0;
    localparam R_RVALID = 1'b1;

    reg rstate;

    always @(posedge aclk or negedge aresetn) begin
        if (!aresetn) begin
            rstate    <= R_IDLE;
            s_arready <= 1'b1;
            s_rvalid  <= 1'b0;
            s_rdata   <= 32'h0;
            s_rresp   <= 2'b00;
        end else begin
            case (rstate)

                R_IDLE: begin
                    if (s_arvalid) begin
                        s_rdata   <= axil_addr_valid(s_araddr) ? reg_rdata(s_araddr) : 32'h0;
                        s_rresp   <= axil_addr_valid(s_araddr) ? 2'b00 : 2'b10;
                        s_rvalid  <= 1'b1;
                        s_arready <= 1'b0;
                        rstate    <= R_RVALID;
                    end
                end

                R_RVALID: begin
                    if (s_rready) begin
                        s_rvalid  <= 1'b0;
                        s_rresp   <= 2'b00;
                        s_arready <= 1'b1;
                        rstate    <= R_IDLE;
                    end
                end

            endcase
        end
    end

endmodule
