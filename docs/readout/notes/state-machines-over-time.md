Five definitions that read the events of one entity, in time order, as a machine that is in one state at a time. Three of them share one move: **find the positions where something changes, then cut the array at those positions.**

```text
states:     Open  Open  Work  Open  Closed
position:   0     1     2     3     4
starts:     0           2     3     4          a position starts a block when its state differs from the one before
blocks:     [0, 2)      [2, 3) [3, 4) [4, end)
```

`$st` in the code is that list of start positions. Building it with `range | select` and then slicing by position does one pass over the events and appends to nothing.

## _time_check/2
<!-- code: da10aa6a -->

Passes its input through, or stops with `F: an event has no time` when any event's time is null; `$who` is the calling function's name. `state_blocks`, `transitions` and `sessions` each call it first, because a null time cannot be sorted into place or subtracted.

```jq run
[{e: 1, t: null}, {e: 1, t: 5}] | try _time_check(.t; "sessions") catch .
```

## _blocks/2
<!-- code: e3881968 -->

Input: one entity's events, already sorted by time. Output: its blocks.

- `[range($n) | select(. == 0 or (state here != state before))] as $st`: the start positions.
- For block `$j` starting at `$i = $st[$j]`: `$nx` is the next start, or null for the last block.
- `start` is the time of the block's first event; `end` is the time of the next block's first event, so blocks tile the timeline with no gaps; the last block has a null end and a null duration.
- `events` is how many events fall in the block: next start minus this start, or the rest of the array.

```jq run
[{t: 0, s: "Open"}, {t: 10, s: "Open"}, {t: 30, s: "Work"}, {t: 50, s: "Open"}, {t: 80, s: "Closed"}]
| _blocks(.t; .s)
```

The two Open events at 0 and 10 are one block of 30: a repeated state does not restart the clock.

## state_blocks/3
<!-- code: d2bc4a2b -->

- `_time_check(time; "state_blocks")` refuses an event with no time.
- `group_agg(entity; {blocks: (sort_by(time) | _blocks(time; state))})` gives one row per entity with its key fields and a `blocks` array.
- `[.[] | del(.blocks) as $k | .blocks[] | $k + .]` flattens: `$k` is the row without `blocks`, which is the entity key, and each block gets those fields.

```jq run
[{id: "T1", t: 0, s: "Open"}, {id: "T2", t: 5, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 80, s: "Closed"}]
| state_blocks({id}; .t; .s)
```

**Review finding 9, fixed in 0.9.0.** Until 0.8.1 a null time was not checked in this family, and `sessions` stopped with jq's own `number (5) and null (null) cannot be subtracted`. All three functions now raise `F: an event has no time`.

## transitions/3
<!-- code: 4cb8d9cf -->

The same blocks, read as changes: for each block after the first, a row `{from, to, at}` where `at` is the block's start. `range(1; $b | length)` skips the first block, which has nothing before it.

```jq run
[{id: "T1", t: 0, s: "Open"}, {id: "T1", t: 10, s: "Open"}, {id: "T1", t: 30, s: "Work"}, {id: "T1", t: 50, s: "Open"}, {id: "T1", t: 80, s: "Closed"}]
| transitions({id}; .t; .s)
```

## sessions/3
<!-- code: ef77a136 -->

The same cut, with a different test: a position starts a session when the gap from the previous event is greater than `$gap`. Each session reports its number within the entity, its first and last event time, and its event count. `$a[$nx - 1]` is the last event before the next start.

```jq run
[0, 10, 100, 120, 200] | map({user: "u1", t: .}) | sessions({user}; .t; 30)
```

Gaps of 10 and 20 stay inside a session; gaps of 90 and 80 start a new one. A gap of exactly `$gap` does not.

## runs/1
<!-- code: 2be581b8 -->

Run-length encoding of an array as it stands (no sorting, no entity): consecutive items with the same `f` become `{value, start, n}`.

```jq run
["ok", "ok", "fail", "fail", "fail", "ok"] | runs(.)
```

The longest failing streak is then `map(select(.value == "fail")) | max_by(.n)`.
