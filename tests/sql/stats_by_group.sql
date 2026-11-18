-- stats_by_group.sql: per group g, count, sum, mean, variances, standard deviations, discrete and
-- continuous quantiles at eight p, and median, over x; nulls skipped by every aggregate.
WITH t AS (FROM read_json('tests/fixtures/nums.json', columns = {i: 'INTEGER', g: 'VARCHAR', x: 'DOUBLE'})),
     s AS (SELECT g, count(x) AS n, sum(x) AS sum, avg(x) AS mean, var_samp(x) AS var_samp, var_pop(x) AS var_pop,
                  stddev_samp(x) AS sd_samp, stddev_pop(x) AS sd_pop,
                  quantile_disc(x, [0, 0.1, 0.25, 0.3, 0.5, 0.7, 0.9, 1]) AS qd,
                  quantile_cont(x, [0, 0.1, 0.25, 0.3, 0.5, 0.7, 0.9, 1]) AS qc,
                  median(x) AS median
           FROM t GROUP BY g)
SELECT list(s ORDER BY g) AS result FROM s;
