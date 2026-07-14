# phase5_register_xfft_ips.tcl
#
# Register the three xfft 9.1 IPs (xfft_N, xfft_2N, xfft_IFFT) into a
# non-project (in-memory) Vivado session and generate simulation sources.
#
# What this script does, and does NOT do:
#   - read_ip  : adds the XCI to the in-memory session.
#   - generate_target {simulation} : emits .vhd / .v sim sources plus the
#     compile_order.tcl that xsim needs.
#   - export_simulation -simulator xsim : optional convenience, emits a
#     ready-to-run xsim project script under sim_out/phase5_xsim/.
#   It does NOT run synthesis / implementation / bitstream.
#
# Target part: ZCU102 / xczu9eg-ffvb1156-2-e is the single source of truth.
#
# Invocation (interactive Vivado prompt or `vivado -mode batch -source ...`):
#   # default uses the locked ZCU102 part:
#   source scripts/phase5_register_xfft_ips.tcl
#   # override only for a CI environment where ZU9 isn't installed:
#   set ::env(XFFT_TARGET_PART) "xczu5ev-sfvc784-2-i"
#   source scripts/phase5_register_xfft_ips.tcl
#
# Output:
#   <repo>/.Xil/ip/xfft_*/                — generated sim sources
#   <repo>/sim_out/phase5_xsim/           — exported xsim project (optional)

set repo_root [pwd]

# Locked target part for PHASE5 (ZCU102). Env override allowed only for
# local Vivado installs that lack ZU9 device support files.
set part "xczu9eg-ffvb1156-2-e"
if {[info exists ::env(XFFT_TARGET_PART)]} { set part $::env(XFFT_TARGET_PART) }

# Fresh in-memory project keeps the XCI bring-up independent of any
# existing Vivado project state in the repo.
create_project -in_memory -part $part xfft_inmem

set xcis [list \
    [file join $repo_root rtl xfft_N    xfft_N.xci] \
    [file join $repo_root rtl xfft_2N   xfft_2N.xci] \
    [file join $repo_root rtl xfft_IFFT xfft_IFFT.xci]]

foreach x $xcis {
    if {![file exists $x]} {
        puts "ERROR: missing XCI: $x"
        exit 1
    }
    puts "Registering IP: $x"
    read_ip $x
}

# Emit simulation sources (BFP behavioral model + IP wrappers).
generate_target {simulation} [get_ips xfft_N xfft_2N xfft_IFFT]

# Optional: emit a ready-to-source xsim project script.
set sim_out [file join $repo_root sim_out phase5_xsim]
file mkdir $sim_out
catch {
    export_simulation -force -simulator xsim -directory $sim_out \
        -of_objects [get_ips xfft_N xfft_2N xfft_IFFT]
}

puts "PHASE5_XFFT_IP_REGISTRATION: OK"
