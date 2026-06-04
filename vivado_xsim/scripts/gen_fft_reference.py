#!/usr/bin/env python3
"""gen_fft_reference.py — Generate reference FFT vectors for xsim comparison.

Scale factor: 1/16 (SCALE_SCH=0xAA, 4 of 8 xfft 9.1 stages divide by 2).
Output format: vivado_xsim/vectors/fft_ref_case_<N>.csv

Cases match xsim_fft_ip_value_protocol_tb.sv:
  0 — Impulse at n=0 (A=32767)
  1 — Complex tone k=1  (A=1024)
  2 — Real cosine k=17  (A=1024)
  3 — DC constant       (A=1024)
  4 — 32-sample periodic comb (square wave ±512)
  5 — Zero input
"""

import os
import math
import csv

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

FFT_LEN    = 256
IQ_WIDTH   = 16
# fft256_xilinx_r8.vhd behavioral model scales by 1/N = 1/256 regardless of SCALE_SCH.
# (All 8 radix-2 stages of the 256-pt FFT each divide by 2.)
SCALE      = 256.0       # 1/N = 1/256
MAX_INT16  = (1 << (IQ_WIDTH - 1)) - 1  # 32767
MIN_INT16  = -(1 << (IQ_WIDTH - 1))     # -32768
OUT_DIR    = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "..", "vectors")


def to_int16(v):
    """Saturate and round float to int16."""
    r = int(round(v))
    if r > MAX_INT16: r = MAX_INT16
    if r < MIN_INT16: r = MIN_INT16
    return r


def scaled_fft(time_re, time_im):
    """Compute DFT scaled by 1/16, returning lists of int16 [re, im] per bin."""
    N = len(time_re)
    if HAS_NUMPY:
        x = np.array(time_re, dtype=np.float64) + 1j * np.array(time_im, dtype=np.float64)
        X = np.fft.fft(x) / SCALE
    else:
        # Pure Python DFT fallback (slow but correct)
        X = []
        for k in range(N):
            s = complex(0.0, 0.0)
            for n in range(N):
                angle = -2.0 * math.pi * k * n / N
                s += (time_re[n] + 1j * time_im[n]) * complex(math.cos(angle), math.sin(angle))
            X.append(s / SCALE)
    result = []
    for v in X:
        result.append((to_int16(v.real), to_int16(v.imag)))
    return result


def write_case(case_num, time_re, time_im, freq_bins):
    os.makedirs(OUT_DIR, exist_ok=True)
    fname = os.path.join(OUT_DIR, f"fft_ref_case_{case_num}.csv")
    with open(fname, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["bin", "in_re", "in_im", "ref_re", "ref_im"])
        for k in range(FFT_LEN):
            writer.writerow([k, time_re[k], time_im[k], freq_bins[k][0], freq_bins[k][1]])
    print(f"  Written: {fname}")


def main():
    print(f"gen_fft_reference.py  (numpy={'YES' if HAS_NUMPY else 'NO (fallback DFT)'})")
    print(f"FFT_LEN={FFT_LEN}  SCALE={SCALE}  IQ_WIDTH={IQ_WIDTH}")
    print()

    # -----------------------------------------------------------------------
    # Case 0: Impulse at n=0, A=32767
    # -----------------------------------------------------------------------
    re = [0] * FFT_LEN; im = [0] * FFT_LEN
    re[0] = 32767
    bins = scaled_fft(re, im)
    write_case(0, re, im, bins)
    print(f"  Case 0 bin[0] expected ≈ ({32767//16}, 0) → got {bins[0]}")

    # -----------------------------------------------------------------------
    # Case 1: Complex tone k=1, A=1024
    # -----------------------------------------------------------------------
    A = 1024.0
    re = [int(round(A * math.cos(2*math.pi*1*n/FFT_LEN))) for n in range(FFT_LEN)]
    im = [int(round(A * math.sin(2*math.pi*1*n/FFT_LEN))) for n in range(FFT_LEN)]
    bins = scaled_fft(re, im)
    write_case(1, re, im, bins)
    print(f"  Case 1 bin[1] expected ≈ ({int(A*FFT_LEN//SCALE)}, 0) → got {bins[1]}")

    # -----------------------------------------------------------------------
    # Case 2: Real cosine k=17, A=1024
    # -----------------------------------------------------------------------
    A = 1024.0
    re = [int(round(A * math.cos(2*math.pi*17*n/FFT_LEN))) for n in range(FFT_LEN)]
    im = [0] * FFT_LEN
    bins = scaled_fft(re, im)
    write_case(2, re, im, bins)
    print(f"  Case 2 bin[17] expected ≈ ({int(A*FFT_LEN//2//SCALE)}, ...) → got {bins[17]}")

    # -----------------------------------------------------------------------
    # Case 3: DC constant, A=1024
    # -----------------------------------------------------------------------
    re = [1024] * FFT_LEN
    im = [0]   * FFT_LEN
    bins = scaled_fft(re, im)
    write_case(3, re, im, bins)
    print(f"  Case 3 bin[0] expected ≈ ({1024*FFT_LEN//SCALE:.0f}, 0) → got {bins[0]}")

    # -----------------------------------------------------------------------
    # Case 4: 32-sample periodic square wave ±512
    # -----------------------------------------------------------------------
    re = [512 if (n % 32) < 16 else -512 for n in range(FFT_LEN)]
    im = [0] * FFT_LEN
    bins = scaled_fft(re, im)
    write_case(4, re, im, bins)
    print(f"  Case 4 bin[0]={bins[0]}  bin[8]={bins[8]}  (DC=0 expected, bin 8 non-zero)")

    # -----------------------------------------------------------------------
    # Case 5: Zero input
    # -----------------------------------------------------------------------
    re = [0] * FFT_LEN
    im = [0] * FFT_LEN
    bins = scaled_fft(re, im)
    write_case(5, re, im, bins)
    print(f"  Case 5 all zeros: {all(b==(0,0) for b in bins)}")

    print("\nDone.  Reference vectors in:", os.path.abspath(OUT_DIR))


if __name__ == "__main__":
    main()
