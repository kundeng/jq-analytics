-- four instants around the start of daylight saving in Detroit (2026-03-08 02:00 local) as local text
SET TimeZone = 'UTC';
SELECT to_json(list(strftime(timezone('America/Detroit', to_timestamp(e)), '%Y-%m-%d %H:%M') ORDER BY e)) AS result
FROM (VALUES (1772946000), (1772949600), (1772953200), (1773043200)) t(e);
