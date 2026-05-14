`timescale 1ns/1ps

// Hand-written simulation wrapper matching Vivado's generated output for
// ip/fft256_xilinx/fft256_xilinx/fft256_xilinx.xci (xfft v9.1 rev 8).
//
// Port names and widths are taken verbatim from the .xci boundary section
// and the .veo instantiation template.  All generics come from the XCI
// model_parameters section.  Replace with the Vivado-generated file once
// full IP generation has been run on a machine with the target device part.
//
// IP VLNV: xilinx.com:ip:xfft:9.1
// IP Revision: 8
// Component: fft256_xilinx

module fft256_xilinx (
    aclk,
    s_axis_config_tdata,
    s_axis_config_tvalid,
    s_axis_config_tready,
    s_axis_data_tdata,
    s_axis_data_tvalid,
    s_axis_data_tready,
    s_axis_data_tlast,
    m_axis_data_tdata,
    m_axis_data_tuser,
    m_axis_data_tvalid,
    m_axis_data_tlast,
    event_frame_started,
    event_tlast_unexpected,
    event_tlast_missing,
    event_data_in_channel_halt
);

    input  wire        aclk;
    input  wire [15:0] s_axis_config_tdata;
    input  wire        s_axis_config_tvalid;
    output wire        s_axis_config_tready;
    input  wire [31:0] s_axis_data_tdata;
    input  wire        s_axis_data_tvalid;
    output wire        s_axis_data_tready;
    input  wire        s_axis_data_tlast;
    output wire [31:0] m_axis_data_tdata;
    output wire [7:0]  m_axis_data_tuser;
    output wire        m_axis_data_tvalid;
    output wire        m_axis_data_tlast;
    output wire        event_frame_started;
    output wire        event_tlast_unexpected;
    output wire        event_tlast_missing;
    output wire        event_data_in_channel_halt;

    xfft_v9_1_8 #(
        .C_XDEVICEFAMILY             ("zynquplus"),
        .C_S_AXIS_CONFIG_TDATA_WIDTH (16),
        .C_S_AXIS_DATA_TDATA_WIDTH   (32),
        .C_M_AXIS_DATA_TDATA_WIDTH   (32),
        .C_M_AXIS_DATA_TUSER_WIDTH   (8),
        .C_M_AXIS_STATUS_TDATA_WIDTH (1),
        .C_THROTTLE_SCHEME           (0),
        .C_CHANNELS                  (1),
        .C_NFFT_MAX                  (8),
        .C_ARCH                      (3),
        .C_HAS_NFFT                  (0),
        .C_USE_FLT_PT                (0),
        .C_INPUT_WIDTH               (16),
        .C_TWIDDLE_WIDTH             (16),
        .C_OUTPUT_WIDTH              (16),
        .C_HAS_SCALING               (1),
        .C_HAS_BFP                   (0),
        .C_HAS_ROUNDING              (1),
        .C_HAS_ACLKEN                (0),
        .C_HAS_ARESETN               (0),
        .C_HAS_OVFLO                 (0),
        .C_HAS_NATURAL_INPUT         (1),
        .C_HAS_NATURAL_OUTPUT        (1),
        .C_HAS_CYCLIC_PREFIX         (0),
        .C_HAS_XK_INDEX              (1),
        .C_DATA_MEM_TYPE             (1),
        .C_TWIDDLE_MEM_TYPE          (1),
        .C_BRAM_STAGES               (1),
        .C_REORDER_MEM_TYPE          (1),
        .C_USE_HYBRID_RAM            (0),
        .C_OPTIMIZE_GOAL             (0),
        .C_CMPY_TYPE                 (1),
        .C_BFLY_TYPE                 (0)
    ) inst (
        .aclk                        (aclk),
        .s_axis_config_tdata         (s_axis_config_tdata),
        .s_axis_config_tvalid        (s_axis_config_tvalid),
        .s_axis_config_tready        (s_axis_config_tready),
        .s_axis_data_tdata           (s_axis_data_tdata),
        .s_axis_data_tvalid          (s_axis_data_tvalid),
        .s_axis_data_tready          (s_axis_data_tready),
        .s_axis_data_tlast           (s_axis_data_tlast),
        .m_axis_data_tdata           (m_axis_data_tdata),
        .m_axis_data_tuser           (m_axis_data_tuser),
        .m_axis_data_tvalid          (m_axis_data_tvalid),
        .m_axis_data_tlast           (m_axis_data_tlast),
        .event_frame_started         (event_frame_started),
        .event_tlast_unexpected      (event_tlast_unexpected),
        .event_tlast_missing         (event_tlast_missing),
        .event_data_in_channel_halt  (event_data_in_channel_halt)
    );

endmodule
