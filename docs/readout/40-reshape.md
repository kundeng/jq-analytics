# Reshape

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/reshape.md`. Do not edit.

Two definitions: `unpivot` turns columns into rows, and `pivot` turns rows into columns.

## unpivot

`unpivot/3`, lines 310 to 313:

```jq
# unpivot: every field not in $keep becomes its own row {keep fields..., $name: field, $value: value}.
# Null values are kept (Power Query's example drops them). Within a row, fields come out sorted by
# name, so every engine agrees (jq and jaq keep insertion order, gojq sorts keys).
def unpivot($keep; $name; $value):
  [.[] as $r | ($r | with_entries(select(.key as $k | $keep | any(. == $k)))) as $base
   | $r | to_entries | sort_by(.key)[] | select(.key as $k | $keep | any(. == $k) | not)
   | $base + {($name): .key, ($value): .value}];
```

For each row, the fields named in `$keep` stay as they are (`$base`); every other field becomes a row of its own, holding the field's name under `$name` and its value under `$value`.

- `with_entries(select(.key as $k | $keep | any(. == $k)))` is the row cut down to the kept fields.
- `to_entries | sort_by(.key)[]` walks the row's fields in name order. jq and jaq keep fields in the order they were written and gojq sorts them, so sorting here is what makes every engine give the same row order.
- A null value still gets its row.

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

## pivot

`pivot/5`, lines 318 to 320:

```jq
# pivot: one output row per rowkey (an object) and one column per name in $cols (Power Query's
# pivotValues), holding agg applied to the array of valf values whose colf (as a string) is that
# name. A name with no matching rows gives null; colf values not in $cols are dropped.
def pivot($cols; rowkey; colf; valf; agg):
  group_agg(rowkey; (reduce .[] as $r ({}; .[$r | colf | tostring] += [$r | valf])) as $cells
    | reduce $cols[] as $c ({}; .[$c] = ($cells[$c] | if . == null then null else agg end)));
```

One output row per `rowkey`, one column per name in `$cols`.

- `group_agg(rowkey; …)` makes the row groups.
- Inside each group, `reduce .[] as $r ({}; .[$r | colf | tostring] += [$r | valf])` collects the values under their column name: `$cells` is `{column: [values]}`.
- `reduce $cols[] as $c ({}; .[$c] = …)` builds the output columns in the order of `$cols`: `agg` applied to the column's values, or null when the group has none. Column values that are not in `$cols` are dropped.

The caller lists the columns because jq cannot know them before reading all the data, and a fixed list gives every row the same columns in the same order.

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

`db01` has no `cpu` rows, so its `cpu` is null; its `disk` row is dropped because `disk` is not in the list.

**Review finding 8.** The inner `reduce` appends to an array inside an object, the pattern the comment above `_groups` says is avoided everywhere in this file. Its cost grows with the square of the number of values in one cell: one row key and one column with 20,000 values took 0.5 s, 40,000 took 1.6 s and 80,000 took 5.9 s (jq 1.8.2). With many row keys and few values per cell it is fine (80,000 rows over 5,000 keys: 1.0 s). Grouping by column inside each row group would remove it.
