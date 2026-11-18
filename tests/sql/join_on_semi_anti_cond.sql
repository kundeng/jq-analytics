-- join_on_semi_anti_cond.sql: orders with at least one band of their region holding their amount, and those with none.
WITH l AS (FROM read_json('tests/fixtures/orders.json', columns = {id: 'INTEGER', region: 'VARCHAR', amount: 'INTEGER', gid: 'VARCHAR'})), r AS (FROM read_json('tests/fixtures/bands.json', columns = {bi: 'INTEGER', region: 'VARCHAR', lo: 'INTEGER', hi: 'INTEGER', band: 'VARCHAR'}))
SELECT {"semi": (SELECT list(id ORDER BY id) FROM l WHERE EXISTS (SELECT 1 FROM r WHERE l.region = r.region AND l.amount >= r.lo AND l.amount < r.hi)),
        "anti": (SELECT list(id ORDER BY id) FROM l WHERE NOT EXISTS (SELECT 1 FROM r WHERE l.region = r.region AND l.amount >= r.lo AND l.amount < r.hi))} AS result;
