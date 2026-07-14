#!/usr/bin/env python3
"""gen_bram_init.py — OFDM stimulus vector -> BRAM init artifacts.

Converts an OFDM stimulus vector into Vivado .coe + $readmemh .mem files so
the DMA-free digital-loopback stimulus player (dut_player) can initialize its
8192-deep x 32-bit stim BRAM.

All words represent IQ pairs packed as {Q[31:16], I[15:0]} (int16 Q15, Q in
the upper half) — matching scripts/pack_ddr_vectors.py:quantize_word():
    word = ((q & 0xFFFF) << 16) | (i & 0xFFFF)

Supported input formats (auto-detected by extension, overridable via --fmt):
  .hex / .mem / .txt : ASCII hex, one already-packed 32-bit word per line.
  .bin               : little-endian uint32 packed words (pack_ddr_vectors .bin).
  .f32               : little-endian float32, interleaved I,Q,I,Q... in [-1,1];
                       scaled by 32767 (Q15), rounded, clipped, then packed.

Usage:
    gen_bram_init.py --src <file> [--depth 8192] [--out-prefix <path>]
                     [--fmt hex|bin|f32]
"""

import argparse
import os
import struct
import sys

DEFAULT_DEPTH = 8192
Q15_SCALE = 32767
INT16_MIN = -32768
INT16_MAX = 32767
WORD_MASK = 0xFFFFFFFF


def detect_fmt(src, override):
    if override:
        return override
    ext = os.path.splitext(src)[1].lower()
    if ext in (".hex", ".mem", ".txt"):
        return "hex"
    if ext == ".bin":
        return "bin"
    if ext == ".f32":
        return "f32"
    raise ValueError(
        "Cannot auto-detect format for extension %r; pass --fmt." % ext)


def read_hex(src):
    """ASCII hex, one 32-bit word per line; already packed."""
    words = []
    with open(src, "r") as fh:
        for ln, raw in enumerate(fh, 1):
            tok = raw.strip()
            if not tok or tok.startswith(("//", "#")):
                continue
            tok = tok[2:] if tok.lower().startswith("0x") else tok
            try:
                words.append(int(tok, 16) & WORD_MASK)
            except ValueError:
                raise ValueError("line %d: not hex: %r" % (ln, raw.rstrip()))
    return words


def read_bin(src):
    """Little-endian uint32 packed words."""
    data = open(src, "rb").read()
    if len(data) % 4:
        raise ValueError(".bin length %d not a multiple of 4 bytes" % len(data))
    return [w & WORD_MASK for w in struct.unpack("<%dI" % (len(data) // 4), data)]


def read_f32(src):
    """Little-endian float32 interleaved I,Q,...; scale to Q15 and pack."""
    data = open(src, "rb").read()
    if len(data) % 4:
        raise ValueError(".f32 length %d not a multiple of 4 bytes" % len(data))
    flat = struct.unpack("<%df" % (len(data) // 4), data)
    if len(flat) % 2:
        raise ValueError(".f32 has odd float count %d (need I,Q pairs)" % len(flat))
    words = []
    for k in range(0, len(flat), 2):
        i = int(max(INT16_MIN, min(INT16_MAX, round(flat[k] * Q15_SCALE))))
        q = int(max(INT16_MIN, min(INT16_MAX, round(flat[k + 1] * Q15_SCALE))))
        words.append((((q & 0xFFFF) << 16) | (i & 0xFFFF)) & WORD_MASK)
    return words


READERS = {"hex": read_hex, "bin": read_bin, "f32": read_f32}


def first_nonzero(words):
    for idx, w in enumerate(words):
        if w != 0:
            return idx
    return -1


def write_mem(path, words):
    with open(path, "w") as fh:
        fh.write("".join("%08x\n" % w for w in words))


def write_coe(path, words):
    with open(path, "w") as fh:
        fh.write("memory_initialization_radix=16;\n")
        fh.write("memory_initialization_vector=\n")
        fh.write(",\n".join("%08x" % w for w in words))
        fh.write(";\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description="OFDM stimulus -> BRAM init (.mem + .coe)")
    ap.add_argument("--src", required=True, help="input vector file")
    ap.add_argument("--depth", type=int, default=DEFAULT_DEPTH,
                    help="BRAM depth in words (default %d)" % DEFAULT_DEPTH)
    ap.add_argument("--out-prefix", default=None,
                    help="output path prefix (default derived from --src)")
    ap.add_argument("--fmt", choices=sorted(READERS), default=None,
                    help="force input format (default: auto by extension)")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.src):
        ap.error("source not found: %s" % args.src)
    if args.depth <= 0:
        ap.error("--depth must be positive")

    fmt = detect_fmt(args.src, args.fmt)
    words = READERS[fmt](args.src)
    n = len(words)

    # Validate 32-bit fit (defensive; readers already mask).
    bad = [k for k, w in enumerate(words) if w < 0 or w > WORD_MASK]
    if bad:
        print("ERROR: %d word(s) do not fit 32-bit (first at index %d)"
              % (len(bad), bad[0]), file=sys.stderr)
        return 1

    if n > args.depth:
        print("WARNING: N=%d exceeds depth=%d; extra words will be DROPPED."
              % (n, args.depth), file=sys.stderr)
        words = words[:args.depth]
    else:
        words = words + [0] * (args.depth - n)

    prefix = args.out_prefix or os.path.splitext(os.path.abspath(args.src))[0]
    mem_path = prefix + ".mem"
    coe_path = prefix + ".coe"
    write_mem(mem_path, words)
    write_coe(coe_path, words)

    fnz = first_nonzero(words)
    print("input format detected : %s" % fmt)
    print("words read (N)        : %d" % n)
    print("BRAM depth            : %d" % args.depth)
    print("output .mem           : %s (%d lines)" % (mem_path, len(words)))
    print("output .coe           : %s (%d entries)" % (coe_path, len(words)))
    if fnz < 0:
        print("sanity                : all words zero (no non-zero sample)")
    else:
        print("sanity                : first non-zero word at index %d "
              "(64 guard zeros => expect 64 for tc0000)" % fnz)
    return 0


if __name__ == "__main__":
    sys.exit(main())
