# State machines over time

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/state-machines-over-time.md`. Do not edit.

Six definitions. Five of them read the events of one entity, in time order, as a machine that is in one state at a time; the sixth, `runs`, does the same cut on a plain array. An entity is the thing the events belong to, such as one request or one user. A block is a stretch of time that the entity spends in one state.

Three of the definitions share one move: **find the positions where something changes, then cut the array at those positions.**

```text
states:     Open  Open  Work  Open  Closed
position:   0     1     2     3     4
starts:     0           2     3     4          a position starts a block when its state differs from the one before
blocks:     [0, 2)      [2, 3) [3, 4) [4, end)
```

`$st` in the code is that list of start positions. Building it with `range` and `select`, and then reading the array by position, does one pass over the events and appends to nothing.

Most examples on this page use the five events of request T1 drawn above:

| id | t | s |
|---|---|---|
| T1 | 0 | Open |
| T1 | 10 | Open |
| T1 | 30 | Work |
| T1 | 50 | Open |
| T1 | 80 | Closed |

## _time_check

A guard that `state_blocks`, `transitions` and `sessions` each call first. An event with a null time cannot be sorted into place or subtracted, so it stops the function with an error that names it.

### The example

Events that all have a time pass through unchanged. One event with no time is the error. The second argument is the name of the calling function, for the message.

```jq
([{id: "T1", t: 0}, {id: "T1", t: 5}] | _time_check(.t; "sessions")),
([{id: "T1", t: null}, {id: "T1", t: 5}] | try _time_check(.t; "sessions") catch .)
```

```json
[{"id":"T1","t":0},{"id":"T1","t":5}]
"sessions: an event has no time"
```

### The definition

`_time_check/2`, lines 343 to 344:

```jq
# an event with a null time cannot be placed in time: an error naming the calling function
def _time_check(time; $who): if any(.[]; (time) == null) then error("\($who): an event has no time") else . end;
```

- `any(.[]; (time) == null)`: true when the `time` filter gives null on at least one event.
- `error("\($who): an event has no time")`: the message starts with the caller's name, which is the value `$who`.
- `else . end`: otherwise the input goes on as it is, so the guard can be the first step of a pipeline.

## _blocks

The blocks of one entity: its events, already sorted by time, with consecutive events of the same state merged. `state_blocks` and `transitions` call it once per entity.

### The example

The five events of T1.

```jq
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| _blocks(.t; .s)
```

```json
[
  {"state": "Open", "start": 0, "end": 30, "duration": 30, "events": 2},
  {"state": "Work", "start": 30, "end": 50, "duration": 20, "events": 1},
  {"state": "Open", "start": 50, "end": 80, "duration": 30, "events": 1},
  {"state": "Closed", "start": 80, "end": null, "duration": null, "events": 1}
]
```

Four blocks from five events. The two Open events at 0 and 10 are one block that lasts from 0 to 30: a repeated state does not restart the clock. Each block ends where the next one starts, so the blocks cover the timeline with no gaps. The last block has no end yet, and so no duration.

### Reading the call

Both arguments are filters, each run on one event: `time` gives the event's time and `state` its state.

### What happens inside, on the example

Step 1, `[range($n) | select(. == 0 or (state here != state before))] as $st`: the positions that start a block. Position 0 always does. Position 1 does not, because its state equals the one before.

```jq
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .s) != ($a[. - 1] | .s)))]
```

```json
[0,2,3,4]
```

Step 2: for each block number `$j`, its own start `$i = $st[$j]` and the next block's start `$nx`, which is null for the last block.

```jq
[0, 2, 3, 4] as $st
| [range($st | length) as $j | {j: $j, i: $st[$j], nx: (if $j + 1 < ($st | length) then $st[$j + 1] else null end)}]
```

```json
[
  {"j": 0, "i": 0, "nx": 2},
  {"j": 1, "i": 2, "nx": 3},
  {"j": 2, "i": 3, "nx": 4},
  {"j": 3, "i": 4, "nx": null}
]
```

Step 3: each block is read off those two positions. For block 0, `$i` is 0 and `$nx` is 2: `start` is the time of event 0, `end` is the time of event 2, `duration` is their difference, and `events` is `$nx - $i`.

```jq
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| {state: .[0].s, start: .[0].t, end: .[2].t, duration: (.[2].t - .[0].t), events: (2 - 0)}
```

```json
{"state":"Open","start":0,"end":30,"duration":30,"events":2}
```

That is the first block of the result at the top.

### The definition

`_blocks/2`, lines 346 to 356:

```jq
# the blocks of one entity's events, already sorted by time
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
```

- `. as $a | length as $n`: the events and their count, under names.
- The `$st` line: step 1.
- `[range($st | length) as $j | $st[$j] as $i | ...]`: one block per start position.
- The `$nx` line: step 2.
- `$t0` and `$t1`: the time of the block's first event, and of the next block's first event, or null.
- The object: step 3. `events` for the last block is `$n - $i`, the rest of the array.

## state_blocks

A table of events into a table of blocks: per entity, how long it spent in each state, in order. It answers "how long was each request in each status".

### The example

The events of two requests, mixed and not in time order.

| id | t | s |
|---|---|---|
| T1 | 30 | Work |
| T2 | 5 | Open |
| T1 | 0 | Open |
| T1 | 80 | Closed |
| T1 | 10 | Open |
| T1 | 50 | Open |

```jq
[{id: "T1", t: 30, s: "Work"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 0, s: "Open"},
 {id: "T1", t: 80, s: "Closed"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 50, s: "Open"}]
| state_blocks({id}; .t; .s)
```

```json
[
  {"id": "T1", "state": "Open", "start": 0, "end": 30, "duration": 30, "events": 2},
  {"id": "T1", "state": "Work", "start": 30, "end": 50, "duration": 20, "events": 1},
  {"id": "T1", "state": "Open", "start": 50, "end": 80, "duration": 30, "events": 1},
  {"id": "T1", "state": "Closed", "start": 80, "end": null, "duration": null, "events": 1},
  {"id": "T2", "state": "Open", "start": 5, "end": null, "duration": null, "events": 1}
]
```

Five rows: the four blocks of T1 in time order, then the one block of T2. T1 comes first because its first event comes first in the input. Each row carries the entity key, `id`.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `entity` | `{id}` | one event | the entity the event belongs to; `{id}` is short for `{id: .id}` |
| `time` | `.t` | one event | the event's time |
| `state` | `.s` | one event | the event's state |

The entity key is copied into the output as `group_agg` does on the grouping page: the fields of an object key, or a field called `key` for any other value.

### What happens inside, on the example

Step 1, `_time_check(time; "state_blocks")`: every event has a time, so the table passes through.

Step 2, `group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})`: one row per entity. Inside each group the events are sorted by time and handed to `_blocks`.

```jq
[{id: "T1", t: 30, s: "Work"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 0, s: "Open"},
 {id: "T1", t: 80, s: "Closed"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 50, s: "Open"}]
| group_agg({id}; {blocks: (sort_by(.t) | _blocks(.t; .s))})
```

```json
[
  {"id": "T1", "blocks": [{"state": "Open", "start": 0, "end": 30, "duration": 30, "events": 2}, {"state": "Work", "start": 30, "end": 50, "duration": 20, "events": 1}, {"state": "Open", "start": 50, "end": 80, "duration": 30, "events": 1}, {"state": "Closed", "start": 80, "end": null, "duration": null, "events": 1}]},
  {"id": "T2", "blocks": [{"state": "Open", "start": 5, "end": null, "duration": null, "events": 1}]}
]
```

Step 3, `[.[] | del(.blocks) as $k | .blocks[] | $k + .]`: the nested blocks are flattened. `$k` is the row without its `blocks` field, which is the entity key, and each block gets those fields in front. On the T2 row:

```jq
{id: "T2", blocks: [{state: "Open", start: 5, end: null, duration: null, events: 1}]}
| del(.blocks) as $k | .blocks[] | $k + .
```

```json
{"id":"T2","state":"Open","start":5,"end":null,"duration":null,"events":1}
```

### What is refused

```jq
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: null, s: "Work"}] | try state_blocks({id}; .t; .s) catch .
```

```json
"state_blocks: an event has no time"
```

### The definition

`state_blocks/3`, lines 357 to 367:

```jq
# state_blocks: per entity, events sorted by time (stable), consecutive events with the same state
# merged into one block: {entity key..., state, start (time of its first event), end (time of the
# next block's first event, null for the entity's last block), duration (end - start, null when
# open), events (how many events it merged)}. A repeated state does not restart the clock: an
# assignee change while the status stays Open is still the same Open block. The entity key is
# merged in as group_agg does (an object key's fields, or field "key"). Order: entities by first
# appearance, blocks by time. An event with a null time is an error.
def state_blocks(entity; time; state):
  _time_check(time; "state_blocks")
  | group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})
  | [.[] | del(.blocks) as $k | .blocks[] | $k + .];
```

The three lines are steps 1, 2 and 3. `sort_by` is stable, so two events of one entity with the same time keep their input order.

## transitions

One row per change of state: from which state, to which, and when. It answers "how often does a request go from Work back to Open".

### The example

The five events of T1.

```jq
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 50, s: "Open"}, {id: "T1", t: 80, s: "Closed"}]
| transitions({id}; .t; .s)
```

```json
[
  {"id": "T1", "from": "Open", "to": "Work", "at": 30},
  {"id": "T1", "from": "Work", "to": "Open", "at": 50},
  {"id": "T1", "from": "Open", "to": "Closed", "at": 80}
]
```

Three changes from four blocks. The event at 10 is no change, because the state stayed Open. An entity with one block has no rows here.

### What happens inside, on the example

Steps 1 and 2 are those of `state_blocks`: the time check, then one row per entity with its `blocks`. Step 3 reads each pair of neighbouring blocks: for `$i` from 1, `from` is the state of block `$i - 1`, `to` is the state of block `$i`, and `at` is the start of block `$i`. On the states and starts of T1's four blocks:

```jq
[{state: "Open", start: 0}, {state: "Work", start: 30}, {state: "Open", start: 50}, {state: "Closed", start: 80}] as $b
| [range(1; $b | length) as $i | {from: $b[$i - 1].state, to: $b[$i].state, at: $b[$i].start}]
```

```json
[
  {"from": "Open", "to": "Work", "at": 30},
  {"from": "Work", "to": "Open", "at": 50},
  {"from": "Open", "to": "Closed", "at": 80}
]
```

### The definition

`transitions/3`, lines 369 to 374:

```jq
# transitions: one row per change of state: {entity key..., from, to, at (time of the change)}
def transitions(entity; time; state):
  _time_check(time; "transitions")
  | group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})
  | [.[] | del(.blocks) as $k | .blocks as $b | range(1; $b | length) as $i
     | $k + {from: $b[$i - 1].state, to: $b[$i].state, at: $b[$i].start}];
```

- The first two lines are the same as in `state_blocks`, with the function's own name in the time check.
- `range(1; $b | length) as $i`: from 1, because the first block has nothing before it.
- `$k + {from: ..., to: ..., at: ...}`: the entity key in front, as in `state_blocks`.

## sessions

Events grouped into sessions: per entity, a new session starts when the gap since the previous event is greater than a limit. It is the usual way to turn page views into visits.

### The example

Five events of user `u1`, at times 0, 10, 100, 120 and 200, with a gap limit of 30.

```jq
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| sessions({user}; .t; 30)
```

```json
[
  {"user": "u1", "session": 1, "start": 0, "end": 10, "events": 2},
  {"user": "u1", "session": 2, "start": 100, "end": 120, "events": 2},
  {"user": "u1", "session": 3, "start": 200, "end": 200, "events": 1}
]
```

Three sessions. The gaps are 10, 90, 20 and 80. The gaps of 10 and 20 stay inside a session, and the gaps of 90 and 80 each start a new one. `end` is the time of the session's last event, so a session of one event starts and ends at the same time.

### Reading the call

`entity` and `time` are filters run on one event, as in `state_blocks`. The third argument, `$gap`, is a value, in the same unit as the times.

### What happens inside, on the example

Steps 1 and 2 have the shape of `state_blocks`: the time check, then `group_agg` by entity with the events sorted by time. Inside one entity:

Step 3, the start positions `$st`: position 0, and every position whose gap from the event before is greater than `$gap`.

```jq
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .t) - ($a[. - 1] | .t)) > 30)]
```

```json
[0,2,4]
```

Step 4: session `$j` runs from its start `$i` up to the next start `$nx`, or to the end of the array. Its last event is at position `$nx - 1`. For the first session, `$i` is 0 and `$nx` is 2:

```jq
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| {session: 1, start: .[0].t, end: .[2 - 1].t, events: (2 - 0)}
```

```json
{"session":1,"start":0,"end":10,"events":2}
```

Step 5: the nested sessions are flattened and the entity key put in front, as in `state_blocks`.

### Edge cases and what is refused

A gap of exactly `$gap` does not start a new session, because the test is "greater than". An event with no time is the error.

```jq
([{user: "u1", t: 0}, {user: "u1", t: 30}] | sessions({user}; .t; 30)),
([{user: "u1", t: 0}, {user: "u1", t: null}] | try sessions({user}; .t; 30) catch .)
```

```json
[{"user":"u1","session":1,"start":0,"end":30,"events":2}]
"sessions: an event has no time"
```

### The definition

`sessions/3`, lines 376 to 386:

```jq
# sessions: per entity, events sorted by time; a new session starts when the gap since the previous
# event is greater than $gap. Rows: {entity key..., session (1, 2, ... within the entity), start,
# end (time of its last event), events}.
def sessions(entity; time; $gap):
  _time_check(time; "sessions")
  | group_agg(entity; {sessions: (sort_by(time) | . as $a | length as $n
      | [range($n) | select(. == 0 or (($a[.] | time) - ($a[. - 1] | time)) > $gap)] as $st
      | [range($st | length) as $j | $st[$j] as $i
         | (if $j + 1 < ($st | length) then $st[$j + 1] else $n end) as $nx
         | {session: ($j + 1), start: ($a[$i] | time), end: ($a[$nx - 1] | time), events: ($nx - $i)}])})
  | [.[] | del(.sessions) as $k | .sessions[] | $k + .];
```

- `_time_check(time; "sessions")`: the guard. Without it the subtraction in step 3 would fail on a null.
- `group_agg(entity; {sessions: (sort_by(time) | ...)})`: one row per entity.
- The `$st` line: step 3.
- The `$nx` line and the object: step 4. Sessions are numbered from 1 within the entity (`$j + 1`).
- The last line: step 5.

## runs

Run-length encoding: consecutive items with the same value become one row with the value, where the run starts and how long it is. It works on an array as it stands, with no sorting and no entity. Streaks are the long runs.

### The example

Six check results in order.

```jq
["ok", "ok", "fail", "fail", "fail", "ok"] | runs(.)
```

```json
[
  {"value": "ok", "start": 0, "n": 2},
  {"value": "fail", "start": 2, "n": 3},
  {"value": "ok", "start": 5, "n": 1}
]
```

Three runs: two `ok` from position 0, three `fail` from position 2, one `ok` from position 5. The lengths add up to 6.

The argument is a filter that gives each item's value. Here the items are the values themselves, so it is `.`; for an array of rows it would be a field such as `.status`.

The longest failing streak is then one more step:

```jq
["ok", "ok", "fail", "fail", "fail", "ok"] | runs(.) | map(select(.value == "fail")) | max_by(.n)
```

```json
{"value":"fail","start":2,"n":3}
```

### What happens inside, on the example

Step 1, the start positions `$st`: position 0, and every position whose value differs from the one before.

```jq
["ok", "ok", "fail", "fail", "fail", "ok"]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .) != ($a[. - 1] | .)))]
```

```json
[0,2,5]
```

Step 2: run `$j` starts at `$i = $st[$j]`, and its length `n` is the next start minus `$i`, or the array's length minus `$i` for the last run. The lengths here are 2 - 0, 5 - 2 and 6 - 5.

### The definition

`runs/1`, lines 388 to 394:

```jq
# runs: run-length encoding of an array in its given order: consecutive items with the same f value
# become {value, start (0-based position of the first), n}. Streaks are the long runs.
def runs(f):
  . as $a | length as $n
  | [range($n) | select(. == 0 or (($a[.] | f) != ($a[. - 1] | f)))] as $st
  | [range($st | length) as $j | $st[$j] as $i
     | {value: ($a[$i] | f), start: $i, n: ((if $j + 1 < ($st | length) then $st[$j + 1] else $n end) - $i)}];
```

- The `$st` line: step 1, the same cut as in `_blocks`.
- The object: `value` is `f` on the run's first item, `start` its position counting from 0, and `n` step 2.
