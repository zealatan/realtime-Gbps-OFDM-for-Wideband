-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
-- Date        : Fri Jun 19 11:15:17 2026
-- Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_usp_rf_data_converter_0_0/system_usp_rf_data_converter_0_0_stub.vhdl
-- Design      : system_usp_rf_data_converter_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xczu49dr-ffvf1760-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity system_usp_rf_data_converter_0_0 is
  Port ( 
    s_axi_aclk : in STD_LOGIC;
    s_axi_aresetn : in STD_LOGIC;
    s_axi_awaddr : in STD_LOGIC_VECTOR ( 17 downto 0 );
    s_axi_awvalid : in STD_LOGIC;
    s_axi_awready : out STD_LOGIC;
    s_axi_wdata : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axi_wstrb : in STD_LOGIC_VECTOR ( 3 downto 0 );
    s_axi_wvalid : in STD_LOGIC;
    s_axi_wready : out STD_LOGIC;
    s_axi_bresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    s_axi_bvalid : out STD_LOGIC;
    s_axi_bready : in STD_LOGIC;
    s_axi_araddr : in STD_LOGIC_VECTOR ( 17 downto 0 );
    s_axi_arvalid : in STD_LOGIC;
    s_axi_arready : out STD_LOGIC;
    s_axi_rdata : out STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axi_rresp : out STD_LOGIC_VECTOR ( 1 downto 0 );
    s_axi_rvalid : out STD_LOGIC;
    s_axi_rready : in STD_LOGIC;
    sysref_in_p : in STD_LOGIC;
    sysref_in_n : in STD_LOGIC;
    adc2_clk_p : in STD_LOGIC;
    adc2_clk_n : in STD_LOGIC;
    clk_adc2 : out STD_LOGIC;
    m2_axis_aclk : in STD_LOGIC;
    m2_axis_aresetn : in STD_LOGIC;
    vin20_p : in STD_LOGIC;
    vin20_n : in STD_LOGIC;
    m20_axis_tdata : out STD_LOGIC_VECTOR ( 127 downto 0 );
    m20_axis_tvalid : out STD_LOGIC;
    m20_axis_tready : in STD_LOGIC;
    dac2_clk_p : in STD_LOGIC;
    dac2_clk_n : in STD_LOGIC;
    clk_dac2 : out STD_LOGIC;
    s2_axis_aclk : in STD_LOGIC;
    s2_axis_aresetn : in STD_LOGIC;
    clk_dac3 : out STD_LOGIC;
    s3_axis_aclk : in STD_LOGIC;
    s3_axis_aresetn : in STD_LOGIC;
    vout20_p : out STD_LOGIC;
    vout20_n : out STD_LOGIC;
    vout32_p : out STD_LOGIC;
    vout32_n : out STD_LOGIC;
    s20_axis_tdata : in STD_LOGIC_VECTOR ( 255 downto 0 );
    s20_axis_tvalid : in STD_LOGIC;
    s20_axis_tready : out STD_LOGIC;
    s32_axis_tdata : in STD_LOGIC_VECTOR ( 255 downto 0 );
    s32_axis_tvalid : in STD_LOGIC;
    s32_axis_tready : out STD_LOGIC;
    irq : out STD_LOGIC
  );

end system_usp_rf_data_converter_0_0;

architecture stub of system_usp_rf_data_converter_0_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "s_axi_aclk,s_axi_aresetn,s_axi_awaddr[17:0],s_axi_awvalid,s_axi_awready,s_axi_wdata[31:0],s_axi_wstrb[3:0],s_axi_wvalid,s_axi_wready,s_axi_bresp[1:0],s_axi_bvalid,s_axi_bready,s_axi_araddr[17:0],s_axi_arvalid,s_axi_arready,s_axi_rdata[31:0],s_axi_rresp[1:0],s_axi_rvalid,s_axi_rready,sysref_in_p,sysref_in_n,adc2_clk_p,adc2_clk_n,clk_adc2,m2_axis_aclk,m2_axis_aresetn,vin20_p,vin20_n,m20_axis_tdata[127:0],m20_axis_tvalid,m20_axis_tready,dac2_clk_p,dac2_clk_n,clk_dac2,s2_axis_aclk,s2_axis_aresetn,clk_dac3,s3_axis_aclk,s3_axis_aresetn,vout20_p,vout20_n,vout32_p,vout32_n,s20_axis_tdata[255:0],s20_axis_tvalid,s20_axis_tready,s32_axis_tdata[255:0],s32_axis_tvalid,s32_axis_tready,irq";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "usp_rf_data_converter_v2_5_0,Vivado 2021.1_AR76780";
begin
end;
