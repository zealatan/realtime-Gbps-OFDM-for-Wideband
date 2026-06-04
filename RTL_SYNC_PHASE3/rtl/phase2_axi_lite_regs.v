`timescale 1ns/1ps

// phase2_axi_lite_regs — P2-14 / P2-18 / P2-20D / P2-20E
// AXI4-Lite slave register bank exposing Phase2 streaming sync status counters.
//
// Register map (byte addresses, 32-bit words, ADDR_WIDTH=7):
//   0x00 CONTROL          [1:0] bit0=enable(R/W), bit1=soft_reset_pulse(W1S, reads 0)
//   0x04 STATUS           [0]   bit0=nco_locked_seen (R, from input or snapshot)
//   0x08 INPUT_COUNT      [31:0] R, from input_count_i (or snapshot)
//   0x0C OUTPUT_COUNT     [31:0] R, from output_count_i (or snapshot)
//   0x10 TIMING_LOCK_COUNT[31:0] R, from timing_lock_count_i (or snapshot)
//   0x14 NCO_LOCKED_SEEN  [0]   R, same as STATUS bit0 (or snapshot)
//   0x18 LAST_LOCK_INDEX  [31:0] R, from last_lock_index_i (or snapshot)
//   0x1C LAST_FRAC_PHASE  [31:0] R, last_frac_phase_i[15:0] sign-extended (or snapshot)
//   0x20 VERSION          [31:0] R, constant 0x00216001
//   0x24 INT_CFO_VALID    [0]   R/clear — sticky latch; read clears; set by int_cfo_valid_i
//                               Reading with latch=1 triggers snapshot of all status registers.
//   0x28 INT_CFO_ESTIMATE [31:0] R, int_cfo_estimate_i[15:0] sign-extended (or snapshot)
//   0x2C INT_CFO_LOCK_IDX [8:0] R, raw peak index from Meyr correlator
//   0x30 RESET_STATUS     [1:0] bit0=RESET_DONE(sticky,W1C), bit1=PIPELINE_IDLE(live)
//   0x34 DEBUG_CONTROL    [3:0] bit0=BYPASS_ENABLE(R/W), bit1=FORCE_TLAST(self-clear),
//                               bit2=COUNTER_CLEAR(self-clear), bit3=DEBUG_MODE(R/W)
//   0x38 FRAME_LEN_SAMPLES[11:0] R/W, default=288, range 1-4095
//   0x3C TLAST_COUNT      [31:0] R, tlast_count_i (output TLAST fires since last clear)
//   0x40 ERROR_FLAGS      [3:0] sticky W1C: bit0=FRAME_LEN_MISMATCH, bit1=TLAST_TIMEOUT,
//                               bit2=RESET_WHILE_ACTIVE, bit3=STALL_TIMEOUT
//   other: SLVERR
//
// Snapshot protocol (P2-20D):
//   When SW reads 0x24 (INT_CFO_VALID) while the latch = 1:
//   - All 7 status registers are frozen into shadow registers simultaneously.
//   - snapshot_valid latches until the next trigger or until reset.
//   - While snapshot_valid=1, reads of 0x04..0x1C and 0x28 return shadow values.
//
// Reset protocol (P2-20D):
//   RESET_DONE (bit0 of 0x30) set by reset_done_i pulse; W1C clear.
//   PIPELINE_IDLE (bit1 of 0x30) is live: (input_count_i == output_count_i).
//
// Debug features (P2-20E):
//   BYPASS_ENABLE: when set, wrapper routes input AXIS directly to output AXIS.
//   FORCE_TLAST: self-clearing; fires next output TLAST immediately on next beat.
//   COUNTER_CLEAR: self-clearing; clears tlast_count in wrapper.
//   DEBUG_MODE: persistent; reserved for future diagnostic use.
//   FRAME_LEN_SAMPLES: configures wrapper output frame counter period (default 288).
//   TLAST_COUNT: read-only count of output TLAST fires since last COUNTER_CLEAR.
//   ERROR_FLAGS: sticky W1C error indicators from wrapper logic.

module phase2_axi_lite_regs #(
    parameter integer ADDR_WIDTH = 7,
    parameter integer DATA_WIDTH = 32
) (
    input  wire                    aclk,
    input  wire                    aresetn,

    // AXI4-Lite slave
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // Status inputs (live; served from snapshot when snapshot_valid=1)
    input  wire                    nco_locked_seen_i,
    input  wire [DATA_WIDTH-1:0]   input_count_i,
    input  wire [DATA_WIDTH-1:0]   output_count_i,
    input  wire [DATA_WIDTH-1:0]   timing_lock_count_i,
    input  wire [DATA_WIDTH-1:0]   last_lock_index_i,
    input  wire [15:0]             last_frac_phase_i,

    // Integer CFO status inputs (P2-18)
    input  wire                    int_cfo_valid_i,
    input  wire [15:0]             int_cfo_estimate_i,
    input  wire [8:0]              int_cfo_lock_index_i,

    // Reset completion pulse from wrapper (P2-20D)
    input  wire                    reset_done_i,

    // Debug status inputs (P2-20E)
    input  wire [DATA_WIDTH-1:0]   tlast_count_i,     // from wrapper TLAST counter
    input  wire [3:0]              error_set_i,        // one-cycle set pulses from wrapper

    // Control outputs
    output reg                     enable_o,
    output reg                     soft_reset_pulse_o,

    // Debug control outputs (P2-20E)
    output reg                     bypass_enable_o,
    output reg                     force_tlast_o,      // self-clearing pulse
    output reg                     counter_clear_o,    // self-clearing pulse
    output reg                     debug_mode_o,
    output reg  [11:0]             frame_len_samples_o
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    localparam [ADDR_WIDTH-1:0] ADDR_CONTROL      = 7'h00;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS        = 7'h04;
    localparam [ADDR_WIDTH-1:0] ADDR_IN_COUNT      = 7'h08;
    localparam [ADDR_WIDTH-1:0] ADDR_OUT_COUNT     = 7'h0C;
    localparam [ADDR_WIDTH-1:0] ADDR_LOCK_COUNT    = 7'h10;
    localparam [ADDR_WIDTH-1:0] ADDR_NCO_LOCKED    = 7'h14;
    localparam [ADDR_WIDTH-1:0] ADDR_LOCK_IDX      = 7'h18;
    localparam [ADDR_WIDTH-1:0] ADDR_FRAC_PHASE    = 7'h1C;
    localparam [ADDR_WIDTH-1:0] ADDR_VERSION       = 7'h20;
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_VALID = 7'h24;
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_EST   = 7'h28;
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_IDX   = 7'h2C;
    localparam [ADDR_WIDTH-1:0] ADDR_RESET_STATUS  = 7'h30;
    localparam [ADDR_WIDTH-1:0] ADDR_DEBUG_CTRL    = 7'h34;   // P2-20E
    localparam [ADDR_WIDTH-1:0] ADDR_FRAME_LEN     = 7'h38;   // P2-20E
    localparam [ADDR_WIDTH-1:0] ADDR_TLAST_COUNT   = 7'h3C;   // P2-20E
    localparam [ADDR_WIDTH-1:0] ADDR_ERROR_FLAGS   = 7'h40;   // P2-20E

    localparam [DATA_WIDTH-1:0] VERSION_VAL = 32'h00216001;   // bumped P2-20E

    // -----------------------------------------------------------------------
    // Snapshot registers (P2-20D)
    // -----------------------------------------------------------------------
    reg        snapshot_valid;
    reg [31:0] snap_input_count;
    reg [31:0] snap_output_count;
    reg [31:0] snap_timing_lock_count;
    reg [31:0] snap_last_lock_index;
    reg [15:0] snap_last_frac_phase;
    reg [15:0] snap_int_cfo_estimate;
    reg        snap_nco_locked_seen;

    reg int_cfo_valid_latch;

    wire ar_fire      = s_axi_arvalid && s_axi_arready;
    wire snap_trigger = ar_fire &&
                        (s_axi_araddr == ADDR_INT_CFO_VALID) &&
                        int_cfo_valid_latch;

    always @(posedge aclk) begin
        if (!aresetn) begin
            snapshot_valid         <= 1'b0;
            snap_input_count       <= 32'd0;
            snap_output_count      <= 32'd0;
            snap_timing_lock_count <= 32'd0;
            snap_last_lock_index   <= 32'd0;
            snap_last_frac_phase   <= 16'd0;
            snap_int_cfo_estimate  <= 16'd0;
            snap_nco_locked_seen   <= 1'b0;
        end else if (snap_trigger) begin
            snapshot_valid         <= 1'b1;
            snap_input_count       <= input_count_i;
            snap_output_count      <= output_count_i;
            snap_timing_lock_count <= timing_lock_count_i;
            snap_last_lock_index   <= last_lock_index_i;
            snap_last_frac_phase   <= last_frac_phase_i;
            snap_int_cfo_estimate  <= int_cfo_estimate_i;
            snap_nco_locked_seen   <= nco_locked_seen_i;
        end
    end

    // -----------------------------------------------------------------------
    // INT_CFO_VALID sticky latch (P2-18)
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            int_cfo_valid_latch <= 1'b0;
        end else begin
            if (int_cfo_valid_i)
                int_cfo_valid_latch <= 1'b1;
            if (ar_fire && (s_axi_araddr == ADDR_INT_CFO_VALID))
                int_cfo_valid_latch <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // RESET_DONE sticky latch (P2-20D)
    // -----------------------------------------------------------------------
    reg reset_done_latch;

    wire pipeline_idle_live = (input_count_i == output_count_i);

    // Write channel pending state
    reg                    aw_pend;
    reg [ADDR_WIDTH-1:0]   aw_addr_r;
    reg                    w_pend;
    reg [DATA_WIDTH-1:0]   w_data_r;
    reg [DATA_WIDTH/8-1:0] w_strb_r;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire do_write = (aw_pend || aw_fire) && (w_pend || w_fire);

    wire [ADDR_WIDTH-1:0]   eff_addr = aw_fire ? s_axi_awaddr : aw_addr_r;
    wire [DATA_WIDTH-1:0]   eff_data = w_fire  ? s_axi_wdata  : w_data_r;

    wire write_ok_ctrl     = do_write && (eff_addr == ADDR_CONTROL);
    wire write_ok_rst      = do_write && (eff_addr == ADDR_RESET_STATUS);
    wire write_ok_dbg_ctrl = do_write && (eff_addr == ADDR_DEBUG_CTRL);
    wire write_ok_frame    = do_write && (eff_addr == ADDR_FRAME_LEN);
    wire write_ok_err_flg  = do_write && (eff_addr == ADDR_ERROR_FLAGS);

    always @(posedge aclk) begin
        if (!aresetn) begin
            reset_done_latch <= 1'b0;
        end else begin
            if (reset_done_i)
                reset_done_latch <= 1'b1;
            else if (write_ok_rst && s_axi_wstrb[0] && eff_data[0])
                reset_done_latch <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // ERROR_FLAGS sticky latch (P2-20E)
    // Set by error_set_i pulses from wrapper; W1C clear.
    // Set takes priority.
    // -----------------------------------------------------------------------
    reg [3:0] error_flags_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            error_flags_r <= 4'b0;
        end else begin
            if (|error_set_i)
                error_flags_r <= error_flags_r | error_set_i;
            else if (write_ok_err_flg && s_axi_wstrb[0])
                error_flags_r <= error_flags_r & ~eff_data[3:0];
        end
    end

    function automatic is_valid_addr;
        input [ADDR_WIDTH-1:0] a;
        begin
            is_valid_addr = (a == ADDR_CONTROL)      ||
                            (a == ADDR_STATUS)        ||
                            (a == ADDR_IN_COUNT)      ||
                            (a == ADDR_OUT_COUNT)     ||
                            (a == ADDR_LOCK_COUNT)    ||
                            (a == ADDR_NCO_LOCKED)    ||
                            (a == ADDR_LOCK_IDX)      ||
                            (a == ADDR_FRAC_PHASE)    ||
                            (a == ADDR_VERSION)       ||
                            (a == ADDR_INT_CFO_VALID) ||
                            (a == ADDR_INT_CFO_EST)   ||
                            (a == ADDR_INT_CFO_IDX)   ||
                            (a == ADDR_RESET_STATUS)  ||
                            (a == ADDR_DEBUG_CTRL)    ||
                            (a == ADDR_FRAME_LEN)     ||
                            (a == ADDR_TLAST_COUNT)   ||
                            (a == ADDR_ERROR_FLAGS);
        end
    endfunction

    // -----------------------------------------------------------------------
    // Write channel FSM
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_awready <= 1'b1;
            s_axi_wready  <= 1'b1;
            aw_pend       <= 1'b0;
            w_pend        <= 1'b0;
            aw_addr_r     <= {ADDR_WIDTH{1'b0}};
            w_data_r      <= {DATA_WIDTH{1'b0}};
            w_strb_r      <= {DATA_WIDTH/8{1'b0}};
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= RESP_OKAY;
        end else begin
            if (aw_fire) begin
                aw_addr_r <= s_axi_awaddr;
                aw_pend   <= 1'b1;
            end
            if (w_fire) begin
                w_data_r <= s_axi_wdata;
                w_strb_r <= s_axi_wstrb;
                w_pend   <= 1'b1;
            end
            if (do_write) begin
                aw_pend <= 1'b0;
                w_pend  <= 1'b0;
            end

            if (do_write) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= (is_valid_addr(eff_addr) &&
                                 ((eff_addr == ADDR_CONTROL)     ||
                                  (eff_addr == ADDR_RESET_STATUS)||
                                  (eff_addr == ADDR_DEBUG_CTRL)  ||
                                  (eff_addr == ADDR_FRAME_LEN)   ||
                                  (eff_addr == ADDR_ERROR_FLAGS)))
                                 ? RESP_OKAY : RESP_SLVERR;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            s_axi_awready <= !(aw_pend && !do_write) && !aw_fire;
            s_axi_wready  <= !(w_pend  && !do_write) && !w_fire;
        end
    end

    // -----------------------------------------------------------------------
    // Control register: enable_o and soft_reset_pulse_o
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            enable_o           <= 1'b0;
            soft_reset_pulse_o <= 1'b0;
        end else begin
            soft_reset_pulse_o <= 1'b0;
            if (write_ok_ctrl && s_axi_wstrb[0]) begin
                enable_o           <= eff_data[0];
                if (eff_data[1]) soft_reset_pulse_o <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Debug control registers (P2-20E)
    // bypass_enable and debug_mode are persistent R/W.
    // force_tlast and counter_clear are self-clearing pulses.
    // frame_len_samples defaults to 288; range 1-4095 enforced by SW convention.
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            bypass_enable_o     <= 1'b0;
            force_tlast_o       <= 1'b0;
            counter_clear_o     <= 1'b0;
            debug_mode_o        <= 1'b0;
            frame_len_samples_o <= 12'd288;
        end else begin
            force_tlast_o   <= 1'b0;
            counter_clear_o <= 1'b0;
            if (write_ok_dbg_ctrl && s_axi_wstrb[0]) begin
                bypass_enable_o <= eff_data[0];
                if (eff_data[1]) force_tlast_o   <= 1'b1;
                if (eff_data[2]) counter_clear_o <= 1'b1;
                debug_mode_o    <= eff_data[3];
            end
            if (write_ok_frame) begin
                if (s_axi_wstrb[0]) frame_len_samples_o[7:0]  <= eff_data[7:0];
                if (s_axi_wstrb[1]) frame_len_samples_o[11:8] <= eff_data[11:8];
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read channel — snapshot mux for status registers
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            s_axi_arready <= 1'b1;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rresp   <= RESP_OKAY;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                s_axi_arready <= 1'b0;
                s_axi_rvalid  <= 1'b1;
                if (is_valid_addr(s_axi_araddr)) begin
                    s_axi_rresp <= RESP_OKAY;
                    case (s_axi_araddr)
                        ADDR_CONTROL:
                            s_axi_rdata <= {{(DATA_WIDTH-2){1'b0}}, 1'b0, enable_o};
                        ADDR_STATUS:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}},
                                           snapshot_valid ? snap_nco_locked_seen : nco_locked_seen_i};
                        ADDR_IN_COUNT:
                            s_axi_rdata <= snapshot_valid ? snap_input_count      : input_count_i;
                        ADDR_OUT_COUNT:
                            s_axi_rdata <= snapshot_valid ? snap_output_count     : output_count_i;
                        ADDR_LOCK_COUNT:
                            s_axi_rdata <= snapshot_valid ? snap_timing_lock_count: timing_lock_count_i;
                        ADDR_NCO_LOCKED:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}},
                                           snapshot_valid ? snap_nco_locked_seen : nco_locked_seen_i};
                        ADDR_LOCK_IDX:
                            s_axi_rdata <= snapshot_valid ? snap_last_lock_index : last_lock_index_i;
                        ADDR_FRAC_PHASE: begin
                            if (snapshot_valid)
                                s_axi_rdata <= {{16{snap_last_frac_phase[15]}}, snap_last_frac_phase};
                            else
                                s_axi_rdata <= {{16{last_frac_phase_i[15]}}, last_frac_phase_i};
                        end
                        ADDR_VERSION:
                            s_axi_rdata <= VERSION_VAL;
                        ADDR_INT_CFO_VALID:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}}, int_cfo_valid_latch};
                        ADDR_INT_CFO_EST: begin
                            if (snapshot_valid)
                                s_axi_rdata <= {{16{snap_int_cfo_estimate[15]}}, snap_int_cfo_estimate};
                            else
                                s_axi_rdata <= {{16{int_cfo_estimate_i[15]}}, int_cfo_estimate_i};
                        end
                        ADDR_INT_CFO_IDX:
                            s_axi_rdata <= {{(DATA_WIDTH-9){1'b0}}, int_cfo_lock_index_i};
                        ADDR_RESET_STATUS:
                            s_axi_rdata <= {{(DATA_WIDTH-2){1'b0}}, pipeline_idle_live, reset_done_latch};
                        ADDR_DEBUG_CTRL:
                            s_axi_rdata <= {{(DATA_WIDTH-4){1'b0}}, debug_mode_o,
                                            1'b0, 1'b0, bypass_enable_o};
                        ADDR_FRAME_LEN:
                            s_axi_rdata <= {{(DATA_WIDTH-12){1'b0}}, frame_len_samples_o};
                        ADDR_TLAST_COUNT:
                            s_axi_rdata <= tlast_count_i;
                        ADDR_ERROR_FLAGS:
                            s_axi_rdata <= {{(DATA_WIDTH-4){1'b0}}, error_flags_r};
                        default:
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                    endcase
                end else begin
                    s_axi_rresp <= RESP_SLVERR;
                    s_axi_rdata <= {DATA_WIDTH{1'b0}};
                end
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b1;
            end
        end
    end

endmodule
