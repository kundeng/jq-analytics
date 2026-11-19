# Distributions, profiles, diffs

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/distributions-profiles-diffs.md`. Do not edit.

Eight definitions for the first questions asked of a table: which values are common, how a number is spread, whether two numbers move together, what each column holds, and what changed between two versions.

The first four take a plain list of values as input, so a column is first pulled out of a table with `map(.field)`. `corr` and `diff_tables` take a table and filter arguments; in jq a `;` separates arguments, and an argument such as `.x` is a filter run on each row.

On this page, in the order of the file:

| Function | Whose | What it is for |
|---|---|---|
| `mode` | Public function | The most frequent non-null value of a list |
| `value_counts` | Public function | One row per distinct non-null value of a list, with its count and its share of the non-null values, most frequent first |
| `bin_edges`, `histogram` | Public functions | A histogram of a list of numbers: how many fall in each bin |
| `corr` | Public function | Pearson's correlation of two columns: 1 when they rise together on a straight line, -1 when one falls as the other rises, near 0 when there is no straight-line relation |
| `profile` | Public function | A first look at a table: one row per column, saying how many rows have it, how many are null or empty, how many distinct values it holds, of which types, and its smallest and largest value |
| `_diff_index`, `diff_tables` | Public functions and internal helpers | `diff_tables` reports what changed between two versions of a table that share a key: one row per key that was added, removed or changed |

---

## mode

**Public function** · `mode`

The most frequent non-null value of a list. SQL has `mode() WITHIN GROUP`; a spreadsheet has `MODE`.

### mode: the example

```jq
[3, 1, 3, 1, null, 2] | mode
```

```json
1
```

1 and 3 both appear twice. On a tie the smallest value in jq's sort order is returned, so the result does not depend on the order of the input.

A list with no non-null value has no mode:

```jq
[["b", "a"], [null], []] | map(mode)
```

```json
["a",null,null]
```

### mode: what happens inside, on the example

Step 1, `nonnull | group_by(.)`: the null dropped, equal values gathered, groups sorted by value.

```jq
[3, 1, 3, 1, null, 2] | nonnull | group_by(.)
```

```json
[
  [1, 1],
  [2],
  [3, 3]
]
```

Step 2, `map([-length, .[0]])`: each group becomes `[minus its size, the value]`.

```jq
[3, 1, 3, 1, null, 2] | nonnull | group_by(.) | map([-length, .[0]])
```

```json
[
  [-2, 1],
  [-1, 2],
  [-2, 3]
]
```

Step 3, `min | .[1]`: arrays compare element by element, so the smallest pair is the largest group, and among groups of the same size the one with the smallest value. Here that is `[-2, 1]`, and its second element is the result.

### mode: the definition

`mode/0`, lines 1094 to 1096:

```jq
# mode: the most frequent non-null value of a list; among equally frequent values the smallest in
# jq's sort order; null when there is none.
def mode: nonnull | if length == 0 then null else group_by(.) | map([-length, .[0]]) | min | .[1] end;
```

Built into jq: `group_by`, `length`, `map`, `min`. From this library: `nonnull`.

One `min` does both the "most frequent" and the tie rule, because the size is negated. `if length == 0 then null` covers the empty case before grouping.

---

## value_counts

**Public function** · `value_counts`

One row per distinct non-null value of a list, with its count and its share of the non-null values, most frequent first. It is SQL's `SELECT v, count(*) ... GROUP BY v ORDER BY 2 DESC`, and what pandas calls `value_counts`.

### value_counts: the example

```jq
["a", "b", "a", "c", null] | value_counts
```

```json
[
  {"value": "a", "count": 2, "share": 0.5},
  {"value": "b", "count": 1, "share": 0.25},
  {"value": "c", "count": 1, "share": 0.25}
]
```

Four non-null values. `a` appears twice, a share of 2 / 4 = 0.5. `b` and `c` tie on count and come in value order. The null is not counted and is not in the divisor.

### value_counts: the definition

`value_counts/0`, lines 1098 to 1101:

```jq
# value_counts: one row per distinct non-null value of a list: {value, count, share (of the non-null
# values)}, most frequent first, ties by value.
def value_counts:
  nonnull | length as $n | group_by(.) | map({value: .[0], count: length, share: (length / $n)}) | sort_by([-.count, .value]);
```

Built into jq: `group_by`, `length`, `map`, `sort_by`. From this library: `nonnull`.

- `nonnull | length as $n` drops nulls and remembers how many values are left. `as` binds `$n` without changing the input.
- `group_by(.) | map({value: .[0], count: length, share: (length / $n)})`: one row per group of equal values.
- `sort_by([-.count, .value])`: highest count first, ties by value.

---

## bin_edges, histogram

**Public functions** · `bin_edges($lo; $hi; $n)`, `histogram($edges)`

A histogram of a list of numbers: how many fall in each bin. `bin_edges($lo; $hi; $n)` makes the edges of `$n` equal bins; `histogram($edges)` counts. A spreadsheet's `FREQUENCY` and numpy's `histogram` do the same.

### bin_edges and the others: the example

Four bins from 0 to 64, and six values, one of them null:

```jq
bin_edges(0; 64; 4) as $e
| $e, ([16, 32, 64, 64, 8, null] | histogram($e))
```

```json
[0,16,32,48,64]
[{"from":0,"to":16,"count":1},{"from":16,"to":32,"count":1},{"from":32,"to":48,"count":1},{"from":48,"to":64,"count":2}]
```

Two values: the five edges, then one row per bin. A bin holds `from <= v < to`, so 16 and 32, which sit on edges, go to the bin above. The last bin also holds its upper edge, so the two 64s are in 48 to 64. The null is skipped.

Refused: a value outside the edges, edges that are not increasing, and a `bin_edges` call with `hi` not above `lo`. A histogram that dropped out-of-range values would undercount without saying so.

```jq
(try ([70] | histogram([0, 16, 32, 48, 64])) catch .),
(try ([1] | histogram([0, 16, 16])) catch .),
(try bin_edges(5; 5; 4) catch .)
```

```json
"histogram: value 70 is outside the edges"
"histogram: edges must be at least two increasing numbers"
"bin_edges: need hi > lo and n >= 1"
```

### bin_edges and the others: what happens inside, on the example

Step 1: the edges are checked: at least two, all numbers, each above the one before.

Step 2: each value is placed in a bin by a binary search of the edges. jq's `bsearch` returns the position of an edge equal to the value, or `-1 - (where it would be inserted)` when there is none. The run shows the search result and the bin number for the five non-null values.

```jq
[0, 16, 32, 48, 64] as $e
| [16, 32, 64, 64, 8]
| map(. as $v | ($e | bsearch($v)) as $i | {v: $v, bsearch: $i, bin: (if $i < 0 then -2 - $i elif $i == 4 then $i - 1 else $i end)})
```

```json
[
  {"v": 16, "bsearch": 1, "bin": 1},
  {"v": 32, "bsearch": 2, "bin": 2},
  {"v": 64, "bsearch": 4, "bin": 3},
  {"v": 64, "bsearch": 4, "bin": 3},
  {"v": 8, "bsearch": -2, "bin": 0}
]
```

16 is edge 1 and goes to bin 1, the bin that starts there. 64 is the last edge, 4, which has no bin above it, so it goes to bin 3. 8 is not an edge: it would be inserted at position 1, `bsearch` gives -2, and `-2 - (-2)` is bin 0.

Step 3: the counts per bin number are 1, 1, 1 and 2, and the last line lays them out over all bins with their edges, with 0 for a bin nothing fell in.

### bin_edges and the others: the definition

`bin_edges/3`, lines 1103 to 1106:

```jq
# bin_edges: $n + 1 equally spaced numbers from $lo to $hi, the edges of $n bins
def bin_edges($lo; $hi; $n):
  if ($hi > $lo and $n >= 1) | not then error("bin_edges: need hi > lo and n >= 1")
  else [range(0; $n + 1) | $lo + ($hi - $lo) * . / $n] end;
```

Built into jq: `error`, `not`, `range`.

`histogram/1`, lines 1108 to 1125:

```jq
# histogram: counts of a list of numbers per bin, the bins given by their edges (bin_edges, or any
# increasing list): one row per bin {from, to, count}. A bin holds from <= v < to, and the last bin
# also holds v == to, as numpy's histogram does. Nulls are skipped. A value outside the edges is an
# error, not a dropped value; so are edges that are not at least two increasing numbers.
def histogram($edges):
  ($edges | length) as $k
  | if $k < 2 or ($edges | any(type != "number")) or ([range(1; $k) | select($edges[.] <= $edges[. - 1])] | length) > 0
    then error("histogram: edges must be at least two increasing numbers")
    else
    (reduce (nonnull[]) as $v ({};
       if ($v | type) != "number" or $v < $edges[0] or $v > $edges[$k - 1]
       then error("histogram: value \($v | tojson) is outside the edges")
       else ($edges | bsearch($v)) as $i
         | (if $i < 0 then -2 - $i elif $i == $k - 1 then $i - 1 else $i end) as $b
         | .[$b | tostring] += 1
       end)) as $c
    | [range(0; $k - 1) | {from: $edges[.], to: $edges[. + 1], count: ($c[tostring] // 0)}]
    end;
```

Built into jq: `any`, `bsearch`, `error`, `length`, `range`, `select`, `tojson`, `tostring`, `type`. From this library: `nonnull`.

- `bin_edges`: `$lo + ($hi - $lo) * . / $n` computes each edge from the two ends, so the last edge is exactly `$hi`.
- `[range(1; $k) | select($edges[.] <= $edges[. - 1])] | length) > 0` finds an edge that is not above the one before.
- `reduce (nonnull[]) as $v ({}; ...)` counts into an object keyed by bin number, `.[$b | tostring] += 1`.
- `if ($v | type) != "number" or $v < $edges[0] or $v > $edges[$k - 1]` is the out-of-range error.
- `$c[tostring] // 0` reads a bin's count, 0 when the bin has no entry.

---

## corr

**Public function** · `corr(x; y)`

Pearson's correlation of two columns: 1 when they rise together on a straight line, -1 when one falls as the other rises, near 0 when there is no straight-line relation. It matches SQL's `corr(y, x)` and a spreadsheet's `CORREL`.

### corr: the example

| x | y |
|---|---|
| 1 | 1 |
| 2 | 3 |
| 3 | 2 |
| 4 | null |

```jq
[[1, 1], [2, 3], [3, 2], [4, null]] | map({x: .[0], y: .[1]}) | corr(.x; .y)
```

```json
0.5
```

The fourth row has no y and is left out. The other three give 0.5; the hand check is below.

Three edge cases: an exact falling line, a side that never varies, and a single pair.

```jq
([{x: 1, y: 3}, {x: 2, y: 2}, {x: 3, y: 1}] | corr(.x; .y)),
([{x: 1, y: 5}, {x: 2, y: 5}] | corr(.x; .y)),
([{x: 1, y: 5}] | corr(.x; .y))
```

```json
-1
null
null
```

### corr: what happens inside, on the example

Step 1, `$p`: the pairs `[x, y]` where neither is null.

```jq
[[1, 1], [2, 3], [3, 2], [4, null]] | map({x: .[0], y: .[1]}) | [.[] | [(.x), (.y)] | select(.[0] != null and .[1] != null)]
```

```json
[
  [1, 1],
  [2, 3],
  [3, 2]
]
```

Step 2: the means. Both are (1 + 2 + 3) / 3 = 2.

Step 3: one pass carries three sums: of `dx * dy`, of `dx * dx` and of `dy * dy`, where `dx` and `dy` are each pair's differences from the means.

```jq
[[1, 1], [2, 3], [3, 2]]
| reduce .[] as $q ([0, 0, 0]; ($q[0] - 2) as $dx | ($q[1] - 2) as $dy | [.[0] + $dx * $dy, .[1] + $dx * $dx, .[2] + $dy * $dy])
```

```json
[1,2,2]
```

By hand: the differences are (-1, -1), (0, 1) and (1, 0). The products sum to 1 + 0 + 0 = 1, the squares of dx to 2, the squares of dy to 2.

Step 4: the first sum divided by the square root of the product of the other two: 1 / sqrt(2 × 2) = 0.5.

### corr: the definition

`corr/2`, lines 1127 to 1137:

```jq
# corr: Pearson's correlation of x and y over the rows where both are non-null; null with fewer than
# two such rows, or when either side does not vary. Matches SQL's corr.
def corr(x; y):
  [.[] | [(x), (y)] | select(.[0] != null and .[1] != null)] as $p
  | ($p | length) as $n
  | if $n < 2 then null
    else (($p | map(.[0]) | add) / $n) as $mx | (($p | map(.[1]) | add) / $n) as $my
    | (reduce $p[] as $q ([0, 0, 0];
         ($q[0] - $mx) as $dx | ($q[1] - $my) as $dy | [.[0] + $dx * $dy, .[1] + $dx * $dx, .[2] + $dy * $dy])) as $s
    | if $s[1] == 0 or $s[2] == 0 then null else $s[0] / (($s[1] * $s[2]) | sqrt) end
    end;
```

Built into jq: `add`, `length`, `map`, `select`, `sqrt`.

- `if $n < 2 then null`: one pair has no spread to compare.
- `$mx`, `$my` are the means of step 2.
- `if $s[1] == 0 or $s[2] == 0 then null`: a sum of squares of 0 means that side never varies, and the division would be by 0.

---

## profile

**Public function** · `profile`

A first look at a table: one row per column, saying how many rows have it, how many are null or empty, how many distinct values it holds, of which types, and its smallest and largest value.

### profile: the example

Four made-up host rows with the usual defects: an empty string, a number stored as text, a null, a missing field.

| host | site | ram |
|---|---|---|
| web01 | N | 32 |
| db01 | S | 64 |
| new01 | "" | "16" |
| x01 | (absent) | null |

```jq
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| profile
```

```json
[
  {"column": "host", "rows": 4, "present": 4, "nulls": 0, "empty": 0, "distinct": 4, "types": {"string": 4}, "min": "db01", "max": "x01"},
  {"column": "ram", "rows": 4, "present": 4, "nulls": 1, "empty": 0, "distinct": 3, "types": {"null": 1, "number": 2, "string": 1}, "min": null, "max": null},
  {"column": "site", "rows": 4, "present": 3, "nulls": 1, "empty": 1, "distinct": 3, "types": {"string": 3}, "min": "", "max": "S"}
]
```

Three rows, in column-name order. `ram` holds two numbers, one string and one null: `types` says so, and `min` and `max` are null because numbers and strings have no common order worth reporting. `site` is present on three rows of four; the absent one counts under `nulls`, and the empty string under `empty`. An empty string is still a value, so it counts in `distinct` and is the `min`.

### profile: what happens inside, on the example

Step 1, `$cols`: every field name of every row, sorted, repeats removed.

```jq
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| [.[] | keys[]] | unique
```

```json
["host","ram","site"]
```

Step 2, per column, three lists. For `ram` the run prints `$pv`, the values on the rows that have the field; `$nn`, the non-null ones; and `$ts`, the distinct types among them.

```jq
[{host: "web01", site: "N", ram: 32}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "", ram: "16"}, {host: "x01", ram: null}]
| [.[] | select(has("ram")) | .ram] as $pv
| $pv, ($pv | map(select(. != null))), ($pv | map(select(. != null)) | map(type) | unique)
```

```json
[32,64,"16",null]
[32,64,"16"]
["number","string"]
```

Step 3: the output row is counted from those lists. For `ram`: `present` 4 (the size of `$pv`), `nulls` 4 - 3 = 1, `distinct` 3, and no `min` or `max` because `$ts` has two types.

### profile: the definition

`profile/0`, lines 1139 to 1156:

```jq
# profile: one row per column of a table, columns in name order:
#   {column, rows (rows in the table), present (rows that have the field), nulls (rows where it is
#    null or absent), empty (rows where it is ""), distinct (distinct non-null values),
#    types (jq type name -> count, over the rows that have the field),
#    min, max (the smallest and largest non-null value when all non-null values are numbers or all
#    are strings; null otherwise)}
def profile:
  . as $rows | length as $n
  | ([.[] | keys[]] | unique) as $cols
  | [$cols[] as $c
     | [$rows[] | select(has($c)) | .[$c]] as $pv
     | ($pv | map(select(. != null))) as $nn
     | ($nn | map(type) | unique) as $ts
     | {column: $c, rows: $n, present: ($pv | length), nulls: ($n - ($nn | length)),
        empty: ($nn | map(select(. == "")) | length), distinct: ($nn | unique | length),
        types: ($pv | group_by(type) | map({key: (.[0] | type), value: length}) | from_entries),
        min: (if $ts == ["number"] or $ts == ["string"] then ($nn | min) else null end),
        max: (if $ts == ["number"] or $ts == ["string"] then ($nn | max) else null end)}];
```

Built into jq: `from_entries`, `group_by`, `has`, `keys`, `length`, `map`, `max`, `min`, `select`, `type`, `unique`.

- `nulls` is all rows minus the non-null values, so an absent field counts as null.
- `types` groups `$pv` by jq type name and counts, nulls included.
- `min` and `max` are given only when `$ts` is exactly `["number"]` or `["string"]`.
- Each column is one pass over the rows, so the cost grows with rows times columns.

---

## _diff_index, diff_tables

**Public functions and internal helpers** · `_diff_index(key; $who)`, `diff_tables($old; key)`

`diff_tables` reports what changed between two versions of a table that share a key: one row per key that was added, removed or changed. The input is the new table and `$old` is the old one. `_diff_index` is its helper: a table as a lookup from key to row.

### _diff_index and the others: the example

Yesterday's hosts:

| host | site | ram |
|---|---|---|
| web01 | N | 16 |
| db01 | S | 64 |
| old01 | N | 8 |

Today's: `web01` has more memory and a new field `os`, `db01` is the same, `old01` is gone, `new01` is new.

```jq
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| diff_tables($yesterday; .host)
```

```json
[
  {"key": "new01", "change": "added", "fields": [], "old": null, "new": {"host": "new01", "site": "N", "ram": 16}},
  {"key": "old01", "change": "removed", "fields": [], "old": {"host": "old01", "site": "N", "ram": 8}, "new": null},
  {"key": "web01", "change": "changed", "fields": ["os", "ram"], "old": {"host": "web01", "site": "N", "ram": 16}, "new": {"host": "web01", "site": "N", "ram": 32, "os": "linux"}}
]
```

Three rows, sorted by key. `new01` is `added` and has no old row; `old01` is `removed` and has no new row. `web01` is `changed`, and `fields` names what differs: `ram` has another value, and `os` exists on one side only. `db01` is unchanged and left out.

A key that appears twice in either table, or a null key, is refused, and the message says which table:

```jq
(try ([{host: "a"}, {host: "a"}] | diff_tables([]; .host)) catch .),
(try ([{host: "a"}] | diff_tables([{host: null}]; .host)) catch .)
```

```json
"diff_tables: key \"a\" appears twice in the new table"
"diff_tables: a row of the old table has a null key"
```

### _diff_index and the others: what happens inside, on the example

Step 1: `_diff_index` on each table. For the new one, `$n`, a lookup from the key as JSON text to the row; the old one, `$o`, is built the same way.

```jq
[{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| _diff_index(.host; "new")
```

```json
{
  "\"web01\"": {"host": "web01", "site": "N", "ram": 32, "os": "linux"},
  "\"db01\"": {"host": "db01", "site": "S", "ram": 64},
  "\"new01\"": {"host": "new01", "site": "N", "ram": 16}
}
```

Step 2, `$ks`: the keys of both tables, sorted, repeats removed.

```jq
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| [.[] | .host] + [$yesterday[] | .host] | unique
```

```json
["db01","new01","old01","web01"]
```

Step 3: each key is looked up in both. A hand trace:

| Key | In new | In old | Outcome |
|---|---|---|---|
| db01 | yes | yes, equal | no row |
| new01 | yes | no | added |
| old01 | no | yes | removed |
| web01 | yes | yes, different | changed; fields os and ram |

### _diff_index and the others: the definition

`_diff_index/2`, lines 1158 to 1162:

```jq
def _diff_index(key; $who):
  reduce .[] as $r ({}; ($r | key) as $k
    | if $k == null then error("diff_tables: a row of the \($who) table has a null key")
      elif has($k | tojson) then error("diff_tables: key \($k | tojson) appears twice in the \($who) table")
      else .[$k | tojson] = $r end);
```

Built into jq: `error`, `has`, `tojson`.

`diff_tables/2`, lines 1164 to 1181:

```jq
# diff_tables: what changed between two versions of a table that share a key. The input is the new
# table, $old the old one. One row per key that was added, removed or changed, sorted by key:
# {key, change ("added", "removed" or "changed"), fields (for a changed row, the fields whose values
# differ, in name order; a field present on one side only counts), old, new (the rows; null on the
# side that has none)}. Unchanged rows are left out. A key that appears twice in either table, or
# a null key, is an error.
def diff_tables($old; key):
  _diff_index(key; "new") as $n | ($old | _diff_index(key; "old")) as $o
  | ([.[] | key] + [$old[] | key] | unique) as $ks
  | [$ks[] as $k | ($k | tojson) as $j | $n[$j] as $a | $o[$j] as $b
     | if $b == null then {key: $k, change: "added", fields: [], old: null, new: $a}
       elif $a == null then {key: $k, change: "removed", fields: [], old: $b, new: null}
       elif $a == $b then empty
       else {key: $k, change: "changed",
             fields: ([($a | keys[]), ($b | keys[])] | unique
                      | map(select(. as $f | ($a | has($f)) != ($b | has($f)) or $a[$f] != $b[$f]))),
             old: $b, new: $a}
       end];
```

Built into jq: `empty`, `has`, `keys`, `map`, `select`, `tojson`, `unique`. From this library: `_diff_index`.

- `_diff_index`: a `reduce` that writes each row under its key's JSON text. `if $k == null` and `elif has($k | tojson)` are the two errors; `$who` is "new" or "old".
- `$n[$j] as $a | $o[$j] as $b`: the new and old row for a key, null when that table lacks it.
- `elif $a == $b then empty`: equal rows emit nothing.
- `fields`: `[($a | keys[]), ($b | keys[])] | unique` is the field names of both rows. `select(... ($a | has($f)) != ($b | has($f)) or $a[$f] != $b[$f])` keeps a field that is on one side only or has different values.
