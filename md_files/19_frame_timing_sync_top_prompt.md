# Step 19 — Implement and Verify `frame_timing_sync_top.v`

You are working inside:

`/home/zealatan/RTL_SYNC`

## Goal

Implement and verify `frame_timing_sync_top.v`, the integrated frame capture, frame detection, CP timing synchronization, and fractional CFO estimation block.

This module integrates:

- `iq_frame_buffer.v`
- `frame_detector.v`
- `timing_frac_cfo_top.v`

It corresponds to this C reference flow inside `synchronization()`:

```c
indexFrame = frame_detector(...);

peakIndexAuto = VanDeBeekAutoCorrelation(...);

fracfreqOffset = -atan2(autoCorrOutQ[peakIndexAuto],
                        autoCorrOutI[peakIndexAuto]) / (2 * PI);
```
