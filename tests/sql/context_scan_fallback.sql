-- context_scan_fallback.sql: share of region when the region level is not one of the report's levels
WITH f AS (SELECT * FROM read_json('tests/fixtures/sales.json'))
SELECT to_json(list({region: region, product: product,
  share_of_region: round(revenue / (SELECT sum(qty * price) FROM f WHERE f.region = g.region), 4),
  months_to_feb: (SELECT count(*) FROM f WHERE f.region = g.region AND f.product = g.product AND f.month >= '2026-01' AND f.month <= '2026-02')}
  ORDER BY region, product)) AS result
FROM (SELECT region, product, sum(qty * price) AS revenue FROM f GROUP BY region, product) g;
