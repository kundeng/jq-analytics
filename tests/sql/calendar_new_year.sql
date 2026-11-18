-- calendar_new_year.sql: days around three New Years: 2020 has 53 ISO weeks, 2024-12-30 is in ISO year 2025, and 2023 starts on a Sunday
WITH d AS (SELECT unnest(generate_series(DATE '2020-12-25', DATE '2021-01-10', INTERVAL 1 DAY))::DATE AS d UNION ALL SELECT unnest(generate_series(DATE '2024-12-28', DATE '2025-01-05', INTERVAL 1 DAY))::DATE UNION ALL SELECT unnest(generate_series(DATE '2023-01-01', DATE '2023-01-08', INTERVAL 1 DAY))::DATE)
SELECT list({date: strftime(d, '%Y-%m-%d'), year: year(d), quarter: quarter(d), month: month(d), day: day(d),
  weekday: dayofweek(d), day_of_year: dayofyear(d), iso_year: isoyear(d), iso_week: weekofyear(d),
  us_week: strftime(d, '%U')::INTEGER + CASE WHEN dayofweek(make_date(year(d), 1, 1)) = 0 THEN 0 ELSE 1 END,
  year_month: strftime(d, '%Y-%m'), year_quarter: year(d) || '-Q' || quarter(d),
  iso_year_week: isoyear(d) || '-W' || lpad(weekofyear(d)::VARCHAR, 2, '0'),
  "start": epoch(d::TIMESTAMP AT TIME ZONE 'Europe/London')::BIGINT,
  "end": epoch((d + 1)::TIMESTAMP AT TIME ZONE 'Europe/London')::BIGINT} ORDER BY d) AS result FROM d;
