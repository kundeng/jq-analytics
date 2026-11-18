Two definitions. `_groups` is used all over the library (intervals, funnels, shapes); `group_agg` is the public face.

## _groups/1
<!-- code: db705fcd -->

Input: rows. Output: an array of groups, each an array of rows; groups in order of first appearance, rows inside a group in input order.

- `to_entries` pairs each row with its position.
- `group_by(.value | f)` groups by the key. The builtin sorts groups by key and keeps input order inside each group.
- `sort_by(.[0].key)` puts the groups back in order of first appearance: `.[0].key` is the position of a group's first row.
- `map(map(.value))` drops the positions.

The comment explains why this is not written as a `reduce` that appends each row to its group: appending inside a `reduce` copies the growing array each time, so the cost grows with the square of the group's size, and an object keyed by group would come out in a different key order on gojq.

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | _groups(.g)
```

**Review finding 5, fixed in 0.9.0.** The comments of `group_agg`, `intervals_from_events` and `state_blocks` used to sit above their helper functions. Each now sits directly above the function it describes.

## group_agg/2
<!-- code: 2c78cb5d -->

One row per group: the key, plus whatever `aggf` returns for the group's rows.

- `.[0] | keyf` evaluates the key on the group's first row.
- `if type == "object" then . else {key: .} end`: a key written as an object, such as `{site, year}`, becomes those fields; any other key goes in a field called `key`.
- `+ aggf`: `aggf` runs with the group's array of rows as input and must return an object, which is merged in. A field of the same name as a key field would overwrite it.

A null key is a group like any other.

```jq run
[{site: "N", x: 1}, {site: "S", x: 5}, {site: null, x: 7}, {site: "N", x: null}, {site: "N", x: 3}]
| group_agg({site}; map(.x) | {rows: length, n: count_nonnull, mean: mean}),
  group_agg(.site; {rows: length})
```
