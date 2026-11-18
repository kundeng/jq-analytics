"""bench_profiles: seconds the distribution, profile and diff functions take in the Python jq package.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_profiles.py <rows>
Made-up rows from a fixed seed: an id, two numbers, a label out of 40 and a field that is often
null; for the diff, a second version with a tenth of the rows changed, a twentieth removed and a
twentieth added. Each time includes parsing the input text.
"""
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"


def timed(program: str, value: object, args: dict | None = None) -> float:
    text = json.dumps(value)
    t0 = time.perf_counter()
    jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program, args=args or {}).input_text(text).first()
    return round(time.perf_counter() - t0, 2)


def main(n: int) -> dict:
    rng = random.Random(20261118)
    rows = [{"id": i, "x": round(rng.uniform(0, 100), 2), "y": round(rng.gauss(50, 20), 2),
             "label": f"l{int(rng.expovariate(0.2)) % 40:02d}", "note": rng.choice([None, None, "", "ok"])} for i in range(n)]
    old = [dict(r, x=r["x"] + 1) if rng.random() < 0.1 else r for r in rows if rng.random() > 0.05]
    old += [{"id": n + i, "x": 1, "y": 1, "label": "l00", "note": None} for i in range(n // 20)]
    return {"rows": n,
            "mode": timed("map(.label) | mode", rows),
            "value_counts": timed("map(.label) | value_counts | length", rows),
            "histogram": timed("map(.x) | histogram(bin_edges(0; 100; 20)) | length", rows),
            "corr": timed("corr(.x; .y)", rows),
            "profile": timed("profile | length", rows),
            "diff_tables": timed("diff_tables($old; .id) | length", rows, {"old": old})}


if __name__ == "__main__":
    print(json.dumps(main(int(sys.argv[1])), indent=1))
