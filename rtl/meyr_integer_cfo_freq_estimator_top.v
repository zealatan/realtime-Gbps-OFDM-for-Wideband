`timescale 1ns/1ps

// Meyr integer CFO frequency-domain estimator top — Step 32
//
// Connects:
//   PSS_FFT / SSS_FFT input stream
//   -> meyr_pss_sss_product_gen  (term1 = PSS * conj(SSS))
//   -> term1 buffer (256 x PROD_WIDTH each I/Q)
//   -> meyr_integer_cfo_core     (511-lag correlation; internal synthetic term2 ROM)
//   -> int_cfo / peak_index / peak_score
//
// meyr_term2_ref_rom is instantiated as an architecture placeholder.
// The core still uses its own identical PRNG ROM internally (Step 31).
// Step 33+ will route meyr_term2_ref_rom to the core when external term2 is wired up.
//
// Protocol:
//   - Pulse start=1; wrapper enters S_RECV; busy asserts.
//   - Stream NSC PSS/SSS sample pairs (s_valid/s_ready handshake; s_index=0..NSC-1).
//   - After NSC term1 products are buffered, wrapper auto-starts the core.
//   - done pulses for 1 clock when complete; busy deasserts.
//   - error is sticky (cleared only by aresetn); set on start-while-busy.

module meyr_integer_cfo_freq_estimator_top #(
    parameter integer NSC         = 256,
    parameter integer IQ_WIDTH    = 16,
    parameter integer PROD_WIDTH  = 32,
    parameter integer ACC_WIDTH   = 56,
    parameter integer SCORE_WIDTH = 64,
    parameter integer INDEX_WIDTH = 9
)(
    input  wire                          aclk,
    input  wire                          aresetn,

    input  wire                          start,

    // PSS_FFT / SSS_FFT input stream (NSC pairs, s_index=0..NSC-1)
    input  wire                          s_valid,
    output wire                          s_ready,
    input  wire [7:0]                    s_index,
    input  wire signed [IQ_WIDTH-1:0]    pss_i,
    input  wire signed [IQ_WIDTH-1:0]    pss_q,
    input  wire signed [IQ_WIDTH-1:0]    sss_i,
    input  wire signed [IQ_WIDTH-1:0]    sss_q,

    output wire                          busy,
    output wire                          done,
    output wire                          error,

    output wire signed [15:0]            int_cfo,
    output wire [INDEX_WIDTH-1:0]        peak_index,
    output wire [SCORE_WIDTH-1:0]        peak_score
);

    // -------------------------------------------------------------------------
    // State encoding
    // -------------------------------------------------------------------------
    localparam [2:0]
        S_IDLE       = 3'd0,
        S_RECV       = 3'd1,
        S_START_CORE = 3'd2,
        S_STREAM     = 3'd3,
        S_WAIT_CORE  = 3'd4,
        S_DONE       = 3'd5;

    reg [2:0] state;

    // -------------------------------------------------------------------------
    // term1 buffer: 256 x PROD_WIDTH I/Q — filled by product_gen, drained to core
    // -------------------------------------------------------------------------
    reg signed [PROD_WIDTH-1:0] term1_buf_i [0:NSC-1];
    reg signed [PROD_WIDTH-1:0] term1_buf_q [0:NSC-1];

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    reg [8:0] recv_cnt;    // inputs accepted (0..NSC)
    reg [8:0] buf_cnt;     // term1 values written to buffer (0..NSC-1 before transition)
    reg [8:0] stream_cnt;  // samples streamed to core (0..NSC-1)

    // -------------------------------------------------------------------------
    // Control / status registers
    // -------------------------------------------------------------------------
    reg busy_r, done_r, error_r;

    assign busy  = busy_r;
    assign done  = done_r;
    assign error = error_r;

    // -------------------------------------------------------------------------
    // Product generator wires
    // -------------------------------------------------------------------------
    wire                         pg_s_ready;
    wire                         pg_m_valid;
    wire [7:0]                   pg_m_index;
    wire signed [PROD_WIDTH-1:0] pg_term1_i;
    wire signed [PROD_WIDTH-1:0] pg_term1_q;

    // Always ready to consume product_gen output when in S_RECV
    wire pg_m_ready = (state == S_RECV);

    // Gate product_gen input: only accept when in S_RECV and haven't yet received NSC inputs
    wire pg_s_valid = s_valid && (state == S_RECV) && (recv_cnt < NSC);

    assign s_ready = (state == S_RECV) && (recv_cnt < NSC) && pg_s_ready;

    meyr_pss_sss_product_gen #(
        .IQ_WIDTH  (IQ_WIDTH),
        .PROD_WIDTH(PROD_WIDTH)
    ) u_prod_gen (
        .aclk    (aclk),
        .aresetn (aresetn),
        .s_valid (pg_s_valid),
        .s_ready (pg_s_ready),
        .s_index (s_index),
        .pss_i   (pss_i),
        .pss_q   (pss_q),
        .sss_i   (sss_i),
        .sss_q   (sss_q),
        .m_valid (pg_m_valid),
        .m_ready (pg_m_ready),
        .m_index (pg_m_index),
        .term1_i (pg_term1_i),
        .term1_q (pg_term1_q)
    );

    // -------------------------------------------------------------------------
    // term2 reference ROM — architecture placeholder for Step 33+
    // The core uses its own identical PRNG ROM internally (Step 31 unchanged).
    // Tie address to stream_cnt so it can be read in parallel with streaming (unused in core).
    // -------------------------------------------------------------------------
    wire signed [PROD_WIDTH-1:0] term2_rom_i_unused;
    wire signed [PROD_WIDTH-1:0] term2_rom_q_unused;

    meyr_term2_ref_rom #(
        .NSC                    (NSC),
        .PROD_WIDTH             (PROD_WIDTH),
        .USE_SYNTHETIC_FALLBACK (1)
    ) u_term2_rom (
        .aclk   (aclk),
        .addr   (stream_cnt[7:0]),
        .term2_i(term2_rom_i_unused),
        .term2_q(term2_rom_q_unused)
    );

    // -------------------------------------------------------------------------
    // Meyr correlation core interface — combinatorial term1 connections
    // (registered in core's S_LOAD state)
    // -------------------------------------------------------------------------
    reg  core_start_r;
    wire core_term1_valid;
    wire core_term1_ready;
    wire signed [15:0]           core_int_cfo;
    wire [INDEX_WIDTH-1:0]       core_peak_index;
    wire [SCORE_WIDTH-1:0]       core_peak_score;
    wire                         core_busy, core_done, core_error;

    // Combinatorial: present current buffer entry directly to core.
    // Core latches when term1_valid && term1_ready (i.e., core state == S_LOAD).
    assign core_term1_valid = (state == S_STREAM);

    meyr_integer_cfo_core #(
        .NSC        (NSC),
        .PROD_WIDTH (PROD_WIDTH),
        .ACC_WIDTH  (ACC_WIDTH),
        .SCORE_WIDTH(SCORE_WIDTH),
        .INDEX_WIDTH(INDEX_WIDTH)
    ) u_core (
        .aclk        (aclk),
        .aresetn     (aresetn),
        .start       (core_start_r),
        .term1_valid (core_term1_valid),
        .term1_index (stream_cnt[7:0]),
        .term1_i     (term1_buf_i[stream_cnt[7:0]]),
        .term1_q     (term1_buf_q[stream_cnt[7:0]]),
        .term1_ready (core_term1_ready),
        .busy        (core_busy),
        .done        (core_done),
        .error       (core_error),
        .int_cfo     (core_int_cfo),
        .peak_index  (core_peak_index),
        .peak_score  (core_peak_score)
    );

    // -------------------------------------------------------------------------
    // Output registers
    // -------------------------------------------------------------------------
    reg signed [15:0]      int_cfo_r;
    reg [INDEX_WIDTH-1:0]  peak_index_r;
    reg [SCORE_WIDTH-1:0]  peak_score_r;

    assign int_cfo    = int_cfo_r;
    assign peak_index = peak_index_r;
    assign peak_score = peak_score_r;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            state        <= S_IDLE;
            busy_r       <= 1'b0;
            done_r       <= 1'b0;
            error_r      <= 1'b0;
            recv_cnt     <= 9'd0;
            buf_cnt      <= 9'd0;
            stream_cnt   <= 9'd0;
            core_start_r <= 1'b0;
            int_cfo_r    <= 16'sd0;
            peak_index_r <= {INDEX_WIDTH{1'b0}};
            peak_score_r <= {SCORE_WIDTH{1'b0}};
        end else begin
            // Default one-cycle pulses
            done_r       <= 1'b0;
            core_start_r <= 1'b0;

            // start-while-busy guard
            if (start && busy_r)
                error_r <= 1'b1;

            // Propagate core error
            if (core_error)
                error_r <= 1'b1;

            case (state)

                // -------------------------------------------------------
                S_IDLE: begin
                    if (start && !busy_r) begin
                        busy_r     <= 1'b1;
                        recv_cnt   <= 9'd0;
                        buf_cnt    <= 9'd0;
                        stream_cnt <= 9'd0;
                        state      <= S_RECV;
                    end
                end

                // -------------------------------------------------------
                // Collect PSS/SSS pairs through product_gen into term1_buf.
                // pg_m_valid fires 1 cycle after each accepted input.
                // Transition when the NSCth term1 value has been written.
                // -------------------------------------------------------
                S_RECV: begin
                    // Count accepted inputs
                    if (pg_s_valid && pg_s_ready)
                        recv_cnt <= recv_cnt + 9'd1;

                    // Buffer product_gen outputs
                    if (pg_m_valid) begin
                        term1_buf_i[pg_m_index] <= pg_term1_i;
                        term1_buf_q[pg_m_index] <= pg_term1_q;
                        if (buf_cnt == NSC - 1) begin
                            state <= S_START_CORE;
                        end else begin
                            buf_cnt <= buf_cnt + 9'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                // Pulse core.start; core enters S_LOAD on next clock.
                // -------------------------------------------------------
                S_START_CORE: begin
                    core_start_r <= 1'b1;
                    stream_cnt   <= 9'd0;
                    state        <= S_STREAM;
                end

                // -------------------------------------------------------
                // Stream term1_buf to core combinatorially.
                // Advance stream_cnt each cycle the core is ready.
                // -------------------------------------------------------
                S_STREAM: begin
                    if (core_term1_ready) begin
                        if (stream_cnt == NSC - 1) begin
                            state <= S_WAIT_CORE;
                        end else begin
                            stream_cnt <= stream_cnt + 9'd1;
                        end
                    end
                end

                // -------------------------------------------------------
                S_WAIT_CORE: begin
                    if (core_done) begin
                        int_cfo_r    <= core_int_cfo;
                        peak_index_r <= core_peak_index;
                        peak_score_r <= core_peak_score;
                        state        <= S_DONE;
                    end
                end

                // -------------------------------------------------------
                S_DONE: begin
                    done_r <= 1'b1;
                    busy_r <= 1'b0;
                    state  <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
