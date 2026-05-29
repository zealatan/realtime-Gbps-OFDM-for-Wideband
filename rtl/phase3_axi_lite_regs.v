`timescale 1ns/1ps

// phase3_axi_lite_regs — P3-14A
// AXI4-Lite slave register bank for Phase3 OFDM synchronizer wrapper.
// Derived from phase2_axi_lite_regs.v (P2-14/P2-18/P2-20D/P2-20E).
//
// Register map (byte addresses, 32-bit words, ADDR_WIDTH=7):
//   0x00 VERSION           [31:0] R,  constant 0x00316001
//   0x04 CONTROL           [1:0]  bit0=enable(R/W), bit1=soft_reset_pulse(W1S, reads 0)
//   0x08 STATUS            [7:0]  bit0=busy(live), bit1=done_seen(W1C), bit2=error_seen(W1C)
//                                  bit[7:4]=last_error_code (latched on error completion)
//   0x0C FRAME_LEN_SAMPLES [11:0] R/W, default=576, range 1-4095
//   0x10 INPUT_COUNT       [31:0] R
//   0x14 OUTPUT_COUNT      [31:0] R
//   0x18 FRAME_START_VALID [0]    R/clear — sticky latch; read clears
//                                  Set by frame_start_valid_i. No snapshot trigger.
//   0x1C FRAME_START_INDEX [11:0] R, latched on frame_start_valid_i (or snapshot)
//   0x20 PEAK_INDEX        [8:0]  R, latched on frame_start_valid_i (or snapshot)
//   0x24 SLOT_START_INDEX  [11:0] R, latched on slot_start_valid_i (or snapshot)
//   0x28 FRAC_CFO_VALID    [0]    R/clear — sticky latch; read clears
//   0x2C FRAC_CFO_PHASE    [31:0] R, Q1.15 frac CFO word sign-extended 16->32 (or snapshot)
//   0x30 PSS_DONE          [0]    R/clear — sticky; TODO: not yet wired
//   0x34 SSS_DONE          [0]    R/clear — sticky; TODO: not yet wired
//   0x38 INT_CFO_VALID     [0]    R/clear — sticky latch; read clears; set by int_cfo_valid_i.
//                                  Reading with latch=1 triggers snapshot of all sync results.
//   0x3C INT_CFO_EST       [31:0] R, 32-bit NCO step word from dbg_integer_cfo_word (or snapshot)
//   0x40 INT_CFO_INDEX     [8:0]  R, Meyr peak index; TODO: not yet wired (always 0)
//   0x44 INT_CFO_APPLIED   [0]    R, sticky; TODO: replay buffer not yet connected
//   0x48 RESET_STATUS      [1:0]  bit0=RESET_DONE(sticky W1C), bit1=PIPELINE_IDLE(live)
//   0x4C DEBUG_CONTROL     [3:0]  bit0=BYPASS_ENABLE(R/W), bit1=FORCE_TLAST(self-clear),
//                                  bit2=COUNTER_CLEAR(self-clear), bit3=DEBUG_MODE(R/W)
//   0x50 TLAST_COUNT       [31:0] R, from tlast_count_i
//   0x54 ERROR_FLAGS       [3:0]  sticky W1C: bit0=FRAME_LEN_MISMATCH, bit1=TLAST_TIMEOUT,
//                                  bit2=RESET_WHILE_ACTIVE, bit3=STALL_TIMEOUT
//   other: SLVERR
//
// Snapshot protocol:
//   When SW reads 0x38 (INT_CFO_VALID) while latch=1:
//   - Five sync result registers frozen simultaneously into shadow registers.
//   - While snapshot_valid=1, reads of 0x1C/0x20/0x24/0x2C/0x3C return shadow values.
//
// Note on frame_start_valid_i timing:
//   dbg_frame_start_valid, dbg_peak_valid, and dbg_frac_cfo_valid all fire on the same
//   cycle (frac_frac_phase_valid) in phase3_sync_top. The wrapper passes one pulse as
//   frame_start_valid_i to this module, which latches all three fields simultaneously.

module phase3_axi_lite_regs #(
    parameter integer ADDR_WIDTH      = 7,
    parameter integer DATA_WIDTH      = 32,
    parameter integer BUF_AW          = 12,
    parameter integer INDEX_WIDTH     = 9,
    parameter integer PHASE_WIDTH     = 16,
    parameter integer NCO_PHASE_WIDTH = 32
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

    // Status inputs from phase3_sync_top (via wrapper)
    input  wire                         busy_i,
    input  wire                         done_pulse_i,
    input  wire                         error_i,
    input  wire [3:0]                   error_code_i,
    input  wire [DATA_WIDTH-1:0]        input_count_i,
    input  wire [DATA_WIDTH-1:0]        output_count_i,
    input  wire                         frame_start_valid_i,
    input  wire [BUF_AW-1:0]           frame_start_index_i,
    input  wire [INDEX_WIDTH-1:0]       peak_index_i,
    input  wire                         slot_start_valid_i,
    input  wire [BUF_AW-1:0]           slot_start_index_i,
    input  wire                         frac_cfo_valid_i,
    input  wire [PHASE_WIDTH-1:0]       frac_cfo_phase_i,
    input  wire                         int_cfo_valid_i,
    input  wire [NCO_PHASE_WIDTH-1:0]   int_cfo_est_i,

    // P3-14B: INT_CFO_APPLIED and INT_CFO_INDEX from wrapper
    input  wire                         int_cfo_applied_i,
    input  wire [INDEX_WIDTH-1:0]       int_cfo_index_i,

    // Wrapper-level status inputs
    input  wire                    reset_done_i,
    input  wire [DATA_WIDTH-1:0]   tlast_count_i,
    input  wire [3:0]              error_set_i,

    // Control outputs
    output reg                     enable_o,
    output reg                     soft_reset_pulse_o,

    // Debug control outputs
    output reg                     bypass_enable_o,
    output reg                     force_tlast_o,
    output reg                     counter_clear_o,
    output reg                     debug_mode_o,
    output reg  [11:0]             frame_len_samples_o
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    localparam [ADDR_WIDTH-1:0] ADDR_VERSION      = 7'h00;
    localparam [ADDR_WIDTH-1:0] ADDR_CONTROL      = 7'h04;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS       = 7'h08;
    localparam [ADDR_WIDTH-1:0] ADDR_FRAME_LEN    = 7'h0C;
    localparam [ADDR_WIDTH-1:0] ADDR_IN_COUNT     = 7'h10;
    localparam [ADDR_WIDTH-1:0] ADDR_OUT_COUNT    = 7'h14;
    localparam [ADDR_WIDTH-1:0] ADDR_FSV          = 7'h18;   // FRAME_START_VALID
    localparam [ADDR_WIDTH-1:0] ADDR_FSI          = 7'h1C;   // FRAME_START_INDEX
    localparam [ADDR_WIDTH-1:0] ADDR_PEAK_IDX     = 7'h20;
    localparam [ADDR_WIDTH-1:0] ADDR_SLOT_IDX     = 7'h24;
    localparam [ADDR_WIDTH-1:0] ADDR_FRAC_CFO_V   = 7'h28;   // FRAC_CFO_VALID
    localparam [ADDR_WIDTH-1:0] ADDR_FRAC_CFO_P   = 7'h2C;   // FRAC_CFO_PHASE
    localparam [ADDR_WIDTH-1:0] ADDR_PSS_DONE     = 7'h30;
    localparam [ADDR_WIDTH-1:0] ADDR_SSS_DONE     = 7'h34;
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_V    = 7'h38;   // INT_CFO_VALID (snapshot trigger)
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_E    = 7'h3C;   // INT_CFO_EST
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_I    = 7'h40;   // INT_CFO_INDEX (TODO)
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO_A    = 7'h44;   // INT_CFO_APPLIED (TODO)
    localparam [ADDR_WIDTH-1:0] ADDR_RESET_STATUS = 7'h48;
    localparam [ADDR_WIDTH-1:0] ADDR_DEBUG_CTRL   = 7'h4C;
    localparam [ADDR_WIDTH-1:0] ADDR_TLAST_COUNT  = 7'h50;
    localparam [ADDR_WIDTH-1:0] ADDR_ERROR_FLAGS  = 7'h54;

    localparam [DATA_WIDTH-1:0] VERSION_VAL = 32'h00316001;

    // -----------------------------------------------------------------------
    // Live-latch registers for phase3_sync_top debug outputs
    // -----------------------------------------------------------------------
    reg [BUF_AW-1:0]           frame_start_index_r;
    reg [INDEX_WIDTH-1:0]       peak_index_r;
    reg [BUF_AW-1:0]           slot_start_index_r;
    reg [PHASE_WIDTH-1:0]       frac_cfo_phase_r;
    reg [NCO_PHASE_WIDTH-1:0]   int_cfo_est_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            frame_start_index_r <= {BUF_AW{1'b0}};
            peak_index_r        <= {INDEX_WIDTH{1'b0}};
            frac_cfo_phase_r    <= {PHASE_WIDTH{1'b0}};
        end else if (frame_start_valid_i) begin
            frame_start_index_r <= frame_start_index_i;
            peak_index_r        <= peak_index_i;
            frac_cfo_phase_r    <= frac_cfo_phase_i;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            slot_start_index_r <= {BUF_AW{1'b0}};
        end else if (slot_start_valid_i) begin
            slot_start_index_r <= slot_start_index_i;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            int_cfo_est_r <= {NCO_PHASE_WIDTH{1'b0}};
        end else if (int_cfo_valid_i) begin
            int_cfo_est_r <= int_cfo_est_i;
        end
    end

    // P3-14B: INT_CFO_INDEX latch (latched on same valid pulse as int_cfo_est)
    reg [INDEX_WIDTH-1:0] int_cfo_index_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            int_cfo_index_r <= {INDEX_WIDTH{1'b0}};
        end else if (int_cfo_valid_i) begin
            int_cfo_index_r <= int_cfo_index_i;
        end
    end

    // -----------------------------------------------------------------------
    // Snapshot registers (frozen on INT_CFO_VALID read-while-set)
    // -----------------------------------------------------------------------
    reg        snapshot_valid;
    reg [BUF_AW-1:0]           snap_frame_start_index;
    reg [INDEX_WIDTH-1:0]       snap_peak_index;
    reg [BUF_AW-1:0]           snap_slot_start_index;
    reg [PHASE_WIDTH-1:0]       snap_frac_cfo_phase;
    reg [NCO_PHASE_WIDTH-1:0]   snap_int_cfo_est;

    wire ar_fire      = s_axi_arvalid && s_axi_arready;
    wire snap_trigger = ar_fire &&
                        (s_axi_araddr == ADDR_INT_CFO_V) &&
                        int_cfo_valid_latch;

    always @(posedge aclk) begin
        if (!aresetn) begin
            snapshot_valid          <= 1'b0;
            snap_frame_start_index  <= {BUF_AW{1'b0}};
            snap_peak_index         <= {INDEX_WIDTH{1'b0}};
            snap_slot_start_index   <= {BUF_AW{1'b0}};
            snap_frac_cfo_phase     <= {PHASE_WIDTH{1'b0}};
            snap_int_cfo_est        <= {NCO_PHASE_WIDTH{1'b0}};
        end else if (snap_trigger) begin
            snapshot_valid          <= 1'b1;
            snap_frame_start_index  <= frame_start_index_r;
            snap_peak_index         <= peak_index_r;
            snap_slot_start_index   <= slot_start_index_r;
            snap_frac_cfo_phase     <= frac_cfo_phase_r;
            snap_int_cfo_est        <= int_cfo_est_r;
        end
    end

    // -----------------------------------------------------------------------
    // Sticky latches for valid pulses (read-clear)
    // -----------------------------------------------------------------------
    reg frame_start_valid_latch;
    reg frac_cfo_valid_latch;
    reg int_cfo_valid_latch;

    always @(posedge aclk) begin
        if (!aresetn) begin
            frame_start_valid_latch <= 1'b0;
        end else begin
            if (frame_start_valid_i)
                frame_start_valid_latch <= 1'b1;
            if (ar_fire && (s_axi_araddr == ADDR_FSV))
                frame_start_valid_latch <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            frac_cfo_valid_latch <= 1'b0;
        end else begin
            if (frac_cfo_valid_i)
                frac_cfo_valid_latch <= 1'b1;
            if (ar_fire && (s_axi_araddr == ADDR_FRAC_CFO_V))
                frac_cfo_valid_latch <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            int_cfo_valid_latch <= 1'b0;
        end else begin
            if (int_cfo_valid_i)
                int_cfo_valid_latch <= 1'b1;
            if (ar_fire && (s_axi_araddr == ADDR_INT_CFO_V))
                int_cfo_valid_latch <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // STATUS: done_seen (W1C), error_seen (W1C), last_error_code
    // done_seen: set on any done pulse; error_seen + last_error_code: set on error completion
    // -----------------------------------------------------------------------
    reg        done_seen_r;
    reg        error_seen_r;
    reg  [3:0] last_error_code_r;

    // Write channel pending state (declared before use in write logic)
    reg                    aw_pend;
    reg [ADDR_WIDTH-1:0]   aw_addr_r;
    reg                    w_pend;
    reg [DATA_WIDTH-1:0]   w_data_r;
    reg [DATA_WIDTH/8-1:0] w_strb_r;

    wire aw_fire  = s_axi_awvalid && s_axi_awready;
    wire w_fire   = s_axi_wvalid  && s_axi_wready;
    wire do_write = (aw_pend || aw_fire) && (w_pend || w_fire);

    wire [ADDR_WIDTH-1:0] eff_addr = aw_fire ? s_axi_awaddr : aw_addr_r;
    wire [DATA_WIDTH-1:0] eff_data = w_fire  ? s_axi_wdata  : w_data_r;

    wire write_ok_ctrl   = do_write && (eff_addr == ADDR_CONTROL);
    wire write_ok_status = do_write && (eff_addr == ADDR_STATUS);
    wire write_ok_frame  = do_write && (eff_addr == ADDR_FRAME_LEN);
    wire write_ok_rst    = do_write && (eff_addr == ADDR_RESET_STATUS);
    wire write_ok_dbgctl = do_write && (eff_addr == ADDR_DEBUG_CTRL);
    wire write_ok_errflg = do_write && (eff_addr == ADDR_ERROR_FLAGS);

    always @(posedge aclk) begin
        if (!aresetn) begin
            done_seen_r      <= 1'b0;
            error_seen_r     <= 1'b0;
            last_error_code_r <= 4'd0;
        end else begin
            if (done_pulse_i) begin
                done_seen_r <= 1'b1;
                if (error_i) begin
                    error_seen_r      <= 1'b1;
                    last_error_code_r <= error_code_i;
                end
            end
            if (write_ok_status && s_axi_wstrb[0]) begin
                if (eff_data[1]) done_seen_r  <= 1'b0;
                if (eff_data[2]) error_seen_r <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // RESET_DONE sticky latch (W1C)
    // -----------------------------------------------------------------------
    reg reset_done_latch;

    wire pipeline_idle_live = (input_count_i == output_count_i);

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
    // ERROR_FLAGS sticky W1C
    // -----------------------------------------------------------------------
    reg [3:0] error_flags_r;

    always @(posedge aclk) begin
        if (!aresetn) begin
            error_flags_r <= 4'b0;
        end else begin
            if (|error_set_i)
                error_flags_r <= error_flags_r | error_set_i;
            else if (write_ok_errflg && s_axi_wstrb[0])
                error_flags_r <= error_flags_r & ~eff_data[3:0];
        end
    end

    // -----------------------------------------------------------------------
    // is_valid_addr
    // -----------------------------------------------------------------------
    function automatic is_valid_addr;
        input [ADDR_WIDTH-1:0] a;
        begin
            is_valid_addr = (a == ADDR_VERSION)      ||
                            (a == ADDR_CONTROL)      ||
                            (a == ADDR_STATUS)       ||
                            (a == ADDR_FRAME_LEN)    ||
                            (a == ADDR_IN_COUNT)     ||
                            (a == ADDR_OUT_COUNT)    ||
                            (a == ADDR_FSV)          ||
                            (a == ADDR_FSI)          ||
                            (a == ADDR_PEAK_IDX)     ||
                            (a == ADDR_SLOT_IDX)     ||
                            (a == ADDR_FRAC_CFO_V)   ||
                            (a == ADDR_FRAC_CFO_P)   ||
                            (a == ADDR_PSS_DONE)     ||
                            (a == ADDR_SSS_DONE)     ||
                            (a == ADDR_INT_CFO_V)    ||
                            (a == ADDR_INT_CFO_E)    ||
                            (a == ADDR_INT_CFO_I)    ||
                            (a == ADDR_INT_CFO_A)    ||
                            (a == ADDR_RESET_STATUS) ||
                            (a == ADDR_DEBUG_CTRL)   ||
                            (a == ADDR_TLAST_COUNT)  ||
                            (a == ADDR_ERROR_FLAGS);
        end
    endfunction

    // -----------------------------------------------------------------------
    // Write channel FSM (identical structure to phase2_axi_lite_regs)
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
                                 ((eff_addr == ADDR_CONTROL)      ||
                                  (eff_addr == ADDR_STATUS)       ||
                                  (eff_addr == ADDR_FRAME_LEN)    ||
                                  (eff_addr == ADDR_RESET_STATUS) ||
                                  (eff_addr == ADDR_DEBUG_CTRL)   ||
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
    // CONTROL register
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            enable_o           <= 1'b0;
            soft_reset_pulse_o <= 1'b0;
        end else begin
            soft_reset_pulse_o <= 1'b0;
            if (write_ok_ctrl && s_axi_wstrb[0]) begin
                enable_o <= eff_data[0];
                if (eff_data[1]) soft_reset_pulse_o <= 1'b1;
            end
        end
    end

    // -----------------------------------------------------------------------
    // FRAME_LEN_SAMPLES (default 576 = 2*(256+32))
    // -----------------------------------------------------------------------
    // DEBUG_CONTROL (bypass_enable persistent; force_tlast/counter_clear self-clear)
    always @(posedge aclk) begin
        if (!aresetn) begin
            bypass_enable_o     <= 1'b0;
            force_tlast_o       <= 1'b0;
            counter_clear_o     <= 1'b0;
            debug_mode_o        <= 1'b0;
            frame_len_samples_o <= 12'd576;
        end else begin
            force_tlast_o   <= 1'b0;
            counter_clear_o <= 1'b0;
            if (write_ok_dbgctl && s_axi_wstrb[0]) begin
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
    // Read channel
    // -----------------------------------------------------------------------
    wire [BUF_AW-1:0]         rd_frame_start_index =
        snapshot_valid ? snap_frame_start_index : frame_start_index_r;
    wire [INDEX_WIDTH-1:0]     rd_peak_index =
        snapshot_valid ? snap_peak_index        : peak_index_r;
    wire [BUF_AW-1:0]         rd_slot_start_index =
        snapshot_valid ? snap_slot_start_index  : slot_start_index_r;
    wire [PHASE_WIDTH-1:0]     rd_frac_cfo_phase =
        snapshot_valid ? snap_frac_cfo_phase    : frac_cfo_phase_r;
    wire [NCO_PHASE_WIDTH-1:0] rd_int_cfo_est =
        snapshot_valid ? snap_int_cfo_est       : int_cfo_est_r;

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
                        ADDR_VERSION:
                            s_axi_rdata <= VERSION_VAL;
                        ADDR_CONTROL:
                            s_axi_rdata <= {{(DATA_WIDTH-2){1'b0}}, 1'b0, enable_o};
                        ADDR_STATUS:
                            s_axi_rdata <= {{(DATA_WIDTH-8){1'b0}},
                                            last_error_code_r, 1'b0,
                                            error_seen_r, done_seen_r, busy_i};
                        ADDR_FRAME_LEN:
                            s_axi_rdata <= {{(DATA_WIDTH-12){1'b0}}, frame_len_samples_o};
                        ADDR_IN_COUNT:
                            s_axi_rdata <= input_count_i;
                        ADDR_OUT_COUNT:
                            s_axi_rdata <= output_count_i;
                        ADDR_FSV:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}}, frame_start_valid_latch};
                        ADDR_FSI:
                            s_axi_rdata <= {{(DATA_WIDTH-BUF_AW){1'b0}}, rd_frame_start_index};
                        ADDR_PEAK_IDX:
                            s_axi_rdata <= {{(DATA_WIDTH-INDEX_WIDTH){1'b0}}, rd_peak_index};
                        ADDR_SLOT_IDX:
                            s_axi_rdata <= {{(DATA_WIDTH-BUF_AW){1'b0}}, rd_slot_start_index};
                        ADDR_FRAC_CFO_V:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}}, frac_cfo_valid_latch};
                        ADDR_FRAC_CFO_P:
                            s_axi_rdata <= {{(DATA_WIDTH-PHASE_WIDTH){rd_frac_cfo_phase[PHASE_WIDTH-1]}},
                                            rd_frac_cfo_phase};
                        ADDR_PSS_DONE:  // TODO: not wired to phase3_sync_top
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                        ADDR_SSS_DONE:  // TODO: not wired to phase3_sync_top
                            s_axi_rdata <= {DATA_WIDTH{1'b0}};
                        ADDR_INT_CFO_V:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}}, int_cfo_valid_latch};
                        ADDR_INT_CFO_E:
                            s_axi_rdata <= rd_int_cfo_est;
                        ADDR_INT_CFO_I:
                            s_axi_rdata <= {{(DATA_WIDTH-INDEX_WIDTH){1'b0}}, int_cfo_index_r};
                        ADDR_INT_CFO_A:
                            s_axi_rdata <= {{(DATA_WIDTH-1){1'b0}}, int_cfo_applied_i};
                        ADDR_RESET_STATUS:
                            s_axi_rdata <= {{(DATA_WIDTH-2){1'b0}},
                                            pipeline_idle_live, reset_done_latch};
                        ADDR_DEBUG_CTRL:
                            s_axi_rdata <= {{(DATA_WIDTH-4){1'b0}},
                                            debug_mode_o, 1'b0, 1'b0, bypass_enable_o};
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
