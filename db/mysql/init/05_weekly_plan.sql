-- Ερώτημα 6.2 σε MySQL 8.4: εβδομαδιαίο πλάνο δωματίων. Το αρχείο μπορεί να ξανατρέξει.
--
-- Η όψη `6_2_weeklyPlan` δείχνει την εβδομάδα μετά την τρέχουσα (Κυριακή έως Σάββατο), μία γραμμή
-- ανά δωμάτιο: τιμή, έκπτωση και για κάθε ημέρα το documentclient του πελάτη ή '0' αν είναι ελεύθερο.
--
-- Στην PostgreSQL η όψη ενημερώνεται με UPDATE, μέσω INSTEAD OF triggers. Η MySQL δεν έχει
-- INSTEAD OF triggers, οπότε την ίδια δουλειά κάνει η συνάρτηση `6_2_weeklyPlan_update`:
--
--   SELECT `6_2_weeklyPlan_update`(idRoom, rate, discount,
--                                  sunday, monday, tuesday, wednesday, thursday, friday, saturday);
--
-- Όρισμα NULL = «μην το αλλάξεις». Σε ημέρα: documentclient = κλείσιμο για τον πελάτη, '0' ή '' =
-- απελευθέρωση. Είναι συνάρτηση (όχι procedure) ώστε όλες οι αλλαγές της να γίνονται ή να
-- αναιρούνται μαζί. Παράδειγμα: κλείσιμο της Δευτέρας στο δωμάτιο 250 και μετά απελευθέρωση:
--
--   SELECT `6_2_weeklyPlan_update`(250, NULL, NULL, NULL, 'AB123456', NULL, NULL, NULL, NULL, NULL);
--   SELECT `6_2_weeklyPlan_update`(250, NULL, NULL, NULL, '0',        NULL, NULL, NULL, NULL, NULL);

SET NAMES utf8mb4;

DROP VIEW IF EXISTS `6_2_weeklyPlan`;
DROP FUNCTION IF EXISTS `6_2_weeklyPlan_update`;
DROP FUNCTION IF EXISTS `6_2_book_room_day`;
DROP FUNCTION IF EXISTS `6_2_free_room_day`;
DROP FUNCTION IF EXISTS `6_2_room_occupant`;
DROP FUNCTION IF EXISTS `6_2_next_week_start`;

DELIMITER $$

-- Κυριακή της επόμενης εβδομάδας (DAYOFWEEK: Κυριακή = 1).
CREATE FUNCTION `6_2_next_week_start`()
RETURNS DATE
NO SQL
BEGIN
    RETURN DATE_ADD(CURRENT_DATE, INTERVAL 7 - (DAYOFWEEK(CURRENT_DATE) - 1) DAY);
END$$

-- Ποιος έχει το δωμάτιο τη νύχτα p_day: documentclient, ή '0' αν είναι ελεύθερο.
-- Σε απευθείας σύγκριση με σταθερά θέλει COLLATE: `6_2_room_occupant`(2, CURRENT_DATE) COLLATE utf8mb4_0900_as_cs = '0'.
CREATE FUNCTION `6_2_room_occupant`(p_room_id INT, p_day DATE)
RETURNS VARCHAR(60)
READS SQL DATA
BEGIN
    RETURN COALESCE(
        (SELECT COALESCE(cl.documentclient, CONCAT('person ', COALESCE(CAST(rb.bookedforpersonID AS CHAR), '?')))
         FROM roombooking rb
         LEFT JOIN client cl ON cl.idClient = rb.bookedforpersonID
         WHERE rb.roomID = p_room_id AND rb.checkin <= p_day AND rb.checkout > p_day
         ORDER BY rb.checkin, rb.hotelbookingID
         LIMIT 1),
        '0');
END$$

-- Κλείνει τη νύχτα p_day του δωματίου για τον πελάτη με το documentclient p_document.
CREATE FUNCTION `6_2_book_room_day`(p_room_id INT, p_day DATE, p_document VARCHAR(45))
RETURNS INT
MODIFIES SQL DATA
BEGIN
    DECLARE v_client_id INT;
    DECLARE v_neighbour INT;
    DECLARE v_new_booking INT;

    SET v_client_id = (SELECT cl.idClient FROM client cl WHERE cl.documentclient = p_document);
    IF v_client_id IS NULL THEN
        CALL hotel_raise(CONCAT('There is no client with document client ', COALESCE(p_document, 'NULL'), '.'));
    END IF;

    -- Ο ίδιος πελάτης έχει το δωμάτιο ως την προηγούμενη νύχτα: παράταση.
    SET v_neighbour = (SELECT x.hotelbookingID FROM roombooking x
                       WHERE x.roomID = p_room_id AND x.bookedforpersonID = v_client_id AND x.checkout = p_day
                       LIMIT 1);
    IF v_neighbour IS NOT NULL THEN
        UPDATE roombooking SET checkout = DATE_ADD(p_day, INTERVAL 1 DAY)
        WHERE hotelbookingID = v_neighbour AND roomID = p_room_id;
        RETURN v_neighbour;
    END IF;

    -- Ο ίδιος πελάτης έχει το δωμάτιο από την επόμενη νύχτα: νωρίτερο checkin.
    SET v_neighbour = (SELECT x.hotelbookingID FROM roombooking x
                       WHERE x.roomID = p_room_id AND x.bookedforpersonID = v_client_id
                         AND x.checkin = DATE_ADD(p_day, INTERVAL 1 DAY)
                       LIMIT 1);
    IF v_neighbour IS NOT NULL THEN
        UPDATE roombooking SET checkin = p_day
        WHERE hotelbookingID = v_neighbour AND roomID = p_room_id;
        RETURN v_neighbour;
    END IF;

    INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
    VALUES (CURRENT_DATE, DATE_SUB(p_day, INTERVAL 1 DAY), NULL,      -- δωρεάν ακύρωση ως την παραμονή
            v_client_id, FALSE, NULL, 'confirmed');
    SET v_new_booking = LAST_INSERT_ID();

    INSERT INTO roombooking (hotelbookingID, roomID, bookedforpersonID, checkin, checkout, rate)
    VALUES (v_new_booking, p_room_id, v_client_id, p_day, DATE_ADD(p_day, INTERVAL 1 DAY), NULL);
    RETURN v_new_booking;
END$$

-- Ελευθερώνει τη νύχτα p_day του δωματίου. Επιστρέφει 1 αν άλλαξε κάτι, 0 αν ήταν ήδη ελεύθερο.
CREATE FUNCTION `6_2_free_room_day`(p_room_id INT, p_day DATE)
RETURNS INT
MODIFIES SQL DATA
BEGIN
    DECLARE v_booking INT;
    DECLARE v_person INT;
    DECLARE v_checkin DATE;
    DECLARE v_checkout DATE;
    DECLARE v_new_booking INT;
    DECLARE v_next_day DATE DEFAULT DATE_ADD(p_day, INTERVAL 1 DAY);

    SET v_booking = (SELECT x.hotelbookingID FROM roombooking x
                     WHERE x.roomID = p_room_id AND x.checkin <= p_day AND x.checkout > p_day
                     ORDER BY x.checkin, x.hotelbookingID
                     LIMIT 1);
    IF v_booking IS NULL THEN
        RETURN 0;                                 -- ήδη ελεύθερο
    END IF;

    SELECT x.bookedforpersonID, x.checkin, x.checkout INTO v_person, v_checkin, v_checkout
    FROM roombooking x
    WHERE x.hotelbookingID = v_booking AND x.roomID = p_room_id;

    IF v_checkin = p_day AND v_checkout = v_next_day THEN
        DELETE FROM roombooking WHERE hotelbookingID = v_booking AND roomID = p_room_id;
        -- Αν ήταν το τελευταίο δωμάτιο, δεν μένει άδεια κράτηση πίσω.
        IF NOT EXISTS (SELECT 1 FROM roombooking x WHERE x.hotelbookingID = v_booking) THEN
            DELETE FROM hotelbooking WHERE idhotelbooking = v_booking;
        END IF;
    ELSEIF v_checkin = p_day THEN
        UPDATE roombooking SET checkin = v_next_day
        WHERE hotelbookingID = v_booking AND roomID = p_room_id;
    ELSEIF v_checkout = v_next_day THEN
        UPDATE roombooking SET checkout = p_day
        WHERE hotelbookingID = v_booking AND roomID = p_room_id;
    ELSE
        -- Νύχτα στη μέση: το πρώτο μισό μένει στην ίδια κράτηση, το δεύτερο πάει σε νέα.
        UPDATE roombooking SET checkout = p_day
        WHERE hotelbookingID = v_booking AND roomID = p_room_id;

        INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
        SELECT hb.reservationdate, hb.cancellationdate, NULL, hb.bookedbyclientID, hb.payed, hb.paymethod, hb.status
        FROM hotelbooking hb
        WHERE hb.idhotelbooking = v_booking;
        SET v_new_booking = LAST_INSERT_ID();

        INSERT INTO roombooking (hotelbookingID, roomID, bookedforpersonID, checkin, checkout, rate)
        VALUES (v_new_booking, p_room_id, v_person, v_next_day, v_checkout, NULL);

        -- Η νέα κράτηση κρατά την κατάσταση πληρωμής και τους υπαλλήλους που τη διαχειρίζονται.
        INSERT INTO Manages (employeeid, idhotelbooking)
        SELECT m.employeeid, v_new_booking FROM Manages m WHERE m.idhotelbooking = v_booking;
    END IF;
    RETURN 1;
END$$

-- Ενημέρωση μιας γραμμής του πλάνου (βλ. επικεφαλίδα). Επιστρέφει το πλήθος των αλλαγών.
CREATE FUNCTION `6_2_weeklyPlan_update`(
    p_room_id INT, p_rate FLOAT, p_discount FLOAT,
    p_sunday VARCHAR(45), p_monday VARCHAR(45), p_tuesday VARCHAR(45), p_wednesday VARCHAR(45),
    p_thursday VARCHAR(45), p_friday VARCHAR(45), p_saturday VARCHAR(45))
RETURNS INT
MODIFIES SQL DATA
BEGIN
    DECLARE v_hotel_id INT;
    DECLARE v_roomtype VARCHAR(45);
    DECLARE v_has_rate INT;
    DECLARE v_old_rate FLOAT;
    DECLARE v_old_discount FLOAT;
    DECLARE v_new_rate FLOAT;
    DECLARE v_new_discount FLOAT;
    DECLARE v_week_start DATE DEFAULT `6_2_next_week_start`();
    DECLARE v_i INT;
    DECLARE v_day DATE;
    DECLARE v_requested VARCHAR(45);
    DECLARE v_new_doc VARCHAR(60);
    DECLARE v_changes INT DEFAULT 0;
    -- Ποιος έχει το δωμάτιο κάθε ημέρα πριν από οποιαδήποτε αλλαγή.
    DECLARE v_old1, v_old2, v_old3, v_old4, v_old5, v_old6, v_old7 VARCHAR(60);

    SELECT r.idHotel, r.roomtype INTO v_hotel_id, v_roomtype FROM room r WHERE r.idRoom = p_room_id;
    IF v_hotel_id IS NULL THEN
        CALL hotel_raise(CONCAT('There is no room with id ', COALESCE(CAST(p_room_id AS CHAR), 'NULL'), '.'));
    END IF;

    IF p_rate IS NOT NULL OR p_discount IS NOT NULL THEN
        SELECT COUNT(*), MAX(rr.rate), MAX(rr.discount) INTO v_has_rate, v_old_rate, v_old_discount
        FROM roomrate rr
        WHERE rr.idHotel = v_hotel_id AND rr.roomtype <=> v_roomtype;
        IF v_has_rate = 0 OR v_old_rate IS NULL THEN
            CALL hotel_raise(CONCAT('There is no rate for room type ', COALESCE(v_roomtype, 'NULL'), ' in hotel ',
                                    v_hotel_id, '. Add a row to roomrate first.'));
        END IF;
        SET v_new_rate = COALESCE(p_rate, v_old_rate);
        SET v_new_discount = COALESCE(p_discount, v_old_discount);
        IF NOT (v_new_rate <=> v_old_rate) OR NOT (v_new_discount <=> v_old_discount) THEN
            IF v_new_rate < 0 OR v_new_discount IS NULL OR v_new_discount < 0 OR v_new_discount > 100 THEN
                CALL hotel_raise('Rate must be >= 0 and discount between 0 and 100.');
            END IF;
            UPDATE roomrate SET rate = v_new_rate, discount = v_new_discount
            WHERE idHotel = v_hotel_id AND roomtype = v_roomtype;
            SET v_changes = v_changes + 1;
        END IF;
    END IF;

    SET v_old1 = `6_2_room_occupant`(p_room_id, v_week_start);
    SET v_old2 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 1 DAY));
    SET v_old3 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 2 DAY));
    SET v_old4 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 3 DAY));
    SET v_old5 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 4 DAY));
    SET v_old6 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 5 DAY));
    SET v_old7 = `6_2_room_occupant`(p_room_id, DATE_ADD(v_week_start, INTERVAL 6 DAY));

    -- Πρώτα όλες οι απελευθερώσεις, μετά όλα τα κλεισίματα, ώστε να μη συγκρούονται.
    SET v_i = 1;
    WHILE v_i <= 7 DO
        SET v_requested = ELT(v_i, p_sunday, p_monday, p_tuesday, p_wednesday, p_thursday, p_friday, p_saturday);
        IF v_requested IS NOT NULL THEN
            SET v_new_doc = COALESCE(NULLIF(TRIM(v_requested), ''), '0');
            IF v_new_doc <> ELT(v_i, v_old1, v_old2, v_old3, v_old4, v_old5, v_old6, v_old7)
               AND ELT(v_i, v_old1, v_old2, v_old3, v_old4, v_old5, v_old6, v_old7) <> '0' THEN
                SET v_day = DATE_ADD(v_week_start, INTERVAL v_i - 1 DAY);
                SET v_changes = v_changes + `6_2_free_room_day`(p_room_id, v_day);
            END IF;
        END IF;
        SET v_i = v_i + 1;
    END WHILE;

    SET v_i = 1;
    WHILE v_i <= 7 DO
        SET v_requested = ELT(v_i, p_sunday, p_monday, p_tuesday, p_wednesday, p_thursday, p_friday, p_saturday);
        IF v_requested IS NOT NULL THEN
            SET v_new_doc = COALESCE(NULLIF(TRIM(v_requested), ''), '0');
            IF v_new_doc <> ELT(v_i, v_old1, v_old2, v_old3, v_old4, v_old5, v_old6, v_old7)
               AND v_new_doc <> '0' THEN
                SET v_day = DATE_ADD(v_week_start, INTERVAL v_i - 1 DAY);
                IF `6_2_book_room_day`(p_room_id, v_day, v_new_doc) > 0 THEN
                    SET v_changes = v_changes + 1;
                END IF;
            END IF;
        END IF;
        SET v_i = v_i + 1;
    END WHILE;

    RETURN v_changes;
END$$

DELIMITER ;

-- Το COLLATE επιτρέπει σύγκριση των ημερών με κείμενο (monday = '0') από οποιαδήποτε σύνδεση.
CREATE VIEW `6_2_weeklyPlan` AS
SELECT r.idHotel,
       r.idRoom,
       r.number AS room_number,
       r.roomtype,
       rr.rate,
       rr.discount,
       w.week_start,
       `6_2_room_occupant`(r.idRoom, w.week_start) COLLATE utf8mb4_0900_as_cs AS sunday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 1 DAY)) COLLATE utf8mb4_0900_as_cs AS monday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 2 DAY)) COLLATE utf8mb4_0900_as_cs AS tuesday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 3 DAY)) COLLATE utf8mb4_0900_as_cs AS wednesday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 4 DAY)) COLLATE utf8mb4_0900_as_cs AS thursday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 5 DAY)) COLLATE utf8mb4_0900_as_cs AS friday,
       `6_2_room_occupant`(r.idRoom, DATE_ADD(w.week_start, INTERVAL 6 DAY)) COLLATE utf8mb4_0900_as_cs AS saturday
FROM room r
LEFT JOIN roomrate rr ON rr.idHotel = r.idHotel AND rr.roomtype = r.roomtype
CROSS JOIN (SELECT `6_2_next_week_start`() AS week_start) w
ORDER BY r.idHotel, r.number, r.idRoom;
