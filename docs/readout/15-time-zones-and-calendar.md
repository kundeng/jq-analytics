# Time zones and calendar

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/time-zones-and-calendar.md`. Do not edit.

Four definitions that turn a moment (seconds since 1970 UTC) into a local clock reading. They read the zone tables at the top of the file, `tz_rules`, which a script generates from the tzdata package. For each zone, `t` is the sorted list of moments at which an offset starts, and `o` is the offset, in seconds east of UTC, that starts there. The first `t` of every zone is a very large negative number, so every moment has an entry at or before it. Seven zones are included, 1970 to 2100.

No function here reads the machine's own time zone, so a result does not depend on where the program runs.

The examples use `parse_ts` from the types page to write a moment as text: `"2026-07-15 12:00:00" | parse_ts` is that UTC time as seconds.

## tz

The rules of one zone, looked up by name. A program that converts many rows calls it once and keeps the result.

### The example

The smallest zone is UTC: one entry, offset 0, in force from the start.

```jq
tz("UTC")
```

```json
{"t":[-1000000000000000],"o":[0]}
```

A zone with daylight saving time has two entries per year. `America/Detroit` has several hundred, so the run shows three of them, positions 106 to 108, with each `t` also printed as a date:

```jq
tz("America/Detroit") | {t: .t[106:109], starts: (.t[106:109] | map(todate)), o: .o[106:109]}
```

```json
{
  "t": [1762063200, 1772953200, 1793512800],
  "starts": ["2025-11-02T06:00:00Z", "2026-03-08T07:00:00Z", "2026-11-01T06:00:00Z"],
  "o": [-18000, -14400, -18000]
}
```

Read the three lists position by position: from 2 November 2025 the offset is -18000 seconds (five hours behind UTC), from 8 March 2026 it is -14400 (four hours behind), and from 1 November 2026 it is -18000 again.

A name that is not in the tables is an error:

```jq
try tz("Mars/Olympus") catch .
```

```json
"tz: zone not in the zone tables: Mars/Olympus"
```

### The definition

`tz/1`, lines 135 to 139:

```jq
# the transition rules of one IANA zone, from the generated tzdata block above (from the tzdata package; covers
# 1970 to 2100). Unknown zone is an error. No process TZ is read anywhere in this file.
# tz_rules is a 27 KB literal that jq rebuilds on every call (0.8 ms), so a program that converts
# many rows looks the zone up once: tz("America/Detroit") as $det | ... | local_time($det).
def tz($name): tz_rules[$name] // error("tz: zone not in the zone tables: \($name)");
```

Built into jq: `error`. From this library: `tz_rules`.

- `tz_rules[$name]`: the zone's entry in the tables, or null when the name is not a key.
- `// error(...)`: `//` gives its right-hand side when the left is null or false, so a missing zone becomes the error above.
- It is a separate function because `tz_rules` is a large literal that jq builds again each time it is mentioned. `tz("America/Detroit") as $det` builds it once, and `$det` can then be passed to the two functions below, which accept either a name or this object.

## tz_offset

The zone's offset from UTC at one moment, in seconds. Add it to the moment to get the local clock.

### The example

Four moments in one zone: mid January, mid July, and the second before and the moment of the 2026 spring change.

```jq
["2026-01-15 12:00:00", "2026-07-15 12:00:00", "2026-03-08 06:59:59", "2026-03-08 07:00:00"]
| map({utc: ., offset: (parse_ts | tz_offset("America/Detroit"))})
```

```json
[
  {"utc": "2026-01-15 12:00:00", "offset": -18000},
  {"utc": "2026-07-15 12:00:00", "offset": -14400},
  {"utc": "2026-03-08 06:59:59", "offset": -18000},
  {"utc": "2026-03-08 07:00:00", "offset": -14400}
]
```

Winter is -18000 seconds, five hours behind UTC, and summer is -14400, four hours behind. The change is at 07:00:00 UTC on 8 March, which is 02:00 local: one second before it the winter offset still holds.

### Reading the call

The input is the moment. The argument `$tz` is a value: a zone name, or the object that `tz($name)` returned.

### What happens inside, on the example

For the July moment. Step 1: the moment as seconds, kept as `$e`.

```jq
"2026-07-15 12:00:00" | parse_ts
```

```json
1784116800
```

Step 2, `$tz | if type == "string" then tz(.) else . end`: the name is looked up, which gives the zone's `{t, o}` object shown under `tz` above. From here on the input is that object.

Step 3, `(.t | bsearch($e)) as $i`: a binary search for the moment in the sorted list `t`. `bsearch` returns the position when the value is in the list. When it is not, it returns `-1 - p`, where `p` is the position at which the value would be inserted. The July moment is not a transition, so the result is negative:

```jq
tz("America/Detroit") | .t | bsearch(1784116800)
```

```json
-109
```

Step 4, `if $i >= 0 then $i else -2 - $i end`: the insertion position is `-1 - (-109) = 108`, and the entry before it, `-2 - (-109) = 107`, is the latest transition at or before the moment. Its start and the next one's:

```jq
tz("America/Detroit") | .t[107:109] | map(todate)
```

```json
["2026-03-08T07:00:00Z","2026-11-01T06:00:00Z"]
```

15 July lies between 8 March and 1 November, so entry 107 is the one in force.

Step 5, `.o[...]`: the offset at that position.

```jq
tz("America/Detroit") | .o[107]
```

```json
-14400
```

A moment that is a transition is found exactly, and step 4 uses its own position:

```jq
tz("America/Detroit") | .t | bsearch(1772953200)
```

```json
107
```

### The definition

`tz_offset/1`, lines 141 to 146:

```jq
# UTC offset in seconds at the input epoch; $tz is a zone name or the object tz($name) returned
def tz_offset($tz):
  . as $e
  | ($tz | if type == "string" then tz(.) else . end)
  | (.t | bsearch($e)) as $i
  | .o[if $i >= 0 then $i else -2 - $i end];
```

Built into jq: `bsearch`, `type`. From this library: `tz`.

- `. as $e`: the moment, kept under a name, because the next line replaces the input with the zone's rules.
- `$tz | if type == "string" then tz(.) else . end`: step 2. A name is looked up; an object is taken to be the rules already.
- `(.t | bsearch($e)) as $i`: step 3.
- `.o[if $i >= 0 then $i else -2 - $i end]`: steps 4 and 5. The very large negative first `t` guarantees that the position is never below 0.

## local_time

The local clock reading of a moment in a zone, as an object with the date, the clock fields and the weekday. It is SQL's `ts AT TIME ZONE 'zone'` with the parts already taken out.

### The example

```jq
"2026-08-12 13:05:00.5" | parse_ts | local_time("America/Detroit")
```

```json
{
  "date": "2026-08-12",
  "year": 2026,
  "month": 8,
  "day": 12,
  "hour": 9,
  "minute": 5,
  "second": 0.5,
  "weekday": 3,
  "offset_s": -14400,
  "local_epoch": 1786525500.5
}
```

13:05 UTC in August is 09:05 in that zone, four hours behind. `weekday` 3 is Wednesday, counting from Sunday as 0. The half second is kept in `second`.

### What happens inside, on the example

Step 1, `tz_offset($tz) as $o`: the offset at that moment. The moment itself is the first value here and the offset the second.

```jq
"2026-08-12 13:05:00.5" | parse_ts | ., tz_offset("America/Detroit")
```

```json
1786539900.5
-14400
```

Step 2, `(. + $o) as $l`: the moment plus the offset. Read as if it were UTC, this number shows the local clock.

```jq
1786539900.5 + -14400 | ., (floor | todate)
```

```json
1786525500.5
"2026-08-12T09:05:00Z"
```

Step 3, `$l | floor | gmtime`: jq's own breakdown of a whole number of seconds into year, month (0 to 11), day, hour, minute, second, weekday and day of the year.

```jq
1786525500.5 | floor | gmtime
```

```json
[2026,7,12,9,5,0,3,223]
```

Step 4: the object is built from that array. The month gets 1 added (7 becomes 8, August), and the fraction that `floor` removed is added back to the seconds.

### The definition

`local_time/1`, lines 148 to 155:

```jq
# the local wall clock of the input epoch in zone $tz (a name or tz($name)), as an object:
# {date: "YYYY-MM-DD", year, month (1-12), day, hour, minute, second, weekday (0 = Sunday),
#  offset_s, local_epoch (epoch of the wall clock read as if it were UTC)}
def local_time($tz):
  tz_offset($tz) as $o | (. + $o) as $l | ($l | floor | gmtime) as $g
  | {date: ($g | strftime("%Y-%m-%d")), year: $g[0], month: ($g[1] + 1), day: $g[2],
     hour: $g[3], minute: $g[4], second: ($g[5] + ($l - ($l | floor))), weekday: $g[6],
     offset_s: $o, local_epoch: $l};
```

Built into jq: `floor`, `gmtime`, `strftime`. From this library: `tz_offset`.

- `tz_offset($tz) as $o | (. + $o) as $l | ($l | floor | gmtime) as $g`: steps 1 to 3. `floor` comes first because the fraction is handled separately.
- `date: ($g | strftime("%Y-%m-%d"))`: the local date as text, for grouping by day.
- `month: ($g[1] + 1)`: 1 to 12.
- `second: ($g[5] + ($l - ($l | floor)))`: the whole seconds plus the fraction.
- `offset_s` and `local_epoch` are kept so that a caller can go back to UTC, or compare two local times as numbers.

## hours_between

The hours from one moment to another, with no rounding; null when either is missing. It is SQL's `DATE_DIFF` in hours, kept as a fraction.

### The example

Two requests, each with the moment it was opened. The first was resolved 90 minutes later. The second is still open.

```jq
[{id: 1, opened: "2026-08-12 13:00:00", resolved: "2026-08-12 14:30:00"}, {id: 2, opened: "2026-08-12 13:00:00", resolved: null}]
| map({id, hours: hours_between(.opened | parse_ts; .resolved | parse_ts)})
```

```json
[
  {"id": 1, "hours": 1.5},
  {"id": 2, "hours": null}
]
```

90 minutes is 1.5 hours. The open request gets null, not an error and not a negative number.

### Reading the call

Both arguments are filters, run on the current input, which here is one row. `;` separates them: jq uses a semicolon between arguments because a comma already means "emit both values".

### The definition

`hours_between/2`, lines 157 to 159:

```jq
# hours from epoch a to epoch b, exact (no rounding); null when either is null
def hours_between(a; b): (a) as $a | (b) as $b
  | if $a == null or $b == null then null else ($b - $a) / 3600 end;
```

- `(a) as $a | (b) as $b`: each filter is run once and its result named.
- `if $a == null or $b == null then null else ($b - $a) / 3600 end`: null on either side gives null; otherwise the difference in seconds divided by the 3600 seconds of an hour.
