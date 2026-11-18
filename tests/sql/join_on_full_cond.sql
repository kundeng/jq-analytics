-- join_on_full_cond.sql: FULL JOIN on region plus amount in [lo, hi); unmatched bands follow, in band order.
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), r AS (FROM read_json('tests/fixtures/bands.json', columns = {bi: 'INTEGER', region: 'VARCHAR', lo: 'INTEGER', hi: 'INTEGER', band: 'VARCHAR'}))
SELECT list({id: l.id, bi: r.bi} ORDER BY l.id NULLS LAST, r.bi) AS result
FROM l FULL JOIN r ON l.region = r.region AND l.amount >= r.lo AND l.amount < r.hi;
