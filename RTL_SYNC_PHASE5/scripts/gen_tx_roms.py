#!/usr/bin/env python3
"""
gen_tx_roms.py
==============
Generate the TX-side ROM/vector files used by the OFDM transmitter RTL and
its test-benches.  All outputs are deterministic and derived from the SAME
sources as the golden RX-downstream vectors (ref/*.txt, the validated
rx_downstream_ref model, and golden/rx_downstream/), so the TX RTL is
bit-faithful to golden/rx_downstream/tx_slot_iq*.hex.

Outputs (rtl/tx_rom/):
  tx_specmap.hex   256 lines, 12-bit hex.  For each IFFT-input index i
                   (i = 0..255, spectrum is fed to the IFFT in fftshift /
                   rearrange_spectrum order), encodes what subcarrier goes
                   there:  word = (src<<2)|kind, kind: 0=zero,1=pilot,
                   2=data; src = pilot index 0..31 or data index 0..220.
  tx_sync_rom.hex  576 lines, 32-bit {Q,I} Q15.  The 2 REAL PSS/SSS sync
                   symbols (PSS_CP|PSS|SSS_CP|SSS) taken byte-identical from
                   golden/rx_downstream/tx_slot_iq.hex[64:640] (== fc_kp0).

Outputs (golden/tx/):
  tx_data_bits.hex  12 lines x 884 bits (== golden tx_bits.txt) for the TB.
  (pilot ROM + golden frame reuse golden/rx_downstream/ directly.)

numpy only.  Does NOT modify any RTL.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import rx_downstream_ref as R  # noqa: E402

OUT_RTL = os.path.join(ROOT, "rtl", "tx_rom")
GOLD    = os.path.join(ROOT, "golden", "rx_downstream")
NSC = R.NSC


def gen_specmap():
    kind = [0] * NSC
    src = [0] * NSC
    for p, idx in enumerate(R.PLT_INDX):
        kind[idx] = 1
        src[idx] = p
    for d, idx in enumerate(R.DATA_INDX):
        kind[idx] = 2
        src[idx] = d
    # TX feeds rearrange_spectrum(txSym) into the IFFT, i.e. IFFT input
    # index i carries natural bin (i+128) % 256.
    rom = []
    for i in range(NSC):
        nb = (i + 128) % NSC
        rom.append((src[nb] << 2) | kind[nb])
    path = os.path.join(OUT_RTL, "tx_specmap.hex")
    with open(path, "w") as f:
        for w in rom:
            f.write("%03X\n" % w)
    nz = sum(1 for w in rom if (w & 3) == 0)
    npil = sum(1 for w in rom if (w & 3) == 1)
    nd = sum(1 for w in rom if (w & 3) == 2)
    assert (nz, npil, nd) == (3, 32, 221), (nz, npil, nd)
    print(f"[specmap] {path}: zeros={nz} pilots={npil} data={nd}")


def gen_sync_rom():
    lines = open(os.path.join(GOLD, "tx_slot_iq.hex")).read().split()
    assert len(lines) == 4160, len(lines)
    sync = lines[64:640]
    assert len(sync) == 576
    path = os.path.join(OUT_RTL, "tx_sync_rom.hex")
    with open(path, "w") as f:
        f.write("\n".join(sync) + "\n")
    print(f"[sync] {path}: {len(sync)} words")


def gen_data_bits():
    os.makedirs(os.path.join(ROOT, "golden", "tx"), exist_ok=True)
    txb = open(os.path.join(GOLD, "tx_bits.txt")).read().split()
    assert len(txb) == 12, len(txb)
    path = os.path.join(ROOT, "golden", "tx", "tx_data_bits.txt")
    with open(path, "w") as f:
        f.write("\n".join(txb) + "\n")
    print(f"[bits] {path}: {len(txb)} symbols x {len(txb[0])} bits")


def gen_stage_golden():
    """Per-stage TX golden for the unit TBs (numpy, bit-faithful)."""
    import numpy as np
    OUTG = os.path.join(ROOT, "golden", "tx")
    os.makedirs(OUTG, exist_ok=True)
    Q15 = 5090.697374
    data_bits = R.load_bits(os.path.join(R.REF, "Data_Bits.txt"),
                            R.DATA_BITS_PER_BLOCK * R.NUM_DATA)
    pilot_bits = R.load_bits(os.path.join(R.REF, "Pilot_Bits.txt"),
                             R.PILOT_BITS_PER_BLOCK * R.NUM_DATA)

    def pack(iv, qv):
        iv = int(max(-32768, min(32767, round(iv)))) & 0xFFFF
        qv = int(max(-32768, min(32767, round(qv)))) & 0xFFFF
        return (qv << 16) | iv

    spec_lines = []
    for z in range(R.NUM_DATA):
        plt = np.array([R.mod_qpsk(pilot_bits[(z * 32 + p) * 2:(z * 32 + p) * 2 + 2])
                        for p in range(32)])
        dblk = data_bits[z * 884:(z + 1) * 884]
        txSym = np.zeros(256, dtype=complex)
        for i, idx in enumerate(R.PLT_INDX):
            txSym[idx] = plt[i]
        for k, idx in enumerate(R.DATA_INDX):
            txSym[idx] = R.mod_16qam(dblk[k * 4:k * 4 + 4])
        spec = R.rearrange_spectrum(txSym)
        for c in spec:
            spec_lines.append("%08X" % pack(c.real * Q15, c.imag * Q15))
    with open(os.path.join(OUTG, "tx_spec_in.hex"), "w") as f:
        f.write("\n".join(spec_lines) + "\n")
    print(f"[stage] tx_spec_in.hex: {len(spec_lines)} lines (IFFT input spectrum)")

    slot = open(os.path.join(GOLD, "tx_slot_iq_4032.hex")).read().split()
    assert len(slot) == 4032, len(slot)
    with open(os.path.join(OUTG, "tx_dsym_out.hex"), "w") as f:
        f.write("\n".join(slot[576:4032]) + "\n")     # 12*288 data symbols
    with open(os.path.join(OUTG, "tx_slot_4032.hex"), "w") as f:
        f.write("\n".join(slot) + "\n")                # full 4032 slot
    print("[stage] tx_dsym_out.hex: 3456 lines (12 data symbols CP+body)")
    print("[stage] tx_slot_4032.hex: 4032 lines (full TX slot)")


def main():
    os.makedirs(OUT_RTL, exist_ok=True)
    gen_specmap()
    gen_sync_rom()
    gen_data_bits()
    gen_stage_golden()
    print("[done] TX ROMs + stage golden generated")


if __name__ == "__main__":
    main()
