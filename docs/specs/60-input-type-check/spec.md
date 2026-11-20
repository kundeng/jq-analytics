---
spec_id: 60-input-type-check
status: CLOSED
closed_as: SHIPPED
since: 2026-11-19
until: null
epic: hardening
features: [input-type-check]
supersedes: []
superseded_by: null
depends_on: [62-open-intervals-in-join-overlap]
anchors: [05-shapes]
---

# 60 Input-type check

## Requirements

### Scope

A function takes its whole input as one value: a table is one array of rows (README, rule 6 "One value in"). The commonest mistake is `$rows[] | f`, which runs `f` once per row. Measured on 0.9.2: most table functions then stop with jq's own message, which names neither the function nor the cause (`Cannot index string with string "g"`), and three do not stop at all: `mode`, `value_counts` and `count_nonnull` treat one row's field values as the list and answer about them. The owner asked for the assumption to be "explicit when the assumption is violated" (review comment under `_groups`, 2026-11-18), and for this sprint to wait for the end of his review; on 2026-11-19 he asked for it to be done now.

### Requirements

- **R1.** Every public function whose input is a table or a list of values stops, when its input is not an array, with an error that names the function, says what the input is, and says what to write instead.
- **R2.** A table passed as an argument (`$right` of the joins, `$dim` of `lookup`, `$intervals` of `join_within`, `$old` of `diff_tables`, `$right` of `join_fuzzy`) is checked the same way, and the message names the argument.
- **R3.** Functions whose input is an object (`shape`, `keep_tables`, `rows_from_map`) stop on an input that is not an object, naming the function.
- **R4.** Valid programs give the same answers as before: every existing case passes unchanged.
- **R5.** The same message on all five engines (jq 1.7.1, jq 1.8.2, gojq, jaq, the Python package).
- **R6.** The cost is too small to measure against the function's own work at 200,000 rows.

### Out of scope

- **The items of the array are not checked.** A table's rows are not required to be objects: `map(.site) | group_agg(.; length)` over a list of strings and edge lists of pairs are valid uses. Checking items would also cost a pass over every row (measured below).
- The window functions (`row_number` … `moving_mean`), which `window` hands one partition, an array, by construction; the measure-context functions, which `rollup` calls; the single-value functions (`parse_ts`, `round_to`, `tz_offset`, `local_time`) and the functions that read only their arguments.
- A library prefix on public names (spec 57, out of scope there too).

## Design

### The check

Four internal functions in a new section "input checks" at the top of the library, before every function that uses them:

```jq
def _what: if type == "object" then "one object" elif type == "array" then "an array" else "a \(type)" end;
def _table($who; $arg): if type == "array" then . else error("\($who): \($arg) is \(_what), not a table (an array of rows). ...") end;
def _list($who): if type == "array" then . else error("\($who): the input is \(_what), not a list of values. ...") end;
def _tables($who): if type == "object" then . else error("\($who): the input is \(_what), not an object of tables. ...") end;
```

Each public function starts with one call, for example `def group_agg(keyf; aggf): _table("group_agg"; "the input") | ...`. The joins share one body; to name the function the user called, `join_on`'s six-argument body moves to `_join(...; $who)`, and `join_on`, `join_inner`, `join_left`, `join_full`, `join_semi` and `join_anti` call it with their own names. A function that calls another public function (`median` calls `quantile_cont`) checks once, under its own name, before the call.

### The messages

| Input | Message |
|---|---|
| one row given to a table function | `group_agg: the input is one object, not a table (an array of rows). Pass the whole table as one value: $rows \| group_agg(...), not $rows[] \| group_agg(...).` |
| a row given as an argument | `join_left: the right table is one object, not a table (an array of rows). Pass the whole table: join_left($right; ...), where $right is an array.` |
| one row given to a list function | `mode: the input is one object, not a list of values. Make the list first, such as map(.site) \| mode.` |
| an array given where an object of tables is expected | `shape: the input is an array, not an object of tables (split_by makes one). For one table, use profile.` |

### Worked case

```text
[{site: "a"}, {site: "b"}, {site: "a"}][] | count_nonnull
before: 1, 1, 1          (each row's one field counted, no error)
after:  error "count_nonnull: the input is one object, not a list of values. ..."
[{site: "a"}, {site: "b"}, {site: "a"}] | map(.site) | count_nonnull
before and after: 3
```

### Cost, measured 2026-11-19 on 200,000 rows of ten fields

| Program | jq 1.8.2 | gojq | jaq |
|---|---|---|---|
| `length` | 0.32 s | 0.36 s | 0.21 s |
| array check, then `length` | 0.32 s | 0.35 s | 0.20 s |
| array check and every item an object, then `length` | 0.37 s | 0.39 s | 0.51 s |

The array check is free; the item check, left out, would add up to 0.3 s.

## Tasks

- [x] 1. Section "input checks" with `_what`, `_table`, `_list`, `_tables`; every public table, list and object-of-tables function starts with its check; `_join` carries the joins' name.
- [x] 2. Tests: one error case per message form and one per family (a row given to a table function, to a list function, as a join's right table, an array given to `shape`); the existing 182 cases pass unchanged, on five engines.
- [x] 3. Read-out: notes for the four new internal functions; every note whose definition changed is restamped and its line numbers rebuilt; README rule 6 rewritten (what happens when the rule is broken); the agent skill's error table; feature matrix.
- [x] 4. Carry back into `docs/readout/notes/` the rewrites made during the owner's review of the Grouping page (`_groups` step by step and against `group_by`; `group_agg` rewritten) and the "one value in" lead. Found already done in 0.9.3 (1ed603e); the lead is now page 00 and README rule 6.
- [x] 5. Version 0.14.0, tag, push.

## Log

- 2026-11-19. Opened on the owner's word to do it now. Scope from the 2026-11-18 decisions and README rule 6.
- 2026-11-19. 73 public functions check their input: 50 for a table (six joins through `_join`), 21 for a list, 2 for an object of tables; five functions also check a table argument. Read-out page 00 "Input checks" holds the four helpers; `readout.py` numbers pages from 00 so every other page keeps its number. 190 of 190 cases on jq 1.7.1, gojq 0.12.20, jaq 3.1.2 and the Python package 1.13.0 (jq 1.8.2); the 182 earlier cases unchanged. Read-out: 19 pages, 140 definitions, built on three engines. Closed SHIPPED as 0.14.0.
