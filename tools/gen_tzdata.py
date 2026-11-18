"""gen_tzdata: write the UTC-offset transitions of a few IANA zones into analytics.jq's tzdata block,
so the library is one file.

Usage: python gen_tzdata.py <analytics.jq>   (run with the `tzdata` package pinned; PYTHONTZPATH is
cleared so zoneinfo reads that package, not the operating system's copy)

For each zone the block holds two parallel arrays: `t`, the UTC epoch seconds at which a new
offset starts (the first entry is a sentinel far in the past), and `o`, the offset in seconds that
starts there. A lookup takes the last `t` at or before an instant. Transitions are found by stepping
one day at a time from 1970 to 2100 and bisecting to the second inside a day whose offset changed.
"""
import importlib.metadata
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

os.environ["PYTHONTZPATH"] = ""
from zoneinfo import ZoneInfo, reset_tzpath  # noqa: E402  (must follow the env change)

reset_tzpath([])

ZONES: list[str] = ["UTC", "America/Detroit", "America/New_York", "America/Chicago",
                    "America/Denver", "America/Los_Angeles", "Europe/London"]
START = datetime(1970, 1, 1, tzinfo=timezone.utc)
END = datetime(2100, 1, 1, tzinfo=timezone.utc)
SENTINEL: int = -10**15  # before any instant a caller can pass


def offset_at(zone: ZoneInfo, instant: datetime) -> int:
    return int(instant.astimezone(zone).utcoffset().total_seconds())


def transitions(name: str) -> dict[str, list[int]]:
    zone = ZoneInfo(name)
    t, o = [SENTINEL], [offset_at(zone, START)]
    day = START
    while day < END:
        nxt = day + timedelta(days=1)
        if offset_at(zone, nxt) != offset_at(zone, day):
            lo, hi = int(day.timestamp()), int(nxt.timestamp())
            # bisect to the first second carrying the new offset
            while hi - lo > 1:
                mid = (lo + hi) // 2
                if offset_at(zone, datetime.fromtimestamp(mid, timezone.utc)) == o[-1]:
                    lo = mid
                else:
                    hi = mid
            t.append(hi)
            o.append(offset_at(zone, datetime.fromtimestamp(hi, timezone.utc)))
        day = nxt
    return {"t": t, "o": o}


BLOCK_BEGIN = "# ---------------------------------------------------------------- tzdata (generated, do not edit)\n"
BLOCK_END = "# ---------------------------------------------------------------- end of tzdata\n"


def block(rules: dict, version: str) -> str:
    return (BLOCK_BEGIN
            + f"# Written by gen_tzdata.py from the tzdata package {version}; regenerate, never edit by hand.\n"
            + "# tz_rules[zone] = {t: UTC epoch seconds where an offset starts (sorted), o: that offset in seconds}.\n"
            + f"# Covers 1970 to 2100 for: {', '.join(ZONES)}.\n"
            + f"def tzdata_version: {json.dumps(version)};\n"
            + f"def tz_rules: {json.dumps(rules, separators=(',', ':'))};\n"
            + BLOCK_END)


def main() -> None:
    """Rewrite the tzdata block of analytics.jq (argv[1]) in place, so the library is one file. The
    block must already be there, between BLOCK_BEGIN and BLOCK_END, once; anything else is an error."""
    lib = Path(sys.argv[1])
    text = lib.read_text()
    if text.count(BLOCK_BEGIN) != 1 or text.count(BLOCK_END) != 1 or text.index(BLOCK_BEGIN) > text.index(BLOCK_END):
        raise SystemExit(f"{lib}: expected one tzdata block between the BLOCK_BEGIN and BLOCK_END markers")
    rules = {z: transitions(z) for z in ZONES}
    version = importlib.metadata.version("tzdata")
    head, rest = text.split(BLOCK_BEGIN)
    lib.write_text(head + block(rules, version) + rest.split(BLOCK_END, 1)[1])
    print(json.dumps({"tzdata": version, "zones": {z: len(r["t"]) - 1 for z, r in rules.items()}}))


if __name__ == "__main__":
    main()
