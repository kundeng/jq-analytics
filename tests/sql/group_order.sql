-- group_order.sql: groups of g in order of their first row (smallest i), null key as one group; n and sum of x.
WITH t AS (FROM read_json('tests/fixtures/order.json', columns = {i: 'INTEGER', g: 'VARCHAR', x: 'INTEGER'})),
     s AS (SELECT g, min(i) AS first_i, count(*) AS n, sum(x) AS total FROM t GROUP BY g)
SELECT list({g: g, n: n, total: total} ORDER BY first_i) AS result FROM s;
