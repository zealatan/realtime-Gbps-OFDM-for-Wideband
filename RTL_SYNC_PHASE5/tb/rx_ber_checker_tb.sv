`timescale 1ns/1ps
// Standalone unit TB for rx_ber_checker (ROBUST free-running rewrite): drive N
// frames of golden nibbles (with optional injected errors) and check the
// accumulators. The checker anchors its frame position on the FIRST beat after
// clr and free-runs; rot_off rotates the reference. Here we drive aligned
// (rot_off=0) so the first beat is symbol-0/carrier-0.
module rx_ber_checker_tb;
    localparam integer NDATA_SC = 221;
    localparam integer NUM_DATA = 12;
    localparam integer TOTAL    = NDATA_SC*NUM_DATA; // 2652

    reg aclk=0, aresetn=0;
    reg v=0, r=1, user=0, last=0;
    reg [3:0] d=0;
    reg [3:0] sel=0;
    reg clr=0;
    reg [3:0] rot=0;
    wire [31:0] status;

    // golden ref (same file the DUT loads)
    reg [3:0] ref_rom [0:TOTAL-1];
    initial $readmemh("rtl/rx_ber_ref_rom.hex", ref_rom);

    rx_ber_checker #(.NDATA_SC(NDATA_SC), .NUM_DATA(NUM_DATA),
                     .REF_ROM_FILE("rtl/rx_ber_ref_rom.hex")) dut (
        .aclk(aclk), .aresetn(aresetn),
        .m_bits_tvalid(v), .m_bits_tready(r), .m_bits_tdata(d),
        .m_bits_tuser(user), .m_bits_tlast(last),
        .rot_off(rot),
        .clr(clr), .status_sel(sel), .status_data(status)
    );

    always #5 aclk = ~aclk;

    integer total_inj_err; // bits we deliberately flip in counted frames

    // drive one beat at pos p (sym,car), optionally flip 'flip' bits
    task drive_nib(input integer sym, input integer car, input integer flipbits, input integer counted);
        integer pos; reg [3:0] gold;
        begin
            pos = sym*NDATA_SC + car;
            gold = ref_rom[pos];
            @(negedge aclk);
            v   = 1'b1;
            user= (car==0);
            last= (car==NDATA_SC-1);
            d   = gold ^ flipbits[3:0];
            if (counted) total_inj_err = total_inj_err + (flipbits[0]+flipbits[1]+flipbits[2]+flipbits[3]);
            @(posedge aclk);
            #1;
            v = 1'b0; user=0; last=0; // idle a cycle (tests gap handling)
        end
    endtask

    task drive_frame(input integer flip_one_carrier, input integer counted);
        integer s,c;
        begin
            for (s=0; s<NUM_DATA; s=s+1)
                for (c=0; c<NDATA_SC; c=c+1) begin
                    // inject a 1-bit error at sym3/car7 only when flip_one_carrier set
                    if (flip_one_carrier && s==3 && c==7)
                        drive_nib(s,c,4'b0010,counted);
                    else
                        drive_nib(s,c,4'b0000,counted);
                end
        end
    endtask

    integer rd_err, rd_frames, rd_nib, rd_flags, rd_warm;
    task readstat;
        begin
            sel=4'h0; @(posedge aclk); #1; rd_err   = status;
            sel=4'h1; @(posedge aclk); #1; rd_frames= status;
            sel=4'h2; @(posedge aclk); #1; rd_nib   = status;
            sel=4'h3; @(posedge aclk); #1; rd_flags = status;
            sel=4'h4; @(posedge aclk); #1; rd_warm  = status;
        end
    endtask

    integer fail;
    initial begin
        fail = 0; total_inj_err = 0;
        rot = 4'd0;
        repeat(5) @(posedge aclk);
        aresetn = 1;
        repeat(3) @(posedge aclk);
        // soft-clear so the NEXT beat anchors as frame-pos 0
        clr=1'b1; @(posedge aclk); #1; clr=1'b0;
        repeat(2) @(posedge aclk);

        // Frame 0 = warm-up (not counted; first frame boundary begins counting),
        // frames 1..4 counted. Frame with injected error is a COUNTED frame.
        drive_frame(0,0); // f0 warm-up (not counted)
        drive_frame(0,1); // f1 counted, clean
        drive_frame(1,1); // f2 counted, 1 injected bit error at sym3/car7
        drive_frame(0,1); // f3 counted, clean
        drive_frame(0,1); // f4 counted, clean
        // one more frame's start crosses the boundary that counts f4
        drive_frame(0,1); // f5 -> boundary increments frames_checked for f4

        repeat(5) @(posedge aclk);
        readstat;
        $display("BER_TB: total_bit_errors=%0d (expect %0d)", rd_err, total_inj_err);
        $display("BER_TB: frames_checked=%0d", rd_frames);
        $display("BER_TB: total_nibbles=%0d", rd_nib);
        $display("BER_TB: err_flags=0x%08x (expect 0)", rd_flags);
        $display("BER_TB: warmup word=0x%08x", rd_warm);

        if (rd_err   !== total_inj_err) begin fail=1; $display("BER_TB: FAIL err mismatch"); end
        if (rd_flags !== 32'd0)         begin fail=1; $display("BER_TB: FAIL flags set"); end
        if (rd_frames < 3)              begin fail=1; $display("BER_TB: FAIL too few frames counted"); end
        // total_nibbles counts from the start of the first counted frame to the
        // in-flight frame. Allow frames_checked*TOTAL <= nib <= (frames_checked+2)*TOTAL.
        if (rd_nib < rd_frames*TOTAL || rd_nib > (rd_frames+2)*TOTAL) begin
            fail=1; $display("BER_TB: FAIL nibble count out of range (%0d)", rd_nib);
        end

        if (fail) $display("BER_TB: RESULT FAIL");
        else      $display("BER_TB: RESULT PASS");
        $finish;
    end
endmodule
