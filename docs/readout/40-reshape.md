# Reshape

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/reshape.md`. Do not edit.

Four definitions. Two are each other's opposite: `unpivot` turns columns into rows, and `pivot` turns rows into columns. The other two change only the names of the columns: `rename_fields` renames the ones listed, and `prefix_fields` puts a prefix on all of them.

A table with one column per measurement (`cpu`, `ram`) is called wide. The same data with one row per measurement, and the measurement's name in a column of its own, is called long. Grouping and joining work on long tables; reports are usually wide.

On this page, in the order of the file:

| Function | Whose | What it is for |
|---|---|---|
| `unpivot` | Public function | Wide to long: every column that is not kept becomes a row of its own |
| `pivot` | Public function | Long to wide: one output row per row key, and one column per name in a list the caller gives |
| `rename_fields` | Public function | New names for the fields listed, in every row of a table |
| `prefix_fields` | Public function | A prefix in front of every field name of a table |

---

## unpivot

**Public function** · `unpivot($keep; $name; $value)`

Wide to long: every column that is not kept becomes a row of its own. It is Power Query's "Unpivot Other Columns", SQL's `UNPIVOT`, and pandas' `melt`.

### unpivot: the example

Two hosts with two measurements each. The second row has its fields in another order, and one null.

| host | cpu | ram |
|---|---|---|
| web01 | 0.5 | 16 |
| db01 | null | 64 |

```jq
[{host: "web01", cpu: 0.5, ram: 16}, {host: "db01", ram: 64, cpu: null}]
| unpivot(["host"]; "metric"; "value")
```

```json
[
  {"host": "web01", "metric": "cpu", "value": 0.5},
  {"host": "web01", "metric": "ram", "value": 16},
  {"host": "db01", "metric": "cpu", "value": null},
  {"host": "db01", "metric": "ram", "value": 64}
]
```

Two rows in, four out: one per host and measurement. `host` is repeated on each. The null `cpu` of `db01` still gets its row. Within each host the measurements come in name order, `cpu` before `ram`, whatever order the fields were written in.

### unpivot: reading the call

All three arguments are values (each has a `$` in the definition).

| Argument | In the example | Meaning |
|---|---|---|
| `$keep` | `["host"]` | the columns that stay as they are, on every output row |
| `$name` | `"metric"` | the name of the new column that holds the old column's name |
| `$value` | `"value"` | the name of the new column that holds its value |

### unpivot: what happens inside, on the example

The steps run once per input row. For the first row, `{host: "web01", cpu: 0.5, ram: 16}`:

Step 1, `with_entries(select(.key as $k | $keep | any(. == $k)))`: the row cut down to its kept fields. This is `$base`.

```jq
{host: "web01", cpu: 0.5, ram: 16} | with_entries(select(.key as $k | ["host"] | any(. == $k)))
```

```json
{"host":"web01"}
```

Step 2, `to_entries | sort_by(.key)[]`, then the `select` that drops the kept fields: the other fields as `{key, value}` pairs, in name order. This emits two values, one per field:

```jq
{host: "web01", cpu: 0.5, ram: 16}
| to_entries | sort_by(.key)[] | select(.key as $k | ["host"] | any(. == $k) | not)
```

```json
{"key":"cpu","value":0.5}
{"key":"ram","value":16}
```

Step 3, `$base + {($name): .key, ($value): .value}`: each pair becomes an output row. Again two values:

```jq
{host: "web01"} as $base
| ({key: "cpu", value: 0.5}, {key: "ram", value: 16}) | $base + {("metric"): .key, ("value"): .value}
```

```json
{"host":"web01","metric":"cpu","value":0.5}
{"host":"web01","metric":"ram","value":16}
```

The outer `[...]` collects the rows of all input rows into one array.

### unpivot: the definition

`unpivot/3`, lines 402 to 408:

```jq
# unpivot: every field not in $keep becomes its own row {keep fields..., $name: field, $value: value}.
# Null values are kept (Power Query's example drops them). Within a row, fields come out sorted by
# name, so every engine agrees (jq and jaq keep insertion order, gojq sorts keys).
def unpivot($keep; $name; $value): _table("unpivot"; "the input") |
  [.[] as $r | ($r | with_entries(select(.key as $k | $keep | any(. == $k)))) as $base
   | $r | to_entries | sort_by(.key)[] | select(.key as $k | $keep | any(. == $k) | not)
   | $base + {($name): .key, ($value): .value}];
```

Built into jq: `any`, `not`, `select`, `sort_by`, `to_entries`, `with_entries`. From this library: `_table`.

- `[.[] as $r | ...]`: one pass per input row `$r`.
- The `$base` line: step 1. `any(. == $k)` asks whether the field's name is in `$keep`.
- `$r | to_entries | sort_by(.key)[]`: step 2. jq and jaq keep fields in the order they were written and gojq sorts them, so sorting here is what makes every engine give the same row order.
- `select(... | not)`: the kept fields are not unpivoted.
- `$base + {($name): .key, ($value): .value}`: step 3. The parentheses make the field names come from the variables. No `select` on the value follows, so a null value keeps its row.

---

## pivot

**Public function** · `pivot($cols; rowkey; colf; valf; agg)`

Long to wide: one output row per row key, and one column per name in a list the caller gives. It is a spreadsheet's pivot table, SQL's `PIVOT`, and Power Query's "Pivot Column".

### pivot: the example

Five measurements in long form. `web01` has two `cpu` values. `db01` has no `cpu` and has a `disk` value.

| host | metric | v |
|---|---|---|
| web01 | cpu | 0.5 |
| web01 | cpu | 0.7 |
| web01 | ram | 16 |
| db01 | ram | 64 |
| db01 | disk | 1 |

The call: one row per host, columns `cpu` and `ram`, each holding the greatest value.

```jq
[{host: "web01", metric: "cpu", v: 0.5}, {host: "web01", metric: "cpu", v: 0.7}, {host: "web01", metric: "ram", v: 16},
 {host: "db01", metric: "ram", v: 64}, {host: "db01", metric: "disk", v: 1}]
| pivot(["cpu", "ram"]; {host}; .metric; .v; max)
```

```json
[
  {"host": "web01", "cpu": 0.7, "ram": 16},
  {"host": "db01", "cpu": null, "ram": 64}
]
```

Two rows. For `web01`, `cpu` is 0.7, the greater of its two values. `db01` has no `cpu` rows, so its `cpu` is null. Its `disk` row is dropped, because `disk` is not in the list.

### pivot: reading the call

`pivot(["cpu", "ram"]; {host}; .metric; .v; max)` has five arguments, separated by `;`.

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$cols` | `["cpu", "ram"]` | nothing: it is a value | the output columns, in this order |
| `rowkey` | `{host}` | one row | the object that identifies the output row |
| `colf` | `.metric` | one row | which column the row's value goes to |
| `valf` | `.v` | one row | the value |
| `agg` | `max` | the array of one cell's values | the one value shown in the cell |

`{host}` is short for `{host: .host}`. The caller lists the columns because jq cannot know them before it has read all the data, and a fixed list gives every row the same columns in the same order.

### pivot: what happens inside, on the example

Step 1, `group_agg(rowkey; ...)`: the rows are grouped by `{host}`, as on the grouping page. Steps 2 and 3 run inside each group. The `web01` group is the first three rows.

Step 2, `group_by(colf | tostring) | map({key: ..., value: map(valf)}) | from_entries`: the group's values gathered per column name. This is `$cells`.

```jq
[{host: "web01", metric: "cpu", v: 0.5}, {host: "web01", metric: "cpu", v: 0.7}, {host: "web01", metric: "ram", v: 16}]
| group_by(.metric | tostring) | map({key: (.[0] | .metric | tostring), value: map(.v)}) | from_entries
```

```json
{"cpu":[0.5,0.7],"ram":[16]}
```

Step 3, `reduce $cols[] as $c ({}; .[$c] = ...)`: the output columns are built one at a time, in the order of `$cols`. Each is `agg` on that column's list. The run uses `foreach`, which does the same as `reduce` and also prints the object after each column:

```jq
{cpu: [0.5, 0.7], ram: [16]} as $cells
| foreach ("cpu", "ram") as $c ({}; .[$c] = ($cells[$c] | if . == null then null else max end))
```

```json
{"cpu":0.7}
{"cpu":0.7,"ram":16}
```

Two values: the object after `cpu`, then after `ram`. `group_agg` puts the group's key `{host: "web01"}` in front of the last one.

For `db01`, `$cells` has `ram` and `disk`. `$cells["cpu"]` is null, so the `cpu` column is null and `max` is not called. `disk` is never asked for.

### pivot: the definition

`pivot/5`, lines 410 to 415:

```jq
# pivot: one output row per rowkey (an object) and one column per name in $cols (Power Query's
# pivotValues), holding agg applied to the array of valf values whose colf (as a string) is that
# name. A name with no matching rows gives null; colf values not in $cols are dropped.
def pivot($cols; rowkey; colf; valf; agg): _table("pivot"; "the input") |
  group_agg(rowkey; (group_by(colf | tostring) | map({key: (.[0] | colf | tostring), value: map(valf)}) | from_entries) as $cells
    | reduce $cols[] as $c ({}; .[$c] = ($cells[$c] | if . == null then null else agg end)));
```

Built into jq: `from_entries`, `group_by`, `map`, `tostring`. From this library: `_table`, `group_agg`.

- `group_agg(rowkey; ...)`: step 1. The row key should be an object, such as `{host}`, so that its fields become the first columns.
- The `$cells` expression: step 2. `tostring` is applied to the column value because the names in `$cols` are strings. Inside a group, `group_by` keeps input order, so the values reach `agg` in input order.
- `reduce $cols[] as $c ({}; .[$c] = ($cells[$c] | if . == null then null else agg end))`: step 3. A column with no rows gives null without calling `agg`.

---

## rename_fields

**Public function** · `rename_fields($names)`

New names for the fields listed, in every row of a table. It is SQL's `AS`, pandas' and Polars' `rename`, Power Query's "Rename Columns" and Splunk's `rename`.

It is needed in three places. After a join, `site_right` says which side a value came from, and a reader wants to know what it is. Before two tables are stacked, one may say `host` where the other says `hostname`. Before a report, the columns get the names its reader expects.

### rename_fields: the example

The result of a join of hosts with an inventory, both of which had a `site`. The second host matched nothing, so it has no `site_right`. The third row is empty.

| host | site | site_right |
|---|---|---|
| db01 | N | S |
| web01 | N | |
| | | |

```jq
[{host: "db01", site: "N", site_right: "S"}, {host: "web01", site: "N"}, {}]
| rename_fields({site_right: "site_cmdb"})
```

```json
[
  {"host": "db01", "site": "N", "site_cmdb": "S"},
  {"host": "web01", "site": "N"},
  {}
]
```

In the first row `site_right` is now `site_cmdb`, with the same value, in the same place. The other two rows have no `site_right` and are unchanged: no `site_cmdb` is added to them.

### rename_fields: reading the call

The one argument, `{site_right: "site_cmdb"}`, is a value: an object with the old name as key and the new name as value. Several fields are renamed in one call, `{site_right: "site_cmdb", host: "hostname"}`. An old name that no row has is ignored.

### rename_fields: why not plain jq

Plain jq has no rename. The usual way is to copy the field and delete the old one:

```jq
[{host: "db01", site: "N", site_right: "S"}, {host: "web01", site: "N"}, {}]
| map(.site_cmdb = .site_right | del(.site_right))
```

```json
[
  {"host": "db01", "site": "N", "site_cmdb": "S"},
  {"host": "web01", "site": "N", "site_cmdb": null},
  {"site_cmdb": null}
]
```

The first row is the same as before. The other two rows now have a `site_cmdb` that is null: jq reads a missing field as null and writes it back as a real one. On jq and jaq the copied field also moves to the end of its row, where `rename_fields` leaves it in place (gojq prints every object's fields sorted by name, so there the place cannot be seen).

### rename_fields: all names change at once

Each field is looked up once, under its old name. So two fields can swap names in one call, which two copy-and-delete steps cannot do without a third name:

```jq
[{first: "a", second: "b"}] | rename_fields({first: "second", second: "first"}) | map([.first, .second])
```

```json
[
  ["b", "a"]
]
```

`first` now holds "b" and `second` holds "a".

### rename_fields: what happens inside, on the example

Each row is handled alone. For the first row:

Step 1, `to_entries`: the row as a list of `{key, value}` entries, in the row's order.

Step 2, `map(.key = ($names[.key] // .key))`: each entry's key is looked up in `$names`. `$names["site_right"]` is `"site_cmdb"`, so that key is replaced. `$names["host"]` is null, and `// .key` puts the old key back. This list is `$e`.

```jq
{site_right: "site_cmdb"} as $names
| {host: "db01", site: "N", site_right: "S"} | to_entries | map(.key = ($names[.key] // .key))
```

```json
[
  {"key": "host", "value": "db01"},
  {"key": "site", "value": "N"},
  {"key": "site_cmdb", "value": "S"}
]
```

Step 3, `$e | from_entries`: the entries back into an object, `$o`. That is the output row.

### rename_fields: what is refused

A new name that is already another field of the row. `from_entries` would keep one of the two values and drop the other without a word, so the two lengths are compared: three entries went in, and an object of two fields came out.

```jq
try ([{host: "db01", site: "N", site_right: "S"}] | rename_fields({site_right: "site"})) catch .
```

```json
"rename_fields: a row would have two fields named \"site\""
```

The fix is to rename both, or to drop one first with `map(del(.site))`. An argument that is not an object of strings is refused too, with a message showing the form expected:

```jq
try ([{host: "db01"}] | rename_fields({host: 1})) catch .
```

```json
"rename_fields: the argument is an object of old name to new name, such as {\"host\": \"hostname\"}; got {\"host\":1}"
```

### rename_fields: the definition

`rename_fields/1`, lines 417 to 428:

```jq
# rename_fields: $names is an object {old name: new name}. Every row's field with an old name gets
# the new one and keeps its value and its place in the row; a row without the field is left as it
# is. All names change at once, so {a: "b", b: "a"} swaps two fields. A new name that is already
# another field of the row is an error: one of the two values would be lost.
def rename_fields($names): _table("rename_fields"; "the input") |
  if ($names | type) != "object" or any($names[]; type != "string")
  then error("rename_fields: the argument is an object of old name to new name, such as {\"host\": \"hostname\"}; got \($names | tojson)")
  else map((to_entries | map(.key = ($names[.key] // .key))) as $e | ($e | from_entries) as $o
    | if ($o | length) != ($e | length)   # a repeated name collapsed in from_entries
      then error("rename_fields: a row would have two fields named \($e | map(.key) | group_by(.) | map(select(length > 1)[0])[0] | tojson)")
      else $o end)
  end;
```

Built into jq: `any`, `error`, `from_entries`, `group_by`, `length`, `map`, `select`, `to_entries`, `tojson`, `type`. From this library: `_table`.

- The first `if` checks the argument: an object, all of whose values are strings.
- `map(...)`: one row at a time.
- `(to_entries | map(.key = ($names[.key] // .key))) as $e`: steps 1 and 2.
- `($e | from_entries) as $o`: step 3.
- `if ($o | length) != ($e | length)`: the check of "What is refused". The message names the first name that occurs twice in `$e`.

---

## prefix_fields

**Public function** · `prefix_fields($prefix)`

A prefix in front of every field name of a table. Put on one table before a join, it makes every field of the result show which table it came from, which is how Power Query names the columns of a merged table.

### prefix_fields: the example

A registry of hosts, and an empty row.

```jq
[{host: "db01", owner: "bo", team: "dba"}, {}] | prefix_fields("reg_")
```

```json
[
  {"reg_host": "db01", "reg_owner": "bo", "reg_team": "dba"},
  {}
]
```

Every field has `reg_` in front. The values are untouched, and the empty row stays empty.

### prefix_fields: before a join

Two tables that both have `host` and `owner`. Joined as they are, the result has `owner` and `owner_right` (the joins page says why). With the registry prefixed first, no name is shared, and each field says where it came from. The right key is then `.reg_host`:

```jq
[{host: "db01", owner: "ann"}, {host: "web01", owner: "cy"}]
| join_left([{host: "db01", owner: "bo", team: "dba"}] | prefix_fields("reg_"); .host; .reg_host)
```

```json
[
  {"host": "db01", "owner": "ann", "reg_host": "db01", "reg_owner": "bo", "reg_team": "dba"},
  {"host": "web01", "owner": "cy"}
]
```

`db01` has its own owner and the registry's. Both key fields are kept, `host` and `reg_host`, because they now have different names. `web01` matched nothing and has only its own fields.

To prefix all fields but one, rename that one back: `prefix_fields("reg_") | rename_fields({reg_host: "host"})`.

### prefix_fields: what is refused

A prefix that is not a string:

```jq
try ([{host: "db01"}] | prefix_fields(null)) catch .
```

```json
"prefix_fields: the prefix is a string, such as \"cmdb_\"; got null"
```

Two fields cannot end up with the same name, because two different names stay different with the same text in front. So there is no clash to check, unlike `rename_fields`.

### prefix_fields: the definition

`prefix_fields/1`, lines 430 to 435:

```jq
# prefix_fields: every field name of every row with $prefix in front ("cmdb_" turns site into
# cmdb_site). Put on one table before a join, it makes every output field show which table it came from.
def prefix_fields($prefix): _table("prefix_fields"; "the input") |
  if ($prefix | type) != "string"
  then error("prefix_fields: the prefix is a string, such as \"cmdb_\"; got \($prefix | tojson)")
  else map(with_entries(.key = $prefix + .key)) end;
```

Built into jq: `error`, `map`, `tojson`, `type`, `with_entries`. From this library: `_table`.

- The `if` checks that the prefix is a string.
- `map(with_entries(.key = $prefix + .key))`: for each row, `with_entries` turns the row into `{key, value}` entries, puts the prefix in front of each key, and builds the row again. On strings, `+` joins.
