# State machines over time

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/state-machines-over-time.md`. Do not edit.

Five definitions that read the events of one entity, in time order, as a machine that is in one state at a time. Three of them share one move: **find the positions where something changes, then cut the array at those positions.**

```text
states:     Open  Open  Work  Open  Closed
position:   0     1     2     3     4
starts:     0           2     3     4          a position starts a block when its state differs from the one before
blocks:     [0, 2)      [2, 3) [3, 4) [4, end)
```

`$st` in the code is that list of start positions. Building it with `range | select` and then slicing by position does one pass over the events and appends to nothing.

## _time_check

`_time_check/2`, line 344:

```jq
# an event with a null time cannot be placed in time: an error naming the calling function
def _time_check(time; $who): if any(.[]; (time) == null) then error("\($who): an event has no time") else . end;
```

Passes its input through, or stops with `F: an event has no time` when any event's time is null; `$who` is the calling function's name. `state_blocks`, `transitions` and `sessions` each call it first, because a null time cannot be sorted into place or subtracted.

```jq
[{e: 1, t: null}, {e: 1, t: 5}] | try _time_check(.t; "sessions") catch .
```

```json
"sessions: an event has no time"
```

## _blocks

`_blocks/2`, lines 347 to 356:

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

Input: one entity's events, already sorted by time. Output: its blocks.

- `[range($n) | select(. == 0 or (state here != state before))] as $st`: the start positions.
- For block `$j` starting at `$i = $st[$j]`: `$nx` is the next start, or null for the last block.
- `start` is the time of the block's first event; `end` is the time of the next block's first event, so blocks tile the timeline with no gaps; the last block has a null end and a null duration.
- `events` is how many events fall in the block: next start minus this start, or the rest of the array.

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

The two Open events at 0 and 10 are one block of 30: a repeated state does not restart the clock.

## state_blocks

`state_blocks/3`, lines 364 to 367:

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

- `_time_check(time; "state_blocks")` refuses an event with no time.
- `group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})` gives one row per entity with its key fields and a `blocks` array.
- `[.[] | del(.blocks) as $k | .blocks[] | $k + .]` flattens: `$k` is the row without `blocks`, which is the entity key, and each block gets those fields.

```jq
[{id: "T1", t: 0, s: "Open"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 80, s: "Closed"}]
| state_blocks({id}; .t; .s)
```

```json
[
  {"id": "T1", "state": "Open", "start": 0, "end": 30, "duration": 30, "events": 1},
  {"id": "T1", "state": "Work", "start": 30, "end": 80, "duration": 50, "events": 1},
  {"id": "T1", "state": "Closed", "start": 80, "end": null, "duration": null, "events": 1},
  {"id": "T2", "state": "Open", "start": 5, "end": null, "duration": null, "events": 1}
]
```

**Review finding 9, fixed in 0.9.0.** Until 0.8.1 a null time was not checked in this family, and `sessions` stopped with jq's own `number (5) and null (null) cannot be subtracted`. All three functions now raise `F: an event has no time`.

## transitions

`transitions/3`, lines 370 to 374:

```jq
# transitions: one row per change of state: {entity key..., from, to, at (time of the change)}
def transitions(entity; time; state):
  _time_check(time; "transitions")
  | group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})
  | [.[] | del(.blocks) as $k | .blocks as $b | range(1; $b | length) as $i
     | $k + {from: $b[$i - 1].state, to: $b[$i].state, at: $b[$i].start}];
```

The same blocks, read as changes: for each block after the first, a row `{from, to, at}` where `at` is the block's start. `range(1; $b | length)` skips the first block, which has nothing before it.

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

## sessions

`sessions/3`, lines 379 to 386:

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

The same cut, with a different test: a position starts a session when the gap from the previous event is greater than `$gap`. Each session reports its number within the entity, its first and last event time, and its event count. `$a[$nx - 1]` is the last event before the next start.

```jq
[0, 10, 100, 120, 200] | map({user: "u1", t: .}) | sessions({user}; .t; 30)
```

```json
[
  {"user": "u1", "session": 1, "start": 0, "end": 10, "events": 2},
  {"user": "u1", "session": 2, "start": 100, "end": 120, "events": 2},
  {"user": "u1", "session": 3, "start": 200, "end": 200, "events": 1}
]
```

Gaps of 10 and 20 stay inside a session; gaps of 90 and 80 start a new one. A gap of exactly `$gap` does not.

## runs

`runs/1`, lines 390 to 394:

```jq
# runs: run-length encoding of an array in its given order: consecutive items with the same f value
# become {value, start (0-based position of the first), n}. Streaks are the long runs.
def runs(f):
  . as $a | length as $n
  | [range($n) | select(. == 0 or (($a[.] | f) != ($a[. - 1] | f)))] as $st
  | [range($st | length) as $j | $st[$j] as $i
     | {value: ($a[$i] | f), start: $i, n: ((if $j + 1 < ($st | length) then $st[$j + 1] else $n end) - $i)}];
```

Run-length encoding of an array as it stands (no sorting, no entity): consecutive items with the same `f` become `{value, start, n}`.

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

The longest failing streak is then `map(select(.value == "fail")) | max_by(.n)`.
