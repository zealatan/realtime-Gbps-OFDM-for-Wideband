`timescale 1ns/1ps

// fft256_xilinx_wrapper — Project-local wrapper around the Xilinx FFT IP.
//
// USE_BEHAVIORAL_STUB=1  compile-only passthrough stub (NOT an FFT).
// USE_BEHAVIORAL_STUB=0  actual Xilinx xfft_v9_1_8 IP via fft256_xilinx.v.
//
// Port interface (stable across modes):
//   s_axis_tdata = {Im[15:0], Re[15:0]} — Xilinx FFT native packing
//   m_axis_tdata = {Im[15:0], Re[15:0]} — same packing on output
//   m_axis_tuser = xk_index[7:0]        — bin index (natural order)
//
// Config channel (USE_BEHAVIORAL_STUB=0 only):
//   s_axis_config_tdata[0]   = FWD_INV  : 1 = forward FFT
//   s_axis_config_tdata[8:1] = SCALE_SCH: 8 bits, 1 bit per radix-2 stage
//                              0xAA = scale at alternating stages (conservative)
//   Config is driven continuously with tvalid=1 after reset deasserts.
//   IP latches config at the accepted handshake before each frame.
//
// Realtime throttle constraints (USE_BEHAVIORAL_STUB=0):
//   - C_THROTTLE_SCHEME=0: output has no m_axis_data_tready port.
//   - m_axis_tready input is accepted but NOT connected to the IP.
//   - Data flows at full rate; downstream must always be ready to consume.
//   - See T10 test notes for observed behavior.
//
// C_HAS_ARESETN=0: the underlying IP has no reset port.  aresetn is used
//   only to gate the config state machine in this wrapper.
//
// Verified port names: ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.veo
// Verified parameters: ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.xci

module fft256_xilinx_wrapper #(
    parameter integer FFT_LEN             = 256,
    parameter integer IQ_WIDTH            = 16,
    parameter integer FFT_OUT_WIDTH       = 16,
    parameter integer USE_BEHAVIORAL_STUB = 1,
    // Stub mode 2 only: STUB_TLAST_AT 0..255 = bin where TLAST fires; >=256 = never.
    // STUB_STOP_AT: last bin index to output (inclusive).
    parameter integer STUB_TLAST_AT       = 255,
    parameter integer STUB_STOP_AT        = 255
)(
    input  wire                       aclk,
    input  wire                       aresetn,
    input  wire                       start,        // sideband compat; unused internally

    // AXI4-Stream input  {Im[IQ_WIDTH-1:0], Re[IQ_WIDTH-1:0]}
    input  wire                       s_axis_tvalid,
    output wire                       s_axis_tready,
    input  wire [2*IQ_WIDTH-1:0]      s_axis_tdata,
    input  wire                       s_axis_tlast,

    // AXI4-Stream output {Im[FFT_OUT_WIDTH-1:0], Re[FFT_OUT_WIDTH-1:0]}
    output wire                       m_axis_tvalid,
    input  wire                       m_axis_tready,
    output wire [2*FFT_OUT_WIDTH-1:0] m_axis_tdata,
    output wire [7:0]                 m_axis_tuser,   // xk_index bin index
    output wire                       m_axis_tlast,

    // Status
    output wire                       busy,
    output wire                       done,
    output wire                       error,

    // IP event outputs
    output wire                       event_frame_started,
    output wire                       event_tlast_unexpected,
    output wire                       event_tlast_missing,
    output wire                       event_data_in_channel_halt,
    output wire                       event_data_out_channel_halt,
    output wire                       event_status_channel_halt
);

    // Config word: FWD_INV=1 (bit 0), SCALE_SCH=0xAA (bits[8:1])
    localparam [15:0] CFG_TDATA = 16'h0155;

    wire _unused = start;

    generate

        // =====================================================================
        // STUB MODE — compile-only passthrough, NOT an FFT
        // =====================================================================
        if (USE_BEHAVIORAL_STUB == 1) begin : gen_stub

            // synthesis translate_off
            initial begin
                $display("[WARNING] fft256_xilinx_wrapper: USE_BEHAVIORAL_STUB=1");
                $display("[WARNING] Passthrough stub only — NOT an FFT.");
            end
            // synthesis translate_on

            assign s_axis_tready = m_axis_tready;
            assign m_axis_tvalid = s_axis_tvalid;
            assign m_axis_tdata  = {{FFT_OUT_WIDTH{1'b0}}, s_axis_tdata[IQ_WIDTH-1:0]};
            assign m_axis_tuser  = 8'h00;
            assign m_axis_tlast  = s_axis_tlast;

            reg done_r;
            always @(posedge aclk) begin
                if (!aresetn)
                    done_r <= 1'b0;
                else
                    done_r <= m_axis_tvalid & m_axis_tready & m_axis_tlast;
            end

            assign busy  = s_axis_tvalid & ~m_axis_tlast;
            assign done  = done_r;
            assign error = 1'b0;

            assign event_frame_started         = 1'b0;
            assign event_tlast_unexpected      = 1'b0;
            assign event_tlast_missing         = 1'b0;
            assign event_data_in_channel_halt  = 1'b0;
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        // =====================================================================
        // STUB MODE 2 — sequential-output behavioral stub (simulation only)
        //
        // Accepts 256 inputs (s_axis_tvalid, tready=1 always).
        // After 256th input, outputs bins 0..STUB_STOP_AT sequentially.
        // TLAST fired at bin STUB_TLAST_AT (never if STUB_TLAST_AT >= 256).
        // Used for cap_bin_cnt / watchdog / TLAST-mismatch hardening tests.
        // =====================================================================
        end else if (USE_BEHAVIORAL_STUB == 2) begin : gen_seq_stub

            // synthesis translate_off
            initial begin
                $display("[INFO] fft256_xilinx_wrapper: USE_BEHAVIORAL_STUB=2");
                $display("[INFO] Sequential stub: STUB_TLAST_AT=%0d STUB_STOP_AT=%0d",
                         STUB_TLAST_AT, STUB_STOP_AT);
            end
            // synthesis translate_on

            reg [7:0] in_cnt_s2;
            reg [7:0] out_cnt_s2;
            reg       out_active_s2;

            always @(posedge aclk) begin
                if (!aresetn) begin
                    in_cnt_s2    <= 8'd0;
                    out_cnt_s2   <= 8'd0;
                    out_active_s2 <= 1'b0;
                end else if (!out_active_s2) begin
                    // Input phase: count 256 arriving samples
                    if (s_axis_tvalid) begin
                        if (in_cnt_s2 == 8'd255) begin
                            in_cnt_s2    <= 8'd0;
                            out_cnt_s2   <= 8'd0;
                            out_active_s2 <= 1'b1;
                        end else begin
                            in_cnt_s2 <= in_cnt_s2 + 8'd1;
                        end
                    end
                end else begin
                    // Output phase: emit bins 0..STUB_STOP_AT
                    if (out_cnt_s2 == STUB_STOP_AT[7:0]) begin
                        out_active_s2 <= 1'b0;
                    end else begin
                        out_cnt_s2 <= out_cnt_s2 + 8'd1;
                    end
                end
            end

            assign s_axis_tready = 1'b1;
            assign m_axis_tvalid = out_active_s2;
            assign m_axis_tdata  = {(2*FFT_OUT_WIDTH){1'b0}};
            assign m_axis_tuser  = out_cnt_s2;
            assign m_axis_tlast  = out_active_s2 &&
                                   (out_cnt_s2 == STUB_TLAST_AT[7:0]) &&
                                   (STUB_TLAST_AT < 256);

            assign busy  = out_active_s2;
            assign done  = out_active_s2 && (out_cnt_s2 == STUB_STOP_AT[7:0]);
            assign error = 1'b0;

            assign event_frame_started         = 1'b0;
            assign event_tlast_unexpected      = 1'b0;
            assign event_tlast_missing         = 1'b0;
            assign event_data_in_channel_halt  = 1'b0;
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        // =====================================================================
        // BEHAVIORAL DFT MODE — simulation-only exact 256-pt DFT
        //
        // USE_BEHAVIORAL_STUB = 3
        //
        // Computes the actual 256-pt DFT using real arithmetic (no FFT IP).
        // Output is unscaled DFT (same convention as numpy.fft.fft).
        // Max output magnitude for our test stimulus ≈ 24635 — fits in int16.
        // Enables k_int sweep validation under iverilog without Xilinx IP.
        //
        // Packing: {Im[15:0], Re[15:0]} matching Xilinx FFT native format.
        // Bin ordering: natural order 0..FFT_LEN-1 (same as Xilinx IP).
        // m_axis_tuser = bin index (same as xk_index from Xilinx IP).
        //
        // NOT synthesizable.  For simulation validation only.
        // =====================================================================
        end else if (USE_BEHAVIORAL_STUB == 3) begin : gen_behavioral_dft

            // synthesis translate_off
            initial begin
                $display("[INFO] fft256_xilinx_wrapper: USE_BEHAVIORAL_STUB=3 (behavioral DFT)");
                $display("[INFO]   Exact 256-pt DFT, real arithmetic, simulation-only.");
                $display("[INFO]   Enables k_int sweep validation without Xilinx IP.");
            end
            // synthesis translate_on

            localparam [1:0]
                BD_IDLE    = 2'd0,
                BD_FILL    = 2'd1,
                BD_COMPUTE = 2'd2,
                BD_OUTPUT  = 2'd3;

            reg [1:0]               bd_state;
            reg [8:0]               bd_cnt;
            reg [2*IQ_WIDTH-1:0]    bd_ibuf [0:FFT_LEN-1];
            reg [2*FFT_OUT_WIDTH-1:0] bd_obuf [0:FFT_LEN-1];
            reg                     bd_tvalid_r;
            reg [7:0]               bd_tuser_r;
            reg                     bd_tlast_r;
            reg [2*FFT_OUT_WIDTH-1:0] bd_tdata_r;
            reg                     bd_busy_r;
            reg                     bd_done_r;

            assign s_axis_tready = (bd_state == BD_IDLE) || (bd_state == BD_FILL);
            assign m_axis_tvalid = bd_tvalid_r;
            assign m_axis_tdata  = bd_tdata_r;
            assign m_axis_tuser  = bd_tuser_r;
            assign m_axis_tlast  = bd_tlast_r;
            assign busy  = bd_busy_r;
            assign done  = bd_done_r;
            assign error = 1'b0;

            assign event_frame_started         = 1'b0;
            assign event_tlast_unexpected      = 1'b0;
            assign event_tlast_missing         = 1'b0;
            assign event_data_in_channel_halt  = 1'b0;
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

            // synthesis translate_off
            integer    bd_k, bd_n;
            real       bd_re [0:FFT_LEN-1];
            real       bd_im [0:FFT_LEN-1];
            real       bd_Xre, bd_Xim, bd_ang;
            integer    bd_ore, bd_oim;
            // synthesis translate_on

            always @(posedge aclk) begin
                if (!aresetn) begin
                    bd_state    <= BD_IDLE;
                    bd_cnt      <= 9'd0;
                    bd_tvalid_r <= 1'b0;
                    bd_tlast_r  <= 1'b0;
                    bd_tuser_r  <= 8'd0;
                    bd_tdata_r  <= {(2*FFT_OUT_WIDTH){1'b0}};
                    bd_busy_r   <= 1'b0;
                    bd_done_r   <= 1'b0;
                end else begin
                    bd_done_r   <= 1'b0;
                    bd_tvalid_r <= 1'b0;
                    bd_tlast_r  <= 1'b0;

                    case (bd_state)

                        BD_IDLE: begin
                            bd_busy_r <= 1'b0;
                            if (s_axis_tvalid) begin
                                bd_ibuf[0] <= s_axis_tdata;
                                bd_cnt     <= 9'd1;
                                bd_busy_r  <= 1'b1;
                                bd_state   <= BD_FILL;
                            end
                        end

                        BD_FILL: begin
                            if (s_axis_tvalid) begin
                                bd_ibuf[bd_cnt[7:0]] <= s_axis_tdata;
                                if (bd_cnt == 9'd255) begin
                                    bd_cnt   <= 9'd0;
                                    bd_state <= BD_COMPUTE;
                                end else begin
                                    bd_cnt <= bd_cnt + 9'd1;
                                end
                            end
                        end

                        BD_COMPUTE: begin
                            // synthesis translate_off
                            // Compute unscaled 256-pt DFT in one simulation time step.
                            // Real arithmetic: no precision loss, exact integer results.
                            for (bd_n = 0; bd_n < FFT_LEN; bd_n = bd_n + 1) begin
                                bd_re[bd_n] = $itor($signed(bd_ibuf[bd_n][IQ_WIDTH-1:0]));
                                bd_im[bd_n] = $itor($signed(bd_ibuf[bd_n][2*IQ_WIDTH-1:IQ_WIDTH]));
                            end
                            for (bd_k = 0; bd_k < FFT_LEN; bd_k = bd_k + 1) begin
                                bd_Xre = 0.0;
                                bd_Xim = 0.0;
                                for (bd_n = 0; bd_n < FFT_LEN; bd_n = bd_n + 1) begin
                                    bd_ang = -6.283185307179586 * bd_n * bd_k / FFT_LEN;
                                    bd_Xre = bd_Xre + bd_re[bd_n]*$cos(bd_ang) - bd_im[bd_n]*$sin(bd_ang);
                                    bd_Xim = bd_Xim + bd_re[bd_n]*$sin(bd_ang) + bd_im[bd_n]*$cos(bd_ang);
                                end
                                // Clamp to FFT_OUT_WIDTH signed range
                                if (bd_Xre >  32767.5) bd_ore = 32767;
                                else if (bd_Xre < -32768.5) bd_ore = -32768;
                                else bd_ore = $rtoi(bd_Xre);
                                if (bd_Xim >  32767.5) bd_oim = 32767;
                                else if (bd_Xim < -32768.5) bd_oim = -32768;
                                else bd_oim = $rtoi(bd_Xim);
                                // Pack {Im[15:0], Re[15:0]} matching Xilinx convention
                                bd_obuf[bd_k] = {bd_oim[FFT_OUT_WIDTH-1:0],
                                                 bd_ore[FFT_OUT_WIDTH-1:0]};
                            end
                            // synthesis translate_on
                            bd_cnt   <= 9'd0;
                            bd_state <= BD_OUTPUT;
                        end

                        BD_OUTPUT: begin
                            bd_tvalid_r <= 1'b1;
                            bd_tdata_r  <= bd_obuf[bd_cnt[7:0]];
                            bd_tuser_r  <= bd_cnt[7:0];
                            bd_tlast_r  <= (bd_cnt == 9'd255);
                            if (bd_cnt == 9'd255) begin
                                bd_done_r <= 1'b1;
                                bd_cnt    <= 9'd0;
                                bd_state  <= BD_IDLE;
                            end else begin
                                bd_cnt <= bd_cnt + 9'd1;
                            end
                        end

                        default: bd_state <= BD_IDLE;
                    endcase
                end
            end

        // =====================================================================
        // PRODUCTION MODE — actual Xilinx xfft IP
        // =====================================================================
        end else begin : gen_production

            // Config channel wires
            wire        cfg_tready;
            // Drive config continuously after reset; IP latches on handshake
            wire        cfg_tvalid = aresetn;
            wire [15:0] cfg_tdata  = CFG_TDATA;

            // IP data wires
            wire [31:0] ip_m_tdata;
            wire [7:0]  ip_m_tuser;
            wire        ip_m_tvalid;
            wire        ip_m_tlast;
            wire        ip_ev_frame_started;
            wire        ip_ev_tlast_unexpected;
            wire        ip_ev_tlast_missing;
            wire        ip_ev_din_halt;

            fft256_xilinx u_fft (
                .aclk                        (aclk),
                .s_axis_config_tdata         (cfg_tdata),
                .s_axis_config_tvalid        (cfg_tvalid),
                .s_axis_config_tready        (cfg_tready),
                .s_axis_data_tdata           (s_axis_tdata),
                .s_axis_data_tvalid          (s_axis_tvalid),
                .s_axis_data_tready          (s_axis_tready),
                .s_axis_data_tlast           (s_axis_tlast),
                .m_axis_data_tdata           (ip_m_tdata),
                .m_axis_data_tuser           (ip_m_tuser),
                .m_axis_data_tvalid          (ip_m_tvalid),
                .m_axis_data_tlast           (ip_m_tlast),
                .event_frame_started         (ip_ev_frame_started),
                .event_tlast_unexpected      (ip_ev_tlast_unexpected),
                .event_tlast_missing         (ip_ev_tlast_missing),
                .event_data_in_channel_halt  (ip_ev_din_halt)
            );

            assign m_axis_tvalid = ip_m_tvalid;
            assign m_axis_tdata  = ip_m_tdata;
            assign m_axis_tuser  = ip_m_tuser;
            assign m_axis_tlast  = ip_m_tlast;

            // busy: high from first input handshake through last output
            reg frame_active;
            always @(posedge aclk) begin
                if (!aresetn)
                    frame_active <= 1'b0;
                else if (s_axis_tvalid && s_axis_tready)
                    frame_active <= 1'b1;
                else if (ip_m_tvalid && ip_m_tlast)
                    frame_active <= 1'b0;
            end

            assign busy  = frame_active;
            assign done  = ip_m_tvalid & ip_m_tlast;
            assign error = ip_ev_tlast_unexpected | ip_ev_tlast_missing | ip_ev_din_halt;

            assign event_frame_started         = ip_ev_frame_started;
            assign event_tlast_unexpected      = ip_ev_tlast_unexpected;
            assign event_tlast_missing         = ip_ev_tlast_missing;
            assign event_data_in_channel_halt  = ip_ev_din_halt;
            // Not present in realtime-throttle IP boundary; tie low
            assign event_data_out_channel_halt = 1'b0;
            assign event_status_channel_halt   = 1'b0;

        end

    endgenerate

endmodule
