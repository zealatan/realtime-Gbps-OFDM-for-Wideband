# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  ipgui::add_param $IPINST -name "ACC_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "BUF_AW" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CORDIC_LATENCY" -parent ${Page_0}
  ipgui::add_param $IPINST -name "CP_LEN" -parent ${Page_0}
  ipgui::add_param $IPINST -name "ENERGY_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "HIT_COUNT" -parent ${Page_0}
  ipgui::add_param $IPINST -name "INDEX_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "IQ_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "METRIC_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NCO_PHASE_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "NSC" -parent ${Page_0}
  ipgui::add_param $IPINST -name "PHASE_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "POWER_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "RESULT_WIDTH" -parent ${Page_0}
  ipgui::add_param $IPINST -name "THRESHOLD" -parent ${Page_0}
  ipgui::add_param $IPINST -name "WINDOW_LEN" -parent ${Page_0}


}

proc update_PARAM_VALUE.ACC_WIDTH { PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to update ACC_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ACC_WIDTH { PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to validate ACC_WIDTH
	return true
}

proc update_PARAM_VALUE.BUF_AW { PARAM_VALUE.BUF_AW } {
	# Procedure called to update BUF_AW when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.BUF_AW { PARAM_VALUE.BUF_AW } {
	# Procedure called to validate BUF_AW
	return true
}

proc update_PARAM_VALUE.CORDIC_LATENCY { PARAM_VALUE.CORDIC_LATENCY } {
	# Procedure called to update CORDIC_LATENCY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CORDIC_LATENCY { PARAM_VALUE.CORDIC_LATENCY } {
	# Procedure called to validate CORDIC_LATENCY
	return true
}

proc update_PARAM_VALUE.CP_LEN { PARAM_VALUE.CP_LEN } {
	# Procedure called to update CP_LEN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.CP_LEN { PARAM_VALUE.CP_LEN } {
	# Procedure called to validate CP_LEN
	return true
}

proc update_PARAM_VALUE.ENERGY_WIDTH { PARAM_VALUE.ENERGY_WIDTH } {
	# Procedure called to update ENERGY_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.ENERGY_WIDTH { PARAM_VALUE.ENERGY_WIDTH } {
	# Procedure called to validate ENERGY_WIDTH
	return true
}

proc update_PARAM_VALUE.HIT_COUNT { PARAM_VALUE.HIT_COUNT } {
	# Procedure called to update HIT_COUNT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.HIT_COUNT { PARAM_VALUE.HIT_COUNT } {
	# Procedure called to validate HIT_COUNT
	return true
}

proc update_PARAM_VALUE.INDEX_WIDTH { PARAM_VALUE.INDEX_WIDTH } {
	# Procedure called to update INDEX_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.INDEX_WIDTH { PARAM_VALUE.INDEX_WIDTH } {
	# Procedure called to validate INDEX_WIDTH
	return true
}

proc update_PARAM_VALUE.IQ_WIDTH { PARAM_VALUE.IQ_WIDTH } {
	# Procedure called to update IQ_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.IQ_WIDTH { PARAM_VALUE.IQ_WIDTH } {
	# Procedure called to validate IQ_WIDTH
	return true
}

proc update_PARAM_VALUE.METRIC_WIDTH { PARAM_VALUE.METRIC_WIDTH } {
	# Procedure called to update METRIC_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.METRIC_WIDTH { PARAM_VALUE.METRIC_WIDTH } {
	# Procedure called to validate METRIC_WIDTH
	return true
}

proc update_PARAM_VALUE.NCO_PHASE_WIDTH { PARAM_VALUE.NCO_PHASE_WIDTH } {
	# Procedure called to update NCO_PHASE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NCO_PHASE_WIDTH { PARAM_VALUE.NCO_PHASE_WIDTH } {
	# Procedure called to validate NCO_PHASE_WIDTH
	return true
}

proc update_PARAM_VALUE.NSC { PARAM_VALUE.NSC } {
	# Procedure called to update NSC when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.NSC { PARAM_VALUE.NSC } {
	# Procedure called to validate NSC
	return true
}

proc update_PARAM_VALUE.PHASE_WIDTH { PARAM_VALUE.PHASE_WIDTH } {
	# Procedure called to update PHASE_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.PHASE_WIDTH { PARAM_VALUE.PHASE_WIDTH } {
	# Procedure called to validate PHASE_WIDTH
	return true
}

proc update_PARAM_VALUE.POWER_WIDTH { PARAM_VALUE.POWER_WIDTH } {
	# Procedure called to update POWER_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.POWER_WIDTH { PARAM_VALUE.POWER_WIDTH } {
	# Procedure called to validate POWER_WIDTH
	return true
}

proc update_PARAM_VALUE.RESULT_WIDTH { PARAM_VALUE.RESULT_WIDTH } {
	# Procedure called to update RESULT_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.RESULT_WIDTH { PARAM_VALUE.RESULT_WIDTH } {
	# Procedure called to validate RESULT_WIDTH
	return true
}

proc update_PARAM_VALUE.THRESHOLD { PARAM_VALUE.THRESHOLD } {
	# Procedure called to update THRESHOLD when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.THRESHOLD { PARAM_VALUE.THRESHOLD } {
	# Procedure called to validate THRESHOLD
	return true
}

proc update_PARAM_VALUE.WINDOW_LEN { PARAM_VALUE.WINDOW_LEN } {
	# Procedure called to update WINDOW_LEN when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.WINDOW_LEN { PARAM_VALUE.WINDOW_LEN } {
	# Procedure called to validate WINDOW_LEN
	return true
}


proc update_MODELPARAM_VALUE.IQ_WIDTH { MODELPARAM_VALUE.IQ_WIDTH PARAM_VALUE.IQ_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.IQ_WIDTH}] ${MODELPARAM_VALUE.IQ_WIDTH}
}

proc update_MODELPARAM_VALUE.NSC { MODELPARAM_VALUE.NSC PARAM_VALUE.NSC } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NSC}] ${MODELPARAM_VALUE.NSC}
}

proc update_MODELPARAM_VALUE.CP_LEN { MODELPARAM_VALUE.CP_LEN PARAM_VALUE.CP_LEN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CP_LEN}] ${MODELPARAM_VALUE.CP_LEN}
}

proc update_MODELPARAM_VALUE.BUF_AW { MODELPARAM_VALUE.BUF_AW PARAM_VALUE.BUF_AW } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.BUF_AW}] ${MODELPARAM_VALUE.BUF_AW}
}

proc update_MODELPARAM_VALUE.ACC_WIDTH { MODELPARAM_VALUE.ACC_WIDTH PARAM_VALUE.ACC_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ACC_WIDTH}] ${MODELPARAM_VALUE.ACC_WIDTH}
}

proc update_MODELPARAM_VALUE.METRIC_WIDTH { MODELPARAM_VALUE.METRIC_WIDTH PARAM_VALUE.METRIC_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.METRIC_WIDTH}] ${MODELPARAM_VALUE.METRIC_WIDTH}
}

proc update_MODELPARAM_VALUE.INDEX_WIDTH { MODELPARAM_VALUE.INDEX_WIDTH PARAM_VALUE.INDEX_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.INDEX_WIDTH}] ${MODELPARAM_VALUE.INDEX_WIDTH}
}

proc update_MODELPARAM_VALUE.RESULT_WIDTH { MODELPARAM_VALUE.RESULT_WIDTH PARAM_VALUE.RESULT_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.RESULT_WIDTH}] ${MODELPARAM_VALUE.RESULT_WIDTH}
}

proc update_MODELPARAM_VALUE.PHASE_WIDTH { MODELPARAM_VALUE.PHASE_WIDTH PARAM_VALUE.PHASE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.PHASE_WIDTH}] ${MODELPARAM_VALUE.PHASE_WIDTH}
}

proc update_MODELPARAM_VALUE.POWER_WIDTH { MODELPARAM_VALUE.POWER_WIDTH PARAM_VALUE.POWER_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.POWER_WIDTH}] ${MODELPARAM_VALUE.POWER_WIDTH}
}

proc update_MODELPARAM_VALUE.ENERGY_WIDTH { MODELPARAM_VALUE.ENERGY_WIDTH PARAM_VALUE.ENERGY_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.ENERGY_WIDTH}] ${MODELPARAM_VALUE.ENERGY_WIDTH}
}

proc update_MODELPARAM_VALUE.WINDOW_LEN { MODELPARAM_VALUE.WINDOW_LEN PARAM_VALUE.WINDOW_LEN } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.WINDOW_LEN}] ${MODELPARAM_VALUE.WINDOW_LEN}
}

proc update_MODELPARAM_VALUE.HIT_COUNT { MODELPARAM_VALUE.HIT_COUNT PARAM_VALUE.HIT_COUNT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.HIT_COUNT}] ${MODELPARAM_VALUE.HIT_COUNT}
}

proc update_MODELPARAM_VALUE.THRESHOLD { MODELPARAM_VALUE.THRESHOLD PARAM_VALUE.THRESHOLD } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.THRESHOLD}] ${MODELPARAM_VALUE.THRESHOLD}
}

proc update_MODELPARAM_VALUE.NCO_PHASE_WIDTH { MODELPARAM_VALUE.NCO_PHASE_WIDTH PARAM_VALUE.NCO_PHASE_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.NCO_PHASE_WIDTH}] ${MODELPARAM_VALUE.NCO_PHASE_WIDTH}
}

proc update_MODELPARAM_VALUE.CORDIC_LATENCY { MODELPARAM_VALUE.CORDIC_LATENCY PARAM_VALUE.CORDIC_LATENCY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.CORDIC_LATENCY}] ${MODELPARAM_VALUE.CORDIC_LATENCY}
}

