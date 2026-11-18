-- parse_and_local.sql: each string as a UTC instant (no offset means UTC), its epoch, and its wall
-- clock, weekday (0 = Sunday) and UTC offset in America/Detroit and Europe/London.
SET TimeZone = 'UTC';
WITH t AS (FROM read_json('tests/fixtures/ts.json', columns = {i: 'INTEGER', s: 'VARCHAR'})),
     p AS (SELECT i, s::TIMESTAMPTZ AS ts FROM t),
     l AS (SELECT i, ts, ts AT TIME ZONE 'America/Detroit' AS det, ts AT TIME ZONE 'Europe/London' AS lon FROM p)
SELECT list({i: i, epoch: epoch(ts),
             det: {date: strftime(det, '%Y-%m-%d'), hour: hour(det), minute: minute(det), weekday: dayofweek(det),
                   offset_s: epoch(det) - epoch(ts)},
             lon: {date: strftime(lon, '%Y-%m-%d'), hour: hour(lon), weekday: dayofweek(lon), offset_s: epoch(lon) - epoch(ts)}}
            ORDER BY i) AS result FROM l;
