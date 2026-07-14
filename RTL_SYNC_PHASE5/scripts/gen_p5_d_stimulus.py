#!/usr/bin/env python3
"""
gen_p5_d_stimulus.py
====================
Generate PSS+SSS time-domain stimulus for the new meyr_cfo_top unit sim,
derived from the C reference's transmit-side sequence chain.

Pipeline (mirrors ref/transmitter.c):
    mU_freq  [j+CP_LEN]  = m_seq[j]    (for j in sync window, else 0)
    PSS_td   [n]         = idft(mU_freq[CP_LEN..CP_LEN+NSC-1], NSC)
    goldU_freq[j+CP_LEN] = gold_seq[j]
    SSS_td   [n]         = idft(goldU_freq[CP_LEN..CP_LEN+NSC-1], NSC)

For a CFO of k_int (subcarriers):
    PSS_rx[n] = PSS_td[n] * exp(j*2*pi*k_int*n/NSC)
    SSS_rx[n] = SSS_td[n] * exp(j*2*pi*k_int*(n+NSC)/NSC)
              = SSS_td[n] * exp(j*2*pi*k_int*n/NSC)   (since k_int*NSC/NSC integer)

Output:
  vectors/p5_d/p5_d_k{tag}.mem   - Q15 {im[15:0], re[15:0]} packed hex,
                                   512 lines per file (256 PSS + 256 SSS)
  vectors/p5_d/manifest.json     - per-case expected peak_idx + cfo_int
"""

import json
import os
import sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_p5_bk_conj_fft512_rom import (  # noqa: E402
    NSC, CP_LEN, SEQ_LEN, SYNC_START, NID_1, NID_2,
    m_seq, gold_seq,
)

# k_int sweep — bounded to |k_int| <= 16 for the Level-1 unit check; the
# core's signed decode handles up to N-1 in either direction.
K_INT_SWEEP = list(range(-8, 9))
TARGET_PEAK = 16384  # Q15 target peak (well below the 32767 saturation point).
N2 = 2 * NSC


def c_idft(in_I, in_Q):
    """Mirror of ref/signal_processing_common.c::idft.

    out[i] = (1/sqrt(N)) * sum_j in[j] * exp(+j*2*pi*i*j/N)
    """
    N = len(in_I)
    inC = in_I + 1j * in_Q
    n = np.arange(N)
    W = np.exp(1j * 2 * np.pi * np.outer(n, n) / N)
    out = (W @ inC) / np.sqrt(N)
    return out


def build_pss_sss_td():
    """Compute reference (no-CFO) PSS_td and SSS_td of length NSC samples."""
    mU_freq_I = np.zeros(CP_LEN + NSC, dtype=np.float64)
    mU_freq_Q = np.zeros(CP_LEN + NSC, dtype=np.float64)
    gU_freq_I = np.zeros(CP_LEN + NSC, dtype=np.float64)
    gU_freq_Q = np.zeros(CP_LEN + NSC, dtype=np.float64)

    base = SYNC_START + CP_LEN
    mI, mQ = m_seq(SEQ_LEN, NID_2)
    gI, gQ = gold_seq(SEQ_LEN, NID_1, NID_2)
    mU_freq_I[base : base + SEQ_LEN] = mI
    mU_freq_Q[base : base + SEQ_LEN] = mQ
    gU_freq_I[base : base + SEQ_LEN] = gI
    gU_freq_Q[base : base + SEQ_LEN] = gQ

    PSS_td = c_idft(mU_freq_I[CP_LEN : CP_LEN + NSC],
                    mU_freq_Q[CP_LEN : CP_LEN + NSC])
    SSS_td = c_idft(gU_freq_I[CP_LEN : CP_LEN + NSC],
                    gU_freq_Q[CP_LEN : CP_LEN + NSC])
    return PSS_td, SSS_td


def apply_cfo(td, k_int, n_offset=0):
    n = np.arange(len(td)) + n_offset
    rot = np.exp(1j * 2 * np.pi * k_int * n / NSC)
    return td * rot


def quantize_q15(signal, scale):
    qi = np.clip(np.round(signal.real * scale), -32768, 32767).astype(np.int32)
    qq = np.clip(np.round(signal.imag * scale), -32768, 32767).astype(np.int32)
    return qi, qq


def expected_peak_idx(k_int):
    """Natural-ordered IFFT peak (per new core decode):
        k_int=0       -> bin 0 (DC)
        k_int=+k > 0  -> bin k
        k_int=-k < 0  -> bin 2N + k_int  (= 2N - k)
    Nyquist bin (N) is excluded by the meyr_ifft_peak_dut guard.
    """
    return k_int % N2


def expected_cfo_int(peak_idx):
    return peak_idx if peak_idx < NSC else peak_idx - N2


def main():
    root = os.path.normpath(os.path.join(HERE, ".."))
    out_dir = os.path.join(root, "vectors", "p5_d")
    os.makedirs(out_dir, exist_ok=True)

    PSS_td_ref, SSS_td_ref = build_pss_sss_td()
    peak_ref = max(float(np.abs(PSS_td_ref.real).max()),
                   float(np.abs(PSS_td_ref.imag).max()),
                   float(np.abs(SSS_td_ref.real).max()),
                   float(np.abs(SSS_td_ref.imag).max()))
    scale = TARGET_PEAK / peak_ref if peak_ref > 0 else 1.0
    print(f"[p5_d] PSS_td peak={peak_ref:.4f}  Q15 scale={scale:.4f}  "
          f"target peak={TARGET_PEAK}")

    manifest = {
        "generator": "scripts/gen_p5_d_stimulus.py",
        "params": {
            "NSC": NSC, "CP_LEN": CP_LEN, "SEQ_LEN": SEQ_LEN,
            "SYNC_START": SYNC_START, "NID_1": NID_1, "NID_2": NID_2,
            "TARGET_PEAK": TARGET_PEAK, "Q15_scale": scale,
        },
        "tdata_format": "{im[15:0], re[15:0]} - matches meyr_cfo_top s_tdata",
        "samples_per_file": "256 PSS + 256 SSS = 512 lines",
        "cases": {},
    }

    for k_int in K_INT_SWEEP:
        tag = f"kp{k_int:02d}" if k_int >= 0 else f"km{abs(k_int):02d}"
        pss_rx = apply_cfo(PSS_td_ref, k_int, n_offset=0)
        # SSS is at sample offset NSC relative to PSS in the C reference;
        # exp(j*2*pi*k_int*(n+NSC)/NSC) = exp(j*2*pi*k_int*n/NSC) since
        # k_int is integer. Apply the same rotation.
        sss_rx = apply_cfo(SSS_td_ref, k_int, n_offset=0)

        pi_q, pq_q = quantize_q15(pss_rx, scale)
        si_q, sq_q = quantize_q15(sss_rx, scale)

        lines = []
        for n in range(NSC):
            word = ((int(pq_q[n]) & 0xFFFF) << 16) | (int(pi_q[n]) & 0xFFFF)
            lines.append(f"{word:08x}")
        for n in range(NSC):
            word = ((int(sq_q[n]) & 0xFFFF) << 16) | (int(si_q[n]) & 0xFFFF)
            lines.append(f"{word:08x}")
        fpath = os.path.join(out_dir, f"p5_d_{tag}.mem")
        with open(fpath, "w") as fh:
            fh.write("\n".join(lines) + "\n")

        peak_idx = expected_peak_idx(k_int)
        cfo_int = expected_cfo_int(peak_idx)
        manifest["cases"][tag] = {
            "k_int": int(k_int),
            "file": os.path.relpath(fpath, root),
            "expected_peak_idx": int(peak_idx),
            "expected_cfo_int": int(cfo_int),
        }
        print(f"[p5_d] {tag}: k_int={k_int:+d}  expect peak_idx={peak_idx}  "
              f"cfo_int={cfo_int:+d}  -> {fpath}")

    mpath = os.path.join(out_dir, "manifest.json")
    with open(mpath, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    print(f"[p5_d] Wrote manifest -> {mpath}")


if __name__ == "__main__":
    main()
