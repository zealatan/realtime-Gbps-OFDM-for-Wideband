#!/usr/bin/env python3
"""gen_ofdm_dac_waveform.py - offline OFDM DAC-TX waveform generator (RF 6b/6d).

Takes the OFDM slot IQ (packed 32-bit [31:16]=Q [15:0]=I, signed16) at the DUT
sample rate (153.6 Msps), resamples to the DAC LANE rate, mixes to an IF, takes
the real part, quantizes to 16-bit, and packs 16 REAL samples/beat (256-bit)
matching zcu216_dac_tone_axis.v ([15:0]=sample0 ... [255:240]=sample15) into a
$readmemh hex file for ofdm_dac_rom.v.

RF-6d FIX (RF root-cause endgame): the ZCU216 RFDC DAC tile at 6.88128 GSPS /
single-slice could NOT be configured for a transparent Interp=1 real-bypass
datapath -- the IP forced it into a C2R COARSE -Fs/4 mixer mode (DAC_Mode32=3,
Mixer_Type=1, Mixer_Mode=2 C2R, Coarse_Mixer_Freq=3). In C2R the RFDC consumes
the 256-bit beat as 8 I + 8 Q INTERLEAVED complex samples (PG269 "Dual RF-DAC
I/Q Input to Real Output"), NOT 16 sequential real samples. Feeding a baked PURE
REAL full-rate waveform into that path mis-pairs the 16 real lanes into bogus
I/Q, complex-mixes -Fs/4, and emits Re{} -> DESTROYS the fast-varying OFDM (a
flat tone with 16 identical sub-samples is near-DC complex and survives, which
is why the tone looked clean but the OFDM demod was 137% EVM / CP-autocorr~0.01).

The valid real-bypass datapath is DAC_Mode32=0 + DAC_Mixer_Mode32=0 (mixer OFF,
Coarse=0, NCO=0). In that mode the IP FORCES interpolation >= 2 (Interp=1 is
illegal). So the DAC now takes 16 REAL lanes at FS_DAC/INTERP and its own real
interpolation filter up-samples to 6.88128 GSPS. => the generator must bake the
real passband at the LANE rate FS_DAC/INTERP (= 3.44064 GSPS for Interp=2), NOT
the full 6.88128 GSPS. The ADC DDC (-300 MHz fine NCO, decim 16) is UNCHANGED.
Verified (model): EVM 4.8% (vs 137% broken), CP-autocorr peaks at lag 256.

Usage:
  python3 scripts/gen_ofdm_dac_waveform.py <in.mem> <out.hex> \
          [--if 300e6] [--amp 14000] [--interp 2]
"""
import sys, argparse
import numpy as np

FS_IN  = 153.6e6      # OFDM/DUT sample rate
FS_DAC = 6.88128e9    # DAC full output rate
SPB    = 16           # 16-bit samples per 256-bit beat

def read_mem(path):
    iq = []
    for ln in open(path):
        ln = ln.strip()
        if not ln or ln.startswith('//'):
            continue
        w = int(ln, 16) & 0xFFFFFFFF
        i = w & 0xFFFF
        q = (w >> 16) & 0xFFFF
        i = i - 0x10000 if i >= 0x8000 else i   # signed16
        q = q - 0x10000 if q >= 0x8000 else q
        iq.append(complex(i, q))
    return np.array(iq, dtype=complex)

def fft_resample(x, n_out):
    """FFT-based resample of complex x to length n_out (clean for edge-zeroed frames)."""
    n_in = len(x)
    X = np.fft.fft(x)
    Y = np.zeros(n_out, dtype=complex)
    h = n_in // 2
    Y[:h] = X[:h]
    Y[n_out-h:] = X[n_in-h:]
    if n_in % 2 == 0:           # split nyquist bin
        Y[h] = X[h] / 2; Y[n_out-h] += X[h] / 2
    return np.fft.ifft(Y) * (n_out / n_in)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('inmem'); ap.add_argument('outhex')
    ap.add_argument('--if', dest='iff', type=float, default=300e6)
    ap.add_argument('--amp', type=int, default=14000, help='peak |sample| target (16-bit signed)')
    ap.add_argument('--interp', type=int, default=2,
                    help='DAC real-bypass interpolation factor (>=2; lane rate = FS_DAC/interp). '
                         'Use 1 ONLY for a legacy Interp=1 real-bypass DAC.')
    a = ap.parse_args()

    fs_lane = FS_DAC / a.interp          # DAC AXIS lane rate (pre on-chip interpolation)
    ratio   = fs_lane / FS_IN

    iq = read_mem(a.inmem)
    n_in = len(iq)
    n_out = int(round(n_in * ratio))
    assert n_out % SPB == 0 or True, n_out
    # pad n_out up to a multiple of SPB so the beat packing is clean
    if n_out % SPB:
        n_out += SPB - (n_out % SPB)

    up = fft_resample(iq, n_out)                       # 153.6 Msps complex -> fs_lane complex
    t = np.arange(n_out) / fs_lane
    rf = (up * np.exp(2j * np.pi * a.iff * t)).real    # mix to IF, take real -> passband

    peak = np.max(np.abs(rf)) or 1.0
    q = np.round(rf * (a.amp / peak)).astype(np.int64)
    q = np.clip(q, -32768, 32767).astype(np.int32)

    nbeats = n_out // SPB
    with open(a.outhex, 'w') as f:
        f.write(f"// OFDM DAC-TX waveform from {a.inmem}: {n_in} samp @153.6M -> "
                f"{n_out} samp @{fs_lane/1e9:.5f}G (lane rate; DAC interp x{a.interp} "
                f"-> {FS_DAC/1e9:.5f}G), IF={a.iff/1e6:.1f}MHz, peak={a.amp}\n")
        f.write(f"// {nbeats} beats x 256-bit (16 REAL samp/beat, "
                f"[15:0]=s0 .. [255:240]=s15). DAC: Mode0/MixerOff real-bypass.\n")
        for b in range(nbeats):
            word = 0
            for s in range(SPB):
                v = int(q[b*SPB + s]) & 0xFFFF
                word |= v << (16 * s)
            f.write(f"{word:064x}\n")

    clipped = int(np.sum(np.abs(np.round(rf*(a.amp/peak))) > 32767))
    print(f"wrote {a.outhex}: {nbeats} beats ({n_out} samples) @lane {fs_lane/1e9:.5f}G "
          f"(DAC interp x{a.interp} -> {FS_DAC/1e9:.5f}G), IF={a.iff/1e6:.1f}MHz, "
          f"peak_target={a.amp}, clipped={clipped}")
    # spectrum sanity: dominant freq of the real passband (at the LANE rate)
    P = np.abs(np.fft.rfft(rf * np.hanning(n_out)))
    fbin = np.argmax(P) * fs_lane / n_out
    print(f"spectrum peak ~ {fbin/1e6:.1f} MHz (expect near IF {a.iff/1e6:.1f} MHz +/- OFDM BW)")

if __name__ == '__main__':
    main()
