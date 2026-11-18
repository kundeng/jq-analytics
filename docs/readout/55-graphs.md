# Graphs

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/graphs.md`. Do not edit.

Eight definitions. A graph is a table of edges; `from` and `to` are expressions giving each edge's two ends. Four functions share one breadth-first search, `_search`.

```mermaid
flowchart LR
  A[_adj: node to its neighbours] --> S[_search: breadth first, records position, hops and where each node was reached from]
  S --> R[reachable] & H[hops] & P[shortest_path by hops] & C[components]
  W[shortest_path by weight: settle the nearest open node, relax its edges]
  T[topo_order: peel off the nodes nothing points to, level by level]
```

The examples use one made-up graph of build steps, an edge meaning "must come before":

```text
fetch -> compile -> test -> package
fetch -> lint    -> package
docs  -> package
```

## _adj

`_adj/2`, line 411:

```jq
# node (as JSON text) -> the nodes its edges lead to, in input order
def _adj(from; to): group_by(from) | map({key: (.[0] | from | tojson), value: map(to)}) | from_entries;
```

A lookup from a node (as JSON text) to the list of nodes its edges lead to. `group_by(from)` gathers each node's edges, keeping their input order inside the group; one `from_entries` builds the object. Nothing is appended edge by edge.

```jq
[["fetch", "compile"], ["compile", "test"], ["test", "package"], ["fetch", "lint"], ["lint", "package"], ["docs", "package"]]
| map({a: .[0], b: .[1]}) | _adj(.a; .b)
```

```json
{
  "\"compile\"": ["test"],
  "\"docs\"": ["package"],
  "\"fetch\"": ["compile", "lint"],
  "\"lint\"": ["package"],
  "\"test\"": ["package"]
}
```

## _search

`_search/2`, lines 417 to 426:

```jq
# breadth-first search from $start: the nodes reached, the start first, in the order met, as
# [{node, hops, via (the node it was reached from; null for the start)}]. New nodes are recorded
# under their position in objects and sorted once at the end: an array growing by one inside the
# loop is copied each time, which made the search slow with the square of the graph.
def _search($adj; $start):
  {seen: {($start | tojson): [0, $start, 0, null]}, n: 1, frontier: [$start], level: 0}
  | until((.frontier | length) == 0;
      .frontier as $f | .level += 1 | .next = {}
      | reduce ($f[] as $u | $adj[$u | tojson][]? | [$u, .]) as $e (.;
          ($e[1] | tojson) as $k
          | if .seen[$k] != null then .
            else .seen[$k] = [.n, $e[1], .level, $e[0]] | .next[.n | tostring] = $e[1] | .n += 1 end)
      | .frontier = (.next | to_entries | sort_by(.key | tonumber) | map(.value)))
  | [.seen[]] | sort_by(.[0]) | map({node: .[1], hops: .[2], via: .[3]});
```

Breadth-first search from `$start`. The state:

- `seen`: node (as text) to `[position, node, hops, via]`. Position is the order in which nodes were first met; `via` is the node it was reached from.
- `frontier`: the nodes met at the current distance; `next`: those met while expanding them, stored under their position as a key.

Each round takes the frontier, and for every edge out of it, in input order, records the far end if it is new. Then `next`, sorted by position, becomes the frontier. At the end `seen` is sorted by position once.

`next` and `seen` are objects written to by key. The first version of this search appended each new node to an array inside the loop; jq copies the array on each append, and the search slowed with the square of the graph.

```jq
[["fetch", "compile"], ["compile", "test"], ["test", "package"], ["fetch", "lint"], ["lint", "package"], ["docs", "package"]]
| map({a: .[0], b: .[1]}) | _adj(.a; .b) as $adj | _search($adj; "fetch")
```

```json
[
  {"node": "fetch", "hops": 0, "via": null},
  {"node": "compile", "hops": 1, "via": "fetch"},
  {"node": "lint", "hops": 1, "via": "fetch"},
  {"node": "test", "hops": 2, "via": "compile"},
  {"node": "package", "hops": 2, "via": "lint"}
]
```

`compile` and `lint` are at distance 1. Expanding them in that order meets `test` (from `compile`) and then `package` (from `lint`), both at distance 2. `docs` is not reachable from `fetch`.

## reachable, hops

`reachable/3`, line 431:

```jq
# reachable: every node that can be reached from $start along directed edges from -> to, at any
# number of hops, nearest first. $start itself is never listed, even when a cycle leads back to it:
# each node appears once and the start counts as already seen. Cycles are safe.
def reachable(from; to; $start): _adj(from; to) as $adj | _search($adj; $start) | .[1:] | map(.node);
```

`hops/3`, line 436:

```jq
# hops: one row per node that can be reached from $start along directed edges, the start itself
# included at 0: {node, hops}, where hops is the number of edges on the shortest route; nearest
# first, and within one distance in the order the search meets them.
def hops(from; to; $start): _adj(from; to) as $adj | _search($adj; $start) | map({node, hops});
```

Both are `_search` with a different cut of its output: `reachable` drops the start (`.[1:]`) and keeps the node names; `hops` keeps `{node, hops}` and includes the start at 0.

```jq
[["fetch", "compile"], ["compile", "test"], ["test", "package"], ["fetch", "lint"], ["lint", "package"], ["docs", "package"]]
| map({a: .[0], b: .[1]})
| {reachable_from_compile: reachable(.a; .b; "compile"), hops_from_fetch: (hops(.a; .b; "fetch") | map([.node, .hops]))}
```

```json
{
  "reachable_from_compile": ["test", "package"],
  "hops_from_fetch": [["fetch", 0], ["compile", 1], ["lint", 1], ["test", 2], ["package", 2]]
}
```

## shortest_path

`shortest_path/4`, lines 442 to 447:

```jq
# shortest_path, four arguments: the route from $start to $goal with the fewest edges, as
# {path: [the nodes from start to goal], cost: the number of edges}; null when there is none;
# {path: [$start], cost: 0} when they are the same node. Among routes of equal length, the one a
# breadth-first search following edges in input order finds first.
def shortest_path(from; to; $start; $goal):
  _adj(from; to) as $adj
  | (reduce _search($adj; $start)[] as $r ({}; .[$r.node | tojson] = $r)) as $ix
  | if $ix[$goal | tojson] == null then null
    else {path: ([$goal | recurse($ix[tojson].via | select(. != null))] | reverse), cost: $ix[$goal | tojson].hops}
    end;
```

The fewest edges. `$ix` indexes the search result by node. `[$goal | recurse($ix[tojson].via | select(. != null))]` starts at the goal and follows `via` back until it reaches the start, whose `via` is null; `reverse` turns that into start to goal. `cost` is the goal's hop count. A goal the search never met gives null.

```jq
[["fetch", "compile"], ["compile", "test"], ["test", "package"], ["fetch", "lint"], ["lint", "package"], ["docs", "package"]]
| map({a: .[0], b: .[1]})
| [shortest_path(.a; .b; "fetch"; "package"), shortest_path(.a; .b; "fetch"; "docs"), shortest_path(.a; .b; "fetch"; "fetch")]
```

```json
[{"path":["fetch","lint","package"],"cost":2},null,{"path":["fetch"],"cost":0}]
```

## shortest_path

`shortest_path/5`, lines 453 to 476:

```jq
# shortest_path, five arguments: the route with the lowest total weight (weights are numbers >= 0;
# anything else is an error), same output with cost the total. Among routes of equal cost, the one
# found first. It settles the nearest open node by scanning them all, with no priority queue: fine
# for a few thousand nodes, slow beyond.
def shortest_path(from; to; weight; $start; $goal):
  (first(.[] | (weight) | select(type != "number" or . < 0) | [.]) // null) as $bad
  | if $bad != null then error("shortest_path: an edge has weight \($bad[0] | tojson); weights must be numbers >= 0")
    else
    (group_by(from) | map({key: (.[0] | from | tojson), value: map([(to), (weight)])}) | from_entries) as $adj
    # d and open: node -> [cost, order found, node, via]
    | {d: {($start | tojson): [0, 0, $start, null]}, open: {($start | tojson): [0, 0, $start, null]}, done: {}, n: 1, stop: false}
    | until(.stop;
        (.open | [.[]] | if length == 0 then null else min_by([.[0], .[1]]) end) as $u
        | if $u == null or $u[2] == $goal then .stop = true
          else ($u[2] | tojson) as $uk
            | .open |= del(.[$uk]) | .done[$uk] = true
            | reduce $adj[$uk][]? as $e (.;
                ($e[0] | tojson) as $vk | ($u[0] + $e[1]) as $nd
                | if .done[$vk] then .
                  elif .d[$vk] == null then .d[$vk] = [$nd, .n, $e[0], $u[2]] | .open[$vk] = .d[$vk] | .n += 1
                  elif $nd < .d[$vk][0] then .d[$vk] = [$nd, .d[$vk][1], $e[0], $u[2]] | .open[$vk] = .d[$vk]
                  else . end)
          end)
    | .d as $d
    | if $d[$goal | tojson] == null then null
      else {path: ([$goal | recurse($d[tojson][3] | select(. != null))] | reverse), cost: $d[$goal | tojson][0]}
      end
    end;
```

The lowest total weight: Dijkstra's algorithm without a priority queue.

- **Check first.** `first(… | select(type != "number" or . < 0) | [.])` finds a weight that is not a non-negative number; the error names it.
- **`$adj`** here holds `[neighbour, weight]` pairs.
- **State.** `d`: the best known `[cost, order found, node, via]` per node. `open`: the nodes with a known cost that are not settled yet. `done`: the settled ones.
- **Each round.** `$u` is the open node with the lowest cost, the earliest found on a tie (`min_by([.[0], .[1]])`). If there is none, or it is the goal, stop: a settled node's cost is final. Otherwise `$u` moves from `open` to `done`, and each of its edges is tried: a neighbour not seen before gets a cost; one seen at a higher cost gets the lower one and its `via` changed; a settled one is left alone.
- **Path.** As in the four-argument form, following `via` back from the goal.

The scan for the lowest open node looks at every open node each round, so the time grows with nodes times open nodes. The comment says so; the measurement is in the spec's log.

Weights in minutes: fetch to compile 1, compile to test 1, test to package 1, fetch to lint 5, lint to package 5, docs to package 2. Through compile and test costs 3 with three edges; through lint costs 10 with two.

```jq
[["fetch", "compile", 1], ["compile", "test", 1], ["test", "package", 1], ["fetch", "lint", 5], ["lint", "package", 5], ["docs", "package", 2]]
| map({a: .[0], b: .[1], min: .[2]})
| shortest_path(.a; .b; .min; "fetch"; "package"),
  (try (map(.min = -1) | shortest_path(.a; .b; .min; "fetch"; "package")) catch .)
```

```json
{"path":["fetch","compile","test","package"],"cost":3}
"shortest_path: an edge has weight -1; weights must be numbers >= 0"
```

## topo_order

`topo_order/2`, lines 482 to 501:

```jq
# topo_order: a dependency order of the nodes of a directed graph. One row per node: {node, level},
# sorted by level then node: level 0 for a node nothing points to, otherwise one more than the
# highest level among the nodes that point to it, so every edge goes from a lower level to a higher
# one and the nodes of one level do not depend on each other. A cycle is an error naming a node on it.
def topo_order(from; to):
  ([.[] | (from), (to)] | unique) as $nodes
  | _adj(from; to) as $adj
  | (reduce .[] as $e (reduce $nodes[] as $n ({}; .[$n | tojson] = 0); .[$e | to | tojson] += 1)) as $deg0
  | . as $edges
  | {deg: $deg0, level: 0, frontier: [$nodes[] | select($deg0[tojson] == 0)], out: {}, k: 0, left: ($nodes | length)}
  | until((.frontier | length) == 0;
      .frontier as $f | .level as $lv
      | .out[.k | tostring] = ($f | map({node: ., level: $lv})) | .k += 1 | .left -= ($f | length) | .next = {}
      | reduce ($f[] | $adj[tojson][]?) as $v (.;
          ($v | tojson) as $vk | .deg[$vk] -= 1 | if .deg[$vk] == 0 then .next[$vk] = $v else . end)
      | .frontier = ([.next[]] | sort) | .level += 1)
  | if .left > 0
    then .deg as $deg
      # every node left has a node left pointing to it: walk back until one repeats; it is on a cycle
      | ($edges | map(select($deg[to | tojson] > 0 and $deg[from | tojson] > 0)) | _adj(to; from)) as $pred
      | ({cur: ([$nodes[] | select($deg[tojson] > 0)][0]), on: {}}
         | until(.on[.cur | tojson]; .on[.cur | tojson] = true | .cur = ($pred[.cur | tojson] | sort | .[0])) | .cur) as $c
      | error("topo_order: cycle through \($c | tojson)")
    else [.out[][]] | sort_by([.level, .node]) end;
```

A dependency order with levels.

- `$nodes`: every node named at either end of an edge, sorted. `$deg0`: for each, how many edges point to it.
- **Each round**: the frontier is the nodes with nothing left pointing to them. They get the current level and go into `out`; each edge out of them lowers its target's count by one, and a target that reaches zero joins `next`. `[.next[]] | sort` is the next frontier.
- A node therefore gets its level in the round after the last of its predecessors got theirs: one more than the highest level among them.
- **Cycle.** If nodes are left when the frontier runs empty, each of them has another left node pointing to it. `$pred` is the reversed graph among those nodes; walking back along it from any left node must come round to a node already visited, and that node is on a cycle. The walk always takes the smallest predecessor, so the node named is the same on every run.

```jq
[["fetch", "compile"], ["compile", "test"], ["test", "package"], ["fetch", "lint"], ["lint", "package"], ["docs", "package"]]
| map({a: .[0], b: .[1]})
| (topo_order(.a; .b) | map([.node, .level])),
  (try (. + [{a: "package", b: "compile"}] | topo_order(.a; .b)) catch .)
```

```json
[["docs",0],["fetch",0],["compile",1],["lint",1],["test",2],["package",3]]
"topo_order: cycle through \"compile\""
```

`package` is at level 3: one more than `test` (2), the highest of `test`, `lint` (1) and `docs` (0).

## components

`components/2`, lines 505 to 514:

```jq
# components: connected groups, edges read as undirected. One row per node: {node, component},
# where component is the smallest node of its group in jq's sort order. Rows sorted by node.
def components(a; b):
  ([.[] | [(a), (b)], [(b), (a)]] | group_by(.[0]) | map({key: (.[0][0] | tojson), value: map(.[1])}) | from_entries) as $adj
  | ([.[] | (a), (b)] | unique) as $nodes
  | reduce $nodes[] as $n ({seen: {}, parts: {}, k: 0};
      if .seen[$n | tojson] then .
      else (_search($adj; $n) | map(.node)) as $c
        | reduce $c[] as $m (.; .seen[$m | tojson] = true)
        | .parts[.k | tostring] = ($c | map({node: ., component: $n})) | .k += 1
      end)
  | [.parts[][]] | sort_by(.node);
```

Edges read as undirected. `$adj` therefore holds every edge in both directions (`[(a), (b)], [(b), (a)]`). Then, for each node in sorted order that is not yet in a group, `_search` finds its whole group; every member is marked seen and labelled with that node. Since nodes are taken in sorted order, the label is the smallest node of the group.

```jq
[["fetch", "compile"], ["lint", "fetch"], ["x", "y"]] | map({a: .[0], b: .[1]}) | components(.a; .b)
```

```json
[
  {"node": "compile", "component": "compile"},
  {"node": "fetch", "component": "compile"},
  {"node": "lint", "component": "compile"},
  {"node": "x", "component": "x"},
  {"node": "y", "component": "x"}
]
```
