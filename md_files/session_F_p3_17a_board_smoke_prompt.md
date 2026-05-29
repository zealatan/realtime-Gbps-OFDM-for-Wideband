# Claude Code Prompt — Session F / P3-17A Board/Vitis Smoke Revalidation

## Working Directory
`/home/zealatan/RTL_SYNC_PHASE3`

## Objective
Revalidate board/Vitis integration using the existing Phase2 shell.

Required smoke checks:
- VERSION readable
- CONTROL writable
- STATUS readable
- INPUT_COUNT increments
- OUTPUT_COUNT increments
- INT_CFO_VALID observable
- TLAST_COUNT increments

DMA checks:
- DMA starts
- DMA completes
- output buffer nonzero
- TLAST observed

Create:
- vitis/session_F_p3_17a_phase3_smoke.c
- scripts/windows/run_session_F_p3_17a_phase3_smoke.bat
- docs/session_F_p3_17a_board_smoke.md
