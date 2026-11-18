# analytics.jq: table and statistics functions for jq, with their rules written beside each def.
#
# Runs on jq 1.7.1 and on the jq 1.8.2 inside the `jq` PyPI binding 1.13.0 (no 1.8-only builtins;
# a `reduce ... as $x` inside a function argument is parenthesised, which 1.7.1 requires).
# Load it, with tzdata.jq in the same directory <dir>, in any of these ways:
#   jq -L <dir> 'include "analytics"; ...'
#   jq 'include "analytics" {search: "<dir>"}; ...'           (also in the binding, which has no -L)
#   jq 'import "analytics" as a {search: "<dir>"}; ... a::mean'
#
# Vocabulary. A table is an array of objects (rows). A key or value expression (keyf, f, ord) is a
# jq filter applied to one row. Missing fields read as null, as everywhere in jq.
# Null rule, everywhere unless a def says otherwise: aggregates skip nulls, as SQL does, and
# return null when nothing is left; join keys that are null never match; group keys that are
# null form one group of their own.

include "tzdata" {search: "./"};  # "./" (not ".") is read relative to this file, so tzdata.jq needs no -L

# ---------------------------------------------------------------- math: arrays of numbers

# the input array without nulls
def nonnull: map(select(. != null));

# number of non-null values
def count_nonnull: nonnull | length;

# sum of non-null values; null when there are none (jq's add returns null for [] but counts nothing)
def sum_nonnull: nonnull | if length == 0 then null else add end;

# arithmetic mean of non-null values; null when none. Plain `add / length` divides by a count
# that includes nulls: [1, null, 3] gives 1.33 there and 2 here.
def mean: nonnull | if length == 0 then null else add / length end;

# variance and standard deviation: sample (divide by n - 1, null below 2 values) and population
# (divide by n, null when none). Two-pass: mean first, then squared deviations.
def var_samp: nonnull | length as $n
  | if $n < 2 then null else (add / $n) as $m | (map((. - $m) * (. - $m)) | add) / ($n - 1) end;
def var_pop: nonnull | length as $n
  | if $n == 0 then null else (add / $n) as $m | (map((. - $m) * (. - $m)) | add) / $n end;
def stddev_samp: var_samp | if . == null then null else sqrt end;
def stddev_pop: var_pop | if . == null then null else sqrt end;

# Quantiles over non-null values, p in [0, 1]; null when none.
# quantile_disc: nearest rank, an element of the data: the value at 1-based rank ceil(n * p) of the
#   sorted values, at least rank 1. DuckDB's quantile_disc gives the same (checked by the tests),
#   and so did the sibling slug's lib.jq pctl.
# quantile_cont: linear interpolation at h = (n - 1) * p between the neighbours of h, the rule of
#   DuckDB's quantile_cont and median, Excel PERCENTILE.INC and Power Query PercentileMode.ExcelInc.
def quantile_disc($p): nonnull | sort as $x | length as $n
  | if $n == 0 then null else $x[([(($n * $p) | ceil), 1] | max) - 1] end;
def quantile_cont($p): nonnull | sort as $x | length as $n
  | if $n == 0 then null
    else (($n - 1) * $p) as $h | ($h | floor) as $lo
    | if $lo + 1 >= $n then $x[$lo] else $x[$lo] + ($h - $lo) * ($x[$lo + 1] - $x[$lo]) end
    end;
def median: quantile_cont(0.5);
# several quantiles at once, as DuckDB's list form: null (not a list of nulls) when no values
def quantiles_disc($ps): if count_nonnull == 0 then null else [$ps[] as $p | quantile_disc($p)] end;
def quantiles_cont($ps): if count_nonnull == 0 then null else [$ps[] as $p | quantile_cont($p)] end;

# round to $d decimal places, halves away from zero, on the binary double (so 1.005 becomes 1.0,
# because 1.005 is stored as 1.00499999...). Null stays null.
def round_to($d): if . == null then null else pow(10; $d) as $m | (. * $m | round) / $m end;

# ---------------------------------------------------------------- types

# a timestamp string to UTC epoch seconds (fractions kept). Accepts "YYYY-MM-DD HH:MM:SS" or "T",
# optional fraction, optional "Z" or +HH:MM / +HHMM offset. No offset means UTC (as ServiceNow
# and Splunk's _time strings store it). null and "" give null; anything else is an error, never
# a silent empty. Unlike strptime("%z"), the offset is applied.
def parse_ts:
  if . == null or . == "" then null
  else . as $s
    | (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
       // error("parse_ts: not a timestamp: \($s | tojson)")) as $m
    | ("\($m.d)T\($m.t)Z" | fromdateiso8601)
      + (if $m.f == null then 0 else ("0" + $m.f | tonumber) end)
      - (if $m.z == null or $m.z == "Z" then 0
         else ($m.z | sub(":"; "")) as $z
         | (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60) * (if $z[0:1] == "-" then -1 else 1 end)
         end)
  end;

# cast the named columns of every row. $schema = {column: "number" | "timestamp" | "string" | "boolean"}.
# "" and null become null. A value that does not parse is an error naming the column and value
# (Power Query's rule), never a null. Numbers must look like JSON numbers: jq 1.7.1's tonumber
# accepts " 12" and jq 1.8's refuses it, so the pattern decides instead of the version.
def cast($schema):
  map(reduce ($schema | to_entries[]) as $c (.;
    .[$c.key] |= (
      if . == null or . == "" then null
      elif $c.value == "number" then
        (if type == "number" then .
         elif type == "string" and test("^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$") then tonumber
         else error("cast: \($c.key) = \(tojson) is not a number") end)
      elif $c.value == "timestamp" then parse_ts
      elif $c.value == "string" then tostring
      elif $c.value == "boolean" then
        (if . == true or . == "true" then true elif . == false or . == "false" then false
         else error("cast: \($c.key) = \(tojson) is not a boolean") end)
      else error("cast: unknown type \($c.value | tojson) for \($c.key)") end)));

# ---------------------------------------------------------------- time zones and calendar

# the transition rules of one IANA zone, from tzdata.jq (generated from the tzdata package; covers
# 1970 to 2100). Unknown zone is an error. No process TZ is read anywhere in this file.
# tz_rules is a 27 KB literal that jq rebuilds on every call (0.8 ms), so a program that converts
# many rows looks the zone up once: tz("America/Detroit") as $det | ... | local_time($det).
def tz($name): tz_rules[$name] // error("tz: zone not in tzdata.jq: \($name)");

# UTC offset in seconds at the input epoch; $tz is a zone name or the object tz($name) returned
def tz_offset($tz):
  . as $e
  | ($tz | if type == "string" then tz(.) else . end)
  | (.t | bsearch($e)) as $i
  | .o[if $i >= 0 then $i else -2 - $i end];

# the local wall clock of the input epoch in zone $tz (a name or tz($name)), as an object:
# {date: "YYYY-MM-DD", year, month (1-12), day, hour, minute, second, weekday (0 = Sunday),
#  offset_s, local_epoch (epoch of the wall clock read as if it were UTC)}
def local_time($tz):
  tz_offset($tz) as $o | (. + $o) as $l | ($l | floor | gmtime) as $g
  | {date: ($l | floor | strftime("%Y-%m-%d")), year: $g[0], month: ($g[1] + 1), day: $g[2],
     hour: $g[3], minute: $g[4], second: ($g[5] + ($l - ($l | floor))), weekday: $g[6],
     offset_s: $o, local_epoch: $l};

# hours from epoch a to epoch b, exact (no rounding); null when either is null
def hours_between(a; b): (a) as $a | (b) as $b
  | if $a == null or $b == null then null else ($b - $a) / 3600 end;

# ---------------------------------------------------------------- grouping

# group rows by keyf and aggregate each group with aggf (applied to the group's array of rows).
# Output: one row per group, in order of first appearance (group_by sorts by key instead).
# A key that is an object is merged into the output row; any other key goes in field "key".
# aggf must return an object. Null keys form one group, as in SQL GROUP BY.
# rows grouped by f: an array of groups in order of first appearance, each group in input order.
# Built on the builtin group_by (a stable sort), then put back in first-appearance order by each
# group's first input position. Appending rows to groups inside a reduce is avoided everywhere in
# this file: it grows with the square of a group's size (measured: 40 times the time for 10 times
# the rows), and an object's key order differs between engines (gojq sorts keys).
def _groups(f): to_entries | group_by(.value | f) | sort_by(.[0].key) | map(map(.value));

def group_agg(keyf; aggf):
  _groups(keyf) | map((.[0] | keyf | if type == "object" then . else {key: .} end) + aggf);

# ---------------------------------------------------------------- several tables at once

# Name each table with `as $name` and refer to it later by that name, as SPL2 names its searches:
#   split_by(.event_type) as $by_type | ($by_type.dhcp | map(...)) as $leases | ...
# split_by, keep and shape below work on an object of tables: {dhcp: [...], firewall: [...]}.

# split a stream of rows into an object of tables by a tag: rows with the same tagf value form one table,
# named by that value as a string (a null tag gives the table "null"). A host that can pass only one
# stream hands over several tables this way: one stream, with a field saying which table each row belongs to.
def split_by(tagf): _groups(tagf) | map({key: (.[0] | tagf | tostring), value: .}) | from_entries;

# keep only the named tables (drop the rest before a heavy step or before output)
def keep($names): with_entries(select(.key as $k | $names | any(. == $k)));

# for checking a pipeline midway: each table's row count and field names (sorted)
def shape: map_values({rows: length, fields: (map(keys) | add // [] | unique)});

# ---------------------------------------------------------------- joins

# Every join is four choices:
#   key   - lkey and rkey, the equality part: any expression per side, an array for a composite key.
#           The right table is indexed once by rkey, so cost is left rows + right rows.
#           For a join with no equality part, pass `true` for both keys: every pair is then checked.
#   cond  - the rest of the match, a filter over the pair {l: left row, r: right row}; `true` for none.
#           It is checked only for pairs that share a key.
#   kind  - "inner", "left", "full", "semi" or "anti".
#   shape - flat (join_on: one output row per match) or nested (join_nest: matches as an array).
# Rules for all: a null key never matches. Duplicate keys multiply rows in a flat join. Output
# follows the left table's order, then the right table's order among matches, on every engine.
# A flat match is the left row merged with the right row. A field present in both with the same
# value is kept once; with different values it is an error naming the field, never a silent
# overwrite: rename one side first.

def _merge($l; $r):
  reduce ($r | to_entries[]) as $e ($l;
    if has($e.key) and .[$e.key] != $e.value
    then error("join: field \($e.key | tojson) differs between left (\(.[$e.key] | tojson)) and right (\($e.value | tojson)); rename one side first")
    else .[$e.key] = $e.value end);

# each left row with its matching right rows: [{l: row, m: [{key: right position, value: right row}]}]
def _matches($right; lkey; rkey; cond):
  ($right | to_entries | group_by(.value | rkey)
   | map(select((.[0].value | rkey) != null) | {key: (.[0].value | rkey | tojson), value: .}) | from_entries) as $ix
  | [.[] as $l | ($l | lkey) as $k
     | {l: $l, m: [(if $k == null then empty else $ix[$k | tojson][]? end)
                   | select(.value as $r | {l: $l, r: $r} | cond)]}];

# the general flat join
def join_on($right; lkey; rkey; cond; $kind):
  _matches($right; lkey; rkey; cond) as $rows
  | if $kind == "inner" then [$rows[] | .l as $l | .m[] | _merge($l; .value)]
    elif $kind == "left" then [$rows[] | .l as $l | if (.m | length) > 0 then .m[] | _merge($l; .value) else $l end]
    elif $kind == "semi" then [$rows[] | select((.m | length) > 0) | .l]
    elif $kind == "anti" then [$rows[] | select((.m | length) == 0) | .l]
    elif $kind == "full" then
      # right rows that matched no left row follow the left part, in right order
      ([$rows[].m[] | {key: (.key | tostring), value: true}] | from_entries) as $hit
      | [$rows[] | .l as $l | if (.m | length) > 0 then .m[] | _merge($l; .value) else $l end]
        + [$right | to_entries[] | select($hit[.key | tostring] | not) | .value]
    else error("join_on: unknown kind \($kind | tojson)") end;

# equality joins: shorthands for join_on with no condition
def join_inner($right; lkey; rkey): join_on($right; lkey; rkey; true; "inner");
def join_left($right; lkey; rkey): join_on($right; lkey; rkey; true; "left");
def join_full($right; lkey; rkey): join_on($right; lkey; rkey; true; "full");
def join_semi($right; lkey; rkey): join_on($right; lkey; rkey; true; "semi");
def join_anti($right; lkey; rkey): join_on($right; lkey; rkey; true; "anti");

# nested join: every left row once, with field $as holding the array of its matching right rows
# (empty when none). Never multiplies rows. Power Query's Table.NestedJoin.
def join_nest($right; lkey; rkey; cond; $as):
  [_matches($right; lkey; rkey; cond)[] | .l + {($as): [.m[].value]}];

# lookup: attach exactly one record of a dimension table under field $as (null when none).
# A key that appears twice in the dimension is an error, so a lookup can never multiply rows.
def lookup($dim; lkey; dkey; $as):
  ($dim | group_by(dkey)
   | map(select((.[0] | dkey) != null)
         | if length > 1 then error("lookup: key \(.[0] | dkey | tojson) appears more than once in the dimension")
           else {key: (.[0] | dkey | tojson), value: .[0]} end)
   | from_entries) as $ix
  | map(. as $l | ($l | lkey) as $k | $l + {($as): (if $k == null then null else $ix[$k | tojson] end)});

# interval overlap: pairs with the same key whose intervals overlap, each interval closed at its
# start and open at its end ([start, end)). Flat and inner; rename start and end on one side first.
def join_overlap($right; lkey; rkey; lstart; lend; rstart; rend):
  join_on($right; lkey; rkey; (.l | lstart) < (.r | rend) and (.r | rstart) < (.l | lend); "inner");

# As-of join (left outer): for each left row, the right row with the same key whose rtime is the
# greatest rtime <= the left row's ltime (DuckDB's ASOF LEFT JOIN ... ON l.k = r.k AND l.t >= r.t).
# $max_age, when not null, rejects a match older than that: ltime - rtime must be <= $max_age.
# Ties on rtime: the first such right row in input order (DuckDB 2.0.0 gave the same on the test
# fixture; pandas merge_asof takes the last; SQL leaves it open). No match, or a null key or time
# on the left: the left row alone. Right rows with a null key or time are dropped.
def join_asof($right; lkey; rkey; ltime; rtime; $max_age):
  ([$right[] | select((rkey) != null and (rtime) != null)] | group_by(rkey)
   | map({key: (.[0] | rkey | tojson), value: (sort_by(rtime) | {rows: ., t: map(rtime)})}) | from_entries) as $ix
  | [.[] as $l | ($l | lkey) as $k | ($l | ltime) as $t
     | if $k == null or $t == null or $ix[$k | tojson] == null then $l
       else $ix[$k | tojson] as $g
       | ($g.t | bsearch($t)) as $i
       # bsearch gives some entry equal to $t, or the insertion point; take the last entry <= $t,
       # then step back to the first of its run of equal times
       | (if $i >= 0 then $i else -2 - $i end) as $last
       | (if $last < 0 then -1 else $last | until(. == 0 or $g.t[. - 1] != $g.t[$last]; . - 1) end) as $j
       | if $j < 0 or ($max_age != null and $t - $g.t[$j] > $max_age) then $l else _merge($l; $g.rows[$j]) end
       end];
def join_asof($right; lkey; rkey; ltime; rtime): join_asof($right; lkey; rkey; ltime; rtime; null);

# ---------------------------------------------------------------- windows

# Window over partitions: split rows by part (first appearance), sort each partition by ord
# (stable: ties keep input order), call wf on the sorted partition (an array of rows), which must
# return an array of the same length, and write its i-th value into field $col of the i-th row.
# Rows come back in input order. Frames are ROWS frames (each row by itself), not SQL's default
# RANGE frame, which gives tied rows the same running value.
def over(part; ord; $col; wf):
  . as $rows
  | [to_entries | map({i: .key, r: .value}) | group_by(.r | part)[]
     | sort_by(.r | ord) | (map(.r) | wf) as $v | to_entries[] | {i: .value.i, v: $v[.key]}]
  | sort_by(.i) | map(.v) as $vals
  | [$rows | to_entries[] | .value + {($col): $vals[.key]}];

# window value functions: input is one sorted partition (array of rows)
def row_number: [range(1; length + 1)];
# rank with gaps (SQL RANK) by f over the partition's order: tied f values share a rank
def rank_by(f): . as $a | [range(length) as $i | ($a[$i] | f) as $v
  | ([$a[:$i][] | select((f) != $v)] | length) + 1];
def lag(f; $k): . as $a | [range(length) as $i | if $i - $k >= 0 then ($a[$i - $k] | f) else null end];
def lead(f; $k): . as $a | length as $n | [range($n) as $i | if $i + $k < $n then ($a[$i + $k] | f) else null end];
# running sum of f, ROWS frame from the partition start: nulls skipped; null until the first non-null
def running_sum(f): [foreach .[] as $r (null; ($r | f) as $v | if $v == null then . else (. // 0) + $v end; .)];
# moving mean of f over the current row and the $n - 1 rows before it (fewer at the start); nulls skipped
def moving_mean(f; $n): . as $a | [range(length) as $i | [$a[([$i - $n + 1, 0] | max):($i + 1)][] | f] | mean];

# ---------------------------------------------------------------- reshape

# unpivot: every field not in $keep becomes its own row {keep fields..., $name: field, $value: value}.
# Null values are kept (Power Query's example drops them). Within a row, fields come out sorted by
# name, so every engine agrees (jq and jaq keep insertion order, gojq sorts keys).
def unpivot($keep; $name; $value):
  [.[] as $r | ($r | with_entries(select(.key as $k | $keep | any(. == $k)))) as $base
   | $r | to_entries | sort_by(.key)[] | select(.key as $k | $keep | any(. == $k) | not)
   | $base + {($name): .key, ($value): .value}];

# pivot: one output row per rowkey (an object) and one column per name in $cols (Power Query's
# pivotValues), holding agg applied to the array of valf values whose colf (as a string) is that
# name. A name with no matching rows gives null; colf values not in $cols are dropped.
def pivot($cols; rowkey; colf; valf; agg):
  group_agg(rowkey; (reduce .[] as $r ({}; .[$r | colf | tostring] += [$r | valf])) as $cells
    | reduce $cols[] as $c ({}; .[$c] = ($cells[$c] | if . == null then null else agg end)));

# ---------------------------------------------------------------- state machines over time

# Events of one entity, ordered by time, are read as a machine that is in one state at a time.

# state_blocks: per entity, events sorted by time (stable), consecutive events with the same state
# merged into one block: {entity key..., state, start (time of its first event), end (time of the
# next block's first event, null for the entity's last block), duration (end - start, null when
# open), events (how many events it merged)}. A repeated state does not restart the clock: an
# assignee change while the status stays Open is still the same Open block. The entity key is
# merged in as group_agg does (an object key's fields, or field "key"). Order: entities by first
# appearance, blocks by time.
def _blocks(time; state):
  # positions where a new block starts, then each block from its start to the next start
  . as $a | length as $n
  | [range($n) | select(. == 0 or (($a[.] | state) != ($a[. - 1] | state)))] as $st
  | [range($st | length) as $j | $st[$j] as $i
     | (if $j + 1 < ($st | length) then $st[$j + 1] else null end) as $nx
     | ($a[$i] | time) as $t0 | (if $nx == null then null else ($a[$nx] | time) end) as $t1
     | {state: ($a[$i] | state), start: $t0, end: $t1,
        duration: (if $t1 == null then null else $t1 - $t0 end),
        events: ((if $nx == null then $n else $nx end) - $i)}];
def state_blocks(entity; time; state):
  group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})
  | [.[] | del(.blocks) as $k | .blocks[] | $k + .];

# transitions: one row per change of state: {entity key..., from, to, at (time of the change)}
def transitions(entity; time; state):
  group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})
  | [.[] | del(.blocks) as $k | .blocks as $b | range(1; $b | length) as $i
     | $k + {from: $b[$i - 1].state, to: $b[$i].state, at: $b[$i].start}];

# sessions: per entity, events sorted by time; a new session starts when the gap since the previous
# event is greater than $gap. Rows: {entity key..., session (1, 2, ... within the entity), start,
# end (time of its last event), events}.
def sessions(entity; time; $gap):
  group_agg(entity; {sessions: (sort_by(time) | . as $a | length as $n
      | [range($n) | select(. == 0 or (($a[.] | time) - ($a[. - 1] | time)) > $gap)] as $st
      | [range($st | length) as $j | $st[$j] as $i
         | (if $j + 1 < ($st | length) then $st[$j + 1] else $n end) as $nx
         | {session: ($j + 1), start: ($a[$i] | time), end: ($a[$nx - 1] | time), events: ($nx - $i)}])})
  | [.[] | del(.sessions) as $k | .sessions[] | $k + .];

# runs: run-length encoding of an array in its given order: consecutive items with the same f value
# become {value, start (0-based position of the first), n}. Streaks are the long runs.
def runs(f):
  . as $a | length as $n
  | [range($n) | select(. == 0 or (($a[.] | f) != ($a[. - 1] | f)))] as $st
  | [range($st | length) as $j | $st[$j] as $i
     | {value: ($a[$i] | f), start: $i, n: ((if $j + 1 < ($st | length) then $st[$j + 1] else $n end) - $i)}];

# ---------------------------------------------------------------- hierarchies

# A tree is a table of nodes, each naming its parent; a root's parent is null or "".

# tree_paths: adds to every node `ancestry` (the ids from its root down to itself) and `depth`
# (0 for a root). A parent id that is not a node, or a cycle, is an error.
def tree_paths(id; parent):
  (reduce .[] as $n ({}; .[$n | id | tojson] = $n)) as $ix
  | map(. as $n
      | ({path: [$n | id], cur: $n}
         | until((.cur | parent) as $p | $p == null or $p == "";
             (.cur | parent) as $p
             | ($ix[$p | tojson] // error("tree_paths: parent \($p | tojson) is not a node")) as $pn
             | if (.path | any(. == $p)) then error("tree_paths: cycle through \($p | tojson)")
               else {path: ([$p] + .path), cur: $pn} end)
         | .path) as $a
      | $n + {ancestry: $a, depth: (($a | length) - 1)});

# tree_rollup: tree_paths, plus `subtree`: the node's own value plus the values of all its
# descendants, at any depth. A null value counts as 0.
def tree_rollup(id; parent; value):
  tree_paths(id; parent) as $t
  | (reduce $t[] as $n ({}; ($n | value) as $v
       | reduce $n.ancestry[] as $a (.; .[$a | tojson] += ($v // 0)))) as $sum
  | $t | map(. + {subtree: $sum[id | tojson]});

# ---------------------------------------------------------------- graphs

# A graph is a table of edges; from and to (or a and b) are expressions giving each edge's two ends.

# nodes reached from $start by following edges, nearest first (breadth first), each once
def _bfs($adj; $start):
  {seen: {($start | tojson): true}, frontier: [$start], order: []}
  | until((.frontier | length) == 0;
      .frontier as $f
      | reduce ($f[] | $adj[tojson][]?) as $n (.frontier = [];
          if .seen[$n | tojson] then . else .seen[$n | tojson] = true | .frontier += [$n] | .order += [$n] end))
  | .order;

# reachable: every node that can be reached from $start along directed edges from -> to, at any
# number of hops, nearest first. $start itself is never listed, even when a cycle leads back to it:
# each node appears once and the start counts as already seen. Cycles are safe.
def reachable(from; to; $start):
  (reduce .[] as $e ({}; .[$e | from | tojson] += [$e | to])) as $adj | _bfs($adj; $start);

# components: connected groups, edges read as undirected. One row per node: {node, component},
# where component is the smallest node of its group in jq's sort order. Rows sorted by node.
def components(a; b):
  (reduce .[] as $e ({}; ($e | a) as $x | ($e | b) as $y | .[$x | tojson] += [$y] | .[$y | tojson] += [$x])) as $adj
  | ([.[] | (a), (b)] | unique) as $nodes
  | reduce $nodes[] as $n ({seen: {}, out: []};
      if .seen[$n | tojson] then .
      else reduce ([$n] + _bfs($adj; $n))[] as $m (.; .seen[$m | tojson] = true | .out += [{node: $m, component: $n}]) end)
  | .out | sort_by(.node);

# ---------------------------------------------------------------- measures in a context

# A measure is any jq function over an array of rows (def requests: length;). A report evaluates it
# in a context: the set of filters a cell stands for. rollup and rollup_levels run their cell
# argument once per group at every level, with this object as input:
#   {at: {level field: value}, rows: [the rows matching .at], all: [every row], level: [field names],
#    members: {field: sorted distinct values}, index: (private, rows by level and value)}
# Every level is a field on the row; put it there first (a computed field, or lookup).

# rows matching $at by scan. {field: value} is equality; {field: {from, to}} is a closed range that
# a null never satisfies. Used when a changed context is not one of the report's own levels.
def _where($at): map(select(. as $r | $at | to_entries | all(
  .key as $k | .value as $v | $r[$k] as $x
  | if ($v | type) == "object"
    then $x != null and ($v.from == null or $x >= $v.from) and ($v.to == null or $x <= $v.to)
    else $x == $v end)));

# the rows of the context given as input. A context whose fields are one of the report's levels is
# read from the index (no scan); one range on such a level is the union of that level's groups in
# the range, in order of the field's values. Anything else scans every row.
def _ctx_rows:
  . as $c
  | ($c.at | keys) as $ks
  | ($c.at | to_entries | map(select(.value | type == "object") | .key)) as $ranges
  | $c.index[$ks | tojson] as $ix
  | if $ix == null or ($ranges | length) > 1 then $c.all | _where($c.at)
    elif ($ranges | length) == 0 then $ix[[$c.at[$ks[]]] | tojson] // []
    else $ranges[0] as $d | $c.at[$d] as $v
      | [$c.members[$d][]
         | select(. != null and ($v.from == null or . >= $v.from) and ($v.to == null or . <= $v.to))
         | . as $m | $ix[[($c.at + {($d): $m})[$ks[]]] | tojson][]?]
    end;

# rollup_levels: one output row per group at each listed level. $levels is a list of field lists,
# for example [["region", "product"], ["region"], []]; [] is the grand total. Each output row is the
# level's fields, a level name ("region/product", or "all") and the fields of cell. Rows come level
# by level in the order listed, sorted by the level's values within a level. Nothing is added up
# from finer cells: every level is computed from rows, so a median or a ratio is right at the total.
# A row missing a level's field forms its own group (null). No input rows give no output rows.
def rollup_levels($levels; cell):
  . as $all
  | (reduce ($levels | add // [] | unique)[] as $d ({}; .[$d] = ($all | map(.[$d]) | unique))) as $members
  | (reduce ($levels + [[]])[] as $lvl ({};
       ((reduce $lvl[] as $d ({}; .[$d] = 1)) | keys) as $ks
       | if has($ks | tojson) then .
         else .[$ks | tojson] = ($all | group_by([.[$ks[]]]) | map({key: ([.[0][$ks[]]] | tojson), value: .}) | from_entries)
         end)) as $index
  | [$levels[] as $lvl
     | ((reduce $lvl[] as $d ({}; .[$d] = 1)) | keys) as $ks
     | [$index[$ks | tojson][] | . as $rows
        | {at: (reduce $lvl[] as $d ({}; .[$d] = $rows[0][$d])), rows: $rows}]
     | sort_by([.at[$lvl[]]])[]
     | {all: $all, members: $members, index: $index, at: .at, rows: .rows, level: $lvl}
     | .at + {level: (if $lvl == [] then "all" else ($lvl | join("/")) end)} + cell];

# rollup: the hierarchy of $dims: every field, then one fewer from the right, down to the grand
# total (SQL's GROUP BY ROLLUP). rollup(["region", "month"]; ...) gives region/month, region, all.
def rollup($dims; cell): rollup_levels([range($dims | length; -1; -1) as $n | $dims[0:$n]]; cell);

# inside a cell: measure f on the cell's own rows
def measure(f): .rows | f;

# inside a cell: measure f on the rows of a changed context (DAX's CALCULATE). change is one or
# more of without, keep_only, with_filter, shift, to_date, piped. A shift past the first or last
# value has no context, and calc returns null without running f.
def calc(f; change): (change) as $c | if $c.void then null else ($c | _ctx_rows | f) end;

# inside a cell: measure f here divided by f in the changed context; null when that is null or 0
def share(f; change): measure(f) as $a | calc(f; change) as $b
  | if $a == null or $b == null or $b == 0 then null else $a / $b end;

# context changes. Each takes a context and returns one.
# remove one filter (ALL, REMOVEFILTERS). Written as .at |= del(...), not del(.at[$dim]): gojq's del
# copies the whole context, every row included, which cost 0.03 s per cell at 37,960 rows.
def without($dim): .at |= del(.[$dim]);
def keep_only($dims): .at |= with_entries(select(.key as $k | $dims | any(. == $k)));   # ALLEXCEPT
def with_filter($at): .at += $at;                     # add or replace filters; a value or {from, to}

# Not a calendar. shift and to_date follow the values present in the data, sorted as values: a month
# with no rows is skipped, and month names sort alphabetically. For calendar time (PREVIOUSMONTH,
# DATEADD, DATESYTD, months with no rows, DAX's blank rules) write the measure in DAX and compile it
# with dax-sql to DuckDB SQL (decisions-2026-11-17-02).
#
# move to the $k-th neighbouring value of $dim (-1 is the previous one). Neighbours are the field's
# distinct values over all rows, sorted, so "previous" is the previous value that has rows anywhere,
# not the previous calendar period. No filter on $dim (a total row) or no such neighbour: no context.
def shift($dim; $k):
  .at[$dim] as $v
  | if (.at | has($dim) | not) or $v == null or ($v | type) == "object" then .void = true
    else (.members[$dim] | index($v)) as $i
    | if $i == null or $i + $k < 0 or $i + $k >= (.members[$dim] | length) then .void = true
      else .at[$dim] = .members[$dim][$i + $k] end
    end;

# everything up to and including this value of $dim, other filters kept (a running total, DATESYTD
# when the year is another filter). No filter on $dim: unchanged.
def to_date($dim):
  if (.at | has($dim) | not) then .
  elif .at[$dim] == null then .void = true
  else .at[$dim] = {to: .at[$dim]} end;
