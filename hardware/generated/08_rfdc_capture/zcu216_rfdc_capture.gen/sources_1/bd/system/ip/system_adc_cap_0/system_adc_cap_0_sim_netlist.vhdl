-- Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
-- Date        : Fri Jun 19 11:14:15 2026
-- Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
-- Command     : write_vhdl -force -mode funcsim
--               /home/dsp-mikro7/FPGA_Based_OFDM_Transceiver/hardware/generated/08_rfdc_capture/zcu216_rfdc_capture.gen/sources_1/bd/system/ip/system_adc_cap_0/system_adc_cap_0_sim_netlist.vhdl
-- Design      : system_adc_cap_0
-- Purpose     : This VHDL netlist is a functional simulation representation of the design and should not be modified or
--               synthesized. This netlist cannot be used for SDF annotated simulation.
-- Device      : xczu49dr-ffvf1760-2-e
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity system_adc_cap_0_zcu216_adc_capture is
  port (
    active_reg_0 : out STD_LOGIC;
    status_capture : out STD_LOGIC_VECTOR ( 15 downto 0 );
    status1 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status3 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    O15 : out STD_LOGIC_VECTOR ( 15 downto 0 );
    status2 : out STD_LOGIC_VECTOR ( 31 downto 0 );
    status0 : out STD_LOGIC_VECTOR ( 4 downto 0 );
    s_axis_tvalid : in STD_LOGIC;
    aclk : in STD_LOGIC;
    s_axis_tdata : in STD_LOGIC_VECTOR ( 15 downto 0 );
    ctrl : in STD_LOGIC_VECTOR ( 31 downto 0 );
    aresetn : in STD_LOGIC
  );
  attribute ORIG_REF_NAME : string;
  attribute ORIG_REF_NAME of system_adc_cap_0_zcu216_adc_capture : entity is "zcu216_adc_capture";
end system_adc_cap_0_zcu216_adc_capture;

architecture STRUCTURE of system_adc_cap_0_zcu216_adc_capture is
  signal \^o15\ : STD_LOGIC_VECTOR ( 15 downto 0 );
  signal abs16_return : STD_LOGIC_VECTOR ( 15 downto 1 );
  signal active_i_2_n_0 : STD_LOGIC;
  signal active_i_3_n_0 : STD_LOGIC;
  signal active_i_4_n_0 : STD_LOGIC;
  signal active_i_5_n_0 : STD_LOGIC;
  signal active_i_6_n_0 : STD_LOGIC;
  signal active_i_7_n_0 : STD_LOGIC;
  signal active_i_8_n_0 : STD_LOGIC;
  signal active_i_9_n_0 : STD_LOGIC;
  signal \^active_reg_0\ : STD_LOGIC;
  signal cap_en_d : STD_LOGIC;
  signal clipping_i_1_n_0 : STD_LOGIC;
  signal clipping_i_2_n_0 : STD_LOGIC;
  signal clipping_i_3_n_0 : STD_LOGIC;
  signal clipping_i_4_n_0 : STD_LOGIC;
  signal clipping_i_5_n_0 : STD_LOGIC;
  signal clipping_i_6_n_0 : STD_LOGIC;
  signal clipping_i_7_n_0 : STD_LOGIC;
  signal count : STD_LOGIC;
  signal \count[7]_i_2_n_0\ : STD_LOGIC;
  signal count_reg : STD_LOGIC_VECTOR ( 31 downto 16 );
  signal \count_reg[15]_i_2_n_0\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_1\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_10\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_11\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_12\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_13\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_14\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_15\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_2\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_3\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_4\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_5\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_6\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_7\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_8\ : STD_LOGIC;
  signal \count_reg[15]_i_2_n_9\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_0\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_10\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_11\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_12\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_13\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_14\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_15\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_7\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_8\ : STD_LOGIC;
  signal \count_reg[16]_i_1_n_9\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_10\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_11\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_12\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_13\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_14\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_15\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_7\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_8\ : STD_LOGIC;
  signal \count_reg[24]_i_1_n_9\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_0\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_1\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_10\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_11\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_12\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_13\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_14\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_15\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_2\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_3\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_4\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_5\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_6\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_7\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_8\ : STD_LOGIC;
  signal \count_reg[7]_i_1_n_9\ : STD_LOGIC;
  signal ctrl_meta : STD_LOGIC_VECTOR ( 31 downto 0 );
  attribute async_reg : string;
  attribute async_reg of ctrl_meta : signal is "true";
  signal ctrl_sync : STD_LOGIC_VECTOR ( 31 downto 0 );
  attribute async_reg of ctrl_sync : signal is "true";
  signal done_i_2_n_0 : STD_LOGIC;
  signal done_i_3_n_0 : STD_LOGIC;
  signal \first_sample[15]_i_1_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_2_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_3_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_4_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_5_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_6_n_0\ : STD_LOGIC;
  signal \first_sample[15]_i_7_n_0\ : STD_LOGIC;
  signal last_sign : STD_LOGIC;
  signal last_sign_0 : STD_LOGIC;
  signal last_sign_valid : STD_LOGIC;
  signal last_sign_valid_reg_n_0 : STD_LOGIC;
  signal max_abs : STD_LOGIC;
  signal max_abs0_carry_i_10_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_11_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_12_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_13_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_14_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_15_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_16_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_17_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_18_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_1_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_2_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_3_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_4_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_5_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_6_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_7_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_8_n_0 : STD_LOGIC;
  signal max_abs0_carry_i_9_n_0 : STD_LOGIC;
  signal max_abs0_carry_n_0 : STD_LOGIC;
  signal max_abs0_carry_n_1 : STD_LOGIC;
  signal max_abs0_carry_n_2 : STD_LOGIC;
  signal max_abs0_carry_n_3 : STD_LOGIC;
  signal max_abs0_carry_n_4 : STD_LOGIC;
  signal max_abs0_carry_n_5 : STD_LOGIC;
  signal max_abs0_carry_n_6 : STD_LOGIC;
  signal max_abs0_carry_n_7 : STD_LOGIC;
  signal \max_abs[13]_i_2_n_0\ : STD_LOGIC;
  signal \max_abs[5]_i_2_n_0\ : STD_LOGIC;
  signal \max_abs[7]_i_2_n_0\ : STD_LOGIC;
  signal max_sample0_carry_i_10_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_11_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_12_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_13_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_14_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_15_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_16_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_1_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_2_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_3_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_4_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_5_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_6_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_7_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_8_n_0 : STD_LOGIC;
  signal max_sample0_carry_i_9_n_0 : STD_LOGIC;
  signal max_sample0_carry_n_0 : STD_LOGIC;
  signal max_sample0_carry_n_1 : STD_LOGIC;
  signal max_sample0_carry_n_2 : STD_LOGIC;
  signal max_sample0_carry_n_3 : STD_LOGIC;
  signal max_sample0_carry_n_4 : STD_LOGIC;
  signal max_sample0_carry_n_5 : STD_LOGIC;
  signal max_sample0_carry_n_6 : STD_LOGIC;
  signal max_sample0_carry_n_7 : STD_LOGIC;
  signal \max_sample[15]_i_1_n_0\ : STD_LOGIC;
  signal mem_reg_bram_0_i_1_n_0 : STD_LOGIC;
  signal mem_reg_bram_0_i_2_n_0 : STD_LOGIC;
  signal mem_reg_bram_0_n_0 : STD_LOGIC;
  signal mem_reg_bram_0_n_1 : STD_LOGIC;
  signal mem_reg_bram_0_n_139 : STD_LOGIC;
  signal mem_reg_bram_0_n_60 : STD_LOGIC;
  signal mem_reg_bram_0_n_61 : STD_LOGIC;
  signal mem_reg_bram_0_n_62 : STD_LOGIC;
  signal mem_reg_bram_0_n_63 : STD_LOGIC;
  signal mem_reg_bram_0_n_64 : STD_LOGIC;
  signal mem_reg_bram_0_n_65 : STD_LOGIC;
  signal mem_reg_bram_0_n_66 : STD_LOGIC;
  signal mem_reg_bram_0_n_67 : STD_LOGIC;
  signal mem_reg_bram_1_i_1_n_0 : STD_LOGIC;
  signal mem_reg_bram_1_i_2_n_0 : STD_LOGIC;
  signal mem_reg_bram_1_i_3_n_0 : STD_LOGIC;
  signal mem_reg_bram_3_i_1_n_0 : STD_LOGIC;
  signal min_sample : STD_LOGIC;
  signal min_sample0_carry_i_10_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_11_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_12_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_13_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_14_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_15_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_16_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_1_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_2_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_3_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_4_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_5_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_6_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_7_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_8_n_0 : STD_LOGIC;
  signal min_sample0_carry_i_9_n_0 : STD_LOGIC;
  signal min_sample0_carry_n_0 : STD_LOGIC;
  signal min_sample0_carry_n_1 : STD_LOGIC;
  signal min_sample0_carry_n_2 : STD_LOGIC;
  signal min_sample0_carry_n_3 : STD_LOGIC;
  signal min_sample0_carry_n_4 : STD_LOGIC;
  signal min_sample0_carry_n_5 : STD_LOGIC;
  signal min_sample0_carry_n_6 : STD_LOGIC;
  signal min_sample0_carry_n_7 : STD_LOGIC;
  signal overflow_i_10_n_0 : STD_LOGIC;
  signal overflow_i_11_n_0 : STD_LOGIC;
  signal overflow_i_12_n_0 : STD_LOGIC;
  signal overflow_i_13_n_0 : STD_LOGIC;
  signal overflow_i_14_n_0 : STD_LOGIC;
  signal overflow_i_15_n_0 : STD_LOGIC;
  signal overflow_i_16_n_0 : STD_LOGIC;
  signal overflow_i_17_n_0 : STD_LOGIC;
  signal overflow_i_1_n_0 : STD_LOGIC;
  signal overflow_i_3_n_0 : STD_LOGIC;
  signal overflow_i_4_n_0 : STD_LOGIC;
  signal overflow_i_5_n_0 : STD_LOGIC;
  signal overflow_i_6_n_0 : STD_LOGIC;
  signal overflow_i_7_n_0 : STD_LOGIC;
  signal overflow_i_8_n_0 : STD_LOGIC;
  signal overflow_i_9_n_0 : STD_LOGIC;
  signal p_0_in : STD_LOGIC;
  signal \p_0_in__0\ : STD_LOGIC_VECTOR ( 12 downto 0 );
  signal saw_nonzero_i_1_n_0 : STD_LOGIC;
  signal saw_nonzero_i_2_n_0 : STD_LOGIC;
  signal saw_sign_change : STD_LOGIC;
  signal saw_sign_change_i_1_n_0 : STD_LOGIC;
  signal \sign_changes[31]_i_1_n_0\ : STD_LOGIC;
  signal \sign_changes[7]_i_2_n_0\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_0\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_1\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_10\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_11\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_12\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_13\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_14\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_15\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_2\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_3\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_4\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_5\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_6\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_7\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_8\ : STD_LOGIC;
  signal \sign_changes_reg[15]_i_1_n_9\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_0\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_1\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_10\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_11\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_12\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_13\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_14\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_15\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_2\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_3\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_4\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_5\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_6\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_7\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_8\ : STD_LOGIC;
  signal \sign_changes_reg[23]_i_1_n_9\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_1\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_10\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_11\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_12\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_13\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_14\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_15\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_2\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_3\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_4\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_5\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_6\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_7\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_8\ : STD_LOGIC;
  signal \sign_changes_reg[31]_i_2_n_9\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_0\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_1\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_10\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_11\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_12\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_13\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_14\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_15\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_2\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_3\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_4\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_5\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_6\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_7\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_8\ : STD_LOGIC;
  signal \sign_changes_reg[7]_i_1_n_9\ : STD_LOGIC;
  signal start : STD_LOGIC;
  signal \^status0\ : STD_LOGIC_VECTOR ( 4 downto 0 );
  signal \^status1\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \^status2\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \^status3\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \wr_addr0_carry__0_n_5\ : STD_LOGIC;
  signal \wr_addr0_carry__0_n_6\ : STD_LOGIC;
  signal \wr_addr0_carry__0_n_7\ : STD_LOGIC;
  signal wr_addr0_carry_n_0 : STD_LOGIC;
  signal wr_addr0_carry_n_1 : STD_LOGIC;
  signal wr_addr0_carry_n_2 : STD_LOGIC;
  signal wr_addr0_carry_n_3 : STD_LOGIC;
  signal wr_addr0_carry_n_4 : STD_LOGIC;
  signal wr_addr0_carry_n_5 : STD_LOGIC;
  signal wr_addr0_carry_n_6 : STD_LOGIC;
  signal wr_addr0_carry_n_7 : STD_LOGIC;
  signal \wr_addr[12]_i_2_n_0\ : STD_LOGIC;
  signal \wr_addr[12]_i_3_n_0\ : STD_LOGIC;
  signal \wr_addr[12]_i_4_n_0\ : STD_LOGIC;
  signal \wr_addr[12]_i_5_n_0\ : STD_LOGIC;
  signal wr_addr_reg : STD_LOGIC_VECTOR ( 12 downto 0 );
  signal wr_full : STD_LOGIC;
  signal wr_full2 : STD_LOGIC;
  signal wr_full_i_1_n_0 : STD_LOGIC;
  signal \NLW_count_reg[24]_i_1_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 7 to 7 );
  signal NLW_max_abs0_carry_O_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_max_sample0_carry_O_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_mem_reg_bram_0_DBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_0_SBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_0_CASDOUTA_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_0_CASDOUTB_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 8 );
  signal NLW_mem_reg_bram_0_CASDOUTPA_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_0_CASDOUTPB_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 1 );
  signal NLW_mem_reg_bram_0_DOUTADOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_0_DOUTBDOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_0_DOUTPADOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_0_DOUTPBDOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_0_ECCPARITY_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_mem_reg_bram_0_RDADDRECC_UNCONNECTED : STD_LOGIC_VECTOR ( 8 downto 0 );
  signal NLW_mem_reg_bram_1_CASOUTDBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_1_CASOUTSBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_1_DBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_1_SBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_1_CASDOUTA_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_1_CASDOUTB_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_1_CASDOUTPA_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_1_CASDOUTPB_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_1_DOUTADOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_1_DOUTBDOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 8 );
  signal NLW_mem_reg_bram_1_DOUTPADOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_1_DOUTPBDOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 1 );
  signal NLW_mem_reg_bram_1_ECCPARITY_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_mem_reg_bram_1_RDADDRECC_UNCONNECTED : STD_LOGIC_VECTOR ( 8 downto 0 );
  signal NLW_mem_reg_bram_2_CASOUTDBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_2_CASOUTSBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_2_DBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_2_SBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_2_CASDOUTA_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_2_CASDOUTB_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_2_CASDOUTPA_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_2_CASDOUTPB_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_2_DOUTADOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_2_DOUTBDOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 4 );
  signal NLW_mem_reg_bram_2_DOUTPADOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_2_DOUTPBDOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_2_ECCPARITY_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_mem_reg_bram_2_RDADDRECC_UNCONNECTED : STD_LOGIC_VECTOR ( 8 downto 0 );
  signal NLW_mem_reg_bram_3_CASOUTDBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_3_CASOUTSBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_3_DBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_3_SBITERR_UNCONNECTED : STD_LOGIC;
  signal NLW_mem_reg_bram_3_CASDOUTA_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_3_CASDOUTB_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_3_CASDOUTPA_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_3_CASDOUTPB_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_3_DOUTADOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal NLW_mem_reg_bram_3_DOUTBDOUT_UNCONNECTED : STD_LOGIC_VECTOR ( 31 downto 3 );
  signal NLW_mem_reg_bram_3_DOUTPADOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_3_DOUTPBDOUTP_UNCONNECTED : STD_LOGIC_VECTOR ( 3 downto 0 );
  signal NLW_mem_reg_bram_3_ECCPARITY_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal NLW_mem_reg_bram_3_RDADDRECC_UNCONNECTED : STD_LOGIC_VECTOR ( 8 downto 0 );
  signal NLW_min_sample0_carry_O_UNCONNECTED : STD_LOGIC_VECTOR ( 7 downto 0 );
  signal \NLW_sign_changes_reg[31]_i_2_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 7 to 7 );
  signal \NLW_wr_addr0_carry__0_CO_UNCONNECTED\ : STD_LOGIC_VECTOR ( 7 downto 3 );
  signal \NLW_wr_addr0_carry__0_O_UNCONNECTED\ : STD_LOGIC_VECTOR ( 7 downto 4 );
  attribute SOFT_HLUTNM : string;
  attribute SOFT_HLUTNM of active_i_5 : label is "soft_lutpair6";
  attribute SOFT_HLUTNM of clipping_i_3 : label is "soft_lutpair1";
  attribute SOFT_HLUTNM of clipping_i_4 : label is "soft_lutpair3";
  attribute SOFT_HLUTNM of clipping_i_6 : label is "soft_lutpair12";
  attribute SOFT_HLUTNM of clipping_i_7 : label is "soft_lutpair5";
  attribute ADDER_THRESHOLD : integer;
  attribute ADDER_THRESHOLD of \count_reg[15]_i_2\ : label is 16;
  attribute ADDER_THRESHOLD of \count_reg[16]_i_1\ : label is 16;
  attribute ADDER_THRESHOLD of \count_reg[24]_i_1\ : label is 16;
  attribute ADDER_THRESHOLD of \count_reg[7]_i_1\ : label is 16;
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
  attribute COMPARATOR_THRESHOLD : integer;
  attribute COMPARATOR_THRESHOLD of max_abs0_carry : label is 11;
  attribute SOFT_HLUTNM of max_abs0_carry_i_17 : label is "soft_lutpair3";
  attribute SOFT_HLUTNM of max_abs0_carry_i_18 : label is "soft_lutpair9";
  attribute SOFT_HLUTNM of \max_abs[10]_i_1\ : label is "soft_lutpair2";
  attribute SOFT_HLUTNM of \max_abs[12]_i_1\ : label is "soft_lutpair7";
  attribute SOFT_HLUTNM of \max_abs[13]_i_1\ : label is "soft_lutpair7";
  attribute SOFT_HLUTNM of \max_abs[13]_i_2\ : label is "soft_lutpair1";
  attribute SOFT_HLUTNM of \max_abs[14]_i_1\ : label is "soft_lutpair11";
  attribute SOFT_HLUTNM of \max_abs[15]_i_2\ : label is "soft_lutpair11";
  attribute SOFT_HLUTNM of \max_abs[1]_i_1\ : label is "soft_lutpair9";
  attribute SOFT_HLUTNM of \max_abs[2]_i_1\ : label is "soft_lutpair4";
  attribute SOFT_HLUTNM of \max_abs[3]_i_1\ : label is "soft_lutpair4";
  attribute SOFT_HLUTNM of \max_abs[6]_i_1\ : label is "soft_lutpair8";
  attribute SOFT_HLUTNM of \max_abs[7]_i_1\ : label is "soft_lutpair8";
  attribute SOFT_HLUTNM of \max_abs[8]_i_1\ : label is "soft_lutpair12";
  attribute SOFT_HLUTNM of \max_abs[9]_i_1\ : label is "soft_lutpair2";
  attribute COMPARATOR_THRESHOLD of max_sample0_carry : label is 11;
  attribute \MEM.PORTA.DATA_BIT_LAYOUT\ : string;
  attribute \MEM.PORTA.DATA_BIT_LAYOUT\ of mem_reg_bram_0 : label is "p1_d8";
  attribute \MEM.PORTB.DATA_BIT_LAYOUT\ : string;
  attribute \MEM.PORTB.DATA_BIT_LAYOUT\ of mem_reg_bram_0 : label is "p1_d8";
  attribute METHODOLOGY_DRC_VIOS : string;
  attribute METHODOLOGY_DRC_VIOS of mem_reg_bram_0 : label is "";
  attribute RDADDR_COLLISION_HWCONFIG : string;
  attribute RDADDR_COLLISION_HWCONFIG of mem_reg_bram_0 : label is "DELAYED_WRITE";
  attribute RTL_RAM_BITS : integer;
  attribute RTL_RAM_BITS of mem_reg_bram_0 : label is 131072;
  attribute RTL_RAM_NAME : string;
  attribute RTL_RAM_NAME of mem_reg_bram_0 : label is "inst/mem";
  attribute RTL_RAM_TYPE : string;
  attribute RTL_RAM_TYPE of mem_reg_bram_0 : label is "RAM_SDP";
  attribute ram_addr_begin : integer;
  attribute ram_addr_begin of mem_reg_bram_0 : label is 0;
  attribute ram_addr_end : integer;
  attribute ram_addr_end of mem_reg_bram_0 : label is 4095;
  attribute ram_offset : integer;
  attribute ram_offset of mem_reg_bram_0 : label is 0;
  attribute ram_slice_begin : integer;
  attribute ram_slice_begin of mem_reg_bram_0 : label is 0;
  attribute ram_slice_end : integer;
  attribute ram_slice_end of mem_reg_bram_0 : label is 8;
  attribute SOFT_HLUTNM of mem_reg_bram_0_i_1 : label is "soft_lutpair6";
  attribute SOFT_HLUTNM of mem_reg_bram_0_i_2 : label is "soft_lutpair13";
  attribute \MEM.PORTA.DATA_BIT_LAYOUT\ of mem_reg_bram_1 : label is "p1_d8";
  attribute \MEM.PORTB.DATA_BIT_LAYOUT\ of mem_reg_bram_1 : label is "p1_d8";
  attribute METHODOLOGY_DRC_VIOS of mem_reg_bram_1 : label is "{SYNTH-6 {cell *THIS*}}";
  attribute RDADDR_COLLISION_HWCONFIG of mem_reg_bram_1 : label is "DELAYED_WRITE";
  attribute RTL_RAM_BITS of mem_reg_bram_1 : label is 131072;
  attribute RTL_RAM_NAME of mem_reg_bram_1 : label is "inst/mem";
  attribute RTL_RAM_TYPE of mem_reg_bram_1 : label is "RAM_SDP";
  attribute ram_addr_begin of mem_reg_bram_1 : label is 4096;
  attribute ram_addr_end of mem_reg_bram_1 : label is 8191;
  attribute ram_offset of mem_reg_bram_1 : label is 0;
  attribute ram_slice_begin of mem_reg_bram_1 : label is 0;
  attribute ram_slice_end of mem_reg_bram_1 : label is 8;
  attribute SOFT_HLUTNM of mem_reg_bram_1_i_2 : label is "soft_lutpair10";
  attribute SOFT_HLUTNM of mem_reg_bram_1_i_3 : label is "soft_lutpair13";
  attribute \MEM.PORTA.DATA_BIT_LAYOUT\ of mem_reg_bram_2 : label is "p0_d4";
  attribute \MEM.PORTB.DATA_BIT_LAYOUT\ of mem_reg_bram_2 : label is "p0_d4";
  attribute METHODOLOGY_DRC_VIOS of mem_reg_bram_2 : label is "{SYNTH-6 {cell *THIS*}}";
  attribute RDADDR_COLLISION_HWCONFIG of mem_reg_bram_2 : label is "DELAYED_WRITE";
  attribute RTL_RAM_BITS of mem_reg_bram_2 : label is 131072;
  attribute RTL_RAM_NAME of mem_reg_bram_2 : label is "inst/mem";
  attribute RTL_RAM_TYPE of mem_reg_bram_2 : label is "RAM_SDP";
  attribute ram_addr_begin of mem_reg_bram_2 : label is 0;
  attribute ram_addr_end of mem_reg_bram_2 : label is 8191;
  attribute ram_offset of mem_reg_bram_2 : label is 0;
  attribute ram_slice_begin of mem_reg_bram_2 : label is 9;
  attribute ram_slice_end of mem_reg_bram_2 : label is 12;
  attribute \MEM.PORTA.DATA_BIT_LAYOUT\ of mem_reg_bram_3 : label is "p0_d3";
  attribute \MEM.PORTB.DATA_BIT_LAYOUT\ of mem_reg_bram_3 : label is "p0_d3";
  attribute METHODOLOGY_DRC_VIOS of mem_reg_bram_3 : label is "{SYNTH-6 {cell *THIS*}}";
  attribute RDADDR_COLLISION_HWCONFIG of mem_reg_bram_3 : label is "DELAYED_WRITE";
  attribute RTL_RAM_BITS of mem_reg_bram_3 : label is 131072;
  attribute RTL_RAM_NAME of mem_reg_bram_3 : label is "inst/mem";
  attribute RTL_RAM_TYPE of mem_reg_bram_3 : label is "RAM_SDP";
  attribute ram_addr_begin of mem_reg_bram_3 : label is 0;
  attribute ram_addr_end of mem_reg_bram_3 : label is 8191;
  attribute ram_offset of mem_reg_bram_3 : label is 0;
  attribute ram_slice_begin of mem_reg_bram_3 : label is 13;
  attribute ram_slice_end of mem_reg_bram_3 : label is 15;
  attribute SOFT_HLUTNM of mem_reg_bram_3_i_1 : label is "soft_lutpair10";
  attribute COMPARATOR_THRESHOLD of min_sample0_carry : label is 11;
  attribute SOFT_HLUTNM of saw_nonzero_i_1 : label is "soft_lutpair5";
  attribute ADDER_THRESHOLD of \sign_changes_reg[15]_i_1\ : label is 16;
  attribute ADDER_THRESHOLD of \sign_changes_reg[23]_i_1\ : label is 16;
  attribute ADDER_THRESHOLD of \sign_changes_reg[31]_i_2\ : label is 16;
  attribute ADDER_THRESHOLD of \sign_changes_reg[7]_i_1\ : label is 16;
  attribute ADDER_THRESHOLD of wr_addr0_carry : label is 35;
  attribute ADDER_THRESHOLD of \wr_addr0_carry__0\ : label is 35;
  attribute SOFT_HLUTNM of \wr_addr[0]_i_1\ : label is "soft_lutpair0";
  attribute SOFT_HLUTNM of \wr_addr[12]_i_5\ : label is "soft_lutpair0";
begin
  O15(15 downto 0) <= \^o15\(15 downto 0);
  active_reg_0 <= \^active_reg_0\;
  status0(4 downto 0) <= \^status0\(4 downto 0);
  status1(31 downto 0) <= \^status1\(31 downto 0);
  status2(31 downto 0) <= \^status2\(31 downto 0);
  status3(31 downto 0) <= \^status3\(31 downto 0);
active_i_1: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => aresetn,
      O => p_0_in
    );
active_i_2: unisim.vcomponents.LUT6
    generic map(
      INIT => X"C4CCCCCC44444444"
    )
        port map (
      I0 => cap_en_d,
      I1 => ctrl_sync(1),
      I2 => active_i_3_n_0,
      I3 => active_i_4_n_0,
      I4 => active_i_5_n_0,
      I5 => \^active_reg_0\,
      O => active_i_2_n_0
    );
active_i_3: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFBFFFFFFF"
    )
        port map (
      I0 => active_i_6_n_0,
      I1 => \^o15\(4),
      I2 => \^o15\(3),
      I3 => \^o15\(6),
      I4 => \^o15\(5),
      I5 => active_i_7_n_0,
      O => active_i_3_n_0
    );
active_i_4: unisim.vcomponents.LUT2
    generic map(
      INIT => X"8"
    )
        port map (
      I0 => active_i_8_n_0,
      I1 => active_i_9_n_0,
      O => active_i_4_n_0
    );
active_i_5: unisim.vcomponents.LUT4
    generic map(
      INIT => X"4000"
    )
        port map (
      I0 => count_reg(16),
      I1 => \^active_reg_0\,
      I2 => s_axis_tvalid,
      I3 => done_i_3_n_0,
      O => active_i_5_n_0
    );
active_i_6: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => \^o15\(8),
      I1 => \^o15\(7),
      I2 => \^o15\(10),
      I3 => \^o15\(9),
      O => active_i_6_n_0
    );
active_i_7: unisim.vcomponents.LUT5
    generic map(
      INIT => X"7FFFFFFF"
    )
        port map (
      I0 => \^o15\(0),
      I1 => \^o15\(11),
      I2 => \^o15\(12),
      I3 => \^o15\(2),
      I4 => \^o15\(1),
      O => active_i_7_n_0
    );
active_i_8: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => count_reg(19),
      I1 => count_reg(20),
      I2 => count_reg(17),
      I3 => count_reg(18),
      I4 => count_reg(22),
      I5 => count_reg(21),
      O => active_i_8_n_0
    );
active_i_9: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => count_reg(25),
      I1 => count_reg(26),
      I2 => count_reg(23),
      I3 => count_reg(24),
      I4 => count_reg(28),
      I5 => count_reg(27),
      O => active_i_9_n_0
    );
active_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => active_i_2_n_0,
      Q => \^active_reg_0\,
      R => p_0_in
    );
cap_en_d_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => ctrl_sync(1),
      Q => cap_en_d,
      R => p_0_in
    );
clipping_i_1: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFC8CC8888"
    )
        port map (
      I0 => clipping_i_2_n_0,
      I1 => last_sign_0,
      I2 => clipping_i_3_n_0,
      I3 => clipping_i_4_n_0,
      I4 => clipping_i_5_n_0,
      I5 => \^status0\(0),
      O => clipping_i_1_n_0
    );
clipping_i_2: unisim.vcomponents.LUT6
    generic map(
      INIT => X"8000000000000000"
    )
        port map (
      I0 => clipping_i_6_n_0,
      I1 => clipping_i_7_n_0,
      I2 => s_axis_tdata(12),
      I3 => s_axis_tdata(13),
      I4 => s_axis_tdata(10),
      I5 => s_axis_tdata(11),
      O => clipping_i_2_n_0
    );
clipping_i_3: unisim.vcomponents.LUT2
    generic map(
      INIT => X"7"
    )
        port map (
      I0 => s_axis_tdata(8),
      I1 => s_axis_tdata(9),
      O => clipping_i_3_n_0
    );
clipping_i_4: unisim.vcomponents.LUT3
    generic map(
      INIT => X"FE"
    )
        port map (
      I0 => s_axis_tdata(6),
      I1 => \max_abs[7]_i_2_n_0\,
      I2 => s_axis_tdata(7),
      O => clipping_i_4_n_0
    );
clipping_i_5: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000100000000"
    )
        port map (
      I0 => s_axis_tdata(12),
      I1 => s_axis_tdata(13),
      I2 => s_axis_tdata(10),
      I3 => s_axis_tdata(11),
      I4 => s_axis_tdata(14),
      I5 => s_axis_tdata(15),
      O => clipping_i_5_n_0
    );
clipping_i_6: unisim.vcomponents.LUT2
    generic map(
      INIT => X"E"
    )
        port map (
      I0 => s_axis_tdata(8),
      I1 => s_axis_tdata(9),
      O => clipping_i_6_n_0
    );
clipping_i_7: unisim.vcomponents.LUT2
    generic map(
      INIT => X"2"
    )
        port map (
      I0 => s_axis_tdata(14),
      I1 => s_axis_tdata(15),
      O => clipping_i_7_n_0
    );
clipping_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => clipping_i_1_n_0,
      Q => \^status0\(0),
      R => last_sign_valid
    );
\count[15]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => overflow_i_4_n_0,
      I1 => ctrl_sync(1),
      I2 => \^active_reg_0\,
      I3 => s_axis_tvalid,
      O => count
    );
\count[7]_i_2\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => \^o15\(0),
      O => \count[7]_i_2_n_0\
    );
\count_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_15\,
      Q => \^o15\(0),
      R => last_sign_valid
    );
\count_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_13\,
      Q => \^o15\(10),
      R => last_sign_valid
    );
\count_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_12\,
      Q => \^o15\(11),
      R => last_sign_valid
    );
\count_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_11\,
      Q => \^o15\(12),
      R => last_sign_valid
    );
\count_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_10\,
      Q => \^o15\(13),
      R => last_sign_valid
    );
\count_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_9\,
      Q => \^o15\(14),
      R => last_sign_valid
    );
\count_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_8\,
      Q => \^o15\(15),
      R => last_sign_valid
    );
\count_reg[15]_i_2\: unisim.vcomponents.CARRY8
     port map (
      CI => \count_reg[7]_i_1_n_0\,
      CI_TOP => '0',
      CO(7) => \count_reg[15]_i_2_n_0\,
      CO(6) => \count_reg[15]_i_2_n_1\,
      CO(5) => \count_reg[15]_i_2_n_2\,
      CO(4) => \count_reg[15]_i_2_n_3\,
      CO(3) => \count_reg[15]_i_2_n_4\,
      CO(2) => \count_reg[15]_i_2_n_5\,
      CO(1) => \count_reg[15]_i_2_n_6\,
      CO(0) => \count_reg[15]_i_2_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \count_reg[15]_i_2_n_8\,
      O(6) => \count_reg[15]_i_2_n_9\,
      O(5) => \count_reg[15]_i_2_n_10\,
      O(4) => \count_reg[15]_i_2_n_11\,
      O(3) => \count_reg[15]_i_2_n_12\,
      O(2) => \count_reg[15]_i_2_n_13\,
      O(1) => \count_reg[15]_i_2_n_14\,
      O(0) => \count_reg[15]_i_2_n_15\,
      S(7 downto 0) => \^o15\(15 downto 8)
    );
\count_reg[16]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_15\,
      Q => count_reg(16),
      R => last_sign_valid
    );
\count_reg[16]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => \count_reg[15]_i_2_n_0\,
      CI_TOP => '0',
      CO(7) => \count_reg[16]_i_1_n_0\,
      CO(6) => \count_reg[16]_i_1_n_1\,
      CO(5) => \count_reg[16]_i_1_n_2\,
      CO(4) => \count_reg[16]_i_1_n_3\,
      CO(3) => \count_reg[16]_i_1_n_4\,
      CO(2) => \count_reg[16]_i_1_n_5\,
      CO(1) => \count_reg[16]_i_1_n_6\,
      CO(0) => \count_reg[16]_i_1_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \count_reg[16]_i_1_n_8\,
      O(6) => \count_reg[16]_i_1_n_9\,
      O(5) => \count_reg[16]_i_1_n_10\,
      O(4) => \count_reg[16]_i_1_n_11\,
      O(3) => \count_reg[16]_i_1_n_12\,
      O(2) => \count_reg[16]_i_1_n_13\,
      O(1) => \count_reg[16]_i_1_n_14\,
      O(0) => \count_reg[16]_i_1_n_15\,
      S(7 downto 0) => count_reg(23 downto 16)
    );
\count_reg[17]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_14\,
      Q => count_reg(17),
      R => last_sign_valid
    );
\count_reg[18]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_13\,
      Q => count_reg(18),
      R => last_sign_valid
    );
\count_reg[19]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_12\,
      Q => count_reg(19),
      R => last_sign_valid
    );
\count_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_14\,
      Q => \^o15\(1),
      R => last_sign_valid
    );
\count_reg[20]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_11\,
      Q => count_reg(20),
      R => last_sign_valid
    );
\count_reg[21]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_10\,
      Q => count_reg(21),
      R => last_sign_valid
    );
\count_reg[22]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_9\,
      Q => count_reg(22),
      R => last_sign_valid
    );
\count_reg[23]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[16]_i_1_n_8\,
      Q => count_reg(23),
      R => last_sign_valid
    );
\count_reg[24]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_15\,
      Q => count_reg(24),
      R => last_sign_valid
    );
\count_reg[24]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => \count_reg[16]_i_1_n_0\,
      CI_TOP => '0',
      CO(7) => \NLW_count_reg[24]_i_1_CO_UNCONNECTED\(7),
      CO(6) => \count_reg[24]_i_1_n_1\,
      CO(5) => \count_reg[24]_i_1_n_2\,
      CO(4) => \count_reg[24]_i_1_n_3\,
      CO(3) => \count_reg[24]_i_1_n_4\,
      CO(2) => \count_reg[24]_i_1_n_5\,
      CO(1) => \count_reg[24]_i_1_n_6\,
      CO(0) => \count_reg[24]_i_1_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \count_reg[24]_i_1_n_8\,
      O(6) => \count_reg[24]_i_1_n_9\,
      O(5) => \count_reg[24]_i_1_n_10\,
      O(4) => \count_reg[24]_i_1_n_11\,
      O(3) => \count_reg[24]_i_1_n_12\,
      O(2) => \count_reg[24]_i_1_n_13\,
      O(1) => \count_reg[24]_i_1_n_14\,
      O(0) => \count_reg[24]_i_1_n_15\,
      S(7 downto 0) => count_reg(31 downto 24)
    );
\count_reg[25]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_14\,
      Q => count_reg(25),
      R => last_sign_valid
    );
\count_reg[26]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_13\,
      Q => count_reg(26),
      R => last_sign_valid
    );
\count_reg[27]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_12\,
      Q => count_reg(27),
      R => last_sign_valid
    );
\count_reg[28]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_11\,
      Q => count_reg(28),
      R => last_sign_valid
    );
\count_reg[29]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_10\,
      Q => count_reg(29),
      R => last_sign_valid
    );
\count_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_13\,
      Q => \^o15\(2),
      R => last_sign_valid
    );
\count_reg[30]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_9\,
      Q => count_reg(30),
      R => last_sign_valid
    );
\count_reg[31]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[24]_i_1_n_8\,
      Q => count_reg(31),
      R => last_sign_valid
    );
\count_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_12\,
      Q => \^o15\(3),
      R => last_sign_valid
    );
\count_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_11\,
      Q => \^o15\(4),
      R => last_sign_valid
    );
\count_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_10\,
      Q => \^o15\(5),
      R => last_sign_valid
    );
\count_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_9\,
      Q => \^o15\(6),
      R => last_sign_valid
    );
\count_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[7]_i_1_n_8\,
      Q => \^o15\(7),
      R => last_sign_valid
    );
\count_reg[7]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => '0',
      CI_TOP => '0',
      CO(7) => \count_reg[7]_i_1_n_0\,
      CO(6) => \count_reg[7]_i_1_n_1\,
      CO(5) => \count_reg[7]_i_1_n_2\,
      CO(4) => \count_reg[7]_i_1_n_3\,
      CO(3) => \count_reg[7]_i_1_n_4\,
      CO(2) => \count_reg[7]_i_1_n_5\,
      CO(1) => \count_reg[7]_i_1_n_6\,
      CO(0) => \count_reg[7]_i_1_n_7\,
      DI(7 downto 0) => B"00000001",
      O(7) => \count_reg[7]_i_1_n_8\,
      O(6) => \count_reg[7]_i_1_n_9\,
      O(5) => \count_reg[7]_i_1_n_10\,
      O(4) => \count_reg[7]_i_1_n_11\,
      O(3) => \count_reg[7]_i_1_n_12\,
      O(2) => \count_reg[7]_i_1_n_13\,
      O(1) => \count_reg[7]_i_1_n_14\,
      O(0) => \count_reg[7]_i_1_n_15\,
      S(7 downto 1) => \^o15\(7 downto 1),
      S(0) => \count[7]_i_2_n_0\
    );
\count_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_15\,
      Q => \^o15\(8),
      R => last_sign_valid
    );
\count_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => count,
      D => \count_reg[15]_i_2_n_14\,
      Q => \^o15\(9),
      R => last_sign_valid
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
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
      R => p_0_in
    );
done_i_1: unisim.vcomponents.LUT3
    generic map(
      INIT => X"4F"
    )
        port map (
      I0 => cap_en_d,
      I1 => ctrl_sync(1),
      I2 => aresetn,
      O => last_sign_valid
    );
done_i_2: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFF00004000"
    )
        port map (
      I0 => active_i_3_n_0,
      I1 => active_i_4_n_0,
      I2 => done_i_3_n_0,
      I3 => last_sign_0,
      I4 => count_reg(16),
      I5 => \^status0\(4),
      O => done_i_2_n_0
    );
done_i_3: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => count_reg(31),
      I1 => \^o15\(13),
      I2 => count_reg(29),
      I3 => count_reg(30),
      I4 => \^o15\(15),
      I5 => \^o15\(14),
      O => done_i_3_n_0
    );
done_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => done_i_2_n_0,
      Q => \^status0\(4),
      R => last_sign_valid
    );
\first_sample[15]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"8000000000000000"
    )
        port map (
      I0 => \first_sample[15]_i_2_n_0\,
      I1 => \first_sample[15]_i_3_n_0\,
      I2 => \first_sample[15]_i_4_n_0\,
      I3 => \first_sample[15]_i_5_n_0\,
      I4 => \first_sample[15]_i_6_n_0\,
      I5 => \first_sample[15]_i_7_n_0\,
      O => \first_sample[15]_i_1_n_0\
    );
\first_sample[15]_i_2\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => \^o15\(6),
      I1 => \^o15\(7),
      I2 => \^o15\(4),
      I3 => \^o15\(5),
      I4 => \^o15\(9),
      I5 => \^o15\(8),
      O => \first_sample[15]_i_2_n_0\
    );
\first_sample[15]_i_3\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => \^o15\(12),
      I1 => \^o15\(13),
      I2 => \^o15\(10),
      I3 => \^o15\(11),
      I4 => \^o15\(15),
      I5 => \^o15\(14),
      O => \first_sample[15]_i_3_n_0\
    );
\first_sample[15]_i_4\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"10000000"
    )
        port map (
      I0 => count_reg(17),
      I1 => count_reg(16),
      I2 => ctrl_sync(1),
      I3 => \^active_reg_0\,
      I4 => s_axis_tvalid,
      O => \first_sample[15]_i_4_n_0\
    );
\first_sample[15]_i_5\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => count_reg(20),
      I1 => count_reg(21),
      I2 => count_reg(18),
      I3 => count_reg(19),
      I4 => count_reg(23),
      I5 => count_reg(22),
      O => \first_sample[15]_i_5_n_0\
    );
\first_sample[15]_i_6\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => \^o15\(0),
      I1 => \^o15\(1),
      I2 => count_reg(30),
      I3 => count_reg(31),
      I4 => \^o15\(3),
      I5 => \^o15\(2),
      O => \first_sample[15]_i_6_n_0\
    );
\first_sample[15]_i_7\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000000000000001"
    )
        port map (
      I0 => count_reg(26),
      I1 => count_reg(27),
      I2 => count_reg(24),
      I3 => count_reg(25),
      I4 => count_reg(29),
      I5 => count_reg(28),
      O => \first_sample[15]_i_7_n_0\
    );
\first_sample_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(0),
      Q => \^status1\(0),
      R => last_sign_valid
    );
\first_sample_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(10),
      Q => \^status1\(10),
      R => last_sign_valid
    );
\first_sample_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(11),
      Q => \^status1\(11),
      R => last_sign_valid
    );
\first_sample_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(12),
      Q => \^status1\(12),
      R => last_sign_valid
    );
\first_sample_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(13),
      Q => \^status1\(13),
      R => last_sign_valid
    );
\first_sample_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(14),
      Q => \^status1\(14),
      R => last_sign_valid
    );
\first_sample_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(15),
      Q => \^status1\(15),
      R => last_sign_valid
    );
\first_sample_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(1),
      Q => \^status1\(1),
      R => last_sign_valid
    );
\first_sample_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(2),
      Q => \^status1\(2),
      R => last_sign_valid
    );
\first_sample_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(3),
      Q => \^status1\(3),
      R => last_sign_valid
    );
\first_sample_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(4),
      Q => \^status1\(4),
      R => last_sign_valid
    );
\first_sample_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(5),
      Q => \^status1\(5),
      R => last_sign_valid
    );
\first_sample_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(6),
      Q => \^status1\(6),
      R => last_sign_valid
    );
\first_sample_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(7),
      Q => \^status1\(7),
      R => last_sign_valid
    );
\first_sample_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(8),
      Q => \^status1\(8),
      R => last_sign_valid
    );
\first_sample_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \first_sample[15]_i_1_n_0\,
      D => s_axis_tdata(9),
      Q => \^status1\(9),
      R => last_sign_valid
    );
last_sign_i_1: unisim.vcomponents.LUT3
    generic map(
      INIT => X"80"
    )
        port map (
      I0 => s_axis_tvalid,
      I1 => \^active_reg_0\,
      I2 => ctrl_sync(1),
      O => last_sign_0
    );
last_sign_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => last_sign_0,
      D => s_axis_tdata(15),
      Q => last_sign,
      R => last_sign_valid
    );
last_sign_valid_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => last_sign_0,
      D => last_sign_0,
      Q => last_sign_valid_reg_n_0,
      R => last_sign_valid
    );
max_abs0_carry: unisim.vcomponents.CARRY8
     port map (
      CI => '0',
      CI_TOP => '0',
      CO(7) => max_abs0_carry_n_0,
      CO(6) => max_abs0_carry_n_1,
      CO(5) => max_abs0_carry_n_2,
      CO(4) => max_abs0_carry_n_3,
      CO(3) => max_abs0_carry_n_4,
      CO(2) => max_abs0_carry_n_5,
      CO(1) => max_abs0_carry_n_6,
      CO(0) => max_abs0_carry_n_7,
      DI(7) => max_abs0_carry_i_1_n_0,
      DI(6) => max_abs0_carry_i_2_n_0,
      DI(5) => max_abs0_carry_i_3_n_0,
      DI(4) => max_abs0_carry_i_4_n_0,
      DI(3) => max_abs0_carry_i_5_n_0,
      DI(2) => max_abs0_carry_i_6_n_0,
      DI(1) => max_abs0_carry_i_7_n_0,
      DI(0) => max_abs0_carry_i_8_n_0,
      O(7 downto 0) => NLW_max_abs0_carry_O_UNCONNECTED(7 downto 0),
      S(7) => max_abs0_carry_i_9_n_0,
      S(6) => max_abs0_carry_i_10_n_0,
      S(5) => max_abs0_carry_i_11_n_0,
      S(4) => max_abs0_carry_i_12_n_0,
      S(3) => max_abs0_carry_i_13_n_0,
      S(2) => max_abs0_carry_i_14_n_0,
      S(1) => max_abs0_carry_i_15_n_0,
      S(0) => max_abs0_carry_i_16_n_0
    );
max_abs0_carry_i_1: unisim.vcomponents.LUT5
    generic map(
      INIT => X"0004007C"
    )
        port map (
      I0 => saw_nonzero_i_2_n_0,
      I1 => s_axis_tdata(15),
      I2 => s_axis_tdata(14),
      I3 => \^status1\(31),
      I4 => \^status1\(30),
      O => max_abs0_carry_i_1_n_0
    );
max_abs0_carry_i_10: unisim.vcomponents.LUT6
    generic map(
      INIT => X"5028285007808007"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \max_abs[13]_i_2_n_0\,
      I2 => s_axis_tdata(12),
      I3 => s_axis_tdata(13),
      I4 => \^status1\(29),
      I5 => \^status1\(28),
      O => max_abs0_carry_i_10_n_0
    );
max_abs0_carry_i_11: unisim.vcomponents.LUT6
    generic map(
      INIT => X"1248482184842121"
    )
        port map (
      I0 => \^status1\(27),
      I1 => \^status1\(26),
      I2 => s_axis_tdata(11),
      I3 => max_abs0_carry_i_17_n_0,
      I4 => s_axis_tdata(10),
      I5 => s_axis_tdata(15),
      O => max_abs0_carry_i_11_n_0
    );
max_abs0_carry_i_12: unisim.vcomponents.LUT6
    generic map(
      INIT => X"4224188148843003"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \^status1\(24),
      I2 => \^status1\(25),
      I3 => s_axis_tdata(9),
      I4 => s_axis_tdata(8),
      I5 => clipping_i_4_n_0,
      O => max_abs0_carry_i_12_n_0
    );
max_abs0_carry_i_13: unisim.vcomponents.LUT6
    generic map(
      INIT => X"1248482184842121"
    )
        port map (
      I0 => \^status1\(23),
      I1 => \^status1\(22),
      I2 => s_axis_tdata(7),
      I3 => \max_abs[7]_i_2_n_0\,
      I4 => s_axis_tdata(6),
      I5 => s_axis_tdata(15),
      O => max_abs0_carry_i_13_n_0
    );
max_abs0_carry_i_14: unisim.vcomponents.LUT6
    generic map(
      INIT => X"1248482184842121"
    )
        port map (
      I0 => \^status1\(21),
      I1 => \^status1\(20),
      I2 => s_axis_tdata(5),
      I3 => max_abs0_carry_i_18_n_0,
      I4 => s_axis_tdata(4),
      I5 => s_axis_tdata(15),
      O => max_abs0_carry_i_14_n_0
    );
max_abs0_carry_i_15: unisim.vcomponents.LUT6
    generic map(
      INIT => X"1248482184842121"
    )
        port map (
      I0 => \^status1\(19),
      I1 => \^status1\(18),
      I2 => s_axis_tdata(3),
      I3 => \max_abs[5]_i_2_n_0\,
      I4 => s_axis_tdata(2),
      I5 => s_axis_tdata(15),
      O => max_abs0_carry_i_15_n_0
    );
max_abs0_carry_i_16: unisim.vcomponents.LUT5
    generic map(
      INIT => X"60900C03"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(1),
      I2 => s_axis_tdata(0),
      I3 => \^status1\(17),
      I4 => \^status1\(16),
      O => max_abs0_carry_i_16_n_0
    );
max_abs0_carry_i_17: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => s_axis_tdata(9),
      I1 => s_axis_tdata(8),
      I2 => s_axis_tdata(7),
      I3 => \max_abs[7]_i_2_n_0\,
      I4 => s_axis_tdata(6),
      O => max_abs0_carry_i_17_n_0
    );
max_abs0_carry_i_18: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => s_axis_tdata(2),
      I1 => s_axis_tdata(0),
      I2 => s_axis_tdata(1),
      I3 => s_axis_tdata(3),
      O => max_abs0_carry_i_18_n_0
    );
max_abs0_carry_i_2: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0717133331717000"
    )
        port map (
      I0 => \^status1\(28),
      I1 => \^status1\(29),
      I2 => s_axis_tdata(15),
      I3 => \max_abs[13]_i_2_n_0\,
      I4 => s_axis_tdata(12),
      I5 => s_axis_tdata(13),
      O => max_abs0_carry_i_2_n_0
    );
max_abs0_carry_i_3: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0717133331717000"
    )
        port map (
      I0 => \^status1\(26),
      I1 => \^status1\(27),
      I2 => s_axis_tdata(15),
      I3 => max_abs0_carry_i_17_n_0,
      I4 => s_axis_tdata(10),
      I5 => s_axis_tdata(11),
      O => max_abs0_carry_i_3_n_0
    );
max_abs0_carry_i_4: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0000502857A87FF8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => clipping_i_4_n_0,
      I2 => s_axis_tdata(8),
      I3 => s_axis_tdata(9),
      I4 => \^status1\(24),
      I5 => \^status1\(25),
      O => max_abs0_carry_i_4_n_0
    );
max_abs0_carry_i_5: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0717133331717000"
    )
        port map (
      I0 => \^status1\(22),
      I1 => \^status1\(23),
      I2 => s_axis_tdata(15),
      I3 => \max_abs[7]_i_2_n_0\,
      I4 => s_axis_tdata(6),
      I5 => s_axis_tdata(7),
      O => max_abs0_carry_i_5_n_0
    );
max_abs0_carry_i_6: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0717133331717000"
    )
        port map (
      I0 => \^status1\(20),
      I1 => \^status1\(21),
      I2 => s_axis_tdata(15),
      I3 => max_abs0_carry_i_18_n_0,
      I4 => s_axis_tdata(4),
      I5 => s_axis_tdata(5),
      O => max_abs0_carry_i_6_n_0
    );
max_abs0_carry_i_7: unisim.vcomponents.LUT6
    generic map(
      INIT => X"0717133331717000"
    )
        port map (
      I0 => \^status1\(18),
      I1 => \^status1\(19),
      I2 => s_axis_tdata(15),
      I3 => \max_abs[5]_i_2_n_0\,
      I4 => s_axis_tdata(2),
      I5 => s_axis_tdata(3),
      O => max_abs0_carry_i_7_n_0
    );
max_abs0_carry_i_8: unisim.vcomponents.LUT5
    generic map(
      INIT => X"17337100"
    )
        port map (
      I0 => \^status1\(16),
      I1 => \^status1\(17),
      I2 => s_axis_tdata(15),
      I3 => s_axis_tdata(0),
      I4 => s_axis_tdata(1),
      O => max_abs0_carry_i_8_n_0
    );
max_abs0_carry_i_9: unisim.vcomponents.LUT5
    generic map(
      INIT => X"00106C83"
    )
        port map (
      I0 => saw_nonzero_i_2_n_0,
      I1 => s_axis_tdata(14),
      I2 => s_axis_tdata(15),
      I3 => \^status1\(30),
      I4 => \^status1\(31),
      O => max_abs0_carry_i_9_n_0
    );
\max_abs[10]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"5557AAA8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(9),
      I2 => s_axis_tdata(8),
      I3 => clipping_i_4_n_0,
      I4 => s_axis_tdata(10),
      O => abs16_return(10)
    );
\max_abs[11]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"55555557AAAAAAA8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => clipping_i_4_n_0,
      I2 => s_axis_tdata(8),
      I3 => s_axis_tdata(9),
      I4 => s_axis_tdata(10),
      I5 => s_axis_tdata(11),
      O => abs16_return(11)
    );
\max_abs[12]_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \max_abs[13]_i_2_n_0\,
      I2 => s_axis_tdata(12),
      O => abs16_return(12)
    );
\max_abs[13]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"57A8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \max_abs[13]_i_2_n_0\,
      I2 => s_axis_tdata(12),
      I3 => s_axis_tdata(13),
      O => abs16_return(13)
    );
\max_abs[13]_i_2\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => s_axis_tdata(10),
      I1 => s_axis_tdata(9),
      I2 => s_axis_tdata(8),
      I3 => clipping_i_4_n_0,
      I4 => s_axis_tdata(11),
      O => \max_abs[13]_i_2_n_0\
    );
\max_abs[14]_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"6A"
    )
        port map (
      I0 => s_axis_tdata(14),
      I1 => saw_nonzero_i_2_n_0,
      I2 => s_axis_tdata(15),
      O => abs16_return(14)
    );
\max_abs[15]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => ctrl_sync(1),
      I1 => \^active_reg_0\,
      I2 => s_axis_tvalid,
      I3 => max_abs0_carry_n_0,
      O => max_abs
    );
\max_abs[15]_i_2\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"04"
    )
        port map (
      I0 => s_axis_tdata(14),
      I1 => s_axis_tdata(15),
      I2 => saw_nonzero_i_2_n_0,
      O => abs16_return(15)
    );
\max_abs[1]_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(0),
      I2 => s_axis_tdata(1),
      O => abs16_return(1)
    );
\max_abs[2]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"57A8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(0),
      I2 => s_axis_tdata(1),
      I3 => s_axis_tdata(2),
      O => abs16_return(2)
    );
\max_abs[3]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"5557AAA8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(1),
      I2 => s_axis_tdata(0),
      I3 => s_axis_tdata(2),
      I4 => s_axis_tdata(3),
      O => abs16_return(3)
    );
\max_abs[4]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"55555557AAAAAAA8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(2),
      I2 => s_axis_tdata(0),
      I3 => s_axis_tdata(1),
      I4 => s_axis_tdata(3),
      I5 => s_axis_tdata(4),
      O => abs16_return(4)
    );
\max_abs[5]_i_1\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"55555557AAAAAAA8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(3),
      I2 => \max_abs[5]_i_2_n_0\,
      I3 => s_axis_tdata(2),
      I4 => s_axis_tdata(4),
      I5 => s_axis_tdata(5),
      O => abs16_return(5)
    );
\max_abs[5]_i_2\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"E"
    )
        port map (
      I0 => s_axis_tdata(0),
      I1 => s_axis_tdata(1),
      O => \max_abs[5]_i_2_n_0\
    );
\max_abs[6]_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \max_abs[7]_i_2_n_0\,
      I2 => s_axis_tdata(6),
      O => abs16_return(6)
    );
\max_abs[7]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"57A8"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \max_abs[7]_i_2_n_0\,
      I2 => s_axis_tdata(6),
      I3 => s_axis_tdata(7),
      O => abs16_return(7)
    );
\max_abs[7]_i_2\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFFFFFFFFE"
    )
        port map (
      I0 => s_axis_tdata(4),
      I1 => s_axis_tdata(2),
      I2 => s_axis_tdata(0),
      I3 => s_axis_tdata(1),
      I4 => s_axis_tdata(3),
      I5 => s_axis_tdata(5),
      O => \max_abs[7]_i_2_n_0\
    );
\max_abs[8]_i_1\: unisim.vcomponents.LUT3
    generic map(
      INIT => X"78"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => clipping_i_4_n_0,
      I2 => s_axis_tdata(8),
      O => abs16_return(8)
    );
\max_abs[9]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"666A"
    )
        port map (
      I0 => s_axis_tdata(9),
      I1 => s_axis_tdata(15),
      I2 => s_axis_tdata(8),
      I3 => clipping_i_4_n_0,
      O => abs16_return(9)
    );
\max_abs_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => s_axis_tdata(0),
      Q => \^status1\(16),
      R => last_sign_valid
    );
\max_abs_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(10),
      Q => \^status1\(26),
      R => last_sign_valid
    );
\max_abs_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(11),
      Q => \^status1\(27),
      R => last_sign_valid
    );
\max_abs_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(12),
      Q => \^status1\(28),
      R => last_sign_valid
    );
\max_abs_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(13),
      Q => \^status1\(29),
      R => last_sign_valid
    );
\max_abs_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(14),
      Q => \^status1\(30),
      R => last_sign_valid
    );
\max_abs_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(15),
      Q => \^status1\(31),
      R => last_sign_valid
    );
\max_abs_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(1),
      Q => \^status1\(17),
      R => last_sign_valid
    );
\max_abs_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(2),
      Q => \^status1\(18),
      R => last_sign_valid
    );
\max_abs_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(3),
      Q => \^status1\(19),
      R => last_sign_valid
    );
\max_abs_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(4),
      Q => \^status1\(20),
      R => last_sign_valid
    );
\max_abs_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(5),
      Q => \^status1\(21),
      R => last_sign_valid
    );
\max_abs_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(6),
      Q => \^status1\(22),
      R => last_sign_valid
    );
\max_abs_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(7),
      Q => \^status1\(23),
      R => last_sign_valid
    );
\max_abs_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(8),
      Q => \^status1\(24),
      R => last_sign_valid
    );
\max_abs_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => max_abs,
      D => abs16_return(9),
      Q => \^status1\(25),
      R => last_sign_valid
    );
max_sample0_carry: unisim.vcomponents.CARRY8
     port map (
      CI => '0',
      CI_TOP => '0',
      CO(7) => max_sample0_carry_n_0,
      CO(6) => max_sample0_carry_n_1,
      CO(5) => max_sample0_carry_n_2,
      CO(4) => max_sample0_carry_n_3,
      CO(3) => max_sample0_carry_n_4,
      CO(2) => max_sample0_carry_n_5,
      CO(1) => max_sample0_carry_n_6,
      CO(0) => max_sample0_carry_n_7,
      DI(7) => max_sample0_carry_i_1_n_0,
      DI(6) => max_sample0_carry_i_2_n_0,
      DI(5) => max_sample0_carry_i_3_n_0,
      DI(4) => max_sample0_carry_i_4_n_0,
      DI(3) => max_sample0_carry_i_5_n_0,
      DI(2) => max_sample0_carry_i_6_n_0,
      DI(1) => max_sample0_carry_i_7_n_0,
      DI(0) => max_sample0_carry_i_8_n_0,
      O(7 downto 0) => NLW_max_sample0_carry_O_UNCONNECTED(7 downto 0),
      S(7) => max_sample0_carry_i_9_n_0,
      S(6) => max_sample0_carry_i_10_n_0,
      S(5) => max_sample0_carry_i_11_n_0,
      S(4) => max_sample0_carry_i_12_n_0,
      S(3) => max_sample0_carry_i_13_n_0,
      S(2) => max_sample0_carry_i_14_n_0,
      S(1) => max_sample0_carry_i_15_n_0,
      S(0) => max_sample0_carry_i_16_n_0
    );
max_sample0_carry_i_1: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7150"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \^status3\(14),
      I2 => \^status3\(15),
      I3 => s_axis_tdata(14),
      O => max_sample0_carry_i_1_n_0
    );
max_sample0_carry_i_10: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(13),
      I1 => s_axis_tdata(13),
      I2 => \^status3\(12),
      I3 => s_axis_tdata(12),
      O => max_sample0_carry_i_10_n_0
    );
max_sample0_carry_i_11: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(11),
      I1 => s_axis_tdata(11),
      I2 => \^status3\(10),
      I3 => s_axis_tdata(10),
      O => max_sample0_carry_i_11_n_0
    );
max_sample0_carry_i_12: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => \^status3\(9),
      I1 => \^status3\(8),
      I2 => s_axis_tdata(9),
      I3 => s_axis_tdata(8),
      O => max_sample0_carry_i_12_n_0
    );
max_sample0_carry_i_13: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(7),
      I1 => s_axis_tdata(7),
      I2 => \^status3\(6),
      I3 => s_axis_tdata(6),
      O => max_sample0_carry_i_13_n_0
    );
max_sample0_carry_i_14: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(5),
      I1 => s_axis_tdata(5),
      I2 => \^status3\(4),
      I3 => s_axis_tdata(4),
      O => max_sample0_carry_i_14_n_0
    );
max_sample0_carry_i_15: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(3),
      I1 => s_axis_tdata(3),
      I2 => \^status3\(2),
      I3 => s_axis_tdata(2),
      O => max_sample0_carry_i_15_n_0
    );
max_sample0_carry_i_16: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => s_axis_tdata(1),
      I1 => s_axis_tdata(0),
      I2 => \^status3\(1),
      I3 => \^status3\(0),
      O => max_sample0_carry_i_16_n_0
    );
max_sample0_carry_i_2: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(13),
      I1 => \^status3\(13),
      I2 => s_axis_tdata(12),
      I3 => \^status3\(12),
      O => max_sample0_carry_i_2_n_0
    );
max_sample0_carry_i_3: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(11),
      I1 => \^status3\(11),
      I2 => s_axis_tdata(10),
      I3 => \^status3\(10),
      O => max_sample0_carry_i_3_n_0
    );
max_sample0_carry_i_4: unisim.vcomponents.LUT4
    generic map(
      INIT => X"20BA"
    )
        port map (
      I0 => s_axis_tdata(9),
      I1 => \^status3\(8),
      I2 => s_axis_tdata(8),
      I3 => \^status3\(9),
      O => max_sample0_carry_i_4_n_0
    );
max_sample0_carry_i_5: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(7),
      I1 => \^status3\(7),
      I2 => s_axis_tdata(6),
      I3 => \^status3\(6),
      O => max_sample0_carry_i_5_n_0
    );
max_sample0_carry_i_6: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(5),
      I1 => \^status3\(5),
      I2 => s_axis_tdata(4),
      I3 => \^status3\(4),
      O => max_sample0_carry_i_6_n_0
    );
max_sample0_carry_i_7: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(3),
      I1 => \^status3\(3),
      I2 => s_axis_tdata(2),
      I3 => \^status3\(2),
      O => max_sample0_carry_i_7_n_0
    );
max_sample0_carry_i_8: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => s_axis_tdata(1),
      I1 => \^status3\(1),
      I2 => s_axis_tdata(0),
      I3 => \^status3\(0),
      O => max_sample0_carry_i_8_n_0
    );
max_sample0_carry_i_9: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => \^status3\(15),
      I1 => \^status3\(14),
      I2 => s_axis_tdata(15),
      I3 => s_axis_tdata(14),
      O => max_sample0_carry_i_9_n_0
    );
\max_sample[15]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => ctrl_sync(1),
      I1 => \^active_reg_0\,
      I2 => s_axis_tvalid,
      I3 => max_sample0_carry_n_0,
      O => \max_sample[15]_i_1_n_0\
    );
\max_sample_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(0),
      Q => \^status3\(0),
      R => last_sign_valid
    );
\max_sample_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(10),
      Q => \^status3\(10),
      R => last_sign_valid
    );
\max_sample_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(11),
      Q => \^status3\(11),
      R => last_sign_valid
    );
\max_sample_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(12),
      Q => \^status3\(12),
      R => last_sign_valid
    );
\max_sample_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(13),
      Q => \^status3\(13),
      R => last_sign_valid
    );
\max_sample_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(14),
      Q => \^status3\(14),
      R => last_sign_valid
    );
\max_sample_reg[15]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(15),
      Q => \^status3\(15),
      S => last_sign_valid
    );
\max_sample_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(1),
      Q => \^status3\(1),
      R => last_sign_valid
    );
\max_sample_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(2),
      Q => \^status3\(2),
      R => last_sign_valid
    );
\max_sample_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(3),
      Q => \^status3\(3),
      R => last_sign_valid
    );
\max_sample_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(4),
      Q => \^status3\(4),
      R => last_sign_valid
    );
\max_sample_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(5),
      Q => \^status3\(5),
      R => last_sign_valid
    );
\max_sample_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(6),
      Q => \^status3\(6),
      R => last_sign_valid
    );
\max_sample_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(7),
      Q => \^status3\(7),
      R => last_sign_valid
    );
\max_sample_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(8),
      Q => \^status3\(8),
      R => last_sign_valid
    );
\max_sample_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \max_sample[15]_i_1_n_0\,
      D => s_axis_tdata(9),
      Q => \^status3\(9),
      R => last_sign_valid
    );
mem_reg_bram_0: unisim.vcomponents.RAMB36E2
    generic map(
      CASCADE_ORDER_A => "NONE",
      CASCADE_ORDER_B => "FIRST",
      CLOCK_DOMAINS => "COMMON",
      DOA_REG => 0,
      DOB_REG => 0,
      ENADDRENA => "FALSE",
      ENADDRENB => "FALSE",
      EN_ECC_PIPE => "FALSE",
      EN_ECC_READ => "FALSE",
      EN_ECC_WRITE => "FALSE",
      INIT_A => X"000000000",
      INIT_B => X"000000000",
      INIT_FILE => "NONE",
      RDADDRCHANGEA => "FALSE",
      RDADDRCHANGEB => "FALSE",
      READ_WIDTH_A => 9,
      READ_WIDTH_B => 9,
      RSTREG_PRIORITY_A => "RSTREG",
      RSTREG_PRIORITY_B => "RSTREG",
      SIM_COLLISION_CHECK => "ALL",
      SLEEP_ASYNC => "FALSE",
      SRVAL_A => X"000000000",
      SRVAL_B => X"000000000",
      WRITE_MODE_A => "READ_FIRST",
      WRITE_MODE_B => "WRITE_FIRST",
      WRITE_WIDTH_A => 9,
      WRITE_WIDTH_B => 9
    )
        port map (
      ADDRARDADDR(14 downto 3) => wr_addr_reg(11 downto 0),
      ADDRARDADDR(2 downto 0) => B"111",
      ADDRBWRADDR(14 downto 3) => ctrl_sync(13 downto 2),
      ADDRBWRADDR(2 downto 0) => B"111",
      ADDRENA => '1',
      ADDRENB => '1',
      CASDIMUXA => '0',
      CASDIMUXB => '0',
      CASDINA(31 downto 0) => B"00000000000000000000000000000000",
      CASDINB(31 downto 0) => B"00000000000000000000000000000000",
      CASDINPA(3 downto 0) => B"0000",
      CASDINPB(3 downto 0) => B"0000",
      CASDOMUXA => '0',
      CASDOMUXB => '0',
      CASDOMUXEN_A => '1',
      CASDOMUXEN_B => '1',
      CASDOUTA(31 downto 0) => NLW_mem_reg_bram_0_CASDOUTA_UNCONNECTED(31 downto 0),
      CASDOUTB(31 downto 8) => NLW_mem_reg_bram_0_CASDOUTB_UNCONNECTED(31 downto 8),
      CASDOUTB(7) => mem_reg_bram_0_n_60,
      CASDOUTB(6) => mem_reg_bram_0_n_61,
      CASDOUTB(5) => mem_reg_bram_0_n_62,
      CASDOUTB(4) => mem_reg_bram_0_n_63,
      CASDOUTB(3) => mem_reg_bram_0_n_64,
      CASDOUTB(2) => mem_reg_bram_0_n_65,
      CASDOUTB(1) => mem_reg_bram_0_n_66,
      CASDOUTB(0) => mem_reg_bram_0_n_67,
      CASDOUTPA(3 downto 0) => NLW_mem_reg_bram_0_CASDOUTPA_UNCONNECTED(3 downto 0),
      CASDOUTPB(3 downto 1) => NLW_mem_reg_bram_0_CASDOUTPB_UNCONNECTED(3 downto 1),
      CASDOUTPB(0) => mem_reg_bram_0_n_139,
      CASINDBITERR => '0',
      CASINSBITERR => '0',
      CASOREGIMUXA => '0',
      CASOREGIMUXB => '0',
      CASOREGIMUXEN_A => '1',
      CASOREGIMUXEN_B => '1',
      CASOUTDBITERR => mem_reg_bram_0_n_0,
      CASOUTSBITERR => mem_reg_bram_0_n_1,
      CLKARDCLK => aclk,
      CLKBWRCLK => aclk,
      DBITERR => NLW_mem_reg_bram_0_DBITERR_UNCONNECTED,
      DINADIN(31 downto 8) => B"000000000000000000000000",
      DINADIN(7 downto 0) => s_axis_tdata(7 downto 0),
      DINBDIN(31 downto 0) => B"00000000000000000000000011111111",
      DINPADINP(3 downto 1) => B"000",
      DINPADINP(0) => s_axis_tdata(8),
      DINPBDINP(3 downto 0) => B"0001",
      DOUTADOUT(31 downto 0) => NLW_mem_reg_bram_0_DOUTADOUT_UNCONNECTED(31 downto 0),
      DOUTBDOUT(31 downto 0) => NLW_mem_reg_bram_0_DOUTBDOUT_UNCONNECTED(31 downto 0),
      DOUTPADOUTP(3 downto 0) => NLW_mem_reg_bram_0_DOUTPADOUTP_UNCONNECTED(3 downto 0),
      DOUTPBDOUTP(3 downto 0) => NLW_mem_reg_bram_0_DOUTPBDOUTP_UNCONNECTED(3 downto 0),
      ECCPARITY(7 downto 0) => NLW_mem_reg_bram_0_ECCPARITY_UNCONNECTED(7 downto 0),
      ECCPIPECE => '1',
      ENARDEN => mem_reg_bram_0_i_1_n_0,
      ENBWREN => mem_reg_bram_1_i_1_n_0,
      INJECTDBITERR => '0',
      INJECTSBITERR => '0',
      RDADDRECC(8 downto 0) => NLW_mem_reg_bram_0_RDADDRECC_UNCONNECTED(8 downto 0),
      REGCEAREGCE => '1',
      REGCEB => '1',
      RSTRAMARSTRAM => '0',
      RSTRAMB => '0',
      RSTREGARSTREG => '0',
      RSTREGB => '0',
      SBITERR => NLW_mem_reg_bram_0_SBITERR_UNCONNECTED,
      SLEEP => '0',
      WEA(3) => mem_reg_bram_0_i_2_n_0,
      WEA(2) => mem_reg_bram_0_i_2_n_0,
      WEA(1) => mem_reg_bram_0_i_2_n_0,
      WEA(0) => mem_reg_bram_0_i_2_n_0,
      WEBWE(7 downto 0) => B"00000000"
    );
mem_reg_bram_0_i_1: unisim.vcomponents.LUT3
    generic map(
      INIT => X"08"
    )
        port map (
      I0 => s_axis_tvalid,
      I1 => \^active_reg_0\,
      I2 => wr_addr_reg(12),
      O => mem_reg_bram_0_i_1_n_0
    );
mem_reg_bram_0_i_2: unisim.vcomponents.LUT2
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => wr_full,
      I1 => wr_addr_reg(12),
      O => mem_reg_bram_0_i_2_n_0
    );
mem_reg_bram_1: unisim.vcomponents.RAMB36E2
    generic map(
      CASCADE_ORDER_A => "NONE",
      CASCADE_ORDER_B => "LAST",
      CLOCK_DOMAINS => "COMMON",
      DOA_REG => 0,
      DOB_REG => 0,
      ENADDRENA => "FALSE",
      ENADDRENB => "FALSE",
      EN_ECC_PIPE => "FALSE",
      EN_ECC_READ => "FALSE",
      EN_ECC_WRITE => "FALSE",
      INIT_A => X"000000000",
      INIT_B => X"000000000",
      INIT_FILE => "NONE",
      RDADDRCHANGEA => "FALSE",
      RDADDRCHANGEB => "FALSE",
      READ_WIDTH_A => 9,
      READ_WIDTH_B => 9,
      RSTREG_PRIORITY_A => "RSTREG",
      RSTREG_PRIORITY_B => "RSTREG",
      SIM_COLLISION_CHECK => "ALL",
      SLEEP_ASYNC => "FALSE",
      SRVAL_A => X"000000000",
      SRVAL_B => X"000000000",
      WRITE_MODE_A => "READ_FIRST",
      WRITE_MODE_B => "WRITE_FIRST",
      WRITE_WIDTH_A => 9,
      WRITE_WIDTH_B => 9
    )
        port map (
      ADDRARDADDR(14 downto 3) => wr_addr_reg(11 downto 0),
      ADDRARDADDR(2 downto 0) => B"111",
      ADDRBWRADDR(14 downto 3) => ctrl_sync(13 downto 2),
      ADDRBWRADDR(2 downto 0) => B"111",
      ADDRENA => '1',
      ADDRENB => '1',
      CASDIMUXA => '0',
      CASDIMUXB => '0',
      CASDINA(31 downto 0) => B"00000000000000000000000000000000",
      CASDINB(31 downto 8) => B"000000000000000000000000",
      CASDINB(7) => mem_reg_bram_0_n_60,
      CASDINB(6) => mem_reg_bram_0_n_61,
      CASDINB(5) => mem_reg_bram_0_n_62,
      CASDINB(4) => mem_reg_bram_0_n_63,
      CASDINB(3) => mem_reg_bram_0_n_64,
      CASDINB(2) => mem_reg_bram_0_n_65,
      CASDINB(1) => mem_reg_bram_0_n_66,
      CASDINB(0) => mem_reg_bram_0_n_67,
      CASDINPA(3 downto 0) => B"0000",
      CASDINPB(3 downto 1) => B"000",
      CASDINPB(0) => mem_reg_bram_0_n_139,
      CASDOMUXA => '0',
      CASDOMUXB => mem_reg_bram_1_i_1_n_0,
      CASDOMUXEN_A => '1',
      CASDOMUXEN_B => '1',
      CASDOUTA(31 downto 0) => NLW_mem_reg_bram_1_CASDOUTA_UNCONNECTED(31 downto 0),
      CASDOUTB(31 downto 0) => NLW_mem_reg_bram_1_CASDOUTB_UNCONNECTED(31 downto 0),
      CASDOUTPA(3 downto 0) => NLW_mem_reg_bram_1_CASDOUTPA_UNCONNECTED(3 downto 0),
      CASDOUTPB(3 downto 0) => NLW_mem_reg_bram_1_CASDOUTPB_UNCONNECTED(3 downto 0),
      CASINDBITERR => mem_reg_bram_0_n_0,
      CASINSBITERR => mem_reg_bram_0_n_1,
      CASOREGIMUXA => '0',
      CASOREGIMUXB => '0',
      CASOREGIMUXEN_A => '1',
      CASOREGIMUXEN_B => '1',
      CASOUTDBITERR => NLW_mem_reg_bram_1_CASOUTDBITERR_UNCONNECTED,
      CASOUTSBITERR => NLW_mem_reg_bram_1_CASOUTSBITERR_UNCONNECTED,
      CLKARDCLK => aclk,
      CLKBWRCLK => aclk,
      DBITERR => NLW_mem_reg_bram_1_DBITERR_UNCONNECTED,
      DINADIN(31 downto 8) => B"000000000000000000000000",
      DINADIN(7 downto 0) => s_axis_tdata(7 downto 0),
      DINBDIN(31 downto 0) => B"00000000000000000000000011111111",
      DINPADINP(3 downto 1) => B"000",
      DINPADINP(0) => s_axis_tdata(8),
      DINPBDINP(3 downto 0) => B"0001",
      DOUTADOUT(31 downto 0) => NLW_mem_reg_bram_1_DOUTADOUT_UNCONNECTED(31 downto 0),
      DOUTBDOUT(31 downto 8) => NLW_mem_reg_bram_1_DOUTBDOUT_UNCONNECTED(31 downto 8),
      DOUTBDOUT(7 downto 0) => status_capture(7 downto 0),
      DOUTPADOUTP(3 downto 0) => NLW_mem_reg_bram_1_DOUTPADOUTP_UNCONNECTED(3 downto 0),
      DOUTPBDOUTP(3 downto 1) => NLW_mem_reg_bram_1_DOUTPBDOUTP_UNCONNECTED(3 downto 1),
      DOUTPBDOUTP(0) => status_capture(8),
      ECCPARITY(7 downto 0) => NLW_mem_reg_bram_1_ECCPARITY_UNCONNECTED(7 downto 0),
      ECCPIPECE => '1',
      ENARDEN => mem_reg_bram_1_i_2_n_0,
      ENBWREN => ctrl_sync(14),
      INJECTDBITERR => '0',
      INJECTSBITERR => '0',
      RDADDRECC(8 downto 0) => NLW_mem_reg_bram_1_RDADDRECC_UNCONNECTED(8 downto 0),
      REGCEAREGCE => '1',
      REGCEB => '1',
      RSTRAMARSTRAM => '0',
      RSTRAMB => '0',
      RSTREGARSTREG => '0',
      RSTREGB => '0',
      SBITERR => NLW_mem_reg_bram_1_SBITERR_UNCONNECTED,
      SLEEP => '0',
      WEA(3) => mem_reg_bram_1_i_3_n_0,
      WEA(2) => mem_reg_bram_1_i_3_n_0,
      WEA(1) => mem_reg_bram_1_i_3_n_0,
      WEA(0) => mem_reg_bram_1_i_3_n_0,
      WEBWE(7 downto 0) => B"00000000"
    );
mem_reg_bram_1_i_1: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => ctrl_sync(14),
      O => mem_reg_bram_1_i_1_n_0
    );
mem_reg_bram_1_i_2: unisim.vcomponents.LUT3
    generic map(
      INIT => X"80"
    )
        port map (
      I0 => s_axis_tvalid,
      I1 => \^active_reg_0\,
      I2 => wr_addr_reg(12),
      O => mem_reg_bram_1_i_2_n_0
    );
mem_reg_bram_1_i_3: unisim.vcomponents.LUT2
    generic map(
      INIT => X"2"
    )
        port map (
      I0 => wr_addr_reg(12),
      I1 => wr_full,
      O => mem_reg_bram_1_i_3_n_0
    );
mem_reg_bram_2: unisim.vcomponents.RAMB36E2
    generic map(
      CASCADE_ORDER_A => "NONE",
      CASCADE_ORDER_B => "NONE",
      CLOCK_DOMAINS => "COMMON",
      DOA_REG => 0,
      DOB_REG => 0,
      ENADDRENA => "FALSE",
      ENADDRENB => "FALSE",
      EN_ECC_PIPE => "FALSE",
      EN_ECC_READ => "FALSE",
      EN_ECC_WRITE => "FALSE",
      INIT_A => X"000000000",
      INIT_B => X"000000000",
      INIT_FILE => "NONE",
      RDADDRCHANGEA => "FALSE",
      RDADDRCHANGEB => "FALSE",
      READ_WIDTH_A => 4,
      READ_WIDTH_B => 4,
      RSTREG_PRIORITY_A => "RSTREG",
      RSTREG_PRIORITY_B => "RSTREG",
      SIM_COLLISION_CHECK => "ALL",
      SLEEP_ASYNC => "FALSE",
      SRVAL_A => X"000000000",
      SRVAL_B => X"000000000",
      WRITE_MODE_A => "READ_FIRST",
      WRITE_MODE_B => "WRITE_FIRST",
      WRITE_WIDTH_A => 4,
      WRITE_WIDTH_B => 4
    )
        port map (
      ADDRARDADDR(14 downto 2) => wr_addr_reg(12 downto 0),
      ADDRARDADDR(1 downto 0) => B"11",
      ADDRBWRADDR(14 downto 2) => ctrl_sync(14 downto 2),
      ADDRBWRADDR(1 downto 0) => B"11",
      ADDRENA => '1',
      ADDRENB => '1',
      CASDIMUXA => '0',
      CASDIMUXB => '0',
      CASDINA(31 downto 0) => B"00000000000000000000000000000000",
      CASDINB(31 downto 0) => B"00000000000000000000000000000000",
      CASDINPA(3 downto 0) => B"0000",
      CASDINPB(3 downto 0) => B"0000",
      CASDOMUXA => '0',
      CASDOMUXB => '0',
      CASDOMUXEN_A => '1',
      CASDOMUXEN_B => '1',
      CASDOUTA(31 downto 0) => NLW_mem_reg_bram_2_CASDOUTA_UNCONNECTED(31 downto 0),
      CASDOUTB(31 downto 0) => NLW_mem_reg_bram_2_CASDOUTB_UNCONNECTED(31 downto 0),
      CASDOUTPA(3 downto 0) => NLW_mem_reg_bram_2_CASDOUTPA_UNCONNECTED(3 downto 0),
      CASDOUTPB(3 downto 0) => NLW_mem_reg_bram_2_CASDOUTPB_UNCONNECTED(3 downto 0),
      CASINDBITERR => '0',
      CASINSBITERR => '0',
      CASOREGIMUXA => '0',
      CASOREGIMUXB => '0',
      CASOREGIMUXEN_A => '1',
      CASOREGIMUXEN_B => '1',
      CASOUTDBITERR => NLW_mem_reg_bram_2_CASOUTDBITERR_UNCONNECTED,
      CASOUTSBITERR => NLW_mem_reg_bram_2_CASOUTSBITERR_UNCONNECTED,
      CLKARDCLK => aclk,
      CLKBWRCLK => aclk,
      DBITERR => NLW_mem_reg_bram_2_DBITERR_UNCONNECTED,
      DINADIN(31 downto 4) => B"0000000000000000000000000000",
      DINADIN(3 downto 0) => s_axis_tdata(12 downto 9),
      DINBDIN(31 downto 0) => B"00000000000000000000000000001111",
      DINPADINP(3 downto 0) => B"0000",
      DINPBDINP(3 downto 0) => B"0000",
      DOUTADOUT(31 downto 0) => NLW_mem_reg_bram_2_DOUTADOUT_UNCONNECTED(31 downto 0),
      DOUTBDOUT(31 downto 4) => NLW_mem_reg_bram_2_DOUTBDOUT_UNCONNECTED(31 downto 4),
      DOUTBDOUT(3 downto 0) => status_capture(12 downto 9),
      DOUTPADOUTP(3 downto 0) => NLW_mem_reg_bram_2_DOUTPADOUTP_UNCONNECTED(3 downto 0),
      DOUTPBDOUTP(3 downto 0) => NLW_mem_reg_bram_2_DOUTPBDOUTP_UNCONNECTED(3 downto 0),
      ECCPARITY(7 downto 0) => NLW_mem_reg_bram_2_ECCPARITY_UNCONNECTED(7 downto 0),
      ECCPIPECE => '1',
      ENARDEN => mem_reg_bram_3_i_1_n_0,
      ENBWREN => '1',
      INJECTDBITERR => '0',
      INJECTSBITERR => '0',
      RDADDRECC(8 downto 0) => NLW_mem_reg_bram_2_RDADDRECC_UNCONNECTED(8 downto 0),
      REGCEAREGCE => '1',
      REGCEB => '1',
      RSTRAMARSTRAM => '0',
      RSTRAMB => '0',
      RSTREGARSTREG => '0',
      RSTREGB => '0',
      SBITERR => NLW_mem_reg_bram_2_SBITERR_UNCONNECTED,
      SLEEP => '0',
      WEA(3) => wr_full2,
      WEA(2) => wr_full2,
      WEA(1) => wr_full2,
      WEA(0) => wr_full2,
      WEBWE(7 downto 0) => B"00000000"
    );
mem_reg_bram_3: unisim.vcomponents.RAMB36E2
    generic map(
      CASCADE_ORDER_A => "NONE",
      CASCADE_ORDER_B => "NONE",
      CLOCK_DOMAINS => "COMMON",
      DOA_REG => 0,
      DOB_REG => 0,
      ENADDRENA => "FALSE",
      ENADDRENB => "FALSE",
      EN_ECC_PIPE => "FALSE",
      EN_ECC_READ => "FALSE",
      EN_ECC_WRITE => "FALSE",
      INIT_A => X"000000000",
      INIT_B => X"000000000",
      INIT_FILE => "NONE",
      RDADDRCHANGEA => "FALSE",
      RDADDRCHANGEB => "FALSE",
      READ_WIDTH_A => 4,
      READ_WIDTH_B => 4,
      RSTREG_PRIORITY_A => "RSTREG",
      RSTREG_PRIORITY_B => "RSTREG",
      SIM_COLLISION_CHECK => "ALL",
      SLEEP_ASYNC => "FALSE",
      SRVAL_A => X"000000000",
      SRVAL_B => X"000000000",
      WRITE_MODE_A => "READ_FIRST",
      WRITE_MODE_B => "WRITE_FIRST",
      WRITE_WIDTH_A => 4,
      WRITE_WIDTH_B => 4
    )
        port map (
      ADDRARDADDR(14 downto 2) => wr_addr_reg(12 downto 0),
      ADDRARDADDR(1 downto 0) => B"11",
      ADDRBWRADDR(14 downto 2) => ctrl_sync(14 downto 2),
      ADDRBWRADDR(1 downto 0) => B"11",
      ADDRENA => '1',
      ADDRENB => '1',
      CASDIMUXA => '0',
      CASDIMUXB => '0',
      CASDINA(31 downto 0) => B"00000000000000000000000000000000",
      CASDINB(31 downto 0) => B"00000000000000000000000000000000",
      CASDINPA(3 downto 0) => B"0000",
      CASDINPB(3 downto 0) => B"0000",
      CASDOMUXA => '0',
      CASDOMUXB => '0',
      CASDOMUXEN_A => '1',
      CASDOMUXEN_B => '1',
      CASDOUTA(31 downto 0) => NLW_mem_reg_bram_3_CASDOUTA_UNCONNECTED(31 downto 0),
      CASDOUTB(31 downto 0) => NLW_mem_reg_bram_3_CASDOUTB_UNCONNECTED(31 downto 0),
      CASDOUTPA(3 downto 0) => NLW_mem_reg_bram_3_CASDOUTPA_UNCONNECTED(3 downto 0),
      CASDOUTPB(3 downto 0) => NLW_mem_reg_bram_3_CASDOUTPB_UNCONNECTED(3 downto 0),
      CASINDBITERR => '0',
      CASINSBITERR => '0',
      CASOREGIMUXA => '0',
      CASOREGIMUXB => '0',
      CASOREGIMUXEN_A => '1',
      CASOREGIMUXEN_B => '1',
      CASOUTDBITERR => NLW_mem_reg_bram_3_CASOUTDBITERR_UNCONNECTED,
      CASOUTSBITERR => NLW_mem_reg_bram_3_CASOUTSBITERR_UNCONNECTED,
      CLKARDCLK => aclk,
      CLKBWRCLK => aclk,
      DBITERR => NLW_mem_reg_bram_3_DBITERR_UNCONNECTED,
      DINADIN(31 downto 3) => B"00000000000000000000000000000",
      DINADIN(2 downto 0) => s_axis_tdata(15 downto 13),
      DINBDIN(31 downto 0) => B"00000000000000000000000000000111",
      DINPADINP(3 downto 0) => B"0000",
      DINPBDINP(3 downto 0) => B"0000",
      DOUTADOUT(31 downto 0) => NLW_mem_reg_bram_3_DOUTADOUT_UNCONNECTED(31 downto 0),
      DOUTBDOUT(31 downto 3) => NLW_mem_reg_bram_3_DOUTBDOUT_UNCONNECTED(31 downto 3),
      DOUTBDOUT(2 downto 0) => status_capture(15 downto 13),
      DOUTPADOUTP(3 downto 0) => NLW_mem_reg_bram_3_DOUTPADOUTP_UNCONNECTED(3 downto 0),
      DOUTPBDOUTP(3 downto 0) => NLW_mem_reg_bram_3_DOUTPBDOUTP_UNCONNECTED(3 downto 0),
      ECCPARITY(7 downto 0) => NLW_mem_reg_bram_3_ECCPARITY_UNCONNECTED(7 downto 0),
      ECCPIPECE => '1',
      ENARDEN => mem_reg_bram_3_i_1_n_0,
      ENBWREN => '1',
      INJECTDBITERR => '0',
      INJECTSBITERR => '0',
      RDADDRECC(8 downto 0) => NLW_mem_reg_bram_3_RDADDRECC_UNCONNECTED(8 downto 0),
      REGCEAREGCE => '1',
      REGCEB => '1',
      RSTRAMARSTRAM => '0',
      RSTRAMB => '0',
      RSTREGARSTREG => '0',
      RSTREGB => '0',
      SBITERR => NLW_mem_reg_bram_3_SBITERR_UNCONNECTED,
      SLEEP => '0',
      WEA(3) => wr_full2,
      WEA(2) => wr_full2,
      WEA(1) => wr_full2,
      WEA(0) => wr_full2,
      WEBWE(7 downto 0) => B"00000000"
    );
mem_reg_bram_3_i_1: unisim.vcomponents.LUT2
    generic map(
      INIT => X"8"
    )
        port map (
      I0 => \^active_reg_0\,
      I1 => s_axis_tvalid,
      O => mem_reg_bram_3_i_1_n_0
    );
mem_reg_bram_3_i_2: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => wr_full,
      O => wr_full2
    );
min_sample0_carry: unisim.vcomponents.CARRY8
     port map (
      CI => '0',
      CI_TOP => '0',
      CO(7) => min_sample0_carry_n_0,
      CO(6) => min_sample0_carry_n_1,
      CO(5) => min_sample0_carry_n_2,
      CO(4) => min_sample0_carry_n_3,
      CO(3) => min_sample0_carry_n_4,
      CO(2) => min_sample0_carry_n_5,
      CO(1) => min_sample0_carry_n_6,
      CO(0) => min_sample0_carry_n_7,
      DI(7) => min_sample0_carry_i_1_n_0,
      DI(6) => min_sample0_carry_i_2_n_0,
      DI(5) => min_sample0_carry_i_3_n_0,
      DI(4) => min_sample0_carry_i_4_n_0,
      DI(3) => min_sample0_carry_i_5_n_0,
      DI(2) => min_sample0_carry_i_6_n_0,
      DI(1) => min_sample0_carry_i_7_n_0,
      DI(0) => min_sample0_carry_i_8_n_0,
      O(7 downto 0) => NLW_min_sample0_carry_O_UNCONNECTED(7 downto 0),
      S(7) => min_sample0_carry_i_9_n_0,
      S(6) => min_sample0_carry_i_10_n_0,
      S(5) => min_sample0_carry_i_11_n_0,
      S(4) => min_sample0_carry_i_12_n_0,
      S(3) => min_sample0_carry_i_13_n_0,
      S(2) => min_sample0_carry_i_14_n_0,
      S(1) => min_sample0_carry_i_15_n_0,
      S(0) => min_sample0_carry_i_16_n_0
    );
min_sample0_carry_i_1: unisim.vcomponents.LUT4
    generic map(
      INIT => X"0A8E"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => \^status3\(30),
      I2 => \^status3\(31),
      I3 => s_axis_tdata(14),
      O => min_sample0_carry_i_1_n_0
    );
min_sample0_carry_i_10: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(29),
      I1 => s_axis_tdata(13),
      I2 => \^status3\(28),
      I3 => s_axis_tdata(12),
      O => min_sample0_carry_i_10_n_0
    );
min_sample0_carry_i_11: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(27),
      I1 => s_axis_tdata(11),
      I2 => \^status3\(26),
      I3 => s_axis_tdata(10),
      O => min_sample0_carry_i_11_n_0
    );
min_sample0_carry_i_12: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => \^status3\(25),
      I1 => \^status3\(24),
      I2 => s_axis_tdata(9),
      I3 => s_axis_tdata(8),
      O => min_sample0_carry_i_12_n_0
    );
min_sample0_carry_i_13: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(23),
      I1 => s_axis_tdata(7),
      I2 => \^status3\(22),
      I3 => s_axis_tdata(6),
      O => min_sample0_carry_i_13_n_0
    );
min_sample0_carry_i_14: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(21),
      I1 => s_axis_tdata(5),
      I2 => \^status3\(20),
      I3 => s_axis_tdata(4),
      O => min_sample0_carry_i_14_n_0
    );
min_sample0_carry_i_15: unisim.vcomponents.LUT4
    generic map(
      INIT => X"9009"
    )
        port map (
      I0 => \^status3\(19),
      I1 => s_axis_tdata(3),
      I2 => \^status3\(18),
      I3 => s_axis_tdata(2),
      O => min_sample0_carry_i_15_n_0
    );
min_sample0_carry_i_16: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => s_axis_tdata(1),
      I1 => s_axis_tdata(0),
      I2 => \^status3\(17),
      I3 => \^status3\(16),
      O => min_sample0_carry_i_16_n_0
    );
min_sample0_carry_i_2: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => \^status3\(29),
      I1 => s_axis_tdata(13),
      I2 => \^status3\(28),
      I3 => s_axis_tdata(12),
      O => min_sample0_carry_i_2_n_0
    );
min_sample0_carry_i_3: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => \^status3\(27),
      I1 => s_axis_tdata(11),
      I2 => \^status3\(26),
      I3 => s_axis_tdata(10),
      O => min_sample0_carry_i_3_n_0
    );
min_sample0_carry_i_4: unisim.vcomponents.LUT4
    generic map(
      INIT => X"50D4"
    )
        port map (
      I0 => s_axis_tdata(9),
      I1 => \^status3\(24),
      I2 => \^status3\(25),
      I3 => s_axis_tdata(8),
      O => min_sample0_carry_i_4_n_0
    );
min_sample0_carry_i_5: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => \^status3\(23),
      I1 => s_axis_tdata(7),
      I2 => \^status3\(22),
      I3 => s_axis_tdata(6),
      O => min_sample0_carry_i_5_n_0
    );
min_sample0_carry_i_6: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => \^status3\(21),
      I1 => s_axis_tdata(5),
      I2 => \^status3\(20),
      I3 => s_axis_tdata(4),
      O => min_sample0_carry_i_6_n_0
    );
min_sample0_carry_i_7: unisim.vcomponents.LUT4
    generic map(
      INIT => X"22B2"
    )
        port map (
      I0 => \^status3\(19),
      I1 => s_axis_tdata(3),
      I2 => \^status3\(18),
      I3 => s_axis_tdata(2),
      O => min_sample0_carry_i_7_n_0
    );
min_sample0_carry_i_8: unisim.vcomponents.LUT4
    generic map(
      INIT => X"50D4"
    )
        port map (
      I0 => s_axis_tdata(1),
      I1 => \^status3\(16),
      I2 => \^status3\(17),
      I3 => s_axis_tdata(0),
      O => min_sample0_carry_i_8_n_0
    );
min_sample0_carry_i_9: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8421"
    )
        port map (
      I0 => \^status3\(31),
      I1 => \^status3\(30),
      I2 => s_axis_tdata(15),
      I3 => s_axis_tdata(14),
      O => min_sample0_carry_i_9_n_0
    );
\min_sample[15]_i_1\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"8000"
    )
        port map (
      I0 => ctrl_sync(1),
      I1 => \^active_reg_0\,
      I2 => s_axis_tvalid,
      I3 => min_sample0_carry_n_0,
      O => min_sample
    );
\min_sample_reg[0]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(0),
      Q => \^status3\(16),
      S => last_sign_valid
    );
\min_sample_reg[10]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(10),
      Q => \^status3\(26),
      S => last_sign_valid
    );
\min_sample_reg[11]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(11),
      Q => \^status3\(27),
      S => last_sign_valid
    );
\min_sample_reg[12]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(12),
      Q => \^status3\(28),
      S => last_sign_valid
    );
\min_sample_reg[13]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(13),
      Q => \^status3\(29),
      S => last_sign_valid
    );
\min_sample_reg[14]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(14),
      Q => \^status3\(30),
      S => last_sign_valid
    );
\min_sample_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(15),
      Q => \^status3\(31),
      R => last_sign_valid
    );
\min_sample_reg[1]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(1),
      Q => \^status3\(17),
      S => last_sign_valid
    );
\min_sample_reg[2]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(2),
      Q => \^status3\(18),
      S => last_sign_valid
    );
\min_sample_reg[3]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(3),
      Q => \^status3\(19),
      S => last_sign_valid
    );
\min_sample_reg[4]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(4),
      Q => \^status3\(20),
      S => last_sign_valid
    );
\min_sample_reg[5]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(5),
      Q => \^status3\(21),
      S => last_sign_valid
    );
\min_sample_reg[6]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(6),
      Q => \^status3\(22),
      S => last_sign_valid
    );
\min_sample_reg[7]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(7),
      Q => \^status3\(23),
      S => last_sign_valid
    );
\min_sample_reg[8]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(8),
      Q => \^status3\(24),
      S => last_sign_valid
    );
\min_sample_reg[9]\: unisim.vcomponents.FDSE
    generic map(
      INIT => '1'
    )
        port map (
      C => aclk,
      CE => min_sample,
      D => s_axis_tdata(9),
      Q => \^status3\(25),
      S => last_sign_valid
    );
overflow_i_1: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF22F2"
    )
        port map (
      I0 => saw_sign_change,
      I1 => overflow_i_3_n_0,
      I2 => last_sign_0,
      I3 => overflow_i_4_n_0,
      I4 => \^status0\(2),
      O => overflow_i_1_n_0
    );
overflow_i_10: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFF7F"
    )
        port map (
      I0 => \^o15\(15),
      I1 => \^o15\(14),
      I2 => count_reg(16),
      I3 => overflow_i_16_n_0,
      I4 => overflow_i_17_n_0,
      O => overflow_i_10_n_0
    );
overflow_i_11: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => \^status2\(13),
      I1 => \^status2\(12),
      I2 => \^status2\(15),
      I3 => \^status2\(14),
      O => overflow_i_11_n_0
    );
overflow_i_12: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => \^status2\(5),
      I1 => \^status2\(4),
      I2 => \^status2\(7),
      I3 => \^status2\(6),
      O => overflow_i_12_n_0
    );
overflow_i_13: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => \^status2\(29),
      I1 => \^status2\(28),
      I2 => \^status2\(31),
      I3 => \^status2\(30),
      O => overflow_i_13_n_0
    );
overflow_i_14: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => \^status2\(21),
      I1 => \^status2\(20),
      I2 => \^status2\(23),
      I3 => \^status2\(22),
      O => overflow_i_14_n_0
    );
overflow_i_15: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => count_reg(26),
      I1 => count_reg(25),
      I2 => count_reg(28),
      I3 => count_reg(27),
      O => overflow_i_15_n_0
    );
overflow_i_16: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => count_reg(30),
      I1 => count_reg(29),
      I2 => \^o15\(13),
      I3 => count_reg(31),
      O => overflow_i_16_n_0
    );
overflow_i_17: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => count_reg(18),
      I1 => count_reg(17),
      I2 => count_reg(20),
      I3 => count_reg(19),
      O => overflow_i_17_n_0
    );
overflow_i_2: unisim.vcomponents.LUT6
    generic map(
      INIT => X"6000000000000000"
    )
        port map (
      I0 => last_sign,
      I1 => s_axis_tdata(15),
      I2 => s_axis_tvalid,
      I3 => \^active_reg_0\,
      I4 => ctrl_sync(1),
      I5 => last_sign_valid_reg_n_0,
      O => saw_sign_change
    );
overflow_i_3: unisim.vcomponents.LUT4
    generic map(
      INIT => X"FFFE"
    )
        port map (
      I0 => overflow_i_5_n_0,
      I1 => overflow_i_6_n_0,
      I2 => overflow_i_7_n_0,
      I3 => overflow_i_8_n_0,
      O => overflow_i_3_n_0
    );
overflow_i_4: unisim.vcomponents.LUT3
    generic map(
      INIT => X"FE"
    )
        port map (
      I0 => active_i_3_n_0,
      I1 => overflow_i_9_n_0,
      I2 => overflow_i_10_n_0,
      O => overflow_i_4_n_0
    );
overflow_i_5: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => \^status2\(10),
      I1 => \^status2\(11),
      I2 => \^status2\(8),
      I3 => \^status2\(9),
      I4 => overflow_i_11_n_0,
      O => overflow_i_5_n_0
    );
overflow_i_6: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => \^status2\(2),
      I1 => \^status2\(3),
      I2 => \^status2\(0),
      I3 => \^status2\(1),
      I4 => overflow_i_12_n_0,
      O => overflow_i_6_n_0
    );
overflow_i_7: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => \^status2\(26),
      I1 => \^status2\(27),
      I2 => \^status2\(24),
      I3 => \^status2\(25),
      I4 => overflow_i_13_n_0,
      O => overflow_i_7_n_0
    );
overflow_i_8: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => \^status2\(18),
      I1 => \^status2\(19),
      I2 => \^status2\(16),
      I3 => \^status2\(17),
      I4 => overflow_i_14_n_0,
      O => overflow_i_8_n_0
    );
overflow_i_9: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF7FFF"
    )
        port map (
      I0 => count_reg(23),
      I1 => count_reg(24),
      I2 => count_reg(21),
      I3 => count_reg(22),
      I4 => overflow_i_15_n_0,
      O => overflow_i_9_n_0
    );
overflow_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => overflow_i_1_n_0,
      Q => \^status0\(2),
      R => last_sign_valid
    );
saw_nonzero_i_1: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFF0E0"
    )
        port map (
      I0 => s_axis_tdata(15),
      I1 => s_axis_tdata(14),
      I2 => last_sign_0,
      I3 => saw_nonzero_i_2_n_0,
      I4 => \^status0\(3),
      O => saw_nonzero_i_1_n_0
    );
saw_nonzero_i_2: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFFFFFE"
    )
        port map (
      I0 => s_axis_tdata(12),
      I1 => s_axis_tdata(10),
      I2 => max_abs0_carry_i_17_n_0,
      I3 => s_axis_tdata(11),
      I4 => s_axis_tdata(13),
      O => saw_nonzero_i_2_n_0
    );
saw_nonzero_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => saw_nonzero_i_1_n_0,
      Q => \^status0\(3),
      R => last_sign_valid
    );
saw_sign_change_i_1: unisim.vcomponents.LUT5
    generic map(
      INIT => X"FFFF0880"
    )
        port map (
      I0 => last_sign_valid_reg_n_0,
      I1 => last_sign_0,
      I2 => s_axis_tdata(15),
      I3 => last_sign,
      I4 => \^status0\(1),
      O => saw_sign_change_i_1_n_0
    );
saw_sign_change_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => saw_sign_change_i_1_n_0,
      Q => \^status0\(1),
      R => last_sign_valid
    );
\sign_changes[31]_i_1\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"00808000"
    )
        port map (
      I0 => overflow_i_3_n_0,
      I1 => last_sign_valid_reg_n_0,
      I2 => last_sign_0,
      I3 => s_axis_tdata(15),
      I4 => last_sign,
      O => \sign_changes[31]_i_1_n_0\
    );
\sign_changes[7]_i_2\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => \^status2\(0),
      O => \sign_changes[7]_i_2_n_0\
    );
\sign_changes_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_15\,
      Q => \^status2\(0),
      R => last_sign_valid
    );
\sign_changes_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_13\,
      Q => \^status2\(10),
      R => last_sign_valid
    );
\sign_changes_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_12\,
      Q => \^status2\(11),
      R => last_sign_valid
    );
\sign_changes_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_11\,
      Q => \^status2\(12),
      R => last_sign_valid
    );
\sign_changes_reg[13]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_10\,
      Q => \^status2\(13),
      R => last_sign_valid
    );
\sign_changes_reg[14]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_9\,
      Q => \^status2\(14),
      R => last_sign_valid
    );
\sign_changes_reg[15]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_8\,
      Q => \^status2\(15),
      R => last_sign_valid
    );
\sign_changes_reg[15]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => \sign_changes_reg[7]_i_1_n_0\,
      CI_TOP => '0',
      CO(7) => \sign_changes_reg[15]_i_1_n_0\,
      CO(6) => \sign_changes_reg[15]_i_1_n_1\,
      CO(5) => \sign_changes_reg[15]_i_1_n_2\,
      CO(4) => \sign_changes_reg[15]_i_1_n_3\,
      CO(3) => \sign_changes_reg[15]_i_1_n_4\,
      CO(2) => \sign_changes_reg[15]_i_1_n_5\,
      CO(1) => \sign_changes_reg[15]_i_1_n_6\,
      CO(0) => \sign_changes_reg[15]_i_1_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \sign_changes_reg[15]_i_1_n_8\,
      O(6) => \sign_changes_reg[15]_i_1_n_9\,
      O(5) => \sign_changes_reg[15]_i_1_n_10\,
      O(4) => \sign_changes_reg[15]_i_1_n_11\,
      O(3) => \sign_changes_reg[15]_i_1_n_12\,
      O(2) => \sign_changes_reg[15]_i_1_n_13\,
      O(1) => \sign_changes_reg[15]_i_1_n_14\,
      O(0) => \sign_changes_reg[15]_i_1_n_15\,
      S(7 downto 0) => \^status2\(15 downto 8)
    );
\sign_changes_reg[16]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_15\,
      Q => \^status2\(16),
      R => last_sign_valid
    );
\sign_changes_reg[17]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_14\,
      Q => \^status2\(17),
      R => last_sign_valid
    );
\sign_changes_reg[18]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_13\,
      Q => \^status2\(18),
      R => last_sign_valid
    );
\sign_changes_reg[19]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_12\,
      Q => \^status2\(19),
      R => last_sign_valid
    );
\sign_changes_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_14\,
      Q => \^status2\(1),
      R => last_sign_valid
    );
\sign_changes_reg[20]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_11\,
      Q => \^status2\(20),
      R => last_sign_valid
    );
\sign_changes_reg[21]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_10\,
      Q => \^status2\(21),
      R => last_sign_valid
    );
\sign_changes_reg[22]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_9\,
      Q => \^status2\(22),
      R => last_sign_valid
    );
\sign_changes_reg[23]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[23]_i_1_n_8\,
      Q => \^status2\(23),
      R => last_sign_valid
    );
\sign_changes_reg[23]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => \sign_changes_reg[15]_i_1_n_0\,
      CI_TOP => '0',
      CO(7) => \sign_changes_reg[23]_i_1_n_0\,
      CO(6) => \sign_changes_reg[23]_i_1_n_1\,
      CO(5) => \sign_changes_reg[23]_i_1_n_2\,
      CO(4) => \sign_changes_reg[23]_i_1_n_3\,
      CO(3) => \sign_changes_reg[23]_i_1_n_4\,
      CO(2) => \sign_changes_reg[23]_i_1_n_5\,
      CO(1) => \sign_changes_reg[23]_i_1_n_6\,
      CO(0) => \sign_changes_reg[23]_i_1_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \sign_changes_reg[23]_i_1_n_8\,
      O(6) => \sign_changes_reg[23]_i_1_n_9\,
      O(5) => \sign_changes_reg[23]_i_1_n_10\,
      O(4) => \sign_changes_reg[23]_i_1_n_11\,
      O(3) => \sign_changes_reg[23]_i_1_n_12\,
      O(2) => \sign_changes_reg[23]_i_1_n_13\,
      O(1) => \sign_changes_reg[23]_i_1_n_14\,
      O(0) => \sign_changes_reg[23]_i_1_n_15\,
      S(7 downto 0) => \^status2\(23 downto 16)
    );
\sign_changes_reg[24]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_15\,
      Q => \^status2\(24),
      R => last_sign_valid
    );
\sign_changes_reg[25]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_14\,
      Q => \^status2\(25),
      R => last_sign_valid
    );
\sign_changes_reg[26]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_13\,
      Q => \^status2\(26),
      R => last_sign_valid
    );
\sign_changes_reg[27]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_12\,
      Q => \^status2\(27),
      R => last_sign_valid
    );
\sign_changes_reg[28]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_11\,
      Q => \^status2\(28),
      R => last_sign_valid
    );
\sign_changes_reg[29]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_10\,
      Q => \^status2\(29),
      R => last_sign_valid
    );
\sign_changes_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_13\,
      Q => \^status2\(2),
      R => last_sign_valid
    );
\sign_changes_reg[30]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_9\,
      Q => \^status2\(30),
      R => last_sign_valid
    );
\sign_changes_reg[31]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[31]_i_2_n_8\,
      Q => \^status2\(31),
      R => last_sign_valid
    );
\sign_changes_reg[31]_i_2\: unisim.vcomponents.CARRY8
     port map (
      CI => \sign_changes_reg[23]_i_1_n_0\,
      CI_TOP => '0',
      CO(7) => \NLW_sign_changes_reg[31]_i_2_CO_UNCONNECTED\(7),
      CO(6) => \sign_changes_reg[31]_i_2_n_1\,
      CO(5) => \sign_changes_reg[31]_i_2_n_2\,
      CO(4) => \sign_changes_reg[31]_i_2_n_3\,
      CO(3) => \sign_changes_reg[31]_i_2_n_4\,
      CO(2) => \sign_changes_reg[31]_i_2_n_5\,
      CO(1) => \sign_changes_reg[31]_i_2_n_6\,
      CO(0) => \sign_changes_reg[31]_i_2_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7) => \sign_changes_reg[31]_i_2_n_8\,
      O(6) => \sign_changes_reg[31]_i_2_n_9\,
      O(5) => \sign_changes_reg[31]_i_2_n_10\,
      O(4) => \sign_changes_reg[31]_i_2_n_11\,
      O(3) => \sign_changes_reg[31]_i_2_n_12\,
      O(2) => \sign_changes_reg[31]_i_2_n_13\,
      O(1) => \sign_changes_reg[31]_i_2_n_14\,
      O(0) => \sign_changes_reg[31]_i_2_n_15\,
      S(7 downto 0) => \^status2\(31 downto 24)
    );
\sign_changes_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_12\,
      Q => \^status2\(3),
      R => last_sign_valid
    );
\sign_changes_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_11\,
      Q => \^status2\(4),
      R => last_sign_valid
    );
\sign_changes_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_10\,
      Q => \^status2\(5),
      R => last_sign_valid
    );
\sign_changes_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_9\,
      Q => \^status2\(6),
      R => last_sign_valid
    );
\sign_changes_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[7]_i_1_n_8\,
      Q => \^status2\(7),
      R => last_sign_valid
    );
\sign_changes_reg[7]_i_1\: unisim.vcomponents.CARRY8
     port map (
      CI => '0',
      CI_TOP => '0',
      CO(7) => \sign_changes_reg[7]_i_1_n_0\,
      CO(6) => \sign_changes_reg[7]_i_1_n_1\,
      CO(5) => \sign_changes_reg[7]_i_1_n_2\,
      CO(4) => \sign_changes_reg[7]_i_1_n_3\,
      CO(3) => \sign_changes_reg[7]_i_1_n_4\,
      CO(2) => \sign_changes_reg[7]_i_1_n_5\,
      CO(1) => \sign_changes_reg[7]_i_1_n_6\,
      CO(0) => \sign_changes_reg[7]_i_1_n_7\,
      DI(7 downto 0) => B"00000001",
      O(7) => \sign_changes_reg[7]_i_1_n_8\,
      O(6) => \sign_changes_reg[7]_i_1_n_9\,
      O(5) => \sign_changes_reg[7]_i_1_n_10\,
      O(4) => \sign_changes_reg[7]_i_1_n_11\,
      O(3) => \sign_changes_reg[7]_i_1_n_12\,
      O(2) => \sign_changes_reg[7]_i_1_n_13\,
      O(1) => \sign_changes_reg[7]_i_1_n_14\,
      O(0) => \sign_changes_reg[7]_i_1_n_15\,
      S(7 downto 1) => \^status2\(7 downto 1),
      S(0) => \sign_changes[7]_i_2_n_0\
    );
\sign_changes_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_15\,
      Q => \^status2\(8),
      R => last_sign_valid
    );
\sign_changes_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \sign_changes[31]_i_1_n_0\,
      D => \sign_changes_reg[15]_i_1_n_14\,
      Q => \^status2\(9),
      R => last_sign_valid
    );
wr_addr0_carry: unisim.vcomponents.CARRY8
     port map (
      CI => wr_addr_reg(0),
      CI_TOP => '0',
      CO(7) => wr_addr0_carry_n_0,
      CO(6) => wr_addr0_carry_n_1,
      CO(5) => wr_addr0_carry_n_2,
      CO(4) => wr_addr0_carry_n_3,
      CO(3) => wr_addr0_carry_n_4,
      CO(2) => wr_addr0_carry_n_5,
      CO(1) => wr_addr0_carry_n_6,
      CO(0) => wr_addr0_carry_n_7,
      DI(7 downto 0) => B"00000000",
      O(7 downto 0) => \p_0_in__0\(8 downto 1),
      S(7 downto 0) => wr_addr_reg(8 downto 1)
    );
\wr_addr0_carry__0\: unisim.vcomponents.CARRY8
     port map (
      CI => wr_addr0_carry_n_0,
      CI_TOP => '0',
      CO(7 downto 3) => \NLW_wr_addr0_carry__0_CO_UNCONNECTED\(7 downto 3),
      CO(2) => \wr_addr0_carry__0_n_5\,
      CO(1) => \wr_addr0_carry__0_n_6\,
      CO(0) => \wr_addr0_carry__0_n_7\,
      DI(7 downto 0) => B"00000000",
      O(7 downto 4) => \NLW_wr_addr0_carry__0_O_UNCONNECTED\(7 downto 4),
      O(3 downto 0) => \p_0_in__0\(12 downto 9),
      S(7 downto 4) => B"0000",
      S(3 downto 0) => wr_addr_reg(12 downto 9)
    );
\wr_addr[0]_i_1\: unisim.vcomponents.LUT1
    generic map(
      INIT => X"1"
    )
        port map (
      I0 => wr_addr_reg(0),
      O => \p_0_in__0\(0)
    );
\wr_addr[12]_i_1\: unisim.vcomponents.LUT2
    generic map(
      INIT => X"2"
    )
        port map (
      I0 => ctrl_sync(1),
      I1 => cap_en_d,
      O => start
    );
\wr_addr[12]_i_2\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"2000"
    )
        port map (
      I0 => \wr_addr[12]_i_3_n_0\,
      I1 => wr_full,
      I2 => \^active_reg_0\,
      I3 => s_axis_tvalid,
      O => \wr_addr[12]_i_2_n_0\
    );
\wr_addr[12]_i_3\: unisim.vcomponents.LUT6
    generic map(
      INIT => X"FFFFFFFFBFFFFFFF"
    )
        port map (
      I0 => \wr_addr[12]_i_4_n_0\,
      I1 => wr_addr_reg(4),
      I2 => wr_addr_reg(3),
      I3 => wr_addr_reg(6),
      I4 => wr_addr_reg(5),
      I5 => \wr_addr[12]_i_5_n_0\,
      O => \wr_addr[12]_i_3_n_0\
    );
\wr_addr[12]_i_4\: unisim.vcomponents.LUT4
    generic map(
      INIT => X"7FFF"
    )
        port map (
      I0 => wr_addr_reg(8),
      I1 => wr_addr_reg(7),
      I2 => wr_addr_reg(10),
      I3 => wr_addr_reg(9),
      O => \wr_addr[12]_i_4_n_0\
    );
\wr_addr[12]_i_5\: unisim.vcomponents.LUT5
    generic map(
      INIT => X"7FFFFFFF"
    )
        port map (
      I0 => wr_addr_reg(0),
      I1 => wr_addr_reg(11),
      I2 => wr_addr_reg(12),
      I3 => wr_addr_reg(2),
      I4 => wr_addr_reg(1),
      O => \wr_addr[12]_i_5_n_0\
    );
\wr_addr_reg[0]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(0),
      Q => wr_addr_reg(0),
      R => start
    );
\wr_addr_reg[10]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(10),
      Q => wr_addr_reg(10),
      R => start
    );
\wr_addr_reg[11]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(11),
      Q => wr_addr_reg(11),
      R => start
    );
\wr_addr_reg[12]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(12),
      Q => wr_addr_reg(12),
      R => start
    );
\wr_addr_reg[1]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(1),
      Q => wr_addr_reg(1),
      R => start
    );
\wr_addr_reg[2]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(2),
      Q => wr_addr_reg(2),
      R => start
    );
\wr_addr_reg[3]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(3),
      Q => wr_addr_reg(3),
      R => start
    );
\wr_addr_reg[4]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(4),
      Q => wr_addr_reg(4),
      R => start
    );
\wr_addr_reg[5]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(5),
      Q => wr_addr_reg(5),
      R => start
    );
\wr_addr_reg[6]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(6),
      Q => wr_addr_reg(6),
      R => start
    );
\wr_addr_reg[7]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(7),
      Q => wr_addr_reg(7),
      R => start
    );
\wr_addr_reg[8]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(8),
      Q => wr_addr_reg(8),
      R => start
    );
\wr_addr_reg[9]\: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => \wr_addr[12]_i_2_n_0\,
      D => \p_0_in__0\(9),
      Q => wr_addr_reg(9),
      R => start
    );
wr_full_i_1: unisim.vcomponents.LUT6
    generic map(
      INIT => X"AAEA0000AAEAAAEA"
    )
        port map (
      I0 => wr_full,
      I1 => \^active_reg_0\,
      I2 => s_axis_tvalid,
      I3 => \wr_addr[12]_i_3_n_0\,
      I4 => cap_en_d,
      I5 => ctrl_sync(1),
      O => wr_full_i_1_n_0
    );
wr_full_reg: unisim.vcomponents.FDRE
    generic map(
      INIT => '0'
    )
        port map (
      C => aclk,
      CE => '1',
      D => wr_full_i_1_n_0,
      Q => wr_full,
      R => '0'
    );
end STRUCTURE;
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
library UNISIM;
use UNISIM.VCOMPONENTS.ALL;
entity system_adc_cap_0 is
  port (
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
  attribute NotValidForBitStream : boolean;
  attribute NotValidForBitStream of system_adc_cap_0 : entity is true;
  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of system_adc_cap_0 : entity is "system_adc_cap_0,zcu216_adc_capture,{}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of system_adc_cap_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of system_adc_cap_0 : entity is "module_ref";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of system_adc_cap_0 : entity is "zcu216_adc_capture,Vivado 2021.1_AR76780";
end system_adc_cap_0;

architecture STRUCTURE of system_adc_cap_0 is
  signal \<const0>\ : STD_LOGIC;
  signal \^s_axis_tready\ : STD_LOGIC;
  signal \^status0\ : STD_LOGIC_VECTOR ( 31 downto 0 );
  signal \^status_capture\ : STD_LOGIC_VECTOR ( 15 downto 0 );
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of aclk : signal is "xilinx.com:signal:clock:1.0 aclk CLK";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of aclk : signal is "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF s_axis, ASSOCIATED_RESET aresetn, FREQ_HZ 307200000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_adc2, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of aresetn : signal is "xilinx.com:signal:reset:1.0 aresetn RST";
  attribute X_INTERFACE_PARAMETER of aresetn : signal is "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axis_tready : signal is "xilinx.com:interface:axis:1.0 s_axis TREADY";
  attribute X_INTERFACE_PARAMETER of s_axis_tready : signal is "XIL_INTERFACENAME s_axis, TDATA_NUM_BYTES 16, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 307200000, PHASE 0.0, CLK_DOMAIN system_usp_rf_data_converter_0_0_clk_adc2, LAYERED_METADATA undef, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of s_axis_tvalid : signal is "xilinx.com:interface:axis:1.0 s_axis TVALID";
  attribute X_INTERFACE_INFO of s_axis_tdata : signal is "xilinx.com:interface:axis:1.0 s_axis TDATA";
begin
  s_axis_tready <= \^s_axis_tready\;
  status0(31) <= \^status0\(31);
  status0(30) <= \^s_axis_tready\;
  status0(29 downto 26) <= \^status0\(29 downto 26);
  status0(25) <= \<const0>\;
  status0(24) <= \<const0>\;
  status0(23) <= \<const0>\;
  status0(22) <= \<const0>\;
  status0(21) <= \<const0>\;
  status0(20) <= \<const0>\;
  status0(19) <= \<const0>\;
  status0(18) <= \<const0>\;
  status0(17) <= \<const0>\;
  status0(16) <= \<const0>\;
  status0(15 downto 0) <= \^status0\(15 downto 0);
  status_capture(31) <= \^status_capture\(15);
  status_capture(30) <= \^status_capture\(15);
  status_capture(29) <= \^status_capture\(15);
  status_capture(28) <= \^status_capture\(15);
  status_capture(27) <= \^status_capture\(15);
  status_capture(26) <= \^status_capture\(15);
  status_capture(25) <= \^status_capture\(15);
  status_capture(24) <= \^status_capture\(15);
  status_capture(23) <= \^status_capture\(15);
  status_capture(22) <= \^status_capture\(15);
  status_capture(21) <= \^status_capture\(15);
  status_capture(20) <= \^status_capture\(15);
  status_capture(19) <= \^status_capture\(15);
  status_capture(18) <= \^status_capture\(15);
  status_capture(17) <= \^status_capture\(15);
  status_capture(16) <= \^status_capture\(15);
  status_capture(15 downto 0) <= \^status_capture\(15 downto 0);
GND: unisim.vcomponents.GND
     port map (
      G => \<const0>\
    );
inst: entity work.system_adc_cap_0_zcu216_adc_capture
     port map (
      O15(15 downto 0) => \^status0\(15 downto 0),
      aclk => aclk,
      active_reg_0 => \^s_axis_tready\,
      aresetn => aresetn,
      ctrl(31 downto 0) => ctrl(31 downto 0),
      s_axis_tdata(15 downto 0) => s_axis_tdata(15 downto 0),
      s_axis_tvalid => s_axis_tvalid,
      status0(4) => \^status0\(31),
      status0(3 downto 0) => \^status0\(29 downto 26),
      status1(31 downto 0) => status1(31 downto 0),
      status2(31 downto 0) => status2(31 downto 0),
      status3(31 downto 0) => status3(31 downto 0),
      status_capture(15 downto 0) => \^status_capture\(15 downto 0)
    );
end STRUCTURE;
