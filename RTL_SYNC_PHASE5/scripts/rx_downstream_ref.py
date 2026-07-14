#!/usr/bin/env python3
"""
rx_downstream_ref.py
====================

Bit-faithful Python reference model for the OFDM RX *downstream* chain
(FFT -> Channel-Estimation -> Equalize -> 16-QAM demod), ported directly
from the C reference in ref/ (transmitter.c, receiver.c,
signal_processing_common.c, auxiliary.c, pluto.h).

It also implements the matching TX so we can build a PROPER OFDM frame
(16-QAM data on 221 data carriers + QPSK pilots on 32 pilot carriers,
IDFT(256), CP(32)) and validate the full loop end-to-end.

With an identity channel (no noise) the loop BER MUST be exactly 0.

Outputs per-stage golden vectors into golden/rx_downstream/ and a
CONTRACT.md describing the interfaces for the 4 RTL subagents.

numpy only (no scipy).

----------------------------------------------------------------------
EXACT C-REFERENCE CONVENTIONS REPRODUCED HERE
----------------------------------------------------------------------
- NSC=256, CP_LEN=32, symbol=288. Slot = 2 sync + 12 data = 14 sym = 4032.
- numPilots=32, num_data_subcarrier = 256-32-3 = 221.
- pltIndx[i] = 1 + floor(i * 256/32) = 1 + 8*i  (i=0..31) -> {1,9,...,249}
  (transmitter.c get_pilot_indexes_for_fft_interpolation_toan, l.407)
- dataIndx: for i in 1..254, skip pltIndx, skip DC(128) -> 221 carriers.
- 16-QAM (transmitter.c generate_symbol_16qam):
    map16QAM = {-1,-3,1,3}*SCALE_16QAM, SCALE_16QAM = 1/sqrt(10).
    tmpI = b0*2 + b1*1 ; tmpQ = b2*2 + b3*1 ; symI=map[tmpI], symQ=map[tmpQ].
- QPSK pilot (transmitter.c generate_symbol_qpsk):
    symI=(b0?1:-1)*SCALE_QPSK, symQ=(b1?1:-1)*SCALE_QPSK, SCALE_QPSK=1/sqrt(2).
- FFTW conventions:
    FFTW_FORWARD  = exp(-j2pi kn/N), unnormalized      == np.fft.fft
    FFTW_BACKWARD = exp(+j2pi kn/N), unnormalized      == N*np.fft.ifft
- TX modulate (transmitter.c l.104-108):
    build spectrum txSym[NSC] -> rearrange_spectrum (fftshift, in-place swap
    halves) -> ifft_new (FFTW_BACKWARD then /sqrt(NSC)) -> insert_cp (copy
    last CP_LEN samples of the NSC body to the front).
- RX (receiver.c l.123-176) per data block z:
    generate_complex_symbol (drop CP, take NSC samples) ->
    fft_with_rearrange (FFTW_FORWARD -> rearrange_spectrum -> /sqrt(NSC)) ->
    ch_estimation_fdm (H[pltIndx]=rx*conj(plt)/|plt|^2) ->
    interp_fft (32-pt IFFT of pilot-H into low taps, zero rest, 256-pt FFT) ->
    memcpy H into HestI[1..254] (offset +1; HestI[0],HestI[255] left 0) ->
    fde ZF (RXSig*conj(H)/|H|^2) ->
    extract dataIndx carriers -> decode_16qam.

DATA / PILOT BIT SOURCE
-----------------------
We read ref/Data_Bits.txt and ref/Pilot_Bits.txt verbatim, exactly like the
C reference (signal_processing_common.c l.54-110). This makes the golden
deterministic AND identical to what the C program would produce, and gives
the RTL pilot ROM an unambiguous source. No RNG / seed is used.
  - Data: first 221*4*12 = 10608 bits consumed (one bit per line, 0.0/1.0).
  - Pilot: first 32*2*12 = 768 bits consumed.
Both files contain 16384 lines; surplus is ignored (matches C while-loop
bound).
"""

import os
import numpy as np

# ----------------------------------------------------------------------
# constants (pluto.h / signal_processing_common.c)
# ----------------------------------------------------------------------
NSC        = 256
CP_LEN     = 32
SYM_LEN    = NSC + CP_LEN            # 288
NUM_SYN    = 2                       # sync symbols (not demodulated here)
NUM_DATA   = 12
SLOT_LEN   = (NUM_SYN + NUM_DATA) * SYM_LEN   # 4032
NUM_PILOTS = 32
NUM_DATA_SC = NSC - NUM_PILOTS - 3   # 221
QAM16_BPS  = 4                       # bits per 16-QAM symbol
QPSK_BPS   = 2
DATA_BITS_PER_BLOCK = NUM_DATA_SC * QAM16_BPS    # 884
PILOT_BITS_PER_BLOCK = NUM_PILOTS * QPSK_BPS      # 64

SCALE_16QAM = 1.0 / np.sqrt(10.0)    # 0.316227766...
SCALE_QPSK  = 1.0 / np.sqrt(2.0)     # 0.707106781...

# ----------------------------------------------------------------------
# multi-modulation (Phase 1): runtime-selectable square QAM on the DATA
# subcarriers.  Pilots STAY QPSK (used by CE) for every modulation.
#   mod_sel : 0=QPSK 1=16QAM 2=64QAM 3=256QAM
#   k (bits/axis) = mod_sel+1 ; bits/sym = 2*k ; nlev=2^k levels/axis.
#   per-mod SCALE = 1/sqrt(2/3*(M-1)) with M=2^(2k) -> {1/sqrt2,1/sqrt10,
#   1/sqrt42,1/sqrt170} : matched average symbol power = 1.
# Folded-Gray per axis: axis k bits a[0..k-1], a[0]=MSB=sign(1=pos),
# a[1..k-1]=Gray(m), value=+/-(2m+1). For k=2 this is bit-exact identical
# to the legacy 16-QAM map ({-1,-3,1,3} at code 00,01,10,11).
# ----------------------------------------------------------------------
MOD_NAMES = {0: "qpsk", 1: "16qam", 2: "64qam", 3: "256qam"}
MOD_K     = {0: 1, 1: 2, 2: 3, 3: 4}            # bits/axis
MOD_SCALE = {0: 1.0/np.sqrt(2.0), 1: 1.0/np.sqrt(10.0),
             2: 1.0/np.sqrt(42.0), 3: 1.0/np.sqrt(170.0)}


def _gray(n):
    return n ^ (n >> 1)


def _ungray(g):
    n = 0
    while g:
        n ^= g
        g >>= 1
    return n


def axis_bits_to_value(axis_bits, k):
    """k-bit folded-Gray axis code (MSB first = a[0]) -> odd integer level."""
    sign_pos = axis_bits[0]
    g = 0
    for b in axis_bits[1:]:
        g = (g << 1) | int(b)
    m = _ungray(g)
    return (2 * m + 1) if sign_pos else -(2 * m + 1)


def value_to_axis_bits(val, k):
    """odd integer level -> k-bit folded-Gray axis code (MSB first)."""
    sign_pos = 1 if val > 0 else 0
    m = (abs(int(val)) - 1) // 2
    g = _gray(m)
    bits = [sign_pos]
    for i in range(k - 2, -1, -1):
        bits.append((g >> i) & 1)
    return bits


def mod_qam(bits, mod_sel):
    """bits-per-symbol (2*k) bits -> complex symbol for the given modulation.
    bits layout [I axis k bits | Q axis k bits], a[0]=sign. 16-QAM(k=2)
    reduces to the legacy mod_16qam exactly."""
    k = MOD_K[mod_sel]
    S = MOD_SCALE[mod_sel]
    iax = axis_bits_to_value([int(b) for b in bits[0:k]], k)
    qax = axis_bits_to_value([int(b) for b in bits[k:2 * k]], k)
    return (iax * S) + 1j * (qax * S)


def demod_qam(sym, mod_sel, q15_scale):
    """hard-slice a complex sample to 2*k bits for the given modulation.
    Slices each axis to the nearest odd level using the SAME integer-step
    rule the RTL uses (STEP=round(2*S*Q15)), then folded-Gray encodes it.
    Returns 2*k bits [I axis k | Q axis k], a[0]=sign."""
    k = MOD_K[mod_sel]
    S = MOD_SCALE[mod_sel]
    nlev = 1 << k
    step = round(2 * S * q15_scale)

    def slice_axis(v_float):
        v = int(round(v_float * q15_scale))   # Q15 integer (match RTL input)
        sign_pos = 1 if v >= 0 else 0
        av = abs(v)
        m = av // step
        if m > nlev // 2 - 1:
            m = nlev // 2 - 1
        lvl = (2 * m + 1) if sign_pos else -(2 * m + 1)
        return value_to_axis_bits(lvl, k)

    return slice_axis(sym.real) + slice_axis(sym.imag)

# Q15 fixed-point scale for the TX time-domain slot (M_AXIS input to fft
# frontend). The OFDM time-domain peak amplitude is ~2.47 (high PAPR), so a
# 2^14 scale would clip. We use 2^13 == amplitude 1.0, giving the peak
# (~2.47 -> ~20200) comfortable headroom inside int16 (no clipping). The
# constellation/spectrum-domain values (fft_out, hest~1.0, eq~unit-16QAM)
# remain well-resolved at this scale.
Q15_SCALE = 8192.0                   # 2^13 == amplitude 1.0

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REF  = os.path.join(ROOT, "ref")
OUT  = os.path.join(ROOT, "golden", "rx_downstream")

# ----------------------------------------------------------------------
# index tables
# ----------------------------------------------------------------------
def build_indexes():
    """Reproduce get_pilot_indexes_for_fft_interpolation_toan (transmitter.c)."""
    pilot_dist = NSC / NUM_PILOTS                       # 8.0
    pltIndx = [1 + int(np.floor(i * pilot_dist)) for i in range(NUM_PILOTS)]
    if pltIndx[-1] > NSC - 1:
        pltIndx[-1] = NSC - 1
    pltset = set(pltIndx)
    dataIndx = []
    k = 0
    for i in range(1, NSC - 1):          # 1 .. 254
        if k < len(pltIndx) and i == pltIndx[k]:
            k += 1
        elif i != (NSC // 2):            # skip DC (128)
            dataIndx.append(i)
    assert len(dataIndx) == NUM_DATA_SC, len(dataIndx)
    return pltIndx, dataIndx

PLT_INDX, DATA_INDX = build_indexes()

# ----------------------------------------------------------------------
# modulation / demodulation (transmitter.c / receiver.c)
# ----------------------------------------------------------------------
def mod_16qam(bits4):
    """bits4 = [b0,b1,b2,b3] -> complex sym. (generate_symbol_16qam)"""
    m = np.array([-1, -3, 1, 3], dtype=float) * SCALE_16QAM
    tmpI = int(bits4[0]) * 2 + int(bits4[1]) * 1
    tmpQ = int(bits4[2]) * 2 + int(bits4[3]) * 1
    return m[tmpI] + 1j * m[tmpQ]

def mod_qpsk(bits2):
    """generate_symbol_qpsk"""
    si = (1.0 if bits2[0] else -1.0) * SCALE_QPSK
    sq = (1.0 if bits2[1] else -1.0) * SCALE_QPSK
    return si + 1j * sq

def demod_16qam(sym):
    """decode_16qam -> 4 bits [b0,b1,b2,b3]. thresholds {-2,0,2}*SCALE."""
    d0 = -2 * SCALE_16QAM
    d1 = 0.0
    d2 = 2 * SCALE_16QAM
    re = sym.real
    im = sym.imag
    b = [0, 0, 0, 0]
    if re < d0:
        b[0], b[1] = 0, 1
    elif re < d1:
        b[0], b[1] = 0, 0
    elif re < d2:
        b[0], b[1] = 1, 0
    else:
        b[0], b[1] = 1, 1
    if im < d0:
        b[2], b[3] = 0, 1
    elif im < d1:
        b[2], b[3] = 0, 0
    elif im < d2:
        b[2], b[3] = 1, 0
    else:
        b[2], b[3] = 1, 1
    return b

# ----------------------------------------------------------------------
# FFT helpers matching the C / FFTW conventions exactly
# ----------------------------------------------------------------------
def rearrange_spectrum(x):
    """In-place half-swap == np.fft.fftshift for even length (receiver.c)."""
    n = len(x)
    h = n // 2
    return np.concatenate([x[h:], x[:h]])

def fftw_forward(x):
    return np.fft.fft(x)            # exp(-j), unnormalized

def fftw_backward(x):
    return len(x) * np.fft.ifft(x)  # exp(+j), unnormalized

# ----------------------------------------------------------------------
# TX (transmitter.c add_data_in_slot loop)
# ----------------------------------------------------------------------
def tx_modulate_block(data_bits_block, plt_block, mod_sel=1):
    """One OFDM data symbol (288 samples) from the block's data bits + 32
    QPSK pilots, for the given modulation. data_bits_block has
    NUM_DATA_SC*(2*MOD_K[mod_sel]) bits. Returns (sym288, spectrum256)."""
    bps = 2 * MOD_K[mod_sel]
    txSym = np.zeros(NSC, dtype=complex)
    # insert pilots (transmitter.c l.96) -- always QPSK
    for i, idx in enumerate(PLT_INDX):
        txSym[idx] = plt_block[i]
    # insert data (transmitter.c l.101)
    for k, idx in enumerate(DATA_INDX):
        b = data_bits_block[k * bps:(k + 1) * bps]
        txSym[idx] = mod_qam(b, mod_sel)
    # rearrange (fftshift) then IFFT/sqrt(N) (l.104-106)
    spec = rearrange_spectrum(txSym)
    body = fftw_backward(spec) / np.sqrt(NSC)     # NSC samples
    # insert_cp: prepend last CP_LEN of body (l.108)
    sym = np.concatenate([body[NSC - CP_LEN:], body])
    return sym, txSym

# ----------------------------------------------------------------------
# RX downstream chain (receiver.c process_received_slot l.93-176)
# ----------------------------------------------------------------------
def rx_fft(sym288):
    """generate_complex_symbol (drop CP) + fft_with_rearrange."""
    body = sym288[CP_LEN:CP_LEN + NSC]
    spec = fftw_forward(body)
    spec = rearrange_spectrum(spec)
    return spec / np.sqrt(NSC)

def ch_estimation_fdm(rxSym, plt_block):
    """receiver.c ch_estimation_fdm. Returns H over 256 bins, only pilot
    bins populated, others 0."""
    H = np.zeros(NSC, dtype=complex)
    for k, i in enumerate(PLT_INDX):
        p = plt_block[k]
        tmp = (p.real * p.real + p.imag * p.imag)
        Hi = (rxSym[i].real * p.real + rxSym[i].imag * p.imag) / tmp
        Hq = (rxSym[i].imag * p.real - rxSym[i].real * p.imag) / tmp
        H[i] = Hi + 1j * Hq
    return H

def interp_fft(H_pilots):
    """receiver.c interp_fft. Input: H over 256 bins (pilot bins set).
    Returns interpolated H over 256 bins."""
    mid = NSC // 2                       # 128
    hi = np.zeros(NSC, dtype=complex)
    # copy CTF pilot samples to second half (l.1398)
    for i in range(NUM_PILOTS):
        hi[mid + i] = H_pilots[PLT_INDX[i]]
    # numPilots-point IFFT of those, /numPilots, into first half (l.1404-1410)
    pilot_in = hi[mid:mid + NUM_PILOTS]
    pilot_out = fftw_backward(pilot_in) / NUM_PILOTS
    hnew = np.zeros(NSC, dtype=complex)
    hnew[:NUM_PILOTS] = pilot_out
    # zero from th=min(numPilots,CP_LEN)=32 .. 256 (already zero) (l.1412-1416)
    th = min(NUM_PILOTS, CP_LEN)
    hnew[th:] = 0.0
    # 256-pt FFT (l.1419-1424)
    H = fftw_forward(hnew)
    return H

def fde_zf(rxSym, H):
    """receiver.c fde ZF: out = rxSym*conj(H)/|H|^2 (in place semantics)."""
    out = np.zeros(NSC, dtype=complex)
    for i in range(NSC):
        ri, rq = rxSym[i].real, rxSym[i].imag
        hi, hq = H[i].real, H[i].imag
        oi = ri * hi + rq * hq
        oq = rq * hi - ri * hq
        sc = hi * hi + hq * hq
        if sc == 0.0:
            out[i] = 0.0
        else:
            out[i] = (oi / sc) + 1j * (oq / sc)
    return out

# ----------------------------------------------------------------------
# bit file loaders (signal_processing_common.c)
# ----------------------------------------------------------------------
def load_bits(path, n):
    """Load the first n deterministic bits. If n exceeds the file length
    (e.g. 256-QAM needs 21216 > 16384), TILE the file's bits cyclically so
    the source stays fully deterministic. For modulations whose bit count
    is <= the file length (incl. 16-QAM's 10608), the first n bits are the
    file's first n bits verbatim -> golden stays byte-identical."""
    vals = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            vals.append(int(round(float(line))))
    assert len(vals) > 0, f"{path}: empty"
    if len(vals) >= n:
        return np.array(vals[:n], dtype=int)
    # tile cyclically to reach n (deterministic extension)
    out = (vals * ((n // len(vals)) + 1))[:n]
    return np.array(out, dtype=int)

# ----------------------------------------------------------------------
# hex / file dump helpers
# ----------------------------------------------------------------------
def to_q15(x):
    """float amplitude -> signed 16-bit int (Q15 with scale Q15_SCALE)."""
    v = int(np.round(x * Q15_SCALE))
    if v > 32767:
        v = 32767
    if v < -32768:
        v = -32768
    return v

def pack_iq_q15(i_f, q_f):
    """M_AXIS packing {Q[31:16], I[15:0]} -> 32-bit hex string."""
    i = to_q15(i_f) & 0xFFFF
    q = to_q15(q_f) & 0xFFFF
    return f"{((q << 16) | i) & 0xFFFFFFFF:08X}"

def dump_complex_hex(path, arr_complex, scale):
    """Dump complex array as one 32-bit word/line {Q[31:16],I[15:0]} (Q with
    given fixed scale, saturating). Companion .npy holds exact float."""
    with open(path, "w") as f:
        for c in arr_complex.ravel():
            iv = int(np.round(c.real * scale))
            qv = int(np.round(c.imag * scale))
            iv = max(-32768, min(32767, iv)) & 0xFFFF
            qv = max(-32768, min(32767, qv)) & 0xFFFF
            f.write(f"{((qv << 16) | iv) & 0xFFFFFFFF:08X}\n")

# Q15 scale of the SPECTRUM/EQ-domain samples the RTL demod actually sees
# (THRESH=3220=2*SCALE_16QAM*Q15_DEMOD). The constellation/eq values live at
# this scale; the time-domain slot uses Q15_SCALE=8192 (PAPR headroom).
Q15_DEMOD = 5090.697374

# ----------------------------------------------------------------------
# core pipeline (parameterized by modulation), used by main()
# ----------------------------------------------------------------------
def run_chain(mod_sel, out_dir):
    """Run the full TX + RX-downstream reference for one modulation and emit
    per-mod golden into out_dir. Returns (ber, evm_rms, n_data_bits)."""
    os.makedirs(out_dir, exist_ok=True)
    k = MOD_K[mod_sel]
    bps_blk = NUM_DATA_SC * 2 * k                 # data bits / OFDM symbol
    n_data_bits = bps_blk * NUM_DATA              # data bits / frame

    # --- deterministic bit sources (tiled if a mod needs > file length) ---
    data_bits = load_bits(os.path.join(REF, "Data_Bits.txt"), n_data_bits)
    pilot_bits = load_bits(os.path.join(REF, "Pilot_Bits.txt"),
                           PILOT_BITS_PER_BLOCK * NUM_DATA)     # 768 (QPSK)

    # --- pilot symbols (always QPSK) : 32 x 12 ---
    plt = np.zeros((NUM_DATA, NUM_PILOTS), dtype=complex)
    for z in range(NUM_DATA):
        for p in range(NUM_PILOTS):
            base = (z * NUM_PILOTS + p) * QPSK_BPS
            plt[z, p] = mod_qpsk(pilot_bits[base:base + QPSK_BPS])

    # --- TX: build 12 data symbols + the 4032-sample slot ---
    tx_slot = np.zeros(SLOT_LEN, dtype=complex)
    tx_specs = np.zeros((NUM_DATA, NSC), dtype=complex)
    tx_bits = np.zeros((NUM_DATA, bps_blk), dtype=int)
    for z in range(NUM_DATA):
        dblk = data_bits[z * bps_blk:(z + 1) * bps_blk]
        tx_bits[z] = dblk
        sym, spec = tx_modulate_block(dblk, plt[z], mod_sel)
        tx_specs[z] = spec
        off = (NUM_SYN + z) * SYM_LEN
        tx_slot[off:off + SYM_LEN] = sym

    peak = np.max(np.abs(np.concatenate([tx_slot.real, tx_slot.imag])))
    clip_at = 32767.0 / Q15_SCALE
    print(f"[{MOD_NAMES[mod_sel]}] time-domain peak = {peak:.4f} "
          f"(clip {clip_at:.4f}) -> {'OK' if peak < clip_at else 'CLIPS!'}")

    # --- RX downstream chain per data symbol ---
    fft_out = np.zeros((NUM_DATA, NSC), dtype=complex)
    eq_out = np.zeros((NUM_DATA, NUM_DATA_SC), dtype=complex)
    rx_bits = np.zeros((NUM_DATA, bps_blk), dtype=int)
    evm_acc = 0.0
    evm_cnt = 0

    for z in range(NUM_DATA):
        off = (NUM_SYN + z) * SYM_LEN
        sym288 = tx_slot[off:off + SYM_LEN]      # identity channel, no noise
        rxSym = rx_fft(sym288)
        fft_out[z] = rxSym
        Hp = ch_estimation_fdm(rxSym, plt[z])
        H = interp_fft(Hp)
        Hest = np.zeros(NSC, dtype=complex)
        Hest[1:1 + (NSC - 2)] = H[0:NSC - 2]
        eq = fde_zf(rxSym, Hest)
        eqdata = np.array([eq[idx] for idx in DATA_INDX])
        eq_out[z] = eqdata
        ideal = np.array([mod_qam(tx_bits[z][n * 2 * k:(n + 1) * 2 * k], mod_sel)
                          for n in range(NUM_DATA_SC)])
        evm_acc += np.sum(np.abs(eqdata - ideal) ** 2)
        evm_cnt += len(ideal)
        for n in range(NUM_DATA_SC):
            b = demod_qam(eqdata[n], mod_sel, Q15_DEMOD)
            rx_bits[z][n * 2 * k:(n + 1) * 2 * k] = b

    nbits = tx_bits.size
    nerr = int(np.sum(tx_bits != rx_bits))
    ber = nerr / nbits
    ideal_pow = np.mean(np.abs(np.array(
        [mod_qam(tx_bits[z][n * 2 * k:(n + 1) * 2 * k], mod_sel)
         for z in range(NUM_DATA) for n in range(NUM_DATA_SC)])) ** 2)
    evm_rms = np.sqrt(evm_acc / evm_cnt) / np.sqrt(ideal_pow)
    print(f"[{MOD_NAMES[mod_sel]}] bits/frame={nbits} errored={nerr} "
          f"BER={ber:.3e} EVM={100*evm_rms:.4f}%")

    # ================= dump golden vectors =================
    with open(os.path.join(out_dir, "tx_slot_iq.hex"), "w") as f:
        for c in tx_slot:
            f.write(pack_iq_q15(c.real, c.imag) + "\n")
    # 4032-only alias (gen_tx_roms consumes tx_slot_iq_4032.hex)
    with open(os.path.join(out_dir, "tx_slot_iq_4032.hex"), "w") as f:
        for c in tx_slot:
            f.write(pack_iq_q15(c.real, c.imag) + "\n")
    np.save(os.path.join(out_dir, "tx_slot_iq_float.npy"),
            np.stack([tx_slot.real, tx_slot.imag], axis=1))

    np.save(os.path.join(out_dir, "fft_out_float.npy"), fft_out)
    dump_complex_hex(os.path.join(out_dir, "fft_out.hex"), fft_out, Q15_SCALE)

    hest_used = hest_out_full(tx_slot, plt)
    np.save(os.path.join(out_dir, "hest_float.npy"), hest_used)
    dump_complex_hex(os.path.join(out_dir, "hest.hex"), hest_used, Q15_SCALE)

    np.save(os.path.join(out_dir, "eq_out_float.npy"), eq_out)
    dump_complex_hex(os.path.join(out_dir, "eq_out.hex"), eq_out, Q15_SCALE)

    # TX spectrum (IFFT-input, fftshift order) at the demod/spectrum Q15 scale,
    # for the tx_subcarrier_map TB.  (mirrors gen_tx_roms.gen_stage_golden)
    with open(os.path.join(out_dir, "tx_spec_in.hex"), "w") as f:
        for z in range(NUM_DATA):
            spec = rearrange_spectrum(tx_specs[z])
            for c in spec:
                iv = int(max(-32768, min(32767, round(c.real * Q15_DEMOD)))) & 0xFFFF
                qv = int(max(-32768, min(32767, round(c.imag * Q15_DEMOD)))) & 0xFFFF
                f.write(f"{((qv << 16) | iv) & 0xFFFFFFFF:08X}\n")

    # bits (tx = injected, rx = demodulated). One line per OFDM symbol.
    with open(os.path.join(out_dir, "tx_bits.txt"), "w") as f:
        for z in range(NUM_DATA):
            f.write("".join(str(int(b)) for b in tx_bits[z]) + "\n")
    with open(os.path.join(out_dir, "rx_bits.txt"), "w") as f:
        for z in range(NUM_DATA):
            f.write("".join(str(int(b)) for b in rx_bits[z]) + "\n")
    # flat packed data bits (BPC_MAX=8 bits/carrier, low 2k used) for the
    # TX-map / loopback TBs that present a fixed 8-bit-per-carrier bus.
    with open(os.path.join(out_dir, "tx_data_bits_bpc8.txt"), "w") as f:
        for z in range(NUM_DATA):
            line = []
            for n in range(NUM_DATA_SC):
                cb = list(tx_bits[z][n * 2 * k:(n + 1) * 2 * k])
                cb = cb + [0] * (8 - len(cb))      # pad to 8 bits
                line.extend(str(int(b)) for b in cb)
            f.write("".join(line) + "\n")

    # pilot ROM in the SPECTRUM/EQ Q15 scale (Q15_DEMOD), matching the
    # committed golden/rx_downstream/pilot_rom.hex and tx_spec_in.hex pilots
    # (QPSK 1/sqrt2 -> 3600). The mapper inserts these pilot words verbatim.
    def pack_demod(i_f, q_f):
        iv = int(max(-32768, min(32767, round(i_f * Q15_DEMOD)))) & 0xFFFF
        qv = int(max(-32768, min(32767, round(q_f * Q15_DEMOD)))) & 0xFFFF
        return f"{((qv << 16) | iv) & 0xFFFFFFFF:08X}"
    with open(os.path.join(out_dir, "pilot_rom.hex"), "w") as f:
        for z in range(NUM_DATA):
            for p in range(NUM_PILOTS):
                f.write(pack_demod(plt[z, p].real, plt[z, p].imag) + "\n")
    np.save(os.path.join(out_dir, "pilot_rom_float.npy"),
            np.stack([plt.real, plt.imag], axis=2))

    with open(os.path.join(out_dir, "pilot_indx.txt"), "w") as f:
        f.write(",".join(str(i) for i in PLT_INDX) + "\n")
    with open(os.path.join(out_dir, "data_indx.txt"), "w") as f:
        f.write(",".join(str(i) for i in DATA_INDX) + "\n")
    with open(os.path.join(out_dir, "mod_meta.txt"), "w") as f:
        f.write(f"mod_sel={mod_sel}\nmod_name={MOD_NAMES[mod_sel]}\n"
                f"bits_per_axis={k}\nbits_per_sym={2*k}\n"
                f"data_bits_per_frame={n_data_bits}\nscale={MOD_SCALE[mod_sel]}\n")

    print(f"[done] {MOD_NAMES[mod_sel]} golden -> {out_dir}")
    return ber, evm_rms, n_data_bits


# ----------------------------------------------------------------------
# main : default = 16-QAM into golden/rx_downstream/16qam/ (per-mod subdir).
#   The committed legacy top-level golden/rx_downstream/*.hex files (made by
#   the board-level generator, 4160-sample frame) are intentionally LEFT
#   UNTOUCHED; the per-mod subdirs hold the Phase-1 multi-mod golden. The
#   16-QAM bit golden (tx_bits/rx_bits) is byte-identical to committed.
# ----------------------------------------------------------------------
def main(mod_sel=1, out_dir=None):
    if out_dir is None:
        out_dir = os.path.join(OUT, MOD_NAMES[mod_sel])
    return run_chain(mod_sel, out_dir)


def hest_out_full(tx_slot, plt):
    """Recompute the Hest array (post +1 memcpy shift) actually consumed by
    fde, for all 12 blocks, for golden dump."""
    out = np.zeros((NUM_DATA, NSC), dtype=complex)
    for z in range(NUM_DATA):
        off = (NUM_SYN + z) * SYM_LEN
        sym288 = tx_slot[off:off + SYM_LEN]
        rxSym = rx_fft(sym288)
        Hp = ch_estimation_fdm(rxSym, plt[z])
        H = interp_fft(Hp)
        Hest = np.zeros(NSC, dtype=complex)
        Hest[1:1 + (NSC - 2)] = H[0:NSC - 2]
        out[z] = Hest
    return out


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1 and sys.argv[1] in MOD_NAMES.values():
        # single named modulation
        ms = [k for k, v in MOD_NAMES.items() if v == sys.argv[1]][0]
        ber, evm, nb = run_chain(ms, os.path.join(OUT, MOD_NAMES[ms]))
        if ber != 0.0:
            raise SystemExit(f"FAIL: {MOD_NAMES[ms]} BER={ber} (must be 0)")
    else:
        # default: emit all four per-mod golden into golden/rx_downstream/<mod>/
        for ms in range(4):
            ber, evm, nb = run_chain(ms, os.path.join(OUT, MOD_NAMES[ms]))
            if ber != 0.0:
                raise SystemExit(f"FAIL: {MOD_NAMES[ms]} BER={ber} (must be 0)")
        print("[all-mods] all four modulations: clean BER=0")
