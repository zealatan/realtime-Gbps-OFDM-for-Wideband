# RX Downstream RTL Contract — FFT → CE → EQ → 16-QAM demod

**Source of truth:** `ref/transmitter.c`, `ref/receiver.c`,
`ref/signal_processing_common.c`, `ref/auxiliary.c`, `ref/pluto.h`.
**Reference model:** `scripts/rx_downstream_ref.py` (numpy, bit-faithful).
**Golden generator (sync-capable frame):**
`scripts/gen_rx_downstream_synccap_golden.py` (numpy only).
**Validation achieved:** end-to-end loop (TX→identity channel→RX) gives
**BER = 0 / 10608** and **RMS EVM = 1.171e-04 (0.0117 %)**. This is the
correctness gate every RTL module must hold to.

> ## ⚠️ SYNC-CAPABLE FRAME (correction — read this first)
>
> The golden frame in this directory is now ONE COMPLETE, SYNC-CAPABLE
> 4160-sample frame that BOTH the synchronizer can lock onto AND the
> downstream can demodulate. The earlier version put **placeholder/zero
> samples in the 576-sample sync region** — that was wrong: a zero sync
> region produces **no frame-detection peak**, so the end-to-end chain
> (sync → FFT → CE → EQ → demod) could not run at all.
>
> The frame is built by:
> - keeping `golden/p5_wrapper_fullchain/fc_kp0.mem[0:640]` **byte-identical**
>   — `[0:64]` PRE_ZEROS + `[64:640]` the **REAL** PSS/SSS sync region
>   (PSS_CP|PSS|SSS_CP|SSS, 576 samples). The synchronizer therefore makes
>   the **identical** frame-detection peak as on fc_kp0.
> - replacing `fc_kp0.mem[640:4096]` with the **12 proper rx_downstream data
>   symbols** (QPSK pilots on `pltIndx` + 16-QAM data on `dataIndx`, IDFT+CP)
>   from the validated `rx_downstream_ref` model.
> - keeping `fc_kp0.mem[4096:4160]` = POST_ZEROS.
>
> **Sync-capable (verified):** the CP-autocorrelation / PSS-detection metric
> on the new frame has a clear peak at the **PSS symbol end, abs idx 351**
> (CP at abs [64:96) correlates with body tail at [320:352)), value
> **832 982 221** — **bit-identical to fc_kp0** (sync region samples and the
> CP-autocorr metric over `[64:640]` are exactly equal). The 12 data symbols
> each carry their own CP, so the data region shows comparable CP-autocorr
> magnitude (framing preserved).
>
> **Demodulable (verified):** running the downstream RX on the 12 data
> symbols extracted at the corrected positions (after the 576-sample sync
> region, i.e. from abs idx 640) gives **BER = 0 / 10608**, **EVM 0.0117 %**.
>
> **Q15 scale = `5090.697374`** (NOT 2^13). It is chosen to **RMS-match
> fc_kp0's data region**: fc_kp0's data-region complex RMS is `5045.88`
> integer Q15 units; the data symbols' native float RMS is `0.9912`, so the
> scale = `5045.88 / 0.9912 = 5090.70`. The achieved data int RMS is
> `5045.89` (ratio 1.000001 vs fc_kp0). Data peak (int) = `12560` — no
> clipping. Matching this RMS keeps the synchronizer's threshold and the ×4
> gearbox energy assumptions consistent between the sync and data regions.

All golden vectors in this directory were produced by
`python3 scripts/gen_rx_downstream_synccap_golden.py`. Re-running reproduces
them exactly (deterministic; bit + PSS/SSS sources are files, no RNG). It
reads `fc_kp0.mem` read-only and does **not** modify it or any RTL.

---

## 0. Top-level numerology (pluto.h / signal_processing_common.c)

| Symbol | Value | Meaning |
|---|---|---|
| `NSC` | 256 | subcarriers / FFT size |
| `CP_LEN` | 32 | cyclic prefix samples |
| `SYM_LEN` | 288 | one OFDM symbol (CP+body) |
| `NUM_SYN` | 2 | sync symbols per slot (PSS/SSS — **not** demodulated here) |
| `NUM_DATA` | 12 | data OFDM symbols per slot |
| `SLOT_LEN` | 4032 | (2+12)·288 samples |
| `NUM_PILOTS` | 32 | pilot subcarriers per symbol |
| `NUM_DATA_SC` | 221 | data subcarriers = NSC − 32 − 3 |
| `tx/rx_bitsPerSymbol` | 4 | 16-QAM |
| `bitsPerSymbolPilot` | 2 | QPSK |
| data bits / symbol | 884 | 221·4 |

`SCALE_16QAM = 1/sqrt(10) = 0.316227766`,
`SCALE_QPSK = 1/sqrt(2) = 0.707106781`.

---

## 1. Fixed-point / Q-format conventions

### Q15 packing (the canonical M_AXIS word, used by tx_slot, pilot_rom)
One 32-bit beat carries one complex sample:

```
bits [31:16] = Q (imag), signed 16-bit
bits [15:0]  = I (real), signed 16-bit
```

This matches the locked project convention `[31:16]=Q, [15:0]=I` and the
fc_kp0 packing `{im[15:0], re[15:0]}` (same thing).

**Chosen Q15 scale = `5090.697374` (RMS-matched to fc_kp0).**
Reason: the frame's sync region is taken byte-identical from `fc_kp0.mem`
(scale `5045.88`), so the data region must use the **same energy scale** for
the synchronizer threshold + ×4 gearbox assumptions to hold. The data
symbols' native float RMS is `0.9912`; matching fc_kp0's data int RMS
(`5045.88`) gives scale = `5045.88 / 0.9912 = 5090.697374`. The OFDM
time-domain data peak amplitude is ≈ **2.467** → at this scale ≈ `12560`,
safely inside int16 (no clipping). All frequency-domain golden hex files
(`fft_out`, `hest`, `eq_out`, `pilot_rom`) also use scale `5090.697374`, so a
value of 1.0 ⇒ `0x13E3` and `H ≈ 1.0`.

> The `_float.npy` companions remain authoritative; the `.hex` is the
> saturated Q-format view. The previous `2^13 = 8192` scale is superseded —
> it was unaware of fc_kp0's sync region. Do not mix scales.

> Each `*.hex` has a companion `*_float.npy` holding the exact float64
> values — **the .npy is authoritative** for the RTL TB; the .hex is the
> saturated Q-format view a fixed-point datapath should match within its
> own rounding budget.

### Recommended internal widths (proposals — RTL owner may widen)

| Stage | In | Out | Notes |
|---|---|---|---|
| FFT frontend | 16b I/Q (Q13) | 16b I/Q BFP (Q13) | Xilinx xfft + fftshift + 1/√256 (=1/16) scale |
| Ch-Est divide | 16b rx, 16b pilot | ≥18b H (Q13) | H≈1.0 here; allow growth ~×4 for real channels |
| interp_fft (32-IFFT, 256-FFT) | H pilots | H 256 (Q13) | intermediate `hi` taps need ~18b |
| EQ ZF divide | 16b rx, ≥18b H | 16b eq (Q13) | complex divide; guard against |H|²→0 |
| Demod | 16b eq | 4 bits | sign/threshold compares only |

The complex divides (CE and EQ) are the only places that need a real
divider / reciprocal. Because the channel here is identity, `|H|²≈1`, but
the RTL must implement the true division to match the C reference for real
channels.

---

## 2. Subcarrier ordering & index tables

**Bin ordering is `fftshift`ed** (`rearrange_spectrum`, even-length
half-swap). After FFT+rearrange, bin index `0` = most-negative frequency,
bin `128` = DC, bin `255` = most-positive. TX applies the same rearrange
*before* the IFFT, so TX and RX share one indexing convention.

### `pltIndx` (32 pilots) — `pltIndx[i] = 1 + floor(i·256/32) = 1 + 8·i`
```
1, 9, 17, 25, 33, 41, 49, 57, 65, 73, 81, 89, 97, 105, 113, 121,
129, 137, 145, 153, 161, 169, 177, 185, 193, 201, 209, 217, 225, 233, 241, 249
```
(file: `pilot_indx.txt`. Note pilot #16 sits at bin **129**, i.e. DC+1, not DC.)

### `dataIndx` (221 data) — bins 1..254, minus pltIndx, minus DC(128)
```
2,3,4,5,6,7,8, 10..16, 18..24, 26..32, 34..40, 42..48, 50..56, 58..64,
66..72, 74..80, 82..88, 90..96, 98..104, 106..112, 114..120, 122..127,
130..136, 138..144, ... , 250,251,252,253,254
```
(full list in `data_indx.txt`, 221 entries, in ascending bin order — this
is the order EQ output / demod input must use.)

Bins **0** and **255** and **128(DC)** carry no data and no pilot.

---

## 3. Per-module interfaces (one beat = one complex sample unless noted)

### 3.1 FFT frontend  (`tx_slot_iq.hex` → `fft_out.hex`)
- **Input:** the time slot streamed I/Q in Q15, M_AXIS `{Q,I}`. Two forms:
  - `tx_slot_iq.hex` — the **full 4160-sample** frame (PRE_ZEROS(64) +
    sync(576) + data(3456) + POST_ZEROS(64)). Use for a full-chain TB that
    drives the synchronizer too.
  - `tx_slot_iq_4032.hex` — the **synchronizer's corrected M_AXIS output**
    (4032 samples = full frame minus the 64 pre/post zeros). **beat0 = PSS
    CP start** (abs idx 64 of fc_kp0). This is the actual downstream RTL
    input per the sync-wrapper contract.
- In the 4032 stream: samples 0..575 are the 2 **REAL** sync symbols
  (PSS/SSS — used by sync, **not** demodulated by this chain). Data symbol
  `z` (z=0..11) occupies samples `576 + z·288 … 576 + z·288 + 287`.
- **Per symbol:** drop the first `CP_LEN=32` samples, take the next
  `NSC=256`, run a 256-pt forward FFT (`exp(-j2π kn/N)`), apply
  `rearrange_spectrum` (fftshift), then scale by `1/√256`.
- **Output:** 12 symbols × 256 complex bins, fftshift-ordered
  (`fft_out.hex`, 3072 lines; bin order 0..255 within each symbol, symbols
  0..11 consecutively). This is the CE input.

### 3.2 Channel estimation + interpolation  (`fft_out` + `pilot_rom` → `hest.hex`)
Two sub-steps, both from `receiver.c`:

**(a) `ch_estimation_fdm`** — at each pilot bin `i = pltIndx[k]`:
```
tmp  = pltI[k]^2 + pltQ[k]^2
H_i  = (rxI[i]·pltI[k] + rxQ[i]·pltQ[k]) / tmp      // real
H_q  = (rxQ[i]·pltI[k] − rxI[i]·pltQ[k]) / tmp      // imag
```
i.e. `H[i] = rxSym[i]·conj(plt[k]) / |plt[k]|²`. Only the 32 pilot bins get
a value; all other bins are 0 at this point. Pilot symbols for block `z`
come from `pilot_rom.hex` lines `z·32 … z·32+31` (QPSK, Q15).

**(b) `interp_fft`** — turn 32 pilot estimates into a smooth 256-bin H:
1. `mid = 128`. Copy the 32 pilot H values into a scratch `hi[128..159]`
   (in pilot order k=0..31).
2. 32-pt **IFFT** of `hi[128..159]` (`exp(+j)`, then `/32`) → write to
   `hi[0..31]`.
3. Zero `hi[32..255]` (th = min(32,32) = 32).
4. 256-pt **forward FFT** of `hi[0..255]` → `H[0..255]`.
   *(Note: no fftshift inside interp_fft.)*

**(c) +1 offset memcpy** (`receiver.c` l.152-153): the interpolated
`H[0..253]` is copied into the equalizer's `Hest[1..254]`; `Hest[0]` and
`Hest[255]` are left **0**. The golden `hest.hex` is this final `Hest` array
(post-shift) actually consumed by EQ — 12 × 256 lines. `Hest[0]` reads
`0x00000000`, pilot/data region reads ≈ `0x00002000` (H≈1.0).

> The +1 offset is a known quirk of the C reference (it shifts the whole
> CTF by one bin). With an identity channel H is flat ≈ 1, so the shift is
> harmless and **BER stays 0**. RTL must reproduce the shift bit-for-bit so
> it matches the C reference under *real* channels too. Bins 0 and 255 being
> 0 means EQ at those bins divides by 0 — they carry no data/pilot, so the
> result is discarded (guard with |H|²==0 ⇒ output 0).

### 3.3 Equalizer — ZF  (`fft_out` + `hest` → `eq_out.hex`)
Per bin `i = 0..255`:
```
num_i = rxI[i]·HestI[i] + rxQ[i]·HestQ[i]
num_q = rxQ[i]·HestI[i] − rxI[i]·HestQ[i]
sc    = HestI[i]² + HestQ[i]²            // = |H|²
eq[i] = (num_i + j·num_q) / sc           // rxSym·conj(H)/|H|²
```
(`sc==0` ⇒ output 0; only happens at bins 0/255 which are discarded.)
Then **extract the 221 `dataIndx` bins, in ascending order** → that is the
demod input. Golden `eq_out.hex` = 12 × 221 equalized data carriers
(2652 lines).

### 3.4 16-QAM demod  (`eq_out` → `rx_bits.txt`)
Per data carrier, thresholds `d = {−2, 0, +2}·SCALE_16QAM`:
```
I-axis -> b0,b1 :  re<d0:(0,1) | re<d1:(0,0) | re<d2:(1,0) | else:(1,1)
Q-axis -> b2,b3 :  im<d0:(0,1) | im<d1:(0,0) | im<d2:(1,0) | else:(1,1)
```
Output 884 bits/symbol, order = `[b0 b1 b2 b3]` per carrier, carriers in
`dataIndx` order. `rx_bits.txt` = 12 lines × 884 chars; must equal
`tx_bits.txt` (BER 0).

---

## 4. 16-QAM and QPSK bit↔symbol maps (exact)

### 16-QAM modulate (`generate_symbol_16qam`)
`map16QAM = [−1, −3, +1, +3]·SCALE_16QAM` (indexed 0..3).
```
tmpI = b0·2 + b1·1   ->  symI = map16QAM[tmpI]
tmpQ = b2·2 + b3·1   ->  symQ = map16QAM[tmpQ]
```
So per axis: `00→−1, 01→−3, 10→+1, 11→+3` (×SCALE). The demod thresholds in
§3.4 are the exact inverse.

### QPSK pilot modulate (`generate_symbol_qpsk`)
```
symI = (b0 ? +1 : −1)·SCALE_QPSK
symQ = (b1 ? +1 : −1)·SCALE_QPSK
```

---

## 5. FFT/IFFT normalization summary (FFTW → numpy → RTL)

| C call | math | numpy equiv | extra scale applied |
|---|---|---|---|
| TX `ifft_new` | FFTW_BACKWARD `exp(+j)` | `N·np.fft.ifft` | then `/√256` |
| RX `fft_with_rearrange` | FFTW_FORWARD `exp(−j)` | `np.fft.fft` | rearrange, then `/√256` |
| interp 32-IFFT | FFTW_BACKWARD | `32·np.fft.ifft` | then `/32` (net = `np.fft.ifft`) |
| interp 256-FFT | FFTW_FORWARD | `np.fft.fft` | none |

A Xilinx xfft configured "unscaled forward, exp(−j)" + the explicit `1/√256`
(= `1/16`) post-scale reproduces the RX FFT stage.

---

## 6. Files in this directory

| File | Shape | Format |
|---|---|---|
| `tx_slot_iq.hex` | 4160 | Q15 `{Q,I}` FULL sync-capable frame (PRE+sync+data+POST) |
| `tx_slot_iq_4032.hex` | 4032 | Q15 `{Q,I}` synchronizer corrected M_AXIS output (beat0=PSS CP) |
| `tx_slot_iq_float.npy` | 4160×2 | float [I,Q] (full frame) |
| `fft_out.hex` / `_float.npy` | 12×256 | Q `{Q,I}` / complex (CE INPUT), scale 5090.70 |
| `hest.hex` / `_float.npy` | 12×256 | Q `{Q,I}` / complex (EQ INPUT, post +1 shift) |
| `eq_out.hex` / `_float.npy` | 12×221 | Q `{Q,I}` / complex (demod INPUT) |
| `pilot_rom.hex` / `_float.npy` | 384=32×12 | Q `{Q,I}` QPSK pilots (CE pilot ROM) |
| `tx_bits.txt` / `rx_bits.txt` | 12×884 | ASCII bits (BER check; identical) |
| `pilot_indx.txt` / `data_indx.txt` | 32 / 221 | CSV bin indices |

Bit sources (deterministic, identical to the C program): the first
10608 lines of `ref/Data_Bits.txt` (data) and first 768 lines of
`ref/Pilot_Bits.txt` (pilots). No seed / RNG is used. The PSS/SSS sync
region is taken byte-identical from `golden/p5_wrapper_fullchain/fc_kp0.mem`
(read-only; never modified).

The 2 sync symbols are the **REAL** PSS/SSS (they drive frame detection,
producing the peak `832 982 221` at abs idx 351 identical to fc_kp0); they
are **not** part of the downstream FFT/CE/EQ/demod chain and are never
demodulated. Downstream starts at the first data symbol (abs idx 640 of the
full frame, or beat 576 of the 4032 stream).
