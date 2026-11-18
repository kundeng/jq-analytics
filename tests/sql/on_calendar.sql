-- on_calendar.sql: revenue by region and month, the previous calendar month's (null when it has no rows), and the running total.
WITH f AS (FROM read_json('tests/fixtures/sales_gap.json', columns = {region: 'VARCHAR', month: 'VARCHAR', amount: 'BIGINT'})),
     g AS (SELECT region, month, sum(amount) AS revenue FROM f GROUP BY region, month)
SELECT list({region: region, month: month, revenue: revenue,
  prior: (SELECT sum(amount) FROM f WHERE f.region = g.region
          AND f.month = strftime(strptime(g.month || '-01', '%Y-%m-%d') - INTERVAL 1 MONTH, '%Y-%m')),
  to_date: (SELECT sum(amount) FROM f WHERE f.region = g.region AND f.month <= g.month)} ORDER BY region, month) AS result FROM g;
