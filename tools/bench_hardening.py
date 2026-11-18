"""bench_hardening: seconds, in the Python jq package, for the functions spec 55 changes for speed.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_hardening.py
Each workload is generated in jq itself, so the time is the function's own work with no parsing:
rank_by over one partition; pivot with every value in one cell; retention over 365 periods;
nested_from_nodes with every node under one root; and parse_ts on 200,000 timestamps, which spec 55
makes do more work. Prints one row per workload and size.
"""
import json
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"
WORK = [
    ("rank_by, one partition", [2000, 4000, 8000],
     '[range({n}) | {{g: 1, x: (. % 97)}}] | over(.g; .x; "r"; rank_by(.x)) | length'),
    ("pivot, one cell", [20000, 40000, 80000],
     '[range({n}) | {{k: 1, c: "a", v: .}}] | pivot(["a"]; {{k}}; .c; .v; length) | length'),
    ("retention, 365 periods", [20000, 40000],
     '[range(365)] as $p | [range({n}) as $i | {{e: $i, p: ($i % 365)}}, {{e: $i, p: (($i * 7 + 3) % 365)}}] | retention(.e; .p; $p) | length'),
    ("nested_from_nodes, one root", [20000, 40000, 80000],
     '[{{id: 0, p: null}}] + [range(1; {n}) | {{id: ., p: 0}}] | nested_from_nodes(.id; .p; "kids") | .[0].kids | length'),
    ("parse_ts", [200000],
     '[range({n}) | 1767225600 + . * 61 | todate | .[0:10] + " " + .[11:19]] | map(parse_ts) | length'),
]


def main() -> None:
    rows = []
    for name, sizes, program in WORK:
        for n in sizes:
            t0 = time.perf_counter()
            jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program.format(n=n)).input_value(None).first()
            rows.append({"workload": name, "n": n, "seconds": round(time.perf_counter() - t0, 2)})
    print(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
