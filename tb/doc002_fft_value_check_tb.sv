`timescale 1ns/1ps
// doc002_fft_value_check_tb — DOC-002 FFT bin-value comparison gate
//
// Runs 3 deterministic test vectors through fft256_xilinx_wrapper
// (USE_BEHAVIORAL_STUB=3, exact 256-pt DFT) and dumps bin outputs to CSV.
// The compare_doc002_fft_values.py script validates against golden references.
//
// Driver timing: s_tdata is updated at posedge+1ns (post-NBA) so the DUT's
// NBA evaluation at the posedge reads the CURRENT sample, not the next one.

module doc002_fft_value_check_tb;

localparam integer FFT_LEN   = 256;
localparam integer IQ_WIDTH  = 16;
localparam integer CLK_HALF  = 5;  // 100 MHz

reg  aclk    = 0;
reg  aresetn = 0;
always #CLK_HALF aclk = ~aclk;

reg                     s_tvalid = 0;
wire                    s_tready;
reg  [2*IQ_WIDTH-1:0]   s_tdata  = 0;
reg                     s_tlast  = 0;

wire                    m_tvalid;
reg                     m_tready = 1;
wire [2*IQ_WIDTH-1:0]   m_tdata;
wire [7:0]              m_tuser;
wire                    m_tlast;
wire                    busy, done, error;

fft256_xilinx_wrapper #(
    .FFT_LEN            (FFT_LEN),
    .IQ_WIDTH           (IQ_WIDTH),
    .FFT_OUT_WIDTH      (IQ_WIDTH),
    .USE_BEHAVIORAL_STUB(3)
) dut (
    .aclk                       (aclk),
    .aresetn                    (aresetn),
    .start                      (1'b0),
    .s_axis_tvalid              (s_tvalid),
    .s_axis_tready              (s_tready),
    .s_axis_tdata               (s_tdata),
    .s_axis_tlast               (s_tlast),
    .m_axis_tvalid              (m_tvalid),
    .m_axis_tready              (m_tready),
    .m_axis_tdata               (m_tdata),
    .m_axis_tuser               (m_tuser),
    .m_axis_tlast               (m_tlast),
    .busy                       (busy),
    .done                       (done),
    .error                      (error),
    .event_frame_started        (),
    .event_tlast_unexpected     (),
    .event_tlast_missing        (),
    .event_data_in_channel_halt (),
    .event_data_out_channel_halt(),
    .event_status_channel_halt  ()
);

reg [31:0] stim_buf  [0:FFT_LEN-1];
reg signed [IQ_WIDTH-1:0] out_re [0:FFT_LEN-1];
reg signed [IQ_WIDTH-1:0] out_im [0:FFT_LEN-1];

task do_reset;
    begin
        aresetn = 0; s_tvalid = 0; s_tlast = 0; s_tdata = 0; m_tready = 1;
        repeat(4) @(posedge aclk);
        @(negedge aclk); aresetn = 1;
        repeat(2) @(posedge aclk);
    end
endtask

// Run one vector.
// AXI-Stream driver: present stim_buf[n] at the posedge, advance data at
// posedge+1ns (post-NBA) so the DUT's NBA evaluation reads the correct sample.
integer n_send, n_recv;
task run_vector;
    integer timeout_cnt;
    begin
        n_send = 0; n_recv = 0;
        timeout_cnt = 0;

        // ── Input phase ──────────────────────────────────────────────────────
        // Pre-load sample 0 before first posedge fire
        #1; s_tdata = stim_buf[0]; s_tlast = 0; s_tvalid = 1;

        while (n_send < FFT_LEN) begin
            @(posedge aclk);           // posedge: DUT NBA reads s_tdata (stim_buf[n_send])
            if (s_tready)
                n_send = n_send + 1;   // note fire; do NOT change s_tdata here
            #1;                        // post-posedge: NBA region complete; safe to advance data
            if (n_send < FFT_LEN) begin
                s_tdata = stim_buf[n_send];
                s_tlast = (n_send == FFT_LEN-1) ? 1'b1 : 1'b0;
            end
        end
        s_tvalid = 0; s_tlast = 0; s_tdata = 0;

        // ── Output phase ─────────────────────────────────────────────────────
        // Collect bins. Read at posedge (pre-NBA): bd_tvalid_r was set at
        // previous cycle's NBA so it's stable for the entire cycle until posedge.
        m_tready = 1;
        while (n_recv < FFT_LEN && timeout_cnt < 10000) begin
            @(posedge aclk);
            timeout_cnt = timeout_cnt + 1;
            if (m_tvalid && m_tready) begin
                out_re[m_tuser] = $signed(m_tdata[IQ_WIDTH-1:0]);
                out_im[m_tuser] = $signed(m_tdata[2*IQ_WIDTH-1:IQ_WIDTH]);
                n_recv = n_recv + 1;
            end
        end
        if (timeout_cnt >= 10000)
            $display("  ERROR: timeout collecting output (n_recv=%0d)", n_recv);
        repeat(4) @(posedge aclk);
    end
endtask

integer fd, k;

task write_output_csv;
    begin
        for (k = 0; k < FFT_LEN; k = k+1)
            $fdisplay(fd, "%0d,%0d,%0d", k, out_re[k], out_im[k]);
    end
endtask

initial begin
    $display("[DOC-002] Running V0: impulse");
    do_reset;
    $readmemh("vectors/doc002/v0_stim.hex", stim_buf);
    run_vector;
    fd = $fopen("sim_out/verification_closure_20260603/doc002_fft_check/v0_output.csv","w");
    if (fd) begin
        $fdisplay(fd, "bin,Re,Im"); write_output_csv; $fclose(fd);
        $display("  Written v0_output.csv (%0d bins)", n_recv);
    end

    $display("[DOC-002] Running V1: tone k0=7");
    do_reset;
    $readmemh("vectors/doc002/v1_stim.hex", stim_buf);
    run_vector;
    fd = $fopen("sim_out/verification_closure_20260603/doc002_fft_check/v1_output.csv","w");
    if (fd) begin
        $fdisplay(fd, "bin,Re,Im"); write_output_csv; $fclose(fd);
        $display("  Written v1_output.csv (%0d bins)", n_recv);
    end

    $display("[DOC-002] Running V2: pseudo-random");
    do_reset;
    $readmemh("vectors/doc002/v2_stim.hex", stim_buf);
    run_vector;
    fd = $fopen("sim_out/verification_closure_20260603/doc002_fft_check/v2_output.csv","w");
    if (fd) begin
        $fdisplay(fd, "bin,Re,Im"); write_output_csv; $fclose(fd);
        $display("  Written v2_output.csv (%0d bins)", n_recv);
    end

    $display("[DOC-002] All vectors complete.");
    $finish;
end

initial begin
    #5_000_000;
    $display("DOC-002 TIMEOUT");
    $finish;
end

endmodule
