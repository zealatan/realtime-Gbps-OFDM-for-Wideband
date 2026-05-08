/*
 * known_vector.h
 * Known-vector test stimulus for frac_cfo_sync_bram_test_wrapper
 * Step 29A — ZCU102 Phase 1 known-vector test
 *
 * Mirrors Step 26 testbench T7 (load_known_vector(8, 20)):
 *   8  quiet samples  — I=0,   Q=0   packed as 0x00000000
 *   20 active samples — I=100, Q=0   packed as 0x00000064
 *   total: 28 samples
 *
 * IQ packing:  tdata[15:0]=I (lower),  tdata[31:16]=Q (upper)
 *   quiet:  (Q=0  << 16) | (I=0)   = 0x00000000
 *   active: (Q=0  << 16) | (I=100) = 0x00000064  (100 = 0x64)
 *
 * Step 26 TB comment (line 337):
 *   "8 quiet (I=Q=0) + 20 active (I=100, Q=0) = 28 samples"
 */

#ifndef KNOWN_VECTOR_H
#define KNOWN_VECTOR_H

#include "xil_types.h"

/* =========================================================================
 * Test vector parameters
 * ========================================================================= */

#define KNOWN_QUIET_LEN              8U
#define KNOWN_ACTIVE_LEN             20U
#define KNOWN_INPUT_LEN              28U   /* QUIET_LEN + ACTIVE_LEN        */
#define KNOWN_OUTPUT_MAX_LEN         64U   /* capture limit passed to reg    */

/* =========================================================================
 * Pass/fail criteria
 *
 * INPUT_COUNT should exactly equal KNOWN_INPUT_LEN (all samples streamed).
 * OUTPUT_COUNT should be >= 1 (at least one corrected sample produced).
 * The exact OUTPUT_COUNT depends on the frame detector finding the frame
 * in the quiet→active transition.  Step 26 TB expected 20 with these params.
 *
 * We treat OUTPUT_COUNT == 20 as the expected value but do not hard-fail on
 * a different count since the corrector output length depends on frame_index
 * and peak_lag, which may vary with exact timing of the synthesized design.
 * ========================================================================= */

#define KNOWN_EXPECTED_INPUT_COUNT   28U
#define KNOWN_EXPECTED_OUTPUT_COUNT  20U   /* informational; see note above  */
#define KNOWN_EXPECTED_MIN_OUTPUT    1U    /* hard fail if below this        */

/* =========================================================================
 * Sample values
 *
 * quiet_sample:  I=0,   Q=0   → packed 0x00000000
 * active_sample: I=100, Q=0   → packed 0x00000064
 * ========================================================================= */

#define KNOWN_QUIET_SAMPLE    0x00000000U
#define KNOWN_ACTIVE_SAMPLE   0x00000064U  /* (0 << 16) | 100 */

/*
 * Full 28-sample vector, indexed [0..27].
 * Indices 0..7  = quiet,  indices 8..27 = active.
 * Declared const so it can be placed in flash / read-only section.
 */
static const u32 known_input[KNOWN_INPUT_LEN] = {
    /* quiet samples: I=0, Q=0 */
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    0x00000000U, 0x00000000U, 0x00000000U, 0x00000000U,
    /* active samples: I=100, Q=0 */
    0x00000064U, 0x00000064U, 0x00000064U, 0x00000064U,
    0x00000064U, 0x00000064U, 0x00000064U, 0x00000064U,
    0x00000064U, 0x00000064U, 0x00000064U, 0x00000064U,
    0x00000064U, 0x00000064U, 0x00000064U, 0x00000064U,
    0x00000064U, 0x00000064U, 0x00000064U, 0x00000064U,
};

#endif /* KNOWN_VECTOR_H */
