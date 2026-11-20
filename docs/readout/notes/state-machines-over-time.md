### What it is for

Six definitions. Five of them read the events of one entity, in time order, as a machine that is in one state at a time; the sixth, `runs`, does the same cut on a plain array. An entity is the thing the events belong to, such as one request or one user. A block is a stretch of time that the entity spends in one state.

| The question | Use | Output |
|---|---|---|
| how long was each thing in each state | `state_blocks` | one row per block: state, start, end, duration, events |
| what changed, and when | `transitions` | one row per change: from, to, at |
| which events belong to one visit | `sessions` | one row per session: number, start, end, events |
| how long was the longest streak | `runs` | run-length encoding of a list as it stands |

The input is a table of events, read through three filters: the entity (`{id}`), the time (`.t`) and the state (`.s`); `sessions` takes a gap limit instead of a state. What makes a table an event log is which fields the function is told to read. Intervals with an explicit end, such as leases and sessions that are opened and released, are built by `intervals_from_events` on page 70; funnels and retention over events are on page 80.

Most examples on this page use the five events of request T1:

| id | t | s |
|---|---|---|
| T1 | 0 | Open |
| T1 | 10 | Open |
| T1 | 30 | Work |
| T1 | 50 | Open |
| T1 | 80 | Closed |

By hand: Open from 0 to 30, with two events; Work from 30 to 50; Open again from 50 to 80; Closed from 80, with no end yet.

```jq run
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 50, s: "Open"}, {id: "T1", t: 80, s: "Closed"}]
| state_blocks({id}; .t; .s)
```

Three of the definitions share one move: **find the positions where something changes, then cut the array at those positions.**

```text
states:     Open  Open  Work  Open  Closed
position:   0     1     2     3     4
starts:     0           2     3     4          a position starts a block when its state differs from the one before
blocks:     [0, 2)      [2, 3) [3, 4) [4, end)
```

`$st` in the code is that list of start positions. Building it with `range` and `select`, and then reading the array by position, does one pass over the events and appends to nothing.

### The rules it keeps

- **A repeated state does not restart the clock:** the Open events at 0 and 10 are one block.
- **Blocks tile the timeline.** A block ends where the next one starts, so there are no gaps and no overlaps.
- **The last block has no end:** its `end` and `duration` are null. The data stopped; the state did not.
- **A session is cut where the gap is greater than the limit**; a gap of exactly the limit stays inside the session. A session's `end` is the time of its last event, so a session of one event starts and ends at the same time.
- **Order:** entities in the order their first event appears in the input (the grouping rule); inside an entity, events are sorted by time with a stable sort, so two events at the same time keep input order. `runs` does not sort at all: it reads the array as it stands.
- **The entity key is copied into every output row**, as `group_agg` does: an object key's fields, or a field `key`.
- **Refuses** an event with a null time: `state_blocks: an event has no time` (and the same for `transitions` and `sessions`), because such an event can be neither sorted into place nor subtracted. And an input that is not a table, or for `runs` not a list (page 00).

### Beside core jq, SQL and pandas

Core jq has no state or session function. Run-length encoding is the usual hand-written `reduce`:

```jq
reduce .[] as $x ([]; if length > 0 and .[-1].value == $x then .[-1].n += 1 else . + [{value: $x, n: 1}] end)
```

On `["ok", "ok", "fail", "fail", "fail", "ok"]` it gives the same three runs as `runs(.)` on jq 1.7.1, gojq and jaq (gojq prints each run's fields sorted). It has no start position, and the state version needs the per-entity grouping, the sort by time and the end of each block from the next block's start written around it each time.

SQL writes this as "gaps and islands": `LAG(s) OVER (PARTITION BY id ORDER BY t)` marks a change, a running `SUM` of the marks numbers the blocks, a `GROUP BY id, block` takes each block's first state, start and count, and a `LEAD` of the start gives the end. Run on DuckDB over T1's events, that query gives the four blocks above, with end 30, 50, 80 and NULL. For sessions the mark is `t - LAG(t) > 30`.

pandas does the same with `(s != s.groupby(id).shift()).groupby(id).cumsum()` as the block number, then a `groupby` on entity and block (checked with pandas 3.1.1: the same four blocks, starts and counts); sessions use `df.groupby(id).t.diff() > gap`.

What the family adds: the whole gaps-and-islands pattern as one call, with the open last block, the null-time check and the entity's key handled.

### Decisions

- **One pass, cut at positions.** The blocks are found from the list of positions where the state changes, not by appending to a growing array; the same cut serves `_blocks`, `sessions` and `runs`.
- **0.9.0 (2026-11-18, spec 55).** `state_blocks`, `transitions` and `sessions` refuse a null time (review finding 9); before, `sessions` failed with jq's own `number (5) and null (null) cannot be subtracted`. The comment of `state_blocks` was moved back above it (finding 5).

## _time_check/2
<!-- code: da10aa6a -->

A guard that `state_blocks`, `transitions` and `sessions` each call first. An event with a null time cannot be sorted into place or subtracted, so it stops the function with an error that names it.

### The example

Events that all have a time pass through unchanged. One event with no time is the error. The second argument is the name of the calling function, for the message.

```jq run
([{id: "T1", t: 0}, {id: "T1", t: 5}] | _time_check(.t; "sessions")),
([{id: "T1", t: null}, {id: "T1", t: 5}] | try _time_check(.t; "sessions") catch .)
```

### The definition

<!-- definition -->

- `any(.[]; (time) == null)`: true when the `time` filter gives null on at least one event.
- `error("\($who): an event has no time")`: the message starts with the caller's name, which is the value `$who`.
- `else . end`: otherwise the input goes on as it is, so the guard can be the first step of a pipeline.

## _blocks/2
<!-- code: e3881968 -->

The blocks of one entity: its events, already sorted by time, with consecutive events of the same state merged. `state_blocks` and `transitions` call it once per entity.

### The example

The five events of T1.

```jq run
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| _blocks(.t; .s)
```

Four blocks from five events. The two Open events at 0 and 10 are one block that lasts from 0 to 30: a repeated state does not restart the clock. Each block ends where the next one starts, so the blocks cover the timeline with no gaps. The last block has no end yet, and so no duration.

### Reading the call

Both arguments are filters, each run on one event: `time` gives the event's time and `state` its state.

### What happens inside, on the example

Step 1, `[range($n) | select(. == 0 or (state here != state before))] as $st`: the positions that start a block. Position 0 always does. Position 1 does not, because its state equals the one before.

```jq run
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .s) != ($a[. - 1] | .s)))]
```

Step 2: for each block number `$j`, its own start `$i = $st[$j]` and the next block's start `$nx`, which is null for the last block.

```jq run
[0, 2, 3, 4] as $st
| [range($st | length) as $j | {j: $j, i: $st[$j], nx: (if $j + 1 < ($st | length) then $st[$j + 1] else null end)}]
```

Step 3: each block is read off those two positions. For block 0, `$i` is 0 and `$nx` is 2: `start` is the time of event 0, `end` is the time of event 2, `duration` is their difference, and `events` is `$nx - $i`.

```jq run
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| {state: .[0].s, start: .[0].t, end: .[2].t, duration: (.[2].t - .[0].t), events: (2 - 0)}
```

That is the first block of the result at the top.

### The definition

<!-- definition -->

- `. as $a | length as $n`: the events and their count, under names.
- The `$st` line: step 1.
- `[range($st | length) as $j | $st[$j] as $i | ...]`: one block per start position.
- The `$nx` line: step 2.
- `$t0` and `$t1`: the time of the block's first event, and of the next block's first event, or null.
- The object: step 3. `events` for the last block is `$n - $i`, the rest of the array.

## state_blocks/3
<!-- code: 47d58bd3 -->

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

```jq run
[{id: "T1", t: 30, s: "Work"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 0, s: "Open"},
 {id: "T1", t: 80, s: "Closed"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 50, s: "Open"}]
| state_blocks({id}; .t; .s)
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

```jq run
[{id: "T1", t: 30, s: "Work"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 0, s: "Open"},
 {id: "T1", t: 80, s: "Closed"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 50, s: "Open"}]
| group_agg({id}; {blocks: (sort_by(.t) | _blocks(.t; .s))})
```

Step 3, `[.[] | del(.blocks) as $k | .blocks[] | $k + .]`: the nested blocks are flattened. `$k` is the row without its `blocks` field, which is the entity key, and each block gets those fields in front. On the T2 row:

```jq run
{id: "T2", blocks: [{state: "Open", start: 5, end: null, duration: null, events: 1}]}
| del(.blocks) as $k | .blocks[] | $k + .
```

### What is refused

```jq run
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: null, s: "Work"}] | try state_blocks({id}; .t; .s) catch .
```

### The definition

<!-- definition -->

The three lines are steps 1, 2 and 3. `sort_by` is stable, so two events of one entity with the same time keep their input order.

## transitions/3
<!-- code: f972ddf2 -->

One row per change of state: from which state, to which, and when. It answers "how often does a request go from Work back to Open".

### The example

The five events of T1.

```jq run
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 50, s: "Open"}, {id: "T1", t: 80, s: "Closed"}]
| transitions({id}; .t; .s)
```

Three changes from four blocks. The event at 10 is no change, because the state stayed Open. An entity with one block has no rows here.

### What happens inside, on the example

Steps 1 and 2 are those of `state_blocks`: the time check, then one row per entity with its `blocks`. Step 3 reads each pair of neighbouring blocks: for `$i` from 1, `from` is the state of block `$i - 1`, `to` is the state of block `$i`, and `at` is the start of block `$i`. On the states and starts of T1's four blocks:

```jq run
[{state: "Open", start: 0}, {state: "Work", start: 30}, {state: "Open", start: 50}, {state: "Closed", start: 80}] as $b
| [range(1; $b | length) as $i | {from: $b[$i - 1].state, to: $b[$i].state, at: $b[$i].start}]
```

### The definition

<!-- definition -->

- The first two lines are the same as in `state_blocks`, with the function's own name in the time check.
- `range(1; $b | length) as $i`: from 1, because the first block has nothing before it.
- `$k + {from: ..., to: ..., at: ...}`: the entity key in front, as in `state_blocks`.

## sessions/3
<!-- code: 0ef6729d -->

Events grouped into sessions: per entity, a new session starts when the gap since the previous event is greater than a limit. It is the usual way to turn page views into visits.

### The example

Five events of user `u1`, at times 0, 10, 100, 120 and 200, with a gap limit of 30.

```jq run
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| sessions({user}; .t; 30)
```

Three sessions. The gaps are 10, 90, 20 and 80. The gaps of 10 and 20 stay inside a session, and the gaps of 90 and 80 each start a new one. `end` is the time of the session's last event, so a session of one event starts and ends at the same time.

### Reading the call

`entity` and `time` are filters run on one event, as in `state_blocks`. The third argument, `$gap`, is a value, in the same unit as the times.

### What happens inside, on the example

Steps 1 and 2 have the shape of `state_blocks`: the time check, then `group_agg` by entity with the events sorted by time. Inside one entity:

Step 3, the start positions `$st`: position 0, and every position whose gap from the event before is greater than `$gap`.

```jq run
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .t) - ($a[. - 1] | .t)) > 30)]
```

Step 4: session `$j` runs from its start `$i` up to the next start `$nx`, or to the end of the array. Its last event is at position `$nx - 1`. For the first session, `$i` is 0 and `$nx` is 2:

```jq run
[{user: "u1", t: 0}, {user: "u1", t: 10}, {user: "u1", t: 100}, {user: "u1", t: 120}, {user: "u1", t: 200}]
| {session: 1, start: .[0].t, end: .[2 - 1].t, events: (2 - 0)}
```

Step 5: the nested sessions are flattened and the entity key put in front, as in `state_blocks`.

### Edge cases and what is refused

A gap of exactly `$gap` does not start a new session, because the test is "greater than". An event with no time is the error.

```jq run
([{user: "u1", t: 0}, {user: "u1", t: 30}] | sessions({user}; .t; 30)),
([{user: "u1", t: 0}, {user: "u1", t: null}] | try sessions({user}; .t; 30) catch .)
```

### The definition

<!-- definition -->

- `_time_check(time; "sessions")`: the guard. Without it the subtraction in step 3 would fail on a null.
- `group_agg(entity; {sessions: (sort_by(time) | ...)})`: one row per entity.
- The `$st` line: step 3.
- The `$nx` line and the object: step 4. Sessions are numbered from 1 within the entity (`$j + 1`).
- The last line: step 5.

## runs/1
<!-- code: 00ff4fd0 -->

Run-length encoding: consecutive items with the same value become one row with the value, where the run starts and how long it is. It works on an array as it stands, with no sorting and no entity. Streaks are the long runs.

### The example

Six check results in order.

```jq run
["ok", "ok", "fail", "fail", "fail", "ok"] | runs(.)
```

Three runs: two `ok` from position 0, three `fail` from position 2, one `ok` from position 5. The lengths add up to 6.

The argument is a filter that gives each item's value. Here the items are the values themselves, so it is `.`; for an array of rows it would be a field such as `.status`.

The longest failing streak is then one more step:

```jq run
["ok", "ok", "fail", "fail", "fail", "ok"] | runs(.) | map(select(.value == "fail")) | max_by(.n)
```

### What happens inside, on the example

Step 1, the start positions `$st`: position 0, and every position whose value differs from the one before.

```jq run
["ok", "ok", "fail", "fail", "fail", "ok"]
| . as $a | [range(length) | select(. == 0 or (($a[.] | .) != ($a[. - 1] | .)))]
```

Step 2: run `$j` starts at `$i = $st[$j]`, and its length `n` is the next start minus `$i`, or the array's length minus `$i` for the last run. The lengths here are 2 - 0, 5 - 2 and 6 - 5.

### The definition

<!-- definition -->

- The `$st` line: step 1, the same cut as in `_blocks`.
- The object: `value` is `f` on the run's first item, `start` its position counting from 0, and `n` step 2.
