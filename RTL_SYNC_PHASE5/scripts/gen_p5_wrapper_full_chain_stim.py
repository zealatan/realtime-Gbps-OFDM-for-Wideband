#!/usr/bin/env python3
"""
gen_p5_wrapper_full_chain_stim.py
==================================
Generate B[k]-matched FULL-CHAIN time-domain stimulus for the wrapper TB
(p5_d_continuous_wrapper_tb.sv). Reuses gen_p5_d_stimulus.py's PSS_td and
SSS_td (receiver.c m_seq / gold_seq based), prepends CP_LEN samples to each,
concatenates [PSS_CP | PSS | SSS_CP | SSS] = 576 samples for the sync region,
then appends 12 random-QPSK OFDM data symbols (CP + IDFT) to fill the full
14-symbol slot, padded with PRE_ZEROS=64 + POST_ZEROS=64.

Layout per file (2026-06-19 spec bump — NUM_DATA_BLOCKS 5 -> 12):
    [zeros(64)]
    [PSS_CP(32)] [PSS_body(256)]                   sync sym 0
    [SSS_CP(32)] [SSS_body(256)]                   sync sym 1
    [DATA_CP(32)] [DATA_body(256)]  x 12           data sym 0..11
    [zeros(64)]
    -> 64 + 2*288 + 12*288 + 64 = 64 + 4032 + 64 = 4160 samples total
       (slot itself = 14 * 288 = 4032)

This produces stim that is sequence-matched with the B[k] ROM at
vectors/bk_conj_fft512_rom.txt over the sync region, so Meyr's IFFT
correlation peak lands at the spec-expected position (NOT the +30-bin offset
seen with the J1 random-QPSK stim from gen_p3_21a_cfo_sweep_vectors.py).

Output: golden/p5_wrapper_fullchain/
    fc_k{tag}.mem    -- Q15 IQ hex, 4160 samples ({im[15:0], re[15:0]})
    manifest.json    -- per-case expected values:
                          k_int, frame_start, peak_index_auto,
                          slot_start_approx, frac_cfo, int_cfo_word

ISS-26 closure: with this stim, Step 2 wrapper-level absolute k_int decode
becomes exact (no bias) and the cold-start warmup workaround can be removed.

Reference math (CFO is continuous across the whole 4160-sample frame):
    frame[n] = base[n] * exp(j * 2*pi * k_int * n / NSC)    for n in [0, 4159]
    PSS body samples Meyr sees at abs idx 96..351
    -> DFT( PSS_td * exp(j*2pi*k_int*n/NSC) ) = DFT(PSS_td) shifted by k_int
    -> Meyr peak at bin k_int (cyclic), int_cfo decoded = k_int
"""

import json
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from gen_p5_d_stimulus import (   # noqa: E402
    NSC, CP_LEN, TARGET_PEAK,
    build_pss_sss_td,
)

# Frame geometry: 14 OFDM symbols (2 sync + 12 data) with CP, padded.
# (2026-06-19 spec bump: NUM_DATA_BLOCKS 5 -> 12.)
SYM_LEN     = NSC + CP_LEN        # 288 samples per OFDM symbol incl. CP
NUM_SYNC    = 2                   # PSS + SSS
NUM_DATA    = 12                  # was 5 (pre 2026-06-19); spec change
NUM_SYMBOLS = NUM_SYNC + NUM_DATA # 14
FRAME_LEN   = NUM_SYMBOLS * SYM_LEN     # 4032 (was 576)
SYNC_LEN    = NUM_SYNC * SYM_LEN        # 576 (PSS_CP|PSS|SSS_CP|SSS)
PRE_ZEROS   = 64
POST_ZEROS  = 64
TOTAL_LEN   = PRE_ZEROS + FRAME_LEN + POST_ZEROS    # 4160

# Random data-symbol generator (separate stream so PSS/SSS stay deterministic
# and identical to the legacy 576-sample build).
DATA_SEED   = 0xDA7A_0019

# k_int sweep. Same range as the p5_d unit test; wrapper TB picks 5
# representative cases from this set.
K_INT_SWEEP = [-8, -4, -2, -1, 0, +1, +2, +4, +8]

# Wrapper-level expected metrics (constant across cases when only k_int varies).
# frame_detector finds PSS CP via autocorrelation:
#   first CP sample at abs idx PRE_ZEROS = 64; CP correlation rises gradually
#   over the WINDOW_LEN=25 averaging window; meta-derived first-above-threshold
#   sample is around 41 for the phase3_iq_stimulus golden vector (which has
#   identical PRE_ZEROS).
EXPECTED_FRAME_START = 41   # +/- 2
EXPECTED_PEAK_AUTO   = 23   # frac_peak_lag, constant
EXPECTED_SLOT_START  = EXPECTED_FRAME_START + EXPECTED_PEAK_AUTO   # 64


def _make_data_symbol(rng):
    """Random QPSK + IDFT + CP, mirroring Agent A's baseline data-symbol gen."""
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j],
                      dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=NSC)
    td     = np.fft.ifft(table[angles])
    cp     = td[-CP_LEN:]
    return np.concatenate([cp, td])


def build_base_frame_td():
    """Construct the 4160-sample base frame (no CFO).

    Layout:
        [zeros(64)]
        [PSS_CP(32)] [PSS_body(256)]                   sync sym 0
        [SSS_CP(32)] [SSS_body(256)]                   sync sym 1
        [DATA_CP(32)] [DATA_body(256)]  x 12           data sym 0..11
        [zeros(64)]
    Total slot (sync + data) = 14 * 288 = 4032 samples.
    Total file = 64 + 4032 + 64 = 4160 samples.
    """
    PSS_td, SSS_td = build_pss_sss_td()   # 256 complex samples each
    assert len(PSS_td) == NSC, f"PSS_td len {len(PSS_td)} != {NSC}"
    assert len(SSS_td) == NSC, f"SSS_td len {len(SSS_td)} != {NSC}"

    pss_cp = PSS_td[-CP_LEN:]
    sss_cp = SSS_td[-CP_LEN:]

    # Data symbols: random QPSK, deterministic seed for reproducibility.
    rng       = np.random.default_rng(DATA_SEED)
    data_syms = [_make_data_symbol(rng) for _ in range(NUM_DATA)]

    # Scale random-QPSK data symbols so their per-sample magnitude is comparable
    # to PSS/SSS_td. PSS/SSS body comes from c_idft normalized by 1/sqrt(N),
    # whereas numpy.fft.ifft scales by 1/N. Match their RMS so the data tail
    # neither swamps nor sits well below the sync region.
    pss_rms  = float(np.sqrt(np.mean(np.abs(PSS_td) ** 2)))
    data_rms = float(np.sqrt(np.mean(np.abs(np.concatenate(data_syms)) ** 2)))
    if data_rms > 0:
        gain = pss_rms / data_rms
        data_syms = [d * gain for d in data_syms]

    frame = np.concatenate([
        np.zeros(PRE_ZEROS, dtype=np.complex128),
        pss_cp, PSS_td,
        sss_cp, SSS_td,
        *data_syms,
        np.zeros(POST_ZEROS, dtype=np.complex128),
    ])
    assert len(frame) == TOTAL_LEN, f"frame {len(frame)} != {TOTAL_LEN}"
    return frame


def apply_cfo(frame, k_int):
    """Multiply by exp(j * 2*pi * k_int * n / NSC) for n in [0, TOTAL_LEN-1]."""
    n = np.arange(len(frame), dtype=np.float64)
    return frame * np.exp(1j * 2.0 * np.pi * k_int * n / NSC)


def quantize_q15(frame, scale):
    qi = np.clip(np.round(frame.real * scale), -32768, 32767).astype(np.int32)
    qq = np.clip(np.round(frame.imag * scale), -32768, 32767).astype(np.int32)
    return qi, qq


def int_cfo_step_word(k_int):
    """RTL convention: step_word = (-k_int) << 24, 32-bit two's complement."""
    raw = (-k_int) << 24
    if raw >= (1 << 31):
        raw -= (1 << 32)
    return raw


def main():
    root    = os.path.normpath(os.path.join(HERE, ".."))
    out_dir = os.path.join(root, "golden", "p5_wrapper_fullchain")
    os.makedirs(out_dir, exist_ok=True)

    base = build_base_frame_td()
    peak = max(float(np.abs(base.real).max()),
               float(np.abs(base.imag).max()))
    scale = TARGET_PEAK / peak if peak > 0 else 1.0
    print(f"[p5_fc] base peak={peak:.4f}  scale={scale:.4f}  "
          f"-> Q15 target peak={TARGET_PEAK}")

    manifest = {
        "generator": "scripts/gen_p5_wrapper_full_chain_stim.py",
        "purpose":   "B[k]-matched full-chain stim for wrapper TB (ISS-26 fix)",
        "date":      "2026-06-19",
        "spec_change": (
            "NUM_DATA_BLOCKS 5 -> 12: slot is now 2 sync + 12 data = 14 OFDM "
            "symbols. Per-file length 704 -> 4160 samples; full M_AXIS "
            "output_count is now 4032 beats. Sync-region landmarks unchanged."
        ),
        "params": {
            "NSC": NSC, "CP_LEN": CP_LEN,
            "SYM_LEN":     SYM_LEN,
            "NUM_SYNC":    NUM_SYNC,
            "NUM_DATA":    NUM_DATA,
            "NUM_SYMBOLS": NUM_SYMBOLS,
            "SYNC_LEN":    SYNC_LEN,
            "FRAME_LEN":   FRAME_LEN,
            "PRE_ZEROS":   PRE_ZEROS,
            "POST_ZEROS":  POST_ZEROS,
            "TOTAL_LEN":   TOTAL_LEN,
            "TARGET_PEAK": TARGET_PEAK,
            "Q15_scale":   scale,
            "DATA_SEED":   DATA_SEED,
        },
        "wrapper_expected_constants": {
            "frame_start_index_approx":   EXPECTED_FRAME_START,
            "peak_index_auto":            EXPECTED_PEAK_AUTO,
            "slot_start_index_approx":    EXPECTED_SLOT_START,
            "frac_cfo_q15":               0,
            "expected_output_count":      FRAME_LEN,
            "expected_tlast_beat":        FRAME_LEN - 1,
        },
        "tdata_format": "{im[15:0], re[15:0]}, 32b LSB-packed hex per AXI-S beat",
        "samples_per_file": TOTAL_LEN,
        "cases": {},
    }

    for k_int in K_INT_SWEEP:
        tag = f"kp{k_int}" if k_int >= 0 else f"km{abs(k_int)}"
        fname = f"fc_{tag}.mem"
        fpath = os.path.join(out_dir, fname)

        rx = apply_cfo(base, k_int)
        qi, qq = quantize_q15(rx, scale)

        lines = []
        for n in range(TOTAL_LEN):
            word = ((int(qq[n]) & 0xFFFF) << 16) | (int(qi[n]) & 0xFFFF)
            lines.append(f"{word:08x}")
        with open(fpath, "w") as fh:
            fh.write("\n".join(lines) + "\n")

        step = int_cfo_step_word(k_int)
        manifest["cases"][tag] = {
            "k_int": int(k_int),
            "file":  os.path.relpath(fpath, root),
            "expected_k_int":      int(k_int),
            "expected_int_cfo_word": int(step),
        }
        print(f"  k={k_int:+3d}  step_word=0x{step & 0xFFFFFFFF:08x}  -> {fname}")

    mpath = os.path.join(out_dir, "manifest.json")
    with open(mpath, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"\n[p5_fc] wrote {len(K_INT_SWEEP)} cases + manifest.json to {out_dir}")


if __name__ == "__main__":
    main()
