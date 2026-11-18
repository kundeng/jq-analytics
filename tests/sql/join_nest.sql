-- join_nest.sql: every order once, with the names of its matching bands as a list in band order (empty when none).
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), r AS (FROM read_json('tests/fixtures/bands.json', columns = {bi: 'INTEGER', region: 'VARCHAR', lo: 'INTEGER', hi: 'INTEGER', band: 'VARCHAR'}))
SELECT list({id: id, bands: bands} ORDER BY id) AS result FROM (
  SELECT l.id, coalesce(list(r.band ORDER BY r.bi) FILTER (WHERE r.bi IS NOT NULL), []) AS bands
  FROM l LEFT JOIN r ON l.region = r.region AND l.amount >= r.lo AND l.amount < r.hi GROUP BY l.id);
