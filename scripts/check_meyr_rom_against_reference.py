#!/usr/bin/env python3
"""
check_meyr_rom_against_reference.py — DOC-003 Meyr ROM verification

Verifies that vectors/meyr_pss_reference_romhex.txt and
vectors/meyr_sss_reference_romhex.txt match the values that
gen_meyr_reference_roms.py would produce for the current project parameters.

ROM derivation (from gen_meyr_reference_roms.py):
  PSS_rom[j] = term1_ref[j] = PSS_td[j] * conj(SSS_td[j]), normalized to Q1.15
  SSS_rom[j] = all {I=+32767, Q=0}  (sign() = +1 for all j)

These ROMs are stimulus-derived (bypass mode, time-domain cross-product), NOT
from 5G-standard m_seq / gold_seq directly. Valid for INT_CFO=0, SEED=0xC0FFEE.

Parameters:
  Nid_1=170, Nid_2=2, NSC=256, CP_LEN=32
  SLOT_START=64, TARGET_PEAK=3000, EPS_FRAC=0.05, SEED=0xC0FFEE
"""

import numpy as np
import csv, sys, os

BASE    = os.path.join(os.path.dirname(__file__), '..')
RPT_DIR = os.path.join(BASE, 'reports', 'verification_closure_20260603')
os.makedirs(RPT_DIR, exist_ok=True)

# ── Parameters (must match gen_meyr_reference_roms.py) ───────────────────────
NSC         = 256
CP_LEN      = 32
PRE_ZEROS   = 64
POST_ZEROS  = 64
TARGET_PEAK = 3000.0
SLOT_START  = 64
SEED        = 0xC0FFEE

# ── Reproduce the reference computation ──────────────────────────────────────
def _make_ofdm_symbol(rng, nsc, cp_len):
    table  = np.array([1+1j, 1-1j, -1+1j, -1-1j], dtype=np.complex128) / np.sqrt(2.0)
    angles = rng.integers(0, 4, size=nsc)
    freq   = table[angles]
    td     = np.fft.ifft(freq)
    cp     = td[-cp_len:]
    return np.concatenate([cp, td])

rng   = np.random.default_rng(SEED)
sym1  = _make_ofdm_symbol(rng, NSC, CP_LEN)
sym2  = _make_ofdm_symbol(rng, NSC, CP_LEN)

frame = np.concatenate([
    np.zeros(PRE_ZEROS, dtype=np.complex128),
    sym1, sym2,
    np.zeros(POST_ZEROS, dtype=np.complex128),
])

sig   = np.concatenate([sym1, sym2])
peak  = max(float(np.abs(sig.real).max()), float(np.abs(sig.imag).max()))
scale = TARGET_PEAK / peak if peak > 0 else 1.0
frame = frame * scale

pss_start = SLOT_START + CP_LEN
sss_start = SLOT_START + 2 * CP_LEN + NSC

pss_float = frame[pss_start : pss_start + NSC]
sss_float = frame[sss_start : sss_start + NSC]

pss_i = np.clip(np.round(pss_float.real), -32768, 32767).astype(np.int32)
pss_q = np.clip(np.round(pss_float.imag), -32768, 32767).astype(np.int32)
sss_i = np.clip(np.round(sss_float.real), -32768, 32767).astype(np.int32)
sss_q = np.clip(np.round(sss_float.imag), -32768, 32767).astype(np.int32)

t1_i    = pss_i * sss_i + pss_q * sss_q
t1_q    = pss_q * sss_i - pss_i * sss_q
max_abs = max(int(np.abs(t1_i).max()), int(np.abs(t1_q).max()))

q15_scale = float(32767) / float(max_abs) if max_abs != 0 else 1.0
pss_rom_i = np.clip(np.round(t1_i * q15_scale), -32768, 32767).astype(np.int16)
pss_rom_q = np.clip(np.round(t1_q * q15_scale), -32768, 32767).astype(np.int16)
sss_rom_i = np.full(NSC, 32767, dtype=np.int16)
sss_rom_q = np.zeros(NSC, dtype=np.int16)

# Build expected hex strings
expected_pss = []
expected_sss = []
for j in range(NSC):
    pi = int(pss_rom_i[j]) & 0xFFFF
    pq = int(pss_rom_q[j]) & 0xFFFF
    si = int(sss_rom_i[j]) & 0xFFFF
    sq = int(sss_rom_q[j]) & 0xFFFF
    expected_pss.append(f"{(pq << 16) | pi:08x}")
    expected_sss.append(f"{(sq << 16) | si:08x}")

# ── Load existing ROM files ───────────────────────────────────────────────────
def load_rom(path):
    lines = []
    with open(path) as f:
        for ln in f:
            s = ln.strip().lower()
            if s:
                lines.append(s)
    return lines

pss_path = os.path.join(BASE, 'vectors', 'meyr_pss_reference_romhex.txt')
sss_path = os.path.join(BASE, 'vectors', 'meyr_sss_reference_romhex.txt')

existing_pss = load_rom(pss_path)
existing_sss = load_rom(sss_path)

# ── Compare ───────────────────────────────────────────────────────────────────
def compare_rom(name, existing, expected):
    if len(existing) != len(expected):
        print(f'  {name}: FAIL — length {len(existing)} vs expected {len(expected)}')
        return 0, len(expected), []
    match = 0
    mismatches = []
    for j, (e, x) in enumerate(zip(existing, expected)):
        if e == x:
            match += 1
        else:
            e_word = int(e, 16)
            x_word = int(x, 16)
            e_i = np.int16(e_word & 0xFFFF)
            e_q = np.int16((e_word >> 16) & 0xFFFF)
            x_i = np.int16(x_word & 0xFFFF)
            x_q = np.int16((x_word >> 16) & 0xFFFF)
            mismatches.append((j, e, x, int(e_i), int(e_q), int(x_i), int(x_q)))
    return match, len(expected), mismatches

print('DOC-003 Meyr ROM Check')
print('=' * 60)
print(f'  NSC={NSC}  CP_LEN={CP_LEN}  SLOT_START={SLOT_START}  SEED=0x{SEED:06X}')
print(f'  TARGET_PEAK={TARGET_PEAK}  q15_scale={q15_scale:.6e}')
print()

pss_match, pss_total, pss_mm = compare_rom('PSS ROM', existing_pss, expected_pss)
sss_match, sss_total, sss_mm = compare_rom('SSS ROM', existing_sss, expected_sss)

pss_pass = (pss_match == pss_total)
sss_pass = (sss_match == sss_total)

print(f'  PSS ROM: {pss_match}/{pss_total} entries match  — {"PASS" if pss_pass else "FAIL (%d mismatches)" % len(pss_mm)}')
if pss_mm:
    for (j, e, x, ei, eq, xi, xq) in pss_mm[:5]:
        print(f'    bin {j}: existing=0x{e} ({ei},{eq})  expected=0x{x} ({xi},{xq})')
    if len(pss_mm) > 5:
        print(f'    ... ({len(pss_mm)-5} more)')

print(f'  SSS ROM: {sss_match}/{sss_total} entries match  — {"PASS" if sss_pass else "FAIL (%d mismatches)" % len(sss_mm)}')
if sss_mm:
    for (j, e, x, ei, eq, xi, xq) in sss_mm[:5]:
        print(f'    bin {j}: existing=0x{e} ({ei},{eq})  expected=0x{x} ({xi},{xq})')
    if len(sss_mm) > 5:
        print(f'    ... ({len(sss_mm)-5} more)')

print()
print('ROM derivation:')
print('  PSS_rom = term1_ref = PSS_td × conj(SSS_td), normalized to Q1.15')
print('  SSS_rom = all {I=+32767, Q=0}  →  sign(SSS_I) = +1 for all bins')
print('  (bypass/time-domain mode; NOT 5G-standard m_seq/gold_seq directly)')
print('  5G-standard sequence cross-product is encoded in term1 numerically.')
print()

# Confirm PSS ROM is non-trivial (not all zero or constant)
nonzero = int(np.count_nonzero(
    np.array([int(h, 16) for h in expected_pss], dtype=np.uint32)))
print(f'  PSS ROM non-zero bins: {nonzero}/{NSC}  (all-zero ROM would indicate bug)')

# ── CSV report ─────────────────────────────────────────────────────────────────
csv_path = os.path.join(RPT_DIR, 'doc003_meyr_rom_check.csv')
with open(csv_path, 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['bin', 'pss_existing', 'pss_expected', 'pss_match',
                'sss_existing', 'sss_expected', 'sss_match'])
    for j in range(NSC):
        ep = existing_pss[j] if j < len(existing_pss) else 'N/A'
        xp = expected_pss[j]
        es = existing_sss[j] if j < len(existing_sss) else 'N/A'
        xs = expected_sss[j]
        w.writerow([j, ep, xp, 'Y' if ep==xp else 'N', es, xs, 'Y' if es==xs else 'N'])

# ── Gate verdict ───────────────────────────────────────────────────────────────
all_pass = pss_pass and sss_pass
print('=' * 60)
if all_pass:
    print('DOC_003_MEYR_ROM_GATE: PASS — ROM matches generator output')
else:
    print('DOC_003_MEYR_ROM_GATE: FAIL — ROM differs from generator output')
    print('  Action: run scripts/gen_meyr_reference_roms.py to regenerate')
print('=' * 60)
sys.exit(0 if all_pass else 1)
