# Several tables at once

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/several-tables-at-once.md`. Do not edit.

Three small definitions for a program that carries several tables in one object, `{leases: […], hits: […]}`, usually because the host can hand it only one stream of rows with a field saying which table each row belongs to.

## split_by

`split_by/1`, line 179:

```jq
# split a stream of rows into an object of tables by a tag: rows with the same tagf value form one table,
# named by that value as a string (a null tag gives the table "null"). A host that can pass only one
# stream hands over several tables this way: one stream, with a field saying which table each row belongs to.
def split_by(tagf): _groups(tagf) | map({key: (.[0] | tagf | tostring), value: .}) | from_entries;
```

Rows to an object of tables. `_groups(tagf)` makes the groups; each becomes an entry whose name is the tag as text (`tostring`), and `from_entries` builds the object.

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type) | map_values(length)
```

```json
{"lease":2,"hit":1,"null":1}
```

A null tag gives a table called `"null"`.

**Review finding 6.** Because the tag is turned into text, two different tags with the same text collide, and `from_entries` keeps only the last: `[{t: 1}, {t: "1"}] | split_by(.t)` returns `{"1": [{"t": "1"}]}`, and the row with the number 1 is gone without an error. Tags are nearly always strings, so this is rare, but rows should never vanish silently. Proposed: merge groups whose names are equal, or raise an error.

## keep

`keep/1`, line 182:

```jq
# keep only the named tables (drop the rest before a heavy step or before output)
def keep($names): with_entries(select(.key as $k | $names | any(. == $k)));
```

`with_entries(select(…))` keeps the tables whose name is in `$names`; a name that is not present is ignored.

```jq
{leases: [1, 2], hits: [3], scratch: [4]} | keep(["leases", "hits", "missing"])
```

```json
{"leases":[1,2],"hits":[3]}
```

## shape

`shape/0`, line 185:

```jq
# for checking a pipeline midway: each table's row count and field names (sorted)
def shape: map_values({rows: length, fields: (map(keys) | add // [] | unique)});
```

For each table: its row count and the sorted union of its rows' field names. `map(keys) | add // [] | unique`: `keys` of each row, joined into one list (`add` of no rows is null, hence `// []`), without repeats. It is for looking at a pipeline midway without printing the data.

```jq
{leases: [{ip: "a", user: "u"}, {ip: "b", ttl: 60}], empty: []} | shape
```

```json
{"leases":{"rows":2,"fields":["ip","ttl","user"]},"empty":{"rows":0,"fields":[]}}
```
