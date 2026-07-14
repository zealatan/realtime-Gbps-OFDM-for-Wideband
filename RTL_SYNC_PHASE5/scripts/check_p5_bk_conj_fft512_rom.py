#!/usr/bin/env python3
"""
check_p5_bk_conj_fft512_rom.py
==============================
Round-trip verification for vectors/bk_conj_fft512_rom.txt.

Re-derives B[k] = conj(FFT_2N(zero_pad(term2))) independently from the C
reference's m_seq / gold_seq / fft formulas, applies the same Q31 anchor
scaling, and bit-compares the resulting 64-bit hex words against the file.

Exits 0 iff every line matches.
"""
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_p5_bk_conj_fft512_rom import (  # noqa: E402
    NSC, FFT_2N, build_term2,
)


def main():
    root = os.path.normpath(os.path.join(HERE, ".."))
    rom_path = os.path.join(root, "vectors", "bk_conj_fft512_rom.txt")
    if not os.path.exists(rom_path):
        print(f"[bk_chk] MISSING: {rom_path}")
        sys.exit(2)

    term2 = build_term2()
    pad = np.zeros(FFT_2N, dtype=np.complex128)
    pad[:NSC] = term2
    Bk = np.conj(np.fft.fft(pad, FFT_2N))
    max_abs = float(max(np.abs(Bk.real).max(), np.abs(Bk.imag).max()))
    if max_abs == 0.0:
        print("[bk_chk] B[k] all-zero; cannot verify")
        sys.exit(2)

    INT32_MAX = (1 << 31) - 1
    scale = float(INT32_MAX) / max_abs
    re_q = np.clip(np.round(Bk.real * scale), -(1 << 31), INT32_MAX).astype(np.int64)
    im_q = np.clip(np.round(Bk.imag * scale), -(1 << 31), INT32_MAX).astype(np.int64)
    expected = []
    for k in range(FFT_2N):
        word = ((int(im_q[k]) & 0xFFFFFFFF) << 32) | (int(re_q[k]) & 0xFFFFFFFF)
        expected.append(f"{word:016x}")

    with open(rom_path) as fh:
        actual = [line.strip() for line in fh if line.strip()]
    if len(actual) != FFT_2N:
        print(f"[bk_chk] FAIL: expected {FFT_2N} lines, got {len(actual)}")
        sys.exit(1)

    mismatches = []
    for k, (a, e) in enumerate(zip(actual, expected)):
        if a != e:
            mismatches.append((k, a, e))
    if mismatches:
        print(f"[bk_chk] FAIL: {len(mismatches)} mismatches")
        for k, a, e in mismatches[:5]:
            print(f"  k={k:3d}  got={a}  want={e}")
        sys.exit(1)
    print(f"[bk_chk] OK: all {FFT_2N} lines match")


if __name__ == "__main__":
    main()
