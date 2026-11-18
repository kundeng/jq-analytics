"""made_up_incidents: a made-up incident table with ten string fields shaped like an IT service desk's
export, for the test cases that ask questions of service requests.

Usage (from the repository root): python tests/make_incidents.py tests/fixtures/made_up_incidents.json

Rows are drawn from a fixed seed, so the file is the same on every
run. What the shape keeps, because the cases depend on it:
  - timestamps are UTC wall clocks "YYYY-MM-DD HH:MM:SS" from 3 August to 13 November 2026, so the
    1 November switch to winter time in Detroit falls inside the data
  - about 1 in 40 rows is unresolved (resolved_at and closed_at are "")
  - resolution takes from minutes to several days, so "within a day" is neither all nor none
  - three assignment groups and four states ("2", "3", "6", "7"), so groups and levels have
    several members
"""
import json
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path

SEED = 20261117
ROWS = 600
START = datetime(2026, 8, 3)
DAYS = 103
GROUPS = ["Access Team A", "Access Team B", "Service Desk"]
SUBCATEGORIES = ["new account", "account change", "password"]
CONTACT = ["self-service", "phone", "email"]


def made_up_incidents(rng: random.Random) -> list[dict[str, str]]:
    rows = []
    for n in range(ROWS):
        opened = START + timedelta(days=rng.randrange(DAYS), hours=rng.choice(range(11, 24)),
                                   minutes=rng.randrange(60), seconds=rng.randrange(60))
        open_still = rng.random() < 0.025
        hours = rng.choice([rng.uniform(0.1, 4), rng.uniform(4, 24), rng.uniform(24, 120)])
        resolved = "" if open_still else (opened + timedelta(hours=hours)).strftime("%Y-%m-%d %H:%M:%S")
        rows.append({
            "number": f"REQ{9000001 + n:07d}",
            "opened_at": opened.strftime("%Y-%m-%d %H:%M:%S"),
            "resolved_at": resolved,
            "closed_at": resolved,
            "state": rng.choice(["2", "3"]) if open_still else rng.choices(["6", "7"], [1, 20])[0],
            "contact_type": rng.choice(CONTACT),
            "category": "account",
            "subcategory": rng.choice(SUBCATEGORIES),
            "assignment_group": rng.choice(GROUPS),
            "opened_by": f"user{rng.randrange(1, 60):03d}",
        })
    return sorted(rows, key=lambda r: r["opened_at"])


if __name__ == "__main__":
    Path(sys.argv[1]).write_text(json.dumps(made_up_incidents(random.Random(SEED)), indent=1) + "\n")
