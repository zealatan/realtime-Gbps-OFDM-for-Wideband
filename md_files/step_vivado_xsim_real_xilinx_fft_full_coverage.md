# Step: Vivado xsim Real Xilinx FFT IP Full Coverage

## Mandatory archive — saved 2026-06-03

From now on, Vivado xsim with the real Xilinx FFT IP simulation model is the authoritative simulator
for any RTL path that includes Xilinx FFT IP.

The existing iverilog + USE_BEHAVIORAL_STUB=3 flow is allowed only as a fast pre-check.
It must NOT be used as final verification for:

- fft256_xilinx_wrapper
- fft256_dual_symbol_frontend
- PSS/SSS FFT path
- Meyr integer CFO path
- full synchronizer path after PSS/SSS extraction

Do NOT mark any FFT/Meyr/Xilinx-IP-dependent gate as final PASS unless Vivado xsim with the real
Xilinx FFT IP model has run and passed.

---

## Environment architecture

**WSL workspace:** `/home/zealatan/RTL_SYNC_PHASE4`
Used for: RTL source editing, testbench generation, Python checkers, iverilog pre-checks,
documentation, HTML reports, Git/status tracking.

**Windows workspace:** Vivado / Vitis / XSCT / xsim / Hardware Manager are installed on Windows,
not WSL. Never assume Vivado is installed in WSL.

---

## Goal

Create a high-coverage Vivado/xsim verification flow using the real Xilinx FFT IP, verifying:

- Real Xilinx FFT IP integration
- AXI-Stream tvalid/tready/tlast protocol
- FFT scaling, output bin ordering, sign convention
- event_tlast_unexpected, event_tlast_missing, event_fft_overflow
- Backpressure behavior, reset behavior
- PSS/SSS dual-symbol FFT sequencing
- Meyr integer CFO behavior with real FFT output
- Full synchronizer path up to integer CFO decision

---

## Directory structure

    /home/zealatan/RTL_SYNC_PHASE4/vivado_xsim/
      config/
      tcl/
      windows/
      tb/
      scripts/
      vectors/
      logs/
      reports/
      xsim_work/
      README.md

---

## Target part / board

- Part: `xczu9eg-ffvb1156-2-e`
- Board: ZCU102

---

## Gate labels

- `PASS_VIVADO_XSIM_REAL_IP` — xsim with real Xilinx FFT IP ran and passed
- `PASS_BEHAVIORAL_ONLY` — only iverilog + behavioral stub has passed (not final)
- `FAIL_VALUE_MISMATCH` — xsim ran but bin values do not match
- `FAIL_PROTOCOL` — TLAST/tready/event protocol failed
- `BLOCKED_XCI_NOT_FOUND` — no .xci and cannot generate IP
- `BLOCKED_WINDOWS_VIVADO_REQUIRED` — WSL cannot run Vivado

---

## Safety rules

- Do not remove iverilog tests or behavioral stub
- Do not mark behavioral results as final
- Do not modify stable RTL unless real xsim reveals a confirmed bug
- Do not overwrite existing IP without backup
- Generated FFT IP goes under `vivado_xsim/ip_generated/`, never overwriting project IP
- Preserve all logs; every PASS must have a corresponding log/report
