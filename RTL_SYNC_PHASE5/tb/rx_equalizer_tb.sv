// =====================================================================
// rx_equalizer_tb.sv — AXI-Stream wrapper TB with random backpressure
// ---------------------------------------------------------------------
// Drives the full 12x256 golden through the AXI-Stream equalizer while
// randomly de-asserting m_axis_tready (backpressure) and randomly
// gapping s_axis_*_tvalid. Proves: (1) no samples dropped, (2) output
// matches eq_out.hex on the 221 dataIndx carriers, (3) order preserved.
//
// GATE OUTPUT: GATE_RX_EQ_AXIS_UNIT: PASS|FAIL
// =====================================================================
`timescale 1ns/1ps

module rx_equalizer_tb;
    localparam integer NSYM=12, NBIN=256, NDATA=221, TUSERW=16, ERR_TOL=3;

    reg [31:0] fft_mem [0:NSYM*NBIN-1];
    reg [31:0] hest_mem[0:NSYM*NBIN-1];
    reg [31:0] eq_mem  [0:NSYM*NDATA-1];
    integer    data_indx[0:NDATA-1];
    reg        is_data [0:NBIN-1];
    integer    data_pos[0:NBIN-1];

    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    // s_axis
    reg         rx_tvalid, h_tvalid;
    wire        rx_tready, h_tready;
    reg [31:0]  rx_tdata, h_tdata;
    reg [TUSERW-1:0] rx_tuser;
    // m_axis
    wire        m_tvalid;
    reg         m_tready;
    wire [31:0] m_tdata;
    wire [TUSERW-1:0] m_tuser;

    rx_equalizer #(.LUT_FILE("golden_lut/rx_equalizer_recip_lut.hex")) dut (
        .clk(clk), .rst_n(rst_n),
        .s_axis_rx_tvalid(rx_tvalid), .s_axis_rx_tready(rx_tready),
        .s_axis_rx_tdata(rx_tdata),   .s_axis_rx_tuser(rx_tuser),
        .s_axis_h_tvalid(h_tvalid),   .s_axis_h_tready(h_tready),
        .s_axis_h_tdata(h_tdata),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tdata(m_tdata),   .m_axis_tuser(m_tuser)
    );

    function signed [15:0] sx16; input [15:0] v; sx16=$signed(v); endfunction

    integer fd, idx, n, bin;
    initial begin
        $readmemh("golden_in/fft_out.hex", fft_mem);
        $readmemh("golden_in/hest.hex",    hest_mem);
        $readmemh("golden_in/eq_out.hex",  eq_mem);
        for (bin=0;bin<NBIN;bin=bin+1) begin is_data[bin]=0; data_pos[bin]=-1; end
        fd=$fopen("golden_in/data_indx_lines.txt","r");
        n=0;
        while(!$feof(fd) && n<NDATA) if($fscanf(fd,"%d\n",idx)==1) begin
            data_indx[n]=idx; is_data[idx]=1; data_pos[idx]=n; n=n+1; end
        $fclose(fd);
    end

    // ---- driver: walk linear index, present RX & H, gap tvalid randomly ----
    integer di;
    reg [31:0] lfsr_in;
    initial begin
        rx_tvalid=0; h_tvalid=0; rx_tdata=0; h_tdata=0; rx_tuser=0;
        lfsr_in=32'hACE12345;
        rst_n=0; repeat(8) @(posedge clk); rst_n=1; @(posedge clk);
        di=0;
        while (di < NSYM*NBIN) begin
            // random stall: present invalid sometimes
            @(negedge clk);
            if (lfsr_in[3:0]==4'h0) begin
                rx_tvalid<=0; h_tvalid<=0;
            end else begin
                rx_tvalid<=1; h_tvalid<=1;
                rx_tdata <= fft_mem[di];
                h_tdata  <= hest_mem[di];
                rx_tuser <= di;
            end
            @(posedge clk);
            // advance only on a real handshake
            if (rx_tvalid && rx_tready) di=di+1;
            lfsr_in = {lfsr_in[30:0], lfsr_in[31]^lfsr_in[21]^lfsr_in[1]^lfsr_in[0]};
        end
        @(negedge clk); rx_tvalid<=0; h_tvalid<=0;
    end

    // ---- backpressure on m_axis ----
    reg [31:0] lfsr_out;
    initial begin
        m_tready=0; lfsr_out=32'h1357BD9F;
        @(posedge rst_n);
        forever begin
            @(negedge clk);
            m_tready <= (lfsr_out[2:0]!=3'b000);   // ~7/8 ready, random gaps
            lfsr_out = {lfsr_out[30:0], lfsr_out[31]^lfsr_out[21]^lfsr_out[1]^lfsr_out[0]};
        end
    end

    // ---- scoreboard: outputs must arrive in linear order ----
    integer exp_idx, checked, errcnt, recv;
    integer o_sym, o_bin, worst;
    reg signed [15:0] gi, gq, ei, eq_;
    initial begin exp_idx=0; checked=0; errcnt=0; recv=0; worst=0; end

    always @(posedge clk) begin
        if (rst_n && m_tvalid && m_tready) begin
            // order check via tuser
            if (m_tuser !== exp_idx[TUSERW-1:0]) begin
                if (errcnt<20) $display("  ORDER ERR got tuser=%0d exp=%0d", m_tuser, exp_idx);
                errcnt=errcnt+1;
            end
            o_sym = m_tuser / NBIN; o_bin = m_tuser % NBIN;
            if (is_data[o_bin]) begin
                gi = sx16(eq_mem[o_sym*NDATA+data_pos[o_bin]][15:0]);
                gq = sx16(eq_mem[o_sym*NDATA+data_pos[o_bin]][31:16]);
                ei = sx16(m_tdata[15:0]); eq_ = sx16(m_tdata[31:16]);
                checked=checked+1;
                if ((ei-gi)>worst) worst=ei-gi; if ((gi-ei)>worst) worst=gi-ei;
                if ((eq_-gq)>worst) worst=eq_-gq; if ((gq-eq_)>worst) worst=gq-eq_;
                if (((ei-gi)>ERR_TOL)||((gi-ei)>ERR_TOL)||((eq_-gq)>ERR_TOL)||((gq-eq_)>ERR_TOL)) begin
                    if (errcnt<20) $display("  MISMATCH sym=%0d bin=%0d got=(%0d,%0d) exp=(%0d,%0d)",
                                            o_sym,o_bin,ei,eq_,gi,gq);
                    errcnt=errcnt+1;
                end
            end
            exp_idx = exp_idx+1;
            recv=recv+1;
        end
    end

    // ---- end / verdict ----
    initial begin
        wait (rst_n);
        wait (exp_idx == NSYM*NBIN);
        repeat(20) @(posedge clk);
        $display("----------------------------------------------------------");
        $display("[rx_eq_axis] received %0d (exp %0d), checked %0d data carriers, worst |err|=%0d (tol %0d)",
                 recv, NSYM*NBIN, checked, worst, ERR_TOL);
        if (recv != NSYM*NBIN)       $display("GATE_RX_EQ_AXIS_UNIT: FAIL (lost samples: %0d/%0d)", recv, NSYM*NBIN);
        else if (checked != NSYM*NDATA) $display("GATE_RX_EQ_AXIS_UNIT: FAIL (checked %0d != %0d)", checked, NSYM*NDATA);
        else if (errcnt != 0)        $display("GATE_RX_EQ_AXIS_UNIT: FAIL (%0d errors)", errcnt);
        else                         $display("GATE_RX_EQ_AXIS_UNIT: PASS");
        $finish;
    end

    initial begin #5000000; $display("GATE_RX_EQ_AXIS_UNIT: FAIL (timeout)"); $finish; end
endmodule
