-- made_up_incidents.sql: the made-up incident fixture as the same typed view as real_incidents.sql,
-- so a case's answer SQL runs unchanged on either. Timestamps are UTC wall clocks; '' in
-- resolved_at becomes NULL. i is the row's position in the file.
SET TimeZone = 'UTC';
CREATE VIEW incidents AS
SELECT row_number() OVER () AS i, number, subcategory, assignment_group,
       opened_at::TIMESTAMPTZ AS opened, nullif(resolved_at, '')::TIMESTAMPTZ AS resolved,
       (epoch(nullif(resolved_at, '')::TIMESTAMPTZ) - epoch(opened_at::TIMESTAMPTZ)) / 3600 AS hours
FROM read_json('tests/fixtures/made_up_incidents.json',
               columns = {number: 'VARCHAR', opened_at: 'VARCHAR', resolved_at: 'VARCHAR', closed_at: 'VARCHAR',
                          state: 'VARCHAR', contact_type: 'VARCHAR', category: 'VARCHAR', subcategory: 'VARCHAR',
                          assignment_group: 'VARCHAR', opened_by: 'VARCHAR'});
