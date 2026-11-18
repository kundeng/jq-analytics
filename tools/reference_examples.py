"""reference_examples: run every example of README.md and write its program and output into the README.

Usage (from the repository root): python tools/reference_examples.py <jq binary> [<jq binary> ...]

Each example is a jq program run with `-c -L src/jq_analytics 'include "analytics"; <program>'`, either on
SAMPLE (the four made-up incidents) or with `-n`. Every listed engine must print the same output, or
the script stops without writing. The README's `<!-- example: id -->` … `<!-- /example -->` blocks are
replaced by the program in a jq block and the output in a json block, one array element per line.
Prints {example id: "same on N engines"}.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "src" / "jq_analytics"
README = ROOT / "README.md"

SAMPLE = [
    {"number": "REQ0001", "opened_at": "2026-08-12 13:30:00", "resolved_at": "2026-08-12 16:00:00", "group": "access"},
    {"number": "REQ0002", "opened_at": "2026-08-14 23:10:00", "resolved_at": "2026-08-15 10:40:00", "group": "access"},
    {"number": "REQ0003", "opened_at": "2026-08-17 15:00:00", "resolved_at": "", "group": "devices"},
    {"number": "REQ0004", "opened_at": "2026-11-02 14:00:00", "resolved_at": "2026-11-02 15:00:00", "group": "access"},
]

PREP = ('map(.opened = (.opened_at | parse_ts) | .resolved = (.resolved_at | parse_ts)'
        ' | .hours = hours_between(.opened; .resolved))')
FLAG = (PREP + ' | map(select(.resolved != null) | (.opened | local_time($det)) as $o'
        ' | .in_hours = ($o.weekday >= 1 and $o.weekday <= 5 and $o.hour >= 8 and $o.hour <= 16))')
ANSWER = 'tz("America/Detroit") as $det | ' + FLAG + ' | group_agg({in_hours}; map(.hours) | {n: length, median: quantile_disc(0.5)})'

LEFT = '[{id: 1, k: "a"}, {id: 2, k: "b"}, {id: 3, k: "z"}, {id: 4, k: null}]'
RIGHT = '[{rk: "a", rv: "A1"}, {rk: "b", rv: "B1"}, {rk: "b", rv: "B2"}, {rk: "y", rv: "Y1"}, {rk: null, rv: "N1"}]'

# id -> (program, uses SAMPLE as input, show the program)
EXAMPLES: dict[str, tuple[str, bool, bool]] = {
    "sample_rows": (".", True, False),
    "trace_answer": (ANSWER, True, False),
    "trace_parse": (PREP + " | map({number, opened, resolved, hours})", True, True),
    "trace_local": ('tz("America/Detroit") as $det | map(.opened_at | parse_ts | local_time($det) | {date, weekday, hour, minute, offset_s})', True, True),
    "trace_flag": ('tz("America/Detroit") as $det | ' + FLAG + " | map({number, hours, in_hours})", True, True),
    "trace_answer_code": (ANSWER, True, True),
    "null_rule": ("[1, null, 3] | {plain_add_over_length: (add / length), mean: mean, count_nonnull: count_nonnull, length: length, sum_nonnull: sum_nonnull, mean_of_nulls: ([null, null] | mean)}", False, True),
    "min_max": ('[null, 3, 1] | {plain_min: min, min_nonnull: min_nonnull, max_nonnull: max_nonnull, nothing: ([null] | min_nonnull), first_lowest: ([{id: 1, x: null}, {id: 2, x: 5}, {id: 3, x: 2}] | min_by_nonnull(.x) | .id)}', False, True),
    "variance": ("[2, 4, 4, 4, 5, 5, 7, 9] | {var_samp: var_samp, var_pop: var_pop, stddev_samp: stddev_samp, stddev_pop: stddev_pop, one_value_var_samp: ([3] | var_samp)}", False, True),
    "quantiles": ("[40, 10, null, 30, 20] | {disc: quantiles_disc([0.1, 0.25, 0.5, 0.9]), cont: quantiles_cont([0.1, 0.25, 0.5, 0.9]), median: median, none: ([null] | quantiles_disc([0.5]))}", False, True),
    "round": ("[1.005, 2.675, 0.125, -0.5, 1.5, null] | map(round_to(2)), map(round_to(0))", False, True),
    "parse_ts": ('["2026-08-12 13:05:00", "2026-08-12T13:05:00Z", "2026-08-12T09:05:00-04:00", "2026-08-12T18:35:00+0530", "2026-08-12 13:05:00.250", "", null] | map(parse_ts | if . == null then null else {epoch: ., utc: (floor | todate)} end)', False, True),
    "cast": ('[{n: "12.5", t: "2026-08-12 13:05:00", b: "true"}, {n: "", t: "", b: "false"}, {n: "1e3", t: null, b: null}] | cast({n: "number", t: "timestamp", b: "boolean"})', False, True),
    "cast_error": ('[{n: " 12"}] | try cast({n: "number"}) catch .', False, True),
    "local_time": ('tz("America/Detroit") as $det | ["2026-03-08 06:59:59", "2026-03-08 07:00:00", "2026-11-01 05:59:59", "2026-11-01 06:00:00"] | map(parse_ts | local_time($det) | {date, hour, minute, weekday, offset_s})', False, True),
    "group_agg": ('[{g: "a", x: 1}, {g: "b", x: 5}, {g: null, x: 7}, {g: "a", x: null}, {g: "a", x: 3}] | group_agg({g}; map(.x) | {rows: length, n: count_nonnull, mean: mean})', False, True),
    "joins": (LEFT + " as $l | " + RIGHT + " as $r | {inner: ($l | join_inner($r; .k; .rk) | map([.id, .rv])), left: ($l | join_left($r; .k; .rk) | map([.id, .rv])), full: ($l | join_full($r; .k; .rk) | map([.id, .rv])), semi: ($l | join_semi($r; .k; .rk) | map(.id)), anti: ($l | join_anti($r; .k; .rk) | map(.id))}", False, True),
    "several_tables": ("[{t: \"100\", ip_address: \"10.1.1.55\", user: \"bsmith\", src_ip: \"\", event_type: \"dhcp\"}, {t: \"300\", ip_address: \"10.1.1.55\", user: \"jdoe\", src_ip: \"\", event_type: \"dhcp\"}, {t: \"10\", ip_address: \"10.1.1.99\", user: \"olduser\", src_ip: \"\", event_type: \"dhcp\"}, {t: \"400\", ip_address: \"\", user: \"\", src_ip: \"10.1.1.55\", event_type: \"firewall\"}, {t: \"1000\", ip_address: \"\", user: \"\", src_ip: \"10.1.1.99\", event_type: \"firewall\"}] | split_by(.event_type) as $by_type | ($by_type.dhcp | map({ip: .ip_address, user, lease_t: (.t | tonumber)})) as $leases | ($by_type.firewall | map({ip: .src_ip, t: (.t | tonumber)})) as $hits | {split: ($by_type | shape | map_values(.rows)), answer: ($hits | join_asof($leases; .ip; .ip; .t; .lease_t; 300) | map({t, ip, user}))}", False, True),
    "join_on": ("[{id: 1, region: \"east\", amount: 5}, {id: 2, region: \"east\", amount: 60}, {id: 3, region: \"west\", amount: 5}] as $orders | [{region: \"east\", lo: 0, hi: 10, band: \"small\"}, {region: \"east\", lo: 10, hi: 100, band: \"medium\"}, {region: \"east\", lo: 50, hi: 100, band: \"upper\"}] as $bands | $orders | join_on($bands; .region; .region; .l.amount >= .r.lo and .l.amount < .r.hi; \"left\") | map({id, amount, band})", False, True),
    "join_nest": ("[{id: 1, region: \"east\", amount: 5}, {id: 2, region: \"east\", amount: 60}, {id: 3, region: \"west\", amount: 5}] as $orders | [{region: \"east\", lo: 0, hi: 10, band: \"small\"}, {region: \"east\", lo: 10, hi: 100, band: \"medium\"}, {region: \"east\", lo: 50, hi: 100, band: \"upper\"}] as $bands | $orders | join_nest($bands; .region; .region; .l.amount >= .r.lo and .l.amount < .r.hi; \"bands\") | map({id, bands: (.bands | map(.band))})", False, True),
    "lookup": ("[{id: 1, gid: \"g1\"}, {id: 2, gid: \"g9\"}, {id: 3, gid: null}] | lookup([{gid: \"g1\", name: \"Access\"}, {gid: \"g2\", name: \"Devices\"}]; .gid; .gid; \"group\")", False, True),
    "join_asof": ("[{q: 100, k: \"a\", qt: 2}, {q: 101, k: \"a\", qt: 10}, {q: 102, k: \"a\", qt: 10}, {q: 103, k: \"a\", qt: 14}] as $quotes | [{id: 1, k: \"a\", t: 1}, {id: 2, k: \"a\", t: 10}, {id: 3, k: \"a\", t: 12}, {id: 4, k: \"a\", t: 30}, {id: 5, k: \"b\", t: 30}] | {latest_at_or_before: (join_asof($quotes; .k; .k; .t; .qt) | map({id, q})), no_older_than_3: (join_asof($quotes; .k; .k; .t; .qt; 3) | map({id, q}))}", False, True),
    "join_overlap": ("[{shift: 1, host: \"a\", start: 0, end: 10}, {shift: 2, host: \"a\", start: 10, end: 20}] | join_overlap([{outage: \"x\", host: \"a\", ostart: 8, oend: 12}, {outage: \"y\", host: \"a\", ostart: 20, oend: 25}]; .host; .host; .start; .end; .ostart; .oend) | map({shift, outage})", False, True),
    "state_blocks": ("[{ticket: \"T1\", t: 0, status: \"New\"}, {ticket: \"T1\", t: 600, status: \"Open\"}, {ticket: \"T1\", t: 4200, status: \"Open\"}, {ticket: \"T1\", t: 6000, status: \"InReview\"}, {ticket: \"T1\", t: 9600, status: \"Closed\"}] | state_blocks({ticket}; .t; .status)", False, True),
    "state_others": ("[{ticket: \"T1\", t: 0, status: \"New\"}, {ticket: \"T1\", t: 600, status: \"Open\"}, {ticket: \"T1\", t: 4200, status: \"Open\"}, {ticket: \"T1\", t: 6000, status: \"InReview\"}, {ticket: \"T1\", t: 9600, status: \"Closed\"}] | {transitions: transitions({ticket}; .t; .status), sessions: sessions({ticket}; .t; 3000), runs: (map(.status) | runs(.))}", False, True),
    "tree_rollup": ("[{id: 1, parent: null, name: \"CEO\", cost: 100}, {id: 2, parent: 1, name: \"Engineering\", cost: 50}, {id: 3, parent: 1, name: \"Sales\", cost: 40}, {id: 4, parent: 2, name: \"Backend\", cost: 30}, {id: 5, parent: 2, name: \"Frontend\", cost: 20}, {id: 6, parent: 4, name: \"Platform\", cost: 10}] | tree_rollup(.id; .parent; .cost) | map({name, depth, ancestry, subtree})", False, True),
    "graphs": ("[{a: 1, b: 2}, {a: 2, b: 3}, {a: 3, b: 1}, {a: 4, b: 5}] | {reachable_from_1: reachable(.a; .b; 1), components: components(.a; .b)}", False, True),
    "windows": ('[{i: 1, g: "a", t: 3, v: 5}, {i: 2, g: "a", t: 1, v: 2}, {i: 3, g: "a", t: 3, v: 7}, {i: 4, g: "a", t: 2, v: null}, {i: 5, g: "b", t: 1, v: 4}] | over(.g; .t; "rn"; row_number) | over(.g; .t; "rank"; rank_by(.t)) | over(.g; .t; "prev_v"; lag(.v; 1)) | over(.g; .t; "running"; running_sum(.v)) | over(.g; .t; "mean2"; moving_mean(.v; 2)) | map({i, g, t, v, rn, rank, prev_v, running, mean2})', False, True),
    "reshape": ('[{id: 1, a: 10, b: null}, {id: 2, a: 11, b: 21}] | unpivot(["id"]; "col"; "val") as $long | {long: $long, wide_again: ($long | pivot(["a", "b", "c"]; {id}; .col; .val; add))}', False, True),
}


SALES = ('[{region: "east", product: "A", month: "2026-01", amount: 30}, {region: "east", product: "A", month: "2026-02", amount: 50}, '
         '{region: "east", product: "B", month: "2026-01", amount: 20}, {region: "west", product: "A", month: "2026-02", amount: 60}, '
         '{region: "west", product: "B", month: "2026-01", amount: 40}]')
REVENUE = "def revenue: map(.amount) | add; "
SHAPE_EXAMPLES: dict[str, tuple[str, bool, bool]] = {
    "shapes_nested": ('[{id: "REQ1", user: {name: "Avery", dept: {code: "RAD"}}, tags: ["vpn", "laptop"]}, {id: "REQ2", user: {name: "Bo", dept: {code: "LAB"}}, tags: []}] | flatten_fields(".") | {inner: (unnest(.tags; "tag") | map(del(.tags))), outer: (unnest_outer(.tags; "tag") | map({id, tag}))}', False, True),
    "shapes_tree": ('{id: "ceo", children: [{id: "ops", children: [{id: "desk"}]}, {id: "fin"}]} | nodes_from_nested(.id; .children) as $nodes | {nodes: $nodes, depths: ($nodes | tree_paths(.id; .parent) | map({id, depth})), nested_again: ($nodes | nested_from_nodes(.id; .parent; "children") | .[0].children | map(.id))}', False, True),
    "shapes_map": ('{web01: {site: "North"}, db01: {site: "South"}} | rows_from_map("host") as $rows | {rows: $rows, map_again: ($rows | to_map(.host) | keys)}', False, True),
    "shapes_grid": ('[{site: "North", hour: 0, requests: 3}, {site: "North", hour: 7200, requests: 1}, {site: "South", hour: 3600, requests: 2}] | fill_grid(["site"]; "hour"; 3600; {requests: 0})', False, True),
    "shapes_out": ('[{from: "web01", to: "db01", port: 5432}, {from: "web01", to: "cache01", port: 6379}] | node_link(.from; .to), ([{id: "REQ1", site: "South, annex", hours: null}] | to_csv(["id", "site", "hours"]))', False, True),
}
EXAMPLES.update(SHAPE_EXAMPLES)

CONTEXT_EXAMPLES: dict[str, tuple[str, bool, bool]] = {
    "context_rollup": (REVENUE + SALES + ' | rollup(["region", "product"]; {revenue: measure(revenue), share_of_region: share(revenue; without("product")), share_of_all: share(revenue; keep_only([]))})', False, True),
    "context_time": (REVENUE + SALES + ' | rollup(["month"]; {revenue: measure(revenue), prior: calc(revenue; shift("month"; -1)), to_date: calc(revenue; to_date("month")), east_only: calc(revenue; with_filter({region: "east"}))})', False, True),
    "context_levels": (REVENUE + SALES + ' | rollup_levels([["region"], ["product"], []]; {revenue: measure(revenue), rows: measure(length)})', False, True),
    "context_cell": (REVENUE + SALES + ' | rollup(["region"]; {context_at: .at, context_level: .level, rows_here: (.rows | length), rows_in_all: (.all | length), months_known: .members})', False, True),
}
EXAMPLES.update(CONTEXT_EXAMPLES)


def run(binary: str, program: str, uses_sample: bool) -> str:
    args = [binary, "-c", "-L", str(LIB), 'include "analytics"; ' + program]
    out = subprocess.run(args if uses_sample else args[:1] + ["-n"] + args[1:],
                         input=json.dumps(SAMPLE) if uses_sample else None, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"{binary}: {out.stderr.strip()}")
    return out.stdout


def as_lines(stdout: str) -> str:
    # each output value on its own; an array of objects or arrays gets one element per line
    blocks = []
    for line in stdout.splitlines():
        value = json.loads(line)
        if isinstance(value, list) and value and all(isinstance(v, (dict, list)) for v in value):
            blocks.append("[\n" + ",\n".join("  " + json.dumps(v) for v in value) + "\n]")
        elif isinstance(value, dict) and len(json.dumps(value)) > 100:
            blocks.append("{\n" + ",\n".join(f"  {json.dumps(k)}: {json.dumps(v)}" for k, v in value.items()) + "\n}")
        else:
            blocks.append(json.dumps(value))
    return "\n".join(blocks)


def main() -> None:
    engines = sys.argv[1:]
    text = README.read_text()
    report = {}
    for ex_id, (program, uses_sample, show) in EXAMPLES.items():
        outputs = {b: run(b, program, uses_sample) for b in engines}
        canonical = {b: [json.loads(l) for l in o.splitlines()] for b, o in outputs.items()}
        first = canonical[engines[0]]
        bad = [b for b in engines if canonical[b] != first]
        if bad:
            raise SystemExit(f"{ex_id}: {bad} differ from {engines[0]}")
        block = (f"```jq\n{program}\n```\n\n" if show else "") + f"```json\n{as_lines(outputs[engines[0]])}\n```"
        pattern = re.compile(rf"(<!-- example: {ex_id} -->\n).*?(<!-- /example -->)", re.S)
        if not pattern.search(text):
            raise SystemExit(f"{ex_id}: no marker in README.md")
        text = pattern.sub(lambda m: m.group(1) + block + "\n" + m.group(2), text)
        report[ex_id] = f"same on {len(engines)} engines"
    README.write_text(text)
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
