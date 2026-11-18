-- join_overlap.sql: shift and outage pairs on the same host whose half-open intervals [start, end) overlap.
WITH l AS (FROM read_json('tests/fixtures/shifts.json', columns = {sid: 'INTEGER', host: 'VARCHAR', "start": 'INTEGER', "end": 'INTEGER'})),
     r AS (FROM read_json('tests/fixtures/outages.json', columns = {oid: 'INTEGER', host: 'VARCHAR', ostart: 'INTEGER', oend: 'INTEGER'}))
SELECT list({sid: l.sid, oid: r.oid} ORDER BY l.sid, r.oid) AS result
FROM l JOIN r ON l.host = r.host AND l."start" < r.oend AND r.ostart < l."end";
