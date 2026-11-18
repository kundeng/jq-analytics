Three small definitions for a program that carries several tables in one object, `{leases: […], hits: […]}`, usually because the host can hand it only one stream of rows with a field saying which table each row belongs to.

## split_by/1
<!-- code: 3636e7a7 -->

Rows to an object of tables.

- `_groups(tagf)` makes the groups; each becomes `{key: the tag as text, tag: the tag itself, value: the rows}`.
- `group_by(.key) | map(select(length > 1))[0]` looks for a name that two groups share. Groups are formed by the tag's value, names by its text, so the number 1 and the string `"1"` are two groups with one name.
- Such a pair is an error naming both tags and the name. Otherwise `from_entries` builds the object.

```jq run
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type) | map_values(length),
  (try ([{t: 1}, {t: "1"}] | split_by(.t)) catch .)
```

A null tag gives a table called `"null"`.

**Review finding 6, fixed in 0.9.0.** Until 0.8.1 two tags with the same text collided, `from_entries` kept only the last, and the other table's rows were lost without an error. It is now the error shown above.

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
