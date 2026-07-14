#!/usr/bin/env python3
"""Complex-baseband FFT of a ZCU216 RFDC DDC capture (RF bringup 6c-1).

After the ADC tile2/blk0 DDC (fine mixer NCO -300 MHz, I/Q, decimation 16) the
m20_axis carries complex baseband at fs = 153.6 Msps. The capture buffer stores
one 32-bit {Q[31:16], I[15:0]} word per complex sample (zcu216_adc_capture flat
layout, 5 complex samples per 160-bit AXIS beat, contiguous). This script
deinterleaves I/Q, forms x = I + jQ, and runs a full complex FFT so the OFDM
band (originally +/-76.8 MHz around the 300 MHz IF) appears centered at DC,
spanning +/-76.8 MHz of the +/-76.8 MHz (= fs/2) baseband window.

Usage:
    python3 scripts/fft_capture_ddc.py tests/08_rfdc_capture/capture_ofdm_ddc.bin
    # compare two:
    python3 scripts/fft_capture_ddc.py <on.bin> --ref <off.bin>
"""
import argparse
import numpy as np

FS = 153.6e6  # complex baseband sample rate after decimation-16


BANK_AW = 10
BEATS = 1 << BANK_AW   # 1024 beats per bank
SPB = 5               # complex samples per beat / number of banks


def load_iq(path):
    """Load the banked capture dump and reconstruct the complex baseband stream.

    The capture flat index maps to bank=index>>10, addr=index&1023 (5 banks of
    1024 beats). Complex sample at time t = addr*SPB + bank, i.e. flat index of
    time t is bank*BEATS + addr with bank=t%SPB, addr=t//SPB. We read each bank
    contiguously and interleave the lanes back into time order.
    """
    raw = np.fromfile(path, dtype="<i4")
    if raw.size == 0:
        return np.empty(0, dtype=np.complex128)
    need = SPB * BEATS
    if raw.size < need:
        raw = np.concatenate([raw, np.zeros(need - raw.size, dtype=raw.dtype)])
    words = raw[:need].reshape(SPB, BEATS)        # words[bank, addr]
    # time-ordered words: t = addr*SPB + bank -> stack lanes per addr.
    ordered = words.T.reshape(-1)                 # addr-major, bank-minor
    i = (ordered & 0xFFFF).astype(np.int16).astype(np.float64)      # bits[15:0]
    q = ((ordered >> 16) & 0xFFFF).astype(np.int16).astype(np.float64)  # bits[31:16]
    return i + 1j * q


def band_energy(x, fs, f_lo, f_hi):
    """Total spectral energy in [f_lo, f_hi] (Hz, signed) of complex x."""
    n = x.size
    X = np.fft.fftshift(np.fft.fft(x * np.hanning(n)))
    f = np.fft.fftshift(np.fft.fftfreq(n, d=1.0 / fs))
    mask = (f >= f_lo) & (f <= f_hi)
    return float(np.sum(np.abs(X[mask]) ** 2)), f, X


def summarize(path, fs):
    x = load_iq(path)
    if x.size == 0:
        print(f"DDCFFT: empty dump {path}")
        return None
    x = x - x.mean()
    n = x.size
    X = np.fft.fftshift(np.fft.fft(x * np.hanning(n)))
    f = np.fft.fftshift(np.fft.fftfreq(n, d=1.0 / fs))
    mag = np.abs(X)
    peak = int(np.argmax(mag))
    # OFDM occupied band ~ +/-76.8 MHz; measure the in-band vs out-of-band split.
    occ = 76.8e6
    inband = (f >= -occ) & (f <= occ)
    # "centered at DC" check: energy within +/-40 MHz vs the 40..76.8 wings.
    core = (f >= -40e6) & (f <= 40e6)
    e_total = float(np.sum(mag[inband] ** 2))
    e_core = float(np.sum(mag[core] ** 2))
    lines = [
        f"DDCFFT: source={path}",
        f"DDCFFT: N={n} complex samp  fs={fs/1e6:.1f} MHz  span=+/-{fs/2e6:.1f} MHz",
        f"DDCFFT: peak bin freq={f[peak]/1e6:+.3f} MHz mag={mag[peak]:.1f}",
        f"DDCFFT: in-band(+/-76.8MHz) energy={e_total:.3e}",
        f"DDCFFT: core(+/-40MHz) energy={e_core:.3e} "
        f"({100*e_core/e_total if e_total>0 else 0:.1f}% of in-band)",
        f"DDCFFT: I rms={np.std(x.real):.1f}  Q rms={np.std(x.imag):.1f}",
    ]
    for l in lines:
        print(l)
    return dict(path=path, f=f, mag=mag, e_total=e_total, e_core=e_core,
                n=n, lines=lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path")
    ap.add_argument("--ref", default=None, help="DAC_OFF reference dump to compare")
    ap.add_argument("--fs", type=float, default=FS)
    args = ap.parse_args()

    on = summarize(args.path, args.fs)
    ref = summarize(args.ref, args.fs) if args.ref else None
    if on and ref:
        ratio = on["e_total"] / ref["e_total"] if ref["e_total"] > 0 else float("inf")
        db = 10 * np.log10(ratio) if ratio > 0 else float("-inf")
        print(f"DDCFFT: DAC_ON/DAC_OFF in-band energy ratio = {ratio:.2f}x "
              f"({db:+.1f} dB)")

    # write summary + plot
    summary = args.path.rsplit(".", 1)[0] + "_ddcfft.txt"
    with open(summary, "w") as fh:
        if on:
            fh.write("\n".join(on["lines"]) + "\n")
        if ref:
            fh.write("\n--- DAC_OFF ref ---\n" + "\n".join(ref["lines"]) + "\n")
    print(f"DDCFFT: summary saved {summary}")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.figure(figsize=(9, 4))
        if on:
            with np.errstate(divide="ignore"):
                plt.plot(on["f"] / 1e6, 20 * np.log10(np.maximum(on["mag"], 1e-9)),
                         label="DAC_ON", lw=0.8)
        if ref:
            with np.errstate(divide="ignore"):
                plt.plot(ref["f"] / 1e6, 20 * np.log10(np.maximum(ref["mag"], 1e-9)),
                         label="DAC_OFF", lw=0.8, alpha=0.7)
        for fx in (-76.8, 76.8):
            plt.axvline(fx, color="r", ls="--", lw=0.6)
        plt.axvline(0, color="k", ls=":", lw=0.6)
        plt.xlabel("MHz (baseband, 0 = DC after DDC)")
        plt.ylabel("dB")
        plt.title(f"ZCU216 DDC complex-baseband spectrum ({args.path})")
        plt.legend()
        plt.tight_layout()
        out = args.path.rsplit(".", 1)[0] + "_ddcfft.png"
        plt.savefig(out, dpi=110)
        print(f"DDCFFT: plot saved {out}")
    except Exception as exc:
        print(f"DDCFFT: plot skipped ({exc})")


if __name__ == "__main__":
    main()
