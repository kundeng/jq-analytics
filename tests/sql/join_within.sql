-- join_within.sql: for each query, the holder whose interval [start, end) contains t; a null end is still open.
WITH q AS (FROM read_json('tests/fixtures/lease_queries.json', columns = {q: 'INTEGER', res: 'VARCHAR', t: 'BIGINT'})),
     i AS (FROM read_json('tests/fixtures/lease_intervals.json', columns = {resource: 'VARCHAR', holder: 'VARCHAR', "start": 'BIGINT', "end": 'BIGINT'}))
SELECT list({q: q.q, holder: i.holder} ORDER BY q.q) AS result
FROM q LEFT JOIN i ON i.resource = q.res AND i."start" <= q.t AND (i."end" IS NULL OR q.t < i."end");
