-- Παραδείγματα κλήσης των συναρτήσεων του project (μόνο ανάγνωση).
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/02_examples.sql
--
-- Τα ονόματα ξεκινούν με ψηφίο, άρα θέλουν πάντα διπλά εισαγωγικά.

\pset pager off

\echo
\echo === 3.1 Πόλεις/χώρες με ξενοδοχείο που έχει έκπτωση > 30% (5 πρώτες) ===
SELECT * FROM "3_1_cities_countries_with_disc_over_30"() ORDER BY country, city LIMIT 5;

\echo
\echo === 3.3 Τύπος δωματίου με τη μέγιστη έκπτωση ανά ξενοδοχείο (5 πρώτες) ===
SELECT * FROM "3_3_displayMaxDiscountRoomsPerHotel"() ORDER BY name, roomtype LIMIT 5;

\echo
\echo === 3.4 Κρατήσεις του ξενοδοχείου 11 και ποιος τις έκανε (5 πρώτες) ===
SELECT * FROM "3_4_displayBookingStatus"(11) ORDER BY idhotelbooking LIMIT 5;

\echo
\echo === 3.6 Υπο-παροχές της παροχής "Business Services" ===
SELECT * FROM "3_6_findSubtypesOfAFacility"('Business Services') ORDER BY facility;

\echo
\echo === 3.8 Ξενοδοχεία με διαθέσιμο δωμάτιο από κάθε κατηγορία ===
SELECT * FROM "3_8_search_hotels_having_room_from_each_category"() ORDER BY hotel_id;

\echo
\echo === 4.2 Μέση ηλικία πελατών που έκλεισαν δωμάτιο τύπου Studio ===
\echo     (εξαρτάται από το τρέχον έτος, άρα η τιμή αλλάζει κάθε χρόνο)
SELECT * FROM "4_2_countAvgAge"('Studio');

\echo
\echo === 4.3 Φθηνότερα δωμάτια ανά τύπο στη Ρωσία (5 πρώτες) ===
SELECT * FROM "4_3_search_cheap_rooms_by_country"('Russia') ORDER BY roomtype, city LIMIT 5;

\echo
\echo === 4.5 Πληρότητα (%) του ξενοδοχείου 11 ανά μήνα του 2021 ===
SELECT id_hotel, month_value, round(month_fullness, 2) AS month_fullness
FROM "4_5_find_hotel_fullness"(11, 2021);

\echo
\echo === 6.1 Όψη διαθέσιμων δωματίων ===
\echo     (0 γραμμές: η όψη κοιτά μόνο κρατήσεις μετά τη σημερινή ημερομηνία,
\echo      ενώ τα δεδομένα φτάνουν έως τον Μάιο του 2022)
SELECT count(*) AS rows_in_view FROM "6_1_availableRoomsByHotel";
