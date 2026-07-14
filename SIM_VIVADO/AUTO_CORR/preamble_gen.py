#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import random
from pathlib import Path

# =========================================================
# Configuration
# =========================================================
FFT_SIZE = 256
CP_SIZE = 32
DELAY_MIN = 0
DELAY_MAX = 32
USE_FIXED_DELAY = True
FIXED_DELAY = 14

OUTPUT_FILE = "rtl_input_iq.txt"

# User-provided 32-bit IQ words (hex)
# Each word is assumed to be:
#   [31:16] = I (signed 16-bit)
#   [15: 0] = Q (signed 16-bit)
# Text file will store one 32-bit hex word per line.
SEED_WORDS_HEX = [
    "ffa1ffd1",
    "ffb1ffa1",
    "ffd1ffd1",
    "ff81ff81",
    "0000ff81",
    "ff91ff91",
    "002fffa1",
    "ff31ff91",
    "004fff91",
    "fee1ffc1",
    "00efff81",
    "fe81ffd1",
    "015fff71",
    "fe11ffa1",
    "01efffb1",
    "fd51ff11",
    "027f02ff",
    "f8f1248f",
    "02bfee31",
    "1bbfe011",
    "e1313c1f",
    "057fe121",
    "0c2fedf1",
]

# =========================================================
# Helpers
# =========================================================
def normalize_hex_word(word: str) -> str:
    """Normalize hex word to 8 lowercase hex chars."""
    word = word.strip().lower().replace("0x", "")
    if len(word) > 8:
        raise ValueError(f"Hex word too long: {word}")
    return word.zfill(8)

def build_symbol_from_seed(seed_words, fft_size):
    """
    Build one OFDM DATA symbol of length fft_size by repeating the seed words.
    """
    if not seed_words:
        raise ValueError("seed_words is empty")

    out = []
    idx = 0
    while len(out) < fft_size:
        out.append(seed_words[idx % len(seed_words)])
        idx += 1
    return out

def make_cp(data_words, cp_size):
    """
    CP is copied from the tail of the data.
    """
    if len(data_words) < cp_size:
        raise ValueError("DATA length must be >= CP length")
    return data_words[-cp_size:]

def make_delay(delay_len, fill_word="00000000"):
    """
    Delay region before the OFDM frame.
    Usually zeros, but can be changed if needed.
    """
    return [fill_word] * delay_len

def write_txt(words, filename):
    with open(filename, "w", encoding="utf-8") as f:
        for w in words:
            f.write(f"{w}\n")

def signed16(x: int) -> int:
    """Convert unsigned 16-bit to signed."""
    x &= 0xFFFF
    return x - 0x10000 if x & 0x8000 else x

def print_preview(words, title, count=8):
    print(f"\n[{title}] length = {len(words)}")
    for i, w in enumerate(words[:count]):
        val = int(w, 16)
        i_part = signed16((val >> 16) & 0xFFFF)
        q_part = signed16(val & 0xFFFF)
        print(f"  {i:03d}: {w}   I={i_part:6d}, Q={q_part:6d}")
    if len(words) > count:
        print("  ...")

# =========================================================
# Main
# =========================================================
def main():
    # Normalize input words
    seed_words = [normalize_hex_word(w) for w in SEED_WORDS_HEX]

    # Delay
    if USE_FIXED_DELAY:
        delay_len = FIXED_DELAY
    else:
        delay_len = random.randint(DELAY_MIN, DELAY_MAX)

    # Two OFDM data sections
    # Here I set data1 == data2 to mimic repeated preamble-style structure.
    # If you want different symbols, create data2 separately.
    data1 = build_symbol_from_seed(seed_words, FFT_SIZE)
    cp1 = make_cp(data1, CP_SIZE)

    data2 = build_symbol_from_seed(seed_words, FFT_SIZE)
    cp2 = make_cp(data2, CP_SIZE)

    delay = make_delay(delay_len, fill_word="00000000")

    # Final frame:
    # delay + cp1 + data1 + cp2 + data2
    frame = delay + cp1 + data1 + cp2 + data2

    # Write file
    write_txt(frame, OUTPUT_FILE)

    # Console summary
    print("Generated OFDM RTL input file")
    print(f"  output file : {OUTPUT_FILE}")
    print(f"  delay       : {delay_len}")
    print(f"  fft size    : {FFT_SIZE}")
    print(f"  cp size     : {CP_SIZE}")
    print(f"  frame len   : {len(frame)}")
    print(f"               = delay({delay_len}) + (cp+data)({CP_SIZE+FFT_SIZE}) + (cp+data)({CP_SIZE+FFT_SIZE})")

    print_preview(delay, "DELAY")
    print_preview(cp1, "CP1")
    print_preview(data1, "DATA1")
    print_preview(cp2, "CP2")
    print_preview(data2, "DATA2")

    # Sanity checks
    assert cp1 == data1[-CP_SIZE:], "CP1 is not copied from the tail of DATA1"
    assert cp2 == data2[-CP_SIZE:], "CP2 is not copied from the tail of DATA2"

    print("\nSanity check passed:")
    print("  CP1 == DATA1[-CP_SIZE:]")
    print("  CP2 == DATA2[-CP_SIZE:]")

if __name__ == "__main__":
    main()
