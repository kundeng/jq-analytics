-- distributions.sql: the most frequent label, the count and share of each label, the correlation of x and y,
-- and a histogram of x over five bins of width 20 from 0 to 100 (the last bin includes 100); nulls skipped.
WITH t AS (FROM read_json('tests/fixtures/stats_generated.json', columns = {id: 'INTEGER', x: 'DOUBLE', y: 'DOUBLE', label: 'VARCHAR'})),
     vc AS (SELECT label, count(*) AS c FROM t WHERE label IS NOT NULL GROUP BY label),
     bins AS (SELECT unnest(generate_series(0, 4)) AS b),
     h AS (SELECT least(floor(x / 20)::INTEGER, 4) AS b, count(*) AS c FROM t WHERE x IS NOT NULL GROUP BY 1)
SELECT {mode: (SELECT mode(label) FROM t),
        counts: (SELECT list({value: label, count: c, share: c / (SELECT sum(c) FROM vc)} ORDER BY c DESC, label) FROM vc),
        corr: (SELECT corr(x, y) FROM t),
        hist: (SELECT list({"from": bins.b * 20, "to": bins.b * 20 + 20, count: coalesce(h.c, 0)} ORDER BY bins.b) FROM bins LEFT JOIN h USING (b))} AS result;
