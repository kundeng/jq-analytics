-- join_on_range_left.sql: LEFT JOIN on region equality plus amount in [lo, hi); null regions never match.
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), r AS (FROM read_json('tests/fixtures/bands.json', columns = {bi: 'INTEGER', region: 'VARCHAR', lo: 'INTEGER', hi: 'INTEGER', band: 'VARCHAR'}))
SELECT list({id: l.id, bi: r.bi, band: r.band} ORDER BY l.id, r.bi) AS result
FROM l LEFT JOIN r ON l.region = r.region AND l.amount >= r.lo AND l.amount < r.hi;
