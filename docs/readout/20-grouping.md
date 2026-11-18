# Grouping

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/grouping.md`. Do not edit.

Two definitions. `_groups` is used all over the library (intervals, funnels, shapes); `group_agg` is the public face.

## _groups

`_groups/1`, line 165:

```jq
# group rows by keyf and aggregate each group with aggf (applied to the group's array of rows).
# Output: one row per group, in order of first appearance (group_by sorts by key instead).
# A key that is an object is merged into the output row; any other key goes in field "key".
# aggf must return an object. Null keys form one group, as in SQL GROUP BY.
# rows grouped by f: an array of groups in order of first appearance, each group in input order.
# Built on the builtin group_by (a stable sort), then put back in first-appearance order by each
# group's first input position. Appending rows to groups inside a reduce is avoided everywhere in
# this file: it grows with the square of a group's size (measured: 40 times the time for 10 times
# the rows), and an object's key order differs between engines (gojq sorts keys).
def _groups(f): to_entries | group_by(.value | f) | sort_by(.[0].key) | map(map(.value));
```

Input: rows. Output: an array of groups, each an array of rows; groups in order of first appearance, rows inside a group in input order.

- `to_entries` pairs each row with its position.
- `group_by(.value | f)` groups by the key. The builtin sorts groups by key and keeps input order inside each group.
- `sort_by(.[0].key)` puts the groups back in order of first appearance: `.[0].key` is the position of a group's first row.
- `map(map(.value))` drops the positions.

The comment explains why this is not written as a `reduce` that appends each row to its group: appending inside a `reduce` copies the growing array each time, so the cost grows with the square of the group's size, and an object keyed by group would come out in a different key order on gojq.

```jq
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | _groups(.g)
```

```json
[
  [{"g": "b", "x": 1}, {"g": "b", "x": 4}],
  [{"g": "a", "x": 2}],
  [{"g": null, "x": 3}]
]
```

**Review finding 5.** The first four comment lines above `_groups` describe `group_agg`, the function after it. The same happens at `_iv_check` and `intervals_from_events`. Each public function's comment should sit directly above that function.

## group_agg

`group_agg/2`, lines 167 to 168:

```jq
def group_agg(keyf; aggf):
  _groups(keyf) | map((.[0] | keyf | if type == "object" then . else {key: .} end) + aggf);
```

One row per group: the key, plus whatever `aggf` returns for the group's rows.

- `.[0] | keyf` evaluates the key on the group's first row.
- `if type == "object" then . else {key: .} end`: a key written as an object, such as `{site, year}`, becomes those fields; any other key goes in a field called `key`.
- `+ aggf`: `aggf` runs with the group's array of rows as input and must return an object, which is merged in. A field of the same name as a key field would overwrite it.

A null key is a group like any other.

```jq
[{site: "N", x: 1}, {site: "S", x: 5}, {site: null, x: 7}, {site: "N", x: null}, {site: "N", x: 3}]
| group_agg({site}; map(.x) | {rows: length, n: count_nonnull, mean: mean}),
  group_agg(.site; {rows: length})
```

```json
[{"site":"N","rows":3,"n":2,"mean":2},{"site":"S","rows":1,"n":1,"mean":5},{"site":null,"rows":1,"n":1,"mean":7}]
[{"key":"N","rows":3},{"key":"S","rows":1},{"key":null,"rows":1}]
```
