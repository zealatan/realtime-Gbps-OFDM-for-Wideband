/* dump_p5_d1.c — D1 3-way reference dump.
 *
 * Calls the exact C reference m_seq / gold_seq functions used by
 * receiver.c, emits the I/Q float arrays + term2 product as text.
 * The Python mirror (gen_p5_bk_conj_fft512_rom.py) is verified
 * against this output bit-exact (float == float when both compute
 * the same arithmetic in the same order).
 *
 * Compile:   gcc -O0 -o dump_p5_d1 dump_p5_d1.c signal_processing_common.c -lm
 * Run:       ./dump_p5_d1 > golden/p5_d1/c_dump.txt
 *
 * Constants pinned to ref/pluto.h + signal_processing_common.c::init_sig_pro:
 *   NSC=256, CP_LEN=32, seqLen=127, syncSigStartIndex=55,
 *   Nid_1=170, Nid_2=2, bitsPerSymbolPreamble=1
 */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include "pluto.h"

/* Inlined verbatim from ref/signal_processing_common.c — identical
 * bit pattern. No fftw3 dependency, so the standalone dump compiles
 * without linking the full system.
 */
void m_seq(float* preambleI, float* preambleQ, int len,
           int bitsPerSymbolPreamble, int Nid_2) {
    unsigned char x_init[7] = {1, 1, 1, 0, 1, 1, 0};
    unsigned char x[256];
    int m;
    for (int i = 0; i < len; i++) {
        if (i < 7)  x[i] = x_init[i];
        else        x[i] = (x[i - 3] + x[i - 7]) % 2;
    }
    for (int n = 0; n < len; n++) {
        m = (n + 43 * Nid_2) % len;
        preambleI[n] = - (1 - 2 * x[m]) * sqrtf((float)NSC / (float)len);
        preambleQ[n] = 0;
    }
}
void gold_seq(float* preambleI, float* preambleQ, int len,
              int bitsPerSymbolPreamble, int Nid_1, int Nid_2) {
    unsigned char x0_init[7] = {0, 0, 0, 0, 0, 0, 1};
    unsigned char x1_init[7] = {0, 0, 0, 0, 0, 0, 1};
    unsigned char x0[256], x1[256];
    int m0, m1;
    for (int i = 0; i < len; i++) {
        if (i < 7) { x0[i] = x0_init[i]; x1[i] = x1_init[i]; }
        else {
            x0[i] = (x0[i - 3] + x0[i - 7]) % 2;
            x1[i] = (x1[i - 6] + x1[i - 7]) % 2;
        }
    }
    for (int n = 0; n < len; n++) {
        m0 = 15 * (int)(floor((float)Nid_1 / 112.0)) + 5 * Nid_2;
        m1 = Nid_1 % 112;
        preambleI[n] = (1 - 2 * x0[(n + m0) % len])
                     * (1 - 2 * x1[(n + m1) % len])
                     * sqrtf((float)NSC / (float)len);
        preambleQ[n] = 0;
    }
}

int main(void) {
    const int seqLen = 127;
    const int syncStart = 55;
    const int Nid_1 = 170;
    const int Nid_2 = 2;
    const int bps   = 1;

    /* Allocate the layout receiver.c uses: at least syncStart+CP_LEN+seqLen,
     * but expose mU[CP_LEN..CP_LEN+NSC-1] which is what term2 reads. */
    const int sym_block = (syncStart + CP_LEN + seqLen);
    const int alloc_n   = (sym_block > CP_LEN + NSC) ? sym_block : (CP_LEN + NSC);

    float *mUI   = calloc(alloc_n, sizeof(float));
    float *mUQ   = calloc(alloc_n, sizeof(float));
    float *gUI   = calloc(alloc_n, sizeof(float));
    float *gUQ   = calloc(alloc_n, sizeof(float));

    /* Same call pattern as ref/transmitter.c::generate_transmit_slot */
    int base = syncStart + CP_LEN;
    m_seq   (mUI + base, mUQ + base, seqLen, bps, Nid_2);
    gold_seq(gUI + base, gUQ + base, seqLen, bps, Nid_1, Nid_2);

    /* term2[j] = mU[j+CP_LEN] * conj(gU[j+CP_LEN]) for j in [0,NSC).
     * Both sequences are real (Q=0) so:
     *   term2.I = mU.I * gU.I
     *   term2.Q = 0
     */
    printf("# P5-D1 C reference dump\n");
    printf("# NSC=%d CP_LEN=%d seqLen=%d sync=%d Nid_1=%d Nid_2=%d\n",
           NSC, CP_LEN, seqLen, syncStart, Nid_1, Nid_2);
    printf("# Format: j mU_I mU_Q gU_I gU_Q term2_I\n");
    for (int j = 0; j < NSC; j++) {
        int idx = j + CP_LEN;
        float t2i = mUI[idx] * gUI[idx];   /* (mU.I*gU.I) - (mU.Q*gU.Q)=0 */
        printf("%d %.10f %.10f %.10f %.10f %.10f\n",
               j, mUI[idx], mUQ[idx], gUI[idx], gUQ[idx], t2i);
    }

    free(mUI); free(mUQ); free(gUI); free(gUQ);
    return 0;
}
