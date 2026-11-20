-- the CSV fixture as DuckDB reads it: header, every value as text, an empty field as "" (not null)
SELECT to_json(list(r)) AS result
FROM (SELECT * FROM read_csv('tests/fixtures/requests.csv', header = true, all_varchar = true, nullstr = '\N', quote = '"', escape = '"')) r;
