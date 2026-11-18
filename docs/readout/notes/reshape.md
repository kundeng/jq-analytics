Two definitions that are each other's opposite: `unpivot` turns columns into rows, and `pivot` turns rows into columns.

A table with one column per measurement (`cpu`, `ram`) is called wide. The same data with one row per measurement, and the measurement's name in a column of its own, is called long. Grouping and joining work on long tables; reports are usually wide.

## unpivot/3
<!-- code: dcf3efa5 -->

Wide to long: every column that is not kept becomes a row of its own. It is Power Query's "Unpivot Other Columns", SQL's `UNPIVOT`, and pandas' `melt`.

### The example

Two hosts with two measurements each. The second row has its fields in another order, and one null.

| host | cpu | ram |
|---|---|---|
| web01 | 0.5 | 16 |
| db01 | null | 64 |

```jq run
[{host: "web01", cpu: 0.5, ram: 16}, {host: "db01", ram: 64, cpu: null}]
| unpivot(["host"]; "metric"; "value")
```

Two rows in, four out: one per host and measurement. `host` is repeated on each. The null `cpu` of `db01` still gets its row. Within each host the measurements come in name order, `cpu` before `ram`, whatever order the fields were written in.

### Reading the call

All three arguments are values (each has a `$` in the definition).

| Argument | In the example | Meaning |
|---|---|---|
| `$keep` | `["host"]` | the columns that stay as they are, on every output row |
| `$name` | `"metric"` | the name of the new column that holds the old column's name |
| `$value` | `"value"` | the name of the new column that holds its value |

### What happens inside, on the example

The steps run once per input row. For the first row, `{host: "web01", cpu: 0.5, ram: 16}`:

Step 1, `with_entries(select(.key as $k | $keep | any(. == $k)))`: the row cut down to its kept fields. This is `$base`.

```jq run
{host: "web01", cpu: 0.5, ram: 16} | with_entries(select(.key as $k | ["host"] | any(. == $k)))
```

Step 2, `to_entries | sort_by(.key)[]`, then the `select` that drops the kept fields: the other fields as `{key, value}` pairs, in name order. This emits two values, one per field:

```jq run
{host: "web01", cpu: 0.5, ram: 16}
| to_entries | sort_by(.key)[] | select(.key as $k | ["host"] | any(. == $k) | not)
```

Step 3, `$base + {($name): .key, ($value): .value}`: each pair becomes an output row. Again two values:

```jq run
{host: "web01"} as $base
| ({key: "cpu", value: 0.5}, {key: "ram", value: 16}) | $base + {("metric"): .key, ("value"): .value}
```

The outer `[...]` collects the rows of all input rows into one array.

### The definition

<!-- definition -->

- `[.[] as $r | ...]`: one pass per input row `$r`.
- The `$base` line: step 1. `any(. == $k)` asks whether the field's name is in `$keep`.
- `$r | to_entries | sort_by(.key)[]`: step 2. jq and jaq keep fields in the order they were written and gojq sorts them, so sorting here is what makes every engine give the same row order.
- `select(... | not)`: the kept fields are not unpivoted.
- `$base + {($name): .key, ($value): .value}`: step 3. The parentheses make the field names come from the variables. No `select` on the value follows, so a null value keeps its row.

## pivot/5
<!-- code: 09ec9157 -->

Long to wide: one output row per row key, and one column per name in a list the caller gives. It is a spreadsheet's pivot table, SQL's `PIVOT`, and Power Query's "Pivot Column".

### The example

Five measurements in long form. `web01` has two `cpu` values. `db01` has no `cpu` and has a `disk` value.

| host | metric | v |
|---|---|---|
| web01 | cpu | 0.5 |
| web01 | cpu | 0.7 |
| web01 | ram | 16 |
| db01 | ram | 64 |
| db01 | disk | 1 |

The call: one row per host, columns `cpu` and `ram`, each holding the greatest value.

```jq run
[{host: "web01", metric: "cpu", v: 0.5}, {host: "web01", metric: "cpu", v: 0.7}, {host: "web01", metric: "ram", v: 16},
 {host: "db01", metric: "ram", v: 64}, {host: "db01", metric: "disk", v: 1}]
| pivot(["cpu", "ram"]; {host}; .metric; .v; max)
```

Two rows. For `web01`, `cpu` is 0.7, the greater of its two values. `db01` has no `cpu` rows, so its `cpu` is null. Its `disk` row is dropped, because `disk` is not in the list.

### Reading the call

`pivot(["cpu", "ram"]; {host}; .metric; .v; max)` has five arguments, separated by `;`.

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$cols` | `["cpu", "ram"]` | nothing: it is a value | the output columns, in this order |
| `rowkey` | `{host}` | one row | the object that identifies the output row |
| `colf` | `.metric` | one row | which column the row's value goes to |
| `valf` | `.v` | one row | the value |
| `agg` | `max` | the array of one cell's values | the one value shown in the cell |

`{host}` is short for `{host: .host}`. The caller lists the columns because jq cannot know them before it has read all the data, and a fixed list gives every row the same columns in the same order.

### What happens inside, on the example

Step 1, `group_agg(rowkey; ...)`: the rows are grouped by `{host}`, as on the grouping page. Steps 2 and 3 run inside each group. The `web01` group is the first three rows.

Step 2, `group_by(colf | tostring) | map({key: ..., value: map(valf)}) | from_entries`: the group's values gathered per column name. This is `$cells`.

```jq run
[{host: "web01", metric: "cpu", v: 0.5}, {host: "web01", metric: "cpu", v: 0.7}, {host: "web01", metric: "ram", v: 16}]
| group_by(.metric | tostring) | map({key: (.[0] | .metric | tostring), value: map(.v)}) | from_entries
```

Step 3, `reduce $cols[] as $c ({}; .[$c] = ...)`: the output columns are built one at a time, in the order of `$cols`. Each is `agg` on that column's list. The run uses `foreach`, which does the same as `reduce` and also prints the object after each column:

```jq run
{cpu: [0.5, 0.7], ram: [16]} as $cells
| foreach ("cpu", "ram") as $c ({}; .[$c] = ($cells[$c] | if . == null then null else max end))
```

Two values: the object after `cpu`, then after `ram`. `group_agg` puts the group's key `{host: "web01"}` in front of the last one.

For `db01`, `$cells` has `ram` and `disk`. `$cells["cpu"]` is null, so the `cpu` column is null and `max` is not called. `disk` is never asked for.

### The definition

<!-- definition -->

- `group_agg(rowkey; ...)`: step 1. The row key should be an object, such as `{host}`, so that its fields become the first columns.
- The `$cells` expression: step 2. `tostring` is applied to the column value because the names in `$cols` are strings. Inside a group, `group_by` keeps input order, so the values reach `agg` in input order.
- `reduce $cols[] as $c ({}; .[$c] = ($cells[$c] | if . == null then null else agg end))`: step 3. A column with no rows gives null without calling `agg`.
