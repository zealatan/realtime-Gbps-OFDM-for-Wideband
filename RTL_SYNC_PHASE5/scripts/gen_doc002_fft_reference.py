#!/usr/bin/env python3
"""
gen_doc002_fft_reference.py  —  DOC-002 FFT value gate reference generator

Generates stimulus and golden-reference files for the RTL fft256_xilinx_wrapper
behavioral DFT stub (USE_BEHAVIORAL_STUB=3).

Convention used by the RTL behavioral stub:
  - 256-pt DFT (same formula as numpy.fft.fft)
  - Unscaled (no 1/sqrt(256) normalization)
  - Natural bin order 0..255 (no fftshift)
  - I/Q packing: {Im[15:0], Re[15:0]} as 32-bit words (Xilinx native)
  - Output clamped to int16 [-32768..32767] with round-to-nearest

Convention used by the C reference fft_without_rearrange():
  - FFTW forward DFT, natural order
  - Divided by sqrt(256) = 16
  NOTE: the behavioral stub is UNSCALED. The Xilinx IP applies 1/16 via
        SCALE_SCH=0xAA. The behavioral stub output will be 16x the C reference.

Three test vectors are generated:
  V0: Impulse  — I[0]=1000, Q[0]=0, rest zero.
      Expected: all 256 bins = 1000+0j (Re=1000, Im=0 for all bins).
  V1: Tone     — complex exponential at bin k0=7, amplitude ~16384.
      I[n] = round(16384 * cos(2pi*7*n/256))
      Q[n] = round(16384 * sin(2pi*7*n/256))
      Expected: FFT[7] = 256*16384+0j, FFT[k!=7] = 0  (up to rounding).
  V2: PN random — 256 samples, PRNG seed=0xCAFE, values in [-1000, 1000].

Output files (all in vectors/doc002/):
  vN_stim.hex   — 256 lines, each "IIIIIIII" hex32 = {Im[15:0],Re[15:0]}
  vN_golden.csv — 256 lines, each "k,Re,Im"
  doc002_golden.json — all three vectors combined for Python compare script

Usage:
  python3 scripts/gen_doc002_fft_reference.py
"""

import numpy as np
import json, os, sys

OUT_DIR = os.path.join(os.path.dirname(__file__), '..', 'vectors', 'doc002')
os.makedirs(OUT_DIR, exist_ok=True)

FFT_LEN = 256
INT16_MAX = 32767
INT16_MIN = -32768

def clamp16(v):
    return max(INT16_MIN, min(INT16_MAX, int(round(v))))

def pack32(re_i16, im_i16):
    """Pack as {Im[15:0], Re[15:0]} 32-bit word (Xilinx/RTL convention)."""
    re_u = re_i16 & 0xFFFF
    im_u = im_i16 & 0xFFFF
    return (im_u << 16) | re_u

def compute_reference_fft(stim_re, stim_im):
    """
    Compute unscaled 256-pt DFT, matching RTL behavioral stub exactly.
    Inputs are int16 arrays of length FFT_LEN.
    Returns (out_re, out_im) int16 arrays.
    """
    x = np.array(stim_re, dtype=np.float64) + 1j * np.array(stim_im, dtype=np.float64)
    X = np.fft.fft(x)  # unscaled, natural order, standard sign convention
    out_re = [clamp16(v.real) for v in X]
    out_im = [clamp16(v.imag) for v in X]
    return out_re, out_im

def write_stim_hex(path, stim_re, stim_im):
    with open(path, 'w') as f:
        for i in range(FFT_LEN):
            word = pack32(stim_re[i], stim_im[i])
            f.write(f'{word:08X}\n')

def write_golden_csv(path, out_re, out_im):
    with open(path, 'w') as f:
        f.write('bin,Re,Im\n')
        for k in range(FFT_LEN):
            f.write(f'{k},{out_re[k]},{out_im[k]}\n')

# ── V0: Impulse ────────────────────────────────────────────────────────────────
stim0_re = [0] * FFT_LEN
stim0_im = [0] * FFT_LEN
stim0_re[0] = 1000

ref0_re, ref0_im = compute_reference_fft(stim0_re, stim0_im)

write_stim_hex(os.path.join(OUT_DIR, 'v0_stim.hex'), stim0_re, stim0_im)
write_golden_csv(os.path.join(OUT_DIR, 'v0_golden.csv'), ref0_re, ref0_im)

print('V0 (impulse):')
print(f'  FFT[0] = ({ref0_re[0]}, {ref0_im[0]})  expected (1000, 0)')
print(f'  FFT[128] = ({ref0_re[128]}, {ref0_im[128]})  expected (1000, 0)')
uniq_re = set(ref0_re); uniq_im = set(ref0_im)
print(f'  All Re identical: {len(uniq_re)==1}  All Im zero: {len(uniq_im)==1 and 0 in uniq_im}')

# ── V1: Complex tone at bin k0=7 ──────────────────────────────────────────────
K0 = 7
AMP = 16384
stim1_re = [clamp16(AMP * np.cos(2*np.pi*K0*n/FFT_LEN)) for n in range(FFT_LEN)]
stim1_im = [clamp16(AMP * np.sin(2*np.pi*K0*n/FFT_LEN)) for n in range(FFT_LEN)]

ref1_re, ref1_im = compute_reference_fft(stim1_re, stim1_im)

write_stim_hex(os.path.join(OUT_DIR, 'v1_stim.hex'), stim1_re, stim1_im)
write_golden_csv(os.path.join(OUT_DIR, 'v1_golden.csv'), ref1_re, ref1_im)

print(f'\nV1 (tone k0={K0}, amp={AMP}):')
print(f'  FFT[{K0}] = ({ref1_re[K0]}, {ref1_im[K0]})  expected ~({256*AMP}, 0) → clamped to (32767, 0)')
max_side = max(abs(ref1_re[k]) + abs(ref1_im[k]) for k in range(FFT_LEN) if k != K0)
print(f'  Max sidelobe (all other bins): {max_side}  (should be small, rounding only)')

# ── V2: Pseudo-random 256-sample complex IQ ───────────────────────────────────
rng = np.random.default_rng(0xCAFE)
stim2_re = [int(v) for v in rng.integers(-1000, 1001, FFT_LEN)]
stim2_im = [int(v) for v in rng.integers(-1000, 1001, FFT_LEN)]

ref2_re, ref2_im = compute_reference_fft(stim2_re, stim2_im)

write_stim_hex(os.path.join(OUT_DIR, 'v2_stim.hex'), stim2_re, stim2_im)
write_golden_csv(os.path.join(OUT_DIR, 'v2_golden.csv'), ref2_re, ref2_im)

print(f'\nV2 (pseudo-random, seed=0xCAFE):')
max_re = max(abs(v) for v in ref2_re)
max_im = max(abs(v) for v in ref2_im)
print(f'  Max |Re| = {max_re}  Max |Im| = {max_im}  (int16 range: 32767)')

# ── Combined JSON ─────────────────────────────────────────────────────────────
golden = {
    'convention': 'unscaled 256-pt DFT, natural order, no fftshift, Xilinx {Im,Re} packing',
    'note': 'C reference fft_without_rearrange() divides by sqrt(256)=16; behavioral stub is unscaled (matches numpy.fft.fft)',
    'vectors': [
        {'name': 'V0_impulse',   'stim_hex': 'v0_stim.hex', 'golden_csv': 'v0_golden.csv'},
        {'name': 'V1_tone_k7',   'stim_hex': 'v1_stim.hex', 'golden_csv': 'v1_golden.csv'},
        {'name': 'V2_pseudo_rng','stim_hex': 'v2_stim.hex', 'golden_csv': 'v2_golden.csv'},
    ]
}
with open(os.path.join(OUT_DIR, 'doc002_golden.json'), 'w') as f:
    json.dump(golden, f, indent=2)

print(f'\nOutput files written to {os.path.abspath(OUT_DIR)}/')
print('  v0_stim.hex  v0_golden.csv')
print('  v1_stim.hex  v1_golden.csv')
print('  v2_stim.hex  v2_golden.csv')
print('  doc002_golden.json')
