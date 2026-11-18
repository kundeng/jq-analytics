-- real_day_volume_join.sql: each incident joined to the count of incidents on its America/Detroit
-- opening date; incidents on days with 100 or more against the rest: n and mean resolved hours.
WITH d AS (SELECT *, strftime(opened AT TIME ZONE 'America/Detroit', '%Y-%m-%d') AS day FROM incidents),
     v AS (SELECT day, count(*) AS n FROM d GROUP BY day),
     j AS (SELECT d.hours, v.n >= 100 AS busy FROM d JOIN v ON d.day = v.day)
SELECT {busy: (SELECT {n: count(*), mean: round(avg(hours), 4)} FROM j WHERE busy),
        quiet: (SELECT {n: count(*), mean: round(avg(hours), 4)} FROM j WHERE NOT busy)} AS result;
