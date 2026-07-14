#!/usr/bin/env python3
"""
vid_to_img.py -- reconstruct the streamed COLOR video clip from the on-chip demod.

Reads the JTAG dump of xcvr_lb_buf (NFRAMES payload frames x 2652 demod nibbles),
inverts the LSB-first + PRBS packing per payload frame, regroups FPP payload
frames per video frame into VH x VW RGB, saves the recovered clip as GIF, and
verifies every pixel vs the original (vid_orig.raw).
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
VW, VH = 51, 26
NVFRAMES = 16
FPP = (VW * VH * 3) // 1326      # 3
NFRAMES = NVFRAMES * FPP         # 48
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


def frame_bytes(nib):
    n = nib.astype(np.uint8)
    planes = np.stack([(n >> 3) & 1, (n >> 2) & 1, (n >> 1) & 1, n & 1], axis=1)
    bits = planes.reshape(-1).astype(np.uint8) ^ DESCRAMBLE
    return np.packbits(bits, bitorder="little")      # 1326 bytes


def main():
    binf = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(HERE, "..", "xcvr_lb_buf_video.bin")
    d = np.fromfile(binf, dtype="<i4")
    need = NFRAMES * NCARR
    if d.size < need:
        print(f"FAIL: dump too short ({d.size} < {need})")
        return 1
    nib = (d[:need] & 0xF).astype(np.uint8)

    payload = np.concatenate([frame_bytes(nib[p * NCARR:(p + 1) * NCARR])
                              for p in range(NFRAMES)])          # NFRAMES*1326 bytes
    vid = payload.reshape(NVFRAMES, VH, VW, 3)                   # RGB video frames

    up = [Image.fromarray(vid[f], "RGB").resize((VW * UPSCALE, VH * UPSCALE),
                                                Image.NEAREST) for f in range(NVFRAMES)]
    gif = os.path.join(HERE, "vid_recovered.gif")
    up[0].save(gif, save_all=True, append_images=up[1:], duration=120, loop=0)
    print(f"recovered color GIF -> {gif}")

    orig_raw = os.path.join(HERE, "vid_orig.raw")
    if os.path.exists(orig_raw):
        orig = np.fromfile(orig_raw, dtype=np.uint8).reshape(NVFRAMES, VH, VW, 3)
        nbad = int(np.sum(orig != vid))
        bad_f = int(np.sum([np.any(orig[f] != vid[f]) for f in range(NVFRAMES)]))
        print(f"video {VW}x{VH} RGB x {NVFRAMES} frames: {NVFRAMES - bad_f}/{NVFRAMES} "
              f"pixel-perfect, byte diff {nbad}/{orig.size} "
              f"-> {'IDENTICAL (all BER=0)' if nbad == 0 else 'MISMATCH'}")
        both = [np.concatenate([orig[f], np.full((VH, 2, 3), 128, np.uint8), vid[f]],
                               axis=1) for f in range(NVFRAMES)]
        bup = [Image.fromarray(b, "RGB").resize((b.shape[1] * UPSCALE, VH * UPSCALE),
                                                Image.NEAREST) for b in both]
        sbs = os.path.join(HERE, "vid_sidebyside.gif")
        bup[0].save(sbs, save_all=True, append_images=bup[1:], duration=120, loop=0)
        print(f"side-by-side -> {sbs}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
