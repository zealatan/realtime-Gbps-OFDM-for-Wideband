#!/usr/bin/env python3
"""
compare_board_capture.py
========================
Compare a ZCU216 digital-loopback board capture (.bin) of the OFDM
synchronizer's CORRECTED M_AXIS output against the bit-exact golden for the
fc_kp0 stimulus.

Board dump format (from scripts/run_10_digital_loopback.xsct `mrd -bin`):
    little-endian u32 words, one AXI-S beat each, 32-bit packed IQ:
        [31:16] = Q (signed 16b),  [15:0] = I (signed 16b)
    capture_buf is CAPTURE_DEPTH(8192) deep but only ~4160 words are dumped.

Golden format (golden/p5_corrected/fc_kp0_corrected_m_axis_golden.hex):
    4032 packed-IQ words, same [31:16]=Q / [15:0]=I layout, one per line,
    '//' comment lines ignored. This is fc_kp0.mem words [64:4096] (the
    14-symbol, 4032-beat slot). For k_int=0 the integer NCO is identity
    (step_word=0) and the fractional-CFO estimate is ~0, so the DUT's
    corrected output equals the input slot to within the BRAM/GPIO
    read-back quantization (~+/-2 LSB per IQ component).

Alignment: the board capture may lead the golden by a small fixed offset
(the indexed BRAM read-back starts at capture beat 0, which is the first
corrected M_AXIS beat, but pipeline / capture-arm timing can introduce a
0..N word lead). We search a lead-offset window and pick the offset that
maximizes the within-tolerance match count, then report against it.

Exit code 0 on PASS, 1 on FAIL.

Usage:
    scripts/compare_board_capture.py <board_dump.bin> [golden.hex] \
        [--tol N] [--maxbad K] [--maxoff M] [--show N]

Defaults:
    golden  = RTL_SYNC_PHASE5/golden/p5_corrected/fc_kp0_corrected_m_axis_golden.hex
    --tol    2    per-IQ-component LSB tolerance (0 = strict bit-exact)
    --maxbad 1    samples allowed to exceed tol and still PASS (boundary beat)
    --maxoff 200  lead-offset search window [0..maxoff]
    --show   20   number of first mismatches to print
"""
import argparse
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
DEFAULT_GOLDEN = os.path.join(
    REPO, "RTL_SYNC_PHASE5", "golden", "p5_corrected",
    "fc_kp0_corrected_m_axis_golden.hex")


def split_iq(word):
    """Return (I, Q) signed-16 from a 32-bit packed word [31:16]=Q [15:0]=I."""
    i = word & 0xFFFF
    q = (word >> 16) & 0xFFFF
    if i & 0x8000:
        i -= 0x10000
    if q & 0x8000:
        q -= 0x10000
    return i, q


def load_bin(path):
    with open(path, "rb") as f:
        data = f.read()
    n = len(data) // 4
    return list(struct.unpack("<%dI" % n, data[:n * 4]))


def load_golden(path):
    words = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//") or line.startswith("#"):
                continue
            words.append(int(line, 16))
    return words


def score(cap, golden, off, tol):
    """Match count + mismatch list for golden placed at cap[off:off+len]."""
    n = len(golden)
    if off + n > len(cap):
        n = len(cap) - off
        if n <= 0:
            return -1, n, []
    match = 0
    mism = []
    for i in range(n):
        gw = golden[i]
        cw = cap[off + i]
        gi, gq = split_iq(gw)
        ci, cq = split_iq(cw)
        if abs(ci - gi) <= tol and abs(cq - gq) <= tol:
            match += 1
        else:
            mism.append((i, off + i, cw, gw, ci, cq, gi, gq))
    return match, n, mism


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("board_bin")
    ap.add_argument("golden", nargs="?", default=DEFAULT_GOLDEN)
    ap.add_argument("--tol", type=int, default=2,
                    help="per-IQ-component LSB tolerance (0 = strict)")
    ap.add_argument("--maxbad", type=int, default=1,
                    help="samples allowed over tol and still PASS")
    ap.add_argument("--maxoff", type=int, default=200,
                    help="lead-offset search window upper bound")
    ap.add_argument("--show", type=int, default=20,
                    help="number of first mismatches to print")
    args = ap.parse_args()

    if not os.path.isfile(args.board_bin):
        print("ERROR: board dump not found: %s" % args.board_bin)
        return 1
    if not os.path.isfile(args.golden):
        print("ERROR: golden not found: %s" % args.golden)
        return 1

    cap = load_bin(args.board_bin)
    golden = load_golden(args.golden)
    print("board dump : %s  (%d u32 words)" % (args.board_bin, len(cap)))
    print("golden     : %s  (%d samples)" % (args.golden, len(golden)))
    print("tolerance  : +/-%d LSB per IQ component  maxbad=%d  search off 0..%d"
          % (args.tol, args.maxbad, args.maxoff))

    # Find best lead offset by within-tol match count.
    best = (-1, 0, 0, [])  # (match, off, n, mism)
    hi = min(args.maxoff, max(0, len(cap) - 1))
    for off in range(0, hi + 1):
        m, n, mism = score(cap, golden, off, args.tol)
        if m > best[0]:
            best = (m, off, n, mism)
    match, off, n, mism = best
    bad = n - match

    print("-" * 60)
    print("best lead offset = %d  (capture[%d] aligns to golden[0])"
          % (off, off))
    print("compared %d samples : %d within tol, %d over tol" % (n, match, bad))

    if mism:
        print("first %d mismatches (golden_idx, cap_idx, got=0x.., "
              "exp=0x.., gotIQ, expIQ):" % min(args.show, len(mism)))
        for (gi_idx, ci_idx, cw, gw, ci, cq, gi, gq) in mism[:args.show]:
            print("  g[%4d] c[%4d]  got=%08x exp=%08x  got(I=%d,Q=%d) "
                  "exp(I=%d,Q=%d)  dI=%d dQ=%d"
                  % (gi_idx, ci_idx, cw, gw, ci, cq, gi, gq,
                     ci - gi, cq - gq))

    exact_off, _, exact_mism = (best[1], None, None)
    # report strict bit-exact count at the chosen offset too
    exact = 0
    for i in range(n):
        if cap[off + i] == golden[i]:
            exact += 1
    print("-" * 60)
    print("strict bit-exact (==) at off=%d : %d / %d" % (off, exact, n))

    ok = (n == len(golden)) and (bad <= args.maxbad)
    if ok:
        print("RESULT: PASS  (%d/%d within +/-%d LSB; %d over tol <= maxbad=%d; "
              "lead_off=%d)" % (match, n, args.tol, bad, args.maxbad, off))
        return 0
    print("RESULT: FAIL  (%d/%d within +/-%d LSB; %d over tol > maxbad=%d; "
          "lead_off=%d)" % (match, n, args.tol, bad, args.maxbad, off))
    return 1


if __name__ == "__main__":
    sys.exit(main())
