-- join_inner.sql: JOIN of left.json and right.json on k; null keys never match.
WITH l AS (FROM read_json('tests/fixtures/left.json', columns = {id: 'INTEGER', k: 'VARCHAR', lv: 'INTEGER'})),
     r AS (FROM read_json('tests/fixtures/right.json', columns = {ri: 'INTEGER', k: 'VARCHAR', rv: 'VARCHAR'}))
SELECT list({id: l.id, lk: l.k, lv: l.lv, ri: r.ri, rv: r.rv} ORDER BY l.id NULLS LAST, r.ri) AS result
FROM l JOIN r ON l.k = r.k;
