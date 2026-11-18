-- join_asof_max_age.sql: as-of join of trades to quotes, the match dropped when the quote is more than 3 older.
WITH l AS (FROM read_json('tests/fixtures/trades.json', columns = {id: 'INTEGER', k: 'VARCHAR', t: 'INTEGER'})),
     r AS (FROM read_json('tests/fixtures/quotes.json', columns = {qi: 'INTEGER', k: 'VARCHAR', t: 'INTEGER', q: 'INTEGER'}))
SELECT list({id: l.id, qi: CASE WHEN l.t - r.t <= 3 THEN r.qi END, q: CASE WHEN l.t - r.t <= 3 THEN r.q END} ORDER BY l.id) AS result
FROM l ASOF LEFT JOIN r ON l.k = r.k AND l.t >= r.t;
