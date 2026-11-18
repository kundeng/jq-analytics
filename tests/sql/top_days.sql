-- real_top_days.sql: incidents per America/Detroit local opening date, five largest (ties by date).
WITH d AS (SELECT strftime(opened AT TIME ZONE 'America/Detroit', '%Y-%m-%d') AS day FROM incidents),
     c AS (SELECT day, count(*) AS n FROM d GROUP BY day ORDER BY n DESC, day LIMIT 5)
SELECT list({day: day, n: n} ORDER BY n DESC, day) AS result FROM c;
