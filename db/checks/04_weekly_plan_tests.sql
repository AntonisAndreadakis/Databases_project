-- Δοκιμές της όψης 6.2 (db/fixes/03_weekly_plan_view.sql). Τρέχουν μέσα σε transaction
-- που κάνει ROLLBACK, άρα δεν αφήνουν τίποτα στη βάση. Σταματούν στο πρώτο λάθος.
-- Εκτέλεση:  docker compose exec db psql -U postgres -d hotel -f /sql/checks/04_weekly_plan_tests.sql
-- Αναμένονται 3 γραμμές "OK ..." και στο τέλος "ALL TESTS PASSED".

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

-- 6.2 ---------------------------------------------------------------------------------
DO $$
DECLARE r record; ws date; p record;
BEGIN
    SELECT * INTO r FROM t;
    ws = "6_2_next_week_start"();
    ASSERT extract(dow FROM ws) = 0 AND ws > current_date AND ws <= current_date + 7, '6.2: week start is not next Sunday';

    UPDATE "6_2_weeklyPlan" SET monday = r.client_doc, tuesday = r.client_doc, wednesday = r.client_doc
    WHERE "idRoom" = r.room_id;
    SELECT * INTO p FROM "6_2_weeklyPlan" WHERE "idRoom" = r.room_id;
    ASSERT p.sunday = '0' AND p.monday = r.client_doc AND p.wednesday = r.client_doc AND p.thursday = '0', '6.2: days not booked';
    ASSERT (SELECT count(*) FROM roombooking WHERE "roomID" = r.room_id AND checkin = ws + 1 AND checkout = ws + 4) = 1,
           '6.2: three nights should be one room booking';

    UPDATE "6_2_weeklyPlan" SET tuesday = '0' WHERE "idRoom" = r.room_id;            -- νύχτα στη μέση
    SELECT * INTO p FROM "6_2_weeklyPlan" WHERE "idRoom" = r.room_id;
    ASSERT p.monday = r.client_doc AND p.tuesday = '0' AND p.wednesday = r.client_doc, '6.2: middle night not freed';

    UPDATE "6_2_weeklyPlan" SET monday = '0', wednesday = '0' WHERE "idRoom" = r.room_id;
    ASSERT NOT EXISTS (SELECT 1 FROM roombooking WHERE "roomID" = r.room_id AND checkout > ws AND checkin < ws + 7),
           '6.2: room should be free all week';
END $$;
\echo OK  6.2  nights are booked, split and freed through the view

DO $$
DECLARE r record; p record;
BEGIN
    SELECT * INTO r FROM t;
    UPDATE "6_2_weeklyPlan" SET rate = 123, discount = 10 WHERE "idRoom" = r.room_id;
    SELECT * INTO p FROM "6_2_weeklyPlan" WHERE "idRoom" = r.room_id;
    ASSERT p.rate = 123 AND p.discount = 10, '6.2: rate/discount not updated';
    ASSERT "5_3_current_room_rate"(r.room_id) = 110.7::real, '6.2: roomrate not updated';
END $$;
\echo OK  6.2  rate and discount are updated through the view

DO $$
DECLARE r record; failures integer = 0;
BEGIN
    SELECT * INTO r FROM t;
    BEGIN UPDATE "6_2_weeklyPlan" SET room_number = 999 WHERE "idRoom" = r.room_id;
    EXCEPTION WHEN raise_exception THEN failures = failures + 1; END;
    BEGIN UPDATE "6_2_weeklyPlan" SET friday = 'NO-SUCH-DOCUMENT' WHERE "idRoom" = r.room_id;
    EXCEPTION WHEN raise_exception THEN failures = failures + 1; END;
    BEGIN DELETE FROM "6_2_weeklyPlan" WHERE "idRoom" = r.room_id;
    EXCEPTION WHEN raise_exception THEN failures = failures + 1; END;
    ASSERT failures = 3, '6.2: a forbidden change was accepted';
END $$;
\echo OK  6.2  other columns, unknown clients and deletes are rejected

ROLLBACK;
\echo ALL TESTS PASSED
