#!/usr/bin/env python3
"""
gen_p3_15d_random_stimuli.py — P3-15D Random Stimulus Generator

Generates N random stimuli for Session D4 equivalence regression.

Randomized per case:
  pre_zeros (frame offset) : [32, 112]
  eps_frac  (frac CFO)     : [−0.38, +0.38]
  amplitude                : [800, 3500]
  k_int     (integer CFO)  : {−4,−2,−1,0,0,0,0,0,1,2,4}  (weighted 0)
  snr_db    (noise level)  : [25.0, 45.0] dB

Outputs per case (golden/p3_15d_stimuli/):
  case_NNN.f32        — binary float32 interleaved IQ (golden_dump input)
  case_NNN.mem        — hex Q15 {Q[15:0],I[15:0]} for $readmemh
  case_NNN_meta.json  — parameters + Python-computed golden values

Usage:
  python3 scripts/gen_p3_15d_random_stimuli.py [--n-cases N] [--seed S] [--out-dir DIR]
"""

import argparse
import json
import math
import os

import numpy as np

# ── Constants (must match RTL and golden_dump.c) ───────────────────────────────
NSC        = 256
CP_LEN     = 32
FRAME_LEN  = 2 * (NSC + CP_LEN)   # 576
STIM_TOTAL = 704                   # TB STIM_DEPTH; 128 slack split pre/post

WND_LEN   = 25
THRESHOLD = 40000.0

# k_int pool: 5×0 so ~45% zero, rest uniform over {±1,±2,±4}
K_INT_POOL = [-4, -2, -1, 0, 0, 0, 0, 0, 1, 2, 4]

# Note: expected_integer_cfo_word and expected_meyr_peak_index are always 0/255
# for the fft256_dual_symbol_frontend pipeline — it cannot recover integer CFO
# (phase cancels in cross-product).  k_int still applied to stimulus to diversify
# the IQ content and test pipeline robustness.
_PIPELINE_INT_CFO_ALWAYS_ZERO = True

BASE_SEED  = 0xD4BEEF


# ── OFDM symbol builder ────────────────────────────────────────────────────────
def _make_ofdm_symbol(rng):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=NSC)
    td     = np.fft.ifft(table[angles])
    return np.concatenate([td[-CP_LEN:], td])   # CP + body


# ── Frame assembly ─────────────────────────────────────────────────────────────
def _gen_frame(pre_zeros, eps_frac, k_int, amplitude, snr_db, rng):
    post_zeros = STIM_TOTAL - FRAME_LEN - pre_zeros
    assert post_zeros >= 0, f"pre_zeros={pre_zeros} leaves no room for post-guard"

    sym1  = _make_ofdm_symbol(rng)
    sym2  = _make_ofdm_symbol(rng)
    frame = np.concatenate([
        np.zeros(pre_zeros,  dtype=np.complex128),
        sym1, sym2,
        np.zeros(post_zeros, dtype=np.complex128),
    ])

    # Scale so signal peak = amplitude (in Q15 units)
    sig  = np.concatenate([sym1, sym2])
    peak = max(np.abs(sig.real).max(), np.abs(sig.imag).max())
    if peak > 0.0:
        frame = frame * (amplitude / peak)

    # Apply total CFO: frac (VanDeBeek-recoverable) + integer (Meyr-recoverable)
    n     = np.arange(STIM_TOTAL, dtype=np.float64)
    frame = frame * np.exp(1j * 2.0 * np.pi * (eps_frac + k_int) * n / NSC)

    # Add complex Gaussian noise to the FRAME REGION ONLY (not guard zeros).
    # Noise in pre/post-zero guard would cause float32 (golden_dump.c) and Q15 (RTL)
    # to cross the energy threshold at different samples, making comparison unreliable.
    # Noise in the OFDM frame region still exercises frac_cfo and IQ robustness.
    sig_start = pre_zeros
    sig_end   = pre_zeros + FRAME_LEN
    sig_power = float(np.mean(np.abs(frame[sig_start:sig_end])**2))
    noise_std = math.sqrt(sig_power / (2.0 * 10.0 ** (snr_db / 10.0)))
    noise_seg = rng.normal(0.0, noise_std, FRAME_LEN) + \
                1j * rng.normal(0.0, noise_std, FRAME_LEN)
    frame[sig_start:sig_end] += noise_seg
    return frame


# ── Python reference — mirrors golden_dump.c exactly ─────────────────────────
def _frame_detector(I, Q):
    half   = len(I) // 2 + 10
    energy = I[:half + WND_LEN] ** 2 + Q[:half + WND_LEN] ** 2
    cum    = np.empty(half + WND_LEN + 1, dtype=np.float64)
    cum[0] = 0.0
    np.cumsum(energy, out=cum[1:])
    env = (cum[WND_LEN:WND_LEN + half] - cum[:half]) / WND_LEN

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
    parser = argparse.ArgumentParser()
    parser.add_argument('--n-cases', type=int, default=100,
                        help="Number of random stimuli to generate (default 100)")
    parser.add_argument('--seed',    type=int, default=BASE_SEED,
                        help="Master RNG seed (default 0xD4BEEF)")
    parser.add_argument('--out-dir', type=str, default=None,
                        help="Output directory (default golden/p3_15d_stimuli)")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    root       = os.path.normpath(os.path.join(script_dir, ".."))
    out_dir    = args.out_dir or os.path.join(root, "golden", "p3_15d_stimuli")
    os.makedirs(out_dir, exist_ok=True)

    master_rng  = np.random.default_rng(args.seed)
    n_cases     = args.n_cases
    detect_fail = 0
    manifest    = []

    print(f"[gen] P3-15D: generating {n_cases} random stimuli → {out_dir}")
    print(f"[gen] Master seed: 0x{args.seed:X}")
    print()

    for idx in range(n_cases):
        case_id   = f"case_{idx:03d}"

        # Sample parameters
        pre_zeros = int(master_rng.integers(32, 113))          # [32, 112]
        eps_frac  = float(master_rng.uniform(-0.30, 0.30))    # ±0.30: stays in reliable range
        amplitude = float(master_rng.uniform(1500.0, 3500.0)) # ≥1500: well above VanDeBeek degenerate zone
        k_int     = int(master_rng.choice(K_INT_POOL))
        snr_db    = float(master_rng.uniform(25.0, 45.0))
        stim_seed = int(master_rng.integers(0, 2**31))

        # Generate with retries if Python frame detector fails
        frame        = None
        detection_ok = False
        frame_start  = pre_zeros   # fallback
        for attempt in range(20):
            rng_attempt = np.random.default_rng(stim_seed + attempt)
            f_candidate = _gen_frame(pre_zeros, eps_frac, k_int, amplitude, snr_db,
                                     rng_attempt)
            I64 = f_candidate.real.astype(np.float32).astype(np.float64)
            Q64 = f_candidate.imag.astype(np.float32).astype(np.float64)
            fs  = _frame_detector(I64, Q64)
            if fs >= 0:
                frame        = f_candidate
                frame_start  = fs
                detection_ok = True
                stim_seed    = stim_seed + attempt   # record final seed
                break
        if not detection_ok:
            print(f"[gen] WARNING {case_id}: all retries failed detection — "
                  f"pre={pre_zeros} amp={amplitude:.0f} snr={snr_db:.1f}dB")
            detect_fail += 1
            frame = f_candidate   # use last attempt anyway

        I_f32 = frame.real.astype(np.float32)
        Q_f32 = frame.imag.astype(np.float32)

        # Write .f32 (golden_dump input: binary float32 interleaved I Q ...)
        f32_path = os.path.join(out_dir, f"{case_id}.f32")
        iq_flat  = np.empty(2 * STIM_TOTAL, dtype=np.float32)
        iq_flat[0::2] = I_f32
        iq_flat[1::2] = Q_f32
        iq_flat.tofile(f32_path)

        # Write .mem ({Q[15:0],I[15:0]} hex for $readmemh)
        mem_path = os.path.join(out_dir, f"{case_id}.mem")
        with open(mem_path, "w") as fmem:
            for i_f, q_f in zip(I_f32, Q_f32):
                i16 = int(max(-32768, min(32767, round(float(i_f))))) & 0xFFFF
                q16 = int(max(-32768, min(32767, round(float(q_f))))) & 0xFFFF
                fmem.write(f"{q16:04X}{i16:04X}\n")

        # Compute Python reference on float32-cast samples (matches golden_dump.c input)
        I64 = I_f32.astype(np.float64)
        Q64 = Q_f32.astype(np.float64)

        if not detection_ok:
            fs = pre_zeros   # fallback keeps meta consistent

        P_I, P_Q, E    = _auto_corr(I64[frame_start:], Q64[frame_start:])
        metric         = 2.0 * np.sqrt(P_I**2 + P_Q**2) - E
        peak_idx       = int(np.argmax(metric))
        slot_start     = peak_idx + frame_start
        frac_cfo_ref   = float(-np.arctan2(P_Q[peak_idx], P_I[peak_idx]) / (2.0 * np.pi))
        # fft256_dual_symbol_frontend pipeline: integer CFO phase cancels in cross-product.
        # Expected RTL output is always meyr_peak=255, int_cfo=0, regardless of k_int.
        exp_meyr_peak  = 255
        exp_int_cfo    = 0

        meta = {
            "case_id"                   : case_id,
            "nsamples_total"            : STIM_TOTAL,
            "pre_zeros"                 : pre_zeros,
            "post_zeros"                : STIM_TOTAL - FRAME_LEN - pre_zeros,
            "nsc"                       : NSC,
            "cp_len"                    : CP_LEN,
            "frame_len"                 : FRAME_LEN,
            "eps_frac"                  : eps_frac,
            "integer_cfo"               : k_int,
            "amplitude"                 : amplitude,
            "snr_db"                    : snr_db,
            "stim_seed"                 : stim_seed,
            "detection_ok"              : detection_ok,
            "expected_frame_start"      : frame_start,
            "expected_peak_index_auto"  : peak_idx,
            "expected_slot_start"       : slot_start,
            "expected_frac_cfo"         : frac_cfo_ref,
            "expected_meyr_peak_index"  : exp_meyr_peak,   # always 255 for this pipeline
            "expected_integer_cfo_word" : exp_int_cfo,     # always 0 for this pipeline
        }
        meta_path = os.path.join(out_dir, f"{case_id}_meta.json")
        with open(meta_path, "w") as fj:
            json.dump(meta, fj, indent=2)
            fj.write("\n")

        manifest.append({
            "case_id"     : case_id,
            "pre_zeros"   : pre_zeros,
            "eps_frac"    : round(eps_frac, 6),
            "k_int"       : k_int,
            "amplitude"   : round(amplitude, 1),
            "snr_db"      : round(snr_db, 2),
            "detection_ok": detection_ok,
        })

        if idx % 10 == 0 or idx == n_cases - 1:
            print(f"[gen] {case_id}: pre={pre_zeros:3d}  eps={eps_frac:+.3f}"
                  f"  k={k_int:+d}  amp={amplitude:6.0f}  snr={snr_db:5.1f}dB"
                  f"  detect={'OK' if detection_ok else 'FAIL'}")

    manifest_path = os.path.join(out_dir, "manifest.json")
    with open(manifest_path, "w") as fj:
        json.dump(manifest, fj, indent=2)
        fj.write("\n")

    print()
    print(f"[gen] Done. {n_cases} stimuli → {out_dir}")
    print(f"[gen] Detection failures (Python ref): {detect_fail}/{n_cases}")
    if detect_fail:
        print("[gen] WARNING: detection-failed cases will likely fail D4-2 metadata check")


if __name__ == "__main__":
    main()
