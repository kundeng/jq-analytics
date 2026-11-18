-- join_semi_anti.sql: ids of left rows with a match (SEMI) and without one (ANTI); null keys never match.
WITH l AS (FROM read_json('tests/fixtures/left.json', columns = {id: 'INTEGER', k: 'VARCHAR', lv: 'INTEGER'})),
     r AS (FROM read_json('tests/fixtures/right.json', columns = {ri: 'INTEGER', k: 'VARCHAR', rv: 'VARCHAR'}))
SELECT {"semi": (SELECT list(id ORDER BY id) FROM l SEMI JOIN r ON l.k = r.k),
        "anti": (SELECT list(id ORDER BY id) FROM l ANTI JOIN r ON l.k = r.k)} AS result;
