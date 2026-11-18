-- transitions.sql: per u ordered by t then i, each change of state: from, to, at.
WITH e AS (FROM read_json('tests/fixtures/events.json', columns = {i: 'INTEGER', u: 'VARCHAR', t: 'INTEGER', s: 'VARCHAR'})),
     m AS (SELECT *, lag(s) OVER w AS prev, min(i) OVER (PARTITION BY u) AS first_i FROM e WINDOW w AS (PARTITION BY u ORDER BY t, i))
SELECT list({u: u, "from": prev, "to": s, "at": t} ORDER BY first_i, t, i) AS result FROM m WHERE prev IS NOT NULL AND prev <> s;
