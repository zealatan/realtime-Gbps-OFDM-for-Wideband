#!/usr/bin/env python3
"""Generate the precomputed CE pilot-reciprocal ROM for rx_ch_est.v.

The channel-estimate at each pilot is
    H_pilot[k] = rx[pltIndx[k]] * conj(plt[k]) / |plt[k]|^2 * Q15_SCALE
The transmitted QPSK pilot plt[k] is KNOWN, so
    W[k] = conj(plt[k]) / |plt[k]|^2 * Q15_SCALE   (the rx already carries the
                                                    Q15 scale, so it cancels and
                                                    Hp comes out at Q15 scale)
is a precomputable complex CONSTANT per pilot.  Then
    H_pilot[k] = rx[pltIndx[k]] * W[k]              (single complex MULTIPLY)
which is mathematically identical to the divide -> golden hest.hex UNCHANGED.

Fixed-point format (derived in /tmp/derive_W.py, verified bit-for-bit vs the
old divide on golden + robust):
    WF = 16 fractional bits, CW = 18-bit signed coefficients.
    Wr = round( Q15_SCALE * plI / (plI^2 + plQ^2) * 2^WF )   (Re of W)
    Wi = round(-Q15_SCALE * plQ / (plI^2 + plQ^2) * 2^WF )   (Im of W)
where plI,plQ are the Q15 (int16) pilot components from pilot_rom.hex.
The RTL computes (matching the old divide to 0-1 LSB, golden to 0-2 LSB):
    Hp_i = sat18( (rxI*Wr - rxQ*Wi + 2^(WF-1)) >> WF )
    Hp_q = sat18( (rxI*Wi + rxQ*Wr + 2^(WF-1)) >> WF )

ROM line = {Wi[17:0], Wr[17:0]} (36 bits, 9 hex), in the SAME order the CE pulls
the pilot stream: slot-major (symbol 0..11 outer, pilot k=0..31 inner), 384
lines.  Built directly from golden/rx_downstream/pilot_rom.hex so the W ROM and
the pilot ROM are guaranteed consistent.
"""
import os

NUM_PILOTS = 32
NUM_DATA   = 12
WF         = 16          # coeff fractional bits
CW         = 18          # coeff signed width
Q15_SCALE  = 5090.697374

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load_pilot_hex(path):
    """Return list of (plI, plQ) signed int16 from a {Q[31:16],I[15:0]} hex."""
    out = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            w = int(ln, 16)
            i = w & 0xFFFF
            q = (w >> 16) & 0xFFFF
            if i >= 0x8000:
                i -= 0x10000
            if q >= 0x8000:
                q -= 0x10000
            out.append((i, q))
    return out


def tc(v, b=CW):
    return int(v) & ((1 << b) - 1)


def main():
    src = os.path.join(ROOT, "golden", "rx_downstream", "pilot_rom.hex")
    plt = load_pilot_hex(src)
    assert len(plt) == NUM_PILOTS * NUM_DATA, f"expected 384 pilots, got {len(plt)}"

    lim = 1 << (CW - 1)
    # Two copies (identical content), so every flow that resolves a CE ROM finds
    # one:  golden/rx_downstream/ (bare-filename + golden flows) AND
    # rtl/rx_ch_est_rom/ (next to ce_interp_W.hex; the relative default).
    outs = [
        os.path.join(ROOT, "golden", "rx_downstream", "ce_pilot_recip.hex"),
        os.path.join(ROOT, "rtl", "rx_ch_est_rom", "ce_pilot_recip.hex"),
    ]
    lines = []
    maxq = 0
    for (plI, plQ) in plt:
        den = plI * plI + plQ * plQ
        assert den != 0, "QPSK pilot must be nonzero"
        Wr = round(Q15_SCALE * plI / den * (1 << WF))
        Wi = round(-Q15_SCALE * plQ / den * (1 << WF))
        maxq = max(maxq, abs(Wr), abs(Wi))
        assert abs(Wr) < lim and abs(Wi) < lim, \
            f"coeff overflow {Wr},{Wi} >= {lim} (widen CW)"
        lines.append("%09x\n" % ((tc(Wi) << CW) | tc(Wr)))

    for out in outs:
        with open(out, "w") as f:
            f.writelines(lines)
        print(f"wrote {out}  {len(plt)} lines; WF={WF} CW={CW} "
              f"max|coeff|={maxq} (<{lim})")


if __name__ == "__main__":
    main()
