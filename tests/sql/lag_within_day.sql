-- real_lag_within_day.sql: within each America/Detroit local opening date, ordered by opened then file
-- position, the hours since the previous incident opened (lag); over all gaps: partitions, gaps counted,
-- interpolated median and nearest-rank p90, rounded to 0.0001; and the row number of the last row of the busiest day.
WITH d AS (SELECT *, strftime(opened AT TIME ZONE 'America/Detroit', '%Y-%m-%d') AS day FROM incidents),
     g AS (SELECT day,
                  (epoch(opened) - epoch(lag(opened, 1) OVER (PARTITION BY day ORDER BY opened, i))) / 3600 AS gap,
                  row_number() OVER (PARTITION BY day ORDER BY opened, i) AS rn
           FROM d)
SELECT {days: count(DISTINCT day), gaps: count(gap), median: round(quantile_cont(gap, 0.5), 4),
        p90: round(quantile_disc(gap, 0.9), 4), max_rn: max(rn)} AS result FROM g;
