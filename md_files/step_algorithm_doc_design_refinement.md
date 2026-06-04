# Task Prompt Archive: Algorithm Reference Document Design Refinement

**Saved:** 2026-06-02  
**Target document:** `docs/algorithm_reference_spec.html`

---

## Task

Refine and upgrade the visual design of:

`/home/zealatan/RTL_SYNC_PHASE4/docs/algorithm_reference_spec.html`

using the Coolors palette:  
`https://coolors.co/palette/001219-005f73-0a9396-94d2bd-e9d8a6-ee9b00-ca6702-bb3e03-ae2012-9b2226`

## Palette

| Color | Hex | Usage |
|-------|-----|-------|
| Dark Navy | #001219 | Page background |
| Dark Teal | #005F73 | Main panels/cards |
| Medium Teal | #0A9396 | Secondary headings |
| Light Teal/Mint | #94D2BD | Primary headings, PASS badges |
| Warm Cream | #E9D8A6 | Code text, equation text |
| Amber/Gold | #EE9B00 | Highlight, accent, callout borders |
| Orange | #CA6702 | Warnings |
| Dark Orange-Red | #BB3E03 | Severe warnings |
| Red | #AE2012 | Failure/critical |
| Dark Red | #9B2226 | Critical severity |

## Execution rules

- Do NOT ask yes/no questions
- Do NOT pause for confirmation
- Continue until concrete result produced
- Do NOT modify RTL or testbench files

## Archive rule

Save this prompt as: `md_files/step_algorithm_doc_design_refinement.md`

## Design requirements

1. Refined dark engineering dashboard style
2. No childish bright colors
3. Subtle gradients only
4. Rounded cards, consistent spacing
5. Improved table readability
6. Stage cards/timeline blocks for sync flow
7. Clean PASS/WARN/FAIL/OPEN/BLOCKED badges
8. Sticky/clear table of contents (HTML/CSS only)
9. No external CDN
10. No JavaScript unless pre-existing
11. Self-contained document
12. Preserve ALL technical content

## Additional content requirements

- Hero section: title, project root, C reference root, milestone, open blockers, date, scope
- Visual pipeline diagram (pure HTML/CSS)
- Stage mapping table with Risk column
- Verification readiness section (Ready/Partially verified/Blocked/Needs deeper equivalence)

## Functional sections to preserve

1. Project purpose
2. End-to-end synchronization flow
3. C reference function inventory
4. Algorithm stage breakdown
5. Mathematical formulation
6. Reference vs RTL implementation differences
7. Fixed-point and streaming constraints
8. Verification gate mapping
9. Known open functional risks
10. RTL functionality verification checklist
11. Recommended next verification steps

## Known project status (to use for status blocks)

**PASS:** P3-12B/C, P3-13E, P3-14B, P3-14C, P3-15A, P3-15C, P3-20A, P3-22A, P3-23A  
**FAIL:** P3-15D (85/100), P3-16A (SSS deadlock)  
**ISSUE-001:** complex_mult_iq backpressure violation  
**ISSUE-002:** P3-15D 15/100 D2 metadata failures
