# RF Integration Plan — Internal DAC→SMA→ADC OFDM Loopback (ZCU216)

Scope: design only. Option B (build a new OFDM DAC-TX block). Sample rate LOCKED = **153.6 Msps**.

## 0. Baseline (cited)
- DUT: 32-bit packed IQ [31:16]=Q [15:0]=I, 1 samp/beat, pl_clk0 (timing-closed 187.5; RF uses 153.6). slot=4032. THRESHOLD override=40000 (digital_loopback_bd.tcl:200).
- RFDC 08 (hardware/generated/08_rfdc_capture/.../system.bd): ADC tile2/blk0 2.4576 GSPS REAL decim=1 mixer=1 width=8, m20_axis@clk_adc2=307.2; DAC tile3/blk2 6.88128 GSPS interp=1 mode=3(real) width=16, vout32/s32_axis@clk_dac3=430.08. CLK104 refclk 245.76 (main.c:639-652).
- DAC scaffold: zcu216_dac_tone_axis.v (256-bit s32_axis, 16 sub-samp/beat, SQUARE wave — replace).

## 1. SAMPLE-RATE PLAN (locked 153.6)
- ADC 2.4576 GSPS / **16** = 153.6 Msps complex (DDC decim ×16, supported). Exact integer → RX path exact.
- **pl_clk0 = 153.6 MHz** (DUT+capture+RX gearbox). DIVISOR0≈10 (vs current 8→187.5, run_10:48). Below 187.5 closure → timing easy.
- DAC analog 6.88128 G is NOT an integer multiple of 153.6 (ratio 2.8× vs ADC) → cross-converter mismatch absorbed as residual SRO/CFO by the DUT estimator (NOT forced integer).
- IF ≈ 300 MHz (1st Nyquist, inside XM655 balun 10MHz–1GHz). RX fine-mixer NCO at −IF. **TX has the IF baked into the pre-computed samples (DAC Interp=1, no DUC).**

## 2. TX — pre-computed full-rate BRAM player (eliminates the resampler — chosen approach)
**The OFDM waveform is computed OFFLINE at the DAC full rate (6.88128 GSPS) with the IF + upsampling already baked in, stored in BRAM, and streamed straight out the DAC at Interp=1 — exactly like `zcu216_dac_tone_axis.v` but reading samples from BRAM instead of generating a square wave.** This moves the non-integer 44.8× resampling to offline floating-point Python (exact, free), removing the #1-risk PL polyphase resampler AND the DAC DUC.

### Offline generator: `scripts/gen_ofdm_dac_waveform.py` (new)
Input: the OFDM slot IQ at 153.6 Msps (reuse fc_kp0 / a clean OFDM slot, 4160 words). Steps:
1. Polyphase/FFT resample 153.6 Msps complex → 6.88128 GSPS complex (ratio 44.8, high-quality LPF).
2. Mix to IF: multiply by exp(j·2π·300MHz·t) at 6.88128 GSPS.
3. Take real part → real passband at IF (DAC real mode 3).
4. Quantize to 16-bit (scale headroom so ADC peaks land near the THRESHOLD regime; tunable amp).
5. Pack 16 samples/beat (256-bit) matching `zcu216_dac_tone_axis.v:27-32` newest-last layout → $writememh hex.
Size: 4160×44.8 ≈ **186 368 samples = 11 648 beats × 256-bit ≈ 3.0 Mbit** (BRAM/URAM; xczu49dr has ~60 Mb total — fine). Loop the slot for continuous TX.

### TX RTL: `ofdm_dac_rom` (clone of `zcu216_dac_tone_axis.v`)
- Replace the square-wave gen (`:24`) with a BRAM read (256-bit/beat) + free-running address with wrap (loop). Keep the exact `s32_axis` 256-bit @ clk_dac3=430.08 packing/handshake.
- `$readmemh` the generated hex at synth (or GPIO-load like dut_player). `amp`/enable ctrl like the tone block (`:16-17`).
- **No PL resampler, no DAC DUC, no TX CDC needed beyond the BRAM running on clk_dac3.** DAC: Interp=1, mode 3 (real), unchanged from 08.

### Trade-offs (accepted)
- ~3 Mbit BRAM/URAM (fine). Fixed waveform (regenerate+reload to change — OK for test). Loop seam: OFDM CP is quasi-cyclic; a 1-slot seam is tolerable or insert a guard gap.

## 3. RX — ADC → DDC → CDC → gearbox → DUT
1. RFDC ADC reconfig: blk20 fine mixer (ADC_Mixer_Type20=2), NCO=−IF, **Decimation=16** → complex 153.6.
2. CDC FIFO clk_adc2-derived → pl_clk0 (axis_data_fifo dual-clock; absorbs phase+SRO).
3. RX gearbox → 32-bit packed [31:16]=Q[15:0]=I; deserialize to 1 samp/beat; scale 16-bit ADC to DUT fixed-point (peaks near THRESHOLD regime).
4. → DUT s_axis (tready honored end-to-end).

## 4. CAPTURE
- DUT m_axis → existing dut_capture.v UNCHANGED (BRAM, GPIO readback, circular ctrl[16]).
- **S2MM DMA NOT needed** (in-fabric consume + BRAM readback, like digital loopback).
- Optional raw-ADC tap (zcu216_adc_capture 128-bit) for bringup step 6b only.

## 5. COMBINED BD + BUILD
New project 11_rf_loopback seeded from 08 (RFDC+CLK104+clocks), graft DUT subsystem from 10.
- Reconfig RFDC (§1-3); set pl_clk0=153.6 (PSU__CRL_APB__PL0_REF_CTRL).
- Add DUT IP (user:user:phase3_sync_axis_dma_wrapper:1.0) THRESHOLD=40000 (retune §6c).
- TX: ofdm_dac_rom (pre-computed BRAM, runs on clk_dac3) → s32_axis directly (no TX CDC, no DUC, Interp=1).  RX: m20_axis → CDC(clk_adc2→pl_clk0) → gearbox → DUT.
- 3 clock domains: clk_adc2, pl_clk0=153.6, clk_dac3=430.08. ONE CDC FIFO (RX only).
- Keep SW-locked GPIO/lite addrs (loop 0xA0050000, stim 0xA0090000, status 0xA0060000, cap 0xA0080000, DUT-lite 0xA00A0000).
- build_rf_loopback.tcl (clone build_digital_loopback). run_11 (clone run_10) + RFDC/CLK104 init (un-#define RUN_DIGITAL_LOOPBACK path), mwr 0xFF5E00C0 for 153.6 (DIVISOR0=10).

## 6. BRINGUP ORDER (smallest derisk first)
- **a.** DAC tone (unmodified) → raw ADC capture: confirm clocking/CLK104/PLL in new project.
- **b. ★ FIRST PROTOTYPE:** gen_ofdm_dac_waveform.py → ofdm_dac_rom (BRAM) → DAC(Interp=1) → SMA → ADC(decim=1) → zcu216_adc_capture → offline FFT (scripts/fft_capture.py). Validates the offline waveform + BRAM player + balun + analog loop, NO resampler/DDC/DUT. Reuses 100% proven 08 path. (Easiest possible first step — TX is just dac_tone with BRAM samples.)
- **c.** Enable ADC DDC(×16 IQ) + RX gearbox → DUT; measure ADC peak; retune THRESHOLD ~(ADC_peak/stim_peak)².
- **d.** Verify sync: frame_start/peak/int_cfo over GPIO + captured slot vs fc_kp0 golden.
- **e.** Absorb 1.3838 DAC:ADC analog mismatch (residual CFO+SRO); ensure frac-CFO+frame tracker lock; fallback = common PLL dist (DAC3_Clock_Source shares dist).

## 7. RISKS (ranked) — TX resampler risk ELIMINATED by pre-computed BRAM (§2)
1. **RFDC DDC reconfig changes AXIS width/clock** — enabling ADC IQ-mixer+decim16 alters m20_axis samp/beat + Outclk; reconfig in throwaway BD, read back actual bus before RX gearbox RTL.
2. **SRO/CFO from 2.8× analog mismatch** — DAC 6.88128G vs ADC 2.4576G + independent PLLs → residual CFO+SRO across the slot; DUT frac-CFO/frame tracker must absorb. Fallback: common PLL dist (DAC3_Clock_Source shares dist). Highest-uncertainty item.
3. **Offline waveform fidelity + loop seam** — Python resample quality (use FFT/polyphase LPF); slot-loop seam continuity (CP quasi-cyclic, or guard gap). Low risk, fully offline-tunable.
4. **RX CDC (clk_adc2→pl_clk0)** — use Xilinx axis_data_fifo dual-clock (proven). Only ONE CDC now (TX BRAM runs on clk_dac3, no TX CDC).
5. **THRESHOLD/fixed-point scaling** — set DAC amp + DUT THRESHOLD from measured ADC level (§6c); runtime-tunable.
6. **BRAM/URAM budget** — ~3 Mbit for the full-rate slot; fits xczu49dr but place in URAM to spare BRAM.

## Reuse (file refs)
dut_player.v (TX source verbatim) · zcu216_dac_tone_axis.v (DAC pack template) · digital_loopback_bd.tcl (DUT+capture+GPIO graft) · 08 system.bd (RFDC seed) · main.c (RFDC/CLK104 init + GPIO control for run_11).
