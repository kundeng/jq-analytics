"""bench_rows: how long the library's questions take at a given number of rows, in the Python jq
package and in DuckDB, each answer checked against the other.

Usage (from the repository root, with jq==1.13.0 and duckdb==2.0.0):
    python tools/bench_rows.py <rows> [case ...]
Generates a made-up table of <rows> service requests (tests/make_incidents.py's generator and seed)
in a temporary file, then runs each case in its own child process:
  jq      the case's program from tests/cases.json, compiled with the library, on the file's text:
          parsing and computing, as a Python caller pays them
  duckdb  the case's view SQL pointed at the file, then its answer SQL, in one connection: reading
          and parsing the file is inside the time; starting Python and importing DuckDB are not
A case still running after TIMEOUT_S is reported as timed out. DuckDB uses every core; jq one.
Prints a JSON array of {case, rows, jq_s, jq_peak_mb, duckdb_s, same_answer}.
"""
import json
import random
import resource
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
import make_incidents  # noqa: E402
from run_tests import LIB, TESTS, diffs  # noqa: E402

CASES = ["made_up_resolved_summary", "made_up_office_hours", "made_up_top_days", "made_up_lag_within_day",
         "made_up_asof_last_resolution", "made_up_day_volume_join", "made_up_context_months"]
FIXTURE = "tests/fixtures/made_up_incidents.json"
TIMEOUT_S = 300


def write_rows(path: Path, rows: int) -> None:
    make_incidents.ROWS = rows
    path.write_text(json.dumps(make_incidents.made_up_incidents(random.Random(make_incidents.SEED))))


def case_by_name(name: str) -> dict:
    return next(c for c in json.loads((TESTS / "cases.json").read_text()) if c["name"] == name)


def run_jq(name: str, path: str) -> dict:
    import jq
    text = Path(path).read_text()
    t0 = time.perf_counter()
    answer = jq.compile(f'include "analytics" {{search: "{LIB}"}}; ' + case_by_name(name)["jq"]).input_text(text).first()
    took = time.perf_counter() - t0
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return {"answer": answer, "s": round(took, 2), "peak_mb": round(peak / (2**20 if sys.platform == "darwin" else 2**10))}


def run_duckdb(name: str, path: str) -> dict:
    import duckdb
    case, con = case_by_name(name), duckdb.connect()
    t0 = time.perf_counter()
    for sql in ([case["view"]] if isinstance(case.get("view"), str) else []) + [case["sql"]]:
        rel = con.execute((TESTS / "sql" / sql).read_text().replace(FIXTURE, path))
    value = rel.fetchone()[0]
    return {"answer": json.loads(value) if isinstance(value, str) else value, "s": round(time.perf_counter() - t0, 2)}


def child(engine: str, name: str, path: str) -> dict:
    try:
        out = subprocess.run([sys.executable, "-I", __file__, "--one", engine, name, path], capture_output=True,
                             text=True, timeout=TIMEOUT_S, cwd=ROOT)
    except subprocess.TimeoutExpired:
        return {"answer": None, "s": None, "peak_mb": None}
    if out.returncode != 0:
        raise RuntimeError(f"{engine} {name}: {out.stderr[-600:]}")
    return json.loads(out.stdout)


def main() -> None:
    if sys.argv[1] == "--one":
        engine, name, path = sys.argv[2:5]
        print(json.dumps((run_jq if engine == "jq" else run_duckdb)(name, path)))
        return
    rows = int(sys.argv[1])
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / f"made_up_{rows}.json"
        write_rows(path, rows)
        report = []
        for name in sys.argv[2:] or CASES:
            d, j = child("duckdb", name, str(path)), child("jq", name, str(path))
            done = d["s"] is not None and j["s"] is not None
            report.append({"case": name, "rows": rows, "jq_s": j["s"] if j["s"] is not None else f">{TIMEOUT_S}",
                           "jq_peak_mb": j.get("peak_mb"), "duckdb_s": d["s"] if d["s"] is not None else f">{TIMEOUT_S}",
                           "same_answer": (not diffs(d["answer"], j["answer"])) if done else None})
            print(json.dumps(report[-1]), file=sys.stderr)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
