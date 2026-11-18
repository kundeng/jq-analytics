-- real_resolved_summary.sql: resolved hours: counts, mean, nearest-rank quartiles and p90, max
-- (each rounded to 0.01 after computing), and counts within 1 h, 1 day, 7 days on exact hours.
SELECT {incidents: count(*), unresolved: count(*) FILTER (WHERE resolved IS NULL), resolved: count(hours),
        mean: round(avg(hours), 2), p25: round(quantile_disc(hours, 0.25), 2), p50: round(quantile_disc(hours, 0.5), 2),
        p75: round(quantile_disc(hours, 0.75), 2), p90: round(quantile_disc(hours, 0.9), 2), max: round(max(hours), 2),
        within_1h: count(*) FILTER (WHERE hours <= 1), within_1d: count(*) FILTER (WHERE hours <= 24),
        within_7d: count(*) FILTER (WHERE hours <= 168)} AS result
FROM incidents;
