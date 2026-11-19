Sixteen definitions. Two helpers do the work: `_matches` pairs each left row with its right rows, and `_merge` joins one left row to one right row. `_merge` follows a plan made once per join by `_merge_plan`, which says what happens to a field name that both tables have; `_key_fields` finds the key's own field names for that plan. `join_on` chooses what to emit from those pairs. Everything else except `lookup` and `join_asof` is a one-line call of `join_on` or `_matches`.

```mermaid
flowchart LR
  M[_matches: index the right table by key, pair each left row with its matches] --> ON[join_on: emit by kind]
  KF[_key_fields: the names both keys read] --> MP[_merge_plan: which right fields get the suffix]
  MP --> MG
  MG[_merge: one left row + one right row, by the plan] --> ON
  ON --> EQ[join_inner, join_left, join_full, join_semi, join_anti]
  ON --> OV[join_overlap]
  M --> NEST[join_nest]
  MG --> ASOF[join_asof: own index, sorted by time]
  LK[lookup: own index, one row per key]
```

Most of this page uses two small tables. The left table is four requests, each naming the host it reached. The right table is five host records.

Requests, the left table:

| id | host |
|---|---|
| 1 | web01 |
| 2 | db01 |
| 3 | zz09 |
| 4 | null |

Hosts, the right table:

| host | site |
|---|---|
| web01 | N |
| db01 | S |
| db01 | N |
| app07 | S |
| null | S |

`db01` is in the right table twice, `zz09` is not in it, `app07` is used by no request, and each table has one row with no host.

In every join the left table is the input (it comes before the `|`) and the right table is the first argument. The arguments are separated by `;`, because in jq a comma means "emit both values". The runs name the right table once with `as $hosts`, which binds a name and passes nothing on, so the next `|` starts from the left table.

Two idioms recur in the code and are explained once here:

- **A key goes through `tojson` before it is used as an object key.** jq object keys are strings, so the number `1` and the string `"1"` would otherwise collide, and an array key (a composite key) could not be used at all. `tojson` gives `1`, `"1"` and `[1,"a"]` three different strings.
- **The right table is indexed once.** An object from key to rows is built before the left rows are walked, so the cost is left rows plus right rows, not their product.

## _key_fields/4
<!-- code: bc1d78e0 -->

The field names that both keys read directly, at the same place of the key. A join's key is a filter, not a field name, so the library has to find out which fields it reads: those fields are equal in every match and should appear once in the output, not twice.

### The example

The requests have the fields `id` and `host`, the hosts `host` and `site`, and both keys are `.host`.

```jq run
_key_fields(["host", "id"]; ["host", "site"]; .host; .host)
```

One name: `host` is the key on both sides.

### Reading the call

| Argument | In the example | What it is |
|---|---|---|
| `$lnames` | `["host", "id"]` | a value: every field name of the left table |
| `$rnames` | `["host", "site"]` | a value: every field name of the right table |
| `lkey`, `rkey` | `.host`, `.host` | filters: the join's two keys, exactly as the join received them |

### What happens inside, on the example

The keys are run on a made-up row in which every field holds a label with its own name. Whatever comes out carries the labels of the fields the key read.

Step 1, `probe`: the made-up left row. The label's field name starts with a character no real field has (shown as `\u0000`).

```jq run
["host", "id"] | map({key: ., value: {"\u0000field": .}}) | from_entries
```

Step 2, `[$lnames | probe | lkey]`: the key run on that row, inside an array. `.host` gives the label of `host`.

```jq run
[{"host": {"\u0000field": "host"}, "id": {"\u0000field": "id"}} | .host]
```

Step 3, `marks`: every label in that result, with the place where it sits. Here one label, at position 0.

```jq run
[{"\u0000field": "host"}] | [paths as $p | getpath($p) as $v | select(($v | type) == "object" and ($v | length) == 1 and ($v | has("\u0000field"))) | {p: $p, f: $v["\u0000field"]}]
```

Step 4: the same for the right side, and the names whose label sits at the same place on both sides.

### Other keys

An object key and an array key work the same way, because the labels pass through them. A key that computes something from the field fails on a label, which is not a string; the failure is caught and no field counts as the key. Two array keys that read the same fields in a different order share no place, so nothing counts either.

```jq run
_key_fields(["host", "site"]; ["host", "site"]; {site, host}; {site, host}),
_key_fields(["host", "site"]; ["host", "site"]; [.site, .host]; [.site, .host]),
_key_fields(["host"]; ["host"]; .host | ascii_downcase; .host | ascii_downcase),
_key_fields(["a", "b"]; ["a", "b"]; [.a, .b]; [.b, .a])
```

### The definition

<!-- definition -->

- `def probe` and `def marks` are two helpers defined inside the function: steps 1 and 3.
- `try (...) catch []`: a key that cannot run on labels gives no marks.
- The last line is step 4. `unique` sorts the names and drops repeats.

## _merge_plan/5
<!-- code: 4a766fc1 -->

The plan for merging the rows of two tables, made once per join: which fields are the key, and the new name of every other field name that both tables have.

### The example

Two requests that carry a `site` of their own, and the hosts, which have a `site` too. The key is `host`.

```jq run
_merge_plan([{id: 1, host: "db01", site: "N"}, {id: 2, host: "db02", site: "S"}];
            [{host: "db01", site: "S", owner: "ann"}];
            .host; .host; "_right")
```

`host` is the key and will appear once. `site` is on both sides and is not the key, so the right table's `site` will be written as `site_right`. `id` and `owner` are on one side only and are not in the plan.

### What happens inside, on the example

Step 1, `$ln` and `$rn`: the field names of each table, over all its rows.

```jq run
[{id: 1, host: "db01", site: "N"}, {id: 2, host: "db02", site: "S"}] | [.[] | keys[]] | unique
```

Step 2, `$k`: `_key_fields` on those names, `["host"]`.

Step 3, `$shared`: the names on both sides, without the key. `$ln - ($ln - $rn)` is the names of the left table that the right table also has.

```jq run
["host", "id", "site"] as $ln | ["host", "owner", "site"] as $rn | ($ln - ($ln - $rn)), ($ln - ($ln - $rn) - ["host"])
```

Step 4, `$new`: each shared name with the suffix, `["site_right"]`. If one of the new names is already a field of either table, the plan stops with an error.

The plan is made from the field names, not from the values. `site_right` is in every matched row, whether or not the two sites agree, so the output has the same fields on every run.

### What is refused

A new name that is taken, and a suffix that is not a string. A null suffix is allowed and asks for the strict rule, described under `_merge` below.

```jq run
(try _merge_plan([{a: 1, x: 1, x_right: 2}]; [{a: 1, x: 5}]; .a; .a; "_right") catch .),
(try _merge_plan([{a: 1}]; [{a: 1}]; .a; .a; "") catch .),
_merge_plan([{a: 1}]; [{a: 1}]; .a; .a; null)
```

### The definition

<!-- definition -->

- `if $suffix == null then {strict: true}`: the strict plan needs no names.
- The `$ln`, `$rn`, `$k`, `$shared` and `$new` lines are steps 1 to 4.
- `$taken`: the first new name that is already a field somewhere, or null.
- The last lines build the plan. `[$shared, $new] | transpose` pairs each name with its new name.

## _merge/3
<!-- code: 3402ce98 -->

One left row and one right row made into one output row, by the plan. A flat join calls it for every matching pair. It differs from jq's `$l + $r`, where the right row's value silently replaces the left row's.

### The example

Request 1 with a `site` of its own, and the `db01` host record. The plan is the one from above.

```jq run
_merge({id: 1, host: "db01", site: "N"}; {host: "db01", site: "S", owner: "ann"};
       {keys: {host: true}, names: {site: "site_right"}})
```

One row. `host` appears once, both sites are there, and `owner` is added under its own name.

### What happens inside, on the example

Step 1, `$r | to_entries`: the right row as a list of field and value pairs. (The row is written here with its fields in alphabetical order, because one engine, gojq, always lists them that way.)

```jq run
{host: "db01", owner: "ann", site: "S"} | to_entries
```

Step 2: `reduce` starts from the left row and handles one pair at a time. The run below uses `foreach`, which has the same form and also gives the row after each pair. Both are keywords of jq, written `reduce SOURCE as $e (START; UPDATE)`: START is the row to begin with, and UPDATE is run once per pair on the row so far.

```jq run
{keys: {host: true}, names: {site: "site_right"}} as $plan
| foreach ({host: "db01", owner: "ann", site: "S"} | to_entries[]) as $e ({id: 1, host: "db01", site: "N"};
    if $plan.keys[$e.key] then (if has($e.key) then . else .[$e.key] = $e.value end)
    else .[$plan.names[$e.key] // $e.key] = $e.value end)
```

Three values, one per pair. After `host` the row is unchanged: it is a key field and the row has it. After `owner` the row has `owner`. After `site` it has `site_right`.

### The strict plan

With the plan `{strict: true}` a field on both sides is kept once when the two values are equal, and stops the join when they differ. The message names the field and both values.

```jq run
_merge({id: 2, host: "db01"}; {host: "db01", site: "S"}; {strict: true}),
(try _merge({id: 2, host: "db01", site: "N"}; {host: "db01", site: "S"}; {strict: true}) catch .)
```

### The definition

<!-- definition -->

- `if $plan.strict then ...`: the strict rule, one `reduce` over the right row's pairs.
- `else reduce ...`: the usual rule, step 2.
- `if $plan.keys[$e.key] then (if has($e.key) then . else .[$e.key] = $e.value end)`: a key field is set only when the row does not have it. That happens for a right row of a full join that matched nothing, which starts from an empty row.
- `.[$plan.names[$e.key] // $e.key] = $e.value`: a name in the plan is written under its new name, any other under its own.

## _matches/4
<!-- code: dd80c824 -->

The pairing step that every join here shares, except `lookup` and `join_asof`. For each left row it finds the right rows with the same key. It merges nothing and drops nothing; `join_on` and `join_nest` decide what to do with the pairs.

### The example

The two tables from the top of the page, matched on `host`.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| _matches($hosts; .host; .host; true)
```

One entry per left row, in left order. `l` is the left row. `m` is the list of its matches, each as `{key, value}`, where `value` is the right row and `key` is that row's position in the right table (0 for the first row). Request 1 has one match, request 2 has two, and request 3 has none. Request 4 has a null host and matches nothing, not even the right row whose host is also null.

### Reading the call

`_matches($hosts; .host; .host; true)` has four arguments.

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$right` | `$hosts` | nothing: it is a value | the right table |
| `lkey` | `.host` | one left row | that row's key |
| `rkey` | `.host` | one right row | that row's key |
| `cond` | `true` | one pair `{l: left row, r: right row}` | an extra test on a pair that already shares a key |

In the definition `$right` has a `$` and the other three do not. A `$name` parameter is a value, computed once before the call. A bare parameter is a filter: a piece of program that the function runs later, on an input it chooses.

### What happens inside, on the example

Step 1, `$right | to_entries`: every right row with its position as `key`.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}]
| to_entries
```

Step 2, `group_by(.value | .host)`: the pairs grouped by the right key. `group_by` sorts the groups by key, so the null group comes first, and inside a group it keeps input order: in the `db01` group position 1 is before position 2.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}]
| to_entries | group_by(.value | .host)
```

Step 3, `map(select(...) | {key: ..., value: .}) | from_entries`: the null group is dropped, and the rest become one object, the index `$ix`. Its keys are the host names through `tojson`, which is why they carry their own quotes.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}]
| to_entries | group_by(.value | .host)
| map(select((.[0].value | .host) != null) | {key: (.[0].value | .host | tojson), value: .}) | from_entries
```

Step 4: the left rows are walked in order. For each, `($l | lkey) as $k` is its key, and `$ix[$k | tojson][]?` looks the key up. For request 2:

```jq run
{"\"db01\"": [{key: 1, value: {host: "db01", site: "S"}}, {key: 2, value: {host: "db01", site: "N"}}]} as $ix
| {id: 2, host: "db01"} | .host as $k | [$ix[$k | tojson][]?]
```

A key that is not in the index, such as `zz09`, gives no values: the `?` after `[]` turns "cannot iterate over null" into nothing. A null key is not looked up at all.

Step 5, `select(.value as $r | {l: $l, r: $r} | cond)`: each match found is kept only when `cond` is true for the pair. With `true` every match is kept. The entries `{l, m}` are collected into the array shown at the top.

### The definition

<!-- definition -->

- The first two lines build `$ix`: steps 1 to 3. Dropping the null group is half of the rule "a null key never matches".
- `[.[] as $l | ($l | lkey) as $k | {l: $l, m: [...]}]`: step 4, one entry per left row.
- `if $k == null then empty`: the other half of the null rule.
- `$ix[$k | tojson][]?`: the lookup. The matches come out in right-table order, because step 2 kept that order inside each group, on every engine.
- `select(...)`: step 5. `cond` runs only on pairs that already share a key.

## join_on/6, join_on/5
<!-- code: f0ed3dc1 -->

The general flat join: one output row per matching pair, with the fields of both rows. It is SQL's `FROM l JOIN r ON l.k = r.k AND cond`, with the kind of join as an argument.

### The example

A left join of the requests to the hosts.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| join_on($hosts; .host; .host; true; "left")
```

Five rows from four requests. Request 1 has its site. Request 2 appears twice, once per `db01` record: a duplicate key on the right multiplies rows. Requests 3 and 4 have no match and come back as they were, with no `site` field.

### Reading the call

The first four arguments are those of `_matches` above. The fifth, `$kind`, is a value, one of five strings. The sixth, `$suffix`, may be left out and is then `"_right"`; it is explained under "A field name on both sides" below.

| kind | emits |
|---|---|
| `"inner"` | for each left row, one merged row per match |
| `"left"` | the same, and the left row alone when it has no match |
| `"semi"` | the left row once when it has any match; no right fields |
| `"anti"` | the left row when it has no match |
| `"full"` | the `left` output, then the right rows no left row matched, in right order |

### The other four kinds

The same call with `"inner"`, `"semi"` and `"anti"`. Each kind's result is one array, printed on its own line.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| join_on($hosts; .host; .host; true; "inner"),
  join_on($hosts; .host; .host; true; "semi"),
  join_on($hosts; .host; .host; true; "anti")
```

`inner` is the left join without requests 3 and 4. `semi` has request 2 once, although it has two matches, and no `site`. `anti` is the two requests that `inner` left out.

`"full"`:

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| join_on($hosts; .host; .host; true; "full")
```

The first five rows are the left join. The last two are the right rows that no request matched: `app07`, and the record with a null host. They have no `id`.

### What happens inside, on the example

Step 1, `_merge_plan(...) as $plan`: the plan, made once, for the three kinds that merge rows. Here it is `{keys: {host: true}, names: {}}`: `host` is the key and no other name is on both sides. Then `_matches($right; lkey; rkey; cond) as $rows`: the array of `{l, m}` entries shown under `_matches` above.

Step 2: one expression per kind turns `$rows` into output rows. For `"left"`, on the entries of requests 2 and 3:

```jq run
[{l: {id: 2, host: "db01"}, m: [{key: 1, value: {host: "db01", site: "S"}}, {key: 2, value: {host: "db01", site: "N"}}]},
 {l: {id: 3, host: "zz09"}, m: []}] as $rows
| {keys: {host: true}, names: {}} as $plan
| [$rows[] | .l as $l | if (.m | length) > 0 then .m[] | _merge($l; .value; $plan) else $l end]
```

An entry with matches gives one merged row per match. An entry with none gives its left row.

Step 3, for `"full"` only. `$hit` is an object whose keys are the positions of the right rows that matched something:

```jq run
[{l: {id: 1, host: "web01"}, m: [{key: 0, value: {host: "web01", site: "N"}}]},
 {l: {id: 2, host: "db01"}, m: [{key: 1, value: {host: "db01", site: "S"}}, {key: 2, value: {host: "db01", site: "N"}}]},
 {l: {id: 3, host: "zz09"}, m: []}, {l: {id: 4, host: null}, m: []}] as $rows
| [$rows[].m[] | {key: (.key | tostring), value: true}] | from_entries
```

Positions 0, 1 and 2 matched. The right rows at the other positions, 3 and 4, are appended after the left part:

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $right
| {"0": true, "1": true, "2": true} as $hit
| [$right | to_entries[] | select($hit[.key | tostring] | not) | .value]
```

### A condition, and a join with no key

`cond` is a filter over the pair `{l: left row, r: right row}`. With `true` for both keys every right row shares the one key `true`, so every pair is checked. A left join of three amounts to the bands that contain them:

```jq run
[{id: 1, amount: 5}, {id: 2, amount: 60}, {id: 3, amount: 500}]
| join_on([{lo: 0, hi: 10, band: "small"}, {lo: 10, hi: 100, band: "medium"}];
          true; true; .l.amount >= .r.lo and .l.amount < .r.hi; "left")
```

Amount 500 is in no band and comes back alone. This form checks left rows times right rows pairs, so it is for small right tables.

### A field name on both sides

Here the requests carry a `site` of their own, the site the request came from. The hosts have a `site` too. Both are kept: the left one under its name, the right one as `site_right`.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}] as $hosts
| [{id: 1, host: "web01", site: "N"}, {id: 2, host: "db01", site: "N"}, {id: 3, host: "zz09", site: "S"}]
| join_on($hosts; .host; .host; true; "left")
```

Request 3 has no match and so no `site_right`. The two values sit side by side, which makes the check a plain filter. The requests that reached a host at another site:

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}] as $hosts
| [{id: 1, host: "web01", site: "N"}, {id: 2, host: "db01", site: "N"}, {id: 3, host: "zz09", site: "S"}]
| join_on($hosts; .host; .host; true; "inner") | map(select(.site != .site_right))
```

The sixth argument changes the suffix. With `null` it asks for the strict rule: a shared field is kept once when the values agree, and the join stops when they differ.

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}] as $hosts
| [{id: 1, host: "web01", site: "N"}, {id: 2, host: "db01", site: "N"}]
| join_on($hosts; .host; .host; true; "inner"; ".host"),
  (try join_on($hosts; .host; .host; true; "inner"; null) catch .)
```

In a full join the right rows that matched nothing carry their shared fields under the suffixed names too, so a field means the same thing in every row:

```jq run
[{host: "web01", site: "N"}, {host: "app07", site: "S"}] as $hosts
| [{id: 1, host: "web01", site: "N"}]
| join_on($hosts; .host; .host; true; "full")
```

When the key is computed, as in `.host | ascii_downcase`, the library cannot tell that `host` is the key, and `host` comes out twice like any other shared field (`_key_fields` above).

### What is refused

A kind that is not one of the five is an error, not an empty result. So is a suffixed name that one of the tables already has.

```jq run
(try ([{id: 1, host: "web01"}] | join_on([{host: "web01"}]; .host; .host; true; "outer")) catch .),
(try ([{id: 1, host: "web01", site: "S", site_right: "x"}] | join_on([{host: "web01", site: "N"}]; .host; .host; true; "inner")) catch .)
```

### The definition

<!-- definition -->

- `. as $left` keeps the left table for the plan. The plan is made only for `"inner"`, `"left"` and `"full"`; the other two kinds merge nothing.
- `_matches(...) as $rows`: step 1.
- `"inner"`: `.m[] | _merge($l; .value; $plan)` gives one row per match and nothing for an entry with no matches.
- `"left"`: step 2.
- `"semi"` and `"anti"`: `select` on whether `m` is empty; the left row `.l` is emitted as it is, once.
- `"full"`: `$hit` is step 3. The position goes through `tostring` because object keys are strings. The left part is the same expression as `"left"`, and the unmatched right rows follow it, each merged into an empty row so that its shared fields take the suffixed names.
- The last `else`: the unknown-kind error.
- The five-argument form calls the six-argument form with `"_right"`.

## join_inner/3, join_left/3, join_full/3, join_semi/3, join_anti/3
<!-- code: 0a54328b -->

The five kinds of equality join under their own names. Each is `join_on` with `true` for the condition and its kind fixed, so the common case reads as one word and has three arguments.

### The example

Which requests reached a known host, and which did not:

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| join_semi($hosts; .host; .host), join_anti($hosts; .host; .host)
```

Two arrays. They are the `"semi"` and `"anti"` results shown under `join_on`.

A key can be made of several fields by writing an array. Here a request matches a host record only when both host and site agree:

```jq run
[{id: 1, host: "db01", site: "N"}, {id: 2, host: "db01", site: "W"}]
| join_inner([{host: "db01", site: "S", rack: 4}, {host: "db01", site: "N", rack: 7}]; [.host, .site]; [.host, .site])
```

Request 1 matches the second record. Request 2 matches neither.

### The definition

<!-- definition -->

Each line passes its three arguments through to `join_on` and adds `true` and the kind.

## join_nest/5
<!-- code: b669d9a4 -->

Every left row exactly once, with one new field holding the array of its matching right rows. It never multiplies rows and never clashes on a field name. It is Power Query's `Table.NestedJoin`. Use it when the right side is "many" and the next step counts or summarises the matches per left row.

### The example

```jq run
[{host: "web01", site: "N"}, {host: "db01", site: "S"}, {host: "db01", site: "N"}, {host: "app07", site: "S"}, {host: null, site: "S"}] as $hosts
| [{id: 1, host: "web01"}, {id: 2, host: "db01"}, {id: 3, host: "zz09"}, {id: 4, host: null}]
| join_nest($hosts; .host; .host; true; "records")
```

Four requests in, four rows out. Request 2 holds both `db01` records in its `records` field. Requests 3 and 4 hold an empty array.

### Reading the call

The first four arguments are those of `_matches`. The fifth, `$as`, is a value: the name of the new field.

### What happens inside, on the example

Step 1: `_matches`, as shown in its own section. Step 2, on the entry of request 2: `[.m[].value]` takes the right rows out of the matches, and `.l + {...}` adds them to the left row under the name in `$as`.

```jq run
{l: {id: 2, host: "db01"}, m: [{key: 1, value: {host: "db01", site: "S"}}, {key: 2, value: {host: "db01", site: "N"}}]}
| [.m[].value], (.l + {("records"): [.m[].value]})
```

### The definition

<!-- definition -->

- `[_matches(...)[] | ...]`: one output row per entry, so one per left row.
- `.l + {($as): [.m[].value]}`: step 2. The parentheses in `{($as): ...}` make the field name come from the variable. A left row that already has a field of that name gets it replaced.

## lookup/4
<!-- code: cdb7e6e2 -->

Attaches the one matching row of a second table under a new field. It is a spreadsheet's `VLOOKUP` or `XLOOKUP`, or SQL's left join to a table with a unique key. The second table is called the dimension: one row per key, such as one row per site.

### The example

Three requests with a site code, and a dimension of two sites.

```jq run
[{id: 1, site: "N"}, {id: 2, site: "W"}, {id: 3, site: null}]
| lookup([{site: "N", name: "North", staff: 12}, {site: "S", name: "South", staff: 7}]; .site; .site; "info")
```

Every request comes back once with an `info` field. Request 1 has the row of site N. Site W is not in the dimension and request 3 has no site, so both get null.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$dim` | the two site rows | nothing: it is a value | the dimension table |
| `lkey` | `.site` | one left row | that row's key |
| `dkey` | `.site` | one dimension row | that row's key |
| `$as` | `"info"` | nothing: it is a value | the name of the new field |

### What happens inside, on the example

Step 1, `$dim | group_by(dkey)`: the dimension grouped by key. With a unique key every group has one row.

```jq run
[{site: "N", name: "North", staff: 12}, {site: "S", name: "South", staff: 7}] | group_by(.site)
```

Step 2: each group becomes an entry from the key, through `tojson`, to the group's one row, and `from_entries` builds the index `$ix`.

```jq run
[{site: "N", name: "North", staff: 12}, {site: "S", name: "South", staff: 7}] | group_by(.site)
| map({key: (.[0] | .site | tojson), value: .[0]}) | from_entries
```

Step 3: each left row gets the field. For request 1, the key through `tojson`, then the index entry under it:

```jq run
{"\"N\"": {site: "N", name: "North", staff: 12}} as $ix
| {id: 1, site: "N"} | .site as $k | ($k | tojson), ({id: 1, site: "N"} + {("info"): $ix[$k | tojson]})
```

### What is refused

A key that appears twice in the dimension is an error naming the key, so a lookup can never multiply rows. The check runs while the index is built, so it fires even when no left row uses that key.

```jq run
try ([{id: 1, site: "N"}] | lookup([{site: "N", name: "North"}, {site: "S", name: "South"}, {site: "S", name: "Sud"}]; .site; .site; "info")) catch .
```

### The definition

<!-- definition -->

- `$dim | group_by(dkey)`: step 1.
- `select((.[0] | dkey) != null)`: dimension rows with a null key are left out of the index.
- `if length > 1 then error(...)`: the duplicate-key error.
- `else {key: ..., value: .[0]} end ... | from_entries`: step 2.
- `map(. as $l | ($l | lkey) as $k | $l + {($as): ...})`: step 3. A null key gives null without a lookup, and a key that is not in `$ix` gives null because that is what a missing object key reads as.

## join_overlap/7
<!-- code: ca87eb71 -->

Pairs with the same key whose time intervals overlap. It is SQL's `JOIN ... ON l.k = r.k AND l.start < r.end AND r.start < l.end`. Each interval is closed at its start and open at its end, written `[start, end)`.

### The example

Two jobs on host `web01`, and one maintenance window on the same host from 10 to 11.

| job | host | s | e |
|---|---|---|---|
| backup | web01 | 9 | 11 |
| report | web01 | 11 | 12 |

```jq run
[{job: "backup", host: "web01", s: 9, e: 11}, {job: "report", host: "web01", s: 11, e: 12}]
| join_overlap([{host: "web01", window: "patching", ws: 10, we: 11}]; .host; .host; .s; .e; .ws; .we)
```

One row: the backup job ran during the window. The report job starts at 11, the moment the window ends, and two intervals that only touch do not overlap.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$right` | the one window | nothing: it is a value | the right table |
| `lkey`, `rkey` | `.host`, `.host` | one left row, one right row | the keys that must be equal |
| `lstart`, `lend` | `.s`, `.e` | one left row | the left interval |
| `rstart`, `rend` | `.ws`, `.we` | one right row | the right interval |

The output is merged rows. If both tables called their fields `s` and `e`, the right table's would come out as `s_right` and `e_right`.

### What happens inside, on the example

It is one call of `join_on` with kind `"inner"` and the overlap test as the condition. The test on each of the two pairs, as `{l, r}`:

```jq run
{host: "web01", window: "patching", ws: 10, we: 11} as $w
| ({l: {job: "backup", s: 9, e: 11}, r: $w}, {l: {job: "report", s: 11, e: 12}, r: $w})
| {job: .l.job, l_starts_before_r_ends: ((.l | .s) < (.r | .we)), r_starts_before_l_ends: ((.r | .ws) < (.l | .e))}
```

Two values, one per pair. Both halves are true for the backup job. For the report job the first half is false: it starts at 11, which is not before the window's end at 11.

### The definition

<!-- definition -->

- `(.l | lstart) < (.r | rend) and (.r | rstart) < (.l | lend)`: each interval starts before the other ends. The `<` and not `<=` is what makes the end open.
- The condition is checked only for pairs with the same key, so the cost follows the number of same-key pairs.

## join_asof/6, join_asof/5
<!-- code: f7caf903 -->

For each left row, the right row with the same key and the latest time at or before the left row's time. It is DuckDB's `ASOF LEFT JOIN` and pandas' `merge_asof`. It answers "which value was in force when this happened", for a table of changes such as prices or settings.

### The example

The rate limit of host `web01` was set four times; two of the changes carry the same time, 10.

| host | at | limit |
|---|---|---|
| web01 | 2 | 100 |
| web01 | 10 | 101 |
| web01 | 10 | 102 |
| web01 | 14 | 103 |

Five requests, each with its time `t`:

```jq run
[{host: "web01", at: 2, limit: 100}, {host: "web01", at: 10, limit: 101}, {host: "web01", at: 10, limit: 102}, {host: "web01", at: 14, limit: 103}] as $limits
| [{id: 1, host: "web01", t: 1}, {id: 2, host: "web01", t: 10}, {id: 3, host: "web01", t: 12}, {id: 4, host: "web01", t: 30}, {id: 5, host: "db01", t: 30}]
| join_asof($limits; .host; .host; .t; .at)
```

Request 1 is before every change and comes back alone. Requests 2 and 3 get limit 101: the latest change at or before 10 and 12 is at time 10, and of the two changes at that time the first in input order is taken. Request 4 gets the last change. Request 5's host has no changes.

The six-argument form adds a maximum age. With 3, a match older than 3 time units is rejected:

```jq run
[{host: "web01", at: 2, limit: 100}, {host: "web01", at: 10, limit: 101}, {host: "web01", at: 10, limit: 102}, {host: "web01", at: 14, limit: 103}] as $limits
| [{id: 1, host: "web01", t: 1}, {id: 2, host: "web01", t: 10}, {id: 3, host: "web01", t: 12}, {id: 4, host: "web01", t: 30}, {id: 5, host: "db01", t: 30}]
| join_asof($limits; .host; .host; .t; .at; 3)
```

Request 4 now comes back alone: its match is 30 - 14 = 16 old. Requests 2 and 3 keep theirs, 0 and 2 old.

### Reading the call

| Argument | In the example | Runs on | Meaning |
|---|---|---|---|
| `$right` | `$limits` | nothing: it is a value | the table of changes |
| `lkey`, `rkey` | `.host`, `.host` | one left row, one right row | the keys that must be equal |
| `ltime` | `.t` | one left row | the moment to look up |
| `rtime` | `.at` | one right row | the moment the change took effect |
| `$max_age` | 3, or absent | nothing: it is a value | the greatest allowed `ltime - rtime`; null for no limit |

### What happens inside, on the example

Step 1, the index `$ix`: the right rows grouped by key, each group sorted by time and stored as `{rows, t}`, where `t` is the list of times alone.

```jq run
[{host: "web01", at: 2, limit: 100}, {host: "web01", at: 10, limit: 101}, {host: "web01", at: 10, limit: 102}, {host: "web01", at: 14, limit: 103}]
| group_by(.host) | map({key: (.[0] | .host | tojson), value: (sort_by(.at) | {rows: ., t: map(.at)})}) | from_entries
```

Step 2, for request 3 (`$t` is 12), `($g.t | bsearch($t)) as $i`: a binary search in the times. 12 is not among them, so `bsearch` returns `-1 - p`, where `p` is the position at which 12 would be inserted:

```jq run
[2, 10, 10, 14] | bsearch(12)
```

Step 3, `(if $i >= 0 then $i else -2 - $i end) as $last`: the insertion position is `-1 - (-4) = 3`, and the entry before it, `-2 - (-4) = 2`, is the last time at or below 12. For request 1 (`$t` is 1) the same arithmetic gives -1, which means no entry:

```jq run
[2, 10, 10, 14] | (bsearch(12) | -2 - .), (bsearch(1) | -2 - .)
```

Step 4, `until(. == 0 or $g.t[. - 1] != $g.t[$last]; . - 1)`: from position 2, step back while the entry before has the same time. Position 1 also holds time 10 and position 0 does not, so the walk stops at 1. This step is also why request 2 gets the same answer on every engine: for a time that is in the list twice, `bsearch` returns position 1 on some engines and 2 on others, and the walk ends at 1 from either.

```jq run
[2, 10, 10, 14] as $t | (1, 2) | . as $last | until(. == 0 or $t[. - 1] != $t[$last]; . - 1)
```

Step 5: `$j` is 1, so the right row is `rows[1]`, the change to limit 101, and `_merge` joins it to the request.

```jq run
_merge({id: 3, host: "web01", t: 12}; {host: "web01", at: 10, limit: 101}; {keys: {host: true}, names: {}})
```

If the changes called their time `t` as well, it would be in the output as `t_right`, beside the request's `t`.

### Edge cases

A left row with a null key or a null time comes back alone. Right rows with a null key or a null time are dropped before the index is built.

```jq run
[{id: 1, host: "web01", t: null}, {id: 2, host: null, t: 5}, {id: 3, host: "web01", t: 5}]
| join_asof([{host: "web01", at: null, limit: 1}, {host: null, at: 1, limit: 2}, {host: "web01", at: 3, limit: 3}]; .host; .host; .t; .at)
```

### What it is not for

"Latest value at or before T" is the right question for prices and settings. It is the wrong one for "who held this at T", where the value may have ended before T. For that, use `intervals_from_events` and `join_within` on the intervals page.

### The definition

<!-- definition -->

- The first two lines build `$ix`: step 1. Keeping `t` beside `rows` lets `bsearch` run on plain numbers. `sort_by` is stable, so rows with the same time stay in input order.
- `if $k == null or $t == null or $ix[$k | tojson] == null then $l`: no key, no time, or no changes for this key.
- `($g.t | bsearch($t)) as $i` and the `$last` line: steps 2 and 3.
- The `$j` line: step 4, or -1 when `$last` is -1.
- `if $j < 0 or ($max_age != null and $t - $g.t[$j] > $max_age) then $l else _merge(...)`: no entry, or one that is too old, gives the left row alone. Otherwise step 5. The plan is made on the first line, with the suffix `"_right"`.
- The five-argument form calls the six-argument form with `null` for `$max_age`.
