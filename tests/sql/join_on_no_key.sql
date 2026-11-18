-- join_on_no_key.sql: inner join with no equality part: every order against every band, kept when amount in [lo, hi).
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), r AS (FROM read_json('tests/fixtures/bands.json', columns = {bi: 'INTEGER', region: 'VARCHAR', lo: 'INTEGER', hi: 'INTEGER', band: 'VARCHAR'}))
SELECT list({id: l.id, bi: r.bi} ORDER BY l.id, r.bi) AS result
FROM l JOIN r ON l.amount >= r.lo AND l.amount < r.hi;
