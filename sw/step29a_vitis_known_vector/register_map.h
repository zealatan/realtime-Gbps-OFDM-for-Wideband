/*
 * register_map.h
 * Register map for frac_cfo_sync_bram_test_wrapper
 * Step 29A — ZCU102 Phase 1 known-vector test
 *
 * Base address: 0xA0000000  (wrapper_0, assigned in Step 27 BD)
 * Address range: 64 KB
 *
 * Bit definitions verified against:
 *   rtl/frac_cfo_sync_bram_test_wrapper.v  (CONTROL decode line 272-320,
 *                                            STATUS word lines 346-357)
 */

#ifndef REGISTER_MAP_H
#define REGISTER_MAP_H

#include "xil_io.h"
#include "xil_types.h"

/* =========================================================================
 * Base address
 * ========================================================================= */

#define SYNC_BASE_ADDR  ((u32)0xA0000000U)

/* =========================================================================
 * Register offsets (byte addresses relative to SYNC_BASE_ADDR)
 * ========================================================================= */

#define SYNC_REG_CONTROL         0x0000U  /* R/W — control pulses + enable */
#define SYNC_REG_STATUS          0x0004U  /* R/O — status flags             */
#define SYNC_REG_CFG_CFO_STEP    0x0008U  /* R/W — NCO step word            */
#define SYNC_REG_CFG_TIMING_OFF  0x000CU  /* R/W — timing offset (unused)   */
#define SYNC_REG_CFG_FRAME_LEN   0x0010U  /* R/W — frame length config      */
#define SYNC_REG_INPUT_LEN       0x0014U  /* R/W — number of input samples  */
#define SYNC_REG_OUTPUT_MAX_LEN  0x0018U  /* R/W — output capture limit     */
#define SYNC_REG_INPUT_COUNT     0x001CU  /* R/O — samples streamed to DUT  */
#define SYNC_REG_OUTPUT_COUNT    0x0020U  /* R/O — samples captured to mem  */
#define SYNC_REG_DEBUG_STATE     0x0024U  /* R/O — FSM state code           */
#define SYNC_REG_ERROR_STATUS    0x0028U  /* R/O — error flags              */

/* =========================================================================
 * Memory window offsets (byte addresses relative to SYNC_BASE_ADDR)
 * ========================================================================= */

#define SYNC_INPUT_MEM_BASE   0x1000U  /* 1024 x 32-bit, R/W from PS */
#define SYNC_OUTPUT_MEM_BASE  0x2000U  /* 1024 x 32-bit, R/O from PS */
#define SYNC_MEM_WORDS        1024U    /* max entries per window      */

/* =========================================================================
 * CONTROL register bit fields  [from RTL lines 272-277]
 *
 *   bit[0]  start_pulse   — auto-clears next clock; triggers DUT start
 *   bit[1]  soft_reset    — auto-clears next clock; resets DUT + sticky flags
 *   bit[2]  clr_status    — auto-clears next clock; clears sticky flags only
 *   bit[3]  enable        — sticky; must be 1 for start_pulse to launch DUT
 *
 * Run sequence:
 *   CONTROL = ENABLE                   (set enable sticky)
 *   CONTROL = ENABLE | START_PULSE     (launch; start_pulse auto-clears)
 *
 * Or in one write:
 *   CONTROL = ENABLE | START_PULSE
 * ========================================================================= */

#define CTRL_START_PULSE   (1U << 0)
#define CTRL_SOFT_RESET    (1U << 1)
#define CTRL_CLR_STATUS    (1U << 2)
#define CTRL_ENABLE        (1U << 3)

/* =========================================================================
 * STATUS register bit fields  [from RTL lines 346-357]
 *
 *   bit[0]  dut_busy               — DUT (frac_cfo_frame_corrector_top) busy
 *   bit[1]  done_sticky            — set when DUT done; cleared by clr_status
 *   bit[2]  running                — stream source/sink active
 *   bit[3]  input_done             — source FSM reached SRC_DONE
 *   bit[4]  output_done            — sink   FSM reached SNK_DONE
 *   bit[5]  input_underflow_sticky — source ran out before INPUT_LEN
 *   bit[6]  output_overflow_sticky — output_mem full before DUT finished
 *   bit[7]  done_sticky (dup)      — same as bit[1]; use bit[1] for polling
 *   bit[8]  frame_error_sticky     — DUT reported no frame found
 * ========================================================================= */

#define STATUS_BUSY                 (1U << 0)
#define STATUS_DONE_STICKY          (1U << 1)
#define STATUS_RUNNING              (1U << 2)
#define STATUS_INPUT_DONE           (1U << 3)
#define STATUS_OUTPUT_DONE          (1U << 4)
#define STATUS_INPUT_UNDERFLOW      (1U << 5)
#define STATUS_OUTPUT_OVERFLOW      (1U << 6)
#define STATUS_FRAME_ERROR          (1U << 8)

/* =========================================================================
 * ERROR_STATUS register bit fields  [from RTL lines 369-375]
 *
 *   bit[0]  input_underflow_sticky
 *   bit[1]  output_overflow_sticky
 *   bit[2]  (reserved)
 *   bit[3]  timeout (running && timeout counter expired)
 * ========================================================================= */

#define ERR_INPUT_UNDERFLOW  (1U << 0)
#define ERR_OUTPUT_OVERFLOW  (1U << 1)
#define ERR_TIMEOUT          (1U << 3)

/* =========================================================================
 * DEBUG_STATE codes  [from RTL lines 361-367]
 *
 *   0 = idle / disabled
 *   1 = enabled, waiting for start
 *   2 = SRC_STREAM (source active, streaming to DUT)
 *   3 = SRC_DONE + SNK_CAPTURE (source done, sink still capturing)
 *   4 = done_sticky
 *   5 = frame_error_sticky
 * ========================================================================= */

#define DBGSTATE_IDLE          0U
#define DBGSTATE_READY         1U
#define DBGSTATE_STREAMING     2U
#define DBGSTATE_SINK_ACTIVE   3U
#define DBGSTATE_DONE          4U
#define DBGSTATE_FRAME_ERROR   5U

/* =========================================================================
 * IQ packing convention  [Step 3 fixed-point spec, complex_mult_iq.v]
 *
 *   tdata[15: 0] = I (real),  Q1.15 signed, lower 16 bits
 *   tdata[31:16] = Q (imag),  Q1.15 signed, upper 16 bits
 *
 *   Packed word = ((u32)(s16)Q << 16) | ((u32)(u16)I)
 * ========================================================================= */

static inline u32 sync_pack_iq(s16 i_val, s16 q_val)
{
    return ((u32)(u16)q_val << 16) | (u32)(u16)i_val;
}

/* =========================================================================
 * Register accessors
 * ========================================================================= */

static inline void sync_write32(u32 offset, u32 value)
{
    Xil_Out32(SYNC_BASE_ADDR + offset, value);
}

static inline u32 sync_read32(u32 offset)
{
    return Xil_In32(SYNC_BASE_ADDR + offset);
}

static inline void sync_mem_write(u32 mem_base, u32 word_index, u32 value)
{
    Xil_Out32(SYNC_BASE_ADDR + mem_base + (word_index * 4U), value);
}

static inline u32 sync_mem_read(u32 mem_base, u32 word_index)
{
    return Xil_In32(SYNC_BASE_ADDR + mem_base + (word_index * 4U));
}

#endif /* REGISTER_MAP_H */
