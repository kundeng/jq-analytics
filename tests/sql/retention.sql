-- retention.sql: per cohort (first month) and each month from it to 2026-07, how many of the cohort were active.
WITH v AS (FROM read_json('tests/fixtures/visits_generated.json', columns = {u: 'VARCHAR', m: 'VARCHAR'})),
     pos AS (SELECT m, row_number() OVER (ORDER BY m) - 1 AS i FROM (SELECT unnest(['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07']) AS m)),
     co AS (SELECT u, min(m) AS cohort FROM v GROUP BY u),
     sz AS (SELECT cohort, count(*) AS n FROM co GROUP BY cohort),
     act AS (SELECT DISTINCT u, m FROM v),
     cell AS (SELECT sz.cohort, p.m AS period, p.i - c.i AS off, sz.n,
                     (SELECT count(*) FROM act JOIN co USING (u) WHERE co.cohort = sz.cohort AND act.m = p.m) AS k
              FROM sz JOIN pos c ON c.m = sz.cohort JOIN pos p ON p.i >= c.i)
SELECT {"table": (SELECT list({cohort: cohort, period: period, "offset": off, entities: k, cohort_size: n, rate: k / n} ORDER BY cohort, period) FROM cell),
        cohorts: (SELECT list({u: u, cohort: cohort} ORDER BY u) FROM co)} AS result;
