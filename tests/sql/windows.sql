-- windows.sql: per partition g ordered by t then input order i, ROWS frames:
-- row_number, lag(v, 1), running sum of v, rank by t, mean of v over this and the previous row.
WITH t AS (FROM read_json('tests/fixtures/window.json', columns = {i: 'INTEGER', g: 'VARCHAR', t: 'INTEGER', v: 'INTEGER'}))
SELECT list({i: i, rn: rn, lag1: lag1, rs: rs, rk: rk, mm: mm} ORDER BY i) AS result FROM (
  SELECT i,
         row_number() OVER w AS rn,
         lag(v, 1) OVER w AS lag1,
         sum(v) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rs,
         rank() OVER (PARTITION BY g ORDER BY t) AS rk,
         avg(v) OVER (w ROWS BETWEEN 1 PRECEDING AND CURRENT ROW) AS mm
  FROM t WINDOW w AS (PARTITION BY g ORDER BY t, i));
