Two definitions. A tree here is a table of nodes, each naming its parent; a root's parent is null or `""`.

## tree_paths/2
<!-- code: d56459c6 -->

Adds to every node its `ancestry` (the ids from its root down to itself) and `depth`.

Three parts:

1. **`$par`**: a lookup from node id to `[parent]`. The parent is wrapped in an array so that "this id is a node whose parent is null" (`[null]`) can be told from "this id is not a node" (`null`). While it is built, an id that is already in it is an error: two rows with one id would otherwise share the last row's parent.
2. **The outer `reduce`** builds `.m`, a lookup from id to ancestry, one node at a time. A node already in `.m` is skipped. Otherwise:
   - **walk up.** `.chain` collects the ids met, starting with the node itself; `.on` is the same ids as an object, for the cycle test. The `until` stops at a root, or at the first ancestor whose ancestry is already in `.m`. On the way, a parent that is not a node, or one already on this walk, is an error.
   - **fill down.** `.a` starts as the ancestry of the node the walk stopped under (empty at a root). `reduce (.chain | reverse)[]` then goes back down the chain, top first, extending `.a` by one id and storing it for that id.
3. **The last line** attaches each node's ancestry and its length minus one as the depth.

Because a walk stops at the first ancestor already done, every node is walked over once. An earlier version walked each node's whole ancestry and compared every step with the path so far, which took time with the square of the depth; the answers are the same.

```jq run
[{id: "web", boss: "eng"}, {id: "ceo", boss: null}, {id: "eng", boss: "ceo"}, {id: "ops", boss: "ceo"}, {id: "api", boss: "eng"}]
| tree_paths(.id; .boss) | map({id, depth, ancestry})
```

The first node, `web`, walks up through `eng` to `ceo` and fills all three; `ceo` and `eng` are then skipped; `ops` and `api` each stop after one step.

```jq run
([{id: "a", boss: "b"}, {id: "b", boss: "a"}] | try tree_paths(.id; .boss) catch .),
([{id: "a", boss: "zz"}] | try tree_paths(.id; .boss) catch .),
([{id: 1, p: null}, {id: 1, p: 2}, {id: 2, p: null}] | try tree_paths(.id; .p) catch .)
```

**Review finding 11, fixed in 0.9.0.** Until 0.8.1 an id on two rows was not detected: the lookup kept the last row's parent, and a root could come back with an ancestry. It is now the error in the last line above; `tree_rollup` and `nested_from_nodes` get it too, since they call `tree_paths`.

## tree_rollup/3
<!-- code: 425ecb0a -->

`tree_paths` first; then `$sum`, a lookup from id to the total of its subtree. The double `reduce` adds each node's value to every id on its ancestry, itself included, so a node's total is its own value plus those of all its descendants. `$v // 0` counts a null value as 0.

The cost is the total length of all ancestries: nodes times average depth.

```jq run
[{id: "ceo", boss: null, n: 1}, {id: "eng", boss: "ceo", n: 2}, {id: "ops", boss: "ceo", n: 3},
 {id: "web", boss: "eng", n: 4}, {id: "api", boss: "eng", n: null}]
| tree_rollup(.id; .boss; .n) | map({id, n, subtree})
```

Hand check: `eng` is 2 + 4 + 0 = 6; `ceo` is 1 + 6 + 3 = 10.
