/*
#include "xparameters.h"
#include "xrfclk.h"
#include "xstatus.h"
#include "xil_io.h"

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

// ============================================================
// AXI GPIO for SPI MUX
// ============================================================
#define SPI_MUX_GPIO_BASEADDR   XPAR_AXI_GPIO_0_BASEADDR
#define SPI_MUX_GPIO_DATA_ADDR  (SPI_MUX_GPIO_BASEADDR + 0x0U)
#define SPI_MUX_GPIO_TRI_ADDR   (SPI_MUX_GPIO_BASEADDR + 0x4U)


#define SPI_MUX_SEL_LMX2594_1   0U
#define SPI_MUX_SEL_LMX2594_2   1U
#define SPI_MUX_SEL_LMK         2U

static u32 data[256];

// ============================================================
// SPI MUX control
// ============================================================
static int spi_mux_init(void)
{
    Xil_Out32(SPI_MUX_GPIO_TRI_ADDR, 0x0U);
    usleep(1000);
    return EXIT_SUCCESS;
}

static void spi_mux_close(void)
{

}

static int spi_mux_write(u32 val)
{
    Xil_Out32(SPI_MUX_GPIO_DATA_ADDR, val);
    return EXIT_SUCCESS;
}

static u32 spi_mux_read(void)
{
    return Xil_In32(SPI_MUX_GPIO_DATA_ADDR);
}

static int spi_mux_select_for_chip(u32 chip_id)
{
    u32 mux_val;

    switch (chip_id) {
    case RFCLK_LMX2594_1:
        mux_val = SPI_MUX_SEL_LMX2594_1;
        break;

    case RFCLK_LMX2594_2:
        mux_val = SPI_MUX_SEL_LMX2594_2;
        break;

    case RFCLK_LMK:
        mux_val = SPI_MUX_SEL_LMK;
        break;

    default:
        printf("\n[ERR] Unknown chip_id = %u", chip_id);
        return EXIT_FAILURE;
    }

    spi_mux_write(mux_val);
    usleep(1000);

    printf("\n[SPI_MUX] chip_id=%u -> mux=%u (reg=0x%08X)",
           chip_id, mux_val, spi_mux_read());

    return EXIT_SUCCESS;
}

// ============================================================
// Wrapped RFCLK calls
// ============================================================
static int rfclk_reset_chip_checked(u32 chip_id)
{
    if (spi_mux_select_for_chip(chip_id) != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XST_FAILURE == XRFClk_ResetChip(chip_id))
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_write_reg_checked(u32 chip_id, u32 val)
{
    if (spi_mux_select_for_chip(chip_id) != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XST_FAILURE == XRFClk_WriteReg(chip_id, val))
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_read_reg_checked(u32 chip_id, u32 *val)
{
    if (spi_mux_select_for_chip(chip_id) != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XST_FAILURE == XRFClk_ReadReg(chip_id, val))
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_get_config_checked(u32 chip_id, u32 *cfg)
{
    if (spi_mux_select_for_chip(chip_id) != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XST_FAILURE == XRFClk_GetConfigFromOneChip(chip_id, cfg))
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_set_config_one_checked(u32 chip_id, u32 cfg_id)
{
    if (spi_mux_select_for_chip(chip_id) != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XST_FAILURE == XRFClk_SetConfigOnOneChipFromConfigId(chip_id, cfg_id))
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

// ============================================================
// Helpers
// ============================================================ //
static int resetAll(void)
{
    int ret = EXIT_FAILURE;

    printf("\nReset LMK");
    if (rfclk_reset_chip_checked(RFCLK_LMK) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_reset_chip_checked(RFCLK_LMK)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nReset LMX2594_1");
    if (rfclk_reset_chip_checked(RFCLK_LMX2594_1) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_reset_chip_checked(RFCLK_LMX2594_1)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nReset LMX2594_2");
    if (rfclk_reset_chip_checked(RFCLK_LMX2594_2) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_reset_chip_checked(RFCLK_LMX2594_2)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    ret = EXIT_SUCCESS;

ret_jump:
    return ret;
}

static int getConfigAll(void)
{
    int i;
    int ret = EXIT_FAILURE;

    printf("\nGet config from ID on LMX2594_1");
    if (rfclk_get_config_checked(RFCLK_LMX2594_1, data) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_get_config_checked(RFCLK_LMX2594_1)");
        goto ret_jump;
    } else {
        printf("      Pass");
        printf("\nLMX2594_1 config data are:\n");
        for (i = 0; i < LMX2594_COUNT; i++)
            printf("%x,", data[i]);
    }

    printf("\nGet config from ID on LMX2594_2");
    if (rfclk_get_config_checked(RFCLK_LMX2594_2, data) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_get_config_checked(RFCLK_LMX2594_2)");
        goto ret_jump;
    } else {
        printf("      Pass");
        printf("\nLMX2594_2 config data are:\n");
        for (i = 0; i < LMX2594_COUNT; i++)
            printf("%x,", data[i]);
    }

    printf("\nGet config from ID on LMK");
    if (rfclk_get_config_checked(RFCLK_LMK, data) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_get_config_checked(RFCLK_LMK)");
        goto ret_jump;
    } else {
        printf("      Pass");
        printf("\nLMK config data are:\n");
        for (i = 0; i < LMK_COUNT; i++)
            printf("%x,", data[i]);
    }

    ret = EXIT_SUCCESS;

ret_jump:
    return ret;
}

// ============================================================
// Probe helper
// ============================================================ //
static void probe_spi_mux_values(void)
{
    u32 d = 0;
    int mux;

    printf("\n\n=========== SPI MUX PROBE START ===========");

    for (mux = 0; mux < 4; mux++) {
        printf("\n\n[TEST] Forced MUX = %d", mux);

        spi_mux_write((u32)mux);
        usleep(1000);

        printf("\n[AFTER WRITE] GPIO=0x%08X", spi_mux_read());

        d = 0;
        printf("\nReading LMK...");
        if (XST_FAILURE == XRFClk_ReadReg(RFCLK_LMK, &d))
            printf("\nLMK ReadReg failed");
        else
            printf("\nLMK ReadReg = 0x%X", d);

        d = 0;
        printf("\nReading LMX2594_1...");
        if (XST_FAILURE == XRFClk_ReadReg(RFCLK_LMX2594_1, &d))
            printf("\nLMX2594_1 ReadReg failed");
        else
            printf("\nLMX2594_1 ReadReg = 0x%X", d);

        d = 0;
        printf("\nReading LMX2594_2...");
        if (XST_FAILURE == XRFClk_ReadReg(RFCLK_LMX2594_2, &d))
            printf("\nLMX2594_2 ReadReg failed");
        else
            printf("\nLMX2594_2 ReadReg = 0x%X", d);
    }

    printf("\n\n=========== SPI MUX PROBE STOP ===========\n");
}

// ============================================================
// Main
// ============================================================ //
int main(void)
{
    int ret = EXIT_FAILURE;
    u32 d;

    printf("\n----------- START ------------\n");

    if (spi_mux_init() == EXIT_FAILURE) {
        printf("\n[ERR] spi_mux_init() failed");
        goto ret_jump;
    }

    printf("\n[DBG] GPIO BASE = 0x%08X", SPI_MUX_GPIO_BASEADDR);
    printf("\n[DBG] initial DATA = 0x%08X", spi_mux_read());

    printf("\n[DBG] before XRFClk_Init(481)");
    XRFClk_Init(481);
    printf("\n[DBG] after XRFClk_Init(481)");


    printf("\n[DBG] Try LMK read first");
    d = 0;
    if (rfclk_read_reg_checked(RFCLK_LMK, &d) == EXIT_FAILURE) {
        printf("\n[FAIL] rfclk_read_reg_checked(RFCLK_LMK)");
    } else {
        printf("\n[PASS] LMK read value = 0x%x", d);
    }

    if (resetAll() == EXIT_FAILURE)
        goto ret_jump;

    d = 0x20112;
    printf("\nWrite dummy data to register in LMX2594_1");
    if (rfclk_write_reg_checked(RFCLK_LMX2594_1, d) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_write_reg_checked(RFCLK_LMX2594_1)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nRead and validate register value in LMX2594_1");
    if (rfclk_read_reg_checked(RFCLK_LMX2594_1, &d) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_read_reg_checked(RFCLK_LMX2594_1)");
        goto ret_jump;
    }
    printf("\nread value = %x      Pass", d);

    d = 0x20212;
    printf("\nWrite dummy data to register in LMX2594_2");
    if (rfclk_write_reg_checked(RFCLK_LMX2594_2, d) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_write_reg_checked(RFCLK_LMX2594_2)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nRead and validate register value in LMX2594_2");
    if (rfclk_read_reg_checked(RFCLK_LMX2594_2, &d) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_read_reg_checked(RFCLK_LMX2594_2)");
        goto ret_jump;
    }
    printf("\nread value = %x      Pass", d);

    printf("\nSet config from ID on LMK");
    if (rfclk_set_config_one_checked(RFCLK_LMK, 0) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_set_config_one_checked(RFCLK_LMK)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nSet config from ID on LMX2594_1");
    if (rfclk_set_config_one_checked(RFCLK_LMX2594_1, 0) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_set_config_one_checked(RFCLK_LMX2594_1)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    printf("\nSet config from ID on LMX2594_2");
    if (rfclk_set_config_one_checked(RFCLK_LMX2594_2, 1) == EXIT_FAILURE) {
        printf("\nFailure in rfclk_set_config_one_checked(RFCLK_LMX2594_2)");
        goto ret_jump;
    } else {
        printf("      Pass");
    }

    if (getConfigAll() == EXIT_FAILURE)
        goto ret_jump;

    sleep(1);

    if (resetAll() == EXIT_FAILURE)
        goto ret_jump;

    printf("\nSet config on all RF chips (sequential, mux-aware)");

    if (rfclk_set_config_one_checked(RFCLK_LMK, 1) == EXIT_FAILURE) {
        printf("\nFailure configuring LMK");
        goto ret_jump;
    }
    if (rfclk_set_config_one_checked(RFCLK_LMX2594_1, 2) == EXIT_FAILURE) {
        printf("\nFailure configuring LMX2594_1");
        goto ret_jump;
    }
    if (rfclk_set_config_one_checked(RFCLK_LMX2594_2, 3) == EXIT_FAILURE) {
        printf("\nFailure configuring LMX2594_2");
        goto ret_jump;
    }
    printf("      Pass");

    if (getConfigAll() == EXIT_FAILURE)
        goto ret_jump;

    printf("\n----------- STOP ------------\n");

    XRFClk_Close();
    spi_mux_close();
    ret = EXIT_SUCCESS;

ret_jump:
    if (ret != EXIT_SUCCESS)
        printf("\n----------- ERROR STOP ------------\n");

    XRFClk_Close();
    spi_mux_close();
    return ret;
}
*/


/*
#include "xparameters.h"
#include "xstatus.h"
#include "xil_io.h"
#include "xrfclk.h"
#include "xrfdc.h"

#include <stdio.h>
#include <stdlib.h>

// ============================================================
// AXI GPIO for SPI MUX
// ============================================================
#define SPI_MUX_GPIO_BASEADDR   XPAR_AXI_GPIO_0_BASEADDR
#define SPI_MUX_GPIO_DATA_ADDR  (SPI_MUX_GPIO_BASEADDR + 0x0U)
#define SPI_MUX_GPIO_TRI_ADDR   (SPI_MUX_GPIO_BASEADDR + 0x4U)

#define SPI_MUX_SEL_LMX2594_1   0U
#define SPI_MUX_SEL_LMK         2U

#define RFDC_DEVICE_ID          XPAR_XRFDC_0_DEVICE_ID
#define RFDC_BASEADDR           XPAR_XRFDC_0_BASEADDR

static XRFdc RFdcInst;

//* ============================================================
// * SPI MUX control
// * ============================================================

static int spi_mux_init(void)
{
    Xil_Out32(SPI_MUX_GPIO_TRI_ADDR, 0x0U);
    usleep(1000);
    return EXIT_SUCCESS;
}

static int spi_mux_write(u32 val)
{
    Xil_Out32(SPI_MUX_GPIO_DATA_ADDR, val);
    return EXIT_SUCCESS;
}

static u32 spi_mux_read(void)
{
    return Xil_In32(SPI_MUX_GPIO_DATA_ADDR);
}

static int spi_mux_select_lmk(void)
{
    spi_mux_write(SPI_MUX_SEL_LMK);
    usleep(1000);
    printf("\n[SPI_MUX] LMK -> mux=%u (reg=0x%08X)",
           SPI_MUX_SEL_LMK, spi_mux_read());
    return EXIT_SUCCESS;
}

static int spi_mux_select_lmx1(void)
{
    spi_mux_write(SPI_MUX_SEL_LMX2594_1);
    usleep(1000);
    printf("\n[SPI_MUX] LMX2594_1 -> mux=%u (reg=0x%08X)",
           SPI_MUX_SEL_LMX2594_1, spi_mux_read());
    return EXIT_SUCCESS;
}

//* ============================================================
// * RFCLK helper
// * ============================================================
static int rfclk_reset_lmk(void)
{
    if (spi_mux_select_lmk() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ResetChip(RFCLK_LMK) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_reset_lmx1(void)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ResetChip(RFCLK_LMX2594_1) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_set_lmk_cfg0(void)
{
    if (spi_mux_select_lmk() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMK, 0U) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_set_lmx1_cfg0(void)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMX2594_1, 0U) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_read_lmx1(u32 *val)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ReadReg(RFCLK_LMX2594_1, val) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

//* ============================================================
// * RFDC helper
//* ============================================================
static int rfdc_init(XRFdc *InstancePtr)
{
    XRFdc_Config *CfgPtr;

    printf("\n====================================================");
    printf("\nRFDC init");
    printf("\n====================================================");

    CfgPtr = XRFdc_LookupConfig(RFDC_DEVICE_ID);
    if (CfgPtr == NULL) {
        printf("\n[FAIL] XRFdc_LookupConfig() returned NULL");
        return EXIT_FAILURE;
    }

    if (XRFdc_CfgInitialize(InstancePtr, CfgPtr) != XRFDC_SUCCESS) {
        printf("\n[FAIL] XRFdc_CfgInitialize() failed");
        return EXIT_FAILURE;
    }

    printf("\n[OK ] RFDC driver initialized");
    printf("\nRFDC BaseAddr = 0x%08lX", (unsigned long)CfgPtr->BaseAddr);

    return EXIT_SUCCESS;
}

static void rfdc_raw_reg_check(void)
{
    UINTPTR base = RFDC_BASEADDR;

    printf("\n====================================================");
    printf("\nRFDC raw register check");
    printf("\n====================================================");

    printf("\nRFDC @0x%08lX = 0x%08X",
           (unsigned long)base, Xil_In32(base + 0x0000U));
    printf("\nRFDC +0x0004  = 0x%08X", Xil_In32(base + 0x0004U));
    printf("\nRFDC +0x0008  = 0x%08X", Xil_In32(base + 0x0008U));
    printf("\nRFDC +0x000C  = 0x%08X", Xil_In32(base + 0x000CU));
}

static void rfdc_check_adc_tile0_state(XRFdc *InstancePtr)
{
    u32 tile_en;
    u32 block_en;
    u32 dig_en;
    double fab_clk;

    printf("\n====================================================");
    printf("\nRFDC ADC tile 0 state check");
    printf("\n====================================================");

    tile_en  = XRFdc_CheckTileEnabled(InstancePtr, XRFDC_ADC_TILE, 0U);
    block_en = XRFdc_CheckBlockEnabled(InstancePtr, XRFDC_ADC_TILE, 0U, 0U);
    dig_en   = XRFdc_IsADCDigitalPathEnabled(InstancePtr, 0U, 0U);
    fab_clk  = XRFdc_GetFabClkFreq(InstancePtr, XRFDC_ADC_TILE, 0U);

    printf("\n[CHK] ADC tile0 enabled      = %u", tile_en);
    printf("\n[CHK] ADC tile0 block0 en    = %u", block_en);
    printf("\n[CHK] ADC tile0 digital path = %u", dig_en);
    printf("\n[CHK] ADC tile0 fab clk      = %f", fab_clk);
}

static int rfdc_start_adc_tile0(XRFdc *InstancePtr)
{
    u32 status;

    printf("\n====================================================");
    printf("\nRFDC ADC tile 0 startup");
    printf("\n====================================================");

    status = XRFdc_StartUp(InstancePtr, XRFDC_ADC_TILE, 0U);
    if (status != XRFDC_SUCCESS) {
        printf("\n[FAIL] ADC tile 0 startup failed, status=%u", status);
        return EXIT_FAILURE;
    }

    printf("\n[OK ] ADC tile 0 startup success");
    return EXIT_SUCCESS;
}

//* ============================================================
// * Main
// * ============================================================
int main(void)
{
    int ret = EXIT_FAILURE;
    u32 readback = 0U;

    printf("\n----------- START ------------\n");

    if (spi_mux_init() != EXIT_SUCCESS) {
        printf("\n[FAIL] spi_mux_init()");
        goto ret_jump;
    }

    printf("\n[DBG] GPIO BASE = 0x%08X", SPI_MUX_GPIO_BASEADDR);
    printf("\n[DBG] initial DATA = 0x%08X", spi_mux_read());

    printf("\n====================================================");
    printf("\nRFCLK init");
    printf("\n====================================================");

    printf("\n[DBG] before XRFClk_Init(481)");
    XRFClk_Init(481);
    printf("\n[DBG] after XRFClk_Init(481)");

    printf("\n====================================================");
    printf("\nClock chip setup: minimal path");
    printf("\n====================================================");

    printf("\nReset LMK");
    if (rfclk_reset_lmk() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_reset_lmk()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nReset LMX2594_1");
    if (rfclk_reset_lmx1() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_reset_lmx1()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nSet LMK config ID 0");
    if (rfclk_set_lmk_cfg0() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_set_lmk_cfg0()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nSet LMX2594_1 config ID 0");
    if (rfclk_set_lmx1_cfg0() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_set_lmx1_cfg0()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nRead back LMX2594_1");
    if (rfclk_read_lmx1(&readback) != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_read_lmx1()");
        goto ret_jump;
    } else {
        if (readback == 0U || readback == 0xFFFFFFFFU) {
            printf("\n[WARN] LMX2594_1 readback suspicious: 0x%08X", readback);
        } else {
            printf("\n[PASS] LMX2594_1 readback = 0x%08X", readback);
        }
    }

    printf("\n[DBG] wait 1 second for clock settle");
    sleep(1U);

    if (rfdc_init(&RFdcInst) != EXIT_SUCCESS)
        goto ret_jump;

    rfdc_raw_reg_check();

    rfdc_check_adc_tile0_state(&RFdcInst);

    if (rfdc_start_adc_tile0(&RFdcInst) != EXIT_SUCCESS)
        goto ret_jump;

    printf("\n----------- STOP ------------\n");
    XRFClk_Close();
    ret = EXIT_SUCCESS;

ret_jump:
    if (ret != EXIT_SUCCESS)
        printf("\n----------- ERROR STOP ------------\n");

    XRFClk_Close();
    return ret;
}
*/

/*
#include "xparameters.h"
#include "xstatus.h"
#include "xil_io.h"
#include "xrfclk.h"
#include "xrfdc.h"

#include <stdio.h>
#include <stdlib.h>

//* ============================================================
// * AXI GPIO for SPI MUX
// * ============================================================
#define SPI_MUX_GPIO_BASEADDR   XPAR_AXI_GPIO_0_BASEADDR
#define SPI_MUX_GPIO_DATA_ADDR  (SPI_MUX_GPIO_BASEADDR + 0x0U)
#define SPI_MUX_GPIO_TRI_ADDR   (SPI_MUX_GPIO_BASEADDR + 0x4U)

#define SPI_MUX_SEL_LMX2594_1   0U
#define SPI_MUX_SEL_LMK         2U

#define RFDC_DEVICE_ID          XPAR_XRFDC_0_DEVICE_ID
#define RFDC_BASEADDR           XPAR_XRFDC_0_BASEADDR

static XRFdc RFdcInst;

//* ============================================================
// * SPI MUX control
// * ============================================================
static int spi_mux_init(void)
{
    Xil_Out32(SPI_MUX_GPIO_TRI_ADDR, 0x0U);
    usleep(1000);
    return EXIT_SUCCESS;
}

static int spi_mux_write(u32 val)
{
    Xil_Out32(SPI_MUX_GPIO_DATA_ADDR, val);
    return EXIT_SUCCESS;
}

static u32 spi_mux_read(void)
{
    return Xil_In32(SPI_MUX_GPIO_DATA_ADDR);
}

static int spi_mux_select_lmk(void)
{
    spi_mux_write(SPI_MUX_SEL_LMK);
    usleep(1000);
    printf("\n[SPI_MUX] LMK -> mux=%u (reg=0x%08X)",
           SPI_MUX_SEL_LMK, spi_mux_read());
    return EXIT_SUCCESS;
}

static int spi_mux_select_lmx1(void)
{
    spi_mux_write(SPI_MUX_SEL_LMX2594_1);
    usleep(1000);
    printf("\n[SPI_MUX] LMX2594_1 -> mux=%u (reg=0x%08X)",
           SPI_MUX_SEL_LMX2594_1, spi_mux_read());
    return EXIT_SUCCESS;
}

//* ============================================================
// * RFCLK helper
// * ============================================================
static int rfclk_reset_lmk(void)
{
    if (spi_mux_select_lmk() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ResetChip(RFCLK_LMK) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_reset_lmx1(void)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ResetChip(RFCLK_LMX2594_1) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_set_lmk_cfg0(void)
{
    if (spi_mux_select_lmk() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMK, 0U) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_set_lmx1_cfg0(void)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMX2594_1, 0U) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

static int rfclk_read_lmx1(u32 *val)
{
    if (spi_mux_select_lmx1() != EXIT_SUCCESS)
        return EXIT_FAILURE;

    if (XRFClk_ReadReg(RFCLK_LMX2594_1, val) == XST_FAILURE)
        return EXIT_FAILURE;

    return EXIT_SUCCESS;
}

//* ============================================================
// * RFDC helper
//* ============================================================
static int rfdc_init(XRFdc *InstancePtr)
{
    XRFdc_Config *CfgPtr;

    printf("\n====================================================");
    printf("\nRFDC init");
    printf("\n====================================================");

    CfgPtr = XRFdc_LookupConfig(RFDC_DEVICE_ID);
    if (CfgPtr == NULL) {
        printf("\n[FAIL] XRFdc_LookupConfig() returned NULL");
        return EXIT_FAILURE;
    }

    if (XRFdc_CfgInitialize(InstancePtr, CfgPtr) != XRFDC_SUCCESS) {
        printf("\n[FAIL] XRFdc_CfgInitialize() failed");
        return EXIT_FAILURE;
    }

    printf("\n[OK ] RFDC driver initialized");
    printf("\nRFDC BaseAddr = 0x%08lX", (unsigned long)CfgPtr->BaseAddr);

    return EXIT_SUCCESS;
}

static void rfdc_raw_reg_check(void)
{
    UINTPTR base = RFDC_BASEADDR;

    printf("\n====================================================");
    printf("\nRFDC raw register check");
    printf("\n====================================================");

    printf("\nRFDC @0x%08lX = 0x%08X",
           (unsigned long)base, Xil_In32(base + 0x0000U));
    printf("\nRFDC +0x0004  = 0x%08X", Xil_In32(base + 0x0004U));
    printf("\nRFDC +0x0008  = 0x%08X", Xil_In32(base + 0x0008U));
    printf("\nRFDC +0x000C  = 0x%08X", Xil_In32(base + 0x000CU));
}

static void rfdc_scan_all_adc(XRFdc *InstancePtr)
{
    int tile, block;
    u32 tile_en, block_en, dig_en;
    double fab_clk;

    printf("\n====================================================");
    printf("\nRFDC ADC full scan");
    printf("\n====================================================");

    for (tile = 0; tile < 4; tile++) {
        tile_en = XRFdc_CheckTileEnabled(InstancePtr, XRFDC_ADC_TILE, (u32)tile);
        fab_clk = XRFdc_GetFabClkFreq(InstancePtr, XRFDC_ADC_TILE, (u32)tile);

        printf("\n[TILE %d] enabled=%u fab_clk=%f", tile, tile_en, fab_clk);

        for (block = 0; block < 4; block++) {
            block_en = XRFdc_CheckBlockEnabled(
                InstancePtr, XRFDC_ADC_TILE, (u32)tile, (u32)block);
            dig_en = XRFdc_IsADCDigitalPathEnabled(
                InstancePtr, (u32)tile, (u32)block);

            printf("\n    [BLOCK %d] block_en=%u dig_en=%u",
                   block, block_en, dig_en);
        }
    }
}

static void rfdc_try_start_enabled_adc_tiles(XRFdc *InstancePtr)
{
    int tile;
    u32 tile_en;
    u32 status;

    printf("\n====================================================");
    printf("\nRFDC ADC startup trial for enabled tiles");
    printf("\n====================================================");

    for (tile = 0; tile < 4; tile++) {
        tile_en = XRFdc_CheckTileEnabled(InstancePtr, XRFDC_ADC_TILE, (u32)tile);

        if (tile_en == 0U) {
            printf("\n[TILE %d] skipped (disabled)", tile);
            continue;
        }

        printf("\n[TILE %d] startup try...", tile);
        status = XRFdc_StartUp(InstancePtr, XRFDC_ADC_TILE, (u32)tile);

        if (status != XRFDC_SUCCESS) {
            printf("\n[TILE %d] startup FAIL, status=%u", tile, status);
        } else {
            printf("\n[TILE %d] startup PASS", tile);
        }
    }
}

//* ============================================================
// * Main
// * ============================================================
int main(void)
{
    int ret = EXIT_FAILURE;
    u32 readback = 0U;

    printf("\n----------- START ------------\n");

    if (spi_mux_init() != EXIT_SUCCESS) {
        printf("\n[FAIL] spi_mux_init()");
        goto ret_jump;
    }

    printf("\n[DBG] GPIO BASE = 0x%08X", SPI_MUX_GPIO_BASEADDR);
    printf("\n[DBG] initial DATA = 0x%08X", spi_mux_read());

    printf("\n====================================================");
    printf("\nRFCLK init");
    printf("\n====================================================");

    printf("\n[DBG] before XRFClk_Init(481)");
    XRFClk_Init(481);
    printf("\n[DBG] after XRFClk_Init(481)");

    printf("\n====================================================");
    printf("\nClock chip setup: minimal path");
    printf("\n====================================================");

    printf("\nReset LMK");
    if (rfclk_reset_lmk() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_reset_lmk()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nReset LMX2594_1");
    if (rfclk_reset_lmx1() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_reset_lmx1()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nSet LMK config ID 0");
    if (rfclk_set_lmk_cfg0() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_set_lmk_cfg0()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nSet LMX2594_1 config ID 0");
    if (rfclk_set_lmx1_cfg0() != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_set_lmx1_cfg0()");
        goto ret_jump;
    }
    printf("      Pass");

    printf("\nRead back LMX2594_1");
    if (rfclk_read_lmx1(&readback) != EXIT_SUCCESS) {
        printf("\n[FAIL] rfclk_read_lmx1()");
        goto ret_jump;
    } else {
        if (readback == 0U || readback == 0xFFFFFFFFU) {
            printf("\n[WARN] LMX2594_1 readback suspicious: 0x%08X", readback);
        } else {
            printf("\n[PASS] LMX2594_1 readback = 0x%08X", readback);
        }
    }

    printf("\n[DBG] wait 1 second for clock settle");
    sleep(1U);

    if (rfdc_init(&RFdcInst) != EXIT_SUCCESS)
        goto ret_jump;

    rfdc_raw_reg_check();

    rfdc_scan_all_adc(&RFdcInst);

    rfdc_try_start_enabled_adc_tiles(&RFdcInst);

    printf("\n----------- STOP ------------\n");
    XRFClk_Close();
    ret = EXIT_SUCCESS;

ret_jump:
    if (ret != EXIT_SUCCESS)
        printf("\n----------- ERROR STOP ------------\n");

    XRFClk_Close();
    return ret;
}

*/



/******************************************************************************
 * ZCU216 RFDC ADC host-side bring-up observer
 * Baremetal / Vitis 2022.2
 *
 * 목적:
 *   1) CLK104 (LMK/LMX) 초기화
 *   2) RFDC 초기화
 *   3) ADC tile/block 상태를 host에서 최대한 자세히 관찰
 *   4) ILA 없이 polling으로 상태 변화를 추적
 *
 * 주의:
 *   - 이 코드는 RFDC 상태 관찰용이다.
 *   - reset/startup/ip-reset 실험은 intentionally 제거했다.
 *   - PL 내부 actual signal waveform은 볼 수 없으므로,
 *     DataPathClocksStatus / FIFO / Tile status를 반복 관찰한다.
 ******************************************************************************/

#ifdef __BAREMETAL__
#ifndef SDT
#include "xparameters.h"
#endif
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"
#endif

#include "xrfdc.h"
#include "xrfclk.h"

#include <string.h>
#include <metal/device.h>

/* ------------------------------------------------------------ */
/* Basic config                                                 */
/* ------------------------------------------------------------ */
#ifndef SDT
#define RFDC_DEVICE_ID      XPAR_XRFDC_0_DEVICE_ID
#define RFDC_BASEADDR       XPAR_XRFDC_0_BASEADDR
#define RFDC_DEV_NAME       XPAR_XRFDC_0_DEV_NAME
#else
#define RFDC_DEVICE_ID      0
#define RFDC_BASEADDR       XPAR_XRFDC_0_BASEADDR
#define RFDC_DEV_NAME       "usp_rf_data_converter_0"
#endif

#if defined(XPAR_AXI_GPIO_0_BASEADDR)
  #define HAVE_SPI_MUX_GPIO     1
  #define SPI_MUX_GPIO_BASEADDR XPAR_AXI_GPIO_0_BASEADDR
#elif defined(XPAR_AXI_GPIO_1_BASEADDR)
  #define HAVE_SPI_MUX_GPIO     1
  #define SPI_MUX_GPIO_BASEADDR XPAR_AXI_GPIO_1_BASEADDR
#else
  #define HAVE_SPI_MUX_GPIO     0
  #define SPI_MUX_GPIO_BASEADDR 0U
#endif

/* ------------------------------------------------------------ */
/* User target                                                  */
/* ------------------------------------------------------------ */
#define TARGET_ADC_TILE_ID          0U
#define TARGET_ADC_BLOCK_ID         0U

/* CLK104 config IDs */
#define LMK_CFG_ID                  1U
#define LMX1_CFG_ID                 7U

/* behavior */
#define ENABLE_ALL_ADC_TILE_SCAN    1
#define ENABLE_REG_DUMP             1
#define ENABLE_PERIODIC_POLL        1
#define POLL_COUNT                  10
#define POLL_INTERVAL_US            200000   /* 200 ms */

/* ------------------------------------------------------------ */
/* Globals                                                      */
/* ------------------------------------------------------------ */
static XRFdc RFdcInst;
static struct metal_device *deviceptr = NULL;

#ifdef __BAREMETAL__
static metal_phys_addr_t metal_phys = RFDC_BASEADDR;
static struct metal_device CustomDev = {
    .name = RFDC_DEV_NAME,
    .bus = NULL,
    .num_regions = 1,
    .regions = {
        {
            .virt       = (void *)RFDC_BASEADDR,
            .physmap    = &metal_phys,
            .size       = 0x40000,
            .page_shift = (unsigned)(-1),
            .page_mask  = (unsigned)(-1),
            .mem_flags  = 0x0,
            .ops        = {NULL},
        }
    },
    .node     = {NULL},
    .irq_num  = 0,
    .irq_info = NULL,
};
#endif

/* ------------------------------------------------------------ */
/* Helper print                                                 */
/* ------------------------------------------------------------ */
static void print_banner(const char *title)
{
    xil_printf("\r\n====================================================\r\n");
    xil_printf("%s\r\n", title);
    xil_printf("====================================================\r\n");
}

static void print_sub(const char *title)
{
    xil_printf("\r\n-------------------- %s --------------------\r\n", title);
}

static void print_double_3(const char *tag, double v)
{
    int neg = 0;
    long iv;
    long fv;
    double x = v;

    if (x < 0.0) {
        neg = 1;
        x = -x;
    }

    iv = (long)x;
    fv = (long)((x - (double)iv) * 1000.0 + 0.5);

    if (fv >= 1000) {
        iv += 1;
        fv -= 1000;
    }

    if (neg) {
        xil_printf("%s-%ld.%03ld\r\n", tag, iv, fv);
    } else {
        xil_printf("%s%ld.%03ld\r\n", tag, iv, fv);
    }
}

static const char *yesno(int x)
{
    return x ? "YES" : "NO";
}

/* ------------------------------------------------------------ */
/* Basic info                                                   */
/* ------------------------------------------------------------ */
static void print_basic_info(void)
{
    print_banner("Basic info");

#if HAVE_SPI_MUX_GPIO
    xil_printf("[INFO] SPI_MUX_GPIO_BASEADDR = 0x%08lX\r\n",
               (unsigned long)SPI_MUX_GPIO_BASEADDR);
#else
    xil_printf("[INFO] SPI_MUX_GPIO_BASEADDR = <not present>\r\n");
#endif

    xil_printf("[INFO] RFDC_BASEADDR         = 0x%08lX\r\n",
               (unsigned long)RFDC_BASEADDR);
    xil_printf("[INFO] TARGET_ADC_TILE_ID   = %lu\r\n",
               (unsigned long)TARGET_ADC_TILE_ID);
    xil_printf("[INFO] TARGET_ADC_BLOCK_ID  = %lu\r\n",
               (unsigned long)TARGET_ADC_BLOCK_ID);
    xil_printf("[INFO] LMK_CFG_ID           = %lu\r\n",
               (unsigned long)LMK_CFG_ID);
    xil_printf("[INFO] LMX1_CFG_ID          = %lu\r\n",
               (unsigned long)LMX1_CFG_ID);
}

/* ------------------------------------------------------------ */
/* RFCLK init                                                   */
/* ------------------------------------------------------------ */
static int init_rfclk(void)
{
    u32 reg = 0U;
    int ret;

    print_banner("RFCLK init");

#if HAVE_SPI_MUX_GPIO
    xil_printf("[DBG ] SPI MUX GPIO detected at 0x%08lX\r\n",
               (unsigned long)SPI_MUX_GPIO_BASEADDR);
#else
    xil_printf("[WARN] No AXI GPIO found in xparameters.h\r\n");
    xil_printf("[WARN] Calling XRFClk_Init(0)\r\n");
#endif

    xil_printf("[DBG ] before XRFClk_Init\r\n");
    ret = XRFClk_Init((u32)SPI_MUX_GPIO_BASEADDR);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] XRFClk_Init failed, ret=%d\r\n", ret);
        return XST_FAILURE;
    }
    xil_printf("[DBG ] after XRFClk_Init\r\n");

    print_sub("LMK setup");
    ret = XRFClk_ResetChip(RFCLK_LMK);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] LMK reset failed, ret=%d\r\n", ret);
        return XST_FAILURE;
    }
    xil_printf("[OK  ] LMK reset\r\n");

    ret = XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMK, LMK_CFG_ID);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] LMK cfg %lu apply failed, ret=%d\r\n",
                   (unsigned long)LMK_CFG_ID, ret);
        return XST_FAILURE;
    }
    xil_printf("[OK  ] LMK cfg %lu apply\r\n", (unsigned long)LMK_CFG_ID);

    reg = 0U;
    ret = XRFClk_ReadReg(RFCLK_LMK, &reg);
    if (ret == XST_SUCCESS) {
        xil_printf("[INFO] LMK readback  = 0x%08lX\r\n", (unsigned long)reg);
    } else {
        xil_printf("[WARN] LMK readback failed, ret=%d\r\n", ret);
    }

    print_sub("LMX2594_1 setup");
    ret = XRFClk_ResetChip(RFCLK_LMX2594_1);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] LMX1 reset failed, ret=%d\r\n", ret);
        return XST_FAILURE;
    }
    xil_printf("[OK  ] LMX1 reset\r\n");

    ret = XRFClk_SetConfigOnOneChipFromConfigId(RFCLK_LMX2594_1, LMX1_CFG_ID);
    if (ret != XST_SUCCESS) {
        xil_printf("[FAIL] LMX1 cfg %lu apply failed, ret=%d\r\n",
                   (unsigned long)LMX1_CFG_ID, ret);
        return XST_FAILURE;
    }
    xil_printf("[OK  ] LMX1 cfg %lu apply\r\n", (unsigned long)LMX1_CFG_ID);

    reg = 0U;
    ret = XRFClk_ReadReg(RFCLK_LMX2594_1, &reg);
    if (ret == XST_SUCCESS) {
        xil_printf("[INFO] LMX1 readback = 0x%08lX\r\n", (unsigned long)reg);
    } else {
        xil_printf("[WARN] LMX1 readback failed, ret=%d\r\n", ret);
    }

    print_sub("LMX2594_2 probe");
    reg = 0U;
    ret = XRFClk_ReadReg(RFCLK_LMX2594_2, &reg);
    if (ret == XST_SUCCESS) {
        xil_printf("[INFO] LMX2 readback = 0x%08lX\r\n", (unsigned long)reg);
    } else {
        xil_printf("[INFO] LMX2 readback failed, ret=%d\r\n", ret);
    }

    xil_printf("[DBG ] wait clock settle 100 ms\r\n");
    usleep(50000);
    usleep(50000);

    return XST_SUCCESS;
}

/* ------------------------------------------------------------ */
/* RFDC init                                                    */
/* ------------------------------------------------------------ */
static int init_rfdc(XRFdc *InstPtr)
{
    int Status;
    XRFdc_Config *ConfigPtr;
    struct metal_init_params init_param = METAL_INIT_DEFAULTS;

    print_banner("RFDC init");

    if (metal_init(&init_param)) {
        xil_printf("[FAIL] metal_init failed\r\n");
        return XRFDC_FAILURE;
    }

    ConfigPtr = XRFdc_LookupConfig(RFDC_DEVICE_ID);
    if (ConfigPtr == NULL) {
        xil_printf("[FAIL] XRFdc_LookupConfig failed\r\n");
        return XRFDC_FAILURE;
    }

#ifdef __BAREMETAL__
    deviceptr = &CustomDev;
#endif

    Status = XRFdc_RegisterMetal(InstPtr, RFDC_DEVICE_ID, &deviceptr);
    if (Status != XRFDC_SUCCESS) {
        xil_printf("[FAIL] XRFdc_RegisterMetal failed, Status=%d\r\n", Status);
        return XRFDC_FAILURE;
    }

    Status = XRFdc_CfgInitialize(InstPtr, ConfigPtr);
    if (Status != XRFDC_SUCCESS) {
        xil_printf("[FAIL] XRFdc_CfgInitialize failed, Status=%d\r\n", Status);
        return XRFDC_FAILURE;
    }

    xil_printf("[OK  ] RFDC init done\r\n");
    xil_printf("[INFO] RFDC BaseAddr = 0x%08lX\r\n",
               (unsigned long)ConfigPtr->BaseAddr);
    xil_printf("[INFO] RFDC IPType   = %lu\r\n",
               (unsigned long)InstPtr->RFdc_Config.IPType);

    return XRFDC_SUCCESS;
}

/* ------------------------------------------------------------ */
/* RFDC status helpers                                          */
/* ------------------------------------------------------------ */
static void print_ip_status(XRFdc *InstPtr)
{
    XRFdc_IPStatus ipst;
    int t;

    memset(&ipst, 0, sizeof(ipst));

    print_banner("RFDC IP status");

    if (XRFdc_GetIPStatus(InstPtr, &ipst) != XRFDC_SUCCESS) {
        xil_printf("[FAIL] XRFdc_GetIPStatus failed\r\n");
        return;
    }

    for (t = 0; t < 4; t++) {
        xil_printf("[ADC TILE %d]\r\n", t);
        xil_printf("  IsEnabled       = %lu\r\n",
                   (unsigned long)ipst.ADCTileStatus[t].IsEnabled);
        xil_printf("  BlockStatusMask = 0x%08lX\r\n",
                   (unsigned long)ipst.ADCTileStatus[t].BlockStatusMask);
        xil_printf("  PowerUpState    = %lu\r\n",
                   (unsigned long)ipst.ADCTileStatus[t].PowerUpState);
        xil_printf("  PLLState        = %lu\r\n",
                   (unsigned long)ipst.ADCTileStatus[t].PLLState);
        xil_printf("  TileState       = %lu\r\n",
                   (unsigned long)ipst.ADCTileStatus[t].TileState);
    }

    for (t = 0; t < 4; t++) {
        xil_printf("[DAC TILE %d]\r\n", t);
        xil_printf("  IsEnabled       = %lu\r\n",
                   (unsigned long)ipst.DACTileStatus[t].IsEnabled);
        xil_printf("  BlockStatusMask = 0x%08lX\r\n",
                   (unsigned long)ipst.DACTileStatus[t].BlockStatusMask);
        xil_printf("  PowerUpState    = %lu\r\n",
                   (unsigned long)ipst.DACTileStatus[t].PowerUpState);
        xil_printf("  PLLState        = %lu\r\n",
                   (unsigned long)ipst.DACTileStatus[t].PLLState);
        xil_printf("  TileState       = %lu\r\n",
                   (unsigned long)ipst.DACTileStatus[t].TileState);
    }
}

static void print_clock_info(XRFdc *InstPtr, u32 Tile)
{
    u32 Ret;
    u32 ClkSrc = 0U;
    u32 PllLock = 0U;

    print_sub("RFDC clock info");

    Ret = XRFdc_GetClockSource(InstPtr, XRFDC_ADC_TILE, Tile, &ClkSrc);
    xil_printf("[CLOCK] Tile=%lu GetClockSource   ret=%lu src=%lu\r\n",
               (unsigned long)Tile,
               (unsigned long)Ret,
               (unsigned long)ClkSrc);

    Ret = XRFdc_GetPLLLockStatus(InstPtr, XRFDC_ADC_TILE, Tile, &PllLock);
    xil_printf("[CLOCK] Tile=%lu GetPLLLockStatus ret=%lu lock=%lu\r\n",
               (unsigned long)Tile,
               (unsigned long)Ret,
               (unsigned long)PllLock);
}

static void print_runtime_basic(XRFdc *InstPtr, u32 Tile, u32 Block)
{
    int Ret;
    u32 Decim = 0U;
    double FabClk = 0.0;

    print_sub("RFDC ADC runtime basic");

    Ret = XRFdc_CheckTileEnabled(InstPtr, XRFDC_ADC_TILE, Tile);
    xil_printf("[RUN ] CheckTileEnabled      = %d\r\n", Ret);

    Ret = XRFdc_CheckBlockEnabled(InstPtr, XRFDC_ADC_TILE, Tile, Block);
    xil_printf("[RUN ] CheckBlockEnabled     = %d\r\n", Ret);

    Ret = XRFdc_IsADCBlockEnabled(InstPtr, Tile, Block);
    xil_printf("[RUN ] IsADCBlockEnabled     = %d\r\n", Ret);

    Ret = XRFdc_IsADCDigitalPathEnabled(InstPtr, Tile, Block);
    xil_printf("[RUN ] IsADCDigitalPathEn    = %d\r\n", Ret);

    FabClk = XRFdc_GetFabClkFreq(InstPtr, XRFDC_ADC_TILE, Tile);
    print_double_3("[RUN ] FabClkFreq = ", FabClk);

    Ret = XRFdc_GetDecimationFactor(InstPtr, Tile, Block, &Decim);
    if (Ret == XRFDC_SUCCESS) {
        xil_printf("[RUN ] DecimationFactor     = %lu\r\n",
                   (unsigned long)Decim);
    } else {
        xil_printf("[RUN ] DecimationFactor     = <get failed> ret=%d\r\n", Ret);
    }
}

static void print_block_status(XRFdc *InstPtr, u32 Tile, u32 Block)
{
    int Ret;
    XRFdc_BlockStatus Blk;
    u32 Decim = 0U;

    memset(&Blk, 0, sizeof(Blk));

    print_sub("RFDC ADC block status");

    Ret = XRFdc_GetBlockStatus(InstPtr, XRFDC_ADC_TILE, Tile, Block, &Blk);
    if (Ret != XRFDC_SUCCESS) {
        xil_printf("[FAIL] XRFdc_GetBlockStatus failed, ret=%d\r\n", Ret);
        return;
    }

    xil_printf("[BLK ] Tile=%lu Block=%lu\r\n",
               (unsigned long)Tile, (unsigned long)Block);

    print_double_3("[BLK ] SamplingFreq = ", Blk.SamplingFreq);
    xil_printf("[BLK ] DigitalDataPathStatus = 0x%08lX\r\n",
               (unsigned long)Blk.DigitalDataPathStatus);
    xil_printf("[BLK ] AnalogDataPathStatus  = 0x%08lX\r\n",
               (unsigned long)Blk.AnalogDataPathStatus);
    xil_printf("[BLK ] DataPathClocksStatus  = 0x%08lX\r\n",
               (unsigned long)Blk.DataPathClocksStatus);
    xil_printf("[BLK ] IsFIFOFlagsEnabled    = 0x%08lX\r\n",
               (unsigned long)Blk.IsFIFOFlagsEnabled);
    xil_printf("[BLK ] IsFIFOFlagsAsserted   = 0x%08lX\r\n",
               (unsigned long)Blk.IsFIFOFlagsAsserted);

    Ret = XRFdc_GetDecimationFactor(InstPtr, Tile, Block, &Decim);
    if (Ret == XRFDC_SUCCESS) {
        xil_printf("[BLK ] DecimationFactor      = %lu\r\n",
                   (unsigned long)Decim);
    } else {
        xil_printf("[BLK ] DecimationFactor      = <get failed> ret=%d\r\n", Ret);
    }

    xil_printf("\r\n[DECODE]\r\n");
    xil_printf("  Analog path up         : %s\r\n",
               yesno((Blk.AnalogDataPathStatus  != 0U) ? 1 : 0));
    xil_printf("  Digital path nonzero   : %s\r\n",
               yesno((Blk.DigitalDataPathStatus != 0U) ? 1 : 0));
    xil_printf("  Data clocks up         : %s\r\n",
               yesno((Blk.DataPathClocksStatus  != 0U) ? 1 : 0));
    xil_printf("  FIFO flags enabled     : %s\r\n",
               yesno((Blk.IsFIFOFlagsEnabled    != 0U) ? 1 : 0));
    xil_printf("  FIFO flags asserted    : %s\r\n",
               yesno((Blk.IsFIFOFlagsAsserted   != 0U) ? 1 : 0));

    if (Blk.DataPathClocksStatus == 0U) {
        xil_printf("  WARN: datapath clocks are NOT up.\r\n");
        xil_printf("        Check m0_axis_aclk / m0_axis_aresetn / AXIS clock domain wiring.\r\n");
    }
}

static void print_mixer_settings(XRFdc *InstPtr, u32 Tile, u32 Block)
{
    int Ret;
    XRFdc_Mixer_Settings Mix;

    memset(&Mix, 0, sizeof(Mix));

    print_sub("RFDC ADC mixer settings");

    Ret = XRFdc_GetMixerSettings(InstPtr, XRFDC_ADC_TILE, Tile, Block, &Mix);
    if (Ret != XRFDC_SUCCESS) {
        xil_printf("[FAIL] XRFdc_GetMixerSettings failed, ret=%d\r\n", Ret);
        return;
    }

    xil_printf("[MIX ] Tile=%lu Block=%lu\r\n",
               (unsigned long)Tile, (unsigned long)Block);
    xil_printf("[MIX ] MixerType       = %lu\r\n", (unsigned long)Mix.MixerType);
    xil_printf("[MIX ] MixerMode       = %lu\r\n", (unsigned long)Mix.MixerMode);
    xil_printf("[MIX ] CoarseMixFreq   = %lu\r\n", (unsigned long)Mix.CoarseMixFreq);
    xil_printf("[MIX ] EventSource     = %lu\r\n", (unsigned long)Mix.EventSource);
    xil_printf("[MIX ] FineMixerScale  = %lu\r\n", (unsigned long)Mix.FineMixerScale);
    print_double_3("[MIX ] Freq        = ", Mix.Freq);
    print_double_3("[MIX ] PhaseOffset = ", Mix.PhaseOffset);
}

static void print_fifo_status(XRFdc *InstPtr, u32 Tile)
{
    int Ret;
    u8 FifoSt = 0U;

    print_sub("RFDC ADC FIFO status");

    Ret = XRFdc_GetFIFOStatus(InstPtr, XRFDC_ADC_TILE, Tile, &FifoSt);
    if (Ret == XRFDC_SUCCESS) {
        xil_printf("[FIFO] Tile=%lu status=%u\r\n",
                   (unsigned long)Tile, (unsigned)FifoSt);
    } else {
        xil_printf("[FIFO] Tile=%lu get failed ret=%d\r\n",
                   (unsigned long)Tile, Ret);
    }
}

static void dump_one_adc_tile(XRFdc *InstPtr, u32 Tile, u32 Block)
{
    print_banner("ADC tile snapshot");

    xil_printf("[SNAP] Tile=%lu Block=%lu\r\n",
               (unsigned long)Tile, (unsigned long)Block);

    print_clock_info(InstPtr, Tile);
    print_runtime_basic(InstPtr, Tile, Block);
    print_block_status(InstPtr, Tile, Block);
    print_mixer_settings(InstPtr, Tile, Block);
    print_fifo_status(InstPtr, Tile);
}

static void scan_all_adc_tiles(XRFdc *InstPtr)
{
    u32 tile;
    u32 block;

    print_banner("ADC tile scan");

    for (tile = 0; tile < 4; tile++) {
        xil_printf("\r\n[TILE %lu]\r\n", (unsigned long)tile);

        for (block = 0; block < 4; block++) {
            int ret_en = XRFdc_CheckBlockEnabled(InstPtr, XRFDC_ADC_TILE, tile, block);
            xil_printf("  Block %lu enabled check ret = %d\r\n",
                       (unsigned long)block, ret_en);

            if (ret_en == XRFDC_SUCCESS) {
                XRFdc_BlockStatus Blk;
                memset(&Blk, 0, sizeof(Blk));

                if (XRFdc_GetBlockStatus(InstPtr, XRFDC_ADC_TILE, tile, block, &Blk) == XRFDC_SUCCESS) {
                    xil_printf("    SamplingFreq         = ");
                    print_double_3("", Blk.SamplingFreq);
                    xil_printf("    DigitalDataPath      = 0x%08lX\r\n",
                               (unsigned long)Blk.DigitalDataPathStatus);
                    xil_printf("    AnalogDataPath       = 0x%08lX\r\n",
                               (unsigned long)Blk.AnalogDataPathStatus);
                    xil_printf("    DataPathClocks       = 0x%08lX\r\n",
                               (unsigned long)Blk.DataPathClocksStatus);
                } else {
                    xil_printf("    GetBlockStatus failed\r\n");
                }
            }
        }
    }
}

static void dump_driver_regs(XRFdc *InstPtr, u32 Tile)
{
#if ENABLE_REG_DUMP
    print_banner("RFDC register dump (driver)");
    xil_printf("[DUMP] ADC tile %lu regs\r\n", (unsigned long)Tile);
    XRFdc_DumpRegs(InstPtr, XRFDC_ADC_TILE, Tile);
#else
    (void)InstPtr;
    (void)Tile;
#endif
}

static void periodic_poll(XRFdc *InstPtr, u32 Tile, u32 Block, int count, u32 interval_us)
{
    int i;

    print_banner("Periodic ADC tile polling");

    for (i = 0; i < count; i++) {
        XRFdc_BlockStatus Blk;
        u32 ClkSrc = 0U;
        u32 PllLock = 0U;
        int Ret;

        memset(&Blk, 0, sizeof(Blk));

        xil_printf("\r\n[POLL %02d]\r\n", i);

        Ret = XRFdc_GetClockSource(InstPtr, XRFDC_ADC_TILE, Tile, &ClkSrc);
        xil_printf("  GetClockSource   ret=%d src=%lu\r\n",
                   Ret, (unsigned long)ClkSrc);

        Ret = XRFdc_GetPLLLockStatus(InstPtr, XRFDC_ADC_TILE, Tile, &PllLock);
        xil_printf("  GetPLLLockStatus ret=%d lock=%lu\r\n",
                   Ret, (unsigned long)PllLock);

        Ret = XRFdc_GetBlockStatus(InstPtr, XRFDC_ADC_TILE, Tile, Block, &Blk);
        if (Ret != XRFDC_SUCCESS) {
            xil_printf("  GetBlockStatus   ret=%d\r\n", Ret);
        } else {
            print_double_3("  SamplingFreq     = ", Blk.SamplingFreq);
            xil_printf("  DigitalDataPath  = 0x%08lX\r\n",
                       (unsigned long)Blk.DigitalDataPathStatus);
            xil_printf("  AnalogDataPath   = 0x%08lX\r\n",
                       (unsigned long)Blk.AnalogDataPathStatus);
            xil_printf("  DataPathClocks   = 0x%08lX\r\n",
                       (unsigned long)Blk.DataPathClocksStatus);
            xil_printf("  FIFOFlagsEnable  = 0x%08lX\r\n",
                       (unsigned long)Blk.IsFIFOFlagsEnabled);
            xil_printf("  FIFOFlagsAssert  = 0x%08lX\r\n",
                       (unsigned long)Blk.IsFIFOFlagsAsserted);
        }

        usleep(interval_us);
    }
}

/* ------------------------------------------------------------ */
/* Main                                                         */
/* ------------------------------------------------------------ */
int main(void)
{
    int Status;

    xil_printf("\r\n=========== START ===========\r\n");

    print_basic_info();

    Status = init_rfclk();
    if (Status != XST_SUCCESS) {
        xil_printf("\r\n[STOP] RFCLK init failed\r\n");
        xil_printf("=========== ERROR STOP ===========\r\n");
        return XST_FAILURE;
    }

    Status = init_rfdc(&RFdcInst);
    if (Status != XRFDC_SUCCESS) {
        xil_printf("\r\n[STOP] RFDC init failed\r\n");
        xil_printf("=========== ERROR STOP ===========\r\n");
        return XST_FAILURE;
    }

    /* 1) 전체 IP 상태 */
    print_ip_status(&RFdcInst);

    /* 2) 타겟 tile/block 상세 상태 */
    dump_one_adc_tile(&RFdcInst, TARGET_ADC_TILE_ID, TARGET_ADC_BLOCK_ID);

#if ENABLE_ALL_ADC_TILE_SCAN
    /* 3) 전체 ADC tile/block 스캔 */
    scan_all_adc_tiles(&RFdcInst);
#endif

#if ENABLE_REG_DUMP
    /* 4) driver reg dump */
    dump_driver_regs(&RFdcInst, TARGET_ADC_TILE_ID);
#endif

#if ENABLE_PERIODIC_POLL
    /* 5) 반복 polling */
    periodic_poll(&RFdcInst,
                  TARGET_ADC_TILE_ID,
                  TARGET_ADC_BLOCK_ID,
                  POLL_COUNT,
                  POLL_INTERVAL_US);
#endif

    xil_printf("\r\n=========== STOP ===========\r\n");
    return XRFDC_SUCCESS;
}
