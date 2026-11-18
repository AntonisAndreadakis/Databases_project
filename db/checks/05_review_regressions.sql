-- Δοκιμές για τα ελαττώματα που βρήκε ο ανεξάρτητος έλεγχος των διορθώσεων.
-- Τρέχουν μέσα σε transaction που κάνει ROLLBACK. Σταματούν στο πρώτο λάθος.
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/05_review_regressions.sql
-- Αναμένονται 12 γραμμές "OK ..." και στο τέλος "ALL TESTS PASSED".

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET client_min_messages = warning;

BEGIN;

-- Δύο πελάτες, δύο δωμάτια του ξενοδοχείου 11 με διαφορετικό τύπο, τρεις άδειες κρατήσεις:
-- hb1/hb2 με προθεσμία ακύρωσης σε 5 ημέρες, hb_late με προθεσμία που έληξε χθες.
CREATE TEMP TABLE t ON COMMIT DROP AS
SELECT c1."idClient" AS client_id, c1.documentclient AS client_doc, c2."idClient" AS client2_id,
       r1."idRoom" AS room_id, r2."idRoom" AS room2_id,
       nextval('idhbooking')::int AS hb1, nextval('idhbooking')::int AS hb2, nextval('idhbooking')::int AS hb_late
FROM (SELECT * FROM client ORDER BY "idClient" LIMIT 1) AS c1,
     (SELECT * FROM client ORDER BY "idClient" OFFSET 1 LIMIT 1) AS c2,
     (SELECT * FROM room WHERE "idHotel" = 11 ORDER BY "idRoom" LIMIT 1) AS r1,
     LATERAL (SELECT * FROM room WHERE "idHotel" = 11 AND roomtype <> r1.roomtype ORDER BY "idRoom" LIMIT 1) AS r2;

INSERT INTO hotelbooking
SELECT v.hb, current_date - 9, v.canc, NULL, t.client_id, false, NULL, 'confirmed'
FROM t, LATERAL (VALUES (t.hb1, current_date + 5), (t.hb2, current_date + 5), (t.hb_late, current_date - 1)) AS v(hb, canc);

-- Εκτελεί μια εντολή και επιστρέφει το μήνυμα του σφάλματος, ή NULL αν πέτυχε.
CREATE FUNCTION pg_temp.fails(cmd text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
    EXECUTE cmd;
    RETURN NULL;
EXCEPTION WHEN raise_exception THEN
    RETURN SQLERRM;
END $$;

-- ---------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    INSERT INTO roombooking VALUES (r.hb1, r.room_id,  r.client_id,  '2030-03-01', '2030-03-05', NULL);
    INSERT INTO roombooking VALUES (r.hb2, r.room2_id, r.client2_id, '2030-03-01', '2030-03-05', NULL);
    ASSERT pg_temp.fails(format('UPDATE roombooking SET "roomID" = %s WHERE "hotelbookingID" = %s', r.room_id, r.hb2))
           LIKE 'The room is not available%', 'moving a booking onto an occupied room was accepted';

    -- Σε ελεύθερες ημερομηνίες η αλλαγή δωματίου επιτρέπεται και το rate γίνεται του νέου δωματίου.
    UPDATE roombooking SET checkin = '2030-04-01', checkout = '2030-04-03' WHERE "hotelbookingID" = r.hb2;
    UPDATE roombooking SET "roomID" = r.room_id WHERE "hotelbookingID" = r.hb2;
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb2) = "5_3_current_room_rate"(r.room_id),
           'rate was not re-priced for the new room';
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;
END $$;
\echo OK  5.3  a booking cannot be moved onto an occupied room; a free move re-prices it

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    ASSERT pg_temp.fails(format('INSERT INTO roombooking VALUES (%s, %s, %s, %L, NULL, NULL)', r.hb2, r.room_id, r.client_id, '2030-03-02'))
           = 'The checkin and the checkout cannot be null.', 'insert with NULL checkout was accepted';
    ASSERT pg_temp.fails(format('UPDATE roombooking SET checkout = NULL WHERE "hotelbookingID" = %s', r.hb1))
           = 'The checkin and the checkout cannot be null.', 'update to NULL checkout was accepted';
END $$;
\echo OK  5.3  NULL dates are rejected on insert and update

DO $$
DECLARE r record; room_without_rate integer;
BEGIN
    SELECT * INTO r FROM t;
    SELECT ro."idRoom" INTO room_without_rate
    FROM room ro
    WHERE NOT EXISTS (SELECT 1 FROM roomrate rr WHERE rr."idHotel" = ro."idHotel" AND rr.roomtype = ro.roomtype)
    LIMIT 1;
    IF room_without_rate IS NOT NULL THEN
        ASSERT pg_temp.fails(format('INSERT INTO roombooking VALUES (%s, %s, %s, %L, %L, NULL)',
                                    r.hb2, room_without_rate, r.client_id, '2030-06-01', '2030-06-03'))
               = 'There is no rate for this room type in this hotel.', 'a room without a rate was booked for free';
    END IF;
END $$;
\echo OK  5.3  a room whose type has no rate cannot be booked

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    -- Διαμονή που άρχισε χθες: η παράταση επιτρέπεται, η μετακίνηση στο παρελθόν όχι.
    INSERT INTO roombooking VALUES (r.hb2, r.room2_id, r.client_id, current_date - 1, current_date + 2, NULL);
    UPDATE roombooking SET checkout = current_date + 4 WHERE "hotelbookingID" = r.hb2;
    ASSERT (SELECT checkout FROM roombooking WHERE "hotelbookingID" = r.hb2) = current_date + 4, 'stay was not extended';
    ASSERT pg_temp.fails(format('UPDATE roombooking SET checkin = current_date - 3 WHERE "hotelbookingID" = %s', r.hb2))
           LIKE '%in the past.', 'checkin was moved into the past';
    UPDATE roombooking SET checkin = current_date + 30, checkout = current_date + 32 WHERE "hotelbookingID" = r.hb2;
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;
END $$;
\echo OK  5.3  a stay that has started can be extended

DO $$
DECLARE r record; other_rate real;
BEGIN
    SELECT * INTO r FROM t;
    -- Ρητό rate ίσο με το παλιό κρατιέται, ακόμη κι αν η τρέχουσα τιμή έχει αλλάξει.
    UPDATE roombooking SET rate = 50 WHERE "hotelbookingID" = r.hb1;
    UPDATE roombooking SET checkout = '2030-03-06', rate = 50 WHERE "hotelbookingID" = r.hb1;
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb1) = 50, 'an explicit rate equal to the old one was replaced';
    -- Χωρίς rate στο UPDATE, ξαναπαίρνει την τρέχουσα τιμή.
    UPDATE roombooking SET checkout = '2030-03-05' WHERE "hotelbookingID" = r.hb1;
    ASSERT (SELECT rate FROM roombooking WHERE "hotelbookingID" = r.hb1) = "5_3_current_room_rate"(r.room_id), 'rate was not refreshed';
END $$;
\echo OK  5.3  an explicit rate is kept even when it equals the old one

DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM t;
    INSERT INTO roombooking VALUES (r.hb_late, r.room2_id, r.client_id, '2030-03-01', '2030-03-05', NULL);
    ASSERT pg_temp.fails(format('UPDATE roombooking SET rate = 0 WHERE "hotelbookingID" = %s', r.hb_late))
           LIKE '%cannot decrease the rate.', 'rate was decreased after the deadline';
    ASSERT pg_temp.fails(format('UPDATE roombooking SET "hotelbookingID" = %s WHERE "hotelbookingID" = %s', r.hb2, r.hb_late))
           LIKE '%cannot move the room to another booking.', 'room was moved to another booking after the deadline';
    ASSERT pg_temp.fails(format('UPDATE hotelbooking SET status = %L WHERE idhotelbooking = %s', 'canceled', r.hb_late))
           LIKE 'Cannot cancel the reservation%', 'booking was canceled after the deadline';
    ASSERT pg_temp.fails(format('UPDATE hotelbooking SET cancellationdate = NULL WHERE idhotelbooking = %s', r.hb_late))
           LIKE 'Cannot update the cancellation date%', 'cancellation date was cleared without a manager';
    UPDATE roombooking SET checkout = '2030-03-07' WHERE "hotelbookingID" = r.hb_late;      -- η παράταση επιτρέπεται
END $$;
\echo OK  5.2  after the deadline: no rate cut, no move, no cancel, no clearing of the deadline

DO $$
DECLARE r record; total numeric;
BEGIN
    SELECT * INTO r FROM t;
    total = (SELECT totalamount::numeric FROM hotelbooking WHERE idhotelbooking = r.hb1);
    UPDATE hotelbooking SET payed = true  WHERE idhotelbooking = r.hb1;
    UPDATE hotelbooking SET payed = false WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = 0, 'unpaying did not record a refund';
    UPDATE hotelbooking SET payed = true  WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = total, 'paying twice charged twice';
END $$;
\echo OK  5.1  toggling payed keeps the ledger equal to the amount charged

DO $$
DECLARE r record; total numeric;
BEGIN
    SELECT * INTO r FROM t;
    total = (SELECT totalamount::numeric FROM hotelbooking WHERE idhotelbooking = r.hb1);
    UPDATE hotelbooking SET status = 'pending' WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = 0, 'pending booking still charged';
    UPDATE hotelbooking SET status = 'confirmed' WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = total, 'confirming a paid booking was not recorded';
    UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = r.hb1;
    ASSERT (SELECT sum(amount) FROM "Transaction" WHERE idhotelbooking = r.hb1) = 0, 'canceling a paid booking was not refunded';
    -- Πληρωμένη κράτηση χωρίς δωμάτια ακόμη: δεν σκάει, χρεώνεται όταν προστεθεί δωμάτιο.
    INSERT INTO hotelbooking VALUES (nextval('idhbooking'), current_date, current_date + 5, NULL, r.client_id, true, 'cash', 'confirmed');
END $$;
\echo OK  5.1  status changes are recorded; a paid booking can be inserted before its rooms

DO $$
DECLARE r record; ws date = "6_2_next_week_start"(); rate real; hb integer; n_before integer;
BEGIN
    SELECT * INTO r FROM t;
    rate = "5_3_current_room_rate"(r.room_id);
    n_before = (SELECT count(*) FROM hotelbooking);
    UPDATE "6_2_weeklyPlan" SET monday = r.client_doc, tuesday = r.client_doc, wednesday = r.client_doc WHERE "idRoom" = r.room_id;
    SELECT "hotelbookingID" INTO hb FROM roombooking WHERE "roomID" = r.room_id AND checkin = ws + 1;
    UPDATE hotelbooking SET payed = true, paymethod = 'cash' WHERE idhotelbooking = hb;

    UPDATE "6_2_weeklyPlan" SET tuesday = '0' WHERE "idRoom" = r.room_id;                -- σπάσιμο πληρωμένης κράτησης
    ASSERT (SELECT bool_and(h.payed) FROM hotelbooking h JOIN roombooking rb ON rb."hotelbookingID" = h.idhotelbooking
            WHERE rb."roomID" = r.room_id AND rb.checkin >= ws AND rb.checkin < ws + 7), 'second half lost its paid flag';
    ASSERT (SELECT sum(tr.amount) FROM "Transaction" tr
            WHERE tr.idhotelbooking IN (SELECT idhotelbooking FROM hotelbooking WHERE idhotelbooking >= hb)) = (rate * 2)::numeric,
           'freeing one of three paid nights should leave two nights charged';

    UPDATE "6_2_weeklyPlan" SET monday = '0', wednesday = '0' WHERE "idRoom" = r.room_id;
    ASSERT (SELECT count(*) FROM hotelbooking) = n_before, 'empty hotel bookings were left behind';
END $$;
\echo OK  6.2  splitting a paid booking keeps it paid; freeing every night leaves no empty booking

DO $$
DECLARE r record; ws date = "6_2_next_week_start"();
BEGIN
    SELECT * INTO r FROM t;
    -- Διαμονή που έχει αρχίσει και τελειώνει την Κυριακή της επόμενης εβδομάδας: παράταση μέσω της όψης.
    INSERT INTO roombooking VALUES (r.hb2, r.room2_id, r.client_id, current_date - 1, ws, NULL);
    UPDATE "6_2_weeklyPlan" SET sunday = r.client_doc WHERE "idRoom" = r.room2_id;
    ASSERT (SELECT checkout FROM roombooking WHERE "hotelbookingID" = r.hb2) = ws + 1, 'in-house stay was not extended through the view';
    UPDATE "6_2_weeklyPlan" SET sunday = '0' WHERE "idRoom" = r.room2_id;
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;

    -- Κράτηση χωρίς υπεύθυνο πρόσωπο δεν φαίνεται ως ελεύθερη.
    INSERT INTO roombooking VALUES (r.hb2, r.room2_id, NULL, ws + 1, ws + 2, NULL);
    ASSERT (SELECT monday FROM "6_2_weeklyPlan" WHERE "idRoom" = r.room2_id) <> '0', 'booking without a person shown as free';
    DELETE FROM roombooking WHERE "hotelbookingID" = r.hb2;
END $$;
\echo OK  6.2  an in-house stay can be extended; a booking without a person is not shown as free

DO $$
DECLARE pid integer;
BEGIN
    ASSERT pg_temp.fails($q$SELECT "2_1_update_clients_and_cards"('insert', 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'TEST-EXP', current_date - 1, 'A B')$q$)
           LIKE 'Card has expired%', '2.1: expired card accepted';
    ASSERT NOT EXISTS (SELECT 1 FROM client WHERE documentclient = 'ZZ-TEST-2'), '2.1: client left behind without a card';

    PERFORM "2_1_update_clients_and_cards"('insert', 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'TEST-0003', current_date + 30, 'A B');
    SELECT "idClient" INTO pid FROM client WHERE documentclient = 'ZZ-TEST-2';
    DELETE FROM creditcard WHERE "clientID" = pid;
    ASSERT "2_1_update_clients_and_cards"('update', 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'TEST-0004', current_date + 30, 'A B'),
           '2.1: update returned false';
    ASSERT (SELECT number FROM creditcard WHERE "clientID" = pid) = 'TEST-0004', '2.1: update did not add the missing card';
END $$;
\echo OK  2.1  an expired card leaves nothing behind; update adds a missing card

DO $$
DECLARE before_max integer = (SELECT max(idhotelbooking) FROM hotelbooking);
BEGIN
    PERFORM "2_2_insertRandomBookings"(11, '2031-01-01', '2031-12-31', 6);
    ASSERT (SELECT count(*) FROM hotelbooking WHERE idhotelbooking > before_max) = 6, '2.2: expected 6 bookings';
    ASSERT (SELECT count(DISTINCT (rb.checkin, rb.checkout)) FROM roombooking rb WHERE rb."hotelbookingID" > before_max) > 1,
           '2.2: every booking got the same dates';
    ASSERT NOT EXISTS (SELECT 1 FROM hotelbooking hb JOIN employee e ON e."idEmployee" = hb."bookedbyclientID"
                       WHERE hb.idhotelbooking > before_max AND e."hotelID" = 11), '2.2: booked by a hotel employee';
    ASSERT NOT EXISTS (SELECT 1 FROM roombooking rb JOIN employee e ON e."idEmployee" = rb."bookedforpersonID"
                       WHERE rb."hotelbookingID" > before_max AND e."hotelID" = 11), '2.2: room given to a hotel employee';
END $$;
\echo OK  2.2  each booking has its own dates; hotel employees are excluded

ROLLBACK;
\echo ALL TESTS PASSED
