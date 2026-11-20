# Input checks

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/input-checks.md`. Do not edit.

Four internal definitions that every other page calls first. A function here takes its whole input as one value: a table is one array of rows, a list is one array of values (README, rule 6 "One value in"). The usual mistake is `$rows[] | f`, which runs `f` once per row. Before version 0.14.0 that gave jq's own message, which names neither the function nor the cause, or, for `mode`, `value_counts` and `count_nonnull`, a wrong answer with no error. Now the function stops and says what it was given and what to write instead.

```mermaid
flowchart LR
  W[_what: the value in words] --> T[_table: an array of rows]
  W --> L[_list: an array of values]
  W --> O[_tables: an object of tables]
  T --> F1[group_agg, joins, window, ... 50 functions]
  L --> F2[mean, median, mode, ... 21 functions]
  O --> F3[shape, keep_tables]
```

Only the outer type is checked. The rows of a table are not required to be objects, so `map(.site) | group_agg({site: .}; {n: length})`, a table of plain values, still works, and so does an edge list of pairs. Checking every item would also cost a pass over the rows; checking the outer type costs nothing measurable.

On this page, in the order of the file:

| Function | Whose | What it is for |
|---|---|---|
| `_what` | Internal helper, not for callers | What a value is, in words, for the messages: "one object" for an object, since an object given where a table belongs is almost always one row; otherwise its type |
| `_table` | Internal helper, not for callers | The input, or an argument, must be a table |
| `_list`, `_tables` | Internal helpers, not for callers | `_list`: the input must be a list of values |

---

## _what

**Internal helper, not for callers** · `_what`

`_what/0`, lines 30 to 31:

```jq
# what a value is, in words, for the messages below
def _what: if type == "object" then "one object" elif type == "array" then "an array" else "a \(type)" end;
```

Built into jq: `type`.

What a value is, in words, for the messages: "one object" for an object, since an object given where a table belongs is almost always one row; otherwise its type.

### _what: the example

```jq
{site: "N"}, [1, 2], "N", 3, null | _what
```

```json
"one object"
"an array"
"a string"
"a number"
"a null"
```

---

## _table

**Internal helper, not for callers** · `_table($who; $arg)`

The input, or an argument, must be a table. `$who` is the function's name and `$arg` says which value is checked: `"the input"`, or for an argument a phrase such as `"the right table"`. A table passes through unchanged, so `_table(...) | rest` is the function as it was.

### _table: the example

The mistake, then the right call, on the same three rows:

```jq
[{site: "N", n: 1}, {site: "S", n: 2}, {site: "N", n: 3}] as $rows
| (try ($rows[] | group_agg({site}; {n: length})) catch .),
  ($rows | group_agg({site}; {n: length}))
```

```json
"group_agg: the input is one object, not a table (an array of rows). Pass the whole table as one value: $rows | group_agg(...), not $rows[] | group_agg(...)."
[{"site":"N","n":2},{"site":"S","n":1}]
```

The first line is the message, given once: the first row stops the run. The second is the answer.

A row passed where an argument table belongs:

```jq
[{host: "web01"}] | try join_left({host: "web01", site: "N"}; .host; .host) catch .
```

```json
"join_left: the right table is one object, not a table (an array of rows). Pass the whole table as an array."
```

### _table: the definition

`_table/2`, lines 33 to 37:

```jq
# the input, or the argument named by $arg, must be a table: an array of rows
def _table($who; $arg):
  if type == "array" then .
  elif $arg == "the input" then error("\($who): the input is \(_what), not a table (an array of rows). Pass the whole table as one value: $rows | \($who)(...), not $rows[] | \($who)(...).")
  else error("\($who): \($arg) is \(_what), not a table (an array of rows). Pass the whole table as an array.") end;
```

Built into jq: `error`, `type`. From this library: `_what`.

- `type == "array"`: a table of any rows passes, an empty one included.
- For the input, the message shows the call written both ways, with the function's own name.

---

## _list, _tables

**Internal helpers, not for callers** · `_list($who)`, `_tables($who)`

`_list`: the input must be a list of values. `_tables`: the input must be an object whose fields are tables, the shape `split_by` makes and `shape` and `keep_tables` read.

### _list and the others: the example

`count_nonnull` used to count a row's fields when given one row. Now it stops, and on the column it counts the rows:

```jq
[{site: "N"}, {site: null}, {site: "S"}] as $rows
| (try ($rows[] | count_nonnull) catch .),
  ($rows | map(.site) | count_nonnull)
```

```json
"count_nonnull: the input is one object, not a list of values. Make the list first, such as map(.site) | count_nonnull."
2
```

`shape` given one table instead of an object of tables:

```jq
try ([{site: "N"}] | shape) catch .
```

```json
"shape: the input is an array, not an object of tables (split_by makes one). For one table, use profile."
```

### _list and the others: the definition

`_list/1`, lines 39 to 42:

```jq
# the input must be a list of values: an array
def _list($who):
  if type == "array" then .
  else error("\($who): the input is \(_what), not a list of values. Make the list first, such as map(.site) | \($who).") end;
```

Built into jq: `error`, `type`. From this library: `_what`.

`_tables/1`, lines 44 to 47:

```jq
# the input must be an object whose fields are tables
def _tables($who):
  if type == "object" then .
  else error("\($who): the input is \(_what), not an object of tables (split_by makes one). For one table, use profile.") end;
```

Built into jq: `error`, `type`. From this library: `_what`.

The same pattern as `_table`, with a message that says how to make the right input: `map(.site)` for a list, `split_by` for an object of tables.
