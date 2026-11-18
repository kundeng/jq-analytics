-- funnel_no_window.sql: view, cart, pay in time order with no limit: entities per step and each entity's depth.
-- An entity reaches cart when some view and cart exist with view.t <= cart.t <= view.t + W, and pay when a pay
-- exists after that cart within the same limit. This states the rule; it is not the step-by-step search.
WITH e AS (FROM read_json('tests/fixtures/shop_generated.json', columns = {u: 'VARCHAR', t: 'BIGINT', step: 'VARCHAR'})),
     r1 AS (SELECT DISTINCT u FROM e WHERE step = 'view'),
     r2 AS (SELECT DISTINCT v.u FROM e v JOIN e c ON c.u = v.u AND c.step = 'cart' AND c.t >= v.t AND c.t <= v.t + 1000000000000 WHERE v.step = 'view'),
     r3 AS (SELECT DISTINCT v.u FROM e v JOIN e c ON c.u = v.u AND c.step = 'cart' AND c.t >= v.t AND c.t <= v.t + 1000000000000
            JOIN e p ON p.u = v.u AND p.step = 'pay' AND p.t >= c.t AND p.t <= v.t + 1000000000000 WHERE v.step = 'view'),
     d AS (SELECT r1.u, 1 + (r1.u IN (SELECT u FROM r2))::INTEGER + (r1.u IN (SELECT u FROM r3))::INTEGER AS depth FROM r1)
SELECT {counts: [(SELECT count(*) FROM r1), (SELECT count(*) FROM r2), (SELECT count(*) FROM r3)],
        depths: (SELECT list({u: u, depth: depth} ORDER BY u) FROM d)} AS result;
