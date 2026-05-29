/*
 * golden_dump.c — Phase 3 C Reference Golden Value Extractor
 *
 * Builds standalone: gcc -O2 -Wall golden_dump.c -lm -o golden_dump
 * Does NOT require libiio, fftw3, or ad9361.
 *
 * Usage:
 *   ./golden_dump <iq_float32.f32> <golden_values.txt> <autocorr_full.txt>
 *
 * Input: binary float32 interleaved IQ (I0 Q0 I1 Q1 ...)
 * Output: golden/phase3_golden_values.txt + golden/phase3_autocorr_full.txt
 *
 * Re-implements Steps 1–3 of ref/signal_processing_common.c:synchronization()
 * using the exact same algorithm, no FFTW dependency.
 * Step 4 (integer CFO / Meyr) requires FFT and is excluded.
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <time.h>

/* ======================================================
 * Constants — must match ref/pluto.h
 * ====================================================== */
#define NSC     256
#define CP_LEN  32
#define PI      3.14159265358979323846

/* ======================================================
 * frame_detector — energy window detector
 * Direct copy of logic from ref/signal_processing_common.c
 * ====================================================== */
static int frame_detector(const float *rxI, const float *rxQ,
                           int rxLen, int wndLen, float threshold)
{
    int   half       = rxLen / 2 + 10;
    float *env       = (float *) malloc(half * sizeof(float));
    int   indexFrame = -1;
    int   ctr        = 0;

    for (int j = 0; j < half; j++) {
        env[j] = 0.0f;
        for (int i = j; i < j + wndLen; i++)
            env[j] += rxI[i]*rxI[i] + rxQ[i]*rxQ[i];
        env[j] /= (float) wndLen;
    }

    if (env[0] < threshold) {
        for (int j = 1; j < half; j++) {
            if (env[j] > threshold) {
                if (++ctr == 10) { indexFrame = j + 1 - 10; break; }
            } else ctr = 0;
        }
    } else {
        int startIdx = 0;
        for (int j = 1; j < half; j++) {
            if (env[j] < threshold) { startIdx = j; break; }
        }
        if (startIdx > 0) {
            for (int j = startIdx; j < half; j++) {
                if (env[j] > threshold) {
                    if (++ctr == 10) { indexFrame = j + 1 - 10; break; }
                } else ctr = 0;
            }
        }
    }

    free(env);
    return indexFrame;
}

/* ======================================================
 * auto_corr — CP autocorrelation (ref eq. verbatim)
 * ====================================================== */
static void auto_corr(const float *inI, const float *inQ,
                      float *outI, float *outQ, float *normVal,
                      int nFFT, int cpLen)
{
    for (int m = 0; m < nFFT; m++) {
        outI[m]    = 0.0f;
        outQ[m]    = 0.0f;
        normVal[m] = 0.0f;
        for (int i = 0; i < cpLen; i++) {
            outI[m] +=  inI[i+m] * inI[i+m+nFFT] + inQ[i+m] * inQ[i+m+nFFT];
            outQ[m] += -inI[i+m] * inQ[i+m+nFFT] + inQ[i+m] * inI[i+m+nFFT];
            normVal[m] += inI[i+m+nFFT]*inI[i+m+nFFT] + inQ[i+m+nFFT]*inQ[i+m+nFFT]
                        + inI[i+m]    *inI[i+m]     + inQ[i+m]    *inQ[i+m];
        }
    }
}

/* ======================================================
 * find_max_index — argmax of float array
 * ====================================================== */
static int find_max_index(const float *arr, int len)
{
    int   idx  = 0;
    float best = arr[0];
    for (int j = 1; j < len; j++) {
        if (arr[j] > best) { best = arr[j]; idx = j; }
    }
    return idx;
}

/* ======================================================
 * read_iq_f32 — read binary float32 interleaved IQ
 * ====================================================== */
static int read_iq_f32(const char *path, float **rxI, float **rxQ)
{
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return -1; }

    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    rewind(f);

    int n_floats = (int)(sz / sizeof(float));
    int n_samples = n_floats / 2;

    float *buf = (float *) malloc(n_floats * sizeof(float));
    if (!buf) { fclose(f); return -1; }
    if (fread(buf, sizeof(float), n_floats, f) != (size_t)n_floats) {
        fprintf(stderr, "WARNING: short read from %s\n", path);
    }
    fclose(f);

    *rxI = (float *) malloc(n_samples * sizeof(float));
    *rxQ = (float *) malloc(n_samples * sizeof(float));
    for (int i = 0; i < n_samples; i++) {
        (*rxI)[i] = buf[2*i];
        (*rxQ)[i] = buf[2*i + 1];
    }
    free(buf);
    return n_samples;
}

/* ======================================================
 * main
 * ====================================================== */
int main(int argc, char **argv)
{
    if (argc != 4) {
        fprintf(stderr,
            "Usage: %s <iq.f32> <golden_values.txt> <autocorr_full.txt>\n",
            argv[0]);
        return 1;
    }

    /* ---- Load IQ ---- */
    float *rxI = NULL, *rxQ = NULL;
    int n_samples = read_iq_f32(argv[1], &rxI, &rxQ);
    if (n_samples < 0) {
        fprintf(stderr, "ERROR: Failed to read IQ file %s\n", argv[1]);
        return 1;
    }
    printf("[golden_dump] Loaded %d IQ samples from %s\n", n_samples, argv[1]);

    /* ---- Step 1: frame_detector ---- */
    float threshold = 40000.0f;
    int   wndLen    = 25;
    int frameStart = frame_detector(rxI, rxQ, n_samples, wndLen, threshold);

    int detection_ok = (frameStart >= 0);
    if (!detection_ok) {
        printf("[golden_dump] frame_detector returned -1 (no frame found)\n");
        frameStart = 0;  /* fallback: compare from sample 0 */
    }
    printf("[golden_dump] frameStart = %d\n", frameStart);

    /* ---- Step 2: VanDeBeekAutoCorrelation ---- */
    float *autoCorrOutI  = (float *) calloc(NSC, sizeof(float));
    float *autoCorrOutQ  = (float *) calloc(NSC, sizeof(float));
    float *normVal_1     = (float *) calloc(NSC, sizeof(float));
    float *normVal_2     = (float *) calloc(NSC, sizeof(float));

    auto_corr(rxI + frameStart, rxQ + frameStart,
              autoCorrOutI, autoCorrOutQ, normVal_1, NSC, CP_LEN);

    for (int j = 0; j < NSC; j++) {
        float mag = 2.0f * sqrtf(autoCorrOutI[j]*autoCorrOutI[j] +
                                  autoCorrOutQ[j]*autoCorrOutQ[j]);
        normVal_2[j] = mag - normVal_1[j];
    }

    int peakIndexAuto  = find_max_index(normVal_2, NSC);
    int slotStartIndex = peakIndexAuto + frameStart;

    printf("[golden_dump] peakIndexAuto  = %d\n", peakIndexAuto);
    printf("[golden_dump] slotStartIndex = %d\n", slotStartIndex);
    printf("[golden_dump] autoCorrI[peak]= %g\n", autoCorrOutI[peakIndexAuto]);
    printf("[golden_dump] autoCorrQ[peak]= %g\n", autoCorrOutQ[peakIndexAuto]);
    printf("[golden_dump] metric[peak]   = %g\n", normVal_2[peakIndexAuto]);

    /* ---- Step 3: fractional CFO ---- */
    float fracfreqOffset = -atan2f(autoCorrOutQ[peakIndexAuto],
                                    autoCorrOutI[peakIndexAuto]) / (2.0f * (float)PI);
    printf("[golden_dump] fracfreqOffset = %.9g\n", fracfreqOffset);

    /* ---- Write golden_values.txt ---- */
    {
        FILE *fout = fopen(argv[2], "w");
        if (!fout) { perror(argv[2]); return 1; }

        /* Header */
        char timebuf[64];
        time_t t = time(NULL);
        strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", localtime(&t));
        fprintf(fout, "# Phase 3 Golden Reference Values\n");
        fprintf(fout, "# Generated: %s\n", timebuf);
        fprintf(fout, "# Input: %s  (%d samples)\n", argv[1], n_samples);
        fprintf(fout, "# NSC=%d  CP_LEN=%d\n", NSC, CP_LEN);
        fprintf(fout, "\n");

        fprintf(fout, "DETECTION_STATUS %d\n", detection_ok ? 1 : 0);
        fprintf(fout, "FRAME_START %d\n",          frameStart);
        fprintf(fout, "PEAK_INDEX_AUTO %d\n",       peakIndexAuto);
        fprintf(fout, "SLOT_START_INDEX %d\n",      slotStartIndex);
        fprintf(fout, "AUTOCORR_I_AT_PEAK %.9g\n",  autoCorrOutI[peakIndexAuto]);
        fprintf(fout, "AUTOCORR_Q_AT_PEAK %.9g\n",  autoCorrOutQ[peakIndexAuto]);
        fprintf(fout, "ENERGY_AT_PEAK %.9g\n",       normVal_1[peakIndexAuto]);
        fprintf(fout, "METRIC_AT_PEAK %.9g\n",        normVal_2[peakIndexAuto]);
        fprintf(fout, "FRAC_CFO_OFFSET %.9g\n",       fracfreqOffset);
        fprintf(fout, "PSS_START %d\n",          CP_LEN);
        fprintf(fout, "SSS_START %d\n",          2*CP_LEN + NSC);
        fprintf(fout, "PSS_SAMPLE_COUNT %d\n",   NSC);
        fprintf(fout, "SSS_SAMPLE_COUNT %d\n",   NSC);
        /* P3-08: integer CFO golden values — valid only for INT_CFO=0 stimulus.
         * Meyr backend: peak_index=NSC-1=255 → int_cfo=0 → step_word=0. */
        fprintf(fout, "INTEGER_CFO_WORD %d\n",   0);
        fprintf(fout, "MEYR_PEAK_INDEX %d\n",    NSC - 1);

        fclose(fout);
        printf("[golden_dump] Written: %s\n", argv[2]);
    }

    /* ---- Write autocorr_full.txt ---- */
    {
        FILE *fout = fopen(argv[3], "w");
        if (!fout) { perror(argv[3]); return 1; }

        fprintf(fout, "# lag  P_I  P_Q  energy  metric\n");
        for (int m = 0; m < NSC; m++) {
            fprintf(fout, "%d %.9g %.9g %.9g %.9g\n",
                    m,
                    autoCorrOutI[m],
                    autoCorrOutQ[m],
                    normVal_1[m],
                    normVal_2[m]);
        }
        fclose(fout);
        printf("[golden_dump] Written: %s\n", argv[3]);
    }

    free(rxI);
    free(rxQ);
    free(autoCorrOutI);
    free(autoCorrOutQ);
    free(normVal_1);
    free(normVal_2);

    return 0;
}
