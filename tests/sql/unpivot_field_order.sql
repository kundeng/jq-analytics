-- unpivot_field_order.sql: columns a, m, z of wide_unsorted.json into rows {id, col, val}, nulls kept,
-- ordered by id and then column name (the library sorts field names so every engine agrees).
WITH t AS (FROM read_json('tests/fixtures/wide_unsorted.json', columns = {id: 'INTEGER', z: 'INTEGER', a: 'INTEGER', m: 'INTEGER'})),
     u AS (FROM t UNPIVOT INCLUDE NULLS (val FOR col IN (a, m, z)))
SELECT list({id: id, col: col, val: val} ORDER BY id, col) AS result FROM u;
