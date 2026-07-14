# p5_04_fulldesign_timing.xdc — full-design (OOC) timing constraints
# Top = phase3_sync_axis_dma_wrapper, port aclk @ 250 MHz (4.0 ns).
#
# This XDC is used only for the P5-04 measurement build (OOC mode).
# In BD-mode HIL builds the clock comes from pl_clk0 inside the BD;
# there create_clock is auto-generated and this XDC is NOT applied.

create_clock -name aclk -period 4.000 [get_ports aclk]

# Conservative I/O delays so the report focuses on internal logic rather
# than artificial I/O paths. Set to <=20% of the clock so internal slack
# dominates.
set_input_delay  -clock aclk -max 0.8 [get_ports {s_axi_* s_axis_* aresetn}]
set_input_delay  -clock aclk -min 0.2 [get_ports {s_axi_* s_axis_* aresetn}]
set_output_delay -clock aclk -max 0.8 [get_ports {s_axi_* m_axis_* dbg_*}]
set_output_delay -clock aclk -min 0.2 [get_ports {s_axi_* m_axis_* dbg_*}]
