# Step 33 — Real mU/goldU Reference Audit

## Objective

Determine whether real mU and goldU sequences exist anywhere in this repository,
answer the 11 audit questions, and document the ROM status clearly.

**Conclusion: Outcome C — Real data unavailable.**

---

## Repository Audit

### Files examined

```
ref/receiver.c          — only C source in ref/
sw/                     — platform headers (no mU/goldU sequences)
rtl/                    — RTL only
tb/                     — testbenches only
scripts/                — shell and Python scripts only
```

Commands run:

```bash
find /home/zealatan/RTL_SYNC -maxdepth 4 -type f | sort \
  | grep -Ei "\.(c|h|csv|json|mat|bin|npy|txt|dat)$"

grep -n "CP_LEN\|NSC\|mUI\|goldUI\|mUQ\|goldUQ\|mU_i\|goldU_i" \
  /home/zealatan/RTL_SYNC/ref/receiver.c

find /home/zealatan/RTL_SYNC -name "pluto.h"
```

**Key findings**:

- Only `ref/receiver.c` is present under `ref/`. No header files, no data files.
- `pluto.h` (which defines NSC, CP_LEN, and the `signal_process_t` struct) is **not present** in the repository.
- `mUI`, `mUQ`, `goldUI`, `goldUQ` appear in `receiver.c` exclusively as struct member accesses (`signal_process->mUI`) and function parameters — they are provided by the calling application and are not generated in `receiver.c`.
- No `.csv`, `.json`, `.mat`, `.bin`, `.npy`, or `.dat` files containing mU/goldU sequences exist anywhere in the repository.

---

## Audit Questions

### Q1 — Where are mU and goldU originally defined?

They are fields of the `signal_process_t` struct, declared in `pluto.h`.
That header is external to this repository and belongs to the transmitter
application.  Their concrete values depend on the waveform parameters
(e.g. subcarrier spacing, ZC-root index, sample rate) set by the transmitter.

### Q2 — What type are they? (float / fixed-point / integer?)

In `ref/receiver.c` they are accessed via `float*` pointers (the struct
fields are floating-point arrays).  Scaling relative to the FPGA fixed-point
representation is not specified in the available source.

### Q3 — What is the expected array length?

At minimum `NSC + CP_LEN = 256 + 32 = 288` elements per I and Q component.
The formula `mUI[j + CP_LEN]` for `j = 0 … NSC−1` reads indices 32–287.

### Q4 — What is CP_LEN?

`CP_LEN = 32`, established from Step 2 documentation sourced from `pluto.h`.

### Q5 — What is NSC?

`NSC = 256`, established from Step 2 documentation sourced from `pluto.h`.

### Q6 — What does the j + CP_LEN offset mean?

It skips the cyclic prefix (first 32 samples) and indexes into the
frequency-domain useful symbol portion of the time-domain PSS/SSS waveform.
The correlation is performed over the NSC = 256 data-bearing subcarriers.

### Q7 — Is `mU` the same as the transmitted PSS sequence?

Based on the naming convention and its usage in `carrierFreqOffsetEstMeyr()`,
`mU` is the reference time-domain PSS waveform (or its frequency-domain
equivalent post-CP strip), and `goldU` is the corresponding SSS or Gold-code
reference.  Exact generation algorithm requires the transmitter source.

### Q8 — Is `goldU` a Gold code or a Zadoff-Chu sequence?

The name suggests a Gold-code sequence (consistent with SSS in LTE/NR-style
waveforms), but the exact root/index/polynomial is not determinable without the
transmitter source.

### Q9 — Can term2 be computed without the transmitter source?

No.  Both mU and goldU must be extracted from the transmitter application
before term2 can be computed.

### Q10 — What would be needed to produce a real ROM?

1. Access to the transmitter source or a captured `pluto.h` defining the sequences.
2. Extract `mU_i[j + CP_LEN]`, `mU_q[j + CP_LEN]`, `goldU_i[j + CP_LEN]`,
   `goldU_q[j + CP_LEN]` for `j = 0 … 255`.
3. Run `scripts/generate_meyr_term2_rom.py --input-json data/mu_goldu.json`.
4. Set `USE_SYNTHETIC_FALLBACK=0` in `rtl/meyr_term2_ref_rom.v` and point
   `$readmemh` to the generated file.

### Q11 — What is the impact of using the synthetic fallback?

The Step 31 and Step 32 verified simulation results remain valid.  The
estimator correctly recovers integer CFO shifts using the internally
consistent PRNG term2 ROM.  End-to-end FPGA accuracy against real received
signals will require the real term2 ROM once mU/goldU data is available.

---

## Outcome

**Outcome C — Real data unavailable.**

| Item | Status |
|------|--------|
| `mU` / `goldU` in repository | Not present |
| `pluto.h` in repository | Not present |
| term2 ROM (real) | **Pending** |
| term2 ROM (synthetic PRNG fallback) | Implemented and verified in Steps 31–32 |
| `scripts/generate_meyr_term2_rom.py` | Template ready; accepts real data when available |

---

## Real term2 ROM Integration Path (Step 33+)

When the transmitter sequences become available:

```bash
# 1. Prepare input JSON
cat > data/mu_goldu.json << 'EOF'
{
  "cp_len": 32,
  "nsc": 256,
  "mu_i":    [ ... ],
  "mu_q":    [ ... ],
  "goldu_i": [ ... ],
  "goldu_q": [ ... ]
}
EOF

# 2. Generate ROM file
python3 scripts/generate_meyr_term2_rom.py \
    --input-json data/mu_goldu.json \
    --scale 1.0 \
    --output rtl/term2_rom_init.mem

# 3. Update meyr_term2_ref_rom.v
#    Set USE_SYNTHETIC_FALLBACK=0
#    Replace generate block with: $readmemh("term2_rom_init.mem", rom);

# 4. Re-run Step 32 simulation suite to confirm no regression
bash scripts/run_meyr_integer_cfo_freq_estimator_top_sim.sh
```

---

## Related Files

| File | Purpose |
|------|---------|
| `ref/receiver.c` | C reference — uses mU/goldU as external parameters |
| `rtl/meyr_term2_ref_rom.v` | Synthesisable ROM — synthetic fallback active |
| `rtl/meyr_integer_cfo_core.v` | Step 31 core — uses identical PRNG internally |
| `scripts/generate_meyr_term2_rom.py` | Template generator for real mU/goldU |
| `docs/step32_meyr_product_generator_real_term2.md` | Step 32 architecture |

---

## Simulation Regression

No RTL changes were made in Step 33.  Step 32 simulations remain valid.

```
meyr_pss_sss_product_gen_tb:
  PASS: 13   FAIL: 0   CI GATE: PASSED

meyr_integer_cfo_freq_estimator_top_tb:
  PASS: 32   FAIL: 0   CI GATE: PASSED
```
