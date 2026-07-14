#!/usr/bin/env python3
"""
gen_rx_demod_16qam_stress.py
============================
Robust stress-vector generator for the rx_demod_16qam (16-QAM hard slicer)
RTL module. Produces (I,Q) integer points + the EXPECTED 4 bits per point,
where the expected bits come from the EXACT decode_16qam reference
(scripts/rx_downstream_ref.py: demod_16qam), i.e. float thresholds
{-2,0,+2}*SCALE_16QAM applied to value/Q15_SCALE.

Vector categories:
  (a) N random equalized points, uniform over the full int16 plane.
  (b) BOUNDARY points: exactly at and +/-1 LSB around each integer
      threshold {-3220, 0, +3220} on BOTH I and Q axes (cross product),
      to verify the comparison direction (< vs <=) vs the C reference.
  (c) the 4 ideal 16-QAM constellation points (+/-1, +/-3 levels) AND
      noisy versions that must still decode to the same symbol.
  (d) saturated / extreme points (+/-32767, +/-32768-ish int16 edges).

Output: golden/rx_downstream/demod_stress_vectors.hex
  one line per vector: "IIII QQQQ BBBB_expected_label"  -- but for the
  RTL TB we emit a clean machine-readable file:
      <8-hex packed {Q[31:16],I[15:0]}> <4 expected bits b0b1b2b3>
  plus a human summary to stdout.

Bit/threshold conventions are taken verbatim from CONTRACT.md sec 3.4 / 4
and rx_downstream_ref.demod_16qam. NO RTL is read or modified.
"""
import os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(ROOT, "golden", "rx_downstream")

# ---- exact reference constants (must match CONTRACT.md + ref model) ----
SCALE_16QAM = 1.0 / np.sqrt(10.0)        # 0.316227766...
Q15_SCALE   = 5090.697374                 # RMS-matched scale (CONTRACT sec 1)
THRESH_INT  = 3220                         # RTL integer threshold

D0 = -2.0 * SCALE_16QAM                    # float lower threshold
D1 =  0.0
D2 =  2.0 * SCALE_16QAM                    # float upper threshold

INT16_MIN, INT16_MAX = -32768, 32767


def ref_axis_bits(intval):
    """EXACT decode_16qam per-axis logic (float thresholds on intval/Q15)."""
    v = float(intval) / Q15_SCALE
    if   v < D0: return (0, 1)             # -3 region
    elif v < D1: return (0, 0)             # -1 region
    elif v < D2: return (1, 0)             # +1 region
    else:        return (1, 1)             # +3 region


def ref_demod(i_int, q_int):
    """4-bit reference [b0,b1,b2,b3] = (I->b0,b1)+(Q->b2,b3)."""
    b0, b1 = ref_axis_bits(i_int)
    b2, b3 = ref_axis_bits(q_int)
    return (b0, b1, b2, b3)


def clamp16(v):
    return max(INT16_MIN, min(INT16_MAX, int(v)))


def pack(i_int, q_int):
    i = i_int & 0xFFFF
    q = q_int & 0xFFFF
    return f"{((q << 16) | i) & 0xFFFFFFFF:08X}"


def build_vectors(n_random=40, seed=0xC0FFEE):
    rng = np.random.default_rng(seed)
    vecs = []   # list of (i_int, q_int, tag)

    # ---- (a) random uniform over the full int16 plane ----
    ai = rng.integers(INT16_MIN, INT16_MAX + 1, size=n_random)
    aq = rng.integers(INT16_MIN, INT16_MAX + 1, size=n_random)
    for i, q in zip(ai, aq):
        vecs.append((int(i), int(q), "random"))

    # ---- (b) boundary points around each integer threshold ----
    # axis test levels: exactly at and +/-1 LSB around {-3220,0,+3220}
    bnd = []
    for t in (-THRESH_INT, 0, THRESH_INT):
        bnd += [t - 1, t, t + 1]
    # also the exact float-threshold rounded neighbours (3219/3220 already in)
    bnd += [-3219, 3219, -3221, 3221]
    bnd = sorted(set(bnd))
    # full cross product over I and Q so both axes' boundary logic is hit
    for i in bnd:
        for q in bnd:
            vecs.append((int(i), int(q), "boundary"))

    # ---- (c) ideal constellation + additive noise ----
    # ideal per-axis integer levels for +/-1, +/-3:  round(level*SCALE*Q15)
    lvl = {}
    for L in (-3, -1, 1, 3):
        lvl[L] = int(round(L * SCALE_16QAM * Q15_SCALE))
    # 16 ideal points (all symbol combinations)
    for Li in (-3, -1, 1, 3):
        for Lq in (-3, -1, 1, 3):
            vecs.append((lvl[Li], lvl[Lq], "ideal"))
    # noisy versions: add bounded noise that keeps each axis in its decision
    # cell (|noise| < ~half the 2*SCALE*Q15 spacing = ~1610). Use +/-1200.
    noise_mags = [-1200, -600, -100, 100, 600, 1200]
    for Li in (-3, -1, 1, 3):
        for Lq in (-3, -1, 1, 3):
            for nm in noise_mags:
                i = clamp16(lvl[Li] + nm)
                q = clamp16(lvl[Lq] - nm)
                vecs.append((i, q, "noisy"))

    # ---- (d) saturated / extreme corners ----
    extremes = [INT16_MIN, INT16_MIN + 1, -32767, -1, 0, 1, 32766, INT16_MAX]
    for i in extremes:
        for q in extremes:
            vecs.append((int(i), int(q), "extreme"))

    return vecs


def main():
    os.makedirs(OUT, exist_ok=True)
    vecs = build_vectors()

    # de-dup while preserving order (boundary/extreme overlap a little)
    seen = set()
    uniq = []
    for (i, q, tag) in vecs:
        key = (i, q)
        if key in seen:
            continue
        seen.add(key)
        uniq.append((i, q, tag))
    vecs = uniq

    # constellation-coverage check: ensure all 16 symbols are produced
    sym_hit = set()
    cat_count = {}
    lines = []
    for (i, q, tag) in vecs:
        b = ref_demod(i, q)
        sym_hit.add(b)
        cat_count[tag] = cat_count.get(tag, 0) + 1
        bits = "".join(str(x) for x in b)   # b0 b1 b2 b3
        lines.append(f"{pack(i, q)} {bits}")

    out_path = os.path.join(OUT, "demod_stress_vectors.hex")
    with open(out_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    print(f"[stress] wrote {len(vecs)} vectors -> {out_path}")
    print(f"[stress] category counts: {cat_count}")
    print(f"[stress] distinct 16-QAM symbols hit: {len(sym_hit)} / 16")
    assert len(sym_hit) == 16, f"NOT all 16 symbols covered: {sorted(sym_hit)}"

    # also emit count file the TB reads (so TB N is data-driven)
    with open(os.path.join(OUT, "demod_stress_count.txt"), "w") as f:
        f.write(f"{len(vecs)}\n")

    # ---- self-report the known RTL-vs-ref boundary divergence ----
    div = []
    for iv in range(INT16_MIN, INT16_MAX + 1):
        # rtl per-axis
        if   iv < -THRESH_INT: r = (0, 1)
        elif iv < 0:           r = (0, 0)
        elif iv < THRESH_INT:  r = (1, 0)
        else:                  r = (1, 1)
        if r != ref_axis_bits(iv):
            div.append(iv)
    print(f"[stress] per-axis int values where RTL(int {THRESH_INT}) != "
          f"float-ref: {div}")
    return out_path, len(vecs)


if __name__ == "__main__":
    main()
