"""bench_graphs: seconds the tree and graph functions take in the Python jq package at growing sizes.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_graphs.py <n> [<n> ...]
For each n, from a fixed seed: a random tree of n edges (each node under a random earlier one), read
as a graph for reachable, hops, components and topo_order, and as node rows for tree_paths; a deep
tree (each node under one of the 50 before it) for tree_paths; and, at min(n, 4000) edges with
random weights, the weighted shortest_path. Each time includes parsing the input text.
"""
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"


def timed(program: str, value: object) -> float:
    text = json.dumps(value)
    t0 = time.perf_counter()
    jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program).input_text(text).first()
    return round(time.perf_counter() - t0, 2)


def main(n: int) -> dict:
    rng = random.Random(20261118)
    edges = [{"a": rng.randrange(i), "b": i} for i in range(1, n)]
    wide = [{"id": 0, "parent": None}] + [{"id": e["b"], "parent": e["a"]} for e in edges]
    deep = [{"id": i, "parent": None if i == 0 else rng.randrange(max(0, i - 50), i)} for i in range(n)]
    m = min(n, 4000)
    weighted = [{"a": rng.randrange(m // 4), "b": rng.randrange(m // 4), "w": rng.randrange(1, 20)} for _ in range(m)]
    return {"n": n,
            "reachable": timed("reachable(.a; .b; 0) | length", edges),
            "hops": timed("hops(.a; .b; 0) | length", edges),
            "components": timed("components(.a; .b) | length", edges),
            "topo_order": timed("topo_order(.a; .b) | length", edges),
            "tree_paths_shallow": timed("tree_paths(.id; .parent) | length", wide),
            "tree_paths_deep": timed("tree_paths(.id; .parent) | length", deep),
            "shortest_path_by_hops": timed(f"shortest_path(.a; .b; 0; {n - 1}) | .cost", edges),
            "shortest_path_weighted_edges": m,
            "shortest_path_weighted": timed(f"shortest_path(.a; .b; .w; 0; {m // 4 - 1}) | .cost", weighted)}


if __name__ == "__main__":
    print(json.dumps([main(int(a)) for a in sys.argv[1:]]))
