"""run_tests: run every case of tests/cases.json on each jq engine and the Python jq package, and
compare each answer with DuckDB's.

Usage (from the repository root):
    uv run --no-project --python 3.13 --with jq==1.13.0 --with duckdb==2.0.0 \
        python -I tests/run_tests.py [<jq binary> ...]
With no binary named, uses jq, gojq and jaq from the PATH, whichever exist.

Expected answer, per case, from the first of:
  expect_value  a literal
  expect_file   a recorded answer file, narrowed by the jq filter expect_jq (run in the jq package)
  sql           tests/sql/<view> then tests/sql/<sql> in one DuckDB connection; the last query's
                single row has a column `result`
  expect_error  no answer: the run must fail with a message holding this text
Each engine runs `<binary> -c -L src/jq_analytics [--argjson <var> <file>] 'include "analytics"; <jq>' <input>`;
the package compiles 'include "analytics" {search: "<lib dir>"}; <jq>' with args={var: value}.
Numbers match within 1e-9 relative; everything else must be equal, and a field missing on one side
is a difference. Prints one JSON object; exits 1 if any case fails anywhere.
"""
import importlib.metadata
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import duckdb
import jq

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "src" / "jq_analytics"
TESTS = ROOT / "tests"


def diffs(a: object, b: object, path: str = "") -> list[str]:
    if isinstance(a, bool) or isinstance(b, bool):
        return [] if a is b else [f"{path}: {a!r} != {b!r}"]
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return [] if abs(a - b) <= 1e-9 * max(1.0, abs(a), abs(b)) else [f"{path}: {a!r} != {b!r}"]
    if isinstance(a, dict) and isinstance(b, dict):
        out = [f"{path}.{k}: missing on one side" for k in sorted(set(a) ^ set(b))]
        for k in a.keys() & b.keys():
            out += diffs(a[k], b[k], f"{path}.{k}")
        return out
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return [f"{path}: length {len(a)} != {len(b)}"]
        return [d for i, (x, y) in enumerate(zip(a, b)) for d in diffs(x, y, f"{path}[{i}]")]
    return [] if a == b else [f"{path}: {a!r} != {b!r}"]


def expected(case: dict) -> object:
    if "expect_value" in case:
        return case["expect_value"]
    if "expect_file" in case:
        return jq.compile(case["expect_jq"]).input_text((ROOT / case["expect_file"]).read_text()).first()
    con = duckdb.connect()
    for name in ([case["view"]] if isinstance(case.get("view"), str) else []) + [case["sql"]]:
        rel = con.execute((TESTS / "sql" / name).read_text())
    value = rel.fetchone()[0]
    return json.loads(value) if isinstance(value, str) else value


def vars_text(case: dict) -> dict[str, str]:
    return {name: (ROOT / f).read_text() for name, f in case.get("vars", {}).items()}


def run_engine(binary: str, case: dict) -> object:
    args = [a for name, text in vars_text(case).items() for a in ("--argjson", name, text)]
    out = subprocess.run([binary, "-c", "-L", str(LIB), *args, 'include "analytics"; ' + case["jq"], str(ROOT / case["input"])],
                         capture_output=True, text=True, cwd=ROOT)
    return json.loads(out.stdout) if out.returncode == 0 else {"error": out.stderr.strip()}


def run_package(case: dict) -> object:
    args = {name: json.loads(text) for name, text in vars_text(case).items()}
    try:
        program = f'include "analytics" {{search: "{LIB}"}}; ' + case["jq"]
        return jq.compile(program, args=args).input_text((ROOT / case["input"]).read_text()).first()
    except Exception as exc:  # the package raises ValueError for jq errors
        return {"error": str(exc)}


def judge(case: dict, want: object, got: object) -> list[str]:
    if "expect_error" in case:
        ok = isinstance(got, dict) and case["expect_error"] in str(got.get("error", ""))
        return [] if ok else [f"expected an error containing {case['expect_error']!r}, got {str(got)[:200]}"]
    return diffs(want, got)[:4]


def version(binary: str) -> str:
    out = subprocess.run([binary, "--version"], capture_output=True, text=True)
    return (out.stdout or out.stderr).strip().splitlines()[0]


def main() -> None:
    os.chdir(ROOT)  # the answer SQL reads fixtures by paths relative to the repository root
    engines = sys.argv[1:] or [p for p in (shutil.which(n) for n in ("jq", "gojq", "jaq")) if p]
    cases = json.loads((TESTS / "cases.json").read_text())
    want = {c["name"]: None if "expect_error" in c else expected(c) for c in cases}
    runners = [(f"{b} ({version(b)})", lambda c, b=b: run_engine(b, c)) for b in engines]
    runners.append((f"python jq package {importlib.metadata.version('jq')}", run_package))
    report = []
    for label, run in runners:
        failures = [{"case": c["name"], "diffs": d} for c in cases if (d := judge(c, want[c["name"]], run(c)))]
        report.append({"engine": label, "passed": len(cases) - len(failures), "of": len(cases), "failures": failures})
    print(json.dumps({"cases": len(cases), "engines": report}, indent=1))
    sys.exit(1 if any(r["failures"] for r in report) else 0)


if __name__ == "__main__":
    main()
