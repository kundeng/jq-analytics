-- cast.sql: '' becomes NULL, then n as DOUBLE, t as a UTC instant (epoch seconds), b as BOOLEAN.
SET TimeZone = 'UTC';
WITH t AS (FROM read_json('tests/fixtures/raw_strings.json', columns = {i: 'INTEGER', n: 'VARCHAR', t: 'VARCHAR', b: 'VARCHAR'}))
SELECT list({i: i, n: nullif(n, '')::DOUBLE, t: epoch(nullif(t, '')::TIMESTAMPTZ), b: nullif(b, '')::BOOLEAN} ORDER BY i) AS result FROM t;
