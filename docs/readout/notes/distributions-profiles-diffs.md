Eight definitions for the first questions asked of a table: which values are common, how a number is spread, whether two numbers move together, what each column holds, and what changed between two versions.

The first four take a plain list of values as input, so a column is first pulled out of a table with `map(.field)`. `corr` and `diff_tables` take a table and filter arguments; in jq a `;` separates arguments, and an argument such as `.x` is a filter run on each row.

## mode/0
<!-- code: 8146f90d -->

The most frequent non-null value of a list. SQL has `mode() WITHIN GROUP`; a spreadsheet has `MODE`.

### The example

```jq run
[3, 1, 3, 1, null, 2] | mode
```

1 and 3 both appear twice. On a tie the smallest value in jq's sort order is returned, so the result does not depend on the order of the input.

A list with no non-null value has no mode:

```jq run
[["b", "a"], [null], []] | map(mode)
```

### What happens inside, on the example

Step 1, `nonnull | group_by(.)`: the null dropped, equal values gathered, groups sorted by value.

```jq run
[3, 1, 3, 1, null, 2] | nonnull | group_by(.)
```

Step 2, `map([-length, .[0]])`: each group becomes `[minus its size, the value]`.

```jq run
[3, 1, 3, 1, null, 2] | nonnull | group_by(.) | map([-length, .[0]])
```

Step 3, `min | .[1]`: arrays compare element by element, so the smallest pair is the largest group, and among groups of the same size the one with the smallest value. Here that is `[-2, 1]`, and its second element is the result.

### The definition

<!-- definition -->

One `min` does both the "most frequent" and the tie rule, because the size is negated. `if length == 0 then null` covers the empty case before grouping.

## value_counts/0
<!-- code: 22da6115 -->

One row per distinct non-null value of a list, with its count and its share of the non-null values, most frequent first. It is SQL's `SELECT v, count(*) ... GROUP BY v ORDER BY 2 DESC`, and what pandas calls `value_counts`.

### The example

```jq run
["a", "b", "a", "c", null] | value_counts
```

Four non-null values. `a` appears twice, a share of 2 / 4 = 0.5. `b` and `c` tie on count and come in value order. The null is not counted and is not in the divisor.

### The definition

<!-- definition -->

- `nonnull | length as $n` drops nulls and remembers how many values are left. `as` binds `$n` without changing the input.
- `group_by(.) | map({value: .[0], count: length, share: (length / $n)})`: one row per group of equal values.
- `sort_by([-.count, .value])`: highest count first, ties by value.

## bin_edges/3, histogram/1
<!-- code: bd27b4a5 -->

A histogram of a list of numbers: how many fall in each bin. `bin_edges($lo; $hi; $n)` makes the edges of `$n` equal bins; `histogram($edges)` counts. A spreadsheet's `FREQUENCY` and numpy's `histogram` do the same.

### The example

Four bins from 0 to 64, and six values, one of them null:

```jq run
bin_edges(0; 64; 4) as $e
| $e, ([16, 32, 64, 64, 8, null] | histogram($e))
```

Two values: the five edges, then one row per bin. A bin holds `from <= v < to`, so 16 and 32, which sit on edges, go to the bin above. The last bin also holds its upper edge, so the two 64s are in 48 to 64. The null is skipped.

Refused: a value outside the edges, edges that are not increasing, and a `bin_edges` call with `hi` not above `lo`. A histogram that dropped out-of-range values would undercount without saying so.

```jq run
(try ([70] | histogram([0, 16, 32, 48, 64])) catch .),
(try ([1] | histogram([0, 16, 16])) catch .),
(try bin_edges(5; 5; 4) catch .)
```

### What happens inside, on the example

Step 1: the edges are checked: at least two, all numbers, each above the one before.

Step 2: each value is placed in a bin by a binary search of the edges. jq's `bsearch` returns the position of an edge equal to the value, or `-1 - (where it would be inserted)` when there is none. The run shows the search result and the bin number for the five non-null values.

```jq run
[0, 16, 32, 48, 64] as $e
| [16, 32, 64, 64, 8]
| map(. as $v | ($e | bsearch($v)) as $i | {v: $v, bsearch: $i, bin: (if $i < 0 then -2 - $i elif $i == 4 then $i - 1 else $i end)})
```

16 is edge 1 and goes to bin 1, the bin that starts there. 64 is the last edge, 4, which has no bin above it, so it goes to bin 3. 8 is not an edge: it would be inserted at position 1, `bsearch` gives -2, and `-2 - (-2)` is bin 0.

Step 3: the counts per bin number are 1, 1, 1 and 2, and the last line lays them out over all bins with their edges, with 0 for a bin nothing fell in.

### The definition

<!-- definition -->

- `bin_edges`: `$lo + ($hi - $lo) * . / $n` computes each edge from the two ends, so the last edge is exactly `$hi`.
- `[range(1; $k) | select($edges[.] <= $edges[. - 1])] | length) > 0` finds an edge that is not above the one before.
- `reduce (nonnull[]) as $v ({}; ...)` counts into an object keyed by bin number, `.[$b | tostring] += 1`.
- `if ($v | type) != "number" or $v < $edges[0] or $v > $edges[$k - 1]` is the out-of-range error.
- `$c[tostring] // 0` reads a bin's count, 0 when the bin has no entry.

## corr/2
<!-- code: 4f91a295 -->

Pearson's correlation of two columns: 1 when they rise together on a straight line, -1 when one falls as the other rises, near 0 when there is no straight-line relation. It matches SQL's `corr(y, x)` and a spreadsheet's `CORREL`.

### The example

| x | y |
|---|---|
| 1 | 1 |
| 2 | 3 |
| 3 | 2 |
| 4 | null |

```jq run
[[1, 1], [2, 3], [3, 2], [4, null]] | map({x: .[0], y: .[1]}) | corr(.x; .y)
```

The fourth row has no y and is left out. The other three give 0.5; the hand check is below.

Three edge cases: an exact falling line, a side that never varies, and a single pair.

```jq run
([{x: 1, y: 3}, {x: 2, y: 2}, {x: 3, y: 1}] | corr(.x; .y)),
([{x: 1, y: 5}, {x: 2, y: 5}] | corr(.x; .y)),
([{x: 1, y: 5}] | corr(.x; .y))
```

### What happens inside, on the example

Step 1, `$p`: the pairs `[x, y]` where neither is null.

```jq run
[[1, 1], [2, 3], [3, 2], [4, null]] | map({x: .[0], y: .[1]}) | [.[] | [(.x), (.y)] | select(.[0] != null and .[1] != null)]
```

Step 2: the means. Both are (1 + 2 + 3) / 3 = 2.

Step 3: one pass carries three sums: of `dx * dy`, of `dx * dx` and of `dy * dy`, where `dx` and `dy` are each pair's differences from the means.

```jq run
[[1, 1], [2, 3], [3, 2]]
| reduce .[] as $q ([0, 0, 0]; ($q[0] - 2) as $dx | ($q[1] - 2) as $dy | [.[0] + $dx * $dy, .[1] + $dx * $dx, .[2] + $dy * $dy])
```

By hand: the differences are (-1, -1), (0, 1) and (1, 0). The products sum to 1 + 0 + 0 = 1, the squares of dx to 2, the squares of dy to 2.

Step 4: the first sum divided by the square root of the product of the other two: 1 / sqrt(2 × 2) = 0.5.

### The definition

<!-- definition -->

- `if $n < 2 then null`: one pair has no spread to compare.
- `$mx`, `$my` are the means of step 2.
- `if $s[1] == 0 or $s[2] == 0 then null`: a sum of squares of 0 means that side never varies, and the division would be by 0.

## profile/0
<!-- code: 98412ab7 -->

A first look at a table: one row per column, saying how many rows have it, how many are null or empty, how many distinct values it holds, of which types, and its smallest and largest value.

### The example

Four made-up host rows with the usual defects: an empty string, a number stored as text, a null, a missing field.

| host | site | ram |
|---|---|---|
| web01 | N | 32 |
| db01 | S | 64 |
| new01 | "" | "16" |
| x01 | (absent) | null |

```jq run
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| profile
```

Three rows, in column-name order. `ram` holds two numbers, one string and one null: `types` says so, and `min` and `max` are null because numbers and strings have no common order worth reporting. `site` is present on three rows of four; the absent one counts under `nulls`, and the empty string under `empty`. An empty string is still a value, so it counts in `distinct` and is the `min`.

### What happens inside, on the example

Step 1, `$cols`: every field name of every row, sorted, repeats removed.

```jq run
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| [.[] | keys[]] | unique
```

Step 2, per column, three lists. For `ram` the run prints `$pv`, the values on the rows that have the field; `$nn`, the non-null ones; and `$ts`, the distinct types among them.

```jq run
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| [.[] | select(has("ram")) | .ram] as $pv
| $pv, ($pv | map(select(. != null))), ($pv | map(select(. != null)) | map(type) | unique)
```

Step 3: the output row is counted from those lists. For `ram`: `present` 4 (the size of `$pv`), `nulls` 4 - 3 = 1, `distinct` 3, and no `min` or `max` because `$ts` has two types.

### The definition

<!-- definition -->

- `nulls` is all rows minus the non-null values, so an absent field counts as null.
- `types` groups `$pv` by jq type name and counts, nulls included.
- `min` and `max` are given only when `$ts` is exactly `["number"]` or `["string"]`.
- Each column is one pass over the rows, so the cost grows with rows times columns.

## _diff_index/2, diff_tables/2
<!-- code: 578d7b70 -->

`diff_tables` reports what changed between two versions of a table that share a key: one row per key that was added, removed or changed. The input is the new table and `$old` is the old one. `_diff_index` is its helper: a table as a lookup from key to row.

### The example

Yesterday's hosts:

| host | site | ram |
|---|---|---|
| web01 | N | 16 |
| db01 | S | 64 |
| old01 | N | 8 |

Today's: `web01` has more memory and a new field `os`, `db01` is the same, `old01` is gone, `new01` is new.

```jq run
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| diff_tables($yesterday; .host)
```

Three rows, sorted by key. `new01` is `added` and has no old row; `old01` is `removed` and has no new row. `web01` is `changed`, and `fields` names what differs: `ram` has another value, and `os` exists on one side only. `db01` is unchanged and left out.

A key that appears twice in either table, or a null key, is refused, and the message says which table:

```jq run
(try ([{host: "a"}, {host: "a"}] | diff_tables([]; .host)) catch .),
(try ([{host: "a"}] | diff_tables([{host: null}]; .host)) catch .)
```

### What happens inside, on the example

Step 1: `_diff_index` on each table. For the new one, `$n`, a lookup from the key as JSON text to the row; the old one, `$o`, is built the same way.

```jq run
[{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| _diff_index(.host; "new")
```

Step 2, `$ks`: the keys of both tables, sorted, repeats removed.

```jq run
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| [.[] | .host] + [$yesterday[] | .host] | unique
```

Step 3: each key is looked up in both. A hand trace:

| Key | In new | In old | Outcome |
|---|---|---|---|
| db01 | yes | yes, equal | no row |
| new01 | yes | no | added |
| old01 | no | yes | removed |
| web01 | yes | yes, different | changed; fields os and ram |

### The definition

<!-- definition -->

- `_diff_index`: a `reduce` that writes each row under its key's JSON text. `if $k == null` and `elif has($k | tojson)` are the two errors; `$who` is "new" or "old".
- `$n[$j] as $a | $o[$j] as $b`: the new and old row for a key, null when that table lacks it.
- `elif $a == $b then empty`: equal rows emit nothing.
- `fields`: `[($a | keys[]), ($b | keys[])] | unique` is the field names of both rows. `select(... ($a | has($f)) != ($b | has($f)) or $a[$f] != $b[$f])` keeps a field that is on one side only or has different values.
