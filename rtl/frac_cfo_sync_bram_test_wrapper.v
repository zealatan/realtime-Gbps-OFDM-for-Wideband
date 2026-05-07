`timescale 1ns/1ps

// frac_cfo_sync_bram_test_wrapper
// BRAM preload/readback wrapper for known-vector FPGA testing.
//
// Architecture:
//   One AXI-Lite slave (16-bit address) handles:
//     0x0000-0x0028  Control/status/config registers (11 × 32-bit)
//     0x1000-0x1FFF  Input memory window  (1024 × 32-bit, R/W from AXI)
//     0x2000-0x2FFF  Output memory window (1024 × 32-bit, R/O from AXI)
//
//   Stream source FSM reads input_mem → DUT s_axis
//   Stream sink  FSM receives DUT m_axis → output_mem
//   frac_cfo_frame_corrector_top instantiated directly (Option A: avoids dual AXI slave)
//
// Run sequence:
//   1. Write input samples to 0x1000 window
//   2. Set CFG/INPUT_LEN/OUTPUT_MAX_LEN registers
//   3. Write CONTROL.enable=1, CONTROL.start_pulse=1 (same write or separate)
//   4. Poll STATUS.done_sticky
//   5. Read OUTPUT_COUNT and 0x2000 window

module frac_cfo_sync_bram_test_wrapper #(
    // frac_cfo_frame_corrector_top parameters
    parameter integer NSC              = 256,
    parameter integer CP_LEN          = 32,
    parameter integer BUF_AW          = 12,
    parameter integer ACC_WIDTH       = 40,
    parameter integer METRIC_WIDTH    = 32,
    parameter integer INDEX_WIDTH     = 9,
    parameter integer RESULT_WIDTH    = 32,
    parameter integer PHASE_WIDTH     = 16,
    parameter integer POWER_WIDTH     = 33,
    parameter integer ENERGY_WIDTH    = 40,
    parameter integer WINDOW_LEN      = 25,
    parameter integer HIT_COUNT       = 10,
    parameter integer THRESHOLD       = 10240000,
    parameter integer NCO_PHASE_WIDTH = 32,
    parameter integer LATENCY         = 15,
    // Memory: 2^MEM_ADDR_WIDTH entries per buffer (1024 at default of 10)
    parameter integer MEM_ADDR_WIDTH  = 10,
    parameter integer TIMEOUT_CYCLES  = 100000
) (
    input  wire        aclk,
    input  wire        aresetn,

    // AXI4-Lite slave (16-bit byte address, 32-bit data)
    input  wire [15:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [15:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // -----------------------------------------------------------------------
    // Memories
    // -----------------------------------------------------------------------
    localparam integer MEM_DEPTH = 1 << MEM_ADDR_WIDTH;

    reg [31:0] input_mem  [0:MEM_DEPTH-1];
    reg [31:0] output_mem [0:MEM_DEPTH-1];

    integer j;
    initial begin
        for (j = 0; j < MEM_DEPTH; j = j + 1) begin
            input_mem[j]  = 32'd0;
            output_mem[j] = 32'd0;
        end
    end

    // -----------------------------------------------------------------------
    // AXI-Lite write channel — single-outstanding write FSM
    // -----------------------------------------------------------------------
    localparam [1:0] WS_IDLE = 2'd0, WS_AW = 2'd1, WS_W = 2'd2, WS_EXEC = 2'd3;

    reg [1:0]  wr_state;
    reg [15:0] wr_addr_r;
    reg [31:0] wr_data_r;
    reg [3:0]  wr_strb_r;

    // Address region decode (registered address)
    wire [3:0]  wr_region  = wr_addr_r[15:12];
    wire [9:0]  wr_word    = wr_addr_r[11:2];   // word index within region
    wire [9:0]  wr_reg_idx = wr_addr_r[11:2];   // same, for control-reg region

    // -----------------------------------------------------------------------
    // Control/status registers
    // -----------------------------------------------------------------------
    // Pulse registers (auto-clear every cycle)
    reg start_pulse_r;
    reg soft_reset_pulse_r;
    reg clr_status_pulse_r;
    // Sticky config registers
    reg        enable_r;
    reg [31:0] cfg_cfo_step_r;
    reg [31:0] cfg_timing_offset_r;
    reg [31:0] cfg_frame_len_r;
    reg [31:0] input_len_r;
    reg [31:0] output_max_len_r;

    // -----------------------------------------------------------------------
    // Status/counters
    // -----------------------------------------------------------------------
    reg        done_sticky_r;
    reg        frame_error_sticky_r;
    reg        input_underflow_sticky_r;   // reserved/always 0 in current impl
    reg        output_overflow_sticky_r;
    reg        running_r;
    reg        input_done_r;
    reg        output_done_r;
    reg [31:0] input_count_r;
    reg [31:0] output_count_r;
    reg [31:0] timeout_cnt;

    wire clear_sticky = soft_reset_pulse_r || clr_status_pulse_r;

    // -----------------------------------------------------------------------
    // Source FSM
    // -----------------------------------------------------------------------
    localparam [1:0] SRC_IDLE = 2'd0, SRC_STREAM = 2'd1, SRC_DONE = 2'd2;
    reg [1:0]                    src_state;
    reg [MEM_ADDR_WIDTH-1:0]     src_ptr;

    // -----------------------------------------------------------------------
    // Sink FSM
    // -----------------------------------------------------------------------
    localparam [1:0] SNK_IDLE = 2'd0, SNK_CAPTURE = 2'd1, SNK_DONE = 2'd2;
    reg [1:0]                    snk_state;
    reg [MEM_ADDR_WIDTH-1:0]     snk_ptr;

    // -----------------------------------------------------------------------
    // DUT signals
    // -----------------------------------------------------------------------
    wire        dut_aresetn;
    wire        dut_start;

    wire [31:0] dut_s_axis_tdata;
    wire        dut_s_axis_tvalid;
    wire        dut_s_axis_tready;
    wire        dut_s_axis_tlast;

    wire [31:0] dut_m_axis_tdata;
    wire        dut_m_axis_tvalid;
    wire        dut_m_axis_tready;
    wire        dut_m_axis_tlast;

    wire        dut_done;
    wire        dut_busy;
    wire        dut_frame_error;

    wire [BUF_AW-1:0]      dut_frame_index;
    wire                   dut_frame_found;
    wire [INDEX_WIDTH-1:0] dut_peak_lag;
    wire [METRIC_WIDTH-1:0] dut_peak_metric;
    wire [PHASE_WIDTH-1:0] dut_frac_phase;
    wire                   dut_frac_phase_valid;

    // -----------------------------------------------------------------------
    // DUT control wires
    // -----------------------------------------------------------------------
    assign dut_aresetn = aresetn && !soft_reset_pulse_r;
    assign dut_start   = start_pulse_r && enable_r && !running_r;

    // Stream source → DUT
    assign dut_s_axis_tdata  = input_mem[src_ptr];
    assign dut_s_axis_tvalid = (src_state == SRC_STREAM);
    assign dut_s_axis_tlast  = (src_state == SRC_STREAM) &&
                                (src_ptr == input_len_r[MEM_ADDR_WIDTH-1:0] - 1);

    // DUT → stream sink (always accept samples in CAPTURE state; no backpressure)
    assign dut_m_axis_tready = (snk_state == SNK_CAPTURE);

    // -----------------------------------------------------------------------
    // AXI-Lite write FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            wr_state      <= WS_IDLE;
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= RESP_OKAY;
            wr_addr_r     <= 16'd0;
            wr_data_r     <= 32'd0;
            wr_strb_r     <= 4'd0;
            // Config regs reset
            start_pulse_r      <= 1'b0;
            soft_reset_pulse_r <= 1'b0;
            clr_status_pulse_r <= 1'b0;
            enable_r           <= 1'b0;
            cfg_cfo_step_r     <= 32'd0;
            cfg_timing_offset_r <= 32'd0;
            cfg_frame_len_r    <= 32'd0;
            input_len_r        <= 32'd0;
            output_max_len_r   <= 32'd0;
        end else begin
            // Auto-clear pulses every cycle
            start_pulse_r      <= 1'b0;
            soft_reset_pulse_r <= 1'b0;
            clr_status_pulse_r <= 1'b0;

            // Clear B response when accepted
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

                    if (wr_region == 4'h0) begin
                        // Control/status register region
                        if (wr_reg_idx > 10) begin
                            s_axi_bresp <= RESP_SLVERR;
                        end else begin
                            case (wr_reg_idx)
                                10'd0: begin // CONTROL
                                    if (wr_strb_r[0]) begin
                                        start_pulse_r      <= wr_data_r[0];
                                        soft_reset_pulse_r <= wr_data_r[1];
                                        clr_status_pulse_r <= wr_data_r[2];
                                        enable_r           <= wr_data_r[3];
                                    end
                                end
                                10'd1: begin // STATUS — R/O, writes are no-op
                                end
                                10'd2: begin // CFG_CFO_STEP
                                    if (wr_strb_r[0]) cfg_cfo_step_r[ 7: 0] <= wr_data_r[ 7: 0];
                                    if (wr_strb_r[1]) cfg_cfo_step_r[15: 8] <= wr_data_r[15: 8];
                                    if (wr_strb_r[2]) cfg_cfo_step_r[23:16] <= wr_data_r[23:16];
                                    if (wr_strb_r[3]) cfg_cfo_step_r[31:24] <= wr_data_r[31:24];
                                end
                                10'd3: begin // CFG_TIMING_OFFSET
                                    if (wr_strb_r[0]) cfg_timing_offset_r[ 7: 0] <= wr_data_r[ 7: 0];
                                    if (wr_strb_r[1]) cfg_timing_offset_r[15: 8] <= wr_data_r[15: 8];
                                    if (wr_strb_r[2]) cfg_timing_offset_r[23:16] <= wr_data_r[23:16];
                                    if (wr_strb_r[3]) cfg_timing_offset_r[31:24] <= wr_data_r[31:24];
                                end
                                10'd4: begin // CFG_FRAME_LEN
                                    if (wr_strb_r[0]) cfg_frame_len_r[ 7: 0] <= wr_data_r[ 7: 0];
                                    if (wr_strb_r[1]) cfg_frame_len_r[15: 8] <= wr_data_r[15: 8];
                                    if (wr_strb_r[2]) cfg_frame_len_r[23:16] <= wr_data_r[23:16];
                                    if (wr_strb_r[3]) cfg_frame_len_r[31:24] <= wr_data_r[31:24];
                                end
                                10'd5: begin // INPUT_LEN
                                    if (wr_strb_r[0]) input_len_r[ 7: 0] <= wr_data_r[ 7: 0];
                                    if (wr_strb_r[1]) input_len_r[15: 8] <= wr_data_r[15: 8];
                                    if (wr_strb_r[2]) input_len_r[23:16] <= wr_data_r[23:16];
                                    if (wr_strb_r[3]) input_len_r[31:24] <= wr_data_r[31:24];
                                end
                                10'd6: begin // OUTPUT_MAX_LEN
                                    if (wr_strb_r[0]) output_max_len_r[ 7: 0] <= wr_data_r[ 7: 0];
                                    if (wr_strb_r[1]) output_max_len_r[15: 8] <= wr_data_r[15: 8];
                                    if (wr_strb_r[2]) output_max_len_r[23:16] <= wr_data_r[23:16];
                                    if (wr_strb_r[3]) output_max_len_r[31:24] <= wr_data_r[31:24];
                                end
                                10'd7,  // INPUT_COUNT  — R/O
                                10'd8,  // OUTPUT_COUNT — R/O
                                10'd9,  // DEBUG_STATE  — R/O
                                10'd10: begin // ERROR_STATUS — R/O
                                end
                                default: s_axi_bresp <= RESP_SLVERR;
                            endcase
                        end
                    end else if (wr_region == 4'h1) begin
                        // Input memory write (byte-strobe capable)
                        if (wr_strb_r[0]) input_mem[wr_word][7:0]   <= wr_data_r[7:0];
                        if (wr_strb_r[1]) input_mem[wr_word][15:8]  <= wr_data_r[15:8];
                        if (wr_strb_r[2]) input_mem[wr_word][23:16] <= wr_data_r[23:16];
                        if (wr_strb_r[3]) input_mem[wr_word][31:24] <= wr_data_r[31:24];
                    end else if (wr_region == 4'h2) begin
                        // Output memory — write-protected, return SLVERR
                        s_axi_bresp <= RESP_SLVERR;
                    end else begin
                        s_axi_bresp <= RESP_SLVERR;
                    end
                end

                default: wr_state <= WS_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // AXI-Lite read channel
    // -----------------------------------------------------------------------
    wire [3:0] rd_region  = s_axi_araddr[15:12];
    wire [9:0] rd_word    = s_axi_araddr[11:2];
    wire [9:0] rd_reg_idx = s_axi_araddr[11:2];

    wire [31:0] status_word = {
        23'd0,
        frame_error_sticky_r,      // bit[8]
        done_sticky_r,             // bit[7] = wrapped_done_sticky
        output_overflow_sticky_r,  // bit[6]
        input_underflow_sticky_r,  // bit[5]
        output_done_r,             // bit[4]
        input_done_r,              // bit[3]
        running_r,                 // bit[2]
        done_sticky_r,             // bit[1]
        dut_busy                   // bit[0]
    };

    wire [31:0] control_readback = {28'd0, enable_r, 3'd0};

    wire [31:0] debug_state_word =
        frame_error_sticky_r ? 32'd5 :
        done_sticky_r        ? 32'd4 :
        (src_state == SRC_DONE && snk_state == SNK_CAPTURE) ? 32'd3 :
        (src_state == SRC_STREAM)                           ? 32'd2 :
        (enable_r && !running_r)                            ? 32'd1 :
        32'd0;

    wire [31:0] error_status_word = {
        28'd0,
        (running_r && timeout_cnt >= TIMEOUT_CYCLES[31:0]), // bit[3] timeout
        1'b0,                        // bit[2]
        output_overflow_sticky_r,    // bit[1]
        input_underflow_sticky_r     // bit[0]
    };

    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= 32'd0;
            s_axi_rresp   <= RESP_OKAY;
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end

            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= RESP_OKAY;

                if (rd_region == 4'h0) begin
                    if (rd_reg_idx > 10) begin
                        s_axi_rdata <= 32'd0;
                        s_axi_rresp <= RESP_SLVERR;
                    end else begin
                        case (rd_reg_idx)
                            10'd0:  s_axi_rdata <= control_readback;
                            10'd1:  s_axi_rdata <= status_word;
                            10'd2:  s_axi_rdata <= cfg_cfo_step_r;
                            10'd3:  s_axi_rdata <= cfg_timing_offset_r;
                            10'd4:  s_axi_rdata <= cfg_frame_len_r;
                            10'd5:  s_axi_rdata <= input_len_r;
                            10'd6:  s_axi_rdata <= output_max_len_r;
                            10'd7:  s_axi_rdata <= input_count_r;
                            10'd8:  s_axi_rdata <= output_count_r;
                            10'd9:  s_axi_rdata <= debug_state_word;
                            10'd10: s_axi_rdata <= error_status_word;
                            default: begin
                                s_axi_rdata <= 32'd0;
                                s_axi_rresp <= RESP_SLVERR;
                            end
                        endcase
                    end
                end else if (rd_region == 4'h1) begin
                    s_axi_rdata <= input_mem[rd_word];
                end else if (rd_region == 4'h2) begin
                    s_axi_rdata <= output_mem[rd_word];
                end else begin
                    s_axi_rdata <= 32'd0;
                    s_axi_rresp <= RESP_SLVERR;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Status / sticky / counters
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            done_sticky_r           <= 1'b0;
            frame_error_sticky_r    <= 1'b0;
            input_underflow_sticky_r <= 1'b0;
            output_overflow_sticky_r <= 1'b0;
            running_r               <= 1'b0;
            input_done_r            <= 1'b0;
            output_done_r           <= 1'b0;
            input_count_r           <= 32'd0;
            output_count_r          <= 32'd0;
            timeout_cnt             <= 32'd0;
        end else if (soft_reset_pulse_r) begin
            done_sticky_r           <= 1'b0;
            frame_error_sticky_r    <= 1'b0;
            input_underflow_sticky_r <= 1'b0;
            output_overflow_sticky_r <= 1'b0;
            running_r               <= 1'b0;
            input_done_r            <= 1'b0;
            output_done_r           <= 1'b0;
            input_count_r           <= 32'd0;
            output_count_r          <= 32'd0;
            timeout_cnt             <= 32'd0;
        end else begin
            // Clear-status pulse
            if (clr_status_pulse_r) begin
                done_sticky_r           <= 1'b0;
                frame_error_sticky_r    <= 1'b0;
                input_underflow_sticky_r <= 1'b0;
                output_overflow_sticky_r <= 1'b0;
                input_done_r            <= 1'b0;
                output_done_r           <= 1'b0;
                input_count_r           <= 32'd0;
                output_count_r          <= 32'd0;
                timeout_cnt             <= 32'd0;
            end else begin
                // Running: set on start, clear on done or timeout
                if (start_pulse_r && enable_r && !running_r) begin
                    running_r     <= 1'b1;
                    input_count_r <= 32'd0;
                    output_count_r <= 32'd0;
                    input_done_r  <= 1'b0;
                    output_done_r <= 1'b0;
                    timeout_cnt   <= 32'd0;
                end else begin
                    if (dut_done || (running_r && timeout_cnt >= TIMEOUT_CYCLES[31:0]))
                        running_r <= 1'b0;

                    // Timeout counter
                    if (running_r && timeout_cnt < TIMEOUT_CYCLES[31:0])
                        timeout_cnt <= timeout_cnt + 1;

                    // Done sticky (from DUT done or timeout)
                    if (dut_done || (running_r && timeout_cnt >= TIMEOUT_CYCLES[31:0]))
                        done_sticky_r <= 1'b1;

                    // Frame error sticky
                    if (dut_frame_error)
                        frame_error_sticky_r <= 1'b1;

                    // Input count: increment on each source handshake
                    if (dut_s_axis_tvalid && dut_s_axis_tready)
                        input_count_r <= input_count_r + 1;

                    // Output count (capped at OUTPUT_MAX_LEN) and overflow
                    if (dut_m_axis_tvalid && dut_m_axis_tready) begin
                        if (output_count_r < output_max_len_r)
                            output_count_r <= output_count_r + 1;
                        else
                            output_overflow_sticky_r <= 1'b1;
                    end

                    // Input/output done from FSM transitions
                    if (src_state == SRC_DONE)
                        input_done_r <= 1'b1;
                    if (snk_state == SNK_DONE)
                        output_done_r <= 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------------------------
    // Stream source FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_pulse_r) begin
            src_state <= SRC_IDLE;
            src_ptr   <= {MEM_ADDR_WIDTH{1'b0}};
        end else begin
            case (src_state)
                SRC_IDLE: begin
                    if (start_pulse_r && enable_r && !running_r) begin
                        src_ptr   <= {MEM_ADDR_WIDTH{1'b0}};
                        src_state <= SRC_STREAM;
                    end
                end
                SRC_STREAM: begin
                    if (dut_s_axis_tvalid && dut_s_axis_tready) begin
                        if (dut_s_axis_tlast) begin
                            src_state <= SRC_DONE;
                        end else begin
                            src_ptr <= src_ptr + 1;
                        end
                    end
                end
                SRC_DONE: begin
                    src_state <= SRC_IDLE;
                end
                default: src_state <= SRC_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Stream sink FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn || soft_reset_pulse_r) begin
            snk_state <= SNK_IDLE;
            snk_ptr   <= {MEM_ADDR_WIDTH{1'b0}};
        end else begin
            case (snk_state)
                SNK_IDLE: begin
                    if (start_pulse_r && enable_r && !running_r) begin
                        snk_ptr   <= {MEM_ADDR_WIDTH{1'b0}};
                        snk_state <= SNK_CAPTURE;
                    end
                end
                SNK_CAPTURE: begin
                    // Capture sample into output_mem when accepted
                    if (dut_m_axis_tvalid && dut_m_axis_tready) begin
                        if (output_count_r < output_max_len_r) begin
                            output_mem[snk_ptr] <= dut_m_axis_tdata;
                            snk_ptr <= snk_ptr + 1;
                        end
                        // Extra samples beyond OUTPUT_MAX_LEN are discarded
                        // (overflow_sticky set in status block above)
                    end
                    // Terminate on done_sticky (set 1 cycle after dut_done)
                    // or on timeout done
                    if (done_sticky_r) begin
                        snk_state <= SNK_DONE;
                    end
                end
                SNK_DONE: begin
                    snk_state <= SNK_IDLE;
                end
                default: snk_state <= SNK_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // DUT: frac_cfo_frame_corrector_top
    // -----------------------------------------------------------------------
    frac_cfo_frame_corrector_top #(
        .NSC             (NSC),
        .CP_LEN          (CP_LEN),
        .BUF_AW          (BUF_AW),
        .ACC_WIDTH       (ACC_WIDTH),
        .METRIC_WIDTH    (METRIC_WIDTH),
        .INDEX_WIDTH     (INDEX_WIDTH),
        .RESULT_WIDTH    (RESULT_WIDTH),
        .PHASE_WIDTH     (PHASE_WIDTH),
        .POWER_WIDTH     (POWER_WIDTH),
        .ENERGY_WIDTH    (ENERGY_WIDTH),
        .WINDOW_LEN      (WINDOW_LEN),
        .HIT_COUNT       (HIT_COUNT),
        .THRESHOLD       (THRESHOLD),
        .NCO_PHASE_WIDTH (NCO_PHASE_WIDTH),
        .LATENCY         (LATENCY)
    ) u_dut (
        .aclk    (aclk),
        .aresetn (dut_aresetn),

        .s_axis_tdata  (dut_s_axis_tdata),
        .s_axis_tvalid (dut_s_axis_tvalid),
        .s_axis_tready (dut_s_axis_tready),
        .s_axis_tlast  (dut_s_axis_tlast),

        .start       (dut_start),
        .done        (dut_done),
        .busy        (dut_busy),
        .frame_error (dut_frame_error),

        .threshold_in  ({{(ENERGY_WIDTH-32){1'b0}}, THRESHOLD[31:0]}),
        .window_len_in (WINDOW_LEN[6:0]),
        .hit_count_in  (HIT_COUNT[3:0]),

        .frame_index      (dut_frame_index),
        .frame_found      (dut_frame_found),
        .peak_lag         (dut_peak_lag),
        .peak_metric      (dut_peak_metric),
        .frac_phase       (dut_frac_phase),
        .frac_phase_valid (dut_frac_phase_valid),

        .m_axis_tdata  (dut_m_axis_tdata),
        .m_axis_tvalid (dut_m_axis_tvalid),
        .m_axis_tready (dut_m_axis_tready),
        .m_axis_tlast  (dut_m_axis_tlast)
    );

endmodule
