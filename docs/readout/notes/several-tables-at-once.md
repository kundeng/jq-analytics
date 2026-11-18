Three small definitions for a program that carries several tables in one object, `{leases: […], hits: […]}`, usually because the host can hand it only one stream of rows with a field saying which table each row belongs to.

## split_by/1
<!-- code: c78d6da1 -->

Rows to an object of tables. `_groups(tagf)` makes the groups; each becomes an entry whose name is the tag as text (`tostring`), and `from_entries` builds the object.

```jq run
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type) | map_values(length)
```

A null tag gives a table called `"null"`.

**Review finding 6.** Because the tag is turned into text, two different tags with the same text collide, and `from_entries` keeps only the last: `[{t: 1}, {t: "1"}] | split_by(.t)` returns `{"1": [{"t": "1"}]}`, and the row with the number 1 is gone without an error. Tags are nearly always strings, so this is rare, but rows should never vanish silently. Proposed: merge groups whose names are equal, or raise an error.

## keep/1
<!-- code: 23493c55 -->

`with_entries(select(…))` keeps the tables whose name is in `$names`; a name that is not present is ignored.

```jq run
{leases: [1, 2], hits: [3], scratch: [4]} | keep(["leases", "hits", "missing"])
```

## shape/0
<!-- code: 26a6c462 -->

For each table: its row count and the sorted union of its rows' field names. `map(keys) | add // [] | unique`: `keys` of each row, joined into one list (`add` of no rows is null, hence `// []`), without repeats. It is for looking at a pipeline midway without printing the data.

```jq run
{leases: [{ip: "a", user: "u"}, {ip: "b", ttl: 60}], empty: []} | shape
```
