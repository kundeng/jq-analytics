-- hops.sql: the fewest edges from node 1 to every node it reaches along a -> b, itself at 0.
WITH RECURSIVE e AS (FROM read_json('tests/fixtures/edges.json', columns = {a: 'INTEGER', b: 'INTEGER'})),
     r(node, d) AS (SELECT 1, 0 UNION SELECT e.b, r.d + 1 FROM r JOIN e ON r.node = e.a WHERE r.d < 20)
SELECT list({node: node, hops: h} ORDER BY node) AS result FROM (SELECT node, min(d) AS h FROM r GROUP BY node);
