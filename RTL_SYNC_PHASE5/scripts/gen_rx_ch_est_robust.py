#!/usr/bin/env python3
"""
gen_rx_ch_est_robust.py
=======================
ROBUST verification stimulus + golden for rx_ch_est.v (CE + interp_fft).

The module previously passed against ONE identity-channel golden (H ~= 1).
This generator builds N>=20 RANDOM, NON-IDENTITY frequency-selective channels
plus random QPSK pilots and random 16-QAM data, and computes the EXPECTED
H_est the SAME WAY the reference model (scripts/rx_downstream_ref.py) does:

    ch_estimation_fdm  : H_pilot[k] = rx[pltIndx[k]] * conj(plt[k]) / |plt[k]|^2
    interp_fft         : 32-pt IFFT of the 32 pilot-H into low taps, zero rest,
                         256-pt forward FFT
    +1 offset memcpy   : Hest[1..254] = Hfft[0..253], Hest[0]=Hest[255]=0

IMPORTANT (matches the prompt): the golden H_est is the REFERENCE-MODEL output
of interp_fft from the 32 pilots -- NOT H_true. Interpolation from 32 pilots is
approximate, so we compare module-output vs reference-model-output, both
computed identically. This is exactly what the RTL collapsed-W matrix
(W = DFT256[:,0:32] @ IDFT32/32) reproduces, so any deviation is pure
fixed-point rounding.

Per case we model the RX freq bins as TX_spectrum * H_true (frequency-domain
multiply -- a flat-fading-per-bin channel, the standard OFDM model). CE then
recovers H_pilot[k] ~= H_true[pltIndx[k]] (exactly, up to the QPSK pilot being
nonzero) and interp_fft interpolates a smooth 256-bin estimate.

Channel families (>=20 cases, deterministic seed):
  - flat (H~=1)                         : sanity / regression overlap
  - flat scaled / phase-rotated         : constant non-unit gain
  - random multipath (a few taps -> FFT): realistic smooth selectivity
  - steep (large variation between adjacent pilots)
  - deep null (very small |H| at some bins)
  - random pilot values near QPSK constellation (jittered)

Outputs (multi-case, concatenated, same packing as golden/rx_downstream so the
extended TB can loop):
  golden/rx_ch_est_robust/fft_out.hex     N*256 lines  {Q[31:16],I[15:0]} Q15
  golden/rx_ch_est_robust/pilot_rom.hex   N*32  lines  {Q,I} Q15 (QPSK pilots)
  golden/rx_ch_est_robust/hest.hex        N*256 lines  {Q,I} Q15 (expected Hest)
  golden/rx_ch_est_robust/meta.txt        N + per-case labels + scale
  *_float.npy companions (authoritative float)

Q15 scale = 5090.697374 (same as CONTRACT.md / golden hest.hex), so H=1.0 reads
~0x13E3. All freq-domain hex use this scale.

numpy only. Deterministic (np.random seeded). Does NOT modify any RTL.
"""
import os
import numpy as np

# ---- constants (match rx_downstream_ref.py / CONTRACT.md) ----
NSC        = 256
NUM_PILOTS = 32
NUM_DATA_SC = NSC - NUM_PILOTS - 3      # 221
SCALE_QPSK = 1.0 / np.sqrt(2.0)
SCALE_16QAM = 1.0 / np.sqrt(10.0)
Q15_SCALE  = 5090.697374               # RMS-matched scale, == golden hest scale

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT  = os.path.join(ROOT, "golden", "rx_ch_est_robust")

# pilot indices: 1 + 8*i  -> {1,9,...,249}
PLT_INDX = [1 + 8 * i for i in range(NUM_PILOTS)]
# data indices: 1..254 minus pilots minus DC(128)
_pltset = set(PLT_INDX)
DATA_INDX = [i for i in range(1, NSC - 1) if i not in _pltset and i != NSC // 2]
assert len(DATA_INDX) == NUM_DATA_SC


# ----------------------------------------------------------------------
# reference algorithm (bit-faithful to rx_downstream_ref.py)
# ----------------------------------------------------------------------
def ch_estimation_fdm(rxSym, plt_block):
    H = np.zeros(NSC, dtype=complex)
    for k, i in enumerate(PLT_INDX):
        p = plt_block[k]
        tmp = p.real * p.real + p.imag * p.imag
        Hi = (rxSym[i].real * p.real + rxSym[i].imag * p.imag) / tmp
        Hq = (rxSym[i].imag * p.real - rxSym[i].real * p.imag) / tmp
        H[i] = Hi + 1j * Hq
    return H


def interp_fft(H_pilots):
    hi = np.zeros(NSC, dtype=complex)
    for i in range(NUM_PILOTS):
        hi[NSC // 2 + i] = H_pilots[PLT_INDX[i]]
    pilot_in = hi[NSC // 2:NSC // 2 + NUM_PILOTS]
    pilot_out = (NUM_PILOTS * np.fft.ifft(pilot_in)) / NUM_PILOTS  # == ifft
    hnew = np.zeros(NSC, dtype=complex)
    hnew[:NUM_PILOTS] = pilot_out
    return np.fft.fft(hnew)


def reference_hest(rxSym, plt_block):
    """Full reference: CE -> interp_fft -> +1 offset memcpy."""
    Hp = ch_estimation_fdm(rxSym, plt_block)
    Hfft = interp_fft(Hp)
    Hest = np.zeros(NSC, dtype=complex)
    Hest[1:1 + (NSC - 2)] = Hfft[0:NSC - 2]   # Hest[0]=Hest[255]=0
    return Hest


# ----------------------------------------------------------------------
# stimulus builders
# ----------------------------------------------------------------------
def rand_qpsk_pilots(rng):
    b = rng.integers(0, 2, size=(NUM_PILOTS, 2))
    si = np.where(b[:, 0] > 0, 1.0, -1.0) * SCALE_QPSK
    sq = np.where(b[:, 1] > 0, 1.0, -1.0) * SCALE_QPSK
    return si + 1j * sq


def jittered_qpsk_pilots(rng, jit=0.05):
    """QPSK pilots with small amplitude/phase jitter (still nonzero |p|)."""
    p = rand_qpsk_pilots(rng)
    p = p * (1.0 + jit * (rng.standard_normal(NUM_PILOTS)
                          + 1j * rng.standard_normal(NUM_PILOTS)))
    return p


def rand_16qam_data(rng):
    m = np.array([-1, -3, 1, 3], dtype=float) * SCALE_16QAM
    b = rng.integers(0, 2, size=(NUM_DATA_SC, 4))
    tmpI = b[:, 0] * 2 + b[:, 1]
    tmpQ = b[:, 2] * 2 + b[:, 3]
    return m[tmpI] + 1j * m[tmpQ]


def tx_spectrum(plt_block, data_block):
    """fftshift-ordered TX freq spectrum (what fft_out would be at H=1)."""
    s = np.zeros(NSC, dtype=complex)
    for k, idx in enumerate(PLT_INDX):
        s[idx] = plt_block[k]
    for k, idx in enumerate(DATA_INDX):
        s[idx] = data_block[k]
    return s


def multipath_channel(rng, ntaps, spread, gain=1.0):
    """A few random complex taps -> 256-pt FFT -> smooth selective H[256]
    (fftshift-ordered to match the bin convention)."""
    taps = np.zeros(NSC, dtype=complex)
    delays = rng.choice(np.arange(spread), size=ntaps, replace=False)
    delays[0] = 0  # ensure a strong lead tap
    amps = rng.standard_normal(ntaps) + 1j * rng.standard_normal(ntaps)
    amps[0] = 1.0 + 0.0j  # dominant LOS-ish tap keeps |H| reasonable
    decay = np.exp(-0.6 * np.arange(ntaps))
    for t, d, a in zip(range(ntaps), delays, amps):
        taps[d] += a * decay[t]
    H = np.fft.fft(taps)
    H = np.fft.fftshift(H)   # match fftshift bin ordering
    return gain * H


# ----------------------------------------------------------------------
# case generation
# ----------------------------------------------------------------------
def build_cases():
    rng = np.random.default_rng(0xC0FFEE)
    cases = []  # (label, H_true[256], plt[32], data[221])

    def add(label, H, jitter_pilots=False):
        plt = (jittered_qpsk_pilots(rng) if jitter_pilots
               else rand_qpsk_pilots(rng))
        data = rand_16qam_data(rng)
        cases.append((label, H, plt, data))

    # 1) flat identity (regression overlap)
    add("flat_identity", np.ones(NSC, dtype=complex))
    # 2) flat scaled gain
    add("flat_scaled_0p6", 0.6 * np.ones(NSC, dtype=complex))
    add("flat_scaled_1p8", 1.8 * np.ones(NSC, dtype=complex))
    # 3) flat phase rotation
    add("flat_phase_+45deg", np.exp(1j * np.pi / 4) * np.ones(NSC, dtype=complex))
    add("flat_phase_-120deg", np.exp(-1j * 2 * np.pi / 3) * np.ones(NSC, dtype=complex))
    # 4) mild random multipath (smooth, realistic)
    for i in range(4):
        H = multipath_channel(rng, ntaps=3, spread=8, gain=1.0)
        add(f"multipath_mild_{i}", H)
    # 5) moderate multipath (more taps, more selective)
    for i in range(4):
        H = multipath_channel(rng, ntaps=6, spread=16, gain=1.0)
        add(f"multipath_mod_{i}", H)
    # 6) steep channel: large variation between adjacent pilots (8-bin spacing)
    #    use high-delay taps so H wiggles fast across subcarriers
    for i in range(3):
        H = multipath_channel(rng, ntaps=5, spread=28, gain=1.0)
        add(f"steep_{i}", H)
    # 7) deep null: force small |H| at a cluster of bins (incl. some pilots)
    for i in range(3):
        H = multipath_channel(rng, ntaps=4, spread=12, gain=1.0)
        # carve a notch around a random center
        c = rng.integers(40, 216)
        w = rng.integers(4, 12)
        notch = np.ones(NSC)
        x = np.arange(NSC)
        notch = 1.0 - 0.97 * np.exp(-((x - c) ** 2) / (2.0 * w * w))
        H = H * notch
        add(f"deep_null_c{c}_w{w}", H)
    # 8) jittered pilots near QPSK constellation (CE divide stresses |p|^2!=1)
    for i in range(3):
        H = multipath_channel(rng, ntaps=4, spread=12, gain=1.0)
        add(f"jitter_pilots_{i}", H, jitter_pilots=True)
    # 9) extreme: strong reflection (deep frequency selectivity), high gain
    for i in range(2):
        H = multipath_channel(rng, ntaps=2, spread=20, gain=1.4)
        # second tap nearly equal magnitude -> deep periodic nulls
        add(f"two_ray_deep_{i}", H)
    return cases


# ----------------------------------------------------------------------
# packing / dump
# ----------------------------------------------------------------------
def q(v):
    iv = int(np.round(v))
    return max(-32768, min(32767, iv)) & 0xFFFF


def pack(c, scale):
    return f"{((q(c.imag * scale) << 16) | q(c.real * scale)) & 0xFFFFFFFF:08X}"


def main():
    os.makedirs(OUT, exist_ok=True)
    cases = build_cases()
    N = len(cases)

    fft_all = np.zeros((N, NSC), dtype=complex)
    plt_all = np.zeros((N, NUM_PILOTS), dtype=complex)
    hest_all = np.zeros((N, NSC), dtype=complex)
    labels = []

    # diagnostics
    print(f"[gen] {N} cases, Q15 scale = {Q15_SCALE:.6f}")
    print(f"{'case':>3}  {'label':28} {'|H_true| min/max':>22} "
          f"{'|fft_out| max(Q15)':>18} {'|Hest| max(Q15)':>16}")

    for ci, (label, H_true, plt, data) in enumerate(cases):
        labels.append(label)
        tx = tx_spectrum(plt, data)
        rxSym = tx * H_true                 # per-bin (flat-fading) channel
        Hest = reference_hest(rxSym, plt)

        fft_all[ci] = rxSym
        plt_all[ci] = plt
        hest_all[ci] = Hest

        # pilot-bin magnitudes drive CE; report |H| range over pilots (what
        # interp actually sees) and full-band for context
        hmag = np.abs(H_true)
        fft_q = np.abs(rxSym) * Q15_SCALE
        hest_q = np.abs(Hest) * Q15_SCALE
        print(f"{ci:3d}  {label:28} "
              f"{hmag.min():8.4f}/{hmag.max():-8.4f}    "
              f"{fft_q.max():14.1f}   {hest_q.max():14.1f}")

    # ---- write hex (concatenated, case-major) ----
    with open(os.path.join(OUT, "fft_out.hex"), "w") as f:
        for ci in range(N):
            for b in range(NSC):
                f.write(pack(fft_all[ci, b], Q15_SCALE) + "\n")
    with open(os.path.join(OUT, "pilot_rom.hex"), "w") as f:
        for ci in range(N):
            for p in range(NUM_PILOTS):
                f.write(pack(plt_all[ci, p], Q15_SCALE) + "\n")
    with open(os.path.join(OUT, "hest.hex"), "w") as f:
        for ci in range(N):
            for b in range(NSC):
                f.write(pack(hest_all[ci, b], Q15_SCALE) + "\n")

    np.save(os.path.join(OUT, "fft_out_float.npy"), fft_all)
    np.save(os.path.join(OUT, "pilot_rom_float.npy"), plt_all)
    np.save(os.path.join(OUT, "hest_float.npy"), hest_all)

    with open(os.path.join(OUT, "meta.txt"), "w") as f:
        f.write(f"N={N}\nQ15_SCALE={Q15_SCALE}\n")
        for ci, lab in enumerate(labels):
            f.write(f"{ci} {lab}\n")

    # ---- self-check: does the collapsed-W fixed point reproduce float Hest?
    # mirror the RTL math in float to predict the LSB budget the TB will see.
    predict_lsb(cases)

    print(f"[done] wrote {N} cases to {OUT}")
    return N


def predict_lsb(cases):
    """Offline prediction of the fixed-point LSB error the RTL will exhibit,
    by emulating the RTL datapath (Q15 CE divide -> 18b Hp -> collapsed-W MAC
    with CW=16 frac, round, sat16) and comparing to the float golden. This is
    NOT the RTL run (xsim is authoritative) but flags whether the budget is
    sane before spending sim time."""
    # CW = coeff WORD width (18b signed); CF = coeff FRACTIONAL bits (16).
    # The ROM (gen_rx_ch_est_rom.py) scales W by 2^CF, NOT 2^CW.
    CW, CF, HW = 18, 16, 18
    SCQ, SCQ_SHIFT = 20851496, 12
    NP = NUM_PILOTS
    n = np.arange(NP)
    IDFT = np.exp(1j * 2 * np.pi * np.outer(n, np.arange(NP)) / NP) / NP
    k = np.arange(NSC)
    DFT = np.exp(-1j * 2 * np.pi * np.outer(k, n) / NSC)
    W = DFT @ IDFT
    Wr = np.round(W.real * (1 << CF)).astype(np.int64)
    Wi = np.round(W.imag * (1 << CF)).astype(np.int64)

    def sat(v, bits):
        lim = 1 << (bits - 1)
        return max(-lim, min(lim - 1, int(v)))

    def idiv_trunc(num, den):
        """C / Verilog signed division: truncate toward zero."""
        if den == 0:
            return 0
        q = abs(num) // abs(den)
        return q if (num < 0) == (den < 0) else -q

    def ashr(v, s):
        """arithmetic >>> on a Python int (floor for negatives, matches RTL)."""
        return v >> s  # Python >> already floors -> matches signed >>>

    worst = 0
    worst_case = None
    for ci, (label, H_true, plt, data) in enumerate(cases):
        tx = tx_spectrum(plt, data)
        rxSym = tx * H_true
        # ---- RTL CE divide (integer, matches rx_ch_est.v lines 106-125) ----
        rxI = np.round(rxSym.real * Q15_SCALE).astype(np.int64)
        rxQ = np.round(rxSym.imag * Q15_SCALE).astype(np.int64)
        plI = np.array([sat(np.round(p.real * Q15_SCALE), 16) for p in plt])
        plQ = np.array([sat(np.round(p.imag * Q15_SCALE), 16) for p in plt])
        hp_i = np.zeros(NP, dtype=np.int64)
        hp_q = np.zeros(NP, dtype=np.int64)
        for m, idx in enumerate(PLT_INDX):
            ni = int(rxI[idx]) * int(plI[m]) + int(rxQ[idx]) * int(plQ[m])
            nq = int(rxQ[idx]) * int(plI[m]) - int(rxI[idx]) * int(plQ[m])
            den = (int(plI[m]) ** 2 + int(plQ[m]) ** 2) << SCQ_SHIFT  # dsig>0
            pi = ni * SCQ
            pq = nq * SCQ
            half_i = ashr(-den if pi < 0 else den, 1)   # (sign?-d:d)>>>1
            half_q = ashr(-den if pq < 0 else den, 1)
            hp_i[m] = sat(idiv_trunc(pi + half_i, den), HW)
            hp_q[m] = sat(idiv_trunc(pq + half_q, den), HW)
        # ---- collapsed-W MAC (k=0..253) -> Hest[1..254] (lines 209-255) ----
        hest_fp = np.zeros(NSC, dtype=complex)
        bias = 1 << (CF - 1)
        # use Python-int arithmetic (object dtype) to avoid numpy int64 MAC
        # overflow artifacts; the RTL accumulator (AW=42b) cannot overflow here.
        hpi = [int(x) for x in hp_i]
        hpq = [int(x) for x in hp_q]
        for kk in range(NSC - 2):
            wr = [int(x) for x in Wr[kk]]
            wi = [int(x) for x in Wi[kk]]
            acc_re = sum(wr[m] * hpi[m] - wi[m] * hpq[m] for m in range(NP))
            acc_im = sum(wr[m] * hpq[m] + wi[m] * hpi[m] for m in range(NP))
            re = max(-32768, min(32767, ashr(acc_re + bias, CF)))  # >>> CF, sat16
            im = max(-32768, min(32767, ashr(acc_im + bias, CF)))
            hest_fp[kk + 1] = re + 1j * im
        # golden (float Hest -> Q15)
        Hest = reference_hest(rxSym, plt)
        gi = np.clip(np.round(Hest.real * Q15_SCALE), -32768, 32767)
        gq = np.clip(np.round(Hest.imag * Q15_SCALE), -32768, 32767)
        err = np.maximum(np.abs(hest_fp.real - gi), np.abs(hest_fp.imag - gq))
        cw = err.max()
        if cw > worst:
            worst = cw
            worst_case = (ci, label)
    print(f"[predict] offline fixed-point max|err| vs golden = {worst:.0f} LSB "
          f"(case {worst_case[0]} {worst_case[1]})")


if __name__ == "__main__":
    main()
