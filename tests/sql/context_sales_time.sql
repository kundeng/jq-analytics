-- context_sales_time.sql: revenue by region and month with the previous month that has rows anywhere, and a running total
WITH f AS (SELECT * FROM read_json('tests/fixtures/sales.json')),
g AS (SELECT region, month, grouping(region) AS gr, grouping(month) AS gm, sum(qty * price) AS revenue FROM f GROUP BY ROLLUP (region, month))
SELECT to_json(list({region: region, month: month, revenue: revenue,
  prior: CASE WHEN gm = 1 THEN NULL ELSE (SELECT sum(qty * price) FROM f WHERE f.region = g.region
           AND f.month = (SELECT max(f2.month) FROM f f2 WHERE f2.month < g.month)) END,
  to_date: (SELECT sum(qty * price) FROM f WHERE (gr = 1 OR f.region = g.region) AND (gm = 1 OR f.month <= g.month))}
  ORDER BY gr, gm, region, month)) AS result FROM g;
