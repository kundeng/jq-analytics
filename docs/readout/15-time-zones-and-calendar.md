# Time zones and calendar

Generated from `src/jq_analytics/analytics.jq` and `docs/readout/notes/time-zones-and-calendar.md`. Do not edit.

Four definitions that turn a moment (seconds since 1970 UTC) into a local clock reading. They read the zone tables at the top of the file, `tz_rules`, which a script generates from the tzdata package: for each zone, `t` is the sorted list of moments at which an offset starts and `o` the offset, in seconds east of UTC, that starts there. The first `t` of every zone is a very large negative number, so every moment has an entry at or before it. Seven zones are included, 1970 to 2100.

No function here reads the machine's own time zone, so a result does not depend on where the program runs.

## tz

`tz/1`, line 139:

```jq
# the transition rules of one IANA zone, from the generated tzdata block above (from the tzdata package; covers
# 1970 to 2100). Unknown zone is an error. No process TZ is read anywhere in this file.
# tz_rules is a 27 KB literal that jq rebuilds on every call (0.8 ms), so a program that converts
# many rows looks the zone up once: tz("America/Detroit") as $det | ... | local_time($det).
def tz($name): tz_rules[$name] // error("tz: zone not in the zone tables: \($name)");
```

`tz_rules[$name] // error(…)`: the rules of one zone, or an error naming the zone. `//` gives the right-hand side when the left is null, which is what a missing key gives.

It exists as a separate step because `tz_rules` is a large literal that jq builds again each time it is mentioned. A program that converts many rows calls `tz` once, keeps the result in a variable, and passes that to the functions below, which accept either a name or this object.

```jq
(tz("America/Detroit") | {transitions: (.t | length), first_offset: .o[0], fields: keys}),
(try tz("Mars/Olympus") catch .)
```

```json
{"transitions":255,"first_offset":-18000,"fields":["o","t"]}
"tz: zone not in the zone tables: Mars/Olympus"
```

## tz_offset

`tz_offset/1`, lines 142 to 146:

```jq
# UTC offset in seconds at the input epoch; $tz is a zone name or the object tz($name) returned
def tz_offset($tz):
  . as $e
  | ($tz | if type == "string" then tz(.) else . end)
  | (.t | bsearch($e)) as $i
  | .o[if $i >= 0 then $i else -2 - $i end];
```

Input: a moment. Output: the zone's offset from UTC at that moment, in seconds.

- `$tz | if type == "string" then tz(.) else . end`: a name is looked up; an object is taken to be the rules already.
- `(.t | bsearch($e)) as $i`: position of the moment among the transitions. Found exactly: that position. Otherwise `bsearch` gives `-1 - (insertion point)`, and `-2 - $i` is the entry before the insertion point: the latest transition at or before the moment.
- `.o[…]` is the offset in force from that transition on.

```jq
["2026-01-15 12:00:00", "2026-07-15 12:00:00", "2026-03-08 06:59:59", "2026-03-08 07:00:00"]
| map({utc: ., offset_hours: (parse_ts | tz_offset("America/Detroit") / 3600)})
```

```json
[
  {"utc": "2026-01-15 12:00:00", "offset_hours": -5},
  {"utc": "2026-07-15 12:00:00", "offset_hours": -4},
  {"utc": "2026-03-08 06:59:59", "offset_hours": -5},
  {"utc": "2026-03-08 07:00:00", "offset_hours": -4}
]
```

Winter is five hours behind UTC and summer four. The last two rows are the second before and the moment of the 2026 spring change, 07:00 UTC, which is 02:00 local.

## local_time

`local_time/1`, lines 151 to 155:

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

Input: a moment. Output: the local clock reading as an object.

- `tz_offset($tz) as $o | (. + $o) as $l`: add the offset, giving a number that, read as if it were UTC, shows the local clock.
- `$l | floor | gmtime`: jq's own breakdown of a moment into year, month (0 to 11), day, hour, minute, second, weekday (0 is Sunday), day of year. `floor` first, because the fraction is handled separately.
- The object: `month` is `$g[1] + 1`; `second` gets the fraction back (`$l - ($l | floor)`); `offset_s` and `local_epoch` are kept so a caller can go back to UTC or compare local times as numbers.

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

13:05 UTC in August is 09:05 in Detroit; weekday 3 is Wednesday.

## hours_between

`hours_between/2`, lines 158 to 159:

```jq
# hours from epoch a to epoch b, exact (no rounding); null when either is null
def hours_between(a; b): (a) as $a | (b) as $b
  | if $a == null or $b == null then null else ($b - $a) / 3600 end;
```

`(b - a) / 3600`, or null when either side is null. `(a) as $a | (b) as $b` evaluates each expression once.

```jq
[{o: 0, r: 5400}, {o: 0, r: null}] | map(hours_between(.o; .r))
```

```json
[1.5,null]
```
