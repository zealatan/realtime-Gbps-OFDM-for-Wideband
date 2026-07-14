-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
-- Date        : Fri Jun 19 11:14:09 2026
-- Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
-- Command     : write_vhdl -force -mode synth_stub
--               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_dac_tone_0/system_dac_tone_0_stub.vhdl
-- Design      : system_dac_tone_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xczu49dr-ffvf1760-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity system_dac_tone_0 is
  Port ( 
    aclk : in STD_LOGIC;
    aresetn : in STD_LOGIC;
    ctrl : in STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_tdata : out STD_LOGIC_VECTOR ( 255 downto 0 );
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );

end system_dac_tone_0;

architecture stub of system_dac_tone_0 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "aclk,aresetn,ctrl[31:0],m_axis_tdata[255:0],m_axis_tvalid,m_axis_tready";
attribute X_CORE_INFO : string;
attribute X_CORE_INFO of stub : architecture is "zcu216_dac_tone_axis,Vivado 2021.1_AR76780";
begin
end;
