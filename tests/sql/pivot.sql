-- pivot.sql: one row per id with columns a, b, c holding sum(v); a missing pair is null; col x is not asked for.
WITH t AS (FROM read_json('tests/fixtures/long.json', columns = {id: 'INTEGER', col: 'VARCHAR', v: 'INTEGER'}))
SELECT list({id: id, a: a, b: b, c: c} ORDER BY id) AS result
FROM (PIVOT (FROM t WHERE col IN ('a', 'b', 'c')) ON col IN ('a', 'b', 'c') USING sum(v) GROUP BY id);
