-- Έλεγχος της δομής της βάσης MySQL. Μόνο ανάγνωση.
--   docker compose exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" hotel --table < /sql/checks/01_structure.sql'

SET NAMES utf8mb4;

SELECT '=== 1. Πίνακες ===' AS '';
SELECT table_name AS `table`, table_collation AS collation
FROM information_schema.tables
WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'
ORDER BY table_name;

SELECT '=== 2. Πλήθος στηλών ===' AS '';
SELECT COUNT(*) AS `columns`
FROM information_schema.columns c
JOIN information_schema.tables t ON t.table_schema = c.table_schema AND t.table_name = c.table_name
WHERE c.table_schema = DATABASE() AND t.table_type = 'BASE TABLE';

SELECT '=== 3. Πρωτεύοντα κλειδιά και UNIQUE ===' AS '';
SELECT table_name AS `table`, constraint_type AS type, constraint_name AS name
FROM information_schema.table_constraints
WHERE table_schema = DATABASE() AND constraint_type IN ('PRIMARY KEY', 'UNIQUE')
ORDER BY table_name, constraint_type, constraint_name;

SELECT '=== 4. Ξένα κλειδιά ===' AS '';
SELECT rc.table_name AS `table`, rc.constraint_name AS name, rc.referenced_table_name AS refers_to,
       rc.update_rule AS on_update, rc.delete_rule AS on_delete
FROM information_schema.referential_constraints rc
WHERE rc.constraint_schema = DATABASE()
ORDER BY rc.table_name, rc.constraint_name;

SELECT '=== 5. Περιορισμοί CHECK ===' AS '';
SELECT tc.table_name AS `table`, cc.constraint_name AS name, cc.check_clause AS definition
FROM information_schema.check_constraints cc
JOIN information_schema.table_constraints tc
  ON tc.constraint_schema = cc.constraint_schema AND tc.constraint_name = cc.constraint_name
WHERE cc.constraint_schema = DATABASE()
ORDER BY tc.table_name, cc.constraint_name;

SELECT '=== 6. Στήλες ENUM ===' AS '';
SELECT table_name AS `table`, column_name AS `column`, column_type AS `values`
FROM information_schema.columns
WHERE table_schema = DATABASE() AND data_type = 'enum'
ORDER BY table_name, column_name;

SELECT '=== 7. Στήλες AUTO_INCREMENT (αντί για sequences) ===' AS '';
SELECT c.table_name AS `table`, c.column_name AS `column`
FROM information_schema.columns c
WHERE c.table_schema = DATABASE() AND c.extra LIKE '%auto_increment%'
ORDER BY c.table_name;

SELECT '=== 8. Ευρετήρια ===' AS '';
SELECT table_name AS `table`, index_name AS `index`,
       GROUP_CONCAT(column_name ORDER BY seq_in_index SEPARATOR ', ') AS `columns`,
       IF(MAX(non_unique) = 0, 'unique', '') AS `unique`
FROM information_schema.statistics
WHERE table_schema = DATABASE()
GROUP BY table_name, index_name
ORDER BY table_name, index_name;

SELECT '=== 9. Συναρτήσεις και procedures ===' AS '';
SELECT routine_name AS routine, routine_type AS type
FROM information_schema.routines
WHERE routine_schema = DATABASE()
ORDER BY routine_name;

SELECT '=== 10. Triggers ===' AS '';
SELECT event_object_table AS `table`, trigger_name AS `trigger`, action_timing AS timing, event_manipulation AS event
FROM information_schema.triggers
WHERE trigger_schema = DATABASE()
ORDER BY event_object_table, action_timing DESC, event_manipulation;

SELECT '=== 11. Όψεις ===' AS '';
SELECT table_name AS `view`
FROM information_schema.views
WHERE table_schema = DATABASE()
ORDER BY table_name;

SELECT '=== 12. Πλήθος γραμμών ===' AS '';
SELECT 'person' AS `table`, COUNT(*) AS `rows` FROM person
UNION ALL SELECT 'client', COUNT(*) FROM client
UNION ALL SELECT 'creditcard', COUNT(*) FROM creditcard
UNION ALL SELECT 'employee', COUNT(*) FROM employee
UNION ALL SELECT 'hotel', COUNT(*) FROM hotel
UNION ALL SELECT 'room', COUNT(*) FROM room
UNION ALL SELECT 'roomtype', COUNT(*) FROM roomtype
UNION ALL SELECT 'roomrate', COUNT(*) FROM roomrate
UNION ALL SELECT 'facility', COUNT(*) FROM facility
UNION ALL SELECT 'hotelfacilities', COUNT(*) FROM hotelfacilities
UNION ALL SELECT 'roomfacilities', COUNT(*) FROM roomfacilities
UNION ALL SELECT 'hotelbooking', COUNT(*) FROM hotelbooking
UNION ALL SELECT 'roombooking', COUNT(*) FROM roombooking
UNION ALL SELECT 'Activity', COUNT(*) FROM Activity
UNION ALL SELECT 'Participates', COUNT(*) FROM Participates
UNION ALL SELECT 'Manages', COUNT(*) FROM Manages
UNION ALL SELECT 'Transaction', COUNT(*) FROM `Transaction`
UNION ALL SELECT 'app_user', COUNT(*) FROM app_user;
