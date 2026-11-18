-- diff_tables.sql: keys added, removed or changed between two versions, with the fields that differ (null-safe).
WITH o AS (FROM read_json('tests/fixtures/versions_old.json', columns = {id: 'INTEGER', a: 'INTEGER', b: 'VARCHAR', c: 'DOUBLE'})),
     n AS (FROM read_json('tests/fixtures/versions_new.json', columns = {id: 'INTEGER', a: 'INTEGER', b: 'VARCHAR', c: 'DOUBLE'})),
     j AS (SELECT coalesce(n.id, o.id) AS id, n.id IS NULL AS gone, o.id IS NULL AS fresh,
                  (CASE WHEN n.a IS DISTINCT FROM o.a THEN ['a'] ELSE []::VARCHAR[] END)
                  || (CASE WHEN n.b IS DISTINCT FROM o.b THEN ['b'] ELSE []::VARCHAR[] END)
                  || (CASE WHEN n.c IS DISTINCT FROM o.c THEN ['c'] ELSE []::VARCHAR[] END) AS fields
           FROM n FULL JOIN o ON n.id = o.id)
SELECT list({key: id, change: CASE WHEN fresh THEN 'added' WHEN gone THEN 'removed' ELSE 'changed' END,
             fields: CASE WHEN fresh OR gone THEN []::VARCHAR[] ELSE fields END} ORDER BY id) AS result
FROM j WHERE fresh OR gone OR len(fields) > 0;
