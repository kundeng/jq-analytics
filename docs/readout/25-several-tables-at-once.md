# Several tables at once

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/several-tables-at-once.md`. Do not edit.

Three small definitions for a program that carries several tables in one object, `{leases: […], hits: […]}`, usually because the host can hand it only one stream of rows with a field saying which table each row belongs to.

## split_by

`split_by/1`, lines 188 to 193:

```jq
# split a stream of rows into an object of tables by a tag: rows with the same tagf value form one table,
# named by that value as a string (a null tag gives the table "null"). A host that can pass only one
# stream hands over several tables this way: one stream, with a field saying which table each row belongs to.
# Two different tags with the same name as text (1 and "1", or null and "null") are an error: one
# table would otherwise replace the other.
def split_by(tagf):
  [_groups(tagf)[] | {key: (.[0] | tagf | tostring), tag: (.[0] | tagf), value: .}]
  | (group_by(.key) | map(select(length > 1))[0]) as $dup
  | if $dup != null
    then error("split_by: tags \($dup[0].tag | tojson) and \($dup[1].tag | tojson) give the same table name \($dup[0].key | tojson)")
    else map({key, value}) | from_entries end;
```

Rows to an object of tables.

- `_groups(tagf)` makes the groups; each becomes `{key: the tag as text, tag: the tag itself, value: the rows}`.
- `group_by(.key) | map(select(length > 1))[0]` looks for a name that two groups share. Groups are formed by the tag's value, names by its text, so the number 1 and the string `"1"` are two groups with one name.
- Such a pair is an error naming both tags and the name. Otherwise `from_entries` builds the object.

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type) | map_values(length),
  (try ([{t: 1}, {t: "1"}] | split_by(.t)) catch .)
```

```json
{"lease":2,"hit":1,"null":1}
"split_by: tags 1 and \"1\" give the same table name \"1\""
```

A null tag gives a table called `"null"`.

**Review finding 6, fixed in 0.9.0.** Until 0.8.1 two tags with the same text collided, `from_entries` kept only the last, and the other table's rows were lost without an error. It is now the error shown above.

## keep

`keep/1`, line 196:

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

`shape/0`, line 199:

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
