-- fill_grid.sql: every site at every hour from the earliest to the latest; a missing pair gets requests = 0.
WITH d AS (FROM read_json('tests/fixtures/hourly.json', columns = {site: 'VARCHAR', hour: 'BIGINT', requests: 'BIGINT'})),
     grid AS (SELECT s.site, h.hour FROM (SELECT DISTINCT site FROM d) s,
                (SELECT unnest(generate_series((SELECT min(hour) FROM d), (SELECT max(hour) FROM d), 3600)) AS hour) h)
SELECT list({site: g.site, hour: g.hour, requests: coalesce(d.requests, 0)} ORDER BY g.site, g.hour) AS result
FROM grid g LEFT JOIN d ON d.site = g.site AND d.hour = g.hour;
