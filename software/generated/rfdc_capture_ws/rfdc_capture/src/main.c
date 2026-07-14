#include <string.h>
#include "sleep.h"
#include "xil_printf.h"
#include "xtime_l.h"   /* XTime_GetTime / COUNTER_FREQUENCY (streaming rate) */
#include "xil_io.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xrfclk.h"
#include "xrfdc.h"   /* MTS API (XRFdc_MultiConverter_*) is declared here */

#define CLK104_GPIO_BASEADDR 0xA0040000U
#define RFDC_DEVICE_ID XPAR_XRFDC_0_DEVICE_ID
#define RFDC_BASEADDR XPAR_XRFDC_0_BASEADDR
#define RFDC_DEV_NAME XPAR_XRFDC_0_DEV_NAME

#define LMK_CONFIG_ID 0U
#define ADC_LMX_CONFIG_ID 0U
#define DAC_LMX_CONFIG_ID 0U

#define CTRL_GPIO_BASEADDR    0xA0050000U
#define STATUS_GPIO_BASEADDR  0xA0060000U
#define STATUS2_GPIO_BASEADDR 0xA0070000U
#define CAPTURE_GPIO_BASEADDR 0xA0080000U
#define GPIO2_OFFSET 0x8U

#define CAPTURE_AMPLITUDE 128U   /* known-good 06-19 value (capture_connected: tone SNR 39.4 dB) */
#define CAPTURE_DEPTH 16384         /* dut_capture DEPTH (AW=14): holds >=6 frames
                                     * of demod nibbles for multi-frame BER.    */
/* Goertzel target bin for the loopback tone at fs=307.2 MHz, N=8192.
 * The PL dac_tone square wave is 430.08/4 = 107.52 MHz in the DAC-fabric
 * domain, but the measured loopback tone lands at bin 2834 = 106.275 MHz
 * because the actual DAC:ADC fabric clock ratio is ~1.3838 vs the designed
 * 1.4 (see ISS-21 — clock config + PL IPs verified exact; accepted the
 * measured value). k = 2834; coeff = 2*cos(2*pi*k/N). Hardcoded so the
 * bare-metal app needs no libm. NOTE: takes effect on the next app rebuild. */
#define GOERTZEL_K 2834
#define GOERTZEL_COEFF (-1.13399)

/* Control word bit layout (matches RTL): */
#define CTRL_DAC_EN  0x1U
#define CTRL_DAC_OFDM (1U << 14)  /* RF 6b: DAC streams OFDM from BRAM (ctrl[14], free bit) */
#define RF_OFDM_MODE              /* 6b: OFDM TX. Comment out for 6a square-tone sanity. */
#define CTRL_CAP_EN  0x2U
#define CTRL_INDEX_SHIFT 2U
#define CTRL_AMP_SHIFT 16U

/* ----------------------------------------------------------------------------
 * DIGITAL LOOPBACK (DMA-free): dut_player BRAM -> phase3_sync_axis_dma_wrapper
 * -> dut_capture BRAM, driven entirely over AXI-Lite + GPIO.  No DMA, no
 * DAC/ADC.  Mirrors the proven indexed-GPIO style used by capture_block().
 * ------------------------------------------------------------------------- */
#define LOOP_CTRL_GPIO    0xA0050000U  /* OUT: dut_player.ctrl + dut_capture.ctrl */
#define STIM_LOAD_GPIO    0xA0090000U  /* OUT: dut_player.stim_wdata             */
#define LOOP_STATUS_GPIO  0xA0060000U  /* IN dual: +0x0 cap.status0, +0x8 player.status */
#define LOOP_CAPTURE_GPIO CAPTURE_GPIO_BASEADDR  /* IN: dut_capture.status_capture (reused) */
#define DUT_LITE          0xA00A0000U  /* DUT AXI-Lite base (byte offsets below) */

/* DUT AXI-Lite register byte offsets (from DUT_LITE). */
#define DUT_CONTROL         0x04U   /* bit0 enable, bit1 soft_reset           */
#define DUT_STATUS          0x08U   /* bit0 busy, bit1 done_seen W1C, bit2 error_seen W1C */
#define DUT_FRAME_LEN       0x0CU   /* = 4032                                  */
#define DUT_INPUT_PERIOD    0x58U   /* = 4160 (player period) */
#define DUT_INT_CFO_VALID   0x38U   /* read = snapshot the CFO result regs     */
#define DUT_INT_CFO_EST     0x3CU
#define DUT_INT_CFO_INDEX   0x40U
#define DUT_INT_CFO_APPLIED 0x44U
#define DUT_RESET_STATUS    0x48U   /* W1C                                     */
#define DUT_TLAST_COUNT     0x50U
#define DUT_ERROR_FLAGS     0x54U   /* W1C                                     */
#define DUT_INPUT_COUNT     0x10U   /* total input samples accepted (no-drop)  */
#define DUT_OUTPUT_COUNT    0x14U   /* total output samples                    */
#define DUT_CYC_TOTAL       0x5CU   /* free-running cycles (window denominator) */
#define DUT_IN_TVALID       0x60U   /* cycles s_axis_tvalid (player presenting) */
#define DUT_IN_TREADY       0x64U   /* cycles s_axis_tready (DUT ready)        */
#define DUT_THRESHOLD_REG   0x68U   /* frame-detector per-sample THRESHOLD R/W  */

#define DUT_CTRL_ENABLE      0x1U
#define DUT_CTRL_SOFT_RESET  0x2U
#define DUT_STAT_BUSY        0x1U
#define DUT_STAT_DONE_SEEN   0x2U
#define DUT_STAT_ERROR_SEEN  0x4U

/* dut_player ctrl-word bits. */
#define LOOP_PLAY_EN        (1U << 14)
#define LOOP_LOAD_EN        (1U << 15)
#define LOOP_CAP_CIRC       (1U << 16)  /* dut_capture circular sink (throughput test) */
#define LOOP_LOOP_EN        (1U << 29)  /* continuous: replay frame forever       */
//#define STREAM_TEST                   /* OFF for the demod control: finite fc_kp0 corrected capture */
#define LOOP_LOAD_ADDR_SHIFT 16U     /* load_addr = bits[28:16] */
/* dut_capture ctrl-word bits (shared ctrl GPIO). */
#define LOOP_CAP_EN         (1U << 1)
#define LOOP_RD_INDEX_SHIFT 2U       /* rd_index low 12 bits = ctrl[13:2]   */
/* MULTI-FRAME capture: dut_capture DEPTH bumped to 16384 (AW=14) so it can hold
 * N>=5 frames of demod nibbles back-to-back (2652 nibbles/frame). The 14-bit read
 * index is split: low 12 bits at ctrl[13:2] (LOOP_RD_INDEX_SHIFT, unchanged) and
 * high 2 bits at ctrl[19:18]. ctrl[19:18] sit inside the player's load_addr field
 * but the player only latches it on a load_en RISING edge (held low in readback),
 * so this is player-safe with NO BD rewiring. Build a 14-bit readback ctrl word
 * with LOOP_RD_CTRL(i). */
#define LOOP_RD_HI_SHIFT    18U       /* rd_index[13:12] = ctrl[19:18]        */
#define LOOP_RD_CTRL(i) ( (((u32)(i) & 0x0FFFU) << LOOP_RD_INDEX_SHIFT) \
                        | ((((u32)(i) >> 12) & 0x3U) << LOOP_RD_HI_SHIFT) )

#define DUT_FRAME_LEN_VAL   4032U
#define DUT_INPUT_PERIOD_VAL 4160U
#define STIM_LEN            4160U    /* number of stim words to load/play */

/* ---- MULTI-FRAME streaming (on-silicon proof of the A+B RTL fix) -------------
 * Drive the player in LOOP mode so frames stream back-to-back; capture N frames'
 * worth of demod nibbles, then compute per-frame BER vs golden tx_bits.        */
#define MF_NIBBLES_PER_FRAME 2652U          /* 12 sym * 221 data SC             */
#define MF_NUM_FRAMES        5U             /* N>=5 consecutive frames          */
#define MF_TOTAL_NIBBLES     (MF_NIBBLES_PER_FRAME * MF_NUM_FRAMES) /* 13260    */
#define MF_CAP_DEPTH         16384U          /* dut_capture DEPTH (AW=14)       */

/* ---- ON-CHIP HW BER CHECKER (additive tap on rx_full_board_top m_bits) -------
 * Scalable long-run BER: an on-chip rx_ber_checker holds the 2652-nibble golden
 * reference, tracks frame position via tuser/tlast, and accumulates bit errors /
 * frames over an UNBOUNDED continuous stream (no per-frame bit capture needed).
 * Read over two new GPIOs:
 *   ber_ctrl_gpio   0xA00C0000 OUT  bit0=soft clear, bits[7:4]=status_sel
 *   ber_status_gpio 0xA00D0000 IN   selected 32-bit counter word
 * status_sel: 0=total_bit_errors 1=frames_checked 2=total_nibbles 3=err_flags
 *             4={done,warmup_frames} 5=signature(0xBE11....)                    */
#define BER_CTRL_GPIO     0xA00C0000U
#define BER_STATUS_GPIO   0xA00D0000U
#define BER_CLR           (1U << 0)
#define BER_SEL_SHIFT     4U
#define BER_ROT_SHIFT     8U          /* ber_ctrl[11:8] = rot_off (0..11)       */
#define BER_ROT_MASK      0xFU
#define BER_NUM_ROT       12U         /* one rotation per OFDM symbol in a frame */
#define BER_SEL_ERRORS    0x0U
#define BER_SEL_FRAMES    0x1U
#define BER_SEL_NIBBLES   0x2U
#define BER_SEL_FLAGS     0x3U
#define BER_SEL_WARMUP    0x4U
#define BER_SEL_SIG       0x5U

/* ---- MODE-SELECTABLE TRANSCEIVER (ofdm_xcvr_board_top) contract --------------
 * The board adapter decodes mode/start from the SAME ber_ctrl GPIO (no new GPIO,
 * no BD rewiring):
 *     ber_ctrl[31:30] = mode  (0=TX, 1=RX, 2=LOOPBACK)
 *     ber_ctrl[29]    = start (level; adapter rising-edge -> 1-cycle TX kick)
 *     ber_ctrl[11:0]  = real rx_ber_checker control (clr/status_sel/rot_off)
 * In TX mode the adapter routes the live TX output IQ onto m_axis (dut_capture
 * records the EMITTED slot); in RX/LOOPBACK it routes the packed demod nibbles. */
#define XCVR_MODE_SHIFT   30U
#define XCVR_START_BIT    (1U << 29)
#define XCVR_LB_CONT_BIT  (1U << 28)   /* ber_ctrl[28]: LOOPBACK continuous re-emit */
#define XCVR_USE_DMA_BIT  (1U << 27)   /* ber_ctrl[27]: TX payload from MM2S DMA bank */
#define XCVR_DMADBG_BIT   (1U << 26)   /* ber_ctrl[26]: ber_status={frame_cnt,beat_cnt} */
#define XCVR_SRST_BIT     (1U << 12)   /* ber_ctrl[12]: transceiver soft-reset (level)  */
#define XCVR_MODE_TX      0U
#define XCVR_MODE_RX      1U
#define XCVR_MODE_LB      2U
#define XCVR_MODE_WORD(m) (((u32)(m) & 0x3U) << XCVR_MODE_SHIFT)

/* ---- MM2S DMA (arbitrary TX payload from DDR) — direct mode, MM2S only -------
 * axi_dma 7.1 @ 0xA00E0000 (SW contract; scripts/xcvr_loopback_bd.tcl). The MM2S
 * engine reads a 1328-byte payload from DDR and streams it (32-bit beats) to the
 * axi_to_parallel_tx bridge in ofdm_xcvr_board_top, which assembles the 10608-bit
 * data_bits_flat4 the modulator consumes. Bit order == tx_data_bits_packed.hex
 * (word w -> flat4[w*32 +: 32]); a payload equal to that hex reproduces the
 * golden slot. Register offsets per PG021 (MM2S direct mode). */
#define TXDMA_BASE        0xA00E0000U
#define TXDMA_MM2S_DMACR  (TXDMA_BASE + 0x00U)  /* MM2S control (RS=b0, Reset=b2) */
#define TXDMA_MM2S_DMASR  (TXDMA_BASE + 0x04U)  /* MM2S status (Halted=b0, Idle=b1) */
#define TXDMA_MM2S_SA     (TXDMA_BASE + 0x18U)  /* MM2S source address (low)      */
#define TXDMA_MM2S_SA_MSB (TXDMA_BASE + 0x1CU)  /* MM2S source address (high)     */
#define TXDMA_MM2S_LENGTH (TXDMA_BASE + 0x28U)  /* MM2S transfer bytes (starts xfer) */

/* ---- RX demod -> AXI DMA S2MM -> DDR (PHY-rate sink, milestone M1) ---------- */
#define RXDMA_BASE        0xA00F0000U          /* axi_dma S2MM lite regs (PG021)   */
#define RXDMA_S2MM_DMACR  (RXDMA_BASE + 0x30U) /* S2MM control (RS=b0, Reset=b2)   */
#define RXDMA_S2MM_DMASR  (RXDMA_BASE + 0x34U) /* S2MM status (Halted=b0, Idle=b1) */
#define RXDMA_S2MM_DA     (RXDMA_BASE + 0x48U) /* S2MM dest addr low               */
#define RXDMA_S2MM_DA_MSB (RXDMA_BASE + 0x4CU) /* S2MM dest addr high              */
#define RXDMA_S2MM_LENGTH (RXDMA_BASE + 0x58U) /* S2MM bytes (writing starts xfer) */
#define RX_DDR            0x30000000U          /* DDR sink for the demod nibbles   */

#define TX_PAYLOAD_WORDS  332U          /* 10608 bits = 331*32 + 16 -> 332 beats  */
#define TX_PAYLOAD_BYTES  (TX_PAYLOAD_WORDS * 4U)   /* 1328 bytes                 */
#define TX_PAYLOAD_DDR    0x20000000U    /* DDR staging buffer for the DMA payload */
#define TX_NBITS          10608U
#define TX_NNIBBLES       2652U          /* demod nibbles per frame (12*221)       */

/* DDR-resident TX payload (packed 32-bit words, bit order = tx_data_bits_packed).*/
static u32 *const g_tx_payload = (u32 *)TX_PAYLOAD_DDR;
/* Golden pattern (baked into the ELF from the hex) for the sanity anchor + as the
 * host-independent reference to reconstruct expected demod bits. Filled at run
 * time from the same source the RTL ROM used, so no new build artifact. */
#include "tx_data_bits_words.h"   /* static const u32 tx_data_bits_words[332];   */
#include "tx_image_words.h"       /* static const u32 tx_image_words[332]; (video) */

/* HIGH ber_ctrl bits ([31:28] = mode/start/lb_cont) that MUST be preserved on
 * every checker write (ber_read/ber_clear/ber_set_rot share the BER_CTRL_GPIO).
 * The continuous-LOOPBACK routine sets this so on-chip checker reads do not drop
 * the mode/lb_cont bits (which would kick the adapter out of LOOPBACK). */
static u32 g_xcvr_mode_word = 0U;
static int g_sync_quiet = 0;    /* suppress per-frame sync_config/STREAM prints (fps) */

/* LONG-RUN streaming target: how many frames to stream before reading the HW
 * counter. >=50 (ideally 100+). At ~187.5 Msps 1SPC each 4160-word frame is
 * ~4160/187.5e6 = 22.2 us; 200 frames ~= 4.4 ms of streaming. We give a generous
 * wall-clock window and let the HW counter tally the real frame count. */
#define BER_TARGET_FRAMES   600U     /* DESYNC-514 long-run verify: >=600 frames past the ~504 onset */
#define BER_STREAM_US       200000U  /* 200 ms continuous stream window (>=8000 frames-worth of cycles) */

/* Choose how stim gets into the player BRAM:
 *   USE_GPIO_LOAD defined  -> load stim_frame[] over STIM_LOAD_GPIO (step 1).
 *   USE_GPIO_LOAD undefined -> stim is pre-baked into the player BRAM via
 *                              $readmemh INIT_FILE in RTL; skip the GPIO load. */
/* First bring-up: stim is baked into the player BRAM via INIT_FILE=stim_tc0000.mem
 * (set in scripts/build_digital_loopback.tcl), so GPIO load is OFF. To load a
 * vector at runtime instead, #define USE_GPIO_LOAD and fill stim_frame[] (e.g.
 * #include "stim_frame_data.h" which has the tc0000 words). */
#define USE_GPIO_LOAD

#ifdef USE_GPIO_LOAD
#include "stim_sweep.h"   /* defines stim_frame[STIM_LEN]; regen per sweep vector */
#endif

/* RUN-MODE SELECT: define RUN_DIGITAL_LOOPBACK to run the DMA-free digital
 * loopback (dut_player -> DUT -> dut_capture) instead of the RF tone capture.
 * Leave it undefined to keep the proven run_capture()/capture_block() path.
 * (Comment out the next line to revert to the tone path.) */
#define RUN_DIGITAL_LOOPBACK  /* frame-7 wedge fix verification: DMA-free digital loopback */

/* ILA_DESYNC_TRIG: for the DESYNC-514 on-chip ILA capture.  At the long-run start
 * it clears the BER checker (total_bit_errors:=0, frame anchor preserved) and then
 * streams FAR past the ~514-frame desync onset, so the ILA (armed to trigger on
 * total_bit_errors!=0) catches the first-error transition with a large pre-trigger.
 * Define ONLY when building the ELF for the desync-ILA run. */
#define ILA_DESYNC_TRIG

/* RUN_XCVR_3MODE: drive the mode-selectable transceiver (ofdm_xcvr_board_top)
 * through TX / RX / LOOPBACK in sequence on silicon, using the SIMPLE reliable
 * continuous-capture method (no rot_off sweep / no capture pumping). Takes
 * priority over RUN_DIGITAL_LOOPBACK in main(). */
/* RF DUAL-TAP: run the RFDC-DDC -> DUT sync path (run_rf_sync), NOT the
 * RFDC-less 3-mode xcvr. RUN_XCVR_3MODE returns early skipping RFDC init, so it
 * must be OFF for the RF capture. */
#define RUN_XCVR_3MODE   /* LIVE-TX->RX LOOPBACK continuous-BER close-out build */

/* RF 6c-2 / DUAL-TAP: define RUN_RF_SYNC to run the RFDC-DDC -> DUT sync path
 * (this is the RF sync milestone + the dual-tap PRE/POST-deser isolation). Needs
 * RFDC/CLK104 up (DAC must transmit the OFDM), so it runs from the tile-ready
 * block like run_capture(). */
//#define RUN_RF_SYNC   /* OFF for digital-loopback frame-7 wedge-fix verification */
//#define RFSYNC_ILA_HOLD /* OFF (RF-only) for the digital-loopback verification build */

/* ----------------------------------------------------------------------------
 * RF SYNC (RF bringup 6c-2): RFDC DDC -> async FIFO -> rfdc_deser -> DUT
 * (phase3_sync_axis_dma_wrapper) -> rfsync_cap (dut_capture). The DAC streams
 * the OFDM (ctrl[14]) at baseband; the DUT should SYNC on the real RF OFDM.
 *
 * GPIO/AXI-Lite map (from scripts/rfsync_bd_edit.tcl):
 *   loop_ctrl_gpio      0xA0050000  OUT  shared: dac_tone+adc_cap+rfsync_cap ctrl
 *                                   bit0  = DAC_EN, bit14 = DAC_OFDM,
 *                                   bit1  = rfsync_cap cap_en, bits[13:2]=rd_index,
 *                                   bit16 = rfsync_cap circular
 *   rfsync_stat_gpio    0xA0090000  IN   rfsync_cap.status0 ({done,active,..,count})
 *   dut_0/s_axi (DUT)   0xA00A0000  AXI-Lite control/status (DUT_LITE)
 *   rfsync_capdata_gpio 0xA00B0000  IN   rfsync_cap.status_capture (BRAM readback)
 * ------------------------------------------------------------------------- */
#define RFSYNC_CTRL_GPIO    0xA0050000U   /* = LOOP_CTRL_GPIO (shared)         */
#define RFSYNC_STAT_GPIO    0xA0090000U   /* rfsync_cap.status0                */
#define RFSYNC_CAPDATA_GPIO 0xA00B0000U   /* rfsync_cap.status_capture         */
/* DUT_LITE = 0xA00A0000 already #defined below; DUT register offsets reused.  */

/* rfsync_cap (dut_capture) ctrl bits (in the shared loop_ctrl_gpio word).     */
#define RFS_CAP_EN          (1U << 1)     /* dut_capture cap_en                */
#define RFS_CAP_CIRC        (1U << 16)    /* dut_capture circular (ctrl_sync[16]) */
#define RFS_RD_INDEX_SHIFT  2U            /* rd_index = bits[13:2]             */
/* DAC bits (already defined as CTRL_DAC_EN=0x1, CTRL_DAC_OFDM=1<<14).         */
#define RFSYNC_FRAME_LEN    4032U
#define RFSYNC_RD_LEN       4096          /* dut_capture DEPTH = 1<<12         */

static XRFdc Rfdc;
static struct metal_device *RfdcDevice;
static metal_phys_addr_t RfdcPhys = RFDC_BASEADDR;
static struct metal_device RfdcCustomDevice = {
    .name = RFDC_DEV_NAME,
    .bus = NULL,
    .num_regions = 1,
    .regions = {{
        .virt = (void *)RFDC_BASEADDR,
        .physmap = &RfdcPhys,
        .size = 0x40000,
        .page_shift = (unsigned)(-1),
        .page_mask = (unsigned)(-1),
        .mem_flags = 0,
        .ops = {NULL},
    }},
    .node = {NULL},
    .irq_num = 0,
    .irq_info = NULL,
};

/* Captured samples kept in DDR so they can also be dumped over JTAG.
 * capture_buf     = DAC_ON window (RF 6c-1 DDC: complex baseband {Q,I} words)
 * capture_buf_off = DAC_OFF baseline window for energy comparison. */
static s32 capture_buf[CAPTURE_DEPTH];
static u8  g_expnib[TX_NNIBBLES];   /* per-frame precomputed expected demod nibbles */
static int g_align_off = -1;        /* cached clean-frame capture offset (stable) */
static s32 capture_buf_off[CAPTURE_DEPTH];
/* Per-mode capture snapshots for the 3-mode transceiver test (each survives in
 * DDR so the host xsct dump can read all three; capture_buf is reused per mode). */
static s32 xcvr_lb_buf[131072];  /* LOOPBACK demod nibbles (>=48 frames x 2652)  */
static s32 xcvr_rx_buf[16384];   /* RX demod nibbles (multi-frame)               */
static s32 xcvr_tx_buf[4096];    /* TX emitted slot IQ (4032 words)              */
/* EXPERIMENT 1: per-NCO bypass captures (5 NCO values x 4096 words). */
static s32 capture_sweep[5][4096];
/* RF DUAL-TAP: PRE-deser banked-BRAM capture (zcu216_adc_capture, 5 banks x
 * 1024 beats = 5120 complex samples). Read back banked; offline de-interleave
 * = raw.reshape(5,1024).T.reshape(-1). Dumped alongside the POST-deser
 * (rfsync_cap) buffer for the SAME RF window. */
#define ACAP_BANKS   5
#define ACAP_BEATS   1024
#define ACAP_SAMPLES (ACAP_BANKS * ACAP_BEATS)   /* 5120 */
static s32 capture_acap[ACAP_SAMPLES];

/* When set, rfsync_window OR's the dut_capture CIRCULAR bit (ctrl_sync[16]) into
 * the capture-control GPIO word so dut_capture keeps tready=1 and the chain
 * drains at full rate (no async-FIFO overflow), capturing a contiguous snapshot
 * of the last DEPTH samples instead of a non-deterministic overflow-dropped
 * slice. FIFO-overflow corruption test (firmware-only). */
static int g_cap_circular = 0;

static void print_tile(const char *kind, u32 tile,
                       const XRFdc_TileStatus *status, u32 pll_lock)
{
    xil_printf("ZCU216_RFDC: %s%lu enabled=%lu blocks=0x%02x "
               "power=%lu pll_state=%lu pll_lock=%lu tile_state=%lu\r\n",
               kind, (unsigned long)tile,
               (unsigned long)status->IsEnabled,
               status->BlockStatusMask,
               (unsigned long)status->PowerUpState,
               (unsigned long)status->PLLState,
               (unsigned long)pll_lock,
               (unsigned long)status->TileState);
}

static int tile_ready(XRFdc_IPStatus *ip_status, u32 type, u32 tile)
{
    XRFdc_TileStatus *tile_status;
    u32 pll_lock = XRFDC_PLL_UNLOCKED;

    tile_status = (type == XRFDC_ADC_TILE)
                    ? &ip_status->ADCTileStatus[tile]
                    : &ip_status->DACTileStatus[tile];

    if (XRFdc_GetPLLLockStatus(&Rfdc, type, tile, &pll_lock)
        != XRFDC_SUCCESS) {
        return 0;
    }

    return tile_status->IsEnabled
        && pll_lock == XRFDC_PLL_LOCKED
        && tile_status->TileState == XRFDC_STATE_FULL;
}

static int report_status(void)
{
    XRFdc_IPStatus ip_status;
    u32 adc3_lock = 0;   /* Plan A: tile225 = ext-clock distribution SOURCE */
    u32 adc2_lock = 0;
    u32 dac2_lock = 0;
    u32 dac3_lock = 0;

    memset(&ip_status, 0, sizeof(ip_status));
    if (XRFdc_GetIPStatus(&Rfdc, &ip_status) != XRFDC_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL GetIPStatus\r\n");
        return XST_FAILURE;
    }

    (void)XRFdc_GetPLLLockStatus(&Rfdc, XRFDC_ADC_TILE, 3, &adc3_lock);
    (void)XRFdc_GetPLLLockStatus(&Rfdc, XRFDC_ADC_TILE, 2, &adc2_lock);
    (void)XRFdc_GetPLLLockStatus(&Rfdc, XRFDC_DAC_TILE, 2, &dac2_lock);
    (void)XRFdc_GetPLLLockStatus(&Rfdc, XRFDC_DAC_TILE, 3, &dac3_lock);

    /* Plan A: ADC3 (tile225) receives the split 245.76 MHz on ADC_CLK_225 and
     * distributes it to ADC2 (tile224). If the external clock is absent, tile225
     * will NOT lock -> diagnostic. */
    print_tile("ADC", 3, &ip_status.ADCTileStatus[3], adc3_lock);
    print_tile("ADC", 2, &ip_status.ADCTileStatus[2], adc2_lock);
    print_tile("DAC", 2, &ip_status.DACTileStatus[2], dac2_lock);
    print_tile("DAC", 3, &ip_status.DACTileStatus[3], dac3_lock);

    /* Gate only on the ENABLED active data tiles: ADC2 (bank226), DAC2 (clock
     * distribution source, bank230) and DAC3 (active OFDM DAC, bank231). ADC3
     * (tile225) is disabled in this build (enabled=0) so requiring it would wedge
     * the gate; the active ADC clock comes from the CLK104/LMK common reference,
     * not from a live ADC3 tile. */
    return tile_ready(&ip_status, XRFDC_ADC_TILE, 2)
        && tile_ready(&ip_status, XRFDC_DAC_TILE, 2)
        && tile_ready(&ip_status, XRFDC_DAC_TILE, 3)
        ? XST_SUCCESS : XST_FAILURE;
}

/* Trigger one capture window, poll done, then read the BRAM into capture_buf.
 * dac_on selects whether the DAC tone is enabled during the window. */
static int capture_block(int dac_on)
{
    u32 base_ctrl = (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT)
                    | (dac_on ? CTRL_DAC_EN : 0U);
#ifdef RF_OFDM_MODE
    if (dac_on) base_ctrl |= CTRL_DAC_OFDM;   /* DAC plays OFDM (ctrl[14]) during capture */
#endif
    u32 status0 = 0;
    u32 done = 0;
    int poll;
    int i;

    /* Ensure a clean rising edge on capture-enable. */
    Xil_Out32(CTRL_GPIO_BASEADDR, base_ctrl);
    usleep(2000);
    Xil_Out32(CTRL_GPIO_BASEADDR, base_ctrl | CTRL_CAP_EN);

    for (poll = 0; poll < 200; ++poll) {
        status0 = Xil_In32(STATUS_GPIO_BASEADDR);
        done = (status0 >> 31) & 0x1U;
        if (done) {
            break;
        }
        usleep(2000);
    }

    /* Stop capture; keep DAC state for readback (does not matter). */
    Xil_Out32(CTRL_GPIO_BASEADDR, base_ctrl);

    xil_printf("ZCU216_CAPTURE: window dac_on=%d done=%lu status0=0x%08lx "
               "beats=%lu\r\n",
               dac_on, (unsigned long)done, (unsigned long)status0,
               (unsigned long)(status0 & 0xFFFFU));
    if (!done) {
        xil_printf("ZCU216_CAPTURE: FAIL window did not finish "
                   "(dac_on=%d status0=0x%08lx)\r\n",
                   dac_on, (unsigned long)status0);
        return XST_FAILURE;
    }

    /* Readback: the 13-bit sample index lives in ctrl[14:2]. The DAC enable
     * (ctrl[0]) and DAC-OFDM (ctrl[14]) bits would otherwise corrupt the index,
     * so drop them for the readback ctrl word (DAC state is irrelevant once the
     * window is captured). Keep only the amplitude field (ctrl[31:16]). */
    u32 rb_base = (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT);
    for (i = 0; i < CAPTURE_DEPTH; ++i) {
        u32 idx_ctrl = rb_base
                       | ((u32)i << CTRL_INDEX_SHIFT);
        Xil_Out32(CTRL_GPIO_BASEADDR, idx_ctrl);
        /* Let the 2-FF ctrl sync and registered BRAM read settle. */
        (void)Xil_In32(CAPTURE_GPIO_BASEADDR);
        capture_buf[i] = (s32)Xil_In32(CAPTURE_GPIO_BASEADDR);
    }

    /* Push capture_buf to physical DDR so the JTAG mrd sees it (the buffer is
     * cacheable write-back). Xil_DCacheFlush() is clean+invalidate on A53. */
    Xil_DCacheFlush();
    xil_printf("ZCU216_CAPTURE: dbg buf[0]=%ld buf[100]=%ld buf[4000]=%ld "
               "addr=0x%08lx\r\n",
               (long)capture_buf[0], (long)capture_buf[100],
               (long)capture_buf[4000], (unsigned long)capture_buf);

    return XST_SUCCESS;
}

/* Single-bin power at the tone frequency (Goertzel), plus total a.c. power.
 * No libm: integer/double +,-,* only with a hardcoded coefficient. */
static void analyze(const char *label)
{
    const double coeff = GOERTZEL_COEFF;
    double s1 = 0.0, s2 = 0.0;
    double sum = 0.0, sumsq = 0.0;
    double mean, ac_power, tone_power, ratio;
    int n;

    for (n = 0; n < CAPTURE_DEPTH; ++n) {
        sum += (double)capture_buf[n];
    }
    mean = sum / (double)CAPTURE_DEPTH;

    for (n = 0; n < CAPTURE_DEPTH; ++n) {
        double x = (double)capture_buf[n] - mean;   /* remove DC */
        double s0 = coeff * s1 - s2 + x;
        sumsq += x * x;
        s2 = s1;
        s1 = s0;
    }
    ac_power = sumsq / (double)CAPTURE_DEPTH;
    tone_power = (s1 * s1 + s2 * s2 - coeff * s1 * s2)
                 / ((double)CAPTURE_DEPTH * (double)CAPTURE_DEPTH);
    ratio = (ac_power > 0.0) ? (tone_power / ac_power) : 0.0;

    /* tone_pwr and ac_pwr are mean-square amplitudes (LSB^2). */
    xil_printf("ZCU216_CAPTURE: %s bin_k=%d tone_pwr=%d ac_pwr=%d "
               "tone/ac_x1000=%d mean=%d\r\n",
               label, GOERTZEL_K, (int)tone_power,
               (int)ac_power, (int)(ratio * 1000.0), (int)mean);
}

/* ISS-21: read back the actual per-tile PLL config / sample rate so the real
 * DAC:ADC fabric-clock ratio can be confirmed (xil_printf has no %f, so print
 * SampleRate[GHz] and RefClkFreq[MHz] scaled to kHz). */
static void report_pll(u32 type, u32 tile, const char *name)
{
    XRFdc_PLL_Settings pll;
    u32 src = 0xffffffffU;
    if (XRFdc_GetPLLConfig(&Rfdc, type, tile, &pll) != XRFDC_SUCCESS) {
        xil_printf("ZCU216_PLL: %s GetPLLConfig FAIL\r\n", name);
        return;
    }
    (void)XRFdc_GetClockSource(&Rfdc, type, tile, &src);
    xil_printf("ZCU216_PLL: %s enabled=%lu src=%lu fs=%lu kHz refclk=%lu kHz "
               "refdiv=%lu fbdiv=%lu outdiv=%lu\r\n",
               name,
               (unsigned long)pll.Enabled,
               (unsigned long)src,
               (unsigned long)(pll.SampleRate * 1000000.0),
               (unsigned long)(pll.RefClkFreq * 1000.0),
               (unsigned long)pll.RefClkDivider,
               (unsigned long)pll.FeedbackDivider,
               (unsigned long)pll.OutputDivider);
}

/* S2 PL BYPASS: AXI DMA (S2MM) register-level capture of the ADC stream to DDR.
 * DMA control @ 0xA0090000 (from the 09_pl_bypass BD); writes 128-bit ADC beats
 * to a DDR buffer for JTAG dump. Register offsets per PG021 (direct mode). */
#define DMA_BASEADDR     0xA0090000U
#define DMA_S2MM_DMACR   (DMA_BASEADDR + 0x30U)
#define DMA_S2MM_DMASR   (DMA_BASEADDR + 0x34U)
#define DMA_S2MM_DA      (DMA_BASEADDR + 0x48U)
#define DMA_S2MM_DA_MSB  (DMA_BASEADDR + 0x4CU)
#define DMA_S2MM_LENGTH  (DMA_BASEADDR + 0x58U)
#define DMA_DDR_BUF      0x10000000U
#define DMA_BEATS        8192U
#define DMA_BYTES        (DMA_BEATS * 16U)   /* 128-bit (16 B) AXIS beats */

static int dma_s2mm_capture(void)
{
    /* DAC tone ON (amp), adc_cap not needed for the DMA path. */
    Xil_Out32(CTRL_GPIO_BASEADDR, (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT) | CTRL_DAC_EN);
    usleep(2000);

    /* Soft-reset the DMA now that clk_adc2 is live (the PL reset at config time
     * happened before the RFDC/LMX clocks existed, so re-init here). Reset =
     * DMACR bit2; it self-clears once all DMA clocks are running. */
    Xil_Out32(DMA_S2MM_DMACR, 0x4U);
    {
        int rst_spins = 0;
        while ((Xil_In32(DMA_S2MM_DMACR) & 0x4U) && rst_spins < 1000000) { ++rst_spins; }
        xil_printf("ZCU216_DMA: soft-reset done spins=%d dmacr=0x%08lx dmasr=0x%08lx\r\n",
                   rst_spins, (unsigned long)Xil_In32(DMA_S2MM_DMACR),
                   (unsigned long)Xil_In32(DMA_S2MM_DMASR));
    }

    /* DEBUG (S2 isolation): small transfer + sentinel pre-fill + periodic DMASR
     * sampling, so we can tell stream-in vs MM-out vs completion. */
    const u32 test_bytes = DMA_BYTES;  /* full 8192-beat capture */
    volatile u32 *ddr = (volatile u32 *)DMA_DDR_BUF;
    for (int i = 0; i < 8; ++i) { ddr[i] = 0xDEADBEEFU; }   /* sentinel */

    Xil_Out32(DMA_S2MM_DMACR, 0x5001U);              /* RS=1 + IOC_IrqEn(b12) + Err_IrqEn(b14) */
    for (int i = 0; i < 1000000 && (Xil_In32(DMA_S2MM_DMASR) & 0x1U); ++i) { }
    xil_printf("ZCU216_DMA: after RS dmasr=0x%08lx\r\n",
               (unsigned long)Xil_In32(DMA_S2MM_DMASR));
    Xil_Out32(DMA_S2MM_DA, DMA_DDR_BUF);
    Xil_Out32(DMA_S2MM_DA_MSB, 0U);
    Xil_Out32(DMA_S2MM_LENGTH, test_bytes);          /* writing length starts S2MM */

    u32 sr = 0;
    int spins = 0;
    for (int s = 0; s < 8; ++s) {                    /* ~8 samples of DMASR over time */
        for (int k = 0; k < 2000000; ++k) {
            sr = Xil_In32(DMA_S2MM_DMASR); ++spins;
            if (sr & ((1U << 12) | (1U << 1))) break;
        }
        xil_printf("ZCU216_DMA: poll[%d] dmasr=0x%08lx len=%lu\r\n",
                   s, (unsigned long)sr, (unsigned long)Xil_In32(DMA_S2MM_LENGTH));
        if (sr & ((1U << 12) | (1U << 1))) break;
    }

    xil_printf("ZCU216_DMA: final sr=0x%08lx xfer_len=%lu ddr[0..3]=%08lx %08lx %08lx %08lx\r\n",
               (unsigned long)sr, (unsigned long)Xil_In32(DMA_S2MM_LENGTH),
               (unsigned long)ddr[0], (unsigned long)ddr[1],
               (unsigned long)ddr[2], (unsigned long)ddr[3]);
    if (sr & 0x70U) {
        xil_printf("ZCU216_DMA: FAIL S2MM error sr=0x%08lx\r\n", (unsigned long)sr);
        return XST_FAILURE;
    }
    if (!(sr & ((1U << 12) | (1U << 1)))) {
        xil_printf("ZCU216_DMA: FAIL S2MM timeout (sentinel intact=%d)\r\n",
                   (ddr[0] == 0xDEADBEEFU));
        return XST_FAILURE;
    }
    xil_printf("ZCU216_DMA: PASS S2MM small transfer complete\r\n");
    return XST_SUCCESS;
}

static int run_capture(void)
{
    xil_printf("ZCU216_CAPTURE: depth=%d fs=307.2MHz tone=107.52MHz "
               "buf=0x%08lx amp=%u\r\n",
               CAPTURE_DEPTH, (unsigned long)capture_buf,
               CAPTURE_AMPLITUDE);

    /* BRAM FALLBACK (AXI DMA S2MM blocked, 0 beats): use the PROVEN adc_cap BRAM
     * readback path on the 08_rfdc_capture bitstream. Capture one window with the
     * DAC tone enabled (RF loopback) into capture_buf for JTAG dump + FFT. */
    {
        int rc, i;
        /* RF 6c-1: capture a DAC_OFF baseline first, copy it aside, then the
         * DAC_ON window. Both buffers are dumped over JTAG for the offline
         * complex-baseband FFT energy comparison. */
        xil_printf("ZCU216_CAPTURE: BRAM window DAC_OFF baseline\r\n");
        rc = capture_block(0);
        if (rc == XST_SUCCESS) {
            for (i = 0; i < CAPTURE_DEPTH; ++i) {
                capture_buf_off[i] = capture_buf[i];
            }
            analyze("dac_off");
        }
        xil_printf("ZCU216_CAPTURE: BRAM window DAC_ON (OFDM loopback)\r\n");
        rc = capture_block(1);
        if (rc == XST_SUCCESS) {
            xil_printf("ZCU216_CAPTURE: PASS BRAM window captured\r\n");
            analyze("dac_on");
        }
        (void)dma_s2mm_capture;  /* retained for the DMA bring-up; unused here */
        return rc;
    }
}

/* DMA-free DIGITAL LOOPBACK: drive dut_player -> DUT -> dut_capture purely over
 * AXI-Lite + GPIO.  Captured frame ends up in capture_buf[] for a JTAG dump,
 * exactly like the tone path.  Leaves run_capture()/capture_block() untouched. */
/* Persisted rot_off (whole-symbol reference rotation, 0..11). The checker's
 * frame alignment is a firmware SEARCH over the 12 rotations; the aligned one
 * yields ~0 errors. We keep it in a global so ber_read() preserves it (the
 * ber_ctrl GPIO is shared between status_sel and rot_off). */
static u32 g_ber_rot = 0;

/* Read one on-chip BER counter word: drive status_sel (preserving rot_off),
 * settle the 2-FF ctrl sync + readback, dummy read, then the real read. */
static u32 ber_read(u32 sel)
{
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word |
              ((sel & 0xFU) << BER_SEL_SHIFT) |
              ((g_ber_rot & BER_ROT_MASK) << BER_ROT_SHIFT));
    (void)Xil_In32(BER_STATUS_GPIO);          /* dummy: settle the mux/readback */
    return Xil_In32(BER_STATUS_GPIO);
}

/* Set the whole-symbol reference rotation (0..11) and remember it. */
static void ber_set_rot(u32 rot)
{
    g_ber_rot = rot & BER_ROT_MASK;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | (g_ber_rot << BER_ROT_SHIFT));  /* sel=0, clr=0 */
}

/* Soft-clear the checker (level pulse on ber_ctrl[0]), keeping rot_off. */
static void ber_clear(void)
{
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word |
              BER_CLR | ((g_ber_rot & BER_ROT_MASK) << BER_ROT_SHIFT));
    usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | ((g_ber_rot & BER_ROT_MASK) << BER_ROT_SHIFT));
    usleep(50);
}

/* Keep the continuous demod stream FLOWING for a fixed number of dwell cycles.
 * FRAME-7 WEDGE FIX: the FINITE dut_capture sink fills after ~16384 nibbles
 * (~6.18 frames) and then DROPS s_axis_tready PERMANENTLY (dut_capture.v:84),
 * back-pressuring the WHOLE chain into the sync STALL_TIMEOUT at frame 7 (ILA-
 * proven: filled=[1,1] -> fft_dout_tready=0 -> s_ready wedge -> stall_cnt=254).
 * The old code toggled cap_en to drain the FINITE sink, but the re-arm cannot
 * un-wedge cleanly within the dwell, so the stream stutters and the rot_off
 * sweep never finds a stable zero-error rotation. Use CIRCULAR mode instead:
 * dut_capture is always-ready + wraps, so the stream is GAPLESS and never
 * wedges. The checker is a passive tap that counts every nibble that flows, so
 * circular mode gives it a clean, uninterrupted stream to anchor + tally on. */
static void ber_pump_stream(int rearms)
{
    int k;
    /* engage circular sink ONCE; then just dwell so the stream keeps flowing.
     *
     * DESYNC-514 FIX B (sink-stall paradox resolution):
     *   dut_capture s_axis_tready = active || circular.  A PRIOR FINITE-mode
     *   capture (Step 4/5 readback fill) drove active->0 at count==DEPTH-1 with
     *   circular still 0 -> tready dropped -> the WHOLE chain deadlocked
     *   (sync stall_cnt->254) BEFORE this circular long-run even starts.  Simply
     *   OR-ing CAP_CIRC onto the already-asserted CAP_EN does NOT re-pulse the
     *   cap_en RISING edge, so `active` stays 0 and `wr_full` stays 1 -- the sink
     *   only un-stalls because circular now forces tready high, but it un-stalls
     *   from a DRAINED-slack state (the recovery slip Fix A then re-anchors).
     *   To make the handoff DETERMINISTIC and keep the sink in a known state,
     *   RE-PULSE cap_en (low->high) WITH circular set: this fires `start`, resets
     *   wr_addr/wr_full, and sets active=1 alongside circular=1 so tready is
     *   unconditionally high (active|circular) for the whole stream. */
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN); /* cap_en LOW */
    usleep(50);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN); /* rising edge */
    for (k = 0; k < rearms; ++k) {
        usleep(2000);
    }
}

/* ============================================================================
 * MODE-SELECTABLE TRANSCEIVER 3-MODE SILICON TEST (ofdm_xcvr_board_top).
 *
 * Tests TX / RX / LOOPBACK in sequence on hardware using the SIMPLE, reliable
 * continuous-capture method proven in 5e6b239 (clean arming; NO rot_off sweep,
 * NO capture "pumping" -> avoids the firmware-arming silicon corruption trap).
 *
 * For each mode: real AXI-Lite writes configure the sync (enable / frame_len
 * 4032 / threshold 40000); the mode is set on the ber_ctrl GPIO; the demod
 * nibbles (RX/LB) OR the emitted TX slot (TX) are captured into dut_capture and
 * read back into capture_buf[] for the host (ber_demod_bits.py / tx-slot
 * compare). The on-chip rx_ber_checker is read only as a SECONDARY sanity.
 * ============================================================================*/

/* Configure the DUT sync via REAL AXI-Lite writes (board needs this; the sim
 * used a force shortcut). clr_only=1 just W1C-clears sticky flags + re-enables. */
static void xcvr_sync_config(void)
{
    Xil_Out32(DUT_LITE + DUT_STATUS, DUT_STAT_DONE_SEEN | DUT_STAT_ERROR_SEEN); /* W1C */
    Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);  /* W1C */
    Xil_Out32(DUT_LITE + DUT_RESET_STATUS, 0xFFFFFFFFU); /* W1C */
    Xil_Out32(DUT_LITE + DUT_FRAME_LEN, DUT_FRAME_LEN_VAL);        /* 4032 */
    Xil_Out32(DUT_LITE + DUT_INPUT_PERIOD, DUT_INPUT_PERIOD_VAL);  /* 4160 */
    Xil_Out32(DUT_LITE + DUT_THRESHOLD_REG, 40000U);              /* detector level */
    Xil_Out32(DUT_LITE + 0x4CU, 0x0U);                  /* DEBUG_CTRL = NORMAL */
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET);       /* soft-reset pulse */
    usleep(20);                                    /* ~3.5ms REAL (usleep ~175x slow) */
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);
    usleep(20);
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_ENABLE);          /* enable = 1 */
    if (!g_sync_quiet)
        xil_printf("ZCU216_XCVR: sync cfg control=0x%08lx status=0x%08lx thr=40000 frame_len=4032\r\n",
                   (unsigned long)Xil_In32(DUT_LITE + DUT_CONTROL),
                   (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS));
}

/* Set the adapter mode on the ber_ctrl GPIO (keeps real ber-ctrl bits = 0). */
static void xcvr_set_mode(u32 m)
{
    Xil_Out32(BER_CTRL_GPIO, XCVR_MODE_WORD(m));
    usleep(100);
}

/* Pulse the TX start (rising edge of ber_ctrl[29]); preserves the mode bits. */
static void xcvr_start_pulse(u32 m)
{
    Xil_Out32(BER_CTRL_GPIO, XCVR_MODE_WORD(m));                 /* start low  */
    usleep(50);
    Xil_Out32(BER_CTRL_GPIO, XCVR_MODE_WORD(m) | XCVR_START_BIT); /* start high */
    usleep(50);
    Xil_Out32(BER_CTRL_GPIO, XCVR_MODE_WORD(m));                 /* start low  */
}

/* Read back the dut_capture demod-nibble / TX-slot buffer into capture_buf[].
 * cap_base must already have cap_en asserted (and any mode bits live on the
 * SEPARATE ber_ctrl GPIO, so loop_ctrl readback indexing is undisturbed). */
static int xcvr_readback(u32 cap_base, int rd_len)
{
    int i;
    if (rd_len > (int)CAPTURE_DEPTH) rd_len = (int)CAPTURE_DEPTH;
    for (i = 0; i < rd_len; ++i) {
        u32 idx_ctrl = cap_base | LOOP_RD_CTRL((u32)i);
        Xil_Out32(LOOP_CTRL_GPIO, idx_ctrl);
        (void)Xil_In32(LOOP_CAPTURE_GPIO);   /* dummy: settle 2-FF + BRAM read */
        capture_buf[i] = (s32)Xil_In32(LOOP_CAPTURE_GPIO);
    }
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    Xil_DCacheFlushRange((INTPTR)capture_buf, (unsigned)rd_len * sizeof(s32));
    return rd_len;
}

/* Poll dut_capture until full (status0 bit31). Returns 1 if done, 0 on timeout. */
static u32 xcvr_wait_capture(void)
{
    u32 status0 = 0, done = 0;
    int poll;
    for (poll = 0; poll < 400; ++poll) {
        status0 = Xil_In32(LOOP_STATUS_GPIO);
        done = (status0 >> 31) & 0x1U;
        if (done) break;
        if ((poll % 50) == 0)
            xil_printf("ZCU216_XCVR: poll=%d cap.status0=0x%08lx count=%lu "
                       "tlast=%lu dut_status=0x%08lx\r\n",
                       poll, (unsigned long)status0,
                       (unsigned long)(status0 & 0xFFFFU),
                       (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
                       (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS));
        usleep(2000);
    }
    return done;
}

/* Poll dut_capture until at least min_count beats recorded (count[15:0]) OR
 * done. Used for TX where only 4032 beats arrive (< DEPTH, never asserts done).
 * Returns the captured count. */
static u32 xcvr_wait_count(u32 min_count)
{
    u32 status0 = 0, cnt = 0, done = 0;
    int poll, stable = 0;
    for (poll = 0; poll < 400; ++poll) {
        status0 = Xil_In32(LOOP_STATUS_GPIO);
        cnt  = status0 & 0xFFFFU;
        done = (status0 >> 31) & 0x1U;
        if (done || (cnt >= min_count)) { stable++; if (stable >= 2) break; }
        else stable = 0;
        usleep(2000);
    }
    return cnt;
}

/* Load the golden 4160 sync-capable frame into the player BRAM (GPIO load). */
static void xcvr_load_player(void)
{
#ifdef USE_GPIO_LOAD
    int i;
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    usleep(2000);
    for (i = 0; i < (int)STIM_LEN; ++i) {
        u32 addr = ((u32)i << LOOP_LOAD_ADDR_SHIFT);
        Xil_Out32(STIM_LOAD_GPIO, stim_frame[i]);
        Xil_Out32(LOOP_CTRL_GPIO, addr);
        Xil_Out32(LOOP_CTRL_GPIO, addr | LOOP_LOAD_EN);
        Xil_Out32(LOOP_CTRL_GPIO, addr);
    }
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    xil_printf("ZCU216_XCVR: player loaded via GPIO (%u words)\r\n", STIM_LEN);
#else
    xil_printf("ZCU216_XCVR: player stim pre-baked (INIT_FILE)\r\n");
#endif
}

/* ============================================================================
 * CONTINUOUS LIVE-TX -> RX LOOPBACK BER (ofdm_xcvr_board_top, lb_cont=1).
 *
 * Closes the full digital transceiver on silicon: the LIVE TX modulator
 * (tx_ofdm_top: bits ROM -> 16-QAM/pilots -> 256-pt IFFT + CP) emits a 4032-
 * sample slot; the adapter frames it 64+4032+64 and (with lb_cont=1) RE-EMITS it
 * back-to-back, so the on-chip PASSIVE rx_ber_checker tallies a long continuous
 * stream of demodulated frames. dut_capture runs CIRCULAR (never fills -> the
 * chain never back-pressures into the sync STALL_TIMEOUT). No player, no DMA.
 *
 * Reports (mirrors the RX-only ZCU216_BER long-run):
 *   first_err_frame (-1 = none), frames_checked, total_bit_errors, dut_error_flags,
 *   and RESULT PASS/FAIL. GOAL: first_err_frame=-1 / BER=0 over many frames.
 * ==========================================================================*/
#define XLB_CONT_TARGET_FRAMES 800U   /* stream past the old ~504 desync onset */
#define XLB_CONT_MAX_IT        400     /* ~2 ms/iter -> ~0.8 s wall cap        */

static int run_xcvr_lb_continuous(void)
{
    u32 sink_cont = LOOP_CAP_EN | LOOP_CAP_CIRC;   /* circular sink, no player  */
    u32 rot, best_rot = 0xFFFFFFFFU, be0, be1, fc0, fc1;
    u32 f0, e0, br_frames, br_errs, br_nibs, br_flags;
    u32 d_frames = 0, d_errs = 0, first_err_at = 0xFFFFFFFFU;
    int it, zero_rots = 0;

    xil_printf("ZCU216_XLB: ===== CONTINUOUS LIVE-TX -> RX LOOPBACK (lb_cont=1) =====\r\n");

    /* Enter LOOPBACK + continuous re-emit; keep these HIGH bits on every GPIO
     * write from now on (ber_read/ber_clear OR in g_xcvr_mode_word). */
    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB) | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);    /* mode=LB, lb_cont=1, start=0 */
    usleep(100);

    xcvr_sync_config();                            /* enable/frame_len/threshold */

    /* Engage the circular sink FIRST (chain flowing, tready high), then kick the
     * live TX once. The framing FSM auto re-arms (lb_cont) -> gapless frames. */
    Xil_Out32(LOOP_CTRL_GPIO, sink_cont & ~LOOP_CAP_EN); usleep(200);
    Xil_Out32(LOOP_CTRL_GPIO, sink_cont);                usleep(2000); /* cap_en rising */

    /* start pulse WHILE preserving mode+lb_cont: low -> high(bit29) -> low. */
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                    usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT);   usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                    usleep(2000);

    /* clear stale sticky DUT error flags now that circular sink prevents stall. */
    Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);
    usleep(4000);   /* let the continuous stream reach steady state */

    /* --- rot_off search: find the aligned whole-symbol rotation (0..11). --- */
    xil_printf("ZCU216_XLB: rot_off | d_frames | d_bit_errors | flags\r\n");
    for (rot = 0; rot < 12U; ++rot) {
        ber_set_rot(rot);
        usleep(300);
        be0 = ber_read(BER_SEL_ERRORS);  fc0 = ber_read(BER_SEL_FRAMES);
        usleep(6000);                                  /* several frames flow */
        be1 = ber_read(BER_SEL_ERRORS);  fc1 = ber_read(BER_SEL_FRAMES);
        xil_printf("ZCU216_XLB:   %2lu   | %8lu | %12lu | 0x%08lx\r\n",
                   (unsigned long)rot, (unsigned long)(fc1 - fc0),
                   (unsigned long)(be1 - be0),
                   (unsigned long)ber_read(BER_SEL_FLAGS));
        if ((fc1 - fc0) >= 1U && (be1 - be0) == 0U) { best_rot = rot; zero_rots++; }
    }
    xil_printf("ZCU216_XLB: SWEEP aligned_rot=%ld zero-error rotations=%lu\r\n",
               (best_rot == 0xFFFFFFFFU) ? -1L : (long)best_rot,
               (unsigned long)zero_rots);
    ber_set_rot((best_rot == 0xFFFFFFFFU) ? 0U : best_rot);

    /* --- LONG RUN: clear once at the aligned rot, then tally the continuous
     * live-TX frame stream. No soft-reset / no re-kick -> alignment preserved. */
    ber_clear();
    usleep(2000);
    f0 = ber_read(BER_SEL_FRAMES);
    e0 = ber_read(BER_SEL_ERRORS);
    xil_printf("ZCU216_XLB: long-run start rot_off=%lu (baseline f0=%lu e0=%lu) target=%u frames\r\n",
               (unsigned long)g_ber_rot, (unsigned long)f0, (unsigned long)e0,
               XLB_CONT_TARGET_FRAMES);

    for (it = 0; it < XLB_CONT_MAX_IT; ++it) {
        usleep(2000);
        br_frames = ber_read(BER_SEL_FRAMES);
        br_errs   = ber_read(BER_SEL_ERRORS);
        br_flags  = ber_read(BER_SEL_FLAGS);
        d_frames  = br_frames - f0;
        d_errs    = br_errs   - e0;
        if (d_errs != 0 && first_err_at == 0xFFFFFFFFU) {
            first_err_at = d_frames;
            xil_printf("ZCU216_XLB: FIRST ERROR at d_frames=%lu d_errs=%lu flags=0x%08lx dut_err=0x%08lx\r\n",
                       (unsigned long)d_frames, (unsigned long)d_errs,
                       (unsigned long)br_flags,
                       (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
        }
        if (it < 12 || (it % 25) == 0)
            xil_printf("ZCU216_XLB: it=%d d_frames=%lu d_errs=%lu flags=0x%08lx\r\n",
                       it, (unsigned long)d_frames, (unsigned long)d_errs,
                       (unsigned long)br_flags);
        if (d_frames >= XLB_CONT_TARGET_FRAMES) break;
    }

    br_frames = ber_read(BER_SEL_FRAMES);
    br_errs   = ber_read(BER_SEL_ERRORS);
    br_nibs   = ber_read(BER_SEL_NIBBLES);
    br_flags  = ber_read(BER_SEL_FLAGS);
    d_frames  = br_frames - f0;
    d_errs    = br_errs   - e0;
    xil_printf("ZCU216_XLB: ======== CONTINUOUS LOOPBACK RESULT ========\r\n");
    xil_printf("ZCU216_XLB: frames_checked=%lu total_bit_errors=%lu (cum nibbles=%lu bits=%lu)\r\n",
               (unsigned long)d_frames, (unsigned long)d_errs,
               (unsigned long)br_nibs, (unsigned long)(br_nibs * 4U));
    xil_printf("ZCU216_XLB: dut_error_flags=0x%08lx tlast_count=%lu first_err_frame=%ld rot_off=%lu\r\n",
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS),
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (first_err_at == 0xFFFFFFFFU) ? -1L : (long)first_err_at,
               (unsigned long)g_ber_rot);
    if (d_frames >= 50U && d_errs == 0U && br_flags == 0U) {
        xil_printf("ZCU216_XLB: RESULT PASS (LIVE TX->RX BER=0 over %lu streamed frames, %lu bits)\r\n",
                   (unsigned long)d_frames,
                   (unsigned long)(d_frames * MF_NIBBLES_PER_FRAME * 4U));
    } else {
        xil_printf("ZCU216_XLB: RESULT FAIL (d_frames=%lu d_errs=%lu flags=0x%08lx)\r\n",
                   (unsigned long)d_frames, (unsigned long)d_errs, (unsigned long)br_flags);
    }

    /* leave continuous mode for the subsequent finite-readback stages. */
    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);
    return XST_SUCCESS;
}

/* ============================================================================
 * ARBITRARY-PAYLOAD TX-FROM-DDR (MM2S DMA) round-trip proof.
 *
 * DDR -> MM2S DMA -> axi_to_parallel_tx bridge -> live TX modulator ->
 * internal RX demod -> dut_capture BRAM -> host/on-chip compare vs the DDR
 * payload. Uses LOOPBACK mode with ber_ctrl[27]=use_dma so the TX payload is
 * the DMA bank (not the ROM). The RX->BRAM path is the proven one (untouched).
 * ==========================================================================*/

/* Issue one MM2S transfer: reset, RS=1, source addr, length (length starts it).
 * Returns 1 on Idle-complete, 0 on timeout/error. */
static int txdma_send(u32 src_addr, u32 nbytes)
{
    int i;
    u32 sr;
    /* soft reset (self-clears) */
    Xil_Out32(TXDMA_MM2S_DMACR, 0x4U);
    for (i = 0; i < 100000 && (Xil_In32(TXDMA_MM2S_DMACR) & 0x4U); ++i) { }
    /* run */
    Xil_Out32(TXDMA_MM2S_DMACR, 0x1U);            /* RS=1 */
    for (i = 0; i < 100000 && (Xil_In32(TXDMA_MM2S_DMASR) & 0x1U); ++i) { } /* wait !Halted */
    Xil_Out32(TXDMA_MM2S_SA,     src_addr);
    Xil_Out32(TXDMA_MM2S_SA_MSB, 0U);
    Xil_Out32(TXDMA_MM2S_LENGTH, nbytes);         /* writing length starts xfer */
    /* wait for Idle (bit1). Bounded low: a 1328-byte MM2S completes in microseconds;
     * each Xil_In32 to the DMA reg is a ~0.7us AXI-lite read, so a big cap was ~1.4ms
     * of pure poll (the fps killer when Idle lagged). Data transfers regardless. */
    sr = 0;
    for (i = 0; i < 30000; ++i) {
        sr = Xil_In32(TXDMA_MM2S_DMASR);
        if (sr & 0x2U) break;                     /* Idle */
        if (sr & 0x770U) break;                    /* any error bit */
    }
    if (!g_sync_quiet)
        xil_printf("ZCU216_TXDMA: send src=0x%08lx bytes=%lu dmasr=0x%08lx (%s)\r\n",
                   (unsigned long)src_addr, (unsigned long)nbytes, (unsigned long)sr,
                   (sr & 0x2U) ? "IDLE-OK" : ((sr & 0x770U) ? "ERROR" : "TIMEOUT"));
    return (sr & 0x2U) && !(sr & 0x770U);
}

/* Expected demod nibble b0..b3 from a packed payload word array. flat4 bit b
 * comes from words[b/32] bit (b%32); carrier c nibble = flat4[c*4 +: 4]; host
 * unpack: b0=(w>>3),b1=(w>>2),b2=(w>>1),b3=(w>>0). Here we return the 4 expected
 * bits packed the SAME way the RX m_axis nibble carries them: the on-chip demod
 * word low nibble = {b0,b1,b2,b3} in bits[3..0] = (b0<<3)|(b1<<2)|(b2<<1)|b3. */
static u32 tx_expected_nibble(const u32 *words, int carrier)
{
    int b = carrier * 4;
    u32 b0 = (words[(b + 0) >> 5] >> ((b + 0) & 31)) & 1U;
    u32 b1 = (words[(b + 1) >> 5] >> ((b + 1) & 31)) & 1U;
    u32 b2 = (words[(b + 2) >> 5] >> ((b + 2) & 31)) & 1U;
    u32 b3 = (words[(b + 3) >> 5] >> ((b + 3) & 31)) & 1U;
    return (b0 << 3) | (b1 << 2) | (b2 << 1) | b3;
}

/* Compare one captured frame (at buffer offset `off`) vs the payload's expected
 * demod, with the reference CYCLICALLY rotated by `rot` whole symbols. This
 * mirrors the on-chip rx_ber_checker rot_off search: a continuous readback
 * starts at an arbitrary symbol phase, so the reference frame must be rotated
 * by whole symbols (NDATA_SC nibbles) to line up. */
static u32 tx_compare_frame_rot(const u32 *payload_words, int off, int rot)
{
    int c;
    u32 errs = 0;
    int rot_nib = rot * 221;
    for (c = 0; c < (int)TX_NNIBBLES; ++c) {
        int rc = c + rot_nib;
        if (rc >= (int)TX_NNIBBLES) rc -= (int)TX_NNIBBLES;   /* cyclic mod 2652 */
        u32 got = (u32)capture_buf[off + c] & 0xFU;
        u32 exp = tx_expected_nibble(payload_words, rc);
        u32 x = got ^ exp;
        x = (x & 0x5U) + ((x >> 1) & 0x5U);
        x = (x & 0x3U) + ((x >> 2) & 0x3U);
        errs += x;
    }
    return errs;
}

/* Search buffer start-offset (whole-symbol steps) AND whole-symbol reference
 * rotation for the min-BER alignment of a continuous readback. Returns the
 * min bit errors of the best-aligned single frame. */
static u32 tx_best_align(const u32 *payload_words, int rd_len,
                         int *best_off_out, int *best_rot_out)
{
    int off, rot, best_off = 0, best_rot = 0;
    u32 best = TX_NBITS + 1;
    for (off = 0; off + (int)TX_NNIBBLES <= rd_len && off < (int)TX_NNIBBLES; off += 221) {
        for (rot = 0; rot < 12; ++rot) {
            u32 e = tx_compare_frame_rot(payload_words, off, rot);
            if (e < best) { best = e; best_off = off; best_rot = rot; }
        }
    }
    if (best_off_out) *best_off_out = best_off;
    if (best_rot_out) *best_rot_out = best_rot;
    return best;
}

/* One DMA-TX frame: stage `words` in DDR, DMA it, arm LOOPBACK+use_dma, kick TX,
 * capture one frame of demod nibbles, align, and return bit errors. */
static u32 run_dma_tx_frame_x(const u32 *words, const char *tag, u32 *out_len,
                              int use_dma_bit, int send_dma)
{
    u32 cap_base = LOOP_CAP_EN;
    int i, rd_len, best_off = 0, best_rot = 0;
    u32 errs, done;
    u32 dmabit = use_dma_bit ? XCVR_USE_DMA_BIT : 0U;

    /* stage payload in DDR (write-back cache -> flush so the DMA sees it) */
    for (i = 0; i < (int)TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = words[i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);

    /* LOOPBACK (+/- use_dma) + lb_cont: framing FSM re-emits the captured slot
     * back-to-back so a FINITE capture records several contiguous demod frames
     * (needed for the whole-symbol alignment search). The DMA bank is DOUBLE-
     * BUFFERED and stays active until the next DMA load. */
    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB) | dmabit | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word); usleep(100);
    xcvr_sync_config();

    /* DMA the payload into the bridge bank BEFORE kicking TX (fully staged). */
    if (send_dma) { (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(200); }
    else          { xil_printf("ZCU216_TXDMA: (no DMA send; bank=reset-ROM)\r\n"); }

    /* arm finite capture (fills DEPTH=16384 nibbles ~6 frames), then kick TX */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);       usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base); usleep(2000);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                  usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT); usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);

    done = xcvr_wait_capture();           /* fill the multi-frame DEPTH */
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);

    /* read back several frames so the alignment search has full phase slack */
    rd_len = xcvr_readback(cap_base, (int)(TX_NNIBBLES * 2U));
    if (out_len) *out_len = (u32)rd_len;

    errs = tx_best_align(words, rd_len, &best_off, &best_rot);
    xil_printf("ZCU216_TXDMA: %s cap_done=%lu cap_count=%lu align_off=%d rot=%d "
               "bit_errors=%lu/%u dut_errf=0x%08lx\r\n",
               tag, (unsigned long)done,
               (unsigned long)(Xil_In32(LOOP_STATUS_GPIO) & 0xFFFFU),
               best_off, best_rot, (unsigned long)errs, TX_NBITS,
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));

    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);
    return errs;
}

static u32 run_dma_tx_frame(const u32 *words, const char *tag, u32 *out_len)
{
    return run_dma_tx_frame_x(words, tag, out_len, 1 /*use_dma*/, 1 /*send*/);
}

/* Simple LFSR PRBS filler for arbitrary payloads (deterministic per seed). */
static void tx_fill_prbs(u32 *words, u32 seed)
{
    u32 lfsr = seed ? seed : 0xACE1u;
    int i;
    for (i = 0; i < (int)TX_PAYLOAD_WORDS; ++i) {
        /* build a 32-bit word from 32 galois-LFSR steps (x^32+x^22+x^2+x^1+1) */
        u32 w = 0;
        int b;
        for (b = 0; b < 32; ++b) {
            u32 bit = lfsr & 1U;
            lfsr >>= 1;
            if (bit) lfsr ^= 0x80200003U;
            w |= (bit << b);
        }
        words[i] = w;
    }
    /* last word only 16 valid bits (10608=331*32+16); mask upper 16 so the
     * expected-demod compare and the RTL agree on the ignored bits. */
    words[TX_PAYLOAD_WORDS - 1] &= 0x0000FFFFU;
}

/* -----------------------------------------------------------------------
 * DMA LANE-INVERT DIAGNOSTIC (offline analysis pinned the DMA-TX corruption
 * to exactly ONE inverted bit-lane per 16-QAM nibble = 25.0% errors; NOT a
 * byte-swap/reorder, all of which give ~50%). The GOLDEN payload syncs & aligns
 * fine (SANITY found off=0), so DMA it, align (tx_best_align), then tally the
 * per-lane error count over all carriers at the best alignment: if exactly ONE
 * of bit0..bit3 is ~2652 (all carriers) and the others ~0, that names the
 * inverted lane precisely. Runs EARLY (before MODE-2) so it prints even if a
 * later stage stalls. Uses whole-symbol align to survive the continuous phase. */
/* Clean-context DMA-TX BER proof. Stages `words` in DDR, arms a single LOOPBACK
 * capture, aligns (whole-symbol search) and reports bit errors. use_dma=0 emits
 * the on-chip golden ROM (so `words` must be golden); use_dma=1 emits the DMA
 * bank (arbitrary payload). Runs FIRST (fresh datapath) so it is not disturbed by
 * the later multi-frame continuous tests that hit STALL_TIMEOUT (bug2). */
static u32 dma_ber_probe(int use_dma, const u32 *words, const char *label)
{
    int i, rd_len, best_off = 0, best_rot = 0, c, rot_nib, nwrong = 0;
    u32 total;

    for (i = 0; i < (int)TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = words[i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);

    int attempt;
    /* DRAIN: stop any prior lb_cont continuous re-emit and let the framing FSM
     * go IDLE before the sync_config soft-reset. Without this, a reset fires
     * while output is active (RESET_WHILE_ACTIVE) and truncates a frame
     * (FRAME_LEN_MISMATCH) -> the 2nd+ probe (ROM or DMA) desyncs to ~50%. The
     * 1st probe was clean only because nothing was running yet. */
    Xil_Out32(BER_CTRL_GPIO, 0U);      usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, 0U);     usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET); usleep(10000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);                  usleep(10000);

    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB)
                     | (use_dma ? XCVR_USE_DMA_BIT : 0U) | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word); usleep(100);
    xcvr_sync_config();
    if (use_dma) {
        /* PURE datapath: DMA only, NO debug reads before the capture (they poke
         * ber_ctrl 300+ times mid-lb_cont; isolate whether that disturbs sync). */
        (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(200);
    }

    /* RETRY the capture: the DMA-fed continuous loopback intermittently fails to
     * lock sync (bug2 -> ~50% random) while it is BIT-PERFECT when it does lock
     * (bug1 already fixed). Re-arm + re-kick until the aligned BER hits 0, up to
     * a few attempts, to see whether the datapath is reliably-with-retry correct. */
    total = TX_NBITS + 1; best_off = 0;
    for (attempt = 0; attempt < 8; ++attempt) {
        int off; u32 best = TX_NBITS + 1; int boff = 0;
        Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFU);  /* W1C: clear per-attempt */
        Xil_Out32(LOOP_CTRL_GPIO, 0U);           usleep(2000);
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN);  usleep(2000);
        Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                  usleep(50);
        Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT); usleep(50);
        Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);
        (void)xcvr_wait_capture();
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN);
        rd_len = xcvr_readback(LOOP_CAP_EN, (int)(TX_NNIBBLES * 2U));
        /* FINE offset search (step 1): any frame phase, not just symbol-aligned */
        for (off = 0; off + (int)TX_NNIBBLES <= rd_len; ++off) {
            u32 e = tx_compare_frame_rot(words, off, 0);
            if (e < best) { best = e; boff = off; if (e == 0) break; }
        }
        total = best; best_off = boff;
        if (total == 0) break;
    }
    best_rot = 0; rot_nib = 0;
    for (c = 0; c < (int)TX_NNIBBLES; ++c) {
        int rc = c + rot_nib; if (rc >= (int)TX_NNIBBLES) rc -= (int)TX_NNIBBLES;
        if (((u32)capture_buf[best_off + c] & 0xFU) != tx_expected_nibble(words, rc)) nwrong++;
    }
    /* stash the ALIGNED demod frame (2652 nibbles, carrier 0 first) for the host
     * JTAG dump -- lets the video reconstructor rebuild the recovered image. */
    for (c = 0; c < (int)TX_NNIBBLES; ++c)
        xcvr_lb_buf[c] = capture_buf[best_off + c] & 0xF;
    Xil_DCacheFlushRange((INTPTR)xcvr_lb_buf, TX_NNIBBLES * sizeof(s32));
    xil_printf("ZCU216_LANEERR: [%s] attempts=%d off=%d bit_errors=%lu/%u wrong_carriers=%d/%u %s\r\n",
               label, attempt + 1, best_off, (unsigned long)total, TX_NBITS,
               nwrong, TX_NNIBBLES, total ? "FAIL" : "BER=0");
    /* B: RX/sync state after the last capture -- did the loopback LOCK sync?
     * fsv=frame_start_valid(sticky), fsi=frame_start_index, peak=corr peak,
     * slot=slot_start. ROM locks (fsv=1,peak>>0); if DMA shows no/weak lock the
     * failure is the sync front-end, not the demod. */
    xil_printf("ZCU216_SYNC: [%s] fsv=%lu fsi=%lu peak=%lu slot=%lu tlast=%lu status=0x%08lx errf=0x%08lx\r\n",
               label,
               (unsigned long)Xil_In32(DUT_LITE + 0x18U),
               (unsigned long)Xil_In32(DUT_LITE + 0x1CU),
               (unsigned long)Xil_In32(DUT_LITE + 0x20U),
               (unsigned long)Xil_In32(DUT_LITE + 0x24U),
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS),
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));

    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);
    return total;
}

/* On-chip THROUGHPUT measurement. Run the continuous loopback (lb_cont) with a
 * circular capture sink so it streams frames forever, then measure the DUT
 * TLAST_COUNT (output frames) and CYC_TOTAL_CNT (PL cycles) increments over a
 * fixed wall-clock window. frames/s -> payload goodput; PL cycles / frame ->
 * effective sample rate (samples/frame = 4160). Payload = 10608 data bits/frame
 * (12 sym x 221 SC x 4 bit, 16-QAM). */
static void run_xcvr_throughput(void)
{
    const u32 WIN_US = 100000U;                 /* 100 ms measurement window */
    u32 f0, f1, y0, y1, df, dy;
    u32 fps, good_mbps, fs_mhz;

    xil_printf("ZCU216_TPUT: ===== on-chip throughput (continuous loopback) =====\r\n");
    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB) | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word); usleep(100);
    xcvr_sync_config();
    Xil_Out32(LOOP_CTRL_GPIO, 0U);                          usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC); usleep(2000); /* forever sink */
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                  usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT); usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);
    usleep(30000);                              /* let the stream ramp to steady state */

    f0 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
    y0 = Xil_In32(DUT_LITE + DUT_CYC_TOTAL);
    usleep(WIN_US);
    f1 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
    y1 = Xil_In32(DUT_LITE + DUT_CYC_TOTAL);
    df = f1 - f0;
    dy = y1 - y0;

    fps       = (u32)((u64)df * 1000000ULL / WIN_US);              /* frames / s   */
    good_mbps = (u32)((u64)df * 10608ULL / WIN_US);               /* Mbit/s (payload) */
    fs_mhz    = (u32)((u64)dy / WIN_US);                          /* PL Msamp/s   */

    xil_printf("ZCU216_TPUT: window=%lums frames=%lu cycles=%lu\r\n",
               (unsigned long)(WIN_US / 1000U), (unsigned long)df, (unsigned long)dy);
    xil_printf("ZCU216_TPUT: %lu frames/s | payload goodput=%lu Mbps (10608 bit/frame) | "
               "effective Fs=%lu Msps (%lu cyc/frame)\r\n",
               (unsigned long)fps, (unsigned long)good_mbps, (unsigned long)fs_mhz,
               (unsigned long)(df ? dy / df : 0));

    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
}

/* Capture the emitted TX slot (4032 IQ words) for a given payload/source into
 * dest[]. TX mode -> the modulator output goes straight to dut_capture (no RX,
 * no loopback sync). Lets us compare the DMA-sourced modulated waveform against
 * the ROM-sourced one: identical => TX modulation is fine (corruption is RX/
 * sync/capture); different => the DMA bank read into tx_ofdm_top is corrupt. */
static int capture_tx_slot(int use_dma, const u32 *words, s32 *dest)
{
    int i, rd_len;
    u32 mw = XCVR_MODE_WORD(XCVR_MODE_TX) | (use_dma ? XCVR_USE_DMA_BIT : 0U);
    for (i = 0; i < (int)TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = words[i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);
    Xil_Out32(BER_CTRL_GPIO, mw); usleep(100);
    xcvr_sync_config();
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET); usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U); usleep(2000);
    if (use_dma) { (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(200); }
    Xil_Out32(LOOP_CTRL_GPIO, 0U);          usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN); usleep(2000);
    Xil_Out32(BER_CTRL_GPIO, mw);                  usleep(50);
    Xil_Out32(BER_CTRL_GPIO, mw | XCVR_START_BIT); usleep(50);
    Xil_Out32(BER_CTRL_GPIO, mw);
    (void)xcvr_wait_count(4032U);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN);
    rd_len = xcvr_readback(LOOP_CAP_EN, 4032);
    for (i = 0; i < rd_len; ++i) dest[i] = capture_buf[i];
    Xil_Out32(BER_CTRL_GPIO, 0U);
    return rd_len;
}

static s32 g_tx_slot_rom[4096];
static void tx_slot_compare(void)
{
    int i, n_rom, n_dma, ndiff = 0, firstdiff = -1;
    xil_printf("ZCU216_TXSLOT: ===== TX modulated-slot compare ROM vs DMA (golden) =====\r\n");
    n_rom = capture_tx_slot(0, tx_data_bits_words, g_tx_slot_rom);
    n_dma = capture_tx_slot(1, tx_data_bits_words, capture_buf);
    for (i = 0; i < n_rom && i < n_dma; ++i)
        if (g_tx_slot_rom[i] != capture_buf[i]) { if (firstdiff < 0) firstdiff = i; ndiff++; }
    xil_printf("ZCU216_TXSLOT: n_rom=%d n_dma=%d diff=%d/%d firstdiff=%d %s\r\n",
               n_rom, n_dma, ndiff, (n_rom < n_dma ? n_rom : n_dma), firstdiff,
               ndiff ? "TX-MODULATION DIFFERS (dma_flat4 read corrupt)"
                     : "TX-MODULATION IDENTICAL (corruption is RX/sync/capture)");
    if (ndiff && firstdiff >= 0)
        xil_printf("ZCU216_TXSLOT: @%d rom=0x%08lx dma=0x%08lx | @0 rom=0x%08lx dma=0x%08lx\r\n",
                   firstdiff, (unsigned long)(u32)g_tx_slot_rom[firstdiff],
                   (unsigned long)(u32)capture_buf[firstdiff],
                   (unsigned long)(u32)g_tx_slot_rom[0], (unsigned long)(u32)capture_buf[0]);
}

static int run_xcvr_dma_tx(void)
{
    u32 e, len, seed;
    int f, npass = 0, ntot = 0;
    static u32 prbs_words[TX_PAYLOAD_WORDS];

    xil_printf("ZCU216_TXDMA: ===== ARBITRARY-PAYLOAD TX-FROM-DDR (MM2S DMA) =====\r\n");
    xil_printf("ZCU216_TXDMA: dma_base=0x%08lx payload_ddr=0x%08lx words=%u bytes=%u\r\n",
               (unsigned long)TXDMA_BASE, (unsigned long)TX_PAYLOAD_DDR,
               TX_PAYLOAD_WORDS, TX_PAYLOAD_BYTES);

    xcvr_load_player();  /* harmless; RX path unused here */

    /* -------- (D1) use_dma=0: pure ROM through the new mux (must be BER=0) --- */
    xil_printf("ZCU216_TXDMA: ----- (D1) use_dma=0 ROM-through-mux -----\r\n");
    e = run_dma_tx_frame_x(tx_data_bits_words, "D1-rom-mux", &len, 0 /*use_dma*/, 0 /*send*/);
    xil_printf("ZCU216_TXDMA: D1 %s (bit_errors=%lu)\r\n", e ? "FAIL" : "PASS", (unsigned long)e);

    /* -------- (D2) use_dma=1, NO DMA send: bank=reset-ROM (must be BER=0) ---- */
    xil_printf("ZCU216_TXDMA: ----- (D2) use_dma=1 bank=reset-ROM (no DMA) -----\r\n");
    e = run_dma_tx_frame_x(tx_data_bits_words, "D2-bank-rom", &len, 1 /*use_dma*/, 0 /*send*/);
    xil_printf("ZCU216_TXDMA: D2 %s (bit_errors=%lu)\r\n", e ? "FAIL" : "PASS", (unsigned long)e);

    /* -------- (a) SANITY: golden pattern via DMA must reproduce BER=0 -------- */
    xil_printf("ZCU216_TXDMA: ----- (a) SANITY golden-pattern via DMA -----\r\n");
    e = run_dma_tx_frame(tx_data_bits_words, "SANITY-golden", &len);
    ntot++;
    if (e == 0) { npass++; xil_printf("ZCU216_TXDMA: SANITY PASS (golden DDR payload -> BER=0)\r\n"); }
    else        xil_printf("ZCU216_TXDMA: SANITY FAIL (golden DDR payload -> %lu bit errors)\r\n",
                           (unsigned long)e);

    /* -------- (b) ARBITRARY: >=3 fresh PRBS payloads, round-trip BER -------- */
    xil_printf("ZCU216_TXDMA: ----- (b) ARBITRARY PRBS payloads via DMA -----\r\n");
    for (f = 0; f < 3; ++f) {
        seed = 0x1234u + (u32)f * 0x1111u;
        tx_fill_prbs(prbs_words, seed);
        e = run_dma_tx_frame(prbs_words, "ARB-prbs", &len);
        ntot++;
        if (e == 0) { npass++;
            xil_printf("ZCU216_TXDMA: ARB frame=%d seed=0x%04lx PASS (BER=0)\r\n",
                       f, (unsigned long)seed);
        } else {
            xil_printf("ZCU216_TXDMA: ARB frame=%d seed=0x%04lx FAIL (%lu bit errors)\r\n",
                       f, (unsigned long)seed, (unsigned long)e);
        }
    }

    xil_printf("ZCU216_TXDMA: ======== TX-FROM-DDR VERDICT: %d/%d frames BER=0 ========\r\n",
               npass, ntot);
    return (npass == ntot) ? XST_SUCCESS : XST_FAILURE;
}

/* SINGLE-FRAME loopback probe (NO lb_cont): emit a handful of discrete framed
 * slots (each completes before the next) to fill the capture, then align + BER.
 * Hypothesis: without the continuous re-emit there is no cross-probe desync, so
 * many DIFFERENT payloads can be sent back-to-back (multi-frame video). Stashes
 * the aligned demod into xcvr_lb_buf for the host reconstructor. */
static u32 run_frame_sf(int use_dma, const u32 *words, const char *label, s32 *dest,
                        int fresh)
{
    /* s2mm_fifo now drops tlast (HAS_TLAST=0), so ONE S2MM arm captures NF frames
     * CONTIGUOUSLY (LENGTH-based completion). Only the very first captured frame
     * loses its head beat (the DMA-arm 1-beat drop); the interior frames are whole,
     * so the offset-search below finds a clean 2652-nibble window (BER=0). */
    const int NF = 3;                        /* 1 head-dropped frame + clean interior */
    const int ndm = NF * (int)TX_NNIBBLES;   /* nibbles captured to DDR (7956) */
    u32 fbytes = (u32)ndm * 4U;
    volatile u32 *ddr = (volatile u32 *)(UINTPTR)RX_DDR;
    const int NWARM = 0;                      /* single arm; NF frames in one transfer */
    int i, best_off = 0, c, poll, nwrong = 0, g;
    u32 total, mw, best, sr;

    for (i = 0; i < (int)TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = words[i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);
    for (i = 0; i < ndm; ++i) ddr[i] = 0xDEADBEEFU;
    Xil_DCacheFlushRange((INTPTR)RX_DDR, fbytes);

    /* CONTINUOUS-SESSION streaming (needs the s2mm_fifo BD decouple):
     * bring the transceiver up ONCE (fresh) and leave it locked & continuously
     * emitting. Per-frame reset re-acquires sync and corrupts the FIFO framing, so
     * subsequent frames keep the SAME locked session -- we only re-DMA the new
     * payload and pulse START to reload the slot. The FIFO keeps the S2MM-leg
     * tready HIGH across the re-arm gaps so the demod never stalls/desyncs, and the
     * warm-up grabs below drain the stale/old-payload frames still buffered. */
    mw = XCVR_MODE_WORD(XCVR_MODE_LB) | (use_dma ? XCVR_USE_DMA_BIT : 0U)
       | XCVR_LB_CONT_BIT;                  /* continuous re-emit of the DMA'd slot  */
    if (fresh) {
        /* NOTE: usleep() on this baremetal runs ~175x SLOWER than nominal (a
         * miscalibrated timer) -- these small values are already several ms of REAL
         * settle each. This is the main fps lever (per-frame reset path). */
        Xil_Out32(BER_CTRL_GPIO, XCVR_SRST_BIT); usleep(20);
        Xil_Out32(BER_CTRL_GPIO, 0U);            usleep(20);
        Xil_Out32(BER_CTRL_GPIO, mw); usleep(15);
        xcvr_sync_config();
        Xil_Out32(LOOP_CTRL_GPIO, 0U);                          usleep(20);
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC); usleep(20);
        /* S2MM soft-reset + RS ONCE (while the demod is still idle -- a DMACR reset
         * with data already in flight drops the in-flight beat -> the captured frame
         * starts 4 nibbles / 1 beat late. Re-arm per grab uses LENGTH only.) */
        Xil_Out32(RXDMA_S2MM_DMACR, 0x4U);
        for (i = 0; i < 100000 && (Xil_In32(RXDMA_S2MM_DMACR) & 0x4U); ++i) {}
        Xil_Out32(RXDMA_S2MM_DMACR, 0x1U);        /* RS=1 (stays set) */
    }
    if (use_dma) { (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(20); }

    /* One S2MM arm captures NF frames contiguously (HAS_TLAST=0). */
    for (g = 0; g <= NWARM; ++g) {
        Xil_Out32(RXDMA_S2MM_DA, RX_DDR);        /* re-arm with LENGTH only (no reset) */
        Xil_Out32(RXDMA_S2MM_DA_MSB, 0U);
        Xil_Out32(RXDMA_S2MM_LENGTH, fbytes);    /* writing LENGTH starts S2MM */

        if (g == 0) {              /* kick START: bring-up + reload the payload slot */
            Xil_Out32(BER_CTRL_GPIO, mw);                  usleep(10);
            Xil_Out32(BER_CTRL_GPIO, mw | XCVR_START_BIT); usleep(10);
            Xil_Out32(BER_CTRL_GPIO, mw);
        }
        /* HAS_TLAST=0 -> the S2MM never asserts Idle (it completes on LENGTH, not
         * tlast), so DON'T poll DMASR.Idle (that spun the full timeout ~1.5 s/frame).
         * Instead poll the LAST DDR word's sentinel: capture is done the instant the
         * final 128-bit beat lands. Invalidate just that cache line each spin. */
        /* Break as soon as the capture reaches the last word; but per-frame fresh
         * captures sometimes stop a little short of NF frames (the clean interior
         * frame is already in DDR long before), so cap the wait low instead of
         * spinning the old 4000x timeout (~1.48 s/frame). ~33ms is ample. */
        for (poll = 0; poll < 300; ++poll) {
            Xil_DCacheInvalidateRange((INTPTR)&ddr[ndm - 4], 32);
            if (ddr[ndm - 1] != 0xDEADBEEFU) break;
            usleep(50);
        }
        (void)sr;
    }
    Xil_DCacheInvalidateRange((INTPTR)RX_DDR, fbytes);
    for (i = 0; i < ndm && i < CAPTURE_DEPTH; ++i)
        capture_buf[i] = (s32)(ddr[i] & 0xFU);

    /* Align: offset-search the NF captured frames for a clean 2652-nibble window.
     * Precompute the expected nibbles ONCE (was recomputed per offset), and give
     * the inner compare an EARLY-EXIT (stop the moment errs can't beat best) -- a
     * badly-aligned offset bails after a few nibbles instead of grinding all 2652.
     * The old no-early-exit full search was ~1.48 s/frame when the clean frame sat
     * at a late offset. */
    for (c = 0; c < (int)TX_NNIBBLES; ++c)
        g_expnib[c] = (u8)tx_expected_nibble(words, c);
    best = TX_NBITS + 1; best_off = 0;
    /* Fast path: the capture alignment (clean-frame offset) is stable frame-to-
     * frame, so try the last winning offset first -- a single 2652-nibble compare.
     * If it's clean, skip the O(offsets) scan entirely. */
    if (g_align_off >= 0 && g_align_off + (int)TX_NNIBBLES <= ndm) {
        u32 e = 0;
        for (c = 0; c < (int)TX_NNIBBLES; ++c) {
            u32 x = ((u32)capture_buf[g_align_off + c] & 0xFU) ^ (u32)g_expnib[c];
            x = (x & 0x5U) + ((x >> 1) & 0x5U);
            x = (x & 0x3U) + ((x >> 2) & 0x3U);
            e += x;
            if (e) break;
        }
        if (e == 0) { best = 0; best_off = g_align_off; }
    }
    if (best != 0) {                         /* full early-exit offset search */
        for (i = 0; i + (int)TX_NNIBBLES <= ndm; ++i) {
            u32 e = 0;
            for (c = 0; c < (int)TX_NNIBBLES; ++c) {
                u32 x = ((u32)capture_buf[i + c] & 0xFU) ^ (u32)g_expnib[c];
                x = (x & 0x5U) + ((x >> 1) & 0x5U);
                x = (x & 0x3U) + ((x >> 2) & 0x3U);
                e += x;
                if (e >= best) break;        /* can't beat best -> abandon offset */
            }
            if (e < best) { best = e; best_off = i; if (e == 0) break; }
        }
        if (best == 0) g_align_off = best_off;   /* remember for next frame */
    }
    total = best;
    for (c = 0; c < (int)TX_NNIBBLES; ++c)
        if (((u32)capture_buf[best_off + c] & 0xFU) != tx_expected_nibble(words, c)) nwrong++;
    if (dest) {
        for (c = 0; c < (int)TX_NNIBBLES; ++c) dest[c] = capture_buf[best_off + c] & 0xF;
        Xil_DCacheFlushRange((INTPTR)dest, TX_NNIBBLES * sizeof(s32));
    }

    if (!g_sync_quiet || total)                    /* quiet mode: only print failures */
        xil_printf("ZCU216_SF: [%s] off=%d bit_errors=%lu/%u wrong=%d/%u %s errf=0x%08lx\r\n",
                   label, best_off, (unsigned long)total, TX_NBITS, nwrong, TX_NNIBBLES,
                   total ? "FAIL" : "BER=0",
                   (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
    /* no teardown -- continuous session stays locked; caller tears down once */
    return total;
}

/* MILESTONE M1: capture the live demod stream to DDR via the S2MM DMA (instead
 * of the per-frame dut_capture BRAM + JTAG readback). Runs the continuous
 * live-TX loopback (one repeating image frame) with dut_capture in CIRCULAR
 * mode (so the broadcaster's other leg never back-pressures), arms the S2MM DMA
 * to write NF frames of 32-bit demod nibbles to DDR, and verifies the captured
 * nibbles demod to the sent frame. Proves the S2MM sink works for our stream. */
static void run_s2mm_test(void)
{
    const int NF = 4;
    u32 nbytes = (u32)NF * TX_NNIBBLES * 4U;    /* 4 frames x 2652 nibbles x 4B */
    u32 i, sr, len; int poll, off, boff = 0, c; u32 best;
    volatile u32 *ddr = (volatile u32 *)(UINTPTR)RX_DDR;

    xil_printf("ZCU216_S2MM: ===== RX demod -> S2MM DMA -> DDR (M1) =====\r\n");
    for (i = 0; i < TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = tx_image_words[0][i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);
    for (i = 0; i < nbytes / 4U; ++i) ddr[i] = 0xDEADBEEFU;
    Xil_DCacheFlushRange((INTPTR)RX_DDR, nbytes);

    Xil_Out32(BER_CTRL_GPIO, XCVR_SRST_BIT); usleep(300);
    Xil_Out32(BER_CTRL_GPIO, 0U);            usleep(300);
    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB) | XCVR_USE_DMA_BIT | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word); usleep(100);
    xcvr_sync_config();
    (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(200);

    /* dut_capture CIRCULAR -> always ready (no broadcaster back-pressure) */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);                          usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC); usleep(2000);

    /* arm S2MM: reset -> RS -> dest -> length (writing LENGTH starts it) */
    Xil_Out32(RXDMA_S2MM_DMACR, 0x4U);
    for (i = 0; i < 100000U && (Xil_In32(RXDMA_S2MM_DMACR) & 0x4U); ++i) {}
    Xil_Out32(RXDMA_S2MM_DMACR, 0x1U);
    Xil_Out32(RXDMA_S2MM_DA, RX_DDR);
    Xil_Out32(RXDMA_S2MM_DA_MSB, 0U);
    Xil_Out32(RXDMA_S2MM_LENGTH, nbytes);

    /* kick the continuous live-TX loopback so the demod flows */
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                  usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT); usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);

    for (poll = 0; poll < 500; ++poll) {        /* wait S2MM Idle (bit1) */
        sr = Xil_In32(RXDMA_S2MM_DMASR);
        if (sr & 0x2U) break;
        usleep(1000);
    }
    sr  = Xil_In32(RXDMA_S2MM_DMASR);
    len = Xil_In32(RXDMA_S2MM_LENGTH);
    Xil_DCacheInvalidateRange((INTPTR)RX_DDR, nbytes);

    /* copy captured nibbles into capture_buf, fine-align vs frame 0, report BER */
    for (i = 0; i < (u32)(NF * (int)TX_NNIBBLES) && i < CAPTURE_DEPTH; ++i)
        capture_buf[i] = (s32)(ddr[i] & 0xFU);
    best = TX_NBITS + 1;
    for (off = 0; off + (int)TX_NNIBBLES <= NF * (int)TX_NNIBBLES; ++off) {
        u32 e = tx_compare_frame_rot(tx_image_words[0], off, 0);
        if (e < best) { best = e; boff = off; if (e == 0) break; }
    }
    {
        u32 nwritten = 0, j;
        for (j = 0; j < nbytes / 4U; ++j) if (ddr[j] != 0xDEADBEEFU) nwritten++;
        xil_printf("ZCU216_S2MM: written_words=%lu/%lu ddr[0..9]=",
                   (unsigned long)nwritten, (unsigned long)(nbytes / 4U));
        for (j = 0; j < 10; ++j) xil_printf("%08lx,", (unsigned long)ddr[j]);
        xil_printf(" ddr[2651,2652]=%08lx,%08lx\r\n",
                   (unsigned long)ddr[2651], (unsigned long)ddr[2652]);
    }
    xil_printf("ZCU216_S2MM: dmasr=0x%08lx idle=%lu bytes=%lu/%lu ddr[0..3]=%08lx,%08lx,%08lx,%08lx\r\n",
               (unsigned long)sr, (unsigned long)((sr >> 1) & 1U),
               (unsigned long)len, (unsigned long)nbytes,
               (unsigned long)ddr[0], (unsigned long)ddr[1],
               (unsigned long)ddr[2], (unsigned long)ddr[3]);
    xil_printf("ZCU216_S2MM: aligned off=%d bit_errors=%lu/%u -> %s (S2MM sink %s)\r\n",
               boff, (unsigned long)best, TX_NBITS, best ? "FAIL" : "BER=0",
               (len && ddr[0] != 0xDEADBEEFU) ? "CAPTURED" : "NO-DATA");
    (void)c;
    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
}

/* MILESTONE M3a: HARDWARE-PACED continuous capture. Bring the loopback up ONCE and
 * let the free-running demod stream NF frames into DDR in a SINGLE S2MM transfer
 * (HAS_TLAST=0 -> LENGTH-based, no per-frame firmware). The S2MM drains the FIFO
 * continuously so the demod never stalls / the RX never loses lock. Measures the
 * true PHY frame rate + BER over the whole burst (same payload every frame). */
static void run_m3_continuous(void)
{
    const int NF = 11;                             /* within the s2mm_fifo(32768) clean
                                                    * window (~12 frames) -> continuous
                                                    * BER=0 burst (no backpressure yet) */
    const u32 ndm = (u32)NF * TX_NNIBBLES;
    u32 fbytes = ndm * 4U;
    volatile u32 *ddr = (volatile u32 *)(UINTPTR)RX_DDR;
    u32 mw, i, poll, us, fps, mbps; XTime c0, c1;
    int f, c, align = -1, nclean = 0, nchk = 0;

    xil_printf("ZCU216_M3: ===== hardware-paced continuous capture (%d frames) =====\r\n", NF);
    for (i = 0; i < TX_PAYLOAD_WORDS; ++i) g_tx_payload[i] = tx_image_words[0][i];
    Xil_DCacheFlushRange((INTPTR)g_tx_payload, TX_PAYLOAD_BYTES);
    ddr[ndm - 1] = 0xDEADBEEFU;                     /* completion sentinel */
    Xil_DCacheFlushRange((INTPTR)&ddr[ndm - 4], 32);

    /* fresh bring-up */
    Xil_Out32(BER_CTRL_GPIO, XCVR_SRST_BIT); usleep(20);
    Xil_Out32(BER_CTRL_GPIO, 0U);            usleep(20);
    mw = XCVR_MODE_WORD(XCVR_MODE_LB) | XCVR_USE_DMA_BIT | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, mw); usleep(15);
    xcvr_sync_config();
    Xil_Out32(LOOP_CTRL_GPIO, 0U);                          usleep(20);
    Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC); usleep(20);
    (void)txdma_send(TX_PAYLOAD_DDR, TX_PAYLOAD_BYTES); usleep(20);

    /* one big S2MM transfer: reset -> RS -> dest -> LENGTH(NF frames) */
    Xil_Out32(RXDMA_S2MM_DMACR, 0x4U);
    for (i = 0; i < 100000 && (Xil_In32(RXDMA_S2MM_DMACR) & 0x4U); ++i) {}
    Xil_Out32(RXDMA_S2MM_DMACR, 0x1U);
    Xil_Out32(RXDMA_S2MM_DA, RX_DDR);
    Xil_Out32(RXDMA_S2MM_DA_MSB, 0U);
    Xil_Out32(RXDMA_S2MM_LENGTH, fbytes);

    /* kick continuous lb, then time the whole burst to completion */
    Xil_Out32(BER_CTRL_GPIO, mw);                  usleep(10);
    Xil_Out32(BER_CTRL_GPIO, mw | XCVR_START_BIT); usleep(10);
    Xil_Out32(BER_CTRL_GPIO, mw);
    XTime_GetTime(&c0);
    for (poll = 0; poll < 4000000U; ++poll) {
        Xil_DCacheInvalidateRange((INTPTR)&ddr[ndm - 4], 32);
        if (ddr[ndm - 1] != 0xDEADBEEFU) break;    /* last word landed -> done */
    }
    XTime_GetTime(&c1);
    Xil_Out32(BER_CTRL_GPIO, 0U);
    Xil_Out32(LOOP_CTRL_GPIO, 0U);

    us   = (u32)((c1 - c0) * 1000000ULL / COUNTS_PER_SECOND);
    fps  = us ? (u32)((u64)NF * 1000000ULL / us) : 0;
    mbps = us ? (u32)((u64)NF * TX_NBITS / us) : 0;      /* NF*10608 bits / us */

    /* BER over the whole burst: find the alignment (first-beat drop) on the first
     * 2 frames, then every frame sits at align + f*TX_NNIBBLES (contiguous capture). */
    Xil_DCacheInvalidateRange((INTPTR)RX_DDR, fbytes);
    for (c = 0; c < (int)TX_NNIBBLES; ++c)
        g_expnib[c] = (u8)tx_expected_nibble(tx_image_words[0], c);
    { u32 best = TX_NBITS + 1;
      for (i = 0; i < 2U * TX_NNIBBLES; ++i) {
          u32 e = 0;
          for (c = 0; c < (int)TX_NNIBBLES; ++c) {
              u32 x = (ddr[i + c] & 0xFU) ^ (u32)g_expnib[c];
              x = (x & 0x5U) + ((x >> 1) & 0x5U); x = (x & 0x3U) + ((x >> 2) & 0x3U);
              e += x; if (e >= best) break;
          }
          if (e < best) { best = e; align = (int)i; if (e == 0) break; }
      }
    }
    /* Walk frame-by-frame, but SEARCH a window around the expected next-frame
     * position so a per-frame alignment DRIFT (non-2652 spacing) doesn't fail an
     * otherwise-clean frame. Tracks the running offset. */
    { int prev = align; int minbe = TX_NBITS, maxbe = 0; long sumbe = 0;
      for (f = 0; f < NF && align >= 0; ++f) {
        int base = (f == 0) ? align : prev + (int)TX_NNIBBLES;
        u32 bbe = TX_NBITS + 1; int boff = base, w;
        for (w = -192; w <= 192; ++w) {
            int off = base + w; u32 e = 0;
            if (off < 0 || (u32)off + TX_NNIBBLES > ndm) continue;
            for (c = 0; c < (int)TX_NNIBBLES; ++c) {
                u32 x = (ddr[off + c] & 0xFU) ^ (u32)g_expnib[c];
                x = (x & 0x5U) + ((x >> 1) & 0x5U); x = (x & 0x3U) + ((x >> 2) & 0x3U);
                e += x; if (e >= bbe) break;
            }
            if (e < bbe) { bbe = e; boff = off; if (e == 0) break; }
        }
        if ((int)((u32)boff + TX_NNIBBLES) > (int)ndm) break;
        nchk++; if (bbe == 0) nclean++;
        if ((int)bbe < minbe) minbe = bbe; if ((int)bbe > maxbe) maxbe = bbe;
        sumbe += bbe; prev = boff;
        if (f < 12) xil_printf("ZCU216_M3:   frame %d errs=%lu off=%d\r\n",
                               f, (unsigned long)bbe, boff);
      }
      xil_printf("ZCU216_M3: %d frames in %lu us -> %lu fps, %lu Mbps | BER(windowed): "
                 "%d/%d clean, per-frame errs min=%d max=%d avg=%d (align=%d)\r\n",
                 NF, (unsigned long)us, (unsigned long)fps, (unsigned long)mbps,
                 nclean, nchk, minbe, maxbe, nchk ? (int)(sumbe / nchk) : 0, align);
    }
    (void)Xil_In32(DUT_LITE + DUT_INT_CFO_VALID);  /* snapshot CFO result regs */
    xil_printf("ZCU216_M3: errflags=0x%08lx (bit3=STALL_TIMEOUT) CFO est=%ld applied=%ld idx=%lu\r\n",
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS),
               (long)(s32)Xil_In32(DUT_LITE + DUT_INT_CFO_EST),
               (long)(s32)Xil_In32(DUT_LITE + DUT_INT_CFO_APPLIED),
               (unsigned long)Xil_In32(DUT_LITE + DUT_INT_CFO_INDEX));
    xil_printf("ZCU216_M3: in_cnt=%lu out_cnt=%lu tlast=%lu | cyc=%lu tvalid=%lu tready=%lu\r\n",
               (unsigned long)Xil_In32(DUT_LITE + DUT_INPUT_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_OUTPUT_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_CYC_TOTAL),
               (unsigned long)Xil_In32(DUT_LITE + DUT_IN_TVALID),
               (unsigned long)Xil_In32(DUT_LITE + DUT_IN_TREADY));
    g_xcvr_mode_word = 0U;
}

static int run_xcvr_3mode(void)
{
    u32 cap_base = LOOP_CAP_EN;
    u32 done;
    int rd_len;

    xil_printf("ZCU216_XCVR: ===== mode-selectable transceiver 3-mode silicon test =====\r\n");
    xil_printf("ZCU216_XCVR: ber_ctrl[31:30]=mode [29]=start; buf=0x%08lx\r\n",
               (unsigned long)capture_buf);

    /* Pre-load the player BRAM once (used by RX; harmless for TX/LB). */
    xcvr_load_player();

    /* DMA lane-invert diagnostic FIRST (fresh bridge widx=0; prints early so a
     * later-stage stall cannot hide the result). Names the inverted bit-lane. */
    /* ORDER TEST: DMA-golden as the CLEAN FIRST probe. If it is BER=0 while a
     * 2nd/3rd probe (ROM or DMA) FAILs with FRAME_LEN_MISMATCH, the ~50% was a
     * firmware call-ordering / reset-while-active artifact, not a DMA datapath
     * bug -> the arbitrary-payload DMA-TX actually works. */
    /* ===== VIDEO: DMA an IMAGE payload as the clean FIRST probe, then dump the
     * aligned demod (xcvr_lb_buf) so the host reconstructs the recovered image.
     * The image is one 10608-bit frame (39x34 grayscale = 1326 bytes). ===== */
    /* ===== MULTI-FRAME VIDEO: send an image as TX_IMAGE_NFRAMES payload frames,
     * each a clean single-frame DMA loopback (per-frame transceiver soft-reset),
     * storing each recovered frame into xcvr_lb_buf so the host reassembles the
     * full image. ===== */
    /* M1: prove the S2MM demod->DDR sink before the (firmware-paced) streaming */
    run_s2mm_test();

    /* M3a: hardware-paced continuous capture -- measure the true PHY frame rate */
    run_m3_continuous();

    xil_printf("ZCU216_VIDEO: ===== streaming %d frames of %dx%d over OFDM =====\r\n",
               TX_IMAGE_NFRAMES, TX_IMAGE_W, TX_IMAGE_H);
    {
        int f, r, nbad = 0;
        XTime t0, t1; u32 us, mfps;
        g_sync_quiet = 1;                    /* silence per-frame prints (UART = ~9ms/line) */
        XTime_GetTime(&t0);
        for (f = 0; f < TX_IMAGE_NFRAMES; ++f) {
            u32 e = 1;
            for (r = 0; r < 4 && e; ++r)     /* retry a frame that didn't lock */
                e = run_frame_sf(1, tx_image_words[f], "STREAM",
                                 &xcvr_lb_buf[f * (int)TX_NNIBBLES],
                                 1);  /* per-frame FRESH reset: each frame re-locks like
                                       * frame 0 (immune to inter-frame FIFO overflow) */
            if (e) nbad++;
        }
        g_sync_quiet = 0;
        g_xcvr_mode_word = 0U;               /* tear down the locked session once */
        Xil_Out32(BER_CTRL_GPIO, 0U);
        Xil_Out32(LOOP_CTRL_GPIO, 0U);
        XTime_GetTime(&t1);
        us = (u32)(((t1 - t0) * 1000000ULL) / COUNTS_PER_SECOND);
        mfps = us ? (u32)(((u64)TX_IMAGE_NFRAMES * 1000000ULL) / us) : 0;
        xil_printf("ZCU216_VIDEO: %d/%d frames BER=0 -> %s\r\n",
                   TX_IMAGE_NFRAMES - nbad, TX_IMAGE_NFRAMES,
                   nbad ? "SOME CORRUPT" : "ALL PIXEL-PERFECT");
        xil_printf("ZCU216_VIDEO: streamed %d frames in %lu.%03lu ms -> %lu frames/s "
                   "(firmware-paced; PHY ceiling ~38990 fps / 413 Mbps)\r\n",
                   TX_IMAGE_NFRAMES, (unsigned long)(us / 1000U),
                   (unsigned long)(us % 1000U), (unsigned long)mfps);
        xil_printf("ZCU216_XCVR_DUMP: tag=LOOPBACK buf=xcvr_lb_buf len=%d\r\n",
                   TX_IMAGE_NFRAMES * (int)TX_NNIBBLES);
    }
    return XST_SUCCESS;

    /* =================== MODE 2: LOOPBACK (internal TX->RX) =================== */
    xil_printf("ZCU216_XCVR: ----- MODE 2 LOOPBACK -----\r\n");
    xcvr_set_mode(XCVR_MODE_LB);
    xcvr_sync_config();
    /* arm capture (rising edge), then kick the internal TX (start pulse). The
     * adapter buffers the TX slot, frames it 64+4032+64, and feeds the RX. */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);    usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base); usleep(2000);
    xcvr_start_pulse(XCVR_MODE_LB);
    /* LOOPBACK emits ONE frame (2652 demod nibbles) per start kick (the internal
     * TX slot is replayed once), so wait for the frame's worth of nibbles, not
     * a full 16384-deep capture. */
    done = (xcvr_wait_count(MF_NIBBLES_PER_FRAME) >= MF_NIBBLES_PER_FRAME);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);
    xil_printf("ZCU216_XCVR: LOOPBACK got_frame=%lu count=%lu tlast=%lu sync fsv=%lu fsi=%lu peak=%lu slot=%lu errf=0x%08lx\r\n",
               (unsigned long)done,
               (unsigned long)(Xil_In32(LOOP_STATUS_GPIO) & 0xFFFFU),
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + 0x18U),
               (unsigned long)Xil_In32(DUT_LITE + 0x1CU),
               (unsigned long)Xil_In32(DUT_LITE + 0x20U),
               (unsigned long)Xil_In32(DUT_LITE + 0x24U),
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
    rd_len = xcvr_readback(cap_base, (int)MF_NIBBLES_PER_FRAME);
    memcpy(xcvr_lb_buf, capture_buf, (unsigned)rd_len * sizeof(s32));
    Xil_DCacheFlushRange((INTPTR)xcvr_lb_buf, (unsigned)rd_len * sizeof(s32));
    xil_printf("ZCU216_XCVR: LOOPBACK readback %d nibbles first=0x%08lx last=0x%08lx\r\n",
               rd_len, (unsigned long)(u32)capture_buf[0],
               (unsigned long)(u32)capture_buf[rd_len-1]);
    xil_printf("ZCU216_XCVR_DUMP: tag=LOOPBACK buf=xcvr_lb_buf len=%d\r\n", rd_len);

    /* ============ MODE 2a-DMA: ARBITRARY-PAYLOAD TX-FROM-DDR ================= */
    /* The de-risking gate toward video: DDR -> MM2S DMA -> TX -> RX -> BRAM.   */
    (void)run_xcvr_dma_tx();
    /* leave one ARBITRARY frame's demod in xcvr_lb_buf for the host cross-check */
    memcpy(xcvr_lb_buf, capture_buf, TX_NNIBBLES * sizeof(s32));
    Xil_DCacheFlushRange((INTPTR)xcvr_lb_buf, TX_NNIBBLES * sizeof(s32));

    /* ============ MODE 2b: CONTINUOUS LIVE-TX -> RX LOOPBACK BER ============= */
    /* The on-chip passive checker tallies a long continuous live-TX stream. */
    (void)run_xcvr_lb_continuous();

    /* ============ MODE 2c: MULTI-FRAME LOOPBACK host readback =============== */
    /* Re-emit continuously and FINITE-capture several contiguous frames so the
     * host ber_demod_bits.py can cross-check multi-frame BER vs the TX bits. */
    xil_printf("ZCU216_XCVR: ----- MODE 2c LOOPBACK multi-frame host capture -----\r\n");
    g_xcvr_mode_word = XCVR_MODE_WORD(XCVR_MODE_LB) | XCVR_LB_CONT_BIT;
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);   usleep(100);
    xcvr_sync_config();
    Xil_Out32(LOOP_CTRL_GPIO, 0U);      usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base); usleep(2000);   /* finite sink, arm */
    /* kick live TX (preserve mode+lb_cont) */
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);                  usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word | XCVR_START_BIT); usleep(50);
    Xil_Out32(BER_CTRL_GPIO, g_xcvr_mode_word);
    done = xcvr_wait_capture();                          /* fill DEPTH nibbles */
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);
    xil_printf("ZCU216_XCVR: LOOPBACK-cont capture done=%lu count=%lu tlast=%lu errf=0x%08lx\r\n",
               (unsigned long)done,
               (unsigned long)(Xil_In32(LOOP_STATUS_GPIO) & 0xFFFFU),
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
    rd_len = xcvr_readback(cap_base, (int)MF_TOTAL_NIBBLES);
    memcpy(xcvr_lb_buf, capture_buf, (unsigned)rd_len * sizeof(s32));
    Xil_DCacheFlushRange((INTPTR)xcvr_lb_buf, (unsigned)rd_len * sizeof(s32));
    xil_printf("ZCU216_XCVR: LOOPBACK-cont readback %d nibbles first=0x%08lx last=0x%08lx\r\n",
               rd_len, (unsigned long)(u32)capture_buf[0],
               (unsigned long)(u32)capture_buf[rd_len-1]);
    xil_printf("ZCU216_XCVR_DUMP: tag=LOOPBACK_CONT buf=xcvr_lb_buf len=%d\r\n", rd_len);
    g_xcvr_mode_word = 0U;
    Xil_Out32(BER_CTRL_GPIO, 0U);

    /* =================== MODE 1: RX (player feeds ext input) ================== */
    xil_printf("ZCU216_XCVR: ----- MODE 1 RX -----\r\n");
    xcvr_set_mode(XCVR_MODE_RX);
    xcvr_sync_config();
    Xil_Out32(LOOP_CTRL_GPIO, 0U);    usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base); usleep(2000);
    /* drive the player continuous (play_en|loop_en) so frames stream back-to-back;
     * finite capture records the first 16384 nibbles (~6 frames). */
    Xil_Out32(LOOP_CTRL_GPIO, cap_base | LOOP_PLAY_EN | LOOP_LOOP_EN);
    done = xcvr_wait_capture();
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);
    xil_printf("ZCU216_XCVR: RX capture done=%lu tlast=%lu sync fsv=%lu fsi=%lu peak=%lu slot=%lu in=%lu out=%lu errf=0x%08lx\r\n",
               (unsigned long)done,
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + 0x18U),
               (unsigned long)Xil_In32(DUT_LITE + 0x1CU),
               (unsigned long)Xil_In32(DUT_LITE + 0x20U),
               (unsigned long)Xil_In32(DUT_LITE + 0x24U),
               (unsigned long)Xil_In32(DUT_LITE + 0x10U),
               (unsigned long)Xil_In32(DUT_LITE + 0x14U),
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
    rd_len = xcvr_readback(cap_base, (int)MF_TOTAL_NIBBLES);
    memcpy(xcvr_rx_buf, capture_buf, (unsigned)rd_len * sizeof(s32));
    Xil_DCacheFlushRange((INTPTR)xcvr_rx_buf, (unsigned)rd_len * sizeof(s32));
    xil_printf("ZCU216_XCVR: RX readback %d nibbles first=0x%08lx last=0x%08lx\r\n",
               rd_len, (unsigned long)(u32)capture_buf[0],
               (unsigned long)(u32)capture_buf[rd_len-1]);
    xil_printf("ZCU216_XCVR_DUMP: tag=RX buf=xcvr_rx_buf len=%d\r\n", rd_len);

    /* =================== MODE 0: TX (capture emitted slot) =================== */
    xil_printf("ZCU216_XCVR: ----- MODE 0 TX -----\r\n");
    xcvr_set_mode(XCVR_MODE_TX);
    /* TX needs no sync; but a soft-reset clears the capture/beat counters. */
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET); usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U); usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, 0U);    usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base); usleep(2000);  /* arm capture (TX IQ) */
    xcvr_start_pulse(XCVR_MODE_TX);                      /* kick TX slot */
    {
        u32 cnt = xcvr_wait_count(4032U);               /* slot = 4032 IQ words */
        xil_printf("ZCU216_XCVR: TX capture count=%lu (emitted-slot IQ; DEPTH not filled is OK)\r\n",
                   (unsigned long)cnt);
    }
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);
    /* TX slot is 4032 IQ words. */
    rd_len = xcvr_readback(cap_base, 4032);
    memcpy(xcvr_tx_buf, capture_buf, (unsigned)rd_len * sizeof(s32));
    Xil_DCacheFlushRange((INTPTR)xcvr_tx_buf, (unsigned)rd_len * sizeof(s32));
    xil_printf("ZCU216_XCVR: TX slot readback %d words PSS[0]=0x%08lx [1]=0x%08lx [4031]=0x%08lx\r\n",
               rd_len, (unsigned long)(u32)capture_buf[0],
               (unsigned long)(u32)capture_buf[1],
               (unsigned long)(u32)capture_buf[rd_len-1]);
    xil_printf("ZCU216_XCVR_DUMP: tag=TX buf=xcvr_tx_buf len=%d\r\n", rd_len);

    xil_printf("ZCU216_XCVR: PASS 3-mode sequence complete (host computes BER / slot-match)\r\n");
    return XST_SUCCESS;
}

static int run_digital_loopback(void)
{
    /* DESYNC-512 ROOT-CAUSE FIX (ILA-proven, firmware-only):
     * The on-chip cap-internals ILA (frx_ila_capinternals, trigger stall_cnt>=40)
     * caught the wedge ONSET verbatim: at frames_checked=5, dut_capture.count
     * ramped 0x3fff->0x4000 (=16383->16384=DEPTH), wr_full 0->1, active 1->0, and
     * s_axis_tready 1->0 -- the classic FINITE-sink fill at DEPTH=16384 (RTL
     * dut_capture.v:91-99,127-129).  Critically the ILA also probed the circular
     * command path and showed ctrl_sync[16]=ctrl[16]=loop_ctrl_gpio_o[16]=0 for
     * ALL 32768 captured cycles: circular was NEVER asserted during this fill,
     * because cap_base only got LOOP_CAP_CIRC under #ifdef STREAM_TEST (OFF).  So
     * Steps 4/5 armed the sink FINITE; with the player looping forever, the sink
     * filled after 16384/2652=6.18 frames and back-pressured the whole chain
     * (stall_cnt->254), draining the FFT/align slack -> a ~1-symbol recovery slip
     * -> permanent whole-frame demod desync.  The later ILA_DESYNC_TRIG circular
     * long-run then counts that pre-existing desync as errors, REPORTED as a
     * delta-from-anchor "first_err_frame=512" (an artifact of the f0=167 baseline,
     * NOT a real onset at frame 512).  The paradox ("circular commanded yet tready
     * drops") was FALSE: circular was simply never commanded during the fill.
     * FIX: arm the STREAMING sink CIRCULAR so it never fills/wedges.  The BER
     * checker is a passive snoop (needs no stored capture), so circular is ideal.
     * A separate FINITE re-arm right before Step 7 gives a clean readback fill. */
    u32 cap_base = LOOP_CAP_EN | LOOP_CAP_CIRC; /* CIRCULAR: sink never fills -> no wedge */
    u32 cap_finite = LOOP_CAP_EN;               /* finite re-arm for Step-7 readback     */
    u32 status0 = 0, pstatus = 0;
    u32 done = 0;
    u32 tlast0, tlast;
    int poll, i;
    int rd_len = (STIM_LEN < CAPTURE_DEPTH) ? (int)STIM_LEN : CAPTURE_DEPTH;

    xil_printf("ZCU216_DLOOP: start frame_len=%u stim_len=%u buf=0x%08lx\r\n",
               DUT_FRAME_LEN_VAL, STIM_LEN, (unsigned long)capture_buf);

    /* Idle the shared ctrl GPIO before we begin (clean edges). */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    usleep(2000);

    /* --- Step 1: load stim BRAM (rising edge of load_en per word). --------- */
#ifdef USE_GPIO_LOAD
    for (i = 0; i < (int)STIM_LEN; ++i) {
        u32 addr = ((u32)i << LOOP_LOAD_ADDR_SHIFT);
        Xil_Out32(STIM_LOAD_GPIO, stim_frame[i]);   /* present data           */
        Xil_Out32(LOOP_CTRL_GPIO, addr);            /* address, load_en low   */
        Xil_Out32(LOOP_CTRL_GPIO, addr | LOOP_LOAD_EN); /* rising edge -> write */
        Xil_Out32(LOOP_CTRL_GPIO, addr);            /* drop load_en           */
    }
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    xil_printf("ZCU216_DLOOP: stim loaded via GPIO (%u words)\r\n", STIM_LEN);
#else
    xil_printf("ZCU216_DLOOP: stim pre-baked in player BRAM (INIT_FILE); "
               "skipping GPIO load\r\n");
#endif

    /* --- Step 2: DUT bring-up: clear flags, soft-reset, enable. ----------- */
    Xil_Out32(DUT_LITE + DUT_STATUS,
              DUT_STAT_DONE_SEEN | DUT_STAT_ERROR_SEEN);  /* W1C done/error    */
    Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);   /* W1C               */
    Xil_Out32(DUT_LITE + DUT_RESET_STATUS, 0xFFFFFFFFU);  /* W1C               */
    Xil_Out32(DUT_LITE + DUT_FRAME_LEN, DUT_FRAME_LEN_VAL);
    Xil_Out32(DUT_LITE + DUT_INPUT_PERIOD, DUT_INPUT_PERIOD_VAL);
    /* DEBUG_CTRL(0x4C) bit0 = bypass_enable. NORMAL mode (=0): the DUT runs the
     * full OFDM sync (frame detect + CFO est/correct) and streams the aligned
     * slot on m_axis. (Set to 1 for passthrough bring-up.) */
    Xil_Out32(DUT_LITE + 0x4CU, 0x0U);
    xil_printf("ZCU216_DLOOP: NORMAL mode, DEBUG_CTRL=0x%08lx\r\n",
               (unsigned long)Xil_In32(DUT_LITE + 0x4CU));

    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET); /* soft-reset pulse */
    usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);
    usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_ENABLE);     /* enable = 1       */
    xil_printf("ZCU216_DLOOP: DUT enabled control=0x%08lx status=0x%08lx\r\n",
               (unsigned long)Xil_In32(DUT_LITE + DUT_CONTROL),
               (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS));

    tlast0 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);

    /* --- Step 3: arm capture (rising edge of cap_en). --------------------- */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);
    usleep(2000);
    Xil_Out32(LOOP_CTRL_GPIO, cap_base);   /* cap_en high, play_en low        */
    usleep(2000);

    /* --- Step 4: start player ONE-SHOT (play_en + cap_en, NO loop). --------
     * With THRESHOLD=40000 the sync chain now detects + processes a single
     * frame (the earlier IN=4096 deadlock was the 256x-too-high threshold, not
     * one-shot). One-shot gives a clean single-frame run for golden compare;
     * loop mode caused frame-boundary artifacts (err_frame_mismatch + a bogus
     * meyr int-CFO from the FFT window spanning back-to-back frames). */
#ifdef STREAM_TEST
    /* ===== Continuous-streaming test (Phase A): loop the player and snapshot
     * the sample/slot counters over time -> sustained throughput + no-drop.
     * Verifies the sync chain handles back-to-back slots (ISS-06/24). ===== */
    {
        u32 in0,in1,in2, tl0,tl1,tl2, er0,er2;
        /* S_AXIS handshake diag counters snapshotted at t1 and t2 over the
         * same 100ms in1->in2 window; firmware computes the duty breakdown. */
        u32 cyc1,cyc2, tv1,tv2, tr1,tr2;
        u32 d_cyc, d_tv, d_tr, d_in;
        in0 = Xil_In32(DUT_LITE + DUT_INPUT_COUNT);
        tl0 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
        er0 = Xil_In32(DUT_LITE + DUT_ERROR_FLAGS);
        Xil_Out32(LOOP_CTRL_GPIO, cap_base | LOOP_PLAY_EN | LOOP_LOOP_EN);
        usleep(100000);                       /* 100 ms */
        in1 = Xil_In32(DUT_LITE + DUT_INPUT_COUNT);
        tl1 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
        cyc1 = Xil_In32(DUT_LITE + DUT_CYC_TOTAL);
        tv1  = Xil_In32(DUT_LITE + DUT_IN_TVALID);
        tr1  = Xil_In32(DUT_LITE + DUT_IN_TREADY);
        usleep(100000);                       /* +100 ms */
        in2 = Xil_In32(DUT_LITE + DUT_INPUT_COUNT);
        tl2 = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
        cyc2 = Xil_In32(DUT_LITE + DUT_CYC_TOTAL);
        tv2  = Xil_In32(DUT_LITE + DUT_IN_TVALID);
        tr2  = Xil_In32(DUT_LITE + DUT_IN_TREADY);
        er2 = Xil_In32(DUT_LITE + DUT_ERROR_FLAGS);
        Xil_Out32(LOOP_CTRL_GPIO, cap_base);  /* stop player */
        xil_printf("ZCU216_STREAM: t0 in=%lu tlast=%lu err=0x%lx\r\n",
                   (unsigned long)in0,(unsigned long)tl0,(unsigned long)er0);
        xil_printf("ZCU216_STREAM: t1(+100ms) in=%lu tlast=%lu\r\n",
                   (unsigned long)in1,(unsigned long)tl1);
        xil_printf("ZCU216_STREAM: t2(+200ms) in=%lu tlast=%lu err=0x%lx\r\n",
                   (unsigned long)in2,(unsigned long)tl2,(unsigned long)er2);
        xil_printf("ZCU216_STREAM: d_in1=%lu d_tl1=%lu  d_in2=%lu d_tl2=%lu\r\n",
                   (unsigned long)(in1-in0),(unsigned long)(tl1-tl0),
                   (unsigned long)(in2-in1),(unsigned long)(tl2-tl1));
        /* eff Msps = d_in/0.1s/1e6 ; @187.5MHz 1SPC the 100ms cap is 18.75M */
        xil_printf("ZCU216_STREAM: eff_Msps~%lu  duty~%lu%%  err=%s\r\n",
                   (unsigned long)((in2-in1)/100000),
                   (unsigned long)(((in2-in1)/100000)*100/187),
                   (er2==0)?"CLEAN":"SET");
        /* Input-duty gap diagnosis over the t1->t2 window. Integer-percent math.
         *   tvalid% ~46% -> player not presenting beats (player-gap)
         *   tvalid% ~100% but accepted% ~46% -> DUT back-pressure (tready) */
        d_cyc = cyc2 - cyc1;
        d_tv  = tv2  - tv1;
        d_tr  = tr2  - tr1;
        d_in  = in2  - in1;
        xil_printf("ZCU216_DIAG: tvalid%%=%lu tready%%=%lu accepted%%=%lu\r\n",
                   (unsigned long)(d_cyc ? d_tv*100/d_cyc : 0),
                   (unsigned long)(d_cyc ? d_tr*100/d_cyc : 0),
                   (unsigned long)(d_cyc ? d_in*100/d_cyc : 0));
        return XST_SUCCESS;
    }
#endif
    /* === Step 4 (MULTI-FRAME): start the player in LOOP/continuous mode so it
     * streams the frame back-to-back forever (play_en + loop_en). The capture is
     * armed in FINITE mode (cap_base has NO circular bit) so it records the first
     * MF_CAP_DEPTH (16384) consecutive demod nibbles then asserts done. 16384
     * nibbles = ~6.18 frames, so >= MF_NUM_FRAMES (5) frames land contiguously.
     * The player honors s_axis_tready strictly (direct AXIS, no FIFO) -> a real
     * backpressure-honoring source, exactly like the sim. This is the on-silicon
     * proof of the A+B streaming fix (frame-buffer 13-bit + per-frame tlast). */
    Xil_Out32(LOOP_CTRL_GPIO, cap_base | LOOP_PLAY_EN | LOOP_LOOP_EN);

    /* --- Step 5: confirm the CIRCULAR stream is LIVE (DESYNC-512 fix).
     * In circular mode the sink never fills, so status0 bit31 (done) never
     * asserts by design -- waiting on it would be wrong.  Instead confirm the
     * stream is flowing by watching DUT_TLAST_COUNT advance across several frame
     * boundaries (>= MF_NUM_FRAMES worth).  Because circular keeps s_axis_tready
     * high, the chain never back-pressures -> stall_cnt stays 0, no frame-fill
     * wedge, no recovery slip.  `done` is set true once enough frames stream so
     * the downstream Step-7 readback logic still proceeds. */
    {
        u32 tlast_mid = tlast0;
        u32 tlast_target = tlast0 + (u32)MF_NUM_FRAMES + 2U; /* a few full frames */
        for (poll = 0; poll < 400; ++poll) {
            status0 = Xil_In32(LOOP_STATUS_GPIO);
            pstatus = Xil_In32(LOOP_STATUS_GPIO + GPIO2_OFFSET);
            tlast   = Xil_In32(DUT_LITE + DUT_TLAST_COUNT);
            done = (tlast >= tlast_target) ? 1U : 0U; /* circular: liveness, not fill */
            if (poll == 100) tlast_mid = tlast;
            if (done) break;
            if ((poll % 40) == 0) {
                xil_printf("ZCU216_DLOOP: poll=%d cap.status0=0x%08lx count=%lu "
                           "player.status=0x%08lx tlast=%lu dut_status=0x%08lx\r\n",
                           poll, (unsigned long)status0,
                           (unsigned long)(status0 & 0xFFFFU),
                           (unsigned long)pstatus, (unsigned long)tlast,
                           (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS));
            }
            usleep(2000);
        }
        xil_printf("ZCU216_DLOOP: stream tlast0=%lu mid=%lu final=%lu (frames "
                   "crossed = %lu)\r\n",
                   (unsigned long)tlast0, (unsigned long)tlast_mid,
                   (unsigned long)tlast, (unsigned long)(tlast - tlast0));
    }

    /* === Step 5a: rot_off ALIGNMENT SWEEP (robust checker). =================
     * The rewritten rx_ber_checker free-runs its frame position from the first
     * nibble after clr, so the frame phase vs the golden reference is unknown by
     * a whole number of OFDM symbols. rot_off (0..11) rotates the REFERENCE by
     * whole symbols; the ALIGNED rot_off yields ~0 errors, every other ~50%.
     * SINGLE-ANCHOR DELTA SWEEP: clr is async to the continuous demod stream, so
     * re-clearing per rot would re-anchor to a DIFFERENT frame phase each time and
     * give an ambiguous result. Instead we clear ONCE (anchoring the frame phase
     * stably, warm-up absorbed), then for each rot_off measure the bit-error DELTA
     * over a fixed streaming window. rot_off rotates the REFERENCE combinationally
     * (anchor never moves), so EXACTLY ONE rot_off yields a zero-error window;
     * every other ~50%. The player loop (PLAY_EN|LOOP_EN) stays asserted throughout
     * -> a genuine continuous stream. */
#ifdef ILA_DESYNC_TRIG
    /* DESYNC-514 ILA capture: SKIP the sweep.  rot_off=0 is the established aligned
     * rotation (HW k=0 PASS), and the sweep floods total_bit_errors with millions of
     * errors that would trip the ILA onset trigger long before the real ~504-frame
     * desync.  Going straight to the rot_off=0 long-run (which clears the checker)
     * keeps total_bit_errors == 0 from the anchor until the genuine desync onset. */
    xil_printf("ZCU216_BER: [ILA_DESYNC_TRIG] SKIPPING rot_off sweep; rot_off=0 direct\r\n");
    ber_set_rot(0);
#else
    {
        u32 be0, fc0, be1, fc1, sw_flags;
        u32 aligned_rot = 0xFFFFFFFFU;
        u32 zero_count = 0;
        u32 rot;
        xil_printf("ZCU216_BER: ===== rot_off DELTA SWEEP (0..%u, single anchor) =====\r\n",
                   BER_NUM_ROT - 1U);
        /* CLR-TIMING FIX (firmware-only, no rebuild of the PL):
         * The demod's first ~5 OFDM symbols after a (re)start are a PIPELINE-FILL
         * TRANSIENT -- garbage DATA (proven: ~45% wrong at EVERY rot_off, i.e. the
         * noise floor; capture symbols 5..59 are bit-perfect).  The checker anchors
         * its frame phase at the FIRST beat after clr.  If clr lands in that
         * transient (as the OLD order did: clear THEN pump), the anchor + the single
         * skipped warm-up frame cannot keep transient symbols out of the counted
         * window, and a transient symbol is unrecoverable by the whole-symbol
         * rot_off -> the on-chip readout floors at ~50% for every rot.
         * FIX: PUMP the stream PAST the transient FIRST, THEN clr, so the anchor
         * lands on a clean steady-state frame boundary; now exactly one rot_off
         * yields 0 errors. */
        ber_set_rot(0);
        ber_pump_stream(6);   /* drain past the 5-symbol pipeline-fill transient */
        ber_clear();          /* NOW anchor on a clean steady-state frame */
        ber_pump_stream(2);   /* burn the 1 warm-up frame; counting starts clean */
        xil_printf("ZCU216_BER: rot_off | d_frames | d_bit_errors | flags\r\n");
        for (rot = 0; rot < BER_NUM_ROT; ++rot) {
            ber_set_rot(rot);
            usleep(200);                      /* let the new rot propagate */
            be0 = ber_read(BER_SEL_ERRORS);
            fc0 = ber_read(BER_SEL_FRAMES);
            ber_pump_stream(4);               /* ~4 re-arms -> >=20 frames flow */
            be1 = ber_read(BER_SEL_ERRORS);
            fc1 = ber_read(BER_SEL_FRAMES);
            sw_flags = ber_read(BER_SEL_FLAGS);
            xil_printf("ZCU216_BER:   %2lu   | %8lu | %12lu | 0x%08lx\r\n",
                       (unsigned long)rot, (unsigned long)(fc1 - fc0),
                       (unsigned long)(be1 - be0), (unsigned long)sw_flags);
            if ((fc1 - fc0) >= 1U && (be1 - be0) == 0U) {
                aligned_rot = rot;
                zero_count++;
            }
        }
        xil_printf("ZCU216_BER: SWEEP aligned_rot=%ld zero-error rotations=%lu (expect 1)\r\n",
                   (aligned_rot == 0xFFFFFFFFU) ? -1L : (long)aligned_rot,
                   (unsigned long)zero_count);
        if (aligned_rot == 0xFFFFFFFFU) {
            xil_printf("ZCU216_BER: SWEEP FAIL: no rot_off aligned -> using rot_off=0\r\n");
            ber_set_rot(0);
        } else {
            ber_set_rot(aligned_rot);
        }
    }
#endif /* !ILA_DESYNC_TRIG */

    /* === Step 5b: LONG-RUN continuous-streaming BER at the ALIGNED rot_off.
     * The player loop started in Step 4 is STILL running. We clear the checker
     * once at the aligned rotation, then keep the SAME continuous stream and
     * RE-ARM the FINITE capture repeatedly (each cap_en rising edge drains
     * another 16384 nibbles with the backpressure pattern the demod likes); the
     * player never stops, so the checker keeps counting from its aligned anchor.
     * NO soft-reset, NO player restart -> alignment is preserved. */
    {
        u32 f0, e0;                                        /* baseline snapshot   */
        u32 br_frames = 0, br_errs = 0, br_nibs = 0, br_flags = 0, br_warm = 0;
        u32 d_frames = 0, d_errs = 0;
        u32 first_err_at = 0xFFFFFFFFU;
        int it;
#ifdef ILA_DESYNC_TRIG
        /* DESYNC-514 ILA capture mode: stream FAR past the ~514-frame onset and
         * make total_bit_errors read EXACTLY 0 through the good frames so the ILA
         * can trigger on the FIRST error (total_bit_errors!=0).  ber_clear() zeroes
         * total_bit_errors / frames_checked WITHOUT moving the frame anchor
         * (rx_ber_checker.v keeps nib_in_sym/sym_in_frame/started across clr), so
         * the aligned rot_off stays valid and BER stays 0 until the real desync. */
        const int MAX_IT = 60000;                          /* ~120 ms cap */
        const u32 ILA_TARGET_FRAMES = 3000U;               /* stream well past 514 */
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN);
        usleep(4000);                                       /* settle steady state  */
        ber_clear();                                        /* total_bit_errors := 0 (anchor preserved) */
        usleep(2000);
        xil_printf("ZCU216_BER: [ILA_DESYNC_TRIG] cleared checker at long-run start; streaming to %lu frames\r\n",
                   (unsigned long)ILA_TARGET_FRAMES);
#else
        const int MAX_IT = (int)(BER_STREAM_US / 2000U);   /* ~2 ms / iter */
        /* NO re-clear: a fresh clr would re-anchor to a different async phase and
         * invalidate the rot_off we just found. Keep the stable sweep anchor and
         * measure the bit-error DELTA from this baseline over the long window. */
#endif
        f0 = ber_read(BER_SEL_FRAMES);
        e0 = ber_read(BER_SEL_ERRORS);
        xil_printf("ZCU216_BER: long-run start at rot_off=%lu (baseline f0=%lu e0=%lu); sig=0x%08lx target=%u frames\r\n",
                   (unsigned long)g_ber_rot, (unsigned long)f0, (unsigned long)e0,
                   (unsigned long)ber_read(BER_SEL_SIG), BER_TARGET_FRAMES);
        /* FRAME-7 WEDGE FIX (ILA-proven root cause).
         * The FINITE dut_capture sink (DEPTH=16384 nibbles) fills after
         * 16384/2652 = 6.18 frames -- i.e. partway through frame 7 -- then
         * DROPS s_axis_tready PERMANENTLY (dut_capture.v:84
         *   assign s_axis_tready = active || circular;  active=0 at count==DEPTH-1).
         * With the player looping forever the demod keeps producing, so that
         * dropped-ready back-pressures the whole chain: demod -> EQ
         * (eq_rx_ready=0) -> ch_est (h_tready=0, hbuf_full=[1,1]) -> align buf
         * (inflight=3, buf_wr_ready=0) -> fft_frontend (filled=[1,1],
         * fft_dout_tready=0) -> s_ready wedges -> sync stall_cnt -> 254 ->
         * STALL_TIMEOUT (dut_error_flags bit3 = 0x8), which is STICKY. Re-arming
         * cap_en 2 ms later resets dut_capture but the sticky error is already
         * latched at frame 7 -> the deterministic first_err_frame=7 seen on 10/10
         * PORs.  The downstream buffers were NEVER the cause; they back-pressured
         * correctly. Verified on silicon by the frx_ila_wedge capture (stall_cnt
         * 0..254; permanent m_axis_tready=0 from the 16384th accepted nibble).
         *
         * The BER checker (rx_ber_checker) is a PASSIVE snoop on
         * (m_bits_tvalid & m_bits_tready) -- it needs NO stored capture data.
         * So drive dut_capture in CIRCULAR (always-ready, wrapping) mode for the
         * long BER stream: s_axis_tready stays high, the chain never
         * back-pressures, stall_cnt never reaches 254, dut_error_flags stays 0,
         * and the checker tallies the unbounded stream continuously. Mirrors the
         * throughput-test path (cap_base |= LOOP_CAP_CIRC). */
        /* Engage CIRCULAR sink FIRST so the chain is flowing (s_axis_tready high),
         * THEN W1C-clear the sticky dut_error_flags that Steps 4/5/5a latched while
         * they used the FINITE sink (which wedges at frame 7 by design). This is a
         * pure AXI-Lite W1C (0x54) -- it does NOT soft-reset the DUT, so the BER
         * checker's aligned rot_off anchor is preserved. With circular mode active,
         * err_stall_timeout is no longer asserting, so the clear sticks. */
        /* FIX B: re-PULSE cap_en (low->high) WITH circular set so the FINITE-fill
         * deadlock left by Steps 4/5 is cleanly released -- fires dut_capture
         * `start` (resets wr_addr/wr_full, active=1) so tready is unconditionally
         * high before the checker anchor is taken. */
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN); /* cap_en LOW */
        usleep(200);
        Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN); /* rising edge */
        usleep(2000);
        Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);   /* W1C stale STALL_TIMEOUT */
        for (it = 0; it < MAX_IT; ++it) {
            /* CIRCULAR sink: keep cap_en asserted with CAP_CIRC so dut_capture is
             * always ready and never fills -> no artificial frame-7 back-pressure.
             * The player loop bits (PLAY_EN|LOOP_EN) stay asserted the whole time. */
            Xil_Out32(LOOP_CTRL_GPIO, LOOP_CAP_EN | LOOP_CAP_CIRC | LOOP_PLAY_EN | LOOP_LOOP_EN);
            usleep(2000);
            br_frames = ber_read(BER_SEL_FRAMES);
            br_errs   = ber_read(BER_SEL_ERRORS);
            br_flags  = ber_read(BER_SEL_FLAGS);
            d_frames  = br_frames - f0;
            d_errs    = br_errs   - e0;
            if (d_errs != 0 && first_err_at == 0xFFFFFFFFU) {
                first_err_at = d_frames;
                xil_printf("ZCU216_BER: FIRST ERROR at d_frames=%lu d_errs=%lu "
                           "flags=0x%08lx dut_err=0x%08lx\r\n",
                           (unsigned long)d_frames, (unsigned long)d_errs,
                           (unsigned long)br_flags,
                           (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
            }
            if (it < 12 || (it % 25) == 0)
                xil_printf("ZCU216_BER: it=%d d_frames=%lu d_errs=%lu flags=0x%08lx\r\n",
                           it, (unsigned long)d_frames, (unsigned long)d_errs,
                           (unsigned long)br_flags);
#ifdef ILA_DESYNC_TRIG
            /* keep streaming past the ~514 onset (and a little past first error so
             * the already-triggered ILA finishes filling), up to ILA_TARGET_FRAMES. */
            if (d_frames >= ILA_TARGET_FRAMES) break;
            if (first_err_at != 0xFFFFFFFFU && d_frames >= first_err_at + 100U) break;
#else
            if (d_frames >= BER_TARGET_FRAMES) break;
#endif
        }
        br_frames = ber_read(BER_SEL_FRAMES);
        br_errs   = ber_read(BER_SEL_ERRORS);
        br_nibs   = ber_read(BER_SEL_NIBBLES);
        br_flags  = ber_read(BER_SEL_FLAGS);
        br_warm   = ber_read(BER_SEL_WARMUP);
        d_frames  = br_frames - f0;
        d_errs    = br_errs   - e0;
        xil_printf("ZCU216_BER: ======== LONG-RUN RESULT (delta from stable anchor) ========\r\n");
        xil_printf("ZCU216_BER: frames_checked=%lu total_bit_errors=%lu (cum frames=%lu nibbles=%lu bits=%lu errs=%lu)\r\n",
                   (unsigned long)d_frames, (unsigned long)d_errs,
                   (unsigned long)br_frames, (unsigned long)br_nibs,
                   (unsigned long)(br_nibs * 4U), (unsigned long)br_errs);
        xil_printf("ZCU216_BER: err_flags=0x%08lx warmup_frames=%lu warmup_done=%lu rot_off=%lu\r\n",
                   (unsigned long)br_flags,
                   (unsigned long)(br_warm & 0xFFFFU),
                   (unsigned long)((br_warm >> 16) & 0x1U),
                   (unsigned long)g_ber_rot);
        xil_printf("ZCU216_BER: dut_error_flags=0x%08lx tlast_count=%lu first_err_frame=%ld\r\n",
                   (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS),
                   (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
                   (first_err_at == 0xFFFFFFFFU) ? -1L : (long)first_err_at);
        if (d_frames >= 50U && d_errs == 0U && br_flags == 0U)
            xil_printf("ZCU216_BER: RESULT PASS (BER=0 over %lu streamed frames, %lu bits)\r\n",
                       (unsigned long)d_frames, (unsigned long)(d_frames * MF_NIBBLES_PER_FRAME * 4U));
        else
            xil_printf("ZCU216_BER: RESULT FAIL (d_frames=%lu d_errs=%lu flags=0x%08lx)\r\n",
                       (unsigned long)d_frames, (unsigned long)d_errs, (unsigned long)br_flags);
    }

    /* DESYNC-512 fix: the BER long-run above streamed CIRCULAR (no wedge).  For
     * the Step-7 indexed readback we need a CONTIGUOUS finite fill, so re-arm the
     * sink FINITE (pulse cap_en low->high with cap_finite = LOOP_CAP_EN, circular
     * bit CLEARED) while the player keeps looping; the sink records the next
     * 16384 nibbles then asserts done.  This finite fill happens AFTER the sync is
     * already locked+streaming clean, so its one-time DEPTH back-pressure no
     * longer corrupts the (already-measured) BER -- it only stages readback data. */
    Xil_Out32(LOOP_CTRL_GPIO, cap_finite | LOOP_PLAY_EN | LOOP_LOOP_EN); /* cap_en stays hi, circ cleared */
    /* re-pulse cap_en to fire dut_capture `start` (reset wr_addr/wr_full, active=1) */
    Xil_Out32(LOOP_CTRL_GPIO, (cap_finite & ~LOOP_CAP_EN) | LOOP_PLAY_EN | LOOP_LOOP_EN); /* cap_en LOW */
    usleep(50);
    Xil_Out32(LOOP_CTRL_GPIO, cap_finite | LOOP_PLAY_EN | LOOP_LOOP_EN); /* cap_en rising -> finite fill */
    for (poll = 0; poll < 400; ++poll) {
        status0 = Xil_In32(LOOP_STATUS_GPIO);
        done = ((status0 >> 31) & 0x1U);
        if (done) break;
        usleep(2000);
    }
    /* Stop the player; keep cap_en (finite) asserted for the indexed readback. */
    Xil_Out32(LOOP_CTRL_GPIO, cap_finite);

    if (!done) {
        xil_printf("ZCU216_DLOOP: FAIL capture never filled (cap.status0=0x%08lx "
                   "player.status=0x%08lx tlast=%lu->%lu dut_status=0x%08lx "
                   "errflags=0x%08lx)\r\n",
                   (unsigned long)status0, (unsigned long)pstatus,
                   (unsigned long)tlast0,
                   (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
                   (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS),
                   (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));
        return XST_FAILURE;
    }
    xil_printf("ZCU216_DLOOP: capture FULL cap.status0=0x%08lx player.status=0x%08lx "
               "tlast=%lu dut_status=0x%08lx\r\n",
               (unsigned long)status0, (unsigned long)pstatus,
               (unsigned long)Xil_In32(DUT_LITE + DUT_TLAST_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_STATUS));

    /* --- Step 6: read CFO results (read VALID to snapshot, then the regs). - */
    {
        u32 cfo_valid   = Xil_In32(DUT_LITE + DUT_INT_CFO_VALID); /* snapshot */
        u32 cfo_est     = Xil_In32(DUT_LITE + DUT_INT_CFO_EST);
        u32 cfo_index   = Xil_In32(DUT_LITE + DUT_INT_CFO_INDEX);
        u32 cfo_applied = Xil_In32(DUT_LITE + DUT_INT_CFO_APPLIED);
        /* int-CFO decode: the meyr IFFT peak index is k_int mod N (N=512),
         * signed-wrapped at N/2: peak 0 -> k=0, 511 -> k=-1, 508 -> k=-4, etc.
         * Matches sim P5-D peak_meyr (km4=508, km1=511, kp0=0). The previous
         * "+60 calibration" was STALE (an old meyr-feed offset that this RTL no
         * longer has -- board raw index now matches sim exactly, no +60). */
        #define INT_CFO_N 512
        int int_cfo_cal = (int)cfo_index;
        if (int_cfo_cal >= INT_CFO_N/2) int_cfo_cal -= INT_CFO_N;
        xil_printf("ZCU216_DLOOP: CFO valid=%lu est=0x%08lx index=%lu "
                   "applied=0x%08lx\r\n",
                   (unsigned long)cfo_valid, (unsigned long)cfo_est,
                   (unsigned long)cfo_index, (unsigned long)cfo_applied);
        xil_printf("ZCU216_DLOOP: int_cfo (signed-wrap N=%d) = %d\r\n",
                   INT_CFO_N, int_cfo_cal);
    }
    /* --- Step 6b: sync metadata vs golden (tc0000: fsi=41 peak=23 slot=64). -- */
    xil_printf("ZCU216_DLOOP: SYNC fsv=%lu fsi=%lu peak=%lu slot=%lu "
               "in=%lu out=%lu errflags=0x%08lx\r\n",
               (unsigned long)Xil_In32(DUT_LITE + 0x18U),  /* FRAME_START_VALID */
               (unsigned long)Xil_In32(DUT_LITE + 0x1CU),  /* FRAME_START_INDEX */
               (unsigned long)Xil_In32(DUT_LITE + 0x20U),  /* PEAK_INDEX        */
               (unsigned long)Xil_In32(DUT_LITE + 0x24U),  /* SLOT_START_INDEX  */
               (unsigned long)Xil_In32(DUT_LITE + 0x10U),  /* IN_COUNT  */
               (unsigned long)Xil_In32(DUT_LITE + 0x14U),  /* OUT_COUNT */
               (unsigned long)Xil_In32(DUT_LITE + DUT_ERROR_FLAGS));

    /* --- Step 7: indexed readback of the N-frame demod-nibble capture into
     * capture_buf[]. The 14-bit read index is split low12=ctrl[13:2] /
     * hi2=ctrl[19:18] via LOOP_RD_CTRL(i); cap_en (bit1) stays asserted. The
     * player is stopped (play_en/load_en low) so driving ctrl[19:18] is safe. */
    rd_len = (int)MF_TOTAL_NIBBLES;             /* 5 frames * 2652 = 13260      */
    if (rd_len > (int)CAPTURE_DEPTH) rd_len = (int)CAPTURE_DEPTH;
    for (i = 0; i < rd_len; ++i) {
        /* DESYNC-512 fix: read back the FINITE fill (cap_finite, circular bit
         * CLEARED) -- driving circular here would keep the sink writing during
         * readback and scramble the indexed data. */
        u32 idx_ctrl = cap_finite | LOOP_RD_CTRL((u32)i);
        Xil_Out32(LOOP_CTRL_GPIO, idx_ctrl);
        /* Dummy read first: let the 2-FF ctrl sync + registered BRAM read settle. */
        (void)Xil_In32(LOOP_CAPTURE_GPIO);
        capture_buf[i] = (s32)Xil_In32(LOOP_CAPTURE_GPIO);
    }
    /* Release cap_en. */
    Xil_Out32(LOOP_CTRL_GPIO, 0U);

    /* Push capture_buf to physical DDR so the JTAG mrd sees it. */
    Xil_DCacheFlushRange((INTPTR)capture_buf, (unsigned)rd_len * sizeof(s32));

    /* --- Step 8: per-frame summary + markers for the xsct/JTAG dump flow. The
     * authoritative per-frame BER vs golden/rx_downstream/tx_bits.txt is computed
     * on host by scripts/ber_demod_bits.py --frames (one frame = 2652 nibbles =
     * 10608 bits). Here we just report frame[0] head nibbles as a liveness probe
     * and confirm contiguous frames captured. */
    {
        u32 f;
        for (f = 0; f < MF_NUM_FRAMES; ++f) {
            u32 base = f * MF_NIBBLES_PER_FRAME;
            if ((int)(base + MF_NIBBLES_PER_FRAME) > rd_len) break;
            xil_printf("ZCU216_DLOOP: frame %lu nibbles[%lu]=0x%lx [%lu]=0x%lx "
                       "last[%lu]=0x%lx\r\n",
                       (unsigned long)f, (unsigned long)base,
                       (unsigned long)(u32)capture_buf[base],
                       (unsigned long)(base + 1),
                       (unsigned long)(u32)capture_buf[base + 1],
                       (unsigned long)(base + MF_NIBBLES_PER_FRAME - 1),
                       (unsigned long)(u32)capture_buf[base + MF_NIBBLES_PER_FRAME - 1]);
        }
    }
    xil_printf("ZCU216_DLOOP: readback %d words (%u frames) buf=0x%08lx "
               "first=0x%08lx last=0x%08lx\r\n",
               rd_len, MF_NUM_FRAMES, (unsigned long)capture_buf,
               (unsigned long)(u32)capture_buf[0],
               (unsigned long)(u32)capture_buf[rd_len - 1]);
    xil_printf("ZCU216_DLOOP: PASS multi-frame digital loopback complete\r\n");
    return XST_SUCCESS;
}

/* RF 6c-2: bring up the DUT on the live RFDC-DDC OFDM stream and report sync.
 * dac_on selects whether the DAC OFDM is transmitting during the window. With
 * the DAC OFF the DUT should NOT detect a frame (fsv=0); with it ON it should
 * SYNC (fsv=1) and produce a stable int_cfo. */
/* RF DUAL-TAP: read back the PRE-deser banked-BRAM (zcu216_adc_capture) into
 * capture_acap[]. adc_cap shares loop_ctrl_gpio with rfsync_cap: cap_en=bit1,
 * the readback index lives in ctrl[14:2] (adc_cap AW=13; bits[12:10]=bank,
 * bits[9:0]=addr). status0 = capture_gpio @0xA0080000? No: adc_cap.status0 ->
 * loop_status_gpio (STATUS_GPIO_BASEADDR), status_capture -> capture_gpio
 * (CAPTURE_GPIO_BASEADDR). We hold cap_en high (shared with rfsync_cap arm) and
 * stride i=0..5119 reading the {Q,I} word of each (bank,addr).  The index field
 * top bit (ctrl[14]) coincides with DAC_OFDM; keep ONLY the amplitude + index +
 * cap_en bits during readback so the DAC/OFDM enables don't corrupt the index. */
static void acap_dump(void)
{
    u32 cstat = Xil_In32(STATUS_GPIO_BASEADDR);   /* adc_cap.status0 */
    int i;
    xil_printf("ZCU216_DUALTAP: pre-deser adc_cap.status0=0x%08lx "
               "(done=%lu beats=%lu)\r\n",
               (unsigned long)cstat, (unsigned long)((cstat >> 31) & 1U),
               (unsigned long)(cstat & 0xFFFFU));
    /* readback ctrl: amplitude field + cap_en + index<<2; NO DAC bits. */
    u32 rb_base = (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT) | RFS_CAP_EN;
    for (i = 0; i < ACAP_SAMPLES; ++i) {
        u32 idx_ctrl = rb_base | ((u32)i << CTRL_INDEX_SHIFT);
        Xil_Out32(RFSYNC_CTRL_GPIO, idx_ctrl);
        (void)Xil_In32(CAPTURE_GPIO_BASEADDR);   /* settle 2FF + banked BRAM read */
        capture_acap[i] = (s32)Xil_In32(CAPTURE_GPIO_BASEADDR);
    }
    Xil_DCacheFlush();
    xil_printf("ZCU216_DUALTAP: pre-deser dump acap[0]=0x%08lx [2560]=0x%08lx "
               "[5119]=0x%08lx addr=0x%08lx\r\n",
               (unsigned long)(u32)capture_acap[0],
               (unsigned long)(u32)capture_acap[2560],
               (unsigned long)(u32)capture_acap[ACAP_SAMPLES-1],
               (unsigned long)capture_acap);
}

static int rfsync_window(int dac_on, s32 *dst, int do_dump, int bypass, u32 threshold)
{
    u32 dac_ctrl = (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT);
#ifdef RF_OFDM_MODE
    if (dac_on) dac_ctrl |= CTRL_DAC_EN | CTRL_DAC_OFDM;  /* DAC plays OFDM */
#else
    /* TONE DISCRIMINATOR TEST: ctrl[14]=0 -> DAC plays the clean ~107.52 MHz
     * square tone (NOT OFDM). Only DAC_EN is asserted. */
    if (dac_on) dac_ctrl |= CTRL_DAC_EN;
#endif
    /* Circular capture: keep tready=1 so the chain drains at full rate (no
     * async-FIFO overflow). OR'd into the base so it persists across the arm
     * sequence AND the indexed readback (all use dac_ctrl). */
    if (g_cap_circular) dac_ctrl |= RFS_CAP_CIRC;
    u32 fsv, fsi, peak, slot, cfo_v, cfo_est, cfo_idx, cfo_app, dstat, errf;
    int int_cfo_cal;
    int i;

    /* --- Turn the DAC OFDM on (or off) BEFORE arming the DUT. ------------- */
    Xil_Out32(RFSYNC_CTRL_GPIO, dac_ctrl);
    usleep(20000);   /* let the DDC stream settle in the async FIFO */

    /* --- DUT bring-up: clear sticky flags, soft-reset, set frame_len, enable */
    Xil_Out32(DUT_LITE + DUT_STATUS, DUT_STAT_DONE_SEEN | DUT_STAT_ERROR_SEEN);
    Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);
    Xil_Out32(DUT_LITE + DUT_RESET_STATUS, 0xFFFFFFFFU);
    Xil_Out32(DUT_LITE + DUT_FRAME_LEN, RFSYNC_FRAME_LEN);
    /* threshold!=0: runtime-override the frame-detector energy THRESHOLD (0x68) so
     * we can retune on the live RF signal without a bitstream rebuild. 0 = keep the
     * build/reset default. */
    if (threshold) Xil_Out32(DUT_LITE + DUT_THRESHOLD_REG, threshold);
    /* `bypass` is the DEBUG_CTRL (0x4C) mode value:
     *   0x0 = NORMAL  (m_axis = fully-corrected slot)
     *   0x1 = BYPASS  (m_axis = raw DUT input, UNALIGNED)
     *   0x8 = DEBUG   (m_axis = frac-corrector output: frame-ALIGNED + frac-corrected,
     *                  BEFORE the meyr integer-CFO rotator) -> offline we add the
     *                  integer offset + demod to verify signal/timing vs the meyr. */
    Xil_Out32(DUT_LITE + 0x4CU, (u32)bypass);
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET);
    usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);
    usleep(2000);
    Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_ENABLE);   /* enable=1, auto-arm */

    /* --- Arm rfsync_cap (rising edge of cap_en) to grab a corrected slot. -- */
    Xil_Out32(RFSYNC_CTRL_GPIO, dac_ctrl);                /* cap_en low        */
    usleep(2000);
    Xil_Out32(RFSYNC_CTRL_GPIO, dac_ctrl | RFS_CAP_EN);   /* cap_en high       */

    /* --- Let the DUT run several slots on the live stream. ----------------- */
    usleep(50000);

    /* --- Read sync status (snapshot via 0x38 read while latch set). -------- */
    cfo_v   = Xil_In32(DUT_LITE + DUT_INT_CFO_VALID);     /* triggers snapshot */
    cfo_est = Xil_In32(DUT_LITE + DUT_INT_CFO_EST);
    cfo_idx = Xil_In32(DUT_LITE + DUT_INT_CFO_INDEX);
    cfo_app = Xil_In32(DUT_LITE + DUT_INT_CFO_APPLIED);
    fsi     = Xil_In32(DUT_LITE + 0x1CU);                 /* FRAME_START_INDEX */
    peak    = Xil_In32(DUT_LITE + 0x20U);                 /* PEAK_INDEX        */
    slot    = Xil_In32(DUT_LITE + 0x24U);                 /* SLOT_START_INDEX  */
    {   /* FRAC_CFO: 0x28 valid, 0x2C phase (signed Q-format residual CFO) */
        u32 frv = Xil_In32(DUT_LITE + 0x28U);
        s32 frp = (s32)Xil_In32(DUT_LITE + 0x2CU);
        xil_printf("ZCU216_RFSYNC: dac_on=%d frac_cfo_valid=%lu frac_cfo_phase=%ld\r\n",
                   dac_on, (unsigned long)frv, (long)frp);
    }
    fsv     = Xil_In32(DUT_LITE + 0x18U);                 /* FRAME_START_VALID (read-clear) */
    dstat   = Xil_In32(DUT_LITE + DUT_STATUS);
    errf    = Xil_In32(DUT_LITE + DUT_ERROR_FLAGS);

    #define RFS_INT_CFO_N 512
    int_cfo_cal = (int)cfo_idx;
    if (int_cfo_cal >= RFS_INT_CFO_N/2) int_cfo_cal -= RFS_INT_CFO_N;

    xil_printf("ZCU216_RFSYNC: dac_on=%d fsv=%lu fsi=%lu peak=%lu int_cfo=%d "
               "(idx=%lu est=0x%08lx)\r\n",
               dac_on, (unsigned long)fsv, (unsigned long)fsi,
               (unsigned long)peak, int_cfo_cal,
               (unsigned long)cfo_idx, (unsigned long)cfo_est);
    xil_printf("ZCU216_RFSYNC: dac_on=%d cfo_valid=%lu cfo_applied=%lu slot=%lu "
               "dut_status=0x%08lx errflags=0x%08lx in=%lu out=%lu\r\n",
               dac_on, (unsigned long)cfo_v, (unsigned long)cfo_app,
               (unsigned long)slot, (unsigned long)dstat, (unsigned long)errf,
               (unsigned long)Xil_In32(DUT_LITE + DUT_INPUT_COUNT),
               (unsigned long)Xil_In32(DUT_LITE + DUT_OUTPUT_COUNT));
    /* RF 6c-2 rate diag: s_axis handshake counters -> is the DUT input-starved
     * (tvalid low = gearbox/FIFO slow) or back-pressured (tready low = DUT stall)? */
    {
        u32 cyc = Xil_In32(DUT_LITE + DUT_CYC_TOTAL);
        u32 tv  = Xil_In32(DUT_LITE + DUT_IN_TVALID);
        u32 tr  = Xil_In32(DUT_LITE + DUT_IN_TREADY);
        xil_printf("ZCU216_RFSYNC: dac_on=%d s_axis cyc=%lu tvalid=%lu tready=%lu "
                   "(tvalid%%=%lu tready%%=%lu)\r\n",
                   dac_on, (unsigned long)cyc, (unsigned long)tv, (unsigned long)tr,
                   (unsigned long)(cyc ? (u32)((u64)tv*100/cyc) : 0),
                   (unsigned long)(cyc ? (u32)((u64)tr*100/cyc) : 0));
    }

    /* --- Optionally dump the rfsync_cap (corrected DUT m_axis) BRAM. ------- */
    if (do_dump && dst) {
        u32 cstat = Xil_In32(RFSYNC_STAT_GPIO);
        xil_printf("ZCU216_RFSYNC: cap.status0=0x%08lx (done=%lu beats=%lu)\r\n",
                   (unsigned long)cstat, (unsigned long)((cstat >> 31) & 1U),
                   (unsigned long)(cstat & 0xFFFFU));
        for (i = 0; i < RFSYNC_RD_LEN; ++i) {
            u32 idx_ctrl = dac_ctrl | RFS_CAP_EN |
                           ((u32)i << RFS_RD_INDEX_SHIFT);
            Xil_Out32(RFSYNC_CTRL_GPIO, idx_ctrl);
            (void)Xil_In32(RFSYNC_CAPDATA_GPIO);          /* settle 2FF+BRAM   */
            dst[i] = (s32)Xil_In32(RFSYNC_CAPDATA_GPIO);
        }
        Xil_DCacheFlush();
        xil_printf("ZCU216_RFSYNC: dump dst[0]=0x%08lx [100]=0x%08lx "
                   "[2000]=0x%08lx addr=0x%08lx\r\n",
                   (unsigned long)(u32)dst[0], (unsigned long)(u32)dst[100],
                   (unsigned long)(u32)dst[2000], (unsigned long)dst);
    }

    /* --- Disable DUT + capture for a clean next window. -------------------- */
    Xil_Out32(RFSYNC_CTRL_GPIO, dac_ctrl);                /* drop cap_en       */
    Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);                /* disable DUT       */
    return (int)fsv;
}

/* RF 6c-2 THRESHOLD sweep: the frame_detect_fsm needs the window-energy to CROSS
 * the per-sample THRESHOLD (dip below at the preamble/inter-frame gap, then 10
 * consecutive above). The measured DUT-input baseband band is per-sample ~4e5..1e6
 * (quiet/dip ~ window 1e7 -> /25 ~4e5; active ~2.7e7 -> /25 ~1.08e6). Sweep across
 * that band and report the first THRESHOLD that detects (fsv=1). 0x68 is a runtime
 * AXI-Lite reg so this needs no rebuild. */
/* NOTE: rfdc_deser now applies a x4 digital gain (GAIN_SHIFT=2) -> window ENERGY
 * is x16, so the per-sample THRESHOLD band scales x16 vs the unity-gain build
 * (was ~4e5..1.2e6 -> now ~3e6..2e7). */
static const u32 RFSYNC_THR_SWEEP[] = {
    3000000U, 6000000U, 9000000U, 12000000U, 16000000U, 20000000U
};
#define RFSYNC_THR_N (sizeof(RFSYNC_THR_SWEEP)/sizeof(RFSYNC_THR_SWEEP[0]))

/* EXPERIMENT 1: set the ADC2/blk0 fine-mixer NCO frequency (MHz) at runtime. */
static void set_adc2_nco(double freq_mhz)
{
    XRFdc_Mixer_Settings ms;
    XRFdc_GetMixerSettings(&Rfdc, XRFDC_ADC_TILE, 2, 0, &ms);
    ms.Freq        = freq_mhz;
    ms.EventSource = XRFDC_EVNT_SRC_IMMEDIATE;
    (void)XRFdc_SetMixerSettings(&Rfdc, XRFDC_ADC_TILE, 2, 0, &ms);
    (void)XRFdc_UpdateEvent(&Rfdc, XRFDC_ADC_TILE, 2, 0, XRFDC_EVENT_MIXER);
}

static int run_rf_sync(void)
{
    int fsv_off, fsv_on = 0;
    u32 best_thr = 0;
    unsigned k;
    xil_printf("ZCU216_RFSYNC: start (DDC->FIFO->deser->DUT->cap), "
               "frame_len=%u thr=runtime-sweep\r\n", RFSYNC_FRAME_LEN);

    /* ===================================================================== */
    /* RF DUAL-TAP ISOLATION: capture the SAME RF OFDM at BOTH taps in ONE    */
    /* window. m20 -> broadcaster -> { FIFO->deser->DUT->rfsync_cap (POST),   */
    /* adc_cap banked BRAM (PRE) }. cap_en (loop_ctrl bit1) arms BOTH sinks   */
    /* simultaneously. NCO=-300 (OFDM IF). 4 PORs are driven from the host    */
    /* (run_rfsync_dualtap.sh re-runs this per POR); here we grab 4 back-to-  */
    /* back windows so even a single boot yields repeatability evidence.      */
    /* For each: BYPASS mode (0x1) so rfsync_cap records the RAW DUT input    */
    /* (== post-deser baseband, the directly-comparable tap to adc_cap's raw  */
    /* DDC baseband). g_cap_circular keeps the post-deser sink draining.      */
    /* ===================================================================== */
    {
        int s;
        set_adc2_nco(-300.0);
        g_cap_circular = 1;
        xil_printf("ZCU216_DUALTAP: ===== RF dual-tap (PRE adc_cap + POST rfsync_cap) =====\r\n");
        xil_printf("ZCU216_DUALTAP: NCO=-300 OFDM, circular post sink, 4 back-to-back windows\r\n");
        (void)rfsync_window(1, capture_sweep[0], 0, 0x1, 9000000U);  /* warm-up */
        usleep(50000);
        for (s = 0; s < 4; ++s) {
            usleep(40000);
            xil_printf("ZCU216_DUALTAP: --- window s=%d (DAC ON OFDM, BYPASS) ---\r\n", s);
            /* POST-deser tap -> capture_buf (rfsync_cap raw DUT input, BYPASS) */
            (void)rfsync_window(1, capture_buf, 1, 0x1, 9000000U);
            /* PRE-deser tap -> capture_acap (adc_cap banked BRAM, armed by the
             * SAME cap_en that rfsync_window just left asserted). */
            acap_dump();
            /* On the LAST window keep both buffers in DDR for the JTAG dump
             * (capture_buf = POST window s=3, capture_acap = PRE window s=3). */
        }
        /* DAC-OFF baseline at both taps for noise-floor reference. */
        usleep(40000);
        xil_printf("ZCU216_DUALTAP: --- baseline (DAC OFF) ---\r\n");
        (void)rfsync_window(0, capture_buf_off, 1, 0x1, 9000000U);
        g_cap_circular = 0;
        xil_printf("ZCU216_DUALTAP: done (capture_buf=POST, capture_acap=PRE, capture_buf_off=OFF)\r\n");
#ifdef RFSYNC_ILA_HOLD
        /* LIVE-STREAM ILA HOLD: bring the FULL chain up and keep it DRAINING so an
         * on-chip ILA observes the live m20->FIFO->deser->DUT handshake + data.
         * REQUIRES: (a) DUT int_enable=1 + BYPASS (DEBUG_CTRL 0x1) so the DUT
         * s_axis_tready follows m_axis_tready (== rfsync_cap tready), and
         * (b) rfsync_cap CIRCULAR + cap_en so its tready stays HIGH.  Then
         * dut_0/s_axis tready=1 -> deser/FIFO/m20 all transfer -> stream flows.
         * Without the DUT enable the wrapper forces s_axis_tready=0 (chain stalls).
         * We re-read DUT error_flags + in/out counts so the UART reports whether
         * the stream is actually moving. */
        {
            u32 hold = (CAPTURE_AMPLITUDE << CTRL_AMP_SHIFT)
                     | CTRL_DAC_EN | CTRL_DAC_OFDM | RFS_CAP_EN | RFS_CAP_CIRC;
            /* DUT: clear sticky, soft-reset, frame_len, BYPASS, ENABLE, threshold */
            Xil_Out32(DUT_LITE + DUT_STATUS, DUT_STAT_DONE_SEEN | DUT_STAT_ERROR_SEEN);
            Xil_Out32(DUT_LITE + DUT_ERROR_FLAGS, 0xFFFFFFFFU);
            Xil_Out32(DUT_LITE + DUT_RESET_STATUS, 0xFFFFFFFFU);
            Xil_Out32(DUT_LITE + DUT_FRAME_LEN, RFSYNC_FRAME_LEN);
            Xil_Out32(DUT_LITE + DUT_THRESHOLD_REG, 9000000U);
            Xil_Out32(DUT_LITE + 0x4CU, 0x1U);                  /* BYPASS */
            Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_SOFT_RESET);
            usleep(2000);
            Xil_Out32(DUT_LITE + DUT_CONTROL, 0U);
            usleep(2000);
            Xil_Out32(DUT_LITE + DUT_CONTROL, DUT_CTRL_ENABLE); /* enable + auto-arm */
            Xil_Out32(RFSYNC_CTRL_GPIO, hold);                  /* cap_en + circular */
            xil_printf("ZCU216_ILAHOLD: DUT enabled+BYPASS+CIRCULAR, ctrl=0x%08lx; spinning.\r\n",
                       (unsigned long)hold);
            u32 it = 0;
            for (;;) {
                Xil_Out32(RFSYNC_CTRL_GPIO, hold);   /* keep cap_en+circular asserted */
                if ((it++ & 0x3FF) == 0) {           /* periodic live status */
                    u32 inc  = Xil_In32(DUT_LITE + DUT_INPUT_COUNT);
                    u32 outc = Xil_In32(DUT_LITE + DUT_OUTPUT_COUNT);
                    u32 errf = Xil_In32(DUT_LITE + DUT_ERROR_FLAGS);
                    u32 dst  = Xil_In32(DUT_LITE + DUT_STATUS);
                    xil_printf("ZCU216_ILAHOLD: in=%lu out=%lu err=0x%lx stat=0x%lx (streaming if in rising)\r\n",
                               (unsigned long)inc, (unsigned long)outc,
                               (unsigned long)errf, (unsigned long)dst);
                }
                usleep(1000);
            }
        }
#endif
        return XST_SUCCESS;
    }

    /* ===== EXPERIMENT 1: DDC NCO sweep. The 1.16% DAC:ADC rate mismatch shifts
     * the DAC IF (300MHz designed) to ~296.5MHz; if the OFDM band falls off the
     * DDC decimation filter, subcarriers are lost. Sweep the ADC NCO to re-center
     * the band, capture the raw DUT input (bypass) at each, dump for offline demod. */
    {
        /* EXP-4: re-test with the freshly-connected external SMA loopback
         * (XM655 10MHz-1GHz balun, DAC tile3 2_231 -> cable -> ADC tile2 0_226).
         * 5x baseline bypass captures -> reproducibility/demod. If cross-coherence
         * now jumps to ~1.0, the earlier 55% non-reproducibility was a loose/
         * intermittent cable, not clock jitter. */
        /* EXP-5: SNR check. s0,s1 = DAC OFF (noise floor); s2..s4 = DAC ON
         * (signal). SNR = sig_rms/noise_rms. High SNR => the 55% non-reproducibility
         * is NOT additive noise => clock jitter (MTS). Low SNR => weak signal is the
         * cause => boost power, no MTS needed. (Warm up first to avoid settle artifact.) */
        /* EXP-5b: CLEAN noise floor. DAC stays OFF the whole run (never on),
         * 3x warm-up (no dump) to let everything settle, then 5x capture. rms here =
         * pure ADC noise floor with the external SMA cable. Compare to the known
         * signal rms ~2900 (ext-SMA DAC ON). SNR = sig/noise. */
        /* EXP-6: Plan A jitter re-test. With the external common 245.76 reference
         * feeding BOTH ADC and DAC clock SMAs, the inter-LMX jitter should be gone.
         * 5x DAC-ON bypass captures -> cross-coherence. Before Plan A: ~0.45 (55%
         * non-reproducible). If Plan A worked: cross-coherence ~1.0. */
        int s;
        /* OFDM mode: NCO=-300 MHz (OFDM IF). TONE DISCRIMINATOR TEST (2026-06-26)
         * used NCO=-97.92 with RF_OFDM_MODE off: the 107.52 MHz square tone lands
         * at +9.6 MHz baseband (bin 256). Result: CLEAN reproducible tone (sharp
         * harmonic lines, P_peak/P_mean ~1000) => verdict (A) wideband-DDC, the
         * per-sample/CDC path is fine. Restore NCO=-300 for the OFDM run. */
        set_adc2_nco(-300.0);
        /* FIFO-OVERFLOW FIX TEST: enable dut_capture CIRCULAR mode (ctrl[16]) for
         * these bypass captures. Finite mode accepts only 4096 beats then drops
         * tready, so the free-running RFDC-DDC master overflows the async FIFO
         * and each capture grabs a non-deterministic overflow-dropped slice
         * (~0.4 cross-coherence, 137% demod). Circular mode keeps tready=1 ->
         * chain drains at full rate -> contiguous reproducible snapshot. */
        g_cap_circular = 1;
        xil_printf("ZCU216_RFSYNC: CIRCULAR capture mode ENABLED (ctrl[16]=0x10000)\r\n");
        (void)rfsync_window(1, capture_sweep[0], 0, 0x1, 9000000U);  /* warm-up, no dump */
        usleep(50000);
        for (s = 0; s < 5; ++s) {
            usleep(40000);
            xil_printf("ZCU216_RFSYNC: --- CIRCULAR cap s=%d (DAC ON bypass) ---\r\n", s);
            (void)rfsync_window(1, capture_sweep[s], 1, 0x1, 9000000U);  /* DAC ON */
        }
        /* tonecheck7: DAC-OFF baseline (same circular bypass mode) -> capture_buf_off
         * so the xsct _off.bin dump is the matched noise-floor reference for the
         * DAC-ON-vs-OFF RMS / in-band tone-bin discriminator. */
        usleep(40000);
        xil_printf("ZCU216_RFSYNC: --- CIRCULAR baseline (DAC OFF) -> capture_buf_off ---\r\n");
        (void)rfsync_window(0, capture_buf_off, 1, 0x1, 9000000U);  /* DAC OFF */
        g_cap_circular = 0;
        xil_printf("ZCU216_RFSYNC: CIRCULAR 5x DAC-ON + 1x DAC-OFF baseline done\r\n");
        return XST_SUCCESS;
    }

    /* DAC OFF baseline at a mid threshold: the DUT should NOT sync (noise only). */
    xil_printf("ZCU216_RFSYNC: --- window DAC_OFF (expect no sync) ---\r\n");
    fsv_off = rfsync_window(0, capture_buf_off, 0, 0, 9000000U);

    /* DAC ON: sweep THRESHOLD over the measured band, report fsv per value. */
    xil_printf("ZCU216_RFSYNC: --- DAC_ON THRESHOLD sweep ---\r\n");
    for (k = 0; k < RFSYNC_THR_N; ++k) {
        int fsv = rfsync_window(1, capture_buf, 0, 0, RFSYNC_THR_SWEEP[k]);
        xil_printf("ZCU216_RFSYNC: SWEEP thr=%lu -> fsv=%d\r\n",
                   (unsigned long)RFSYNC_THR_SWEEP[k], fsv);
        if (fsv && !best_thr) { best_thr = RFSYNC_THR_SWEEP[k]; fsv_on = 1; }
    }

    /* CFO STABILITY characterization: N fresh detections at the robust threshold
     * on the SAME continuous signal. Stable lock -> int/frac CFO consistent;
     * jittery -> detection-timing or int-CFO-algorithm instability (NOT pure SRO,
     * since ADC+DAC share the CLK104 245.76 MHz ref -> coherent sample clocks). */
    xil_printf("ZCU216_RFSYNC: --- CFO stability (8x @ thr=9000000) ---\r\n");
    for (k = 0; k < 8; ++k) {
        (void)rfsync_window(1, capture_buf, 0, 0, 9000000U);
    }

    /* Dump the corrected DUT output at a ROBUST threshold for verification. The
     * sweep's first-detect (best_thr, often 400000) is marginal (low sustained
     * out); 600000 gives sustained continuous processing (out=4096, in=millions)
     * -> a clean corrected slot to compare against golden. */
    {
        u32 thr = (best_thr && best_thr > 9000000U) ? best_thr : 9000000U;
        xil_printf("ZCU216_RFSYNC: --- DAC_ON detect+dump thr=%lu (DEBUG frac-m aligned) ---\r\n",
                   (unsigned long)thr);
        /* mode 0x8 = DEBUG: capture the frame-ALIGNED frac-corrected slot (pre-int
         * rotator). Offline: int-offset + CE/EQ + demod -> verify signal vs meyr. */
        (void)rfsync_window(1, capture_buf, 1, 0x8, thr);
    }

    /* DIAG: bypass-capture the RAW DUT-input baseband (DAC ON) into capture_buf_off
     * for offline autocorr (xsct dumps capture_buf_off -> _off.bin). */
    xil_printf("ZCU216_RFSYNC: --- window DAC_ON BYPASS (raw DUT input) ---\r\n");
    (void)rfsync_window(1, capture_buf_off, 1, 1, 0);

    xil_printf("ZCU216_RFSYNC: RESULT fsv_off=%d fsv_on=%d best_thr=%lu -> %s\r\n",
               fsv_off, fsv_on, (unsigned long)best_thr,
               (fsv_on && !fsv_off) ? "SYNC-OK (ON syncs, OFF does not)" :
               (fsv_on) ? "ON-syncs (OFF also flagged - check noise floor)" :
               "NO-SYNC (no THRESHOLD in sweep detected)");
    return (fsv_on) ? XST_SUCCESS : XST_FAILURE;
}

/* ----------------------------------------------------------------------------
 * MULTI-TILE SYNC (MTS): align the per-tile clock dividers of the active ADC
 * tile2 (bank226) and the DAC tiles 2+3 (bank230 distribution src + bank231
 * active OFDM DAC) to the COMMON external LMK SYSREF.  Without MTS each tile's
 * fabric-clock divider powers up at a RANDOM phase per reset -> the DAC<->ADC
 * sample-phase relationship is random per capture (the ~55% non-reproducible
 * / cross-coherence ~0.45 symptom).  MTS makes the divider phase deterministic
 * -> reproducible captures -> OFDM demod works.
 *
 * Requires CONFIG.{ADC2,DAC2,DAC3}_Multi_Tile_Sync=true in the RFDC IP (build_
 * rfsync_mts.tcl) and C_Sysref_Source=1 (external LMK SYSREF, already set).
 * The LMK already emits a 7.68 MHz SYSREF.  Returns XRFDC_MTS_OK(0) on success.
 * ------------------------------------------------------------------------- */
static int run_mts_sync(void)
{
    XRFdc_MultiConverter_Sync_Config DAC_Sync, ADC_Sync;
    u32 mts_dac, mts_adc;

    /* Enable the SYSREF distribution to the tiles (gate it through to the
     * converters) before running the sync.  XRFDC_MTS_SYSREF_ENABLE arms the
     * analog+fabric SYSREF capture on the tiles being synced. */
    XRFdc_MultiConverter_Init(&DAC_Sync, NULL, NULL, XRFDC_TILE_ID2);
    XRFdc_MultiConverter_Init(&ADC_Sync, NULL, NULL, XRFDC_TILE_ID2);

    /* DAC: span tile2 (distribution source) + tile3 (active OFDM DAC).
     * RefTile = the lowest tile in the mask (tile2). Tiles bitmask: b2|b3. */
    DAC_Sync.RefTile = 2U;
    DAC_Sync.Tiles   = (1U << 2) | (1U << 3);     /* 0xC */
    DAC_Sync.Target_Latency = -1;                  /* auto-target */
    DAC_Sync.SysRef_Enable  = 1;

    /* ADC: only tile2 active (bank226). RefTile = tile2. */
    ADC_Sync.RefTile = 2U;
    ADC_Sync.Tiles   = (1U << 2);                  /* 0x4 */
    ADC_Sync.Target_Latency = -1;                  /* auto-target */
    ADC_Sync.SysRef_Enable  = 1;

    /* Route the LMK SYSREF through to the requested DAC+ADC tiles, then run
     * the two converter syncs.  Order: DAC first (it is the clock-distribution
     * master via DAC2 Clock_Dist=1), then ADC. */
    XRFdc_MTS_Sysref_Config(&Rfdc, &DAC_Sync, &ADC_Sync, XRFDC_MTS_SYSREF_ENABLE);

    mts_dac = XRFdc_MultiConverter_Sync(&Rfdc, XRFDC_DAC_TILE, &DAC_Sync);
    xil_printf("ZCU216_MTS: DAC sync status=0x%lx (0=OK) tiles=0x%lx "
               "lat[2]=%d lat[3]=%d off[2]=%d off[3]=%d marker=%d\r\n",
               (unsigned long)mts_dac, (unsigned long)DAC_Sync.Tiles,
               DAC_Sync.Latency[2], DAC_Sync.Latency[3],
               DAC_Sync.Offset[2], DAC_Sync.Offset[3], DAC_Sync.Marker_Delay);

    mts_adc = XRFdc_MultiConverter_Sync(&Rfdc, XRFDC_ADC_TILE, &ADC_Sync);
    xil_printf("ZCU216_MTS: ADC sync status=0x%lx (0=OK) tiles=0x%lx "
               "lat[2]=%d off[2]=%d marker=%d\r\n",
               (unsigned long)mts_adc, (unsigned long)ADC_Sync.Tiles,
               ADC_Sync.Latency[2], ADC_Sync.Offset[2], ADC_Sync.Marker_Delay);

    if (mts_dac != XRFDC_MTS_OK || mts_adc != XRFDC_MTS_OK) {
        xil_printf("ZCU216_MTS: WARN sync not fully OK "
                   "(dac=0x%lx adc=0x%lx) - decode: 2=TIMEOUT 4=MARKER_RUN "
                   "8=MARKER_MISM 16=DELAY_OVER 32=TARGET_LOW 64=IP_NOT_READY "
                   "512=NOT_ENABLED 2048=SYSREF_GATE 4096=SYSREF_FREQ "
                   "8192=BAD_REF_TILE\r\n",
                   (unsigned long)mts_dac, (unsigned long)mts_adc);
        return XST_FAILURE;
    }
    xil_printf("ZCU216_MTS: PASS DAC+ADC multi-tile sync complete\r\n");
    return XST_SUCCESS;
}

int main(void)
{
    struct metal_init_params metal_params = METAL_INIT_DEFAULTS;
    XRFdc_Config *config;
    int status;
    int attempt;

    xil_printf("\r\nZCU216_RFDC: capture application start\r\n");

    /* RF 6c-2: enable pl_clk1 = 153.6 MHz (PL1_REF_CTRL: SRCSEL=2 RPLL,
     * DIVISOR0=5 -> RPLL/5 = 153.6). The DUT in the rfsync build runs on
     * pl_clk1, but the workspace psu_init predates it (PL1 off) -> without this
     * the DUT + its AXI-Lite get no clock and AXI accesses hang. The A53 has
     * full CRL_APB access, so do it here (JTAG-DAP mwr hit a DAP AXI error). */
    Xil_Out32(0xFF5E00C4U, 0x01010502U);
    usleep(1000);
    xil_printf("ZCU216_RFDC: pl_clk1 enabled (PL1_REF_CTRL=0x%08lx)\r\n",
               (unsigned long)Xil_In32(0xFF5E00C4U));

#ifdef RUN_XCVR_3MODE
    /* The xcvr-loopback bitstream has NO RFDC — skip all RFDC/CLK104/libmetal
     * init and go straight to the mode-selectable 3-mode silicon test
     * (pl_clk0, GPIO + AXI-Lite only). */
    xil_printf("ZCU216_XCVR: mode-selectable transceiver mode (skipping RFDC init)\r\n");
    return run_xcvr_3mode();
#endif

#ifdef RUN_DIGITAL_LOOPBACK
    /* The digital-loopback bitstream (10_digital_loopback) has NO RFDC — skip
     * all RFDC/CLK104/libmetal init and go straight to the DMA-free DUT loopback
     * (pl_clk0, GPIO + AXI-Lite only). The RFDC code below stays compiled (BSP
     * still has xrfdc) but is unreachable in this mode. */
    xil_printf("ZCU216_DLOOP: digital-loopback mode (skipping RFDC init)\r\n");
    return run_digital_loopback();
#endif

    status = XRFClk_Init(CLK104_GPIO_BASEADDR);
    if (status != XST_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL XRFClk_Init status=%d\r\n", status);
        return XST_FAILURE;
    }

    status = XRFClk_SetConfigOnAllChipsFromConfigId(
        LMK_CONFIG_ID, ADC_LMX_CONFIG_ID, DAC_LMX_CONFIG_ID);
    if (status != XST_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL CLK104 configuration status=%d\r\n",
                   status);
        return XST_FAILURE;
    }
    xil_printf("ZCU216_RFDC: CLK104 configuration complete\r\n");
    usleep(500000);

    /* RF common-clock: drive CLK104 OUTPUT_REF SMA (J17) at 245.76 MHz so an
     * external splitter can feed BOTH ZCU216 direct-connect clock SMAs
     * (ADC_CLK_225, DAC_CLK_229). This removes the per-tile LMX2594 jitter that
     * destroys OFDM by giving the ADC and DAC a single coherent sample clock.
     *
     * J17 = CLK104 OUTPUT_REF SMA, driven by LMK04828 DCLKout12 (default
     * 7.68 MHz). In the xrfclk driver the LMK "PortId" indexes the device-clock
     * register group (reg 0x100 + 8*PortId), so PortId=6 selects the DCLKout12
     * group. VCO = 2949.12 MHz (= 245.76*12); DCLKoutX_DIV = 12 -> 245.76 MHz.
     * MUX = 1 (divided path). Keep SYSREF_DIV at its config value (0x140 = 320)
     * so this call does NOT disturb the SYSREF that the ADC/DAC tiles need.
     * Finally ENABLE the port (state 0x03 = device-clock output on, matches the
     * 0x107-style format byte used by the active refclk ports in the table). */
    {
        const u32 J17_PORT_ID   = 6U;   /* DCLKout12 group (reg 0x130) -> J17 */
        const u32 J17_DCLK_DIV  = 12U;  /* 2949.12 / 12 = 245.76 MHz          */
        const u32 J17_DCLK_MUX  = 1U;   /* divided clock to the output buffer */
        const u32 J17_SDCLK_MUX = 0U;   /* SDCLKout13 unused by J17           */
        const u32 J17_SYSREF_DIV = 320U;/* = 0x140, current config value (keep)*/

        status = XRFClk_ConfigOutputDividerAndMUXOnLMK(
            J17_PORT_ID, J17_DCLK_DIV, J17_DCLK_MUX, J17_SDCLK_MUX,
            J17_SYSREF_DIV);
        if (status != XST_SUCCESS) {
            xil_printf("ZCU216_RFDC: WARN J17 LMK divider/mux cfg status=%d\r\n",
                       status);
        }
        status = XRFClk_ControlOutputPortLMK(J17_PORT_ID, 0x03U);
        if (status != XST_SUCCESS) {
            xil_printf("ZCU216_RFDC: WARN J17 LMK port enable status=%d\r\n",
                       status);
        }
        xil_printf("ZCU216_RFDC: J17 OUTPUT_REF set to 245.76 MHz "
                   "(DCLKout12 div=12, port enabled)\r\n");
        usleep(100000);
    }

    if (metal_init(&metal_params) != 0) {
        xil_printf("ZCU216_RFDC: FAIL metal_init\r\n");
        return XST_FAILURE;
    }

    config = XRFdc_LookupConfig(RFDC_DEVICE_ID);
    if (config == NULL) {
        xil_printf("ZCU216_RFDC: FAIL XRFdc_LookupConfig\r\n");
        return XST_FAILURE;
    }

    RfdcDevice = &RfdcCustomDevice;
    status = XRFdc_RegisterMetal(&Rfdc, RFDC_DEVICE_ID, &RfdcDevice);
    if (status != XRFDC_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL XRFdc_RegisterMetal status=%d\r\n",
                   status);
        return XST_FAILURE;
    }

    status = XRFdc_CfgInitialize(&Rfdc, config);
    if (status != XRFDC_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL XRFdc_CfgInitialize status=%d\r\n",
                   status);
        return XST_FAILURE;
    }
    xil_printf("ZCU216_RFDC: RFDC initialized base=0x%08lx\r\n",
               (unsigned long)config->BaseAddr);

    /* Reset DAC tiles after CLK104 setup so they re-lock to the LMK reference.
     * NOTE: do NOT reset the ADC tile here. XRFdc_Reset(ADC,2) re-runs the tile
     * startup but LOSES the DDC mixer/NCO/decimation datapath config that
     * XRFdc_CfgInitialize applied -> the ADC then locks (pll_lock=2,state=15)
     * yet produces NO valid baseband, so the bypass capture reads all zeros.
     * (An ADC reset would only be wanted alongside an MTS re-init, which this
     * design cannot enable; see run_mts_sync.) */
    xil_printf("ZCU216_RFDC: resetting all DAC tiles after CLK104 setup\r\n");
    status = XRFdc_Reset(&Rfdc, XRFDC_DAC_TILE, -1);
    if (status != XRFDC_SUCCESS) {
        xil_printf("ZCU216_RFDC: FAIL DAC reset status=%d\r\n", status);
        return XST_FAILURE;
    }
    xil_printf("ZCU216_RFDC: DAC reset complete\r\n");

    for (attempt = 1; attempt <= 20; ++attempt) {
        if (report_status() == XST_SUCCESS) {
            xil_printf("ZCU216_RFDC: PASS all required tiles ready\r\n");
            report_pll(XRFDC_ADC_TILE, 2, "ADC2");
            report_pll(XRFDC_DAC_TILE, 2, "DAC2");
            report_pll(XRFDC_DAC_TILE, 3, "DAC3");
            (void)run_digital_loopback;      /* retained when tone path selected */
            (void)run_capture;               /* retained when loopback selected  */
            (void)run_rf_sync;               /* retained when other path selected */
            /* run_mts_sync() is retained for future use but NOT called: the RFDC
             * IP gates Multi_Tile_Sync behind a clock-distribution architecture
             * this design cannot adopt without moving the wired data tiles, so the
             * MTS delay-aligner HW is absent and XRFdc_MultiConverter_Sync would
             * return XRFDC_MTS_NOT_ENABLED. See the RF-coherence investigation. */
            (void)run_mts_sync;
#ifdef RUN_DIGITAL_LOOPBACK
            return run_digital_loopback();   /* DMA-free DUT loopback path */
#elif defined(RUN_RF_SYNC)
            return run_rf_sync();            /* RF 6c-2: RFDC-DDC -> DUT sync */
#else
            return run_capture();            /* proven RF/tone capture path */
#endif
        }
        xil_printf("ZCU216_RFDC: waiting for tiles attempt=%d/20\r\n",
                   attempt);
        usleep(500000);
    }

    xil_printf("ZCU216_RFDC: FAIL required tiles not ready\r\n");
    return XST_FAILURE;
}
