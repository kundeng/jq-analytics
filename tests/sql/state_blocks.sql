-- state_blocks.sql: per u ordered by t then i, consecutive equal states merged (gaps and islands):
-- start = first t of the block, end = start of the next block, duration, events merged.
WITH e AS (FROM read_json('tests/fixtures/events.json', columns = {i: 'INTEGER', u: 'VARCHAR', t: 'INTEGER', s: 'VARCHAR'})),
     m AS (SELECT *, CASE WHEN s IS DISTINCT FROM lag(s) OVER w THEN 1 ELSE 0 END AS is_new FROM e WINDOW w AS (PARTITION BY u ORDER BY t, i)),
     g AS (SELECT *, sum(is_new) OVER (PARTITION BY u ORDER BY t, i) AS blk, min(i) OVER (PARTITION BY u) AS first_i FROM m),
     b AS (SELECT u, first_i, blk, any_value(s) AS state, min(t) AS "start", count(*) AS events FROM g GROUP BY u, first_i, blk),
     c AS (SELECT *, lead("start") OVER (PARTITION BY u ORDER BY blk) AS "end" FROM b)
SELECT list({u: u, state: state, "start": "start", "end": "end", duration: "end" - "start", events: events} ORDER BY first_i, blk) AS result FROM c;
