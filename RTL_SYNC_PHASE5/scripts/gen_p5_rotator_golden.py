#!/usr/bin/env python3
"""
gen_p5_rotator_golden.py — Golden vector generator for the
P5-ROT-UNIT testbench (tb/p5_complex_rotator_unit_tb.sv).

DUT:  rtl/complex_rotator.v  (wraps rtl/complex_mult_iq.v with CONJ_B=1)

The DUT itself does NOT contain an NCO/phase-to-sincos converter — it
takes raw signed Q1.15 sin_in/cos_in samples directly and computes:

    (I_out + j*Q_out) = (I_in + j*Q_in) * (cos_in - j*sin_in)

So at the gate level we feed (cos_in, sin_in) as Q1.15. To match the
user's spec convention

    expected_out = (I_in + j*Q_in) * exp(+j * phase_word/32768 * pi)

the testbench drives:

    cos_in = round( cos(theta) * 32767)
    sin_in = round(-sin(theta) * 32767)   # negate so that DUT's
                                           # (cos - j*sin) becomes (cos + j*sin)
    theta  = phase_word / 32768.0 * pi    # phase_word is int16, signed

The golden CSV captures (in_I, in_Q, phase_word, exp_out_I, exp_out_Q)
where exp_out is computed in pure floating point with the same Q15
rounding (`(prod_full >> 15)` arithmetic-shift, then clamped to int16)
that the RTL is doing.

CSV layout (40 rows):
   - 16 cases : angle sweep, constant amplitude (I_in=10000, Q_in=0)
   -  8 cases : amplitude sweep at theta = +pi/4
   - 16 cases : random (I, Q, phase) using a fixed seed

Output: golden/p5_rotator_golden.csv
"""

from __future__ import annotations
import math
import random
import os
import sys

# ---------------------------------------------------------------------------
# Path constants
# ---------------------------------------------------------------------------
HERE       = os.path.abspath(os.path.dirname(__file__))
ROOT       = os.path.abspath(os.path.join(HERE, ".."))
OUT_DIR    = os.path.join(ROOT, "golden")
OUT_PATH   = os.path.join(OUT_DIR, "p5_rotator_golden.csv")

# Q1.15 fixed-point constants matching the RTL (COMPONENT_WIDTH=16, SHIFT=15)
Q15_SCALE  = 32767          # max positive int16
INT16_MAX  =  32767
INT16_MIN  = -32768

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def to_q15(x: float) -> int:
    """Convert a unit-magnitude float (|x|<=1) to signed Q1.15 int16."""
    v = int(round(x * Q15_SCALE))
    if v >  INT16_MAX: v =  INT16_MAX
    if v <  INT16_MIN: v =  INT16_MIN
    return v

def arith_shift_right(v: int, n: int) -> int:
    """Python's // doesn't behave like Verilog >>> for negative numbers
    only when the result truncates to non-integer. Use math.floor."""
    return v >> n if v >= 0 else -((-v) >> n) if (((-v) & ((1<<n)-1)) == 0) \
                                  else -(((-v) >> n) + 1)

def clamp_int16(v: int) -> int:
    if v >  INT16_MAX: return  INT16_MAX
    if v <  INT16_MIN: return  INT16_MIN
    return v

def trunc_int16(v: int) -> int:
    """Match RTL: take lower 16 bits and sign-extend (wrap-around, no clamp)."""
    v16 = v & 0xFFFF
    if v16 & 0x8000:
        v16 -= 0x10000
    return v16

def model_rotator(in_I: int, in_Q: int, phase_word: int) -> tuple[int, int]:
    """
    Compute the bit-exact RTL output for (in_I, in_Q, phase_word) using the
    same fixed-point operations as rtl/complex_mult_iq.v + complex_rotator.v.

      theta     = phase_word / 32768 * pi
      cos_drive = round( cos(theta)*32767)   -> int16
      sin_drive = round(-sin(theta)*32767)   -> int16  (sign flip to match
                                                       spec convention)

      The RTL does (with CONJ_B=1):
        I_out_raw = ( Ia*Ib + Qa*Qb )  (after the conjugate flips the sign
                                        of Qb_eff = -sin_drive)
        Q_out_raw = ( Qa*Ib - Ia*Qb )
        I_out     = arith_shift_right(I_out_raw, 15) clipped to int16
        Q_out     = arith_shift_right(Q_out_raw, 15) clipped to int16
    """
    theta     = phase_word / 32768.0 * math.pi
    cos_drive = to_q15( math.cos(theta))
    sin_drive = to_q15(-math.sin(theta))   # negate -> RTL produces exp(+j*theta)

    # Mimic complex_mult_iq with CONJ_B=1:
    Ia = in_I
    Qa = in_Q
    Ib = cos_drive
    Qb = sin_drive
    Qb_eff = -Qb        # CONJ_B=1

    p_II = Ia * Ib
    p_QQ = Qa * Qb_eff
    p_IQ = Ia * Qb_eff
    p_QI = Qa * Ib

    sum_I = p_II - p_QQ
    sum_Q = p_IQ + p_QI

    # RTL slices the low COMPONENT_WIDTH bits with NO saturation -> wrap-around.
    out_I = trunc_int16(arith_shift_right(sum_I, 15))
    out_Q = trunc_int16(arith_shift_right(sum_Q, 15))
    return out_I, out_Q

# ---------------------------------------------------------------------------
# Case generation
# ---------------------------------------------------------------------------
def gen_cases() -> list[tuple[int, int, int]]:
    """Yields list of (in_I, in_Q, phase_word) triples (40 total)."""
    cases: list[tuple[int, int, int]] = []

    # ---- 16: angle sweep, constant amplitude ----
    AMP = 10000
    for k in range(16):
        # phase ∈ {-π, -7π/8, ..., +7π/8}  (16 evenly-spaced points)
        phase_word = -32768 + k * (65536 // 16)   # = -32768 + k*4096
        cases.append((AMP, 0, phase_word))

    # ---- 8: amplitude sweep at theta = +π/4 ----
    PHASE_PI_4 = 32768 // 4    # = 8192  -> theta = pi/4
    for amp in (100, 500, 1000, 5000, 10000, 20000, 30000, 32000):
        cases.append((amp, 0, PHASE_PI_4))

    # ---- 16: random (I, Q, phase) with fixed seed ----
    rng = random.Random(0xC0FFEE)
    # Bound each component to ~23000 so that |in| = sqrt(I^2+Q^2) <= 32760
    # and the rotated output (same magnitude) fits in signed int16 without
    # wrap-around. The truncating model below would still match the RTL
    # bit-exactly under overflow, but bounded inputs keep the test
    # physically meaningful too.
    for _ in range(16):
        in_I = rng.randint(-23000, 23000)
        in_Q = rng.randint(-23000, 23000)
        phase_word = rng.randint(-32768, 32767)
        cases.append((in_I, in_Q, phase_word))

    return cases

def main() -> int:
    os.makedirs(OUT_DIR, exist_ok=True)

    cases = gen_cases()
    print(f"Generated {len(cases)} test cases (16 angle + 8 amp + 16 random)")

    with open(OUT_PATH, "w", encoding="ascii") as fh:
        fh.write("# p5_rotator_golden.csv\n")
        fh.write("# Generated by scripts/gen_p5_rotator_golden.py\n")
        fh.write("# Format: in_I,in_Q,phase_word,exp_out_I,exp_out_Q\n")
        fh.write("# Phase encoding: theta = phase_word/32768 * pi   (phase_word is int16)\n")
        fh.write("# Expected output: (in_I+j*in_Q) * exp(+j*theta), Q15 arith-shift, low-16-bit truncate (NO saturation)\n")
        for (in_I, in_Q, phase_word) in cases:
            out_I, out_Q = model_rotator(in_I, in_Q, phase_word)
            fh.write(f"{in_I},{in_Q},{phase_word},{out_I},{out_Q}\n")

    # Print a few rows for sanity
    print(f"Wrote {OUT_PATH}")
    print("First 5 rows:")
    with open(OUT_PATH, "r", encoding="ascii") as fh:
        rows = [ln for ln in fh if not ln.startswith("#")]
    for r in rows[:5]:
        print("  " + r.rstrip())
    return 0

if __name__ == "__main__":
    sys.exit(main())
