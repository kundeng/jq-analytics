# Shapes in and out

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/shapes-in-and-out.md`. Do not edit.

Fifteen definitions that convert between the forms data arrives in (nested documents, objects keyed by id) and the tables the rest of the library takes, and from those tables to what the next tool reads. A table here is an array of objects, one object per row.

```mermaid
flowchart TD
  N[nested documents] -- unnest, unnest_outer, flatten_fields --> T[tables]
  NT[a nested tree] -- nodes_from_nested --> T
  M[an object keyed by id] -- rows_from_map --> T
  T -- fill_grid --> T
  T -- to_map --> M2[an object keyed by id]
  T -- nested_from_nodes --> NT2[a nested tree]
  T -- node_link --> G[nodes and links for graph tools]
  T -- to_csv --> C[CSV lines]
```

Two jq reminders for this family. A `;` separates arguments. A parameter written `$as` is a value, here usually a field name as a string; a parameter without the `$`, such as `f` in `unnest(f; $as)`, is a filter the function runs on each row, so `.tags` there means "this row's tags".

On this page, in the order of the file:

| Function | Whose | What it is for |
|---|---|---|
| `_distinct_in_order` | Internal helper, not for callers | The distinct values of an array, in the order they first appear |
| `_unnest_arr`, `unnest`, `unnest_outer` | Public functions and internal helpers | One row per element of an array field |
| `_flat`, `flatten_fields` | Public functions and internal helpers | Nested objects become columns named by their path, so `{"user": {"dept": "x"}}` gives a column `user.dept` |
| `_nodes`, `nodes_from_nested` | Public functions and internal helpers | A nested tree, where each node holds its children in an array, becomes node rows, each with a `parent` field |
| `rows_from_map` | Public function | An object keyed by id becomes rows, with the key in field `$as` |
| `fill_grid` | Public function | Completes a time series: every combination of the key fields gets a row at every time step from the earliest time to the latest, and a missing combination gets a filler row |
| `to_map` | Public function | Rows become an object keyed by `key`, for looking a row up by id |
| `_nest`, `nested_from_nodes` | Public functions and internal helpers | The reverse of `nodes_from_nested`: node rows with an id and a parent become a nested tree, each node's children in an array in field `$as` |
| `node_link` | Public function | Edge rows become the `{nodes, links}` object that graph tools such as networkx, d3 and Cytoscape read |
| `to_csv` | Public function | A table as CSV text: a header line, then one line per row, with the columns in the order of `$cols` |

---

## _distinct_in_order

**Internal helper, not for callers** · `_distinct_in_order`

The distinct values of an array, in the order they first appear. jq's `unique` also removes repeats, but it sorts, which loses that order.

### _distinct_in_order: the example

```jq
["b", "a", "b", 1, "1", "a"] | _distinct_in_order, unique
```

```json
["b","a",1,"1"]
[1,"1","a","b"]
```

Two values: this function's result, then the builtin's. `b` stays first because it appeared first. The number 1 and the string `"1"` are different values and both stay.

### _distinct_in_order: what happens inside, on the example

Step 1, the `reduce`: one pass over the values. `s` maps each value, as JSON text, to `[position of first sighting, value]`; a value already in `s` is skipped. `n` counts the distinct values so far.

```jq
["b", "a", "b", 1, "1", "a"]
| reduce .[] as $x ({n: 0, s: {}}; ($x | tojson) as $k | if .s[$k] then . else .s[$k] = [.n, $x] | .n += 1 end)
```

```json
{"n":4,"s":{"\"b\"":[0,"b"],"\"a\"":[1,"a"],"1":[2,1],"\"1\"":[3,"1"]}}
```

The keys `1` and `"\"1\""` differ because the JSON text of a number has no quotes.

Step 2, `[.s[]] | sort_by(.[0]) | map(.[1])`: the four pairs sorted by position, then the positions dropped. That is the first result at the top.

### _distinct_in_order: the definition

`_distinct_in_order/0`, lines 658 to 662:

```jq
# the distinct values of an array in order of first appearance (jq's unique sorts them)
# (each first sighting is stored with its position and the positions sorted at the end: appending
# to an array inside the reduce copied it every time, 47 s for 400,000 values)
def _distinct_in_order: reduce .[] as $x ({n: 0, s: {}}; ($x | tojson) as $k
  | if .s[$k] then . else .s[$k] = [.n, $x] | .n += 1 end) | [.s[]] | sort_by(.[0]) | map(.[1]);
```

Built into jq: `map`, `sort_by`, `tojson`.

The first sightings are written into an object by key and sorted once at the end. The shorter "append the value when it is new" copies the growing array on every append, so its cost grows with the square of the number of distinct values. The sort at the end is also what makes the order the same on engines that do not keep an object's key order.

---

## _unnest_arr, unnest, unnest_outer

**Public functions and internal helpers** · `_unnest_arr(f; $i)`, `unnest(f; $as)`, `unnest_outer(f; $as)`

One row per element of an array field. `unnest` is SQL's `CROSS JOIN UNNEST(tags)`: a row with no elements disappears. `unnest_outer` is `LEFT JOIN LATERAL`: such a row is kept once, with a null. `_unnest_arr` is the helper that reads the array from one row.

### _unnest_arr and the others: the example

| id | tags |
|---|---|
| 1 | ["x", "y"] |
| 2 | [] |
| 3 | null |

```jq
[{id: 1, tags: ["x", "y"]}, {id: 2, tags: []}, {id: 3, tags: null}]
| unnest(.tags; "tag"), unnest_outer(.tags; "tag")
```

```json
[{"id":1,"tags":["x","y"],"tag":"x"},{"id":1,"tags":["x","y"],"tag":"y"}]
[{"id":1,"tags":["x","y"],"tag":"x"},{"id":1,"tags":["x","y"],"tag":"y"},{"id":2,"tags":[],"tag":null},{"id":3,"tags":null,"tag":null}]
```

Two values. `unnest` gives two rows, both from id 1; ids 2 and 3 have nothing to give. `unnest_outer` gives the same two rows and then ids 2 and 3 once each with `tag` null. The `tags` array stays on every row; drop it afterwards with `map(del(.tags))` if it is not wanted.

A value that is neither an array nor null is refused. The error names the row's position, counting from 0:

```jq
[{id: 1, tags: ["x"]}, {id: 4, tags: "x"}] | try unnest(.tags; "tag") catch .
```

```json
"unnest: row 1 holds a string, not an array"
```

### _unnest_arr and the others: what happens inside, on the example

Step 1, `_unnest_arr(f; $i)` on each row: the array at `.tags`, with null read as an empty array. `to_entries` supplies each row's position `$i` for the error message.

```jq
[{id: 1, tags: ["x", "y"]}, {id: 2, tags: []}, {id: 3, tags: null}]
| to_entries | map(.key as $i | .value | _unnest_arr(.tags; $i))
```

```json
[
  ["x", "y"],
  [],
  []
]
```

Step 2, `unnest`: for each element `$x` of a row's array, the row is emitted once with field `$as` added. An empty array has no elements, so its row is emitted zero times.

Step 2 in `unnest_outer`: an empty array is first replaced by `[null]`, so its row is emitted once with a null:

```jq
[["x", "y"], [], []] | map(if length == 0 then [null] else . end)
```

```json
[
  ["x", "y"],
  [null],
  [null]
]
```

### _unnest_arr and the others: the definition

`_unnest_arr/2`, lines 664 to 668:

```jq
# the array at f for one row: [] for null, an error naming the row for anything else
def _unnest_arr(f; $i):
  (f) as $a
  | if $a == null then [] elif ($a | type) == "array" then $a
    else error("unnest: row \($i) holds a \($a | type), not an array") end;
```

Built into jq: `error`, `type`.

`unnest/2`, lines 670 to 675:

```jq
# unnest: one row per element of the array at f, the element in field $as. A row whose array is
# empty or null is dropped, as SQL's UNNEST drops it; unnest_outer keeps it once with $as null
# (LEFT JOIN LATERAL). A value at f that is neither an array nor null is an error naming the row's
# position. Elements come out in array order, rows in input order.
def unnest(f; $as):
  [to_entries[] | .key as $i | .value as $r | ($r | _unnest_arr(f; $i))[] as $x | $r + {($as): $x}];
```

Built into jq: `to_entries`. From this library: `_unnest_arr`.

`unnest_outer/2`, lines 676 to 678:

```jq
def unnest_outer(f; $as):
  [to_entries[] | .key as $i | .value as $r
   | ($r | _unnest_arr(f; $i) | if length == 0 then [null] else . end)[] as $x | $r + {($as): $x}];
```

Built into jq: `length`, `to_entries`. From this library: `_unnest_arr`.

- `_unnest_arr`: `(f) as $a` runs the caller's filter on the row. Null gives `[]`, an array is returned as it is, anything else is the error.
- `to_entries[] | .key as $i | .value as $r` walks the rows with their positions. `as` binds a name without changing the input.
- `($r | _unnest_arr(f; $i))[] as $x` takes the elements one at a time. `$r + {($as): $x}` is the row with the new field; `($as)` in parentheses uses the value of `$as` as the field name.
- Elements come out in array order and rows in input order.

---

## _flat, flatten_fields

**Public functions and internal helpers** · `_flat($p; $sep)`, `flatten_fields($sep)`

Nested objects become columns named by their path, so `{"user": {"dept": "x"}}` gives a column `user.dept`. jq's own `flatten` flattens arrays; this flattens the objects inside each row.

### _flat and the others: the example

One row with an object two levels deep, an array and an empty object:

```jq
[{user: {name: "ann", dept: {id: 7}}, tags: ["a"], meta: {}}] | flatten_fields(".")
```

```json
[
  {"user.name": "ann", "user.dept.id": 7, "tags": ["a"], "meta": {}}
]
```

`user` is gone and its leaves are columns `user.name` and `user.dept.id`. The array `tags` is left as a value, for `unnest` to take. The empty object `meta` has no leaves and stays as `{}`.

Two paths that flatten to the same name are refused:

```jq
[{a: {b: 1}, "a.b": 2}] | try flatten_fields(".") catch .
```

```json
"flatten_fields: two fields flatten to the same name: [\"a.b\"]"
```

### _flat and the others: what happens inside, on the example

Step 1, `_flat(null; ".")` on the row: one `{key, value}` pair per leaf, the key being the path so far. `_flat` emits the pairs one at a time; the run collects them in an array and sorts them by key, because engines walk an object's fields in different orders.

```jq
{user: {name: "ann", dept: {id: 7}}, tags: ["a"], meta: {}} | [_flat(null; ".")] | sort_by(.key)
```

```json
[
  {"key": "meta", "value": {}},
  {"key": "tags", "value": ["a"]},
  {"key": "user.dept.id", "value": 7},
  {"key": "user.name", "value": "ann"}
]
```

Step 2, `from_entries`: the pairs become one object, the row of the result at the top. If the object has fewer fields than there were pairs, two pairs had the same key and one replaced the other. That is the case the error reports.

### _flat and the others: the definition

`_flat/2`, lines 680 to 684:

```jq
# one value flattened to {key: path, value} pairs; a non-empty object recurses, anything else is a leaf
def _flat($p; $sep):
  if type == "object" and length > 0
  then to_entries[] | .key as $k | .value | _flat(if $p == null then $k else $p + $sep + $k end; $sep)
  else {key: $p, value: .} end;
```

Built into jq: `length`, `to_entries`, `type`.

`flatten_fields/1`, lines 686 to 696:

```jq
# flatten_fields: nested objects become columns named by their path joined with $sep
# ({"user": {"dept": "x"}} gives "user.dept"). Arrays and scalars are left as values, for unnest to
# take; an empty object stays as the value {}. Two paths that flatten to the same name are an error.
# (jq's own flatten flattens arrays; this flattens the objects inside each row.)
def flatten_fields($sep):
  map(if length == 0 then {}
      else [_flat(null; $sep)] as $e | ($e | from_entries) as $o
        | if ($o | length) != ($e | length)   # a repeated name collapsed in from_entries
          then error("flatten_fields: two fields flatten to the same name: \($e | map(.key) | group_by(.) | map(select(length > 1)[0]) | tojson)")
          else $o end
      end);
```

Built into jq: `error`, `from_entries`, `group_by`, `length`, `map`, `select`, `tojson`. From this library: `_flat`.

- `_flat($p; $sep)`: a non-empty object recurses into each field, with the path extended by the field's name (`$p + $sep + $k`, or `$k` at the top where `$p` is null). Anything else, a scalar, an array or an empty object, is a leaf and is emitted as `{key: $p, value: .}`.
- `flatten_fields`: `if length == 0 then {}` passes an empty row through.
- `[_flat(null; $sep)] as $e | ($e | from_entries) as $o` keeps both the pairs and the object built from them.
- `if ($o | length) != ($e | length)` detects the repeated name; `group_by(.) | map(select(length > 1)[0])` finds which names repeat, for the message.

---

## _nodes, nodes_from_nested

**Public functions and internal helpers** · `_nodes(id; children; $p)`, `nodes_from_nested(id; children)`

A nested tree, where each node holds its children in an array, becomes node rows, each with a `parent` field. That is the shape `tree_paths` and `tree_rollup` take.

### _nodes and the others: the example

A small reporting tree: ceo has eng and ops under it, and eng has web.

```jq
{id: "ceo", reports: [{id: "eng", reports: [{id: "web"}]}, {id: "ops"}]} | nodes_from_nested(.id; .reports)
```

```json
[
  {"id": "ceo", "parent": null},
  {"id": "eng", "parent": "ceo"},
  {"id": "web", "parent": "eng"},
  {"id": "ops", "parent": "ceo"}
]
```

Four rows, one per node, in depth-first order: a node, then everything under it, then its next sibling. The `reports` arrays are gone and `parent` holds the id of the node above; the root's is null.

### _nodes and the others: reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `id` | `.id` | one node | the node's id, written into its children's `parent` |
| `children` | `.reports` | one node | the array of the node's children; missing means none |

### _nodes and the others: what happens inside, on the example

`_nodes(id; children; $p)` does the work for one node: it emits the node without its children array and with `parent` set to `$p`, then calls itself on each child with this node's id as `$p`. It emits several values, one per node. Called on the `eng` subtree with parent `"ceo"`:

```jq
{id: "eng", reports: [{id: "web"}]} | [_nodes(.id; .reports; "ceo")]
```

```json
[
  {"id": "eng", "parent": "ceo"},
  {"id": "web", "parent": "eng"}
]
```

`nodes_from_nested` calls it on the root with a null parent and collects everything emitted into one array.

### _nodes and the others: the definition

`_nodes/3`, lines 698 to 700:

```jq
# one nested node and its descendants as rows, depth first, each with its parent's id
def _nodes(id; children; $p): . as $n
  | ($n | del(children) + {parent: $p}), ((($n | children) // [])[] | _nodes(id; children; ($n | id)));
```

Built into jq: `del`.

`nodes_from_nested/2`, lines 702 to 705:

```jq
# nodes_from_nested: a nested tree (each node holding its children in an array at `children`)
# becomes node rows, each with `parent` set to its parent's id (null for a root) and the children
# array removed. The input is one root object or an array of roots. Rows are in depth-first order.
def nodes_from_nested(id; children): [(if type == "array" then .[] else . end) | _nodes(id; children; null)];
```

Built into jq: `type`. From this library: `_nodes`.

- `$n | del(children) + {parent: $p}` is the node's own row.
- `(($n | children) // [])[]` takes the children one at a time; `// []` reads a missing or null children field as no children, which is how `web` and `ops` end the recursion.
- `nodes_from_nested`: `if type == "array" then .[] else . end` accepts one root object or an array of roots.

---

## rows_from_map

**Public function** · `rows_from_map($as)`

An object keyed by id becomes rows, with the key in field `$as`. Many APIs return a table in this form.

### rows_from_map: the example

Three keys; two values are objects and one is a string.

```jq
{web01: {ram: 16}, db01: {ram: 64}, note: "spare"} | rows_from_map("host")
```

```json
[
  {"host": "db01", "ram": 64},
  {"host": "note", "value": "spare"},
  {"host": "web01", "ram": 16}
]
```

One row per key, sorted by key. An object value contributes its fields beside the key. The string has no field name of its own, so it goes in a field called `value`.

A value that already has a field named `$as` is refused, because that field would replace the key:

```jq
{a: {id: "zzz"}} | try rows_from_map("id") catch .
```

```json
"rows_from_map: the value of key \"a\" already has a field \"id\""
```

### rows_from_map: what happens inside, on the example

Step 1, `to_entries | sort_by(.key)`: one `{key, value}` pair per key, in key order.

```jq
{web01: {ram: 16}, db01: {ram: 64}, note: "spare"} | to_entries | sort_by(.key)
```

```json
[
  {"key": "db01", "value": {"ram": 64}},
  {"key": "note", "value": "spare"},
  {"key": "web01", "value": {"ram": 16}}
]
```

Step 2: each pair becomes a row. For `db01`, `{host: "db01"} + {ram: 64}`. That gives the result at the top.

### rows_from_map: the definition

`rows_from_map/1`, lines 707 to 716:

```jq
# rows_from_map: an object keyed by id becomes rows, the key in field $as, sorted by key. A value
# that is not an object becomes {($as): key, value: v}. Sorted because gojq does not keep an
# object's key order, so the order the keys were written in cannot be the same on every engine.
# A value that already has a field named $as is an error: it would replace the key.
def rows_from_map($as):
  to_entries | sort_by(.key) | map(. as $e
    | if ($e.value | type) != "object" then {($as): $e.key, value: $e.value}
      elif ($e.value | has($as))
      then error("rows_from_map: the value of key \($e.key | tojson) already has a field \($as | tojson)")
      else {($as): $e.key} + $e.value end);
```

Built into jq: `error`, `has`, `map`, `sort_by`, `to_entries`, `tojson`, `type`.

- `sort_by(.key)`: gojq does not keep the order an object's keys were written in, so sorted order is the one order every engine can agree on.
- `if ($e.value | type) != "object"`: a value that is not an object becomes `{($as): key, value: v}`.
- `elif ($e.value | has($as))`: the error case above.
- `else {($as): $e.key} + $e.value`: the key first, then the value's fields.

---

## fill_grid

**Public function** · `fill_grid($keys; $time; $step; $fill)`

Completes a time series: every combination of the key fields gets a row at every time step from the earliest time to the latest, and a missing combination gets a filler row. Without the filler rows, `lag` or `moving_mean` treats the row after a gap as the next period. In SQL this is a cross join of the keys with `generate_series`, left joined to the data.

### fill_grid: the example

Readings every 60 seconds for two series, `a` and `b`, with gaps:

| g | t | v |
|---|---|---|
| a | 0 | 1 |
| a | 120 | 3 |
| b | 60 | 5 |

```jq
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}] | fill_grid(["g"]; "t"; 60; {v: 0})
```

```json
[
  {"g": "a", "t": 0, "v": 1},
  {"g": "a", "t": 60, "v": 0},
  {"g": "a", "t": 120, "v": 3},
  {"g": "b", "t": 0, "v": 0},
  {"g": "b", "t": 60, "v": 5},
  {"g": "b", "t": 120, "v": 0}
]
```

Six rows: two series times three time steps (0, 60, 120). The three input rows are there unchanged; the other three are fillers with `v` 0.

### fill_grid: reading the call

All four arguments are values, not filters.

| Argument | In the example | Meaning |
|---|---|---|
| `$keys` | `["g"]` | the names of the fields that identify a series |
| `$time` | `"t"` | the name of the time field, holding epoch seconds |
| `$step` | `60` | seconds between grid points |
| `$fill` | `{v: 0}` | the fields a filler row gets besides its keys and time |

### fill_grid: what happens inside, on the example

Step 1: the checks, then the range. No row may lack a time, and every time must be a whole number of steps from the earliest. Here `$t0` is 0 and `$t1` is 120. The two errors:

```jq
(try ([{g: "a", t: 0}, {g: "a", t: null}] | fill_grid(["g"]; "t"; 60; {})) catch .),
(try ([{g: "a", t: 0}, {g: "a", t: 90}] | fill_grid(["g"]; "t"; 60; {})) catch .)
```

```json
"fill_grid: a row has no time"
"fill_grid: 90 is not on the 60-second grid from 0"
```

Step 2, `$ix`: the rows indexed by their key values and time, as JSON text.

```jq
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}]
| reduce .[] as $r ({}; .[[$r[["g"][]], $r["t"]] | tojson] += [$r])
```

```json
{
  "[\"a\",0]": [{"g": "a", "t": 0, "v": 1}],
  "[\"a\",120]": [{"g": "a", "t": 120, "v": 3}],
  "[\"b\",60]": [{"g": "b", "t": 60, "v": 5}]
}
```

Step 3, `$combos`: the distinct key combinations, in order of first appearance.

```jq
[{g: "a", t: 0, v: 1}, {g: "a", t: 120, v: 3}, {g: "b", t: 60, v: 5}] | [.[] | [.[["g"][]]]] | _distinct_in_order
```

```json
[
  ["a"],
  ["b"]
]
```

Step 4: for each combination and each time 0, 60, 120, the rows found in `$ix`, or one filler row. The filler starts from the key fields, built by pairing each key name with its value:

```jq
[["g"], ["a"]] | transpose | map({key: .[0], value: .[1]}) | from_entries
```

```json
{"g":"a"}
```

For `["a"]` at time 60 there is no entry in `$ix`, so the row is `{"g":"a"} + {"t":60} + {"v":0}`, the second row of the result.

### fill_grid: the definition

`fill_grid/4`, lines 718 to 735:

```jq
# fill_grid: every combination of the $keys fields' values (in first appearance) at every time from
# the earliest to the latest in steps of $step seconds; a missing combination gets a row with the
# key fields, the time field and $fill. $keys and $time are field names; times are epoch seconds
# and must sit on the grid (an offset from the earliest that is a multiple of $step), else an
# error. Without the filled rows a lag or a moving mean steps over an empty period as if it were
# the next one.
def fill_grid($keys; $time; $step; $fill):
  if length == 0 then []
  elif any(.[]; .[$time] == null) then error("fill_grid: a row has no time") else
  (map(.[$time]) | min) as $t0 | (map(.[$time]) | max) as $t1
  | (map(select(((.[$time] - $t0) % $step) != 0)) | if length > 0
       then error("fill_grid: \(.[0][$time]) is not on the \($step)-second grid from \($t0)") else . end) as $_
  | (reduce .[] as $r ({}; .[[$r[$keys[]], $r[$time]] | tojson] += [$r])) as $ix
  | ([.[] | [.[$keys[]]]] | _distinct_in_order) as $combos
  | [$combos[] as $k | range($t0; $t1 + 1; $step) as $t
     | ($ix[$k + [$t] | tojson] // [([$keys, $k] | transpose | map({key: .[0], value: .[1]}) | from_entries)
                                     + {($time): $t} + $fill])[]]
  end;
```

Built into jq: `any`, `error`, `from_entries`, `length`, `map`, `max`, `min`, `range`, `select`, `tojson`, `transpose`. From this library: `_distinct_in_order`.

- `if length == 0 then []`: no rows in, no rows out.
- `(map(select(...)) | if length > 0 then error(...) else . end) as $_` runs the grid check for its error only; `$_` is not used again.
- `.[[$r[$keys[]], $r[$time]] | tojson] += [$r]`: several rows with the same keys and time are all kept, under one index entry.
- `range($t0; $t1 + 1; $step)` emits the grid times, the last one included.
- `($ix[...] // [filler])[]` emits the found rows, or the one filler. Rows come out combination by combination, each in time order.

---

## to_map

**Public function** · `to_map(key)`

Rows become an object keyed by `key`, for looking a row up by id. jq's own `INDEX(key)` does the same but keeps the last row when a key repeats; here a repeated key is an error.

### to_map: the example

```jq
[{id: "web01", ram: 16}, {id: "db01", ram: 64}] | to_map(.id)
```

```json
{"web01":{"id":"web01","ram":16},"db01":{"id":"db01","ram":64}}
```

One object with one entry per row; each value is the whole row.

The key is turned into a string, because an object key has to be one. So a repeat is refused, and the number 1 and the string `"1"` count as a repeat too:

```jq
(try ([{id: "a"}, {id: "a"}] | to_map(.id)) catch .),
(try ([{id: 1}, {id: "1"}] | to_map(.id)) catch .)
```

```json
"to_map: duplicate key \"a\""
"to_map: duplicate key \"1\""
```

### to_map: the definition

`to_map/1`, lines 737 to 741:

```jq
# to_map: rows become an object keyed by `key` (as a string). A duplicate key is an error; jq's
# own INDEX(key) keeps the last row silently.
def to_map(key):
  reduce .[] as $r ({}; ($r | key | tostring) as $k
    | if has($k) then error("to_map: duplicate key \($k | tojson)") else .[$k] = $r end);
```

Built into jq: `error`, `has`, `tojson`, `tostring`.

`reduce .[] as $r ({}; ...)` adds one row at a time to an object that starts empty. `($r | key | tostring) as $k` runs the caller's filter on the row. `if has($k)` is the duplicate check; otherwise `.[$k] = $r`.

---

## _nest, nested_from_nodes

**Public functions and internal helpers** · `_nest($by; id; $as)`, `nested_from_nodes(id; parent; $as)`

The reverse of `nodes_from_nested`: node rows with an id and a parent become a nested tree, each node's children in an array in field `$as`. This is the form a tree view or a JSON API wants.

### _nest and the others: the example

| id | boss |
|---|---|
| ceo | null |
| eng | ceo |
| web | eng |
| ops | ceo |

```jq
[{id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "web", boss: "eng"}, {id: "ops", boss: "ceo"}]
| nested_from_nodes(.id; .boss; "reports")
```

```json
[
  {"id": "ceo", "boss": null, "reports": [{"id": "eng", "boss": "ceo", "reports": [{"id": "web", "boss": "eng", "reports": []}]}, {"id": "ops", "boss": "ceo", "reports": []}]}
]
```

An array with one root, `ceo`. Its `reports` holds `eng` and `ops`, and `eng`'s holds `web`. A node with no children gets an empty array. Each node keeps its own fields, `boss` included.

A parent that is not a node, or a cycle, is refused with the error of `tree_paths`, which does the checking:

```jq
(try ([{id: "a", boss: "zz"}] | nested_from_nodes(.id; .boss; "reports")) catch .),
(try ([{id: "a", boss: "b"}, {id: "b", boss: "a"}] | nested_from_nodes(.id; .boss; "reports")) catch .)
```

```json
"tree_paths: parent \"zz\" is not a node"
"tree_paths: cycle through \"a\""
```

### _nest and the others: what happens inside, on the example

Step 1: `tree_paths(id; parent)` runs for its checks; its result is thrown away.

Step 2, `$by`: the rows grouped under their parent's id, as JSON text. The root is under the key `null`.

```jq
[{id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "web", boss: "eng"}, {id: "ops", boss: "ceo"}]
| group_by(.boss) | map({key: (.[0] | .boss | tojson), value: .}) | from_entries
```

```json
{
  "null": [{"id": "ceo", "boss": null}],
  "\"ceo\"": [{"id": "eng", "boss": "ceo"}, {"id": "ops", "boss": "ceo"}],
  "\"eng\"": [{"id": "web", "boss": "eng"}]
}
```

Step 3: each root is expanded by `_nest`, which adds field `reports` holding the node's children from `$by`, each expanded the same way. For `ceo` it looks up `"\"ceo\""` and finds `eng` and `ops`; for `eng` it finds `web`; for `web` and `ops` it finds nothing and adds an empty array.

### _nest and the others: the definition

`_nest/3`, lines 743 to 744:

```jq
# one node with its children, and theirs, nested under field $as
def _nest($by; id; $as): . as $n | $n + {($as): [($by[$n | id | tojson] // [])[] | _nest($by; id; $as)]};
```

Built into jq: `tojson`.

`nested_from_nodes/3`, lines 746 to 752:

```jq
# nested_from_nodes: node rows (id, parent) become a nested tree, each node's children in an array
# in field $as, the roots in an array. Checked with tree_paths first, so a missing parent or a
# cycle is the same error as there.
def nested_from_nodes(id; parent; $as):
  (tree_paths(id; parent) | length) as $_
  | (group_by(parent) | map({key: (.[0] | parent | tojson), value: .}) | from_entries) as $by
  | [.[] | select((parent) == null or (parent) == "") | _nest($by; id; $as)];
```

Built into jq: `from_entries`, `group_by`, `length`, `map`, `select`, `tojson`. From this library: `_nest`, `tree_paths`.

- `(tree_paths(id; parent) | length) as $_` forces `tree_paths` to run; `$_` is not used again.
- `group_by(parent)` keeps the children of one parent in input order.
- `select((parent) == null or (parent) == "")` picks the roots: a null or empty parent.
- `_nest`: `($by[$n | id | tojson] // [])[]` is the node's children, none when it has no entry. The recursion ends at nodes without children.

---

## node_link

**Public function** · `node_link(from; to)`

Edge rows become the `{nodes, links}` object that graph tools such as networkx, d3 and Cytoscape read.

### node_link: the example

```jq
[{a: "fetch", b: "compile", min: 1}, {a: "compile", b: "test", min: 2}] | node_link(.a; .b)
```

```json
{
  "nodes": [{"id": "fetch"}, {"id": "compile"}, {"id": "test"}],
  "links": [{"a": "fetch", "b": "compile", "min": 1, "source": "fetch", "target": "compile"}, {"a": "compile", "b": "test", "min": 2, "source": "compile", "target": "test"}]
}
```

`nodes` lists each end of an edge once, in order of first appearance. Each link is the edge row with `source` and `target` added, so other fields such as `min` travel along.

### node_link: the definition

`node_link/2`, lines 754 to 758:

```jq
# node_link: edge rows become the node-link form graph tools read (networkx, d3, Cytoscape):
# {nodes: [{id}], links: [row + {source, target}]}. Nodes are in order of first appearance.
def node_link(from; to):
  {nodes: ([.[] | (from), (to)] | _distinct_in_order | map({id: .})),
   links: map(. + {source: (from), target: (to)})};
```

Built into jq: `map`. From this library: `_distinct_in_order`.

- `[.[] | (from), (to)] | _distinct_in_order | map({id: .})`: both ends of every edge, repeats removed, each wrapped as `{id}`.
- `map(. + {source: (from), target: (to)})`: `from` and `to` are the caller's filters, run on each edge row.

---

## to_csv

**Public function** · `to_csv($cols)`

A table as CSV text: a header line, then one line per row, with the columns in the order of `$cols`.

### to_csv: the example

Two rows; one host name contains a comma, and one `ram` is null.

```jq
[{host: "web01", ram: 16}, {host: "db, 01", ram: null}] | [to_csv(["host", "ram"])]
```

```json
["\"host\",\"ram\"","\"web01\",16","\"db, 01\","]
```

`to_csv` emits three strings, one per line; the run collects them in an array to show them as JSON. Strings are quoted, which keeps the comma inside `"db, 01"` in one cell. The null is an empty cell. Run jq with `-r` to get the plain lines.

### to_csv: the definition

`to_csv/1`, lines 760 to 763:

```jq
# to_csv: a header line, then one CSV line per row, columns in the order of $cols; a stream of
# strings, so run jq with -r. A null is an empty cell. A nested value in a cell is an error from
# @csv itself: flatten_fields first.
def to_csv($cols): ($cols | @csv), (.[] | [.[$cols[]]] | @csv);
```

- `$cols | @csv` is the header.
- `.[] | [.[$cols[]]] | @csv`: for each row, its values for the columns in order, formatted by `@csv`. A column the row lacks is null, so an empty cell.
- A nested value in a cell, an object or an array, is an error from `@csv` itself, worded differently by each engine. Run `flatten_fields` first.
