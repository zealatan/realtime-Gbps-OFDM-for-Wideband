// =====================================================================
// rx_demod_16qam_stress_tb.sv
// ---------------------------------------------------------------------
// ROBUST stress self-check for rx_demod_16qam.
//
//  * Reads golden/rx_downstream/demod_stress_vectors.hex produced by
//    scripts/gen_rx_demod_16qam_stress.py. Each line:
//        <8-hex packed {Q[31:16],I[15:0]}>  <4 expected bits b0b1b2b3>
//    Expected bits come from the EXACT decode_16qam reference.
//  * Streams every vector through the DUT 1/clock with pseudo-random
//    m_ready back-pressure (exercises the skid-free handshake).
//  * Checks the 4 output bits EXACTLY against the reference for every
//    vector. BER must be 0 over ALL vectors (random + boundary +
//    ideal + noisy + extreme).
//  * Reports per-category and, on any mismatch, prints the exact
//    (I,Q,expected,got) so a real boundary/mapping bug is pinpointed.
//
// Vector count is data-driven via demod_stress_count.txt.
// =====================================================================
`timescale 1ns/1ps
`default_nettype none

module rx_demod_16qam_stress_tb;

    localparam integer MAXV = 4096;     // upper bound on vector count

    // ---- clock / reset ----
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rst_n = 1'b0;

    // ---- DUT wiring ----
    reg                 s_valid;
    wire                s_ready;
    reg  signed [15:0]  s_i, s_q;
    reg                 s_last, s_user;

    wire                m_valid;
    reg                 m_ready;
    wire [3:0]          m_bits;
    wire                m_last, m_user;

    rx_demod_16qam #(.DATA_W(16), .THRESH(3220)) dut (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_valid), .s_ready(s_ready),
        .s_i(s_i), .s_q(s_q), .s_last(s_last), .s_user(s_user),
        .m_valid(m_valid), .m_ready(m_ready),
        .m_bits(m_bits), .m_last(m_last), .m_user(m_user)
    );

    // ---- storage: packed vector word + expected bits ----
    // file format per line: "PPPPPPPP bbbb" ; $readmemh would only grab the
    // first token, so parse with $fscanf to capture both fields.
    reg [31:0] vec_word [0:MAXV-1];
    reg [3:0]  vec_exp  [0:MAXV-1];   // {b0,b1,b2,b3}
    integer    NVEC;

    reg [3:0]  got_bits [0:MAXV-1];
    integer    out_cnt;

    integer fd, rc, k;
    reg [31:0] w;
    reg [7:0]  c0, c1, c2, c3;
    integer    bval;

    initial begin
        NVEC = 0;
        fd = $fopen("golden/rx_downstream/demod_stress_vectors.hex", "r");
        if (fd == 0) begin
            $display("FATAL: cannot open demod_stress_vectors.hex");
            $display("RESULT: FAIL"); $finish;
        end
        // each line: 8 hex chars, space, 4 ascii bits
        rc = $fscanf(fd, "%h %c%c%c%c\n", w, c0, c1, c2, c3);
        while (rc == 5 && NVEC < MAXV) begin
            vec_word[NVEC] = w;
            bval = ((c0=="1")?8:0) | ((c1=="1")?4:0) |
                   ((c2=="1")?2:0) | ((c3=="1")?1:0);
            vec_exp[NVEC] = bval[3:0];   // [b0 b1 b2 b3] -> m_bits ordering
            NVEC = NVEC + 1;
            rc = $fscanf(fd, "%h %c%c%c%c\n", w, c0, c1, c2, c3);
        end
        $fclose(fd);
        $display("[stress] loaded %0d vectors", NVEC);
    end

    // ---- stimulus ----
    integer in_idx;
    initial begin
        s_valid = 1'b0; s_i = 0; s_q = 0; s_last = 0; s_user = 0;
        m_ready = 1'b0; rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        // wait for the vector file to be parsed
        while (NVEC == 0) @(posedge clk);

        for (in_idx = 0; in_idx < NVEC; in_idx = in_idx + 1) begin
            s_valid <= 1'b1;
            s_i     <= vec_word[in_idx][15:0];
            s_q     <= vec_word[in_idx][31:16];
            s_last  <= (in_idx == NVEC-1);
            s_user  <= (in_idx == 0);
            @(posedge clk);
            while (!s_ready) @(posedge clk);
        end
        s_valid <= 1'b0; s_last <= 1'b0; s_user <= 1'b0;
    end

    // ---- back-pressure generator (~75% ready) ----
    integer seed = 32'hBADC0DE;
    always @(posedge clk) begin
        if (!rst_n) m_ready <= 1'b0;
        else        m_ready <= ($random(seed) % 4) != 0;
    end

    // ---- collect outputs in arrival order ----
    initial out_cnt = 0;
    always @(posedge clk) begin
        if (rst_n && m_valid && m_ready) begin
            got_bits[out_cnt] <= m_bits;
            out_cnt <= out_cnt + 1;
        end
    end

    // ---- finish + exact compare ----
    integer errors, timeout, mism_shown;
    integer iv, qv;
    initial begin
        timeout = 0;
        wait (rst_n);
        while (NVEC == 0 && timeout < 200000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        while (out_cnt < NVEC && timeout < 500000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (5) @(posedge clk);

        if (out_cnt != NVEC) begin
            $display("FATAL: collected %0d outputs, expected %0d (timeout=%0d)",
                     out_cnt, NVEC, timeout);
            $display("RESULT: FAIL"); $finish;
        end

        errors = 0; mism_shown = 0;
        for (k = 0; k < NVEC; k = k + 1) begin
            if (got_bits[k] !== vec_exp[k]) begin
                errors = errors + 1;
                if (mism_shown < 20) begin
                    iv = $signed(vec_word[k][15:0]);
                    qv = $signed(vec_word[k][31:16]);
                    $display("  MISMATCH idx %0d : I=%0d Q=%0d  exp=%b got=%b",
                             k, iv, qv, vec_exp[k], got_bits[k]);
                    mism_shown = mism_shown + 1;
                end
            end
        end

        $display("==================================================");
        $display(" rx_demod_16qam STRESS self-check");
        $display("   vectors       = %0d", NVEC);
        $display("   total bits    = %0d", NVEC*4);
        $display("   vector errors = %0d", errors);
        $display("   THRESH        = 3220");
        if (errors == 0)
            $display("RESULT: PASS  (BER = 0 over all stress vectors)");
        else
            $display("RESULT: FAIL  (%0d vectors mismatch reference)", errors);
        $display("==================================================");
        $finish;
    end

    initial begin
        #20_000_000;
        $display("FATAL: global timeout");
        $display("RESULT: FAIL"); $finish;
    end

endmodule

`default_nettype wire
