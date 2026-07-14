#!/usr/bin/env python3
"""
xcvr_tx_slot_check.py
=====================
TX-mode silicon verify: compare the captured EMITTED OFDM slot (ofdm_xcvr_board_top
TX mode -> m_axis -> dut_capture, 4032 IQ words {Q[31:16],I[15:0]}) against the
golden RTL slot golden/rx_downstream/tx_slot_iq_4032.hex.

PASS criteria (mirrors the sim gate MODE0):
  - the 2 PSS words (first sync-symbol head) are BYTE-EXACT
  - every data sample is within an LSB budget (default 3 LSB) of golden, the
    IFFT block-floating-point rounding budget.
"""
import sys, os, argparse
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GOLD = os.path.join(ROOT, "RTL_SYNC_PHASE5", "golden", "rx_downstream",
                    "tx_slot_iq_4032.hex")

SLOT = 4032


def split_iq(words):
    w = np.asarray(words, dtype=np.uint32)
    q = (w >> 16).astype(np.int32)
    i = (w & 0xFFFF).astype(np.int32)
    q = np.where(q >= 0x8000, q - 0x10000, q)
    i = np.where(i >= 0x8000, i - 0x10000, i)
    return i, q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True, help="JTAG mrd -bin dump of xcvr_tx_buf")
    ap.add_argument("--lsb", type=int, default=3, help="per-sample LSB budget")
    args = ap.parse_args()

    cap = np.fromfile(args.bin, dtype="<u4")
    if len(cap) < SLOT:
        print(f"FATAL: only {len(cap)} words, need {SLOT}")
        return 2
    cap = cap[:SLOT]

    gold = []
    for line in open(GOLD):
        line = line.strip()
        if line:
            gold.append(int(line, 16))
    gold = np.array(gold[:SLOT], dtype=np.uint32)
    assert len(gold) == SLOT, len(gold)

    # PSS byte-exact (first 2 words; word0 should be 0xFAC111BD)
    pss_ok = bool(cap[0] == gold[0] and cap[1] == gold[1])
    print(f"PSS word0 cap=0x{cap[0]:08X} gold=0x{gold[0]:08X}  "
          f"word1 cap=0x{cap[1]:08X} gold=0x{gold[1]:08X}  "
          f"{'BYTE-EXACT' if pss_ok else 'MISMATCH'}")

    ci, cq = split_iq(cap)
    gi, gq = split_iq(gold)
    di = np.abs(ci - gi)
    dq = np.abs(cq - gq)
    maxd = int(max(di.max(), dq.max()))
    nbad = int(np.sum((di > args.lsb) | (dq > args.lsb)))
    exact = int(np.sum((di == 0) & (dq == 0)))
    print(f"slot {SLOT} samples: max|delta|={maxd} LSB, "
          f"exact={exact}/{SLOT}, over-budget(>{args.lsb})={nbad}")

    ok = pss_ok and (nbad == 0)
    print("RESULT:", "TX SLOT MATCH PASS" if ok
          else f"FAIL (pss_ok={pss_ok} over_budget={nbad} maxd={maxd})")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
