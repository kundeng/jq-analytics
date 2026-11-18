Thirteen definitions. Two helpers do the work: `_matches` pairs each left row with its right rows, and `_merge` joins one left row to one right row. `join_on` chooses what to emit from those pairs; everything else except `lookup` and `join_asof` is a one-line call of `join_on` or `_matches`.

```mermaid
flowchart LR
  M[_matches: index the right table by key, pair each left row with its matches] --> ON[join_on: emit by kind]
  MG[_merge: one left row + one right row] --> ON
  ON --> EQ[join_inner, join_left, join_full, join_semi, join_anti]
  ON --> OV[join_overlap]
  M --> NEST[join_nest]
  MG --> ASOF[join_asof: own index, sorted by time]
  LK[lookup: own index, one row per key]
```

Two idioms recur and are explained once here:

- **A key goes through `tojson` before it is used as an object key.** jq object keys are strings, so the number `1` and the string `"1"` would otherwise collide, and an array key (a composite key) could not be used at all. `tojson` gives `1`, `"1"` and `[1,"a"]` three different strings.
- **The right table is indexed once.** An object from key to rows is built before the left rows are walked, so the cost is left rows plus right rows, not their product.

## _merge/2
<!-- code: 9dfc51ed -->


Takes a left row `$l` and a right row `$r`; returns one object with the fields of both.

- `reduce ($r | to_entries[]) as $e ($l; …)` starts from the left row and adds the right row's fields one at a time.
- `if has($e.key) and .[$e.key] != $e.value then error(…)`: a field on both sides with different values stops the join and names the field and both values. A plain `$l + $r` would let the right value overwrite the left one without a word.
- `else .[$e.key] = $e.value`: a new field is added; a field with the same value on both sides is set to what it already is, which is how the join key ends up in the output once.

```jq run
_merge({id: 1, k: "a"}; {k: "a", v: 9}),
(try _merge({id: 1, v: 2}; {v: 9}) catch .)
```
## _matches/4
<!-- code: dd80c824 -->


Input: the left table. Returns one entry per left row, in left order: `{l: the row, m: [{key: position in the right table, value: right row}, …]}`. The position is kept because `join_on` needs it for a full join.

- `$right | to_entries` turns the right table into `{key: position, value: row}` pairs.
- `group_by(.value | rkey)` groups them by the right key. `group_by` sorts groups by key but keeps input order inside a group, on every engine, so a left row's matches come out in right-table order.
- `map(select((.[0].value | rkey) != null) | {key: (… | tojson), value: .}) | from_entries` drops the group whose key is null and turns the rest into the index `$ix`: key text to the group's pairs. Dropping the null group is half of "a null key never matches".
- `[.[] as $l | ($l | lkey) as $k | {l: $l, m: […]}]` walks the left rows. `if $k == null then empty` is the other half of the null rule. `$ix[$k | tojson][]?` looks the key up; the `?` makes a missing key give no matches instead of an error.
- `select(.value as $r | {l: $l, r: $r} | cond)` applies the caller's extra condition to the pair. It runs only on pairs that already share a key.

```jq run
[{id: 1, k: "a"}, {id: 2, k: "z"}, {id: 3, k: null}]
| _matches([{k: "a", v: 1}, {k: null, v: 2}, {k: "a", v: 3}]; .k; .k; true)
```
## join_on/5
<!-- code: f2564bd2 -->


The general flat join. Input: the left table. `$kind` chooses what to emit from the pairs `_matches` found:

| kind | emits |
|---|---|
| `inner` | for each left row, one merged row per match |
| `left` | the same, and the left row alone when it has no match |
| `semi` | the left row once when it has any match; no right fields |
| `anti` | the left row when it has no match |
| `full` | the `left` output, then the right rows no left row matched, in right order |

For `full`, `$hit` is an object whose keys are the positions of right rows that matched something (`.key | tostring`, since a position is a number). The unmatched right rows are then the entries whose position is not in `$hit`. Anything else as `$kind` is an error rather than an empty result.

```jq run
[{id: 1, k: "a"}, {id: 2, k: "b"}, {id: 3, k: "z"}] as $l
| [{k: "a", v: "A"}, {k: "b", v: "B1"}, {k: "b", v: "B2"}, {k: "y", v: "Y"}] as $r
| ["inner", "left", "semi", "anti", "full"]
| map({key: ., value: (. as $kind | $l | join_on($r; .k; .k; true; $kind) | map([.id, .v]))}) | from_entries
```

In `full`, the last row is `[null, "Y"]`: the unmatched right row has no `id`. The condition form, a left join of amounts to the bands that contain them:

```jq run
[{id: 1, amount: 5}, {id: 2, amount: 60}, {id: 3, amount: 500}]
| join_on([{lo: 0, hi: 10, band: "small"}, {lo: 10, hi: 100, band: "medium"}];
          true; true; .l.amount >= .r.lo and .l.amount < .r.hi; "left")
| map({id, band})
```

With `true` for both keys every right row is in one group, so every pair is checked: this is the slow form, for small right tables.
## join_inner/3, join_left/3, join_full/3, join_semi/3, join_anti/3
<!-- code: 0a54328b -->


Each is `join_on` with `true` for the condition and its kind fixed. They exist so the common case reads as one word.

```jq run
[{id: 1, k: "a"}, {id: 2, k: "z"}] | join_left([{k: "a", v: 9}]; .k; .k)
```
## join_nest/5
<!-- code: b669d9a4 -->


Every left row exactly once, with field `$as` holding the array of its matching right rows. `.l + {($as): [.m[].value]}` adds one field to the left row, so nothing is merged, no field can clash, and the row count never changes. Use it when the right side is "many" and you want to count or summarise the matches per left row.

```jq run
[{id: 1, k: "a"}, {id: 2, k: "z"}]
| join_nest([{k: "a", v: 1}, {k: "a", v: 2}]; .k; .k; true; "hits")
```
## lookup/4
<!-- code: cdb7e6e2 -->


Attaches one row of a dimension table under field `$as`. It builds its own index because its rule differs from a join's: a key that appears twice in the dimension is an error.

- `$dim | group_by(dkey)` groups the dimension by key; `select((.[0] | dkey) != null)` drops null keys.
- `if length > 1 then error(…)`: two rows with one key stop the lookup, naming the key. The check runs when the index is built, so it fires even when no left row uses that key.
- `map(. as $l | … $l + {($as): …})`: every left row gets the field; a null or unknown key gives `null`.

```jq run
[{id: 1, gid: "g1"}, {id: 2, gid: "g9"}, {id: 3, gid: null}]
| lookup([{gid: "g1", name: "Access"}, {gid: "g2", name: "Devices"}]; .gid; .gid; "group"),
  (try ([{gid: "g1"}] | lookup([{gid: "g1", n: 1}, {gid: "g1", n: 2}]; .gid; .gid; "g")) catch .)
```
## join_overlap/7
<!-- code: ca87eb71 -->


An inner `join_on` whose condition is the overlap test for half-open intervals: `l.start < r.end and r.start < l.end`. Two intervals that only touch (one ends where the other starts) do not overlap. The output is merged rows, so the two sides must not both call their fields `start` and `end` with different values; rename one side first, as in the run.

```jq run
[{room: "A", who: "ann", s: 9, e: 11}, {room: "A", who: "bo", s: 11, e: 12}]
| join_overlap([{room: "A", what: "cleaning", cs: 10, ce: 11}]; .room; .room; .s; .e; .cs; .ce)
```
## join_asof/6, join_asof/5
<!-- code: d3cb4788 -->


For each left row, the right row with the same key and the latest time at or before the left row's time. Left outer: a left row with no such right row comes back alone.

- **The index.** Right rows with a null key or time are dropped, the rest grouped by key; each group is sorted by time and stored as `{rows, t}` where `t` is the array of times alone. Keeping `t` lets `bsearch` run on plain numbers.
- **`($g.t | bsearch($t)) as $i`.** `bsearch` returns the position of an entry equal to `$t` when there is one, and otherwise `-1 - (the position where $t would be inserted)`.
- **`(if $i >= 0 then $i else -2 - $i end) as $last`.** Found: that position. Not found: the insertion point is `-1 - $i`, and the entry before it, `-2 - $i`, is the last one below `$t`; it is `-1` when `$t` is before every entry.
- **`until(. == 0 or $g.t[. - 1] != $g.t[$last]; . - 1)`.** When several right rows have that same time, step back to the first of them. `sort_by` is stable, so that is the first in input order, which is the stated tie rule.
- **The last line.** No entry (`$j < 0`), or an entry older than `$max_age`, gives the left row alone; otherwise the two rows are merged with `_merge`, so a clashing field is an error here too.

The five-parameter form passes `null` for `$max_age`.

```jq run
[{q: 100, k: "a", qt: 2}, {q: 101, k: "a", qt: 10}, {q: 102, k: "a", qt: 10}, {q: 103, k: "a", qt: 14}] as $quotes
| [{id: 1, k: "a", t: 1}, {id: 2, k: "a", t: 10}, {id: 3, k: "a", t: 12}, {id: 4, k: "a", t: 30}, {id: 5, k: "b", t: 30}]
| {latest: (join_asof($quotes; .k; .k; .t; .qt) | map([.id, .q])),
   within_3: (join_asof($quotes; .k; .k; .t; .qt; 3) | map([.id, .q]))}
```

Row 1 is before every quote. Rows 2 and 3 get quote 101, the first of the two at time 10. Row 4 gets 103 with no age limit and nothing within 3. Row 5's key has no quotes.

"Latest value at or before T" is the right question for prices and settings. It is the wrong one for "who held this at T", where the value may have ended before T: use `intervals_from_events` and `join_within`.
