---
spec_id: 75-core-jq-and-engines
status: DRAFT
closed_as: null
since: 2026-11-19
until: null
epic: hardening
features: [core-jq-equivalents, engine-differences-page]
supersedes: []
superseded_by: null
depends_on: [70-api-response-shapes]
anchors: [05-shapes]
---

# 75 Core jq beside the library, and where engines differ

## Requirements

### Scope

The library should sit beside core jq, not over it: where jq already answers a question well, say so instead of adding a function. A check on 2026-11-19 of the 0.15.0 functions against the usual core-jq idioms, run on jq 1.7.1, gojq 0.12.20 and jaq 3.1.2, found that every one adds something, and found engine differences a user would hit without the library:

| Core idiom | What happened |
|---|---|
| `del(.. \| select(. == null or . == "" ...))` | jq and gojq leave the containers it emptied; jaq removes them |
| `strflocaltime` with `TZ=America/Detroit` | jq 1.7.1 printed 03:00 on the day daylight saving starts as `-0500 EST`; gojq and jaq printed `-0400 EDT` |
| `(.[0] \| keys_unsorted) as $k \| ... @csv` | stops on a nested value; `keys_unsorted` does not exist in gojq |
| `[paths(scalars) as $p \| {(...): getpath($p)}] \| add` | works everywhere, but drops nulls and empty arrays, so it does not round-trip |
| `reduce to_entries[] as $e ({}; setpath(...))` | fails on jaq |

### Requirements

- **R1.** Every public function's README entry names the closest core-jq idiom, if there is one, and what the library adds over it; where the idiom is enough for common use, the entry says so.
- **R2.** A page `docs/engines.md`: every engine difference the test suite works around or found (gojq's key order, jaq's `setpath` and assignment past an array's end, jq 1.7.1's `reduce` inside an argument, the two above), each with the program, each engine's output and the date checked.
- **R2a.** The engine differences reported in the last twelve months, each run against the library's functions on all five engines and either covered by a case or shown not to reach the library: `from_entries` with `Name`/`Value` keys (jaq #478), key order after `del` (jaq #436), `isnan` (gojq #327), `--slurp` (jaq #377), `fromstream` end-of-object markers (jq #3479); and three found while writing the primer: `.a = .b // "none"` (`{"a":null}` on jq 1.7.1 and gojq, `{"a":"none"}` on jaq), `IN` undefined in jaq, `{a: 1} | .[0]` an error on jq and gojq and null on jaq.
- **R3.** A decision, recorded in this spec, on functions whose core idiom covers most uses (first candidates: `flatten_paths`, `unflatten_fields`): keep, with the reason in the README, or remove before the alpha.
- **R4.** The read-out diagram on the shapes page names the 0.15.0 output functions.

## Tasks

- [ ] 1. Core idiom per function (R1), each idiom run on the engines.
- [ ] 2. The engines page (R2) and this year's differences (R2a).
- [ ] 3. Keep-or-remove decisions (R3); the diagram (R4); version.

## Log

- 2026-11-19. Drafted from the owner's ask to make sure the new functions are not already in core jq.
- 2026-11-19. R2a added from the survey of the last twelve months (owner's go-ahead).
