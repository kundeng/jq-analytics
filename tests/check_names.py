"""check_names: fail when a public function of analytics.jq has the name of an engine builtin.

Usage (from the repository root):
    python tests/check_names.py [<jq binary> ...]
With no binary named, uses jq, gojq and jaq from the PATH, whichever exist; the Python jq package
is checked too when it is installed. A def in an included module shadows a builtin of the same
name for everything written after the include, so a clash silently changes a caller's program.

A public function is a `def` at the start of a line whose name does not begin with `_`. An engine
is asked for its names with `-n 'builtins'`; one that cannot answer (jaq) is skipped and named in
the output. Prints one JSON object; exits 1 on any clash.
"""
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "src" / "jq_analytics" / "analytics.jq"


def public_defs(text: str) -> set[str]:
    return {m for m in re.findall(r"^def ([A-Za-z0-9_]+)", text, flags=re.M) if not m.startswith("_")}


def engine_builtins(binary: str) -> set[str] | None:
    out = subprocess.run([binary, "-n", "-c", "builtins"], capture_output=True, text=True)
    return {b.split("/")[0] for b in json.loads(out.stdout)} if out.returncode == 0 else None


def package_builtins() -> set[str] | None:
    try:
        import jq
    except ImportError:
        return None
    return {b.split("/")[0] for b in jq.compile("builtins").input_value(None).first()}


def check(binaries: list[str], lib: Path = LIB) -> dict:
    defs = public_defs(lib.read_text())
    sources = {b: engine_builtins(b) for b in binaries}
    sources["python jq package"] = package_builtins()
    clashes = {name: sorted(defs & names) for name, names in sources.items() if names is not None and defs & names}
    return {"public_defs": len(defs), "checked": sorted(n for n, v in sources.items() if v is not None),
            "skipped_no_builtins_list": sorted(n for n, v in sources.items() if v is None), "clashes": clashes}


if __name__ == "__main__":
    engines = sys.argv[1:] or [p for p in (shutil.which(n) for n in ("jq", "gojq", "jaq")) if p]
    report = check(engines)
    print(json.dumps(report, indent=1))
    sys.exit(1 if report["clashes"] else 0)
