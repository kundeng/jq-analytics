-- lookup.sql: each order with its group's name; null when the order has no gid or the gid is unknown.
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), d AS (FROM read_json('tests/fixtures/groups.json', columns = {gid: 'VARCHAR', gname: 'VARCHAR'}))
SELECT list({id: l.id, gname: d.gname} ORDER BY l.id) AS result FROM l LEFT JOIN d ON l.gid = d.gid;
