-- Δοκιμές των triggers και των συναρτήσεων της MySQL: 1.1 (έλεγχοι Manages / Participates), 2.1, 2.2,
-- 5.1, 5.2, 5.3 και 6.2 (db/mysql/init/04_triggers.sql και 05_weekly_plan.sql).
-- Είναι τα σενάρια των db/checks/03, 04 και 05 της PostgreSQL, μαζί με ελέγχους ειδικούς για τη MySQL.
--
-- Εκτέλεση (χωρίς --force, ώστε ο client να σταματά στο πρώτο σφάλμα):
--   docker compose exec -T mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" hotel -N < /sql/checks/03_trigger_tests.sql'
--
-- Κάθε έλεγχος τυπώνει μία γραμμή "OK ..." και στο τέλος "ALL TESTS PASSED". Αν ένας έλεγχος αποτύχει
-- τυπώνεται "FAILED ..." με την αιτία, οι υπόλοιποι συνεχίζουν, και το αρχείο τελειώνει με σφάλμα
-- "... CHECK(S) FAILED ..." αντί για "ALL TESTS PASSED".
--
-- Όλες οι αλλαγές γίνονται μέσα σε transaction που κάνει ROLLBACK, άρα δεν μένει τίποτα στη βάση (μόνο
-- οι μετρητές AUTO_INCREMENT προχωρούν). Οι βοηθητικές procedures zz_t_* δημιουργούνται πριν από το
-- transaction και σβήνονται μετά (το DDL της MySQL κάνει commit).
-- Οι ημερομηνίες είναι σχετικές με το CURRENT_DATE ή πολύ μελλοντικές, άρα οι δοκιμές τρέχουν όποια μέρα.
--
-- Η τελευταία ενότητα ελέγχει τρία σημεία ειδικά για τη MySQL, που βρέθηκαν και διορθώθηκαν στον έλεγχο
-- της μεταφοράς: σφάλμα 1442, σύγκριση κειμένου στο πλάνο και διαγραφές μέσω cascade.

SET NAMES utf8mb4;
SET SESSION sql_mode = REPLACE(@@sql_mode, 'ANSI_QUOTES', '');     -- τα "..." παρακάτω είναι κείμενο

DROP PROCEDURE IF EXISTS zz_t_exec;
DROP PROCEDURE IF EXISTS zz_t_true;
DROP PROCEDURE IF EXISTS zz_t_rejected;
DROP PROCEDURE IF EXISTS zz_t_accepted;
DROP PROCEDURE IF EXISTS zz_t_done;
DROP PROCEDURE IF EXISTS zz_t_plan;

DELIMITER $$

-- Εκτελεί μια εντολή και επιστρέφει τον κωδικό και το μήνυμα του σφάλματος (0 / NULL αν πέτυχε).
CREATE PROCEDURE zz_t_exec(p_sql TEXT, OUT p_errno INT, OUT p_error VARCHAR(600))
BEGIN
    DECLARE v_errno INT DEFAULT 0;
    DECLARE v_error VARCHAR(600) DEFAULT NULL;
    BEGIN
        DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_error = MESSAGE_TEXT;
        END;
        SET @zz_sql = p_sql;
        PREPARE zz_stmt FROM @zz_sql;
        IF v_errno = 0 THEN
            EXECUTE zz_stmt;
            DEALLOCATE PREPARE zz_stmt;
        END IF;
    END;
    SET p_errno = v_errno, p_error = v_error;
END$$

-- Σημειώνει αποτυχία του τρέχοντος ελέγχου όταν η συνθήκη δεν είναι αληθής (ή είναι NULL).
CREATE PROCEDURE zz_t_true(p_what VARCHAR(300), p_ok BOOLEAN)
BEGIN
    IF p_ok IS NULL OR NOT p_ok THEN
        SET @zz_detail = CONCAT_WS('; ', NULLIF(@zz_detail, ''), p_what);
    END IF;
END$$

-- Η εντολή πρέπει να απορριφθεί, με μήνυμα που ταιριάζει (LIKE) στο p_message_like.
CREATE PROCEDURE zz_t_rejected(p_sql TEXT, p_message_like VARCHAR(300))
BEGIN
    DECLARE v_errno INT;
    DECLARE v_error VARCHAR(600);
    CALL zz_t_exec(p_sql, v_errno, v_error);
    IF v_errno = 0 THEN
        CALL zz_t_true(CONCAT('was accepted: ', LEFT(p_sql, 90)), FALSE);
    ELSEIF v_error NOT LIKE p_message_like THEN
        CALL zz_t_true(CONCAT('wrong error [', v_errno, '] ', LEFT(v_error, 120), ' for: ', LEFT(p_sql, 60)), FALSE);
    END IF;
END$$

-- Η εντολή πρέπει να γίνει δεκτή (χρησιμοποιείται όπου ένα σφάλμα δεν πρέπει να σταματήσει το αρχείο).
CREATE PROCEDURE zz_t_accepted(p_sql TEXT)
BEGIN
    DECLARE v_errno INT;
    DECLARE v_error VARCHAR(600);
    CALL zz_t_exec(p_sql, v_errno, v_error);
    IF v_errno <> 0 THEN
        CALL zz_t_true(CONCAT('error [', v_errno, '] ', LEFT(v_error, 120), ' for: ', LEFT(p_sql, 60)), FALSE);
    END IF;
END$$

-- Κλείνει έναν έλεγχο: τυπώνει OK ή FAILED με όσα σημειώθηκαν.
CREATE PROCEDURE zz_t_done(p_name VARCHAR(200))
BEGIN
    IF COALESCE(@zz_detail, '') = '' THEN
        SELECT CONCAT('OK      ', p_name) AS '';
    ELSE
        SET @zz_failed = @zz_failed + 1;
        SELECT CONCAT('FAILED  ', p_name, '  -->  ', @zz_detail) AS '';
    END IF;
    SET @zz_detail = '';
END$$

-- Οι επτά ημέρες του πλάνου ενός δωματίου στο @plan, π.χ. '0,AB123,AB123,0,0,0,0'.
CREATE PROCEDURE zz_t_plan(p_room INT)
BEGIN
    SET @plan = NULL;
    SELECT CONCAT_WS(',', sunday, monday, tuesday, wednesday, thursday, friday, saturday) INTO @plan
    FROM `6_2_weeklyPlan` WHERE idRoom = p_room;
END$$

DELIMITER ;

SET @zz_failed = 0, @zz_detail = '';

START TRANSACTION;

-- ---------------------------------------------------------------------------------------------
-- Κοινά δεδομένα: δύο πελάτες, τρία δωμάτια του ξενοδοχείου 11 με διαφορετικό τύπο και τιμή,
-- υπάλληλοι του ξενοδοχείου 11 (manager, reception, staff) και ένας manager άλλου ξενοδοχείου.
-- Οι αναγνώσεις γίνονται με SELECT ... INTO (απλή ανάγνωση, χωρίς κλειδώματα).
-- ---------------------------------------------------------------------------------------------
SELECT MIN(idClient) INTO @c1 FROM client;
SELECT documentclient INTO @doc1 FROM client WHERE idClient = @c1;
SELECT MIN(idClient) INTO @c2 FROM client WHERE idClient > @c1;
SELECT documentclient INTO @doc2 FROM client WHERE idClient = @c2;

SELECT MAX(idRoom) INTO @r1 FROM room WHERE idHotel = 11 AND `5_3_current_room_rate`(idRoom) IS NOT NULL;
SELECT roomtype, `5_3_current_room_rate`(idRoom) INTO @type1, @rate1 FROM room WHERE idRoom = @r1;
SELECT MAX(idRoom) INTO @r2 FROM room
WHERE idHotel = 11 AND roomtype <> @type1 AND `5_3_current_room_rate`(idRoom) <> @rate1;
SELECT roomtype, `5_3_current_room_rate`(idRoom) INTO @type2, @rate2 FROM room WHERE idRoom = @r2;
SELECT MAX(idRoom) INTO @r3 FROM room
WHERE idHotel = 11 AND roomtype NOT IN (@type1, @type2) AND `5_3_current_room_rate`(idRoom) IS NOT NULL;
SELECT `5_3_current_room_rate`(@r3) INTO @rate3;
SELECT MIN(ro.idRoom) INTO @r_norate FROM room ro
WHERE NOT EXISTS (SELECT 1 FROM roomrate rr WHERE rr.idHotel = ro.idHotel AND rr.roomtype = ro.roomtype);

SELECT MIN(idEmployee) INTO @mgr FROM employee WHERE hotelID = 11 AND role = 'manager';
SELECT MIN(idEmployee) INTO @rec FROM employee WHERE hotelID = 11 AND role = 'reception';
SELECT MIN(idEmployee) INTO @staff FROM employee WHERE hotelID = 11 AND role = 'staff';
SELECT MIN(idEmployee) INTO @othermgr FROM employee WHERE hotelID <> 11 AND role = 'manager';

CALL zz_t_true('two clients', @c1 IS NOT NULL AND @c2 IS NOT NULL AND @doc1 IS NOT NULL AND @doc2 IS NOT NULL);
CALL zz_t_true('three rooms with a rate in hotel 11', @r1 IS NOT NULL AND @r2 IS NOT NULL AND @r3 IS NOT NULL);
CALL zz_t_true('employees', @mgr IS NOT NULL AND @rec IS NOT NULL AND @staff IS NOT NULL AND @othermgr IS NOT NULL);
CALL zz_t_done('test data: clients, rooms and employees found');

-- Τρεις άδειες κρατήσεις: hb1 / hb2 με προθεσμία ακύρωσης σε 5 ημέρες, hb_late με προθεσμία που έληξε χθες.
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE - INTERVAL 9 DAY, CURRENT_DATE + INTERVAL 5 DAY, NULL, @c1, FALSE, NULL, 'confirmed');
SET @hb1 = LAST_INSERT_ID();
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE - INTERVAL 9 DAY, CURRENT_DATE + INTERVAL 5 DAY, NULL, @c1, FALSE, NULL, 'confirmed');
SET @hb2 = LAST_INSERT_ID();
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE - INTERVAL 9 DAY, CURRENT_DATE - INTERVAL 1 DAY, NULL, @c1, FALSE, NULL, 'confirmed');
SET @hb_late = LAST_INSERT_ID();

-- =============================================================================================
-- 2.1  Πελάτες και κάρτες
-- =============================================================================================
SELECT COUNT(*) INTO @n_person FROM person;
SELECT COUNT(*) INTO @n_client FROM client;
SELECT COUNT(*) INTO @n_card FROM creditcard;

SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-1', 'Anna', 'Old', 'F', '1990-01-01', 'Street 1', 'Chania',
       'Greece', 'visa', 'ZZ-CARD-1', CURRENT_DATE + INTERVAL 365 DAY, 'Anna Old') INTO @ret;
SET @p1 = NULL;
SELECT idClient INTO @p1 FROM client WHERE documentclient = 'ZZ-TEST-1';
SELECT COUNT(*) INTO @k FROM person
WHERE idPerson = @p1 AND fname = 'Anna' AND lname = 'Old' AND sex = 'F' AND dateofbirth = '1990-01-01'
  AND address = 'Street 1' AND city = 'Chania' AND country = 'Greece';
SELECT COUNT(*) INTO @k2 FROM creditcard
WHERE clientID = @p1 AND cardtype = 'visa' AND number = 'ZZ-CARD-1' AND holder = 'Anna Old'
  AND expiration = CURRENT_DATE + INTERVAL 365 DAY;
CALL zz_t_true('insert returns 1', @ret = 1);
CALL zz_t_true('person row', @k = 1);
CALL zz_t_true('card row', @k2 = 1);

SELECT `2_1_update_clients_and_cards`('update', 'ZZ-TEST-1', 'Anna', 'New', 'F', '1990-01-01', 'Street 2', 'Chania',
       'Greece', 'visa', 'ZZ-CARD-2', CURRENT_DATE + INTERVAL 365 DAY, 'Anna New') INTO @ret;
SELECT COUNT(*) INTO @k FROM person WHERE idPerson = @p1 AND lname = 'New' AND address = 'Street 2';
SELECT COUNT(*) INTO @k2 FROM creditcard WHERE clientID = @p1 AND number = 'ZZ-CARD-2' AND holder = 'Anna New';
SELECT COUNT(*) INTO @k3 FROM creditcard WHERE clientID = @p1;
CALL zz_t_true('update returns 1', @ret = 1);
CALL zz_t_true('person updated', @k = 1);
CALL zz_t_true('card updated, still one card', @k2 = 1 AND @k3 = 1);

SELECT `2_1_update_clients_and_cards`('delete', 'ZZ-TEST-1', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
SELECT COUNT(*) INTO @k FROM person WHERE idPerson = @p1;
SELECT COUNT(*) INTO @k2 FROM client WHERE documentclient = 'ZZ-TEST-1';
SELECT COUNT(*) INTO @k3 FROM creditcard WHERE number IN ('ZZ-CARD-1', 'ZZ-CARD-2');
CALL zz_t_true('delete returns 1', @ret = 1);
CALL zz_t_true('person, client and card are gone', @k = 0 AND @k2 = 0 AND @k3 = 0);
CALL zz_t_done('2.1  insert, update and delete of a client with a card');

-- Ενημέρωση χωρίς στοιχεία κάρτας: αλλάζει μόνο το πρόσωπο. Πελάτης χωρίς κάρτα: η κάρτα προστίθεται.
SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece',
       'visa', 'ZZ-CARD-3', CURRENT_DATE, 'A B') INTO @ret;                   -- κάρτα που λήγει σήμερα: δεκτή
SET @p2 = NULL;
SELECT idClient INTO @p2 FROM client WHERE documentclient = 'ZZ-TEST-2';
SELECT `2_1_update_clients_and_cards`('update', 'ZZ-TEST-2', 'A2', 'B2', 'M', '1991-02-03', 'x2', 'y2', 'Italy',
       NULL, NULL, NULL, NULL) INTO @ret;
SELECT COUNT(*) INTO @k FROM person
WHERE idPerson = @p2 AND fname = 'A2' AND lname = 'B2' AND sex = 'M' AND dateofbirth = '1991-02-03'
  AND address = 'x2' AND city = 'y2' AND country = 'Italy';
SELECT COUNT(*) INTO @k2 FROM creditcard WHERE clientID = @p2 AND number = 'ZZ-CARD-3' AND holder = 'A B';
CALL zz_t_true('a card expiring today is accepted', @p2 IS NOT NULL);
CALL zz_t_true('person changed', @k = 1);
CALL zz_t_true('card untouched', @k2 = 1);
DELETE FROM creditcard WHERE clientID = @p2;
SELECT `2_1_update_clients_and_cards`('update', 'ZZ-TEST-2', 'A2', 'B2', 'M', '1991-02-03', 'x2', 'y2', 'Italy',
       'visa', 'ZZ-CARD-4', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret;
SELECT COUNT(*) INTO @k FROM creditcard WHERE clientID = @p2 AND number = 'ZZ-CARD-4';
CALL zz_t_true('missing card added by update', @ret = 1 AND @k = 1);
CALL zz_t_done('2.1  update without card data changes only the person; update adds a missing card');

-- Αρνήσεις. Κάθε μία πρέπει να μην αφήνει τίποτα πίσω.
SELECT COUNT(*) INTO @n_person2 FROM person;
SELECT COUNT(*) INTO @n_card2 FROM creditcard;
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', @doc1, 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-9', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'The document client must be unique%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-3', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-9', CURRENT_DATE - INTERVAL 1 DAY, 'A B') INTO @ret",
                   'Card has expired%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-3', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-9', NULL, 'A B') INTO @ret",
                   'Card has expired%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-3', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', NULL, 'ZZ-CARD-9', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'Card type or card number cannot be null%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-3', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', NULL, CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'Card type or card number cannot be null%');
-- Αριθμός κάρτας που έχει ήδη άλλος πελάτης: αποτυγχάνει στο τρίτο INSERT, μετά το person και το client.
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-3', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-4', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'Duplicate entry%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('upsert', 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-9', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'Unknown action "upsert"%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`(NULL, 'ZZ-TEST-2', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', 'visa', 'ZZ-CARD-9', CURRENT_DATE + INTERVAL 30 DAY, 'A B') INTO @ret",
                   'Unknown action%');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('update', 'ZZ-NO-SUCH', 'A', 'B', 'F', '1990-01-01', 'x', 'y', 'Greece', NULL, NULL, NULL, NULL) INTO @ret",
                   'There is no client with document client ZZ-NO-SUCH.');
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('delete', 'ZZ-NO-SUCH', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret",
                   'There is no client with document client ZZ-NO-SUCH.');
-- Ληγμένη κάρτα στο update: και η αλλαγή του προσώπου αναιρείται.
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('update', 'ZZ-TEST-2', 'CHANGED', 'CHANGED', 'M', '1991-02-03', 'x2', 'y2', 'Italy', 'visa', 'ZZ-CARD-9', CURRENT_DATE - INTERVAL 1 DAY, 'A B') INTO @ret",
                   'Card has expired%');
SELECT COUNT(*) INTO @k FROM person;
SELECT COUNT(*) INTO @k2 FROM creditcard;
SELECT COUNT(*) INTO @k3 FROM client WHERE documentclient = 'ZZ-TEST-3';
SELECT COUNT(*) INTO @k4 FROM person WHERE idPerson = @p2 AND fname = 'A2';
CALL zz_t_true('no person or card left behind', @k = @n_person2 AND @k2 = @n_card2 AND @k3 = 0);
CALL zz_t_true('person not changed by the refused update', @k4 = 1);
CALL zz_t_done('2.1  refusals: duplicate document, bad card, unknown action or client; nothing is left behind');

-- Διαγραφή πελάτη με κρατήσεις: περνά από τα triggers (totalamount, συνδιαλλαγές).
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, NULL, @p2, TRUE, 'cash', 'confirmed');
SET @hb_p2 = LAST_INSERT_ID();
INSERT INTO roombooking VALUES (@hb_p2, @r1, @p2, '2032-01-01', '2032-01-03', NULL);
INSERT INTO roombooking VALUES (@hb_p2, @r2, @c2, '2032-01-01', '2032-01-03', NULL);
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, NULL, @c1, TRUE, 'cash', 'confirmed');
SET @hb_other = LAST_INSERT_ID();
INSERT INTO roombooking VALUES (@hb_other, @r3, @p2, '2032-01-01', '2032-01-04', NULL);    -- δωμάτιο του p2 σε ξένη κράτηση
INSERT INTO roombooking VALUES (@hb_other, @r1, @c1, '2032-02-01', '2032-02-02', NULL);
SELECT `2_1_update_clients_and_cards`('delete', 'ZZ-TEST-2', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
SELECT COUNT(*) INTO @k FROM person WHERE idPerson = @p2;
SELECT COUNT(*) INTO @k2 FROM hotelbooking WHERE idhotelbooking = @hb_p2;
SELECT COUNT(*) INTO @k3 FROM roombooking WHERE hotelbookingID = @hb_p2 OR bookedforpersonID = @p2;
SELECT SUM(amount), SUM(action_tr = 'delete') INTO @sum_tx, @n_del FROM `Transaction` WHERE idhotelbooking = @hb_p2;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb_other;
SELECT SUM(amount) INTO @sum_other FROM `Transaction` WHERE idhotelbooking = @hb_other;
CALL zz_t_true('person and own booking deleted', @k = 0 AND @k2 = 0 AND @k3 = 0);
CALL zz_t_true('ledger of the deleted paid booking sums to 0, with a delete row', @sum_tx = 0 AND @n_del = 1);
CALL zz_t_true('other booking lost only the room of the deleted person', ABS(@tot - @rate1) < 0.005);
CALL zz_t_true('ledger of the other booking follows its total', ABS(@sum_other - @rate1) < 0.005);
DELETE FROM hotelbooking WHERE idhotelbooking = @hb_other;
CALL zz_t_done('2.1  delete removes the bookings of the client through the triggers (totals, ledger)');

-- Διαγραφή πελάτη με κράτηση που έχει περάσει την προθεσμία ακύρωσης: απορρίπτεται, δεν σβήνεται τίποτα.
SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-4', 'L', 'L', 'F', '1990-01-01', 'x', 'y', 'Greece',
       'visa', 'ZZ-CARD-5', CURRENT_DATE + INTERVAL 30 DAY, 'L') INTO @ret;
SET @p4 = NULL;
SELECT idClient INTO @p4 FROM client WHERE documentclient = 'ZZ-TEST-4';
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, NULL, @p4, FALSE, NULL, 'confirmed');
SET @hb_p4a = LAST_INSERT_ID();
INSERT INTO roombooking VALUES (@hb_p4a, @r2, @p4, '2032-03-01', '2032-03-03', NULL);
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE - INTERVAL 20 DAY, CURRENT_DATE - INTERVAL 1 DAY, NULL, @p4, FALSE, NULL, 'confirmed');
SET @hb_p4b = LAST_INSERT_ID();
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('delete', 'ZZ-TEST-4', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret",
                   'Cannot delete the reservation.');
INSERT INTO roombooking VALUES (@hb_p4b, @r3, @p4, '2032-03-01', '2032-03-03', NULL);
CALL zz_t_rejected("SELECT `2_1_update_clients_and_cards`('delete', 'ZZ-TEST-4', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret",
                   'Unable to execute operation! Cancelation date has expired.');
SELECT COUNT(*) INTO @k FROM person WHERE idPerson = @p4;
SELECT COUNT(*) INTO @k2 FROM roombooking WHERE hotelbookingID IN (@hb_p4a, @hb_p4b);
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb_p4a;
CALL zz_t_true('client, bookings and rooms still there', @k = 1 AND @k2 = 2 AND ABS(@tot - 2 * @rate2) < 0.005);
CALL zz_t_done('2.1  delete is refused when a booking is past its cancellation date; nothing is deleted');

-- =============================================================================================
-- 2.2  Τυχαίες κρατήσεις
-- =============================================================================================
SELECT MAX(idhotelbooking) INTO @before_max FROM hotelbooking;
SELECT `2_2_insertRandomBookings`(11, '2040-01-01', '2040-01-31', 3) INTO @ret;
SELECT COUNT(*), SUM(COALESCE(totalamount, 0) <= 0),
       SUM(status = 'confirmed' AND NOT payed AND paymethod IS NULL)
INTO @k, @unpriced, @k_state FROM hotelbooking WHERE idhotelbooking > @before_max;
SELECT COUNT(*) INTO @overlaps
FROM roombooking a JOIN roombooking b
  ON a.roomID = b.roomID AND a.hotelbookingID <> b.hotelbookingID AND a.checkin < b.checkout AND b.checkin < a.checkout
WHERE a.hotelbookingID > @before_max;
SELECT COUNT(*) INTO @bad_rows FROM roombooking rb JOIN room r ON r.idRoom = rb.roomID
WHERE rb.hotelbookingID > @before_max
  AND (r.idHotel <> 11 OR rb.checkin < '2040-01-01' OR rb.checkout > '2040-01-31' OR rb.checkout <= rb.checkin OR rb.rate IS NULL);
SELECT COUNT(*) INTO @bad_shape FROM (
    SELECT hb.idhotelbooking
    FROM hotelbooking hb LEFT JOIN roombooking rb ON rb.hotelbookingID = hb.idhotelbooking
    WHERE hb.idhotelbooking > @before_max
    GROUP BY hb.idhotelbooking, hb.totalamount, hb.cancellationdate, hb.reservationdate
    HAVING COUNT(rb.roomID) NOT BETWEEN 1 AND 5
        OR COUNT(DISTINCT rb.checkin, rb.checkout) <> 1
        OR ABS(hb.totalamount - SUM(rb.rate * DATEDIFF(rb.checkout, rb.checkin))) > 0.01
        OR hb.cancellationdate <> MIN(rb.checkin) - INTERVAL 10 DAY
        OR hb.reservationdate <> MIN(rb.checkin) - INTERVAL 20 DAY) x;
CALL zz_t_true('returns n and creates n bookings', @ret = 3 AND @k = 3);
CALL zz_t_true('every booking is priced', @unpriced = 0);
CALL zz_t_true('confirmed and unpaid', @k_state = 3);
CALL zz_t_true('no overlapping room bookings', @overlaps = 0);
CALL zz_t_true('rooms of hotel 11 inside the period', @bad_rows = 0);
CALL zz_t_true('1-5 rooms, same dates, total = sum, dates of the booking', @bad_shape = 0);
CALL zz_t_done('2.2  random bookings are created, priced and do not overlap');

SELECT MAX(idhotelbooking) INTO @before_max FROM hotelbooking;
SELECT `2_2_insertRandomBookings`(11, '2041-01-01', '2041-12-31', 6) INTO @ret;
SELECT COUNT(DISTINCT rb.checkin, rb.checkout) INTO @k FROM roombooking rb WHERE rb.hotelbookingID > @before_max;
SELECT COUNT(*) INTO @k2 FROM hotelbooking hb JOIN employee e ON e.idEmployee = hb.bookedbyclientID
WHERE hb.idhotelbooking > @before_max AND e.hotelID = 11;
SELECT COUNT(*) INTO @k3 FROM roombooking rb JOIN employee e ON e.idEmployee = rb.bookedforpersonID
WHERE rb.hotelbookingID > @before_max AND e.hotelID = 11;
SELECT COUNT(*) INTO @k4 FROM roombooking rb
JOIN hotelbooking hb ON hb.idhotelbooking = rb.hotelbookingID
JOIN person pb ON pb.idPerson = hb.bookedbyclientID
JOIN person pf ON pf.idPerson = rb.bookedforpersonID
WHERE rb.hotelbookingID > @before_max AND NOT (pb.country <=> pf.country);
CALL zz_t_true('6 bookings', @ret = 6);
CALL zz_t_true('bookings have their own dates', @k > 1);
CALL zz_t_true('not booked by / for an employee of the hotel', @k2 = 0 AND @k3 = 0);
CALL zz_t_true('room guests come from the country of the client', @k4 = 0);
CALL zz_t_done('2.2  each booking has its own dates; hotel employees are excluded');

SELECT COUNT(*) INTO @n_hb FROM hotelbooking;
SELECT COUNT(*) INTO @n_rb FROM roombooking;
CALL zz_t_rejected("SELECT `2_2_insertRandomBookings`(11, '2042-01-05', '2042-01-05', 2) INTO @ret", 'finish_date must be after start_date.');
CALL zz_t_rejected("SELECT `2_2_insertRandomBookings`(11, '2042-01-05', '2042-01-01', 2) INTO @ret", 'finish_date must be after start_date.');
-- 60 κρατήσεις για μία μόνο νύχτα: τα δωμάτια τελειώνουν στη μέση και δεν πρέπει να μείνει καμία.
CALL zz_t_rejected("SELECT `2_2_insertRandomBookings`(11, '2042-01-01', '2042-01-02', 60) INTO @ret", 'No available room. Cannot add other room.');
SELECT `2_2_insertRandomBookings`(11, '2042-01-01', '2042-01-05', 0) INTO @ret;
SELECT COUNT(*) INTO @k FROM hotelbooking;
SELECT COUNT(*) INTO @k2 FROM roombooking;
CALL zz_t_true('n = 0 returns 0', @ret = 0);
CALL zz_t_true('nothing left behind by the refused calls', @k = @n_hb AND @k2 = @n_rb);
CALL zz_t_done('2.2  bad period is refused; a call that runs out of rooms leaves nothing behind');

-- =============================================================================================
-- 5.3  Εισαγωγή κράτησης δωματίου
-- =============================================================================================
INSERT INTO roombooking VALUES (@hb1, @r1, @c1, '2033-03-01', '2033-03-05', 1);     -- το rate 1 αγνοείται
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1 AND roomID = @r1;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb1;
CALL zz_t_true('rate taken from roomrate', ABS(@rate - @rate1) < 0.005);
CALL zz_t_true('totalamount = rate x nights', ABS(@tot - 4 * @rate1) < 0.005);
CALL zz_t_done('5.3  insert sets the rate and the total amount');

CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-03-02', '2033-03-04', NULL)", 'The room is not available.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-02-20', '2033-03-02', NULL)", 'The room is not available.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-03-04', '2033-03-10', NULL)", 'The room is not available.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-02-01', '2033-04-01', NULL)", 'The room is not available.');
CALL zz_t_rejected("INSERT IGNORE INTO roombooking VALUES (@hb2, @r1, @c1, '2033-03-02', '2033-03-04', NULL)", 'The room is not available.');
SELECT COUNT(*) INTO @k FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_true('no row inserted', @k = 0);
CALL zz_t_done('5.3  double booking of a room is rejected');

INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-03-05', '2033-03-07', NULL);
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('total of the second booking', ABS(@tot - 2 * @rate1) < 0.005);
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('total reset to 0 after delete', @tot = 0);
CALL zz_t_done('5.3  a booking may start on the day another one checks out; delete resets the total');

CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r2, @c1, '2033-03-02', NULL, NULL)", 'The checkin and the checkout cannot be null.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r2, @c1, NULL, '2033-03-02', NULL)", 'The checkin and the checkout cannot be null.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r2, @c1, '2033-03-02', '2033-03-02', NULL)", 'The checkout must be after the checkin.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r2, @c1, '2033-03-02', '2033-03-01', NULL)", 'The checkout must be after the checkin.');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb1 + 1000000, @r2, @c1, '2033-03-02', '2033-03-04', NULL)", 'Hotel booking does not exist!');
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb1, @r1, @c1, '2033-06-01', '2033-06-04', NULL)", 'This room booking already exists.');
CALL zz_t_rejected("REPLACE INTO roombooking VALUES (@hb1, @r1, @c1, '2033-06-01', '2033-06-04', NULL)", 'This room booking already exists.');
CALL zz_t_rejected("UPDATE roombooking SET checkout = NULL WHERE hotelbookingID = @hb1", 'The checkin and the checkout cannot be null.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = NULL WHERE hotelbookingID = @hb1", 'The checkin and the checkout cannot be null.');
CALL zz_t_rejected("UPDATE roombooking SET checkout = '2033-03-01' WHERE hotelbookingID = @hb1", 'The checkout must be after the checkin.');
CALL zz_t_done('5.3  NULL or reversed dates, unknown booking and duplicate room are rejected on insert and update');

SET @sql = CONCAT("INSERT INTO roombooking VALUES (@hb2, ", COALESCE(@r_norate, -1), ", @c1, '2033-06-01', '2033-06-03', 50)");
CALL zz_t_rejected(@sql, 'There is no rate for this room type in this hotel.');
CALL zz_t_done('5.3  a room whose type has no rate cannot be booked');

-- Πολλές γραμμές σε μία εντολή: αν μία απορριφθεί, δεν μένει καμία.
CALL zz_t_rejected("INSERT INTO roombooking VALUES (@hb2, @r2, @c1, '2033-07-01', '2033-07-03', NULL), (@hb2, @r3, @c1, '2033-07-03', '2033-07-01', NULL)",
                   'The checkout must be after the checkin.');
SELECT COUNT(*) INTO @k FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_true('first row of the refused statement was undone', @k = 0);
INSERT INTO roombooking VALUES (@hb2, @r2, @c1, '2033-07-01', '2033-07-03', NULL), (@hb2, @r3, @c1, '2033-07-01', '2033-07-03', NULL);
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('total of a two-row insert', ABS(@tot - 2 * @rate2 - 2 * @rate3) < 0.005);
UPDATE roombooking SET checkout = checkout + INTERVAL 1 DAY WHERE hotelbookingID = @hb2;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('total after a two-row update', ABS(@tot - 3 * @rate2 - 3 * @rate3) < 0.005);
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('total after a two-row delete', @tot = 0);
CALL zz_t_done('5.3  multi-row statements: all rows or none, total follows');

-- =============================================================================================
-- 5.3  Ενημέρωση κράτησης δωματίου
-- =============================================================================================
UPDATE roombooking SET checkout = '2033-03-08' WHERE hotelbookingID = @hb1;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb1;
CALL zz_t_true('total recomputed after extension', ABS(@tot - 7 * @rate1) < 0.005);

UPDATE roomrate SET discount = IF(discount >= 50, discount - 10, discount + 10) WHERE idHotel = 11 AND roomtype = @type1;
SELECT `5_3_current_room_rate`(@r1) INTO @rate1b;
CALL zz_t_true('test setup: the current rate changed', ABS(@rate1b - @rate1) > 0.005);
UPDATE roombooking SET checkout = '2033-03-09' WHERE hotelbookingID = @hb1;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1;
CALL zz_t_true('rate refreshed with the current rate', ABS(@rate - @rate1b) < 0.005);

UPDATE roombooking SET rate = 77 WHERE hotelbookingID = @hb1;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb1;
CALL zz_t_true('explicit rate kept', @rate = 77);
CALL zz_t_true('total after explicit rate', @tot = 77 * 8);
UPDATE roombooking SET rate = 78.5, bookedforpersonID = @c2 WHERE hotelbookingID = @hb1;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1;
CALL zz_t_true('explicit rate kept when other columns change too', @rate = 78.5);
UPDATE roombooking SET rate = NULL WHERE hotelbookingID = @hb1;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1;
CALL zz_t_true('rate NULL means: take the current rate', ABS(@rate - @rate1b) < 0.005);
UPDATE roombooking SET rate = 77, bookedforpersonID = @c1 WHERE hotelbookingID = @hb1;
CALL zz_t_done('5.3  update refreshes the rate and the total, and keeps an explicit rate');

-- Γνωστή, τεκμηριωμένη διαφορά από την PostgreSQL: rate ίσο με το παλιό θεωρείται «δεν δόθηκε».
UPDATE roombooking SET checkout = '2033-03-10', rate = 77 WHERE hotelbookingID = @hb1;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb1;
CALL zz_t_true('rate equal to the old one is replaced by the current rate', ABS(@rate - @rate1b) < 0.005);
UPDATE roombooking SET checkout = '2033-03-09', rate = 77 WHERE hotelbookingID = @hb1;
CALL zz_t_done('5.3  (documented difference) a rate equal to the old one counts as not given');

-- Αλλαγή δωματίου: όχι πάνω σε πιασμένο δωμάτιο· σε ελεύθερο επιτρέπεται και παίρνει την τιμή του νέου.
INSERT INTO roombooking VALUES (@hb2, @r2, @c2, '2033-03-01', '2033-03-05', NULL);
CALL zz_t_rejected("UPDATE roombooking SET roomID = @r1 WHERE hotelbookingID = @hb2", 'The room is not available for these dates.');
CALL zz_t_rejected("UPDATE IGNORE roombooking SET roomID = @r1 WHERE hotelbookingID = @hb2", 'The room is not available for these dates.');
UPDATE roombooking SET checkin = '2033-04-01', checkout = '2033-04-03' WHERE hotelbookingID = @hb2;
UPDATE roombooking SET roomID = @r1 WHERE hotelbookingID = @hb2;
SELECT rate INTO @rate FROM roombooking WHERE hotelbookingID = @hb2 AND roomID = @r1;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('re-priced for the new room', ABS(@rate - @rate1b) < 0.005 AND ABS(@tot - 2 * @rate1b) < 0.005);
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_done('5.3  a booking cannot be moved onto an occupied room; a free move re-prices it');

-- Παράταση πάνω σε άλλη κράτηση: απορρίπτεται και το μήνυμα λέει ως πότε μπορεί να παραταθεί.
INSERT INTO roombooking VALUES (@hb2, @r1, @c2, '2033-03-12', '2033-03-14', NULL);
CALL zz_t_rejected("UPDATE roombooking SET checkout = '2033-03-13' WHERE hotelbookingID = @hb1",
                   'The room is not available for these dates. You can extend the checkout up to 2033-03-12.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = '2033-03-11', checkout = '2033-03-13' WHERE hotelbookingID = @hb1",
                   'The room is not available for these dates.');
UPDATE roombooking SET checkout = '2033-03-12' WHERE hotelbookingID = @hb1;         -- ως το checkin του επόμενου
UPDATE roombooking SET checkout = '2033-03-09', rate = 77 WHERE hotelbookingID = @hb1;   -- πίσω στο ρητό rate 77
-- Μεταφορά δωματίου σε άλλη κράτηση (πριν από την προθεσμία): ενημερώνονται και τα δύο σύνολα.
UPDATE roombooking SET rate = 50 WHERE hotelbookingID = @hb2;
UPDATE roombooking SET hotelbookingID = @hb1, roomID = @r2, rate = 50 + 1 WHERE hotelbookingID = @hb2;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb1;
SELECT totalamount INTO @tot2 FROM hotelbooking WHERE idhotelbooking = @hb2;
CALL zz_t_true('totals of both bookings after moving a room', @tot = 77 * 8 + 51 * 2 AND @tot2 = 0);
DELETE FROM roombooking WHERE hotelbookingID = @hb1 AND roomID = @r2;
CALL zz_t_done('5.3  an extension into another booking is refused with the date it can reach; moving a room updates both totals');

-- Διαμονή που άρχισε χθες: η παράταση επιτρέπεται, η μετακίνηση ημερομηνίας στο παρελθόν όχι.
INSERT INTO roombooking VALUES (@hb2, @r2, @c1, CURRENT_DATE - INTERVAL 1 DAY, CURRENT_DATE + INTERVAL 2 DAY, NULL);
UPDATE roombooking SET checkout = CURRENT_DATE + INTERVAL 4 DAY WHERE hotelbookingID = @hb2;
SELECT checkout INTO @d FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_true('stay extended', @d = CURRENT_DATE + INTERVAL 4 DAY);
CALL zz_t_rejected("UPDATE roombooking SET checkin = CURRENT_DATE - INTERVAL 3 DAY WHERE hotelbookingID = @hb2", '%The new checkin is in the past.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = CURRENT_DATE - INTERVAL 5 DAY, checkout = CURRENT_DATE - INTERVAL 2 DAY WHERE hotelbookingID = @hb2", '%in the past.');
UPDATE roombooking SET bookedforpersonID = @c2 WHERE hotelbookingID = @hb2;         -- άλλη στήλη: επιτρέπεται
UPDATE roombooking SET checkout = CURRENT_DATE WHERE hotelbookingID = @hb2;         -- αναχώρηση σήμερα
UPDATE roombooking SET checkin = CURRENT_DATE + INTERVAL 30 DAY, checkout = CURRENT_DATE + INTERVAL 32 DAY WHERE hotelbookingID = @hb2;
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_done('5.3  a stay that has started can be extended; dates cannot be moved into the past');

-- =============================================================================================
-- 5.2 / 5.3  Μετά την προθεσμία ακύρωσης
-- =============================================================================================
INSERT INTO roombooking VALUES (@hb_late, @r2, @c1, '2034-03-10', '2034-03-14', NULL);
CALL zz_t_rejected("UPDATE roombooking SET rate = 0 WHERE hotelbookingID = @hb_late", '%You cannot decrease the rate.');
CALL zz_t_rejected("UPDATE roombooking SET rate = rate - 1 WHERE hotelbookingID = @hb_late", '%You cannot decrease the rate.');
CALL zz_t_rejected("UPDATE roombooking SET hotelbookingID = @hb2 WHERE hotelbookingID = @hb_late", '%You cannot move the room to another booking.');
CALL zz_t_rejected("UPDATE roombooking SET checkout = '2034-03-13' WHERE hotelbookingID = @hb_late", 'The cancellation date has passed.%decrease the number of days.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = '2034-03-11' WHERE hotelbookingID = @hb_late", 'The cancellation date has passed.%decrease the number of days.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = '2034-03-20', checkout = '2034-03-22' WHERE hotelbookingID = @hb_late", 'The cancellation date has passed.%decrease the number of days.');
CALL zz_t_rejected("UPDATE roombooking SET checkin = '2034-03-01', checkout = '2034-03-03' WHERE hotelbookingID = @hb_late", 'The cancellation date has passed.%decrease the number of days.');
CALL zz_t_rejected("DELETE FROM roombooking WHERE hotelbookingID = @hb_late", 'Unable to execute operation! Cancelation date has expired.');
CALL zz_t_rejected("DELETE IGNORE FROM roombooking WHERE hotelbookingID = @hb_late", 'Unable to execute operation! Cancelation date has expired.');
CALL zz_t_rejected("DELETE FROM hotelbooking WHERE idhotelbooking = @hb_late", 'Cannot delete the reservation.');
CALL zz_t_rejected("UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = @hb_late", 'Cannot cancel the reservation. The cancellation date has passed.');
CALL zz_t_rejected("UPDATE hotelbooking SET cancellationdate = NULL WHERE idhotelbooking = @hb_late", 'Cannot update the cancellation date. Only the manager can.');
SELECT COUNT(*) INTO @k FROM roombooking WHERE hotelbookingID = @hb_late AND checkin = '2034-03-10' AND checkout = '2034-03-14' AND ABS(rate - @rate2) < 0.005;
CALL zz_t_true('row unchanged by the refused statements', @k = 1);
-- Ό,τι δεν μειώνει την κράτηση επιτρέπεται: αύξηση τιμής, παράταση, μετατόπιση ίδιας διάρκειας.
UPDATE roombooking SET rate = rate + 10 WHERE hotelbookingID = @hb_late;
UPDATE roombooking SET checkout = '2034-03-16' WHERE hotelbookingID = @hb_late;
UPDATE roombooking SET checkin = '2034-03-11', checkout = '2034-03-17' WHERE hotelbookingID = @hb_late;
UPDATE roombooking SET checkin = '2034-03-05' WHERE hotelbookingID = @hb_late;
INSERT INTO roombooking VALUES (@hb_late, @r3, @c1, '2034-03-10', '2034-03-12', NULL);       -- προσθήκη δωματίου
SELECT COUNT(*) INTO @k FROM roombooking WHERE hotelbookingID = @hb_late AND roomID = @r2 AND checkin = '2034-03-05' AND checkout = '2034-03-17';
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb_late;
CALL zz_t_true('extension and shift accepted', @k = 1 AND ABS(@tot - 12 * @rate2 - 2 * @rate3) < 0.005);
CALL zz_t_done('5.2  after the deadline: no rate cut, no move, fewer nights, delete or cancel; extensions are allowed');

-- Την προθεσμία ακύρωσης την αλλάζει μόνο κράτηση που τη διαχειρίζεται manager (και από/προς NULL).
CALL zz_t_rejected("UPDATE hotelbooking SET cancellationdate = CURRENT_DATE + INTERVAL 10 DAY WHERE idhotelbooking = @hb_late", 'Cannot update the cancellation date. Only the manager can.');
INSERT INTO Manages VALUES (@rec, @hb_late);
CALL zz_t_rejected("UPDATE hotelbooking SET cancellationdate = CURRENT_DATE + INTERVAL 10 DAY WHERE idhotelbooking = @hb_late", 'Cannot update the cancellation date. Only the manager can.');
UPDATE hotelbooking SET cancellationdate = cancellationdate, paymethod = 'card' WHERE idhotelbooking = @hb_late;   -- ίδια τιμή: δεν είναι αλλαγή
INSERT INTO Manages VALUES (@mgr, @hb_late);
UPDATE hotelbooking SET cancellationdate = NULL WHERE idhotelbooking = @hb_late;
UPDATE hotelbooking SET cancellationdate = CURRENT_DATE + INTERVAL 10 DAY WHERE idhotelbooking = @hb_late;
-- Τώρα η προθεσμία δεν έχει περάσει: μείωση νυχτών και ακύρωση επιτρέπονται.
UPDATE roombooking SET checkout = '2034-03-06' WHERE hotelbookingID = @hb_late AND roomID = @r2;
UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = @hb_late;
UPDATE hotelbooking SET status = 'confirmed', cancellationdate = CURRENT_DATE - INTERVAL 3 DAY WHERE idhotelbooking = @hb_late;
CALL zz_t_rejected("UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = @hb_late", 'Cannot cancel the reservation. The cancellation date has passed.');
SELECT status INTO @st FROM hotelbooking WHERE idhotelbooking = @hb_late;
CALL zz_t_true('booking still confirmed', @st = 'confirmed');
CALL zz_t_done('5.2  only a booking managed by a manager can change its cancellation date; cancel is allowed before it');

-- Κράτηση χωρίς προθεσμία ακύρωσης (NULL) και χωρίς status: τίποτα δεν απαγορεύεται, τίποτα δεν χρεώνεται.
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, NULL, NULL, @c1, TRUE, 'cash', NULL);
SET @hb_null = LAST_INSERT_ID();
INSERT INTO roombooking VALUES (@hb_null, @r3, @c1, '2034-05-01', '2034-05-05', NULL);
UPDATE roombooking SET checkout = '2034-05-03' WHERE hotelbookingID = @hb_null;
SELECT COUNT(*) INTO @k FROM `Transaction` WHERE idhotelbooking = @hb_null;
CALL zz_t_true('paid booking with NULL status is not charged', @k = 0);
UPDATE hotelbooking SET status = 'confirmed' WHERE idhotelbooking = @hb_null;
UPDATE hotelbooking SET status = NULL WHERE idhotelbooking = @hb_null;
SELECT COUNT(*), SUM(amount) INTO @k, @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb_null;
CALL zz_t_true('confirming charges, status NULL refunds', @k = 2 AND @sum_tx = 0);
CALL zz_t_rejected("UPDATE hotelbooking SET cancellationdate = CURRENT_DATE WHERE idhotelbooking = @hb_null", 'Cannot update the cancellation date. Only the manager can.');
UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = @hb_null;
DELETE FROM roombooking WHERE hotelbookingID = @hb_null;
DELETE FROM hotelbooking WHERE idhotelbooking = @hb_null;
SELECT COUNT(*) INTO @k FROM hotelbooking WHERE idhotelbooking = @hb_null;
CALL zz_t_true('booking without a deadline can be deleted', @k = 0);
CALL zz_t_done('5.2  NULL cancellation date and NULL status: no rule fires, nothing is charged');

-- =============================================================================================
-- 5.1  Καταγραφή συνδιαλλαγών
-- (η hb1 έχει ένα δωμάτιο, 2033-03-01 έως 2033-03-09, με ρητό rate 77: σύνολο 616)
-- =============================================================================================
UPDATE hotelbooking SET payed = TRUE WHERE idhotelbooking = @hb1;
SELECT COUNT(*), SUM(amount), MIN(action_tr), MIN(made_date) INTO @k, @sum_tx, @act, @d FROM `Transaction` WHERE idhotelbooking = @hb1;
CALL zz_t_true('payment recorded as one update of 616', @k = 1 AND @sum_tx = 616 AND @act = 'update' AND @d = CURRENT_DATE);

-- +1 νύχτα σε πληρωμένη κράτηση: το rate ξαναπαίρνει την τρέχουσα τιμή και καταγράφεται η διαφορά.
UPDATE roombooking SET checkout = '2033-03-10' WHERE hotelbookingID = @hb1;
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb1;
SELECT COUNT(*), SUM(amount) INTO @k, @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb1;
CALL zz_t_true('total after extension', ABS(@tot - 9 * @rate1b) < 0.005);
CALL zz_t_true('difference recorded', @k = 2);
CALL zz_t_true('ledger equals the total', ABS(@sum_tx - @tot) < 0.005);

DELETE FROM hotelbooking WHERE idhotelbooking = @hb1;
SELECT COUNT(*), SUM(amount) INTO @k, @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb1;
SELECT amount INTO @refund FROM `Transaction` WHERE idhotelbooking = @hb1 AND action_tr = 'delete';
SELECT COUNT(*) INTO @k2 FROM roombooking WHERE hotelbookingID = @hb1;
CALL zz_t_true('refund recorded as one delete row of the whole amount', @k = 3 AND ABS(@refund + @tot) < 0.005);
CALL zz_t_true('ledger balances after the delete and survives it', @sum_tx = 0);
CALL zz_t_true('rooms of the deleted booking are gone', @k2 = 0);
CALL zz_t_done('5.1  payment, extra payment and refund on delete are recorded');

INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2033-05-01', '2033-05-05', NULL);
SELECT totalamount INTO @tot FROM hotelbooking WHERE idhotelbooking = @hb2;
UPDATE hotelbooking SET payed = TRUE WHERE idhotelbooking = @hb2;
UPDATE hotelbooking SET payed = FALSE WHERE idhotelbooking = @hb2;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('unpaying records a refund', @sum_tx = 0);
UPDATE hotelbooking SET payed = TRUE WHERE idhotelbooking = @hb2;
SELECT COUNT(*), SUM(amount) INTO @k, @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('paying again charges once', @k = 3 AND ABS(@sum_tx - @tot) < 0.005);
UPDATE hotelbooking SET paymethod = 'cash' WHERE idhotelbooking = @hb2;            -- άσχετη αλλαγή: καμία εγγραφή
SELECT COUNT(*) INTO @k FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('an unrelated update records nothing', @k = 3);
CALL zz_t_done('5.1  toggling payed keeps the ledger equal to the amount charged');

UPDATE hotelbooking SET status = 'pending' WHERE idhotelbooking = @hb2;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('pending booking is not charged', @sum_tx = 0);
UPDATE hotelbooking SET status = 'confirmed' WHERE idhotelbooking = @hb2;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('confirming a paid booking is recorded', ABS(@sum_tx - @tot) < 0.005);
UPDATE hotelbooking SET status = 'canceled' WHERE idhotelbooking = @hb2;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking = @hb2;
CALL zz_t_true('canceling a paid booking is refunded', @sum_tx = 0);
-- Πληρωμένη κράτηση χωρίς δωμάτια: καμία εγγραφή τώρα, χρέωση όταν προστεθεί δωμάτιο.
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, NULL, @c1, TRUE, 'cash', 'confirmed');
SET @hb_paid = LAST_INSERT_ID();
SELECT COUNT(*) INTO @k FROM `Transaction` WHERE idhotelbooking = @hb_paid;
CALL zz_t_true('paid booking without rooms records nothing', @k = 0);
INSERT INTO roombooking VALUES (@hb_paid, @r2, @c1, '2033-06-01', '2033-06-04', NULL);
SELECT COUNT(*), SUM(amount), MIN(action_tr) INTO @k, @sum_tx, @act FROM `Transaction` WHERE idhotelbooking = @hb_paid;
CALL zz_t_true('charged when the room is added', @k = 1 AND ABS(@sum_tx - 3 * @rate2) < 0.005 AND @act = 'update');
-- Κράτηση που μπαίνει ήδη πληρωμένη με ποσό: εγγραφή τύπου insert.
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, 250.5, @c1, TRUE, 'cash', 'confirmed');
SET @hb_paid2 = LAST_INSERT_ID();
SELECT COUNT(*), SUM(amount), MIN(action_tr) INTO @k, @sum_tx, @act FROM `Transaction` WHERE idhotelbooking = @hb_paid2;
CALL zz_t_true('insert row for a booking inserted as paid', @k = 1 AND @sum_tx = 250.5 AND @act = 'insert');
DELETE FROM hotelbooking WHERE idhotelbooking IN (@hb_paid, @hb_paid2);
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking IN (@hb_paid, @hb_paid2);
CALL zz_t_true('both refunded on delete', @sum_tx = 0);
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
UPDATE hotelbooking SET status = 'confirmed', payed = FALSE WHERE idhotelbooking = @hb2;
CALL zz_t_done('5.1  status changes are recorded; a paid booking can be inserted before its rooms');

-- =============================================================================================
-- 1.1  Έλεγχοι στους πίνακες Manages και Participates (CHECK στην PostgreSQL, triggers εδώ)
-- =============================================================================================
INSERT INTO roombooking VALUES (@hb2, @r1, @c1, '2035-01-01', '2035-01-03', NULL);
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE, CURRENT_DATE + INTERVAL 5 DAY, NULL, @c1, FALSE, NULL, 'confirmed');
SET @hb_empty = LAST_INSERT_ID();
CALL zz_t_rejected("INSERT INTO Manages VALUES (@staff, @hb2)", 'Manages: the employee must be manager or reception%');
CALL zz_t_rejected("INSERT INTO Manages VALUES (@othermgr, @hb2)", 'Manages: the employee must be manager or reception%');
CALL zz_t_rejected("INSERT INTO Manages VALUES (@mgr, @hb_empty)", 'Manages: the employee must be manager or reception%');
INSERT INTO Manages VALUES (@mgr, @hb2);
INSERT INTO Manages VALUES (@rec, @hb2);
CALL zz_t_rejected("UPDATE Manages SET employeeid = @staff WHERE idhotelbooking = @hb2 AND employeeid = @rec", 'Manages: the employee must be manager or reception%');
CALL zz_t_rejected("UPDATE Manages SET idhotelbooking = @hb_empty WHERE idhotelbooking = @hb2 AND employeeid = @rec", 'Manages: the employee must be manager or reception%');
SELECT COUNT(*) INTO @k FROM Manages WHERE idhotelbooking = @hb2;
CALL zz_t_true('manager and reception accepted, nothing else', @k = 2);
DELETE FROM Manages WHERE idhotelbooking = @hb2;
DELETE FROM hotelbooking WHERE idhotelbooking = @hb_empty;
CALL zz_t_done('1.1  Manages accepts only a manager or receptionist of the hotel of the booking');

-- Δική μας δραστηριότητα στο ξενοδοχείο 11. Ο @c1 έχει κράτηση δωματίου εκεί (hb2), ο νέος πελάτης όχι.
INSERT INTO Activity VALUES (11, '03:11:00', '03:12:00', 6, 'tennis', @mgr);
SELECT `2_1_update_clients_and_cards`('insert', 'ZZ-TEST-5', 'N', 'N', 'F', '1990-01-01', 'x', 'y', 'Greece',
       'visa', 'ZZ-CARD-6', CURRENT_DATE + INTERVAL 30 DAY, 'N') INTO @ret;
SET @p5 = NULL;
SELECT idClient INTO @p5 FROM client WHERE documentclient = 'ZZ-TEST-5';
INSERT INTO Participates VALUES (@c1, 11, 6, '03:11:00', '03:12:00', 'participant');
INSERT INTO Participates VALUES (@mgr, 11, 6, '03:11:00', '03:12:00', 'responsible');
CALL zz_t_rejected("INSERT INTO Participates VALUES (@p5, 11, 6, '03:11:00', '03:12:00', 'participant')", 'Participates: the person does not fit this role%');
CALL zz_t_rejected("INSERT INTO Participates VALUES (@p5, 11, 6, '03:11:00', '03:12:00', 'responsible')", 'Participates: the person does not fit this role%');
CALL zz_t_rejected("INSERT INTO Participates VALUES (@othermgr, 11, 6, '03:11:00', '03:12:00', 'responsible')", 'Participates: the person does not fit this role%');
CALL zz_t_rejected("UPDATE Participates SET participant_role = 'responsible' WHERE amka_person = @c1 AND idhotel = 11 AND starttime = '03:11:00'", 'Participates: the person does not fit this role%');
CALL zz_t_rejected("UPDATE Participates SET amka_person = @p5 WHERE amka_person = @c1 AND idhotel = 11 AND starttime = '03:11:00'", 'Participates: the person does not fit this role%');
SELECT COUNT(*) INTO @k FROM Participates WHERE idhotel = 11 AND starttime = '03:11:00';
CALL zz_t_true('guest and employee accepted, nothing else', @k = 2);
DELETE FROM Participates WHERE idhotel = 11 AND starttime = '03:11:00';
DELETE FROM Activity WHERE idhotel = 11 AND starttime = '03:11:00';
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_done('1.1  Participates: a participant has a room in the hotel, a responsible is its employee');

-- =============================================================================================
-- 6.2  Εβδομαδιαίο πλάνο
-- =============================================================================================
SELECT `6_2_next_week_start`() INTO @ws;
SELECT COUNT(*), COUNT(DISTINCT week_start), MIN(week_start) INTO @k, @k2, @d FROM `6_2_weeklyPlan` WHERE idHotel = 11;
SELECT COUNT(*) INTO @k3 FROM room WHERE idHotel = 11;
CALL zz_t_true('week start is next Sunday', DAYOFWEEK(@ws) = 1 AND @ws > CURRENT_DATE AND @ws <= CURRENT_DATE + INTERVAL 7 DAY);
CALL zz_t_true('one row per room, all with that week', @k = @k3 AND @k2 = 1 AND @d = @ws);
CALL zz_t_plan(@r1);
CALL zz_t_true('test room is free next week', @plan = '0,0,0,0,0,0,0');
CALL zz_t_done('6.2  the plan shows next week (Sunday to Saturday), one row per room');

SELECT COUNT(*) INTO @n_hb FROM hotelbooking;
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, @doc1, @doc1, @doc1, NULL, NULL, NULL) INTO @ret;
CALL zz_t_plan(@r1);
SELECT COUNT(*) INTO @k FROM roombooking WHERE roomID = @r1 AND checkin = @ws + INTERVAL 1 DAY AND checkout = @ws + INTERVAL 4 DAY AND bookedforpersonID = @c1;
SET @hb_w = NULL;
SELECT hotelbookingID INTO @hb_w FROM roombooking WHERE roomID = @r1 AND checkin = @ws + INTERVAL 1 DAY;
SELECT COUNT(*) INTO @k2 FROM hotelbooking
WHERE idhotelbooking = @hb_w AND bookedbyclientID = @c1 AND status = 'confirmed' AND NOT payed
  AND reservationdate = CURRENT_DATE AND cancellationdate = @ws AND ABS(totalamount - 3 * @rate1b) < 0.005;
CALL zz_t_true('days booked', @plan = CONCAT_WS(',', '0', @doc1, @doc1, @doc1, '0', '0', '0'));
CALL zz_t_true('three nights are one room booking', @k = 1);
CALL zz_t_true('new hotel booking: client, dates, total', @k2 = 1);

SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, '0', NULL, NULL, NULL, NULL) INTO @ret;     -- νύχτα στη μέση
CALL zz_t_plan(@r1);
SELECT COUNT(*), COUNT(DISTINCT hotelbookingID) INTO @k, @k2 FROM roombooking WHERE roomID = @r1 AND checkin >= @ws AND checkin < @ws + INTERVAL 7 DAY;
CALL zz_t_true('middle night freed', @plan = CONCAT_WS(',', '0', @doc1, '0', @doc1, '0', '0', '0'));
CALL zz_t_true('booking split in two', @k = 2 AND @k2 = 2);

SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, '0', NULL, '', NULL, NULL, NULL) INTO @ret;       -- '' = ελεύθερο
CALL zz_t_plan(@r1);
SELECT COUNT(*) INTO @k FROM roombooking WHERE roomID = @r1 AND checkout > @ws AND checkin < @ws + INTERVAL 7 DAY;
SELECT COUNT(*) INTO @k2 FROM hotelbooking;
CALL zz_t_true('room free all week', @plan = '0,0,0,0,0,0,0' AND @k = 0);
CALL zz_t_true('no empty hotel bookings left behind', @k2 = @n_hb);
CALL zz_t_done('6.2  nights are booked, split and freed through the plan');

-- Γειτονικές νύχτες του ίδιου πελάτη επεκτείνουν την κράτηση· άλλος πελάτης παίρνει δική του.
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, @doc1, NULL, NULL, NULL, NULL) INTO @ret;   -- Τρίτη
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, @doc1, NULL, NULL, NULL, NULL, NULL) INTO @ret;   -- Δευτέρα: νωρίτερο checkin
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, @doc1, NULL, NULL, NULL) INTO @ret;   -- Τετάρτη: παράταση
SELECT COUNT(*) INTO @k FROM roombooking WHERE roomID = @r1 AND checkin = @ws + INTERVAL 1 DAY AND checkout = @ws + INTERVAL 4 DAY;
CALL zz_t_true('one booking Monday to Thursday morning', @k = 1);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, NULL, @doc2, NULL, NULL) INTO @ret;   -- Πέμπτη: άλλος πελάτης
SELECT COUNT(*) INTO @k FROM roombooking WHERE roomID = @r1 AND checkin >= @ws AND checkin < @ws + INTERVAL 7 DAY;
CALL zz_t_true('another client gets a separate booking', @k = 2);
-- Αντικατάσταση πελάτη σε μία κλήση (απελευθέρωση και κλείσιμο) και κλήση χωρίς αλλαγές.
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, @doc2, NULL, NULL, NULL) INTO @ret;
CALL zz_t_plan(@r1);
CALL zz_t_true('occupant replaced on Wednesday', @plan = CONCAT_WS(',', '0', @doc1, @doc1, @doc2, @doc2, '0', '0'));
SELECT COUNT(*) INTO @k FROM roombooking WHERE roomID = @r1 AND bookedforpersonID = @c2 AND checkin = @ws + INTERVAL 3 DAY AND checkout = @ws + INTERVAL 5 DAY;
CALL zz_t_true('the new occupant has one two-night booking', @k = 1);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, '0', @doc1, NULL, NULL, CONCAT('  ', @doc2, ' '), NULL, NULL) INTO @ret;
CALL zz_t_true('same values (also with spaces around): 0 changes', @ret = 0);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
CALL zz_t_true('all NULL: 0 changes', @ret = 0);
-- Νύχτα πιασμένη από άλλον πελάτη: με άλλο έγγραφο πρώτα ελευθερώνεται, άρα δεν υπάρχει διπλοκράτηση.
SELECT COUNT(*) INTO @k FROM roombooking a JOIN roombooking b
  ON a.roomID = b.roomID AND a.hotelbookingID < b.hotelbookingID AND a.checkin < b.checkout AND b.checkin < a.checkout
WHERE a.roomID = @r1;
CALL zz_t_true('no overlapping bookings on the room', @k = 0);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, '0', '0', '0', '0', '0', '0', '0') INTO @ret;
CALL zz_t_plan(@r1);
SELECT COUNT(*) INTO @k2 FROM hotelbooking;
CALL zz_t_true('everything freed again', @plan = '0,0,0,0,0,0,0' AND @k2 = @n_hb);
CALL zz_t_done('6.2  adjacent nights extend the booking, other clients get their own, an occupant can be replaced');

-- Τιμή και έκπτωση.
SELECT `6_2_weeklyPlan_update`(@r1, 123, 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
SELECT rate, discount INTO @v_rate, @v_disc FROM `6_2_weeklyPlan` WHERE idRoom = @r1;
SELECT rate, discount INTO @rr_rate, @rr_disc FROM roomrate WHERE idHotel = 11 AND roomtype = @type1;
CALL zz_t_true('one change reported', @ret = 1);
CALL zz_t_true('plan shows the new rate and discount', @v_rate = 123 AND @v_disc = 10);
CALL zz_t_true('roomrate updated', @rr_rate = 123 AND @rr_disc = 10);
CALL zz_t_true('current rate = 110.7', ABS(`5_3_current_room_rate`(@r1) - 110.7) < 0.005);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, 20, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;      -- μόνο έκπτωση
SELECT rate, discount INTO @rr_rate, @rr_disc FROM roomrate WHERE idHotel = 11 AND roomtype = @type1;
CALL zz_t_true('discount alone keeps the rate', @rr_rate = 123 AND @rr_disc = 20);
SELECT `6_2_weeklyPlan_update`(@r1, 123, 20, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
CALL zz_t_true('same rate and discount: 0 changes', @ret = 0);
-- Τιμή και κλείσιμο μαζί: η νέα κράτηση παίρνει τη νέα τιμή.
SELECT `6_2_weeklyPlan_update`(@r1, 100, 0, NULL, NULL, NULL, NULL, NULL, @doc1, NULL) INTO @ret;
SELECT rate INTO @rate FROM roombooking WHERE roomID = @r1 AND checkin = @ws + INTERVAL 5 DAY;
CALL zz_t_true('rate change and booking in one call', @ret = 2 AND @rate = 100);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, '0', NULL) INTO @ret;
CALL zz_t_done('6.2  rate and discount are updated through the plan');

-- Αρνήσεις, και ότι μια κλήση που αποτυγχάνει στη μέση δεν αφήνει τίποτα.
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r1, -1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'Rate must be >= 0 and discount between 0 and 100.');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r1, NULL, 101, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'Rate must be >= 0 and discount between 0 and 100.');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r1, NULL, -1, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'Rate must be >= 0 and discount between 0 and 100.');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'ZZ-NO-SUCH-DOCUMENT', NULL) INTO @ret", 'There is no client with document client ZZ-NO-SUCH-DOCUMENT.');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(-5, NULL, NULL, NULL, @doc1, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'There is no room with id -5.');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(NULL, NULL, NULL, NULL, @doc1, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'There is no room with id NULL.');
SET @sql = CONCAT("SELECT `6_2_weeklyPlan_update`(", COALESCE(@r_norate, -1), ", 10, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret");
CALL zz_t_rejected(@sql, 'There is no r%');
-- Αλλαγή τιμής + κλείσιμο Δευτέρας + άγνωστος πελάτης το Σάββατο: αναιρούνται όλα.
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r1, 500, 50, NULL, @doc1, NULL, NULL, NULL, NULL, 'ZZ-NO-SUCH-DOCUMENT') INTO @ret", 'There is no client with document client ZZ-NO-SUCH-DOCUMENT.');
CALL zz_t_plan(@r1);
SELECT rate, discount INTO @rr_rate, @rr_disc FROM roomrate WHERE idHotel = 11 AND roomtype = @type1;
SELECT COUNT(*) INTO @k2 FROM hotelbooking;
CALL zz_t_true('refused call left no booking', @plan = '0,0,0,0,0,0,0' AND @k2 = @n_hb);
CALL zz_t_true('refused call left the rate alone', @rr_rate = 100 AND @rr_disc = 0);
-- Η όψη δεν ενημερώνεται απευθείας (τεκμηριωμένη διαφορά: στην PostgreSQL γίνεται με INSTEAD OF triggers).
CALL zz_t_rejected("UPDATE `6_2_weeklyPlan` SET monday = '0' WHERE idRoom = @r1", '%not updatable%');
CALL zz_t_rejected("DELETE FROM `6_2_weeklyPlan` WHERE idRoom = @r1", '%not updatable%');
CALL zz_t_done('6.2  bad rate or discount, unknown room or client are rejected; a refused call changes nothing');

-- Σπάσιμο πληρωμένης κράτησης: τα δύο μισά μένουν πληρωμένα, με τους ίδιους υπαλλήλους.
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, @doc1, @doc1, @doc1, NULL, NULL, NULL) INTO @ret;
SET @hb_w = NULL;
SELECT hotelbookingID INTO @hb_w FROM roombooking WHERE roomID = @r1 AND checkin = @ws + INTERVAL 1 DAY;
INSERT INTO Manages VALUES (@mgr, @hb_w);
UPDATE hotelbooking SET payed = TRUE, paymethod = 'cash' WHERE idhotelbooking = @hb_w;
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, NULL, '0', NULL, NULL, NULL, NULL) INTO @ret;
SELECT COUNT(*), SUM(h.payed), SUM(h.paymethod = 'cash'), SUM(h.totalamount), MAX(h.idhotelbooking)
INTO @k, @k_paid, @k_cash, @tot, @hb_w2
FROM hotelbooking h JOIN roombooking rb ON rb.hotelbookingID = h.idhotelbooking
WHERE rb.roomID = @r1 AND rb.checkin >= @ws AND rb.checkin < @ws + INTERVAL 7 DAY;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking IN (@hb_w, @hb_w2);
SELECT COUNT(*) INTO @k2 FROM Manages WHERE idhotelbooking = @hb_w2 AND employeeid = @mgr;
CALL zz_t_true('two bookings, both paid by cash', @k = 2 AND @k_paid = 2 AND @k_cash = 2 AND @hb_w2 > @hb_w);
CALL zz_t_true('two nights remain charged', ABS(@tot - 2 * 100) < 0.005 AND ABS(@sum_tx - 2 * 100) < 0.005);
CALL zz_t_true('second half keeps the manager', @k2 = 1);
SELECT `6_2_weeklyPlan_update`(@r1, NULL, NULL, NULL, '0', NULL, '0', NULL, NULL, NULL) INTO @ret;
SELECT COUNT(*) INTO @k FROM hotelbooking;
SELECT SUM(amount) INTO @sum_tx FROM `Transaction` WHERE idhotelbooking IN (@hb_w, @hb_w2);
SELECT COUNT(*) INTO @k2 FROM Manages WHERE idhotelbooking IN (@hb_w, @hb_w2);
CALL zz_t_true('no empty hotel bookings left behind', @k = @n_hb);
CALL zz_t_true('everything refunded', @sum_tx = 0);
CALL zz_t_true('Manages rows went with the bookings', @k2 = 0);
CALL zz_t_done('6.2  splitting a paid booking keeps it paid; freeing every night leaves no empty booking');

-- Διαμονή που έχει αρχίσει και τελειώνει την Κυριακή της επόμενης εβδομάδας: παράταση μέσω του πλάνου.
INSERT INTO roombooking VALUES (@hb2, @r2, @c1, CURRENT_DATE - INTERVAL 1 DAY, @ws, NULL);
SELECT `6_2_weeklyPlan_update`(@r2, NULL, NULL, @doc1, NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
SELECT checkout INTO @d FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_true('in-house stay extended by one night', @d = @ws + INTERVAL 1 DAY);
SELECT `6_2_weeklyPlan_update`(@r2, NULL, NULL, '0', NULL, NULL, NULL, NULL, NULL, NULL) INTO @ret;
SELECT checkout INTO @d FROM roombooking WHERE hotelbookingID = @hb2;
CALL zz_t_true('and shortened again', @d = @ws);
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
-- Κράτηση χωρίς υπεύθυνο πρόσωπο δεν φαίνεται ως ελεύθερη.
INSERT INTO roombooking VALUES (@hb2, @r2, NULL, @ws + INTERVAL 1 DAY, @ws + INTERVAL 2 DAY, NULL);
CALL zz_t_plan(@r2);
CALL zz_t_true('booking without a person is not shown as free', @plan = '0,person ?,0,0,0,0,0');
DELETE FROM roombooking WHERE hotelbookingID = @hb2;
-- Νύχτες κράτησης που πέρασε την προθεσμία ακύρωσης δεν ελευθερώνονται από το πλάνο.
INSERT INTO hotelbooking (reservationdate, cancellationdate, totalamount, bookedbyclientID, payed, paymethod, status)
VALUES (CURRENT_DATE - INTERVAL 9 DAY, CURRENT_DATE - INTERVAL 1 DAY, NULL, @c2, FALSE, NULL, 'confirmed');
SET @hb_late2 = LAST_INSERT_ID();
INSERT INTO roombooking VALUES (@hb_late2, @r2, @c2, @ws + INTERVAL 1 DAY, @ws + INTERVAL 4 DAY, NULL);
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r2, NULL, NULL, NULL, NULL, '0', NULL, NULL, NULL, NULL) INTO @ret", 'The cancellation date has passed.%');
CALL zz_t_rejected("SELECT `6_2_weeklyPlan_update`(@r2, NULL, NULL, NULL, @doc1, NULL, NULL, NULL, NULL, NULL) INTO @ret", 'The cancellation date has passed.%');
SELECT `6_2_weeklyPlan_update`(@r2, NULL, NULL, NULL, NULL, NULL, NULL, @doc2, NULL, NULL) INTO @ret;   -- η παράταση επιτρέπεται
CALL zz_t_plan(@r2);
CALL zz_t_true('late booking only grew', @plan = CONCAT_WS(',', '0', @doc2, @doc2, @doc2, @doc2, '0', '0'));
CALL zz_t_done('6.2  an in-house stay can be extended; no person is not free; the deadline rules apply to the plan');

-- =============================================================================================
-- Σημεία ειδικά για τη MySQL (βρέθηκαν στον έλεγχο της μεταφοράς και διορθώθηκαν)
-- =============================================================================================

-- (α) Ένα INSERT / UPDATE του roombooking μπορεί να διαβάζει τον πίνακα room. Το trigger κλειδώνει γραμμή
--     του room_lock και όχι του room· αλλιώς τέτοιες εντολές θα έπεφταν σε σφάλμα 1442.
CALL zz_t_accepted("INSERT INTO roombooking VALUES (@hb2, (SELECT idRoom FROM room WHERE idRoom = @r3), @c1, '2036-01-01', '2036-01-03', NULL)");
CALL zz_t_accepted("INSERT INTO roombooking SELECT @hb2, idRoom, @c1, '2036-02-01', '2036-02-03', NULL FROM room WHERE idRoom = @r3 AND NOT EXISTS (SELECT 1 FROM roombooking x WHERE x.hotelbookingID = @hb2 AND x.roomID = @r3)");
CALL zz_t_accepted("UPDATE roombooking SET checkout = checkout + INTERVAL 1 DAY WHERE hotelbookingID = @hb2 AND roomID IN (SELECT idRoom FROM room WHERE idHotel = 11)");
CALL zz_t_accepted("SELECT `6_2_weeklyPlan_update`((SELECT idRoom FROM room WHERE idRoom = @r3), NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, @doc1) INTO @ret");
CALL zz_t_done('MySQL a  a room booking statement may look the room up in table room (no error 1442)');

-- (β) Οι στήλες ημερών της όψης συγκρίνονται με σταθερά κειμένου και από σύνδεση utf8mb4
--     (π.χ. μετά από SET NAMES utf8mb4, όπως εδώ), χωρίς σφάλμα 1267 «Illegal mix of collations».
CALL zz_t_accepted("SELECT COUNT(*) INTO @ret FROM `6_2_weeklyPlan` WHERE idRoom = @r1 AND monday = '0'");
CALL zz_t_accepted("SELECT COUNT(*) INTO @ret FROM `6_2_weeklyPlan` WHERE idHotel = 11 AND saturday <> '0'");
-- Η ίδια η συνάρτηση θέλει ρητό COLLATE όταν συγκρίνεται με σταθερά (η όψη το έχει ήδη).
CALL zz_t_accepted("SELECT `6_2_room_occupant`(@r1, CURRENT_DATE) COLLATE utf8mb4_0900_as_cs = '0' INTO @ret");
CALL zz_t_done('MySQL b  the day columns of the plan can be compared with a string literal on a utf8mb4 connection');

-- (γ) Απευθείας DELETE σε person / room: τα BEFORE DELETE triggers σβήνουν πρώτα ρητά τις κρατήσεις, άρα
--     η προθεσμία ακύρωσης δεν παρακάμπτεται (με σκέτο cascade η MySQL δεν θα έτρεχε τα triggers τους).
--     Ο πελάτης ZZ-TEST-4 έχει κράτηση με δωμάτιο που πέρασε την προθεσμία· το ίδιο και το δωμάτιο @r2.
CALL zz_t_rejected("DELETE FROM person WHERE idPerson = @p4", '%ancel%');
SELECT COUNT(*) INTO @k FROM hotelbooking WHERE idhotelbooking = @hb_p4b;
CALL zz_t_true('booking past its deadline survived DELETE FROM person', @k = 1);
CALL zz_t_rejected("DELETE FROM room WHERE idRoom = @r2", '%ancel%');
SELECT COUNT(*) INTO @k FROM roombooking WHERE hotelbookingID = @hb_late2;
CALL zz_t_true('room booking past its deadline survived DELETE FROM room', @k = 1);
CALL zz_t_done('MySQL c  deleting a person or a room cannot remove bookings that are past their cancellation date');

ROLLBACK;

DROP PROCEDURE IF EXISTS zz_t_exec;
DROP PROCEDURE IF EXISTS zz_t_true;
DROP PROCEDURE IF EXISTS zz_t_rejected;
DROP PROCEDURE IF EXISTS zz_t_accepted;
DROP PROCEDURE IF EXISTS zz_t_done;
DROP PROCEDURE IF EXISTS zz_t_plan;

-- Τελικό αποτέλεσμα. Με αποτυχίες, το PREPARE σκάει με το πλήθος τους στο μήνυμα (ο πίνακας δεν υπάρχει)
-- και το "ALL TESTS PASSED" δεν τυπώνεται.
SET @zz_final = IF(@zz_failed = 0,
                   "SELECT 'ALL TESTS PASSED' AS ''",
                   CONCAT("SELECT * FROM `", @zz_failed, " CHECK(S) FAILED - see the FAILED lines above`"));
PREPARE zz_final FROM @zz_final;
EXECUTE zz_final;
DEALLOCATE PREPARE zz_final;
