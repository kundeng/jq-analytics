Two definitions: `unpivot` turns columns into rows, and `pivot` turns rows into columns.

## unpivot/3
<!-- code: dcf3efa5 -->

For each row, the fields named in `$keep` stay as they are (`$base`); every other field becomes a row of its own, holding the field's name under `$name` and its value under `$value`.

- `with_entries(select(.key as $k | $keep | any(. == $k)))` is the row cut down to the kept fields.
- `to_entries | sort_by(.key)[]` walks the row's fields in name order. jq and jaq keep fields in the order they were written and gojq sorts them, so sorting here is what makes every engine give the same row order.
- A null value still gets its row.

```jq run
[{host: "web01", cpu: 0.5, ram: 16}, {host: "db01", ram: 64, cpu: null}]
| unpivot(["host"]; "metric"; "value")
```

## pivot/5
<!-- code: 9db28264 -->

One output row per `rowkey`, one column per name in `$cols`.

- `group_agg(rowkey; …)` makes the row groups.
- Inside each group, `reduce .[] as $r ({}; .[$r | colf | tostring] += [$r | valf])` collects the values under their column name: `$cells` is `{column: [values]}`.
- `reduce $cols[] as $c ({}; .[$c] = …)` builds the output columns in the order of `$cols`: `agg` applied to the column's values, or null when the group has none. Column values that are not in `$cols` are dropped.

The caller lists the columns because jq cannot know them before reading all the data, and a fixed list gives every row the same columns in the same order.

```jq run
[{host: "web01", metric: "cpu", v: 0.5}, {host: "web01", metric: "cpu", v: 0.7}, {host: "web01", metric: "ram", v: 16},
 {host: "db01", metric: "ram", v: 64}, {host: "db01", metric: "disk", v: 1}]
| pivot(["cpu", "ram"]; {host}; .metric; .v; max)
```

`db01` has no `cpu` rows, so its `cpu` is null; its `disk` row is dropped because `disk` is not in the list.

**Review finding 8.** The inner `reduce` appends to an array inside an object, the pattern the comment above `_groups` says is avoided everywhere in this file. Its cost grows with the square of the number of values in one cell: one row key and one column with 20,000 values took 0.5 s, 40,000 took 1.6 s and 80,000 took 5.9 s (jq 1.8.2). With many row keys and few values per cell it is fine (80,000 rows over 5,000 keys: 1.0 s). Grouping by column inside each row group would remove it.
