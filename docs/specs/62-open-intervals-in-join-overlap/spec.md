---
spec_id: 62-open-intervals-in-join-overlap
status: CLOSED
closed_as: SHIPPED
since: 2026-11-19
until: null
epic: joins
features: [join-overlap-open-end]
supersedes: []
superseded_by: null
depends_on: [61-rename-fields]
anchors: [05-shapes]
---

# 62 Open intervals in join_overlap

## Requirements

### Scope

`join_overlap` compared interval ends with `<`. jq orders null below every number, so an interval whose end is null (still open: a lease or session that has not ended) overlapped nothing and was dropped from the result without an error. `intervals_from_events` writes open intervals that way, and `join_within`, `merge_intervals` and `concurrency` already read a null end as open. The tests had no interval with a null end.

### Requirements

- **R1.** A null end, on either side, means still open: the interval overlaps everything of its key that starts after its start.
- **R2.** An interval with no start, or one that ends before it starts, is an error naming the table, the same check `merge_intervals` and `concurrency` make.
- **R3.** Intervals that only touch still do not overlap.

### Out of scope

A null start read as "open since the beginning"; the other three interval functions, which already behave this way.

## Design

`_iv_order_check` moves from the intervals section to the joins section, before `join_overlap`, because a jq function must be defined before it is used; `merge_intervals` and `concurrency` still call it. `join_overlap` checks both tables with it, then compares with `// $inf` in place of a null end, `$inf` being the largest number jq has, as `join_within` does.

Worked case, the test fixture: lease L1 of `aa` from 100 with no end; sessions S1 20 to 100, S2 20 to 101, S3 150 to 200, S4 from 900 with no end. S1 only touches the lease and is out; S2, S3 and S4 overlap it. Before the fix none did.

## Tasks

- [x] 1. `join_overlap` reads a null end as open and checks both tables; `_iv_order_check` moved up.
- [x] 2. Tests: fixture `tests/fixtures/open_intervals.json`, four cases (open end, open on both sides, no start, ends before it starts).
- [x] 3. Read-out note for `join_overlap` (new sections "An interval with no end" and "What is refused"; the `_iv_order_check` section moved to the joins page); README entry (also drops the old advice to rename the right side's start and end, out of date since 0.12.0); feature matrix; version 0.13.1.

## Log

- 2026-11-19. Found while answering the owner's question on why `join_overlap` was not run on real data: real open sessions would have been dropped. Fixed on his word ("fix it now").
- 182 of 182 cases on jq 1.7.1, jq 1.8.2, gojq 0.12.20, jaq 3.1.2 and the Python package 1.13.0.
- Not done: a run on real lease and session data.
