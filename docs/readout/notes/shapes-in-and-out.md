### What it is for

Twenty-five definitions that convert between the forms data arrives in (nested documents, objects keyed by id, CSV text) and the tables the rest of the library takes, and from those tables to what the next tool reads (CSV, TSV, a printed table, an object keyed by id, a nested tree, a node-link graph). A table here is an array of objects, one object per row. They answer "how do I get this API reply into rows", "how do I fill the gaps in this time series", and "how do I hand this result to a spreadsheet or a graph viewer".

```mermaid
flowchart TD
  N[nested documents] -- unnest, unnest_outer, flatten_fields, flatten_paths --> T[tables]
  CSVIN[CSV text, or arrays with a header] -- from_csv, rows_from_arrays --> T
  NT[a nested tree] -- nodes_from_nested --> T
  M[an object keyed by id] -- rows_from_map --> T
  T -- fill_grid, drop_empty --> T
  T -- unflatten_fields --> N2[nested rows]
  T -- to_map --> M2[an object keyed by id]
  T -- nested_from_nodes --> NT2[a nested tree]
  T -- node_link --> G[nodes and links for graph tools]
  T -- to_csv, to_tsv, to_table --> C[text lines]
```

A small trip from an API reply to CSV: an object keyed by host becomes rows, then text.

```jq run
{web01: {ram: 16, tags: ["web"]}, db01: {ram: 64}} | rows_from_map("host") | [to_csv(null)]
```

The keys come back sorted (`db01` first), the columns are every field name, sorted, and the list in `tags` is written as its JSON text in one cell. `docs/design/05-shapes.md` places these converters among the library's shapes (table, several tables, intervals, tree, graph, star) and traces one nested export through three of them.

Two jq reminders for this family. A `;` separates arguments. A parameter written `$as` is a value, here usually a field name as a string; a parameter without the `$`, such as `f` in `unnest(f; $as)`, is a filter the function runs on each row, so `.tags` there means "this row's tags".

### The rules it keeps

- **A converter changes form, never values.** No cast and no rounding: `from_csv` gives every value as a string, for `cast_columns` to type.
- **Output order is stated and the same on every engine.** Where an object's key order would decide it, the library sorts, because gojq does not keep the order keys were written in: `rows_from_map` sorts by key, `to_csv(null)` sorts the column names. Where the data has an order, it is kept: `unnest` emits rows in input order and elements in array order, `nodes_from_nested` goes depth first, `node_link` lists nodes in order of first appearance, `fill_grid` goes combination by combination in time order.
- **Empty is a value where it matters.** `unnest` drops a row whose array is empty or null (SQL's `CROSS JOIN UNNEST`); `unnest_outer` keeps it once with a null (`LEFT JOIN LATERAL`). `flatten_fields` keeps an empty object as `{}`. `drop_empty` removes null, `""`, `[]` and `{}` at every depth, and a container left empty by that, but keeps `false` and `0`.
- **Refuses rather than guesses**, each with an error naming the row, key or line: an array field that is neither an array nor null (`unnest`); two paths that flatten to one name (`flatten_fields`, `flatten_paths`); a value that already has the key field (`rows_from_map`); a repeated key, with `1` and `"1"` counting as a repeat (`to_map`); a row with no time, or a time off the step grid (`fill_grid`); a parent that is not a node, a cycle, or a repeated id (`nested_from_nodes`, through `tree_paths`); a CSV record longer than its header, or a header that repeats a name (`rows_from_arrays`); anything but text given to `from_csv`. And an input that is not a table (page 00).
- **Limits:** a key made only of digits comes back from `unflatten_fields` as an array position, not a key. `from_csv` reads RFC 4180 only (comma, double quotes), at about 5 s a megabyte in jq 1.7.1; larger files belong to DuckDB's `read_csv`.

### Beside core jq, SQL and pandas

Core jq has pieces of most of these, and the library's versions exist where the piece stops short. Each idiom below was run on jq 1.7.1, gojq and jaq:

| Need | Core jq | Where it stops short |
|---|---|---|
| object keyed by id to rows | `to_entries \| map({host: .key} + .value)` | the row order is the key order the engine keeps: written order on jq and jaq, sorted on gojq |
| CSV out | `@csv` on an array of cells | stops on a nested cell, with a different message on each engine (`array (["x"]) is not valid in a csv row` on jq); no header; the column list is yours to build |
| CSV in | none; `split("\n") \| map(split(","))` | splits inside quotes: `a,"b,c"` gives three cells, `a`, `"b`, `c"`, on all three engines |
| flatten to path names | `[paths(scalars) \| map(tostring) \| join(".")]` | gives the names but drops empty containers (`e: []` is lost); `leaf_paths` is not defined in jq 1.7.1, gojq or jaq |
| drop nulls | `del(.. \| nulls)` | works on all three and is the right tool for nulls alone (`drop_nulls` was left out for that reason); `drop_empty` also removes `""`, `[]`, `{}` and containers emptied by that |
| rows to an object by key | `INDEX(.id)` | keeps the last row of a repeated key silently; not in jaq |

SQL: `CROSS JOIN UNNEST` and `LEFT JOIN LATERAL` are `unnest` and `unnest_outer`; a cross join of the keys with `generate_series`, left-joined to the data, is `fill_grid`; DuckDB's `read_csv` with every column as text reads the test file as `from_csv` does, and the test suite holds that answer.

pandas, checked with pandas 3.1.1: `explode("tags")` is `unnest_outer` (an empty or missing list gives one row with NaN); `pd.json_normalize` is `flatten_fields` with `.` as the separator, except that it drops an empty object where `flatten_fields` keeps `{}`; `read_csv` and `to_csv` are the CSV pair, with type guessing on read that `from_csv` leaves to `cast_columns`.

What the family adds: the conversions at the edges of a jq program, with a stated order and an error instead of a silent loss.

### Decisions

- **2026-11-18, spec 10, version 0.2.0.** Ten converters, in the one library file. A converter changes form, never values, refuses input that is not its source, and states its output order; an object keyed by id becomes rows sorted by key. Parquet, Excel and schema validation were left out: jq cannot write binary formats.
- **0.9.0 (2026-11-18, spec 55).** `rows_from_map` refuses a value that already has the key field (review finding 13; before, the key was lost); `fill_grid` refuses a null time (finding 14); `nested_from_nodes` groups children by parent once instead of appending inside a `reduce` (finding 15), so its cost no longer grows with the number of children of one parent.
- **2026-11-19, spec 65, version 0.15.0.** From a survey of the questions people ask about jq: `to_csv(null)` infers the columns (sorted, because first-seen order differs on gojq) and writes a nested cell as JSON text instead of stopping; `to_tsv` and `to_table` added; `from_csv` and `rows_from_arrays` read CSV; `drop_empty`; `flatten_paths` and `unflatten_fields`, which round-trip. `unflatten_fields` sets values through its own `_setp`, because jaq 3.1.2 will neither create an array from null nor assign past an array's end. Deep merge, other CSV dialects and an approximate document diff were left out.

## _distinct_in_order/0
<!-- code: f7b39916 -->

The distinct values of an array, in the order they first appear. jq's `unique` also removes repeats, but it sorts, which loses that order.

### The example

```jq run
["b", "a", "b", 1, "1", "a"] | _distinct_in_order, unique
```

Two values: this function's result, then the builtin's. `b` stays first because it appeared first. The number 1 and the string `"1"` are different values and both stay.

### What happens inside, on the example

Step 1, the `reduce`: one pass over the values. `s` maps each value, as JSON text, to `[position of first sighting, value]`; a value already in `s` is skipped. `n` counts the distinct values so far.

```jq run
["b", "a", "b", 1, "1", "a"]
| reduce .[] as $x ({n: 0, s: {}}; ($x | tojson) as $k | if .s[$k] then . else .s[$k] = [.n, $x] | .n += 1 end)
```

The keys `1` and `"\"1\""` differ because the JSON text of a number has no quotes.

Step 2, `[.s[]] | sort_by(.[0]) | map(.[1])`: the four pairs sorted by position, then the positions dropped. That is the first result at the top.

### The definition

<!-- definition -->

The first sightings are written into an object by key and sorted once at the end. The shorter "append the value when it is new" copies the growing array on every append, so its cost grows with the square of the number of distinct values. The sort at the end is also what makes the order the same on engines that do not keep an object's key order.

## _unnest_arr/2, unnest/2, unnest_outer/2
<!-- code: 15e025e0 -->

One row per element of an array field. `unnest` is SQL's `CROSS JOIN UNNEST(tags)`: a row with no elements disappears. `unnest_outer` is `LEFT JOIN LATERAL`: such a row is kept once, with a null. `_unnest_arr` is the helper that reads the array from one row.

### The example

| id | tags |
|---|---|
| 1 | ["x", "y"] |
| 2 | [] |
| 3 | null |

```jq run
[{id: 1, tags: ["x", "y"]}, {id: 2, tags: []}, {id: 3, tags: null}]
| unnest(.tags; "tag"), unnest_outer(.tags; "tag")
```

Two values. `unnest` gives two rows, both from id 1; ids 2 and 3 have nothing to give. `unnest_outer` gives the same two rows and then ids 2 and 3 once each with `tag` null. The `tags` array stays on every row; drop it afterwards with `map(del(.tags))` if it is not wanted.

A value that is neither an array nor null is refused. The error names the row's position, counting from 0:

```jq run
[{id: 1, tags: ["x"]}, {id: 4, tags: "x"}] | try unnest(.tags; "tag") catch .
```

### What happens inside, on the example

Step 1, `_unnest_arr(f; $i)` on each row: the array at `.tags`, with null read as an empty array. `to_entries` supplies each row's position `$i` for the error message.

```jq run
[{id: 1, tags: ["x", "y"]}, {id: 2, tags: []}, {id: 3, tags: null}]
| to_entries | map(.key as $i | .value | _unnest_arr(.tags; $i))
```

Step 2, `unnest`: for each element `$x` of a row's array, the row is emitted once with field `$as` added. An empty array has no elements, so its row is emitted zero times.

Step 2 in `unnest_outer`: an empty array is first replaced by `[null]`, so its row is emitted once with a null:

```jq run
[["x", "y"], [], []] | map(if length == 0 then [null] else . end)
```

### The definition

<!-- definition -->

- `_unnest_arr`: `(f) as $a` runs the caller's filter on the row. Null gives `[]`, an array is returned as it is, anything else is the error.
- `to_entries[] | .key as $i | .value as $r` walks the rows with their positions. `as` binds a name without changing the input.
- `($r | _unnest_arr(f; $i))[] as $x` takes the elements one at a time. `$r + {($as): $x}` is the row with the new field; `($as)` in parentheses uses the value of `$as` as the field name.
- Elements come out in array order and rows in input order.

## _flat/2, flatten_fields/1
<!-- code: 66c3aa65 -->

Nested objects become columns named by their path, so `{"user": {"dept": "x"}}` gives a column `user.dept`. jq's own `flatten` flattens arrays; this flattens the objects inside each row.

### The example

One row with an object two levels deep, an array and an empty object:

```jq run
[{user: {name: "ann", dept: {id: 7}}, tags: ["a"], meta: {}}] | flatten_fields(".")
```

`user` is gone and its leaves are columns `user.name` and `user.dept.id`. The array `tags` is left as a value, for `unnest` to take. The empty object `meta` has no leaves and stays as `{}`.

Two paths that flatten to the same name are refused:

```jq run
[{a: {b: 1}, "a.b": 2}] | try flatten_fields(".") catch .
```

### What happens inside, on the example

Step 1, `_flat(null; ".")` on the row: one `{key, value}` pair per leaf, the key being the path so far. `_flat` emits the pairs one at a time; the run collects them in an array and sorts them by key, because engines walk an object's fields in different orders.

```jq run
{user: {name: "ann", dept: {id: 7}}, tags: ["a"], meta: {}} | [_flat(null; ".")] | sort_by(.key)
```

Step 2, `from_entries`: the pairs become one object, the row of the result at the top. If the object has fewer fields than there were pairs, two pairs had the same key and one replaced the other. That is the case the error reports.

### The definition

<!-- definition -->

- `_flat($p; $sep)`: a non-empty object recurses into each field, with the path extended by the field's name (`$p + $sep + $k`, or `$k` at the top where `$p` is null). Anything else, a scalar, an array or an empty object, is a leaf and is emitted as `{key: $p, value: .}`.
- `flatten_fields`: `if length == 0 then {}` passes an empty row through.
- `[_flat(null; $sep)] as $e | ($e | from_entries) as $o` keeps both the pairs and the object built from them.
- `if ($o | length) != ($e | length)` detects the repeated name; `group_by(.) | map(select(length > 1)[0])` finds which names repeat, for the message.

## _nodes/3, nodes_from_nested/2
<!-- code: 87c6a03d -->

A nested tree, where each node holds its children in an array, becomes node rows, each with a `parent` field. That is the shape `tree_paths` and `tree_rollup` take.

### The example

A small reporting tree: ceo has eng and ops under it, and eng has web.

```jq run
{id: "ceo", reports: [{id: "eng", reports: [{id: "web"}]}, {id: "ops"}]} | nodes_from_nested(.id; .reports)
```

Four rows, one per node, in depth-first order: a node, then everything under it, then its next sibling. The `reports` arrays are gone and `parent` holds the id of the node above; the root's is null.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `id` | `.id` | one node | the node's id, written into its children's `parent` |
| `children` | `.reports` | one node | the array of the node's children; missing means none |

### What happens inside, on the example

`_nodes(id; children; $p)` does the work for one node: it emits the node without its children array and with `parent` set to `$p`, then calls itself on each child with this node's id as `$p`. It emits several values, one per node. Called on the `eng` subtree with parent `"ceo"`:

```jq run
{id: "eng", reports: [{id: "web"}]} | [_nodes(.id; .reports; "ceo")]
```

`nodes_from_nested` calls it on the root with a null parent and collects everything emitted into one array.

### The definition

<!-- definition -->

- `$n | del(children) + {parent: $p}` is the node's own row.
- `(($n | children) // [])[]` takes the children one at a time; `// []` reads a missing or null children field as no children, which is how `web` and `ops` end the recursion.
- `nodes_from_nested`: `if type == "array" then .[] else . end` accepts one root object or an array of roots.

## rows_from_map/1
<!-- code: 70158b64 -->

An object keyed by id becomes rows, with the key in field `$as`. Many APIs return a table in this form.

### The example

Three keys; two values are objects and one is a string.

```jq run
{web01: {ram: 16}, db01: {ram: 64}, note: "spare"} | rows_from_map("host")
```

One row per key, sorted by key. An object value contributes its fields beside the key. The string has no field name of its own, so it goes in a field called `value`.

A value that already has a field named `$as` is refused, because that field would replace the key:

```jq run
{a: {id: "zzz"}} | try rows_from_map("id") catch .
```

### What happens inside, on the example

Step 1, `to_entries | sort_by(.key)`: one `{key, value}` pair per key, in key order.

```jq run
{web01: {ram: 16}, db01: {ram: 64}, note: "spare"} | to_entries | sort_by(.key)
```

Step 2: each pair becomes a row. For `db01`, `{host: "db01"} + {ram: 64}`. That gives the result at the top.

### The definition

<!-- definition -->

- `sort_by(.key)`: gojq does not keep the order an object's keys were written in, so sorted order is the one order every engine can agree on.
- `if ($e.value | type) != "object"`: a value that is not an object becomes `{($as): key, value: v}`.
- `elif ($e.value | has($as))`: the error case above.
- `else {($as): $e.key} + $e.value`: the key first, then the value's fields.

## fill_grid/4
<!-- code: 449f76b2 -->

Completes a time series: every combination of the key fields gets a row at every time step from the earliest time to the latest, and a missing combination gets a filler row. Without the filler rows, `lag` or `moving_mean` treats the row after a gap as the next period. In SQL this is a cross join of the keys with `generate_series`, left joined to the data.

### The example

Readings every 60 seconds for two series, `a` and `b`, with gaps:

| g | t | v |
|---|---|---|
| a | 0 | 1 |
| a | 120 | 3 |
| b | 60 | 5 |

```jq run
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}] | fill_grid(["g"]; "t"; 60; {v: 0})
```

Six rows: two series times three time steps (0, 60, 120). The three input rows are there unchanged; the other three are fillers with `v` 0.

### Reading the call

All four arguments are values, not filters.

| Argument | In the example | Meaning |
|---|---|---|
| `$keys` | `["g"]` | the names of the fields that identify a series |
| `$time` | `"t"` | the name of the time field, holding epoch seconds |
| `$step` | `60` | seconds between grid points |
| `$fill` | `{v: 0}` | the fields a filler row gets besides its keys and time |

### What happens inside, on the example

Step 1: the checks, then the range. No row may lack a time, and every time must be a whole number of steps from the earliest. Here `$t0` is 0 and `$t1` is 120. The two errors:

```jq run
(try ([{g: "a", t: 0}, {g: "a", t: null}] | fill_grid(["g"]; "t"; 60; {})) catch .),
(try ([{g: "a", t: 0}, {g: "a", t: 90}] | fill_grid(["g"]; "t"; 60; {})) catch .)
```

Step 2, `$ix`: the rows indexed by their key values and time, as JSON text.

```jq run
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}]
| reduce .[] as $r ({}; .[[$r[["g"][]], $r["t"]] | tojson] += [$r])
```

Step 3, `$combos`: the distinct key combinations, in order of first appearance.

```jq run
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}] | [.[] | [.[["g"][]]]] | _distinct_in_order
```

Step 4: for each combination and each time 0, 60, 120, the rows found in `$ix`, or one filler row. The filler starts from the key fields, built by pairing each key name with its value:

```jq run
[["g"], ["a"]] | transpose | map({key: .[0], value: .[1]}) | from_entries
```

For `["a"]` at time 60 there is no entry in `$ix`, so the row is `{"g":"a"} + {"t":60} + {"v":0}`, the second row of the result.

### The definition

<!-- definition -->

- `if length == 0 then []`: no rows in, no rows out.
- `(map(select(...)) | if length > 0 then error(...) else . end) as $_` runs the grid check for its error only; `$_` is not used again.
- `.[[$r[$keys[]], $r[$time]] | tojson] += [$r]`: several rows with the same keys and time are all kept, under one index entry.
- `range($t0; $t1 + 1; $step)` emits the grid times, the last one included.
- `($ix[...] // [filler])[]` emits the found rows, or the one filler. Rows come out combination by combination, each in time order.

## to_map/1
<!-- code: 7f09dca0 -->

Rows become an object keyed by `key`, for looking a row up by id. jq's own `INDEX(key)` does the same but keeps the last row when a key repeats; here a repeated key is an error.

### The example

```jq run
[{id: "web01", ram: 16}, {id: "db01", ram: 64}] | to_map(.id)
```

One object with one entry per row; each value is the whole row.

The key is turned into a string, because an object key has to be one. So a repeat is refused, and the number 1 and the string `"1"` count as a repeat too:

```jq run
(try ([{id: "a"}, {id: "a"}] | to_map(.id)) catch .),
(try ([{id: 1}, {id: "1"}] | to_map(.id)) catch .)
```

### The definition

<!-- definition -->

`reduce .[] as $r ({}; ...)` adds one row at a time to an object that starts empty. `($r | key | tostring) as $k` runs the caller's filter on the row. `if has($k)` is the duplicate check; otherwise `.[$k] = $r`.

## _nest/3, nested_from_nodes/3
<!-- code: 0c204e23 -->

The reverse of `nodes_from_nested`: node rows with an id and a parent become a nested tree, each node's children in an array in field `$as`. This is the form a tree view or a JSON API wants.

### The example

| id | boss |
|---|---|
| ceo | null |
| eng | ceo |
| web | eng |
| ops | ceo |

```jq run
[{id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "web", boss: "eng"}, {id: "ops", boss: "ceo"}]
| nested_from_nodes(.id; .boss; "reports")
```

An array with one root, `ceo`. Its `reports` holds `eng` and `ops`, and `eng`'s holds `web`. A node with no children gets an empty array. Each node keeps its own fields, `boss` included.

A parent that is not a node, or a cycle, is refused with the error of `tree_paths`, which does the checking:

```jq run
(try ([{id: "a", boss: "zz"}] | nested_from_nodes(.id; .boss; "reports")) catch .),
(try ([{id: "a", boss: "b"}, {id: "b", boss: "a"}] | nested_from_nodes(.id; .boss; "reports")) catch .)
```

### What happens inside, on the example

Step 1: `tree_paths(id; parent)` runs for its checks; its result is thrown away.

Step 2, `$by`: the rows grouped under their parent's id, as JSON text. The root is under the key `null`.

```jq run
[{id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "web", boss: "eng"}, {id: "ops", boss: "ceo"}]
| group_by(.boss) | map({key: (.[0] | .boss | tojson), value: .}) | from_entries
```

Step 3: each root is expanded by `_nest`, which adds field `reports` holding the node's children from `$by`, each expanded the same way. For `ceo` it looks up `"\"ceo\""` and finds `eng` and `ops`; for `eng` it finds `web`; for `web` and `ops` it finds nothing and adds an empty array.

### The definition

<!-- definition -->

- `(tree_paths(id; parent) | length) as $_` forces `tree_paths` to run; `$_` is not used again.
- `group_by(parent)` keeps the children of one parent in input order.
- `select((parent) == null or (parent) == "")` picks the roots: a null or empty parent.
- `_nest`: `($by[$n | id | tojson] // [])[]` is the node's children, none when it has no entry. The recursion ends at nodes without children.

## node_link/2
<!-- code: d230587a -->

Edge rows become the `{nodes, links}` object that graph tools such as networkx, d3 and Cytoscape read.

### The example

```jq run
[{a: "fetch", b: "compile", min: 1}, {a: "compile", b: "test", min: 2}] | node_link(.a; .b)
```

`nodes` lists each end of an edge once, in order of first appearance. Each link is the edge row with `source` and `target` added, so other fields such as `min` travel along.

### The definition

<!-- definition -->

- `[.[] | (from), (to)] | _distinct_in_order | map({id: .})`: both ends of every edge, repeats removed, each wrapped as `{id}`.
- `map(. + {source: (from), target: (to)})`: `from` and `to` are the caller's filters, run on each edge row.

## _cell/0, _cols/1, to_csv/1, to_tsv/1, to_table/1
<!-- code: 4b0ced23 -->

A table as text for another tool or a person: CSV, TSV, or padded columns for a terminal. Since 0.15.0 the columns can be left to the function (`null`) and a nested value is written as its JSON text instead of stopping the run, the two things people most often trip on when they turn JSON into CSV.

### The example

Three rows: a host name with a comma in its note, a list of tags, an owner object, and nulls.

```jq run
[{id: 1, host: "web01", note: "disk full, again", tags: ["disk", "p2"], owner: {team: "ops"}},
 {id: 2, host: "db01", note: "said \"restart\"", tags: [], owner: null},
 {id: 3, host: "app07", note: null}]
| [to_csv(null)], [to_tsv(["id", "note", "tags"])], [to_table(["id", "host", "note"])]
```

Each function emits one string per line; the run collects them in arrays to show them as JSON. Run jq with `-r` to get the plain lines.

- `to_csv(null)`: the columns are every field name of the table, sorted: `host, id, note, owner, tags`. The comma and the quotes inside a note stay in one cell (`@csv` quotes strings and doubles their quotes). The tags and the owner come out as JSON text in one cell; a null or a missing field is an empty cell.
- `to_tsv`: tabs between cells, no quotes; a tab, line break or backslash inside a value would be written as `\t`, `\n`, `\\`.
- `to_table`: each column as wide as its longest value, two spaces between columns, no trailing spaces, so the last row ends after `app07`.

### What happens inside, on the example

`_cols(null)` collects every row's keys and keeps each name once, sorted:

```jq run
[{id: 1, host: "web01"}, {id: 3, note: null}] | _cols(null)
```

`_cell` leaves a string, number, boolean or null alone and turns an array or object into its JSON text:

```jq run
[1, "a, b", null, ["x"], {team: "ops"}] | map(_cell)
```

`to_table` first builds a grid of strings, the header row first, with null as the empty string; then the width of each column is its longest string; then each cell is padded to that width and the row joined with two spaces:

```jq run
[{id: 1, host: "web01"}, {id: 12, host: "db"}] | [to_table(null)]
```

### Why the inferred columns are sorted

The order in which fields first appear would be the natural choice, but gojq does not keep an object's key order, so the same program would give different columns on different engines. Sorted names are the same everywhere. Pass the list to choose the order.

### The definition

<!-- definition -->

- `_cols($cols)`: the list as given, or `[.[] | keys[]] | unique` (keys of every row, sorted, each once).
- `to_csv` and `to_tsv`: the header is the column list through `@csv` or `@tsv`; each row is its values for those columns, each through `_cell`, through the same format.
- `to_table`: `$g` is the grid of strings; `$w` the width of each column (`max` of the lengths down the column); each cell gets `" " * (width - length)` spaces, which is null for zero in jq 1.7, hence `// ""`; `sub(" +$"; "")` removes the padding after the last column.

## rows_from_arrays/0, from_csv/0
<!-- code: fd530ab2 -->

CSV text into rows, the other direction. `from_csv` reads the text of a CSV file, read whole with `jq -Rs`, by RFC 4180, the rules most CSV writers follow; `rows_from_arrays` turns a header and value arrays into rows, for data that is already split.

### The example

A file with a comma inside quotes, doubled quotes, a line break inside quotes, an empty field, Windows line ends and a blank line:

```jq run
"id,host,note\r\n1,web01,\"disk full, again\"\r\n2,db01,\"said \"\"restart\"\"\"\r\n3,,\"line one\nline two\"\r\n\r\n" | from_csv
```

Three rows. Every value is a string, `""` for the empty host: CSV has no types, so give the columns their types next with `cast_columns`. The blank line is skipped. DuckDB's `read_csv` with every column as text reads the test file the same way.

`rows_from_arrays` on data already split into arrays; a short row gets nulls:

```jq run
[["host", "site"], ["web01", "N"], ["db01"]] | rows_from_arrays
```

### What happens inside, on the example

`from_csv` turns the text into its characters' code points with `explode` and reads them one at a time with `reduce`, keeping a small state: the rows so far, the cells of the current row, the characters of the current cell, whether it is inside quotes (`q`), and whether the last character was a quote that may end the quoted part (`pq`):

- Inside quotes, every character belongs to the cell, commas and line breaks included; a quote ends the quoted part for now.
- A quote right after that (`pq`) was a doubled quote: one quote goes into the cell and the quoted part goes on.
- Outside quotes, a comma ends the cell, a line feed ends the row, a carriage return is dropped (so CRLF and LF both work), anything else goes into the cell.
- `-1`, added after the last character, ends the last row if it has anything in it.

Then `rows_from_arrays` makes the first record the header.

### What is refused

```jq run
(try ([["host"], ["web01", "N"]] | rows_from_arrays) catch .),
(try ([["host", "host"], ["a", "b"]] | rows_from_arrays) catch .),
(try ([{id: 1}] | from_csv) catch .)
```

A record longer than the header (a cell would have no name), a header that repeats a name (one value would overwrite the other), and anything but text given to `from_csv`.

### Cost

One step of `reduce` per character: about 5 seconds a megabyte in jq 1.7.1 and 2 in jaq (measured on a 0.5 MB file of 20,000 rows: 2.5 s, gojq 1.1 s, jaq 0.85 s). For files of more than a few megabytes, read them with DuckDB's `read_csv`.

### The definition

<!-- definition -->

- `rows_from_arrays`: the header check, then for each later record its cells paired with the header names by position; `from_entries` makes the row.
- `from_csv`: the type check (a CSV file must be read with `-Rs` to arrive as one string), `explode`, the `reduce` described above with `-1` as the end marker, then `.rows | rows_from_arrays`. `any` records that the current row has started, so that a row of one empty cell (`""` alone on a line, written as `,` would be two) is kept while a blank line is not.

## flatten_paths/1, _setp/2, unflatten_fields/1
<!-- code: 531fbe7f -->

Nested rows as flat columns and back. `flatten_fields` (above) flattens only objects and leaves arrays for `unnest`; `flatten_paths` flattens arrays too, naming each item by its position, which is what a spreadsheet or a CSV needs. `unflatten_fields` rebuilds the nesting from such names.

### The example

```jq run
[{id: 1, tags: ["disk", "p2"], owner: {team: "ops"}}, {id: 2, tags: [], owner: null}]
| . as $rows
| flatten_paths(".") | ., (unflatten_fields(".") == $rows)
```

The first row's tags become `tags.0` and `tags.1`, its owner `owner.team`. The second keeps `tags: []` and `owner: null`, since an empty array and a null are leaves. Unflattening gives the rows back exactly.

### What happens inside, on the example

`flatten_paths` asks jq for the path of every leaf (`paths(f)` with `f` true for a scalar or an empty container), then names each by joining the path's parts:

```jq run
{id: 1, tags: ["disk", "p2"]} | [paths(type != "object" and type != "array" or length == 0)]
```

`unflatten_fields` splits each name back into parts, reads a part made only of digits as an array position, and sets the value at that path with `_setp`, which makes an array where it meets a number and pads it with nulls up to the position:

```jq run
[{"a.1": "x", "a.0": "y", "c.2": 1}] | unflatten_fields(".")
```

### Limits

A key made only of digits, such as an object keyed by year, comes back as an array position, not a key. Two paths that flatten to the same name (a field literally called `"tags.0"` next to a list `tags`) are an error, as in `flatten_fields`.

### The definition

<!-- definition -->

- `flatten_paths`: per row, the leaf paths, each as `{key: joined name, value: getpath(path)}`, then `from_entries`; fewer fields than paths means a name collided.
- `_setp`: jq's own `setpath` does this on jq and gojq, but jaq will not create an array from null or assign past the end of one, so the library builds the step itself: null becomes `[]` or `{}` by the kind of the next part, and an array is padded with nulls before the assignment.
- `unflatten_fields`: per row, `reduce` over its fields, setting each one's value at its path.

## drop_empty/0
<!-- code: 3b93dd44 -->

A document without empty values at any depth: null, `""`, `[]` and `{}` go, as fields and as array items, and a container that ends up empty goes with them. `false` and `0` stay; they are values. For nulls alone, jq's own `del(.. | nulls)` does it.

### The example

```jq run
{host: "web01", tags: ["", null, "p2"], owner: {team: ""}, note: null, ok: false, n: 0, extra: [[], {}]} | drop_empty
```

`owner` held only an empty string, so it is empty after the cleanup and goes too; `extra` held two empty containers and goes the same way.

### The definition

<!-- definition -->

- `d` works from the bottom up: it first cleans a field's value or an array's item, then tests whether what is left is empty, which is how a container emptied by the cleanup is removed in the same pass.
- Any value can be the input, not only a table: a document, a row, a list.
