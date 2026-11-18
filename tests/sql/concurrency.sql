-- concurrency.sql: the number of open intervals after each moment it changes; [s, e) counts from s up to, not including, e.
WITH x AS (FROM read_json('tests/fixtures/spans.json', columns = {k: 'VARCHAR', s: 'BIGINT', e: 'BIGINT'})),
     ch AS (SELECT s AS t, 1 AS d FROM x UNION ALL SELECT e, -1 FROM x),
     net AS (SELECT t, sum(d)::BIGINT AS n FROM ch GROUP BY t HAVING sum(d) != 0)
SELECT list({t: t, open: open} ORDER BY t) AS result
FROM (SELECT t, sum(n) OVER (ORDER BY t)::BIGINT AS open FROM net);
