#!/usr/bin/env python3
"""
gen_p5_bk_conj_fft512_rom.py
============================
Generate the B[k] ROM for the new FFT-correlation Meyr core (meyr_cfo_top).

Derivation (mirrors carrierFreqOffsetEstMeyr + fft_correlation_Meyr in
ref/receiver.c and the m_seq/gold_seq generators in
ref/signal_processing_common.c, line-for-line):

    term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])      for j in [0, NSC-1]
    B[k]     = conj( FFT_{2N}( zero_pad(term2, 2N) ) )    for k in [0, 2N-1]

Notes on equivalence with the C reference:

  * m_seq / gold_seq write into mU/goldU only at indices
    [syncSigStartIndex+CP_LEN, syncSigStartIndex+CP_LEN+seqLen-1] = [87, 213].
    All other indices are zero (calloc), so term2[j] is zero outside
    j in [55, 181] (= [87..213] minus CP_LEN).
  * mU and goldU are real-valued (Q components = 0), so term2 is real.
    term2.I[j] = mU.I[j+CP_LEN] * goldU.I[j+CP_LEN]
    term2.Q[j] = 0
  * sqrt(NSC/seqLen) scale lives in both m_seq and gold_seq; the product
    therefore has an (NSC/seqLen) factor. The argmax does not depend on
    this scale -- we renormalize to fill 32-bit signed range.

ROM word packing (matches meyr_Rm_dut: complex_mult_32 b_i = rom_q[31:0],
b_q = rom_q[63:32]):

    word = {Im[31:0], Re[31:0]}   (signed two's complement, 32 bits each)

Output: vectors/bk_conj_fft512_rom.txt   (2N = 512 lines, 16 hex digits each)
Debug : golden/bk_conj_fft512_debug.json
"""

import json
import os
import sys

import numpy as np

# --- Constants pinned to the C reference --------------------------------------
# ref/pluto.h
NSC        = 256
CP_LEN     = 32
# ref/signal_processing_common.c::init_sig_pro defaults
SEQ_LEN    = 127
SYNC_START = 55
NID_1      = 170
NID_2      = 2
# ref/receiver.c::fft_correlation_Meyr operates on NSC*2 = 512 points
FFT_2N     = 2 * NSC


def m_seq(length, Nid_2):
    """Mirror of ref/signal_processing_common.c::m_seq.

    Returns (I, Q) arrays of given length. Real-valued (Q = 0).
    """
    x_init = [1, 1, 1, 0, 1, 1, 0]
    x = [0] * length
    for i in range(length):
        if i < 7:
            x[i] = x_init[i]
        else:
            x[i] = (x[i - 3] + x[i - 7]) % 2
    scale = np.sqrt(NSC / float(length))
    I = np.zeros(length, dtype=np.float64)
    Q = np.zeros(length, dtype=np.float64)
    for n in range(length):
        m = (n + 43 * Nid_2) % length
        I[n] = -(1 - 2 * x[m]) * scale  # note: leading minus matches C ref
    return I, Q


def gold_seq(length, Nid_1, Nid_2):
    """Mirror of ref/signal_processing_common.c::gold_seq."""
    x0_init = [0, 0, 0, 0, 0, 0, 1]
    x1_init = [0, 0, 0, 0, 0, 0, 1]
    x0 = [0] * length
    x1 = [0] * length
    for i in range(length):
        if i < 7:
            x0[i] = x0_init[i]
            x1[i] = x1_init[i]
        else:
            x0[i] = (x0[i - 3] + x0[i - 7]) % 2
            x1[i] = (x1[i - 6] + x1[i - 7]) % 2
    scale = np.sqrt(NSC / float(length))
    m0 = 15 * int(Nid_1 // 112) + 5 * Nid_2
    m1 = Nid_1 % 112
    I = np.zeros(length, dtype=np.float64)
    Q = np.zeros(length, dtype=np.float64)
    for n in range(length):
        I[n] = (1 - 2 * x0[(n + m0) % length]) * (1 - 2 * x1[(n + m1) % length]) * scale
    return I, Q


def build_term2():
    """Reproduce mU/goldU layout and compute term2[j] = mU * conj(goldU)."""
    # mU and goldU are calloc'd to symbols_per_block; only indices
    # [syncSigStartIndex+CP_LEN .. +seqLen-1] are filled by the sequence
    # generator. We model the slice that term2 actually reads:
    # mU[j+CP_LEN] for j in [0, NSC-1] -> mU[CP_LEN .. CP_LEN+NSC-1].
    sym_block = max(CP_LEN + NSC, SYNC_START + CP_LEN + SEQ_LEN)
    mUI = np.zeros(sym_block, dtype=np.float64)
    mUQ = np.zeros(sym_block, dtype=np.float64)
    goldUI = np.zeros(sym_block, dtype=np.float64)
    goldUQ = np.zeros(sym_block, dtype=np.float64)

    base = SYNC_START + CP_LEN
    mI, mQ = m_seq(SEQ_LEN, NID_2)
    gI, gQ = gold_seq(SEQ_LEN, NID_1, NID_2)
    mUI[base : base + SEQ_LEN] = mI
    mUQ[base : base + SEQ_LEN] = mQ
    goldUI[base : base + SEQ_LEN] = gI
    goldUQ[base : base + SEQ_LEN] = gQ

    # term2[j] = mU[j+CP_LEN] * conj(goldU[j+CP_LEN])  for j in [0, NSC-1]
    j = np.arange(NSC)
    mU = mUI[j + CP_LEN] + 1j * mUQ[j + CP_LEN]
    gU = goldUI[j + CP_LEN] + 1j * goldUQ[j + CP_LEN]
    term2 = mU * np.conj(gU)
    return term2


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(script_dir, ".."))
    vec_dir = os.path.join(root, "vectors")
    gold_dir = os.path.join(root, "golden")
    os.makedirs(vec_dir, exist_ok=True)
    os.makedirs(gold_dir, exist_ok=True)
    rom_path = os.path.join(vec_dir, "bk_conj_fft512_rom.txt")
    dbg_path = os.path.join(gold_dir, "bk_conj_fft512_debug.json")

    term2 = build_term2()
    nz_idx = np.flatnonzero(np.abs(term2) > 0)
    print(f"[bk_rom] term2 nonzero indices: {int(nz_idx.min())}..{int(nz_idx.max())} "
          f"({nz_idx.size} of {NSC})")
    print(f"[bk_rom] term2 max |Re|: {np.abs(term2.real).max():.6f}  "
          f"max |Im|: {np.abs(term2.imag).max():.6f}")

    # Zero-pad to 2N and FFT (numpy unnormalized DFT == fftwf forward DFT).
    term2_zp = np.zeros(FFT_2N, dtype=np.complex128)
    term2_zp[:NSC] = term2
    Bk_unconj = np.fft.fft(term2_zp, FFT_2N)
    Bk = np.conj(Bk_unconj)

    max_abs = float(max(np.abs(Bk.real).max(), np.abs(Bk.imag).max()))
    if max_abs == 0.0:
        print("[bk_rom] ERROR: B[k] is all-zero - check sequence parameters")
        sys.exit(1)

    # Quantize to Q31 using the largest |Re or Im| as the full-scale anchor.
    INT32_MAX = (1 << 31) - 1
    scale = float(INT32_MAX) / max_abs
    re_q = np.clip(np.round(Bk.real * scale), -(1 << 31), INT32_MAX).astype(np.int64)
    im_q = np.clip(np.round(Bk.imag * scale), -(1 << 31), INT32_MAX).astype(np.int64)

    # Pack {Im[31:0], Re[31:0]} as 64-bit two's complement hex.
    lines = []
    for k in range(FFT_2N):
        re_u = int(re_q[k]) & 0xFFFFFFFF
        im_u = int(im_q[k]) & 0xFFFFFFFF
        word = (im_u << 32) | re_u
        lines.append(f"{word:016x}")
    with open(rom_path, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"[bk_rom] Wrote {FFT_2N} 64-bit words to {rom_path}")

    # Sanity: zero-CFO peak should land at the autocorrelation peak.
    # term1 (PSS-side) is real symmetric in the noise-free case; correlation
    # peak lands at the all-zero shift -> IFFT bin 0 (DC). We don't simulate
    # term1 here; only verify B[k] structure and packing.
    debug = {
        "generator": "scripts/gen_p5_bk_conj_fft512_rom.py",
        "derivation": "Python mirror of C m_seq/gold_seq + term2 + FFT_2N conj",
        "parameters": {
            "NSC": NSC,
            "CP_LEN": CP_LEN,
            "SEQ_LEN": SEQ_LEN,
            "SYNC_START": SYNC_START,
            "NID_1": NID_1,
            "NID_2": NID_2,
            "FFT_2N": FFT_2N,
        },
        "rom_word_format": "{Im[31:0], Re[31:0]} - matches meyr_Rm_dut "
                            "(complex_mult_32: b_i=rom_q[31:0], b_q=rom_q[63:32])",
        "q_format": "Signed Q31, full-scale anchor = max(|Re|,|Im|) of B[k]",
        "scale": scale,
        "max_abs_unscaled": max_abs,
        "rom_path": rom_path,
        "term2_nonzero_range": [int(nz_idx.min()), int(nz_idx.max())],
        "first_words": [lines[0], lines[1], lines[2]],
        "last_words": [lines[-3], lines[-2], lines[-1]],
        "method_note": (
            "PYTHON_MIRROR. The C m_seq/gold_seq generators are LFSR + BPSK "
            "with deterministic outputs; the Python here is a line-for-line "
            "mirror. If a future regen requires bit-identity with FFTW float "
            "rounding, switch to instrumented-C dump (script docstring)."
        ),
    }
    with open(dbg_path, "w") as fh:
        json.dump(debug, fh, indent=2)
        fh.write("\n")
    print(f"[bk_rom] Wrote debug -> {dbg_path}")
    print("[bk_rom] Done.")


if __name__ == "__main__":
    main()
