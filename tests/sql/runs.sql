-- runs.sql: run-length encoding of s over the whole table in file order: value, 0-based start, n.
WITH e AS (FROM read_json('tests/fixtures/events.json', columns = {i: 'INTEGER', u: 'VARCHAR', t: 'INTEGER', s: 'VARCHAR'})),
     m AS (SELECT *, CASE WHEN s IS DISTINCT FROM lag(s) OVER (ORDER BY i) THEN 1 ELSE 0 END AS is_new FROM e),
     g AS (SELECT *, sum(is_new) OVER (ORDER BY i) AS blk FROM m)
SELECT list({"value": v, "start": st, n: n} ORDER BY st) AS result
FROM (SELECT blk, any_value(s) AS v, min(i) - 1 AS st, count(*) AS n FROM g GROUP BY blk);
