"""readout: build the code read-out pages from analytics.jq and the notes.

Usage (from the repository root):
    python tools/readout.py [--all] [--stamp] [--list] <jq binary> [<jq binary> ...]

For every family (section of analytics.jq) that has docs/readout/notes/<family>.md, writes
docs/readout/<NN>-<family>.md: each note's definitions copied from analytics.jq with their line
numbers, the note, and the output of each `jq run` block. Stops, writing nothing, on a definition
with no note, a note naming no definition, a stale stamp, or a run whose output differs between
the engines. --all also stops when a family has no notes file. --stamp writes missing stamps into
the notes first. --list prints each family's definitions and whether a note covers them.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "src" / "jq_analytics"
SOURCE = LIB / "analytics.jq"
OUT = ROOT / "docs" / "readout"
NOTES = OUT / "notes"
SKIP = ("tzdata", "end of tzdata")
SECTION = re.compile(r"^# -{20,} (.+)$")
DEF = re.compile(r"^def ([A-Za-z_][A-Za-z0-9_]*)(\(([^)]*)\))?:")
HEADING = re.compile(r"^## (.+)$")
STAMP = re.compile(r"^<!-- code: ([0-9a-f]{8}) -->$")


def slug(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", name.split(":")[0].lower()).strip("-")


def parse(text: str) -> list[dict]:
    """Families in file order: {name, slug, intro, defs: [{key, first, last, comment, code}]}."""
    lines = text.split("\n")
    families: list[dict] = []
    current = None
    i = 0
    while i < len(lines):
        m = SECTION.match(lines[i])
        if m:
            name = m.group(1)
            current = None if name.startswith(SKIP) else {"name": name, "slug": slug(name), "intro": [], "defs": []}
            if current:
                families.append(current)
            i += 1
            continue
        d = DEF.match(lines[i])
        if d and current is not None:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("def ") and not lines[j].startswith("#"):
                j += 1
            while j > i + 1 and lines[j - 1].strip() == "":
                j -= 1
            c = i
            while c > 0 and lines[c - 1].startswith("# ") and not SECTION.match(lines[c - 1]):
                c -= 1
            arity = len([p for p in (d.group(3) or "").split(";") if p.strip()])
            current["defs"].append({
                "key": f"{d.group(1)}/{arity}", "first": i + 1, "last": j,
                "comment": lines[c:i], "code": [ln.rstrip() for ln in lines[i:j]],
            })
            i = j
            continue
        i += 1
    return families


def stamp_of(defs: list[dict]) -> str:
    return hashlib.sha256("\n".join("\n".join(d["code"]) for d in defs).encode()).hexdigest()[:8]


def read_notes(path: Path) -> list[dict]:
    """Notes in file order: {keys, stamp, body: [lines]}; text before the first heading is the family intro."""
    notes: list[dict] = []
    intro: list[str] = []
    for line in path.read_text().split("\n"):
        h = HEADING.match(line)
        if h:
            notes.append({"keys": [k.strip() for k in h.group(1).split(",")], "stamp": None, "body": []})
        elif not notes:
            intro.append(line)
        elif notes[-1]["stamp"] is None and not notes[-1]["body"] and STAMP.match(line):
            notes[-1]["stamp"] = STAMP.match(line).group(1)
        else:
            notes[-1]["body"].append(line)
    return [{"intro": intro}] + notes


def canonical(output: str) -> str:
    """The output with object keys sorted, so that engines that order keys differently (gojq sorts them) compare equal."""
    try:
        whole = lambda text: int(float(text)) if float(text).is_integer() else float(text)  # jaq prints 2.0 where jq prints 2
        return "\n".join(json.dumps(json.loads(line, parse_float=whole), sort_keys=True) for line in output.split("\n"))
    except ValueError:
        return output


def run(program: str, engines: list[str]) -> str:
    """The output of the first engine, after checking that every engine prints the same values."""
    outputs = []
    for engine in engines:
        p = subprocess.run([engine, "-c", "-n", "-L", str(LIB), 'include "analytics"; ' + program],
                           capture_output=True, text=True)
        outputs.append(p.stdout.strip() if p.returncode == 0 else "error: " + p.stderr.strip())
    if len({canonical(o) for o in outputs}) != 1:
        raise SystemExit("run differs between engines:\n" + program + "\n" + json.dumps(dict(zip(engines, outputs)), indent=1))
    if outputs[0].startswith("error: "):
        raise SystemExit("run failed:\n" + program + "\n" + outputs[0])
    return outputs[0]


def show(output: str) -> str:
    """One array element per line when the output is one array of rows; else as printed."""
    try:
        value = json.loads(output)
    except ValueError:
        return output
    if isinstance(value, list) and value and all(isinstance(v, (dict, list)) for v in value):
        return "[\n" + ",\n".join("  " + json.dumps(v, ensure_ascii=False) for v in value) + "\n]"
    if isinstance(value, dict) and len(output) > 100:
        return "{\n" + ",\n".join("  " + json.dumps(k) + ": " + json.dumps(v, ensure_ascii=False) for k, v in value.items()) + "\n}"
    return output


def render_body(body: list[str], engines: list[str]) -> list[str]:
    out: list[str] = []
    i = 0
    while i < len(body):
        if body[i].strip() == "```jq run":
            j = i + 1
            while body[j].strip() != "```":
                j += 1
            program = "\n".join(body[i + 1:j])
            out += ["```jq"] + body[i + 1:j] + ["```", "", "```json", show(run(program, engines)), "```"]
            i = j + 1
        else:
            out.append(body[i])
            i += 1
    return out


def tidy(lines: list[str]) -> str:
    """One blank line before every heading and never two in a row, outside code blocks."""
    out: list[str] = []
    fenced = False
    for line in "\n".join(lines).split("\n"):
        if line.startswith("```"):
            fenced = not fenced
        if not fenced and line.strip() == "" and out and out[-1].strip() == "":
            continue
        if not fenced and line.startswith("## ") and out and out[-1].strip() != "":
            out.append("")
        out.append(line)
    return "\n".join(out).rstrip("\n") + "\n"


def main() -> None:
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    engines = [a for a in sys.argv[1:] if not a.startswith("--")]
    families = parse(SOURCE.read_text())
    problems: list[str] = []
    pages: list[tuple[Path, str]] = []
    index = ["# Code read-out", "",
             "How each definition in `src/jq_analytics/analytics.jq` is written: the code as it stands, an explanation of each clause, and a small run. Generated by `tools/readout.py` from the library and the notes in `notes/`; edit those, not these pages.", "",
             "| Page | Family | Definitions |", "|---|---|---|"]
    listing = {}
    for n, family in enumerate(families):
        number = f"{(n + 1) * 5:02d}"
        path = NOTES / (family["slug"] + ".md")
        by_key = {d["key"]: d for d in family["defs"]}
        if not path.exists():
            listing[family["slug"]] = {"definitions": len(by_key), "noted": 0}
            if "--all" in flags:
                problems.append(f"{family['slug']}: no notes file")
            continue
        notes = read_notes(path)
        intro, notes = notes[0]["intro"], notes[1:]
        covered: set[str] = set()
        for note in notes:
            missing = [k for k in note["keys"] if k not in by_key]
            if missing:
                problems.append(f"{family['slug']}: note names no definition: {', '.join(missing)}")
                continue
            covered |= set(note["keys"])
            want = stamp_of([by_key[k] for k in note["keys"]])
            if note["stamp"] is None and "--stamp" in flags:
                note["stamp"] = want
            elif note["stamp"] is None:
                problems.append(f"{family['slug']}: note {note['keys'][0]} has no stamp (run with --stamp after reading the code)")
            elif note["stamp"] != want:
                problems.append(f"{family['slug']}: note {note['keys'][0]} is stale: the code is now {want}, the note was written for {note['stamp']}")
        left = [k for k in by_key if k not in covered]
        if left:
            problems.append(f"{family['slug']}: no note for {', '.join(left)}")
        listing[family["slug"]] = {"definitions": len(by_key), "noted": len(covered), "without_note": left}
        if "--stamp" in flags:
            lines = list(intro)
            for note in notes:
                lines += ["## " + ", ".join(note["keys"])] + ([f"<!-- code: {note['stamp']} -->"] if note["stamp"] else []) + note["body"]
            path.write_text("\n".join(lines).rstrip("\n") + "\n")
        if problems or "--list" in flags:
            continue
        page = [f"# {family['name'][0].upper() + family['name'][1:]}", "",
                f"Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/{family['slug']}.md`. Do not edit.", ""]
        page += render_body(intro, engines)
        notes.sort(key=lambda note: by_key[note["keys"][0]]["first"])
        for note in notes:
            defs = [by_key[k] for k in note["keys"]]
            names = ", ".join("`" + k.split("/")[0] + "`" for k in dict.fromkeys(note["keys"]))
            page += ["## " + ", ".join(dict.fromkeys(k.split("/")[0] for k in note["keys"])), ""]
            for d in defs:
                where = f"lines {d['first']} to {d['last']}" if d["last"] > d["first"] else f"line {d['first']}"
                page += [f"`{d['key']}`, {where}:", "", "```jq"] + d["comment"] + d["code"] + ["```", ""]
            page += render_body(note["body"], engines)
        pages.append((OUT / f"{number}-{family['slug']}.md", tidy(page)))
        index.append(f"| [{number}]({number}-{family['slug']}.md) | {family['name']} | {len(by_key)} |")
    if "--list" in flags:
        print(json.dumps(listing, indent=1))
        return
    if problems:
        raise SystemExit("read-out not built:\n" + "\n".join(problems))
    for path, text in pages:
        path.write_text(text)
    (OUT / "README.md").write_text("\n".join(index) + "\n")
    print(json.dumps({"pages": len(pages), "families": len(families),
                      "definitions": sum(v["definitions"] for v in listing.values()),
                      "noted": sum(v["noted"] for v in listing.values())}))


if __name__ == "__main__":
    main()
