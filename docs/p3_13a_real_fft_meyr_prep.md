# P3-13A Real FFT / Meyr Integer CFO Preparation

**Date:** 2026-05-28  
**Status:** Preparation complete — official validation blocked pending Xilinx FFT IP + xsim

---

## 1. FFT Frontend Audit Result

### `rtl/unit_test/fft256_dual_symbol_frontend.v`

**Classification: Behavioral passthrough stub (direct buffer copy bypass)**

The `S_COMPUTE` state executes a synthesizable for-loop that copies input
time-domain buffers directly into the FFT output buffers:

```verilog
// FFT PLACEHOLDER: copy time-domain buffers to FFT output buffers.
S_COMPUTE: begin
    for (_k = 0; _k < FFT_LEN; _k = _k + 1) begin
        fft_pss_i[_k] <= pss_buf_i[_k];  // <-- no FFT computation
        fft_pss_q[_k] <= pss_buf_q[_k];
        fft_sss_i[_k] <= sss_buf_i[_k];
        fft_sss_q[_k] <= sss_buf_q[_k];
    end
end
```

No frequency transform is performed.  The module is explicitly self-documented
as a placeholder: *"Replace S_COMPUTE with an FFT IP instantiation for production."*

### `rtl/meyr_fft256_actual_integration_top.v`

**Classification: Xilinx FFT IP wrapper (AXI-Stream interface)**

This module instantiates `fft256_xilinx_wrapper` which accepts a
`USE_BEHAVIORAL_STUB` parameter:

- `USE_BEHAVIORAL_STUB = 0` — production mode, requires Xilinx FFT IP
- `USE_BEHAVIORAL_STUB = 1` — passthrough stub (for compile/structural testing)

The module implements a full FSM: buffer PSS → stream to FFT → capture PSS bins
→ buffer SSS → stream to FFT → capture SSS bins → replay to estimator.
This is the correct production path when the Xilinx FFT IP is instantiated.

### Current Production Path in `phase3_sync_top`

The production top uses `meyr_integer_cfo_fft_frontend_top.v`, which
instantiates `fft256_dual_symbol_frontend` (the bypass stub), not
`meyr_fft256_actual_integration_top`. Therefore the current production path
is **stub-only**.

---

## 2. Why the Bypass Cannot Validate k_int ≠ 0

With integer CFO k_int applied to input samples:

```
PSS_received[n] = PSS_ref[n] × exp(j 2π k_int n / N)
SSS_received[n] = SSS_ref[n] × exp(j 2π k_int n / N)
```

The bypass stub outputs these time-domain samples unchanged as "FFT bins".
The estimator then computes a cross-product per sample:

```
term1_bypass[n] = PSS_received[n] × conj(SSS_received[n])
               = PSS_ref[n] × exp(j 2π k_int n / N)
                 × conj(SSS_ref[n]) × exp(-j 2π k_int n / N)
               = PSS_ref[n] × conj(SSS_ref[n])     ← k_int CANCELS
```

The phase rotation from k_int is identical in PSS and SSS and cancels
in the cross-product.  Every value of k_int produces the same correlation
result, so the peak is always at index 255 and int_cfo is always 0 in bypass mode.

**With a real FFT:**

```
PSS_fft[k]   = FFT(PSS_received)[k] = FFT(PSS_ref)[k - k_int]   (circular shift)
SSS_fft[k]   = FFT(SSS_received)[k] = FFT(SSS_ref)[k - k_int]
cross[k]     = PSS_fft[k] × conj(SSS_fft[k])
             = cross_ref[k - k_int]   ← shifted by k_int in frequency
```

Correlating the shifted cross-spectrum with the unshifted reference ROM
produces a peak at lag `k_int` from center:

```
peak_index = 255 + k_int
int_cfo    = k_int
```

---

## 3. New ROM Format and Scaling

### Files

| File | Purpose |
|------|---------|
| `vectors/meyr_pss_fft_romhex.txt` | PSS frequency-domain cross-spectrum ROM |
| `vectors/meyr_sss_fft_romhex.txt` | SSS reference ROM (all +32767, sign=+1) |

### Derivation

```python
PSS_fft = np.fft.fft(pss_td_ref_q15, 256)   # FFT of quantized time-domain PSS
SSS_fft = np.fft.fft(sss_td_ref_q15, 256)   # FFT of quantized time-domain SSS
cross   = PSS_fft * np.conj(SSS_fft)         # per-bin cross-spectrum
ROM[j]  = cross[j]  normalized to Q1.15
```

where `pss_td_ref_q15` / `sss_td_ref_q15` are extracted from the same reference
frame used by `gen_meyr_reference_roms.py`:
- PSS window: `frame[96 : 352]`  (SLOT_START=64 + CP_LEN=32 = 96)
- SSS window: `frame[384 : 640]` (SLOT_START + 2×CP_LEN + NSC = 384)

### Packing (identical to existing bypass ROMs)

```
One 32-bit word per line, 8 hex digits:
  word = {Q[31:16], I[15:0]}   signed Q1.15
```

### Compatibility

| ROM file | Compatible backend | NOT compatible with |
|----------|--------------------|---------------------|
| `meyr_pss_reference_romhex.txt` | bypass stub | real FFT |
| `meyr_pss_fft_romhex.txt` | real FFT (Xilinx IP) | bypass stub |

**The two ROM sets must not be mixed.**

To generate FFT ROMs:
```bash
python3 scripts/gen_meyr_fft_reference_roms.py
```

The script has a safety guard that refuses to overwrite the bypass ROMs.

---

## 4. Harness Adapter Role

`rtl/meyr_fft256_harness_adapter.v` is a purely combinational adapter that
translates the old-style separate-I/Q test interface used by existing Phase3
testbenches into the packed AXI-Stream input expected by
`meyr_fft256_actual_integration_top`.

```
Old-style input:
  s_valid, s_symbol_sel, s_index[7:0], s_i[15:0], s_q[15:0]

AXI-Stream output:
  m_axis_tvalid, m_axis_tdata[31:0] = {Q[31:16], I[15:0]},
  m_axis_tlast (asserted on s_index==255), m_axis_symbol_sel
```

**Purpose:** allows the standalone TB to drive `meyr_fft256_actual_integration_top`
using the same vector loading infrastructure as existing Phase3 tests, without
requiring changes to the test vectors or production RTL.

**Scope:** standalone harness only.  Not instantiated in `phase3_sync_top`.

---

## 5. TB / Runner Usage

### Stub compile check (no Vivado required)

```bash
# Generate FFT ROMs (optional for stub, required for real FFT mode)
python3 scripts/gen_meyr_fft_reference_roms.py

# Compile harness adapter under iverilog
iverilog -g2012 -tnull rtl/meyr_fft256_harness_adapter.v

# Run dry-run script — will report SANITY_GATE: PASS (stub compile only)
bash scripts/run_p3_13a_real_fft_meyr_dryrun.sh
```

Expected dry-run output when Vivado/xsim unavailable:
```
CI_GATE: BLOCKED_REAL_FFT_UNAVAILABLE
  Missing prerequisite(s):
    - Vivado not found
    - xsim not found
    - fft256_xilinx_wrapper.v missing or stub-only

SANITY_GATE: PASS (stub compile only)
  meyr_fft256_harness_adapter.v compiles cleanly under iverilog.
  k_int correctness NOT verified; real FFT + xsim required.
```

### Real FFT validation (Vivado xsim required)

```bash
# Step 1: generate frequency-domain ROMs
python3 scripts/gen_meyr_fft_reference_roms.py

# Step 2: confirm prerequisites are met
bash scripts/run_p3_13a_real_fft_meyr_dryrun.sh
# Expected: READY_FOR_XSIM: all prerequisites met

# Step 3: compile and simulate under xsim
xvlog -sv -f rtl_filelist.f tb/p3_13a_real_fft_meyr_tb.sv \
      -d USE_BEHAVIORAL_STUB=0
xelab -top p3_13a_real_fft_meyr_tb -snapshot p3_13a_snap
xsim p3_13a_snap --runall

# Expected terminal output: OFFICIAL_GATE: PASS — all 9 k_int sweep cases passed
```

The TB loads time-domain PSS/SSS from `golden/p3_09_sweep/case_k*.mem` and
extracts:
- PSS: words [96..351] (256 samples)
- SSS: words [384..639] (256 samples)

It feeds these through the harness adapter into `meyr_fft256_actual_integration_top`,
waits for `done`, and checks `peak_index == 255 + k_int` and `int_cfo == k_int`.

---

## 6. Exact Blockers for Official Validation

| Blocker | Description | Action to unblock |
|---------|-------------|-------------------|
| Vivado | Xilinx IP simulation requires Vivado/xsim | Install Vivado ≥ 2022.2 |
| Xilinx FFT IP | `fft256_xilinx_wrapper.v` must instantiate real IP | Generate IP core in Vivado, export wrapper |
| FFT ROMs | `meyr_pss_fft_romhex.txt` / `meyr_sss_fft_romhex.txt` must be generated | Run `gen_meyr_fft_reference_roms.py` |
| ROM loading | `meyr_term2_ref_rom.v` must use `$readmemh("meyr_pss_fft_romhex.txt")` in real FFT mode | Update ROM file path when switching from bypass to real FFT |

### Non-blocking items (already done)

- [x] FFT frontend audit documented
- [x] Frequency-domain ROM generator created
- [x] Harness adapter created
- [x] Standalone TB created with dual stub/real-FFT modes
- [x] Dry-run script created with accurate gate reporting
- [x] Existing bypass ROMs protected (not overwritten)
- [x] Production top files not modified

---

## 7. File Inventory

| File | Role |
|------|------|
| `scripts/gen_meyr_fft_reference_roms.py` | Generates FFT-domain ROMs |
| `vectors/meyr_pss_fft_romhex.txt` | PSS FFT ROM (created by above script) |
| `vectors/meyr_sss_fft_romhex.txt` | SSS FFT ROM (all +1, created by above script) |
| `rtl/meyr_fft256_harness_adapter.v` | Old-style → AXI-Stream adapter (standalone) |
| `tb/p3_13a_real_fft_meyr_tb.sv` | Standalone TB (stub + real FFT modes) |
| `scripts/run_p3_13a_real_fft_meyr_dryrun.sh` | Prerequisite gate checker |
| `golden/meyr_fft_reference_debug.json` | ROM generation debug metadata |

### Protected files (not modified)

- `vectors/meyr_pss_reference_romhex.txt` — bypass-compatible PSS ROM
- `vectors/meyr_sss_reference_romhex.txt` — bypass-compatible SSS ROM
- `rtl/phase3_sync_top.v`
- `rtl/fft256_dual_symbol_frontend.v`
- `rtl/meyr_integer_cfo_fft_frontend_top.v`
