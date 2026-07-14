# FPGA-Based OFDM Transceiver (AMD ZCU216 RFSoC)

A **complete, mode-selectable OFDM transceiver** implemented in RTL for the
AMD **ZCU216 RFSoC** evaluation board. The full transmit and receive chains
are written in synthesizable Verilog, verified bit-exactly against a C / NumPy
reference model, and proven on real silicon.

> **Headline result:** the transceiver runs end-to-end on the ZCU216 at the
> full **187.5 MHz** sample clock with **BER = 0** (bit-error-rate zero) in
> simulation *and* on silicon, across **4 modulations** (QPSK / 16-QAM /
> 64-QAM / 256-QAM) and **3 runtime modes** (TX / RX / LOOPBACK).

---

## Table of contents

1. [What this project is](#1-what-this-project-is)
2. [Repository structure](#2-repository-structure)
3. [How to use Git (beginner-friendly)](#3-how-to-use-git-beginner-friendly)
4. [How to build & run](#4-how-to-build--run)
5. [The design principle / flow](#5-the-design-principle--flow)
6. [Dashboards & docs](#6-dashboards--docs)

---

## 1. What this project is

This repo contains a working **Orthogonal Frequency-Division Multiplexing
(OFDM)** modem — the same kind of physical layer used by Wi-Fi, LTE and 5G —
built from scratch in RTL and deployed onto an RFSoC.

The core design lives in **`RTL_SYNC_PHASE5/`**. It is one Verilog design that,
selected at runtime, behaves as a **transmitter**, a **receiver**, or a
**digital loopback** (TX feeding RX internally). Both chains share the same
256-point FFT engine, the same QAM constellation logic, and the same framing.

### Numerology (the radio "shape")

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `NSC`        | 256  | sub-carriers per OFDM symbol (FFT size) |
| `CP_LEN`     | 32   | cyclic-prefix length (guard samples) |
| Data SC      | 221  | sub-carriers carrying payload |
| Pilots       | 32   | QPSK pilot sub-carriers (for channel estimation) |
| Data symbols | 12   | OFDM data symbols per frame |
| Sync symbols | 2    | PSS + SSS synchronization symbols per frame |
| Slot length  | 4032 | samples in one OFDM slot |

### Selectable modes & modulations

- **`mode[1:0]`** — `0 = TX`, `1 = RX`, `2 = LOOPBACK`
- **`mod_sel[1:0]`** — `0 = QPSK`, `1 = 16-QAM`, `2 = 64-QAM`, `3 = 256-QAM`

### What is verified

| Result | Where | Status |
|--------|-------|--------|
| Clean digital loopback, all 4 modulations | xsim (real Xilinx xfft IP) | **BER = 0** |
| Mode-selectable transceiver, 3 modes | xsim | **BER = 0** |
| Full RX at full rate (187.5 MHz) | ZCU216 **silicon** | **BER = 0** |
| Mode-selectable 3 modes | ZCU216 **silicon** | **BER = 0** |
| Multi-frame streaming | ZCU216 **silicon** | **5 / 5 frames BER = 0** |
| RF DAC→ADC analog loopback | ZCU216 RF | C2R mixer bug **fixed**; residual traced to a degraded SMA loopback cable (physical debug) |

---

## 2. Repository structure

The active design and everything you need to reproduce results is under
**`RTL_SYNC_PHASE5/`**. Other top-level dirs are bring-up scaffolding,
hardware projects, and reference material.

```
FPGA_Based_OFDM_Transceiver/
├── README.md                     # ← you are here
├── RTL_SYNC_PHASE5/              # ★ the transceiver design (start here)
│   ├── rtl/                      # synthesizable Verilog
│   │   ├── ofdm_transceiver_top.v    # mode-selectable TX/RX/LOOPBACK top
│   │   ├── ofdm_xcvr_board_top.v     # board adapter (GPIO/AXI control wrap)
│   │   ├── tx_subcarrier_map.v       # QAM map + QPSK pilots + fftshift
│   │   ├── tx_ifft_frontend.v        # 256-pt IDFT (xfft) + cyclic prefix
│   │   ├── tx_ofdm_top.v             # PSS/SSS + 12 data symbols -> 4032 slot
│   │   ├── rx_full_chain_top.v       # full RX: sync->FFT->CE->EQ->demod
│   │   ├── meyr_cfo_top.v + meyr_*   # frame sync + integer-CFO core
│   │   ├── frame_detector.v, frac_cfo_*  # timing + fractional-CFO chain
│   │   ├── rx_fft_frontend.v         # 256-pt FFT receive front-end
│   │   ├── rx_ch_est.v               # pilot-based channel estimation
│   │   ├── rx_equalizer.v            # zero-forcing equalizer
│   │   ├── rx_demod_qam.v            # QAM slicer / demodulator
│   │   ├── rx_ber_checker.v          # on-chip BER counter
│   │   ├── xfft_N/ xfft_2N/ xfft_IFFT/   # real Xilinx xfft 9.1 IP (.xci)
│   │   └── tx_rom/ rx_ch_est_rom/    # generated ROM hex (constellations, LUTs)
│   ├── tb/                        # SystemVerilog testbenches
│   ├── golden/                    # bit-exact reference vectors
│   ├── ref/                       # C reference (receiver.c, transmitter.c)
│   ├── scripts/                   # build / sim / regression / golden-gen
│   │   ├── run_xcvr_3mode.sh          # 3-mode transceiver gate
│   │   ├── run_tx_rx_loop_allmods.sh  # 4-modulation clean-loopback gate
│   │   ├── run_rtl_regression.py      # required-gate regression registry
│   │   └── rx_downstream_ref.py       # NumPy golden model
│   ├── docs/                      # specs, gate logs, block diagrams
│   ├── status/                    # dashboard.json (KPI source of truth)
│   └── vivado_xsim/tcl/           # xsim project Tcl (build artifacts ignored)
├── hardware/                     # Vivado block-design projects + RFDC
├── software/                     # Vitis firmware (board bring-up / BER readout)
├── scripts/                      # repo-level helper scripts
├── docs/                         # repo-level docs + diagrams
├── rtl_dashboard/                # RTL coverage / status HTML
├── fpga_dashboard/               # silicon (FPGA) coverage / status HTML
└── *.html                        # status hub, algorithm spec, verification plan
```

---

## 3. How to use Git (beginner-friendly)

Git tracks the history of every file so you can see *what changed, when, and
why* — and undo mistakes. Here is the minimum you need, with the reasoning.

### Branches — *why they exist*

A **branch** is an independent line of work. We use two:

- **`RX_SYNC`** — the **working branch**. Do all day-to-day work here.
- **`main`** — the **integration branch**. Stable, reviewed work lands here.

Working on a branch means your in-progress changes never destabilize `main`.

```bash
git branch                 # list local branches (* marks current)
git checkout RX_SYNC       # switch to the working branch
```

### Get the code

```bash
git clone <repo-url>                 # download the repo + full history
cd FPGA_Based_OFDM_Transceiver
git checkout RX_SYNC                 # move onto the working branch
```

### See what you changed — *before committing*

Always look before you commit, so you commit exactly what you intend:

```bash
git status                 # which files are new / modified / staged
git diff                   # exact line-by-line changes (unstaged)
git diff --staged          # changes you have already staged
```

### Stage & commit — *save a snapshot with a reason*

A commit is a snapshot plus a message explaining **why**. Good messages are
how future-you understands the history.

```bash
git add README.md docs/transceiver_block_diagram.html   # stage specific files
git add -A                                              # or stage everything
git commit -m "docs: add top-level README + transceiver block diagram"
```

**Commit message convention for this repo** — end the message body with these
two trailers (they link the commit to its authoring session):

```
docs: short summary of what changed

Longer explanation if useful.

Co-Authored-By: <name> <email>
Claude-Session: <session-url>
```

> Tip: commit **related** changes together and keep unrelated changes in
> separate commits — it makes history and code review far easier.

### Send your work up / pull others' work down

```bash
git push origin RX_SYNC    # publish your commits to the shared RX_SYNC branch
git pull origin RX_SYNC    # fetch + merge the latest from the shared branch
```

`push` shares your commits; `pull` brings in everyone else's. Pull before you
start working so you build on the latest code.

### Read the history — *find when something landed*

```bash
git log --oneline                       # compact one-line-per-commit history
git log --oneline -10                    # last 10 commits
git log --oneline --grep "BER"           # commits whose message mentions "BER"
git log --oneline -- rtl/rx_equalizer.v  # history of one file
git show <commit-hash>                   # full diff + message of one commit
git blame rtl/rx_demod_qam.v             # who last changed each line, and when
```

Example — *when did multi-modulation land?*

```bash
git log --oneline --grep "modulation"
# ee1e376 Multi-modulation QPSK/16/64/256-QAM (mod_sel): all 4 clean-loopback BER=0 (sim)
```

---

## 4. How to build & run

> **The real-IP rule.** Functional simulation uses the **real Xilinx xfft 9.1
> IP** and the **locked target part `xczu9eg-ffvb1156-2-e`**. A gate is only
> "PASS" on a real-IP run — stub/fallback runs are sanity checks only. Tools:
> **Vivado 2021.1** (simulation) and **Vitis 2022.2** (firmware).

All commands below run from `RTL_SYNC_PHASE5/`.

### a) Run a simulation gate

```bash
cd RTL_SYNC_PHASE5

# 3-mode transceiver (TX / RX / LOOPBACK) end-to-end, BER must be 0
bash scripts/run_xcvr_3mode.sh

# 4-modulation clean digital loopback (QPSK/16/64/256-QAM), BER must be 0
bash scripts/run_tx_rx_loop_allmods.sh
```

Each gate writes a PASS/FAIL report under `vivado_xsim/reports/`.

### b) Run the regression

```bash
cd RTL_SYNC_PHASE5
python3 scripts/run_rtl_regression.py            # run the required-gate set
python3 scripts/run_rtl_regression.py --list     # list the gates without running
```

The registry in `scripts/run_rtl_regression.py` is the single source of truth
for the required gate set.

### c) Build a bitstream (high level)

The hardware block design (RFDC + DMA + the transceiver IP) lives under
`hardware/`. The flow is the standard Vivado one: open the project, run
synthesis → implementation → generate bitstream, then export the XSA for
Vitis. Synthesis / timing-closure must run on the locked part.

### d) Run on the ZCU216 board (high level)

1. Program the bitstream onto the ZCU216 (JTAG/USB).
2. Boot/launch the Vitis firmware in `software/` (sets `mode`, `mod_sel`,
   issues `start`, reads back the on-chip BER counter via GPIO/AXI-Lite).
3. Read the BER counter — the verified result is **0**.

---

## 5. The design principle / flow

### Methodology: model first, then RTL, then silicon

Every block is proven against a reference **before** it is trusted. The chain
of evidence is:

```
  C reference            NumPy golden model        RTL (Verilog)
  ref/receiver.c    ->   scripts/                ->   rtl/*.v
  ref/transmitter.c      rx_downstream_ref.py
        │                       │                       │
        └──────── bit-exact compare ───────────┬────────┘
                                               ▼
                       xsim with REAL Xilinx xfft 9.1 IP
                       (locked part xczu9eg-ffvb1156-2-e)
                                               │
                                               ▼
                              ZCU216 RFSoC silicon (BER = 0)
```

The C reference defines *correct behavior*; the NumPy golden model makes it
easy to generate bit-exact vectors; the RTL must match those vectors under
xsim with the **real** FFT IP; and only then does it go to silicon.

### TX → channel → RX block diagram

```
            ┌──────────────────── TX chain ────────────────────┐
 data bits  │  tx_subcarrier_map     tx_ifft_frontend          │
 ──────────▶│  QAM map + QPSK pilots  256-pt IDFT (xfft)        │── tx_out
            │  + fftshift            + cyclic prefix (CP=32)    │  (4032 slot)
            │           │                     │                 │
            │           └──────▶ tx_ofdm_top ─┘                 │
            │            PSS/SSS + 12 data symbols -> 4032 slot │
            └──────────────────────────────────────────────────┘
                                   │
                  ┌────────────────┴─────────────────┐
                  │  channel / loopback / RF DAC↔ADC  │
                  └────────────────┬─────────────────┘
                                   │
            ┌──────────────────── RX chain ────────────────────┐
 rx_in      │  synchronizer       rx_fft_frontend              │
 ──────────▶│  frame-detect +     256-pt FFT                   │
 (4160      │  timing + frac/int  │                            │
  frame)    │  CFO (meyr_cfo)     ▼                            │
            │        │         rx_ch_est ─▶ rx_equalizer ─▶    │── demod
            │        │         pilot CE      zero-forcing EQ   │   bits
            │        └────────────────────────▶ rx_demod_qam ─┘
            │                                    QAM slicer     │
            │         rx_ber_checker  (on-chip BER = 0)         │
            └──────────────────────────────────────────────────┘

  ofdm_transceiver_top:  mode[1:0] mux  →  TX / RX / LOOPBACK
                         mod_sel[1:0]   →  QPSK / 16-QAM / 64-QAM / 256-QAM
  Interfaces:  AXI-Stream (32-bit IQ datapath) · AXI-Lite / GPIO (control)
```

- **`ofdm_transceiver_top`** wires both chains and the `mode` mux: in LOOPBACK
  the live TX stream is framed (lead-in 64 + 4032 slot + trailer 64 = 4160)
  and fed straight into the RX input.
- **`ofdm_xcvr_board_top`** is the thin board adapter that exposes `mode`,
  `mod_sel`, `start` and the BER readout over GPIO / AXI-Lite.

---

## 6. Dashboards & docs

Open these HTML files in a browser for the current status at a glance:

| File | What it shows |
|------|---------------|
| `docs/transceiver_block_diagram.html` | full transceiver block diagram (TX→channel→RX, mode/mod mux, interfaces) |
| `rtl_dashboard/rtl_coverage.html`      | RTL module ↔ TB/gate ↔ BER coverage matrix (sim) |
| `fpga_dashboard/fpga_test_coverage.html` | silicon (ZCU216) verification results |
| `current_status.html`                  | overall project status hub |
| `RTL_SYNC_PHASE5/docs/dut_block_diagram.html` | detailed sync-DUT block diagram |

---

*Internal project — not publicly licensed.*
