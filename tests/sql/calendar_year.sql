-- calendar_year.sql: every day of 2026 with its calendar fields and its local start and end in Detroit; US week from %U, which counts from the first Sunday
WITH d AS (SELECT unnest(generate_series(DATE '2026-01-01', DATE '2026-12-31', INTERVAL 1 DAY))::DATE AS d)
SELECT list({date: strftime(d, '%Y-%m-%d'), year: year(d), quarter: quarter(d), month: month(d), day: day(d),
  weekday: dayofweek(d), day_of_year: dayofyear(d), iso_year: isoyear(d), iso_week: weekofyear(d),
  us_week: strftime(d, '%U')::INTEGER + CASE WHEN dayofweek(make_date(year(d), 1, 1)) = 0 THEN 0 ELSE 1 END,
  year_month: strftime(d, '%Y-%m'), year_quarter: year(d) || '-Q' || quarter(d),
  iso_year_week: isoyear(d) || '-W' || lpad(weekofyear(d)::VARCHAR, 2, '0'),
  "start": epoch(d::TIMESTAMP AT TIME ZONE 'America/Detroit')::BIGINT,
  "end": epoch((d + 1)::TIMESTAMP AT TIME ZONE 'America/Detroit')::BIGINT} ORDER BY d) AS result FROM d;
