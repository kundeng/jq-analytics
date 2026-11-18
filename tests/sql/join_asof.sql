-- join_asof.sql: each trade with the latest quote of the same k at or before its t (left outer).
WITH l AS (FROM read_json('tests/fixtures/trades.json', columns = {id: 'INTEGER', k: 'VARCHAR', t: 'INTEGER'})),
     r AS (FROM read_json('tests/fixtures/quotes.json', columns = {qi: 'INTEGER', k: 'VARCHAR', t: 'INTEGER', q: 'INTEGER'}))
SELECT list({id: l.id, qi: r.qi, q: r.q} ORDER BY l.id) AS result
FROM l ASOF LEFT JOIN r ON l.k = r.k AND l.t >= r.t;
