-- dag_paths.sql: over an acyclic graph, every path from node 0 enumerated: the lowest total weight and the fewest
-- edges to each node (null when it cannot be reached), and each node's level (the longest path into it from any source).
WITH RECURSIVE e AS (FROM read_json('tests/fixtures/dag.json', columns = {a: 'INTEGER', b: 'INTEGER', w: 'INTEGER'})),
     n AS (SELECT a AS node FROM e UNION SELECT b FROM e),
     p(node, cost, len) AS (SELECT 0, 0, 0 UNION ALL SELECT e.b, p.cost + e.w, p.len + 1 FROM p JOIN e ON e.a = p.node),
     best AS (SELECT node, min(cost) AS cost, min(len) AS hops FROM p GROUP BY node),
     q(node, len) AS (SELECT node, 0 FROM n WHERE node NOT IN (SELECT b FROM e) UNION ALL SELECT e.b, q.len + 1 FROM q JOIN e ON e.a = q.node),
     lv AS (SELECT node, max(len) AS level FROM q GROUP BY node)
SELECT {costs: (SELECT list({node: n.node, cost: best.cost, hops: best.hops} ORDER BY n.node) FROM n LEFT JOIN best USING (node)),
        levels: (SELECT list({node: node, level: level} ORDER BY node) FROM lv)} AS result;
