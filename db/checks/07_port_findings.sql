-- Δοκιμές για δύο ελαττώματα που βρέθηκαν όταν η βάση συγκρίθηκε με τη μεταφορά της σε MySQL.
-- Τρέχουν μέσα σε transaction που κάνει ROLLBACK. Σταματούν στο πρώτο λάθος.
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/07_port_findings.sql
-- Αναμένονται 2 γραμμές "OK ..." και στο τέλος "ALL TESTS PASSED".
--
-- ΠΡΟΣΟΧΗ: ο πρώτος έλεγχος πρέπει να είναι το πρώτο UPDATE του roombooking στη σύνδεση. Το λάθος
-- που πιάνει εμφανιζόταν μόνο τότε, γι' αυτό το αρχείο τρέχει μόνο του και όχι μετά από άλλο.

\set ON_ERROR_STOP on
\set QUIET on
\pset pager off
SET client_min_messages = warning;

BEGIN;

-- Ένας πελάτης και ένα δωμάτιο του ξενοδοχείου 11, με μία κράτηση τριών νυχτών.
CREATE TEMP TABLE t ON COMMIT DROP AS
SELECT c."idClient" AS client_id, r."idRoom" AS room_id, r."idHotel" AS hotel_id, r.roomtype,
       nextval('idhbooking')::int AS hb
FROM (SELECT * FROM client ORDER BY "idClient" LIMIT 1) AS c,
     (SELECT * FROM room WHERE "idHotel" = 11 ORDER BY "idRoom" LIMIT 1) AS r;

INSERT INTO hotelbooking
SELECT t.hb, current_date, current_date + 5, NULL, t.client_id, false, NULL, 'confirmed' FROM t;
INSERT INTO roombooking
SELECT t.hb, t.room_id, t.client_id, DATE '2031-03-01', DATE '2031-03-04', NULL FROM t;

-- ---------------------------------------------------------------------------------------
-- 5.3: το πρώτο UPDATE μιας σύνδεσης ανανεώνει το rate με την τρέχουσα τιμή.
-- (Πριν, η ρύθμιση hotel.rate_given δεν υπήρχε ακόμα στη σύνδεση, το rate_given έβγαινε NULL
-- και η κράτηση κρατούσε την παλιά τιμή.)
UPDATE roomrate rr SET discount = COALESCE(rr.discount, 0) + 10
FROM t WHERE rr."idHotel" = t.hotel_id AND rr.roomtype = t.roomtype;

UPDATE roombooking rb SET checkout = DATE '2031-03-06' FROM t WHERE rb."hotelbookingID" = t.hb;

DO $$
DECLARE r record;
BEGIN
    SELECT rb.rate, "5_3_current_room_rate"(t.room_id) AS current_rate,
           (SELECT hb.totalamount FROM hotelbooking hb WHERE hb.idhotelbooking = t.hb) AS total
    INTO r FROM t JOIN roombooking rb ON rb."hotelbookingID" = t.hb;
    ASSERT r.rate = r.current_rate, format('5.3: rate %s was not refreshed to %s', r.rate, r.current_rate);
    ASSERT r.total = r.current_rate * 5, format('5.3: total %s, expected %s', r.total, r.current_rate * 5);
END $$;
\echo OK  5.3  the first update of a session refreshes the rate

-- ---------------------------------------------------------------------------------------
-- 2.1: διαγραφή πελάτη με κρατήσεις που δημιουργήθηκαν στην ίδια συναλλαγή.
-- (Πριν, αποτύγχανε με παραβίαση του ξένου κλειδιού "bookedbyclientID_FK".)
SELECT "2_1_update_clients_and_cards"('insert', 'ZZ-PORT-1', 'Test', 'Client', 'F', DATE '1990-01-01',
       'Street 1', 'Chania', 'Greece', 'VISA', 'ZZ-PORT-CARD-1', current_date + 365, 'TEST CLIENT') \gset ins_

CREATE TEMP TABLE n ON COMMIT DROP AS
SELECT cl."idClient" AS new_id, nextval('idhbooking')::int AS own_hb,
       (SELECT r."idRoom" FROM room r, t WHERE r."idHotel" = 11 AND r."idRoom" <> t.room_id
        ORDER BY r."idRoom" LIMIT 1) AS room2_id
FROM client cl WHERE cl.documentclient = 'ZZ-PORT-1';

-- Δική του κράτηση με ένα δωμάτιο, και ένα δωμάτιο μέσα στην κράτηση του άλλου πελάτη.
INSERT INTO hotelbooking
SELECT n.own_hb, current_date, current_date + 5, NULL, n.new_id, false, NULL, 'confirmed' FROM n;
INSERT INTO roombooking
SELECT n.own_hb, n.room2_id, n.new_id, DATE '2032-03-01', DATE '2032-03-03', NULL FROM n;
INSERT INTO roombooking
SELECT t.hb, n.room2_id, n.new_id, DATE '2031-03-01', DATE '2031-03-03', NULL FROM t, n;

SELECT "2_1_update_clients_and_cards"('delete', 'ZZ-PORT-1', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL) \gset del_

DO $$
DECLARE r record;
BEGIN
    ASSERT NOT EXISTS (SELECT 1 FROM person p, n WHERE p."idPerson" = n.new_id), '2.1: the person is still there';
    ASSERT NOT EXISTS (SELECT 1 FROM hotelbooking hb, n WHERE hb.idhotelbooking = n.own_hb), '2.1: own booking is still there';
    ASSERT NOT EXISTS (SELECT 1 FROM roombooking rb, n WHERE rb."bookedforpersonID" = n.new_id), '2.1: a room booking is still there';
    -- Η κράτηση του άλλου πελάτη έμεινε, με ένα δωμάτιο λιγότερο και σωστό ποσό.
    SELECT hb.totalamount AS total,
           (SELECT sum(rb.rate * (rb.checkout - rb.checkin)) FROM roombooking rb WHERE rb."hotelbookingID" = t.hb) AS real_sum,
           (SELECT count(*) FROM roombooking rb WHERE rb."hotelbookingID" = t.hb) AS rooms
    INTO r FROM t JOIN hotelbooking hb ON hb.idhotelbooking = t.hb;
    ASSERT r.rooms = 1, format('2.1: the other booking has %s rooms, expected 1', r.rooms);
    ASSERT r.total = r.real_sum, format('2.1: the other booking has total %s, real sum %s', r.total, r.real_sum);
END $$;
\echo OK  2.1  a client whose bookings were made in the same transaction can be deleted

ROLLBACK;
\echo ALL TESTS PASSED
