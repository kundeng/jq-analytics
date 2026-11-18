"""bench_weighted_path: seconds the weighted shortest_path takes in the Python jq package, with the goal at a known distance.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_weighted_path.py <edges> [<edges> ...]
For each number of edges, from a fixed seed: a random directed graph with one node per four edges and
whole-number weights from 1 to 19. Three goals from node 0: the node a reference search settles
100th, the node it settles last, and a node that does not exist, which makes the search settle every
reachable node. The reference is Dijkstra's algorithm with a heap, written here in Python; its cost
is compared with jq's, and it supplies how many nodes are settled before the goal. Each time
includes parsing the input text.
"""
import heapq
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"


def reference(edges: list[dict], start: int) -> list[tuple[int, int]]:
    """Nodes in the order Dijkstra settles them, each with its cost."""
    adj: dict[int, list[tuple[int, int]]] = {}
    for e in edges:
        adj.setdefault(e["a"], []).append((e["b"], e["w"]))
    best = {start: 0}
    heap = [(0, start)]
    done: set[int] = set()
    order = []
    while heap:
        cost, node = heapq.heappop(heap)
        if node in done:
            continue
        done.add(node)
        order.append((node, cost))
        for nxt, weight in adj.get(node, []):
            if nxt not in done and cost + weight < best.get(nxt, float("inf")):
                best[nxt] = cost + weight
                heapq.heappush(heap, (cost + weight, nxt))
    return order


def main(n_edges: int) -> dict:
    rng = random.Random(20261118)
    n_nodes = n_edges // 4
    edges = [{"a": rng.randrange(n_nodes), "b": rng.randrange(n_nodes), "w": rng.randrange(1, 20)} for _ in range(n_edges)]
    order = reference(edges, 0)
    text = json.dumps(edges)
    out = {"edges": n_edges, "nodes": n_nodes, "reachable_from_start": len(order), "goals": []}
    for label, pick in (("settled 100th", order[99]), ("settled last", order[-1]), ("no such node", (-1, None))):
        goal, want = pick
        t0 = time.perf_counter()
        got = jq.compile(f'include "analytics" {{search: "{LIB}"}}; shortest_path(.a; .b; .w; 0; {goal}) | if . == null then null else .cost end').input_text(text).first()
        out["goals"].append({"goal": label, "seconds": round(time.perf_counter() - t0, 2), "cost": got, "equals_reference": got == want})
    return out


if __name__ == "__main__":
    print(json.dumps([main(int(a)) for a in sys.argv[1:]], indent=1))
