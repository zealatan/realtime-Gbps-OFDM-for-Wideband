#!/usr/bin/env python3
"""Generate fused interp_fft coefficient ROM for rx_ch_est.v.

interp_fft (receiver.c) = 32-pt IFFT of the 32 pilot-H values into the low 32
time taps (taps 32..255 = 0), then a 256-pt forward FFT. Because the tap
vector is zero outside [0:32], the whole operation is LINEAR in the 32 pilot-H
inputs and collapses to a fixed 256x32 complex matrix W:

    H_fft[k] = sum_{m=0..31} W[k][m] * H_pilot[m]
    W = DFT256[:, 0:32] @ (IDFT32 / 32)

W is quantised to CW fractional bits (18-bit signed). Verified vs golden
hest.hex: max abs err 2.236 LSB (= golden's own float->Q15 rounding noise).
ROM line = {Wi[17:0], Wr[17:0]} (36 bits, 9 hex), bin-major (k outer, m inner).
"""
import numpy as np, os
NP, NSC, CW = 32, 256, 16
n = np.arange(NP)
IDFT = np.exp(1j*2*np.pi*np.outer(n, np.arange(NP))/NP)/NP
k = np.arange(NSC)
DFT = np.exp(-1j*2*np.pi*np.outer(k, n)/NSC)
W = DFT @ IDFT
Wr = np.round(W.real*(1 << CW)).astype(np.int64)
Wi = np.round(W.imag*(1 << CW)).astype(np.int64)
tc = lambda v, b=18: int(v) & ((1 << b)-1)
out = os.path.join(os.path.dirname(__file__), "..", "rtl", "rx_ch_est_rom", "ce_interp_W.hex")
with open(out, "w") as f:
    for kk in range(NSC):
        for m in range(NP):
            f.write("%09x\n" % ((tc(Wi[kk, m]) << 18) | tc(Wr[kk, m])))
print("wrote", out, NSC*NP, "lines; CW=%d Wr[%d,%d] Wi[%d,%d]" %
      (CW, Wr.min(), Wr.max(), Wi.min(), Wi.max()))
