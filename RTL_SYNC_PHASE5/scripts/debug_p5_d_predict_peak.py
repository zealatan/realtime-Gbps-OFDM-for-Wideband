#!/usr/bin/env python3
"""Offline pipeline emulator for debugging P5-D peak prediction."""
import os, sys, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_p5_bk_conj_fft512_rom import NSC, FFT_2N, build_term2

def load_mem(path, n_lines):
    out = np.zeros(n_lines, dtype=np.complex128)
    with open(path) as fh:
        for i, line in enumerate(fh):
            if i >= n_lines: break
            w = int(line.strip(), 16)
            lo = w & 0xFFFF; hi = (w >> 16) & 0xFFFF
            if lo & 0x8000: lo -= 0x10000
            if hi & 0x8000: hi -= 0x10000
            out[i] = lo + 1j*hi
    return out

def emulate(mem_path):
    s = load_mem(mem_path, 2*NSC)
    pss = s[:NSC]; sss = s[NSC:]
    # FFT_N (no normalization)
    Sp = np.fft.fft(pss, NSC); Ss = np.fft.fft(sss, NSC)
    # A[k] = SSS * conj(PSS) (matches meyr_FFT_ak_dut)
    A = Ss * np.conj(Sp)
    # zero-pad to 2N
    Az = np.zeros(FFT_2N, dtype=np.complex128); Az[:NSC] = A
    # FFT_2N
    Fa = np.fft.fft(Az, FFT_2N)
    # ROM = conj(FFT_2N(zpad(term2_ref)))
    term2 = build_term2()
    t2z = np.zeros(FFT_2N, dtype=np.complex128); t2z[:NSC] = term2
    B = np.conj(np.fft.fft(t2z, FFT_2N))
    R = Fa * B
    # IFFT_2N
    out = np.fft.ifft(R, FFT_2N)
    power = np.abs(out)**2
    # Exclude Nyquist bin N
    mask = np.ones(FFT_2N, bool); mask[NSC] = False
    idx = np.argmax(power * mask)
    return idx, power

if __name__ == "__main__":
    cases = [("kp00",0),("kp01",1),("km01",-1),("kp02",2),("km02",-2),
             ("kp04",4),("km04",-4),("kp08",8),("km08",-8)]
    for tag, k in cases:
        idx, p = emulate(f"vectors/p5_d/p5_d_{tag}.mem")
        cfo = idx if idx < NSC else idx - FFT_2N
        # show top 5 bins
        top5 = np.argsort(p)[-5:][::-1]
        print(f"{tag} k_int={k:+d}  peak_idx={idx:3d} cfo={cfo:+d}  top5={top5.tolist()}  power_ratio={p[idx]/p[0]:.2f}")
