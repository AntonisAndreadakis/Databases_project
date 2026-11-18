-- 6.2  Εβδομαδιαίο πλάνο κρατήσεων (δεν είχε υλοποιηθεί στην αρχική παράδοση).
--
-- Η όψη "6_2_weeklyPlan" δίνει, για την εβδομάδα ΜΕΤΑ την τρέχουσα (Κυριακή έως Σάββατο),
-- μία γραμμή ανά δωμάτιο: αριθμός δωματίου, τιμή, έκπτωση και, για κάθε ημέρα, το
-- documentclient του πελάτη που έχει το δωμάτιο εκείνη τη νύχτα ή '0' αν είναι ελεύθερο.
--
--   SELECT * FROM "6_2_weeklyPlan" WHERE "idHotel" = 11;        -- ένα ξενοδοχείο
--
-- Επιτρέπονται μόνο UPDATE, και μόνο σε: rate, discount και στις επτά στήλες ημερών.
--   UPDATE "6_2_weeklyPlan" SET monday = 'AB123' WHERE "idRoom" = 250;   -- κλείσιμο
--   UPDATE "6_2_weeklyPlan" SET monday = '0'     WHERE "idRoom" = 250;   -- απελευθέρωση
--   UPDATE "6_2_weeklyPlan" SET discount = 20    WHERE "idRoom" = 250;
--
-- Τι κάνει το trigger στους βασικούς πίνακες:
--   rate / discount  -> UPDATE στο roomrate για (ξενοδοχείο, τύπο δωματίου). Η τιμή ορίζεται
--                       ανά τύπο, άρα αλλάζει για όλα τα δωμάτια του ίδιου τύπου.
--   '0' -> έγγραφο   -> αν ο ίδιος πελάτης έχει ήδη το δωμάτιο την προηγούμενη ή την επόμενη
--                       νύχτα, επεκτείνεται εκείνη η κράτηση· αλλιώς δημιουργείται νέα
--                       hotelbooking + roombooking μίας νύχτας.
--   έγγραφο -> '0'   -> η κράτηση που καλύπτει τη νύχτα κονταίνει, σβήνεται (αν ήταν μόνο
--                       εκείνη η νύχτα) ή, αν η νύχτα είναι στη μέση, σπάει στα δύο (το
--                       δεύτερο μισό γίνεται νέα hotelbooking, γιατί το κλειδί του
--                       roombooking είναι (κράτηση, δωμάτιο)).
-- Όλα περνούν από τα triggers του roombooking, άρα ισχύουν οι κανόνες του 5.2/5.3
-- (διαθεσιμότητα, προθεσμία ακύρωσης, rate, totalamount, συνδιαλλαγές).

CREATE OR REPLACE FUNCTION "6_2_next_week_start"()
RETURNS date
LANGUAGE sql STABLE
AS $$
    -- Κυριακή της επόμενης εβδομάδας (extract(dow): Κυριακή = 0).
    SELECT current_date - extract(dow FROM current_date)::int + 7;
$$;

-- Το documentclient όποιου έχει το δωμάτιο τη νύχτα day_in, αλλιώς '0'.
CREATE OR REPLACE FUNCTION "6_2_room_occupant"(room_id integer, day_in date)
RETURNS character varying
LANGUAGE sql STABLE
AS $$
    SELECT COALESCE(
        (SELECT COALESCE(cl.documentclient, 'person ' || COALESCE(rb."bookedforpersonID"::text, '?'))
         FROM roombooking AS rb
         LEFT JOIN client AS cl ON cl."idClient" = rb."bookedforpersonID"
         WHERE rb."roomID" = room_id AND rb.checkin <= day_in AND rb.checkout > day_in
         ORDER BY rb.checkin, rb."hotelbookingID"
         LIMIT 1),
        '0');
$$;

DROP VIEW IF EXISTS "6_2_weeklyPlan";

CREATE VIEW "6_2_weeklyPlan" AS
SELECT r."idHotel",
       r."idRoom",
       r.number AS room_number,
       r.roomtype,
       rr.rate,
       rr.discount,
       w.week_start,
       "6_2_room_occupant"(r."idRoom", w.week_start)     AS sunday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 1) AS monday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 2) AS tuesday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 3) AS wednesday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 4) AS thursday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 5) AS friday,
       "6_2_room_occupant"(r."idRoom", w.week_start + 6) AS saturday
FROM room AS r
LEFT JOIN roomrate AS rr ON rr."idHotel" = r."idHotel" AND rr.roomtype = r.roomtype
CROSS JOIN (SELECT "6_2_next_week_start"() AS week_start) AS w
ORDER BY r."idHotel", r.number, r."idRoom";

-- Απελευθέρωση ενός δωματίου για μία νύχτα.
CREATE OR REPLACE FUNCTION "6_2_free_room_day"(room_id integer, day_in date)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    rb roombooking%ROWTYPE;
    new_booking_id integer;
BEGIN
    SELECT * INTO rb
    FROM roombooking AS x
    WHERE x."roomID" = room_id AND x.checkin <= day_in AND x.checkout > day_in
    ORDER BY x.checkin, x."hotelbookingID"
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN;                                   -- ήδη ελεύθερο
    END IF;

    IF rb.checkin = day_in AND rb.checkout = day_in + 1 THEN
        DELETE FROM roombooking
        WHERE "hotelbookingID" = rb."hotelbookingID" AND "roomID" = room_id;
        -- Αν ήταν το τελευταίο δωμάτιο, δεν μένει άδεια κράτηση πίσω.
        DELETE FROM hotelbooking AS hb
        WHERE hb.idhotelbooking = rb."hotelbookingID"
          AND NOT EXISTS (SELECT 1 FROM roombooking AS x WHERE x."hotelbookingID" = hb.idhotelbooking);
    ELSIF rb.checkin = day_in THEN
        UPDATE roombooking SET checkin = day_in + 1
        WHERE "hotelbookingID" = rb."hotelbookingID" AND "roomID" = room_id;
    ELSIF rb.checkout = day_in + 1 THEN
        UPDATE roombooking SET checkout = day_in
        WHERE "hotelbookingID" = rb."hotelbookingID" AND "roomID" = room_id;
    ELSE
        -- Νύχτα στη μέση: το πρώτο μισό μένει στην ίδια κράτηση, το δεύτερο πάει σε νέα.
        UPDATE roombooking SET checkout = day_in
        WHERE "hotelbookingID" = rb."hotelbookingID" AND "roomID" = room_id;

        new_booking_id = nextval('idhbooking');
        INSERT INTO hotelbooking (idhotelbooking, reservationdate, cancellationdate, totalamount,
                                  "bookedbyclientID", payed, paymethod, status)
        SELECT new_booking_id, hb.reservationdate, hb.cancellationdate, NULL,
               hb."bookedbyclientID", hb.payed, hb.paymethod, hb.status
        FROM hotelbooking AS hb
        WHERE hb.idhotelbooking = rb."hotelbookingID";

        INSERT INTO roombooking ("hotelbookingID", "roomID", "bookedforpersonID", checkin, checkout, rate)
        VALUES (new_booking_id, room_id, rb."bookedforpersonID", day_in + 1, rb.checkout, NULL);

        -- Η νέα κράτηση κρατά την κατάσταση πληρωμής και τους υπαλλήλους που τη διαχειρίζονται.
        INSERT INTO "Manages" (employeeid, idhotelbooking)
        SELECT m.employeeid, new_booking_id FROM "Manages" AS m WHERE m.idhotelbooking = rb."hotelbookingID";
    END IF;
END;
$$;

-- Κλείσιμο ενός δωματίου για μία νύχτα, για τον πελάτη με το έγγραφο document_in.
CREATE OR REPLACE FUNCTION "6_2_book_room_day"(room_id integer, day_in date, document_in character varying)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    client_id integer;
    neighbour_booking integer;
    new_booking_id integer;
BEGIN
    SELECT cl."idClient" INTO client_id FROM client AS cl WHERE cl.documentclient = document_in;
    IF client_id IS NULL THEN
        RAISE EXCEPTION 'There is no client with document client %.', document_in;
    END IF;

    -- Ο ίδιος πελάτης έχει το δωμάτιο ως την προηγούμενη νύχτα: παράταση.
    SELECT x."hotelbookingID" INTO neighbour_booking
    FROM roombooking AS x
    WHERE x."roomID" = room_id AND x."bookedforpersonID" = client_id AND x.checkout = day_in
    LIMIT 1;
    IF FOUND THEN
        UPDATE roombooking SET checkout = day_in + 1
        WHERE "hotelbookingID" = neighbour_booking AND "roomID" = room_id;
        RETURN;
    END IF;

    -- Ο ίδιος πελάτης έχει το δωμάτιο από την επόμενη νύχτα: νωρίτερο checkin.
    SELECT x."hotelbookingID" INTO neighbour_booking
    FROM roombooking AS x
    WHERE x."roomID" = room_id AND x."bookedforpersonID" = client_id AND x.checkin = day_in + 1
    LIMIT 1;
    IF FOUND THEN
        UPDATE roombooking SET checkin = day_in
        WHERE "hotelbookingID" = neighbour_booking AND "roomID" = room_id;
        RETURN;
    END IF;

    new_booking_id = nextval('idhbooking');
    INSERT INTO hotelbooking (idhotelbooking, reservationdate, cancellationdate, totalamount,
                              "bookedbyclientID", payed, paymethod, status)
    VALUES (new_booking_id, current_date, day_in - 1, NULL,       -- δωρεάν ακύρωση ως την παραμονή
            client_id, false, NULL, 'confirmed');

    INSERT INTO roombooking ("hotelbookingID", "roomID", "bookedforpersonID", checkin, checkout, rate)
    VALUES (new_booking_id, room_id, client_id, day_in, day_in + 1, NULL);
END;
$$;

CREATE OR REPLACE FUNCTION "6_2_weeklyPlan_update"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    old_days character varying[] = ARRAY[OLD.sunday, OLD.monday, OLD.tuesday, OLD.wednesday,
                                         OLD.thursday, OLD.friday, OLD.saturday];
    new_days character varying[] = ARRAY[NEW.sunday, NEW.monday, NEW.tuesday, NEW.wednesday,
                                         NEW.thursday, NEW.friday, NEW.saturday];
    new_doc character varying;
BEGIN
    IF NEW."idHotel" IS DISTINCT FROM OLD."idHotel"
       OR NEW."idRoom" IS DISTINCT FROM OLD."idRoom"
       OR NEW.room_number IS DISTINCT FROM OLD.room_number
       OR NEW.roomtype IS DISTINCT FROM OLD.roomtype
       OR NEW.week_start IS DISTINCT FROM OLD.week_start THEN
        RAISE EXCEPTION 'Only rate, discount and the seven day columns can be updated through this view.';
    END IF;

    IF NEW.rate IS DISTINCT FROM OLD.rate OR NEW.discount IS DISTINCT FROM OLD.discount THEN
        IF OLD.rate IS NULL THEN
            RAISE EXCEPTION 'There is no rate for room type % in hotel %. Add a row to roomrate first.', OLD.roomtype, OLD."idHotel";
        END IF;
        IF NEW.rate IS NULL OR NEW.rate < 0 OR NEW.discount IS NULL OR NEW.discount < 0 OR NEW.discount > 100 THEN
            RAISE EXCEPTION 'Rate must be >= 0 and discount between 0 and 100.';
        END IF;
        UPDATE roomrate SET rate = NEW.rate, discount = NEW.discount
        WHERE "idHotel" = OLD."idHotel" AND roomtype = OLD.roomtype;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'There is no rate for room type % in hotel %.', OLD.roomtype, OLD."idHotel";
        END IF;
    END IF;

    -- Πρώτα όλες οι απελευθερώσεις, μετά όλα τα κλεισίματα, ώστε να μη συγκρούονται.
    FOR i IN 1..7 LOOP
        new_doc = COALESCE(NULLIF(btrim(new_days[i]), ''), '0');
        IF new_doc IS DISTINCT FROM old_days[i] AND old_days[i] <> '0' THEN
            PERFORM "6_2_free_room_day"(OLD."idRoom", OLD.week_start + (i - 1));
        END IF;
    END LOOP;

    FOR i IN 1..7 LOOP
        new_doc = COALESCE(NULLIF(btrim(new_days[i]), ''), '0');
        IF new_doc IS DISTINCT FROM old_days[i] AND new_doc <> '0' THEN
            PERFORM "6_2_book_room_day"(OLD."idRoom", OLD.week_start + (i - 1), new_doc);
        END IF;
    END LOOP;

    RETURN NEW;
END;
$$;

CREATE TRIGGER "6_2_weeklyPlan_update"
    INSTEAD OF UPDATE ON "6_2_weeklyPlan"
    FOR EACH ROW EXECUTE FUNCTION "6_2_weeklyPlan_update"();

CREATE OR REPLACE FUNCTION "6_2_weeklyPlan_readonly"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Rows cannot be inserted into or deleted from the weekly plan; only updates are allowed.';
END;
$$;

CREATE TRIGGER "6_2_weeklyPlan_readonly"
    INSTEAD OF INSERT OR DELETE ON "6_2_weeklyPlan"
    FOR EACH ROW EXECUTE FUNCTION "6_2_weeklyPlan_readonly"();
