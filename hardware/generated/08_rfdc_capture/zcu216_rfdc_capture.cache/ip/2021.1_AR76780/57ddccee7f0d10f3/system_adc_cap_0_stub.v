// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
// Date        : Fri Jun 19 11:14:13 2026
// Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
// Command     : write_verilog -force -mode synth_stub -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_adc_cap_0_stub.v
// Design      : system_adc_cap_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xczu49dr-ffvf1760-2-e
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "zcu216_adc_capture,Vivado 2021.1_AR76780" *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix(aclk, aresetn, ctrl, s_axis_tdata, s_axis_tvalid, 
  s_axis_tready, status0, status1, status2, status3, status_capture)
/* synthesis syn_black_box black_box_pad_pin="aclk,aresetn,ctrl[31:0],s_axis_tdata[127:0],s_axis_tvalid,s_axis_tready,status0[31:0],status1[31:0],status2[31:0],status3[31:0],status_capture[31:0]" */;
  input aclk;
  input aresetn;
  input [31:0]ctrl;
  input [127:0]s_axis_tdata;
  input s_axis_tvalid;
  output s_axis_tready;
  output [31:0]status0;
  output [31:0]status1;
  output [31:0]status2;
  output [31:0]status3;
  output [31:0]status_capture;
endmodule
