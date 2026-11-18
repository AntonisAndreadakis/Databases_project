-- Ερωτήματα 1.1 (έλεγχοι), 2.1, 2.2 και 5.1-5.3 σε MySQL 8.4.
-- Μεταφορά των διορθωμένων συναρτήσεων και triggers της PostgreSQL. Το αρχείο μπορεί να ξανατρέξει.
--
-- Τι αλλάζει σε σχέση με την PostgreSQL:
--   * RAISE EXCEPTION -> SIGNAL SQLSTATE '45000' (μέσω της hotel_raise). Τα RAISE NOTICE δεν έχουν
--     αντίστοιχο και παραλείπονται.
--   * Τα 2.1 και 2.2 μένουν ΣΥΝΑΡΤΗΣΕΙΣ (καλούνται με SELECT): έτσι ό,τι κάνουν είναι μία εντολή
--     και, αν αποτύχει στη μέση, αναιρείται ολόκληρο, όπως στην PostgreSQL.
--   * Ένα trigger «INSERT OR UPDATE OR DELETE» γίνεται τρία triggers.
--   * Οι δύο CHECK που καλούσαν συνάρτηση (Manages, Participates) γίνονται triggers.
--   * Το κλείδωμα ανά δωμάτιο (pg_advisory_xact_lock) γίνεται κλείδωμα μιας γραμμής του βοηθητικού
--     πίνακα room_lock (SELECT ... FOR UPDATE), που κρατά επίσης ως το τέλος της συναλλαγής. Δεν
--     κλειδώνεται η γραμμή του ίδιου του room: τότε κάθε εντολή στο roombooking που διαβάζει το room
--     (π.χ. για να βρει το δωμάτιο από τον αριθμό του) θα απορριπτόταν με σφάλμα 1442.
--   * Η MySQL δεν εκτελεί triggers για γραμμές που σβήνονται με ON DELETE CASCADE. Γι' αυτό τα
--     BEFORE DELETE triggers των person, client, room, roomtype και hotel σβήνουν πρώτα ρητά τις
--     κρατήσεις, ώστε να ισχύσουν οι κανόνες του 5.2 και να ενημερωθούν ποσά και συνδιαλλαγές.
--   * Το trigger ενημέρωσης δεν μπορεί να ξέρει αν το UPDATE όρισε ρητά rate (δεν υπάρχει
--     «BEFORE UPDATE OF rate»). Θεωρεί ότι ορίστηκε όταν η νέα τιμή διαφέρει από την παλιά.

SET NAMES utf8mb4;

DROP TRIGGER IF EXISTS manages_check_insert;
DROP TRIGGER IF EXISTS manages_check_update;
DROP TRIGGER IF EXISTS participates_check_insert;
DROP TRIGGER IF EXISTS participates_check_update;
DROP TRIGGER IF EXISTS transaction_edit_insert;
DROP TRIGGER IF EXISTS transaction_edit_update;
DROP TRIGGER IF EXISTS transaction_edit_delete;
DROP TRIGGER IF EXISTS hotelbooking_update;
DROP TRIGGER IF EXISTS hotelbooking_delete;
DROP TRIGGER IF EXISTS before_roombooking_insert;
DROP TRIGGER IF EXISTS before_roombooking_update;
DROP TRIGGER IF EXISTS before_roombooking_delete;
DROP TRIGGER IF EXISTS after_roombooking_insert;
DROP TRIGGER IF EXISTS after_roombooking_update;
DROP TRIGGER IF EXISTS after_roombooking_delete;
DROP TRIGGER IF EXISTS room_lock_insert;
DROP TRIGGER IF EXISTS person_delete_bookings;
DROP TRIGGER IF EXISTS client_delete_bookings;
DROP TRIGGER IF EXISTS room_delete_bookings;
DROP TRIGGER IF EXISTS roomtype_delete_rooms;
DROP TRIGGER IF EXISTS hotel_delete_rooms;
DROP PROCEDURE IF EXISTS hotel_raise;
DROP PROCEDURE IF EXISTS `5_3_refresh_totalamount`;
DROP FUNCTION IF EXISTS `1_1_check_employee_for_booking`;
DROP FUNCTION IF EXISTS `1_1_check_person_for_participating`;
DROP FUNCTION IF EXISTS `2_1_update_clients_and_cards`;
DROP FUNCTION IF EXISTS `2_2_insertRandomBookings`;
DROP FUNCTION IF EXISTS `5_3_current_room_rate`;

-- Μία γραμμή ανά δωμάτιο, μόνο για κλείδωμα (βλ. επικεφαλίδα). Τη συντηρούν το trigger
-- room_lock_insert και το ON DELETE CASCADE.
CREATE TABLE IF NOT EXISTS room_lock (
    idRoom INT NOT NULL,
    CONSTRAINT room_lock_PK PRIMARY KEY (idRoom),
    CONSTRAINT room_lock_FK FOREIGN KEY (idRoom) REFERENCES room (idRoom)
        ON UPDATE CASCADE ON DELETE CASCADE
);
INSERT IGNORE INTO room_lock (idRoom) SELECT idRoom FROM room;

DELIMITER $$

CREATE TRIGGER room_lock_insert AFTER INSERT ON room FOR EACH ROW
BEGIN
    INSERT IGNORE INTO room_lock (idRoom) VALUES (NEW.idRoom);
END$$

-- Σφάλμα με μήνυμα (το MESSAGE_TEXT χωρά ως 128 χαρακτήρες).
CREATE PROCEDURE hotel_raise(p_message VARCHAR(255))
BEGIN
    DECLARE v_message VARCHAR(128) DEFAULT LEFT(p_message, 128);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = v_message;
END$$

-- ---------------------------------------------------------------------------------------------
-- 1.1: οι δύο έλεγχοι που στην PostgreSQL ήταν CHECK
-- ---------------------------------------------------------------------------------------------

-- Ο υπάλληλος είναι manager ή reception στο ξενοδοχείο της κράτησης;
CREATE FUNCTION `1_1_check_employee_for_booking`(p_idemployee INT, p_idhotelbooking INT)
RETURNS TINYINT(1)
READS SQL DATA
BEGIN
    DECLARE v_role VARCHAR(20);
    SET v_role = (SELECT e.role
                  FROM employee e
                  WHERE e.idEmployee = p_idemployee
                    AND e.hotelID = (SELECT DISTINCT r.idHotel
                                     FROM room r
                                     WHERE r.idRoom IN (SELECT rb.roomID FROM roombooking rb
                                                        WHERE rb.hotelbookingID = p_idhotelbooking)));
    RETURN COALESCE(v_role IN ('manager', 'reception'), FALSE);
END$$

-- 'participant': το πρόσωπο έχει κράτηση δωματίου στο ξενοδοχείο. 'responsible': είναι υπάλληλός του.
CREATE FUNCTION `1_1_check_person_for_participating`(p_idperson INT, p_id_hotel INT, p_role VARCHAR(20))
RETURNS TINYINT(1)
READS SQL DATA
BEGIN
    IF p_role = 'participant' THEN
        RETURN EXISTS (SELECT 1
                       FROM roombooking rb
                       JOIN room r ON r.idRoom = rb.roomID
                       WHERE r.idHotel = p_id_hotel AND rb.bookedforpersonID = p_idperson);
    ELSEIF p_role = 'responsible' THEN
        RETURN EXISTS (SELECT 1 FROM employee e
                       WHERE e.hotelID = p_id_hotel AND e.idEmployee = p_idperson);
    END IF;
    RETURN TRUE;
END$$

CREATE TRIGGER manages_check_insert BEFORE INSERT ON Manages FOR EACH ROW
BEGIN
    IF NOT `1_1_check_employee_for_booking`(NEW.employeeid, NEW.idhotelbooking) THEN
        CALL hotel_raise('Manages: the employee must be manager or reception of the hotel of the booking (check_role_emp).');
    END IF;
END$$

CREATE TRIGGER manages_check_update BEFORE UPDATE ON Manages FOR EACH ROW
BEGIN
    IF NOT `1_1_check_employee_for_booking`(NEW.employeeid, NEW.idhotelbooking) THEN
        CALL hotel_raise('Manages: the employee must be manager or reception of the hotel of the booking (check_role_emp).');
    END IF;
END$$

CREATE TRIGGER participates_check_insert BEFORE INSERT ON Participates FOR EACH ROW
BEGIN
    IF NOT `1_1_check_person_for_participating`(NEW.amka_person, NEW.idhotel, NEW.participant_role) THEN
        CALL hotel_raise('Participates: the person does not fit this role in this hotel (check_person_participating).');
    END IF;
END$$

CREATE TRIGGER participates_check_update BEFORE UPDATE ON Participates FOR EACH ROW
BEGIN
    IF NOT `1_1_check_person_for_participating`(NEW.amka_person, NEW.idhotel, NEW.participant_role) THEN
        CALL hotel_raise('Participates: the person does not fit this role in this hotel (check_person_participating).');
    END IF;
END$$

-- ---------------------------------------------------------------------------------------------
-- 5.3: βοηθητικά
-- ---------------------------------------------------------------------------------------------

-- Τρέχουσα τιμή ενός δωματίου, με την έκπτωση (NULL αν ο τύπος του δεν έχει τιμή στο ξενοδοχείο).
CREATE FUNCTION `5_3_current_room_rate`(p_room_id INT)
RETURNS FLOAT
READS SQL DATA
BEGIN
    RETURN (SELECT rr.rate - rr.rate * rr.discount / 100
            FROM room r
            JOIN roomrate rr ON rr.idHotel = r.idHotel AND rr.roomtype = r.roomtype
            WHERE r.idRoom = p_room_id);
END$$

-- Το totalamount μιας κράτησης είναι το άθροισμα (τιμή x νύχτες) των δωματίων της.
CREATE PROCEDURE `5_3_refresh_totalamount`(p_hotelbooking_id INT)
BEGIN
    DECLARE v_total DOUBLE;
    SET v_total = (SELECT COALESCE(SUM(rb.rate * DATEDIFF(rb.checkout, rb.checkin)), 0)
                   FROM roombooking rb
                   WHERE rb.hotelbookingID = p_hotelbooking_id);
    UPDATE hotelbooking SET totalamount = v_total WHERE idhotelbooking = p_hotelbooking_id;
END$$

-- ---------------------------------------------------------------------------------------------
-- 5.1: καταγραφή συνδιαλλαγών
-- Εισπραγμένο ποσό μιας κράτησης = totalamount όταν είναι πληρωμένη και επιβεβαιωμένη, αλλιώς 0.
-- Κάθε αλλαγή του γράφεται ως διαφορά, ώστε το άθροισμα των συνδιαλλαγών να ισούται με αυτό.
-- ---------------------------------------------------------------------------------------------

CREATE TRIGGER transaction_edit_insert AFTER INSERT ON hotelbooking FOR EACH ROW
BEGIN
    DECLARE v_new DECIMAL(16, 4) DEFAULT 0;
    IF NEW.payed AND NEW.status = 'confirmed' THEN
        SET v_new = COALESCE(NEW.totalamount, 0);
    END IF;
    IF v_new > 0 THEN
        INSERT INTO `Transaction` (idhotelbooking, action_tr, amount, made_date)
        VALUES (NEW.idhotelbooking, 'insert', v_new, CURRENT_DATE);
    END IF;
END$$

CREATE TRIGGER transaction_edit_update AFTER UPDATE ON hotelbooking FOR EACH ROW
BEGIN
    DECLARE v_old DECIMAL(16, 4) DEFAULT 0;
    DECLARE v_new DECIMAL(16, 4) DEFAULT 0;
    IF OLD.payed AND OLD.status = 'confirmed' THEN
        SET v_old = COALESCE(OLD.totalamount, 0);
    END IF;
    IF NEW.payed AND NEW.status = 'confirmed' THEN
        SET v_new = COALESCE(NEW.totalamount, 0);
    END IF;
    IF v_new <> v_old THEN
        INSERT INTO `Transaction` (idhotelbooking, action_tr, amount, made_date)
        VALUES (NEW.idhotelbooking, 'update', v_new - v_old, CURRENT_DATE);
    END IF;
END$$

CREATE TRIGGER transaction_edit_delete AFTER DELETE ON hotelbooking FOR EACH ROW
BEGIN
    DECLARE v_old DECIMAL(16, 4) DEFAULT 0;
    IF OLD.payed AND OLD.status = 'confirmed' THEN
        SET v_old = COALESCE(OLD.totalamount, 0);
    END IF;
    IF v_old > 0 THEN
        INSERT INTO `Transaction` (idhotelbooking, action_tr, amount, made_date)
        VALUES (OLD.idhotelbooking, 'delete', -v_old, CURRENT_DATE);
    END IF;
END$$

-- ---------------------------------------------------------------------------------------------
-- 5.2: κανόνες για την κράτηση (hotelbooking)
-- ---------------------------------------------------------------------------------------------

CREATE TRIGGER hotelbooking_update BEFORE UPDATE ON hotelbooking FOR EACH ROW
BEGIN
    -- Την προθεσμία ακύρωσης την αλλάζει μόνο κράτηση που τη διαχειρίζεται manager.
    IF NOT (NEW.cancellationdate <=> OLD.cancellationdate) THEN
        IF NOT EXISTS (SELECT 1
                       FROM Manages m
                       JOIN employee e ON e.idEmployee = m.employeeid
                       WHERE m.idhotelbooking = OLD.idhotelbooking AND e.role = 'manager') THEN
            CALL hotel_raise('Cannot update the cancellation date. Only the manager can.');
        END IF;
    END IF;

    IF NEW.status = 'canceled' AND NOT (OLD.status <=> 'canceled')
       AND OLD.cancellationdate < CURRENT_DATE THEN
        CALL hotel_raise('Cannot cancel the reservation. The cancellation date has passed.');
    END IF;
END$$

CREATE TRIGGER hotelbooking_delete BEFORE DELETE ON hotelbooking FOR EACH ROW
BEGIN
    IF OLD.cancellationdate < CURRENT_DATE THEN
        CALL hotel_raise('Cannot delete the reservation.');
    END IF;
END$$

-- ---------------------------------------------------------------------------------------------
-- 5.2 / 5.3: κανόνες για τα δωμάτια της κράτησης (roombooking)
-- Σύμβαση: μια κράτηση πιάνει τις νύχτες από το checkin έως πριν το checkout.
-- ---------------------------------------------------------------------------------------------

CREATE TRIGGER before_roombooking_insert BEFORE INSERT ON roombooking FOR EACH ROW
BEGIN
    DECLARE v_locked_room INT;
    DECLARE v_overlaps INT;

    -- Κλείδωμα του δωματίου ως το τέλος της συναλλαγής, πριν από κάθε ανάγνωση: δύο ταυτόχρονες
    -- κρατήσεις του ίδιου δωματίου εκτελούνται η μία μετά την άλλη.
    SELECT l.idRoom INTO v_locked_room FROM room_lock l WHERE l.idRoom = NEW.roomID FOR UPDATE;

    IF NOT EXISTS (SELECT 1 FROM hotelbooking hb WHERE hb.idhotelbooking = NEW.hotelbookingID) THEN
        CALL hotel_raise('Hotel booking does not exist!');
    END IF;

    IF EXISTS (SELECT 1 FROM roombooking rb
               WHERE rb.roomID = NEW.roomID AND rb.hotelbookingID = NEW.hotelbookingID) THEN
        CALL hotel_raise('This room booking already exists.');
    END IF;

    IF NEW.checkin IS NULL OR NEW.checkout IS NULL THEN
        CALL hotel_raise('The checkin and the checkout cannot be null.');
    END IF;

    IF NEW.checkout <= NEW.checkin THEN
        CALL hotel_raise('The checkout must be after the checkin.');
    END IF;

    -- FOR SHARE: διαβάζει τις τελευταίες επικυρωμένες γραμμές, όχι το στιγμιότυπο της συναλλαγής,
    -- ώστε να φαίνεται η κράτηση που μόλις επικύρωσε άλλη σύνδεση.
    SELECT COUNT(*) INTO v_overlaps
    FROM roombooking rb
    WHERE rb.roomID = NEW.roomID AND rb.checkin < NEW.checkout AND rb.checkout > NEW.checkin
    FOR SHARE;
    IF v_overlaps > 0 THEN
        CALL hotel_raise('The room is not available.');
    END IF;

    SET NEW.rate = `5_3_current_room_rate`(NEW.roomID);
    IF NEW.rate IS NULL THEN
        CALL hotel_raise('There is no rate for this room type in this hotel.');
    END IF;
END$$

CREATE TRIGGER before_roombooking_update BEFORE UPDATE ON roombooking FOR EACH ROW
BEGIN
    DECLARE v_locked_room INT;
    DECLARE v_overlaps INT;
    DECLARE v_canc_date DATE;
    DECLARE v_free_until DATE;
    DECLARE v_rate_given TINYINT(1);
    DECLARE v_current_rate FLOAT;

    IF NEW.checkin IS NULL OR NEW.checkout IS NULL THEN
        CALL hotel_raise('The checkin and the checkout cannot be null.');
    END IF;
    IF NEW.checkout <= NEW.checkin THEN
        CALL hotel_raise('The checkout must be after the checkin.');
    END IF;

    -- Απαγορεύεται μόνο η μετακίνηση ημερομηνίας στο παρελθόν· διαμονή που έχει αρχίσει παρατείνεται.
    IF NEW.checkin <> OLD.checkin AND NEW.checkin < CURRENT_DATE THEN
        CALL hotel_raise('You cannot do this! The new checkin is in the past.');
    END IF;
    IF NEW.checkout <> OLD.checkout AND NEW.checkout < CURRENT_DATE THEN
        CALL hotel_raise('You cannot do this! The new checkout is in the past.');
    END IF;

    -- Το UPDATE όρισε δικό του rate; (βλ. επικεφαλίδα του αρχείου)
    SET v_rate_given = NOT (NEW.rate <=> OLD.rate);

    -- Μετά την προθεσμία ακύρωσης: όχι μεταφορά σε άλλη κράτηση, όχι μείωση τιμής, όχι λιγότερες
    -- νύχτες. (Στην PostgreSQL ο τελευταίος κανόνας είναι γραμμένος ως εννέα περιπτώσεις πάνω στα
    -- checkin/checkout· όλες καταλήγουν σε αυτή τη σύγκριση.)
    SET v_canc_date = (SELECT hb.cancellationdate FROM hotelbooking hb
                       WHERE hb.idhotelbooking = OLD.hotelbookingID);
    IF v_canc_date < CURRENT_DATE THEN
        IF NEW.hotelbookingID <> OLD.hotelbookingID THEN
            CALL hotel_raise('The cancellation date has passed. You cannot move the room to another booking.');
        END IF;
        IF v_rate_given AND NEW.rate < OLD.rate THEN
            CALL hotel_raise('The cancellation date has passed. You cannot decrease the rate.');
        END IF;
        IF DATEDIFF(NEW.checkout, NEW.checkin) < DATEDIFF(OLD.checkout, OLD.checkin) THEN
            CALL hotel_raise('The cancellation date has passed. You cannot decrease the number of days.');
        END IF;
    END IF;

    -- Διαθεσιμότητα, όταν αλλάζουν οι ημερομηνίες ή το δωμάτιο.
    IF NEW.roomID <> OLD.roomID OR NEW.checkin <> OLD.checkin OR NEW.checkout <> OLD.checkout THEN
        SELECT l.idRoom INTO v_locked_room FROM room_lock l WHERE l.idRoom = NEW.roomID FOR UPDATE;

        SELECT COUNT(*) INTO v_overlaps
        FROM roombooking rb
        WHERE rb.roomID = NEW.roomID
          AND NOT (rb.hotelbookingID = OLD.hotelbookingID AND rb.roomID = OLD.roomID)
          AND rb.checkin < NEW.checkout AND rb.checkout > NEW.checkin
        FOR SHARE;

        IF v_overlaps > 0 THEN
            SET v_free_until = (SELECT MIN(rb.checkin) FROM roombooking rb
                                WHERE rb.roomID = NEW.roomID
                                  AND NOT (rb.hotelbookingID = OLD.hotelbookingID AND rb.roomID = OLD.roomID)
                                  AND rb.checkin >= OLD.checkout);
            IF NEW.roomID = OLD.roomID AND NEW.checkin = OLD.checkin AND v_free_until IS NOT NULL THEN
                CALL hotel_raise(CONCAT('The room is not available for these dates. You can extend the checkout up to ',
                                        v_free_until, '.'));
            END IF;
            CALL hotel_raise('The room is not available for these dates.');
        END IF;
    END IF;

    -- Το rate ανανεώνεται με την τρέχουσα τιμή/έκπτωση, εκτός αν το UPDATE όρισε δικό του.
    IF NOT v_rate_given OR NEW.rate IS NULL THEN
        SET v_current_rate = `5_3_current_room_rate`(NEW.roomID);
        IF v_current_rate IS NULL THEN
            CALL hotel_raise('There is no rate for this room type in this hotel.');
        END IF;
        SET NEW.rate = v_current_rate;
    END IF;
END$$

CREATE TRIGGER before_roombooking_delete BEFORE DELETE ON roombooking FOR EACH ROW
BEGIN
    DECLARE v_canc_date DATE;
    SET v_canc_date = (SELECT hb.cancellationdate FROM hotelbooking hb
                       WHERE hb.idhotelbooking = OLD.hotelbookingID);
    IF CURRENT_DATE > v_canc_date THEN
        CALL hotel_raise('Unable to execute operation! Cancelation date has expired.');
    END IF;
END$$

CREATE TRIGGER after_roombooking_insert AFTER INSERT ON roombooking FOR EACH ROW
BEGIN
    CALL `5_3_refresh_totalamount`(NEW.hotelbookingID);
END$$

CREATE TRIGGER after_roombooking_update AFTER UPDATE ON roombooking FOR EACH ROW
BEGIN
    CALL `5_3_refresh_totalamount`(NEW.hotelbookingID);
    IF OLD.hotelbookingID <> NEW.hotelbookingID THEN
        CALL `5_3_refresh_totalamount`(OLD.hotelbookingID);
    END IF;
END$$

CREATE TRIGGER after_roombooking_delete AFTER DELETE ON roombooking FOR EACH ROW
BEGIN
    CALL `5_3_refresh_totalamount`(OLD.hotelbookingID);
END$$

-- ---------------------------------------------------------------------------------------------
-- Διαγραφές που φτάνουν σε κρατήσεις μέσω ON DELETE CASCADE
-- Τα cascades δεν εκτελούν triggers. Εδώ οι κρατήσεις σβήνονται ρητά ΠΡΙΝ από τη γραμμή-γονέα,
-- ώστε να τρέξουν τα triggers τους: έλεγχος προθεσμίας ακύρωσης, totalamount, συνδιαλλαγές.
-- Αν μια κράτηση δεν επιτρέπεται να σβηστεί, απορρίπτεται ολόκληρη η διαγραφή.
-- ---------------------------------------------------------------------------------------------

CREATE TRIGGER person_delete_bookings BEFORE DELETE ON person FOR EACH ROW
BEGIN
    DELETE FROM roombooking WHERE bookedforpersonID = OLD.idPerson;
    DELETE FROM hotelbooking WHERE bookedbyclientID = OLD.idPerson;
END$$

CREATE TRIGGER client_delete_bookings BEFORE DELETE ON client FOR EACH ROW
BEGIN
    DELETE FROM hotelbooking WHERE bookedbyclientID = OLD.idClient;
END$$

CREATE TRIGGER room_delete_bookings BEFORE DELETE ON room FOR EACH ROW
BEGIN
    DELETE FROM roombooking WHERE roomID = OLD.idRoom;
END$$

CREATE TRIGGER roomtype_delete_rooms BEFORE DELETE ON roomtype FOR EACH ROW
BEGIN
    DELETE FROM room WHERE roomtype = OLD.typename;
END$$

CREATE TRIGGER hotel_delete_rooms BEFORE DELETE ON hotel FOR EACH ROW
BEGIN
    DELETE FROM room WHERE idHotel = OLD.idHotel;
END$$

-- ---------------------------------------------------------------------------------------------
-- 2.1: εισαγωγή / ενημέρωση / διαγραφή πελάτη και κάρτας
--   SELECT `2_1_update_clients_and_cards`('insert', 'DOC-1', 'Ada', 'Lovelace', 'F', '1990-12-10',
--          'Street 1', 'Chania', 'Greece', 'VISA', '4111-0000', '2031-01-01', 'ADA LOVELACE');
-- ---------------------------------------------------------------------------------------------

CREATE FUNCTION `2_1_update_clients_and_cards`(
    p_action VARCHAR(10), p_documentclient VARCHAR(45), p_fname VARCHAR(45), p_lname VARCHAR(45),
    p_sex CHAR(1), p_date_of_birth DATE, p_address VARCHAR(75), p_city VARCHAR(45), p_country VARCHAR(45),
    p_cardtype VARCHAR(30), p_number_card VARCHAR(45), p_expiration_card DATE, p_holder VARCHAR(45))
RETURNS TINYINT(1)
MODIFIES SQL DATA
BEGIN
    DECLARE v_id_client INT;

    IF p_action = 'insert' THEN
        IF EXISTS (SELECT 1 FROM client cl WHERE cl.documentclient = p_documentclient) THEN
            CALL hotel_raise('The document client must be unique and there is other client with this document client.');
        END IF;
        IF p_cardtype IS NULL OR p_number_card IS NULL THEN
            CALL hotel_raise('Card type or card number cannot be null.');
        END IF;
        IF p_expiration_card IS NULL OR p_expiration_card < CURRENT_DATE THEN
            CALL hotel_raise('Card has expired. Need to insert new card.');
        END IF;

        INSERT INTO person (fname, lname, sex, dateofbirth, address, city, country)
        VALUES (p_fname, p_lname, p_sex, p_date_of_birth, p_address, p_city, p_country);
        SET v_id_client = LAST_INSERT_ID();
        INSERT INTO client (idClient, documentclient) VALUES (v_id_client, p_documentclient);
        INSERT INTO creditcard (cardtype, number, expiration, holder, clientID)
        VALUES (p_cardtype, p_number_card, p_expiration_card, p_holder, v_id_client);
        RETURN TRUE;
    END IF;

    IF p_action NOT IN ('update', 'delete') OR p_action IS NULL THEN
        CALL hotel_raise(CONCAT('Unknown action "', COALESCE(p_action, 'NULL'), '". Use insert, update or delete.'));
    END IF;

    SET v_id_client = (SELECT cl.idClient FROM client cl WHERE cl.documentclient = p_documentclient);
    IF v_id_client IS NULL THEN
        CALL hotel_raise(CONCAT('There is no client with document client ', COALESCE(p_documentclient, 'NULL'), '.'));
    END IF;

    IF p_action = 'delete' THEN
        -- Το trigger person_delete_bookings σβήνει πρώτα τις κρατήσεις του (με τους κανόνες τους)·
        -- client και creditcard φεύγουν με cascade.
        DELETE FROM person WHERE idPerson = v_id_client;
        RETURN TRUE;
    END IF;

    -- update
    UPDATE person
    SET fname = p_fname, lname = p_lname, sex = p_sex, dateofbirth = p_date_of_birth,
        address = p_address, city = p_city, country = p_country
    WHERE idPerson = v_id_client;

    IF p_cardtype IS NOT NULL AND p_number_card IS NOT NULL THEN
        IF p_expiration_card IS NULL OR p_expiration_card < CURRENT_DATE THEN
            CALL hotel_raise(CONCAT('Card has expired. Need to insert new card. Person Id=', v_id_client));
        END IF;
        IF EXISTS (SELECT 1 FROM creditcard cc WHERE cc.clientID = v_id_client) THEN
            UPDATE creditcard
            SET cardtype = p_cardtype, number = p_number_card, expiration = p_expiration_card, holder = p_holder
            WHERE clientID = v_id_client;
        ELSE                                                  -- ο πελάτης δεν είχε κάρτα: προστίθεται
            INSERT INTO creditcard (cardtype, number, expiration, holder, clientID)
            VALUES (p_cardtype, p_number_card, p_expiration_card, p_holder, v_id_client);
        END IF;
    END IF;
    RETURN TRUE;
END$$

-- ---------------------------------------------------------------------------------------------
-- 2.2: n τυχαίες κρατήσεις σε ένα ξενοδοχείο, μέσα σε ένα διάστημα. Επιστρέφει το n.
--   SELECT `2_2_insertRandomBookings`(11, '2031-01-01', '2031-03-01', 5);
-- ---------------------------------------------------------------------------------------------

CREATE FUNCTION `2_2_insertRandomBookings`(p_hotelid INT, p_start_date DATE, p_finish_date DATE, p_n INT)
RETURNS INT
MODIFIES SQL DATA
BEGIN
    DECLARE v_i INT DEFAULT 0;
    DECLARE v_j INT;
    DECLARE v_rooms INT;
    DECLARE v_checkin DATE;
    DECLARE v_checkout DATE;
    DECLARE v_booked_by INT;
    DECLARE v_booked_for INT;
    DECLARE v_country VARCHAR(45);
    DECLARE v_booking_id INT;
    DECLARE v_room_id INT;

    IF p_finish_date <= p_start_date THEN
        CALL hotel_raise('finish_date must be after start_date.');
    END IF;

    WHILE v_i < p_n DO
        -- Κάθε κράτηση έχει δικό της τυχαίο πλήθος δωματίων (1-5) και δικές της ημερομηνίες:
        -- checkin στο [start, finish) και checkout στο (checkin, finish].
        SET v_rooms    = FLOOR(RAND() * 5 + 1);
        SET v_checkin  = DATE_ADD(p_start_date, INTERVAL FLOOR(RAND() * DATEDIFF(p_finish_date, p_start_date)) DAY);
        SET v_checkout = DATE_ADD(v_checkin, INTERVAL 1 + FLOOR(RAND() * DATEDIFF(p_finish_date, v_checkin)) DAY);

        -- Ο πελάτης που κάνει την κράτηση δεν είναι υπάλληλος του ξενοδοχείου.
        SET v_booked_by = (SELECT cl.idClient
                           FROM client cl
                           WHERE NOT EXISTS (SELECT 1 FROM employee e
                                             WHERE e.idEmployee = cl.idClient AND e.hotelID = p_hotelid)
                           ORDER BY RAND() LIMIT 1);
        INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
        VALUES (DATE_SUB(v_checkin, INTERVAL 20 DAY), DATE_SUB(v_checkin, INTERVAL 10 DAY), NULL,
                v_booked_by, FALSE, NULL, 'confirmed');
        SET v_booking_id = LAST_INSERT_ID();

        SET v_country = (SELECT pe.country FROM person pe WHERE pe.idPerson = v_booked_by);

        SET v_j = 0;
        WHILE v_j < v_rooms DO
            -- Υπεύθυνος δωματίου: πελάτης από την ίδια χώρα, όχι υπάλληλος του ξενοδοχείου.
            SET v_booked_for = (SELECT cl.idClient
                                FROM client cl
                                JOIN person pe ON pe.idPerson = cl.idClient
                                WHERE pe.country = v_country
                                  AND NOT EXISTS (SELECT 1 FROM employee e
                                                  WHERE e.idEmployee = cl.idClient AND e.hotelID = p_hotelid)
                                ORDER BY RAND() LIMIT 1);

            SET v_room_id = (SELECT r.idRoom
                             FROM room r
                             WHERE r.idHotel = p_hotelid
                               AND NOT EXISTS (SELECT 1 FROM roombooking rb
                                               WHERE rb.roomID = r.idRoom
                                                 AND rb.checkin < v_checkout AND rb.checkout > v_checkin)
                             ORDER BY RAND() LIMIT 1);
            IF v_room_id IS NULL THEN
                CALL hotel_raise('No available room. Cannot add other room.');
            END IF;

            INSERT INTO roombooking (hotelbookingID, roomID, bookedforpersonID, checkin, checkout, rate)
            VALUES (v_booking_id, v_room_id, v_booked_for, v_checkin, v_checkout, NULL);
            SET v_j = v_j + 1;
        END WHILE;
        SET v_i = v_i + 1;
    END WHILE;
    RETURN v_i;
END$$

DELIMITER ;
