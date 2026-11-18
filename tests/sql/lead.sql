-- lead.sql: the next row's v within each group in t order, ties in input order; null at a group's end.
WITH w AS (FROM read_json('tests/fixtures/window.json', columns = {i: 'INTEGER', g: 'VARCHAR', t: 'INTEGER', v: 'INTEGER'}))
SELECT list({i: i, lead1: lead1, lead2: lead2} ORDER BY i) AS result
FROM (SELECT i, lead(v, 1) OVER (PARTITION BY g ORDER BY t, i) AS lead1, lead(v, 2) OVER (PARTITION BY g ORDER BY t, i) AS lead2 FROM w);
