Two definitions that turn text into typed values: `parse_ts` for one timestamp, `cast` for the named columns of a table. Both refuse what they cannot read; neither returns a quiet null for a bad value.

## _ts_exact/1, parse_ts/0
<!-- code: 7163a5ca -->

Input: a string. Output: seconds since 1970-01-01 UTC, with any fraction kept; null for null or `""`.

Two paths:

- **`_ts_exact($s)`** does the parsing for both paths. Its input is `YYYY-MM-DDTHH:MM:SSZ`. `fromdateiso8601` turns that into seconds; a failure is caught as null. Then `($e | todate) != $iso` prints the result back and compares it with what went in. On jq and gojq, `fromdateiso8601` accepts 30 February and returns 2 March; printed back that is `2026-03-02…`, which differs from the input, so it is refused. `$s` is the caller's original text, kept only for the message.
- **Fast path.** A string of exactly 19 characters with a space or `T` at position 10 is taken to be `YYYY-MM-DD HH:MM:SS`, rebuilt as `YYYY-MM-DDTHH:MM:SSZ` and handed to `_ts_exact`. This path exists because the regular expression below was most of the cost on large inputs.
- **General path.** `capture(…)` splits the string into date `d`, time `t`, optional fraction `f` and optional zone `z` (`Z`, `+HH:MM` or `+HHMM`). `// error(…)` turns "no match" into an error. Then: the date and time are read as UTC by `_ts_exact`; the fraction is added (`"0" + $m.f | tonumber` turns `.250` into 0.25); and the offset is subtracted, because a clock reading `+05:30` is five and a half hours ahead of UTC. `sub(":"; "")` makes both offset spellings the same four digits before they are cut into hours and minutes.

No zone means UTC.

```jq run
["2026-08-12 13:05:00", "2026-08-12T13:05:00Z", "2026-08-12T18:35:00+05:30", "2026-08-12 13:05:00.250", "", null]
| map(parse_ts),
  (["12/08/2026", "2026-08-12 13:05", "2026-02-30 00:00:00", "2026-02-30T00:00:00+01:00"] | map(try parse_ts catch .))
```

The first three are the same moment written three ways.

**Review finding 3, fixed in 0.9.0.** Until 0.8.1 an impossible date was accepted on jq 1.7.1, jq 1.8.2 and gojq and came back as another day, while jaq refused it. The print-back check in `_ts_exact` makes every engine refuse it, as the run above shows. The check costs time on the fast path: 200,000 timestamps took 3.9 s before and 5.0 s after, in the Python `jq` package.

## cast/1
<!-- code: 57e695a0 -->

Input: a table. `$schema` maps column names to `"number"`, `"timestamp"`, `"string"` or `"boolean"`.

- `map(reduce ($schema | to_entries[]) as $c (.; .[$c.key] |= (…)))`: for each row, each schema column is rewritten in place; columns not in the schema are untouched.
- Null and `""` become null whatever the type.
- **number:** a number stays; a string must match the pattern of a JSON number before `tonumber` is called. The pattern is there because engines differ on what `tonumber` accepts (`" 12"` is taken by jq 1.7.1 and refused by 1.8), and a library function should not change its answer with the engine.
- **timestamp:** `parse_ts`. **string:** `tostring`. **boolean:** `true` or `"true"`, `false` or `"false"`; anything else is an error.
- An unknown type name in the schema is an error naming the column.

```jq run
[{n: "12.5", t: "2026-08-12 13:05:00", b: "true", other: "kept"}, {n: "", t: null, b: false, other: 1}]
| cast({n: "number", t: "timestamp", b: "boolean"}),
  ([{n: " 12"}] | try cast({n: "number"}) catch .),
  ([{a: "1"}] | cast({a: "number", missing: "number"}))
```

**Review finding 4, settled in 0.9.0.** The last line shows that a schema column absent from a row is added to it as null (`.[key] |= …` creates the key), so every row comes out with the same columns. The function's comment and the README now say so, and a test pins it.
