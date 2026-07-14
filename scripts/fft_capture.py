#!/usr/bin/env python3
"""Offline FFT of a ZCU216 RFDC capture dump.

The dump is a raw little-endian int32 stream of lane-0 ADC samples (sign-
extended 16-bit) written by scripts/run_rfdc_capture.xsct via JTAG mrd.

Default lane-0 effective sample rate is 307.2 MHz. The PL dac_tone square
wave is 107.52 MHz in the DAC-fabric domain, but the measured loopback tone
lands at 106.275 MHz (bin 2834) because the actual DAC:ADC fabric clock ratio
is ~1.3838 vs the designed 1.4 (ISS-21: clock config + PL IPs verified exact;
measured value accepted). TONE defaults to the measured 106.275 MHz so the
peak MATCHES. Use --tone/--fs for other RFDC capture variants.

Usage:
    python3 scripts/fft_capture.py tests/08_rfdc_capture/capture_connected.bin
    python3 scripts/fft_capture.py <dump.bin> --tone 107.52e6 --fs 307.2e6
"""
import argparse
import numpy as np

FS = 307.2e6
TONE = 106.275e6  # measured loopback tone (bin 2834); see ISS-21


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "path",
        nargs="?",
        default="tests/08_rfdc_capture/capture_run.bin",
        help="raw little-endian int32 capture dump",
    )
    parser.add_argument("--fs", type=float, default=FS,
                        help="effective capture sample rate in samples/s")
    parser.add_argument("--tone", type=float, default=TONE,
                        help="expected residual tone frequency in Hz")
    args = parser.parse_args()

    path, fs, tone = args.path, args.fs, args.tone
    x = np.fromfile(path, dtype="<i4").astype(np.float64)
    if x.size == 0:
        print(f"FFT: empty dump {path}")
        return
    n = x.size
    x = x - x.mean()                      # remove DC
    win = np.hanning(n)
    spec = np.fft.rfft(x * win)
    mag = np.abs(spec)
    freqs = np.fft.rfftfreq(n, d=1.0 / fs)

    peak = int(np.argmax(mag[1:]) + 1)    # skip DC bin
    peak_freq = freqs[peak]

    tone_bin = int(round(tone / fs * n))
    lo = max(1, tone_bin - 3)
    hi = min(len(mag), tone_bin + 4)
    tone_pwr = float(np.sum(mag[lo:hi] ** 2))
    total_pwr = float(np.sum(mag[1:] ** 2))
    floor = (total_pwr - tone_pwr) / max(1, (len(mag) - 1 - (hi - lo)))
    snr_db = 10.0 * np.log10(tone_pwr / floor) if floor > 0 else float("inf")

    matches = "MATCHES" if abs(peak_freq - tone) < 2 * fs / n else "DOES NOT MATCH"
    lines = [
        f"FFT: source={path}",
        f"FFT: N={n} fs={fs/1e6:.3f} MHz",
        f"FFT: peak bin={peak} freq={peak_freq/1e6:.3f} MHz mag={mag[peak]:.1f}",
        f"FFT: tone bin={tone_bin} ({tone/1e6:.2f} MHz) "
        f"tone_pwr={tone_pwr:.3e} noise/bin={floor:.3e} SNR~{snr_db:.1f} dB",
        f"FFT: peak {matches} the expected tone",
    ]
    for line in lines:
        print(line)
    summary = path.rsplit(".", 1)[0] + "_fft.txt"
    with open(summary, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"FFT: summary saved {summary}")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.figure(figsize=(9, 4))
        with np.errstate(divide="ignore"):
            db = 20 * np.log10(np.maximum(mag, 1e-9))
        plt.plot(freqs / 1e6, db)
        plt.axvline(tone / 1e6, color="r", ls="--", lw=0.8,
                    label=f"{tone/1e6:.2f} MHz")
        plt.xlabel("MHz")
        plt.ylabel("dB")
        plt.title(f"ZCU216 ADC capture spectrum ({path})")
        plt.legend()
        plt.tight_layout()
        out = path.rsplit(".", 1)[0] + "_fft.png"
        plt.savefig(out, dpi=110)
        print(f"FFT: plot saved {out}")
    except Exception as exc:  # plotting is optional
        print(f"FFT: plot skipped ({exc})")


if __name__ == "__main__":
    main()
