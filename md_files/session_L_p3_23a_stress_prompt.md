# Claude Code Prompt — Session L / P3-23A Multi-Frame and Reset Stress

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Objective
Verify long-run stability.

---

### L1. Multi-Frame

Run:

```text
10 frames
50 frames
100 frames
```

back-to-back.

Verify:

```text
no deadlock
correct TLAST count
correct output count
```

---

### L2. Soft Reset During Input

Assert reset:

```text
during frame acquisition
```

Verify recovery.

---

### L3. Soft Reset During Replay

Assert reset:

```text
during replay correction
```

Verify recovery.

---

### L4. Enable Toggle

Randomly toggle:

```text
enable
start
```

Verify:

```text
no lockup
clean restart
```

---

### Gate

```text
STRESS_GATE: PASS
STRESS_GATE: FAIL
```
