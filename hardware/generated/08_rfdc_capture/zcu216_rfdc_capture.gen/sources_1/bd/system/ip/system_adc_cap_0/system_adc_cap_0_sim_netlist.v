// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
// Date        : Fri Jun 19 11:14:14 2026
// Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
// Command     : write_verilog -force -mode funcsim
//               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_adc_cap_0/system_adc_cap_0_sim_netlist.v
// Design      : system_adc_cap_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xczu49dr-ffvf1760-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "system_adc_cap_0,zcu216_adc_capture,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "zcu216_adc_capture,Vivado 2021.1_AR76780" *) 
(* NotValidForBitStream *)
module system_adc_cap_0
   (aclk,
    aresetn,
    ctrl,
    s_axis_tdata,
    s_axis_tvalid,
    s_axis_tready,
    status0,
    status1,
    status2,
    status3,
    status_capture);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 307200000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_adc2, INSERT_VIP 0" *) input aclk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input aresetn;
  input [31:0]ctrl;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TDATA" *) input [127:0]s_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TVALID" *) input s_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 s_axis TREADY" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 16, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 307200000, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_adc2, LAYERED_METADATA undef, INSERT_VIP 0" *) output s_axis_tready;
  output [31:0]status0;
  output [31:0]status1;
  output [31:0]status2;
  output [31:0]status3;
  output [31:0]status_capture;

  wire \<const0> ;
  wire aclk;
  wire aresetn;
  wire [31:0]ctrl;
  wire [127:0]s_axis_tdata;
  wire s_axis_tready;
  wire s_axis_tvalid;
  wire [31:0]\^status0 ;
  wire [31:0]status1;
  wire [31:0]status2;
  wire [31:0]status3;
  wire [15:0]\^status_capture ;

  assign status0[31] = \^status0 [31];
  assign status0[30] = s_axis_tready;
  assign status0[29:26] = \^status0 [29:26];
  assign status0[25] = \<const0> ;
  assign status0[24] = \<const0> ;
  assign status0[23] = \<const0> ;
  assign status0[22] = \<const0> ;
  assign status0[21] = \<const0> ;
  assign status0[20] = \<const0> ;
  assign status0[19] = \<const0> ;
  assign status0[18] = \<const0> ;
  assign status0[17] = \<const0> ;
  assign status0[16] = \<const0> ;
  assign status0[15:0] = \^status0 [15:0];
  assign status_capture[31] = \^status_capture [15];
  assign status_capture[30] = \^status_capture [15];
  assign status_capture[29] = \^status_capture [15];
  assign status_capture[28] = \^status_capture [15];
  assign status_capture[27] = \^status_capture [15];
  assign status_capture[26] = \^status_capture [15];
  assign status_capture[25] = \^status_capture [15];
  assign status_capture[24] = \^status_capture [15];
  assign status_capture[23] = \^status_capture [15];
  assign status_capture[22] = \^status_capture [15];
  assign status_capture[21] = \^status_capture [15];
  assign status_capture[20] = \^status_capture [15];
  assign status_capture[19] = \^status_capture [15];
  assign status_capture[18] = \^status_capture [15];
  assign status_capture[17] = \^status_capture [15];
  assign status_capture[16] = \^status_capture [15];
  assign status_capture[15:0] = \^status_capture [15:0];
  GND GND
       (.G(\<const0> ));
  system_adc_cap_0_zcu216_adc_capture inst
       (.O15(\^status0 [15:0]),
        .aclk(aclk),
        .active_reg_0(s_axis_tready),
        .aresetn(aresetn),
        .ctrl(ctrl),
        .s_axis_tdata(s_axis_tdata[15:0]),
        .s_axis_tvalid(s_axis_tvalid),
        .status0({\^status0 [31],\^status0 [29:26]}),
        .status1(status1),
        .status2(status2),
        .status3(status3),
        .status_capture(\^status_capture ));
endmodule

(* ORIG_REF_NAME = "zcu216_adc_capture" *) 
module system_adc_cap_0_zcu216_adc_capture
   (active_reg_0,
    status_capture,
    status1,
    status3,
    O15,
    status2,
    status0,
    s_axis_tvalid,
    aclk,
    s_axis_tdata,
    ctrl,
    aresetn);
  output active_reg_0;
  output [15:0]status_capture;
  output [31:0]status1;
  output [31:0]status3;
  output [15:0]O15;
  output [31:0]status2;
  output [4:0]status0;
  input s_axis_tvalid;
  input aclk;
  input [15:0]s_axis_tdata;
  input [31:0]ctrl;
  input aresetn;

  wire [15:0]O15;
  wire [15:1]abs16_return;
  wire aclk;
  wire active_i_2_n_0;
  wire active_i_3_n_0;
  wire active_i_4_n_0;
  wire active_i_5_n_0;
  wire active_i_6_n_0;
  wire active_i_7_n_0;
  wire active_i_8_n_0;
  wire active_i_9_n_0;
  wire active_reg_0;
  wire aresetn;
  wire cap_en_d;
  wire clipping_i_1_n_0;
  wire clipping_i_2_n_0;
  wire clipping_i_3_n_0;
  wire clipping_i_4_n_0;
  wire clipping_i_5_n_0;
  wire clipping_i_6_n_0;
  wire clipping_i_7_n_0;
  wire count;
  wire \count[7]_i_2_n_0 ;
  wire [31:16]count_reg;
  wire \count_reg[15]_i_2_n_0 ;
  wire \count_reg[15]_i_2_n_1 ;
  wire \count_reg[15]_i_2_n_10 ;
  wire \count_reg[15]_i_2_n_11 ;
  wire \count_reg[15]_i_2_n_12 ;
  wire \count_reg[15]_i_2_n_13 ;
  wire \count_reg[15]_i_2_n_14 ;
  wire \count_reg[15]_i_2_n_15 ;
  wire \count_reg[15]_i_2_n_2 ;
  wire \count_reg[15]_i_2_n_3 ;
  wire \count_reg[15]_i_2_n_4 ;
  wire \count_reg[15]_i_2_n_5 ;
  wire \count_reg[15]_i_2_n_6 ;
  wire \count_reg[15]_i_2_n_7 ;
  wire \count_reg[15]_i_2_n_8 ;
  wire \count_reg[15]_i_2_n_9 ;
  wire \count_reg[16]_i_1_n_0 ;
  wire \count_reg[16]_i_1_n_1 ;
  wire \count_reg[16]_i_1_n_10 ;
  wire \count_reg[16]_i_1_n_11 ;
  wire \count_reg[16]_i_1_n_12 ;
  wire \count_reg[16]_i_1_n_13 ;
  wire \count_reg[16]_i_1_n_14 ;
  wire \count_reg[16]_i_1_n_15 ;
  wire \count_reg[16]_i_1_n_2 ;
  wire \count_reg[16]_i_1_n_3 ;
  wire \count_reg[16]_i_1_n_4 ;
  wire \count_reg[16]_i_1_n_5 ;
  wire \count_reg[16]_i_1_n_6 ;
  wire \count_reg[16]_i_1_n_7 ;
  wire \count_reg[16]_i_1_n_8 ;
  wire \count_reg[16]_i_1_n_9 ;
  wire \count_reg[24]_i_1_n_1 ;
  wire \count_reg[24]_i_1_n_10 ;
  wire \count_reg[24]_i_1_n_11 ;
  wire \count_reg[24]_i_1_n_12 ;
  wire \count_reg[24]_i_1_n_13 ;
  wire \count_reg[24]_i_1_n_14 ;
  wire \count_reg[24]_i_1_n_15 ;
  wire \count_reg[24]_i_1_n_2 ;
  wire \count_reg[24]_i_1_n_3 ;
  wire \count_reg[24]_i_1_n_4 ;
  wire \count_reg[24]_i_1_n_5 ;
  wire \count_reg[24]_i_1_n_6 ;
  wire \count_reg[24]_i_1_n_7 ;
  wire \count_reg[24]_i_1_n_8 ;
  wire \count_reg[24]_i_1_n_9 ;
  wire \count_reg[7]_i_1_n_0 ;
  wire \count_reg[7]_i_1_n_1 ;
  wire \count_reg[7]_i_1_n_10 ;
  wire \count_reg[7]_i_1_n_11 ;
  wire \count_reg[7]_i_1_n_12 ;
  wire \count_reg[7]_i_1_n_13 ;
  wire \count_reg[7]_i_1_n_14 ;
  wire \count_reg[7]_i_1_n_15 ;
  wire \count_reg[7]_i_1_n_2 ;
  wire \count_reg[7]_i_1_n_3 ;
  wire \count_reg[7]_i_1_n_4 ;
  wire \count_reg[7]_i_1_n_5 ;
  wire \count_reg[7]_i_1_n_6 ;
  wire \count_reg[7]_i_1_n_7 ;
  wire \count_reg[7]_i_1_n_8 ;
  wire \count_reg[7]_i_1_n_9 ;
  wire [31:0]ctrl;
  (* async_reg = "true" *) wire [31:0]ctrl_meta;
  (* async_reg = "true" *) wire [31:0]ctrl_sync;
  wire done_i_2_n_0;
  wire done_i_3_n_0;
  wire \first_sample[15]_i_1_n_0 ;
  wire \first_sample[15]_i_2_n_0 ;
  wire \first_sample[15]_i_3_n_0 ;
  wire \first_sample[15]_i_4_n_0 ;
  wire \first_sample[15]_i_5_n_0 ;
  wire \first_sample[15]_i_6_n_0 ;
  wire \first_sample[15]_i_7_n_0 ;
  wire last_sign;
  wire last_sign_0;
  wire last_sign_valid;
  wire last_sign_valid_reg_n_0;
  wire max_abs;
  wire max_abs0_carry_i_10_n_0;
  wire max_abs0_carry_i_11_n_0;
  wire max_abs0_carry_i_12_n_0;
  wire max_abs0_carry_i_13_n_0;
  wire max_abs0_carry_i_14_n_0;
  wire max_abs0_carry_i_15_n_0;
  wire max_abs0_carry_i_16_n_0;
  wire max_abs0_carry_i_17_n_0;
  wire max_abs0_carry_i_18_n_0;
  wire max_abs0_carry_i_1_n_0;
  wire max_abs0_carry_i_2_n_0;
  wire max_abs0_carry_i_3_n_0;
  wire max_abs0_carry_i_4_n_0;
  wire max_abs0_carry_i_5_n_0;
  wire max_abs0_carry_i_6_n_0;
  wire max_abs0_carry_i_7_n_0;
  wire max_abs0_carry_i_8_n_0;
  wire max_abs0_carry_i_9_n_0;
  wire max_abs0_carry_n_0;
  wire max_abs0_carry_n_1;
  wire max_abs0_carry_n_2;
  wire max_abs0_carry_n_3;
  wire max_abs0_carry_n_4;
  wire max_abs0_carry_n_5;
  wire max_abs0_carry_n_6;
  wire max_abs0_carry_n_7;
  wire \max_abs[13]_i_2_n_0 ;
  wire \max_abs[5]_i_2_n_0 ;
  wire \max_abs[7]_i_2_n_0 ;
  wire max_sample0_carry_i_10_n_0;
  wire max_sample0_carry_i_11_n_0;
  wire max_sample0_carry_i_12_n_0;
  wire max_sample0_carry_i_13_n_0;
  wire max_sample0_carry_i_14_n_0;
  wire max_sample0_carry_i_15_n_0;
  wire max_sample0_carry_i_16_n_0;
  wire max_sample0_carry_i_1_n_0;
  wire max_sample0_carry_i_2_n_0;
  wire max_sample0_carry_i_3_n_0;
  wire max_sample0_carry_i_4_n_0;
  wire max_sample0_carry_i_5_n_0;
  wire max_sample0_carry_i_6_n_0;
  wire max_sample0_carry_i_7_n_0;
  wire max_sample0_carry_i_8_n_0;
  wire max_sample0_carry_i_9_n_0;
  wire max_sample0_carry_n_0;
  wire max_sample0_carry_n_1;
  wire max_sample0_carry_n_2;
  wire max_sample0_carry_n_3;
  wire max_sample0_carry_n_4;
  wire max_sample0_carry_n_5;
  wire max_sample0_carry_n_6;
  wire max_sample0_carry_n_7;
  wire \max_sample[15]_i_1_n_0 ;
  wire mem_reg_bram_0_i_1_n_0;
  wire mem_reg_bram_0_i_2_n_0;
  wire mem_reg_bram_0_n_0;
  wire mem_reg_bram_0_n_1;
  wire mem_reg_bram_0_n_139;
  wire mem_reg_bram_0_n_60;
  wire mem_reg_bram_0_n_61;
  wire mem_reg_bram_0_n_62;
  wire mem_reg_bram_0_n_63;
  wire mem_reg_bram_0_n_64;
  wire mem_reg_bram_0_n_65;
  wire mem_reg_bram_0_n_66;
  wire mem_reg_bram_0_n_67;
  wire mem_reg_bram_1_i_1_n_0;
  wire mem_reg_bram_1_i_2_n_0;
  wire mem_reg_bram_1_i_3_n_0;
  wire mem_reg_bram_3_i_1_n_0;
  wire min_sample;
  wire min_sample0_carry_i_10_n_0;
  wire min_sample0_carry_i_11_n_0;
  wire min_sample0_carry_i_12_n_0;
  wire min_sample0_carry_i_13_n_0;
  wire min_sample0_carry_i_14_n_0;
  wire min_sample0_carry_i_15_n_0;
  wire min_sample0_carry_i_16_n_0;
  wire min_sample0_carry_i_1_n_0;
  wire min_sample0_carry_i_2_n_0;
  wire min_sample0_carry_i_3_n_0;
  wire min_sample0_carry_i_4_n_0;
  wire min_sample0_carry_i_5_n_0;
  wire min_sample0_carry_i_6_n_0;
  wire min_sample0_carry_i_7_n_0;
  wire min_sample0_carry_i_8_n_0;
  wire min_sample0_carry_i_9_n_0;
  wire min_sample0_carry_n_0;
  wire min_sample0_carry_n_1;
  wire min_sample0_carry_n_2;
  wire min_sample0_carry_n_3;
  wire min_sample0_carry_n_4;
  wire min_sample0_carry_n_5;
  wire min_sample0_carry_n_6;
  wire min_sample0_carry_n_7;
  wire overflow_i_10_n_0;
  wire overflow_i_11_n_0;
  wire overflow_i_12_n_0;
  wire overflow_i_13_n_0;
  wire overflow_i_14_n_0;
  wire overflow_i_15_n_0;
  wire overflow_i_16_n_0;
  wire overflow_i_17_n_0;
  wire overflow_i_1_n_0;
  wire overflow_i_3_n_0;
  wire overflow_i_4_n_0;
  wire overflow_i_5_n_0;
  wire overflow_i_6_n_0;
  wire overflow_i_7_n_0;
  wire overflow_i_8_n_0;
  wire overflow_i_9_n_0;
  wire p_0_in;
  wire [12:0]p_0_in__0;
  wire [15:0]s_axis_tdata;
  wire s_axis_tvalid;
  wire saw_nonzero_i_1_n_0;
  wire saw_nonzero_i_2_n_0;
  wire saw_sign_change;
  wire saw_sign_change_i_1_n_0;
  wire \sign_changes[31]_i_1_n_0 ;
  wire \sign_changes[7]_i_2_n_0 ;
  wire \sign_changes_reg[15]_i_1_n_0 ;
  wire \sign_changes_reg[15]_i_1_n_1 ;
  wire \sign_changes_reg[15]_i_1_n_10 ;
  wire \sign_changes_reg[15]_i_1_n_11 ;
  wire \sign_changes_reg[15]_i_1_n_12 ;
  wire \sign_changes_reg[15]_i_1_n_13 ;
  wire \sign_changes_reg[15]_i_1_n_14 ;
  wire \sign_changes_reg[15]_i_1_n_15 ;
  wire \sign_changes_reg[15]_i_1_n_2 ;
  wire \sign_changes_reg[15]_i_1_n_3 ;
  wire \sign_changes_reg[15]_i_1_n_4 ;
  wire \sign_changes_reg[15]_i_1_n_5 ;
  wire \sign_changes_reg[15]_i_1_n_6 ;
  wire \sign_changes_reg[15]_i_1_n_7 ;
  wire \sign_changes_reg[15]_i_1_n_8 ;
  wire \sign_changes_reg[15]_i_1_n_9 ;
  wire \sign_changes_reg[23]_i_1_n_0 ;
  wire \sign_changes_reg[23]_i_1_n_1 ;
  wire \sign_changes_reg[23]_i_1_n_10 ;
  wire \sign_changes_reg[23]_i_1_n_11 ;
  wire \sign_changes_reg[23]_i_1_n_12 ;
  wire \sign_changes_reg[23]_i_1_n_13 ;
  wire \sign_changes_reg[23]_i_1_n_14 ;
  wire \sign_changes_reg[23]_i_1_n_15 ;
  wire \sign_changes_reg[23]_i_1_n_2 ;
  wire \sign_changes_reg[23]_i_1_n_3 ;
  wire \sign_changes_reg[23]_i_1_n_4 ;
  wire \sign_changes_reg[23]_i_1_n_5 ;
  wire \sign_changes_reg[23]_i_1_n_6 ;
  wire \sign_changes_reg[23]_i_1_n_7 ;
  wire \sign_changes_reg[23]_i_1_n_8 ;
  wire \sign_changes_reg[23]_i_1_n_9 ;
  wire \sign_changes_reg[31]_i_2_n_1 ;
  wire \sign_changes_reg[31]_i_2_n_10 ;
  wire \sign_changes_reg[31]_i_2_n_11 ;
  wire \sign_changes_reg[31]_i_2_n_12 ;
  wire \sign_changes_reg[31]_i_2_n_13 ;
  wire \sign_changes_reg[31]_i_2_n_14 ;
  wire \sign_changes_reg[31]_i_2_n_15 ;
  wire \sign_changes_reg[31]_i_2_n_2 ;
  wire \sign_changes_reg[31]_i_2_n_3 ;
  wire \sign_changes_reg[31]_i_2_n_4 ;
  wire \sign_changes_reg[31]_i_2_n_5 ;
  wire \sign_changes_reg[31]_i_2_n_6 ;
  wire \sign_changes_reg[31]_i_2_n_7 ;
  wire \sign_changes_reg[31]_i_2_n_8 ;
  wire \sign_changes_reg[31]_i_2_n_9 ;
  wire \sign_changes_reg[7]_i_1_n_0 ;
  wire \sign_changes_reg[7]_i_1_n_1 ;
  wire \sign_changes_reg[7]_i_1_n_10 ;
  wire \sign_changes_reg[7]_i_1_n_11 ;
  wire \sign_changes_reg[7]_i_1_n_12 ;
  wire \sign_changes_reg[7]_i_1_n_13 ;
  wire \sign_changes_reg[7]_i_1_n_14 ;
  wire \sign_changes_reg[7]_i_1_n_15 ;
  wire \sign_changes_reg[7]_i_1_n_2 ;
  wire \sign_changes_reg[7]_i_1_n_3 ;
  wire \sign_changes_reg[7]_i_1_n_4 ;
  wire \sign_changes_reg[7]_i_1_n_5 ;
  wire \sign_changes_reg[7]_i_1_n_6 ;
  wire \sign_changes_reg[7]_i_1_n_7 ;
  wire \sign_changes_reg[7]_i_1_n_8 ;
  wire \sign_changes_reg[7]_i_1_n_9 ;
  wire start;
  wire [4:0]status0;
  wire [31:0]status1;
  wire [31:0]status2;
  wire [31:0]status3;
  wire [15:0]status_capture;
  wire wr_addr0_carry__0_n_5;
  wire wr_addr0_carry__0_n_6;
  wire wr_addr0_carry__0_n_7;
  wire wr_addr0_carry_n_0;
  wire wr_addr0_carry_n_1;
  wire wr_addr0_carry_n_2;
  wire wr_addr0_carry_n_3;
  wire wr_addr0_carry_n_4;
  wire wr_addr0_carry_n_5;
  wire wr_addr0_carry_n_6;
  wire wr_addr0_carry_n_7;
  wire \wr_addr[12]_i_2_n_0 ;
  wire \wr_addr[12]_i_3_n_0 ;
  wire \wr_addr[12]_i_4_n_0 ;
  wire \wr_addr[12]_i_5_n_0 ;
  wire [12:0]wr_addr_reg;
  wire wr_full;
  wire wr_full2;
  wire wr_full_i_1_n_0;
  wire [7:7]\NLW_count_reg[24]_i_1_CO_UNCONNECTED ;
  wire [7:0]NLW_max_abs0_carry_O_UNCONNECTED;
  wire [7:0]NLW_max_sample0_carry_O_UNCONNECTED;
  wire NLW_mem_reg_bram_0_DBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_0_SBITERR_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_0_CASDOUTA_UNCONNECTED;
  wire [31:8]NLW_mem_reg_bram_0_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_0_CASDOUTPA_UNCONNECTED;
  wire [3:1]NLW_mem_reg_bram_0_CASDOUTPB_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_0_DOUTADOUT_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_0_DOUTBDOUT_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_0_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_0_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_mem_reg_bram_0_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_mem_reg_bram_0_RDADDRECC_UNCONNECTED;
  wire NLW_mem_reg_bram_1_CASOUTDBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_1_CASOUTSBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_1_DBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_1_SBITERR_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_1_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_1_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_1_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_1_CASDOUTPB_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_1_DOUTADOUT_UNCONNECTED;
  wire [31:8]NLW_mem_reg_bram_1_DOUTBDOUT_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_1_DOUTPADOUTP_UNCONNECTED;
  wire [3:1]NLW_mem_reg_bram_1_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_mem_reg_bram_1_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_mem_reg_bram_1_RDADDRECC_UNCONNECTED;
  wire NLW_mem_reg_bram_2_CASOUTDBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_2_CASOUTSBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_2_DBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_2_SBITERR_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_2_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_2_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_2_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_2_CASDOUTPB_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_2_DOUTADOUT_UNCONNECTED;
  wire [31:4]NLW_mem_reg_bram_2_DOUTBDOUT_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_2_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_2_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_mem_reg_bram_2_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_mem_reg_bram_2_RDADDRECC_UNCONNECTED;
  wire NLW_mem_reg_bram_3_CASOUTDBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_3_CASOUTSBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_3_DBITERR_UNCONNECTED;
  wire NLW_mem_reg_bram_3_SBITERR_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_3_CASDOUTA_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_3_CASDOUTB_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_3_CASDOUTPA_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_3_CASDOUTPB_UNCONNECTED;
  wire [31:0]NLW_mem_reg_bram_3_DOUTADOUT_UNCONNECTED;
  wire [31:3]NLW_mem_reg_bram_3_DOUTBDOUT_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_3_DOUTPADOUTP_UNCONNECTED;
  wire [3:0]NLW_mem_reg_bram_3_DOUTPBDOUTP_UNCONNECTED;
  wire [7:0]NLW_mem_reg_bram_3_ECCPARITY_UNCONNECTED;
  wire [8:0]NLW_mem_reg_bram_3_RDADDRECC_UNCONNECTED;
  wire [7:0]NLW_min_sample0_carry_O_UNCONNECTED;
  wire [7:7]\NLW_sign_changes_reg[31]_i_2_CO_UNCONNECTED ;
  wire [7:3]NLW_wr_addr0_carry__0_CO_UNCONNECTED;
  wire [7:4]NLW_wr_addr0_carry__0_O_UNCONNECTED;

  LUT1 #(
    .INIT(2'h1)) 
    active_i_1
       (.I0(aresetn),
        .O(p_0_in));
  LUT6 #(
    .INIT(64'hC4CCCCCC44444444)) 
    active_i_2
       (.I0(cap_en_d),
        .I1(ctrl_sync[1]),
        .I2(active_i_3_n_0),
        .I3(active_i_4_n_0),
        .I4(active_i_5_n_0),
        .I5(active_reg_0),
        .O(active_i_2_n_0));
  LUT6 #(
    .INIT(64'hFFFFFFFFBFFFFFFF)) 
    active_i_3
       (.I0(active_i_6_n_0),
        .I1(O15[4]),
        .I2(O15[3]),
        .I3(O15[6]),
        .I4(O15[5]),
        .I5(active_i_7_n_0),
        .O(active_i_3_n_0));
  LUT2 #(
    .INIT(4'h8)) 
    active_i_4
       (.I0(active_i_8_n_0),
        .I1(active_i_9_n_0),
        .O(active_i_4_n_0));
  (* SOFT_HLUTNM = "soft_lutpair6" *) 
  LUT4 #(
    .INIT(16'h4000)) 
    active_i_5
       (.I0(count_reg[16]),
        .I1(active_reg_0),
        .I2(s_axis_tvalid),
        .I3(done_i_3_n_0),
        .O(active_i_5_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    active_i_6
       (.I0(O15[8]),
        .I1(O15[7]),
        .I2(O15[10]),
        .I3(O15[9]),
        .O(active_i_6_n_0));
  LUT5 #(
    .INIT(32'h7FFFFFFF)) 
    active_i_7
       (.I0(O15[0]),
        .I1(O15[11]),
        .I2(O15[12]),
        .I3(O15[2]),
        .I4(O15[1]),
        .O(active_i_7_n_0));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    active_i_8
       (.I0(count_reg[19]),
        .I1(count_reg[20]),
        .I2(count_reg[17]),
        .I3(count_reg[18]),
        .I4(count_reg[22]),
        .I5(count_reg[21]),
        .O(active_i_8_n_0));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    active_i_9
       (.I0(count_reg[25]),
        .I1(count_reg[26]),
        .I2(count_reg[23]),
        .I3(count_reg[24]),
        .I4(count_reg[28]),
        .I5(count_reg[27]),
        .O(active_i_9_n_0));
  FDRE #(
    .INIT(1'b0)) 
    active_reg
       (.C(aclk),
        .CE(1'b1),
        .D(active_i_2_n_0),
        .Q(active_reg_0),
        .R(p_0_in));
  FDRE #(
    .INIT(1'b0)) 
    cap_en_d_reg
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_sync[1]),
        .Q(cap_en_d),
        .R(p_0_in));
  LUT6 #(
    .INIT(64'hFFFFFFFFC8CC8888)) 
    clipping_i_1
       (.I0(clipping_i_2_n_0),
        .I1(last_sign_0),
        .I2(clipping_i_3_n_0),
        .I3(clipping_i_4_n_0),
        .I4(clipping_i_5_n_0),
        .I5(status0[0]),
        .O(clipping_i_1_n_0));
  LUT6 #(
    .INIT(64'h8000000000000000)) 
    clipping_i_2
       (.I0(clipping_i_6_n_0),
        .I1(clipping_i_7_n_0),
        .I2(s_axis_tdata[12]),
        .I3(s_axis_tdata[13]),
        .I4(s_axis_tdata[10]),
        .I5(s_axis_tdata[11]),
        .O(clipping_i_2_n_0));
  (* SOFT_HLUTNM = "soft_lutpair1" *) 
  LUT2 #(
    .INIT(4'h7)) 
    clipping_i_3
       (.I0(s_axis_tdata[8]),
        .I1(s_axis_tdata[9]),
        .O(clipping_i_3_n_0));
  (* SOFT_HLUTNM = "soft_lutpair3" *) 
  LUT3 #(
    .INIT(8'hFE)) 
    clipping_i_4
       (.I0(s_axis_tdata[6]),
        .I1(\max_abs[7]_i_2_n_0 ),
        .I2(s_axis_tdata[7]),
        .O(clipping_i_4_n_0));
  LUT6 #(
    .INIT(64'h0000000100000000)) 
    clipping_i_5
       (.I0(s_axis_tdata[12]),
        .I1(s_axis_tdata[13]),
        .I2(s_axis_tdata[10]),
        .I3(s_axis_tdata[11]),
        .I4(s_axis_tdata[14]),
        .I5(s_axis_tdata[15]),
        .O(clipping_i_5_n_0));
  (* SOFT_HLUTNM = "soft_lutpair12" *) 
  LUT2 #(
    .INIT(4'hE)) 
    clipping_i_6
       (.I0(s_axis_tdata[8]),
        .I1(s_axis_tdata[9]),
        .O(clipping_i_6_n_0));
  (* SOFT_HLUTNM = "soft_lutpair5" *) 
  LUT2 #(
    .INIT(4'h2)) 
    clipping_i_7
       (.I0(s_axis_tdata[14]),
        .I1(s_axis_tdata[15]),
        .O(clipping_i_7_n_0));
  FDRE #(
    .INIT(1'b0)) 
    clipping_reg
       (.C(aclk),
        .CE(1'b1),
        .D(clipping_i_1_n_0),
        .Q(status0[0]),
        .R(last_sign_valid));
  LUT4 #(
    .INIT(16'h8000)) 
    \count[15]_i_1 
       (.I0(overflow_i_4_n_0),
        .I1(ctrl_sync[1]),
        .I2(active_reg_0),
        .I3(s_axis_tvalid),
        .O(count));
  LUT1 #(
    .INIT(2'h1)) 
    \count[7]_i_2 
       (.I0(O15[0]),
        .O(\count[7]_i_2_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[0] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_15 ),
        .Q(O15[0]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[10] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_13 ),
        .Q(O15[10]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[11] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_12 ),
        .Q(O15[11]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[12] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_11 ),
        .Q(O15[12]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[13] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_10 ),
        .Q(O15[13]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[14] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_9 ),
        .Q(O15[14]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[15] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_8 ),
        .Q(O15[15]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \count_reg[15]_i_2 
       (.CI(\count_reg[7]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\count_reg[15]_i_2_n_0 ,\count_reg[15]_i_2_n_1 ,\count_reg[15]_i_2_n_2 ,\count_reg[15]_i_2_n_3 ,\count_reg[15]_i_2_n_4 ,\count_reg[15]_i_2_n_5 ,\count_reg[15]_i_2_n_6 ,\count_reg[15]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg[15]_i_2_n_8 ,\count_reg[15]_i_2_n_9 ,\count_reg[15]_i_2_n_10 ,\count_reg[15]_i_2_n_11 ,\count_reg[15]_i_2_n_12 ,\count_reg[15]_i_2_n_13 ,\count_reg[15]_i_2_n_14 ,\count_reg[15]_i_2_n_15 }),
        .S(O15[15:8]));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[16] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_15 ),
        .Q(count_reg[16]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \count_reg[16]_i_1 
       (.CI(\count_reg[15]_i_2_n_0 ),
        .CI_TOP(1'b0),
        .CO({\count_reg[16]_i_1_n_0 ,\count_reg[16]_i_1_n_1 ,\count_reg[16]_i_1_n_2 ,\count_reg[16]_i_1_n_3 ,\count_reg[16]_i_1_n_4 ,\count_reg[16]_i_1_n_5 ,\count_reg[16]_i_1_n_6 ,\count_reg[16]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg[16]_i_1_n_8 ,\count_reg[16]_i_1_n_9 ,\count_reg[16]_i_1_n_10 ,\count_reg[16]_i_1_n_11 ,\count_reg[16]_i_1_n_12 ,\count_reg[16]_i_1_n_13 ,\count_reg[16]_i_1_n_14 ,\count_reg[16]_i_1_n_15 }),
        .S(count_reg[23:16]));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[17] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_14 ),
        .Q(count_reg[17]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[18] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_13 ),
        .Q(count_reg[18]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[19] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_12 ),
        .Q(count_reg[19]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[1] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_14 ),
        .Q(O15[1]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[20] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_11 ),
        .Q(count_reg[20]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[21] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_10 ),
        .Q(count_reg[21]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[22] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_9 ),
        .Q(count_reg[22]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[23] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[16]_i_1_n_8 ),
        .Q(count_reg[23]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[24] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_15 ),
        .Q(count_reg[24]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \count_reg[24]_i_1 
       (.CI(\count_reg[16]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_count_reg[24]_i_1_CO_UNCONNECTED [7],\count_reg[24]_i_1_n_1 ,\count_reg[24]_i_1_n_2 ,\count_reg[24]_i_1_n_3 ,\count_reg[24]_i_1_n_4 ,\count_reg[24]_i_1_n_5 ,\count_reg[24]_i_1_n_6 ,\count_reg[24]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\count_reg[24]_i_1_n_8 ,\count_reg[24]_i_1_n_9 ,\count_reg[24]_i_1_n_10 ,\count_reg[24]_i_1_n_11 ,\count_reg[24]_i_1_n_12 ,\count_reg[24]_i_1_n_13 ,\count_reg[24]_i_1_n_14 ,\count_reg[24]_i_1_n_15 }),
        .S(count_reg[31:24]));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[25] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_14 ),
        .Q(count_reg[25]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[26] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_13 ),
        .Q(count_reg[26]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[27] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_12 ),
        .Q(count_reg[27]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[28] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_11 ),
        .Q(count_reg[28]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[29] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_10 ),
        .Q(count_reg[29]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[2] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_13 ),
        .Q(O15[2]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[30] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_9 ),
        .Q(count_reg[30]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[31] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[24]_i_1_n_8 ),
        .Q(count_reg[31]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[3] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_12 ),
        .Q(O15[3]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[4] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_11 ),
        .Q(O15[4]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[5] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_10 ),
        .Q(O15[5]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[6] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_9 ),
        .Q(O15[6]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[7] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[7]_i_1_n_8 ),
        .Q(O15[7]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \count_reg[7]_i_1 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\count_reg[7]_i_1_n_0 ,\count_reg[7]_i_1_n_1 ,\count_reg[7]_i_1_n_2 ,\count_reg[7]_i_1_n_3 ,\count_reg[7]_i_1_n_4 ,\count_reg[7]_i_1_n_5 ,\count_reg[7]_i_1_n_6 ,\count_reg[7]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\count_reg[7]_i_1_n_8 ,\count_reg[7]_i_1_n_9 ,\count_reg[7]_i_1_n_10 ,\count_reg[7]_i_1_n_11 ,\count_reg[7]_i_1_n_12 ,\count_reg[7]_i_1_n_13 ,\count_reg[7]_i_1_n_14 ,\count_reg[7]_i_1_n_15 }),
        .S({O15[7:1],\count[7]_i_2_n_0 }));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[8] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_15 ),
        .Q(O15[8]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \count_reg[9] 
       (.C(aclk),
        .CE(count),
        .D(\count_reg[15]_i_2_n_14 ),
        .Q(O15[9]),
        .R(last_sign_valid));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[0] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[0]),
        .Q(ctrl_meta[0]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[10] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[10]),
        .Q(ctrl_meta[10]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[11] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[11]),
        .Q(ctrl_meta[11]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[12] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[12]),
        .Q(ctrl_meta[12]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[13] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[13]),
        .Q(ctrl_meta[13]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[14] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[14]),
        .Q(ctrl_meta[14]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[15] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[15]),
        .Q(ctrl_meta[15]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[16] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[16]),
        .Q(ctrl_meta[16]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[17] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[17]),
        .Q(ctrl_meta[17]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[18] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[18]),
        .Q(ctrl_meta[18]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[19] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[19]),
        .Q(ctrl_meta[19]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[1] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[1]),
        .Q(ctrl_meta[1]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[20] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[20]),
        .Q(ctrl_meta[20]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[21] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[21]),
        .Q(ctrl_meta[21]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[22] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[22]),
        .Q(ctrl_meta[22]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[23] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[23]),
        .Q(ctrl_meta[23]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[24] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[24]),
        .Q(ctrl_meta[24]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[25] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[25]),
        .Q(ctrl_meta[25]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[26] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[26]),
        .Q(ctrl_meta[26]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[27] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[27]),
        .Q(ctrl_meta[27]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[28] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[28]),
        .Q(ctrl_meta[28]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[29] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[29]),
        .Q(ctrl_meta[29]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[2] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[2]),
        .Q(ctrl_meta[2]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[30] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[30]),
        .Q(ctrl_meta[30]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[31] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[31]),
        .Q(ctrl_meta[31]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[3] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[3]),
        .Q(ctrl_meta[3]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[4] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[4]),
        .Q(ctrl_meta[4]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[5] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[5]),
        .Q(ctrl_meta[5]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[6] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[6]),
        .Q(ctrl_meta[6]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[7] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[7]),
        .Q(ctrl_meta[7]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[8] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[8]),
        .Q(ctrl_meta[8]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[9] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[9]),
        .Q(ctrl_meta[9]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[0] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[0]),
        .Q(ctrl_sync[0]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[10] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[10]),
        .Q(ctrl_sync[10]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[11] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[11]),
        .Q(ctrl_sync[11]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[12] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[12]),
        .Q(ctrl_sync[12]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[13] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[13]),
        .Q(ctrl_sync[13]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[14] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[14]),
        .Q(ctrl_sync[14]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[15] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[15]),
        .Q(ctrl_sync[15]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[16] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[16]),
        .Q(ctrl_sync[16]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[17] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[17]),
        .Q(ctrl_sync[17]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[18] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[18]),
        .Q(ctrl_sync[18]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[19] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[19]),
        .Q(ctrl_sync[19]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[1] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[1]),
        .Q(ctrl_sync[1]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[20] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[20]),
        .Q(ctrl_sync[20]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[21] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[21]),
        .Q(ctrl_sync[21]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[22] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[22]),
        .Q(ctrl_sync[22]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[23] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[23]),
        .Q(ctrl_sync[23]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[24] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[24]),
        .Q(ctrl_sync[24]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[25] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[25]),
        .Q(ctrl_sync[25]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[26] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[26]),
        .Q(ctrl_sync[26]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[27] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[27]),
        .Q(ctrl_sync[27]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[28] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[28]),
        .Q(ctrl_sync[28]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[29] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[29]),
        .Q(ctrl_sync[29]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[2] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[2]),
        .Q(ctrl_sync[2]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[30] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[30]),
        .Q(ctrl_sync[30]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[31] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[31]),
        .Q(ctrl_sync[31]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[3] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[3]),
        .Q(ctrl_sync[3]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[4] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[4]),
        .Q(ctrl_sync[4]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[5] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[5]),
        .Q(ctrl_sync[5]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[6] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[6]),
        .Q(ctrl_sync[6]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[7] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[7]),
        .Q(ctrl_sync[7]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[8] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[8]),
        .Q(ctrl_sync[8]),
        .R(p_0_in));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[9] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[9]),
        .Q(ctrl_sync[9]),
        .R(p_0_in));
  LUT3 #(
    .INIT(8'h4F)) 
    done_i_1
       (.I0(cap_en_d),
        .I1(ctrl_sync[1]),
        .I2(aresetn),
        .O(last_sign_valid));
  LUT6 #(
    .INIT(64'hFFFFFFFF00004000)) 
    done_i_2
       (.I0(active_i_3_n_0),
        .I1(active_i_4_n_0),
        .I2(done_i_3_n_0),
        .I3(last_sign_0),
        .I4(count_reg[16]),
        .I5(status0[4]),
        .O(done_i_2_n_0));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    done_i_3
       (.I0(count_reg[31]),
        .I1(O15[13]),
        .I2(count_reg[29]),
        .I3(count_reg[30]),
        .I4(O15[15]),
        .I5(O15[14]),
        .O(done_i_3_n_0));
  FDRE #(
    .INIT(1'b0)) 
    done_reg
       (.C(aclk),
        .CE(1'b1),
        .D(done_i_2_n_0),
        .Q(status0[4]),
        .R(last_sign_valid));
  LUT6 #(
    .INIT(64'h8000000000000000)) 
    \first_sample[15]_i_1 
       (.I0(\first_sample[15]_i_2_n_0 ),
        .I1(\first_sample[15]_i_3_n_0 ),
        .I2(\first_sample[15]_i_4_n_0 ),
        .I3(\first_sample[15]_i_5_n_0 ),
        .I4(\first_sample[15]_i_6_n_0 ),
        .I5(\first_sample[15]_i_7_n_0 ),
        .O(\first_sample[15]_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \first_sample[15]_i_2 
       (.I0(O15[6]),
        .I1(O15[7]),
        .I2(O15[4]),
        .I3(O15[5]),
        .I4(O15[9]),
        .I5(O15[8]),
        .O(\first_sample[15]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \first_sample[15]_i_3 
       (.I0(O15[12]),
        .I1(O15[13]),
        .I2(O15[10]),
        .I3(O15[11]),
        .I4(O15[15]),
        .I5(O15[14]),
        .O(\first_sample[15]_i_3_n_0 ));
  LUT5 #(
    .INIT(32'h10000000)) 
    \first_sample[15]_i_4 
       (.I0(count_reg[17]),
        .I1(count_reg[16]),
        .I2(ctrl_sync[1]),
        .I3(active_reg_0),
        .I4(s_axis_tvalid),
        .O(\first_sample[15]_i_4_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \first_sample[15]_i_5 
       (.I0(count_reg[20]),
        .I1(count_reg[21]),
        .I2(count_reg[18]),
        .I3(count_reg[19]),
        .I4(count_reg[23]),
        .I5(count_reg[22]),
        .O(\first_sample[15]_i_5_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \first_sample[15]_i_6 
       (.I0(O15[0]),
        .I1(O15[1]),
        .I2(count_reg[30]),
        .I3(count_reg[31]),
        .I4(O15[3]),
        .I5(O15[2]),
        .O(\first_sample[15]_i_6_n_0 ));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \first_sample[15]_i_7 
       (.I0(count_reg[26]),
        .I1(count_reg[27]),
        .I2(count_reg[24]),
        .I3(count_reg[25]),
        .I4(count_reg[29]),
        .I5(count_reg[28]),
        .O(\first_sample[15]_i_7_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[0] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[0]),
        .Q(status1[0]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[10] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[10]),
        .Q(status1[10]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[11] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[11]),
        .Q(status1[11]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[12] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[12]),
        .Q(status1[12]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[13] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[13]),
        .Q(status1[13]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[14] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[14]),
        .Q(status1[14]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[15] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[15]),
        .Q(status1[15]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[1] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[1]),
        .Q(status1[1]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[2] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[2]),
        .Q(status1[2]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[3] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[3]),
        .Q(status1[3]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[4] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[4]),
        .Q(status1[4]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[5] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[5]),
        .Q(status1[5]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[6] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[6]),
        .Q(status1[6]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[7] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[7]),
        .Q(status1[7]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[8] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[8]),
        .Q(status1[8]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \first_sample_reg[9] 
       (.C(aclk),
        .CE(\first_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[9]),
        .Q(status1[9]),
        .R(last_sign_valid));
  LUT3 #(
    .INIT(8'h80)) 
    last_sign_i_1
       (.I0(s_axis_tvalid),
        .I1(active_reg_0),
        .I2(ctrl_sync[1]),
        .O(last_sign_0));
  FDRE #(
    .INIT(1'b0)) 
    last_sign_reg
       (.C(aclk),
        .CE(last_sign_0),
        .D(s_axis_tdata[15]),
        .Q(last_sign),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    last_sign_valid_reg
       (.C(aclk),
        .CE(last_sign_0),
        .D(last_sign_0),
        .Q(last_sign_valid_reg_n_0),
        .R(last_sign_valid));
  (* COMPARATOR_THRESHOLD = "11" *) 
  CARRY8 max_abs0_carry
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({max_abs0_carry_n_0,max_abs0_carry_n_1,max_abs0_carry_n_2,max_abs0_carry_n_3,max_abs0_carry_n_4,max_abs0_carry_n_5,max_abs0_carry_n_6,max_abs0_carry_n_7}),
        .DI({max_abs0_carry_i_1_n_0,max_abs0_carry_i_2_n_0,max_abs0_carry_i_3_n_0,max_abs0_carry_i_4_n_0,max_abs0_carry_i_5_n_0,max_abs0_carry_i_6_n_0,max_abs0_carry_i_7_n_0,max_abs0_carry_i_8_n_0}),
        .O(NLW_max_abs0_carry_O_UNCONNECTED[7:0]),
        .S({max_abs0_carry_i_9_n_0,max_abs0_carry_i_10_n_0,max_abs0_carry_i_11_n_0,max_abs0_carry_i_12_n_0,max_abs0_carry_i_13_n_0,max_abs0_carry_i_14_n_0,max_abs0_carry_i_15_n_0,max_abs0_carry_i_16_n_0}));
  LUT5 #(
    .INIT(32'h0004007C)) 
    max_abs0_carry_i_1
       (.I0(saw_nonzero_i_2_n_0),
        .I1(s_axis_tdata[15]),
        .I2(s_axis_tdata[14]),
        .I3(status1[31]),
        .I4(status1[30]),
        .O(max_abs0_carry_i_1_n_0));
  LUT6 #(
    .INIT(64'h5028285007808007)) 
    max_abs0_carry_i_10
       (.I0(s_axis_tdata[15]),
        .I1(\max_abs[13]_i_2_n_0 ),
        .I2(s_axis_tdata[12]),
        .I3(s_axis_tdata[13]),
        .I4(status1[29]),
        .I5(status1[28]),
        .O(max_abs0_carry_i_10_n_0));
  LUT6 #(
    .INIT(64'h1248482184842121)) 
    max_abs0_carry_i_11
       (.I0(status1[27]),
        .I1(status1[26]),
        .I2(s_axis_tdata[11]),
        .I3(max_abs0_carry_i_17_n_0),
        .I4(s_axis_tdata[10]),
        .I5(s_axis_tdata[15]),
        .O(max_abs0_carry_i_11_n_0));
  LUT6 #(
    .INIT(64'h4224188148843003)) 
    max_abs0_carry_i_12
       (.I0(s_axis_tdata[15]),
        .I1(status1[24]),
        .I2(status1[25]),
        .I3(s_axis_tdata[9]),
        .I4(s_axis_tdata[8]),
        .I5(clipping_i_4_n_0),
        .O(max_abs0_carry_i_12_n_0));
  LUT6 #(
    .INIT(64'h1248482184842121)) 
    max_abs0_carry_i_13
       (.I0(status1[23]),
        .I1(status1[22]),
        .I2(s_axis_tdata[7]),
        .I3(\max_abs[7]_i_2_n_0 ),
        .I4(s_axis_tdata[6]),
        .I5(s_axis_tdata[15]),
        .O(max_abs0_carry_i_13_n_0));
  LUT6 #(
    .INIT(64'h1248482184842121)) 
    max_abs0_carry_i_14
       (.I0(status1[21]),
        .I1(status1[20]),
        .I2(s_axis_tdata[5]),
        .I3(max_abs0_carry_i_18_n_0),
        .I4(s_axis_tdata[4]),
        .I5(s_axis_tdata[15]),
        .O(max_abs0_carry_i_14_n_0));
  LUT6 #(
    .INIT(64'h1248482184842121)) 
    max_abs0_carry_i_15
       (.I0(status1[19]),
        .I1(status1[18]),
        .I2(s_axis_tdata[3]),
        .I3(\max_abs[5]_i_2_n_0 ),
        .I4(s_axis_tdata[2]),
        .I5(s_axis_tdata[15]),
        .O(max_abs0_carry_i_15_n_0));
  LUT5 #(
    .INIT(32'h60900C03)) 
    max_abs0_carry_i_16
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[1]),
        .I2(s_axis_tdata[0]),
        .I3(status1[17]),
        .I4(status1[16]),
        .O(max_abs0_carry_i_16_n_0));
  (* SOFT_HLUTNM = "soft_lutpair3" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    max_abs0_carry_i_17
       (.I0(s_axis_tdata[9]),
        .I1(s_axis_tdata[8]),
        .I2(s_axis_tdata[7]),
        .I3(\max_abs[7]_i_2_n_0 ),
        .I4(s_axis_tdata[6]),
        .O(max_abs0_carry_i_17_n_0));
  (* SOFT_HLUTNM = "soft_lutpair9" *) 
  LUT4 #(
    .INIT(16'hFFFE)) 
    max_abs0_carry_i_18
       (.I0(s_axis_tdata[2]),
        .I1(s_axis_tdata[0]),
        .I2(s_axis_tdata[1]),
        .I3(s_axis_tdata[3]),
        .O(max_abs0_carry_i_18_n_0));
  LUT6 #(
    .INIT(64'h0717133331717000)) 
    max_abs0_carry_i_2
       (.I0(status1[28]),
        .I1(status1[29]),
        .I2(s_axis_tdata[15]),
        .I3(\max_abs[13]_i_2_n_0 ),
        .I4(s_axis_tdata[12]),
        .I5(s_axis_tdata[13]),
        .O(max_abs0_carry_i_2_n_0));
  LUT6 #(
    .INIT(64'h0717133331717000)) 
    max_abs0_carry_i_3
       (.I0(status1[26]),
        .I1(status1[27]),
        .I2(s_axis_tdata[15]),
        .I3(max_abs0_carry_i_17_n_0),
        .I4(s_axis_tdata[10]),
        .I5(s_axis_tdata[11]),
        .O(max_abs0_carry_i_3_n_0));
  LUT6 #(
    .INIT(64'h0000502857A87FF8)) 
    max_abs0_carry_i_4
       (.I0(s_axis_tdata[15]),
        .I1(clipping_i_4_n_0),
        .I2(s_axis_tdata[8]),
        .I3(s_axis_tdata[9]),
        .I4(status1[24]),
        .I5(status1[25]),
        .O(max_abs0_carry_i_4_n_0));
  LUT6 #(
    .INIT(64'h0717133331717000)) 
    max_abs0_carry_i_5
       (.I0(status1[22]),
        .I1(status1[23]),
        .I2(s_axis_tdata[15]),
        .I3(\max_abs[7]_i_2_n_0 ),
        .I4(s_axis_tdata[6]),
        .I5(s_axis_tdata[7]),
        .O(max_abs0_carry_i_5_n_0));
  LUT6 #(
    .INIT(64'h0717133331717000)) 
    max_abs0_carry_i_6
       (.I0(status1[20]),
        .I1(status1[21]),
        .I2(s_axis_tdata[15]),
        .I3(max_abs0_carry_i_18_n_0),
        .I4(s_axis_tdata[4]),
        .I5(s_axis_tdata[5]),
        .O(max_abs0_carry_i_6_n_0));
  LUT6 #(
    .INIT(64'h0717133331717000)) 
    max_abs0_carry_i_7
       (.I0(status1[18]),
        .I1(status1[19]),
        .I2(s_axis_tdata[15]),
        .I3(\max_abs[5]_i_2_n_0 ),
        .I4(s_axis_tdata[2]),
        .I5(s_axis_tdata[3]),
        .O(max_abs0_carry_i_7_n_0));
  LUT5 #(
    .INIT(32'h17337100)) 
    max_abs0_carry_i_8
       (.I0(status1[16]),
        .I1(status1[17]),
        .I2(s_axis_tdata[15]),
        .I3(s_axis_tdata[0]),
        .I4(s_axis_tdata[1]),
        .O(max_abs0_carry_i_8_n_0));
  LUT5 #(
    .INIT(32'h00106C83)) 
    max_abs0_carry_i_9
       (.I0(saw_nonzero_i_2_n_0),
        .I1(s_axis_tdata[14]),
        .I2(s_axis_tdata[15]),
        .I3(status1[30]),
        .I4(status1[31]),
        .O(max_abs0_carry_i_9_n_0));
  (* SOFT_HLUTNM = "soft_lutpair2" *) 
  LUT5 #(
    .INIT(32'h5557AAA8)) 
    \max_abs[10]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[9]),
        .I2(s_axis_tdata[8]),
        .I3(clipping_i_4_n_0),
        .I4(s_axis_tdata[10]),
        .O(abs16_return[10]));
  LUT6 #(
    .INIT(64'h55555557AAAAAAA8)) 
    \max_abs[11]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(clipping_i_4_n_0),
        .I2(s_axis_tdata[8]),
        .I3(s_axis_tdata[9]),
        .I4(s_axis_tdata[10]),
        .I5(s_axis_tdata[11]),
        .O(abs16_return[11]));
  (* SOFT_HLUTNM = "soft_lutpair7" *) 
  LUT3 #(
    .INIT(8'h78)) 
    \max_abs[12]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(\max_abs[13]_i_2_n_0 ),
        .I2(s_axis_tdata[12]),
        .O(abs16_return[12]));
  (* SOFT_HLUTNM = "soft_lutpair7" *) 
  LUT4 #(
    .INIT(16'h57A8)) 
    \max_abs[13]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(\max_abs[13]_i_2_n_0 ),
        .I2(s_axis_tdata[12]),
        .I3(s_axis_tdata[13]),
        .O(abs16_return[13]));
  (* SOFT_HLUTNM = "soft_lutpair1" *) 
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \max_abs[13]_i_2 
       (.I0(s_axis_tdata[10]),
        .I1(s_axis_tdata[9]),
        .I2(s_axis_tdata[8]),
        .I3(clipping_i_4_n_0),
        .I4(s_axis_tdata[11]),
        .O(\max_abs[13]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair11" *) 
  LUT3 #(
    .INIT(8'h6A)) 
    \max_abs[14]_i_1 
       (.I0(s_axis_tdata[14]),
        .I1(saw_nonzero_i_2_n_0),
        .I2(s_axis_tdata[15]),
        .O(abs16_return[14]));
  LUT4 #(
    .INIT(16'h8000)) 
    \max_abs[15]_i_1 
       (.I0(ctrl_sync[1]),
        .I1(active_reg_0),
        .I2(s_axis_tvalid),
        .I3(max_abs0_carry_n_0),
        .O(max_abs));
  (* SOFT_HLUTNM = "soft_lutpair11" *) 
  LUT3 #(
    .INIT(8'h04)) 
    \max_abs[15]_i_2 
       (.I0(s_axis_tdata[14]),
        .I1(s_axis_tdata[15]),
        .I2(saw_nonzero_i_2_n_0),
        .O(abs16_return[15]));
  (* SOFT_HLUTNM = "soft_lutpair9" *) 
  LUT3 #(
    .INIT(8'h78)) 
    \max_abs[1]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[0]),
        .I2(s_axis_tdata[1]),
        .O(abs16_return[1]));
  (* SOFT_HLUTNM = "soft_lutpair4" *) 
  LUT4 #(
    .INIT(16'h57A8)) 
    \max_abs[2]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[0]),
        .I2(s_axis_tdata[1]),
        .I3(s_axis_tdata[2]),
        .O(abs16_return[2]));
  (* SOFT_HLUTNM = "soft_lutpair4" *) 
  LUT5 #(
    .INIT(32'h5557AAA8)) 
    \max_abs[3]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[1]),
        .I2(s_axis_tdata[0]),
        .I3(s_axis_tdata[2]),
        .I4(s_axis_tdata[3]),
        .O(abs16_return[3]));
  LUT6 #(
    .INIT(64'h55555557AAAAAAA8)) 
    \max_abs[4]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[2]),
        .I2(s_axis_tdata[0]),
        .I3(s_axis_tdata[1]),
        .I4(s_axis_tdata[3]),
        .I5(s_axis_tdata[4]),
        .O(abs16_return[4]));
  LUT6 #(
    .INIT(64'h55555557AAAAAAA8)) 
    \max_abs[5]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[3]),
        .I2(\max_abs[5]_i_2_n_0 ),
        .I3(s_axis_tdata[2]),
        .I4(s_axis_tdata[4]),
        .I5(s_axis_tdata[5]),
        .O(abs16_return[5]));
  LUT2 #(
    .INIT(4'hE)) 
    \max_abs[5]_i_2 
       (.I0(s_axis_tdata[0]),
        .I1(s_axis_tdata[1]),
        .O(\max_abs[5]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair8" *) 
  LUT3 #(
    .INIT(8'h78)) 
    \max_abs[6]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(\max_abs[7]_i_2_n_0 ),
        .I2(s_axis_tdata[6]),
        .O(abs16_return[6]));
  (* SOFT_HLUTNM = "soft_lutpair8" *) 
  LUT4 #(
    .INIT(16'h57A8)) 
    \max_abs[7]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(\max_abs[7]_i_2_n_0 ),
        .I2(s_axis_tdata[6]),
        .I3(s_axis_tdata[7]),
        .O(abs16_return[7]));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \max_abs[7]_i_2 
       (.I0(s_axis_tdata[4]),
        .I1(s_axis_tdata[2]),
        .I2(s_axis_tdata[0]),
        .I3(s_axis_tdata[1]),
        .I4(s_axis_tdata[3]),
        .I5(s_axis_tdata[5]),
        .O(\max_abs[7]_i_2_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair12" *) 
  LUT3 #(
    .INIT(8'h78)) 
    \max_abs[8]_i_1 
       (.I0(s_axis_tdata[15]),
        .I1(clipping_i_4_n_0),
        .I2(s_axis_tdata[8]),
        .O(abs16_return[8]));
  (* SOFT_HLUTNM = "soft_lutpair2" *) 
  LUT4 #(
    .INIT(16'h666A)) 
    \max_abs[9]_i_1 
       (.I0(s_axis_tdata[9]),
        .I1(s_axis_tdata[15]),
        .I2(s_axis_tdata[8]),
        .I3(clipping_i_4_n_0),
        .O(abs16_return[9]));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[0] 
       (.C(aclk),
        .CE(max_abs),
        .D(s_axis_tdata[0]),
        .Q(status1[16]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[10] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[10]),
        .Q(status1[26]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[11] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[11]),
        .Q(status1[27]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[12] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[12]),
        .Q(status1[28]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[13] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[13]),
        .Q(status1[29]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[14] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[14]),
        .Q(status1[30]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[15] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[15]),
        .Q(status1[31]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[1] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[1]),
        .Q(status1[17]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[2] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[2]),
        .Q(status1[18]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[3] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[3]),
        .Q(status1[19]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[4] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[4]),
        .Q(status1[20]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[5] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[5]),
        .Q(status1[21]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[6] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[6]),
        .Q(status1[22]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[7] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[7]),
        .Q(status1[23]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[8] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[8]),
        .Q(status1[24]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_abs_reg[9] 
       (.C(aclk),
        .CE(max_abs),
        .D(abs16_return[9]),
        .Q(status1[25]),
        .R(last_sign_valid));
  (* COMPARATOR_THRESHOLD = "11" *) 
  CARRY8 max_sample0_carry
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({max_sample0_carry_n_0,max_sample0_carry_n_1,max_sample0_carry_n_2,max_sample0_carry_n_3,max_sample0_carry_n_4,max_sample0_carry_n_5,max_sample0_carry_n_6,max_sample0_carry_n_7}),
        .DI({max_sample0_carry_i_1_n_0,max_sample0_carry_i_2_n_0,max_sample0_carry_i_3_n_0,max_sample0_carry_i_4_n_0,max_sample0_carry_i_5_n_0,max_sample0_carry_i_6_n_0,max_sample0_carry_i_7_n_0,max_sample0_carry_i_8_n_0}),
        .O(NLW_max_sample0_carry_O_UNCONNECTED[7:0]),
        .S({max_sample0_carry_i_9_n_0,max_sample0_carry_i_10_n_0,max_sample0_carry_i_11_n_0,max_sample0_carry_i_12_n_0,max_sample0_carry_i_13_n_0,max_sample0_carry_i_14_n_0,max_sample0_carry_i_15_n_0,max_sample0_carry_i_16_n_0}));
  LUT4 #(
    .INIT(16'h7150)) 
    max_sample0_carry_i_1
       (.I0(s_axis_tdata[15]),
        .I1(status3[14]),
        .I2(status3[15]),
        .I3(s_axis_tdata[14]),
        .O(max_sample0_carry_i_1_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    max_sample0_carry_i_10
       (.I0(status3[13]),
        .I1(s_axis_tdata[13]),
        .I2(status3[12]),
        .I3(s_axis_tdata[12]),
        .O(max_sample0_carry_i_10_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    max_sample0_carry_i_11
       (.I0(status3[11]),
        .I1(s_axis_tdata[11]),
        .I2(status3[10]),
        .I3(s_axis_tdata[10]),
        .O(max_sample0_carry_i_11_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    max_sample0_carry_i_12
       (.I0(status3[9]),
        .I1(status3[8]),
        .I2(s_axis_tdata[9]),
        .I3(s_axis_tdata[8]),
        .O(max_sample0_carry_i_12_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    max_sample0_carry_i_13
       (.I0(status3[7]),
        .I1(s_axis_tdata[7]),
        .I2(status3[6]),
        .I3(s_axis_tdata[6]),
        .O(max_sample0_carry_i_13_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    max_sample0_carry_i_14
       (.I0(status3[5]),
        .I1(s_axis_tdata[5]),
        .I2(status3[4]),
        .I3(s_axis_tdata[4]),
        .O(max_sample0_carry_i_14_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    max_sample0_carry_i_15
       (.I0(status3[3]),
        .I1(s_axis_tdata[3]),
        .I2(status3[2]),
        .I3(s_axis_tdata[2]),
        .O(max_sample0_carry_i_15_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    max_sample0_carry_i_16
       (.I0(s_axis_tdata[1]),
        .I1(s_axis_tdata[0]),
        .I2(status3[1]),
        .I3(status3[0]),
        .O(max_sample0_carry_i_16_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_2
       (.I0(s_axis_tdata[13]),
        .I1(status3[13]),
        .I2(s_axis_tdata[12]),
        .I3(status3[12]),
        .O(max_sample0_carry_i_2_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_3
       (.I0(s_axis_tdata[11]),
        .I1(status3[11]),
        .I2(s_axis_tdata[10]),
        .I3(status3[10]),
        .O(max_sample0_carry_i_3_n_0));
  LUT4 #(
    .INIT(16'h20BA)) 
    max_sample0_carry_i_4
       (.I0(s_axis_tdata[9]),
        .I1(status3[8]),
        .I2(s_axis_tdata[8]),
        .I3(status3[9]),
        .O(max_sample0_carry_i_4_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_5
       (.I0(s_axis_tdata[7]),
        .I1(status3[7]),
        .I2(s_axis_tdata[6]),
        .I3(status3[6]),
        .O(max_sample0_carry_i_5_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_6
       (.I0(s_axis_tdata[5]),
        .I1(status3[5]),
        .I2(s_axis_tdata[4]),
        .I3(status3[4]),
        .O(max_sample0_carry_i_6_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_7
       (.I0(s_axis_tdata[3]),
        .I1(status3[3]),
        .I2(s_axis_tdata[2]),
        .I3(status3[2]),
        .O(max_sample0_carry_i_7_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    max_sample0_carry_i_8
       (.I0(s_axis_tdata[1]),
        .I1(status3[1]),
        .I2(s_axis_tdata[0]),
        .I3(status3[0]),
        .O(max_sample0_carry_i_8_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    max_sample0_carry_i_9
       (.I0(status3[15]),
        .I1(status3[14]),
        .I2(s_axis_tdata[15]),
        .I3(s_axis_tdata[14]),
        .O(max_sample0_carry_i_9_n_0));
  LUT4 #(
    .INIT(16'h8000)) 
    \max_sample[15]_i_1 
       (.I0(ctrl_sync[1]),
        .I1(active_reg_0),
        .I2(s_axis_tvalid),
        .I3(max_sample0_carry_n_0),
        .O(\max_sample[15]_i_1_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[0] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[0]),
        .Q(status3[0]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[10] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[10]),
        .Q(status3[10]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[11] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[11]),
        .Q(status3[11]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[12] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[12]),
        .Q(status3[12]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[13] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[13]),
        .Q(status3[13]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[14] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[14]),
        .Q(status3[14]),
        .R(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \max_sample_reg[15] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[15]),
        .Q(status3[15]),
        .S(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[1] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[1]),
        .Q(status3[1]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[2] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[2]),
        .Q(status3[2]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[3] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[3]),
        .Q(status3[3]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[4] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[4]),
        .Q(status3[4]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[5] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[5]),
        .Q(status3[5]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[6] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[6]),
        .Q(status3[6]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[7] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[7]),
        .Q(status3[7]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[8] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[8]),
        .Q(status3[8]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \max_sample_reg[9] 
       (.C(aclk),
        .CE(\max_sample[15]_i_1_n_0 ),
        .D(s_axis_tdata[9]),
        .Q(status3[9]),
        .R(last_sign_valid));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p1_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p1_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "131072" *) 
  (* RTL_RAM_NAME = "inst/mem" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "4095" *) 
  (* ram_offset = "0" *) 
  (* ram_slice_begin = "0" *) 
  (* ram_slice_end = "8" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("FIRST"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(9),
    .READ_WIDTH_B(9),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST"),
    .WRITE_WIDTH_A(9),
    .WRITE_WIDTH_B(9)) 
    mem_reg_bram_0
       (.ADDRARDADDR({wr_addr_reg[11:0],1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({ctrl_sync[13:2],1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINB({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINPA({1'b0,1'b0,1'b0,1'b0}),
        .CASDINPB({1'b0,1'b0,1'b0,1'b0}),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_mem_reg_bram_0_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB({NLW_mem_reg_bram_0_CASDOUTB_UNCONNECTED[31:8],mem_reg_bram_0_n_60,mem_reg_bram_0_n_61,mem_reg_bram_0_n_62,mem_reg_bram_0_n_63,mem_reg_bram_0_n_64,mem_reg_bram_0_n_65,mem_reg_bram_0_n_66,mem_reg_bram_0_n_67}),
        .CASDOUTPA(NLW_mem_reg_bram_0_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB({NLW_mem_reg_bram_0_CASDOUTPB_UNCONNECTED[3:1],mem_reg_bram_0_n_139}),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(mem_reg_bram_0_n_0),
        .CASOUTSBITERR(mem_reg_bram_0_n_1),
        .CLKARDCLK(aclk),
        .CLKBWRCLK(aclk),
        .DBITERR(NLW_mem_reg_bram_0_DBITERR_UNCONNECTED),
        .DINADIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,s_axis_tdata[7:0]}),
        .DINBDIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .DINPADINP({1'b0,1'b0,1'b0,s_axis_tdata[8]}),
        .DINPBDINP({1'b0,1'b0,1'b0,1'b1}),
        .DOUTADOUT(NLW_mem_reg_bram_0_DOUTADOUT_UNCONNECTED[31:0]),
        .DOUTBDOUT(NLW_mem_reg_bram_0_DOUTBDOUT_UNCONNECTED[31:0]),
        .DOUTPADOUTP(NLW_mem_reg_bram_0_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_mem_reg_bram_0_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_mem_reg_bram_0_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(mem_reg_bram_0_i_1_n_0),
        .ENBWREN(mem_reg_bram_1_i_1_n_0),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_mem_reg_bram_0_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_mem_reg_bram_0_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({mem_reg_bram_0_i_2_n_0,mem_reg_bram_0_i_2_n_0,mem_reg_bram_0_i_2_n_0,mem_reg_bram_0_i_2_n_0}),
        .WEBWE({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}));
  (* SOFT_HLUTNM = "soft_lutpair6" *) 
  LUT3 #(
    .INIT(8'h08)) 
    mem_reg_bram_0_i_1
       (.I0(s_axis_tvalid),
        .I1(active_reg_0),
        .I2(wr_addr_reg[12]),
        .O(mem_reg_bram_0_i_1_n_0));
  (* SOFT_HLUTNM = "soft_lutpair13" *) 
  LUT2 #(
    .INIT(4'h1)) 
    mem_reg_bram_0_i_2
       (.I0(wr_full),
        .I1(wr_addr_reg[12]),
        .O(mem_reg_bram_0_i_2_n_0));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p1_d8" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p1_d8" *) 
  (* METHODOLOGY_DRC_VIOS = "{SYNTH-6 {cell *THIS*}}" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "131072" *) 
  (* RTL_RAM_NAME = "inst/mem" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "4096" *) 
  (* ram_addr_end = "8191" *) 
  (* ram_offset = "0" *) 
  (* ram_slice_begin = "0" *) 
  (* ram_slice_end = "8" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("LAST"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(9),
    .READ_WIDTH_B(9),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST"),
    .WRITE_WIDTH_A(9),
    .WRITE_WIDTH_B(9)) 
    mem_reg_bram_1
       (.ADDRARDADDR({wr_addr_reg[11:0],1'b1,1'b1,1'b1}),
        .ADDRBWRADDR({ctrl_sync[13:2],1'b1,1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINB({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,mem_reg_bram_0_n_60,mem_reg_bram_0_n_61,mem_reg_bram_0_n_62,mem_reg_bram_0_n_63,mem_reg_bram_0_n_64,mem_reg_bram_0_n_65,mem_reg_bram_0_n_66,mem_reg_bram_0_n_67}),
        .CASDINPA({1'b0,1'b0,1'b0,1'b0}),
        .CASDINPB({1'b0,1'b0,1'b0,mem_reg_bram_0_n_139}),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(mem_reg_bram_1_i_1_n_0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_mem_reg_bram_1_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_mem_reg_bram_1_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_mem_reg_bram_1_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_mem_reg_bram_1_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(mem_reg_bram_0_n_0),
        .CASINSBITERR(mem_reg_bram_0_n_1),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_mem_reg_bram_1_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_mem_reg_bram_1_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(aclk),
        .CLKBWRCLK(aclk),
        .DBITERR(NLW_mem_reg_bram_1_DBITERR_UNCONNECTED),
        .DINADIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,s_axis_tdata[7:0]}),
        .DINBDIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1}),
        .DINPADINP({1'b0,1'b0,1'b0,s_axis_tdata[8]}),
        .DINPBDINP({1'b0,1'b0,1'b0,1'b1}),
        .DOUTADOUT(NLW_mem_reg_bram_1_DOUTADOUT_UNCONNECTED[31:0]),
        .DOUTBDOUT({NLW_mem_reg_bram_1_DOUTBDOUT_UNCONNECTED[31:8],status_capture[7:0]}),
        .DOUTPADOUTP(NLW_mem_reg_bram_1_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP({NLW_mem_reg_bram_1_DOUTPBDOUTP_UNCONNECTED[3:1],status_capture[8]}),
        .ECCPARITY(NLW_mem_reg_bram_1_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(mem_reg_bram_1_i_2_n_0),
        .ENBWREN(ctrl_sync[14]),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_mem_reg_bram_1_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_mem_reg_bram_1_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({mem_reg_bram_1_i_3_n_0,mem_reg_bram_1_i_3_n_0,mem_reg_bram_1_i_3_n_0,mem_reg_bram_1_i_3_n_0}),
        .WEBWE({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}));
  LUT1 #(
    .INIT(2'h1)) 
    mem_reg_bram_1_i_1
       (.I0(ctrl_sync[14]),
        .O(mem_reg_bram_1_i_1_n_0));
  (* SOFT_HLUTNM = "soft_lutpair10" *) 
  LUT3 #(
    .INIT(8'h80)) 
    mem_reg_bram_1_i_2
       (.I0(s_axis_tvalid),
        .I1(active_reg_0),
        .I2(wr_addr_reg[12]),
        .O(mem_reg_bram_1_i_2_n_0));
  (* SOFT_HLUTNM = "soft_lutpair13" *) 
  LUT2 #(
    .INIT(4'h2)) 
    mem_reg_bram_1_i_3
       (.I0(wr_addr_reg[12]),
        .I1(wr_full),
        .O(mem_reg_bram_1_i_3_n_0));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d4" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d4" *) 
  (* METHODOLOGY_DRC_VIOS = "{SYNTH-6 {cell *THIS*}}" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "131072" *) 
  (* RTL_RAM_NAME = "inst/mem" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "8191" *) 
  (* ram_offset = "0" *) 
  (* ram_slice_begin = "9" *) 
  (* ram_slice_end = "12" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(4),
    .READ_WIDTH_B(4),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST"),
    .WRITE_WIDTH_A(4),
    .WRITE_WIDTH_B(4)) 
    mem_reg_bram_2
       (.ADDRARDADDR({wr_addr_reg,1'b1,1'b1}),
        .ADDRBWRADDR({ctrl_sync[14:2],1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINB({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINPA({1'b0,1'b0,1'b0,1'b0}),
        .CASDINPB({1'b0,1'b0,1'b0,1'b0}),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_mem_reg_bram_2_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_mem_reg_bram_2_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_mem_reg_bram_2_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_mem_reg_bram_2_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_mem_reg_bram_2_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_mem_reg_bram_2_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(aclk),
        .CLKBWRCLK(aclk),
        .DBITERR(NLW_mem_reg_bram_2_DBITERR_UNCONNECTED),
        .DINADIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,s_axis_tdata[12:9]}),
        .DINBDIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1}),
        .DINPADINP({1'b0,1'b0,1'b0,1'b0}),
        .DINPBDINP({1'b0,1'b0,1'b0,1'b0}),
        .DOUTADOUT(NLW_mem_reg_bram_2_DOUTADOUT_UNCONNECTED[31:0]),
        .DOUTBDOUT({NLW_mem_reg_bram_2_DOUTBDOUT_UNCONNECTED[31:4],status_capture[12:9]}),
        .DOUTPADOUTP(NLW_mem_reg_bram_2_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_mem_reg_bram_2_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_mem_reg_bram_2_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(mem_reg_bram_3_i_1_n_0),
        .ENBWREN(1'b1),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_mem_reg_bram_2_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_mem_reg_bram_2_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({wr_full2,wr_full2,wr_full2,wr_full2}),
        .WEBWE({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}));
  (* \MEM.PORTA.DATA_BIT_LAYOUT  = "p0_d3" *) 
  (* \MEM.PORTB.DATA_BIT_LAYOUT  = "p0_d3" *) 
  (* METHODOLOGY_DRC_VIOS = "{SYNTH-6 {cell *THIS*}}" *) 
  (* RDADDR_COLLISION_HWCONFIG = "DELAYED_WRITE" *) 
  (* RTL_RAM_BITS = "131072" *) 
  (* RTL_RAM_NAME = "inst/mem" *) 
  (* RTL_RAM_TYPE = "RAM_SDP" *) 
  (* ram_addr_begin = "0" *) 
  (* ram_addr_end = "8191" *) 
  (* ram_offset = "0" *) 
  (* ram_slice_begin = "13" *) 
  (* ram_slice_end = "15" *) 
  RAMB36E2 #(
    .CASCADE_ORDER_A("NONE"),
    .CASCADE_ORDER_B("NONE"),
    .CLOCK_DOMAINS("COMMON"),
    .DOA_REG(0),
    .DOB_REG(0),
    .ENADDRENA("FALSE"),
    .ENADDRENB("FALSE"),
    .EN_ECC_PIPE("FALSE"),
    .EN_ECC_READ("FALSE"),
    .EN_ECC_WRITE("FALSE"),
    .INIT_A(36'h000000000),
    .INIT_B(36'h000000000),
    .INIT_FILE("NONE"),
    .RDADDRCHANGEA("FALSE"),
    .RDADDRCHANGEB("FALSE"),
    .READ_WIDTH_A(4),
    .READ_WIDTH_B(4),
    .RSTREG_PRIORITY_A("RSTREG"),
    .RSTREG_PRIORITY_B("RSTREG"),
    .SIM_COLLISION_CHECK("ALL"),
    .SLEEP_ASYNC("FALSE"),
    .SRVAL_A(36'h000000000),
    .SRVAL_B(36'h000000000),
    .WRITE_MODE_A("READ_FIRST"),
    .WRITE_MODE_B("WRITE_FIRST"),
    .WRITE_WIDTH_A(4),
    .WRITE_WIDTH_B(4)) 
    mem_reg_bram_3
       (.ADDRARDADDR({wr_addr_reg,1'b1,1'b1}),
        .ADDRBWRADDR({ctrl_sync[14:2],1'b1,1'b1}),
        .ADDRENA(1'b1),
        .ADDRENB(1'b1),
        .CASDIMUXA(1'b0),
        .CASDIMUXB(1'b0),
        .CASDINA({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINB({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .CASDINPA({1'b0,1'b0,1'b0,1'b0}),
        .CASDINPB({1'b0,1'b0,1'b0,1'b0}),
        .CASDOMUXA(1'b0),
        .CASDOMUXB(1'b0),
        .CASDOMUXEN_A(1'b1),
        .CASDOMUXEN_B(1'b1),
        .CASDOUTA(NLW_mem_reg_bram_3_CASDOUTA_UNCONNECTED[31:0]),
        .CASDOUTB(NLW_mem_reg_bram_3_CASDOUTB_UNCONNECTED[31:0]),
        .CASDOUTPA(NLW_mem_reg_bram_3_CASDOUTPA_UNCONNECTED[3:0]),
        .CASDOUTPB(NLW_mem_reg_bram_3_CASDOUTPB_UNCONNECTED[3:0]),
        .CASINDBITERR(1'b0),
        .CASINSBITERR(1'b0),
        .CASOREGIMUXA(1'b0),
        .CASOREGIMUXB(1'b0),
        .CASOREGIMUXEN_A(1'b1),
        .CASOREGIMUXEN_B(1'b1),
        .CASOUTDBITERR(NLW_mem_reg_bram_3_CASOUTDBITERR_UNCONNECTED),
        .CASOUTSBITERR(NLW_mem_reg_bram_3_CASOUTSBITERR_UNCONNECTED),
        .CLKARDCLK(aclk),
        .CLKBWRCLK(aclk),
        .DBITERR(NLW_mem_reg_bram_3_DBITERR_UNCONNECTED),
        .DINADIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,s_axis_tdata[15:13]}),
        .DINBDIN({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1}),
        .DINPADINP({1'b0,1'b0,1'b0,1'b0}),
        .DINPBDINP({1'b0,1'b0,1'b0,1'b0}),
        .DOUTADOUT(NLW_mem_reg_bram_3_DOUTADOUT_UNCONNECTED[31:0]),
        .DOUTBDOUT({NLW_mem_reg_bram_3_DOUTBDOUT_UNCONNECTED[31:3],status_capture[15:13]}),
        .DOUTPADOUTP(NLW_mem_reg_bram_3_DOUTPADOUTP_UNCONNECTED[3:0]),
        .DOUTPBDOUTP(NLW_mem_reg_bram_3_DOUTPBDOUTP_UNCONNECTED[3:0]),
        .ECCPARITY(NLW_mem_reg_bram_3_ECCPARITY_UNCONNECTED[7:0]),
        .ECCPIPECE(1'b1),
        .ENARDEN(mem_reg_bram_3_i_1_n_0),
        .ENBWREN(1'b1),
        .INJECTDBITERR(1'b0),
        .INJECTSBITERR(1'b0),
        .RDADDRECC(NLW_mem_reg_bram_3_RDADDRECC_UNCONNECTED[8:0]),
        .REGCEAREGCE(1'b1),
        .REGCEB(1'b1),
        .RSTRAMARSTRAM(1'b0),
        .RSTRAMB(1'b0),
        .RSTREGARSTREG(1'b0),
        .RSTREGB(1'b0),
        .SBITERR(NLW_mem_reg_bram_3_SBITERR_UNCONNECTED),
        .SLEEP(1'b0),
        .WEA({wr_full2,wr_full2,wr_full2,wr_full2}),
        .WEBWE({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}));
  (* SOFT_HLUTNM = "soft_lutpair10" *) 
  LUT2 #(
    .INIT(4'h8)) 
    mem_reg_bram_3_i_1
       (.I0(active_reg_0),
        .I1(s_axis_tvalid),
        .O(mem_reg_bram_3_i_1_n_0));
  LUT1 #(
    .INIT(2'h1)) 
    mem_reg_bram_3_i_2
       (.I0(wr_full),
        .O(wr_full2));
  (* COMPARATOR_THRESHOLD = "11" *) 
  CARRY8 min_sample0_carry
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({min_sample0_carry_n_0,min_sample0_carry_n_1,min_sample0_carry_n_2,min_sample0_carry_n_3,min_sample0_carry_n_4,min_sample0_carry_n_5,min_sample0_carry_n_6,min_sample0_carry_n_7}),
        .DI({min_sample0_carry_i_1_n_0,min_sample0_carry_i_2_n_0,min_sample0_carry_i_3_n_0,min_sample0_carry_i_4_n_0,min_sample0_carry_i_5_n_0,min_sample0_carry_i_6_n_0,min_sample0_carry_i_7_n_0,min_sample0_carry_i_8_n_0}),
        .O(NLW_min_sample0_carry_O_UNCONNECTED[7:0]),
        .S({min_sample0_carry_i_9_n_0,min_sample0_carry_i_10_n_0,min_sample0_carry_i_11_n_0,min_sample0_carry_i_12_n_0,min_sample0_carry_i_13_n_0,min_sample0_carry_i_14_n_0,min_sample0_carry_i_15_n_0,min_sample0_carry_i_16_n_0}));
  LUT4 #(
    .INIT(16'h0A8E)) 
    min_sample0_carry_i_1
       (.I0(s_axis_tdata[15]),
        .I1(status3[30]),
        .I2(status3[31]),
        .I3(s_axis_tdata[14]),
        .O(min_sample0_carry_i_1_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    min_sample0_carry_i_10
       (.I0(status3[29]),
        .I1(s_axis_tdata[13]),
        .I2(status3[28]),
        .I3(s_axis_tdata[12]),
        .O(min_sample0_carry_i_10_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    min_sample0_carry_i_11
       (.I0(status3[27]),
        .I1(s_axis_tdata[11]),
        .I2(status3[26]),
        .I3(s_axis_tdata[10]),
        .O(min_sample0_carry_i_11_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    min_sample0_carry_i_12
       (.I0(status3[25]),
        .I1(status3[24]),
        .I2(s_axis_tdata[9]),
        .I3(s_axis_tdata[8]),
        .O(min_sample0_carry_i_12_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    min_sample0_carry_i_13
       (.I0(status3[23]),
        .I1(s_axis_tdata[7]),
        .I2(status3[22]),
        .I3(s_axis_tdata[6]),
        .O(min_sample0_carry_i_13_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    min_sample0_carry_i_14
       (.I0(status3[21]),
        .I1(s_axis_tdata[5]),
        .I2(status3[20]),
        .I3(s_axis_tdata[4]),
        .O(min_sample0_carry_i_14_n_0));
  LUT4 #(
    .INIT(16'h9009)) 
    min_sample0_carry_i_15
       (.I0(status3[19]),
        .I1(s_axis_tdata[3]),
        .I2(status3[18]),
        .I3(s_axis_tdata[2]),
        .O(min_sample0_carry_i_15_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    min_sample0_carry_i_16
       (.I0(s_axis_tdata[1]),
        .I1(s_axis_tdata[0]),
        .I2(status3[17]),
        .I3(status3[16]),
        .O(min_sample0_carry_i_16_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    min_sample0_carry_i_2
       (.I0(status3[29]),
        .I1(s_axis_tdata[13]),
        .I2(status3[28]),
        .I3(s_axis_tdata[12]),
        .O(min_sample0_carry_i_2_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    min_sample0_carry_i_3
       (.I0(status3[27]),
        .I1(s_axis_tdata[11]),
        .I2(status3[26]),
        .I3(s_axis_tdata[10]),
        .O(min_sample0_carry_i_3_n_0));
  LUT4 #(
    .INIT(16'h50D4)) 
    min_sample0_carry_i_4
       (.I0(s_axis_tdata[9]),
        .I1(status3[24]),
        .I2(status3[25]),
        .I3(s_axis_tdata[8]),
        .O(min_sample0_carry_i_4_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    min_sample0_carry_i_5
       (.I0(status3[23]),
        .I1(s_axis_tdata[7]),
        .I2(status3[22]),
        .I3(s_axis_tdata[6]),
        .O(min_sample0_carry_i_5_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    min_sample0_carry_i_6
       (.I0(status3[21]),
        .I1(s_axis_tdata[5]),
        .I2(status3[20]),
        .I3(s_axis_tdata[4]),
        .O(min_sample0_carry_i_6_n_0));
  LUT4 #(
    .INIT(16'h22B2)) 
    min_sample0_carry_i_7
       (.I0(status3[19]),
        .I1(s_axis_tdata[3]),
        .I2(status3[18]),
        .I3(s_axis_tdata[2]),
        .O(min_sample0_carry_i_7_n_0));
  LUT4 #(
    .INIT(16'h50D4)) 
    min_sample0_carry_i_8
       (.I0(s_axis_tdata[1]),
        .I1(status3[16]),
        .I2(status3[17]),
        .I3(s_axis_tdata[0]),
        .O(min_sample0_carry_i_8_n_0));
  LUT4 #(
    .INIT(16'h8421)) 
    min_sample0_carry_i_9
       (.I0(status3[31]),
        .I1(status3[30]),
        .I2(s_axis_tdata[15]),
        .I3(s_axis_tdata[14]),
        .O(min_sample0_carry_i_9_n_0));
  LUT4 #(
    .INIT(16'h8000)) 
    \min_sample[15]_i_1 
       (.I0(ctrl_sync[1]),
        .I1(active_reg_0),
        .I2(s_axis_tvalid),
        .I3(min_sample0_carry_n_0),
        .O(min_sample));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[0] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[0]),
        .Q(status3[16]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[10] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[10]),
        .Q(status3[26]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[11] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[11]),
        .Q(status3[27]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[12] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[12]),
        .Q(status3[28]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[13] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[13]),
        .Q(status3[29]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[14] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[14]),
        .Q(status3[30]),
        .S(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \min_sample_reg[15] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[15]),
        .Q(status3[31]),
        .R(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[1] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[1]),
        .Q(status3[17]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[2] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[2]),
        .Q(status3[18]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[3] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[3]),
        .Q(status3[19]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[4] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[4]),
        .Q(status3[20]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[5] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[5]),
        .Q(status3[21]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[6] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[6]),
        .Q(status3[22]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[7] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[7]),
        .Q(status3[23]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[8] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[8]),
        .Q(status3[24]),
        .S(last_sign_valid));
  FDSE #(
    .INIT(1'b1)) 
    \min_sample_reg[9] 
       (.C(aclk),
        .CE(min_sample),
        .D(s_axis_tdata[9]),
        .Q(status3[25]),
        .S(last_sign_valid));
  LUT5 #(
    .INIT(32'hFFFF22F2)) 
    overflow_i_1
       (.I0(saw_sign_change),
        .I1(overflow_i_3_n_0),
        .I2(last_sign_0),
        .I3(overflow_i_4_n_0),
        .I4(status0[2]),
        .O(overflow_i_1_n_0));
  LUT5 #(
    .INIT(32'hFFFFFF7F)) 
    overflow_i_10
       (.I0(O15[15]),
        .I1(O15[14]),
        .I2(count_reg[16]),
        .I3(overflow_i_16_n_0),
        .I4(overflow_i_17_n_0),
        .O(overflow_i_10_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_11
       (.I0(status2[13]),
        .I1(status2[12]),
        .I2(status2[15]),
        .I3(status2[14]),
        .O(overflow_i_11_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_12
       (.I0(status2[5]),
        .I1(status2[4]),
        .I2(status2[7]),
        .I3(status2[6]),
        .O(overflow_i_12_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_13
       (.I0(status2[29]),
        .I1(status2[28]),
        .I2(status2[31]),
        .I3(status2[30]),
        .O(overflow_i_13_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_14
       (.I0(status2[21]),
        .I1(status2[20]),
        .I2(status2[23]),
        .I3(status2[22]),
        .O(overflow_i_14_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_15
       (.I0(count_reg[26]),
        .I1(count_reg[25]),
        .I2(count_reg[28]),
        .I3(count_reg[27]),
        .O(overflow_i_15_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_16
       (.I0(count_reg[30]),
        .I1(count_reg[29]),
        .I2(O15[13]),
        .I3(count_reg[31]),
        .O(overflow_i_16_n_0));
  LUT4 #(
    .INIT(16'h7FFF)) 
    overflow_i_17
       (.I0(count_reg[18]),
        .I1(count_reg[17]),
        .I2(count_reg[20]),
        .I3(count_reg[19]),
        .O(overflow_i_17_n_0));
  LUT6 #(
    .INIT(64'h6000000000000000)) 
    overflow_i_2
       (.I0(last_sign),
        .I1(s_axis_tdata[15]),
        .I2(s_axis_tvalid),
        .I3(active_reg_0),
        .I4(ctrl_sync[1]),
        .I5(last_sign_valid_reg_n_0),
        .O(saw_sign_change));
  LUT4 #(
    .INIT(16'hFFFE)) 
    overflow_i_3
       (.I0(overflow_i_5_n_0),
        .I1(overflow_i_6_n_0),
        .I2(overflow_i_7_n_0),
        .I3(overflow_i_8_n_0),
        .O(overflow_i_3_n_0));
  LUT3 #(
    .INIT(8'hFE)) 
    overflow_i_4
       (.I0(active_i_3_n_0),
        .I1(overflow_i_9_n_0),
        .I2(overflow_i_10_n_0),
        .O(overflow_i_4_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    overflow_i_5
       (.I0(status2[10]),
        .I1(status2[11]),
        .I2(status2[8]),
        .I3(status2[9]),
        .I4(overflow_i_11_n_0),
        .O(overflow_i_5_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    overflow_i_6
       (.I0(status2[2]),
        .I1(status2[3]),
        .I2(status2[0]),
        .I3(status2[1]),
        .I4(overflow_i_12_n_0),
        .O(overflow_i_6_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    overflow_i_7
       (.I0(status2[26]),
        .I1(status2[27]),
        .I2(status2[24]),
        .I3(status2[25]),
        .I4(overflow_i_13_n_0),
        .O(overflow_i_7_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    overflow_i_8
       (.I0(status2[18]),
        .I1(status2[19]),
        .I2(status2[16]),
        .I3(status2[17]),
        .I4(overflow_i_14_n_0),
        .O(overflow_i_8_n_0));
  LUT5 #(
    .INIT(32'hFFFF7FFF)) 
    overflow_i_9
       (.I0(count_reg[23]),
        .I1(count_reg[24]),
        .I2(count_reg[21]),
        .I3(count_reg[22]),
        .I4(overflow_i_15_n_0),
        .O(overflow_i_9_n_0));
  FDRE #(
    .INIT(1'b0)) 
    overflow_reg
       (.C(aclk),
        .CE(1'b1),
        .D(overflow_i_1_n_0),
        .Q(status0[2]),
        .R(last_sign_valid));
  (* SOFT_HLUTNM = "soft_lutpair5" *) 
  LUT5 #(
    .INIT(32'hFFFFF0E0)) 
    saw_nonzero_i_1
       (.I0(s_axis_tdata[15]),
        .I1(s_axis_tdata[14]),
        .I2(last_sign_0),
        .I3(saw_nonzero_i_2_n_0),
        .I4(status0[3]),
        .O(saw_nonzero_i_1_n_0));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    saw_nonzero_i_2
       (.I0(s_axis_tdata[12]),
        .I1(s_axis_tdata[10]),
        .I2(max_abs0_carry_i_17_n_0),
        .I3(s_axis_tdata[11]),
        .I4(s_axis_tdata[13]),
        .O(saw_nonzero_i_2_n_0));
  FDRE #(
    .INIT(1'b0)) 
    saw_nonzero_reg
       (.C(aclk),
        .CE(1'b1),
        .D(saw_nonzero_i_1_n_0),
        .Q(status0[3]),
        .R(last_sign_valid));
  LUT5 #(
    .INIT(32'hFFFF0880)) 
    saw_sign_change_i_1
       (.I0(last_sign_valid_reg_n_0),
        .I1(last_sign_0),
        .I2(s_axis_tdata[15]),
        .I3(last_sign),
        .I4(status0[1]),
        .O(saw_sign_change_i_1_n_0));
  FDRE #(
    .INIT(1'b0)) 
    saw_sign_change_reg
       (.C(aclk),
        .CE(1'b1),
        .D(saw_sign_change_i_1_n_0),
        .Q(status0[1]),
        .R(last_sign_valid));
  LUT5 #(
    .INIT(32'h00808000)) 
    \sign_changes[31]_i_1 
       (.I0(overflow_i_3_n_0),
        .I1(last_sign_valid_reg_n_0),
        .I2(last_sign_0),
        .I3(s_axis_tdata[15]),
        .I4(last_sign),
        .O(\sign_changes[31]_i_1_n_0 ));
  LUT1 #(
    .INIT(2'h1)) 
    \sign_changes[7]_i_2 
       (.I0(status2[0]),
        .O(\sign_changes[7]_i_2_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[0] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_15 ),
        .Q(status2[0]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[10] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_13 ),
        .Q(status2[10]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[11] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_12 ),
        .Q(status2[11]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[12] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_11 ),
        .Q(status2[12]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[13] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_10 ),
        .Q(status2[13]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[14] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_9 ),
        .Q(status2[14]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[15] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_8 ),
        .Q(status2[15]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \sign_changes_reg[15]_i_1 
       (.CI(\sign_changes_reg[7]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\sign_changes_reg[15]_i_1_n_0 ,\sign_changes_reg[15]_i_1_n_1 ,\sign_changes_reg[15]_i_1_n_2 ,\sign_changes_reg[15]_i_1_n_3 ,\sign_changes_reg[15]_i_1_n_4 ,\sign_changes_reg[15]_i_1_n_5 ,\sign_changes_reg[15]_i_1_n_6 ,\sign_changes_reg[15]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\sign_changes_reg[15]_i_1_n_8 ,\sign_changes_reg[15]_i_1_n_9 ,\sign_changes_reg[15]_i_1_n_10 ,\sign_changes_reg[15]_i_1_n_11 ,\sign_changes_reg[15]_i_1_n_12 ,\sign_changes_reg[15]_i_1_n_13 ,\sign_changes_reg[15]_i_1_n_14 ,\sign_changes_reg[15]_i_1_n_15 }),
        .S(status2[15:8]));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[16] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_15 ),
        .Q(status2[16]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[17] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_14 ),
        .Q(status2[17]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[18] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_13 ),
        .Q(status2[18]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[19] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_12 ),
        .Q(status2[19]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[1] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_14 ),
        .Q(status2[1]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[20] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_11 ),
        .Q(status2[20]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[21] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_10 ),
        .Q(status2[21]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[22] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_9 ),
        .Q(status2[22]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[23] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[23]_i_1_n_8 ),
        .Q(status2[23]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \sign_changes_reg[23]_i_1 
       (.CI(\sign_changes_reg[15]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\sign_changes_reg[23]_i_1_n_0 ,\sign_changes_reg[23]_i_1_n_1 ,\sign_changes_reg[23]_i_1_n_2 ,\sign_changes_reg[23]_i_1_n_3 ,\sign_changes_reg[23]_i_1_n_4 ,\sign_changes_reg[23]_i_1_n_5 ,\sign_changes_reg[23]_i_1_n_6 ,\sign_changes_reg[23]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\sign_changes_reg[23]_i_1_n_8 ,\sign_changes_reg[23]_i_1_n_9 ,\sign_changes_reg[23]_i_1_n_10 ,\sign_changes_reg[23]_i_1_n_11 ,\sign_changes_reg[23]_i_1_n_12 ,\sign_changes_reg[23]_i_1_n_13 ,\sign_changes_reg[23]_i_1_n_14 ,\sign_changes_reg[23]_i_1_n_15 }),
        .S(status2[23:16]));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[24] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_15 ),
        .Q(status2[24]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[25] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_14 ),
        .Q(status2[25]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[26] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_13 ),
        .Q(status2[26]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[27] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_12 ),
        .Q(status2[27]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[28] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_11 ),
        .Q(status2[28]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[29] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_10 ),
        .Q(status2[29]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[2] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_13 ),
        .Q(status2[2]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[30] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_9 ),
        .Q(status2[30]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[31] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[31]_i_2_n_8 ),
        .Q(status2[31]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \sign_changes_reg[31]_i_2 
       (.CI(\sign_changes_reg[23]_i_1_n_0 ),
        .CI_TOP(1'b0),
        .CO({\NLW_sign_changes_reg[31]_i_2_CO_UNCONNECTED [7],\sign_changes_reg[31]_i_2_n_1 ,\sign_changes_reg[31]_i_2_n_2 ,\sign_changes_reg[31]_i_2_n_3 ,\sign_changes_reg[31]_i_2_n_4 ,\sign_changes_reg[31]_i_2_n_5 ,\sign_changes_reg[31]_i_2_n_6 ,\sign_changes_reg[31]_i_2_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({\sign_changes_reg[31]_i_2_n_8 ,\sign_changes_reg[31]_i_2_n_9 ,\sign_changes_reg[31]_i_2_n_10 ,\sign_changes_reg[31]_i_2_n_11 ,\sign_changes_reg[31]_i_2_n_12 ,\sign_changes_reg[31]_i_2_n_13 ,\sign_changes_reg[31]_i_2_n_14 ,\sign_changes_reg[31]_i_2_n_15 }),
        .S(status2[31:24]));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[3] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_12 ),
        .Q(status2[3]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[4] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_11 ),
        .Q(status2[4]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[5] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_10 ),
        .Q(status2[5]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[6] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_9 ),
        .Q(status2[6]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[7] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[7]_i_1_n_8 ),
        .Q(status2[7]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "16" *) 
  CARRY8 \sign_changes_reg[7]_i_1 
       (.CI(1'b0),
        .CI_TOP(1'b0),
        .CO({\sign_changes_reg[7]_i_1_n_0 ,\sign_changes_reg[7]_i_1_n_1 ,\sign_changes_reg[7]_i_1_n_2 ,\sign_changes_reg[7]_i_1_n_3 ,\sign_changes_reg[7]_i_1_n_4 ,\sign_changes_reg[7]_i_1_n_5 ,\sign_changes_reg[7]_i_1_n_6 ,\sign_changes_reg[7]_i_1_n_7 }),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1}),
        .O({\sign_changes_reg[7]_i_1_n_8 ,\sign_changes_reg[7]_i_1_n_9 ,\sign_changes_reg[7]_i_1_n_10 ,\sign_changes_reg[7]_i_1_n_11 ,\sign_changes_reg[7]_i_1_n_12 ,\sign_changes_reg[7]_i_1_n_13 ,\sign_changes_reg[7]_i_1_n_14 ,\sign_changes_reg[7]_i_1_n_15 }),
        .S({status2[7:1],\sign_changes[7]_i_2_n_0 }));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[8] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_15 ),
        .Q(status2[8]),
        .R(last_sign_valid));
  FDRE #(
    .INIT(1'b0)) 
    \sign_changes_reg[9] 
       (.C(aclk),
        .CE(\sign_changes[31]_i_1_n_0 ),
        .D(\sign_changes_reg[15]_i_1_n_14 ),
        .Q(status2[9]),
        .R(last_sign_valid));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 wr_addr0_carry
       (.CI(wr_addr_reg[0]),
        .CI_TOP(1'b0),
        .CO({wr_addr0_carry_n_0,wr_addr0_carry_n_1,wr_addr0_carry_n_2,wr_addr0_carry_n_3,wr_addr0_carry_n_4,wr_addr0_carry_n_5,wr_addr0_carry_n_6,wr_addr0_carry_n_7}),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O(p_0_in__0[8:1]),
        .S(wr_addr_reg[8:1]));
  (* ADDER_THRESHOLD = "35" *) 
  CARRY8 wr_addr0_carry__0
       (.CI(wr_addr0_carry_n_0),
        .CI_TOP(1'b0),
        .CO({NLW_wr_addr0_carry__0_CO_UNCONNECTED[7:3],wr_addr0_carry__0_n_5,wr_addr0_carry__0_n_6,wr_addr0_carry__0_n_7}),
        .DI({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .O({NLW_wr_addr0_carry__0_O_UNCONNECTED[7:4],p_0_in__0[12:9]}),
        .S({1'b0,1'b0,1'b0,1'b0,wr_addr_reg[12:9]}));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT1 #(
    .INIT(2'h1)) 
    \wr_addr[0]_i_1 
       (.I0(wr_addr_reg[0]),
        .O(p_0_in__0[0]));
  LUT2 #(
    .INIT(4'h2)) 
    \wr_addr[12]_i_1 
       (.I0(ctrl_sync[1]),
        .I1(cap_en_d),
        .O(start));
  LUT4 #(
    .INIT(16'h2000)) 
    \wr_addr[12]_i_2 
       (.I0(\wr_addr[12]_i_3_n_0 ),
        .I1(wr_full),
        .I2(active_reg_0),
        .I3(s_axis_tvalid),
        .O(\wr_addr[12]_i_2_n_0 ));
  LUT6 #(
    .INIT(64'hFFFFFFFFBFFFFFFF)) 
    \wr_addr[12]_i_3 
       (.I0(\wr_addr[12]_i_4_n_0 ),
        .I1(wr_addr_reg[4]),
        .I2(wr_addr_reg[3]),
        .I3(wr_addr_reg[6]),
        .I4(wr_addr_reg[5]),
        .I5(\wr_addr[12]_i_5_n_0 ),
        .O(\wr_addr[12]_i_3_n_0 ));
  LUT4 #(
    .INIT(16'h7FFF)) 
    \wr_addr[12]_i_4 
       (.I0(wr_addr_reg[8]),
        .I1(wr_addr_reg[7]),
        .I2(wr_addr_reg[10]),
        .I3(wr_addr_reg[9]),
        .O(\wr_addr[12]_i_4_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT5 #(
    .INIT(32'h7FFFFFFF)) 
    \wr_addr[12]_i_5 
       (.I0(wr_addr_reg[0]),
        .I1(wr_addr_reg[11]),
        .I2(wr_addr_reg[12]),
        .I3(wr_addr_reg[2]),
        .I4(wr_addr_reg[1]),
        .O(\wr_addr[12]_i_5_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[0] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[0]),
        .Q(wr_addr_reg[0]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[10] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[10]),
        .Q(wr_addr_reg[10]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[11] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[11]),
        .Q(wr_addr_reg[11]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[12] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[12]),
        .Q(wr_addr_reg[12]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[1] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[1]),
        .Q(wr_addr_reg[1]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[2] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[2]),
        .Q(wr_addr_reg[2]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[3] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[3]),
        .Q(wr_addr_reg[3]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[4] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[4]),
        .Q(wr_addr_reg[4]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[5] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[5]),
        .Q(wr_addr_reg[5]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[6] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[6]),
        .Q(wr_addr_reg[6]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[7] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[7]),
        .Q(wr_addr_reg[7]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[8] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[8]),
        .Q(wr_addr_reg[8]),
        .R(start));
  FDRE #(
    .INIT(1'b0)) 
    \wr_addr_reg[9] 
       (.C(aclk),
        .CE(\wr_addr[12]_i_2_n_0 ),
        .D(p_0_in__0[9]),
        .Q(wr_addr_reg[9]),
        .R(start));
  LUT6 #(
    .INIT(64'hAAEA0000AAEAAAEA)) 
    wr_full_i_1
       (.I0(wr_full),
        .I1(active_reg_0),
        .I2(s_axis_tvalid),
        .I3(\wr_addr[12]_i_3_n_0 ),
        .I4(cap_en_d),
        .I5(ctrl_sync[1]),
        .O(wr_full_i_1_n_0));
  FDRE #(
    .INIT(1'b0)) 
    wr_full_reg
       (.C(aclk),
        .CE(1'b1),
        .D(wr_full_i_1_n_0),
        .Q(wr_full),
        .R(1'b0));
endmodule
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
