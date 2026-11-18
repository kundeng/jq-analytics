WITH f AS (SELECT strftime(opened_at::TIMESTAMP, '%Y-%m') AS month, state
           FROM read_json('tests/fixtures/made_up_incidents.json', columns = {opened_at: 'VARCHAR', state: 'VARCHAR'})),
g AS (SELECT month, state, count(*) AS requests FROM f GROUP BY ROLLUP (month, state))
SELECT to_json(list({month: month, state: state, requests: requests,
  share_of_month: CASE WHEN month IS NULL THEN NULL ELSE round(requests / (SELECT count(*) FROM f WHERE f.month = g.month), 4) END}
  ORDER BY month NULLS LAST, state NULLS LAST)) AS result FROM g;
