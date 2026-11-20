### What it is for

Two public definitions that turn text into typed values: `parse_ts` for one timestamp, `cast_columns` for the named columns of a table. Data from a CSV file, a log export or a ticketing system arrives with every value a string and an empty string where a value is missing; nothing can be added, compared by size or put on a clock until it is typed. This is usually the first stage of a program:

```jq run
[{opened: "2026-08-12 13:30:00", hours: "2.5"}, {opened: "", hours: ""}]
| cast_columns({hours: "number", opened: "timestamp"})
```

`parse_ts` takes one string and gives seconds since 1970-01-01 UTC, the number every time function in the library reads. `cast_columns` takes a table and a schema (column name to `"number"`, `"timestamp"`, `"string"` or `"boolean"`) and gives the table back with those columns converted; other columns are untouched.

### The rules it keeps

- **Missing is `""` or null, and becomes null.** Nothing else turns into null.
- **Both refuse what they cannot read.** Neither returns a quiet null for a bad value: a timestamp in another layout, a date that does not exist (30 February), a number with a leading space, a boolean written `"yes"`, a type name that is not one of the four. The error quotes the value, and `cast_columns` names the column.
- **No zone means UTC.** `parse_ts` reads `YYYY-MM-DD HH:MM:SS` or the same with `T`, an optional fraction of a second, and an optional `Z`, `±HH:MM` or `±HHMM`. A clock with an offset is converted to UTC; a clock without one is taken as UTC, which is how ticketing systems and log exports usually write wall-clock text. A fraction is kept.
- **A number must look like a JSON number** before it is converted, so the answer is the same on every engine.
- **A schema column that a row lacks is added as null**, so every row comes out with the same columns.
- **Order:** rows keep their order, and each row keeps its fields.

### Beside core jq, SQL and pandas

Core jq has `fromdateiso8601` and `tonumber`. Both read less than `parse_ts` and `cast_columns` and, worse, read it differently on each engine (jq 1.7.1, gojq 0.12, jaq 3.1):

| Input | jq 1.7.1 | gojq | jaq |
|---|---|---|---|
| `"2026-08-12 13:05:00" \| fromdateiso8601` (a space, no `Z`) | error | error | error |
| `"2026-08-12T13:05:00.250Z" \| fromdateiso8601` | error | error | 1786539900.25 |
| `"2026-08-12T18:35:00+05:30" \| fromdateiso8601` | error | 1786539900 | 1786539900 |
| `"2026-02-30T00:00:00Z" \| fromdateiso8601` | 1772409600 (2 March) | 1772409600 (2 March) | error |
| `" 12" \| tonumber` | 12 | error | 12 |

`parse_ts` gives one answer for all of these on every engine: the space form, the fraction and the offset are read, 30 February is an error. It still calls `fromdateiso8601` inside, on a text it has rebuilt into the one form every engine reads, and prints the result back with `todate` to catch the engines that roll an impossible date into the next month.

SQL's `CAST(s AS TIMESTAMP)` and `CAST(s AS DOUBLE)` are the model: DuckDB refuses `'2026-02-30 00:00:00'` with `Conversion Error: timestamp field value out of range`, and `parse_ts` matches DuckDB's `ts::TIMESTAMPTZ` with the session zone set to UTC. DuckDB is more lenient about numbers: `CAST(' 12' AS DOUBLE)` is 12. Its `TRY_CAST` turns a failure into NULL, which the library deliberately does not offer.

pandas' `pd.to_datetime` refuses 30 February by default (`DateParseError: day is out of range for month`), but the common `errors="coerce"` turns it, and `""`, into `NaT` with no trace of which was which. `cast_columns` is the one-call form of pandas' `astype` with a dict, or Power Query's "Changed Type" step, with the rule that a failure stops the program.

### Decisions

- **0.1.1 (2026-11-17).** A faster `parse_ts`: a 19-character timestamp takes a short path without the regular expression, which was the larger part of its cost on a big table.
- **0.9.0 (2026-11-18, spec 55).** `parse_ts` refuses a date that does not exist (review finding 3): before, jq and gojq read `"2026-02-30 00:00:00"` as 2 March and jaq raised its own error. The fix prints the parsed moment back and compares, as `calendar` does. The cost of that check on the short path was measured at 200,000 rows and accepted. The same sprint stated, and pinned with a test, that `cast` adds a missing schema column as null (finding 4).
- **0.10.0 (2026-11-18, spec 57).** `cast` was renamed `cast_columns`, because the old name did not say what it acts on. The old name is gone; there is no alias.
- **Errors, not nulls, for bad values** follows the README's rule 4: a value silently turned into null is a row silently dropped from every later count.

## _ts_exact/1, parse_ts/0
<!-- code: 7163a5ca -->

`parse_ts` turns a timestamp string into seconds since 1970-01-01 UTC, the number that every time function in the library takes. It is SQL's `CAST(s AS TIMESTAMP)` followed by `EPOCH`. `_ts_exact` is its helper: it reads one exact form and refuses a date that does not exist.

### The example

Six inputs: the same moment written three ways, a fraction of a second, an empty string and a null.

| input | what it is |
|---|---|
| `"2026-08-12 13:05:00"` | no zone, which means UTC |
| `"2026-08-12T13:05:00Z"` | `T` between date and time, `Z` for UTC |
| `"2026-08-12T18:35:00+05:30"` | a clock five and a half hours ahead of UTC |
| `"2026-08-12 13:05:00.250"` | a quarter of a second later |
| `""` | empty |
| `null` | missing |

```jq run
["2026-08-12 13:05:00", "2026-08-12T13:05:00Z", "2026-08-12T18:35:00+05:30", "2026-08-12 13:05:00.250", "", null]
| map(parse_ts)
```

The first three give the same number, because they are the same moment. Hand check of the third: 18:35 on a clock that is 5:30 ahead of UTC is 13:05 UTC. The fourth keeps its fraction. The empty string and the null give null.

### What is refused

Anything else is an error that quotes the text. That includes a wrong layout, a missing seconds part, and a date that does not exist, with or without an offset.

```jq run
["12/08/2026", "2026-08-12 13:05", "2026-02-30 00:00:00", "2026-02-30T00:00:00+01:00"] | map(try parse_ts catch .)
```

### What happens inside, on the example

`parse_ts` has two paths. A string of exactly 19 characters with a space or `T` between date and time takes the short one. Every other string takes the general one.

**The short path, on `"2026-08-12 13:05:00"`.** Step 1, `.[0:10] + "T" + .[11:19] + "Z"`: the string is rebuilt in the one form `_ts_exact` reads. `.[0:10]` is the date and `.[11:19]` the time.

```jq run
"2026-08-12 13:05:00" | .[0:10], .[11:19], (.[0:10] + "T" + .[11:19] + "Z")
```

Step 2, `_ts_exact($s)` on that. Inside it, `fromdateiso8601` gives the seconds, and `todate` prints the seconds back as text. The text matches what went in, so the seconds are returned.

```jq run
"2026-08-12T13:05:00Z" | fromdateiso8601, (fromdateiso8601 | todate), _ts_exact("2026-08-12 13:05:00")
```

The print-back is what refuses 30 February. Some engines read `2026-02-30T00:00:00Z` as 2 March without complaint. Printed back, that is `2026-03-02T00:00:00Z`, which differs from the input, so `_ts_exact` raises the error. Other engines refuse the date themselves; the `try` turns that into the same error. The argument of `_ts_exact` is the caller's original text, used only in the message:

```jq run
"2026-02-30T00:00:00Z" | try _ts_exact("2026-02-30 00:00:00") catch .
```

**The general path, on `"2026-08-12T18:35:00.250+05:30"`.** Step 1, `capture(...)`: a regular expression cuts the string into date `d`, time `t`, fraction `f` and zone `z`. A part that is absent comes back as null. A string that does not match gives nothing, and `// error(...)` turns that into the error.

```jq run
"2026-08-12T18:35:00.250+05:30"
| capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
```

Step 2, `"\($m.d)T\($m.t)Z" | _ts_exact($s)`: the date and time read as if they were UTC. This is 18:35 UTC, which is not yet the answer.

```jq run
"2026-08-12T18:35:00Z" | _ts_exact("2026-08-12T18:35:00.250+05:30")
```

Step 3, the fraction: `"0" + $m.f | tonumber` turns `.250` into a number to add.

```jq run
"0" + ".250" | tonumber
```

Step 4, the offset in seconds. `sub(":"; "")` removes the colon, so `+05:30` and `+0530` are the same five characters. Characters 1 to 2 are the hours and 3 to 4 the minutes. The sign is character 0.

```jq run
"+05:30" | sub(":"; "") | ., .[1:3], .[3:5], ((.[1:3] | tonumber) * 3600 + (.[3:5] | tonumber) * 60)
```

Step 5, seconds plus fraction minus offset. The offset is subtracted because a clock reading `+05:30` is ahead of UTC.

```jq run
1786559700 + 0.25 - 19800, ("2026-08-12T18:35:00.250+05:30" | parse_ts)
```

Both lines are the same number, and it is the first example's 13:05:00 plus a quarter of a second.

### The definition

<!-- definition -->

`_ts_exact($s)`:

- `. as $iso` keeps the input text under a name; `as` binds a name and leaves the input as it is.
- `(try ($iso | fromdateiso8601) catch null) as $e`: the seconds, or null when the engine refuses the text.
- `if $e == null or ($e | todate) != $iso then error(...)`: refused by the engine, or accepted and printed back as a different date.

`parse_ts`:

- `if . == null or . == "" then null`: nothing in, null out.
- `elif length == 19 and (.[10:11] | . == " " or . == "T")`: the short path. It exists because the regular expression of the general path is the larger part of the cost on a big table, and most timestamps have this form. Its digits, dashes and colons are still checked, by `fromdateiso8601` inside `_ts_exact`.
- `else`: the general path, steps 1 to 5. `$m.z == null or $m.z == "Z"` gives an offset of 0, so no zone means UTC.

## cast_columns/1
<!-- code: 5bf88824 -->

Gives the named columns of a table their types: text to number, timestamp or boolean, and anything to string. It is SQL's `CAST(col AS type)` for several columns at once, and Power Query's "Changed Type" step.

### The example

Two rows as they come from a CSV file, where every value is text. The second row has an empty `n` and a missing `t`.

| n | t | b | other |
|---|---|---|---|
| `"12.5"` | `"2026-08-12 13:05:00"` | `"true"` | `"kept"` |
| `""` | null | false | 1 |

```jq run
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}, {n: "", t: null, b: false, other: 1}]
| cast_columns({b: "boolean", n: "number", t: "timestamp"})
```

In the first row `n` is now the number 12.5, `t` is seconds since 1970 and `b` is the boolean true. In the second row the empty string became null. `other` is not in the schema and is untouched in both rows.

### Reading the call

The one argument is a value, an object from column name to type name. The type names are `"number"`, `"timestamp"`, `"string"` and `"boolean"`. The input is the table.

### What happens inside, on the example

Step 1, `$schema | to_entries`: the schema as a list of column and type pairs. The `[]` after it in the code hands them to `reduce` one at a time.

```jq run
{b: "boolean", n: "number", t: "timestamp"} | to_entries
```

jq and jaq give the pairs in the order the schema was written, and gojq gives them sorted by name. The schema here is written in name order so that both agree. The order does not change the result, because each pair rewrites a different column.

Step 2: for each row, `reduce` starts from the row and rewrites one column per pair. The first row after the `b` pair, after `b` and `n`, and after all three:

```jq run
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}]
| cast_columns({b: "boolean"}), cast_columns({b: "boolean", n: "number"}), cast_columns({b: "boolean", n: "number", t: "timestamp"})
```

Three tables of one row each. One more column has its type in each.

### What is refused

A value that does not parse is an error naming the column and the value. A number must look like a JSON number, so a leading space is refused. A type name that is not one of the four is an error too.

```jq run
([{n: " 12"}] | try cast_columns({n: "number"}) catch .),
([{b: "yes"}] | try cast_columns({b: "boolean"}) catch .),
([{b: "yes"}] | try cast_columns({b: "date"}) catch .)
```

### A column the row lacks

A schema column that a row does not have is added to it as null, so every row comes out with the same columns.

```jq run
[{a: "1"}] | cast_columns({a: "number", missing: "number"})
```

### The definition

<!-- definition -->

- `map(reduce ($schema | to_entries[]) as $c (.; ...))`: steps 1 and 2, for each row.
- `.[$c.key] |= (...)`: rewrites that one column in place. `|=` runs the expression on the column's current value and stores the result. On a column the row lacks, the current value is null and the column is created.
- `if . == null or . == "" then null`: null and the empty string become null whatever the type.
- **number:** a number stays. A string must match the pattern of a JSON number before `tonumber` is called. The pattern is there because engines differ on what `tonumber` accepts (`" 12"` is taken by jq 1.7.1 and refused by jq 1.8), and the pattern makes the answer the same on all of them.
- **timestamp:** `parse_ts`, with its errors. **string:** `tostring`. **boolean:** `true` or `"true"`, `false` or `"false"`; anything else is an error.
- The last `else`: an unknown type name is an error naming the type and the column.
