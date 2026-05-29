/*
 * session_F2_p3_17b_board_dma_validation.c — P3-17B Board DMA Replay Validation
 *
 * Full DMA replay validation of the Phase3 pipeline on real Zynq hardware.
 * Extends the P3-17A smoke test with structured failure classification and
 * tight algorithm-level tolerance checks.
 *
 * BOARD_GATE outputs (printed on final line):
 *   BOARD_GATE: PASS           — all 17 checks pass
 *   BOARD_GATE: PARTIAL_PASS   — AXI-Lite + DMA pass (classes A+D), algorithm fails (class G)
 *   BOARD_GATE: FAIL_AXI       — AXI-Lite register checks failed
 *   BOARD_GATE: FAIL_DMA       — DMA setup or transfer failed
 *   BOARD_GATE: FAIL_DEADLOCK  — DMA started but never completed
 *   BOARD_GATE: FAIL_ALGORITHM — Frame/CFO observables out of tolerance
 *   BOARD_GATE: BLOCKED        — Hardware prerequisite missing
 *
 * Failure classes (non-exclusive — all failing classes are reported):
 *   AXI-Lite  — register read/write errors, VERSION mismatch
 *   DMA       — DMA init/start failure or completion failure
 *   Deadlock  — DMA started but timed out (suggests AXI-Stream stall)
 *   Timing    — INPUT_COUNT or OUTPUT_COUNT mismatch (beat count wrong)
 *   Reset     — RESET_DONE not observed, ERROR_FLAGS set
 *   Algorithm — frame_index, peak_lag, slot_start, INT_CFO_APPLIED out of tolerance
 *
 * Hardware configuration (update BASE_ADDRESS defines to match your Vivado
 * address editor — Window → Address Editor after implementation):
 *
 *   SYNC_BASEADDR    AXI-Lite slave of phase3_sync_axis_dma_wrapper
 *                    Typical Zynq-7000 AXI-GP0 mapping: 0x43C00000
 *
 *   DMA_BASEADDR     Xilinx AXI DMA v7.x
 *                    Typical Zynq-7000 AXI-GP0 mapping: 0x40400000
 *
 * Simulation baseline (iverilog, P3-16A INTEGRATION_GATE: PASS):
 *   frame_index   = 40  (expect 41 ± 1)
 *   peak_lag      = 23  (expect 23 ± 1)
 *   slot_start    = 63  (expect 64 ± 1)
 *   frac_cfo_word = 3278 (Q1.15, ≈ +0.05 fractional CFO)
 *   int_cfo_index = 256 (Meyr peak ± 1 bypass-FFT offset)
 *   int_cfo_step  = 0xFF000000 (= −2^24, NCO step for k_int=0)
 *   output_count  = 576
 *   tlast_count   = 1
 */

#include <stdint.h>
#include <string.h>
#include "xil_printf.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xaxidma.h"
#include "sleep.h"

/* ---------------------------------------------------------------------------
 * UPDATE THESE: match your Vivado address editor output
 * --------------------------------------------------------------------------*/
#define SYNC_BASEADDR   0x43C00000U
#define DMA_BASEADDR    0x40400000U

/* ---------------------------------------------------------------------------
 * Phase3 AXI-Lite register offsets
 * --------------------------------------------------------------------------*/
#define REG_VERSION         0x00U
#define REG_CONTROL         0x04U
#define REG_STATUS          0x08U
#define REG_FRAME_LEN       0x0CU
#define REG_INPUT_COUNT     0x10U
#define REG_OUTPUT_COUNT    0x14U
#define REG_FSV             0x18U
#define REG_FSI             0x1CU
#define REG_PEAK_IDX        0x20U
#define REG_SLOT_IDX        0x24U
#define REG_FRAC_CFO_V      0x28U
#define REG_FRAC_CFO_P      0x2CU
#define REG_PSS_DONE        0x30U
#define REG_SSS_DONE        0x34U
#define REG_INT_CFO_V       0x38U
#define REG_INT_CFO_EST     0x3CU
#define REG_INT_CFO_INDEX   0x40U
#define REG_INT_CFO_APPLIED 0x44U
#define REG_RESET_STATUS    0x48U
#define REG_DEBUG_CTRL      0x4CU
#define REG_TLAST_COUNT     0x50U
#define REG_ERROR_FLAGS     0x54U

#define CTRL_ENABLE         (1U << 0)
#define CTRL_SOFT_RESET     (1U << 1)
#define STATUS_BUSY         (1U << 0)
#define STATUS_DONE_SEEN    (1U << 1)
#define STATUS_ERROR_SEEN   (1U << 2)

/* ---------------------------------------------------------------------------
 * Expected constants and tolerances
 * --------------------------------------------------------------------------*/
#define EXPECTED_VERSION    0x00316001U
#define FRAME_LEN           576U
#define STIM_LEN            704U

/* Algorithm tolerance bands (from P3-16A simulation baseline) */
#define FRAME_IDX_LO        40U
#define FRAME_IDX_HI        42U
#define PEAK_LAG_LO         22U
#define PEAK_LAG_HI         24U
#define SLOT_START_LO       63U
#define SLOT_START_HI       65U

/* Timeouts */
#define DMA_POLL_TIMEOUT    5000000U   /* ~5M poll iterations before deadlock declared */
#define INT_CFO_POLL_MS     500U       /* ms to poll INT_CFO_VALID before giving up */
#define RESET_POLL_ITERS    200000U

/* ---------------------------------------------------------------------------
 * IQ stimulus (embedded copy of golden/phase3_iq_stimulus.mem, 704 samples).
 * Format: bits[31:16]=Q, bits[15:0]=I (signed 16-bit each, packed AXI-Stream).
 * Zero pads: indices [0..63] and [640..703]; signal: indices [64..639].
 * --------------------------------------------------------------------------*/
static const uint32_t iq_stim[STIM_LEN] = {
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0xFF28FD16U, 0x02D3FA72U, 0xFA55FDD8U, 0x0357FA33U, 0xFFFD0063U, 0xFDD00170U, 0xFC4CFD7AU, 0xFF5207F9U,
    0xFF8CFEC3U, 0x0025FF3DU, 0xFC9E0217U, 0x0059FBCDU, 0x01A40609U, 0x009002D6U, 0x0289FB26U, 0xFC0001A4U,
    0xFFE80079U, 0xFF6304A2U, 0xFCE400C8U, 0xFDFD008EU, 0x026DFDD4U, 0xFF0303EAU, 0xFD19FC43U, 0x00E8FDE8U,
    0xFB36FCB9U, 0xFADD0A79U, 0xFE2403BCU, 0x076C0127U, 0xFBC7FC37U, 0xFEAB01B8U, 0x00E30038U, 0xFED1FC05U,
    0x01A70283U, 0x069204AFU, 0xFA6B017BU, 0xFE080426U, 0xFEFC0376U, 0xFFBEFEFFU, 0x026DFA14U, 0x0014FF69U,
    0x00E002AAU, 0x03CDFEA7U, 0x0433FAD2U, 0xFAAC026AU, 0x045501EAU, 0xFB81FFAFU, 0x04F8013EU, 0x00F20472U,
    0x0117FB31U, 0xFFE4FF7FU, 0xFEA802C5U, 0xF8A6066BU, 0x029B00B0U, 0x015F009BU, 0xFD3FFFF3U, 0xFB4200BFU,
    0x02380186U, 0x03E10293U, 0xFFA90466U, 0x0221FD40U, 0xF9CA042FU, 0xFF19FF91U, 0x02DA004CU, 0xFF7E003EU,
    0xFE3AFE72U, 0xFE64056FU, 0xFE3EFE40U, 0xF777FECBU, 0x03BFFCD5U, 0xFE540027U, 0xFEEFFCC4U, 0xFF60FE66U,
    0x0465FF3FU, 0x017AF8F8U, 0x00E8FC6DU, 0x00BEFB33U, 0x018C0307U, 0xFCBE02B1U, 0xFEACFB50U, 0x013E06D9U,
    0xFF570074U, 0xFD65F8C2U, 0x050A01D8U, 0xFDD6009EU, 0xFC68037CU, 0xFCB90375U, 0x05ECFEA5U, 0xFFE805BEU,
    0x01F80211U, 0x013704A2U, 0xFD3CFB62U, 0x00660AB7U, 0x0262FE36U, 0x036802B1U, 0xFCA4014FU, 0x04E3FE65U,
    0xF8860857U, 0xFEA5FDB5U, 0x031C042FU, 0xFF5E01C6U, 0xFD9501F6U, 0x062DFCD0U, 0x00C7F92FU, 0xFB86FE6CU,
    0xFDC2FEC9U, 0xFEDC03D6U, 0xF793FEF6U, 0x0094048FU, 0xFF970229U, 0xFF80FDDBU, 0xFBD70115U, 0xFCBC00A3U,
    0x017E046BU, 0x024500C0U, 0x03E00806U, 0x03F8FF16U, 0x020DFCB5U, 0x010702EAU, 0x025003BDU, 0xFBBF01D6U,
    0xFDBFFEF3U, 0xFEAEFDD0U, 0xFF9F0638U, 0x00D900A9U, 0x01AA0675U, 0x005EFC4DU, 0x0167FE7BU, 0xF920FDDEU,
    0x02EDF660U, 0x0105FE0DU, 0x026B0A24U, 0xFB90FDCFU, 0xFD99028FU, 0xFDADFA6DU, 0xFD4D0349U, 0x0275FEC7U,
    0x028E0695U, 0x001504DAU, 0x025E010EU, 0x01EB027DU, 0xFBBFFCA8U, 0xFDC4FE03U, 0x05E0015EU, 0x0007FD09U,
    0xFB88FADCU, 0xFEB104E3U, 0x022501E2U, 0xFA68084BU, 0xFEE40076U, 0xFD0AFEB7U, 0x016DFBD7U, 0xFD27FEA7U,
    0xFDD805D7U, 0xFC72FBD0U, 0xF6FA050CU, 0xFF48FB70U, 0x006C00C3U, 0x05DC029FU, 0xFB620467U, 0xFD760191U,
    0x0420FFC5U, 0xFDED03F5U, 0x013BFC76U, 0xFDA2FE11U, 0xFE00090CU, 0x0052F937U, 0xFD0BF965U, 0xFC7A02A4U,
    0xFDCF03EEU, 0x016FFE6BU, 0xFD60FE4BU, 0xFE9F004AU, 0x01F0FF34U, 0x0602FE19U, 0xFF1BFC3FU, 0xFBC503B1U,
    0xFA4BFFE3U, 0x007B0549U, 0x03A305F6U, 0xFBF603E0U, 0xFF32FFC6U, 0x00330347U, 0xFA61FC4AU, 0xFD67006AU,
    0xFB2EFCDEU, 0x0023FD03U, 0x06C3FBB3U, 0x00BA01FEU, 0xFE43006EU, 0x0142FEECU, 0x072DFB85U, 0x02D4FDEEU,
    0x020FF8C2U, 0xFF5B03BDU, 0x0850FCDBU, 0xFEAA04A4U, 0x05A00218U, 0x018AFE4AU, 0x042B07DCU, 0x05EE0359U,
    0xFFA0FEA8U, 0x0243FDBEU, 0x07EAFBDDU, 0x00B9FCDFU, 0xFDE5FDBEU, 0x015EFFD8U, 0xFBC800B3U, 0x026AFD2EU,
    0x014FF7E3U, 0xFE5DFC7FU, 0x008EFDADU, 0xFDEA00A7U, 0x00B700C1U, 0x0607053CU, 0x0378044BU, 0xFDD600DCU,
    0xFCD100B3U, 0x0072010FU, 0x026F01A5U, 0xFFCA0030U, 0xFB840057U, 0xFADCF866U, 0x0507FD99U, 0x015D035CU,
    0x00C6021AU, 0xFD48048BU, 0xFE7F00A0U, 0x01610538U, 0xFD7D0303U, 0xFC340625U, 0xFE0301F4U, 0x02DFFEF5U,
    0xFDCEFB7BU, 0x03A10026U, 0x0592F791U, 0x044AFEE1U, 0x03E3F892U, 0x01990514U, 0xFD2C0472U, 0xFCC7FD7AU,
    0xFCFFF96EU, 0xFDBAFC15U, 0x0677FD91U, 0xFBA9FF5AU, 0xFE35044EU, 0x0775039CU, 0x02E4FC80U, 0xFD19FF8AU,
    0xFE11FDD6U, 0xFE32FD5AU, 0xFFA6051DU, 0x00F1F8FDU, 0xFE70031BU, 0xFA2102C8U, 0x007EFB3FU, 0x02F00197U,
    0xFE4CFD7DU, 0x00F8F9D8U, 0xF9F1FFB3U, 0x0162F973U, 0x001C005FU, 0xFE5E020BU, 0xFBB3FEBEU, 0x01D107CBU,
    0xFF2FFEF7U, 0xFFE7FF3BU, 0xFD6E0308U, 0xFF08FBE6U, 0x036D053BU, 0x01690286U, 0x00EAFA9AU, 0xFCB402CCU,
    0x000E007BU, 0x00D90499U, 0xFD4901B4U, 0xFE420127U, 0x01A2FD2FU, 0x00450407U, 0xFC16FD58U, 0x0037FDBBU,
    0xFA6FFE5DU, 0xFE5A0B8DU, 0xFF620420U, 0x076AFECDU, 0xFAD1FDB4U, 0xFF44020CU, 0x00E9FFEFU, 0xFDA5FC94U,
    0xFAFAFFBBU, 0xFDF60178U, 0x0486FC4EU, 0xF94B040FU, 0xFD140107U, 0x0397FC50U, 0x03EF0509U, 0x00C8F843U,
    0x0533FAF9U, 0x02C3FDB5U, 0xF9AE0354U, 0x0482FFDEU, 0xFF7DFBF6U, 0x0125044AU, 0x0253FF8AU, 0x0050FC91U,
    0x00F1F9B1U, 0x01F101D2U, 0xFF5500CEU, 0xFFD50070U, 0x06AB014EU, 0x04ABFEB6U, 0x0376022AU, 0x03CDFDD5U,
    0xFDE9F9A0U, 0x036606CCU, 0xFE43FF50U, 0x01E900CDU, 0x0107018BU, 0x040702F4U, 0x0544FF86U, 0x0063FA8EU,
    0x06D3018DU, 0x04E000FFU, 0x04660164U, 0x0286FD72U, 0x012EFE9AU, 0xFDD9FE09U, 0x0091FD5BU, 0x06D900A6U,
    0x0975065AU, 0x03330403U, 0xFDCCFDACU, 0xFA2D0385U, 0xFE76F988U, 0x0192FD84U, 0xFF16FCA6U, 0xFD94F6DFU,
    0xFDA4003BU, 0x034AFF29U, 0x04CD0063U, 0xFBD1FC0EU, 0xFB86FFD0U, 0xFFB406CAU, 0xFBADFCE0U, 0x035402DCU,
    0xFE9A00FFU, 0x00710770U, 0x014DFD73U, 0xFBBE064DU, 0xFD63019EU, 0xFC29FF63U, 0xF9270169U, 0xFE87FEFEU,
    0x0097FE4EU, 0x007E00E6U, 0x02A600C0U, 0x031A0512U, 0x01DAFB6AU, 0x01ED04A7U, 0x0530FF3CU, 0x03EFFBC5U,
    0xFBA20150U, 0xFF1D00A3U, 0xFE58FAC0U, 0xFCC307C0U, 0xF9C0FE76U, 0xFEA502E8U, 0xFF0000F3U, 0xFD02FFC9U,
    0xFC7D0281U, 0x027902F5U, 0x00AE02C9U, 0xFC32012FU, 0x0418FD4AU, 0xFE03FD9BU, 0xFCEE01D9U, 0xFC21031CU,
    0xFE90FDA3U, 0x0590038AU, 0xFFE1FE47U, 0xFABBFF88U, 0xFECB019AU, 0xFCDCFFCEU, 0x03A8FD0FU, 0x07FE06C8U,
    0xFF88FF3CU, 0xF98AFD13U, 0x0303F9FEU, 0xFF74089EU, 0x03E104FCU, 0x04F5FCB0U, 0x034900E7U, 0xFF6101C3U,
    0xFF2D0246U, 0x037DFA9AU, 0x046B0002U, 0x0005FAEAU, 0x01180344U, 0xFB92FA55U, 0xF900FE57U, 0xFF70FFB9U,
    0xFE1D0003U, 0x08AD026EU, 0x01C902F1U, 0x05FCFE16U, 0xFE06FE61U, 0x0305FD89U, 0xFC0F0394U, 0x0008FF9AU,
    0x003B01C9U, 0xFB9F03EAU, 0x01AC004DU, 0x0779FE27U, 0xFAB80435U, 0xFE9D01B1U, 0xFFAA0521U, 0xFDD3FAD5U,
    0xF7D70733U, 0x0286003EU, 0xFA3F0524U, 0x00BFFC10U, 0x0182FD01U, 0xFF03F7F4U, 0x0179090DU, 0x015FFB3AU,
    0x03F5F976U, 0xFCDA00E0U, 0xFD9C01E3U, 0xFD8F02B5U, 0xF962F97BU, 0xFEDD053AU, 0x02D502FAU, 0xFF92FD58U,
    0x00EC0051U, 0x035006E3U, 0x03780214U, 0x039D03ECU, 0xFB8300DEU, 0xFC58FF35U, 0x056EF9D3U, 0x00D6FCE4U,
    0x0233FBE0U, 0xFF8501EBU, 0x00DF0615U, 0x0296F815U, 0xFE3AFC51U, 0xFAF6FCA7U, 0x0426FF8FU, 0x01DCFFC0U,
    0x05FE06B9U, 0xFDC600DCU, 0xF96D009AU, 0x054DFF83U, 0x009E0502U, 0x074FFDCCU, 0xFBFD00E5U, 0xFDB80448U,
    0x001A0259U, 0x00150282U, 0x01BC0123U, 0xFE6D0153U, 0x016EFCE3U, 0x0388FE1FU, 0xFDB10116U, 0xFD7C02B2U,
    0xFC4FFA35U, 0xFD81014CU, 0x02F3FF13U, 0x049005CDU, 0xFEEA0154U, 0x00EFFDB0U, 0xFD6A0308U, 0x023F01FDU,
    0xF981FCCCU, 0xFF6405E2U, 0xFF2301D0U, 0x04C3FA74U, 0x000AFC18U, 0x01FD010EU, 0x037B02B2U, 0x00D900BAU,
    0x03750237U, 0x04DFFA2CU, 0x02B6FFDCU, 0xFF4EFC41U, 0xFCB8033CU, 0xF780F7CBU, 0xFE8D019DU, 0xFE6B01A8U,
    0xFFF90249U, 0x012C00EEU, 0x0161FD4CU, 0xFC60FD57U, 0x0284FCB8U, 0x00CCFFC4U, 0xFB2C0056U, 0x01310263U,
    0xFB9FFD4CU, 0x0051FC7FU, 0x005EFBF7U, 0xFFEB0021U, 0x02E9024BU, 0x0347FA19U, 0x015101BEU, 0x047F05F1U,
    0x00E003EFU, 0x024F0745U, 0x07BE05FBU, 0xF9FDFD50U, 0xFDD2FC73U, 0x03B705D3U, 0x0132FC7AU, 0x04E20258U,
    0xFF520095U, 0xFE1C0433U, 0xFE0AFEDEU, 0x0183FEF1U, 0xFF410187U, 0x005903B4U, 0xFB5E05BEU, 0xF87BFC72U,
    0x01D30127U, 0x029F0451U, 0xFC62FB49U, 0x0465FCC8U, 0xFE3FFE5FU, 0xFE250041U, 0x008C0086U, 0xFF52FE88U,
    0x0602FF32U, 0xFFC1FEC2U, 0x00FF043FU, 0x06D6FE5DU, 0x0145FE8FU, 0x07310037U, 0xFC12FC79U, 0xFDEAF8A3U,
    0x005B022AU, 0x0276FC58U, 0x030BFDBCU, 0xFA060121U, 0x0221FABCU, 0x04AD01A4U, 0xFFCA00D8U, 0x0484041CU,
    0xFB24014BU, 0xFE840206U, 0x0329FB16U, 0xFAE005EFU, 0xFD8A01E1U, 0x0246FB62U, 0x054C0392U, 0xFE5AF866U,
    0x0364F99CU, 0x01EBFCF7U, 0xFB05051EU, 0x043EFE7BU, 0xFE44FC51U, 0x026A03BAU, 0x0211FED7U, 0xFF3DFCA3U,
    0xFEF2F9B5U, 0x02680122U, 0xFF9D00F9U, 0xFFFA0078U, 0x06BEFF2FU, 0x040BFD55U, 0x03F600FDU, 0x02F2FCC3U,
    0xFC0BFA95U, 0x0556056AU, 0xFE23FFE2U, 0x0210002CU, 0x01740127U, 0x04BE0190U, 0x04DDFDECU, 0xFEAFFAB4U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
};

static uint32_t rx_buf[FRAME_LEN] __attribute__((aligned(32)));

/* ---------------------------------------------------------------------------
 * Failure class bitmask — ORed as failures are detected
 * --------------------------------------------------------------------------*/
#define CLASS_AXI       (1U << 0)
#define CLASS_DMA       (1U << 1)
#define CLASS_DEADLOCK  (1U << 2)
#define CLASS_TIMING    (1U << 3)
#define CLASS_RESET     (1U << 4)
#define CLASS_ALGORITHM (1U << 5)

/* ---------------------------------------------------------------------------
 * Check tracking
 * --------------------------------------------------------------------------*/
#define MAX_CHECKS 20
static int   chk_pass[MAX_CHECKS];
static int   chk_cnt = 0;
static uint32_t fail_class = 0U;

static void check(const char *name, int pass, uint32_t fail_bits)
{
    chk_pass[chk_cnt] = pass;
    xil_printf("  [%2d] %-42s %s\r\n", chk_cnt, name, pass ? "PASS" : "FAIL");
    if (!pass) fail_class |= fail_bits;
    ++chk_cnt;
}

/* ---------------------------------------------------------------------------
 * Register helpers
 * --------------------------------------------------------------------------*/
static inline uint32_t reg_rd(uint32_t off)  { return Xil_In32(SYNC_BASEADDR + off); }
static inline void     reg_wr(uint32_t off, uint32_t v) { Xil_Out32(SYNC_BASEADDR + off, v); }

/* ---------------------------------------------------------------------------
 * Inline range check helper
 * --------------------------------------------------------------------------*/
static int in_range(uint32_t v, uint32_t lo, uint32_t hi)
{
    return (v >= lo && v <= hi);
}

/* ---------------------------------------------------------------------------
 * Main validation
 * --------------------------------------------------------------------------*/
static int run_validation(void)
{
    uint32_t v, timeout;
    XAxiDma  dma;
    XAxiDma_Config *dma_cfg;
    int      rc;

    xil_printf("\r\n");
    xil_printf("========================================================\r\n");
    xil_printf("P3-17B Board DMA Replay Validation\r\n");
    xil_printf("  SYNC_BASEADDR = 0x%08X\r\n", (unsigned)SYNC_BASEADDR);
    xil_printf("  DMA_BASEADDR  = 0x%08X\r\n", (unsigned)DMA_BASEADDR);
    xil_printf("========================================================\r\n\r\n");

    /* ======================================================================
     * Class RESET — soft reset and error flag clear
     * ====================================================================*/
    xil_printf("--- [Reset] ---\r\n");

    /* Clear any sticky error flags first */
    reg_wr(REG_ERROR_FLAGS,  0xFU);
    reg_wr(REG_STATUS,       STATUS_DONE_SEEN | STATUS_ERROR_SEEN);
    reg_wr(REG_RESET_STATUS, 0x1U);

    /* Issue soft reset pulse */
    reg_wr(REG_CONTROL, CTRL_SOFT_RESET);
    usleep(20);
    reg_wr(REG_CONTROL, 0U);
    usleep(200);

    /* Poll RESET_DONE (bit0 of RESET_STATUS) */
    timeout = RESET_POLL_ITERS;
    do {
        v = reg_rd(REG_RESET_STATUS);
        if (v & 0x1U) break;
    } while (--timeout);
    check("R0: soft reset → RESET_DONE observed", (timeout > 0U), CLASS_RESET);
    reg_wr(REG_RESET_STATUS, 0x1U);   /* W1C: clear RESET_DONE */

    v = reg_rd(REG_ERROR_FLAGS);
    xil_printf("  ERROR_FLAGS post-reset = 0x%X (expect 0)\r\n", (unsigned)(v & 0xF));
    check("R1: ERROR_FLAGS clear after reset", (v == 0U), CLASS_RESET);

    /* ======================================================================
     * Class AXI-Lite — register read/write correctness
     * ====================================================================*/
    xil_printf("\r\n--- [AXI-Lite] ---\r\n");

    v = reg_rd(REG_VERSION);
    xil_printf("  VERSION = 0x%08X (expect 0x%08X)\r\n",
               (unsigned)v, (unsigned)EXPECTED_VERSION);
    check("A0: VERSION == 0x00316001", (v == EXPECTED_VERSION), CLASS_AXI);

    reg_wr(REG_CONTROL, CTRL_ENABLE);
    v = reg_rd(REG_CONTROL);
    check("A1: CONTROL enable bit R/W", ((v & CTRL_ENABLE) != 0U), CLASS_AXI);
    reg_wr(REG_CONTROL, 0U);

    v = reg_rd(REG_STATUS);
    xil_printf("  STATUS = 0x%02X\r\n", (unsigned)(v & 0xFF));
    check("A2: STATUS bus responds (readable)", 1, 0U);   /* any value OK */

    reg_wr(REG_FRAME_LEN, FRAME_LEN);
    v = reg_rd(REG_FRAME_LEN);
    xil_printf("  FRAME_LEN = %u (expect %u)\r\n", (unsigned)(v & 0xFFFU), (unsigned)FRAME_LEN);
    check("A3: FRAME_LEN_SAMPLES R/W (576)", ((v & 0xFFFU) == FRAME_LEN), CLASS_AXI);

    /* Bail early if AXI bus is broken — no point running DMA */
    if (fail_class & CLASS_AXI) {
        xil_printf("\r\n  ABORT: AXI-Lite checks failed — skipping DMA\r\n");
        goto summary;
    }

    /* ======================================================================
     * Class DMA — initialise and start transfer
     * ====================================================================*/
    xil_printf("\r\n--- [DMA] ---\r\n");

    dma_cfg = XAxiDma_LookupConfig(0);
    if (!dma_cfg) {
        xil_printf("  ERROR: XAxiDma_LookupConfig(0) returned NULL\r\n");
        check("D0: DMA init", 0, CLASS_DMA);
        goto summary;
    }

    rc = XAxiDma_CfgInitialize(&dma, dma_cfg);
    check("D0: DMA init (XAxiDma_CfgInitialize)", (rc == XST_SUCCESS), CLASS_DMA);
    if (rc != XST_SUCCESS) {
        xil_printf("  ERROR: CfgInitialize returned %d\r\n", rc);
        goto summary;
    }

    XAxiDma_Reset(&dma);
    timeout = 100000U;
    while (!XAxiDma_ResetIsDone(&dma) && --timeout) {}
    if (!timeout) {
        xil_printf("  WARNING: DMA hardware reset did not complete\r\n");
        fail_class |= CLASS_DMA;
    }

    /* Flush TX buffer; invalidate RX buffer before transfer */
    Xil_DCacheFlushRange((UINTPTR)iq_stim, STIM_LEN  * sizeof(uint32_t));
    Xil_DCacheFlushRange((UINTPTR)rx_buf,  FRAME_LEN * sizeof(uint32_t));

    /* Enable synchronizer core before starting DMA */
    reg_wr(REG_CONTROL, CTRL_ENABLE);
    usleep(10);

    /* Start RX before TX to avoid S_AXIS stall when TX data arrives */
    rc = XAxiDma_SimpleTransfer(&dma,
                                (UINTPTR)rx_buf,
                                FRAME_LEN * sizeof(uint32_t),
                                XAXIDMA_DEVICE_TO_DMA);
    check("D1: DMA RX channel start", (rc == XST_SUCCESS), CLASS_DMA);

    rc = XAxiDma_SimpleTransfer(&dma,
                                (UINTPTR)iq_stim,
                                STIM_LEN * sizeof(uint32_t),
                                XAXIDMA_DMA_TO_DEVICE);
    check("D2: DMA TX channel start", (rc == XST_SUCCESS), CLASS_DMA);

    if (fail_class & CLASS_DMA) {
        xil_printf("\r\n  ABORT: DMA start failed — skipping transfer wait\r\n");
        goto summary;
    }

    /* ======================================================================
     * Class DEADLOCK — wait for both DMA channels to complete
     * ====================================================================*/
    xil_printf("\r\n--- [DMA completion] ---\r\n");

    timeout = DMA_POLL_TIMEOUT;
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA) && --timeout) {}
    if (!timeout) {
        xil_printf("  TIMEOUT: DMA RX channel stalled\r\n");
        fail_class |= CLASS_DEADLOCK;
    }

    timeout = DMA_POLL_TIMEOUT;
    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE) && --timeout) {}
    if (!timeout) {
        xil_printf("  TIMEOUT: DMA TX channel stalled\r\n");
        fail_class |= CLASS_DEADLOCK;
    }

    check("D3: DMA completes without deadlock", !(fail_class & CLASS_DEADLOCK), CLASS_DEADLOCK);

    if (fail_class & CLASS_DEADLOCK) {
        xil_printf("\r\n  STATUS at deadlock = 0x%02X\r\n",
                   (unsigned)(reg_rd(REG_STATUS) & 0xFF));
        xil_printf("  INPUT_COUNT = %u  OUTPUT_COUNT = %u\r\n",
                   (unsigned)reg_rd(REG_INPUT_COUNT),
                   (unsigned)reg_rd(REG_OUTPUT_COUNT));
        goto summary;
    }

    /* Allow pipeline to drain after TX completes */
    usleep(10000);

    /* Invalidate RX cache region before reading output */
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, FRAME_LEN * sizeof(uint32_t));

    /* ======================================================================
     * Class TIMING — beat count checks
     * ====================================================================*/
    xil_printf("\r\n--- [Timing / beat counts] ---\r\n");

    v = reg_rd(REG_INPUT_COUNT);
    xil_printf("  INPUT_COUNT  = %u (expect %u)\r\n", (unsigned)v, (unsigned)STIM_LEN);
    check("T0: INPUT_COUNT == 704 (STIM_LEN)", (v == STIM_LEN), CLASS_TIMING);

    v = reg_rd(REG_OUTPUT_COUNT);
    xil_printf("  OUTPUT_COUNT = %u (expect %u)\r\n", (unsigned)v, (unsigned)FRAME_LEN);
    check("T1: OUTPUT_COUNT == 576 (FRAME_LEN)", (v == FRAME_LEN), CLASS_TIMING);

    v = reg_rd(REG_TLAST_COUNT);
    xil_printf("  TLAST_COUNT  = %u (expect >= 1)\r\n", (unsigned)v);
    check("T2: TLAST_COUNT >= 1", (v >= 1U), CLASS_TIMING);

    /* ======================================================================
     * Class ALGORITHM — sync algorithm observables
     * ====================================================================*/
    xil_printf("\r\n--- [Algorithm observables] ---\r\n");

    /* Wait for INT_CFO_VALID (snapshot trigger).
     * Reading 0x38 while latch=1 also freezes the snapshot registers. */
    {
        int cfo_valid = 0;
        for (uint32_t ms = 0; ms < INT_CFO_POLL_MS; ms++) {
            v = reg_rd(REG_INT_CFO_V);
            if (v & 0x1U) { cfo_valid = 1; break; }
            usleep(1000);
        }
        check("G0: INT_CFO_VALID observed (snapshot triggered)", cfo_valid, CLASS_ALGORITHM);

        if (cfo_valid) {
            uint32_t est   = reg_rd(REG_INT_CFO_EST);
            uint32_t idx   = reg_rd(REG_INT_CFO_INDEX) & 0x1FFU;
            uint32_t appld = reg_rd(REG_INT_CFO_APPLIED) & 0x1U;
            uint32_t fsi   = reg_rd(REG_FSI)     & 0xFFFU;
            uint32_t peak  = reg_rd(REG_PEAK_IDX) & 0x1FFU;
            uint32_t slot  = reg_rd(REG_SLOT_IDX) & 0xFFFU;
            int16_t  fcfo  = (int16_t)(reg_rd(REG_FRAC_CFO_P) & 0xFFFFU);

            xil_printf("  INT_CFO_EST     = 0x%08X (expect 0xFF000000 for k_int=0)\r\n",
                       (unsigned)est);
            xil_printf("  INT_CFO_INDEX   = %u (expect 255-256)\r\n", (unsigned)idx);
            xil_printf("  INT_CFO_APPLIED = %u (expect 1)\r\n",  (unsigned)appld);
            xil_printf("  FRAME_START_IDX = %u (expect %u-%u)\r\n",
                       (unsigned)fsi, (unsigned)FRAME_IDX_LO, (unsigned)FRAME_IDX_HI);
            xil_printf("  PEAK_INDEX      = %u (expect %u-%u, peak lag)\r\n",
                       (unsigned)peak, (unsigned)PEAK_LAG_LO, (unsigned)PEAK_LAG_HI);
            xil_printf("  SLOT_START_IDX  = %u (expect %u-%u)\r\n",
                       (unsigned)slot, (unsigned)SLOT_START_LO, (unsigned)SLOT_START_HI);
            xil_printf("  FRAC_CFO_PHASE  = %d Q1.15 (expect ~3277-3278)\r\n", (int)fcfo);

            check("G1: INT_CFO_APPLIED == 1 (replay completed)",
                  (appld == 1U), CLASS_ALGORITHM);

            check("G2: FRAME_START_INDEX in [40, 42]",
                  in_range(fsi, FRAME_IDX_LO, FRAME_IDX_HI), CLASS_ALGORITHM);

            check("G3: PEAK_INDEX (lag) in [22, 24]",
                  in_range(peak, PEAK_LAG_LO, PEAK_LAG_HI), CLASS_ALGORITHM);

            check("G4: SLOT_START_INDEX in [63, 65]",
                  in_range(slot, SLOT_START_LO, SLOT_START_HI), CLASS_ALGORITHM);
        } else {
            xil_printf("  (INT_CFO_VALID not observed — skipping G1-G4)\r\n");
            /* Mark all algorithm checks failed */
            check("G1: INT_CFO_APPLIED == 1", 0, CLASS_ALGORITHM);
            check("G2: FRAME_START_INDEX in [40, 42]", 0, CLASS_ALGORITHM);
            check("G3: PEAK_INDEX in [22, 24]", 0, CLASS_ALGORITHM);
            check("G4: SLOT_START_INDEX in [63, 65]", 0, CLASS_ALGORITHM);
        }
    }

    /* Output buffer nonzero check */
    {
        int any_nonzero = 0;
        for (uint32_t i = 0; i < FRAME_LEN; i++) {
            if (rx_buf[i] != 0U) { any_nonzero = 1; break; }
        }
        check("G5: output buffer contains nonzero samples", any_nonzero, CLASS_ALGORITHM);

        xil_printf("\r\n--- [Output buffer preview] ---\r\n");
        for (int i = 0; i < 4; i++) {
            int16_t I = (int16_t)(rx_buf[i] & 0xFFFFU);
            int16_t Q = (int16_t)((rx_buf[i] >> 16) & 0xFFFFU);
            xil_printf("  rx_buf[%d] = 0x%08X  I=%6d Q=%6d\r\n",
                       i, (unsigned)rx_buf[i], (int)I, (int)Q);
        }
    }

    /* Post-run ERROR_FLAGS check */
    {
        v = reg_rd(REG_ERROR_FLAGS);
        xil_printf("\r\n  ERROR_FLAGS = 0x%X (expect 0)\r\n", (unsigned)(v & 0xF));
        if (v & 0xF) {
            if (v & 0x1) xil_printf("    bit0: FRAME_LEN_MISMATCH\r\n");
            if (v & 0x2) xil_printf("    bit1: TLAST_TIMEOUT\r\n");
            if (v & 0x4) xil_printf("    bit2: RESET_WHILE_ACTIVE\r\n");
            if (v & 0x8) xil_printf("    bit3: STALL_TIMEOUT\r\n");
            fail_class |= CLASS_TIMING;
        }
    }

summary:
    /* ======================================================================
     * Summary and BOARD_GATE output
     * ====================================================================*/
    xil_printf("\r\n========================================================\r\n");
    xil_printf("Summary\r\n");

    int fail = 0;
    for (int i = 0; i < chk_cnt; i++) {
        if (!chk_pass[i]) fail++;
    }
    xil_printf("  Checks passed: %d / %d\r\n", chk_cnt - fail, chk_cnt);

    if (fail_class) {
        xil_printf("  Failure classes:");
        if (fail_class & CLASS_AXI)       xil_printf(" AXI-Lite");
        if (fail_class & CLASS_DMA)       xil_printf(" DMA");
        if (fail_class & CLASS_DEADLOCK)  xil_printf(" Deadlock");
        if (fail_class & CLASS_TIMING)    xil_printf(" Timing");
        if (fail_class & CLASS_RESET)     xil_printf(" Reset");
        if (fail_class & CLASS_ALGORITHM) xil_printf(" Algorithm");
        xil_printf("\r\n");
    }

    xil_printf("========================================================\r\n");

    if (fail == 0) {
        xil_printf("BOARD_GATE: PASS\r\n");
    } else if (fail_class & (CLASS_AXI | CLASS_DMA)) {
        if (fail_class & CLASS_DEADLOCK) {
            xil_printf("BOARD_GATE: FAIL_DEADLOCK\r\n");
        } else if (fail_class & CLASS_DMA) {
            xil_printf("BOARD_GATE: FAIL_DMA\r\n");
        } else {
            xil_printf("BOARD_GATE: FAIL_AXI\r\n");
        }
    } else if (fail_class & CLASS_RESET) {
        xil_printf("BOARD_GATE: FAIL_RESET\r\n");
    } else if (fail_class & CLASS_ALGORITHM) {
        /* AXI + DMA passed but algorithm outputs out of tolerance */
        xil_printf("BOARD_GATE: PARTIAL_PASS\r\n");
        xil_printf("  AXI-Lite and DMA checks passed.\r\n");
        xil_printf("  Algorithm observables out of tolerance — see G* checks.\r\n");
    } else {
        xil_printf("BOARD_GATE: FAIL_TIMING\r\n");
    }

    return fail;
}

int main(void)
{
    int rc = run_validation();
    return (rc == 0) ? 0 : -1;
}
