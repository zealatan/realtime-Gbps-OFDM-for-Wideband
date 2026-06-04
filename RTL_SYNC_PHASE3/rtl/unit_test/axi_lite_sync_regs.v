`timescale 1ns/1ps

// axi_lite_sync_regs: AXI4-Lite slave register bank for Phase-1 OFDM synchronizer.
//
// Register map (byte addresses, 32-bit words):
//   0x00 CONTROL   [3:0] = {clear_sticky_pulse, soft_reset_pulse, enable, start_pulse}
//   0x04 STATUS    [5:0] = {meyr_valid_sticky, fft_error_sticky, frame_error_sticky,
//                            error_sticky, done_sticky, busy}  (read-only)
//   0x08 CFG_FRAME_LEN  frame_len[31:0]
//   0x0C CFG_NSC        nsc[31:0]
//   0x10 CFG_CP_LEN     cp_len[31:0]
//   0x14 DEBUG_INT_CFO  int_cfo_i[31:0]    (read-only, from datapath)
//   0x18 DEBUG_FRAC_PHASE frac_phase_i[31:0] (read-only, from datapath)
//   0x1C DEBUG_PEAK_INDEX peak_index_i[31:0] (read-only, from datapath)
//   0x20 DEBUG_ERROR_CODE error_code_i[31:0] (read-only, from datapath)
//   other: SLVERR
//
// Pulse bits (start_pulse, soft_reset_pulse, clear_sticky): write-1-to-pulse,
// assert internally for exactly one aclk, read back as 0.
// Sticky bits: set by rising edge of external inputs, cleared by clear_sticky pulse.

module axi_lite_sync_regs #(
    parameter integer ADDR_WIDTH = 6,
    parameter integer DATA_WIDTH = 32
) (
    input  wire                   aclk,
    input  wire                   aresetn,

    // AXI4-Lite slave
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready,

    // Datapath status inputs (combinatorial, sampled each cycle)
    input  wire                   busy_i,
    input  wire                   done_i,
    input  wire                   error_i,
    input  wire                   frame_error_i,
    input  wire                   fft_error_i,
    input  wire                   meyr_valid_i,

    // Debug readback inputs
    input  wire signed [DATA_WIDTH-1:0] int_cfo_i,
    input  wire signed [DATA_WIDTH-1:0] frac_phase_i,
    input  wire        [DATA_WIDTH-1:0] peak_index_i,
    input  wire        [DATA_WIDTH-1:0] error_code_i,

    // Control outputs
    output reg                    start_pulse_o,
    output reg                    enable_o,
    output reg                    soft_reset_o,
    output reg                    clear_sticky_o,

    // Config outputs
    output reg  [DATA_WIDTH-1:0]  frame_len_o,
    output reg  [DATA_WIDTH-1:0]  nsc_o,
    output reg  [DATA_WIDTH-1:0]  cp_len_o
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    // Address decode — word-aligned, bits [5:2] select register
    localparam [ADDR_WIDTH-1:0] ADDR_CONTROL   = 6'h00;
    localparam [ADDR_WIDTH-1:0] ADDR_STATUS    = 6'h04;
    localparam [ADDR_WIDTH-1:0] ADDR_FRAME_LEN = 6'h08;
    localparam [ADDR_WIDTH-1:0] ADDR_NSC       = 6'h0C;
    localparam [ADDR_WIDTH-1:0] ADDR_CP_LEN    = 6'h10;
    localparam [ADDR_WIDTH-1:0] ADDR_INT_CFO   = 6'h14;
    localparam [ADDR_WIDTH-1:0] ADDR_FRAC_PHASE= 6'h18;
    localparam [ADDR_WIDTH-1:0] ADDR_PEAK_IDX  = 6'h1C;
    localparam [ADDR_WIDTH-1:0] ADDR_ERR_CODE  = 6'h20;

    // Sticky bits
    reg done_sticky_r;
    reg error_sticky_r;
    reg frame_error_sticky_r;
    reg fft_error_sticky_r;
    reg meyr_valid_sticky_r;

    // Previous-cycle inputs for edge detect on sticky sources
    reg done_prev, error_prev, frame_err_prev, fft_err_prev, meyr_valid_prev;

    // Write channel: latch both AW and W independently, fire when both present
    reg                   aw_pend;
    reg [ADDR_WIDTH-1:0]  aw_addr_r;
    reg                   w_pend;
    reg [DATA_WIDTH-1:0]  w_data_r;
    reg [DATA_WIDTH/8-1:0] w_strb_r;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;

    // Both sides latched -> execute write
    wire do_write = (aw_pend || aw_fire) && (w_pend || w_fire);

    // Address validity
    function automatic is_valid_addr;
        input [ADDR_WIDTH-1:0] a;
        begin
            is_valid_addr = (a == ADDR_CONTROL)    ||
                            (a == ADDR_STATUS)     ||
                            (a == ADDR_FRAME_LEN)  ||
                            (a == ADDR_NSC)        ||
                            (a == ADDR_CP_LEN)     ||
                            (a == ADDR_INT_CFO)    ||
                            (a == ADDR_FRAC_PHASE) ||
                            (a == ADDR_PEAK_IDX)   ||
                            (a == ADDR_ERR_CODE);
        end
    endfunction

    // Byte-lane masked write helper
    function automatic [31:0] apply_wstrb;
        input [31:0] old_val;
        input [31:0] new_val;
        input [3:0]  strb;
        integer b;
        begin
            apply_wstrb = old_val;
            for (b = 0; b < 4; b = b + 1)
                if (strb[b]) apply_wstrb[b*8 +: 8] = new_val[b*8 +: 8];
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
            // Latch AW
            if (aw_fire) begin
                aw_addr_r <= s_axi_awaddr;
                aw_pend   <= 1'b1;
            end
            // Latch W
            if (w_fire) begin
                w_data_r <= s_axi_wdata;
                w_strb_r <= s_axi_wstrb;
                w_pend   <= 1'b1;
            end

            // Execute when both latched
            if (do_write) begin
                // Determine actual addr/data (may arrive same cycle as latch)
                // — already latched above or use direct if firing this cycle
                aw_pend <= 1'b0;
                w_pend  <= 1'b0;
            end

            // B channel
            if (do_write) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= (is_valid_addr(aw_fire ? s_axi_awaddr : aw_addr_r) &&
                                 // STATUS and debug regs are read-only
                                 (aw_fire ? s_axi_awaddr : aw_addr_r) != ADDR_STATUS    &&
                                 (aw_fire ? s_axi_awaddr : aw_addr_r) != ADDR_INT_CFO   &&
                                 (aw_fire ? s_axi_awaddr : aw_addr_r) != ADDR_FRAC_PHASE&&
                                 (aw_fire ? s_axi_awaddr : aw_addr_r) != ADDR_PEAK_IDX  &&
                                 (aw_fire ? s_axi_awaddr : aw_addr_r) != ADDR_ERR_CODE)
                                ? RESP_OKAY : RESP_SLVERR;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Deassert ready when pending, reassert when transaction clears
            s_axi_awready <= !(aw_pend && !do_write) && !aw_fire;
            s_axi_wready  <= !(w_pend  && !do_write) && !w_fire;
        end
    end

    // Resolved write address/data (combinatorial helper for register updates)
    wire [ADDR_WIDTH-1:0] eff_addr = aw_fire ? s_axi_awaddr : aw_addr_r;
    wire [DATA_WIDTH-1:0] eff_data = w_fire  ? s_axi_wdata  : w_data_r;
    wire [DATA_WIDTH/8-1:0] eff_strb = w_fire ? s_axi_wstrb : w_strb_r;

    wire write_ok = do_write &&
                    is_valid_addr(eff_addr) &&
                    eff_addr != ADDR_STATUS     &&
                    eff_addr != ADDR_INT_CFO    &&
                    eff_addr != ADDR_FRAC_PHASE &&
                    eff_addr != ADDR_PEAK_IDX   &&
                    eff_addr != ADDR_ERR_CODE;

    // -----------------------------------------------------------------------
    // Register file
    // -----------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            enable_o          <= 1'b0;
            start_pulse_o     <= 1'b0;
            soft_reset_o      <= 1'b0;
            clear_sticky_o    <= 1'b0;
            frame_len_o       <= 32'd2880;
            nsc_o             <= 32'd256;
            cp_len_o          <= 32'd32;
            done_sticky_r     <= 1'b0;
            error_sticky_r    <= 1'b0;
            frame_error_sticky_r <= 1'b0;
            fft_error_sticky_r   <= 1'b0;
            meyr_valid_sticky_r  <= 1'b0;
            done_prev         <= 1'b0;
            error_prev        <= 1'b0;
            frame_err_prev    <= 1'b0;
            fft_err_prev      <= 1'b0;
            meyr_valid_prev   <= 1'b0;
        end else begin
            // Pulse outputs default off each cycle
            start_pulse_o  <= 1'b0;
            soft_reset_o   <= 1'b0;
            clear_sticky_o <= 1'b0;

            // Edge-detect sticky inputs
            done_prev        <= done_i;
            error_prev       <= error_i;
            frame_err_prev   <= frame_error_i;
            fft_err_prev     <= fft_error_i;
            meyr_valid_prev  <= meyr_valid_i;

            // Set sticky on rising edge
            if (done_i        && !done_prev)        done_sticky_r        <= 1'b1;
            if (error_i       && !error_prev)        error_sticky_r       <= 1'b1;
            if (frame_error_i && !frame_err_prev)    frame_error_sticky_r <= 1'b1;
            if (fft_error_i   && !fft_err_prev)      fft_error_sticky_r   <= 1'b1;
            if (meyr_valid_i  && !meyr_valid_prev)   meyr_valid_sticky_r  <= 1'b1;

            // Register writes
            if (write_ok) begin
                case (eff_addr)
                    ADDR_CONTROL: begin
                        // bit0=start_pulse, bit1=enable, bit2=soft_reset, bit3=clear_sticky
                        // Apply byte-lane mask to the byte containing control bits (byte 0)
                        if (eff_strb[0]) begin
                            if (eff_data[0]) start_pulse_o  <= 1'b1;
                            enable_o         <= eff_data[1];
                            if (eff_data[2]) soft_reset_o   <= 1'b1;
                            if (eff_data[3]) clear_sticky_o <= 1'b1;
                        end
                    end
                    ADDR_FRAME_LEN: frame_len_o <= apply_wstrb(frame_len_o, eff_data, eff_strb);
                    ADDR_NSC:       nsc_o       <= apply_wstrb(nsc_o,       eff_data, eff_strb);
                    ADDR_CP_LEN:    cp_len_o    <= apply_wstrb(cp_len_o,    eff_data, eff_strb);
                    default: ; // SLVERR handled in B channel
                endcase
            end

            // Clear sticky when clear_sticky_o fires
            if (clear_sticky_o) begin
                done_sticky_r        <= 1'b0;
                error_sticky_r       <= 1'b0;
                frame_error_sticky_r <= 1'b0;
                fft_error_sticky_r   <= 1'b0;
                meyr_valid_sticky_r  <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Read channel
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
                        ADDR_CONTROL:    s_axi_rdata <= {28'b0, 1'b0, 1'b0, enable_o, 1'b0};
                        ADDR_STATUS:     s_axi_rdata <= {26'b0,
                                                         meyr_valid_sticky_r,
                                                         fft_error_sticky_r,
                                                         frame_error_sticky_r,
                                                         error_sticky_r,
                                                         done_sticky_r,
                                                         busy_i};
                        ADDR_FRAME_LEN:  s_axi_rdata <= frame_len_o;
                        ADDR_NSC:        s_axi_rdata <= nsc_o;
                        ADDR_CP_LEN:     s_axi_rdata <= cp_len_o;
                        ADDR_INT_CFO:    s_axi_rdata <= int_cfo_i;
                        ADDR_FRAC_PHASE: s_axi_rdata <= frac_phase_i;
                        ADDR_PEAK_IDX:   s_axi_rdata <= peak_index_i;
                        ADDR_ERR_CODE:   s_axi_rdata <= error_code_i;
                        default:         s_axi_rdata <= {DATA_WIDTH{1'b0}};
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
