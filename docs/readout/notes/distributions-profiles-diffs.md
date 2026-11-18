Eight definitions for the first questions asked of a table: which values are common, how a number is spread, whether two numbers move together, what each column holds, and what changed between two versions.

## mode/0
<!-- code: 9f8c2210 -->

The most frequent non-null value.

`group_by(.) | map([-length, .[0]]) | min | .[1]`: each group of equal values becomes `[minus its size, the value]`. The smallest such pair is the largest group, and among groups of the same size the one with the smallest value, because arrays compare element by element. One `min` does both.

```jq run
[[3, 1, 3, 1, null, 2], ["b", "a"], [null]] | map(mode)
```

1 and 3 both appear twice; the smaller is returned.

## value_counts/0
<!-- code: fe09028c -->

One row per distinct non-null value, with its count and its share of the non-null values. `sort_by([-.count, .value])` puts the most frequent first and breaks ties by value.

```jq run
["a", "b", "a", "c", null] | value_counts
```

## bin_edges/3, histogram/1
<!-- code: f37385df -->

`bin_edges($lo; $hi; $n)` is `$n + 1` equally spaced numbers; `$lo + ($hi - $lo) * i / $n` computes each from the ends, so the last edge is exactly `$hi`.

`histogram($edges)`:

- **Edges are checked first**: at least two, all numbers, strictly increasing.
- **Each non-null value** must be a number within the edges, or the run stops with an error naming it. A histogram that silently dropped values outside its range would undercount without saying so.
- **Finding the bin.** `($edges | bsearch($v))` gives the position of an edge equal to `$v`, or `-1 - (insertion point)`. Not on an edge: the bin is the one before the insertion point, `-2 - $i`. On an edge: that edge's own bin, `$i`, so a value on a boundary goes to the upper bin; except on the last edge, which has no bin above it and belongs to the last bin, `$i - 1`.
- **Counting.** `.[$b | tostring] += 1` counts per bin in an object; the last line lays the counts out over all bins, with 0 where none fell.

```jq run
bin_edges(0; 64; 4) as $e | $e, ([16, 32, 64, 64, 8, null] | histogram($e) | map([.from, .to, .count])),
(try ([70] | histogram($e)) catch .)
```

16 and 32 sit on boundaries and go up; the two 64s are on the last edge and stay in the last bin.

## corr/2
<!-- code: ba2570e9 -->

Pearson's correlation over the rows where both values are present.

- `$p`: the pairs `[x, y]` with neither null; `$n` their number. Fewer than two: null.
- `$mx`, `$my`: the means.
- One `reduce` carries three sums: of `dx * dy`, of `dx * dx` and of `dy * dy`, where `dx` and `dy` are the differences from the means.
- The result is the first sum divided by the square root of the product of the other two; null when either of those is 0, which means that side never varies.

```jq run
[[1, 2], [2, 4], [3, 6], [4, 9], [5, null]] | map({x: .[0], y: .[1]})
| {corr: (corr(.x; .y) | round_to(4)), exact_line: ([{x: 1, y: 3}, {x: 2, y: 2}, {x: 3, y: 1}] | corr(.x; .y)),
   constant: ([{x: 1, y: 5}, {x: 2, y: 5}] | corr(.x; .y)), one_pair: ([{x: 1, y: 5}] | corr(.x; .y))}
```

Hand check of the first: the means are 2.5 and 5.25; the three sums are 11.5, 5 and 26.75; 11.5 / sqrt(5 × 26.75) = 0.9944.

## profile/0
<!-- code: 567b502b -->

One row per column, columns in name order.

- `$cols`: the sorted union of every row's field names.
- For column `$c`: `$pv` is its values over the rows that have the field (nulls included), and `$nn` the non-null ones.
- `present` is the size of `$pv`; `nulls` is all rows minus the non-null ones, so an absent field counts as null; `empty` counts `""`; `distinct` is `$nn | unique | length`.
- `types` counts jq type names over `$pv`.
- `min` and `max` are given only when every non-null value is a number, or every one a string; a column of mixed types has no meaningful smallest value, so both are null.

Each column is one pass over the rows, so the cost is rows times columns.

```jq run
[{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64, os: "linux"}, {host: "new01", site: "", ram: "16", os: null}, {host: "x01"}]
| profile | map({column, present, nulls, empty, distinct, types, min, max})
```

`ram` holds two numbers and the string `"16"`, so it has no min or max, and its types say why.

## _diff_index/2, diff_tables/2
<!-- code: 24dd34d0 -->

`_diff_index` turns one table into a lookup from key (through `tojson`) to row, and refuses a null key or a key seen twice, naming which table it was in.

`diff_tables`, with the new table as input and the old one as `$old`:

- `$n` and `$o` are the two lookups; `$ks` the sorted union of both tables' keys.
- For each key: only in the new table, `added`; only in the old, `removed`; in both and equal, nothing; otherwise `changed`.
- For a changed row, `fields` is the sorted union of both rows' field names, filtered to those that are present on one side only or have different values.

```jq run
[{host: "web01", site: "N", ram: 16}, {host: "db01", site: "S", ram: 64}, {host: "old01", site: "N", ram: 8}] as $yesterday
| [{host: "web01", site: "N", ram: 32, os: "linux"}, {host: "db01", site: "S", ram: 64}, {host: "new01", site: "N", ram: 16}]
| diff_tables($yesterday; .host) | map({key, change, fields}),
  (try ([{host: "a"}, {host: "a"}] | diff_tables([]; .host)) catch .)
```

`web01` changed in `ram` and gained `os`; `db01` is unchanged and absent from the result.
