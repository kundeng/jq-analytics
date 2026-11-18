# Types

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/types.md`. Do not edit.

Two public definitions that turn text into typed values: `parse_ts` for one timestamp, `cast` for the named columns of a table. Both refuse what they cannot read. Neither returns a quiet null for a bad value.

## _ts_exact, parse_ts

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

```jq
["2026-08-12 13:05:00", "2026-08-12T13:05:00Z", "2026-08-12T18:35:00+05:30", "2026-08-12 13:05:00.250", "", null]
| map(parse_ts)
```

```json
[1786539900,1786539900,1786539900,1786539900.25,null,null]
```

The first three give the same number, because they are the same moment. Hand check of the third: 18:35 on a clock that is 5:30 ahead of UTC is 13:05 UTC. The fourth keeps its fraction. The empty string and the null give null.

### What is refused

Anything else is an error that quotes the text. That includes a wrong layout, a missing seconds part, and a date that does not exist, with or without an offset.

```jq
["12/08/2026", "2026-08-12 13:05", "2026-02-30 00:00:00", "2026-02-30T00:00:00+01:00"] | map(try parse_ts catch .)
```

```json
["parse_ts: not a timestamp: \"12/08/2026\"","parse_ts: not a timestamp: \"2026-08-12 13:05\"","parse_ts: not a timestamp: \"2026-02-30 00:00:00\"","parse_ts: not a timestamp: \"2026-02-30T00:00:00+01:00\""]
```

### What happens inside, on the example

`parse_ts` has two paths. A string of exactly 19 characters with a space or `T` between date and time takes the short one. Every other string takes the general one.

**The short path, on `"2026-08-12 13:05:00"`.** Step 1, `.[0:10] + "T" + .[11:19] + "Z"`: the string is rebuilt in the one form `_ts_exact` reads. `.[0:10]` is the date and `.[11:19]` the time.

```jq
"2026-08-12 13:05:00" | .[0:10], .[11:19], (.[0:10] + "T" + .[11:19] + "Z")
```

```json
"2026-08-12"
"13:05:00"
"2026-08-12T13:05:00Z"
```

Step 2, `_ts_exact($s)` on that. Inside it, `fromdateiso8601` gives the seconds, and `todate` prints the seconds back as text. The text matches what went in, so the seconds are returned.

```jq
"2026-08-12T13:05:00Z" | fromdateiso8601, (fromdateiso8601 | todate), _ts_exact("2026-08-12 13:05:00")
```

```json
1786539900
"2026-08-12T13:05:00Z"
1786539900
```

The print-back is what refuses 30 February. Some engines read `2026-02-30T00:00:00Z` as 2 March without complaint. Printed back, that is `2026-03-02T00:00:00Z`, which differs from the input, so `_ts_exact` raises the error. Other engines refuse the date themselves; the `try` turns that into the same error. The argument of `_ts_exact` is the caller's original text, used only in the message:

```jq
"2026-02-30T00:00:00Z" | try _ts_exact("2026-02-30 00:00:00") catch .
```

```json
"parse_ts: not a timestamp: \"2026-02-30 00:00:00\""
```

**The general path, on `"2026-08-12T18:35:00.250+05:30"`.** Step 1, `capture(...)`: a regular expression cuts the string into date `d`, time `t`, fraction `f` and zone `z`. A part that is absent comes back as null. A string that does not match gives nothing, and `// error(...)` turns that into the error.

```jq
"2026-08-12T18:35:00.250+05:30"
| capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
```

```json
{"d":"2026-08-12","t":"18:35:00","f":".250","z":"+05:30"}
```

Step 2, `"\($m.d)T\($m.t)Z" | _ts_exact($s)`: the date and time read as if they were UTC. This is 18:35 UTC, which is not yet the answer.

```jq
"2026-08-12T18:35:00Z" | _ts_exact("2026-08-12T18:35:00.250+05:30")
```

```json
1786559700
```

Step 3, the fraction: `"0" + $m.f | tonumber` turns `.250` into a number to add.

```jq
"0" + ".250" | tonumber
```

```json
0.250
```

Step 4, the offset in seconds. `sub(":"; "")` removes the colon, so `+05:30` and `+0530` are the same five characters. Characters 1 to 2 are the hours and 3 to 4 the minutes. The sign is character 0.

```jq
"+05:30" | sub(":"; "") | ., .[1:3], .[3:5], ((.[1:3] | tonumber) * 3600 + (.[3:5] | tonumber) * 60)
```

```json
"+0530"
"05"
"30"
19800
```

Step 5, seconds plus fraction minus offset. The offset is subtracted because a clock reading `+05:30` is ahead of UTC.

```jq
1786559700 + 0.25 - 19800, ("2026-08-12T18:35:00.250+05:30" | parse_ts)
```

```json
1786539900.25
1786539900.25
```

Both lines are the same number, and it is the first example's 13:05:00 plus a quarter of a second.

### The definition

`_ts_exact/1`, lines 82 to 87:

```jq
# "YYYY-MM-DDTHH:MM:SSZ" to epoch seconds, refusing a date or time that does not exist. Some engines
# accept 2026-02-30 and carry it over to 2 March; printing the result back and comparing catches
# that on every engine. $s is the caller's original text, for the message.
def _ts_exact($s):
  . as $iso | (try ($iso | fromdateiso8601) catch null) as $e
  | if $e == null or ($e | todate) != $iso then error("parse_ts: not a timestamp: \($s | tojson)") else $e end;
```

`parse_ts/0`, lines 89 to 111:

```jq
# a timestamp string to UTC epoch seconds (fractions kept). Accepts "YYYY-MM-DD HH:MM:SS" or "T",
# optional fraction, optional "Z" or +HH:MM / +HHMM offset. No offset means UTC (as ServiceNow
# and Splunk's _time strings store it). null and "" give null; anything else is an error, never
# a silent empty: that includes a date or time that does not exist, such as 30 February.
# Unlike strptime("%z"), the offset is applied.
# Fast path: the common 19-character form ("2026-08-12 13:05:00") skips the regex, which was most of
# the cost (at 500,000 rows in the Python jq package, 24.7 s with the regex, 7.5 s without); its
# dashes, colons and digits are still checked, by fromdateiso8601's own format, and a bad one is the
# same error.
def parse_ts:
  if . == null or . == "" then null
  elif length == 19 and (.[10:11] | . == " " or . == "T")
  then . as $s | (.[0:10] + "T" + .[11:19] + "Z") | _ts_exact($s)
  else . as $s
    | (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
       // error("parse_ts: not a timestamp: \($s | tojson)")) as $m
    | ("\($m.d)T\($m.t)Z" | _ts_exact($s))
      + (if $m.f == null then 0 else ("0" + $m.f | tonumber) end)
      - (if $m.z == null or $m.z == "Z" then 0
         else ($m.z | sub(":"; "")) as $z
         | (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60) * (if $z[0:1] == "-" then -1 else 1 end)
         end)
  end;
```

`_ts_exact($s)`:

- `. as $iso` keeps the input text under a name; `as` binds a name and leaves the input as it is.
- `(try ($iso | fromdateiso8601) catch null) as $e`: the seconds, or null when the engine refuses the text.
- `if $e == null or ($e | todate) != $iso then error(...)`: refused by the engine, or accepted and printed back as a different date.

`parse_ts`:

- `if . == null or . == "" then null`: nothing in, null out.
- `elif length == 19 and (.[10:11] | . == " " or . == "T")`: the short path. It exists because the regular expression of the general path is the larger part of the cost on a big table, and most timestamps have this form. Its digits, dashes and colons are still checked, by `fromdateiso8601` inside `_ts_exact`.
- `else`: the general path, steps 1 to 5. `$m.z == null or $m.z == "Z"` gives an offset of 0, so no zone means UTC.

## cast

Gives the named columns of a table their types: text to number, timestamp or boolean, and anything to string. It is SQL's `CAST(col AS type)` for several columns at once, and Power Query's "Changed Type" step.

### The example

Two rows as they come from a CSV file, where every value is text. The second row has an empty `n` and a missing `t`.

| n | t | b | other |
|---|---|---|---|
| `"12.5"` | `"2026-08-12 13:05:00"` | `"true"` | `"kept"` |
| `""` | null | false | 1 |

```jq
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}, {n: "", t: null, b: false, other: 1}]
| cast({b: "boolean", n: "number", t: "timestamp"})
```

```json
[
  {"n": 12.5, "t": 1786539900, "b": true, "other": "kept"},
  {"n": null, "t": null, "b": false, "other": 1}
]
```

In the first row `n` is now the number 12.5, `t` is seconds since 1970 and `b` is the boolean true. In the second row the empty string became null. `other` is not in the schema and is untouched in both rows.

### Reading the call

The one argument is a value, an object from column name to type name. The type names are `"number"`, `"timestamp"`, `"string"` and `"boolean"`. The input is the table.

### What happens inside, on the example

Step 1, `$schema | to_entries`: the schema as a list of column and type pairs. The `[]` after it in the code hands them to `reduce` one at a time.

```jq
{b: "boolean", n: "number", t: "timestamp"} | to_entries
```

```json
[
  {"key": "b", "value": "boolean"},
  {"key": "n", "value": "number"},
  {"key": "t", "value": "timestamp"}
]
```

jq and jaq give the pairs in the order the schema was written, and gojq gives them sorted by name. The schema here is written in name order so that both agree. The order does not change the result, because each pair rewrites a different column.

Step 2: for each row, `reduce` starts from the row and rewrites one column per pair. The first row after the `b` pair, after `b` and `n`, and after all three:

```jq
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}]
| cast({b: "boolean"}), cast({b: "boolean", n: "number"}), cast({b: "boolean", n: "number", t: "timestamp"})
```

```json
[{"n":"12.5","t":"2026-08-12 13:05:00","b":true,"other":"kept"}]
[{"n":12.5,"t":"2026-08-12 13:05:00","b":true,"other":"kept"}]
[{"n":12.5,"t":1786539900,"b":true,"other":"kept"}]
```

Three tables of one row each. One more column has its type in each.

### What is refused

A value that does not parse is an error naming the column and the value. A number must look like a JSON number, so a leading space is refused. A type name that is not one of the four is an error too.

```jq
([{n: " 12"}] | try cast({n: "number"}) catch .),
([{b: "yes"}] | try cast({b: "boolean"}) catch .),
([{b: "yes"}] | try cast({b: "date"}) catch .)
```

```json
"cast: n = \" 12\" is not a number"
"cast: b = \"yes\" is not a boolean"
"cast: unknown type \"date\" for b"
```

### A column the row lacks

A schema column that a row does not have is added to it as null, so every row comes out with the same columns.

```jq
[{a: "1"}] | cast({a: "number", missing: "number"})
```

```json
[
  {"a": 1, "missing": null}
]
```

### The definition

`cast/1`, lines 113 to 131:

```jq
# cast the named columns of every row. $schema = {column: "number" | "timestamp" | "string" | "boolean"}.
# "" and null become null. A value that does not parse is an error naming the column and value
# (Power Query's rule), never a null. Numbers must look like JSON numbers: jq 1.7.1's tonumber
# accepts " 12" and jq 1.8's refuses it, so the pattern decides instead of the version.
# A schema column that a row lacks is added to it as null, so every row comes out with the same columns.
def cast($schema):
  map(reduce ($schema | to_entries[]) as $c (.;
    .[$c.key] |= (
      if . == null or . == "" then null
      elif $c.value == "number" then
        (if type == "number" then .
         elif type == "string" and test("^-?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$") then tonumber
         else error("cast: \($c.key) = \(tojson) is not a number") end)
      elif $c.value == "timestamp" then parse_ts
      elif $c.value == "string" then tostring
      elif $c.value == "boolean" then
        (if . == true or . == "true" then true elif . == false or . == "false" then false
         else error("cast: \($c.key) = \(tojson) is not a boolean") end)
      else error("cast: unknown type \($c.value | tojson) for \($c.key)") end)));
```

- `map(reduce ($schema | to_entries[]) as $c (.; ...))`: steps 1 and 2, for each row.
- `.[$c.key] |= (...)`: rewrites that one column in place. `|=` runs the expression on the column's current value and stores the result. On a column the row lacks, the current value is null and the column is created.
- `if . == null or . == "" then null`: null and the empty string become null whatever the type.
- **number:** a number stays. A string must match the pattern of a JSON number before `tonumber` is called. The pattern is there because engines differ on what `tonumber` accepts (`" 12"` is taken by jq 1.7.1 and refused by jq 1.8), and the pattern makes the answer the same on all of them.
- **timestamp:** `parse_ts`, with its errors. **string:** `tostring`. **boolean:** `true` or `"true"`, `false` or `"false"`; anything else is an error.
- The last `else`: an unknown type name is an error naming the type and the column.
