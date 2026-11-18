-- real_asof_last_resolution.sql: for each incident, the latest resolution in the same assignment group
-- at or before its opening (ASOF LEFT JOIN); hours between them; counts and nearest-rank median and p90.
WITH res AS (SELECT assignment_group, resolved FROM incidents WHERE resolved IS NOT NULL),
     j AS (SELECT (epoch(l.opened) - epoch(r.resolved)) / 3600 AS gap
           FROM incidents l ASOF LEFT JOIN res r ON l.assignment_group = r.assignment_group AND l.opened >= r.resolved)
SELECT {incidents: count(*), matched: count(gap), median: round(quantile_disc(gap, 0.5), 4), p90: round(quantile_disc(gap, 0.9), 4)} AS result
FROM j;
