-- Έλεγχος δομής της βάσης (μόνο ανάγνωση).
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/01_structure.sql

\pset pager off

\echo
\echo === 1. Πίνακες (αναμένονται 17) ===
\dt

\echo
\echo === 2. Στήλες ανά πίνακα ===
SELECT c.table_name, c.ordinal_position AS pos, c.column_name,
       CASE WHEN c.data_type = 'USER-DEFINED' THEN c.udt_name
            WHEN c.character_maximum_length IS NOT NULL
                 THEN c.data_type || '(' || c.character_maximum_length || ')'
            ELSE c.data_type END AS type,
       c.is_nullable AS nullable, c.column_default AS "default"
FROM information_schema.columns AS c
JOIN information_schema.tables AS t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY c.table_name, c.ordinal_position;

\echo
\echo === 3. Πρωτεύοντα κλειδιά και UNIQUE ===
SELECT rel.relname AS table_name, con.conname AS constraint_name,
       CASE con.contype WHEN 'p' THEN 'PRIMARY KEY' ELSE 'UNIQUE' END AS kind,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS rel ON rel.oid = con.conrelid
WHERE con.connamespace = 'public'::regnamespace AND con.contype IN ('p', 'u')
ORDER BY rel.relname, con.contype, con.conname;

\echo
\echo === 4. Ξένα κλειδιά (αναμένονται 25, ή 24 μετά τις διορθώσεις) ===
SELECT rel.relname AS table_name, con.conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS rel ON rel.oid = con.conrelid
WHERE con.connamespace = 'public'::regnamespace AND con.contype = 'f'
ORDER BY rel.relname, con.conname;

\echo
\echo === 5. Περιορισμοί CHECK ===
SELECT rel.relname AS table_name, con.conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS rel ON rel.oid = con.conrelid
WHERE con.connamespace = 'public'::regnamespace AND con.contype = 'c'
ORDER BY rel.relname, con.conname;

\echo
\echo === 6. Τύποι ENUM και οι τιμές τους (αναμένονται 7) ===
SELECT t.typname AS enum_type,
       string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder) AS labels
FROM pg_type AS t
JOIN pg_enum AS e ON e.enumtypid = t.oid
WHERE t.typnamespace = 'public'::regnamespace
GROUP BY t.typname
ORDER BY t.typname;

\echo
\echo === 7. Sequences (αναμένονται 5) ===
SELECT sequencename, start_value, increment_by, last_value
FROM pg_sequences
WHERE schemaname = 'public'
ORDER BY sequencename;

\echo
\echo === 8. Ευρετήρια ===
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;

\echo
\echo === 9. Συναρτήσεις (αναμένονται 29, ή 38 μετά τις διορθώσεις) ===
SELECT p.proname AS function_name,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_function_result(p.oid) AS returns
FROM pg_proc AS p
WHERE p.pronamespace = 'public'::regnamespace
ORDER BY p.proname;

\echo
\echo === 10. Triggers (αναμένονται 9, ή 11 μετά τις διορθώσεις) ===
SELECT rel.relname AS table_name, tg.tgname AS trigger_name,
       pg_get_triggerdef(tg.oid) AS definition
FROM pg_trigger AS tg
JOIN pg_class AS rel ON rel.oid = tg.tgrelid
WHERE NOT tg.tgisinternal AND rel.relnamespace = 'public'::regnamespace
ORDER BY rel.relname, tg.tgname;

\echo
\echo === 11. Όψεις (αναμένεται 1, ή 2 μετά τις διορθώσεις) ===
\dv
SELECT viewname, definition FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;

\echo
\echo === 12. Πλήθος γραμμών ανά πίνακα ===
SELECT t.table_name,
       (xpath('/row/n/text()',
              query_to_xml(format('SELECT count(*) AS n FROM %I.%I', t.table_schema, t.table_name),
                           false, true, '')))[1]::text::bigint AS row_count
FROM information_schema.tables AS t
WHERE t.table_schema = 'public' AND t.table_type = 'BASE TABLE'
ORDER BY t.table_name;
