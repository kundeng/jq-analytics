Four definitions that turn a moment (seconds since 1970 UTC) into a local clock reading. They read the zone tables at the top of the file, `tz_rules`, which a script generates from the tzdata package: for each zone, `t` is the sorted list of moments at which an offset starts and `o` the offset, in seconds east of UTC, that starts there. The first `t` of every zone is a very large negative number, so every moment has an entry at or before it. Seven zones are included, 1970 to 2100.

No function here reads the machine's own time zone, so a result does not depend on where the program runs.

## tz/1
<!-- code: 8379f498 -->

`tz_rules[$name] // error(…)`: the rules of one zone, or an error naming the zone. `//` gives the right-hand side when the left is null, which is what a missing key gives.

It exists as a separate step because `tz_rules` is a large literal that jq builds again each time it is mentioned. A program that converts many rows calls `tz` once, keeps the result in a variable, and passes that to the functions below, which accept either a name or this object.

```jq run
(tz("America/Detroit") | {transitions: (.t | length), first_offset: .o[0], fields: keys}),
(try tz("Mars/Olympus") catch .)
```

## tz_offset/1
<!-- code: 5a4c7e5a -->

Input: a moment. Output: the zone's offset from UTC at that moment, in seconds.

- `$tz | if type == "string" then tz(.) else . end`: a name is looked up; an object is taken to be the rules already.
- `(.t | bsearch($e)) as $i`: position of the moment among the transitions. Found exactly: that position. Otherwise `bsearch` gives `-1 - (insertion point)`, and `-2 - $i` is the entry before the insertion point: the latest transition at or before the moment.
- `.o[…]` is the offset in force from that transition on.

```jq run
["2026-01-15 12:00:00", "2026-07-15 12:00:00", "2026-03-08 06:59:59", "2026-03-08 07:00:00"]
| map({utc: ., offset_hours: (parse_ts | tz_offset("America/Detroit") / 3600)})
```

Winter is five hours behind UTC and summer four. The last two rows are the second before and the moment of the 2026 spring change, 07:00 UTC, which is 02:00 local.

## local_time/1
<!-- code: c634bf0d -->

Input: a moment. Output: the local clock reading as an object.

- `tz_offset($tz) as $o | (. + $o) as $l`: add the offset, giving a number that, read as if it were UTC, shows the local clock.
- `$l | floor | gmtime`: jq's own breakdown of a moment into year, month (0 to 11), day, hour, minute, second, weekday (0 is Sunday), day of year. `floor` first, because the fraction is handled separately.
- The object: `month` is `$g[1] + 1`; `second` gets the fraction back (`$l - ($l | floor)`); `offset_s` and `local_epoch` are kept so a caller can go back to UTC or compare local times as numbers.

```jq run
"2026-08-12 13:05:00.5" | parse_ts | local_time("America/Detroit")
```

13:05 UTC in August is 09:05 in Detroit; weekday 3 is Wednesday.

## hours_between/2
<!-- code: ecb9b38e -->

`(b - a) / 3600`, or null when either side is null. `(a) as $a | (b) as $b` evaluates each expression once.

```jq run
[{o: 0, r: 5400}, {o: 0, r: null}] | map(hours_between(.o; .r))
```
