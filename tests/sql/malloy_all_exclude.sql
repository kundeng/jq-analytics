-- malloy_all_exclude.sql: Malloy's ungrouped aggregates as SQL window sums over the grouped rows.
--   all(revenue)            -> total over every row
--   all(revenue, region)    -> keep only the region grouping
--   exclude(revenue, region) -> drop the region grouping, keep product
WITH g AS (SELECT region, product, sum(qty * price) AS revenue
           FROM read_json('tests/fixtures/sales.json') GROUP BY region, product),
w AS (SELECT *, sum(revenue) OVER () AS total,
                sum(revenue) OVER (PARTITION BY region) AS region_total,
                sum(revenue) OVER (PARTITION BY product) AS product_total FROM g)
SELECT to_json(list({region: region, product: product, revenue: revenue, total: total,
                     region_total: region_total, product_total: product_total} ORDER BY region, product)) AS result FROM w;
