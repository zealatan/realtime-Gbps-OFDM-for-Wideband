set_param project.enableReportConfiguration 0
load_feature core
current_fileset
xsim {dma_ip_tb} -wdb {simulate_xsim_dma_ip_tb.wdb} -autoloadwcfg -tclbatch {sim.tcl} -protoinst {./protoinst_files/sim.protoinst}
