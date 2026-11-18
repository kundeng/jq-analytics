-- unnest.sql: one row per tag; a ticket with an empty or missing tag list gives no row (UNNEST).
WITH t AS (FROM read_json('tests/fixtures/tickets.json', columns = {id: 'VARCHAR', tags: 'VARCHAR[]'}))
SELECT list({id: id, tag: tag} ORDER BY id, pos) AS result
FROM (SELECT id, unnest(tags) AS tag, generate_subscripts(tags, 1) AS pos FROM t);
