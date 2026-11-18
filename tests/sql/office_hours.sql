-- real_office_hours.sql: resolved incidents split by whether opened falls Monday to Friday 08:00 to
-- 16:59 America/Detroit; n, nearest-rank median and p90 hours per side; resolved count by local hour.
WITH r AS (SELECT *, opened AT TIME ZONE 'America/Detroit' AS ol, resolved AT TIME ZONE 'America/Detroit' AS rl
           FROM incidents WHERE resolved IS NOT NULL),
     s AS (SELECT *, dayofweek(ol) BETWEEN 1 AND 5 AND hour(ol) BETWEEN 8 AND 16 AS in_hours FROM r),
     side AS (SELECT in_hours, {n: count(*), median: round(quantile_disc(hours, 0.5), 2), p90: round(quantile_disc(hours, 0.9), 2)} AS v
              FROM s GROUP BY in_hours),
     by_hour AS (SELECT hour(rl) AS hour, count(*) AS n FROM s GROUP BY 1)
SELECT {inside: (SELECT v FROM side WHERE in_hours), outside: (SELECT v FROM side WHERE NOT in_hours),
        by_resolved_hour: (SELECT list({hour: hour, n: n} ORDER BY hour) FROM by_hour)} AS result;
