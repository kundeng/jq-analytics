-- sessions.sql: per u ordered by t then i, a new session when the gap to the previous event exceeds 10.
WITH e AS (FROM read_json('tests/fixtures/events.json', columns = {i: 'INTEGER', u: 'VARCHAR', t: 'INTEGER', s: 'VARCHAR'})),
     m AS (SELECT *, CASE WHEN lag(t) OVER w IS NULL OR t - lag(t) OVER w > 10 THEN 1 ELSE 0 END AS is_new, min(i) OVER (PARTITION BY u) AS first_i
           FROM e WINDOW w AS (PARTITION BY u ORDER BY t, i)),
     g AS (SELECT *, sum(is_new) OVER (PARTITION BY u ORDER BY t, i) AS session FROM m)
SELECT list({u: u, session: session, "start": st, "end": en, events: n} ORDER BY first_i, session) AS result
FROM (SELECT u, first_i, session, min(t) AS st, max(t) AS en, count(*) AS n FROM g GROUP BY u, first_i, session);
