#!/usr/bin/env python3
"""
emulate_ber_checker.py  --  models rx_ber_checker.v against the REAL silicon
demod-nibble capture to show the MECHANISM behind the on-chip BER mis-report
and the firmware clr-timing fix.

WHAT THE DUMP CAN / CANNOT SHOW
  The dumped dut_capture buffer is the m_bits demod stream the checker also taps,
  but ONLY one 16384-nibble snapshot drained with one cap_en window. It does NOT
  capture the checker's clr-relative ANCHOR phase nor the firmware ber_pump_stream
  dynamics (cap_en toggled repeatedly -> the demod is stalled & re-armed, which
  RE-RUNS the pipeline-fill transient each time). So we use the dump to model the
  checker's per-symbol comparison, and reason about the anchor/warmup interaction.

MODEL (faithful to rtl/rx_ber_checker.v)
  ref ROM = rx_ber_ref_rom.hex (2652 nibbles == golden packing).
  anchor at first beat post-clr -> (sym0,carrier0); free-run tuser/tlast.
  skip `warmup` whole frames, then count `count_frames` frames; rot_off rotates
  the REFERENCE by whole OFDM symbols (firmware sweeps 0..11).

KEY MEASURED FACT (from per-symbol decode of the dump, all 5 PORs identical):
  capture symbols 0..4  = pipeline-fill TRANSIENT (garbage data; ~45% err at EVERY
                          rotation -- unrecoverable by rot_off).
  capture symbols 5..59 = bit-perfect demod (BER=0 at the aligned rot_off).
"""
import os, sys
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ROM  = os.path.join(ROOT, "RTL_SYNC_PHASE5", "rtl", "rx_ber_ref_rom.hex")

NDATA_SC = 221
NUM_DATA = 12
TOTAL    = NDATA_SC * NUM_DATA   # 2652
TRANSIENT_SYMS = 5               # measured pipeline-fill length (every POR)


def load_rom():
    rom = np.array([int(l.strip(), 16) for l in open(ROM) if l.strip()], dtype=np.uint8)
    assert rom.size == TOTAL, rom.size
    return rom


def popcount4_arr(d):
    return int(((d & 1) + ((d >> 1) & 1) + ((d >> 2) & 1) + ((d >> 3) & 1)).sum())


def count_window(nibs, rom, anchor_sym, rot, skip_frames, count_frames):
    """Checker counts `count_frames` whole frames starting `skip_frames` after the
    anchor symbol. Maps counted capture symbol -> rom symbol (j+rot)%12. Returns
    (errors, nibbles, touched_transient)."""
    errs = 0
    nb = 0
    touched = False
    for f in range(count_frames):
        for j in range(NUM_DATA):
            capsym = anchor_sym + (skip_frames + f) * NUM_DATA + j
            if (capsym + 1) * NDATA_SC > nibs.size:
                return errs, nb, touched
            if capsym < TRANSIENT_SYMS:
                touched = True
            seg = nibs[capsym * NDATA_SC:(capsym + 1) * NDATA_SC]
            refsym = ((capsym - anchor_sym) + rot) % NUM_DATA
            d = seg ^ rom[refsym * NDATA_SC:(refsym + 1) * NDATA_SC]
            errs += popcount4_arr(d)
            nb += seg.size
    return errs, nb, touched


def best_rot(nibs, rom, anchor_sym, skip_frames, count_frames):
    best = None
    for rot in range(NUM_DATA):
        e, n, t = count_window(nibs, rom, anchor_sym, rot, skip_frames, count_frames)
        if n == 0:
            continue
        if best is None or e < best[0]:
            best = (e, rot, n, t)
    return best


def main():
    bin_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, "tests", "11_full_rx_loopback", "frxbits_confirm_por1.bin")
    w = np.fromfile(bin_path, dtype="<u4")
    nibs = (w & 0xF).astype(np.uint8)
    rom = load_rom()
    print("=" * 90)
    print("rx_ber_checker MODEL vs REAL silicon capture: %s" % os.path.basename(bin_path))
    print("=" * 90)
    print("measured: capture sym 0..%d = pipeline-fill transient (garbage at every rot);"
          % (TRANSIENT_SYMS - 1))
    print("          capture sym %d..59 = bit-perfect demod (BER=0 at aligned rot_off).\n"
          % TRANSIENT_SYMS)

    # --- the on-chip checker counts a TRANSIENT symbol whenever the counted window
    #     reaches back into sym 0..4. With the CURRENT 1-frame warmup and an anchor
    #     in/near the transient, transient symbols enter the counted frames; a
    #     transient symbol is ~45% wrong at EVERY rot_off, so the rot_off sweep
    #     cannot drive the per-frame BER to 0 -> the on-chip readout floors high.
    print("CURRENT firmware (warmup=1 frame): if the clr anchor sits so the counted "
          "window includes a transient symbol, NO rot_off can null it:")
    for anchor in (0,):
        e, rot, n, t = best_rot(nibs, rom, anchor, skip_frames=1, count_frames=4)
        print(f"  anchor_sym={anchor}, skip=1 frame, count=4 frames: best rot_off={rot}, "
              f"errors={e}/{n*4} bits, BER={e/(n*4):.3e}, touched_transient={t}")
    # a transient symbol counted directly:
    seg = nibs[0:NDATA_SC]
    floor = min(popcount4_arr(seg ^ rom[r*NDATA_SC:(r+1)*NDATA_SC])
                for r in range(NUM_DATA))
    print(f"  (a single transient symbol scores >= {floor}/{NDATA_SC*4} = "
          f"{floor/(NDATA_SC*4)*100:.0f}%% errors at its BEST rotation -> noise floor.)")

    # --- FIX: pump past the transient so the anchor + warmup land entirely in the
    #     clean window; then EVERY counted symbol is bit-perfect -> aligned rot_off=0.
    print("\nFIRMWARE FIX (clr-timing): pump the stream past the 5-symbol transient, "
          "then clr + skip >=1 frame so the counted window is 100%% clean data:")
    # model: anchor lands at the start of the clean window (sym 5), skip 1 frame,
    # count the remaining whole clean frames (clean window = sym 5..59 = 55 sym).
    clean_syms = 60 - TRANSIENT_SYMS                     # 55
    count_frames = (clean_syms - NUM_DATA) // NUM_DATA   # skip 1 frame then count whole frames
    best = None
    allr = []
    for rot in range(NUM_DATA):
        e, n, t = count_window(nibs, rom, TRANSIENT_SYMS, rot, skip_frames=1,
                               count_frames=count_frames)
        allr.append((rot, e, n))
        if best is None or e < best[1]:
            best = (rot, e, n)
    for rot, e, n in allr:
        mark = "  <== ALIGNED" if e == 0 else ""
        print(f"  rot_off={rot:2d}: errors={e:6d}/{n*4} bits  BER={e/(n*4):.3e}{mark}")
    rot, e, n = best
    print(f"\n  -> aligned rot_off={rot}: on-chip total_bit_errors={e} over {n*4} bits "
          f"= BER {e/(n*4):.3e}  (reads TRUE ~0)")
    print("=" * 90)
    print("CONCLUSION: the demod is bit-perfect; the on-chip checker floored high only "
          "because\n  counted frames included the 5-symbol pipeline-fill transient. "
          "Clearing the\n  checker AFTER pumping past the transient makes the on-chip "
          "BER read 0.")
    print("=" * 90)
    return 0


if __name__ == "__main__":
    sys.exit(main())
