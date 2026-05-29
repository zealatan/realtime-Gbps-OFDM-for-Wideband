#!/usr/bin/env python3
"""
gen_p3_22a_channel_vectors.py — Session K / P3-22A Channel Robustness Vector Generator

Generates 15 channel-impaired versions of golden/phase3_iq_stimulus.mem in
golden/p3_22a/ and a companion manifest.json.

Test cases (15 total):

  AWGN (4):    SNR = 30, 20, 15, 10 dB
               awgn_snr30dB, awgn_snr20dB, awgn_snr15dB, awgn_snr10dB

  2-tap multipath (5):  delays 1, 4, 8, 16, 32 samples; gains [1.0, 0.5]
               mp2tap_d1 .. mp2tap_d32

  3-tap multipath (5):  delays 1, 4, 8, 16, 32 samples; gains [1.0, 0.5, 0.25]
               mp3tap_d1 .. mp3tap_d32

  Negative test (1):  2-tap delay=33 (> CP_LEN=32); expected ISI degradation
               neg_mp2tap_d33

SNR definition:
  E_signal = mean(I^2+Q^2) over non-zero signal samples [PRE_ZEROS..PRE_ZEROS+FRAME_LEN]
  sigma    = sqrt(E_signal / SNR_linear / 2)  [per I or Q component]
  Noise is added uniformly over all 704 samples.
  NOTE: at SNR <= ~20 dB the noise floor (2*sigma^2) exceeds the detection
  threshold of 40000, so frame detection may fail at 15 dB and 10 dB.
  This is a documented limitation of the fixed-threshold energy detector.

Multipath channel:
  y[n] = sum_i gains[i] * x[n - delays[i]]  (power-normalised: sum(gains[i]^2) = 1)
  Tap 0 always at delay=0 (main path).
"""

import numpy as np
import json
import os
import sys

# ── Project paths ─────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT       = os.path.normpath(os.path.join(SCRIPT_DIR, ".."))
GOLDEN_DIR = os.path.join(ROOT, "golden")
OUT_DIR    = os.path.join(ROOT, "golden", "p3_22a")

# ── Stimulus parameters (must match golden/phase3_iq_stimulus.mem) ─────────
PRE_ZEROS   = 64
FRAME_LEN   = 576   # 2*(NSC=256 + CP_LEN=32)
POST_ZEROS  = 64
N_TOTAL     = 704   # PRE + FRAME + POST
CP_LEN      = 32
THRESHOLD   = 40000  # frame detector threshold (same as TB)


# ── I/O helpers ───────────────────────────────────────────────────────────────

def load_mem(path):
    """Load .mem hex file → numpy complex128 array (int16 I/Q values)."""
    samples = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            w     = int(line, 16)
            i_raw = w & 0xFFFF
            q_raw = (w >> 16) & 0xFFFF
            # Two's-complement sign extension from 16 to Python int
            i16 = i_raw - 65536 if i_raw >= 32768 else i_raw
            q16 = q_raw - 65536 if q_raw >= 32768 else q_raw
            samples.append(float(i16) + 1j * float(q16))
    return np.array(samples, dtype=np.complex128)


def save_mem(samples, path):
    """Save complex array → .mem hex file.  Values clipped to signed int16."""
    with open(path, "w") as f:
        for s in samples:
            i16 = int(np.clip(round(float(s.real)), -32768, 32767)) & 0xFFFF
            q16 = int(np.clip(round(float(s.imag)), -32768, 32767)) & 0xFFFF
            f.write(f"{q16:04X}{i16:04X}\n")


# ── Channel models ─────────────────────────────────────────────────────────────

def add_awgn(clean, snr_db, seed):
    """Add AWGN. SNR measured over signal-bearing samples [PRE:PRE+FRAME_LEN]."""
    sig_region = clean[PRE_ZEROS : PRE_ZEROS + FRAME_LEN]
    sig_power  = float(np.mean(np.abs(sig_region) ** 2))
    snr_lin    = 10.0 ** (snr_db / 10.0)
    # sigma per I or Q component
    sigma      = float(np.sqrt(sig_power / snr_lin / 2.0))

    rng   = np.random.default_rng(seed)
    noise = sigma * (rng.standard_normal(N_TOTAL) +
                     1j * rng.standard_normal(N_TOTAL))
    noisy = clean + noise

    noise_floor_est = 2.0 * sigma * sigma  # E[I^2+Q^2] in noise-only region
    return noisy, {
        "snr_db"              : snr_db,
        "sig_power_per_sample": round(sig_power, 1),
        "sigma_per_component" : round(sigma, 2),
        "noise_floor_est"     : round(noise_floor_est, 1),
        "threshold_tb"        : THRESHOLD,
        "noise_exceeds_threshold": noise_floor_est > THRESHOLD,
        "detection_risk"      : "high" if noise_floor_est > THRESHOLD else "low",
        "seed"                : seed,
    }


def apply_multipath(clean, delays, gains):
    """Apply FIR multipath channel, power-normalised.  delays[0] must be 0."""
    out = np.zeros(N_TOTAL, dtype=np.complex128)
    for d, g in zip(delays, gains):
        if d == 0:
            out += g * clean
        elif 0 < d < N_TOTAL:
            out[d:] += g * clean[: N_TOTAL - d]
    # Power normalization: ensure total received power = transmitted power
    total_power = float(sum(g * g for g in gains))
    out /= float(np.sqrt(total_power))

    max_delay = int(max(delays))
    return out, {
        "taps"              : [{"delay": int(d), "gain": float(g)}
                               for d, g in zip(delays, gains)],
        "tap_count"         : len(delays),
        "max_delay_samples" : max_delay,
        "total_power_raw"   : round(total_power, 4),
        "cp_len"            : CP_LEN,
        "max_delay_vs_cp"   : f"{max_delay}/{CP_LEN}",
        "isi_expected"      : max_delay > CP_LEN,
    }


# ── Case generators ────────────────────────────────────────────────────────────

def make_awgn_case(clean, snr_db, seed, out_dir):
    name = f"awgn_snr{snr_db}dB"
    out, meta = add_awgn(clean, snr_db, seed)
    save_mem(out, os.path.join(out_dir, f"{name}.mem"))
    risk = meta["detection_risk"]
    flag = "** noise > threshold, detection may FAIL **" if meta["noise_exceeds_threshold"] else ""
    print(f"  {name}: sigma={meta['sigma_per_component']:.1f}  "
          f"noise_floor={meta['noise_floor_est']:.0f}  "
          f"risk={risk}  {flag}")
    return {
        "name"          : name,
        "channel"       : "awgn",
        "mem_file"      : f"golden/p3_22a/{name}.mem",
        "gate_required" : snr_db >= 20,
        "expected"      : ("CASE_PASS" if snr_db >= 20 else
                           "CASE_PARTIAL_PASS or CASE_FAIL (threshold limited)"),
        "meta"          : meta,
    }


def make_2tap_case(clean, delay, out_dir):
    name   = f"mp2tap_d{delay}"
    gains  = [1.0, 0.5]
    delays = [0, delay]
    out, meta = apply_multipath(clean, delays, gains)
    save_mem(out, os.path.join(out_dir, f"{name}.mem"))
    isi = " ** ISI expected (delay > CP_LEN) **" if meta["isi_expected"] else ""
    print(f"  {name}: delay={delay}  max_delay/CP={meta['max_delay_vs_cp']}"
          f"  isi={meta['isi_expected']}{isi}")
    return {
        "name"          : name,
        "channel"       : "multipath_2tap",
        "mem_file"      : f"golden/p3_22a/{name}.mem",
        "gate_required" : True,   # 2-tap all delays including CP boundary
        "expected"      : "CASE_PASS (delay <= CP_LEN)" if not meta["isi_expected"]
                          else "WARN or FAIL (delay > CP_LEN, ISI expected)",
        "meta"          : meta,
    }


def make_3tap_case(clean, delay, out_dir):
    name   = f"mp3tap_d{delay}"
    gains  = [1.0, 0.5, 0.25]
    delays = [0, delay, 2 * delay]
    out, meta = apply_multipath(clean, delays, gains)
    save_mem(out, os.path.join(out_dir, f"{name}.mem"))
    isi = " ** ISI (3rd tap beyond CP) **" if meta["isi_expected"] else ""
    print(f"  {name}: delays=[0,{delay},{2*delay}]  "
          f"max_delay/CP={meta['max_delay_vs_cp']}  isi={meta['isi_expected']}{isi}")
    # 3-tap: gate-required for delays 1..16 (max_delay <= CP_LEN=32);
    #        delay=32 has max_delay=64 > CP_LEN → soft / documented only
    return {
        "name"          : name,
        "channel"       : "multipath_3tap",
        "mem_file"      : f"golden/p3_22a/{name}.mem",
        "gate_required" : (2 * delay) <= CP_LEN,
        "expected"      : ("CASE_PASS" if (2 * delay) <= CP_LEN else
                           "CASE_PARTIAL_PASS or CASE_FAIL (3rd tap > CP_LEN)"),
        "meta"          : meta,
    }


def make_negative_case(clean, out_dir):
    name   = "neg_mp2tap_d33"
    gains  = [1.0, 0.5]
    delays = [0, 33]
    out, meta = apply_multipath(clean, delays, gains)
    save_mem(out, os.path.join(out_dir, f"{name}.mem"))
    print(f"  {name}: delay=33 > CP_LEN=32  NEGATIVE TEST — ISI expected")
    return {
        "name"          : name,
        "channel"       : "negative_test",
        "mem_file"      : f"golden/p3_22a/{name}.mem",
        "gate_required" : False,
        "expected"      : "WARN or FAIL — delay=33 > CP_LEN=32, ISI degrades pipeline",
        "meta"          : meta,
    }


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    golden_path = os.path.join(GOLDEN_DIR, "phase3_iq_stimulus.mem")
    if not os.path.exists(golden_path):
        print(f"ERROR: {golden_path} not found.", file=sys.stderr)
        print("       Run: python3 scripts/gen_phase3_iq_stimulus.py", file=sys.stderr)
        sys.exit(1)

    clean = load_mem(golden_path)
    if len(clean) != N_TOTAL:
        print(f"ERROR: expected {N_TOTAL} samples, got {len(clean)}", file=sys.stderr)
        sys.exit(1)

    sig_region = clean[PRE_ZEROS : PRE_ZEROS + FRAME_LEN]
    sig_power  = float(np.mean(np.abs(sig_region) ** 2))
    sig_rms    = float(np.sqrt(sig_power / 2.0))
    print(f"[gen] Loaded {N_TOTAL} samples from {golden_path}")
    print(f"[gen] Signal power (non-zero region): {sig_power:.1f}  "
          f"RMS per component: {sig_rms:.1f}")
    print(f"[gen] Frame detection threshold: {THRESHOLD}")
    print(f"[gen] Noise floor exceeds threshold below "
          f"SNR = {10.0 * np.log10(sig_power / THRESHOLD / 2):.1f} dB (approximate)")
    print()

    cases = []

    # AWGN
    print("[gen] AWGN cases:")
    for snr, seed in [(30, 100), (20, 200), (15, 300), (10, 400)]:
        cases.append(make_awgn_case(clean, snr, seed, OUT_DIR))

    print()

    # 2-tap multipath
    print("[gen] 2-tap multipath cases:")
    for delay in [1, 4, 8, 16, 32]:
        cases.append(make_2tap_case(clean, delay, OUT_DIR))

    print()

    # 3-tap multipath
    print("[gen] 3-tap multipath cases:")
    for delay in [1, 4, 8, 16, 32]:
        cases.append(make_3tap_case(clean, delay, OUT_DIR))

    print()

    # Negative test
    print("[gen] Negative test case:")
    cases.append(make_negative_case(clean, OUT_DIR))

    # Manifest
    n_required = sum(1 for c in cases if c["gate_required"])
    manifest = {
        "generator"             : "scripts/gen_p3_22a_channel_vectors.py",
        "session"               : "K / P3-22A",
        "n_cases"               : len(cases),
        "n_required_for_gate"   : n_required,
        "golden_stimulus"       : "golden/phase3_iq_stimulus.mem",
        "output_dir"            : "golden/p3_22a",
        "signal_power_est"      : round(sig_power, 1),
        "n_total_samples"       : N_TOTAL,
        "pre_zeros"             : PRE_ZEROS,
        "frame_len"             : FRAME_LEN,
        "cp_len"                : CP_LEN,
        "threshold_tb"          : THRESHOLD,
        "channel_gate_pass_req" : "All gate_required cases must show CASE_PASS",
        "cases"                 : cases,
    }
    manifest_path = os.path.join(OUT_DIR, "manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print()
    print(f"[gen] {len(cases)} .mem files written to golden/p3_22a/")
    print(f"[gen] {n_required} cases gate-required for CHANNEL_GATE: PASS")
    print(f"[gen] Manifest → {manifest_path}")


if __name__ == "__main__":
    main()
