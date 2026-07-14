-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
-- Date        : Fri Jun 19 11:14:09 2026
-- Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
-- Command     : write_vhdl -force -mode funcsim
--               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_dac_tone_0/system_dac_tone_0_sim_netlist.vhdl
-- Design      : system_dac_tone_0
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xczu49dr-ffvf1760-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity system_dac_tone_0_zcu216_dac_tone_axis is
  port (
    \out\ : out STD_LOGIC_VECTOR ( 1 downto 0 );
    m_axis_tdata : out STD_LOGIC_VECTOR ( 14 downto 0 );
    aresetn : in STD_LOGIC;
    ctrl : in STD_LOGIC_VECTOR ( 31 downto 0 );
    aclk : in STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );
  attribute ORIG_REF_NAME : string;
  attribute ORIG_REF_NAME of system_dac_tone_0_zcu216_dac_tone_axis : entity is "zcu216_dac_tone_axis";
end system_dac_tone_0_zcu216_dac_tone_axis;

architecture STRUCTURE of system_dac_tone_0_zcu216_dac_tone_axis is
  signal ctrl_meta : STD_LOGIC_VECTOR ( 31 downto 0 );
  attribute async_reg : string;
  attribute async_reg of ctrl_meta : signal is "true";
  signal \ctrl_meta[31]_i_1_n_0\ : STD_LOGIC;
  signal ctrl_sync : STD_LOGIC_VECTOR ( 31 downto 0 );
  attribute async_reg of ctrl_sync : signal is "true";
  signal \m_axis_tdata[10]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[10]_INST_0_i_2_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[11]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[12]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[13]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[15]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[15]_INST_0_i_2_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[5]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[6]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal \m_axis_tdata[9]_INST_0_i_1_n_0\ : STD_LOGIC;
  signal p_0_in : STD_LOGIC_VECTOR ( 1 downto 0 );
  signal \phase[1]_i_1_n_0\ : STD_LOGIC;
  signal phase_reg : STD_LOGIC_VECTOR ( 1 to 1 );
  signal \phase_reg_n_0_[0]\ : STD_LOGIC;
  attribute ASYNC_REG_boolean : boolean;
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[0]\ : label is std.standard.true;
  attribute KEEP : string;
  attribute KEEP of \ctrl_meta_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[10]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[10]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[11]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[11]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[12]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[12]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[13]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[13]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[14]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[14]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[15]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[15]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[16]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[16]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[17]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[17]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[18]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[18]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[19]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[19]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[1]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[20]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[20]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[21]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[21]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[22]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[22]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[23]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[23]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[24]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[24]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[25]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[25]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[26]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[26]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[27]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[27]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[28]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[28]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[29]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[29]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[2]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[30]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[30]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[31]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[31]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[3]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[4]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[5]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[6]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[7]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[7]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[8]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[8]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_meta_reg[9]\ : label is std.standard.true;
  attribute KEEP of \ctrl_meta_reg[9]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[0]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[0]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[10]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[10]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[11]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[11]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[12]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[12]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[13]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[13]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[14]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[14]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[15]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[15]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[16]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[16]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[17]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[17]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[18]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[18]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[19]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[19]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[1]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[1]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[20]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[20]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[21]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[21]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[22]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[22]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[23]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[23]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[24]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[24]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[25]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[25]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[26]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[26]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[27]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[27]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[28]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[28]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[29]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[29]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[2]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[2]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[30]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[30]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[31]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[31]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[3]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[3]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[4]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[4]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[5]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[5]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[6]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[6]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[7]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[7]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[8]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[8]\ : label is "yes";
  attribute ASYNC_REG_boolean of \ctrl_sync_reg[9]\ : label is std.standard.true;
  attribute KEEP of \ctrl_sync_reg[9]\ : label is "yes";
  attribute SOFT_HLUTNM : string;
  attribute SOFT_HLUTNM of \phase[0]_i_1\ : label is "soft_lutpair0";
  attribute SOFT_HLUTNM of \phase[1]_i_2\ : label is "soft_lutpair0";
begin
  \out\(1) <= ctrl_sync(16);
  \out\(0) <= ctrl_sync(0);
\ctrl_meta[31]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => aresetn,
      O => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(0),
      Q => ctrl_meta(0),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(10),
      Q => ctrl_meta(10),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(11),
      Q => ctrl_meta(11),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(12),
      Q => ctrl_meta(12),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(13),
      Q => ctrl_meta(13),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(14),
      Q => ctrl_meta(14),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(15),
      Q => ctrl_meta(15),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[16]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(16),
      Q => ctrl_meta(16),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[17]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(17),
      Q => ctrl_meta(17),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[18]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(18),
      Q => ctrl_meta(18),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[19]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(19),
      Q => ctrl_meta(19),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(1),
      Q => ctrl_meta(1),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[20]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(20),
      Q => ctrl_meta(20),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[21]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(21),
      Q => ctrl_meta(21),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[22]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(22),
      Q => ctrl_meta(22),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[23]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(23),
      Q => ctrl_meta(23),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[24]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(24),
      Q => ctrl_meta(24),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[25]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(25),
      Q => ctrl_meta(25),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[26]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(26),
      Q => ctrl_meta(26),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[27]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(27),
      Q => ctrl_meta(27),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[28]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(28),
      Q => ctrl_meta(28),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[29]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(29),
      Q => ctrl_meta(29),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(2),
      Q => ctrl_meta(2),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[30]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(30),
      Q => ctrl_meta(30),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[31]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(31),
      Q => ctrl_meta(31),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(3),
      Q => ctrl_meta(3),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(4),
      Q => ctrl_meta(4),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(5),
      Q => ctrl_meta(5),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(6),
      Q => ctrl_meta(6),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(7),
      Q => ctrl_meta(7),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(8),
      Q => ctrl_meta(8),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_meta_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl(9),
      Q => ctrl_meta(9),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(0),
      Q => ctrl_sync(0),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(10),
      Q => ctrl_sync(10),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(11),
      Q => ctrl_sync(11),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(12),
      Q => ctrl_sync(12),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(13),
      Q => ctrl_sync(13),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(14),
      Q => ctrl_sync(14),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(15),
      Q => ctrl_sync(15),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[16]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(16),
      Q => ctrl_sync(16),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[17]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(17),
      Q => ctrl_sync(17),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[18]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(18),
      Q => ctrl_sync(18),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[19]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(19),
      Q => ctrl_sync(19),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(1),
      Q => ctrl_sync(1),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[20]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(20),
      Q => ctrl_sync(20),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[21]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(21),
      Q => ctrl_sync(21),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[22]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(22),
      Q => ctrl_sync(22),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[23]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(23),
      Q => ctrl_sync(23),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[24]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(24),
      Q => ctrl_sync(24),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[25]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(25),
      Q => ctrl_sync(25),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[26]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(26),
      Q => ctrl_sync(26),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[27]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(27),
      Q => ctrl_sync(27),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[28]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(28),
      Q => ctrl_sync(28),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[29]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(29),
      Q => ctrl_sync(29),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(2),
      Q => ctrl_sync(2),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[30]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(30),
      Q => ctrl_sync(30),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[31]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(31),
      Q => ctrl_sync(31),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(3),
      Q => ctrl_sync(3),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(4),
      Q => ctrl_sync(4),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(5),
      Q => ctrl_sync(5),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(6),
      Q => ctrl_sync(6),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(7),
      Q => ctrl_sync(7),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(8),
      Q => ctrl_sync(8),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\ctrl_sync_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_meta(9),
      Q => ctrl_sync(9),
      R => \ctrl_meta[31]_i_1_n_0\
    );
\m_axis_tdata[10]_INST_0\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8F70"
    )
        port map (
      I0 => \m_axis_tdata[10]_INST_0_i_1_n_0\,
      I1 => \m_axis_tdata[10]_INST_0_i_2_n_0\,
      I2 => phase_reg(1),
      I3 => ctrl_sync(26),
      O => m_axis_tdata(9)
    );
\m_axis_tdata[10]_INST_0_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFFFFFFFFE"
    )
        port map (
      I0 => ctrl_sync(27),
      I1 => ctrl_sync(29),
      I2 => ctrl_sync(30),
      I3 => ctrl_sync(31),
      I4 => ctrl_sync(28),
      I5 => ctrl_sync(26),
      O => \m_axis_tdata[10]_INST_0_i_1_n_0\
    );
\m_axis_tdata[10]_INST_0_i_2\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"00000001"
    )
        port map (
      I0 => ctrl_sync(23),
      I1 => ctrl_sync(22),
      I2 => \m_axis_tdata[6]_INST_0_i_1_n_0\,
      I3 => ctrl_sync(24),
      I4 => ctrl_sync(25),
      O => \m_axis_tdata[10]_INST_0_i_2_n_0\
    );
\m_axis_tdata[11]_INST_0\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8F70"
    )
        port map (
      I0 => \m_axis_tdata[11]_INST_0_i_1_n_0\,
      I1 => \m_axis_tdata[15]_INST_0_i_1_n_0\,
      I2 => phase_reg(1),
      I3 => ctrl_sync(27),
      O => m_axis_tdata(10)
    );
\m_axis_tdata[11]_INST_0_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => ctrl_sync(28),
      I1 => ctrl_sync(31),
      I2 => ctrl_sync(30),
      I3 => ctrl_sync(29),
      I4 => ctrl_sync(27),
      O => \m_axis_tdata[11]_INST_0_i_1_n_0\
    );
\m_axis_tdata[12]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"08FFF700"
    )
        port map (
      I0 => \m_axis_tdata[12]_INST_0_i_1_n_0\,
      I1 => \m_axis_tdata[15]_INST_0_i_1_n_0\,
      I2 => ctrl_sync(27),
      I3 => phase_reg(1),
      I4 => ctrl_sync(28),
      O => m_axis_tdata(11)
    );
\m_axis_tdata[12]_INST_0_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => ctrl_sync(29),
      I1 => ctrl_sync(30),
      I2 => ctrl_sync(31),
      I3 => ctrl_sync(28),
      O => \m_axis_tdata[12]_INST_0_i_1_n_0\
    );
\m_axis_tdata[13]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0020FFFFFFDF0000"
    )
        port map (
      I0 => \m_axis_tdata[15]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(27),
      I2 => \m_axis_tdata[13]_INST_0_i_1_n_0\,
      I3 => ctrl_sync(28),
      I4 => phase_reg(1),
      I5 => ctrl_sync(29),
      O => m_axis_tdata(12)
    );
\m_axis_tdata[13]_INST_0_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"FE"
    )
        port map (
      I0 => ctrl_sync(31),
      I1 => ctrl_sync(30),
      I2 => ctrl_sync(29),
      O => \m_axis_tdata[13]_INST_0_i_1_n_0\
    );
\m_axis_tdata[14]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"2020FFFFDFFF0000"
    )
        port map (
      I0 => \m_axis_tdata[15]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(27),
      I2 => \m_axis_tdata[15]_INST_0_i_2_n_0\,
      I3 => ctrl_sync(31),
      I4 => phase_reg(1),
      I5 => ctrl_sync(30),
      O => m_axis_tdata(13)
    );
\m_axis_tdata[15]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0020FFFFFFFF0000"
    )
        port map (
      I0 => \m_axis_tdata[15]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(27),
      I2 => \m_axis_tdata[15]_INST_0_i_2_n_0\,
      I3 => ctrl_sync(30),
      I4 => phase_reg(1),
      I5 => ctrl_sync(31),
      O => m_axis_tdata(14)
    );
\m_axis_tdata[15]_INST_0_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => ctrl_sync(25),
      I1 => ctrl_sync(24),
      I2 => \m_axis_tdata[6]_INST_0_i_1_n_0\,
      I3 => ctrl_sync(22),
      I4 => ctrl_sync(23),
      I5 => ctrl_sync(26),
      O => \m_axis_tdata[15]_INST_0_i_1_n_0\
    );
\m_axis_tdata[15]_INST_0_i_2\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => ctrl_sync(28),
      I1 => ctrl_sync(29),
      O => \m_axis_tdata[15]_INST_0_i_2_n_0\
    );
\m_axis_tdata[1]_INST_0\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => ctrl_sync(16),
      I1 => phase_reg(1),
      I2 => ctrl_sync(17),
      O => m_axis_tdata(0)
    );
\m_axis_tdata[2]_INST_0\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"1FE0"
    )
        port map (
      I0 => ctrl_sync(17),
      I1 => ctrl_sync(16),
      I2 => phase_reg(1),
      I3 => ctrl_sync(18),
      O => m_axis_tdata(1)
    );
\m_axis_tdata[3]_INST_0\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"01FFFE00"
    )
        port map (
      I0 => ctrl_sync(18),
      I1 => ctrl_sync(16),
      I2 => ctrl_sync(17),
      I3 => phase_reg(1),
      I4 => ctrl_sync(19),
      O => m_axis_tdata(2)
    );
\m_axis_tdata[4]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0001FFFFFFFE0000"
    )
        port map (
      I0 => ctrl_sync(19),
      I1 => ctrl_sync(17),
      I2 => ctrl_sync(16),
      I3 => ctrl_sync(18),
      I4 => phase_reg(1),
      I5 => ctrl_sync(20),
      O => m_axis_tdata(3)
    );
\m_axis_tdata[5]_INST_0\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => \m_axis_tdata[5]_INST_0_i_1_n_0\,
      I1 => phase_reg(1),
      I2 => ctrl_sync(21),
      O => m_axis_tdata(4)
    );
\m_axis_tdata[5]_INST_0_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => ctrl_sync(19),
      I1 => ctrl_sync(17),
      I2 => ctrl_sync(16),
      I3 => ctrl_sync(18),
      I4 => ctrl_sync(20),
      O => \m_axis_tdata[5]_INST_0_i_1_n_0\
    );
\m_axis_tdata[6]_INST_0\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => \m_axis_tdata[6]_INST_0_i_1_n_0\,
      I1 => phase_reg(1),
      I2 => ctrl_sync(22),
      O => m_axis_tdata(5)
    );
\m_axis_tdata[6]_INST_0_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFFFFFFFFE"
    )
        port map (
      I0 => ctrl_sync(20),
      I1 => ctrl_sync(18),
      I2 => ctrl_sync(16),
      I3 => ctrl_sync(17),
      I4 => ctrl_sync(19),
      I5 => ctrl_sync(21),
      O => \m_axis_tdata[6]_INST_0_i_1_n_0\
    );
\m_axis_tdata[7]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0FF0FF000FF0FF11"
    )
        port map (
      I0 => \m_axis_tdata[10]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(25),
      I2 => phase_reg(1),
      I3 => ctrl_sync(23),
      I4 => \m_axis_tdata[9]_INST_0_i_1_n_0\,
      I5 => ctrl_sync(24),
      O => m_axis_tdata(6)
    );
\m_axis_tdata[8]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"000FFFFFFFF10000"
    )
        port map (
      I0 => \m_axis_tdata[10]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(25),
      I2 => \m_axis_tdata[9]_INST_0_i_1_n_0\,
      I3 => ctrl_sync(23),
      I4 => phase_reg(1),
      I5 => ctrl_sync(24),
      O => m_axis_tdata(7)
    );
\m_axis_tdata[9]_INST_0\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"3333333DCCCCCCCC"
    )
        port map (
      I0 => \m_axis_tdata[10]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(25),
      I2 => ctrl_sync(24),
      I3 => \m_axis_tdata[9]_INST_0_i_1_n_0\,
      I4 => ctrl_sync(23),
      I5 => phase_reg(1),
      O => m_axis_tdata(8)
    );
\m_axis_tdata[9]_INST_0_i_1\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"E"
    )
        port map (
      I0 => \m_axis_tdata[6]_INST_0_i_1_n_0\,
      I1 => ctrl_sync(22),
      O => \m_axis_tdata[9]_INST_0_i_1_n_0\
    );
\phase[0]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => \phase_reg_n_0_[0]\,
      O => p_0_in(0)
    );
\phase[1]_i_1\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"7"
    )
        port map (
      I0 => ctrl_sync(0),
      I1 => aresetn,
      O => \phase[1]_i_1_n_0\
    );
\phase[1]_i_2\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"6"
    )
        port map (
      I0 => \phase_reg_n_0_[0]\,
      I1 => phase_reg(1),
      O => p_0_in(1)
    );
\phase_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => m_axis_tready,
      D => p_0_in(0),
      Q => \phase_reg_n_0_[0]\,
      R => \phase[1]_i_1_n_0\
    );
\phase_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => m_axis_tready,
      D => p_0_in(1),
      Q => phase_reg(1),
      R => \phase[1]_i_1_n_0\
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity system_dac_tone_0 is
  port (
    aclk : in STD_LOGIC;
    aresetn : in STD_LOGIC;
    ctrl : in STD_LOGIC_VECTOR ( 31 downto 0 );
    m_axis_tdata : out STD_LOGIC_VECTOR ( 255 downto 0 );
    m_axis_tvalid : out STD_LOGIC;
    m_axis_tready : in STD_LOGIC
  );
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of system_dac_tone_0 : entity is true;
  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of system_dac_tone_0 : entity is "system_dac_tone_0,zcu216_dac_tone_axis,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of system_dac_tone_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of system_dac_tone_0 : entity is "module_ref";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of system_dac_tone_0 : entity is "zcu216_dac_tone_axis,Vivado 2021.1_AR76780";
end system_dac_tone_0;

architecture STRUCTURE of system_dac_tone_0 is
  signal \^m_axis_tdata\ : STD_LOGIC_VECTOR ( 15 downto 0 );
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of aclk : signal is "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF m_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 430080000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_dac3, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tready : signal is "xilinx.com:interface:axis:1.0 m_axis TREADY";
  attribute X_INTERFACE_PARAMETER of m_axis_tready : signal is "XIL_INTERFACENAME m_axis, TDATA_NUM_BYTES 32, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 430080000, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_dac3, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of m_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 m_axis TVALID";
  attribute X_INTERFACE_INFO of m_axis_tdata : signal is "xilinx.com:interface:axis:1.0 m_axis TDATA";
begin
  m_axis_tdata(255 downto 240) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(239 downto 224) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(223 downto 208) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(207 downto 192) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(191 downto 176) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(175 downto 160) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(159 downto 144) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(143 downto 128) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(127 downto 112) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(111 downto 96) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(95 downto 80) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(79 downto 64) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(63 downto 48) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(47 downto 32) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(31 downto 16) <= \^m_axis_tdata\(15 downto 0);
  m_axis_tdata(15 downto 0) <= \^m_axis_tdata\(15 downto 0);
inst: entity work.system_dac_tone_0_zcu216_dac_tone_axis
     port map (
      aclk => aclk,
      aresetn => aresetn,
      ctrl(31 downto 0) => ctrl(31 downto 0),
      m_axis_tdata(14 downto 0) => \^m_axis_tdata\(15 downto 1),
      m_axis_tready => m_axis_tready,
      \out\(1) => \^m_axis_tdata\(0),
      \out\(0) => m_axis_tvalid
    );
end STRUCTURE;
