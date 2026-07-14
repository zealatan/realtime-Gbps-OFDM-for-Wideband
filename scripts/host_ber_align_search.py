#!/usr/bin/env python3
"""
host_ber_align_search.py  --  FIX3 cfg_done-gate board verification (decisive host BER)
=======================================================================================
Reads N JTAG capture_buf dumps (frxbits_*.bin), each = 16384 LE-u32 words where the
low nibble of each word is one demod 16-QAM symbol (4 bits b0..b3). One OFDM frame =
12 data symbols x 221 data-subcarriers = 2652 nibbles = 10608 bits.

For each run this does an exhaustive host-side ALIGNMENT SEARCH against the golden
RTL_SYNC_PHASE5/golden/rx_downstream/tx_bits.txt (12 lines x 884 bits = 10608 bits):
    * 12 whole-OFDM-symbol ROTATIONS of the reference (frame phase unknown)
    * a NIBBLE-OFFSET sweep into the capture buffer (capture start phase unknown)
    * both BIT-ORDERS per nibble (b0..b3 vs b3..b0)
and reports the MINIMUM BER found (best alignment).  A genuinely-correct demod gives
BER=0 at exactly one alignment; pure noise floors at ~0.5 (44-50%).

It ALSO reports cross-run DETERMINISM: are the raw captured nibbles bit-identical
across all runs (md5 of the first-frame nibbles + pairwise differing-nibble %)?

Usage:
  scripts/host_ber_align_search.py tests/11_full_rx_loopback/frxbits_fix3run*.bin
"""
import sys, os, hashlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GOLD = os.path.join(ROOT, "RTL_SYNC_PHASE5", "golden", "rx_downstream", "tx_bits.txt")

NUM_SYM   = 12          # data OFDM symbols per frame
NDATA_SC  = 221         # data subcarriers per symbol
NBEATS    = NUM_SYM * NDATA_SC      # 2652 nibbles / frame
NBITS     = NBEATS * 4              # 10608 bits / frame
SYM_NIB   = NDATA_SC                # nibbles per OFDM symbol


def load_words(path):
    return np.fromfile(path, dtype="<u4")


def load_golden():
    lines = [l.strip() for l in open(GOLD) if l.strip()]
    assert len(lines) == NUM_SYM, f"golden has {len(lines)} lines, expect {NUM_SYM}"
    bits = np.array([int(c) for l in lines for c in l], dtype=np.uint8)
    assert bits.size == NBITS, bits.size
    return bits, lines


def nibbles_to_bits(nibs, msb_first):
    """nibs (Nx) -> 4N bits. msb_first: b0=bit3..b3=bit0 (matches RTL m_axis)."""
    nibs = nibs.astype(np.uint8)
    if msb_first:
        order = [3, 2, 1, 0]
    else:
        order = [0, 1, 2, 3]
    out = np.empty(nibs.size * 4, dtype=np.uint8)
    for i, sh in enumerate(order):
        out[i::4] = (nibs >> sh) & 1
    return out


def rotate_ref_bits(gold_lines, rot):
    """Rotate the reference by `rot` whole OFDM symbols (cyclic), return NBITS bits."""
    rl = gold_lines[rot:] + gold_lines[:rot]
    return np.array([int(c) for l in rl for c in l], dtype=np.uint8)


def best_align_ber(words, gold_lines, max_nib_off=8):
    """Exhaustive search: nibble-offset x 12 rotations x 2 bit-orders. Return best."""
    best = (NBITS, None)   # (errors, (off,rot,msb))
    # precompute rotated reference bit arrays
    refs = [rotate_ref_bits(gold_lines, r) for r in range(NUM_SYM)]
    for off in range(0, max_nib_off + 1):
        seg = words[off:off + NBEATS]
        if seg.size < NBEATS:
            break
        nibs = (seg & 0xF)
        for msb in (True, False):
            rx = nibbles_to_bits(nibs, msb)
            for rot in range(NUM_SYM):
                err = int(np.count_nonzero(rx != refs[rot]))
                # also try the complement-of-rotation by symbol offset within the
                # nibble stream is already covered by rot; keep simple.
                if err < best[0]:
                    best = (err, (off, rot, msb))
    return best


def main():
    files = sys.argv[1:]
    if not files:
        print("usage: host_ber_align_search.py <dump1.bin> [dump2.bin ...]")
        return 2
    files = sorted(files)
    gold_bits, gold_lines = load_golden()

    print("=" * 78)
    print("FIX3 cfg_done-gate HOST-BER ALIGNMENT SEARCH  (golden = %s)" % os.path.relpath(GOLD, ROOT))
    print("  frame = %d nibbles = %d bits ; search = 9 nib-offsets x 12 rot x 2 bitorder" % (NBEATS, NBITS))
    print("=" * 78)

    run_nibs = []     # first-frame nibbles per run (for determinism)
    results = []      # (name, errors, ber, align)
    for f in files:
        w = load_words(f)
        name = os.path.basename(f)
        if w.size < NBEATS:
            print(f"{name}: SKIP only {w.size} words")
            continue
        nib0 = (w[:NBEATS] & 0xF).astype(np.uint8)
        run_nibs.append((name, nib0))
        err, align = best_align_ber(w, gold_lines)
        ber = err / NBITS
        results.append((name, err, ber, align))
        off, rot, msb = align
        print(f"{name}: best BER = {err:5d}/{NBITS} = {ber:.4e}  "
              f"[nib_off={off} rot={rot} bitorder={'b0=msb' if msb else 'b0=lsb'}]")

    # ---- determinism across runs --------------------------------------------
    print("-" * 78)
    print("DETERMINISM (raw first-frame nibbles, %d per run):" % NBEATS)
    md5s = []
    for name, nib in run_nibs:
        h = hashlib.md5(nib.tobytes()).hexdigest()
        md5s.append(h)
        print(f"  {name}: md5(nibbles)={h}")
    all_identical = len(set(md5s)) == 1
    print(f"  ALL RUNS BIT-IDENTICAL (raw nibbles): {'YES' if all_identical else 'NO'}")
    if not all_identical and len(run_nibs) >= 2:
        base = run_nibs[0][1]
        print("  pairwise differing-nibble %% vs %s:" % run_nibs[0][0])
        for name, nib in run_nibs[1:]:
            d = np.count_nonzero(nib != base) / NBEATS * 100
            print(f"    {name}: {d:.1f}%% nibbles differ")

    # ---- verdict ------------------------------------------------------------
    print("=" * 78)
    bers = [r[2] for r in results]
    max_ber = max(bers) if bers else 1.0
    host_ber0 = all(b == 0 for b in bers)
    print("SUMMARY: runs=%d  determinism=%s  host-BER all-zero=%s  worst-BER=%.4e" %
          (len(results), "YES" if all_identical else "NO",
           "YES" if host_ber0 else "NO", max_ber))
    if all_identical and host_ber0:
        print("VERDICT: FIXED  (deterministic across PORs AND host-BER=0 every run)")
    else:
        print("VERDICT: STILL BROKEN  (determinism=%s, host-BER0=%s)" %
              (all_identical, host_ber0))
    print("=" * 78)
    return 0


if __name__ == "__main__":
    sys.exit(main())
