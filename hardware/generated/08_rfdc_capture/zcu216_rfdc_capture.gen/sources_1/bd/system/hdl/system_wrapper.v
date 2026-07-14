//Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
//--------------------------------------------------------------------------------
//Tool Version: Vivado v.2021.1_AR76780 (lin64) Build 3247384 Thu Jun 10 19:36:07 MDT 2021
//Date        : Fri Jun 19 11:13:17 2026
//Host        : dspmikro7-Venus-Series running 64-bit Ubuntu 22.04.4 LTS
//Command     : generate_target system_wrapper.bd
//Design      : system_wrapper
//Purpose     : IP block netlist
//--------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

module system_wrapper
   (CLK104_CLK_SPI_MUX_SEL_LS,
    adc2_clk_0_clk_n,
    adc2_clk_0_clk_p,
    dac2_clk_0_clk_n,
    dac2_clk_0_clk_p,
    sysref_in_0_diff_n,
    sysref_in_0_diff_p,
    vin20_0_v_n,
    vin20_0_v_p,
    vout32_0_v_n,
    vout32_0_v_p);
  output [1:0]CLK104_CLK_SPI_MUX_SEL_LS;
  input adc2_clk_0_clk_n;
  input adc2_clk_0_clk_p;
  input dac2_clk_0_clk_n;
  input dac2_clk_0_clk_p;
  input sysref_in_0_diff_n;
  input sysref_in_0_diff_p;
  input vin20_0_v_n;
  input vin20_0_v_p;
  output vout32_0_v_n;
  output vout32_0_v_p;

  wire [1:0]CLK104_CLK_SPI_MUX_SEL_LS;
  wire adc2_clk_0_clk_n;
  wire adc2_clk_0_clk_p;
  wire dac2_clk_0_clk_n;
  wire dac2_clk_0_clk_p;
  wire sysref_in_0_diff_n;
  wire sysref_in_0_diff_p;
  wire vin20_0_v_n;
  wire vin20_0_v_p;
  wire vout32_0_v_n;
  wire vout32_0_v_p;

  system system_i
       (.CLK104_CLK_SPI_MUX_SEL_LS(CLK104_CLK_SPI_MUX_SEL_LS),
        .adc2_clk_0_clk_n(adc2_clk_0_clk_n),
        .adc2_clk_0_clk_p(adc2_clk_0_clk_p),
        .dac2_clk_0_clk_n(dac2_clk_0_clk_n),
        .dac2_clk_0_clk_p(dac2_clk_0_clk_p),
        .sysref_in_0_diff_n(sysref_in_0_diff_n),
        .sysref_in_0_diff_p(sysref_in_0_diff_p),
        .vin20_0_v_n(vin20_0_v_n),
        .vin20_0_v_p(vin20_0_v_p),
        .vout32_0_v_n(vout32_0_v_n),
        .vout32_0_v_p(vout32_0_v_p));
endmodule
