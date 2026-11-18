-- unpivot.sql: columns a, b, c of wide.json into rows {id, col, val}, nulls kept.
WITH t AS (FROM read_json('tests/fixtures/wide.json', columns = {id: 'INTEGER', a: 'INTEGER', b: 'INTEGER', c: 'INTEGER'})),
     u AS (FROM t UNPIVOT INCLUDE NULLS (val FOR col IN (a, b, c)))
SELECT list({id: id, col: col, val: val} ORDER BY id, col) AS result FROM u;
