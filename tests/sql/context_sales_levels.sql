-- context_sales_levels.sql: revenue at four hand-picked levels, with shares and one product's revenue in the same region
WITH f AS (SELECT * FROM read_json('tests/fixtures/sales.json')),
g AS (SELECT region, product, grouping(region) AS gr, grouping(product) AS gp, sum(qty * price) AS revenue
      FROM f GROUP BY GROUPING SETS ((region, product), (region), (product), ()))
SELECT to_json(list({region: region, product: product, revenue: revenue,
  share_of_region: round(revenue / (SELECT sum(qty * price) FROM f WHERE gr = 1 OR f.region = g.region), 4),
  share_of_all: round(revenue / (SELECT sum(qty * price) FROM f), 4),
  a_revenue: (SELECT sum(qty * price) FROM f WHERE (gr = 1 OR f.region = g.region) AND f.product = 'A')}
  ORDER BY CASE WHEN gr = 0 AND gp = 0 THEN 0 WHEN gr = 0 THEN 1 WHEN gp = 0 THEN 2 ELSE 3 END, region, product)) AS result FROM g;
