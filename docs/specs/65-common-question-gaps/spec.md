---
spec_id: 65-common-question-gaps
status: CLOSED
closed_as: SHIPPED
since: 2026-11-19
until: null
epic: shapes
features: [table-output-inferred, tsv-and-text-table, csv-text-to-rows, drop-empty, diff-docs, flatten-arrays, unflatten-fields, format-local]
supersedes: []
superseded_by: null
depends_on: [60-input-type-check]
anchors: [05-shapes]
---

# 65 Gaps from the common questions

## Requirements

### Scope

A survey on 2026-11-19 of the questions people ask about jq (the top 200 Stack Overflow [jq] questions by votes and the tag's most-linked ones, jqlang/jq issues by reactions and comments, the jq wiki FAQ, Cookbook and Pitfalls pages, Hacker News stories) found twenty recurring problems. Half are about the shell or core jq and no library can answer them. Of the rest the library solves grouping and counting, keyed joins, dates and time zones, top N per group and statistics. Six it solves partly or not at all, and this sprint closes them, in order of how often people hit them:

| Problem | Evidence (Stack Overflow votes / views) | Today |
|---|---|---|
| JSON to CSV, TSV or a printed table | 32960857 (250 / 268k), 39139107 (166 / 182k); 297 titles mention CSV | `to_csv($cols)` needs the column list and refuses nested values; no TSV, no text table |
| CSV text into JSON | 44780761 (79 / 82k), 29663187 (51 / 60k); two jq wiki Cookbook entries | nothing |
| Dropping null or empty values everywhere in a document | 56692037 (38 / 87k), 39500608 (33 / 50k) | nothing recursive |
| Comparing two JSON documents | 31930041 (214 / 187k) | `diff_tables` for keyed tables only |
| Flattening arrays too, and back | 24698188 (39 / 77k), 39800718 (27 / 24k) | `flatten_fields` flattens objects only; no unflatten |
| A timestamp as readable local text | 44497533 (21 / 16k) | `local_time` gives fields, not text |

### Requirements

- **R1. Table output.** `to_csv(null)` takes the columns as every field name, sorted (gojq does not keep key order, so first-seen order would differ by engine); a nested value in a cell is written as its JSON text, not an error (`to_csv($cols)` with a list behaves as now apart from that). `to_tsv($cols)` the same with tabs, escaping tab, newline and backslash as jq's `@tsv` does. `to_table($cols)` prints padded plain-text columns with a header line, for a terminal.
- **R2. CSV text to rows.** `rows_from_arrays` turns `[header, row, …]` into objects. `from_csv` reads the text of a CSV file (jq `-Rs`) into rows by RFC 4180: quoted fields, doubled quotes, commas and line breaks inside quotes, CRLF or LF line ends; every value stays a string, for `cast_columns`. A row with more cells than the header is an error naming its line.
- **R3. Cleanup.** `drop_empty` removes, at every depth, fields and array items that are null, `""`, `[]` or `{}`, and a container left empty by that. (A `drop_nulls` was planned and left out: jq's own `del(.. | nulls)` does it.)
- **R4. Document diff.** `diff_docs($old)` gives one row per path where the two documents differ, `{path, change, old, new}` with change `added`, `removed` or `changed`, paths in jq's `getpath` form, sorted. Arrays compare by position.
- **R5. Flatten both ways.** `flatten_paths($sep)` flattens arrays as well as objects (`tags.0`); `unflatten_fields($sep)` rebuilds the nesting from such names, numeric parts becoming array positions; flattening then unflattening gives the row back.
- **R6. Local text.** `format_local($tz; $fmt)` formats an instant in a zone with strftime directives, the zone's offset applied (DST included); `%Z` and `%z` are written from the zone tables, not the process.
- **R7.** Each new public function checks its input (spec 60), has a read-out note, an entry in the skill's question table and README, and at least one case with an answer from DuckDB where DuckDB can give it (`read_csv` for `from_csv`, `strftime` with a time zone for `format_local`).

### Out of scope

Deep merge with array rules (rare in the survey); TSV and CSV input dialects other than RFC 4180 (semicolons, no quoting); approximate document diff (moved array items).

## Design

Placement: shapes in and out (`_cell`, `_cols`, `to_csv`, `to_tsv`, `to_table`, `rows_from_arrays`, `from_csv`, `flatten_paths`, `_setp`, `unflatten_fields`, `drop_empty`); distributions, profiles, diffs (`_diff`, `diff_docs`); time zones (`format_local`). Each has a worked case in its read-out note and the README.

- `from_csv` is a `reduce` over the text's code points with a five-field state (rows, row, cell, inside quotes, quote just seen); `-1` after the last character ends the last row. Measured on 0.5 MB, 20,000 rows: jq 1.7.1 2.5 s, gojq 1.1 s, jaq 0.85 s; so about 5 s a megabyte in jq, and the README sends larger files to DuckDB.
- `unflatten_fields` sets values through `_setp`, not `setpath`, because jaq 3.1.2 will neither create an array from null nor assign past an array's end.
- `format_local` writes `%z` and `%Z` itself before calling `strftime`, which would print the machine's zone.

## Tasks

- [x] 1. Table output (R1), with cases.
- [x] 2. CSV text to rows (R2), with cases against DuckDB `read_csv`, quotes and line breaks inside quotes included.
- [x] 3. `drop_empty`, `drop_nulls` (R3).
- [x] 4. `diff_docs` (R4).
- [x] 5. `flatten_paths`, `unflatten_fields` (R5), with the round-trip case.
- [x] 6. `format_local` (R6), across a DST change.
- [x] 7. Read-out notes, README, skill, feature matrix; version 0.15.0.

## Log

- 2026-11-19. Drafted from the survey of common jq questions, on the owner's ask to sprint on what it finds before the alpha.
- 2026-11-19. Built in the same session. 205 of 205 cases on jq 1.7.1, gojq 0.12.20, jaq 3.1.2 and the Python package 1.13.0 (jq 1.8.2), 15 of them new, two with DuckDB answers (`read_csv` for `from_csv`, `strftime` with a time zone for `format_local`); 110 public functions; read-out 19 pages, 153 definitions. Closed SHIPPED as 0.15.0.
