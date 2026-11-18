"""make_fuzzy: write the fixtures for the approximate-matching cases, and their expected answers
from an implementation in Python that shares no code with analytics.jq.

Usage (from the repository root): python tests/make_fuzzy.py
Writes tests/fixtures/fuzzy_pairs.json, fuzzy_left.json, fuzzy_right.json and
tests/expected/fuzzy.json ({pairs: [similarity...], best: [{id, to, similarity}...]}), from a fixed seed.
"""
import json
import random
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORDS = ["north", "south", "clinic", "pharmacy", "radiology", "server", "laptop", "printer", "account", "request",
         "network", "storage", "billing", "surgery", "records", "ünïcode", "a", ""]
MIN = 0.4


def bigrams(s: str) -> set[str]:
    return {s[i:i + 2] for i in range(len(s) - 1)}


def similarity(a, b):
    if a is None or b is None:
        return None
    if a == b:
        return 1
    x, y = bigrams(a), bigrams(b)
    return 0 if not x or not y else 2 * len(x & y) / (len(x) + len(y))


def typo(rng: random.Random, s: str) -> str:
    if len(s) < 3 or rng.random() < 0.4:
        return s
    i = rng.randrange(len(s) - 1)
    return rng.choice([s[:i] + s[i + 1:], s[:i] + s[i + 1] + s[i] + s[i + 2:], s[:i] + "x" + s[i:], s.upper()])


def main() -> None:
    rng = random.Random(20261118)
    name = lambda: " ".join(rng.choice(WORDS) for _ in range(rng.randrange(1, 4))).strip()
    pairs = [[name(), typo(rng, name()) if rng.random() < 0.5 else None if rng.random() < 0.05 else name()] for _ in range(300)]
    pairs = [[a, typo(rng, a)] if rng.random() < 0.4 else [a, b] for a, b in pairs]
    right = [{"rid": i, "site": rng.choice(["N", "S", "E", None]), "dept": None if rng.random() < 0.03 else name()} for i in range(120)]
    left = [{"id": i, "site": rng.choice(["N", "S", "E", "W", None]),
             "name": None if rng.random() < 0.03 else typo(rng, rng.choice(right)["dept"] or name())} for i in range(150)]
    best = []
    for l in left:
        m = None
        if l["site"] is not None and l["name"] is not None:
            for r in right:
                if r["site"] == l["site"] and r["dept"] is not None:
                    s = similarity(l["name"], r["dept"])
                    if s >= MIN and (m is None or s > m[1]):
                        m = (r["rid"], s)
        best.append({"id": l["id"], "to": m[0] if m else None, "similarity": m[1] if m else None})
    dump = lambda p, v: (ROOT / p).write_text(json.dumps(v, ensure_ascii=False) + "\n")
    dump("tests/fixtures/fuzzy_pairs.json", pairs)
    dump("tests/fixtures/fuzzy_left.json", left)
    dump("tests/fixtures/fuzzy_right.json", right)
    dump("tests/expected/fuzzy.json", {"pairs": [similarity(a, b) for a, b in pairs], "best": best})


if __name__ == "__main__":
    main()
