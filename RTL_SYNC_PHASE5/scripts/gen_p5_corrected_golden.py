#!/usr/bin/env python3
"""
gen_p5_corrected_golden.py — P5-CORRECTED (ISS-04) bit-exact gate.

Reads the nightly-TB captured frac IQ and M_AXIS IQ:
    sim_out/p5_07/nightly_frac.hex   (32-bit hex per line, {Q[15:0], I[15:0]})
    sim_out/p5_07/nightly_mout.hex   (same format)
Both files start with a `// K_TEST=<k> STEP_TEST=<step> dump_n=<n>` header.

Applies the C-equivalent NCO + rotator software model
(same arithmetic as nco_phase_gen.v + complex_mult_iq.v):
    step_word_u32 = STEP_TEST & 0xFFFFFFFF
    phase[n] = (n * step_word_u32) & 0xFFFFFFFF
    idx[n]   = phase[n] >> 24                        # 0..255
    cos, sin = round(32767 * cos/sin(2*pi*idx/256))
    I_out[n] = (I[n]*cos + Q[n]*sin) >> 15
    Q_out[n] = (Q[n]*cos - I[n]*sin) >> 15
    clamped to signed 16-bit.

Sweeps the rotator pipeline delay D ∈ [0, 24] and picks the alignment
that maximizes within-tolerance matches.

PASS criteria:
    - dump_n >= 256 (at least one slot's worth of samples)
    - >= 95% of (dump_n - 32 warmup - D) samples match within
      ±LSB_TOL per component (default LSB_TOL = 6)
    - At least one beat differs from frac by > 50 LSB (proves rotation
      actually happened, not identity).

Output: reports/p5_corrected/p5_corrected_gate.txt with one of
    P5_CORRECTED_GATE: PASS <stats>
    P5_CORRECTED_GATE: FAIL <reason>
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
FRAC_F = os.path.join(ROOT, "sim_out", "p5_07", "nightly_frac.hex")
MOUT_F = os.path.join(ROOT, "sim_out", "p5_07", "nightly_mout.hex")
GATE_F = os.path.join(ROOT, "reports", "p5_corrected", "p5_corrected_gate.txt")

WARMUP    = 32
D_MIN     = 0
D_MAX     = 24
LSB_TOL   = 6   # rotator pipeline + NCO ROM quantization noise headroom


def parse_hex_file(path):
    if not os.path.exists(path):
        return None, None, None
    k = None; step = None; n = None
    samples = []
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            if line.startswith("//"):
                # // K_TEST=<k> STEP_TEST=<step> dump_n=<n>
                parts = line.replace("=", " ").split()
                for i, p in enumerate(parts):
                    if p == "K_TEST" and i + 1 < len(parts):
                        k = int(parts[i + 1])
                    if p == "STEP_TEST" and i + 1 < len(parts):
                        step = int(parts[i + 1])
                    if p == "dump_n" and i + 1 < len(parts):
                        n = int(parts[i + 1])
                continue
            try:
                samples.append(int(line, 16))
            except ValueError:
                pass
    return k, step, samples


def split_iq(word):
    lo = word & 0xFFFF
    hi = (word >> 16) & 0xFFFF
    if lo & 0x8000:
        lo -= 0x10000
    if hi & 0x8000:
        hi -= 0x10000
    return lo, hi  # I, Q


def clamp16(v):
    if v > 32767: return 32767
    if v < -32768: return -32768
    return v


def nco_rotate(frac_samples, step_word_signed):
    """Mirror of nco_phase_gen + complex_mult_iq exactly."""
    step_u32 = step_word_signed & 0xFFFFFFFF
    out = []
    for n, w in enumerate(frac_samples):
        I_in, Q_in = split_iq(w)
        phase_u32 = (n * step_u32) & 0xFFFFFFFF
        idx = (phase_u32 >> 24) & 0xFF
        theta = 2.0 * math.pi * idx / 256.0
        cos_v = max(-32768, min(32767, int(math.floor(32767.0 * math.cos(theta) + 0.5))))
        sin_v = max(-32768, min(32767, int(math.floor(32767.0 * math.sin(theta) + 0.5))))
        I_out = clamp16((I_in * cos_v + Q_in * sin_v) >> 15)
        Q_out = clamp16((Q_in * cos_v - I_in * sin_v) >> 15)
        out.append((I_out, Q_out))
    return out


def write_gate(line):
    os.makedirs(os.path.dirname(GATE_F), exist_ok=True)
    with open(GATE_F, "w") as fh:
        fh.write(line + "\n")
    print(line)


def main():
    k1, step1, frac = parse_hex_file(FRAC_F)
    k2, step2, mout = parse_hex_file(MOUT_F)
    if frac is None or mout is None:
        write_gate("P5_CORRECTED_GATE: FAIL · missing capture file(s)")
        sys.exit(1)
    if k1 != k2 or step1 != step2:
        write_gate(f"P5_CORRECTED_GATE: FAIL · header mismatch K {k1}/{k2} STEP {step1}/{step2}")
        sys.exit(1)
    n = min(len(frac), len(mout))
    if n < 256:
        write_gate(f"P5_CORRECTED_GATE: FAIL · dump_n={n} < 256")
        sys.exit(1)

    expected = nco_rotate(frac[:n], step1)
    mout_iq = [split_iq(w) for w in mout[:n]]

    best_d = 0; best_match = -1
    for d in range(D_MIN, D_MAX + 1):
        m = 0
        for j in range(WARMUP, n - d):
            ei, eq = expected[j]
            mi, mq = mout_iq[j + d]
            if abs(mi - ei) <= LSB_TOL and abs(mq - eq) <= LSB_TOL:
                m += 1
        if m > best_match:
            best_match = m; best_d = d

    total = n - WARMUP - best_d
    if total <= 0:
        write_gate(f"P5_CORRECTED_GATE: FAIL · n={n} too short after warmup+D={best_d}")
        sys.exit(1)
    pct = (best_match * 100) // total

    # Sanity: prove rotation actually applied (not identity).
    diff_count = 0
    for j in range(WARMUP, min(n, WARMUP + 256)):
        fi, fq = split_iq(frac[j])
        mi, mq = mout_iq[j]
        if abs(mi - fi) > 50 or abs(mq - fq) > 50:
            diff_count += 1

    if pct < 95:
        write_gate(f"P5_CORRECTED_GATE: FAIL · {best_match}/{total} ({pct}%) within tol=±{LSB_TOL} LSB · D={best_d}")
        sys.exit(1)
    if diff_count < 50:
        write_gate(f"P5_CORRECTED_GATE: FAIL · only {diff_count}/256 beats differ from frac (identity rotation, not real)")
        sys.exit(1)

    write_gate(f"P5_CORRECTED_GATE: PASS · {best_match}/{total} ({pct}%) bit-exact ±{LSB_TOL} LSB · D_rot={best_d} · K={k1} step={step1}")


if __name__ == "__main__":
    main()
