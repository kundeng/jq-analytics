-- min_max_nonnull.sql: per group g, the least and greatest x and the row id i holding each, nulls
-- skipped as SQL's MIN, MAX, ARG_MIN and ARG_MAX skip them; a group of only nulls gives nulls.
WITH t AS (FROM read_json('tests/fixtures/nums.json', columns = {i: 'INTEGER', g: 'VARCHAR', x: 'DOUBLE'})),
     s AS (SELECT g, min(x) AS min, max(x) AS max, arg_min(i, x) AS i_min, arg_max(i, x) AS i_max FROM t GROUP BY g)
SELECT list(s ORDER BY g) AS result FROM s;
