`timescale 1ns/1ps


module cordic_arctan_strobe_wrapper_full #(
    parameter integer AVG_W          = 64,
    parameter integer CORDIC_W       = 24,  // must be 24 for your cordic_0 config
    parameter integer HEADROOM_BITS  = 2,
    parameter integer ROUND_EN       = 1
)(
    input  wire                        clock,
    input  wire                        reset,
    input  wire                        enable,

    input  wire signed [AVG_W-1:0]     avg_out_i,
    input  wire signed [AVG_W-1:0]     avg_out_q,
    input  wire                        avg_out_strobe,

    output reg  signed [CORDIC_W-1:0]  phase_cordic,
    output reg                         phase_strobe
);

    // -------- abs with minneg saturation ----------
    function automatic [AVG_W-1:0] abs_sat(input signed [AVG_W-1:0] x);
        reg signed [AVG_W-1:0] neg;
        begin
            if (!x[AVG_W-1]) abs_sat = x;
            else begin
                neg = -x;
                // if x is most-negative, -x == x (overflow) -> saturate
                abs_sat = (neg == x) ? {1'b0, {(AVG_W-1){1'b1}}} : neg[AVG_W-1:0];
            end
        end
    endfunction

    // -------- msb index (0 if x==0) ----------
    function automatic integer msb_index(input [AVG_W-1:0] x);
        integer k;
        begin
            msb_index = 0;
            for (k = AVG_W-1; k >= 0; k = k-1) begin
                if (x[k]) begin
                    msb_index = k;
                    k = -1;
                end
            end
        end
    endfunction

    // -------- saturate to signed CORDIC_W ----------
    function automatic signed [CORDIC_W-1:0] sat_to_cordic(input signed [AVG_W-1:0] x);
        localparam signed [CORDIC_W-1:0] MAXV = {1'b0, {(CORDIC_W-1){1'b1}}};
        localparam signed [CORDIC_W-1:0] MINV = {1'b1, {(CORDIC_W-1){1'b0}}};
        begin
            if (x[AVG_W-1:CORDIC_W] == {(AVG_W-CORDIC_W){x[CORDIC_W-1]}})
                sat_to_cordic = x[CORDIC_W-1:0];
            else
                sat_to_cordic = x[AVG_W-1] ? MINV : MAXV;
        end
    endfunction

    // -------- arithmetic shift with symmetric rounding ----------
    // y = x >>> sh
    // if ROUND_EN:
    //   x>=0: (x + 2^(sh-1)) >>> sh
    //   x< 0: (x + (2^(sh-1)-1)) >>> sh
    function automatic signed [AVG_W-1:0] arshift_round(input signed [AVG_W-1:0] x, input integer sh);
        reg signed [AVG_W-1:0] xb;
        reg signed [AVG_W-1:0] bias;
        begin
            if (sh <= 0) begin
                arshift_round = x;
            end else if (sh >= AVG_W) begin
                arshift_round = {AVG_W{x[AVG_W-1]}};
            end else begin
                if (ROUND_EN != 0) begin
                    bias = (x[AVG_W-1] == 1'b0) ? ({{(AVG_W-1){1'b0}},1'b1} <<< (sh-1))
                                               : (({{(AVG_W-1){1'b0}},1'b1} <<< (sh-1)) - 1);
                    xb = x + bias;
                end else begin
                    xb = x;
                end
                arshift_round = xb >>> sh;
            end
        end
    endfunction

    localparam integer TARGET_MSB = (CORDIC_W - 1 - HEADROOM_BITS); // e.g., 23-2=21

    // normalized I/Q regs and aligned strobe
    reg signed [CORDIC_W-1:0] i_sf_r, q_sf_r;
    reg                       stb_r;

    integer msb;
    integer sh;
    reg [AVG_W-1:0] abs_i, abs_q, max_mag;

    always @(posedge clock) begin
        if (reset) begin
            i_sf_r <= {CORDIC_W{1'b0}};
            q_sf_r <= {CORDIC_W{1'b0}};
            stb_r  <= 1'b0;
        end else if (enable) begin
            stb_r <= avg_out_strobe;

            abs_i   = abs_sat(avg_out_i);
            abs_q   = abs_sat(avg_out_q);
            max_mag = (abs_i >= abs_q) ? abs_i : abs_q;

            msb = msb_index(max_mag);
            sh  = (msb > TARGET_MSB) ? (msb - TARGET_MSB) : 0;

            i_sf_r <= sat_to_cordic( arshift_round(avg_out_i, sh) );
            q_sf_r <= sat_to_cordic( arshift_round(avg_out_q, sh) );
        end else begin
            stb_r <= 1'b0;
        end
    end

    // CORDIC input (exact stub signals)
    wire        s_axis_cartesian_tvalid = stb_r;
    wire [47:0] s_axis_cartesian_tdata  = {q_sf_r, i_sf_r}; // {Y,Q , X,I}

    wire        m_axis_dout_tvalid;
    wire [23:0] m_axis_dout_tdata;

    // Instantiate IP
    cordic_0 u_cordic_0 (
        .aclk                   (clock),
        .s_axis_cartesian_tvalid (s_axis_cartesian_tvalid),
        .s_axis_cartesian_tdata  (s_axis_cartesian_tdata),
        .m_axis_dout_tvalid      (m_axis_dout_tvalid),
        .m_axis_dout_tdata       (m_axis_dout_tdata)
    );

    // Output capture
    always @(posedge clock) begin
        if (reset) begin
            phase_cordic <= {CORDIC_W{1'b0}};
            phase_strobe <= 1'b0;
        end else if (enable) begin
            phase_strobe <= m_axis_dout_tvalid;
            if (m_axis_dout_tvalid) begin
                phase_cordic <= $signed(m_axis_dout_tdata); // IMPORTANT signed cast
            end
        end else begin
            phase_strobe <= 1'b0;
        end
    end

endmodule
