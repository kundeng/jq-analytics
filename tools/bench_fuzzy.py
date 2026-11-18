"""bench_fuzzy: seconds join_fuzzy takes in the Python jq package, and how many comparisons that is.

Usage (from the repository root, with jq==1.13.0):
    python tools/bench_fuzzy.py <left rows> <right rows> <blocks>
Made-up names from a fixed seed, spread evenly over the blocks, so the join makes about
left * right / blocks comparisons. The time includes parsing the input text.
"""
import json
import random
import sys
import time
from pathlib import Path

import jq

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics"
WORDS = ["north", "south", "clinic", "pharmacy", "radiology", "server", "laptop", "printer", "account", "request"]


def main(n_left: int, n_right: int, blocks: int) -> dict:
    rng = random.Random(20261118)
    name = lambda: rng.choice(WORDS) + " " + rng.choice(WORDS) + " " + str(rng.randrange(100))
    left = [{"id": i, "b": rng.randrange(blocks), "name": name()} for i in range(n_left)]
    right = [{"rid": i, "b": rng.randrange(blocks), "dept": name()} for i in range(n_right)]
    text = json.dumps(left)
    t0 = time.perf_counter()
    matched = jq.compile(f'include "analytics" {{search: "{LIB}"}}; join_fuzzy($right; .b; .b; .name; .dept; 0.6; "m") | map(select(.m != null)) | length',
                         args={"right": right}).input_text(text).first()
    took = time.perf_counter() - t0
    comparisons = n_left * n_right // blocks
    return {"left": n_left, "right": n_right, "blocks": blocks, "comparisons_about": comparisons, "seconds": round(took, 2),
            "comparisons_per_second": round(comparisons / took), "matched": matched}


if __name__ == "__main__":
    print(json.dumps([main(2000, 2000, 20), main(2000, 2000, 200), main(20000, 20000, 2000)], indent=1))
