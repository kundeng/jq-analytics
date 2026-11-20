# What people ask about jq, and what this library does for it

Two read-only surveys, both run on 2026-11-19 by an AI agent and checked against the raw pulls: one of the questions people have asked about jq over all time, one of the last twelve months. They decided what sprints 65 and 67 added (table output, CSV in, document diff, the primer). The raw pulls (Stack Exchange and GitHub API replies, Hacker News search results, a copy of the jq wiki) are kept with the author's working records, not in this repository. Reddit refused every automated read, so nothing below rests on Reddit.

**How the first survey was done.** The 200 highest-voted Stack Overflow questions tagged [jq] (of 6,922) and the tag's 60 most-linked; counts of question titles containing words such as csv, merge, null, date; the 50 jqlang/jq issues with the most thumbs-up, and the most-commented; the jq wiki's FAQ, Cookbook and Pitfalls pages; Hacker News stories found through its search API. The agent grouped the findings into twenty kinds by its own judgement and ran the library on each kind it marked solved.

**What it can and cannot tell.** Votes accumulate over years, so the top questions date from 2013 to 2018 and come from beginners: they measure what people search for, not what slows down someone doing analysis. The titles were read, not the 200 questions in full. The second survey exists because the [jq] tag now gets about one question in 90 days.

## 1. The questions, ranked, and the library's coverage

Evidence: Stack Overflow votes / views; GitHub 👍 and comments (c) on jqlang/jq. Each "solved" was run against the library (0.14.0); the right-hand column is updated to 0.15.0.

| # | Problem | Evidence | Verdict |
|---|---|---|---|
| 1 | Shell glue: raw output, bash variables in, output into arrays or loops | SO 44656515 (800 / 412k), 18592173 (557 / 823k); GH #250 117 👍 | out of scope (CLI) |
| 2 | Selecting objects by a value, also inside arrays | SO 26701538 (518 / 691k) | out of scope (core jq) |
| 3 | Picking fields, listing keys, key/value pairs | SO 28164849 (550 / 566k) | out of scope; `rows_from_map` helps |
| 4 | JSON to CSV, TSV or a printed table | SO 32960857 (250 / 268k), 39139107 (166 / 182k); 297 titles | was partly; 0.15.0: `to_csv(null)` infers the columns and writes nested values as JSON text; `to_tsv`, `to_table` |
| 5 | Merging objects; joining two files on a key | SO 19529688 (265 / 246k) | **solved** for keyed joins (`join_*`, `lookup`, `join_nest`) |
| 6 | Updating a value; editing a file in place | GH #105 382 👍 | out of scope (CLI) |
| 7 | Count, group, sum or average per key | SO 21334348 (476 / 478k) | **solved**: `group_agg`, `value_counts`, `split_by`, `mean`, `median` |
| 8 | Nulls: iterate over null, dropping null or empty values | SO 54794749 (50 / 76k), 56692037 (38 / 87k) | SQL null rules, `profile`; 0.15.0: `drop_empty` |
| 9 | JSON Lines vs arrays; slurp, inputs, streams | SO 42178636 (56 / 38k) | out of scope (CLI flags); rule 1 states it |
| 10 | Dates: fractional seconds, offsets, durations, local time | GH #1409 73 👍, #1117 39 👍, #2224 38 👍 | **solved**: `parse_ts` reads `.123Z` and `+02:00` where `fromdateiso8601` fails; `local_time` across DST |
| 11 | Flattening nested data; all paths | SO 24698188 (39 / 77k) | `flatten_fields`, `unnest`; 0.15.0: `flatten_paths`, `unflatten_fields` |
| 12 | Comparing two JSON files | SO 31930041 (214 / 187k) | `diff_tables` for keyed tables; 0.15.0: `diff_docs` for any document |
| 13 | Sort, dedupe, top N per group | SO 30331504 (177 / 188k) | top N **solved** by `window` + `row_number` / `rank_by` |
| 14 | Error messages and syntax | SO 34543829 (115 / 201k) | out of scope; the library's own errors are clear since 0.14.0 |
| 15 | Large files and speed | HN zq 462 pts, "DuckDB as the new jq" 364 | out of scope; the README hands off past ~200,000 rows |
| 16 | Regex and strings | SO 50868203 (48 / 58k) | out of scope (core) |
| 17 | Variables, reduce, scoping | SO 34745451 (74 / 180k) | language matter; `window` and `group_agg` replace most hand-written reduce |
| 18 | YAML, comments, relaxed JSON | GH #467 365 👍 | out of scope |
| 19 | CSV text into JSON | SO 44780761 (79 / 82k), 29663187 (51 / 60k); two wiki Cookbook entries | was missing; 0.15.0: `from_csv`, `rows_from_arrays` |
| 20 | Median, percentile | rare on SO | **solved** |

Reading: the most viewed questions are about the shell and basic selection, which no library fixes. The library covers the analytic middle (grouping, joins, dates, top N, statistics), where hand-written answers are long and often wrong about nulls and time zones.

### In-scope gaps, most often hit first (1 to 6 closed in 0.15.0)

1. **Table output**: `to_csv(null)` inferring columns (union of keys, first seen) and writing nested values as JSON text; `to_tsv`; `to_table` for a terminal.
2. **CSV text to rows**: `rows_from_arrays` (`[header, row…]` to objects); `from_csv` parsing raw CSV text read with `-R`, quotes included.
3. **Null and empty cleanup**: `drop_empty` (recursive; null, `""`, `[]`, `{}`), `coalesce`.
4. **Comparing nested documents**: `diff_docs($old)`, one row per changed path.
5. **Flattening both ways**: arrays as indexed columns in `flatten_fields`; `unflatten_fields`.
6. **Formatted local time**: `format_local($tz; $fmt)`.
7. **Deep merge with array rules** (rare): `merge_deep`.

## 2. Where to announce

Measured 2026-11-19. The official jq channels are quiet: jq Discussions has 50 posts in all and none in 90 days; the Stack Overflow [jq] tag had 1 new question in 90 days. Reach is now on Hacker News, the awesome-jq list and the jq wiki; jq's own issues still get 9 to 23 new ones a month.

| Place | Activity | Rules that matter | Fit |
|---|---|---|---|
| Show HN | jq-adjacent stories reach 300 to 600 points (jaq 440, sq 606, "A faster alternative to jq" 396); most Show HN jq posts get under 10 | runnable without sign-up, your own work; no "quickly generated one-offs" | high |
| jqlang/awesome-jq | 992 stars; last merge 2026-08-17; PRs wait months | PR under "Libraries and tools for jq itself" | high for discovery, slow |
| jq wiki, Modules and Cookbook | anyone edits; Modules last edited 2021 | edit directly | medium |
| jq issues asking for these functions | #1475 joins (31 c), #2195 strptime %z, closed #1053 (24 c) | a comment showing the exact solving call | medium |
| r/commandline | not verified | reported ban on low-quality AI-generated projects | medium–high |
| Changelog News | has covered gojq and jq before | account; say why it is news | medium |
| jq Discord | 282 members | not joined | low–medium |
| Lobsters | invite only; 70-day account age for self-promotion | | only with an established account |
| jq Discussions "Show and tell" | 3 posts ever | | low reach, on topic |
| Stack Overflow | search traffic on old questions | disclose; answer without the library too; no repeated links | low–medium |
| gojq, jaq repos | discussions off | issues for bugs only | low |

Order: release first; on day 0 the wiki Modules entry and the awesome-jq PR (slow); Show HN on a US weekday morning; then r/commandline, jq Discussions, the Discord and Changelog; later, comments on jq #1475 and #2195 with working examples and a few disclosed Stack Overflow answers.

Prepare before posting: a tagged release; a one-line install; a README that opens on three before/after examples (a join, a group with a median, a time-zone or "who held it" case); a test matrix with exact engine versions and CI that runs them; a demo needing no install (a jq playground link or a GIF); a short note on how the code was written with AI and how it was checked; a Cookbook recipe for the wiki.

Not verified: Reddit membership and rules, Discord message volume, Lobsters counts, Terminal Trove's newsletter size.

## 3. The last twelve months (2025-11-19 to 2026-11-19)

Run the same day, over 2025-11-19 to 2026-11-19, reading the full text of the most-engaged items (all 23 tagged questions, the 25 most-engaged jq issues, all 7 discussions, 11 gojq and jaq issues, the top comments of the largest Hacker News thread). Counts: 23 tagged Stack Exchange questions (1 in the last 90 days); jq 78 issues and 7 discussions; gojq 10 and jaq 33 issues; 32 Hacker News stories and 408 comments naming jq; claude-code 20, yq 3, jnv 3 issues with jq in the title. Reddit and Lobsters were not reachable.

Most items are old kinds: shell glue (now often an AI agent's shell), selecting and how generators behave, merging and joining files (the year's most-viewed question, U&L 801994), CSV output, slurp and streams (now about engines behaving alike), speed (now about other engines), error messages, strings, other formats (TOON is new), dates and number precision (as bug reports). New kinds: correctness and memory-safety reports (about 34), differences between engines (about 11), embedding jq as a library (about 9), AI writing jq and jq as an agent's tool (138 of 408 HN comments), shape, schema and introspection (5; jq #3540 asks for a structure-with-types outline).

For the library: it confirms the AI-vocabulary purpose; engine differences found this year (`from_entries` with Name/Value, key order after `del`, `isnan`, `--slurp`) go to spec 75 (core jq and engines); candidate functions are a recursive type outline (also the first step in unwrapping an API reply) and a merge of documents that combines arrays without duplicates; teaching points go to the primer, `docs/primer.md`. 
