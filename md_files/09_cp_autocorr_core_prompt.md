# Step 9 — Implement and Verify `cp_autocorr_core.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `cp_autocorr_core.v`, the RTL replacement for the CP auto-correlation part of the C reference function:

`VanDeBeekAutoCorrelation()`

More specifically, this module replaces the C `auto_corr()` computation used inside `VanDeBeekAutoCorrelation()`.

This module computes:

```text
P[n] = sum_{k=0}^{CP_LEN-1} r[n+k] * conj(r[n+k+NSC])
```

[Prompt saved — remainder of user message was cut off at this point]
