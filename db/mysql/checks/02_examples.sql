-- Παραδείγματα κλήσης των ερωτημάτων στη MySQL (μόνο ανάγνωση), με τα ίδια ορίσματα που έχει το
-- db/checks/02_examples.sql της PostgreSQL.
--   docker compose exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" hotel --table < /sql/checks/02_examples.sql'
--
-- Οι συναρτήσεις που επιστρέφουν πίνακα είναι εδώ procedures (CALL) και δίνουν όλες τις γραμμές
-- τους: ένα CALL δεν δέχεται ORDER BY ή LIMIT. Τα ονόματα αρχίζουν με ψηφίο, άρα θέλουν `...`.

SET NAMES utf8mb4;

SELECT '=== 3.6 Υπο-παροχές της παροχής "Business Services" (6 γραμμές) ===' AS '';
CALL `3_6_findSubtypesOfAFacility`('Business Services');

SELECT '=== 4.2 Μέση ηλικία πελατών που έκλεισαν δωμάτιο τύπου Studio ===' AS '';
SELECT '    (υπολογίζεται με τη σημερινή ημερομηνία, άρα η τιμή αλλάζει με τον χρόνο)' AS '';
CALL `4_2_countAvgAge`('Studio');

SELECT '=== 4.3 Φθηνότερα δωμάτια ανά τύπο στη Ρωσία (16 γραμμές) ===' AS '';
CALL `4_3_search_cheap_rooms_by_country`('Russia');

SELECT '=== 4.5 Πληρότητα (%) του ξενοδοχείου 11 ανά μήνα του 2021 (12 γραμμές) ===' AS '';
CALL `4_5_find_hotel_fullness`(11, 2021);

SELECT '=== 4.4 Ξενοδοχεία με εισπράξεις πάνω από τον μέσο όρο της πόλης τους ===' AS '';
CALL `4_4_search_hotels_with_max_income`();

SELECT '=== 3.5 Δραστηριότητες του ξενοδοχείου 13 χωρίς συμμετοχές ===' AS '';
CALL `3_5_restoreActivities`(13);

SELECT '=== 6.1 Διαθέσιμα δωμάτια ενός ξενοδοχείου, με τη συνάρτηση (11 γραμμές) ===' AS '';
CALL `6_1_availableRoomsByHotel_function`('Ramblewood Inn');

SELECT '=== 6.1 Όψη διαθέσιμων δωματίων: πλήθος γραμμών (2034: όλα ελεύθερα σήμερα) ===' AS '';
SELECT COUNT(*) AS rows_in_view FROM `6_1_availableRoomsByHotel`;

SELECT '=== 6.2 Εβδομαδιαίο πλάνο: τα 3 πρώτα δωμάτια του ξενοδοχείου 11 ===' AS '';
SELECT room_number, rate, discount, week_start, sunday, monday, tuesday, wednesday, thursday, friday, saturday
FROM `6_2_weeklyPlan`
WHERE idHotel = 11
LIMIT 3;

SELECT '=== 5.3 Τρέχουσα τιμή του δωματίου 250, με την έκπτωση ===' AS '';
SELECT `5_3_current_room_rate`(250) AS current_rate;

-- Οι παρακάτω δίνουν πολλές γραμμές· βγάλτε το σχόλιο για να τις δείτε.
-- CALL `3_1_cities_countries_with_disc_over_30`();          --   91 γραμμές
-- CALL `3_3_displayMaxDiscountRoomsPerHotel`();             --  135 γραμμές
-- CALL `3_4_displayBookingStatus`(11);                      --   61 γραμμές
-- CALL `3_8_search_hotels_having_room_from_each_category`();--  101 γραμμές
-- CALL `4_1_find_clients_activities`();                     -- 8909 γραμμές
