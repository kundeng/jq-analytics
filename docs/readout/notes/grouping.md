Two definitions. `_groups` is used all over the library (intervals, funnels, shapes); `group_agg` is the public face.

## _groups/1
<!-- code: db705fcd -->

Rows into groups: an array of groups, each an array of rows. Groups come in the order their keys first appear; rows inside a group keep input order.

### The example

Four rows; `b` appears twice, and one row has a null key.

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | _groups(.g)
```

The result is one value: an array holding three groups. The `b` group is first because `b` appeared first.

### What happens inside, on the example

At every step the result is one value, an array, and that whole array is what the next step receives.

Step 1, `to_entries`: each row with its position as `key`.

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | to_entries
```

Step 2, `group_by(.value | .g)`: three groups, sorted by the group key, so null comes first, then "a", then "b". Inside "b" the rows keep their input order (positions 0 and 3). `group_by` gives one array holding the groups; it does not give three separate values.

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | to_entries | group_by(.value | .g)
```

Step 3, `sort_by(.[0].key)`: the groups ordered by the position of their first row: 0 ("b"), 1 ("a"), 2 (null). That is the order in which the keys first appeared.

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | to_entries | group_by(.value | .g) | sort_by(.[0].key)
```

Step 4, `map(map(.value))`: the positions dropped, the rows left. This is the result at the top.

### Why not the builtin alone

`group_by(.g)` on the same rows gives the same three groups, with the same rows in each, in a different order:

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}] | group_by(.g)
```

The builtin works by sorting on the key, so its groups come out in jq's sort order: null first, then "a", then "b". The input had "b" first. `_groups` exists to put the groups back in the order their keys first appeared, which is the two extra steps around the builtin.

The library wants first-appearance order for three reasons. A report then lists its groups in the order the data does, so input sorted by date gives output sorted by date without sorting again. A key that is an object, as in `group_agg({site, month}; ...)`, has no sort order a reader would expect. And every function built on `_groups` (intervals, funnels, `split_by`) inherits one stated rule, rule 3 in the README, instead of the builtin's.

### The argument is a filter, run on each row

`_groups(.g)` does not receive a value; it receives the piece of program `.g` and runs it on every row to get that row's key. This is the first function in the library's reading order that takes such an argument, and every grouping, join and window function does the same. What can be written there, on the four rows of the example:

| Written as | Groups | Why |
|---|---|---|
| `.g` | b (2 rows), a, null | the field's value is the key |
| `{g}` | the same three | short for `{g: .g}`: an object as key; rows with the same g still fall together |
| `.x > 2` | false (2 rows), true (2 rows) | any expression on the row will do |
| `g` | error: `g/0 is not defined` | a bare word is a call to a function of that name; a field is always `.g` |
| `"g"` | one group of all four rows | a string is a constant, the same for every row |

```jq run
[{g: "b", x: 1}, {g: "a", x: 2}, {g: null, x: 3}, {g: "b", x: 4}]
| (_groups(.g) == _groups({g})), (_groups(.x > 2) | map(length)), (_groups("g") | map(length))
```

For `_groups` the first two forms give the same result. They differ only in `group_agg` below, which copies the key into its output row and needs a column name for it.

### The definition

<!-- definition -->

The comment says why this is not written as a `reduce` that appends each row to its group: appending inside a `reduce` copies the growing array each time, so the cost grows with the square of the group's size, and an object keyed by group would come out in a different key order on gojq.

## group_agg/2
<!-- code: 2c78cb5d -->

Group a table by a key and compute something per group: one output row per group, holding the key and the results. It is SQL's `SELECT site, count(*), avg(x) ... GROUP BY site`.

### The example

Five rows. Site N has three, one of them with no x; one row has no site.

| site | x |
|---|---|
| N | 1 |
| S | 5 |
| null | 7 |
| N | null |
| N | 3 |

The call: per site, how many rows, how many with an x, and the mean x.

```jq run
[{site: "N", x: 1}, {site: "S", x: 5}, {site: null, x: 7}, {site: "N", x: null}, {site: "N", x: 3}]
| group_agg({site}; map(.x) | {rows: length, n: count_nonnull, mean: mean})
```

One row per site, in the order the sites first appear. Check N by hand: three rows, two of them with an x (1 and 3), mean 2.

### Reading the call

`group_agg({site}; map(.x) | {rows: length, n: count_nonnull, mean: mean})` has two arguments, separated by the `;`.

- **`;` separates arguments.** jq uses a semicolon where most languages use a comma, because in jq a comma already means "emit both values".
- **`{site}` is short for `{site: .site}`**: an object with one field, taken from the current row. On the first row it gives `{"site":"N"}`. It is ordinary jq, not something the library adds.
- **Both arguments are filters, not values.** Each is a piece of program that `group_agg` runs later, on an input it chooses:

| Argument | In the example | Runs on | Returns |
|---|---|---|---|
| first: the key | `{site}` | one row | that row's group key |
| second: the aggregate | `map(.x)`, then `{rows: length, n: count_nonnull, mean: mean}` | one group: an array of rows | an object of result columns |

So inside the second argument the one input value is a group, not the table and not a row. `map(.x)` takes the group's x values, and `length`, `count_nonnull` and `mean` each run on that list.

### What happens inside, on the example

Step 1, `_groups({site})`: one array of three groups. The null site is a group like any other.

```jq run
[{site: "N", x: 1}, {site: "S", x: 5}, {site: null, x: 7}, {site: "N", x: null}, {site: "N", x: 3}]
| _groups({site})
```

Step 2: for each group, two objects are made and merged. For the first group, the key run on the group's first row, then the aggregate run on the group's three rows, then the two merged into the output row:

```jq run
[{site: "N", x: 1}, {site: "N", x: null}, {site: "N", x: 3}]
| (.[0] | {site}), (map(.x) | {rows: length, n: count_nonnull, mean: mean}), ((.[0] | {site}) + (map(.x) | {rows: length, n: count_nonnull, mean: mean}))
```

The same for S and for the null site gives the result at the top.

### Other ways to write the key

The key is a filter run on each row, as in `_groups` above; what is new here is that the key is copied into the output row, so its form decides the column's name. `group_agg` runs the key on the group's first row and starts the output row from what comes back. `{site}` gives the object `{"site":"N"}`, which is used as it is, so the column is `site`. `.site` gives the string `"N"`, which is not an object, so it is wrapped as `{"key":"N"}` and the column is `key`.

On three rows, two of site N and one of site S, with `{rows: length}` as the aggregate: the object form, the bare field, the object form with another name, and a constant by mistake.

```jq run
[{site: "N", x: 1}, {site: "S", x: 5}, {site: "N", x: 3}]
| group_agg({site}; {rows: length}),
  group_agg(.site; {rows: length}),
  group_agg({place: .site}; {rows: length}),
  group_agg("site"; {rows: length})
```

The fourth is the quiet mistake: a string is the same for every row, so there is one group. A bare `site` without the dot is an error, `site/0 is not defined`, because a bare word is a function call.

**Groups by several fields** need nothing more: the key may be any value, and two rows are in the same group when their keys are equal. An object with two fields is such a value.

```jq run
[{site: "N", month: "Jan", x: 1}, {site: "N", month: "Feb", x: 2}, {site: "S", month: "Jan", x: 5}, {site: "N", month: "Jan", x: 3}]
| group_agg({site, month}; {rows: length, total: (map(.x) | add)})
```

Rows 1 and 4 share the key `{"site":"N","month":"Jan"}`, so they form one group. A key field can also be computed: `{site, big: (.x > 2)}` groups by site and by whether x is above 2.

### What it adds to plain jq

Not much, and that is deliberate. The same count with the builtin and with the library:

```jq run
[{site: "N", x: 1}, {site: "S", x: 5}, {site: null, x: 7}, {site: "N", x: 3}]
| (group_by(.site) | map({site: .[0].site, rows: length})),
  group_agg({site}; {rows: length})
```

- **Order.** The builtin's groups come sorted by key (null, "N", "S"). `group_agg`'s come in the order the keys first appear ("N", "S", null), because it is built on `_groups`.
- **The key is written once.** In plain jq the key is named twice: once to group, and once to copy it into the output row from the group's first row (`.[0].site`). `group_agg` does that copy itself.

### The definition

<!-- definition -->

With the example in mind, clause by clause. `keyf` is the first argument (`{site}`), `aggf` the second.

- `_groups(keyf)` makes the groups, in order of first appearance: the array of three groups shown above.
- `map(...)` turns each group into one output row. Inside it, `.` is one group.
- `.[0] | keyf` runs the key on the group's first row: `{"site":"N"}`. Every row of a group has the same key, so the first will do.
- `if type == "object" then . else {key: .} end`: a key that is an object is used as it is; any other key has no name, so it goes in a field called `key`.
- `+ aggf` runs the aggregate on the group and merges its object into the key's. A result field with the same name as a key field would overwrite it.
