-- Διορθώσεις πάνω στο σχήμα της αρχικής παράδοσης (PostgreSQL 16).
-- Εφαρμόζεται ΜΕΤΑ το restore του Phase2/project_base.backup, μέσω του apply.sql.
-- Μπορεί να ξανατρέξει χωρίς πρόβλημα (CREATE OR REPLACE / IF EXISTS).
--
-- Σύμβαση διαθεσιμότητας: μια κράτηση δωματίου πιάνει τις νύχτες [checkin, checkout).
-- Την ημέρα του checkout το δωμάτιο θεωρείται ελεύθερο για νέο checkin. Είναι η σύμβαση
-- που ήδη ακολουθούν τα 3.7, 3.8 και ο υπολογισμός rate * (checkout - checkin).

-- ---------------------------------------------------------------------------------------
-- 0. Sequences: στο backup είναι πίσω από τα μέγιστα id, οπότε κάθε nextval() έδινε
--    duplicate key (έτσι έσκαγε το 2.2).
-- ---------------------------------------------------------------------------------------
SELECT setval('idperson',      GREATEST((SELECT max("idPerson")      FROM person),        1));
SELECT setval('idhotel',       GREATEST((SELECT max("idHotel")       FROM hotel),         1));
SELECT setval('idroom',        GREATEST((SELECT max("idRoom")        FROM room),          1));
SELECT setval('idhbooking',    GREATEST((SELECT max(idhotelbooking)  FROM hotelbooking),  1));
SELECT setval('idtransaction', (SELECT COALESCE(max(idtransaction), 0) + 1 FROM "Transaction"), false);

-- ---------------------------------------------------------------------------------------
-- 2.1  Το action 'update' έσκαγε: "UPDATE person p2 SET p2.fname = ..." δεν είναι έγκυρη
--      σύνταξη (στο SET δεν μπαίνει alias) και χρησιμοποιούνταν η ανύπαρκτη client_id.
--      Επιπλέον: νέο id από το sequence αντί για max+1, και σφάλμα όταν ο πελάτης δεν
--      υπάρχει (πριν το update/delete "πετύχαινε" χωρίς να αλλάξει τίποτα).
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "2_1_update_clients_and_cards"(
    action_in character, documentclient_in character varying, fname_in character varying,
    lname_in character varying, sex_in character, date_of_birth_in date,
    address_in character varying, city_in character varying, country_in character varying,
    cardtype_in character varying, number_card_in character varying,
    expiration_card_in date, holder_in character varying)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    success   boolean = false;
    id_client integer;
BEGIN

IF action_in = 'insert' THEN
    IF EXISTS (SELECT 1 FROM client cl WHERE cl.documentclient = documentclient_in) THEN
        RAISE EXCEPTION 'The document client must be unique and there is other client with this document client.';
    END IF;

    id_client = nextval('idperson');
    INSERT INTO person VALUES (id_client, fname_in, lname_in, sex_in, date_of_birth_in, address_in, city_in, country_in);
    INSERT INTO client VALUES (id_client, documentclient_in);

    IF cardtype_in IS NOT NULL AND number_card_in IS NOT NULL THEN
        IF expiration_card_in >= current_date THEN
            IF expiration_card_in = current_date THEN
                RAISE NOTICE 'Card is expiring today.Person Id=%', id_client;
            END IF;
            INSERT INTO creditcard VALUES (cardtype_in, number_card_in, expiration_card_in, holder_in, id_client);
            success = true;
        ELSE
            -- Πριν ήταν NOTICE: ο πελάτης έμενε στη βάση χωρίς κάρτα και η συνάρτηση γύριζε false.
            RAISE EXCEPTION 'Card has expired. Need to insert new card. Person Id=%', id_client;
        END IF;
    ELSE
        RAISE EXCEPTION 'Card type or card number cannot be null. Person Id=%', id_client;
    END IF;

ELSIF action_in = 'delete' THEN
    id_client = (SELECT cl."idClient" FROM client cl WHERE cl.documentclient = documentclient_in);
    IF id_client IS NULL THEN
        RAISE EXCEPTION 'There is no client with document client %.', documentclient_in;
    END IF;
    -- Οι κρατήσεις σβήνονται ρητά πριν από το πρόσωπο. Με σκέτο cascade η σειρά δεν είναι
    -- εγγυημένη: το trigger που ξαναϋπολογίζει το totalamount μπορεί να ενημερώσει κράτηση της
    -- οποίας ο πελάτης έχει ήδη σβηστεί, και τότε η διαγραφή αποτυγχάνει με σφάλμα ξένου κλειδιού
    -- (συμβαίνει όταν η κράτηση δημιουργήθηκε μέσα στην ίδια συναλλαγή).
    DELETE FROM roombooking rb WHERE rb."bookedforpersonID" = id_client;
    DELETE FROM hotelbooking hb WHERE hb."bookedbyclientID" = id_client;
    DELETE FROM person p1 WHERE p1."idPerson" = id_client;   -- client και creditcard φεύγουν με cascade
    success = true;

ELSIF action_in = 'update' THEN
    id_client = (SELECT cl."idClient" FROM client cl WHERE cl.documentclient = documentclient_in);
    IF id_client IS NULL THEN
        RAISE EXCEPTION 'There is no client with document client %.', documentclient_in;
    END IF;

    UPDATE person
    SET fname = fname_in,
        lname = lname_in,
        sex = sex_in,
        dateofbirth = date_of_birth_in,
        address = address_in,
        city = city_in,
        country = country_in
    WHERE "idPerson" = id_client;

    IF cardtype_in IS NOT NULL AND number_card_in IS NOT NULL THEN
        IF expiration_card_in >= current_date THEN
            IF expiration_card_in = current_date THEN
                RAISE NOTICE 'Card is expiring today.Person Id=%', id_client;
            END IF;
            UPDATE creditcard
            SET cardtype = cardtype_in,
                number = number_card_in,
                expiration = expiration_card_in,
                holder = holder_in
            WHERE "clientID" = id_client;
            IF NOT FOUND THEN       -- ο πελάτης δεν είχε κάρτα: προστίθεται
                INSERT INTO creditcard VALUES (cardtype_in, number_card_in, expiration_card_in, holder_in, id_client);
            END IF;
            success = true;
        ELSE
            RAISE EXCEPTION 'Card has expired. Need to insert new card. Person Id=%', id_client;
        END IF;
    ELSE
        success = true;             -- ενημέρωση μόνο των στοιχείων του προσώπου
    END IF;

ELSE
    RAISE EXCEPTION 'Unknown action "%". Use insert, update or delete.', action_in;
END IF;

RETURN success;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- Βοηθητικές για τα 2.2 / 5.3: τρέχουσα τιμή δωματίου (με την έκπτωση) και επανυπολογισμός
-- του totalamount μιας κράτησης. Πριν, ο ίδιος κώδικας ήταν αντιγραμμένος σε 4 σημεία.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_3_current_room_rate"(room_id integer)
RETURNS real
LANGUAGE sql STABLE
AS $$
    SELECT (rr.rate - rr.rate * rr.discount / 100)::real
    FROM room AS r
    JOIN roomrate AS rr ON rr."idHotel" = r."idHotel" AND rr.roomtype = r.roomtype
    WHERE r."idRoom" = room_id;
$$;

CREATE OR REPLACE FUNCTION "5_3_refresh_totalamount"(hotelbooking_id integer)
RETURNS void
LANGUAGE sql
AS $$
    UPDATE hotelbooking
    SET totalamount = (SELECT COALESCE(sum(rb.rate * (rb.checkout - rb.checkin)), 0)
                       FROM roombooking AS rb
                       WHERE rb."hotelbookingID" = hotelbooking_id)
    WHERE idhotelbooking = hotelbooking_id;
$$;

-- ---------------------------------------------------------------------------------------
-- 2.2  Έσκαγε για δύο λόγους: τα sequences (βλ. 0) και "FROM person WHERE pe.idPerson"
--      χωρίς alias. Ο έλεγχος διαθεσιμότητας δεν έπιανε κρατήσεις που αρχίζουν μέσα στο
--      διάστημα και τελειώνουν μετά· τώρα είναι ο κανονικός έλεγχος επικάλυψης.
--      Το πλήθος δωματίων και οι ημερομηνίες επιλέγονταν μία φορά για όλες τις κρατήσεις
--      της κλήσης· τώρα ανά κράτηση, όπως ζητά η εκφώνηση. Αποκλείονται οι υπάλληλοι του
--      ξενοδοχείου, που η εκφώνηση δεν επιτρέπει ούτε ως πελάτες ούτε ως υπευθύνους.
--      Το rate και το totalamount τα βάζουν πλέον τα triggers.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "2_2_insertRandomBookings"(hotelid integer, start_date date, finish_date date, n integer)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    random_bookedbyclient integer;
    random_bookedforperson integer;
    random_number_of_rooms integer;
    checkin_date date;
    checkout_date date;
    hotel_bookingid integer;
    country_of_random_bookedbyclient varchar(45);
    random_room_available_from_hotelid integer;
BEGIN
IF finish_date <= start_date THEN
    RAISE EXCEPTION 'finish_date must be after start_date.';
END IF;

FOR i IN 1..n LOOP
    -- Κάθε κράτηση έχει δικό της τυχαίο πλήθος δωματίων (1-5) και δικές της ημερομηνίες:
    -- checkin στο [start, finish) και checkout στο (checkin, finish].
    random_number_of_rooms = floor(random() * 5 + 1)::int;
    checkin_date  = start_date + floor(random() * (finish_date - start_date))::int;
    checkout_date = checkin_date + 1 + floor(random() * (finish_date - checkin_date))::int;

    -- Ο πελάτης που κάνει την κράτηση δεν είναι υπάλληλος του ξενοδοχείου.
    random_bookedbyclient =
        (SELECT cl."idClient"
         FROM client cl
         WHERE NOT EXISTS (SELECT 1 FROM employee e
                           WHERE e."idEmployee" = cl."idClient" AND e."hotelID" = hotelid)
         ORDER BY random() LIMIT 1);
    hotel_bookingid = nextval('idhbooking');
    INSERT INTO hotelbooking
    VALUES (hotel_bookingid, checkin_date - 20, checkin_date - 10, NULL, random_bookedbyclient, false, NULL, 'confirmed');

    country_of_random_bookedbyclient =
        (SELECT pe.country FROM person pe WHERE pe."idPerson" = random_bookedbyclient);

    FOR j IN 1..random_number_of_rooms LOOP
        -- Υπεύθυνος δωματίου: πελάτης από την ίδια χώρα, όχι υπάλληλος του ξενοδοχείου.
        random_bookedforperson =
            (SELECT cl."idClient"
             FROM client cl
             JOIN person pe ON cl."idClient" = pe."idPerson"
             WHERE pe.country = country_of_random_bookedbyclient
               AND NOT EXISTS (SELECT 1 FROM employee e
                               WHERE e."idEmployee" = cl."idClient" AND e."hotelID" = hotelid)
             ORDER BY random() LIMIT 1);

        random_room_available_from_hotelid =
            (SELECT r."idRoom"
             FROM room r
             WHERE r."idHotel" = hotelid
               AND NOT EXISTS (SELECT 1 FROM roombooking rb
                               WHERE rb."roomID" = r."idRoom"
                                 AND rb.checkin < checkout_date
                                 AND rb.checkout > checkin_date)
             ORDER BY random() LIMIT 1);

        IF random_room_available_from_hotelid IS NULL THEN
            RAISE EXCEPTION 'No available room. Cannot add other room.';
        END IF;

        INSERT INTO roombooking
        VALUES (hotel_bookingid, random_room_available_from_hotelid, random_bookedforperson,
                checkin_date, checkout_date, NULL);
    END LOOP;
END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- 4.1  (α) Το λάθος που αναφέρει η αναφορά: έλεγχος σε checkout αντί για checkin, άρα
--          έμεναν έξω όσοι μένουν τώρα στο ξενοδοχείο.
--      (β) Το join με το roombooking πολλαπλασίαζε το πλήθος: πελάτης με 3 κρατήσεις
--          δωματίων και 1 συμμετοχή έβγαινε με 3 δραστηριότητες.
--      Τώρα: μία γραμμή ανά (πελάτη, ξενοδοχείο στο οποίο έμεινε ή μένει) με το πλήθος των
--      συμμετοχών του σε δραστηριότητες εκείνου του ξενοδοχείου (0 αν δεν έχει).
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "4_1_find_clients_activities"()
RETURNS TABLE(id_client integer, id_hotel integer, num_of_activities bigint)
LANGUAGE plpgsql
AS $$
BEGIN
RETURN QUERY
SELECT stays.client_id, stays.hotel_id, count(pa.amka_person)
FROM (SELECT DISTINCT cl."idClient" AS client_id, r."idHotel" AS hotel_id
      FROM client AS cl
      JOIN roombooking AS rb ON rb."bookedforpersonID" = cl."idClient"
      JOIN room AS r ON r."idRoom" = rb."roomID"
      WHERE rb.checkin <= current_date) AS stays
LEFT JOIN "Participates" AS pa
       ON pa.amka_person = stays.client_id
      AND pa.idhotel = stays.hotel_id
      AND pa.participant_role = 'participant'
GROUP BY stays.client_id, stays.hotel_id
ORDER BY stays.client_id, stays.hotel_id;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- 5.1  Η διαγραφή πληρωμένης κράτησης έσκαγε: στο DELETE χρησιμοποιούνταν το NEW (που
--      είναι NULL). Και με το OLD όμως η εγγραφή επιστροφής δεν μπορούσε να μείνει, γιατί
--      το Transaction είχε ξένο κλειδί με ON DELETE CASCADE προς την κράτηση που μόλις
--      σβήστηκε. Ο πίνακας συνδιαλλαγών είναι ιστορικό, άρα το ξένο κλειδί αφαιρείται:
--      οι συνδιαλλαγές μένουν και μετά τη διαγραφή της κράτησης.
--      Επίσης η αρχική λογική έχανε συνδιαλλαγές: payed true -> false -> true χρέωνε δύο
--      φορές, και οι αλλαγές status (pending -> confirmed, confirmed -> canceled) δεν
--      καταγράφονταν. Τώρα καταγράφεται πάντα η διαφορά του εισπραγμένου ποσού.
-- ---------------------------------------------------------------------------------------
ALTER TABLE "Transaction" DROP CONSTRAINT IF EXISTS "Transaction_idhotelbooking_fkey";

CREATE OR REPLACE FUNCTION "5_1_transaction_update"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    -- Ποσό που έχει εισπραχθεί για την κράτηση: το totalamount όταν είναι πληρωμένη και
    -- επιβεβαιωμένη, αλλιώς 0. Κάθε αλλαγή του γράφεται ως διαφορά, ώστε το άθροισμα των
    -- συνδιαλλαγών μιας κράτησης να ισούται πάντα με το ποσό αυτό.
    old_charged numeric = 0;
    new_charged numeric = 0;
BEGIN
IF TG_OP IN ('UPDATE', 'DELETE') THEN
    IF OLD.payed AND OLD.status = 'confirmed' THEN
        old_charged = COALESCE(OLD.totalamount, 0)::numeric;
    END IF;
END IF;
IF TG_OP IN ('INSERT', 'UPDATE') THEN
    IF NEW.payed AND NEW.status = 'confirmed' THEN
        new_charged = COALESCE(NEW.totalamount, 0)::numeric;
    END IF;
END IF;

IF TG_OP = 'INSERT' THEN
    IF new_charged > 0 THEN
        INSERT INTO "Transaction" VALUES (nextval('idtransaction'), NEW.idhotelbooking, 'insert', new_charged, current_date);
    END IF;
    RETURN NEW;
ELSIF TG_OP = 'UPDATE' THEN
    IF new_charged <> old_charged THEN
        INSERT INTO "Transaction" VALUES (nextval('idtransaction'), NEW.idhotelbooking, 'update', new_charged - old_charged, current_date);
    END IF;
    RETURN NEW;
ELSE
    IF old_charged > 0 THEN
        INSERT INTO "Transaction" VALUES (nextval('idtransaction'), OLD.idhotelbooking, 'delete', -old_charged, current_date);
    END IF;
    RETURN OLD;
END IF;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- 5.2  Ενημέρωση κράτησης ξενοδοχείου. Η σύγκριση "!=" δεν έπιανε αλλαγή από/προς NULL,
--      άρα η προθεσμία ακύρωσης μηδενιζόταν χωρίς manager και μετά η κράτηση σβηνόταν.
--      Επίσης η ακύρωση (status = canceled) μετά την προθεσμία δεν ελεγχόταν καθόλου.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_hotelbooking_update"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.cancellationdate IS DISTINCT FROM OLD.cancellationdate THEN
        IF NOT EXISTS (SELECT 1
                       FROM "Manages" m
                       JOIN employee e ON e."idEmployee" = m.employeeid
                       WHERE m.idhotelbooking = OLD.idhotelbooking AND e.role = 'manager') THEN
            RAISE EXCEPTION 'Cannot update the cancellation date. Only the manager can.';
        END IF;
    END IF;

    IF NEW.status = 'canceled' AND OLD.status IS DISTINCT FROM 'canceled'
       AND OLD.cancellationdate < current_date THEN
        RAISE EXCEPTION 'Cannot cancel the reservation. The cancellation date has passed.';
    END IF;
    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- 5.2 / 5.3  Εισαγωγή κράτησης δωματίου.
--   BEFORE: ο έλεγχος διαθεσιμότητας χρησιμοποιούσε OLD."roomID", που σε INSERT είναι
--           NULL, άρα περνούσε πάντα και το ίδιο δωμάτιο κλεινόταν δύο φορές. Τώρα NEW.
--           Το rate μπαίνει εδώ (τρέχουσα τιμή με την έκπτωση).
--   AFTER:  πριν έκανε UPDATE στο ίδιο το roombooking για να βάλει το rate, πράγμα που
--           πυροδοτούσε τα triggers του UPDATE (και απέρριπτε κάθε κράτηση με checkin έως
--           σήμερα). Τώρα απλώς επανυπολογίζει το totalamount.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_insert"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
IF NOT EXISTS (SELECT 1 FROM hotelbooking hb WHERE hb.idhotelbooking = NEW."hotelbookingID") THEN
    RAISE EXCEPTION 'Hotel booking does not exist!';
END IF;

IF EXISTS (SELECT 1 FROM roombooking rb
           WHERE rb."roomID" = NEW."roomID" AND rb."hotelbookingID" = NEW."hotelbookingID") THEN
    RAISE EXCEPTION 'This room booking already exists.';
END IF;

IF NEW.checkin IS NULL OR NEW.checkout IS NULL THEN
    RAISE EXCEPTION 'The checkin and the checkout cannot be null.';
END IF;

IF NEW.checkout <= NEW.checkin THEN
    RAISE EXCEPTION 'The checkout must be after the checkin.';
END IF;

-- Κλείδωμα ανά δωμάτιο ως το τέλος της συναλλαγής: δύο ταυτόχρονες εισαγωγές για το ίδιο
-- δωμάτιο εκτελούνται η μία μετά την άλλη, άρα η δεύτερη βλέπει την πρώτη.
PERFORM pg_advisory_xact_lock(NEW."roomID");

IF EXISTS (SELECT 1 FROM roombooking rb
           WHERE rb."roomID" = NEW."roomID"
             AND rb.checkin < NEW.checkout
             AND rb.checkout > NEW.checkin) THEN
    RAISE EXCEPTION 'The room is not available.';
END IF;

NEW.rate = "5_3_current_room_rate"(NEW."roomID");
IF NEW.rate IS NULL THEN
    RAISE EXCEPTION 'There is no rate for this room type in this hotel.';
END IF;
RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_insert"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM "5_3_refresh_totalamount"(NEW."hotelbookingID");
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_update"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM "5_3_refresh_totalamount"(NEW."hotelbookingID");
    IF OLD."hotelbookingID" <> NEW."hotelbookingID" THEN
        PERFORM "5_3_refresh_totalamount"(OLD."hotelbookingID");
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_delete"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM "5_3_refresh_totalamount"(OLD."hotelbookingID");
    RETURN OLD;
END;
$$;

-- ---------------------------------------------------------------------------------------
-- 6.1  Η όψη είχε καρφωτό το 'Ramblewood Inn', έβγαζε μόνο δωμάτια που έχουν μελλοντική
--      κράτηση (όσα δεν είχαν καμία χάνονταν) και δεν απέκλειε όσα είναι πιασμένα σήμερα.
--      Τώρα καλύπτει όλα τα ξενοδοχεία· φιλτράρεται με WHERE ή με τη συνάρτηση από κάτω.
--      available_until = NULL σημαίνει "δεν υπάρχει επόμενη κράτηση".
-- ---------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS "6_1_availableRoomsByHotel_function"(character varying);
DROP VIEW IF EXISTS "6_1_availableRoomsByHotel";

CREATE VIEW "6_1_availableRoomsByHotel" AS
SELECT h."idHotel",
       h.name AS hotel_name,
       r."idRoom",
       r.number AS room_number,
       r.roomtype,
       (SELECT min(rb.checkin) - 1
        FROM roombooking AS rb
        WHERE rb."roomID" = r."idRoom" AND rb.checkin > current_date) AS available_until
FROM hotel AS h
JOIN room AS r ON r."idHotel" = h."idHotel"
WHERE NOT EXISTS (SELECT 1
                  FROM roombooking AS rb
                  WHERE rb."roomID" = r."idRoom"
                    AND rb.checkin <= current_date
                    AND rb.checkout > current_date);

CREATE FUNCTION "6_1_availableRoomsByHotel_function"(hotel_name_in character varying)
RETURNS TABLE(room_id integer, room_number integer, room_type character varying, available_until date)
LANGUAGE sql STABLE
AS $$
    SELECT v."idRoom", v.room_number, v.roomtype, v.available_until
    FROM "6_1_availableRoomsByHotel" AS v
    WHERE v.hotel_name = hotel_name_in
    ORDER BY v.room_number;
$$;
