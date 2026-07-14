#!/usr/bin/env python3
"""
gen_p5_random_sweep.py — B3 P5-RANDOM infrastructure (DEFERRED).

Generates a seed-based pseudo-random sweep of (k_int, frac_cfo, SNR)
scenarios beyond the deterministic ±8 sweep. Each scenario emits a
golden stimulus + manifest entry; the next-session runner is expected
to drive P5-EQUIV through every scenario and accumulate a P5-RANDOM
gate (100+ cases bit-exact).

This script writes the manifest only. The full N-case sweep + TB
extension + cache-aware gate wrapper is the next-session work.

Output: vectors/p5_random/manifest.json
"""
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
OUT_DIR = os.path.join(ROOT, "vectors", "p5_random")
os.makedirs(OUT_DIR, exist_ok=True)


def main():
    seed = int(os.environ.get("P5_RANDOM_SEED", "0xDEC0DE"), 16)
    n_cases = int(os.environ.get("P5_RANDOM_N", "100"))
    rng = random.Random(seed)

    manifest = {
        "generator": "scripts/gen_p5_random_sweep.py",
        "seed": seed,
        "n_cases": n_cases,
        "status": ("INFRASTRUCTURE_READY — manifest written; the actual "
                    "stimulus + TB iteration is deferred to the next "
                    "session. See docs/p5_08_p2_status.md."),
        "cases": [],
    }
    for i in range(n_cases):
        # Cover k_int well outside the ±8 sweep + random fractional CFO
        k_int = rng.randint(-32, 32)
        frac  = rng.uniform(-0.49, 0.49)
        snr_db = rng.choice([None, 30, 20, 10])
        manifest["cases"].append({
            "id":     f"r{i:03d}",
            "k_int":  k_int,
            "frac":   round(frac, 4),
            "snr_db": snr_db,
        })

    out = os.path.join(OUT_DIR, "manifest.json")
    with open(out, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")
    print(f"[p5_random] wrote {out} ({n_cases} planned cases)")


if __name__ == "__main__":
    main()
