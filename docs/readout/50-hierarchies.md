# Hierarchies

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/hierarchies.md`. Do not edit.

Two definitions. A tree here is a table of nodes, each naming its parent; a root's parent is null or `""`.

## tree_paths

`tree_paths/2`, lines 405 to 421:

```jq
# tree_paths: adds to every node `ancestry` (the ids from its root down to itself) and `depth`
# (0 for a root). A parent id that is not a node, a cycle, or an id on two rows is an error.
# Each node's ancestry is built once: a walk up stops at the first ancestor already done and the
# ancestries are then filled in from there down, so the cost follows the size of the output, not
# the square of the depth.
def tree_paths(id; parent):
  (reduce .[] as $n ({}; ($n | id | tojson) as $k
     | if has($k) then error("tree_paths: id \($k) appears twice") else .[$k] = [($n | parent)] end)) as $par
  | (reduce .[] as $n ({m: {}};
       ($n | id) as $i
       | if .m[$i | tojson] != null then .
         else .chain = [$i] | .on = {($i | tojson): true} | .cur = $i
           | until($par[.cur | tojson][0] as $p | $p == null or $p == "" or .m[$p | tojson] != null;
               $par[.cur | tojson][0] as $p
               | if $par[$p | tojson] == null then error("tree_paths: parent \($p | tojson) is not a node")
                 elif .on[$p | tojson] then error("tree_paths: cycle through \($p | tojson)")
                 else .chain += [$p] | .on[$p | tojson] = true | .cur = $p end)
           | $par[.cur | tojson][0] as $top
           | .a = (if $top == null or $top == "" then [] else .m[$top | tojson] end)
           | reduce (.chain | reverse)[] as $c (.; .a += [$c] | .m[$c | tojson] = .a)
         end) | .m) as $anc
  | map(. + ($anc[id | tojson] | {ancestry: ., depth: (length - 1)}));
```

Adds to every node its `ancestry` (the ids from its root down to itself) and `depth`.

Three parts:

1. **`$par`**: a lookup from node id to `[parent]`. The parent is wrapped in an array so that "this id is a node whose parent is null" (`[null]`) can be told from "this id is not a node" (`null`). While it is built, an id that is already in it is an error: two rows with one id would otherwise share the last row's parent.
2. **The outer `reduce`** builds `.m`, a lookup from id to ancestry, one node at a time. A node already in `.m` is skipped. Otherwise:
   - **walk up.** `.chain` collects the ids met, starting with the node itself; `.on` is the same ids as an object, for the cycle test. The `until` stops at a root, or at the first ancestor whose ancestry is already in `.m`. On the way, a parent that is not a node, or one already on this walk, is an error.
   - **fill down.** `.a` starts as the ancestry of the node the walk stopped under (empty at a root). `reduce (.chain | reverse)[]` then goes back down the chain, top first, extending `.a` by one id and storing it for that id.
3. **The last line** attaches each node's ancestry and its length minus one as the depth.

Because a walk stops at the first ancestor already done, every node is walked over once. An earlier version walked each node's whole ancestry and compared every step with the path so far, which took time with the square of the depth; the answers are the same.

```jq
[{id: "web", boss: "eng"}, {id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "ops", boss: "ceo"}, {id: "api", boss: "eng"}]
| tree_paths(.id; .boss) | map({id, depth, ancestry})
```

```json
[
  {"id": "web", "depth": 2, "ancestry": ["ceo", "eng", "web"]},
  {"id": "ceo", "depth": 0, "ancestry": ["ceo"]},
  {"id": "eng", "depth": 1, "ancestry": ["ceo", "eng"]},
  {"id": "ops", "depth": 1, "ancestry": ["ceo", "ops"]},
  {"id": "api", "depth": 2, "ancestry": ["ceo", "eng", "api"]}
]
```

The first node, `web`, walks up through `eng` to `ceo` and fills all three; `ceo` and `eng` are then skipped; `ops` and `api` each stop after one step.

```jq
([{id: "a", boss: "b"}, {id: "b", boss: "a"}] | try tree_paths(.id; .boss) catch .),
([{id: "a", boss: "zz"}] | try tree_paths(.id; .boss) catch .),
([{id: 1, p: null}, {id: 1, p: 2}, {id: 2, p: null}] | try tree_paths(.id; .p) catch .)
```

```json
"tree_paths: cycle through \"a\""
"tree_paths: parent \"zz\" is not a node"
"tree_paths: id 1 appears twice"
```

**Review finding 11, fixed in 0.9.0.** Until 0.8.1 an id on two rows was not detected: the lookup kept the last row's parent, and a root could come back with an ancestry. It is now the error in the last line above; `tree_rollup` and `nested_from_nodes` get it too, since they call `tree_paths`.

## tree_rollup

`tree_rollup/3`, lines 425 to 429:

```jq
# tree_rollup: tree_paths, plus `subtree`: the node's own value plus the values of all its
# descendants, at any depth. A null value counts as 0.
def tree_rollup(id; parent; value):
  tree_paths(id; parent) as $t
  | (reduce $t[] as $n ({}; ($n | value) as $v
       | reduce $n.ancestry[] as $a (.; .[$a | tojson] += ($v // 0)))) as $sum
  | $t | map(. + {subtree: $sum[id | tojson]});
```

`tree_paths` first; then `$sum`, a lookup from id to the total of its subtree. The double `reduce` adds each node's value to every id on its ancestry, itself included, so a node's total is its own value plus those of all its descendants. `$v // 0` counts a null value as 0.

The cost is the total length of all ancestries: nodes times average depth.

```jq
[{id: "ceo", boss: null, n: 1}, {id: "eng", boss: "ceo", n: 2}, {id: "ops", boss: "ceo", n: 3},
 {id: "web", boss: "eng", n: 4}, {id: "api", boss: "eng", n: null}]
| tree_rollup(.id; .boss; .n) | map({id, n, subtree})
```

```json
[
  {"id": "ceo", "n": 1, "subtree": 10},
  {"id": "eng", "n": 2, "subtree": 6},
  {"id": "ops", "n": 3, "subtree": 3},
  {"id": "web", "n": 4, "subtree": 4},
  {"id": "api", "n": null, "subtree": 0}
]
```

Hand check: `eng` is 2 + 4 + 0 = 6; `ceo` is 1 + 6 + 3 = 10.
