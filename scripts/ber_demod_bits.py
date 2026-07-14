#!/usr/bin/env python3
"""
ber_demod_bits.py
=================
STAGE-1 on-board BER: the full-RX bitstream's dut_capture buffer holds the
DEMOD BITS (rx_full_board_top m_axis = one data-subcarrier nibble per beat,
word = {28'b0, b0,b1,b2,b3}).  Read the JTAG mrd -bin dump, unpack 2652
nibbles -> 10608 bits, compare vs golden/rx_downstream/tx_bits.txt.

Bit order matches the RTL/TB: m_axis_tdata[3]=b0, [2]=b1, [1]=b2, [0]=b3.
"""
import sys, os, argparse
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GOLD = os.path.join(ROOT, "RTL_SYNC_PHASE5", "golden", "rx_downstream")

NUM_DATA = 12
NDATA_SC = 221
NBEATS   = NUM_DATA * NDATA_SC      # 2652
NBITS    = NBEATS * 4               # 10608


def unpack_frame(words, off):
    """words[off:off+NBEATS] -> NBITS bits (b0..b3 per nibble)."""
    rx = np.zeros(NBITS, dtype=int)
    for n in range(NBEATS):
        w = int(words[off + n])
        rx[n * 4 + 0] = (w >> 3) & 1   # b0
        rx[n * 4 + 1] = (w >> 2) & 1   # b1
        rx[n * 4 + 2] = (w >> 1) & 1   # b2
        rx[n * 4 + 3] = (w >> 0) & 1   # b3
    return rx


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True, help="JTAG mrd -bin dump of capture_buf")
    ap.add_argument("--frames", type=int, default=1,
                    help="number of consecutive frames in the dump (multi-frame "
                         "streaming proof). Each frame = 2652 nibbles.")
    ap.add_argument("--align", action="store_true",
                    help="search the buffer start-offset (0..NBEATS-1) AND the "
                         "whole-symbol rotation for the alignment that minimizes "
                         "BER, then report multi-frame BER from that anchor. This "
                         "mirrors the on-chip checker's rot_off search: a finite "
                         "JTAG readback of a CONTINUOUS stream starts at an "
                         "arbitrary frame phase, so a raw offset-0 compare fails "
                         "even when the demod is bit-perfect.")
    args = ap.parse_args()

    words = np.fromfile(args.bin, dtype="<u4")

    tx = np.array([int(c) for l in open(os.path.join(GOLD, "tx_bits.txt"))
                   if l.strip() for c in l.strip()])
    assert tx.size == NBITS, tx.size

    start = 0
    if args.align:
        # Search a whole-symbol-granular buffer offset for the frame boundary.
        # The demod nibble stream is symbol-major (12 syms x 221 carriers); a
        # continuous readback starts mid-frame, so slide by whole symbols
        # (NDATA_SC nibbles) over one frame period and pick the min-BER anchor.
        best_off, best_err = 0, NBITS + 1
        max_off = len(words) - NBEATS
        if max_off < 0:
            print(f"FATAL: only {len(words)} words, need >= {NBEATS} for 1 frame")
            return 2
        step = NDATA_SC  # whole-symbol steps (matches on-chip rot_off units)
        for off in range(0, min(NBEATS, max_off + 1), step):
            rx = unpack_frame(words, off)
            e = int(np.sum(rx != tx))
            if e < best_err:
                best_err, best_off = e, off
        start = best_off
        print(f"ALIGN: best start-offset = {start} nibbles "
              f"(sym {start // NDATA_SC}) single-frame BER = {best_err}/{NBITS}")

    need = start + NBEATS * args.frames
    if len(words) < need:
        # trim frame count to what the buffer holds from the aligned anchor
        avail = (len(words) - start) // NBEATS
        print(f"NOTE: buffer holds {avail} aligned frames from offset {start} "
              f"(requested {args.frames})")
        args.frames = max(avail, 0)
        if args.frames == 0:
            print(f"FATAL: no full frame available from offset {start}")
            return 2

    total_err = 0
    all_pass = True
    for f in range(args.frames):
        off = start + f * NBEATS
        rx = unpack_frame(words, off)
        nerr = int(np.sum(rx != tx))
        ber = nerr / NBITS
        upper_nz = int(np.sum((words[off:off + NBEATS] >> 4) != 0))
        total_err += nerr
        ok = (nerr == 0)
        all_pass = all_pass and ok
        print(f"frame {f}: BER = {nerr}/{NBITS} = {ber:.3e} "
              f"(upper-bits-nonzero={upper_nz})  "
              f"{'PASS' if ok else 'FAIL'}")

    print(f"loaded {len(words)} words; {args.frames} frame(s) checked")
    print(f"AGGREGATE demod errors = {total_err} over "
          f"{args.frames * NBITS} bits")
    print("RESULT:", f"ALL {args.frames} FRAMES BER=0 PASS" if all_pass
          else "FAIL (>=1 frame nonzero BER)")
    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
