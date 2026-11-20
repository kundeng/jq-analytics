---
spec_id: 68-design-with-the-code
status: CLOSED
closed_as: SHIPPED
since: 2026-11-20
until: null
epic: teaching
features: [family-design-sections, conventions-anchor, background-anchor]
supersedes: []
superseded_by: null
depends_on: [67-learning-from-the-questions]
anchors: [05-shapes, 10-conventions]
---

# 68 Each family's design beside its code

## Requirements

### Scope

The design of the library lived in three places. One numbered design document in the repository (`docs/design/05-shapes.md`); five hand-written review pages outside it (joins and intervals; state, events, trees and graphs; measures, calendar and DAX; using it; background), which drifted (they still described 0.13.1 on 2026-11-19); and the read-out notes, which carry much of each family's design because there was nowhere else for it (the windows notes explain partitions, order, ties and the SQL equivalent). The owner, reviewing (2026-11-19): the design and the code read-out are closely connected, and the windows read-out holds a lot of design.

### Requirements

- **R1. One page per family, design first.** Each read-out page opens with a "Design" section, then "The functions" (the table and the definitions as now). The design section says: what the family is for and the question it answers; the shape it takes; the rules it keeps (nulls, ties, order, what it refuses); the closest core jq, SQL and pandas, and what the family adds; the decisions that shaped it, with their dates. Its source is the family's notes file in `docs/readout/notes/`, so it is built and checked with the code.
- **R2. Cross-cutting design stays in `docs/design/`**, numbered: `05-shapes.md` (the shapes and sources, as now); `10-conventions.md` (one value in, the null rule, errors and input checks, naming, what each function's arguments mean, engines and the hand-off); `15-background.md` (why the library exists, its purposes, the review that shaped it, the decisions that span families).
- **R3. Nothing is lost.** Every statement of the five review pages lands in a family's design section or in one of the three documents, or is dropped with a reason in this spec's log (out of date, or repeated).
- **R4.** The read-out build fails on a family whose design section lacks one of the parts of R1.

## Tasks

- [x] 1. `readout.py`: the "Design" and "The functions" headings; the check of R4.
- [x] 2. `10-conventions.md` and `15-background.md` from the "Using it" and "Background" review pages and the README's rules.
- [x] 3. Each family's design section, from its notes intro and the review pages.
- [x] 4. Build, check, version.

## Log

- 2026-11-20. Opened at the owner's word ("Yes, as sprint 68").
- 2026-11-20. Shipped as 0.15.2 (docs and tools only). `readout.py` gives each page "## Design" and "## The functions" and refuses a design section without its four parts; `10-conventions.md` and `15-background.md` written (the conventions with new measurements: `IN` against `join_semi`, reading fewer fields, folding while reading); 19 design sections written, the families' SQL and pandas comparisons run on DuckDB 2.0.0 and pandas 3.1.1, every core-jq idiom run on jq 1.7.1, gojq and jaq. Dropped from the five review pages, with reasons: counts and function lists out of date (101 functions, 18 families, the table as of 0.10.0); text that is not about one family ("What it is", the parts diagram, the list of pages: now in `15-background.md` and the README); notes about engines and page pointers; examples that repeat the definition notes (composite-key, range, anti and nest joins; the sessions and retention examples); retention costs measured before 0.9.0 (superseded by 18.6 s to 1.3 s); the working rule that an unanswered proposal counts as yes (how the project was run, not design). Engine differences found on the way go to spec 75.
