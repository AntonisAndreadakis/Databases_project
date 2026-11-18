-- Δοκιμές των διορθωμένων συναρτήσεων 3.4, 3.7, 3.8, 4.2, 4.3, 4.4, 4.5
-- (db/fixes/04_query_functions.sql). Κάθε συνάρτηση συγκρίνεται με ανεξάρτητα γραμμένο
-- ερώτημα πάνω σε όλα τα δεδομένα. Τρέχουν μέσα σε transaction που κάνει ROLLBACK.
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/06_query_function_tests.sql
-- Αναμένονται 7 γραμμές "OK ..." και στο τέλος "ALL TESTS PASSED".

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET client_min_messages = warning;

BEGIN;

-- 3.4 ---------------------------------------------------------------------------------
DO $$
DECLARE h integer; n integer; expected integer;
BEGIN
    FOR h IN SELECT "idHotel" FROM hotel LOOP
        SELECT count(*) INTO n FROM "3_4_displayBookingStatus"(h);
        SELECT count(DISTINCT rb."hotelbookingID") INTO expected
        FROM roombooking rb JOIN room r ON r."idRoom" = rb."roomID" WHERE r."idHotel" = h;
        ASSERT n = expected, format('3.4: hotel %s returned %s rows for %s bookings', h, n, expected);
    END LOOP;
    -- Τα ονόματα είναι του πελάτη που έκανε την κράτηση, και το bookedBy ακολουθεί το Manages.
    ASSERT NOT EXISTS (
        SELECT 1
        FROM hotel ho, LATERAL "3_4_displayBookingStatus"(ho."idHotel") f
        JOIN hotelbooking hb ON hb.idhotelbooking = f.idhotelbooking
        LEFT JOIN person pe ON pe."idPerson" = hb."bookedbyclientID"
        WHERE f.clientfname IS DISTINCT FROM pe.fname OR f.clientlname IS DISTINCT FROM pe.lname
           OR f.reservationdate IS DISTINCT FROM hb.reservationdate
           OR (f.bookedby = 'Employee') <> EXISTS (SELECT 1 FROM "Manages" m WHERE m.idhotelbooking = hb.idhotelbooking)),
        '3.4: wrong client name, date or bookedBy';
END $$;
\echo OK  3.4  one row per booking, with the client who made it

-- 3.7 ---------------------------------------------------------------------------------
DO $$
DECLARE hf text; rf text; n integer; expected integer;
BEGIN
    FOR hf, rf IN SELECT a."nameFacility", b."nameFacility"
                  FROM facility a, facility b
                  WHERE a.type = 'hotel' AND b.type = 'room'
                    AND a."nameFacility" IN ('Restaurant', 'Business Services', 'Fax', 'Root Hotel')
    LOOP
        SELECT count(*) INTO n FROM "3_7_search_hotels_with_specific_facilities"(hf, rf);
        -- Ανεξάρτητος υπολογισμός: ανέβασμα στους προγόνους κάθε διευκόλυνσης, χωρίς αναδρομικό CTE προς τα κάτω.
        SELECT count(*) INTO expected
        FROM room r
        WHERE NOT EXISTS (SELECT 1 FROM roombooking rb WHERE rb."roomID" = r."idRoom"
                          AND rb.checkin <= current_date AND rb.checkout > current_date)
          AND EXISTS (SELECT 1 FROM hotelfacilities x
                      LEFT JOIN facility f1 ON f1."nameFacility" = x."nameFacility"
                      LEFT JOIN facility f2 ON f2."nameFacility" = f1."subtypeOf"
                      LEFT JOIN facility f3 ON f3."nameFacility" = f2."subtypeOf"
                      LEFT JOIN facility f4 ON f4."nameFacility" = f3."subtypeOf"
                      WHERE x."idHotel" = r."idHotel"
                        AND hf IN (f1."nameFacility", f2."nameFacility", f3."nameFacility", f4."nameFacility"))
          AND EXISTS (SELECT 1 FROM roomfacilities x
                      LEFT JOIN facility f1 ON f1."nameFacility" = x."nameFacility"
                      LEFT JOIN facility f2 ON f2."nameFacility" = f1."subtypeOf"
                      LEFT JOIN facility f3 ON f3."nameFacility" = f2."subtypeOf"
                      LEFT JOIN facility f4 ON f4."nameFacility" = f3."subtypeOf"
                      WHERE x."idRoom" = r."idRoom"
                        AND rf IN (f1."nameFacility", f2."nameFacility", f3."nameFacility", f4."nameFacility"));
        ASSERT n = expected, format('3.7: (%s, %s) returned %s rooms, expected %s', hf, rf, n, expected);
    END LOOP;
    ASSERT (SELECT count(*) FROM "3_7_search_hotels_with_specific_facilities"('Restaurant', 'Beverages & Drinks')) = 1467,
           '3.7: the three-level room facility should give 1467 rooms';
END $$;
\echo OK  3.7  every level of the facility hierarchy is followed

-- 3.8 ---------------------------------------------------------------------------------
DO $$
DECLARE studio_room integer; hb integer;
BEGIN
    ASSERT (SELECT count(*) FROM "3_8_search_hotels_having_room_from_each_category"())
           = (SELECT count(DISTINCT "idHotel") FROM room), '3.8: with no room occupied today every hotel qualifies';

    -- Πιάνουμε σήμερα το μοναδικό δωμάτιο ενός τύπου σε ένα ξενοδοχείο: το ξενοδοχείο πρέπει να φύγει.
    SELECT min(r."idRoom") INTO studio_room
    FROM room r GROUP BY r."idHotel", r.roomtype HAVING count(*) = 1 LIMIT 1;
    hb = nextval('idhbooking');
    INSERT INTO hotelbooking VALUES (hb, current_date, current_date + 5, NULL, (SELECT min("idClient") FROM client), false, NULL, 'confirmed');
    INSERT INTO roombooking VALUES (hb, studio_room, (SELECT min("idClient") FROM client), current_date, current_date + 2, NULL);
    ASSERT NOT EXISTS (SELECT 1 FROM "3_8_search_hotels_having_room_from_each_category"() f
                       JOIN room r ON r."idHotel" = f.hotel_id WHERE r."idRoom" = studio_room),
           '3.8: hotel returned although its only room of a type is occupied';
    ASSERT (SELECT count(*) FROM "3_8_search_hotels_having_room_from_each_category"())
           = (SELECT count(DISTINCT "idHotel") FROM room) - 1, '3.8: exactly one hotel should drop out';
    DELETE FROM hotelbooking WHERE idhotelbooking = hb;
END $$;
\echo OK  3.8  a free room of each type the hotel itself has

-- 4.2 ---------------------------------------------------------------------------------
DO $$
DECLARE t text; got numeric; expected numeric;
BEGIN
    FOR t IN SELECT typename FROM roomtype LOOP
        SELECT average_age INTO got FROM "4_2_countAvgAge"(t);
        SELECT round(avg(a), 2) INTO expected
        FROM (SELECT DISTINCT pe."idPerson",
                     (extract(year FROM current_date) - extract(year FROM pe.dateofbirth)
                      - CASE WHEN to_char(current_date, 'MMDD') < to_char(pe.dateofbirth, 'MMDD') THEN 1 ELSE 0 END) AS a
              FROM roombooking rb
              JOIN room ro ON ro."idRoom" = rb."roomID"
              JOIN person pe ON pe."idPerson" = rb."bookedforpersonID"
              WHERE ro.roomtype = t) x;
        ASSERT got IS NOT DISTINCT FROM expected, format('4.2: %s gave %s, expected %s', t, got, expected);
    END LOOP;
END $$;
\echo OK  4.2  average of real ages, each person counted once

-- 4.3 ---------------------------------------------------------------------------------
DO $$
BEGIN
    ASSERT NOT EXISTS (
        SELECT 1
        FROM (SELECT DISTINCT country FROM hotel) c, LATERAL "4_3_search_cheap_rooms_by_country"(c.country) f
        WHERE f.min_rate IS DISTINCT FROM (SELECT min((rr.rate - rr.rate * rr.discount / 100)::real)
                                           FROM roomrate rr JOIN hotel h ON h."idHotel" = rr."idHotel"
                                           WHERE h.country = c.country AND rr.roomtype = f.roomtype)),
        '4.3: returned price is not the cheapest of the type in the country';
    ASSERT (SELECT count(*) FROM (SELECT DISTINCT country FROM hotel) c, LATERAL "4_3_search_cheap_rooms_by_country"(c.country))
           = (SELECT count(*) FROM (
                SELECT DISTINCT h.country, h.city, rr.roomtype
                FROM roomrate rr JOIN hotel h ON h."idHotel" = rr."idHotel"
                WHERE (rr.rate - rr.rate * rr.discount / 100)::real
                      = (SELECT min((r2.rate - r2.rate * r2.discount / 100)::real)
                         FROM roomrate r2 JOIN hotel h2 ON h2."idHotel" = r2."idHotel"
                         WHERE h2.country = h.country AND r2.roomtype = rr.roomtype)) x),
           '4.3: wrong set of (city, room type)';
END $$;
\echo OK  4.3  cheapest price per room type, with its city

-- 4.4 ---------------------------------------------------------------------------------
DO $$
DECLARE before_result text; paid_booking integer; free_room integer;
BEGIN
    SELECT string_agg(hotel_name, ',' ORDER BY hotel_name) INTO before_result FROM "4_4_search_hotels_with_max_income"();
    ASSERT before_result IS NOT DISTINCT FROM (
        SELECT string_agg(name, ',' ORDER BY name)
        FROM (SELECT h.name, h.city, inc.income,
                     avg(inc.income) OVER (PARTITION BY h.city) AS city_avg
              FROM hotel h
              JOIN (SELECT r."idHotel", sum(DISTINCT_TOTAL.totalamount) AS income
                    FROM (SELECT DISTINCT hb.idhotelbooking, hb.totalamount, rb_h.hotel
                          FROM hotelbooking hb
                          JOIN (SELECT rb."hotelbookingID", r."idHotel" AS hotel FROM roombooking rb JOIN room r ON r."idRoom" = rb."roomID") rb_h
                            ON rb_h."hotelbookingID" = hb.idhotelbooking
                          WHERE hb.payed AND hb.status = 'confirmed') DISTINCT_TOTAL
                    JOIN (SELECT DISTINCT "idHotel" FROM room) r ON r."idHotel" = DISTINCT_TOTAL.hotel
                    GROUP BY r."idHotel") inc ON inc."idHotel" = h."idHotel") z
        WHERE income > city_avg), '4.4: differs from the independent query';

    -- Ένα επιπλέον δωμάτιο σε πληρωμένη κράτηση δεν πρέπει να πολλαπλασιάζει τις εισπράξεις της.
    SELECT hb.idhotelbooking INTO paid_booking
    FROM hotelbooking hb WHERE hb.payed AND hb.status = 'confirmed' AND hb.totalamount > 0
      AND EXISTS (SELECT 1 FROM roombooking rb WHERE rb."hotelbookingID" = hb.idhotelbooking)
    ORDER BY hb.idhotelbooking LIMIT 1;
    ALTER TABLE roombooking DISABLE TRIGGER USER;      -- μόνο για το στήσιμο του σεναρίου, μέσα στο transaction
    INSERT INTO roombooking
    SELECT paid_booking, r2."idRoom", NULL, date '2035-01-01', date '2035-01-02', 0
    FROM roombooking rb JOIN room r ON r."idRoom" = rb."roomID"
    JOIN room r2 ON r2."idHotel" = r."idHotel" AND r2."idRoom" <> r."idRoom"
    WHERE rb."hotelbookingID" = paid_booking
      AND NOT EXISTS (SELECT 1 FROM roombooking x WHERE x."hotelbookingID" = paid_booking AND x."roomID" = r2."idRoom")
    LIMIT 2;
    ALTER TABLE roombooking ENABLE TRIGGER USER;
    ASSERT (SELECT string_agg(hotel_name, ',' ORDER BY hotel_name) FROM "4_4_search_hotels_with_max_income"())
           IS NOT DISTINCT FROM before_result, '4.4: extra rooms of a booking changed the income';
END $$;
\echo OK  4.4  a booking is counted once, however many rooms it has

-- 4.5 ---------------------------------------------------------------------------------
DO $$
DECLARE h integer; y integer;
BEGIN
    FOR h IN SELECT "idHotel" FROM hotel WHERE "idHotel" IN (SELECT "idHotel" FROM room) LOOP
        FOR y IN 2021..2022 LOOP
            ASSERT (SELECT count(*) FROM "4_5_find_hotel_fullness"(h, y)) = 12, format('4.5: hotel %s year %s does not have 12 months', h, y);
            ASSERT NOT EXISTS (
                SELECT 1
                FROM "4_5_find_hotel_fullness"(h, y) f
                WHERE f.month_fullness < 0 OR f.month_fullness > 100
                   OR f.month_fullness IS DISTINCT FROM round(100.0 * (
                        -- Ανεξάρτητος υπολογισμός: ξεδίπλωμα κάθε κράτησης σε νύχτες.
                        SELECT count(DISTINCT rb."roomID")
                        FROM roombooking rb
                        JOIN room r ON r."idRoom" = rb."roomID",
                        LATERAL generate_series(rb.checkin, rb.checkout - 1, interval '1 day') AS night
                        WHERE r."idHotel" = h
                          AND extract(year FROM night) = y AND extract(month FROM night) = f.month_value)
                      / (SELECT count(*) FROM room r WHERE r."idHotel" = h), 2)),
                format('4.5: hotel %s year %s differs from the night-by-night count', h, y);
        END LOOP;
    END LOOP;
END $$;
\echo OK  4.5  share of rooms occupied in each of the 12 months, never above 100

ROLLBACK;
\echo ALL TESTS PASSED
