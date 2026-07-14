`timescale 1ns/1ps
// =============================================================
//  meyr_Rm_dut.v
//  Datapath: FFT_N Out -> R[m] Out (Using Known-Good Submodules)
// =============================================================
module meyr_Rm_dut #(
    parameter N_LOG2_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  n_log2,

    // Config for internal FFT_2N (xfft v9.1 16-bit runtime config word)
    input  wire [15:0] cfg2N_tdata,
    input  wire        cfg2N_tvalid,
    output wire        cfg2N_tready,

    // Runtime B[k] ROM write port. Writes are expected while the data path is
    // idle, before a new PSS/SSS packet is streamed.
    input  wire        rom_we,
    input  wire [12:0] rom_waddr,
    input  wire [63:0] rom_wdata,

    // Input: Frequency domain stream from FFT_N
    input  wire [31:0] din_tdata,
    input  wire        din_tvalid,
    input  wire        din_tlast,

    // Output: R[m] Cross-Correlation Result
    output wire [63:0] rm_tdata,
    output wire        rm_tvalid,
    output wire        rm_tlast
);

    // =========================================================
    // 1. REUSE YOUR KNOWN-GOOD MODULE (A[k] + Zero Padder)
    // =========================================================
    wire [63:0] pad_tdata;
    wire        pad_tvalid, pad_tlast, pad_tready;

    meyr_FFT_ak_dut #(.N_LOG2_MAX(N_LOG2_MAX)) u_ak_pad (
        .clk(clk), .rst_n(rst_n),
        .n_log2(n_log2),
        .din_tdata(din_tdata), 
        .din_tvalid(din_tvalid), 
        .din_tlast(din_tlast),
        .pad_tdata(pad_tdata), 
        .pad_tvalid(pad_tvalid), 
        .pad_tlast(pad_tlast), 
        .pad_tready(pad_tready)
    );

    // =========================================================
    // 2. SECOND FFT (2N-point BFP)
    // =========================================================
    wire [63:0] fft2n_tdata;
    wire        fft2n_tvalid, fft2n_tlast;

    xfft_2N u_fft_2N (
        .aclk(clk), .aresetn(rst_n),
        // IP's C_S_AXIS_CONFIG_TDATA_WIDTH = 8 (HAS_NFFT=0, BFP).
        .s_axis_config_tvalid(cfg2N_tvalid), .s_axis_config_tready(cfg2N_tready), .s_axis_config_tdata(cfg2N_tdata[7:0]),
        .s_axis_data_tvalid(pad_tvalid), .s_axis_data_tready(pad_tready), .s_axis_data_tdata(pad_tdata), .s_axis_data_tlast(pad_tlast),
        .m_axis_data_tvalid(fft2n_tvalid), .m_axis_data_tready(1'b1), .m_axis_data_tdata(fft2n_tdata), .m_axis_data_tlast(fft2n_tlast),
        .m_axis_status_tready(1'b1)
    );

    // =========================================================
    // 3. B[k] ROM (Synthesizable Inferred BRAM)
    // =========================================================
    localparam FFT_2N_MAX = 1 << (N_LOG2_MAX + 1);

    (* ram_style = "block" *) reg [63:0] rom [0:FFT_2N_MAX-1];

    // ISS-17 fix (2026-06-17): permanent ROM init for synthesis + simulation.
    // The wrapper (phase3_sync_axis_dma_wrapper) does NOT expose rom_we/_waddr/
    // _wdata at its boundary, and phase3_sync_top ties them low. Without this
    // initial $readmemh, the ROM is all-zero in any deployment (HW included)
    // and meyr correlation can never produce a valid CFO estimate. The TB-
    // hierarchical $readmemh patch in p5_d_continuous_wrapper_tb.sv was sim-
    // only. For HW, Vivado synthesis encodes the listed file as the BRAM
    // initialization. The file path is relative; Vivado searches its include
    // paths (the project's vectors/ dir must be a source or in xelab -i).
    initial $readmemh("bk_conj_fft512_rom.txt", rom);

    reg [N_LOG2_MAX:0] rom_addr;
    reg [63:0] rom_q;
    wire [N_LOG2_MAX:0] fft2n_last =
        ({{N_LOG2_MAX{1'b0}}, 1'b1} << (n_log2 + 1'b1)) - 1'b1;

    always @(posedge clk) begin
        if (rom_we) begin
            rom[rom_waddr] <= rom_wdata;
        end
        if (!rst_n) begin
            rom_addr <= 0;
            rom_q    <= 0;
        end else if (fft2n_tvalid) begin
            rom_q <= rom[rom_addr];
            if (fft2n_tlast || rom_addr == fft2n_last) begin
                rom_addr <= 0;
            end else begin
                rom_addr <= rom_addr + 1;
            end
        end
    end

    // =========================================================
    // 4. R[m] MULTIPLIER (32x32 -> 64-bit complex)
    // =========================================================
    reg [63:0] fft2n_d1;
    reg        valid_d1, tlast_d1;

    always @(posedge clk) begin
        if (!rst_n) begin
            fft2n_d1 <= 0; valid_d1 <= 0; tlast_d1 <= 0;
        end else begin
            fft2n_d1 <= fft2n_tdata;
            valid_d1 <= fft2n_tvalid;
            tlast_d1 <= fft2n_tvalid & fft2n_tlast;
        end
    end

    wire signed [63:0] pi_full, pq_full;
    wire               mult_rm_strobe;

    complex_mult_32 u_mult_rm (
        .clock(clk), .enable(1'b1), .rst_n(rst_n),
        .a_i($signed(fft2n_d1[31:0])), .a_q($signed(fft2n_d1[63:32])),
        .b_i($signed(rom_q[31:0])),    .b_q($signed(rom_q[63:32])),
        .input_strobe(valid_d1),
        .p_i(pi_full), .p_q(pq_full),
        .output_strobe(mult_rm_strobe)
    );

    // Normalize: Arithmetic right shift >> 31
    assign rm_tdata  = {pq_full[62:31], pi_full[62:31]};
    assign rm_tvalid = mult_rm_strobe;

    // Align tlast through 3-cycle multiplier pipeline
    reg [2:0] last_pipe;
    always @(posedge clk) begin
        if (!rst_n) last_pipe <= 0;
        else last_pipe <= {last_pipe[1:0], tlast_d1};
    end
    assign rm_tlast = last_pipe[2] & mult_rm_strobe;

endmodule
