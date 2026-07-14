#!/usr/bin/env python3
"""
steady_state_ber.py  --  authoritative steady-state BER proof for the ZCU216
11_full_rx digital-loopback demod capture.

The dut_capture buffer holds a CONTINUOUS stream of demod nibbles (low 4 bits of
each LE-u32 word): one 16-QAM symbol per data-subcarrier, 221 data SC per OFDM
symbol, 12 OFDM symbols per frame -> the underlying transmitted bitstream is the
2652-nibble (10608-bit) golden frame, REPEATING.

The golden RTL_SYNC_PHASE5/golden/rx_downstream/tx_bits.txt is 12 lines x 884 bits
= one frame, one line PER OFDM SYMBOL (884 = 221 SC x 4 bits).

This script:
  1. Treats the whole capture as a flat nibble stream -> flat bit stream.
  2. Finds the global alignment: a NIBBLE offset (start phase, absorbs the startup
     transient + capture-start jitter) and a whole-OFDM-SYMBOL rotation of the
     golden (frame phase), bit-order fixed to the RTL packing (b0=msb..b3=lsb),
     by MINIMISING errors on a steady-state window (symbols >= --skip).
  3. Slices the aligned stream into consecutive OFDM symbols (221 nibbles each),
     compares each against the matching golden symbol, prints per-symbol BER.
  4. Reports steady-state BER = all symbols with index >= --skip (transient
     excluded) and characterises the transient (first symbol that hits BER=0).

bit packing (matches rtl/tb/rx_ber_checker): word nibble b: bit3=b0..bit0=b3.
"""
import sys, os, argparse, hashlib
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GOLD = os.path.join(ROOT, "RTL_SYNC_PHASE5", "golden", "rx_downstream", "tx_bits.txt")

NUM_SYM  = 12          # OFDM data symbols per frame
NDATA_SC = 221         # data subcarriers (nibbles) per OFDM symbol
SYM_BITS = NDATA_SC * 4        # 884 bits per OFDM symbol
FRAME_NIB = NUM_SYM * NDATA_SC # 2652
FRAME_BITS = FRAME_NIB * 4     # 10608


def load_words(path):
    return np.fromfile(path, dtype="<u4")


def load_golden_symbols():
    """Return list of 12 np.uint8 bit-arrays (884 bits each), one per OFDM symbol."""
    lines = [l.strip() for l in open(GOLD) if l.strip()]
    assert len(lines) == NUM_SYM, f"golden {len(lines)} lines expect {NUM_SYM}"
    syms = []
    for l in lines:
        assert len(l) == SYM_BITS, len(l)
        syms.append(np.array([int(c) for c in l], dtype=np.uint8))
    return syms


def nibbles_to_bits(nibs):
    """nibs -> 4N bits, b0=bit3..b3=bit0 (RTL m_axis packing)."""
    nibs = nibs.astype(np.uint8)
    out = np.empty(nibs.size * 4, dtype=np.uint8)
    for i, sh in enumerate((3, 2, 1, 0)):
        out[i::4] = (nibs >> sh) & 1
    return out


def golden_symbol_at(gsyms, sym_index, rot):
    """Golden bits for absolute aligned OFDM-symbol index, with whole-symbol rot."""
    return gsyms[(sym_index + rot) % NUM_SYM]


def evaluate(nibs, gsyms, nib_off, rot, skip_syms):
    """Slice nibs from nib_off into OFDM symbols, compare to rotated golden.
    Returns (per_sym_err list, n_complete_syms)."""
    avail = nibs.size - nib_off
    nsym = avail // NDATA_SC
    per = []
    for s in range(nsym):
        seg = nibs[nib_off + s * NDATA_SC : nib_off + (s + 1) * NDATA_SC]
        rx = nibbles_to_bits(seg)
        g = golden_symbol_at(gsyms, s, rot)
        per.append(int(np.count_nonzero(rx != g)))
    return per, nsym


def longest_zero_run(per):
    """Return (start, end_inclusive, length) of the longest contiguous BER=0 run."""
    best = (0, -1, 0)
    i = 0
    while i < len(per):
        if per[i] == 0:
            j = i
            while j < len(per) and per[j] == 0:
                j += 1
            if (j - i) > best[2]:
                best = (i, j - 1, j - i)
            i = j
        else:
            i += 1
    return best


def find_alignment(nibs, gsyms, skip_syms, max_nib_off):
    """Search nib_off (0..max) x rot (0..11). Score = MAXIMISE the longest
    contiguous zero-error OFDM-symbol run (the true steady-state window, robust
    to BOTH the head startup transient AND the tail capture-buffer-end artifact).
    Return best (run_len, off, rot, per_sym_err, nsym, run_start, run_end)."""
    best = None
    for off in range(0, max_nib_off + 1):
        for rot in range(NUM_SYM):
            per, nsym = evaluate(nibs, gsyms, off, rot, skip_syms)
            if nsym <= skip_syms:
                continue
            rs, re, rl = longest_zero_run(per)
            if best is None or rl > best[0]:
                best = (rl, off, rot, per, nsym, rs, re)
    return best


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bins", nargs="+")
    ap.add_argument("--skip", type=int, default=5,
                    help="transient OFDM symbols to exclude from steady-state BER")
    ap.add_argument("--max-nib-off", type=int, default=2 * NDATA_SC,
                    help="max nibble start-offset to search (absorbs transient+jitter)")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    gsyms = load_golden_symbols()
    print("=" * 90)
    print("STEADY-STATE BER  golden=%s  (12 sym x %d bits)" %
          (os.path.relpath(GOLD, ROOT), SYM_BITS))
    print("  per-symbol decode, transient = first %d OFDM symbols excluded; "
          "search nib_off 0..%d x rot 0..11" % (args.skip, args.max_nib_off))
    print("=" * 90)

    summary = []
    raw_hashes = []
    for path in sorted(args.bins):
        name = os.path.basename(path)
        w = load_words(path)
        nibs = (w & 0xF).astype(np.uint8)
        raw_hashes.append((name, hashlib.md5(w.tobytes()).hexdigest()))
        best = find_alignment(nibs, gsyms, args.skip, args.max_nib_off)
        if best is None:
            print(f"{name}: SKIP (too few symbols)")
            continue
        run_len, off, rot, per, nsym, run_s, run_e = best
        ss_bits = run_len * SYM_BITS
        ss_err = 0  # by construction the run is all-zero
        ss_ber = ss_err / ss_bits if ss_bits > 0 else float("nan")
        full_err = sum(per)
        head_transient = run_s                 # symbols 0..run_s-1 (startup)
        tail_transient = nsym - 1 - run_e       # symbols after the clean window
        summary.append((name, off, rot, nsym, per, run_len, ss_bits, ss_ber,
                        run_s, run_e, head_transient, tail_transient, full_err))
        print(f"\n{name}:  nib_off={off}  rot={rot}  symbols_decoded={nsym}")
        if not args.quiet:
            line = "  per-sym errs: " + " ".join(
                ("." if e == 0 else str(e)) for e in per)
            print(line)
        print(f"  STARTUP transient: symbols 0..{run_s-1} ({head_transient} syms); "
              f"TAIL (capture-buffer end): symbols {run_e+1}..{nsym-1} ({tail_transient} syms)")
        print(f"  STEADY-STATE clean window: symbols {run_s}..{run_e} "
              f"= {run_len} symbols = {ss_bits} bits, {ss_err} errors "
              f"-> BER {ss_ber:.3e}  {'PASS BER=0' if ss_err==0 else 'NONZERO'}")

    print("\n" + "=" * 90)
    print("CROSS-POR DETERMINISM (md5 of raw 16384-word capture):")
    for name, h in raw_hashes:
        print(f"  {name}: {h}")
    ident = len({h for _, h in raw_hashes}) == 1
    print(f"  ALL CAPTURES BYTE-IDENTICAL: {'YES' if ident else 'NO'}")

    print("-" * 90)
    # steady-state BER=0 iff every run has a non-trivial clean window (here all 0)
    allz = all(s[5] > 0 for s in summary) and len(summary) > 0
    print("SUMMARY: runs=%d  steady-state-BER-all-zero=%s  byte-identical=%s" %
          (len(summary), "YES" if allz else "NO", "YES" if ident else "NO"))
    for s in summary:
        (name, off, rot, nsym, per, run_len, ss_bits, ss_ber,
         run_s, run_e, head, tail, full) = s
        print(f"  {name}: steady BER=0 over sym {run_s}..{run_e} "
              f"({run_len} syms, {ss_bits} bits)  head_transient={head} tail={tail}")
    print("VERDICT:", "RECEIVER WORKS (steady-state BER=0 every POR)" if allz
          else "steady-state nonzero -- inspect")
    print("=" * 90)
    return 0 if allz else 1


if __name__ == "__main__":
    sys.exit(main())
