-- reachable.sql: nodes reachable from 1 and from 7 along directed edges a -> b (recursive), the start left out, sorted.
WITH RECURSIVE e AS (FROM read_json('tests/fixtures/edges.json', columns = {a: 'INTEGER', b: 'INTEGER'})),
     r(start, node) AS (SELECT a, b FROM e WHERE a IN (1, 7) UNION SELECT r.start, e.b FROM r JOIN e ON r.node = e.a)
SELECT {from_1: (SELECT list(node ORDER BY node) FROM r WHERE start = 1 AND node <> 1),
        from_7: (SELECT list(node ORDER BY node) FROM r WHERE start = 7 AND node <> 7)} AS result;
