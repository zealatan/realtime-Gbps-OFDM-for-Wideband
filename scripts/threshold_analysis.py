#!/usr/bin/env python3
"""RF bringup 6c-2: offline detector-threshold analysis on the real RF DDC capture.

Reconstructs the 153.6 Msps complex baseband stream from a banked DDC capture
(same de-banking as fft_capture_ddc.py), then computes:

  (A) The DUT FRAME-DETECTOR metric = sliding sum of |x[n]|^2 (= I^2+Q^2) over a
      WINDOW_LEN-sample window (sliding_window_sum + frame_detect_fsm). This is
      the metric the build-time THRESHOLD actually gates:
          fire if  window_energy  >  THRESHOLD * WINDOW_LEN
      i.e. THRESHOLD ~= per-sample average power threshold.

  (B) The CP autocorrelation metric (streaming_cp_autocorr inside the timing
      block): Manhattan |Re(R)| + |Im(R)| of the CP-window (CP_LEN-tap) sliding
      sum of x[n]*conj(x[n-NSC]). Reported for context / IQ-sanity; it does NOT
      gate detection in this DUT.

Defaults: NSC=256, CP_LEN=32, WINDOW_LEN=25, HIT_COUNT=10 (DUT params).
"""
import argparse
import numpy as np

BANK_AW = 10
BEATS = 1 << BANK_AW
SPB = 5

NSC = 256
CP_LEN = 32
WINDOW_LEN = 25
HIT_COUNT = 10


def load_iq(path):
    raw = np.fromfile(path, dtype="<i4")
    if raw.size == 0:
        return np.empty(0, dtype=np.complex128)
    need = SPB * BEATS
    if raw.size < need:
        raw = np.concatenate([raw, np.zeros(need - raw.size, dtype=raw.dtype)])
    words = raw[:need].reshape(SPB, BEATS)
    ordered = words.T.reshape(-1)
    i = (ordered & 0xFFFF).astype(np.int16).astype(np.float64)
    q = ((ordered >> 16) & 0xFFFF).astype(np.int16).astype(np.float64)
    return i, q, (i + 1j * q)


def window_energy_metric(I, Q, wlen):
    """sliding_window_sum: window_energy[k] = sum_{j=k-wlen+1..k} (I[j]^2+Q[j]^2).
    Integer arithmetic matching the RTL (I,Q are int from int16)."""
    p = (I.astype(np.int64) ** 2) + (Q.astype(np.int64) ** 2)   # per-sample power
    # sliding sum of length wlen
    csum = np.cumsum(p)
    we = np.empty(p.size, dtype=np.int64)
    we[:wlen] = csum[:wlen]            # filling region (not full windows except last)
    we[wlen:] = csum[wlen:] - csum[:-wlen]
    # full windows start at index wlen-1
    return we, p


def autocorr_metric(I, Q, nsc, cp):
    """streaming_cp_autocorr Manhattan metric.
    R[n] = sum_{j=n-cp+1..n} x[j]*conj(x[j-nsc])
    metric[n] = |Re(R[n])| + |Im(R[n])|  (RTL takes high 32 bits of 48-bit acc;
    here we report full-precision; scaling note below)."""
    x = I + 1j * Q
    xd = np.zeros_like(x)
    xd[nsc:] = x[:-nsc]
    prod = x * np.conj(xd)            # x[n]*conj(x[n-nsc])
    # sliding sum over cp taps
    csr = np.cumsum(prod.real)
    csi = np.cumsum(prod.imag)
    Rr = np.empty(prod.size); Ri = np.empty(prod.size)
    Rr[:cp] = csr[:cp]; Rr[cp:] = csr[cp:] - csr[:-cp]
    Ri[:cp] = csi[:cp]; Ri[cp:] = csi[cp:] - csi[:-cp]
    metric = np.abs(Rr) + np.abs(Ri)
    return metric, Rr + 1j * Ri


def analyze(path, label):
    I, Q, x = load_iq(path)
    if x.size == 0:
        print(f"[{label}] empty: {path}")
        return None
    n = x.size
    Ii = np.round(I).astype(np.int64)
    Qi = np.round(Q).astype(np.int64)

    we, p = window_energy_metric(Ii, Qi, WINDOW_LEN)
    full = we[WINDOW_LEN - 1:]              # only full windows are valid
    we_peak = int(full.max())
    we_med = float(np.median(full))
    we_mean = float(full.mean())
    # implied per-sample power threshold = window_energy / WINDOW_LEN
    persamp_peak = we_peak / WINDOW_LEN
    persamp_med = we_med / WINDOW_LEN

    ac, R = autocorr_metric(I, Q, NSC, CP_LEN)
    ac_full = ac[NSC + CP_LEN:]
    ac_peak = float(ac_full.max())
    ac_med = float(np.median(ac_full))

    print(f"=== [{label}] {path}  (N={n} complex samp) ===")
    print(f"  I rms={I.std():.1f}  Q rms={Q.std():.1f}  "
          f"|x| mean={np.abs(x).mean():.1f}  max={np.abs(x).max():.1f}")
    print(f"  per-sample power p=I^2+Q^2:  mean={p.mean():.3e} median={np.median(p):.3e} max={p.max():.3e}")
    print(f"  WINDOW ENERGY metric (WINDOW_LEN={WINDOW_LEN}, the DETECTOR gate):")
    print(f"      peak   = {we_peak:.4e}   (=> per-sample {persamp_peak:.4e})")
    print(f"      median = {we_med:.4e}   (=> per-sample {persamp_med:.4e})")
    print(f"      mean   = {we_mean:.4e}")
    print(f"  AUTOCORR Manhattan metric (CP={CP_LEN}, NSC={NSC}, context only):")
    print(f"      peak   = {ac_peak:.4e}")
    print(f"      median = {ac_med:.4e}")
    return dict(label=label, we_peak=we_peak, we_med=we_med, we_mean=we_mean,
                persamp_peak=persamp_peak, persamp_med=persamp_med,
                ac_peak=ac_peak, ac_med=ac_med, full=full, ac_full=ac_full,
                p=p, I=I, Q=Q)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("on")
    ap.add_argument("--off", default=None)
    a = ap.parse_args()
    on = analyze(a.on, "DAC_ON")
    off = analyze(a.off, "DAC_OFF") if a.off else None

    if on:
        print("\n=== THRESHOLD SELECTION (gates window-energy detector) ===")
        # We need THRESHOLD*WINDOW_LEN < window_energy of the signal for HIT_COUNT
        # consecutive windows. Use a fraction of the ON peak, above OFF.
        # THRESHOLD is per-sample (= window_energy/WINDOW_LEN), parameter to IP.
        wl = WINDOW_LEN
        for frac in (0.4, 0.5, 0.6):
            thr_persamp = on["we_peak"] * frac / wl
            print(f"  frac={frac:.1f} of ON window-energy peak: "
                  f"THRESHOLD(per-sample) = {thr_persamp:.4e}  "
                  f"(thresh_mult = THRESHOLD*{wl} = {thr_persamp*wl:.4e})")
        if off:
            print(f"\n  DAC_OFF window-energy peak  = {off['we_peak']:.4e} "
                  f"(per-sample {off['persamp_peak']:.4e})")
            print(f"  DAC_OFF window-energy median= {off['we_med']:.4e}")
            print(f"  ON/OFF window-energy peak ratio = "
                  f"{on['we_peak']/max(off['we_peak'],1):.2f}x")
            print(f"  ON/OFF autocorr peak ratio      = "
                  f"{on['ac_peak']/max(off['ac_peak'],1):.2f}x")
            # A robust THRESHOLD: midpoint (geom mean) between OFF median window-energy
            # and ON median window-energy, per-sample.
            on_ps = on["we_med"] / wl
            off_ps = max(off["we_med"] / wl, 1.0)
            geo = (on_ps * off_ps) ** 0.5
            print(f"\n  Robust per-sample THRESHOLD candidates:")
            print(f"     ON median per-sample power   = {on_ps:.4e}")
            print(f"     OFF median per-sample power  = {off_ps:.4e}")
            print(f"     geomean(ON_med, OFF_med)     = {geo:.4e}  <-- robust pick")
            print(f"     0.5*ON_median_per-sample     = {0.5*on_ps:.4e}")


if __name__ == "__main__":
    main()
