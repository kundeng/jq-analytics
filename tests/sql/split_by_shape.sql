-- split_by_shape.sql: rows per event_type in the example 05 stream.
WITH t AS (FROM read_json('tests/fixtures/example_05_asof_join.json', columns = {event_type: 'VARCHAR'}))
SELECT {dhcp: count(*) FILTER (WHERE event_type = 'dhcp'), firewall: count(*) FILTER (WHERE event_type = 'firewall')} AS result FROM t;
