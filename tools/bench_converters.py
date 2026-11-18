"""bench_converters: seconds the shape converters take in the Python jq package at a given size.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_converters.py <rows>
Made-up input from a fixed seed: <rows> requests, each with a nested `user` object and 0 to 3
tags (unnest, flatten_fields, to_csv, to_map, rows_from_map); <rows>/10 hourly counts for 20 sites
with one hour in five missing (fill_grid); a shallow tree of <rows> nodes, each under a random
earlier node (nested_from_nodes, nodes_from_nested; a deep tree is much slower, because tree_paths
walks every node's ancestry); <rows> edges among <rows>/2 nodes (node_link).
Each time includes parsing the input text. Prints a JSON object of {converter: seconds}.
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
    jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program + " | length").input_text(text).first()
    return round(time.perf_counter() - t0, 2)


def main(n: int) -> dict:
    rng = random.Random(20261118)
    tags = ["vpn", "laptop", "badge", "mail", "print"]
    reqs = [{"id": f"REQ{i:07d}", "user": {"name": f"user{rng.randrange(500):03d}", "dept": {"code": rng.choice("ABCDE")}},
             "tags": rng.sample(tags, rng.randrange(4)), "hours": round(rng.random() * 40, 1)} for i in range(n)]
    hourly = [{"site": f"s{s:02d}", "hour": h * 3600, "requests": rng.randrange(50)}
              for s in range(20) for h in range(n // 200) if rng.random() > 0.2]
    nodes = [{"id": i, "parent": None if i == 0 else rng.randrange(i)} for i in range(n)]  # shallow: depth grows with log(n)
    edges = [{"from": rng.randrange(n // 2), "to": rng.randrange(n // 2)} for _ in range(n)]
    flat = [{"id": r["id"], "hours": r["hours"]} for r in reqs]
    return {
        "rows": n,
        "unnest": timed('unnest(.tags; "tag")', reqs),
        "unnest_outer": timed('unnest_outer(.tags; "tag")', reqs),
        "flatten_fields": timed('flatten_fields(".")', reqs),
        "to_map": timed("to_map(.id)", flat),
        "rows_from_map": timed('to_map(.id) | rows_from_map("id")', flat),
        "to_csv": timed('[to_csv(["id", "hours"])]', flat),
        "fill_grid": timed('fill_grid(["site"]; "hour"; 3600; {requests: 0})', hourly),
        "fill_grid_rows_in": len(hourly),
        "nested_from_nodes": timed('nested_from_nodes(.id; .parent; "children")', nodes),
        "nodes_round_trip": timed('nested_from_nodes(.id; .parent; "children") | nodes_from_nested(.id; .children)', nodes),
        "node_link": timed("node_link(.from; .to) | .nodes", edges),
    }


if __name__ == "__main__":
    print(json.dumps(main(int(sys.argv[1])), indent=1))
