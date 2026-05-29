# Claude Code Prompt — Session B / P3-13C Real FFT IP Official xsim Closure

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Mandatory Archival Rule
Before making any code change, save this prompt verbatim to:

`md_files/session_B_p3_13c_real_fft_ip_official_xsim_prompt.md`

Create `md_files/` if it does not exist.

---

# Session Naming

This is **Claude Session B**.

Session B owns:

```text
Real FFT path
Meyr integer CFO estimator
FFT-domain ROMs
integer CFO sweep
Vivado/xsim official closure
```

---

# Current Known Status

P3-13B completed behavioral DFT validation.

Protected files untouched:

```text
phase3_sync_top.v
frame_detector.v
frac_cfo_frame_corrector_top.v
phase3_axi_lite_regs.v
phase3_sync_axis_dma_wrapper.v
bypass ROMs
```

Behavioral DFT sweep result:

```text
k_int = 0, ±1, ±2, ±4, ±8
all 9 cases PASS under iverilog / USE_BEHAVIORAL_STUB=3
```

Confirmed convention:

```text
natural order
peak_index = 255 + k_int
int_cfo = peak_index - 255
no sign inversion
```

Current status:

```text
SANITY_GATE: PASS (behavioral DFT, iverilog)
OFFICIAL_GATE: FAIL/BLOCKED because Vivado/xsim and real Xilinx FFT IP are unavailable on host
```

Known FFT IP target:

```text
fft256_xilinx_wrapper.v production branch
USE_BEHAVIORAL_STUB=0
xfft_v9_1_8
256-pt
pipelined streaming
natural-order output
SCALE_SCH=0xAA
FWD_INV=1
config word 16'h0155
```

---

# Objective

Obtain official xsim closure for the real FFT Meyr path using actual Xilinx FFT IP.

The goal is to transition from:

```text
SANITY_GATE: PASS using behavioral DFT
```

to:

```text
OFFICIAL_GATE: PASS using xsim + Xilinx FFT IP
```

---

# Allowed Modifications

You may create/modify:

```text
scripts/create_fft256_xilinx_ip.tcl
scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh
docs/session_B_p3_13c_real_fft_ip_xsim.md
md_files/session_B_p3_13c_real_fft_ip_official_xsim_prompt.md
```

You may minimally modify:

```text
rtl/fft256_xilinx_wrapper.v
tb/p3_13a_real_fft_meyr_tb.sv
scripts/run_p3_13b_real_fft_xsim.sh
```

only if required to correctly bind/generated IP.

---

# Do NOT Modify

Do not modify:

```text
rtl/phase3_sync_top.v
rtl/frame_detector.v
rtl/frac_cfo_frame_corrector_top.v
rtl/phase3_axi_lite_regs.v
rtl/phase3_sync_axis_dma_wrapper.v
rtl/meyr_integer_cfo_freq_estimator_top.v
vectors/* bypass ROMs
```

Do not change the already-passing behavioral DFT logic except to keep it working.

---

# Tasks

## 1. Create Vivado FFT IP generation TCL

Create:

```text
scripts/create_fft256_xilinx_ip.tcl
```

It must generate project-local Xilinx FFT IP for simulation.

Target:

```text
xfft_v9_1_8 or Vivado-compatible xfft version
256-point FFT
natural order output
forward transform
pipelined streaming if available
SCALE_SCH=0xAA or documented equivalent
```

Output location should be project-local, e.g.:

```text
ip/fft256_xilinx/
```

Do not rely on global project state.

## 2. Verify wrapper binding

Confirm:

```text
rtl/fft256_xilinx_wrapper.v
```

instantiates the generated IP module name correctly.

If Vivado generates a different module name, adapt only the wrapper or TCL consistently.

## 3. Create official xsim runner

Create:

```text
scripts/run_session_B_p3_13c_real_fft_ip_xsim.sh
```

It should:

```text
source Vivado settings if available
check xsim availability
check IP collateral exists
compile with xvlog
elaborate with xelab
run with xsim
parse log using anchored grep
```

Gate output:

```text
OFFICIAL_GATE: PASS
OFFICIAL_GATE: FAIL
OFFICIAL_GATE: BLOCKED_XSIM_UNAVAILABLE
OFFICIAL_GATE: BLOCKED_FFT_IP_MISSING
```

Never print OFFICIAL PASS from behavioral DFT fallback.

## 4. Run 9-case k_int sweep under real IP

Required cases:

```text
0, +1, -1, +2, -2, +4, -4, +8, -8
```

Expected:

```text
peak_index = 255 + k_int
int_cfo = k_int
```

Document amplitude/score differences due to Xilinx scaling.

## 5. Preserve behavioral DFT fallback

Ensure existing fallback still works:

```text
USE_BEHAVIORAL_STUB=3
SANITY_GATE: PASS
```

Do not let fallback produce official PASS.

## 6. Documentation

Create:

```text
docs/session_B_p3_13c_real_fft_ip_xsim.md
```

Include:

```text
Vivado version
IP generation command
FFT IP configuration
xsim command
sweep result table
scale schedule impact
remaining risks
```

---

# Pass Criteria

Complete if:

```text
1. IP generation TCL exists
2. official xsim runner exists
3. wrapper binding verified
4. 9-case real IP sweep runs or blocker is clearly reported
5. docs exist
6. behavioral DFT fallback remains passing
```

Official closure only if:

```text
OFFICIAL_GATE: PASS
```

from real Xilinx IP + xsim.

---

# Final Response Format

Return:

```text
Session B / P3-13C Final Status

1. Changed Files
2. FFT IP Generation Result
3. Wrapper Binding Result
4. Real IP k_int Sweep Result
5. Gate Result
6. Behavioral DFT Fallback Status
7. Remaining Risks
8. Recommended Next Step
```
