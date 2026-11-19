---
name: jq-analytics
description: Answer analytic questions over JSON with the jq-analytics library (analytics.jq) - joins, grouping, statistics, time zones, state over time, intervals, trees, graphs and reports at several levels, written as jq. Load before writing any jq program that groups, joins, ranks, windows, pivots, computes a median or a share, asks "who held this at that time", measures time in a state, or walks a hierarchy or a graph, and whenever analytics.jq or `include "analytics"` is in reach. Says when to use the library and when to hand off to a database, the five rules a program must keep, which functions answer which question, a working method, and what jq's error messages mean here.
---

# jq-analytics

A jq library for analytic questions over JSON as it arrives: nested, every value a string, no database at hand. You already know jq. This skill gives you what jq knowledge does not: which function answers which question, and the rules a program must keep to get a right answer.

The files: `references/functions.md` lists every public function with how it is called and what it is for. The repository's `README.md` has the exact rules of each function (nulls, ties, errors) and its cost. Read the function's entry there before relying on an edge case.

## When to use it, and when not

| Situation | Use |
|---|---|
| JSON or YAML in a shell, a pipeline step, a search command or a workflow node, up to about 200,000 rows | this library |
| More than about 200,000 rows, or the same data answering many questions | a database such as DuckDB; the library's answers are tested against DuckDB's, so the hand-off changes speed, not results |
| Edit distance, phonetic matching, approximate quantiles, rank correlation | a database; the library does not have them |
| Fitting a model, forecasting, anything statistical beyond description | not jq |

## Loading it

The library is one file, `analytics.jq`, in a directory `<dir>`.

| Where | How |
|---|---|
| jq, gojq or jaq on the command line | `jq -L <dir> 'include "analytics"; ...' input.json` |
| no `-L` available | `include "analytics" {search: "<dir>"}; ...` |
| names kept apart from your own | `import "analytics" as a {search: "<dir>"}; ... a::mean` |
| Python `jq` package | put the `include` line with `search` in the program text; the installed package `jq_analytics` returns that line from `jq_analytics.include()` |

Names that start with `_` are internal: never call them. Everything else in `references/functions.md` is public.

## Five rules a program must keep

Each of these is a mistake agents make with this library. The first three fail loudly; the last two give a wrong answer quietly.

**1. One value in: the table, never its rows one at a time.** A function takes the whole table, an array of rows, as its one input. `.[]` before a function hands it one row at a time.

```text
right:  $rows | group_agg({site}; {n: length})
wrong:  $rows[] | group_agg({site}; {n: length})      jq: Cannot index string with string "site"
```

A file with one JSON object per line is many values: collect it first with `--slurp` or `[inputs]`.

**2. An argument without `$` is a filter, run on each row.** Write `.site`, or `{site}` for a named key. A bare `site` is a call to a function that does not exist; `"site"` is a constant, the same for every row, so everything lands in one group.

**3. Every value arrives as a string: give columns their types first.** `cast_columns` turns named columns into numbers, instants (seconds since 1970, UTC), strings or booleans; `""` becomes null; a value that does not convert is an error naming the column. Arithmetic on uncast strings fails or, worse, sorts as text.

```jq
[{x: "5"}, {x: "7"}, {x: ""}] | cast_columns({x: "number"}) | map(.x) | mean
```

```json
6
```

**4. Null is "unknown", as in SQL.** The statistics skip nulls (`mean` of `[5, 7, null]` is 6) and return null when nothing is left. A null join key never matches anything. A null group key is a group of its own.

**5. Results keep the order of the input.** Groups come in the order their keys first appear, and a window returns the rows in the order they came in. Sort at the end if the reader needs an order; do not assume one.

## From the question to the functions

Find the question; the shape tells you what one row must be; then read those functions in `references/functions.md`.

| The question sounds like | One row is | Functions |
|---|---|---|
| What is in this data? | anything | `shape` on an object of tables, `profile` on one table |
| How many, how much, what is typical, per something | a record | `group_agg` with `mean`, `median`, `quantile_cont`, `count_nonnull` on a column |
| Most common value; how values spread | a record | `value_counts`, `mode`, `histogram` with `bin_edges`, `corr` |
| Add a name or attribute from a second table | a record with a key | `lookup` (exactly one match, never multiplies rows); `join_left`, `join_inner` when several may match |
| Which rows have no match, or any match | a record with a key | `join_anti`, `join_semi` |
| The latest reading at or before each event | a record with a key and a time | `join_asof` |
| Previous value, change since last, rank within a group, running total | a record with a key and an order | `window` with `lag`, `lead`, `rank_by`, `row_number`, `running_sum`, `moving_mean` |
| Who or what held this at that moment | events that grant and release something | `intervals_from_events`, then `join_within` |
| Do these two things overlap in time; how many at once | an interval with a start and an end | `join_overlap`, `merge_intervals`, `concurrency` |
| How long in each state; when did it change | an event with an entity, a time and a state | `state_blocks`, `transitions` |
| Group activity into visits; longest streak | an event with an entity and a time | `sessions`, `runs` |
| How far through a sequence of steps do they get | an event with an entity, a time and a step name | `funnel`, `funnel_steps` |
| Do they come back in later periods | an event with an entity and a period | `cohorts`, `retention` |
| Totals for a node and everything under it; the path to the root | a node pointing at its parent | `tree_rollup`, `tree_paths` |
| What depends on this; what is reachable; in what order; which things are connected | an edge | `reachable`, `hops`, `shortest_path`, `topo_order`, `components` |
| Subtotals and a grand total; share of the total; this period against the last | a fact record with dimension fields | `rollup` with `measure`, `share_of`, `measure_with` and `without_filter`, `only_filters`, `shift`, `to_date` |
| The local time, the weekday, office hours | a record with an instant | `parse_ts`, then `local_time` with a zone name; `calendar` for a date table |
| Wide to long, long to wide | a record | `unpivot`, `pivot` |
| An array field into rows; nested objects into columns | a nested record | `unnest`, `flatten_fields`, `rows_from_map`, `nodes_from_nested` |
| What changed between two versions | two tables with a key | `diff_tables` |
| Keys that almost match | two tables with a text key | clean the key first (lowercase, trim); then `join_fuzzy` inside a block; for volume, a database |
| Hand the result to another tool | a table | `to_csv`, `to_map`, `node_link`, `nested_from_nodes` |

## What the names do not tell you

<!-- fields: from_first from_previous -->

Facts that cost a wrong answer or a wasted run when guessed. The comment of each function in `references/functions.md` has the rest: what each argument means and which fields the result carries.

- **Results have their own field names.** `intervals_from_events` returns `resource`, `holder`, `start`, `end`; `merge_intervals` returns the key as `key`; `funnel` returns `step`, `entities`, `from_previous`, `from_first`; `topo_order` returns `node`, `level`. Read the function's comment, or run it on two rows, before you join on or select its fields.
- **A rank follows the order of the window.** `rank_by(f)` numbers the rows in the order `window` sorted them and lets rows with equal `f` share a rank. The order and `f` must be the same thing. Top seller per day: `window(.day; -.sales; "rank"; rank_by(.sales))`, then keep rank 1. With another order, such as `.emp`, the ranks are positions by name and mean nothing.
- **Descending order:** negate a number in the order argument (`-.sales`). For text or to reverse a whole result, `sort_by(...) | reverse` afterwards.
- **`group_agg`'s second argument is any filter that returns an object,** run on one group's rows. The last row per group: `group_agg({emp}; max_by(.day) | {last_day: .day, total})`.
- **Graph edges are followed from the first filter to the second.** With an edge meaning "X depends on Y", `reachable(.from; .to; "x")` is what x depends on; swap the two filters, `reachable(.to; .from; "db")`, for what depends on db. `reachable` leaves out the start; `hops` includes it at 0.
- **Intervals include their start and not their end.** One that ends at 10 and one that starts at 10 do not overlap, and a moment equal to an end belongs to the next interval. A null end means still open.
- **Empty or null time text gives null** from `parse_ts`; text that is not a time is an error naming it. `cast_columns` takes the types `"number"`, `"timestamp"`, `"string"` and `"boolean"`.
- **A limit that does not apply is null:** `funnel(...; $steps; null)` puts no time limit between the first and the last step; a number is a limit in the unit of the time argument.

## Working method

1. **Look first.** Run `shape` or `profile` on a sample. Which columns are empty strings, which hold numbers as text, which are nested? Do not write the analysis before you have seen this.
2. **State the question and the expected form of the answer** in one sentence each: "median hours to close, per team; one row per team".
3. **Give the columns their types** with `cast_columns`; turn time strings into instants. Derive what the question needs (`hours_between`, `local_time`).
4. **Build one stage at a time**, joined with `|`, naming a table you need twice with `as $name`. Run after each stage and look at two or three rows.
5. **Check one answer by hand** on a handful of rows before running on everything. Count the rows that should be in a group; work one median with a pencil.
6. **Then run it on all the data**, and say in your answer what was left out (null keys, rows that did not parse, unresolved items).

## Worked cases

Each case is a question, a few made-up rows, the program and what it prints. The outputs are checked against the library on every build.

### Typical time per group, from strings

How long do closed requests take, per team? Every value is a string; R3 is not closed.

```jq
[{id: "R1", opened: "2026-08-12 13:30:00", closed: "2026-08-12 16:00:00", team: "access"},
 {id: "R2", opened: "2026-08-14 23:10:00", closed: "2026-08-15 10:40:00", team: "access"},
 {id: "R3", opened: "2026-08-17 15:00:00", closed: "", team: "devices"}]
| cast_columns({opened: "timestamp", closed: "timestamp"})
| map(.hours = hours_between(.opened; .closed))
| group_agg({team}; {requests: length, closed: (map(.hours) | count_nonnull), median_hours: (map(.hours) | median)})
```

```json
[{"team":"access","requests":2,"closed":2,"median_hours":7},{"team":"devices","requests":1,"closed":0,"median_hours":null}]
```

By hand: R1 took 2.5 h and R2 11.5 h; `median` interpolates, so 7. The open request counts as a request and not as a closed one, and its team's median is null, not 0. Inside the second argument of `group_agg` the input is one group's rows.

### Who held this address at that time

A lease log says who was given an address and when it was released. Three connections came from that address; whose were they?

```jq
[{ip: "10.0.0.5", mac: "aa", t: 1000, msg: "ACK", lease: 3600},
 {ip: "10.0.0.5", mac: "aa", t: 5000, msg: "RELEASE"},
 {ip: "10.0.0.5", mac: "bb", t: 9000, msg: "ACK", lease: 3600}]
| intervals_from_events(.ip; .mac; .t; (if .msg == "ACK" then "hold" elif .msg == "RELEASE" then "release" else null end); .lease) as $leases
| [{src: "10.0.0.5", t: 1200}, {src: "10.0.0.5", t: 6000}, {src: "10.0.0.5", t: 9100}]
| join_within($leases; .src; .resource; .t; .start; .end)
| map({src, t, holder})
```

```json
[{"src":"10.0.0.5","t":1200,"holder":"aa"},{"src":"10.0.0.5","t":6000,"holder":null},{"src":"10.0.0.5","t":9100,"holder":"bb"}]
```

The first step turns events into intervals with the fields `resource`, `holder`, `start`, `end`: join on those names, not on the names of the log. The first lease ran from 1000 to 4600 (granted for 3600 s; the release at 5000 came after it had lapsed), so at 6000 nobody held the address and the answer is null. A join on the address alone would have named a holder for all three.

### Change since the previous reading

Per host, how did the reading change from the one before?

```jq
[{host: "a", t: 1, cpu: 10}, {host: "b", t: 1, cpu: 50}, {host: "a", t: 2, cpu: 30}, {host: "a", t: 3, cpu: 25}]
| window(.host; .t; "prev"; lag(.cpu; 1))
| map(.change = (if .prev == null then null else .cpu - .prev end))
```

```json
[{"host":"a","t":1,"cpu":10,"prev":null,"change":null},{"host":"b","t":1,"cpu":50,"prev":null,"change":null},{"host":"a","t":2,"cpu":30,"prev":10,"change":20},{"host":"a","t":3,"cpu":25,"prev":30,"change":-5}]
```

`window` takes the partition, the order, the name of the new column and a window function. The rows come back in input order with the column added; the first row of each host has no previous one.

### Subtotals and share of the parent

Amount per region and product, with each product's share of its region.

```jq
[{region: "east", product: "A", amount: 30}, {region: "east", product: "B", amount: 20}, {region: "west", product: "A", amount: 50}]
| rollup(["region", "product"]; {amount: measure(map(.amount) | add), of_region: share_of(map(.amount) | add; without_filter("product"))})
| map(select(.level == "region/product"))
```

```json
[{"region":"east","product":"A","level":"region/product","amount":30,"of_region":0.6},{"region":"east","product":"B","level":"region/product","amount":20,"of_region":0.4},{"region":"west","product":"A","level":"region/product","amount":50,"of_region":1}]
```

`rollup` also returns a row per region and a grand total, marked by `level`; the last line keeps the detail level only. `share_of(f; change)` is `f` here divided by `f` in a changed context: with the product filter removed, that is the region.

### Time spent in each state

Events say when a ticket's state was seen. How long was it in each state?

```jq
[{id: 1, t: 0, s: "open"}, {id: 1, t: 50, s: "open"}, {id: 1, t: 90, s: "waiting"}, {id: 1, t: 200, s: "closed"}]
| state_blocks(.id; .t; .s)
| map({state, start, end, duration})
```

```json
[{"state":"open","start":0,"end":90,"duration":90},{"state":"waiting","start":90,"end":200,"duration":110},{"state":"closed","start":200,"end":null,"duration":null}]
```

Repeated sightings of one state become one block. The last block is still open: its end and duration are null, not zero.

### Totals under each node

Head count of each unit including everything below it.

```jq
[{id: "all", parent: null, n: 1}, {id: "ops", parent: "all", n: 4}, {id: "net", parent: "ops", n: 3}]
| tree_rollup(.id; .parent; .n)
| map({id, depth, subtree})
```

```json
[{"id":"all","depth":0,"subtree":8},{"id":"ops","depth":1,"subtree":7},{"id":"net","depth":2,"subtree":3}]
```

### Local time of an instant

Was this opened in office hours in Detroit? The text is UTC.

```jq
"2026-11-02 14:00:00" | parse_ts | local_time("America/Detroit") | {date, hour, weekday}
```

```json
{"date":"2026-11-02","hour":9,"weekday":1}
```

`weekday` 0 is Sunday. Use `local_time` with a zone name; jq's own `localtime` uses the process's zone, which on a server is rarely the reader's.

## What the error messages mean

| Message | Cause | Fix |
|---|---|---|
| `Cannot index string with string "x"`, `Cannot index number with ...` | a row was passed where a table is expected (rule 1), or a list of values where rows are expected | remove the `.[]`, or `map(.x)` only where the function wants a list |
| `x/0 is not defined` | a bare field name as an argument (rule 2) | `.x` |
| `string ("57") and number (2) cannot be divided`, `cannot be subtracted` | arithmetic on an uncast column (rule 3) | `cast_columns` first |
| `cast_columns: x = "..." is not a number` | a value that is not a number in a column you declared as one | look at the value; clean it or leave the column a string |
| `has no keys`, `Cannot iterate over null` | the input is null or a scalar, often a wrong path into the document | print the input of that stage |
| a message that starts with a function's name | the library refused the input and says why | read it; it names the value |
| one group where you expected many | the key is a constant: `"site"` instead of `.site` (rule 2) | `.site` or `{site}` |
| a count that equals the number of fields | `mode`, `value_counts` or `count_nonnull` was given one row, not a list | `map(.x)` first |

## What not to do

- Do not rewrite a library function inline because it is short. The library's versions carry the null, tie and order rules, and are tested against a database.
- Do not report a number you have not checked on a few rows by hand.
- Do not call a name that starts with `_`.
- Do not run a join that compares every row with every row on a large table; `join_fuzzy` and the equality joins need a key or a block for that reason.
