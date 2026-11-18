"""bench_event_paths: seconds the funnel and retention functions take in the Python jq package.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_event_paths.py <events>
Made-up events from a fixed seed: <events> events of five steps over <events>/8 entities, and
<events> visits over <events>/8 entities and 12 months. Each time includes parsing the input text.
"""
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"


def timed(program: str, value: object) -> tuple[float, object]:
    text = json.dumps(value)
    t0 = time.perf_counter()
    out = jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program).input_text(text).first()
    return round(time.perf_counter() - t0, 2), out


def main(n: int) -> dict:
    rng = random.Random(20261118)
    events = [{"u": f"u{rng.randrange(n // 8 + 1)}", "t": rng.randrange(100000),
               "step": rng.choice(["view", "view", "cart", "pay", "search"])} for _ in range(n)]
    months = [f"2026-{m:02d}" for m in range(1, 13)]
    visits = [{"u": f"v{rng.randrange(n // 8 + 1)}", "m": rng.choice(months)} for _ in range(n)]
    f_s, counts = timed('funnel(.u; .t; .step; ["view", "cart", "pay"]; 3600) | map(.entities)', events)
    fn_s, _ = timed('funnel(.u; .t; .step; ["view", "cart", "pay"]; null) | map(.entities)', events)
    r_s, cells = timed(f'retention(.u; .m; {json.dumps(months)}) | length', visits)
    c_s, _ = timed(f'cohorts(.u; .m; {json.dumps(months)}) | length', visits)
    return {"events": n, "funnel_window_s": f_s, "funnel_counts": counts, "funnel_no_window_s": fn_s,
            "retention_s": r_s, "retention_rows": cells, "cohorts_s": c_s}


if __name__ == "__main__":
    print(json.dumps(main(int(sys.argv[1])), indent=1))
