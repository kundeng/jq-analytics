# Distributions, profiles, diffs

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/distributions-profiles-diffs.md`. Do not edit.

Eight definitions for the first questions asked of a table: which values are common, how a number is spread, whether two numbers move together, what each column holds, and what changed between two versions.

## mode

`mode/0`, line 982:

```jq
# mode: the most frequent non-null value of a list; among equally frequent values the smallest in
# jq's sort order; null when there is none.
def mode: nonnull | if length == 0 then null else group_by(.) | map([-length, .[0]]) | min | .[1] end;
```

The most frequent non-null value.

`group_by(.) | map([-length, .[0]]) | min | .[1]`: each group of equal values becomes `[minus its size, the value]`. The smallest such pair is the largest group, and among groups of the same size the one with the smallest value, because arrays compare element by element. One `min` does both.

```jq
[[3, 1, 3, 1, null, 2], ["b", "a"], [null]] | map(mode)
```

```json
[1,"a",null]
```

1 and 3 both appear twice; the smaller is returned.

## value_counts

`value_counts/0`, lines 986 to 987:

```jq
# value_counts: one row per distinct non-null value of a list: {value, count, share (of the non-null
# values)}, most frequent first, ties by value.
def value_counts:
  nonnull | length as $n | group_by(.) | map({value: .[0], count: length, share: (length / $n)}) | sort_by([-.count, .value]);
```

One row per distinct non-null value, with its count and its share of the non-null values. `sort_by([-.count, .value])` puts the most frequent first and breaks ties by value.

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

## bin_edges, histogram

`bin_edges/3`, lines 990 to 992:

```jq
# bin_edges: $n + 1 equally spaced numbers from $lo to $hi, the edges of $n bins
def bin_edges($lo; $hi; $n):
  if ($hi > $lo and $n >= 1) | not then error("bin_edges: need hi > lo and n >= 1")
  else [range(0; $n + 1) | $lo + ($hi - $lo) * . / $n] end;
```

`histogram/1`, lines 998 to 1011:

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

`bin_edges($lo; $hi; $n)` is `$n + 1` equally spaced numbers; `$lo + ($hi - $lo) * i / $n` computes each from the ends, so the last edge is exactly `$hi`.

`histogram($edges)`:

- **Edges are checked first**: at least two, all numbers, strictly increasing.
- **Each non-null value** must be a number within the edges, or the run stops with an error naming it. A histogram that silently dropped values outside its range would undercount without saying so.
- **Finding the bin.** `($edges | bsearch($v))` gives the position of an edge equal to `$v`, or `-1 - (insertion point)`. Not on an edge: the bin is the one before the insertion point, `-2 - $i`. On an edge: that edge's own bin, `$i`, so a value on a boundary goes to the upper bin; except on the last edge, which has no bin above it and belongs to the last bin, `$i - 1`.
- **Counting.** `.[$b | tostring] += 1` counts per bin in an object; the last line lays the counts out over all bins, with 0 where none fell.

```jq
bin_edges(0; 64; 4) as $e | $e, ([16, 32, 64, 64, 8, null] | histogram($e) | map([.from, .to, .count])),
(try ([70] | histogram($e)) catch .)
```

```json
[0,16,32,48,64]
[[0,16,1],[16,32,1],[32,48,1],[48,64,2]]
"histogram: value 70 is outside the edges"
```

16 and 32 sit on boundaries and go up; the two 64s are on the last edge and stay in the last bin.

## corr

`corr/2`, lines 1015 to 1023:

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

Pearson's correlation over the rows where both values are present.

- `$p`: the pairs `[x, y]` with neither null; `$n` their number. Fewer than two: null.
- `$mx`, `$my`: the means.
- One `reduce` carries three sums: of `dx * dy`, of `dx * dx` and of `dy * dy`, where `dx` and `dy` are the differences from the means.
- The result is the first sum divided by the square root of the product of the other two; null when either of those is 0, which means that side never varies.

```jq
[[1, 2], [2, 4], [3, 6], [4, 9], [5, null]] | map({x: .[0], y: .[1]})
| {corr: (corr(.x; .y) | round_to(4)), exact_line: ([{x: 1, y: 3}, {x: 2, y: 2}, {x: 3, y: 1}] | corr(.x; .y)),
   constant: ([{x: 1, y: 5}, {x: 2, y: 5}] | corr(.x; .y)), one_pair: ([{x: 1, y: 5}] | corr(.x; .y))}
```

```json
{"corr":0.9944,"exact_line":-1,"constant":null,"one_pair":null}
```

Hand check of the first: the means are 2.5 and 5.25; the three sums are 11.5, 5 and 26.75; 11.5 / sqrt(5 × 26.75) = 0.9944.

## profile

`profile/0`, lines 1031 to 1042:

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

One row per column, columns in name order.

- `$cols`: the sorted union of every row's field names.
- For column `$c`: `$pv` is its values over the rows that have the field (nulls included), and `$nn` the non-null ones.
- `present` is the size of `$pv`; `nulls` is all rows minus the non-null ones, so an absent field counts as null; `empty` counts `""`; `distinct` is `$nn | unique | length`.
- `types` counts jq type names over `$pv`.
- `min` and `max` are given only when every non-null value is a number, or every one a string; a column of mixed types has no meaningful smallest value, so both are null.

Each column is one pass over the rows, so the cost is rows times columns.

```jq
[{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64, os: "linux"}, {host: "new01", site: "", ram: "16", os: null}, {host: "x01"}]
| profile | map({column, present, nulls, empty, distinct, types, min, max})
```

```json
[
  {"column": "host", "present": 4, "nulls": 0, "empty": 0, "distinct": 4, "types": {"string": 4}, "min": "db01", "max": "x01"},
  {"column": "os", "present": 3, "nulls": 2, "empty": 0, "distinct": 1, "types": {"null": 1, "string": 2}, "min": "linux", "max": "linux"},
  {"column": "ram", "present": 3, "nulls": 1, "empty": 0, "distinct": 3, "types": {"number": 2, "string": 1}, "min": null, "max": null},
  {"column": "site", "present": 3, "nulls": 1, "empty": 1, "distinct": 3, "types": {"string": 3}, "min": "", "max": "S"}
]
```

`ram` holds two numbers and the string `"16"`, so it has no min or max, and its types say why.

## _diff_index, diff_tables

`_diff_index/2`, lines 1044 to 1048:

```jq
def _diff_index(key; $who):
  reduce .[] as $r ({}; ($r | key) as $k
    | if $k == null then error("diff_tables: a row of the \($who) table has a null key")
      elif has($k | tojson) then error("diff_tables: key \($k | tojson) appears twice in the \($who) table")
      else .[$k | tojson] = $r end);
```

`diff_tables/2`, lines 1056 to 1067:

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

`_diff_index` turns one table into a lookup from key (through `tojson`) to row, and refuses a null key or a key seen twice, naming which table it was in.

`diff_tables`, with the new table as input and the old one as `$old`:

- `$n` and `$o` are the two lookups; `$ks` the sorted union of both tables' keys.
- For each key: only in the new table, `added`; only in the old, `removed`; in both and equal, nothing; otherwise `changed`.
- For a changed row, `fields` is the sorted union of both rows' field names, filtered to those that are present on one side only or have different values.

```jq
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| diff_tables($yesterday; .host) | map({key, change, fields}),
  (try ([{host: "a"}, {host: "a"}] | diff_tables([]; .host)) catch .)
```

```json
[{"key":"new01","change":"added","fields":[]},{"key":"old01","change":"removed","fields":[]},{"key":"web01","change":"changed","fields":["os","ram"]}]
"diff_tables: key \"a\" appears twice in the new table"
```

`web01` changed in `ram` and gained `os`; `db01` is unchanged and absent from the result.
