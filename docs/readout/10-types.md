# Types

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/types.md`. Do not edit.

Two definitions that turn text into typed values: `parse_ts` for one timestamp, `cast` for the named columns of a table. Both refuse what they cannot read; neither returns a quiet null for a bad value.

## parse_ts

`parse_ts/0`, lines 91 to 105:

```jq
# a timestamp string to UTC epoch seconds (fractions kept). Accepts "YYYY-MM-DD HH:MM:SS" or "T",
# optional fraction, optional "Z" or +HH:MM / +HHMM offset. No offset means UTC (as ServiceNow
# and Splunk's _time strings store it). null and "" give null; anything else is an error, never
# a silent empty. Unlike strptime("%z"), the offset is applied.
# Fast path: the common 19-character form ("2026-08-12 13:05:00") skips the regex, which was most of
# the cost (at 500,000 rows in the Python jq package, 24.7 s with the regex, 7.5 s without); its
# dashes, colons and digits are still checked, by fromdateiso8601's own format, and a bad one is the
# same error.
def parse_ts:
  if . == null or . == "" then null
  elif length == 19 and (.[10:11] | . == " " or . == "T")
  then . as $s | (.[0:10] + "T" + .[11:19] + "Z")
    | try fromdateiso8601 catch error("parse_ts: not a timestamp: \($s | tojson)")
  else . as $s
    | (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2})[T ](?<t>[0-9]{2}:[0-9]{2}:[0-9]{2})(?<f>[.][0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
       // error("parse_ts: not a timestamp: \($s | tojson)")) as $m
    | ("\($m.d)T\($m.t)Z" | fromdateiso8601)
      + (if $m.f == null then 0 else ("0" + $m.f | tonumber) end)
      - (if $m.z == null or $m.z == "Z" then 0
         else ($m.z | sub(":"; "")) as $z
         | (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60) * (if $z[0:1] == "-" then -1 else 1 end)
         end)
  end;
```

Input: a string. Output: seconds since 1970-01-01 UTC, with any fraction kept; null for null or `""`.

Two paths:

- **Fast path.** A string of exactly 19 characters with a space or `T` at position 10 is taken to be `YYYY-MM-DD HH:MM:SS`. It is rebuilt as `YYYY-MM-DDTHH:MM:SSZ` and handed to `fromdateiso8601`, which checks the digits and separators itself; its failure is caught and reported under `parse_ts`'s own message. This path exists because the regular expression below was most of the cost on large inputs.
- **General path.** `capture(…)` splits the string into date `d`, time `t`, optional fraction `f` and optional zone `z` (`Z`, `+HH:MM` or `+HHMM`). `// error(…)` turns "no match" into an error. Then: the date and time are read as UTC; the fraction is added (`"0" + $m.f | tonumber` turns `.250` into 0.25); and the offset is subtracted, because a clock reading `+05:30` is five and a half hours ahead of UTC. `sub(":"; "")` makes both offset spellings the same four digits before they are cut into hours and minutes.

No zone means UTC.

```jq
["2026-08-12 13:05:00", "2026-08-12T13:05:00Z", "2026-08-12T18:35:00+05:30", "2026-08-12 13:05:00.250", "", null]
| map(parse_ts),
  (["12/08/2026", "2026-08-12 13:05"] | map(try parse_ts catch .))
```

```json
[1786539900,1786539900,1786539900,1786539900.25,null,null]
["parse_ts: not a timestamp: \"12/08/2026\"","parse_ts: not a timestamp: \"2026-08-12 13:05\""]
```

The first three are the same moment written three ways.

**Review finding 3.** A date that does not exist is not refused on every engine. `"2026-02-30 00:00:00" | parse_ts` is an error on jaq, but jq 1.7.1, jq 1.8.2 and gojq return 1772409600, which is 2 March: `fromdateiso8601` there carries the two extra days over instead of failing. So the "never a silent wrong value" rule does not hold for impossible dates, and the engines disagree. `calendar` already guards against this by printing the date back and comparing; `parse_ts` could do the same, at some cost on the fast path. A month above 12 or an hour above 23 is refused everywhere.

## cast

`cast/1`, lines 111 to 124:

```jq
# cast the named columns of every row. $schema = {column: "number" | "timestamp" | "string" | "boolean"}.
# "" and null become null. A value that does not parse is an error naming the column and value
# (Power Query's rule), never a null. Numbers must look like JSON numbers: jq 1.7.1's tonumber
# accepts " 12" and jq 1.8's refuses it, so the pattern decides instead of the version.
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

Input: a table. `$schema` maps column names to `"number"`, `"timestamp"`, `"string"` or `"boolean"`.

- `map(reduce ($schema | to_entries[]) as $c (.; .[$c.key] |= (…)))`: for each row, each schema column is rewritten in place; columns not in the schema are untouched.
- Null and `""` become null whatever the type.
- **number:** a number stays; a string must match the pattern of a JSON number before `tonumber` is called. The pattern is there because engines differ on what `tonumber` accepts (`" 12"` is taken by jq 1.7.1 and refused by 1.8), and a library function should not change its answer with the engine.
- **timestamp:** `parse_ts`. **string:** `tostring`. **boolean:** `true` or `"true"`, `false` or `"false"`; anything else is an error.
- An unknown type name in the schema is an error naming the column.

```jq
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}, {n: "", t: null, b: false, other: 1}]
| cast({n: "number", t: "timestamp", b: "boolean"}),
  ([{n: " 12"}] | try cast({n: "number"}) catch .),
  ([{a: "1"}] | cast({a: "number", missing: "number"}))
```

```json
[{"n":12.5,"t":1786539900,"b":true,"other":"kept"},{"n":null,"t":null,"b":false,"other":1}]
"cast: n = \" 12\" is not a number"
[{"a":1,"missing":null}]
```

**Review finding 4.** The last line shows that a schema column absent from a row is added to it as null (`.[key] |= …` creates the key). That is probably what a caller wants from a cast, since every row then has the same columns, but it is stated nowhere and no test covers it.
