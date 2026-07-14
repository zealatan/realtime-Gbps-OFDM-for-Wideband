-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
-- Date        : Fri Jun 19 11:14:14 2026
-- Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_adc_cap_0/system_adc_cap_0_stub.vhdl
-- Design      : system_adc_cap_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xczu49dr-ffvf1760-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity system_adc_cap_0 is
  Port ( 
    aclk : in STD_LOGIC;
    aresetn : in STD_LOGIC;
    ctrl : in STD_LOGIC_VECTOR ( 31 downto 0 );
    s_axis_tdata : in STD_LOGIC_VECTOR ( 127 downto 0 );
    s_axis_tvalid : in STD_LOGIC;
    s_axis_tready : out STD_LOGIC;
    status0 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status1 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status2 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status3 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status_capture : out STD_LOGIC_VECTOR ( 31 downto 0 )
  );

end system_adc_cap_0;

architecture stub of system_adc_cap_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aclk,aresetn,ctrl[31:0],s_axis_tdata[127:0],s_axis_tvalid,s_axis_tready,status0[31:0],status1[31:0],status2[31:0],status3[31:0],status_capture[31:0]";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "zcu216_adc_capture,Vivado 2021.1_AR76780";
begin
end;
