//----------------------------------------------------------------------------
// Title : ROM for tile configuration
// Project : Ultrascale+ RF Data Converter Subsystem
//----------------------------------------------------------------------------
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
// 
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
// 
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES. 

`timescale 1ps/1ps

module system_usp_rf_data_converter_0_0_device_rom (
    aux_clk,
    data_index,
    data_out,
    addr_out,
    tile_out
  );

    input aux_clk;

    input [10:0] data_index;

    output [15:0] data_out;
    output [10:0] addr_out;
    output [2:0]  tile_out;

    reg [29:0] data;

    // The 30-bit data in the array follows the format below:
    // 29:27 |  26:24  |    23:16    |    15:0
    // Tile  |  Slice  | DRP Address |  DRP Data

    (* rom_style = "distributed" *) reg [29:0] data_array [0:138] = '{
       30'h07280280,  // SYSREF Distribution (ADC0)
       30'h00740080,  // RX_PAIR_MC_CONFIG0 (ADC00)
       30'h01740080,  // RX_PAIR_MC_CONFIG0 (ADC01)
       30'h02740080,  // RX_PAIR_MC_CONFIG0 (ADC02)
       30'h03740080,  // RX_PAIR_MC_CONFIG0 (ADC03)
       30'h0f280600,  // SYSREF Distribution (ADC1)
       30'h08740080,  // RX_PAIR_MC_CONFIG0 (ADC10)
       30'h09740080,  // RX_PAIR_MC_CONFIG0 (ADC11)
       30'h0a740080,  // RX_PAIR_MC_CONFIG0 (ADC12)
       30'h0b740080,  // RX_PAIR_MC_CONFIG0 (ADC13)
       30'h17230000,  // Clock Network Control 0 (ADC2)
       30'h17240000,  // Clock Network Control 1 (ADC2)
       30'h17222000,  // Clock Distribution Control (ADC2)
       30'h10740080,  // RX_PAIR_MC_CONFIG0 (ADC20)
       30'h11740080,  // RX_PAIR_MC_CONFIG0 (ADC21)
       30'h12740080,  // RX_PAIR_MC_CONFIG0 (ADC22)
       30'h13740080,  // RX_PAIR_MC_CONFIG0 (ADC23)
       30'h17170026,  // PLL FB Div (ADC2)
       30'h170c00c0,  // PLL Output Divide (ADC2)
       30'h17100010,  // PLL Ref clock divide (ADC2)
       30'h17000080,  // PLL SDM CONFIG0 (ADC2)
       30'h17060111,  // PLL SDM seed (ADC2)
       30'h17070011,  // PLL SDM seed setup (ADC2)
       30'h170e0d37,  // PLL ChargePump setup (ADC2)
       30'h170f2080,  // PLL temprature sensor control (ADC2)
       30'h1712ffff,  // PLL ChargePump setup (ADC2)
       30'h17137f9a,  // PLL loop filter setup (ADC2)
       30'h17140006,  // PLL loop filter setup (ADC2)
       30'h17155800,  // PLL VCO setup (ADC2)
       30'h17160008,  // PLL VCO setup (ADC2)
       30'h170a7a21,  // PLL Coarse Frequency setup (ADC2)
       30'h170b7008,  // PLL Coarse Frequency setup (ADC2)
       30'h1711002d,  // PLL Voltage Regulator setup (ADC2)
       30'h172c0022,  // CLK_DIV (ADC2)
       30'h17288880,  // SYSREF Distribution (ADC2)
       30'h172dfffc,  // HSCOM_PWR_MASK (ADC2)
       30'h17310062,  // CLOCK_DETECT_CTRL0 (ADC2)
       30'h17320032,  // CLOCK_DETECT_CTRL1 (ADC2)
       30'h17300000,  // FIFO_START (ADC2)
       30'h10020804,  // ADC20 Data Width
       30'h10100000,  // ADC20 Decimation Config
       30'h10110001,  // ADC20 Decimation Mode
       30'h10200000,  // ADC20 Mixer Config 0
       30'h10210924,  // ADC20 Mixer Config 1
       30'h103a0000,  // ADC20 Switch Matrix Config
       30'h107121e1,  // ADC20 RX MC Config 0
       30'h10780002,  // ADC20 DSA Control
       30'h105181c3,  // ADC20 TI_DCB_CTRL0
       30'h1055d448,  // ADC20 TI_TIME_SKEW_CTRL0
       30'h105a0001,  // ADC20 TI_TIME_SKEW_CTRL5
       30'h10060008,  // ADC20 FABRIC_DEBUG
       30'h1f280700,  // SYSREF Distribution (ADC3)
       30'h18740080,  // RX_PAIR_MC_CONFIG0 (ADC30)
       30'h19740080,  // RX_PAIR_MC_CONFIG0 (ADC31)
       30'h1a740080,  // RX_PAIR_MC_CONFIG0 (ADC32)
       30'h1b740080,  // RX_PAIR_MC_CONFIG0 (ADC33)
       30'h2728ca80,  // SYSREF Distribution (DAC0)
       30'h2f282400,  // SYSREF Distribution (DAC1)
       30'h37230000,  // Clock Network Control 0 (DAC2)
       30'h37240000,  // Clock Network Control 1 (DAC2)
       30'h3722a458,  // Clock Distribution Control (DAC2)
       30'h37170036,  // PLL FB Div (DAC2)
       30'h370c0040,  // PLL Output Divide (DAC2)
       30'h37100050,  // PLL Ref clock divide (DAC2)
       30'h37000080,  // PLL SDM CONFIG0 (DAC2)
       30'h37060111,  // PLL SDM seed (DAC2)
       30'h37070011,  // PLL SDM seed setup (DAC2)
       30'h370e0d37,  // PLL ChargePump setup (DAC2)
       30'h370f2080,  // PLL temprature sensor control (DAC2)
       30'h3712ffff,  // PLL ChargePump setup (DAC2)
       30'h37137f9a,  // PLL loop filter setup (DAC2)
       30'h37140006,  // PLL loop filter setup (DAC2)
       30'h37155f03,  // PLL VCO setup (DAC2)
       30'h37160008,  // PLL VCO setup (DAC2)
       30'h370a7a20,  // PLL Coarse Frequency setup (DAC2)
       30'h370b7008,  // PLL Coarse Frequency setup (DAC2)
       30'h3711002d,  // PLL Voltage Regulator setup (DAC2)
       30'h372c0012,  // CLK_DIV (DAC2)
       30'h37280980,  // SYSREF Distribution (DAC2)
       30'h372dfffc,  // HSCOM_PWR_MASK (DAC2)
       30'h373103e6,  // CLOCK_DETECT_CTRL0 (DAC2)
       30'h373204e1,  // CLOCK_DETECT_CTRL1 (DAC2)
       30'h30020810,  // DAC20 Data Width
       30'h30100001,  // DAC20 Interpolation Control
       30'h30110000,  // DAC20 Interpolation Data
       30'h30200000,  // DAC20 Mixer Config 0
       30'h30210924,  // DAC20 Mixer Config 1
       30'h30300000,  // DAC20 Inv Sinc Filter
       30'h30310040,  // DAC20 Multiband Config
       30'h30600009,  // DAC20 Decoder Control
       30'h30610001,  // DAC20 Decoder Clock Enable
       30'h3071a000,  // DAC20 MC_CONFIG0
       30'h3073aa53,  // DAC20 MC_CONFIG2
       30'h30746a45,  // DAC20 MC_CONFIG3
       30'h30660001,  // DAC20 VOP_CTRL
       30'h300d0000,  // DAC20 DATAPATH
       30'h30040000,  // DAC20 FIFO_START
       30'h30070008,  // DAC20 FABRIC_DEBUG
       30'h3f238000,  // Clock Network Control 0 (DAC3)
       30'h3f240000,  // Clock Network Control 1 (DAC3)
       30'h3f222010,  // Clock Distribution Control (DAC3)
       30'h3f170036,  // PLL FB Div (DAC3)
       30'h3f0c0040,  // PLL Output Divide (DAC3)
       30'h3f100050,  // PLL Ref clock divide (DAC3)
       30'h3f000080,  // PLL SDM CONFIG0 (DAC3)
       30'h3f060111,  // PLL SDM seed (DAC3)
       30'h3f070011,  // PLL SDM seed setup (DAC3)
       30'h3f0e0d37,  // PLL ChargePump setup (DAC3)
       30'h3f0f2080,  // PLL temprature sensor control (DAC3)
       30'h3f12ffff,  // PLL ChargePump setup (DAC3)
       30'h3f137f9a,  // PLL loop filter setup (DAC3)
       30'h3f140006,  // PLL loop filter setup (DAC3)
       30'h3f155f03,  // PLL VCO setup (DAC3)
       30'h3f160008,  // PLL VCO setup (DAC3)
       30'h3f0a7a20,  // PLL Coarse Frequency setup (DAC3)
       30'h3f0b7008,  // PLL Coarse Frequency setup (DAC3)
       30'h3f11002d,  // PLL Voltage Regulator setup (DAC3)
       30'h3f2c0022,  // CLK_DIV (DAC3)
       30'h3f280100,  // SYSREF Distribution (DAC3)
       30'h3f2dfdfe,  // HSCOM_PWR_MASK (DAC3)
       30'h3f3103e6,  // CLOCK_DETECT_CTRL0 (DAC3)
       30'h3f3204e1,  // CLOCK_DETECT_CTRL1 (DAC3)
       30'h3a021010,  // DAC32 Data Width
       30'h3a100001,  // DAC32 Interpolation Control
       30'h3a110000,  // DAC32 Interpolation Data
       30'h3a200000,  // DAC32 Mixer Config 0
       30'h3a210924,  // DAC32 Mixer Config 1
       30'h3a300000,  // DAC32 Inv Sinc Filter
       30'h3a310040,  // DAC32 Multiband Config
       30'h3a600009,  // DAC32 Decoder Control
       30'h3a610001,  // DAC32 Decoder Clock Enable
       30'h3a71a000,  // DAC32 MC_CONFIG0
       30'h3a73aa53,  // DAC32 MC_CONFIG2
       30'h3a746a45,  // DAC32 MC_CONFIG3
       30'h3a660001,  // DAC32 VOP_CTRL
       30'h3a0d0003,  // DAC32 DATAPATH
       30'h3a040000,  // DAC32 FIFO_START
       30'h3a070010,  // DAC32 FABRIC_DEBUG
       30'h00000000};

    //-------------------------------------------------------------------------
    // Output the tile number, address and data for the DRP writes
    // depending on the data_index input
    //-------------------------------------------------------------------------
    always @(posedge aux_clk)
    begin
      data <= data_array[data_index];
    end

    assign data_out = data[15:0];
    assign addr_out = data[26:16];
    assign tile_out = data[29:27];

endmodule
