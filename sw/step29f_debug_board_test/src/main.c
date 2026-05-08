/*
 * main.c
 * Step 29F — DEBUG_STATE diagnostic board test for frac_cfo_sync_bram_test_wrapper
 * Vitis 2022.2 baremetal standalone, Cortex-A53 (APU)
 *
 * Purpose:
 *   Diagnose the Step 29E anomaly: STATUS=0x00000192, INPUT_COUNT=0,
 *   OUTPUT_COUNT=0 even with correct ENABLE+START_PULSE sequence.
 *
 *   The RTL was patched (Step 29F) to add a DEBUG_STATE word with a
 *   version-0xF tag in bits[31:28] and sticky diagnostic flags that
 *   survive until cleared by soft_reset or clr_status.
 *
 * DEBUG_STATE bit encoding (version 0xF):
 *   [31:28] = 0xF  (version tag — distinguishes from old 0-5 encoding)
 *   [27]    = dbg_internal_start_seen  (sticky: dut_start pulsed)
 *   [26]    = dbg_source_start_seen    (sticky: source FSM left IDLE)
 *   [25]    = src_active               (SRC_STREAM right now)
 *   [24]    = input_done_r             (source completed)
 *   [23]    = dbg_dut_busy_seen        (sticky: DUT accepted start, went busy)
 *   [22]    = dut_busy                 (DUT running right now)
 *   [21]    = dut_s_axis_tvalid        (source presenting data right now)
 *   [20]    = dut_s_axis_tready        (DUT accepting data right now)
 *   [19]    = dbg_handshake_seen       (sticky: >=1 tvalid && tready handshake)
 *   [18:16] = src_state[2:0]           (0=IDLE 1=STREAM 2=DONE)
 *   [15]    = enable_r
 *   [14]    = running_r
 *   [13]    = done_sticky_r
 *   [12]    = frame_error_sticky_r
 *   [11:0]  = input_count_r[11:0]     (lower 12 bits of INPUT_COUNT)
 *
 * Pass criterion: INPUT_COUNT > 0 (source data flowed to DUT)
 * Fail diagnosis: read sticky flags to identify which step broke.
 *
 * Hardware: ZCU102, Step 28C bitstream (sync_phase1_bd_wrapper_with_bit.xsa)
 */

#include "xil_printf.h"
#include "xil_io.h"
#include "xil_types.h"
#include "sleep.h"

/* =========================================================================
 * Register map (mirror of sw/step29a_vitis_known_vector/register_map.h)
 * ========================================================================= */

#define SYNC_BASE_ADDR         0xA0000000U

#define SYNC_REG_CONTROL       0x0000U
#define SYNC_REG_STATUS        0x0004U
#define SYNC_REG_CFG_CFO_STEP  0x0008U
#define SYNC_REG_CFG_TIMING    0x000CU
#define SYNC_REG_CFG_FRAME_LEN 0x0010U
#define SYNC_REG_INPUT_LEN     0x0014U
#define SYNC_REG_OUTPUT_MAX_LEN 0x0018U
#define SYNC_REG_INPUT_COUNT   0x001CU
#define SYNC_REG_OUTPUT_COUNT  0x0020U
#define SYNC_REG_DEBUG_STATE   0x0024U
#define SYNC_REG_ERROR_STATUS  0x0028U

#define SYNC_INPUT_MEM_BASE    0x1000U
#define SYNC_OUTPUT_MEM_BASE   0x2000U

/* CONTROL bits */
#define CTRL_START_PULSE  (1U << 0)
#define CTRL_SOFT_RESET   (1U << 1)
#define CTRL_CLR_STATUS   (1U << 2)
#define CTRL_ENABLE       (1U << 3)

/* STATUS bits */
#define STATUS_BUSY          (1U << 0)
#define STATUS_DONE_STICKY   (1U << 1)
#define STATUS_RUNNING       (1U << 2)
#define STATUS_INPUT_DONE    (1U << 3)
#define STATUS_OUTPUT_DONE   (1U << 4)
#define STATUS_FRAME_ERROR   (1U << 8)

/* DEBUG_STATE fields */
#define DBG_VERSION_MASK     0xF0000000U
#define DBG_VERSION_EXPECTED 0xF0000000U
#define DBG_INT_START        (1U << 27)
#define DBG_SRC_START        (1U << 26)
#define DBG_SRC_ACTIVE       (1U << 25)
#define DBG_INPUT_DONE       (1U << 24)
#define DBG_DUT_BUSY_SEEN    (1U << 23)
#define DBG_DUT_BUSY_NOW     (1U << 22)
#define DBG_TVALID_NOW       (1U << 21)
#define DBG_TREADY_NOW       (1U << 20)
#define DBG_HANDSHAKE_SEEN   (1U << 19)
#define DBG_SRC_STATE_MASK   (0x7U << 16)
#define DBG_ENABLE           (1U << 15)
#define DBG_RUNNING          (1U << 14)
#define DBG_DONE_STICKY      (1U << 13)
#define DBG_FRAME_ERR        (1U << 12)
#define DBG_INPUT_CNT_MASK   0x00000FFFU

/* =========================================================================
 * Known-vector test stimulus
 * 8 quiet (I=Q=0) + 20 active (I=100, Q=0) = 28 samples — same as T7 / Step 29A
 * ========================================================================= */

#define INPUT_LEN       28U
#define OUTPUT_MAX_LEN  64U
#define QUIET_LEN        8U
#define ACTIVE_I_VAL   100

/* =========================================================================
 * Test parameters
 * ========================================================================= */

/* How many polls before giving up (soft spin — no usleep per poll) */
#define POLL_MAX        5000000U
/* Print a status line every N polls */
#define POLL_INTERVAL   1000000U

/* =========================================================================
 * Helpers
 * ========================================================================= */

static inline void wr(u32 offset, u32 val)
{
    Xil_Out32(SYNC_BASE_ADDR + offset, val);
}

static inline u32 rd(u32 offset)
{
    return Xil_In32(SYNC_BASE_ADDR + offset);
}

static inline void mem_wr(u32 base, u32 idx, u32 val)
{
    Xil_Out32(SYNC_BASE_ADDR + base + (idx * 4U), val);
}

static inline u32 mem_rd(u32 base, u32 idx)
{
    return Xil_In32(SYNC_BASE_ADDR + base + (idx * 4U));
}

static void print_debug_state(u32 dbg)
{
    u32 ver      = (dbg >> 28) & 0xFU;
    u32 src_st   = (dbg >> 16) & 0x7U;
    u32 cnt12    = dbg & DBG_INPUT_CNT_MASK;

    xil_printf("  DEBUG_STATE=0x%08X  ver=0x%X\r\n", (unsigned)dbg, (unsigned)ver);

    if (ver != 0xFU) {
        xil_printf("  WARNING: version tag != 0xF — RTL may be pre-29F bitstream\r\n");
        return;
    }

    xil_printf("  Sticky flags:");
    if (dbg & DBG_INT_START)    xil_printf(" int_start_seen");
    if (dbg & DBG_SRC_START)    xil_printf(" src_start_seen");
    if (dbg & DBG_DUT_BUSY_SEEN) xil_printf(" dut_busy_seen");
    if (dbg & DBG_HANDSHAKE_SEEN) xil_printf(" handshake_seen");
    xil_printf("\r\n");

    xil_printf("  Live snapshot:");
    if (dbg & DBG_SRC_ACTIVE)   xil_printf(" src_streaming");
    if (dbg & DBG_INPUT_DONE)   xil_printf(" input_done");
    if (dbg & DBG_DUT_BUSY_NOW) xil_printf(" dut_busy");
    if (dbg & DBG_TVALID_NOW)   xil_printf(" tvalid");
    if (dbg & DBG_TREADY_NOW)   xil_printf(" tready");
    if (dbg & DBG_ENABLE)       xil_printf(" enable");
    if (dbg & DBG_RUNNING)      xil_printf(" running");
    if (dbg & DBG_DONE_STICKY)  xil_printf(" done_sticky");
    if (dbg & DBG_FRAME_ERR)    xil_printf(" frame_err");
    xil_printf("\r\n");

    xil_printf("  src_state=%u  input_cnt_lo=%u\r\n",
               (unsigned)src_st, (unsigned)cnt12);
}

static void diagnose(u32 input_count, u32 dbg)
{
    xil_printf("\r\n--- Diagnosis ---\r\n");

    if ((dbg & DBG_VERSION_MASK) != DBG_VERSION_EXPECTED) {
        xil_printf("  UNKNOWN RTL version (no 0xF tag) — reprogram with Step 29F bitstream\r\n");
        return;
    }

    if (!(dbg & DBG_INT_START)) {
        xil_printf("  ROOT CAUSE: int_start_seen=0\r\n");
        xil_printf("    dut_start wire never went high.\r\n");
        xil_printf("    Check: enable_r was set before start_pulse write?\r\n");
        xil_printf("    Check: running_r was 0 at the time of start_pulse?\r\n");
        xil_printf("    Fix: write CTRL_ENABLE first, then CTRL_ENABLE|CTRL_START_PULSE.\r\n");
        return;
    }

    if (!(dbg & DBG_SRC_START)) {
        xil_printf("  ROOT CAUSE: src_start_seen=0\r\n");
        xil_printf("    dut_start pulsed but source FSM was not in SRC_IDLE.\r\n");
        xil_printf("    src_state at snapshot: %u\r\n",
                   (unsigned)((dbg >> 16) & 0x7U));
        xil_printf("    Fix: issue soft_reset before start, then re-run.\r\n");
        return;
    }

    if (!(dbg & DBG_DUT_BUSY_SEEN)) {
        xil_printf("  ROOT CAUSE: dut_busy_seen=0\r\n");
        xil_printf("    Source FSM started but DUT never went busy.\r\n");
        xil_printf("    DUT did not accept dut_start. Check iq_frame_buffer/DUT reset state.\r\n");
        return;
    }

    if (!(dbg & DBG_HANDSHAKE_SEEN)) {
        xil_printf("  ROOT CAUSE: handshake_seen=0\r\n");
        xil_printf("    DUT went busy but tvalid&&tready never occurred.\r\n");
        xil_printf("    tready stays 0 until iq_frame_buffer.busy=1 (1-cycle delay).\r\n");
        xil_printf("    This may be a single-sample mis-timing; DUT may have finished with 0 samples.\r\n");
        return;
    }

    if (input_count == 0U) {
        xil_printf("  ANOMALY: all stickies set but INPUT_COUNT=0\r\n");
        xil_printf("    Handshakes seen (dbg) but counter shows 0. Possible causes:\r\n");
        xil_printf("    - INPUT_LEN was 0 at start time; source sent tlast immediately.\r\n");
        xil_printf("    - input_count was reset by a second start_pulse after the first.\r\n");
        xil_printf("    Check: INPUT_LEN register value before this run.\r\n");
        return;
    }

    xil_printf("  All sticky flags set, INPUT_COUNT=%u — normal operation.\r\n",
               (unsigned)input_count);
    if (dbg & DBG_FRAME_ERR) {
        xil_printf("  frame_error is set: frame detector found no sync in the input vector.\r\n");
        xil_printf("  Ensure quiet→active transition is present and threshold is correct.\r\n");
    }
}

/* =========================================================================
 * Main
 * ========================================================================= */

int main(void)
{
    u32 i;
    u32 status, input_count, output_count, dbg;
    u32 poll;
    u32 done = 0U;

    xil_printf("\r\n");
    xil_printf("========================================\r\n");
    xil_printf("Step 29F: DEBUG_STATE diagnostic test\r\n");
    xil_printf("  IP base:    0x%08X\r\n", (unsigned)SYNC_BASE_ADDR);
    xil_printf("  INPUT_LEN:  %u samples\r\n", (unsigned)INPUT_LEN);
    xil_printf("  QUIET_LEN:  %u  ACTIVE I=100 Q=0\r\n", (unsigned)QUIET_LEN);
    xil_printf("========================================\r\n\r\n");

    /* ------------------------------------------------------------------
     * 1. Soft reset — clears running_r, source FSM, all stickies
     * ------------------------------------------------------------------ */
    xil_printf("[1] Soft reset\r\n");
    wr(SYNC_REG_CONTROL, CTRL_SOFT_RESET);
    usleep(100U);
    wr(SYNC_REG_CONTROL, 0U);
    usleep(10U);

    /* ------------------------------------------------------------------
     * 2. Clear status flags (belt-and-suspenders after soft reset)
     * ------------------------------------------------------------------ */
    xil_printf("[2] Clear status\r\n");
    wr(SYNC_REG_CONTROL, CTRL_CLR_STATUS);
    usleep(10U);
    wr(SYNC_REG_CONTROL, 0U);
    usleep(10U);

    status = rd(SYNC_REG_STATUS);
    dbg    = rd(SYNC_REG_DEBUG_STATE);
    xil_printf("    STATUS=0x%08X (expect 0)\r\n", (unsigned)status);
    xil_printf("    ");
    print_debug_state(dbg);

    /* ------------------------------------------------------------------
     * 3. Load input samples: 8 quiet (0x00000000) + 20 active (0x00000064)
     * ------------------------------------------------------------------ */
    xil_printf("[3] Loading %u samples into input memory\r\n", (unsigned)INPUT_LEN);
    for (i = 0U; i < INPUT_LEN; i++) {
        u32 word = (i < QUIET_LEN) ? 0x00000000U : (u32)ACTIVE_I_VAL; /* I=100 Q=0 */
        mem_wr(SYNC_INPUT_MEM_BASE, i, word);
    }
    /* Readback verify first and last */
    xil_printf("    input[0]=0x%08X (expect 0x00000000)\r\n",
               (unsigned)mem_rd(SYNC_INPUT_MEM_BASE, 0));
    xil_printf("    input[%u]=0x%08X (expect 0x%08X)\r\n",
               (unsigned)QUIET_LEN,
               (unsigned)mem_rd(SYNC_INPUT_MEM_BASE, QUIET_LEN),
               (unsigned)ACTIVE_I_VAL);

    /* ------------------------------------------------------------------
     * 4. Configure registers
     * ------------------------------------------------------------------ */
    xil_printf("[4] Writing configuration\r\n");
    wr(SYNC_REG_CFG_CFO_STEP,   0U);
    wr(SYNC_REG_CFG_TIMING,     0U);
    wr(SYNC_REG_CFG_FRAME_LEN,  INPUT_LEN);
    wr(SYNC_REG_INPUT_LEN,      INPUT_LEN);
    wr(SYNC_REG_OUTPUT_MAX_LEN, OUTPUT_MAX_LEN);
    xil_printf("    INPUT_LEN=%u  OUTPUT_MAX_LEN=%u  FRAME_LEN=%u\r\n",
               (unsigned)INPUT_LEN, (unsigned)OUTPUT_MAX_LEN, (unsigned)INPUT_LEN);

    /* ------------------------------------------------------------------
     * 5. Assert enable (separate write — ensures enable_r=1 before start_pulse)
     * ------------------------------------------------------------------ */
    xil_printf("[5] Assert enable\r\n");
    wr(SYNC_REG_CONTROL, CTRL_ENABLE);
    usleep(1U);

    /* ------------------------------------------------------------------
     * 6. Pulse start (enable remains set)
     *
     *    RTL: dut_start = start_pulse_r && enable_r && !running_r
     *    NBA semantics: start_pulse_r is set in WS_EXEC and auto-clears
     *    next cycle. For ONE AXI write the RTL sees start_pulse_r=1 for
     *    exactly one clock.
     * ------------------------------------------------------------------ */
    xil_printf("[6] Pulse start (ENABLE | START_PULSE)\r\n");
    wr(SYNC_REG_CONTROL, CTRL_ENABLE | CTRL_START_PULSE);
    /* enable stays; start_pulse auto-clears in RTL */

    /* Immediate snapshot — stickies should already be set */
    usleep(1U);
    dbg    = rd(SYNC_REG_DEBUG_STATE);
    status = rd(SYNC_REG_STATUS);
    input_count = rd(SYNC_REG_INPUT_COUNT);
    xil_printf("    Snapshot immediately after start:\r\n");
    xil_printf("    STATUS=0x%08X  IC=%u\r\n",
               (unsigned)status, (unsigned)input_count);
    print_debug_state(dbg);

    /* ------------------------------------------------------------------
     * 7. Poll STATUS for done_sticky or frame_error, print DEBUG_STATE
     * ------------------------------------------------------------------ */
    xil_printf("[7] Polling STATUS...\r\n");
    for (poll = 0U; poll < POLL_MAX; poll++) {
        status       = rd(SYNC_REG_STATUS);
        input_count  = rd(SYNC_REG_INPUT_COUNT);
        output_count = rd(SYNC_REG_OUTPUT_COUNT);
        dbg          = rd(SYNC_REG_DEBUG_STATE);

        if ((poll % POLL_INTERVAL) == 0U) {
            xil_printf("  poll=%u  STS=0x%02X  IC=%u  OC=%u\r\n",
                       (unsigned)poll,
                       (unsigned)(status & 0x1FFU),
                       (unsigned)input_count,
                       (unsigned)output_count);
            print_debug_state(dbg);
        }

        if (status & (STATUS_DONE_STICKY | STATUS_FRAME_ERROR)) {
            xil_printf("  Termination after %u polls:\r\n", (unsigned)poll);
            if (status & STATUS_DONE_STICKY) xil_printf("    done_sticky=1\r\n");
            if (status & STATUS_FRAME_ERROR) xil_printf("    frame_error=1\r\n");
            done = 1U;
            break;
        }
    }

    if (!done) {
        xil_printf("  POLL TIMEOUT — done_sticky never set after %u polls\r\n",
                   (unsigned)POLL_MAX);
    }

    /* ------------------------------------------------------------------
     * 8. Final state readout
     * ------------------------------------------------------------------ */
    xil_printf("\r\n[8] Final state\r\n");
    status       = rd(SYNC_REG_STATUS);
    input_count  = rd(SYNC_REG_INPUT_COUNT);
    output_count = rd(SYNC_REG_OUTPUT_COUNT);
    dbg          = rd(SYNC_REG_DEBUG_STATE);

    xil_printf("  STATUS       = 0x%08X\r\n", (unsigned)status);
    xil_printf("  INPUT_COUNT  = %u\r\n", (unsigned)input_count);
    xil_printf("  OUTPUT_COUNT = %u\r\n", (unsigned)output_count);
    print_debug_state(dbg);

    /* ------------------------------------------------------------------
     * 9. Diagnosis
     * ------------------------------------------------------------------ */
    diagnose(input_count, dbg);

    /* ------------------------------------------------------------------
     * 10. Pass / fail
     *    Pass criterion: INPUT_COUNT must be > 0 (data flowed to DUT)
     *    Secondary: no frame_error (full happy path)
     * ------------------------------------------------------------------ */
    xil_printf("\r\n========================================\r\n");
    if (input_count > 0U && !(status & STATUS_FRAME_ERROR)) {
        xil_printf("RESULT: PASS  (IC=%u, no frame_error)\r\n",
                   (unsigned)input_count);
    } else if (input_count > 0U && (status & STATUS_FRAME_ERROR)) {
        xil_printf("RESULT: PARTIAL  (IC=%u but frame_error set)\r\n",
                   (unsigned)input_count);
        xil_printf("  Data flowed but frame not found — check stimulus / threshold\r\n");
    } else {
        xil_printf("RESULT: FAIL  (INPUT_COUNT=0 — see diagnosis above)\r\n");
    }
    xil_printf("========================================\r\n\r\n");

    return (input_count > 0U) ? 0 : 1;
}
