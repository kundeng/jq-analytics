-- merge_intervals.sql: per key, overlapping or touching intervals merged (gaps and islands).
WITH x AS (FROM read_json('tests/fixtures/spans.json', columns = {k: 'VARCHAR', s: 'BIGINT', e: 'BIGINT'})),
     m AS (SELECT *, max(e) OVER (PARTITION BY k ORDER BY s, e ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_end FROM x),
     g AS (SELECT *, sum(CASE WHEN prev_end IS NULL OR s > prev_end THEN 1 ELSE 0 END) OVER (PARTITION BY k ORDER BY s, e) AS island FROM m)
SELECT list({key: k, "start": s0, "end": e1, merged: n} ORDER BY k, s0) AS result
FROM (SELECT k, island, min(s) AS s0, max(e) AS e1, count(*) AS n FROM g GROUP BY k, island);
