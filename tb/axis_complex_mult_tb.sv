`timescale 1ns/1ps

module axis_complex_mult_tb;

    localparam int CW       = 16;
    localparam int SHIFT    = 15;
    localparam int CLK_HALF = 5;
    localparam int TIMEOUT  = 100;

    logic        aclk, aresetn;
    logic [31:0] s_axis_a_tdata;
    logic        s_axis_a_tvalid, s_axis_a_tlast;
    wire         s_axis_a_tready;
    logic [31:0] s_axis_b_tdata;
    logic        s_axis_b_tvalid, s_axis_b_tlast;
    wire         s_axis_b_tready;
    wire  [31:0] m_axis_tdata;
    wire         m_axis_tvalid, m_axis_tlast;
    logic        m_axis_tready;

    axis_complex_mult dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axis_a_tdata  (s_axis_a_tdata),
        .s_axis_a_tvalid (s_axis_a_tvalid),
        .s_axis_a_tready (s_axis_a_tready),
        .s_axis_a_tlast  (s_axis_a_tlast),
        .s_axis_b_tdata  (s_axis_b_tdata),
        .s_axis_b_tvalid (s_axis_b_tvalid),
        .s_axis_b_tready (s_axis_b_tready),
        .s_axis_b_tlast  (s_axis_b_tlast),
        .m_axis_tdata    (m_axis_tdata),
        .m_axis_tvalid   (m_axis_tvalid),
        .m_axis_tready   (m_axis_tready),
        .m_axis_tlast    (m_axis_tlast)
    );

    initial aclk = 1'b0;
    always #CLK_HALF aclk = ~aclk;

    // Golden model — mirrors DUT Q1.15 arithmetic exactly
    function automatic [31:0] golden_complex_mult(input [31:0] a, input [31:0] b);
        logic signed [CW-1:0]   ar, ai, br, bi;
        logic signed [2*CW-1:0] prr, pii, pri, pir;
        logic signed [2*CW:0]   fr, fi;
        logic signed [CW-1:0]   or_, oi;
        ar = a[31:16]; ai = a[15:0];
        br = b[31:16]; bi = b[15:0];
        prr = ar * br;  pii = ai * bi;
        pri = ar * bi;  pir = ai * br;
        fr  = {prr[2*CW-1], prr} - {pii[2*CW-1], pii};
        fi  = {pri[2*CW-1], pri} + {pir[2*CW-1], pir};
        or_ = fr[2*CW-2 : SHIFT];
        oi  = fi[2*CW-2 : SHIFT];
        return {or_, oi};
    endfunction

    // Xorshift32 PRNG (period 2^32-1; seed must be non-zero)
    function automatic [31:0] xorshift32(input [31:0] s);
        logic [31:0] x;
        x = s ^ (s << 13);
        x = x ^ (x >> 17);
        x = x ^ (x << 5);
        return x;
    endfunction

    int          pass_cnt, fail_cnt;
    logic [31:0] got_data;
    logic        got_last;

    // T3 vectors — initialized in initial block
    logic [31:0] t3_a [3];
    logic [31:0] t3_b [3];
    logic        t3_al[3];
    logic        t3_bl[3];

    // T5 TLAST matrix (4 last-signal combinations)
    logic        t5_al[4];
    logic        t5_bl[4];

    // T6 negative arithmetic (2 pairs)
    logic [31:0] t6_a [2];
    logic [31:0] t6_b [2];

    // T7 overflow/wrap (2 pairs with large components)
    logic [31:0] t7_a [2];
    logic [31:0] t7_b [2];

    // T11 back-to-back throughput (5 pairs)
    logic [31:0] t11_a [5];
    logic [31:0] t11_b [5];
    logic        t11_al[5];
    logic        t11_bl[5];

    // T12 smoke state
    logic [31:0] prng;
    logic [31:0] t12_a_d, t12_b_d;
    logic        t12_a_l, t12_b_l;
    int          t12_smoke_pass, t12_smoke_fail, t12_bp_count;

    // Drive inputs on negedge; sample output on posedge (after NBA update)
    task automatic send_recv(
        input        [31:0] a_d, input  logic a_l,
        input        [31:0] b_d, input  logic b_l,
        output logic [31:0] gd,  output logic gl
    );
        int t;
        @(negedge aclk);
        s_axis_a_tdata  = a_d; s_axis_a_tlast = a_l; s_axis_a_tvalid = 1;
        s_axis_b_tdata  = b_d; s_axis_b_tlast = b_l; s_axis_b_tvalid = 1;
        m_axis_tready   = 1;
        // Wait for input acceptance; sample output on same posedge (after #1 NBA settles)
        t = 0;
        do begin
            @(posedge aclk); #1;
            if (++t > TIMEOUT)
                $fatal(1, "[FATAL] send_recv: timeout waiting for input acceptance");
        end while (!(s_axis_a_tready && s_axis_a_tvalid));
        // Sample output on posedge (registered result is now stable)
        gd = m_axis_tdata;
        gl = m_axis_tlast;
        if (!m_axis_tvalid)
            $fatal(1, "[FATAL] send_recv: m_axis_tvalid not set after accept");
        // Deassert on negedge
        @(negedge aclk);
        s_axis_a_tvalid = 0; s_axis_b_tvalid = 0; m_axis_tready = 0;
    endtask

    task automatic check_result(
        input string nm,
        input [31:0] gd, input logic gl,
        input [31:0] ed, input logic el
    );
        if (gd === ed && gl === el) begin
            $display("[PASS] %s  data=0x%08h tlast=%b", nm, gd, gl);
            pass_cnt++;
        end else begin
            $display("[FAIL] %s  got=0x%08h/%b  exp=0x%08h/%b", nm, gd, gl, ed, el);
            fail_cnt++;
        end
    endtask

    initial begin
        aresetn         = 1'b0;
        s_axis_a_tdata  = '0; s_axis_a_tvalid = 0; s_axis_a_tlast = 0;
        s_axis_b_tdata  = '0; s_axis_b_tvalid = 0; s_axis_b_tlast = 0;
        m_axis_tready   = 0;
        pass_cnt = 0; fail_cnt = 0;

        // (0.5+0j)*(0.5+0j)=0.25+0j  (0.5+0.5j)*(0.5+0j)=0.25+0.25j  (0.5-1j)*(0.5+0j)=0.25-0.5j
        t3_a  = '{32'h4000_0000, 32'h4000_4000, 32'h4000_8000};
        t3_b  = '{32'h4000_0000, 32'h4000_0000, 32'h4000_0000};
        t3_al = '{1'b0,          1'b1,           1'b0};
        t3_bl = '{1'b0,          1'b0,           1'b1};

        // T5: all four a_last/b_last combinations
        t5_al = '{1'b0, 1'b1, 1'b0, 1'b1};
        t5_bl = '{1'b0, 1'b0, 1'b1, 1'b1};

        // T6: negative arithmetic
        // [0] (-0.5+j0)*(0.5+j0) = -0.25+j0
        // [1] (0.5-0.5j)*(0+0.5j) = 0.25+0.25j
        t6_a  = '{32'hC000_0000, 32'h4000_C000};
        t6_b  = '{32'h4000_0000, 32'h0000_4000};

        // T7: large components that produce overflow/wrap (golden mirrors RTL truncation)
        // [0] (0x7FFF+0x8000j)*(0x7FFF+0x7FFFj): real accumulator overflows Q1.15
        // [1] (0x8000+0x8000j)*(0x8000+0x8000j): imag accumulator overflows, wraps to 0
        t7_a  = '{32'h7FFF_8000, 32'h8000_8000};
        t7_b  = '{32'h7FFF_7FFF, 32'h8000_8000};

        // T11: back-to-back — varied inputs, last beat has a_last=1
        t11_a  = '{32'h4000_0000, 32'h6000_0000, 32'h2000_2000, 32'hC000_4000, 32'h7FFF_0000};
        t11_b  = '{32'h4000_0000, 32'h4000_0000, 32'h6000_C000, 32'h4000_0000, 32'h2000_0000};
        t11_al = '{1'b0, 1'b0, 1'b0, 1'b0, 1'b1};
        t11_bl = '{1'b0, 1'b0, 1'b0, 1'b0, 1'b0};

        // --- T1: reset defaults ---
        repeat(2) @(negedge aclk);
        if (m_axis_tvalid !== 1'b0 || m_axis_tdata !== 32'h0 || m_axis_tlast !== 1'b0) begin
            $display("[FAIL] T1 reset: tvalid=%b tdata=0x%08h tlast=%b",
                     m_axis_tvalid, m_axis_tdata, m_axis_tlast);
            fail_cnt++;
        end else begin
            $display("[PASS] T1 reset: outputs clear during reset");
            pass_cnt++;
        end

        @(negedge aclk); aresetn = 1'b1;

        // --- T2: single A/B pair ---
        send_recv(32'h4000_0000, 1'b0, 32'h4000_0000, 1'b0, got_data, got_last);
        check_result("T2 single pair", got_data, got_last,
                     golden_complex_mult(32'h4000_0000, 32'h4000_0000), 1'b0);

        // --- T3: three fixed golden vectors (expected_tlast = a_last | b_last) ---
        for (int i = 0; i < 3; i++) begin
            send_recv(t3_a[i], t3_al[i], t3_b[i], t3_bl[i], got_data, got_last);
            check_result($sformatf("T3 vec[%0d]", i), got_data, got_last,
                         golden_complex_mult(t3_a[i], t3_b[i]), t3_al[i] | t3_bl[i]);
        end

        // --- T4: real×real arithmetic ---
        send_recv(32'h6000_0000, 1'b0, 32'h4000_0000, 1'b0, got_data, got_last);
        check_result("T4 rr[0] 0.75x0.5", got_data, got_last,
                     golden_complex_mult(32'h6000_0000, 32'h4000_0000), 1'b0);
        send_recv(32'h7FFF_0000, 1'b0, 32'h4000_0000, 1'b0, got_data, got_last);
        check_result("T4 rr[1] maxr x0.5", got_data, got_last,
                     golden_complex_mult(32'h7FFF_0000, 32'h4000_0000), 1'b0);

        // --- T5: TLAST 4-combination matrix (expected_tlast = a_last | b_last) ---
        for (int i = 0; i < 4; i++) begin
            send_recv(32'h4000_0000, t5_al[i], 32'h4000_0000, t5_bl[i], got_data, got_last);
            check_result($sformatf("T5 tlast al=%b bl=%b", t5_al[i], t5_bl[i]),
                         got_data, got_last,
                         golden_complex_mult(32'h4000_0000, 32'h4000_0000),
                         t5_al[i] | t5_bl[i]);
        end

        // --- T6: negative value arithmetic ---
        for (int i = 0; i < 2; i++) begin
            send_recv(t6_a[i], 1'b0, t6_b[i], 1'b0, got_data, got_last);
            check_result($sformatf("T6 neg[%0d]", i), got_data, got_last,
                         golden_complex_mult(t6_a[i], t6_b[i]), 1'b0);
        end

        // --- T7: overflow/wrap/truncation (golden mirrors RTL truncation exactly) ---
        for (int i = 0; i < 2; i++) begin
            send_recv(t7_a[i], 1'b0, t7_b[i], 1'b0, got_data, got_last);
            check_result($sformatf("T7 wrap[%0d]", i), got_data, got_last,
                         golden_complex_mult(t7_a[i], t7_b[i]), 1'b0);
        end

        // --- T8: output backpressure ---
        // Accept one pair with m_ready=1, then stall for 3 cycles with m_ready=0.
        @(negedge aclk);
        s_axis_a_tdata = 32'h4000_0000; s_axis_a_tlast = 0; s_axis_a_tvalid = 1;
        s_axis_b_tdata = 32'h6000_0000; s_axis_b_tlast = 0; s_axis_b_tvalid = 1;
        m_axis_tready  = 1;
        @(posedge aclk); #1;
        if (!m_axis_tvalid) $fatal(1, "[FATAL] T8: no output on first posedge");
        got_data = m_axis_tdata; got_last = m_axis_tlast;
        @(negedge aclk);
        s_axis_a_tvalid = 0; s_axis_b_tvalid = 0; m_axis_tready = 0;
        repeat(3) begin
            @(posedge aclk); #1;
            if (m_axis_tvalid !== 1'b1 || m_axis_tdata !== got_data || m_axis_tlast !== got_last) begin
                $display("[FAIL] T8 stall: tvalid=%b data=0x%08h last=%b (exp 1/0x%08h/%b)",
                         m_axis_tvalid, m_axis_tdata, m_axis_tlast, got_data, got_last);
                fail_cnt++;
            end else begin
                $display("[PASS] T8 stall cycle: tvalid=1 data=0x%08h stable", m_axis_tdata);
                pass_cnt++;
            end
        end
        @(negedge aclk);
        check_result("T8 accepted after stall", m_axis_tdata, m_axis_tlast,
                     golden_complex_mult(32'h4000_0000, 32'h6000_0000), 1'b0);
        m_axis_tready = 1;
        @(posedge aclk); #1;           // drain: m_axis_tvalid goes to 0
        @(negedge aclk); m_axis_tready = 0;

        // --- T9: A-valid-only stall ---
        // Drive A valid, hold B invalid — no pair accepted, no output generated.
        @(negedge aclk);
        s_axis_a_tdata = 32'h4000_0000; s_axis_a_tlast = 0; s_axis_a_tvalid = 1;
        s_axis_b_tvalid = 0; m_axis_tready = 0;
        repeat(3) begin
            @(posedge aclk); #1;
            if (s_axis_a_tready !== 1'b0 || m_axis_tvalid !== 1'b0) begin
                $display("[FAIL] T9 A-only: a_tready=%b m_tvalid=%b (exp 0/0)",
                         s_axis_a_tready, m_axis_tvalid);
                fail_cnt++;
            end else begin
                $display("[PASS] T9 A-only stall: no accept, no output");
                pass_cnt++;
            end
        end
        @(negedge aclk);
        s_axis_b_tdata = 32'h4000_0000; s_axis_b_tlast = 0; s_axis_b_tvalid = 1;
        m_axis_tready  = 1;
        @(posedge aclk); #1;
        if (!m_axis_tvalid) $fatal(1, "[FATAL] T9: no output after B driven");
        check_result("T9 output after B driven", m_axis_tdata, m_axis_tlast,
                     golden_complex_mult(32'h4000_0000, 32'h4000_0000), 1'b0);
        @(negedge aclk); s_axis_a_tvalid = 0; s_axis_b_tvalid = 0; m_axis_tready = 1;
        @(posedge aclk); #1;           // drain
        @(negedge aclk); m_axis_tready = 0;

        // --- T10: B-valid-only stall ---
        // Drive B valid, hold A invalid — no pair accepted, no output generated.
        @(negedge aclk);
        s_axis_b_tdata = 32'h4000_0000; s_axis_b_tlast = 0; s_axis_b_tvalid = 1;
        s_axis_a_tvalid = 0; m_axis_tready = 0;
        repeat(3) begin
            @(posedge aclk); #1;
            if (s_axis_b_tready !== 1'b0 || m_axis_tvalid !== 1'b0) begin
                $display("[FAIL] T10 B-only: b_tready=%b m_tvalid=%b (exp 0/0)",
                         s_axis_b_tready, m_axis_tvalid);
                fail_cnt++;
            end else begin
                $display("[PASS] T10 B-only stall: no accept, no output");
                pass_cnt++;
            end
        end
        @(negedge aclk);
        s_axis_a_tdata = 32'h6000_0000; s_axis_a_tlast = 0; s_axis_a_tvalid = 1;
        m_axis_tready  = 1;
        @(posedge aclk); #1;
        if (!m_axis_tvalid) $fatal(1, "[FATAL] T10: no output after A driven");
        check_result("T10 output after A driven", m_axis_tdata, m_axis_tlast,
                     golden_complex_mult(32'h6000_0000, 32'h4000_0000), 1'b0);
        @(negedge aclk); s_axis_a_tvalid = 0; s_axis_b_tvalid = 0; m_axis_tready = 1;
        @(posedge aclk); #1;           // drain
        @(negedge aclk); m_axis_tready = 0;

        // --- T11: back-to-back throughput (5 pairs, no idle gap, m_ready=1 throughout) ---
        @(negedge aclk);
        m_axis_tready = 1;
        for (int i = 0; i < 5; i++) begin
            s_axis_a_tdata  = t11_a[i]; s_axis_a_tlast = t11_al[i]; s_axis_a_tvalid = 1;
            s_axis_b_tdata  = t11_b[i]; s_axis_b_tlast = t11_bl[i]; s_axis_b_tvalid = 1;
            @(posedge aclk); #1;
            if (!m_axis_tvalid) $fatal(1, "[FATAL] T11 beat[%0d]: no output", i);
            check_result($sformatf("T11 beat[%0d]", i),
                         m_axis_tdata, m_axis_tlast,
                         golden_complex_mult(t11_a[i], t11_b[i]),
                         t11_al[i] | t11_bl[i]);
            if (i < 4) @(negedge aclk);
        end
        @(negedge aclk); s_axis_a_tvalid = 0; s_axis_b_tvalid = 0; m_axis_tready = 0;

        // --- T12: 80-beat deterministic random smoke ---
        // PRNG: xorshift32, seed 0xDEAD_BEEF.
        // Every 8th beat: verify output holds 2 cycles with m_ready=0 (backpressure).
        prng = 32'hDEAD_BEEF;
        t12_smoke_pass = 0; t12_smoke_fail = 0; t12_bp_count = 0;
        for (int beat = 0; beat < 80; beat++) begin
            prng = xorshift32(prng); t12_a_d = prng;
            prng = xorshift32(prng); t12_b_d = prng;
            prng = xorshift32(prng);
            t12_a_l = (prng[3:0] == 4'h0);   // ~1/16 beats carry a_last
            t12_b_l = (prng[7:4] == 4'h0);   // ~1/16 beats carry b_last
            send_recv(t12_a_d, t12_a_l, t12_b_d, t12_b_l, got_data, got_last);
            if (got_data === golden_complex_mult(t12_a_d, t12_b_d) &&
                got_last === (t12_a_l | t12_b_l)) begin
                t12_smoke_pass++;
            end else begin
                $display("[FAIL] T12 beat[%0d]: got=0x%08h/%b  exp=0x%08h/%b",
                         beat, got_data, got_last,
                         golden_complex_mult(t12_a_d, t12_b_d), t12_a_l | t12_b_l);
                t12_smoke_fail++;
            end
            // Backpressure: every 8th beat hold m_ready=0 for 2 extra posedges
            if (beat % 8 == 7) begin
                repeat(2) begin
                    @(posedge aclk); #1;
                    if (m_axis_tvalid !== 1'b1) begin
                        $display("[FAIL] T12 beat[%0d] bp: tvalid dropped during stall", beat);
                        t12_smoke_fail++;
                    end else begin
                        t12_bp_count++;
                    end
                end
            end
            if (beat % 16 == 15)
                $display("[INFO] T12 beat %0d/80: scoreboard=%0d bp_ok=%0d fail=%0d",
                         beat+1, t12_smoke_pass, t12_bp_count, t12_smoke_fail);
        end
        $display("[INFO] T12 final: 80 beats, %0d scoreboard pass, %0d bp stall cycles ok, %0d fail",
                 t12_smoke_pass, t12_bp_count, t12_smoke_fail);
        if (t12_smoke_fail == 0) begin
            $display("[PASS] T12 smoke: 80/80 beats + %0d bp stall cycles verified", t12_bp_count);
            pass_cnt++;
        end else begin
            $display("[FAIL] T12 smoke: %0d failures", t12_smoke_fail);
            fail_cnt++;
        end

        $display("--- %0d PASS  %0d FAIL ---", pass_cnt, fail_cnt);
        if (fail_cnt > 0) $fatal(1, "CI GATE: FAILED");
        $display("CI GATE: PASSED");
        $finish;
    end

endmodule
