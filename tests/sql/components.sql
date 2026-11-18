-- components.sql: connected groups with edges read both ways; each node labelled with the smallest node of its group.
WITH RECURSIVE e AS (FROM read_json('tests/fixtures/edges.json', columns = {a: 'INTEGER', b: 'INTEGER'})),
     u AS (SELECT a, b FROM e UNION SELECT b, a FROM e),
     r(node, seed) AS (SELECT a, a FROM u UNION SELECT u.b, r.seed FROM r JOIN u ON r.node = u.a)
SELECT list({node: node, component: comp} ORDER BY node) AS result FROM (SELECT node, min(seed) AS comp FROM r GROUP BY node);
