# OFDM Scope GUI — real-time Constellation + Channel viewer

A browser-based, **stdlib-only HTTP server** (`http.server.ThreadingHTTPServer`)
that visualizes the OFDM RX during ZCU216 FPGA tests. It reads a captured OFDM
baseband file, runs the verified RX-downstream demod
(`scripts/rx_downstream_ref.py`: FFT &rarr; pilot channel-estimation &rarr; ZF
equalize &rarr; QAM demod) with numpy. It runs **headless** on the lab machine
and is viewable remotely in any browser.

## TRUE real-time live page (default, `/`)

The default page is a **client-side scope**: two HTML5 `<canvas>` elements
(constellation + channel) drawn with **vanilla JS on the raw 2D context** — no
external libraries, no CDN (works offline). The browser polls the JSON data
endpoint `GET /api/points` every `--refresh-ms` (default 200 ms) and redraws the
canvases. There is **no page reload and no PNG** — the constellation updates
smoothly like a real scope. A **Start/Stop** button pauses polling, a **Refresh
slider** changes the poll interval live, and **Capture now** triggers the board
capture then refetches.

A **legacy PNG view** (the original matplotlib Agg &rarr; base64 page) is kept as
a fallback at **`/png`**.

It is a **host-side viewer only** — it does not touch the verified RX RTL or the
golden vectors.

File: `RTL_SYNC_PHASE5/gui/ofdm_scope_gui.py`

## Animated DEMO mode (`--demo`)

For demos/presentations where a live board capture is too slow to show motion,
`--demo` makes the scope **animate in real time** with **no board and no capture
file**. On **each** `GET /api/points` poll the server synthesizes a
**time-varying received OFDM slot** from the known golden TX
(`golden/rx_downstream/<mod>/tx_slot_iq_float.npy`), applies impairments that are
**smooth functions of wall-clock time** (so consecutive polls differ slightly →
smooth animation), then runs the **same real demod pipeline** (slot-start → FFT →
pilot-CE → ZF-EQ → QAM-demod) so the constellation, channel panel, and EVM/BER
all reflect the current synthetic conditions. The golden load is cached; each
poll computes in ~30–40 ms so polling at 200–500 ms stays smooth.

Impairments (each a smooth periodic function of time `t`):

| impairment | function | default period / amplitude | effect |
|------------|----------|----------------------------|--------|
| residual CFO | `cfo(t)=A·sin(2π t/T_cfo)` | `T_cfo=12 s`, `A=8e-5` cyc/smp (≈±12 kHz @153.6 Msps) | whole constellation + channel-angle panel slowly rotate |
| SNR breathing | `SNR(t)=28+12·sin(2π t/T_snr)` dB | `T_snr=9 s` (16…40 dB) | AWGN level oscillates; clusters tighten/loosen; BER hits **0** at high SNR, nonzero at low |
| channel fade | mild 2-tap multipath, 2nd tap gain/delay/phase drift | `T_fade=15 s`, tap2 gain ≤0.30, delay 1…6 smp | `\|H(k)\|` panel ripples & slowly changes shape; ZF EQ corrects most, residual shows in EVM |
| modulation cycle (optional) | QPSK→16→64→256-QAM→repeat | `T_mod=24 s` (6 s each) | constellation density changes; ideal grid + metrics mod follow |

The RNG is seeded by a quantized timestamp so a given instant is
reproducible-ish but the stream stays lively. The modulation cycle is toggled
with `--demo-cycle-mod` / `--no-demo-cycle-mod`. All periods/amplitudes are
overridable (`--demo-t-cfo`, `--demo-cfo-amp`, `--demo-t-snr`, `--demo-snr0`,
`--demo-snr-amp`, `--demo-t-fade`, `--demo-t-mod`).

```bash
cd RTL_SYNC_PHASE5
# animated demo on :8080 (no board), cycling the modulation:
python3 gui/ofdm_scope_gui.py --demo --mod 16qam --port 8080 \
        --refresh-ms 300 --demo-cycle-mod
# then open  http://localhost:8080/   (constellation + channel move live)
```

The metrics panel additionally shows the **commanded** ground-truth impairments
(`SNR commanded`, `Fade tap2 gain/delay`, `Demo t`) alongside the demod-measured
EVM/BER/SNR, so you can watch BER/EVM rise and fall against the driving SNR.
`--demo` ignores `--capture` and reports `format=demo`.

## Panels

1. **Constellation** — equalized 221 data subcarriers &times; 12 symbols as I/Q
   points, symbol-colored, with the ideal constellation reference grid for the
   selected modulation (QPSK / 16 / 64 / 256-QAM).
2. **Channel** — estimated channel `H(k)`: `|H|` in dB and `angle(H)` in degrees
   vs subcarrier index (the pilot-interpolated channel, pilots highlighted).
3. **Metrics** — detected modulation, live **THROUGHPUT** (PHY gross / framed /
   goodput, see below), BER (vs golden bits if available), EVM (%), SNR estimate,
   sync info (slot start, CFO estimate, peak metric), capture RMS and sample
   count.

## Live THROUGHPUT metric

The metrics panel and the `/api/points` JSON carry a live PHY-throughput block
that tracks the **current modulation and BER** every poll (so in `--demo` mode it
breathes with the modulation cycle and the SNR trough). OFDM numerology:

- 221 data subcarriers &times; 12 data symbols = **2652 data-SC per slot**
- slot = **4032 samples** (14 sym &times; 288); on-wire framed period = **4160**
- bits/SC = `2·k` = `{QPSK:2, 16QAM:4, 64QAM:6, 256QAM:8}`

At sample rate `Fs` (samples/s):

```
gross_bps   = 2652 · bits_per_SC · (Fs / 4032)   # raw PHY payload rate
framed_bps  = 2652 · bits_per_SC · (Fs / 4160)   # incl. inter-slot guard
goodput_bps = gross_bps · (1 − BER)              # info bits after bit errors
```

`Fs` is set with **`--fs`** (default **`153.6e6`** = RF DDC baseband). The board
**sustained** rate is **`162e6`** (`--fs 162e6`). Reference gross rates:

| modulation | bits/SC | gross @153.6 Msps | gross @162 Msps |
|------------|---------|-------------------|-----------------|
| QPSK       | 2       | 202 Mbps          | 213 Mbps        |
| 16-QAM     | 4       | 404 Mbps          | 426 Mbps        |
| 64-QAM     | 6       | 606 Mbps          | 639 Mbps        |
| 256-QAM    | 8       | 808 Mbps          | 852 Mbps        |

The panel renders e.g. `PHY (gross) 426.2 Mbps`, `Goodput 394.1 Mbps`,
`Throughput cfg 16QAM @162.0Msps (4 b/SC)`; goodput drops below gross whenever
BER > 0 (visible at the demo's low-SNR trough). The legacy `/png` dashboard shows
the same three rates and puts the gross rate + modulation in its title pill.

## Capture formats (`--format`)

- `digital` — digital-loopback / golden TX slot (the known-good **BER=0** path).
  Accepts `tx_slot_iq.hex` (4032 hex words `{Q[31:16],I[15:0]}`), the float
  `.npy`, or a raw `.bin` in the same 32-bit packing. Normalised to amplitude ~1.
- `rf` — RF DDC capture (`tests/08_rfdc_capture/capture_*_sweep.bin`), raw
  little-endian signed 32-bit `{Q[31:16], I[15:0]}`, 153.6 Msps. Adds a coarse
  residual-CFO estimate (CP autocorrelation) + a timing search to align onto a
  4032-sample OFDM slot before demod.

## Run

```bash
cd RTL_SYNC_PHASE5

# Known-good digital-loopback / golden capture (BER=0, tight 16-QAM):
python3 gui/ofdm_scope_gui.py \
    --capture golden/rx_downstream/16qam/tx_slot_iq.hex \
    --format digital --mod 16qam --port 8080

# RF DDC capture (live RF OFDM once the loopback datapath is fixed):
python3 gui/ofdm_scope_gui.py \
    --capture ../tests/08_rfdc_capture/capture_clean1_sweep.bin \
    --format rf --mod 16qam --port 8080

# then open  http://<host>:8080
```

Auto-detect the modulation with `--mod auto` (picks the lowest-EVM mapping).

### Options

| flag | default | meaning |
|------|---------|---------|
| `--capture PATH` | (required) | capture file (.bin/.hex/.npy) |
| `--format {digital,rf}` | digital | capture format |
| `--mod {auto,qpsk,16qam,64qam,256qam}` | 16qam | modulation |
| `--refresh-ms N` | 200 | **live page** poll interval (ms) |
| `--cache-ttl S` | 0.5 | reuse a cached demod for `/api/points` for S seconds (a capture-file mtime change always forces a fresh demod) |
| `--fs HZ` | 153.6e6 | sample rate for the live **throughput** metric (RF DDC baseband; board sustained is `162e6`) |
| `--refresh N` | 5 | legacy PNG page (`/png`) auto-refresh seconds |
| `--no-auto` | off | disable legacy PNG page auto-refresh |
| `--host` / `--port` | 0.0.0.0 / 8080 | bind address |
| `--capture-cmd 'CMD'` | (off) | shell cmd for the "Capture now" button |
| `--board` | off | shortcut for `--capture-cmd 'scripts/run_rfsync.sh gui'` |

## Real-time behaviour

- The **live page** (`/`) polls `GET /api/points` every `--refresh-ms` and
  redraws the canvases client-side. The server re-demods the current capture
  file on request, but caches the result for `--cache-ttl` seconds so rapid polls
  are cheap; a change to the capture file's mtime (e.g. the board overwriting it
  in place) always forces a fresh demod, so new data shows up live.
- The poll interval can be changed live with the Refresh slider, and polling can
  be paused/resumed with Start/Stop — all without reloading the page.
- The legacy PNG page (`/png`) instead uses a `<meta refresh>` every `--refresh`
  seconds; the capture path / format / mod can be changed from its top bar.
- **Capture now** hits `POST /api/capture`. With `--capture-cmd` (or `--board`)
  it runs the existing board capture flow (`scripts/run_rfsync.sh <label>`) from
  the repo root, then the live page refetches. Without it, the GUI stays in pure
  **file-replay** mode and reports that board trigger is disabled — so it works
  with no board attached.

## Endpoints

- `GET /` (also `/live`) — the **live client-side canvas page** (vanilla JS)
- `GET /api/points` — **JSON demod data** for the live page: constellation
  (`const.I`/`Q`/`sym` parallel arrays for 221&times;12 equalized points, plus
  `ideal_I`/`ideal_Q` for the reference grid), channel estimate
  (`chan.sc`/`magdb`/`angdeg`/`pilot_mask`/`pilot_idx` over all 256 SC), and
  `metrics` (`mod`, `evm_pct`, `ber`, `snr_db`, `n_symbols`, `slot_start`,
  `cfo`, `peak`, `rms`, …), and a `throughput` block
  (`gross_mbps`, `framed_mbps`, `goodput_mbps`, `bits_per_sc`, `fs_msps`)
  computed from the current modulation + BER + `--fs`. Floats are rounded for a
  compact (~58 KB) payload.
- `GET /png` — legacy matplotlib PNG dashboard (fallback; accepts
  `capture`/`format`/`mod`/`refresh`/`auto` query params)
- `GET /api/state` — JSON `{ber, evm, mod, ts}`
- `GET /healthz` — liveness
- `POST /api/capture` — trigger a fresh board capture (if enabled) + re-render

## Verified

Rendered on the known-good digital-loopback golden capture
(`golden/rx_downstream/16qam/tx_slot_iq.hex`):

- `GET /api/points` returns valid JSON: `ok=true`, 2652 constellation points
  (221 SC &times; 12 sym) in `const.I`/`Q`/`sym`, 16 ideal points, a 256-SC
  channel with 32 pilots, and metrics **BER = 0.0, EVM = 0.007 %**
- The live page (`/`) loads with both `<canvas>` elements, the
  `fetch('/api/points')` poll loop, `drawConst`/`drawChan` 2D-context renderers,
  no `<meta refresh>`, no embedded PNG, and no external CDN libs
- **BER = 0.0** (0/10608 bits) vs golden `tx_bits.txt`
- **EVM = 0.007 %**, SNR estimate ~83 dB
- Constellation: tight 16-QAM clusters sitting on the ideal grid
- Channel: flat `|H|` ≈ 0 dB, `angle(H)` ≈ 0° across the occupied band (identity
  channel)
- `--mod auto` correctly detects `16qam`; 64-QAM golden also demods to BER = 0
- RF format path renders without error on `capture_clean1_sweep.bin` (high EVM
  as expected — the RF loopback datapath corruption is a separate open bug; once
  fixed, the same GUI shows the live RF constellation)

## Notes

- Deps: `numpy` + `matplotlib` only (both already used across the repo). The HTTP
  server is pure Python stdlib.
- The demod imports `RTL_SYNC_PHASE5/scripts/rx_downstream_ref.py` directly, so
  it stays bit-faithful to the C reference and the RTL golden. Pilots are loaded
  from `golden/rx_downstream/16qam/pilot_rom_float.npy`.
