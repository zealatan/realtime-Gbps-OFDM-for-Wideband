/*
 * main.c
 * Step 29A/29B — frac CFO sync known-vector test
 * Vitis 2022.2 baremetal standalone, Cortex-A53 (APU)
 *
 * Hardware: ZCU102, sync_phase1_bd_wrapper from Step 28
 * Custom IP base: 0xA0000000  (wrapper_0, AXI-Lite slave)
 *
 * Test sequence:
 *   1. Soft reset + clear status
 *   2. Write known-vector samples to input memory window
 *   3. Configure registers
 *   4. Enable wrapper, pulse start
 *   5. Poll STATUS until done or timeout
 *   6. Read INPUT_COUNT, OUTPUT_COUNT, first output samples
 *   7. Print RESULT: PASS or RESULT: FAIL
 */

#include "xil_printf.h"
#include "xil_io.h"
#include "xil_types.h"
#include "sleep.h"

#include "../register_map.h"
#include "../known_vector.h"

/* =========================================================================
 * Configuration
 * ========================================================================= */

/* Polling: max iterations before declaring timeout */
#define POLL_TIMEOUT_COUNT   2000000U
/* Print debug line every N polls */
#define POLL_DEBUG_INTERVAL  200000U

/* CFG register defaults for this test */
#define CFG_CFO_STEP        0U   /* NCO step = 0 (no rotation correction) */
#define CFG_TIMING_OFFSET   0U   /* timing offset = 0                     */
#define CFG_FRAME_LEN       KNOWN_INPUT_LEN

/* Number of output samples to print (cap at 16 for readability) */
#define PRINT_OUTPUT_SAMPLES 16U

/* =========================================================================
 * Helpers
 * ========================================================================= */

static void print_status_decoded(u32 status, u32 err)
{
    xil_printf("  STATUS=0x%08X  ERR=0x%08X\r\n", (unsigned)status, (unsigned)err);
    if (status & STATUS_BUSY)           xil_printf("    busy\r\n");
    if (status & STATUS_DONE_STICKY)    xil_printf("    done_sticky\r\n");
    if (status & STATUS_RUNNING)        xil_printf("    running\r\n");
    if (status & STATUS_INPUT_DONE)     xil_printf("    input_done\r\n");
    if (status & STATUS_OUTPUT_DONE)    xil_printf("    output_done\r\n");
    if (status & STATUS_INPUT_UNDERFLOW)xil_printf("    INPUT_UNDERFLOW\r\n");
    if (status & STATUS_OUTPUT_OVERFLOW)xil_printf("    OUTPUT_OVERFLOW\r\n");
    if (status & STATUS_FRAME_ERROR)    xil_printf("    FRAME_ERROR\r\n");
    if (err & ERR_TIMEOUT)              xil_printf("    TIMEOUT\r\n");
}

/* =========================================================================
 * Main
 * ========================================================================= */

int main(void)
{
    u32 status, err, input_count, output_count, debug_state;
    u32 i, poll_count;
    u32 done = 0U;
    u32 pass = 1U;

    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("Step 29A/29B: frac CFO sync known-vector test\r\n");
    xil_printf("Board:   ZCU102\r\n");
    xil_printf("IP base: 0x%08X\r\n", (unsigned)SYNC_BASE_ADDR);
    xil_printf("Vector:  %u quiet + %u active = %u samples\r\n",
               (unsigned)KNOWN_QUIET_LEN,
               (unsigned)KNOWN_ACTIVE_LEN,
               (unsigned)KNOWN_INPUT_LEN);
    xil_printf("========================================\r\n\r\n");

    /* -----------------------------------------------------------------------
     * 1. Soft reset
     * ----------------------------------------------------------------------- */
    xil_printf("[1] Soft reset...\r\n");
    sync_write32(SYNC_REG_CONTROL, CTRL_SOFT_RESET);
    usleep(100);                              /* wait 100 us for reset to propagate */
    sync_write32(SYNC_REG_CONTROL, 0U);      /* clear soft_reset (auto-clears anyway) */

    /* -----------------------------------------------------------------------
     * 2. Clear sticky status flags
     * ----------------------------------------------------------------------- */
    xil_printf("[2] Clear status...\r\n");
    sync_write32(SYNC_REG_CONTROL, CTRL_CLR_STATUS);
    usleep(10);
    sync_write32(SYNC_REG_CONTROL, 0U);

    status = sync_read32(SYNC_REG_STATUS);
    xil_printf("    STATUS after clear = 0x%08X\r\n", (unsigned)status);

    /* -----------------------------------------------------------------------
     * 3. Write known-vector samples into input memory window
     * ----------------------------------------------------------------------- */
    xil_printf("[3] Loading %u samples into input memory...\r\n",
               (unsigned)KNOWN_INPUT_LEN);
    for (i = 0U; i < KNOWN_INPUT_LEN; i++) {
        sync_mem_write(SYNC_INPUT_MEM_BASE, i, known_input[i]);
    }
    xil_printf("    Done. quiet[0]=0x%08X active[8]=0x%08X\r\n",
               (unsigned)known_input[0],
               (unsigned)known_input[KNOWN_QUIET_LEN]);

    /* -----------------------------------------------------------------------
     * 4. Zero output memory window (optional, for clean readback)
     * ----------------------------------------------------------------------- */
    xil_printf("[4] Clearing output memory (%u words)...\r\n",
               (unsigned)KNOWN_OUTPUT_MAX_LEN);
    for (i = 0U; i < KNOWN_OUTPUT_MAX_LEN; i++) {
        sync_mem_write(SYNC_OUTPUT_MEM_BASE, i, 0U);
    }

    /* -----------------------------------------------------------------------
     * 5. Configure registers
     * ----------------------------------------------------------------------- */
    xil_printf("[5] Writing configuration registers...\r\n");
    sync_write32(SYNC_REG_CFG_CFO_STEP,   CFG_CFO_STEP);
    sync_write32(SYNC_REG_CFG_TIMING_OFF, CFG_TIMING_OFFSET);
    sync_write32(SYNC_REG_CFG_FRAME_LEN,  CFG_FRAME_LEN);
    sync_write32(SYNC_REG_INPUT_LEN,      KNOWN_INPUT_LEN);
    sync_write32(SYNC_REG_OUTPUT_MAX_LEN, KNOWN_OUTPUT_MAX_LEN);
    xil_printf("    INPUT_LEN=%u  OUTPUT_MAX_LEN=%u  FRAME_LEN=%u\r\n",
               (unsigned)KNOWN_INPUT_LEN,
               (unsigned)KNOWN_OUTPUT_MAX_LEN,
               (unsigned)CFG_FRAME_LEN);

    /* -----------------------------------------------------------------------
     * 6. Enable wrapper then pulse start
     *
     * From RTL: dut_start = start_pulse_r && enable_r && !running_r
     * So enable must be set before or simultaneously with start_pulse.
     * start_pulse auto-clears the cycle after it is written.
     * ----------------------------------------------------------------------- */
    xil_printf("[6] Enabling wrapper...\r\n");
    sync_write32(SYNC_REG_CONTROL, CTRL_ENABLE);
    usleep(1);

    xil_printf("[6] Pulsing start...\r\n");
    sync_write32(SYNC_REG_CONTROL, CTRL_ENABLE | CTRL_START_PULSE);
    /* enable stays asserted; start_pulse auto-clears in RTL */

    /* -----------------------------------------------------------------------
     * 7. Poll STATUS until done or error or timeout
     * ----------------------------------------------------------------------- */
    xil_printf("[7] Polling STATUS...\r\n");
    poll_count = 0U;
    done = 0U;

    while (!done && poll_count < POLL_TIMEOUT_COUNT) {
        status      = sync_read32(SYNC_REG_STATUS);
        err         = sync_read32(SYNC_REG_ERROR_STATUS);
        input_count = sync_read32(SYNC_REG_INPUT_COUNT);
        output_count= sync_read32(SYNC_REG_OUTPUT_COUNT);
        debug_state = sync_read32(SYNC_REG_DEBUG_STATE);

        if (poll_count % POLL_DEBUG_INTERVAL == 0U) {
            xil_printf("  poll=%u  STS=0x%02X  IC=%u  OC=%u  DBG=%u  ERR=0x%X\r\n",
                       (unsigned)poll_count,
                       (unsigned)(status & 0xFFU),
                       (unsigned)input_count,
                       (unsigned)output_count,
                       (unsigned)debug_state,
                       (unsigned)err);
        }

        if (status & STATUS_DONE_STICKY) {
            done = 1U;
            xil_printf("  done_sticky asserted after %u polls\r\n", (unsigned)poll_count);
        } else if (status & STATUS_FRAME_ERROR) {
            done = 1U;
            xil_printf("  FRAME_ERROR after %u polls\r\n", (unsigned)poll_count);
        } else if (err & ERR_TIMEOUT) {
            done = 1U;
            xil_printf("  DUT TIMEOUT after %u polls\r\n", (unsigned)poll_count);
        }

        poll_count++;
    }

    if (!done) {
        xil_printf("  POLL TIMEOUT after %u polls (STATUS stuck)\r\n",
                   (unsigned)POLL_TIMEOUT_COUNT);
    }

    /* -----------------------------------------------------------------------
     * 8. Read final register state
     * ----------------------------------------------------------------------- */
    xil_printf("\r\n[8] Final register state:\r\n");
    status       = sync_read32(SYNC_REG_STATUS);
    err          = sync_read32(SYNC_REG_ERROR_STATUS);
    input_count  = sync_read32(SYNC_REG_INPUT_COUNT);
    output_count = sync_read32(SYNC_REG_OUTPUT_COUNT);
    debug_state  = sync_read32(SYNC_REG_DEBUG_STATE);

    print_status_decoded(status, err);
    xil_printf("  INPUT_COUNT  = %u  (expected %u)\r\n",
               (unsigned)input_count, (unsigned)KNOWN_EXPECTED_INPUT_COUNT);
    xil_printf("  OUTPUT_COUNT = %u  (expected ~%u)\r\n",
               (unsigned)output_count, (unsigned)KNOWN_EXPECTED_OUTPUT_COUNT);
    xil_printf("  DEBUG_STATE  = %u\r\n", (unsigned)debug_state);

    /* -----------------------------------------------------------------------
     * 9. Pass/fail evaluation
     * ----------------------------------------------------------------------- */
    xil_printf("\r\n[9] Evaluating result...\r\n");

    if (!(status & STATUS_DONE_STICKY)) {
        xil_printf("  FAIL: done_sticky not set\r\n");
        pass = 0U;
    }
    if (status & STATUS_FRAME_ERROR) {
        xil_printf("  FAIL: frame_error_sticky set\r\n");
        pass = 0U;
    }
    if (err != 0U) {
        xil_printf("  FAIL: ERROR_STATUS non-zero (0x%X)\r\n", (unsigned)err);
        pass = 0U;
    }
    if (input_count != KNOWN_EXPECTED_INPUT_COUNT) {
        xil_printf("  FAIL: INPUT_COUNT=%u expected %u\r\n",
                   (unsigned)input_count, (unsigned)KNOWN_EXPECTED_INPUT_COUNT);
        pass = 0U;
    }
    if (output_count < KNOWN_EXPECTED_MIN_OUTPUT) {
        xil_printf("  FAIL: OUTPUT_COUNT=%u below minimum %u\r\n",
                   (unsigned)output_count, (unsigned)KNOWN_EXPECTED_MIN_OUTPUT);
        pass = 0U;
    }

    /* Informational only — do not hard-fail on exact output count */
    if (output_count == KNOWN_EXPECTED_OUTPUT_COUNT) {
        xil_printf("  INFO: OUTPUT_COUNT matches expected (%u)\r\n",
                   (unsigned)KNOWN_EXPECTED_OUTPUT_COUNT);
    } else if (output_count >= KNOWN_EXPECTED_MIN_OUTPUT) {
        xil_printf("  INFO: OUTPUT_COUNT=%u (expected ~%u; acceptable)\r\n",
                   (unsigned)output_count, (unsigned)KNOWN_EXPECTED_OUTPUT_COUNT);
    }

    /* -----------------------------------------------------------------------
     * 10. Read and print first N output samples
     * ----------------------------------------------------------------------- */
    {
        u32 print_n = (output_count < PRINT_OUTPUT_SAMPLES) ?
                       output_count : PRINT_OUTPUT_SAMPLES;
        xil_printf("\r\n[10] First %u output samples:\r\n", (unsigned)print_n);
        xil_printf("  idx   hex_word   I(dec)   Q(dec)\r\n");
        for (i = 0U; i < print_n; i++) {
            u32 word = sync_mem_read(SYNC_OUTPUT_MEM_BASE, i);
            s16 i_val = (s16)(word & 0xFFFFU);         /* tdata[15:0] = I */
            s16 q_val = (s16)((word >> 16) & 0xFFFFU); /* tdata[31:16] = Q */
            xil_printf("  %3u   0x%08X   %6d   %6d\r\n",
                       (unsigned)i, (unsigned)word,
                       (int)i_val, (int)q_val);
        }
    }

    /* -----------------------------------------------------------------------
     * 11. Final result
     * ----------------------------------------------------------------------- */
    xil_printf("\r\n========================================\r\n");
    if (pass) {
        xil_printf("RESULT: PASS\r\n");
    } else {
        xil_printf("RESULT: FAIL\r\n");
    }
    xil_printf("========================================\r\n\r\n");

    return pass ? 0 : 1;
}
