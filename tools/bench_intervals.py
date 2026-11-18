"""bench_intervals: seconds the interval functions take in the Python jq package at a given size.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_intervals.py <events>
Made-up lease events from a fixed seed: <events> grants, renewals and releases over <events>/50
addresses and <events>/40 devices, time to live 1,800 s; then <events>/4 moments to look up.
Each time includes parsing the input text. Prints a JSON object of seconds.
"""
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"
BUILD = 'intervals_from_events(.ip; .mac; .t; .kind; .ttl)'


def timed(program: str, value: object, args: dict | None = None) -> tuple[float, object]:
    text = json.dumps(value)
    t0 = time.perf_counter()
    out = jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + program, args=args or {}).input_text(text).first()
    return round(time.perf_counter() - t0, 2), out


def main(n: int) -> dict:
    rng = random.Random(20261118)
    t, events = 0, []
    for _ in range(n):
        t += rng.randrange(0, 4)
        events.append({"ip": f"10.0.{rng.randrange(n // 50 + 1) // 250}.{rng.randrange(n // 50 + 1) % 250}",
                       "mac": f"d{rng.randrange(n // 40 + 1)}", "t": t,
                       "kind": "release" if rng.random() < 0.1 else "hold", "ttl": 1800})
    hits = [{"src": rng.choice(events)["ip"], "at": rng.randrange(t + 1)} for _ in range(n // 4)]
    build_s, intervals = timed(BUILD, events)
    within_s, matched = timed('join_within($iv; .src; .resource; .at; .start; .end) | map(select(.holder != null)) | length', hits, {"iv": intervals})
    merge_s, merged = timed('merge_intervals(.resource; .start; .end) | length', intervals)
    conc_s, peak = timed('concurrency(.start; .end) | max_by(.open) | .open', intervals)
    return {"events": n, "intervals": len(intervals), "intervals_from_events_s": build_s,
            "lookups": len(hits), "matched": matched, "join_within_s": within_s,
            "merge_intervals_s": merge_s, "merged_rows": merged, "concurrency_s": conc_s, "peak_open": peak}


if __name__ == "__main__":
    print(json.dumps(main(int(sys.argv[1])), indent=1))
