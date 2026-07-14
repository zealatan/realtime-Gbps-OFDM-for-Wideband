#!/usr/bin/env python3
"""
payload_to_img.py -- reconstruct a multi-frame image from the on-chip demod.

Reads the JTAG dump of xcvr_lb_buf (NFRAMES x 2652 int32 demod nibbles; demod
word packs {b0,b1,b2,b3} as [3]=b0..[0]=b3, b0=flat4[c*4+0]), inverts the
LSB-first packing from img_to_payload.py per frame, concatenates the frames,
rebuilds the WxH grayscale image, saves it as PNG, and compares to the original.
"""
import os
import sys
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 104, 102
NBYTES = W * H                   # 10608
FRAME_BYTES = 1326
NCARR = FRAME_BYTES * 8 // 4     # 2652 carriers/frame
NFRAMES = (NBYTES + FRAME_BYTES - 1) // FRAME_BYTES   # 8
UPSCALE = 5


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


def frame_nibbles_to_bytes(nib):
    """2652 nibbles -> 1326 bytes (inverse of the LSB-first + PRBS packer)."""
    n = nib.astype(np.uint8)
    # per carrier: flat bits [b0,b1,b2,b3] = [(n>>3),(n>>2),(n>>1),(n>>0)] & 1
    planes = np.stack([(n >> 3) & 1, (n >> 2) & 1,
                       (n >> 1) & 1, n & 1], axis=1)          # (2652,4)
    bits = planes.reshape(-1).astype(np.uint8) ^ DESCRAMBLE   # (10608,) de-whitened
    return np.packbits(bits, bitorder="little")               # (1326,) bytes


def main():
    binf = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(HERE, "..", "xcvr_lb_buf_video.bin")
    d = np.fromfile(binf, dtype="<i4")
    need = NFRAMES * NCARR
    if d.size < need:
        print(f"FAIL: dump too short ({d.size} < {need})")
        return 1
    nib = (d[:need] & 0xF).astype(np.uint8)

    out = np.zeros(NFRAMES * FRAME_BYTES, dtype=np.uint8)
    for f in range(NFRAMES):
        fn = nib[f * NCARR:(f + 1) * NCARR]
        out[f * FRAME_BYTES:(f + 1) * FRAME_BYTES] = frame_nibbles_to_bytes(fn)

    rec = out[:NBYTES].reshape(H, W)
    Image.fromarray(rec).resize((W * UPSCALE, H * UPSCALE),
                                Image.NEAREST).save(os.path.join(HERE, "image_recovered.png"))

    orig_raw = os.path.join(HERE, "image_orig.raw")
    if os.path.exists(orig_raw):
        orig = np.fromfile(orig_raw, dtype=np.uint8)
        ndiff = int(np.sum(orig != out[:NBYTES]))
        print(f"image {W}x{H} ({NFRAMES} frames): pixel diff {ndiff}/{NBYTES} "
              f"-> {'IDENTICAL (BER=0)' if ndiff == 0 else 'MISMATCH'}")
        both = np.concatenate([orig.reshape(H, W),
                               np.full((H, 3), 128, np.uint8), rec], axis=1)
        Image.fromarray(both).resize((both.shape[1] * UPSCALE, H * UPSCALE),
                                     Image.NEAREST).save(
            os.path.join(HERE, "image_sidebyside.png"))
        print(f"side-by-side -> {os.path.join(HERE, 'image_sidebyside.png')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
