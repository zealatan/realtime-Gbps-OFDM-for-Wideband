#!/usr/bin/env python3
"""
gen_rx_eq_div_stress.py
=======================
ROBUST stress-vector generator for the ZF complex divider rx_eq_complex_div.v.

The committed gate (rx_eq_div_xsim) only exercises an IDENTITY channel
(|H| ~= 1.0, i.e. H ~= 0x2000 in Q15 scale 5090.697374). The complex
reciprocal 1/|H|^2 is the highest-risk part of the datapath, and an
identity channel never stresses it. This generator produces N>=30 RANDOM
cases that span |H|^2 across the FULL dynamic range:

  * deep nulls  : |H| of 1-2 LSB (smallest non-zero |H|^2)
  * small |H|   : near the guard, large reciprocal -> output saturation
  * mid |H|     : ~ identity neighbourhood
  * large |H|   : |H| near full-scale int16/int18
  * H purely real, H purely imaginary
  * the |H|^2 == 0 guard case (expect output 0)

For each case the EXPECTED equalizer output is the EXACT zero-forcing
algorithm at the module's fixed-point scale:

      eq = round( RX * conj(H) / |H|^2 * S ),  saturated to int16
      (S = 5090.697374, the locked golden scale = SFIX/2^10)

This is the *true math* reference (real-valued division, then quantize),
NOT a re-implementation of the RTL's reciprocal -- so the TB genuinely
tests the divider against ground truth, including its reciprocal error.

A bit-faithful Python model of the RTL integer datapath is ALSO run here
as a secondary cross-check and to report the divider's reciprocal error
vs |H| magnitude before xsim even runs.

Outputs (into sim_out/rx_eq_div_stress/golden_in, consumed by the TB):
  rx_in.hex    : N lines, {Q[31:16],I[15:0]} RX bin            (Q15)
  h_in.hex     : N lines, {Q[31:16],I[15:0]} channel estimate  (Q15)
  eq_exp.hex   : N lines, {Q[31:16],I[15:0]} expected eq (ideal ZF)
  meta.txt     : per-case |H|, |H|^2, category, sat flag, guard flag
numpy only.
"""
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(ROOT, "sim_out", "rx_eq_div_stress", "golden_in")

# -------- locked module fixed-point constants (must match rx_eq_complex_div.v) --
SFIX   = 5212874         # round(5090.697374 * 2^10)
SSHIFT = 10
PMANT  = 18
S      = SFIX / (1 << SSHIFT)     # 5090.697...  exact module scale
HW     = 18              # channel width (sign-extended from 16 at the wrapper)
DW     = 16              # RX width
SCW    = 2 * HW + 1      # 37
SH_BIAS  = SCW - 31      # 6
FINAL_SH = SSHIFT + PMANT + 31 + SH_BIAS    # 65

LUT = [int(l, 16) for l in open(os.path.join(ROOT, "rtl",
                                "rx_equalizer_recip_lut.hex"))]

# At the wrapper, H arrives as a 16-bit field sign-extended to 18 bits, so the
# effective H range the DUT can ever see is signed int16 [-32768, 32767]. We
# therefore keep H within int16 to match the real datapath (the divider itself
# accepts 18-bit, but rx_equalizer.v only ever feeds it 16-bit-derived values).
H_MAX = 32767
R_MAX = 32767

# ----------------------------------------------------------------------
def sat16(v):
    return max(-32768, min(32767, int(v)))

# ----------------------------------------------------------------------
# EXACT zero-forcing reference at the module's fixed point (ground truth).
#   eq = round( RX*conj(H)/|H|^2 * S ),  int16 saturate; |H|^2==0 -> 0
# ----------------------------------------------------------------------
def ideal_zf(ri, rq, hi, hq):
    sc = hi * hi + hq * hq
    if sc == 0:
        return 0, 0, True   # guard
    numi = ri * hi + rq * hq
    numq = rq * hi - ri * hq
    ei = numi / sc * S
    eq = numq / sc * S
    sat = (ei > 32767 or ei < -32768 or eq > 32767 or eq < -32768)
    return sat16(round(ei)), sat16(round(eq)), sat

# ----------------------------------------------------------------------
# Bit-faithful model of the RTL integer divider (secondary cross-check).
# Mirrors rx_eq_complex_div.v stages S1..S9 exactly.
# ----------------------------------------------------------------------
def rtl_model(ri, rq, hi, hq):
    sc = hi * hi + hq * hq
    if sc == 0:
        return 0, 0, None
    numi = ri * hi + rq * hq
    numq = rq * hi - ri * hq
    n  = sc.bit_length()          # bitlen
    sh = 31 - n
    m  = (sc << sh) if sh >= 0 else (sc >> (-sh))
    addr = (m >> 23) & 0xFF
    r = LUT[addr - 128]           # Q18 seed
    # two Newton-Raphson iterations r <- r*(2 - m*r>>31) >> PMANT
    for _ in range(2):
        mr   = m * r
        xr   = mr >> 31
        corr = (1 << (PMANT + 1)) - xr
        r    = (r * corr) >> PMANT
    # r approximates 2^(PMANT+31)/m (Q-PMANT recip of mantissa m).
    # m = sc * 2^sh, so 1/sc = (r / 2^(PMANT+31)) * 2^sh  ->  effective recip:
    recip_eff = r * (2.0 ** (sh - PMANT - 31))   # ~ 1/sc
    nsi = numi * SFIX
    nsq = numq * SFIX
    ral = r << (sh + SH_BIAS)
    pi  = nsi * ral
    pq  = nsq * ral
    def rsh(v):                            # round-half-up, constant shift
        return (v + (1 << (FINAL_SH - 1))) >> FINAL_SH
    return sat16(rsh(pi)), sat16(rsh(pq)), recip_eff

# ----------------------------------------------------------------------
def pack(i, q):
    return f"{(((sat16(q) & 0xFFFF) << 16) | (sat16(i) & 0xFFFF)) & 0xFFFFFFFF:08X}"

# ----------------------------------------------------------------------
def build_cases():
    """Return list of (ri,rq,hi,hq,category)."""
    rng = np.random.default_rng(0xE057E55)
    cases = []

    def rnd_rx():
        return int(rng.integers(-32768, 32768)), int(rng.integers(-32768, 32768))

    # 1. GUARD: |H|^2 == 0  (expect output 0)
    cases.append((1234, -5678, 0, 0, "guard_H0"))
    cases.append((-32768, 32767, 0, 0, "guard_H0_extreme"))

    # 2. DEEP NULL: |H| = 1-2 LSB  -> smallest non-zero |H|^2
    cases.append((1000, -2000, 1, 0, "null_1lsb_real"))
    cases.append((1000, -2000, 0, 1, "null_1lsb_imag"))
    cases.append((500, 700, 1, 1, "null_1lsb_diag"))     # |H|^2 = 2
    cases.append((-300, 400, 2, -1, "null_2lsb"))        # |H|^2 = 5
    cases.append((100, 50, 1, -2, "null_2lsb_b"))        # |H|^2 = 5

    # 3. PURELY REAL H over a range of magnitudes
    for hmag in [3, 7, 31, 200, 1500, 8192, 32767]:
        ri, rq = rnd_rx()
        cases.append((ri, rq, hmag, 0, f"realH_{hmag}"))

    # 4. PURELY IMAGINARY H over a range of magnitudes
    for hmag in [3, 7, 31, 200, 1500, 8192, 32767]:
        ri, rq = rnd_rx()
        cases.append((ri, rq, 0, hmag, f"imagH_{hmag}"))

    # 5. LARGE |H| (near full scale, both components)
    cases.append((20000, -15000, 32767, 32767, "largeH_fullscale"))
    cases.append((-32768, 32767, 30000, -28000, "largeH_b"))
    cases.append((12345, 6789, 23170, 23170, "largeH_unit_diag"))  # |H|^2 ~ 2^30

    # 6. IDENTITY neighbourhood (|H| ~ 0x2000 = 8192, the only region the
    #    committed gate ever tested) for regression continuity.
    cases.append((4096, -8192, 8192, 0, "identity_real"))
    cases.append((5000, 3000, 5793, 5793, "identity_diag"))  # |H|~8192

    # 7. RANDOM full-range sweep of H with random RX, log-uniform |H| so the
    #    small-|H| (high-reciprocal) regime is well sampled.
    for _ in range(20):
        ri, rq = rnd_rx()
        # log-uniform magnitude in [1, 32767]
        mag = float(np.exp(rng.uniform(np.log(1.0), np.log(32767.0))))
        ang = rng.uniform(0, 2 * np.pi)
        hi = int(round(mag * np.cos(ang)))
        hq = int(round(mag * np.sin(ang)))
        hi = max(-H_MAX, min(H_MAX, hi))
        hq = max(-H_MAX, min(H_MAX, hq))
        if hi == 0 and hq == 0:
            hi = 1
        cases.append((ri, rq, hi, hq, "rand_loguniform"))

    # 7b. SMALL-|H| NON-SATURATING cases — the critical coverage gap.
    #     With int16 RX, small |H| forces output saturation, which MASKS the
    #     reciprocal error. Here we pair a small |H| with a proportionally
    #     small RX so the quotient lands mid-scale (in int16 range) and the
    #     reciprocal of a SMALL |H|^2 is exercised against ground truth with
    #     full LSB resolution. RX is scaled so |eq| ~ |RX|/|H|*S ~ a few k.
    for hmag in [1, 2, 3, 5, 8, 13, 21, 34, 55, 100, 250, 600, 1500, 4000]:
        # choose target |eq| ~ 4000 (well inside int16); |RX| = |eq|*|H|/S
        target_eq = 4000.0
        rx_mag = target_eq * hmag / S
        ang_h  = rng.uniform(0, 2 * np.pi)
        ang_r  = rng.uniform(0, 2 * np.pi)
        hi = int(round(hmag * np.cos(ang_h)))
        hq = int(round(hmag * np.sin(ang_h)))
        if hi == 0 and hq == 0:
            hi = hmag   # ensure non-zero |H| for tiny hmag rounding
        ri = int(round(rx_mag * np.cos(ang_r)))
        rq = int(round(rx_mag * np.sin(ang_r)))
        ri = max(-32768, min(32767, ri))
        rq = max(-32768, min(32767, rq))
        cases.append((ri, rq, hi, hq, f"smallH_nonsat_{hmag}"))

    # 7c. ROUNDING-BOUNDARY cases (mined from a 300k Monte-Carlo): these land
    #     on a half-LSB boundary where the RTL's round-half-UP differs from the
    #     reference round-half (banker's) by exactly 1 LSB -- the documented
    #     worst case. Including them makes xsim WITNESS a non-zero (1 LSB) error
    #     so the gate proves the comparator + tolerance are live (not trivially
    #     0). They span small and large |H|.
    for (ri, rq, hi, hq) in [
        (112, 35, 169, -23),
        (-13918, 19645, -19127, -16949),
        (-29982, -6721, -1639, 7970),
        (-4958, -15457, 3964, -19872),
        (78, 82, 120, -7),
        (1, -2, -5, -2),
    ]:
        cases.append((ri, rq, hi, hq, "round_boundary_1lsb"))

    # 8. Cases engineered to FORCE int16 saturation (small |H|, large RX):
    #    eq magnitude ~ |RX|/|H| * S  -> with |H| tiny this overflows.
    cases.append((32767, -32768, 3, 4, "sat_smallH_bigRX"))   # |H|^2=25
    cases.append((-32768, -32768, 5, 0, "sat_realH"))
    cases.append((32767, 32767, 0, 6, "sat_imagH"))

    return cases

# ----------------------------------------------------------------------
def main():
    os.makedirs(OUT, exist_ok=True)
    cases = build_cases()
    N = len(cases)

    rx_lines, h_lines, eq_lines, meta = [], [], [], []
    # accumulators for the reciprocal-error report
    rec_err_by_mag = []   # (|H|, rel_recip_err, rel_out_err)

    print(f"[stress] generating {N} cases")
    print(f"[stress] S={S:.6f}  SFIX={SFIX}  FINAL_SH={FINAL_SH}")
    print()
    print(f"{'#':>3} {'cat':<18} {'|H|':>9} {'|H|^2':>12} "
          f"{'exp(I,Q)':>16} {'rtlmodel(I,Q)':>16} {'sat':>4} {'recipRelErr':>12}")

    worst_rec = 0.0
    worst_rec_mag = None
    for n, (ri, rq, hi, hq, cat) in enumerate(cases):
        ei, eq, guard = ideal_zf(ri, rq, hi, hq)
        mi, mq, recip_eff = rtl_model(ri, rq, hi, hq)
        sc = hi * hi + hq * hq
        Hmag = np.sqrt(sc)

        if recip_eff is not None and sc != 0:
            rel_rec = abs(recip_eff - 1.0 / sc) / (1.0 / sc)
            if rel_rec > worst_rec:
                worst_rec = rel_rec
                worst_rec_mag = Hmag
            # relative output error of the bit-faithful RTL model vs ideal
            mag_exp = np.hypot(ei, eq)
            rel_out = (np.hypot(mi - ei, mq - eq) / mag_exp) if mag_exp > 0 else 0.0
            rec_err_by_mag.append((Hmag, rel_rec, rel_out, ei, eq, mi, mq))
            rec_str = f"{rel_rec:.2e}"
        else:
            rec_str = "guard"

        rx_lines.append(pack(ri, rq))
        h_lines.append(pack(hi, hq))
        eq_lines.append(pack(ei, eq))
        meta.append(f"{n} {cat} Hmag={Hmag:.2f} Hsq={sc} exp={ei},{eq} "
                    f"sat={'1' if (ei in (-32768,32767) or eq in (-32768,32767)) else '0'} "
                    f"guard={'1' if guard else '0'}")
        print(f"{n:>3} {cat:<18} {Hmag:>9.1f} {sc:>12} "
              f"{('%d,%d'%(ei,eq)):>16} {('%d,%d'%(mi,mq)):>16} "
              f"{'Y' if guard else ' ':>4} {rec_str:>12}")

    with open(os.path.join(OUT, "rx_in.hex"), "w") as f: f.write("\n".join(rx_lines) + "\n")
    with open(os.path.join(OUT, "h_in.hex"),  "w") as f: f.write("\n".join(h_lines)  + "\n")
    with open(os.path.join(OUT, "eq_exp.hex"),"w") as f: f.write("\n".join(eq_lines) + "\n")
    with open(os.path.join(OUT, "meta.txt"),  "w") as f: f.write("\n".join(meta) + "\n")
    with open(os.path.join(OUT, "ncases.txt"),"w") as f: f.write(f"{N}\n")

    # -------- reciprocal-error vs |H| report (Python pre-flight) --------
    print()
    print("=" * 78)
    print("RECIPROCAL ERROR vs |H| MAGNITUDE  (bit-faithful RTL model, pre-xsim)")
    print("=" * 78)
    arr = sorted(rec_err_by_mag, key=lambda t: t[0])
    print(f"  worst-case relative reciprocal error = {worst_rec:.3e} "
          f"at |H|={worst_rec_mag:.1f}")
    # bucket by |H| decade
    buckets = {}
    for Hmag, rel_rec, rel_out, *_ in arr:
        dec = int(np.floor(np.log10(max(Hmag, 1e-9))))
        buckets.setdefault(dec, []).append((rel_rec, rel_out))
    print(f"  {'|H| decade':>14} {'#':>3} {'max recipRelErr':>16} {'max outRelErr':>14}")
    for dec in sorted(buckets):
        b = buckets[dec]
        mr = max(x[0] for x in b); mo = max(x[1] for x in b)
        print(f"  10^{dec:<11d} {len(b):>3} {mr:>16.2e} {mo:>14.2e}")
    # -------- large Monte-Carlo statistical sweep (Python bit-faithful model) -
    montecarlo_sweep(300000)

    print()
    print(f"[stress] wrote {N} vectors to {OUT}")
    return N, worst_rec


def montecarlo_sweep(NMC):
    """Run NMC random cases through the bit-faithful RTL model and compare to
    the exact ZF reference. Reports worst-case LSB error and worst-case
    reciprocal error bucketed by |H| magnitude, so accuracy-vs-small-|H| is
    quantified far beyond the handful of hand-picked xsim vectors."""
    rng = np.random.default_rng(0x5717E5)
    worst = 0; worst_case = None
    worst_rec = 0.0; worst_rec_mag = None
    nguard = 0; nck = 0; nsat = 0; guard_violation = 0
    bucket_worst = {}
    for t in range(NMC):
        if t % 2 == 0:
            # matched-magnitude small/large |H| -> mid-scale output (probe recip)
            hmag = float(np.exp(rng.uniform(np.log(1.0), np.log(32767.0))))
            ah = rng.uniform(0, 2*np.pi)
            hi = int(round(hmag*np.cos(ah))); hq = int(round(hmag*np.sin(ah)))
            if hi == 0 and hq == 0: hi = 1
            teq = rng.uniform(500, 6000); rxm = teq*np.hypot(hi, hq)/S
            ar = rng.uniform(0, 2*np.pi)
            ri = int(round(rxm*np.cos(ar))); rq = int(round(rxm*np.sin(ar)))
            ri = max(-32768, min(32767, ri)); rq = max(-32768, min(32767, rq))
        else:
            ri = int(rng.integers(-32768, 32768)); rq = int(rng.integers(-32768, 32768))
            hi = int(rng.integers(-32768, 32768)); hq = int(rng.integers(-32768, 32768))
        ei, eq, _ = ideal_zf(ri, rq, hi, hq)
        mi, mq, rec = rtl_model(ri, rq, hi, hq)
        sc = hi*hi + hq*hq
        if sc == 0:
            nguard += 1
            if not (mi == 0 and mq == 0): guard_violation += 1
            continue
        nck += 1
        if rec is not None:
            rr = abs(rec - 1.0/sc)/(1.0/sc)
            if rr > worst_rec: worst_rec = rr; worst_rec_mag = np.sqrt(sc)
        w = max(abs(mi-ei), abs(mq-eq))
        issat = (ei in (-32768, 32767) or eq in (-32768, 32767))
        if issat:
            nsat += 1
        else:
            dec = int(np.floor(np.log10(max(np.sqrt(sc), 1e-9))))
            bucket_worst[dec] = max(bucket_worst.get(dec, 0), w)
        if w > worst:
            worst = w; worst_case = (ri, rq, hi, hq, ei, eq, mi, mq, issat)
    print()
    print("=" * 78)
    print(f"MONTE-CARLO {NMC} CASES  (bit-faithful RTL model vs exact ZF reference)")
    print("=" * 78)
    print(f"  non-guard checked = {nck}   guard(sc==0) = {nguard}   "
          f"guard_violations = {guard_violation}   saturating = {nsat}")
    print(f"  WORST |err| = {worst} LSB")
    if worst_case:
        print(f"    worst-case RX=({worst_case[0]},{worst_case[1]}) "
              f"H=({worst_case[2]},{worst_case[3]}) "
              f"exp=({worst_case[4]},{worst_case[5]}) "
              f"model=({worst_case[6]},{worst_case[7]}) sat={worst_case[8]}")
    print(f"  WORST-CASE relative reciprocal error = {worst_rec:.4e} "
          f"at |H|={worst_rec_mag:.1f}")
    print(f"  NON-saturating worst |err| LSB by |H| decade (degradation check):")
    for d in sorted(bucket_worst):
        print(f"    10^{d:<2d} : {bucket_worst[d]} LSB")

if __name__ == "__main__":
    main()
