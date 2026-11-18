-- round_to.sql: DuckDB round(x, 2) and round(x, 0) on doubles, in input order.
WITH t AS (FROM read_json('tests/fixtures/round.json', columns = {i: 'INTEGER', x: 'DOUBLE'}))
SELECT list({i: i, r2: round(x, 2), r0: round(x, 0)} ORDER BY i) AS result FROM t;
