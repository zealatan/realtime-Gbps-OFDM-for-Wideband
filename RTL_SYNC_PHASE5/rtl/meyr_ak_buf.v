`timescale 1ns/1ps
// =============================================================
//  meyr_ak_buf.v
//  Purely Pipelined Architecture (No FSM)
// =============================================================
module meyr_ak_buf #(
    parameter MAX_N = 4096 // Defines the absolute maximum FFT size supported
)(
    input  wire        clk,
    input  wire        rst_n,
    
    input  wire [31:0] fft_tdata,
    input  wire        fft_tvalid,
    input  wire        fft_tlast,
    
    output wire [15:0] a_i, 
    output wire [15:0] a_q, 
    output wire [15:0] b_i, 
    output wire [15:0] b_q, 
    output wire        mult_strobe
);

    // --- Dynamic Address Width ---
    reg [$clog2(MAX_N)-1:0] addr_cnt;
    
    // Purely combinational data-routing flag (0 = PSS, 1 = SSS)
    reg is_sss_phase;

    // --- Inferred BRAM ---
    //reg [31:0] bram [0:N-1];
    (* ram_style = "block" *) reg [31:0] bram [0:MAX_N-1];
    integer i;
    initial begin
        for (i=0; i<MAX_N; i=i+1) bram[i] = 32'h0;
    end

    // Pipeline Registers
    reg [31:0] pss_stored;
    reg [31:0] sss_delayed;
    reg        strobe_delayed;
    
    // =========================================================
    // BLOCK 1: Pure Synchronous Memory (Forces BRAM Inference)
    // =========================================================
    always @(posedge clk) begin
        // Write Port
        if (fft_tvalid && !is_sss_phase) begin
            bram[addr_cnt] <= fft_tdata;
        end
        
        // Read Port (Continuous synchronous read)
        pss_stored <= bram[addr_cnt];
    end
    
    // =========================================================
    // BLOCK 2: Control Logic (With Async Reset)
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr_cnt       <= 0;
            is_sss_phase   <= 1'b0;
            sss_delayed    <= 32'h0;
            strobe_delayed <= 1'b0;
        end else begin
            // 1. Counters and Flags
            if (fft_tvalid) begin
                addr_cnt <= (fft_tlast) ? 0 : addr_cnt + 1;
                
                if (fft_tlast) begin
                    is_sss_phase <= ~is_sss_phase; 
                end
            end

            // 2. Data Alignment pipeline
            sss_delayed    <= fft_tdata;
            strobe_delayed <= is_sss_phase & fft_tvalid;
        end
    end

//    always @(posedge clk or negedge rst_n) begin
//        if (!rst_n) begin
//            addr_cnt       <= 0;
//            is_sss_phase   <= 1'b0;
//            pss_stored     <= 32'h0;
//            sss_delayed    <= 32'h0;
//            strobe_delayed <= 1'b0;
//        end else begin
            
//            // 1. Data Path (No FSM overhead)
//            if (fft_tvalid) begin
//                // Write to BRAM only during PSS phase
//                if (!is_sss_phase) begin
//                    bram[addr_cnt] <= fft_tdata;
//                end
                
//                // Continuous pipelined counter
//                addr_cnt <= (fft_tlast) ? 0 : addr_cnt + 1;
                
//                // Toggle phase cleanly when AXI-Stream signals the end of a frame
//                if (fft_tlast) begin
//                    is_sss_phase <= ~is_sss_phase; 
//                end
//            end

//            // 2. Pipelined Data Alignment
//            // The read from BRAM happens continuously. It is only valid during the SSS phase.
//            pss_stored     <= bram[addr_cnt];
//            sss_delayed    <= fft_tdata;
//            strobe_delayed <= is_sss_phase & fft_tvalid;
//        end
//    end

    // 3. Output Assignment (Match C-code: PSS * conj(SSS))
    assign a_i = pss_stored[15:0];
    assign a_q = pss_stored[31:16];
    
    assign b_i = sss_delayed[15:0];
    assign b_q = - $signed(sss_delayed[31:16]); // Conjugate SSS
    
    assign mult_strobe = strobe_delayed;

endmodule