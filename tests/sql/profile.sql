-- profile.sql: per column of the generated table: rows, nulls, empty strings, distinct non-null values, min and max.
WITH t AS (FROM read_json('tests/fixtures/stats_generated.json', columns = {id: 'INTEGER', x: 'DOUBLE', y: 'DOUBLE', label: 'VARCHAR'}))
SELECT {x: (SELECT {"rows": count(*), nulls: count(*) - count(x), "empty": 0, "distinct": count(DISTINCT x), "min": min(x), "max": max(x)} FROM t),
        label: (SELECT {"rows": count(*), nulls: count(*) - count(label), "empty": count(*) FILTER (label = ''), "distinct": count(DISTINCT label), "min": min(label), "max": max(label)} FROM t),
        id: (SELECT {"rows": count(*), nulls: count(*) - count(id), "empty": 0, "distinct": count(DISTINCT id), "min": min(id), "max": max(id)} FROM t)} AS result;
