WITH f AS (SELECT strftime(opened, '%Y-%m') AS month, strftime(opened, '%Y-%m-%d') AS day, strftime(resolved, '%Y-%m-%d') AS resolved_day, hours FROM incidents),
g AS (SELECT month, count(*) AS requests, round(count(*) / (SELECT count(*) FROM f), 4) AS share_of_all,
  round(count(*) FILTER (hours <= 24) / count(*), 4) AS within_day, round(median(hours), 2) AS median_hours, max(day) AS last_day
  FROM f GROUP BY ROLLUP (month))
SELECT to_json(list({month: month, requests: requests, share_of_all: share_of_all, within_day: within_day,
  prior_within_day: CASE WHEN month IS NULL THEN NULL ELSE (SELECT g2.within_day FROM g g2 WHERE g2.month = (SELECT max(g3.month) FROM g g3 WHERE g3.month < g.month)) END,
  median_hours: median_hours,
  requests_to_date: (SELECT count(*) FROM f WHERE g.month IS NULL OR f.month <= g.month),
  open_at_end: (SELECT count(*) FROM f WHERE f.day <= g.last_day AND (f.resolved_day IS NULL OR f.resolved_day > g.last_day))} ORDER BY month NULLS LAST)) AS result FROM g;
