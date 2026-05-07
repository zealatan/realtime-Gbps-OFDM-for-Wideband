`timescale 1ns/1ps

// frac_cfo_sync_control_s_axi — AXI4-Lite slave register file.
// 8 word-aligned registers at byte offsets 0x00–0x1C.
// Data width = 32, Address width = 6. Single-outstanding write.

module frac_cfo_sync_control_s_axi #(
    parameter integer AXI_ADDR_WIDTH = 6,
    parameter integer AXI_DATA_WIDTH = 32
) (
    input  wire                          s_axi_aclk,
    input  wire                          s_axi_aresetn,

    // Write address channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    // Write data channel
    input  wire [AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [AXI_DATA_WIDTH/8-1:0]   s_axi_wstrb,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    // Write response channel
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    // Read address channel
    input  wire [AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    // Read data channel
    output reg  [AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // Control outputs (to wrapper)
    output reg                           soft_reset_pulse,
    output reg                           clear_status_pulse,
    output reg                           enable_out,
    output reg  [31:0]                   cfg_cfo_step,
    output reg  [31:0]                   cfg_timing_offset,
    output reg  [31:0]                   cfg_frame_len,

    // Status inputs (from wrapper)
    input  wire                          status_busy,
    input  wire                          status_done_sticky,
    input  wire                          status_frame_detected_sticky,
    input  wire                          status_frame_error_sticky,
    input  wire                          status_in_frame,
    input  wire                          status_input_seen_sticky,
    input  wire                          status_output_seen_sticky,
    input  wire [31:0]                   sample_count_in,
    input  wire [31:0]                   output_count_in,
    input  wire [31:0]                   debug_state_in
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // Write FSM states
    localparam [1:0] WS_IDLE = 2'd0;
    localparam [1:0] WS_AW   = 2'd1;   // AW accepted, waiting for W
    localparam [1:0] WS_W    = 2'd2;   // W accepted, waiting for AW
    localparam [1:0] WS_EXEC = 2'd3;   // both ready, execute

    reg [1:0]                   wr_state;
    reg [AXI_ADDR_WIDTH-1:0]    wr_addr_r;
    reg [AXI_DATA_WIDTH-1:0]    wr_data_r;
    reg [AXI_DATA_WIDTH/8-1:0]  wr_strb_r;

    // -----------------------------------------------------------------------
    // Write channel + register file
    // -----------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            wr_state           <= WS_IDLE;
            s_axi_awready      <= 1'b1;
            s_axi_wready       <= 1'b1;
            s_axi_bvalid       <= 1'b0;
            s_axi_bresp        <= RESP_OKAY;
            wr_addr_r          <= '0;
            wr_data_r          <= '0;
            wr_strb_r          <= '0;
            soft_reset_pulse   <= 1'b0;
            clear_status_pulse <= 1'b0;
            enable_out         <= 1'b0;
            cfg_cfo_step       <= 32'd0;
            cfg_timing_offset  <= 32'd0;
            cfg_frame_len      <= 32'd0;
        end else begin
            // One-shot pulses auto-clear every cycle
            soft_reset_pulse   <= 1'b0;
            clear_status_pulse <= 1'b0;

            // B response: clear when accepted
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            case (wr_state)
                WS_IDLE: begin
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        wr_addr_r     <= s_axi_awaddr;
                        wr_data_r     <= s_axi_wdata;
                        wr_strb_r     <= s_axi_wstrb;
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        wr_state      <= WS_EXEC;
                    end else if (s_axi_awvalid) begin
                        wr_addr_r     <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        wr_state      <= WS_AW;
                    end else if (s_axi_wvalid) begin
                        wr_data_r    <= s_axi_wdata;
                        wr_strb_r    <= s_axi_wstrb;
                        s_axi_wready <= 1'b0;
                        wr_state     <= WS_W;
                    end
                end

                WS_AW: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        wr_data_r    <= s_axi_wdata;
                        wr_strb_r    <= s_axi_wstrb;
                        s_axi_wready <= 1'b0;
                        wr_state     <= WS_EXEC;
                    end
                end

                WS_W: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        wr_addr_r     <= s_axi_awaddr;
                        s_axi_awready <= 1'b0;
                        wr_state      <= WS_EXEC;
                    end
                end

                WS_EXEC: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    s_axi_bvalid  <= 1'b1;
                    s_axi_bresp   <= RESP_OKAY;
                    wr_state      <= WS_IDLE;

                    case (wr_addr_r[5:2])
                        4'h0: begin // CONTROL
                            if (wr_strb_r[0]) begin
                                soft_reset_pulse   <= wr_data_r[0];
                                clear_status_pulse <= wr_data_r[1];
                                enable_out         <= wr_data_r[2];
                            end
                        end
                        4'h1: begin // STATUS — read-only; write is no-op
                        end
                        4'h2: begin // CFG_CFO_STEP
                            if (wr_strb_r[0]) cfg_cfo_step[ 7: 0] <= wr_data_r[ 7: 0];
                            if (wr_strb_r[1]) cfg_cfo_step[15: 8] <= wr_data_r[15: 8];
                            if (wr_strb_r[2]) cfg_cfo_step[23:16] <= wr_data_r[23:16];
                            if (wr_strb_r[3]) cfg_cfo_step[31:24] <= wr_data_r[31:24];
                        end
                        4'h3: begin // CFG_TIMING_OFFSET
                            if (wr_strb_r[0]) cfg_timing_offset[ 7: 0] <= wr_data_r[ 7: 0];
                            if (wr_strb_r[1]) cfg_timing_offset[15: 8] <= wr_data_r[15: 8];
                            if (wr_strb_r[2]) cfg_timing_offset[23:16] <= wr_data_r[23:16];
                            if (wr_strb_r[3]) cfg_timing_offset[31:24] <= wr_data_r[31:24];
                        end
                        4'h4: begin // CFG_FRAME_LEN
                            if (wr_strb_r[0]) cfg_frame_len[ 7: 0] <= wr_data_r[ 7: 0];
                            if (wr_strb_r[1]) cfg_frame_len[15: 8] <= wr_data_r[15: 8];
                            if (wr_strb_r[2]) cfg_frame_len[23:16] <= wr_data_r[23:16];
                            if (wr_strb_r[3]) cfg_frame_len[31:24] <= wr_data_r[31:24];
                        end
                        4'h5, 4'h6, 4'h7: begin // read-only counters/debug
                        end
                        default: begin
                            s_axi_bresp <= RESP_SLVERR;
                        end
                    endcase
                end

                default: wr_state <= WS_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read channel
    // -----------------------------------------------------------------------
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= RESP_OKAY;
        end else begin
            // Consume R response when accepted
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            // Accept new AR when ready
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= RESP_OKAY;
                case (s_axi_araddr[5:2])
                    4'h0: s_axi_rdata <= {29'd0, enable_out, 2'd0};
                    4'h1: s_axi_rdata <= {25'd0,
                                          status_output_seen_sticky,
                                          status_input_seen_sticky,
                                          status_in_frame,
                                          status_frame_error_sticky,
                                          status_frame_detected_sticky,
                                          status_done_sticky,
                                          status_busy};
                    4'h2: s_axi_rdata <= cfg_cfo_step;
                    4'h3: s_axi_rdata <= cfg_timing_offset;
                    4'h4: s_axi_rdata <= cfg_frame_len;
                    4'h5: s_axi_rdata <= sample_count_in;
                    4'h6: s_axi_rdata <= output_count_in;
                    4'h7: s_axi_rdata <= debug_state_in;
                    default: begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= RESP_SLVERR;
                    end
                endcase
            end
        end
    end

endmodule
