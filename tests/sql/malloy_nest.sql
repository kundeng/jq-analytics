-- malloy_nest.sql: Malloy's `nest:` as SQL. One row per region with its revenue, and inside it a
-- sub-table of the region's two best products by revenue (ties broken by product name).
WITH p AS (SELECT region, product, sum(qty * price) AS rev
           FROM read_json('tests/fixtures/sales.json') GROUP BY region, product),
r AS (SELECT region, sum(rev) AS revenue,
             list({product: product, rev: rev} ORDER BY rev DESC, product)[1:2] AS top_products
      FROM p GROUP BY region)
SELECT to_json(list({region: region, revenue: revenue, top_products: top_products} ORDER BY region)) AS result FROM r;
