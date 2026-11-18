-- Δοκιμές των διορθώσεων του db/fixes/01 και 02. Τρέχουν μέσα σε transaction που κάνει ROLLBACK,
-- άρα δεν αφήνουν τίποτα στη βάση. Σταματούν στο πρώτο λάθος.
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/03_fix_tests.sql
-- Αναμένονται 9 γραμμές "OK ..." και στο τέλος "ALL TESTS PASSED".

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET client_min_messages = warning;

BEGIN;

-- Κοινά δεδομένα δοκιμών: ένας πελάτης, ένα δωμάτιο του ξενοδοχείου 11, δύο άδειες κρατήσεις.
CREATE TEMP TABLE t ON COMMIT DROP AS
SELECT (SELECT "idClient" FROM client ORDER BY "idClient" LIMIT 1)                 AS client_id,
       (SELECT documentclient FROM client ORDER BY "idClient" LIMIT 1)             AS client_doc,
       (SELECT min("idRoom") FROM room WHERE "idHotel" = 11)                       AS room_id,
       nextval('idhbooking')::int                                                  AS hb1,
       nextval('idhbooking')::int                                                  AS hb2;

INSERT INTO hotelbooking
SELECT hb, current_date, current_date + 5, NULL, t.client_id, false, NULL, 'confirmed'
FROM t, LATERAL (VALUES (t.hb1), (t.hb2)) AS v(hb);

-- 2.1 ---------------------------------------------------------------------------------
DO $$
DECLARE pid integer;
BEGIN
    PERFORM "2_1_update_clients_and_cards"('insert', 'ZZ-TEST-1', 'Anna', 'Old', 'F', '1990-01-01',
            'Street 1', 'Chania', 'Greece', 'visa', 'TEST-0001', current_date + 365, 'Anna Old');
    PERFORM "2_1_update_clients_and_cards"('update', 'ZZ-TEST-1', 'Anna', 'New', 'F', '1990-01-01',
            'Street 2', 'Chania', 'Greece', 'visa', 'TEST-0002', current_date + 365, 'Anna New');
    SELECT "idClient" INTO pid FROM client WHERE documentclient = 'ZZ-TEST-1';
    ASSERT (SELECT lname FROM person WHERE "idPerson" = pid) = 'New', '2.1 update: person not updated';
    ASSERT (SELECT number FROM creditcard WHERE "clientID" = pid) = 'TEST-0002', '2.1 update: card not updated';
    PERFORM "2_1_update_clients_and_cards"('delete', 'ZZ-TEST-1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
    ASSERT NOT EXISTS (SELECT 1 FROM person WHERE "idPerson" = pid), '2.1 delete: person still there';
END $$;
\echo OK  2.1  insert, update and delete of a client with a card

-- 2.2 ---------------------------------------------------------------------------------
DO $$
DECLARE before_max integer = (SELECT max(idhotelbooking) FROM hotelbooking);
BEGIN
    PERFORM "2_2_insertRandomBookings"(11, '2030-01-01', '2030-01-31', 3);
    ASSERT (SELECT count(*) FROM hotelbooking WHERE idhotelbooking > before_max) = 3, '2.2: expected 3 new bookings';
    ASSERT NOT EXISTS (SELECT 1 FROM hotelbooking WHERE idhotelbooking > before_max AND COALESCE(totalamount, 0) <= 0),
           '2.2: totalamount was not computed';
    ASSERT NOT EXISTS (SELECT 1 FROM roombooking a JOIN roombooking b
                       ON a."roomID" = b."roomID" AND a."hotelbookingID" < b."hotelbookingID"
                      AND a.checkin < b.checkout AND b.checkin < a.checkout
                       WHERE a."hotelbookingID" > before_max), '2.2: created overlapping room bookings';
END $$;
\echo OK  2.2  random bookings are created, priced and do not overlap

-- 5.3 insert --------------------------------------------------------------------------
DO $$
DECLARE r record; expected real;
BEGIN
    SELECT * INTO r FROM t;
    expected = "5_3_current_room_rate"(r.room_id);
    INSERT INTO roombooking VALUES (r.hb1, r.room_id, r.client_id, '2030-03-01', '2030-03-05', 1);
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb1) = expected, 'insert: rate not set from roomrate';
    ASSERT (SELECT totalamount FROM hotelbooking WHERE idhotelbooking = r.hb1) = expected * 4, 'insert: totalamount not computed';
END $$;
\echo OK  5.3  insert sets the rate and the total amount

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    BEGIN
        INSERT INTO roombooking VALUES (r.hb2, r.room_id, r.client_id, '2030-03-02', '2030-03-04', NULL);
        RAISE EXCEPTION 'TEST FAILED: the same room was booked twice';
    EXCEPTION WHEN raise_exception THEN
        IF SQLERRM <> 'The room is not available.' THEN RAISE; END IF;
    END;
END $$;
\echo OK  5.3  double booking of a room is rejected

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    INSERT INTO roombooking VALUES (r.hb2, r.room_id, r.client_id, '2030-03-05', '2030-03-07', NULL);
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;
    ASSERT (SELECT totalamount FROM hotelbooking WHERE idhotelbooking = r.hb2) = 0, 'delete: totalamount not reset';
END $$;
\echo OK  5.3  a booking may start on the day another one checks out

-- 5.3 update --------------------------------------------------------------------------
DO $$
DECLARE r record; rate_before real; rate_after real;
BEGIN
    SELECT * INTO r FROM t;
    rate_before = "5_3_current_room_rate"(r.room_id);

    UPDATE roombooking SET checkout = '2030-03-08' WHERE "hotelbookingID" = r.hb1;
    ASSERT (SELECT totalamount FROM hotelbooking WHERE idhotelbooking = r.hb1) = rate_before * 7, 'update: totalamount not recomputed';

    UPDATE roomrate AS rr SET discount = CASE WHEN rr.discount >= 50 THEN rr.discount - 10 ELSE rr.discount + 10 END
    FROM room AS ro WHERE ro."idRoom" = r.room_id AND rr."idHotel" = ro."idHotel" AND rr.roomtype = ro.roomtype;
    rate_after = "5_3_current_room_rate"(r.room_id);
    ASSERT rate_after <> rate_before, 'test setup: rate did not change';

    UPDATE roombooking SET checkout = '2030-03-09' WHERE "hotelbookingID" = r.hb1;
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb1) = rate_after, 'update: rate not refreshed';

    UPDATE roombooking SET rate = 77 WHERE "hotelbookingID" = r.hb1;
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb1) = 77, 'update: explicit rate was overwritten';
    ASSERT (SELECT totalamount FROM hotelbooking WHERE idhotelbooking = r.hb1) = 77 * 8, 'update: total after explicit rate';
END $$;
\echo OK  5.3  update refreshes the rate and the total, and keeps an explicit rate

-- 5.1 ---------------------------------------------------------------------------------
DO $$
DECLARE r record; total real;
BEGIN
    SELECT * INTO r FROM t;
    UPDATE hotelbooking SET payed = true WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT amount FROM "Transaction" WHERE idhotelbooking = r.hb1 AND action_tr = 'update') = 616, '5.1: payment not recorded';

    -- +1 νύχτα σε πληρωμένη κράτηση: το rate ξαναπαίρνει την τρέχουσα τιμή και η διαφορά καταγράφεται.
    UPDATE roombooking SET checkout = '2030-03-10' WHERE "hotelbookingID" = r.hb1;
    total = (SELECT totalamount FROM hotelbooking WHERE idhotelbooking = r.hb1);
    ASSERT total = "5_3_current_room_rate"(r.room_id) * 9, '5.3: total after extension';
    ASSERT (SELECT count(*) FROM "Transaction" WHERE idhotelbooking = r.hb1) = 2, '5.3: difference not recorded';
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = total::numeric, '5.3: ledger differs from total';

    DELETE FROM hotelbooking WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT amount FROM "Transaction" WHERE idhotelbooking = r.hb1 AND action_tr = 'delete') = -total::numeric, '5.1: refund not recorded';
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = 0, '5.1: ledger does not balance';
END $$;
\echo OK  5.1  payment, extra payment and refund on delete are recorded

-- 4.1 ---------------------------------------------------------------------------------
DO $$
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM "4_1_find_clients_activities"() GROUP BY id_client, id_hotel HAVING count(*) > 1),
           '4.1: duplicate (client, hotel) rows';
    ASSERT (SELECT sum(num_of_activities) FROM "4_1_find_clients_activities"())
           <= (SELECT count(*) FROM "Participates" WHERE participant_role = 'participant'), '4.1: participations counted more than once';
    ASSERT NOT EXISTS (SELECT 1 FROM "4_1_find_clients_activities"() WHERE id_hotel IS NULL), '4.1: client without hotel';
END $$;
\echo OK  4.1  one row per client and hotel, participations counted once

-- 6.1 ---------------------------------------------------------------------------------
DO $$
DECLARE r record; h text;
BEGIN
    SELECT * INTO r FROM t;
    SELECT name INTO h FROM hotel WHERE "idHotel" = 11;
    ASSERT (SELECT count(*) FROM "6_1_availableRoomsByHotel_function"(h)) = (SELECT count(*) FROM room WHERE "idHotel" = 11),
           '6.1: every room of the hotel should be free today';

    INSERT INTO roombooking VALUES (r.hb2, r.room_id, r.client_id, current_date, current_date + 2, NULL);
    ASSERT NOT EXISTS (SELECT 1 FROM "6_1_availableRoomsByHotel" WHERE "idRoom" = r.room_id), '6.1: occupied room listed as available';
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;

    INSERT INTO roombooking VALUES (r.hb2, r.room_id, r.client_id, current_date + 3, current_date + 5, NULL);
    ASSERT (SELECT available_until FROM "6_1_availableRoomsByHotel" WHERE "idRoom" = r.room_id) = current_date + 2,
           '6.1: wrong available_until';
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;
END $$;
\echo OK  6.1  available rooms per hotel, with the date they stay free until

ROLLBACK;
\echo ALL TESTS PASSED
