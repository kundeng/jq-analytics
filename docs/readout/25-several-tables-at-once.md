# Several tables at once

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/several-tables-at-once.md`. Do not edit.

Three small definitions for a program that carries several tables in one object, `{lease: [...], hit: [...]}`. The usual reason is a host that can hand the program only one stream of rows, with a field saying which table each row belongs to.

An object of tables has no row order of its own: jq and jaq print its tables in the order they were made, and gojq prints them sorted by name. The rows inside each table keep their order on every engine.

On this page, in the order of the file:

| Function | Whose | What it is for |
|---|---|---|
| `split_by` | Public function | One list of rows into an object of tables, one table per value of a tag |
| `keep_tables` | Public function | Only the named tables of an object of tables |
| `shape` | Public function | For each table |

---

## split_by

**Public function** · `split_by(tagf)`

One list of rows into an object of tables, one table per value of a tag. It is the first step when several tables arrive mixed in one stream.

### split_by: the example

Four rows from two sources, DHCP leases and firewall hits, with `type` saying which. One row has no type.

| type | ip |
|---|---|
| lease | a |
| hit | a |
| lease | b |
| null | c |

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type)
```

```json
{
  "lease": [{"type": "lease", "ip": "a"}, {"type": "lease", "ip": "b"}],
  "hit": [{"type": "hit", "ip": "a"}],
  "null": [{"type": null, "ip": "c"}]
}
```

One object with three tables. `lease` holds its two rows in input order. The row with no type is in a table called `"null"`, because an object's keys are strings.

A later step then names a table and works on it. `as $t` binds the whole object to a name without changing the input:

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| split_by(.type) as $t | $t.lease | map(.ip)
```

```json
["a","b"]
```

### split_by: reading the call

The one argument, `.type`, is a filter: `split_by` runs it on each row to get that row's tag. Any expression on the row will do, as for `_groups` on the grouping page.

### split_by: what happens inside, on the example

Step 1, `_groups(.type)`: the rows in groups, one per tag, in order of first appearance.

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| _groups(.type)
```

```json
[
  [{"type": "lease", "ip": "a"}, {"type": "lease", "ip": "b"}],
  [{"type": "hit", "ip": "a"}],
  [{"type": null, "ip": "c"}]
]
```

Step 2, `[_groups(tagf)[] | {key: ..., tag: ..., value: .}]`: each group becomes an entry. `key` is the tag of the group's first row as text, `tag` is the tag itself, and `value` is the group's rows.

```jq
[{type: "lease", ip: "a"}, {type: "hit", ip: "a"}, {type: "lease", ip: "b"}, {type: null, ip: "c"}]
| [_groups(.type)[] | {key: (.[0] | .type | tostring), tag: (.[0] | .type), value: .}]
```

```json
[
  {"key": "lease", "tag": "lease", "value": [{"type": "lease", "ip": "a"}, {"type": "lease", "ip": "b"}]},
  {"key": "hit", "tag": "hit", "value": [{"type": "hit", "ip": "a"}]},
  {"key": "null", "tag": null, "value": [{"type": null, "ip": "c"}]}
]
```

In the third entry the tag is null and the key is the string `"null"`.

Step 3, `(group_by(.key) | map(select(length > 1))[0]) as $dup`: the entries are grouped by key, and the first group with more than one entry is taken. That is a pair of different tags with the same text. Here every key occurs once, so `$dup` is null:

```jq
[{key: "lease"}, {key: "hit"}, {key: "null"}] | group_by(.key) | map(select(length > 1))[0]
```

```json
null
```

Step 4, `map({key, value}) | from_entries`: `tag` is dropped, and `from_entries` builds the object from the `key` and `value` pairs. That is the result at the top.

### split_by: what is refused

Groups are formed by the tag's value and tables are named by its text. The number 1 and the string `"1"` are two groups with one name, and so are a null tag and the string `"null"`. One table would replace the other, so it is an error naming both tags:

```jq
(try ([{t: 1}, {t: "1"}] | split_by(.t)) catch .),
(try ([{t: null}, {t: "null"}] | split_by(.t)) catch .)
```

```json
"split_by: tags 1 and \"1\" give the same table name \"1\""
"split_by: tags null and \"null\" give the same table name \"null\""
```

### split_by: the definition

`split_by/1`, lines 183 to 193:

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

Built into jq: `error`, `from_entries`, `group_by`, `length`, `map`, `select`, `tojson`, `tostring`. From this library: `_groups`.

- The first line is steps 1 and 2.
- The `$dup` line is step 3. `map(select(length > 1))` keeps the groups of two or more entries, and `[0]` takes the first, or null when there is none.
- `if $dup != null then error(...)`: the message is built from the two clashing entries' tags and their shared key.
- `else map({key, value}) | from_entries end`: step 4. `{key, value}` is short for `{key: .key, value: .value}`.

---

## keep_tables

**Public function** · `keep_tables($names)`

Only the named tables of an object of tables. It is used to drop work tables before a heavy step or before output.

### keep_tables: the example

Three tables, of which two are wanted. The list also names a table that does not exist.

```jq
{lease: [{ip: "a"}, {ip: "b"}], hit: [{ip: "a"}], scratch: [{n: 1}]} | keep_tables(["lease", "hit", "missing"])
```

```json
{"lease":[{"ip":"a"},{"ip":"b"}],"hit":[{"ip":"a"}]}
```

`scratch` is gone. `missing` is not in the input and is ignored: no error, and no empty table is made for it.

### keep_tables: the definition

`keep_tables/1`, lines 195 to 196:

```jq
# keep only the named tables (drop the rest before a heavy step or before output)
def keep_tables($names): with_entries(select(.key as $k | $names | any(. == $k)));
```

Built into jq: `any`, `select`, `with_entries`.

- `with_entries(f)` turns the object into `{key, value}` entries, runs `f` on each, and builds an object from what is left.
- `select(.key as $k | $names | any(. == $k))` keeps an entry when its key equals some name in `$names`. `$names` has a `$`, so it is a value: the list is passed as it is.

---

## shape

**Public function** · `shape`

For each table: how many rows it has and which fields its rows use. It is for looking at a pipeline midway without printing the data.

### shape: the example

Two tables. The rows of `lease` do not all have the same fields, and `empty` has no rows.

```jq
{lease: [{ip: "a", user: "u"}, {ip: "b", ttl: 60}], empty: []} | shape
```

```json
{"lease":{"rows":2,"fields":["ip","ttl","user"]},"empty":{"rows":0,"fields":[]}}
```

`lease` has two rows and three field names between them, sorted. The empty table has 0 rows and no fields.

### shape: what happens inside, on the example

`map_values(f)` runs `f` on each table. `map_values` is a jq built-in, not a function of this library: on an object it runs `f` on each value and keeps the keys. The object here is the set of tables, so inside `f` the input is one table. `f` makes `rows`, the table's `length`, and `fields`, in three steps. For `lease`: step 1, `map(keys)`, the field names of each row. Step 2, `add`, the lists joined into one. Step 3, `unique`, sorted and without repeats. The three results, in that order:

```jq
[{ip: "a", user: "u"}, {ip: "b", ttl: 60}] | map(keys), (map(keys) | add), (map(keys) | add | unique)
```

```json
[["ip","user"],["ip","ttl"]]
["ip","user","ip","ttl"]
["ip","ttl","user"]
```

For the empty table, `add` of no lists is null, and `// []` replaces the null with an empty list before `unique`:

```jq
[] | (map(keys) | add), (map(keys) | add // [] | unique)
```

```json
null
[]
```

### shape: the definition

`shape/0`, lines 198 to 199:

```jq
# for checking a pipeline midway: each table's row count and field names (sorted)
def shape: map_values({rows: length, fields: (map(keys) | add // [] | unique)});
```

Built into jq: `add`, `keys`, `length`, `map`, `map_values`, `unique`.

- `map_values({rows: length, fields: (...)})`: one small object per table, under the table's name.
- `map(keys) | add // [] | unique`: steps 1 to 3.
