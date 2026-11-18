-- unnest_outer.sql: as unnest.sql, but a ticket with no tags is kept once with a null tag (LEFT JOIN LATERAL).
WITH t AS (FROM read_json('tests/fixtures/tickets.json', columns = {id: 'VARCHAR', tags: 'VARCHAR[]'}))
SELECT list({id: id, tag: tag} ORDER BY id, pos) AS result
FROM (SELECT t.id, u.tag, u.pos FROM t LEFT JOIN LATERAL
        (SELECT unnest(t.tags) AS tag, generate_subscripts(t.tags, 1) AS pos) u ON true);
