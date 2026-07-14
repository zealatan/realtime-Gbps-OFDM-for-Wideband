// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
// Date        : Fri Jun 19 11:14:09 2026
// Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
// Command     : write_verilog -force -mode funcsim -rename_top decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix -prefix
//               decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_ system_dac_tone_0_sim_netlist.v
// Design      : system_dac_tone_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xczu49dr-ffvf1760-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "system_dac_tone_0,zcu216_dac_tone_axis,{}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) (* IP_DEFINITION_SOURCE = "module_ref" *) 
(* X_CORE_INFO = "zcu216_dac_tone_axis,Vivado 2021.1_AR76780" *) 
(* NotValidForBitStream *)
module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix
   (aclk,
    aresetn,
    ctrl,
    m_axis_tdata,
    m_axis_tvalid,
    m_axis_tready);
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 430080000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_dac3, INSERT_VIP 0" *) input aclk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input aresetn;
  input [31:0]ctrl;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TDATA" *) output [255:0]m_axis_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TVALID" *) output m_axis_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 m_axis TREADY" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 32, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 430080000, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_dac3, LAYERED_METADATA undef, INSERT_VIP 0" *) input m_axis_tready;

  wire aclk;
  wire aresetn;
  wire [31:0]ctrl;
  wire [15:0]\^m_axis_tdata ;
  wire m_axis_tready;
  wire m_axis_tvalid;

  assign m_axis_tdata[255:240] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[239:224] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[223:208] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[207:192] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[191:176] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[175:160] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[159:144] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[143:128] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[127:112] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[111:96] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[95:80] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[79:64] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[63:48] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[47:32] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[31:16] = \^m_axis_tdata [15:0];
  assign m_axis_tdata[15:0] = \^m_axis_tdata [15:0];
  decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_zcu216_dac_tone_axis inst
       (.aclk(aclk),
        .aresetn(aresetn),
        .ctrl(ctrl),
        .m_axis_tdata(\^m_axis_tdata [15:1]),
        .m_axis_tready(m_axis_tready),
        .out({\^m_axis_tdata [0],m_axis_tvalid}));
endmodule

module decalper_eb_ot_sdeen_pot_pi_dehcac_xnilix_zcu216_dac_tone_axis
   (out,
    m_axis_tdata,
    aresetn,
    ctrl,
    aclk,
    m_axis_tready);
  output [1:0]out;
  output [14:0]m_axis_tdata;
  input aresetn;
  input [31:0]ctrl;
  input aclk;
  input m_axis_tready;

  wire aclk;
  wire aresetn;
  wire [31:0]ctrl;
  (* async_reg = "true" *) wire [31:0]ctrl_meta;
  wire \ctrl_meta[31]_i_1_n_0 ;
  (* async_reg = "true" *) wire [31:0]ctrl_sync;
  wire [14:0]m_axis_tdata;
  wire \m_axis_tdata[10]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[10]_INST_0_i_2_n_0 ;
  wire \m_axis_tdata[11]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[12]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[13]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[15]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[15]_INST_0_i_2_n_0 ;
  wire \m_axis_tdata[5]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[6]_INST_0_i_1_n_0 ;
  wire \m_axis_tdata[9]_INST_0_i_1_n_0 ;
  wire m_axis_tready;
  wire [1:0]p_0_in;
  wire \phase[1]_i_1_n_0 ;
  wire [1:1]phase_reg;
  wire \phase_reg_n_0_[0] ;

  assign out[1] = ctrl_sync[16];
  assign out[0] = ctrl_sync[0];
  LUT1 #(
    .INIT(2'h1)) 
    \ctrl_meta[31]_i_1 
       (.I0(aresetn),
        .O(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[0] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[0]),
        .Q(ctrl_meta[0]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[10] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[10]),
        .Q(ctrl_meta[10]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[11] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[11]),
        .Q(ctrl_meta[11]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[12] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[12]),
        .Q(ctrl_meta[12]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[13] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[13]),
        .Q(ctrl_meta[13]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[14] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[14]),
        .Q(ctrl_meta[14]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[15] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[15]),
        .Q(ctrl_meta[15]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[16] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[16]),
        .Q(ctrl_meta[16]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[17] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[17]),
        .Q(ctrl_meta[17]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[18] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[18]),
        .Q(ctrl_meta[18]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[19] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[19]),
        .Q(ctrl_meta[19]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[1] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[1]),
        .Q(ctrl_meta[1]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[20] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[20]),
        .Q(ctrl_meta[20]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[21] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[21]),
        .Q(ctrl_meta[21]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[22] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[22]),
        .Q(ctrl_meta[22]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[23] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[23]),
        .Q(ctrl_meta[23]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[24] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[24]),
        .Q(ctrl_meta[24]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[25] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[25]),
        .Q(ctrl_meta[25]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[26] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[26]),
        .Q(ctrl_meta[26]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[27] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[27]),
        .Q(ctrl_meta[27]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[28] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[28]),
        .Q(ctrl_meta[28]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[29] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[29]),
        .Q(ctrl_meta[29]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[2] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[2]),
        .Q(ctrl_meta[2]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[30] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[30]),
        .Q(ctrl_meta[30]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[31] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[31]),
        .Q(ctrl_meta[31]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[3] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[3]),
        .Q(ctrl_meta[3]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[4] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[4]),
        .Q(ctrl_meta[4]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[5] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[5]),
        .Q(ctrl_meta[5]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[6] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[6]),
        .Q(ctrl_meta[6]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[7] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[7]),
        .Q(ctrl_meta[7]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[8] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[8]),
        .Q(ctrl_meta[8]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_meta_reg[9] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl[9]),
        .Q(ctrl_meta[9]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[0] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[0]),
        .Q(ctrl_sync[0]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[10] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[10]),
        .Q(ctrl_sync[10]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[11] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[11]),
        .Q(ctrl_sync[11]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[12] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[12]),
        .Q(ctrl_sync[12]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[13] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[13]),
        .Q(ctrl_sync[13]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[14] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[14]),
        .Q(ctrl_sync[14]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[15] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[15]),
        .Q(ctrl_sync[15]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[16] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[16]),
        .Q(ctrl_sync[16]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[17] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[17]),
        .Q(ctrl_sync[17]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[18] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[18]),
        .Q(ctrl_sync[18]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[19] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[19]),
        .Q(ctrl_sync[19]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[1] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[1]),
        .Q(ctrl_sync[1]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[20] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[20]),
        .Q(ctrl_sync[20]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[21] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[21]),
        .Q(ctrl_sync[21]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[22] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[22]),
        .Q(ctrl_sync[22]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[23] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[23]),
        .Q(ctrl_sync[23]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[24] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[24]),
        .Q(ctrl_sync[24]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[25] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[25]),
        .Q(ctrl_sync[25]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[26] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[26]),
        .Q(ctrl_sync[26]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[27] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[27]),
        .Q(ctrl_sync[27]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[28] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[28]),
        .Q(ctrl_sync[28]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[29] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[29]),
        .Q(ctrl_sync[29]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[2] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[2]),
        .Q(ctrl_sync[2]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[30] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[30]),
        .Q(ctrl_sync[30]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[31] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[31]),
        .Q(ctrl_sync[31]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[3] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[3]),
        .Q(ctrl_sync[3]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[4] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[4]),
        .Q(ctrl_sync[4]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[5] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[5]),
        .Q(ctrl_sync[5]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[6] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[6]),
        .Q(ctrl_sync[6]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[7] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[7]),
        .Q(ctrl_sync[7]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[8] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[8]),
        .Q(ctrl_sync[8]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  (* ASYNC_REG *) 
  (* KEEP = "yes" *) 
  FDRE #(
    .INIT(1'b0)) 
    \ctrl_sync_reg[9] 
       (.C(aclk),
        .CE(1'b1),
        .D(ctrl_meta[9]),
        .Q(ctrl_sync[9]),
        .R(\ctrl_meta[31]_i_1_n_0 ));
  LUT4 #(
    .INIT(16'h8F70)) 
    \m_axis_tdata[10]_INST_0 
       (.I0(\m_axis_tdata[10]_INST_0_i_1_n_0 ),
        .I1(\m_axis_tdata[10]_INST_0_i_2_n_0 ),
        .I2(phase_reg),
        .I3(ctrl_sync[26]),
        .O(m_axis_tdata[9]));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \m_axis_tdata[10]_INST_0_i_1 
       (.I0(ctrl_sync[27]),
        .I1(ctrl_sync[29]),
        .I2(ctrl_sync[30]),
        .I3(ctrl_sync[31]),
        .I4(ctrl_sync[28]),
        .I5(ctrl_sync[26]),
        .O(\m_axis_tdata[10]_INST_0_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h00000001)) 
    \m_axis_tdata[10]_INST_0_i_2 
       (.I0(ctrl_sync[23]),
        .I1(ctrl_sync[22]),
        .I2(\m_axis_tdata[6]_INST_0_i_1_n_0 ),
        .I3(ctrl_sync[24]),
        .I4(ctrl_sync[25]),
        .O(\m_axis_tdata[10]_INST_0_i_2_n_0 ));
  LUT4 #(
    .INIT(16'h8F70)) 
    \m_axis_tdata[11]_INST_0 
       (.I0(\m_axis_tdata[11]_INST_0_i_1_n_0 ),
        .I1(\m_axis_tdata[15]_INST_0_i_1_n_0 ),
        .I2(phase_reg),
        .I3(ctrl_sync[27]),
        .O(m_axis_tdata[10]));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \m_axis_tdata[11]_INST_0_i_1 
       (.I0(ctrl_sync[28]),
        .I1(ctrl_sync[31]),
        .I2(ctrl_sync[30]),
        .I3(ctrl_sync[29]),
        .I4(ctrl_sync[27]),
        .O(\m_axis_tdata[11]_INST_0_i_1_n_0 ));
  LUT5 #(
    .INIT(32'h08FFF700)) 
    \m_axis_tdata[12]_INST_0 
       (.I0(\m_axis_tdata[12]_INST_0_i_1_n_0 ),
        .I1(\m_axis_tdata[15]_INST_0_i_1_n_0 ),
        .I2(ctrl_sync[27]),
        .I3(phase_reg),
        .I4(ctrl_sync[28]),
        .O(m_axis_tdata[11]));
  LUT4 #(
    .INIT(16'hFFFE)) 
    \m_axis_tdata[12]_INST_0_i_1 
       (.I0(ctrl_sync[29]),
        .I1(ctrl_sync[30]),
        .I2(ctrl_sync[31]),
        .I3(ctrl_sync[28]),
        .O(\m_axis_tdata[12]_INST_0_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0020FFFFFFDF0000)) 
    \m_axis_tdata[13]_INST_0 
       (.I0(\m_axis_tdata[15]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[27]),
        .I2(\m_axis_tdata[13]_INST_0_i_1_n_0 ),
        .I3(ctrl_sync[28]),
        .I4(phase_reg),
        .I5(ctrl_sync[29]),
        .O(m_axis_tdata[12]));
  LUT3 #(
    .INIT(8'hFE)) 
    \m_axis_tdata[13]_INST_0_i_1 
       (.I0(ctrl_sync[31]),
        .I1(ctrl_sync[30]),
        .I2(ctrl_sync[29]),
        .O(\m_axis_tdata[13]_INST_0_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h2020FFFFDFFF0000)) 
    \m_axis_tdata[14]_INST_0 
       (.I0(\m_axis_tdata[15]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[27]),
        .I2(\m_axis_tdata[15]_INST_0_i_2_n_0 ),
        .I3(ctrl_sync[31]),
        .I4(phase_reg),
        .I5(ctrl_sync[30]),
        .O(m_axis_tdata[13]));
  LUT6 #(
    .INIT(64'h0020FFFFFFFF0000)) 
    \m_axis_tdata[15]_INST_0 
       (.I0(\m_axis_tdata[15]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[27]),
        .I2(\m_axis_tdata[15]_INST_0_i_2_n_0 ),
        .I3(ctrl_sync[30]),
        .I4(phase_reg),
        .I5(ctrl_sync[31]),
        .O(m_axis_tdata[14]));
  LUT6 #(
    .INIT(64'h0000000000000001)) 
    \m_axis_tdata[15]_INST_0_i_1 
       (.I0(ctrl_sync[25]),
        .I1(ctrl_sync[24]),
        .I2(\m_axis_tdata[6]_INST_0_i_1_n_0 ),
        .I3(ctrl_sync[22]),
        .I4(ctrl_sync[23]),
        .I5(ctrl_sync[26]),
        .O(\m_axis_tdata[15]_INST_0_i_1_n_0 ));
  LUT2 #(
    .INIT(4'h1)) 
    \m_axis_tdata[15]_INST_0_i_2 
       (.I0(ctrl_sync[28]),
        .I1(ctrl_sync[29]),
        .O(\m_axis_tdata[15]_INST_0_i_2_n_0 ));
  LUT3 #(
    .INIT(8'h78)) 
    \m_axis_tdata[1]_INST_0 
       (.I0(ctrl_sync[16]),
        .I1(phase_reg),
        .I2(ctrl_sync[17]),
        .O(m_axis_tdata[0]));
  LUT4 #(
    .INIT(16'h1FE0)) 
    \m_axis_tdata[2]_INST_0 
       (.I0(ctrl_sync[17]),
        .I1(ctrl_sync[16]),
        .I2(phase_reg),
        .I3(ctrl_sync[18]),
        .O(m_axis_tdata[1]));
  LUT5 #(
    .INIT(32'h01FFFE00)) 
    \m_axis_tdata[3]_INST_0 
       (.I0(ctrl_sync[18]),
        .I1(ctrl_sync[16]),
        .I2(ctrl_sync[17]),
        .I3(phase_reg),
        .I4(ctrl_sync[19]),
        .O(m_axis_tdata[2]));
  LUT6 #(
    .INIT(64'h0001FFFFFFFE0000)) 
    \m_axis_tdata[4]_INST_0 
       (.I0(ctrl_sync[19]),
        .I1(ctrl_sync[17]),
        .I2(ctrl_sync[16]),
        .I3(ctrl_sync[18]),
        .I4(phase_reg),
        .I5(ctrl_sync[20]),
        .O(m_axis_tdata[3]));
  LUT3 #(
    .INIT(8'h78)) 
    \m_axis_tdata[5]_INST_0 
       (.I0(\m_axis_tdata[5]_INST_0_i_1_n_0 ),
        .I1(phase_reg),
        .I2(ctrl_sync[21]),
        .O(m_axis_tdata[4]));
  LUT5 #(
    .INIT(32'hFFFFFFFE)) 
    \m_axis_tdata[5]_INST_0_i_1 
       (.I0(ctrl_sync[19]),
        .I1(ctrl_sync[17]),
        .I2(ctrl_sync[16]),
        .I3(ctrl_sync[18]),
        .I4(ctrl_sync[20]),
        .O(\m_axis_tdata[5]_INST_0_i_1_n_0 ));
  LUT3 #(
    .INIT(8'h78)) 
    \m_axis_tdata[6]_INST_0 
       (.I0(\m_axis_tdata[6]_INST_0_i_1_n_0 ),
        .I1(phase_reg),
        .I2(ctrl_sync[22]),
        .O(m_axis_tdata[5]));
  LUT6 #(
    .INIT(64'hFFFFFFFFFFFFFFFE)) 
    \m_axis_tdata[6]_INST_0_i_1 
       (.I0(ctrl_sync[20]),
        .I1(ctrl_sync[18]),
        .I2(ctrl_sync[16]),
        .I3(ctrl_sync[17]),
        .I4(ctrl_sync[19]),
        .I5(ctrl_sync[21]),
        .O(\m_axis_tdata[6]_INST_0_i_1_n_0 ));
  LUT6 #(
    .INIT(64'h0FF0FF000FF0FF11)) 
    \m_axis_tdata[7]_INST_0 
       (.I0(\m_axis_tdata[10]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[25]),
        .I2(phase_reg),
        .I3(ctrl_sync[23]),
        .I4(\m_axis_tdata[9]_INST_0_i_1_n_0 ),
        .I5(ctrl_sync[24]),
        .O(m_axis_tdata[6]));
  LUT6 #(
    .INIT(64'h000FFFFFFFF10000)) 
    \m_axis_tdata[8]_INST_0 
       (.I0(\m_axis_tdata[10]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[25]),
        .I2(\m_axis_tdata[9]_INST_0_i_1_n_0 ),
        .I3(ctrl_sync[23]),
        .I4(phase_reg),
        .I5(ctrl_sync[24]),
        .O(m_axis_tdata[7]));
  LUT6 #(
    .INIT(64'h3333333DCCCCCCCC)) 
    \m_axis_tdata[9]_INST_0 
       (.I0(\m_axis_tdata[10]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[25]),
        .I2(ctrl_sync[24]),
        .I3(\m_axis_tdata[9]_INST_0_i_1_n_0 ),
        .I4(ctrl_sync[23]),
        .I5(phase_reg),
        .O(m_axis_tdata[8]));
  LUT2 #(
    .INIT(4'hE)) 
    \m_axis_tdata[9]_INST_0_i_1 
       (.I0(\m_axis_tdata[6]_INST_0_i_1_n_0 ),
        .I1(ctrl_sync[22]),
        .O(\m_axis_tdata[9]_INST_0_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT1 #(
    .INIT(2'h1)) 
    \phase[0]_i_1 
       (.I0(\phase_reg_n_0_[0] ),
        .O(p_0_in[0]));
  LUT2 #(
    .INIT(4'h7)) 
    \phase[1]_i_1 
       (.I0(ctrl_sync[0]),
        .I1(aresetn),
        .O(\phase[1]_i_1_n_0 ));
  (* SOFT_HLUTNM = "soft_lutpair0" *) 
  LUT2 #(
    .INIT(4'h6)) 
    \phase[1]_i_2 
       (.I0(\phase_reg_n_0_[0] ),
        .I1(phase_reg),
        .O(p_0_in[1]));
  FDRE #(
    .INIT(1'b0)) 
    \phase_reg[0] 
       (.C(aclk),
        .CE(m_axis_tready),
        .D(p_0_in[0]),
        .Q(\phase_reg_n_0_[0] ),
        .R(\phase[1]_i_1_n_0 ));
  FDRE #(
    .INIT(1'b0)) 
    \phase_reg[1] 
       (.C(aclk),
        .CE(m_axis_tready),
        .D(p_0_in[1]),
        .Q(phase_reg),
        .R(\phase[1]_i_1_n_0 ));
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
