"""check_primer: run every jq block of a Markdown page that is followed by a json block, on each
engine named, and compare the output with that block (compact JSON, one value per line).

Usage (from the repository root): python tools/check_primer.py docs/primer.md <jq binary> [<jq binary> ...]
Each program runs as `<binary> -c -n '<program>'`. Prints "<n> blocks, <m> differences"; exits 1 on any
difference. Blocks marked ```text or ```bash are not run.
"""
import json
import re
import subprocess
import sys


def compact(lines: str) -> list[str]:
    return [json.dumps(json.loads(line), separators=(",", ":")) for line in lines.strip().splitlines()]


def main() -> int:
    text = open(sys.argv[1]).read()
    blocks = re.findall(r"```jq\n(.*?)```\n\n```json\n(.*?)```", text, re.S)
    bad = 0
    for program, want in blocks:
        for engine in sys.argv[2:]:
            run = subprocess.run([engine, "-c", "-n", program.strip()], capture_output=True, text=True)
            got = compact(run.stdout) if run.returncode == 0 else [run.stderr.strip()]
            if got != compact(want):
                bad += 1
                print(f"{engine}: {program.strip()[:70]}\n  got  {got}\n  want {compact(want)}")
    print(f"{len(blocks)} blocks, {bad} differences")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
