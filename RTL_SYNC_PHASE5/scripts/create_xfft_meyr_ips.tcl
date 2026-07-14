# Regenerate xfft_N / xfft_2N / xfft_IFFT for ZCU102 (xczu9eg), Vivado 2022.2.
# Reuses each existing .xci config (transform_length/width/BFP/etc. — the agent-
# validated 8-bit-config setup); only the target part is retargeted.
set part xczu9eg-ffvb1156-2-e
create_project -in_memory -part $part
set_property target_language Verilog [current_project]

foreach name {xfft_N xfft_2N xfft_IFFT} {
    set hits [glob -nocomplain ip/$name/$name.xci ip/$name.xci $name/$name.xci rtl/$name/$name.xci]
    if {[llength $hits] == 0} {
        puts "ERROR: $name.xci not found under ip/ or rtl/"
        continue
    }
    set xci [lindex $hits 0]
    puts "==> reading $xci"
    read_ip $xci
    catch { upgrade_ip [get_ips $name] }
    reset_target all [get_ips $name]
    generate_target {synthesis simulation} [get_ips $name]
    puts "==> GENERATED $name for $part"
}
puts "DONE: xfft IPs generated for $part"
