# Intervals

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/intervals.md`. Do not edit.

Six definitions. An interval is a row with a key, a start and an end, read as `[start, end)`: the start belongs to it, the end does not, and a null end means still open. `intervals_from_events` builds intervals from an event log; `join_within` finds the interval that contains a moment; `merge_intervals` and `concurrency` summarise a set of intervals.

```mermaid
flowchart LR
  E[event log: resource, holder, time, kind, ttl] --> B[intervals_from_events]
  B --> I[intervals: resource, holder, start, end, last, events, start_seen, ended_by]
  I --> W[join_within: which interval contains this row's time]
  I --> M[merge_intervals: overlapping or touching become one]
  I --> C[concurrency: how many are open over time]
```

Two of them, `intervals_from_events` and `merge_intervals`, share one pattern worth reading once: **a `foreach` that carries the open interval in `.cur` and hands finished intervals out through `.out`**.

- The state is `{cur, out}`. Each step first sets `.out = []`, then may put the intervals that close at this step into `.out`.
- The third part of the `foreach`, `.out[]`, emits whatever closed at this step. Finished intervals leave as they close.
- The loop runs over `(.[], null)`: the rows, then one extra `null` as an end-of-data marker, so the interval still open after the last row has a step at which to leave.

The obvious alternative, `reduce` appending each finished interval to a result array, copies that array on every append in jq, and the time grows with the square of the output. That was measured and repaired elsewhere in this library; these two were written this way from the start.

## _iv_check

`_iv_check/2`, lines 748 to 754:

```jq
# intervals_from_events: validity intervals built from an event log. A resource (an address, a
# seat, a session id) has at most one holder at a time. For each event, `kind` gives "open" or
# "hold" (evidence that `holder` has `resource` at `time`: a grant, a renewal, a start, a
# keep-alive), "release" (the holder gives it up), or null (ignored). `ttl` gives how many seconds
# a hold stays valid without another one, or null when holds do not expire.
#   - A hold opens an interval, or extends the open one when it is from the same holder: its end
#     becomes the later of its end and time + ttl (null when this hold's ttl is null).
#   - An interval ends in exactly one way, in `ended_by`: "released" (a release from its holder, at
#     that time), "taken_over" (a hold from another holder while it is still valid, at that time),
#     "lapsed" (its end passed before the next event on the resource), or "open" (still open at the
#     end of the data; its end is the last hold + ttl, or null).
#   - At the same time on one resource, events apply in the order open, hold, release. A release from someone
#     who does not hold the resource, or when nothing is held, is ignored.
#   - `start_seen` is true when the interval's first event was "open": a "hold" may be a renewal of
#     something that began before the data does.
# `last` is the time of the interval's last hold: the last evidence, which is what there is to go
# on when an open interval has no end.
# One row per interval: {resource, holder, start, end, last, events, start_seen, ended_by}; resources in
# order of first appearance, intervals in time order. Intervals of one resource never overlap.
# A kind other than the three, or a null time on an event with a kind, is an error naming the event.
def _iv_check(time; kind):
  to_entries[] | .key as $i | .value | (kind) as $k
  | if $k == null then empty
    elif $k != "open" and $k != "hold" and $k != "release"
    then error("intervals_from_events: event \($i) has kind \($k | tojson); expected \"open\", \"hold\", \"release\" or null")
    elif (time) == null then error("intervals_from_events: event \($i) has a kind but no time")
    else empty end;
```

Input: the event rows. Emits nothing; it exists to raise an error before any work is done.

- `to_entries[] | .key as $i | .value` walks the events with their position, so the message can say which event is wrong.
- A null `kind` is skipped: such an event is ignored by the builder too.
- A kind other than `open`, `hold` or `release` is an error; so is a known kind with a null time.

`intervals_from_events` calls it as `([_iv_check(time; kind)] | length) as $_`: collecting its (empty) output forces it to run over every event, and the binding to `$_` keeps the original input flowing on.

```jq
[{t: 1, k: "hold"}, {t: 2, k: "renew"}] | try [_iv_check(.t; .k)] catch .
```

```json
"intervals_from_events: event 1 has kind \"renew\"; expected \"open\", \"hold\", \"release\" or null"
```

## intervals_from_events

`intervals_from_events/5`, lines 755 to 784:

```jq
def intervals_from_events(resource; holder; time; kind; ttl):
  ([_iv_check(time; kind)] | length) as $_
  | [map(select((kind) != null)) | _groups(resource)[]
     | (.[0] | resource) as $res
     | sort_by([(time), ((kind) as $k | if $k == "open" then 0 elif $k == "hold" then 1 else 2 end)])
     # one pass; closed intervals leave through .out as they close, so nothing is appended to a
     # growing array. The trailing null is the end-of-data marker.
     | foreach (.[], null) as $e ({cur: null, out: []};
         .out = []
         | if $e == null then
             (if .cur != null then .out = [.cur + {ended_by: "open"}] | .cur = null else . end)
           else
             ($e | time) as $t | ($e | kind) as $k | ($e | holder) as $h | ($e | ttl) as $ttl
             | (if .cur != null and .cur.end != null and $t >= .cur.end
                then .out += [.cur + {ended_by: "lapsed"}] | .cur = null else . end)
             | if $k == "release" then
                 (if .cur != null and .cur.holder == $h
                  then .out += [.cur + {end: $t, ended_by: "released"}] | .cur = null else . end)
               elif .cur != null and .cur.holder == $h then
                 .cur.events += 1 | .cur.last = $t
                 | .cur.end = (if $ttl == null then null elif .cur.end == null then $t + $ttl
                               else ([.cur.end, $t + $ttl] | max) end)
               else
                 (if .cur != null then .out += [.cur + {end: $t, ended_by: "taken_over"}] else . end)
                 | .cur = {resource: $res, holder: $h, start: $t,
                           end: (if $ttl == null then null else $t + $ttl end),
                           last: $t, events: 1, start_seen: ($k == "open")}
               end
           end;
         .out[])];
```

Input: an event table. `resource`, `holder`, `time`, `kind` and `ttl` are expressions evaluated on each event. Output: one row per interval.

Before the loop:

- `map(select((kind) != null))` drops ignored events.
- `_groups(resource)[]` (from the grouping family) gives the events of each resource, resources in order of first appearance.
- `sort_by([(time), (… 0, 1 or 2)])` orders one resource's events by time, and at the same time by kind: open, hold, release. A release and a renewal logged in the same second therefore apply as "renewed, then released", whichever line came first in the log. This rule came from real lease logs, where the other order produced intervals that never started.

Each step of the loop, for event `$e` with time `$t`, kind `$k`, holder `$h`:

1. **Lapse.** `if .cur != null and .cur.end != null and $t >= .cur.end`: the open interval's validity ran out before this event, so it closes as `lapsed` at the end it already had, and nothing is open. `>=` because the end itself is outside the interval.
2. **Release.** If the current holder releases, the interval closes at `$t` as `released`. A release from anyone else, or with nothing open, falls through `else .` and changes nothing.
3. **Same holder again** (`open` or `hold`): the interval is extended. `events` and `last` are updated, and `end` becomes the later of the old end and `$t + $ttl`. A null `$ttl` on this event makes the end null: the newest evidence says it does not expire.
4. **Anyone else, or nothing open:** if an interval is open it closes at `$t` as `taken_over`; then a new interval starts at `$t`, with `start_seen` true only when the event's kind is `open`.

At the end-of-data marker, an interval still open leaves with `ended_by: "open"` and whatever end its last hold gave it.

One resource, traced. `ttl` is 100 on every event except the last two, where it is 50:

| time | event | what happens | open interval afterwards |
|---|---|---|---|
| 0 | open, ann | nothing was open: start | ann, 0 to 100, 1 event, start seen |
| 50 | hold, ann | same holder: extend to max(100, 150) | ann, 0 to 150, 2 events, last 50 |
| 120 | hold, bo | 120 is before 150, so no lapse; another holder: ann's closes at 120, `taken_over` | bo, 120 to 220, start not seen |
| 130 | release, ann | ann does not hold it: ignored | bo, 120 to 220 |
| 200 | release, bo | holder releases: closes at 200, `released` | none |
| 300 | hold, cy | nothing open: start | cy, 300 to 350 |
| 400 | hold, cy | 400 is past 350: cy's closes at 350, `lapsed`; then start | cy, 400 to 450 |
| end | | still open: leaves as `open` | |

```jq
[{t: 0, who: "ann", k: "open", ttl: 100}, {t: 50, who: "ann", k: "hold", ttl: 100},
 {t: 120, who: "bo", k: "hold", ttl: 100}, {t: 130, who: "ann", k: "release", ttl: null},
 {t: 200, who: "bo", k: "release", ttl: null}, {t: 300, who: "cy", k: "hold", ttl: 50},
 {t: 400, who: "cy", k: "hold", ttl: 50}]
| map(.seat = "seat-7")
| intervals_from_events(.seat; .who; .t; .k; .ttl)
| map(del(.resource))
```

```json
[
  {"holder": "ann", "start": 0, "end": 120, "last": 50, "events": 2, "start_seen": true, "ended_by": "taken_over"},
  {"holder": "bo", "start": 120, "end": 200, "last": 120, "events": 1, "start_seen": false, "ended_by": "released"},
  {"holder": "cy", "start": 300, "end": 350, "last": 300, "events": 1, "start_seen": false, "ended_by": "lapsed"},
  {"holder": "cy", "start": 400, "end": 450, "last": 400, "events": 1, "start_seen": false, "ended_by": "open"}
]
```

## join_within

`join_within/6`, lines 791 to 810:

```jq
# join_within (left outer): each left row with the interval of the same key whose [rstart, rend)
# contains the left row's ltime; a null rend means still open. No such interval, or a null key or
# time on the left: the left row alone. When several intervals of a key contain the time, the one
# that started last. Merged like every flat join: a field on both sides with different values is
# an error. Use it for "who held this at T"; join_asof is for "the latest value at or before T".
def join_within($intervals; lkey; rkey; ltime; rstart; rend):
  1.7976931348623157e308 as $inf
  | ([$intervals[] | select((rkey) != null and (rstart) != null)] | group_by(rkey)
     | map(sort_by(rstart)
           | {key: (.[0] | rkey | tojson),
              value: {rows: ., s: map(rstart), e: map((rend) // $inf)}}
           # m[i]: the latest end among rows 0..i, so a search going back can stop early
           | .value.m = [foreach .value.e[] as $x (null; if . == null or $x > . then $x else . end)])
     | from_entries) as $ix
  | [.[] as $l | ($l | lkey) as $k | ($l | ltime) as $t
     | if $k == null or $t == null or $ix[$k | tojson] == null then $l
       else $ix[$k | tojson] as $g
       | ($g.s | bsearch($t)) as $i
       | (if $i >= 0 then $i else -2 - $i end) as $at
       # the last start <= $t (bsearch may land on any of several equal starts)
       | ($at | until(. + 1 >= ($g.s | length) or $g.s[. + 1] > $t; . + 1)) as $last
       # go back until an interval contains $t, or no earlier one can
       | ($last | until(. < 0 or $g.e[.] > $t or $g.m[.] <= $t; . - 1)) as $c
       | if $c >= 0 and $g.e[$c] > $t then _merge($l; $g.rows[$c]) else $l end
       end];
```

Left outer: each left row with the interval of the same key that contains the row's time.

The index, built once per key from the intervals with a non-null key and start, sorted by start:

- `rows`: the interval rows; `s`: their starts; `e`: their ends, with a null end replaced by `$inf`, the largest number a double can hold, so an open interval contains every later time without a special case.
- `m`: for each position, the latest end among the rows up to and including it. `foreach .value.e[] as $x (null; if . == null or $x > . then $x else . end)` is a running maximum.

For a left row with key `$k` and time `$t`:

1. `($g.s | bsearch($t))` and the `-2 - $i` step find a start at or before `$t`, as in `join_asof`.
2. `until(. + 1 >= ($g.s | length) or $g.s[. + 1] > $t; . + 1)` moves forward to the last such start, since several intervals can start at the same time and `bsearch` may land on any of them.
3. `until(. < 0 or $g.e[.] > $t or $g.m[.] <= $t; . - 1)` walks back. It stops at the first interval whose end is after `$t` (it started at or before `$t`, so it contains it), or as soon as `m` says no interval this far back ends after `$t`, or at the front. Walking back from the last start is what makes the answer "the one that started last" when several contain `$t`.
4. If it stopped on an interval that contains `$t`, the rows are merged with `_merge`; otherwise the left row comes back alone.

Without `m`, step 3 would have to walk to the front of the key's intervals for every time that falls in a gap. For intervals that do not overlap, which is what `intervals_from_events` produces, the walk is at most one step.

```jq
[{seat: "s1", holder: "ann", start: 0, end: 120}, {seat: "s1", holder: "bo", start: 120, end: 200},
 {seat: "s1", holder: "cy", start: 400, end: null}] as $held
| [{at: 119}, {at: 120}, {at: 250}, {at: 9999}, {at: -5}]
| map(.seat = "s1")
| join_within($held; .seat; .seat; .at; .start; .end)
| map({at, holder})
```

```json
[
  {"at": 119, "holder": "ann"},
  {"at": 120, "holder": "bo"},
  {"at": 250, "holder": null},
  {"at": 9999, "holder": "cy"},
  {"at": -5, "holder": null}
]
```

119 is ann's last moment and 120 is bo's first: the end is outside the interval. 250 falls in a gap. cy's interval has no end, so it holds every time from 400 on.

## _iv_order_check

`_iv_order_check/3`, lines 812 to 813:

```jq
def _iv_order_check(start; fin; $who):
  if any(.[]; (fin) != null and (fin) < (start)) then error("\($who): an interval ends before it starts") else . end;
```

Passes its input through unchanged, or stops with an error when any interval has an end before its start. `$who` is the name of the calling function, for the message. A null end is allowed.

**Review finding 1.** A null start is not checked. `merge_intervals` sorts it first and treats it as the earliest start; `concurrency` emits a row with `t: null`. Neither is stated anywhere as intended behaviour. Proposed: both reject a null start by name, as `intervals_from_events` rejects a null time.

```jq
[{s: 5, e: 3}] | try _iv_order_check(.s; .e; "merge_intervals") catch .
```

```json
"merge_intervals: an interval ends before it starts"
```

## merge_intervals

`merge_intervals/3`, lines 818 to 834:

```jq
# merge_intervals: per key, intervals that overlap or touch become one row
# {key..., start, end, merged (how many went in)}; keys in order of first appearance, intervals in
# time order. A null end is open-ended and absorbs everything of its key that starts after it.
def merge_intervals(key; start; fin):
  _iv_order_check(start; fin; "merge_intervals")
  | [_groups(key)[]
     | (.[0] | key | if type == "object" then . else {key: .} end) as $k
     | sort_by(start)
     | foreach (.[], null) as $r ({cur: null, out: []};
         .out = []
         | if $r == null then (if .cur != null then .out = [.cur] | .cur = null else . end)
           else ($r | start) as $s | ($r | fin) as $e
           | if .cur != null and (.cur.end == null or $s <= .cur.end)
             then .cur.merged += 1
                  | .cur.end = (if .cur.end == null or $e == null then null else ([.cur.end, $e] | max) end)
             else (if .cur != null then .out = [.cur] else . end)
                  | .cur = $k + {start: $s, end: $e, merged: 1}
             end
           end;
         .out[])];
```

Per key, intervals that overlap or touch become one.

- `_groups(key)[]` takes each key's intervals; `$k` is the key as fields to put on the output row: the key itself when it is an object such as `{room}`, otherwise `{key: value}`.
- `sort_by(start)`, then the same `foreach` pattern as above. For each interval `$r`: if one is open and `$s <= .cur.end` (or the open one has no end), `$r` joins it: `merged` goes up by one and the end becomes the later of the two, or null if either is null. Otherwise the open one leaves and `$r` starts a new one.
- `<=`, not `<`: an interval that starts exactly where the previous one ends is merged with it.

```jq
[{room: "A", s: 1, e: 3}, {room: "A", s: 3, e: 5}, {room: "A", s: 8, e: 9},
 {room: "B", s: 2, e: null}, {room: "B", s: 7, e: 8}]
| merge_intervals({room}; .s; .e)
```

```json
[
  {"room": "A", "start": 1, "end": 5, "merged": 2},
  {"room": "A", "start": 8, "end": 9, "merged": 1},
  {"room": "B", "start": 2, "end": null, "merged": 2}
]
```

## concurrency

`concurrency/2`, lines 839 to 845:

```jq
# concurrency: how many intervals are open over time: one row {t, open} per moment the count
# changes, in time order (`end` is a jq keyword, so the parameter is called fin). An interval counts from its start up to, not including, its end; one
# with a null end never stops counting. The peak is `concurrency(...) | max_by(.open)`.
def concurrency(start; fin):
  _iv_order_check(start; fin; "concurrency")
  | [.[] | {t: (start), d: 1}, ((fin) as $e | if $e == null then empty else {t: $e, d: -1} end)]
  | group_by(.t)
  | [foreach .[] as $g ({open: 0};
       ($g | map(.d) | add) as $net | {open: (.open + $net), t: $g[0].t, net: $net};
       select(.net != 0) | {t, open})];
```

How many intervals are open, as a step function: one row per moment the count changes.

- Each interval becomes two small records: `{t: start, d: 1}` and, unless its end is null, `{t: end, d: -1}`.
- `group_by(.t)` gathers everything that happens at one moment, in time order.
- The `foreach` keeps a running count. `$net` is the sum of the `d` values at that moment; the state becomes `{open, t, net}`.
- `select(.net != 0) | {t, open}` emits a row only when the count really changed. One interval ending exactly when another starts gives a net of zero and no row: the count did not change.

```jq
[{s: 1, e: 5}, {s: 2, e: 5}, {s: 5, e: 9}, {s: 7, e: null}] | concurrency(.s; .e)
```

```json
[
  {"t": 1, "open": 1},
  {"t": 2, "open": 2},
  {"t": 5, "open": 1},
  {"t": 7, "open": 2},
  {"t": 9, "open": 1}
]
```

At 5 two intervals end and one starts, so the count goes from 2 to 1. The interval with no end keeps the count at 1 after 9.
