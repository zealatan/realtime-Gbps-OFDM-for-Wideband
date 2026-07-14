#!/usr/bin/env python3
"""
anim_to_img.py -- reconstruct the streamed animation from the on-chip demod.

Reads the JTAG dump of xcvr_lb_buf (NFRAMES x 2652 demod nibbles), inverts the
LSB-first + PRBS packing per frame, rebuilds each 39x34 grayscale frame, saves
the recovered animation as GIF, and verifies every frame is BER=0 vs the
original (anim_orig.raw).
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 39, 34
NFRAMES = 16
FRAME_BYTES = 1326
NCARR = 2652
UPSCALE = 8


def prbs_bits(n, seed=0xACE1):
    lfsr = seed & 0xFFFF
    out = np.zeros(n, dtype=np.uint8)
    for i in range(n):
        bit = lfsr & 1
        out[i] = bit
        lfsr >>= 1
        if bit:
            lfsr ^= 0xB400
    return out


DESCRAMBLE = prbs_bits(10608)


def frame_to_img(nib):
    n = nib.astype(np.uint8)
    planes = np.stack([(n >> 3) & 1, (n >> 2) & 1, (n >> 1) & 1, n & 1], axis=1)
    bits = planes.reshape(-1).astype(np.uint8) ^ DESCRAMBLE
    b = np.packbits(bits, bitorder="little")
    return b[:W * H].reshape(H, W)


def main():
    binf = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(HERE, "..", "xcvr_lb_buf_video.bin")
    d = np.fromfile(binf, dtype="<i4")
    need = NFRAMES * NCARR
    if d.size < need:
        print(f"FAIL: dump too short ({d.size} < {need})")
        return 1
    nib = (d[:need] & 0xF).astype(np.uint8)

    orig = None
    orig_raw = os.path.join(HERE, "anim_orig.raw")
    if os.path.exists(orig_raw):
        orig = np.fromfile(orig_raw, dtype=np.uint8).reshape(NFRAMES, H, W)

    recs, nbad_frames, total_bad = [], 0, 0
    for f in range(NFRAMES):
        rec = frame_to_img(nib[f * NCARR:(f + 1) * NCARR])
        recs.append(rec)
        if orig is not None:
            nb = int(np.sum(orig[f] != rec))
            total_bad += nb
            if nb:
                nbad_frames += 1

    up = [Image.fromarray(r).resize((W * UPSCALE, H * UPSCALE), Image.NEAREST)
          for r in recs]
    gif = os.path.join(HERE, "anim_recovered.gif")
    up[0].save(gif, save_all=True, append_images=up[1:], duration=120, loop=0)
    print(f"recovered GIF -> {gif}")
    if orig is not None:
        print(f"frames: {NFRAMES - nbad_frames}/{NFRAMES} pixel-perfect, "
              f"total pixel diff {total_bad}/{NFRAMES * W * H} "
              f"-> {'IDENTICAL (all BER=0)' if total_bad == 0 else 'MISMATCH'}")
        # side-by-side GIF (orig | recovered)
        both = [np.concatenate([orig[f], np.full((H, 2), 128, np.uint8), recs[f]],
                               axis=1) for f in range(NFRAMES)]
        bup = [Image.fromarray(b).resize((b.shape[1] * UPSCALE, H * UPSCALE),
                                         Image.NEAREST) for b in both]
        sbs = os.path.join(HERE, "anim_sidebyside.gif")
        bup[0].save(sbs, save_all=True, append_images=bup[1:], duration=120, loop=0)
        print(f"side-by-side  -> {sbs}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
