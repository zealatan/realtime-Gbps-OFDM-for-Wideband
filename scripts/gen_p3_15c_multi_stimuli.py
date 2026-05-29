#!/usr/bin/env python3
"""
gen_p3_15c_multi_stimuli.py — P3-15C Multi-Stimulus Generator

Generates 5 stimulus files for Session D3 equivalence robustness testing.
Each stimulus is a 704-sample OFDM IQ vector with a different combination of:
  - Frame offset (pre_zeros)
  - Fractional CFO (eps_frac)
  - Signal amplitude (amplitude)
  - Random seed

Outputs per stimulus:
  golden/p3_15c_stimuli/<id>.f32        — binary float32 interleaved I Q ...
  golden/p3_15c_stimuli/<id>.mem        — hex, one 32-bit word: {Q[15:0], I[15:0]}
  golden/p3_15c_stimuli/<id>_meta.json  — expected golden values + parameters

Reference algorithm: mirrors golden_dump.c (same as gen_phase3_iq_stimulus.py).
"""

import numpy as np
import json
import os

# ── Constants matching golden_dump.c / RTL parameters ────────────────────────
NSC       = 256
CP_LEN    = 32
FRAME_LEN = 2 * (NSC + CP_LEN)  # 576
STIM_TOTAL = FRAME_LEN + 64 + 64  # 704 — pre + frame + post (baseline)

WND_LEN   = 25
THRESHOLD = 40000.0

# ── Stimulus table ─────────────────────────────────────────────────────────────
# id, pre_zeros, eps_frac, amplitude, seed
STIMULI = [
    ("stim_01",  64,  0.05, 3000, 0xC0FFEE),  # baseline
    ("stim_02",  32,  0.05, 3000, 0xC0FFEE),  # earlier frame
    ("stim_03",  64, -0.10, 3000, 0xC0FFEE),  # negative frac CFO
    ("stim_04",  64,  0.05, 1500, 0xC0FFEE),  # half power
    ("stim_05",  80,  0.20, 2000, 0xDEAD00),  # combined
]


# ── OFDM symbol builder ───────────────────────────────────────────────────────
def _make_ofdm_symbol(rng):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=NSC)
    td     = np.fft.ifft(table[angles])
    cp     = td[-CP_LEN:]
    return np.concatenate([cp, td])


# ── Frame assembly ─────────────────────────────────────────────────────────────
def gen_frame(pre_zeros, eps_frac, amplitude, seed):
    post_zeros = STIM_TOTAL - FRAME_LEN - pre_zeros
    rng  = np.random.default_rng(seed)
    sym1 = _make_ofdm_symbol(rng)
    sym2 = _make_ofdm_symbol(rng)
    frame = np.concatenate([
        np.zeros(pre_zeros,  dtype=np.complex128),
        sym1, sym2,
        np.zeros(post_zeros, dtype=np.complex128),
    ])
    sig   = np.concatenate([sym1, sym2])
    peak  = max(np.abs(sig.real).max(), np.abs(sig.imag).max())
    if peak > 0.0:
        frame = frame * (amplitude / peak)
    n     = np.arange(len(frame), dtype=np.float64)
    frame = frame * np.exp(1j * 2.0 * np.pi * eps_frac * n / NSC)
    return frame


# ── C-reference algorithms (mirrors golden_dump.c) ────────────────────────────
def _frame_detector(I, Q):
    half = len(I) // 2 + 10
    energy = I[:half + WND_LEN] ** 2 + Q[:half + WND_LEN] ** 2
    cum    = np.empty(half + WND_LEN + 1, dtype=np.float64)
    cum[0] = 0.0
    np.cumsum(energy, out=cum[1:])
    env = (cum[WND_LEN: WND_LEN + half] - cum[:half]) / WND_LEN

    if env[0] < THRESHOLD:
        ctr = 0
        for j in range(1, half):
            if env[j] > THRESHOLD:
                ctr += 1
                if ctr == 10:
                    return j + 1 - 10
            else:
                ctr = 0
    else:
        start_idx = 0
        for j in range(1, half):
            if env[j] < THRESHOLD:
                start_idx = j
                break
        if start_idx > 0:
            ctr = 0
            for j in range(start_idx, half):
                if env[j] > THRESHOLD:
                    ctr += 1
                    if ctr == 10:
                        return j + 1 - 10
                else:
                    ctr = 0
    return -1


def _auto_corr(I, Q):
    P_I = np.zeros(NSC, dtype=np.float64)
    P_Q = np.zeros(NSC, dtype=np.float64)
    E   = np.zeros(NSC, dtype=np.float64)
    for m in range(NSC):
        aI = I[m:m+CP_LEN]; aQ = Q[m:m+CP_LEN]
        bI = I[m+NSC:m+NSC+CP_LEN]; bQ = Q[m+NSC:m+NSC+CP_LEN]
        P_I[m] = float(np.sum(aI * bI + aQ * bQ))
        P_Q[m] = float(np.sum(-aI * bQ + aQ * bI))
        E[m]   = float(np.sum(aI**2 + aQ**2 + bI**2 + bQ**2))
    return P_I, P_Q, E


# ── Main ────────────────────────────────────────────────────────────────────────
def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    out_dir    = os.path.join(root, "golden", "p3_15c_stimuli")
    os.makedirs(out_dir, exist_ok=True)

    for (stim_id, pre_zeros, eps_frac, amplitude, seed) in STIMULI:
        post_zeros = STIM_TOTAL - FRAME_LEN - pre_zeros
        print(f"\n[gen] === {stim_id} ===")
        print(f"[gen] pre={pre_zeros}  post={post_zeros}  eps={eps_frac:+.3f}"
              f"  amp={amplitude}  seed=0x{seed:06X}")

        frame = gen_frame(pre_zeros, eps_frac, amplitude, seed)
        N = len(frame)
        assert N == STIM_TOTAL, f"Frame length {N} != {STIM_TOTAL}"
        I_f32 = frame.real.astype(np.float32)
        Q_f32 = frame.imag.astype(np.float32)

        # Write .f32
        f32_path = os.path.join(out_dir, f"{stim_id}.f32")
        iq_flat  = np.empty(2 * N, dtype=np.float32)
        iq_flat[0::2] = I_f32
        iq_flat[1::2] = Q_f32
        iq_flat.tofile(f32_path)
        print(f"[gen] Written {f32_path}")

        # Write .mem — {Q[15:0], I[15:0]} hex
        mem_path = os.path.join(out_dir, f"{stim_id}.mem")
        with open(mem_path, "w") as fmem:
            for i_f, q_f in zip(I_f32, Q_f32):
                i16 = int(max(-32768, min(32767, round(float(i_f))))) & 0xFFFF
                q16 = int(max(-32768, min(32767, round(float(q_f))))) & 0xFFFF
                fmem.write(f"{q16:04X}{i16:04X}\n")
        print(f"[gen] Written {mem_path}")

        # Run reference algorithms
        I64 = I_f32.astype(np.float64)
        Q64 = Q_f32.astype(np.float64)

        frame_start  = _frame_detector(I64, Q64)
        detection_ok = (frame_start >= 0)
        if not detection_ok:
            print(f"[gen] WARNING: frame_detector returned -1. Falling back to 0.")
            frame_start = 0
        print(f"[gen] frame_start={frame_start}  detection_ok={detection_ok}")

        P_I, P_Q, E = _auto_corr(I64[frame_start:], Q64[frame_start:])
        metric       = 2.0 * np.sqrt(P_I**2 + P_Q**2) - E
        peak_idx     = int(np.argmax(metric))
        slot_start   = peak_idx + frame_start
        frac_cfo_out = float(-np.arctan2(P_Q[peak_idx], P_I[peak_idx]) / (2.0 * np.pi))

        print(f"[gen] peak_lag={peak_idx}  slot_start={slot_start}"
              f"  frac_cfo={frac_cfo_out:.9g}")

        # Write _meta.json
        meta = {
            "stim_id"                      : stim_id,
            "nsamples_total"               : N,
            "pre_zeros"                    : pre_zeros,
            "post_zeros"                   : post_zeros,
            "nsc"                          : NSC,
            "cp_len"                       : CP_LEN,
            "frame_len"                    : FRAME_LEN,
            "eps_frac"                     : eps_frac,
            "integer_cfo"                  : 0,
            "amplitude_peak_per_component" : amplitude,
            "seed"                         : seed,
            "noise_snr"                    : "off",
            "expected_frame_start"         : frame_start,
            "expected_peak_index_auto"     : peak_idx,
            "expected_slot_start"          : slot_start,
            "expected_frac_cfo"            : frac_cfo_out,
            "expected_meyr_peak_index"     : NSC - 1,  # 255
            "expected_integer_cfo_word"    : 0,
            "detection_ok"                 : detection_ok,
        }
        meta_path = os.path.join(out_dir, f"{stim_id}_meta.json")
        with open(meta_path, "w") as fj:
            json.dump(meta, fj, indent=2)
            fj.write("\n")
        print(f"[gen] Written {meta_path}")

    print(f"\n[gen] Done. {len(STIMULI)} stimuli in {out_dir}")


if __name__ == "__main__":
    main()
