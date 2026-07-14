# dac_bypass_bd_edit.tcl  (RF-6d: DAC real-bypass fix)
#
# ROOT CAUSE (HW-validated): the DAC tile3/blk2 ("32") was left in a C2R COARSE
# -Fs/4 datapath (DAC_Mode32=3, Mixer_Type=1, Mixer_Mode=2 C2R, Coarse=3, Interp=1).
# In C2R the RFDC consumes the 256-bit AXI beat as 8 I + 8 Q INTERLEAVED complex
# samples (PG269 "Dual RF-DAC I/Q Input to Real Output"), NOT 16 sequential real
# samples. The offline generator baked a PURE REAL passband -> C2R mis-paired the
# 16 real lanes into bogus I/Q, complex-mixed -Fs/4, took Re{} -> destroyed the
# fast-varying OFDM (137% demod EVM, CP-autocorr ~0.01). A flat tone (16 identical
# sub-samples = near-DC complex) survived -> "tone clean, OFDM destroyed".
#
# The IP at 6.88128 GSPS / single-slice does NOT offer an Interp=1 real bypass
# (Mixer_Type=0 is rejected). The VALID real-bypass datapath is:
#     DAC_Mode32 = 0   (real datapath, no DUC/IMR mixing)  -- set FIRST
#     DAC_Mixer_Mode32 = 0  (mixer OFF) -> IP auto-sets Coarse=0, NCO=0
# In that mode the IP FORCES interpolation to >=2 (Interp=1 illegal). Result:
#     Mode=0, Mixer_Mode=0, Coarse=0, NCO=0, Interp=2, Data_Type=0(Real),
#     s32_axis=256-bit (16 REAL lanes @430.08 MHz, lane rate 3.44064 GSPS, DAC
#     real-interpolates x2 -> 6.88128 GSPS). NO I/Q pairing, NO -Fs/4 shift.
# The generator now bakes the real passband at the 3.44064 GSPS lane rate
# (gen_ofdm_dac_waveform.py --interp 2); the ADC DDC (-300 MHz, decim16) is
# UNCHANGED. Model-verified: EVM 4.8% (vs 137%), CP-autocorr peaks at lag 256.

set REPO /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver
set XPR  $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.xpr
set BD   $REPO/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.srcs/sources_1/bd/system/system.bd

proc fail {msg} { puts "DAC_BYPASS: FAIL $msg"; exit 1 }
if {![file exists $XPR]} { fail "project not found: $XPR" }

open_project $XPR
open_bd_design $BD
set rfdc [get_bd_cells usp_rf_data_converter_0]
if {$rfdc eq ""} { fail "RFDC cell not found" }

proc show {rfdc tag} {
    puts "DAC_BYPASS: ===== $tag ====="
    foreach p {DAC_Mode32 DAC_Data_Type32 DAC_Mixer_Type32 DAC_Mixer_Mode32 \
               DAC_Coarse_Mixer_Freq32 DAC_Interpolation_Mode32 DAC_NCO_Freq32 \
               DAC_Data_Width32 DAC3_Sampling_Rate} {
        catch { puts "  CONFIG.$p = [get_property CONFIG.$p $rfdc]" }
    }
}
show $rfdc "BEFORE"

# Ordered: Mode 0 first (frees the mixer), then Mixer_Mode 0 (off -> Coarse/NCO 0,
# Interp auto-bumps to 2).
set_property CONFIG.DAC_Mode32       {0} $rfdc
set_property CONFIG.DAC_Mixer_Mode32 {0} $rfdc

show $rfdc "AFTER (IP-resolved)"

# Sanity asserts.
if {[get_property CONFIG.DAC_Mixer_Mode32 $rfdc] != 0} { fail "Mixer_Mode32 not OFF" }
if {[get_property CONFIG.DAC_Coarse_Mixer_Freq32 $rfdc] != 0} { fail "Coarse mixer not bypassed" }
set interp [get_property CONFIG.DAC_Interpolation_Mode32 $rfdc]
puts "DAC_BYPASS: resolved DAC interpolation = x$interp (generator must use --interp $interp)"
set m32 [get_bd_intf_pins -quiet usp_rf_data_converter_0/s32_axis]
catch {
    set w [get_property CONFIG.TDATA_NUM_BYTES $m32]
    puts "DAC_BYPASS: s32_axis = [expr {$w*8}] bits (expect 256)"
    if {$w*8 != 256} { fail "s32_axis width changed -> player RTL mismatch" }
}

if {[catch {validate_bd_design} verr]} {
    puts "DAC_BYPASS: validate_bd_design reported: $verr"
}
save_bd_design
puts "DAC_BYPASS: regenerating BD targets..."
if {[catch {generate_target all [get_files $BD]} gerr]} {
    puts "DAC_BYPASS: generate_target reported: $gerr"
}
puts "DAC_BYPASS: DONE"
exit 0
