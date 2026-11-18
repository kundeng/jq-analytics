Eight definitions: four public (`funnel_steps`, `funnel`, `cohorts`, `retention`) and four helpers.

```mermaid
flowchart LR
  E[events: entity, time, step] --> FS[funnel_steps: one row per entity, how deep it got]
  FS --> F[funnel: one row per step]
  E2[events: entity, period] --> C[cohorts: each entity's first period]
  E2 --> R[retention: one row per cohort and later period]
  P[period list, in order] --> C & R
```

## _entity_key/0
<!-- code: 024526e6 -->

An object stays as it is; anything else becomes `{key: value}`. The same rule `group_agg` applies, as a named helper.

```jq run
[{user: "u1"}, "u1"] | map(_entity_key)
```

## _funnel_check/3
<!-- code: 5445bb0e -->

Passes its input through, or stops with an error, before any work:

- an empty step list;
- a step listed twice: `unique | length` differs from `length`, and `group_by(.) | map(select(length > 1)[0])[0]` finds one repeated name for the message;
- an event of a listed step with a null time. `first(… | [step]) // null` wraps the step in an array so that a step whose name is `false` or null would still count as found.

```jq run
[{t: 1, s: "view"}] | (try _funnel_check(.t; .s; ["view", "pay", "view"]) catch .), (try _funnel_check(.t; .s; []) catch .)
```

## funnel_steps/5
<!-- code: a166429e -->

One row per entity that reaches step 1, with how deep it got.

- **Per entity.** Events of unlisted steps are dropped, then `_groups(entity)`. `$t` is, for each step in order, the sorted list of that entity's times for the step: `$t[0]` the first step's times, `$t[1]` the second's.
- **Outer `reduce` over `$t[0]`**, the first-step events, earliest first. Its state is the best chain so far. `if . != null and length == $n then .` stops trying once a complete chain is found.
- **Inner `reduce` over the later steps.** `$lim` is the first event's time plus `$within`. For step `$i`, `first($t[$i][] | select(. >= $prev and …) | [.])` takes the earliest time of that step at or after the previous step's time and within the limit. Found: appended to the chain. Not found: `.ok = false` and the chain ends there.
- **`if . == null or ($chain | length) > length then $chain else . end`**: keep the longer chain; on a tie, the earlier one.
- `>=`, not `>`: two steps logged at the same moment count as in order.

Taking the earliest matching event at every step is safe: for a fixed first event, an earlier next step leaves at least as many choices for the steps after it as a later one would.

Five made-up users, steps view, cart, pay, all within an hour (3,600 s):

| user | events | depth | why |
|---|---|---|---|
| u1 | view 0, cart 100, pay 200 | 3 | in order, within the hour |
| u2 | view 0, pay 50, cart 60 | 2 | pay came before cart; no pay after the cart |
| u3 | view 0, cart 5000 | 1 | the cart is outside the hour |
| u4 | view 0, view 4000, cart 4100, pay 4200 | 3 | the first view times out; the second completes |
| u5 | cart 10, pay 20 | | never viewed: not in the output |

```jq run
[["u1", 0, "view"], ["u1", 100, "cart"], ["u1", 200, "pay"], ["u2", 0, "view"], ["u2", 50, "pay"], ["u2", 60, "cart"],
 ["u3", 0, "view"], ["u3", 5000, "cart"], ["u4", 0, "view"], ["u4", 4000, "view"], ["u4", 4100, "cart"], ["u4", 4200, "pay"],
 ["u5", 10, "cart"], ["u5", 20, "pay"]]
| map({user: .[0], t: .[1], step: .[2]})
| funnel_steps({user}; .t; .step; ["view", "cart", "pay"]; 3600)
```

## funnel/5
<!-- code: 3e514044 -->

Counts from `funnel_steps`. `$d` is every entity's depth; `$c[$i]` is how many have depth above `$i`, that is, reached step `$i + 1`. The two ratios divide by the previous step's count and the first step's, with null where the divisor is zero.

```jq run
[["u1", 0, "view"], ["u1", 100, "cart"], ["u1", 200, "pay"], ["u2", 0, "view"], ["u2", 50, "pay"], ["u2", 60, "cart"],
 ["u3", 0, "view"], ["u3", 5000, "cart"], ["u4", 0, "view"], ["u4", 4000, "view"], ["u4", 4100, "cart"], ["u4", 4200, "pay"],
 ["u5", 10, "cart"], ["u5", 20, "pay"]]
| map({user: .[0], t: .[1], step: .[2]})
| funnel({user}; .t; .step; ["view", "cart", "pay"]; 3600)
| map(.from_previous |= (if . == null then null else round_to(4) end))
```

Four viewed, three of them reached the cart, two paid.

## _period_pos/0, _period_idx/3
<!-- code: 62c33165 -->

`_period_pos` turns the ordered period list into a lookup from period (through `tojson`) to position. `_period_idx` looks one event's period up in it and raises an error, under the caller's name, when the period is not in the list. Positions are what make "earlier" and "later" mean the order of the list, not the order of the values.

```jq run
["2026-01", "2026-02", "2026-03"] | _period_pos as $pos
| [{p: "2026-03"}, {p: "2025-12"}] | map(try _period_idx(.p; $pos; "cohorts") catch .)
```

## cohorts/3
<!-- code: 9d8b18de -->

One row per entity: its key and `cohort`, the earliest period in which it has an event. `map(_period_idx(…)) | min` is the smallest position among the entity's events, and `$periods[…]` turns it back into the period.

```jq run
[["a", "2026-02"], ["a", "2026-01"], ["b", "2026-01"], ["b", "2026-03"], ["c", "2026-02"]]
| map({user: .[0], month: .[1]})
| cohorts({user}; .month; ["2026-01", "2026-02", "2026-03"])
```

## retention/3
<!-- code: 2419087b -->

- `$e`: per entity, `{c: its cohort position, a: the distinct positions in which it is active}`.
- `$byc`: the entities grouped by cohort position, built once.
- For each period position `$c` that is some entity's cohort: `$m` is that cohort's entities, one lookup in `$byc`, and `$cnt` counts, per position, how many of them are active there (`[.[].a[]] | group_by(.)`).
- `range($c; $np) as $p` then emits one row for every period from the cohort's own to the last, with `$cnt[$p] // 0`, so a period in which nobody came back still has its row.

Hand check: a is active in January, February and March, b in January and March, c in February only. The January cohort is a and b: 2 of 2 in January, 1 of 2 in February, 2 of 2 in March. The February cohort is c: 1 of 1, then 0 of 1.

```jq run
[["a", "2026-01"], ["a", "2026-02"], ["a", "2026-03"], ["b", "2026-01"], ["b", "2026-03"], ["c", "2026-02"]]
| map({user: .[0], month: .[1]})
| retention({user}; .month; ["2026-01", "2026-02", "2026-03"])
```

**Review finding 10, fixed in 0.9.0.** Until 0.8.1 every entity was scanned once for every period. The entities are now grouped by cohort once. In the Python `jq` package, 40,000 entities over 365 periods took 18.6 s before and 1.31 s after.
