-- Οι συναρτήσεις ερωτημάτων (μόνο ανάγνωση) της βάσης, μεταφερμένες από την PostgreSQL σε MySQL 8.4.
-- Πηγή: οι διορθωμένες εκδοχές (db/original/schema.sql + db/fixes/). Τα ονόματα μένουν ίδια.
--
-- Αντιστοιχίες:
--   συνάρτηση RETURNS TABLE   -> PROCEDURE που επιστρέφει ένα result set με τις ίδιες στήλες (CALL)
--   παράμετροι / μεταβλητές   -> πρόθεμα p_ / v_ (αλλιώς η MySQL τις μπερδεύει με ομώνυμες στήλες)
--   real                      -> FLOAT· όπου η PostgreSQL επιστρέφει real μπαίνει CAST(... AS FLOAT),
--                                γιατί η MySQL κάνει τις πράξεις σε double
--   IS NOT DISTINCT FROM      -> <=>
--   generate_series(1, 12)    -> αναδρομικό CTE
--   extract(year from age())  -> TIMESTAMPDIFF(YEAR, ...)
--   random()                  -> RAND()
--
-- Το αρχείο τρέχει όσες φορές χρειαστεί (DROP ... IF EXISTS / CREATE OR REPLACE VIEW).

SET NAMES utf8mb4;

DELIMITER $$

-- ---------------------------------------------------------------------------------------
-- 1.1  Βοηθητικές για το γέμισμα του πίνακα Manages.
-- ---------------------------------------------------------------------------------------

-- n τυχαίες κρατήσεις (idhotelbooking).
DROP PROCEDURE IF EXISTS `1_1_select_random_hotel_bookingID`$$
CREATE PROCEDURE `1_1_select_random_hotel_bookingID`(IN p_n INT)
    READS SQL DATA
BEGIN
    SELECT hb.idhotelbooking AS hotelbookingid
    FROM hotelbooking AS hb
    ORDER BY RAND()
    LIMIT p_n;
END$$

-- n τυχαίοι υπάλληλοι (manager ή reception) του ξενοδοχείου στο οποίο ανήκει η κράτηση.
DROP PROCEDURE IF EXISTS `1_1_select_random_employee_from_hotel_bookingID`$$
CREATE PROCEDURE `1_1_select_random_employee_from_hotel_bookingID`(IN p_hotelbookingid INT, IN p_n INT)
    READS SQL DATA
BEGIN
    SELECT e.idEmployee AS employeeid
    FROM employee AS e
    WHERE e.hotelID = (SELECT DISTINCT r.idHotel
                       FROM room AS r
                       WHERE r.idRoom IN (SELECT rb.roomID
                                          FROM roombooking AS rb
                                          WHERE rb.hotelbookingID = p_hotelbookingid))
      AND (e.role = 'manager' OR e.role = 'reception')
    ORDER BY RAND()
    LIMIT p_n;
END$$

-- Γεμίζει τον Manages: n προσπάθειες, καθεμία με τυχαία κράτηση και τυχαίο υπάλληλο του ξενοδοχείου
-- της. Το ζευγάρι μπαίνει μόνο αν βρέθηκε υπάλληλος και δεν υπάρχει ήδη. Οι δύο τυχαίες επιλογές
-- γράφονται εδώ μέσα, γιατί μια PROCEDURE δεν καλείται μέσα σε έκφραση.
DROP PROCEDURE IF EXISTS `1_1_fill_manages`$$
CREATE PROCEDURE `1_1_fill_manages`(IN p_n INT)
    MODIFIES SQL DATA
BEGIN
    DECLARE v_i INT DEFAULT 1;
    DECLARE v_bookingid INT;
    DECLARE v_employeeid INT;
    DECLARE v_alreadyexists TINYINT(1);

    WHILE v_i <= p_n DO
        SET v_bookingid = NULL;
        SET v_employeeid = NULL;

        SELECT hb.idhotelbooking INTO v_bookingid
        FROM hotelbooking AS hb
        ORDER BY RAND()
        LIMIT 1;

        -- Με SET (όχι SELECT ... INTO): όταν δεν βρεθεί υπάλληλος η μεταβλητή μένει NULL χωρίς
        -- προειδοποίηση.
        SET v_employeeid =
            (SELECT e.idEmployee
             FROM employee AS e
             WHERE e.hotelID = (SELECT DISTINCT r.idHotel
                                FROM room AS r
                                WHERE r.idRoom IN (SELECT rb.roomID
                                                   FROM roombooking AS rb
                                                   WHERE rb.hotelbookingID = v_bookingid))
               AND (e.role = 'manager' OR e.role = 'reception')
             ORDER BY RAND()
             LIMIT 1);

        SET v_alreadyexists = EXISTS (SELECT 1
                                      FROM Manages AS ma
                                      WHERE ma.idhotelbooking = v_bookingid
                                        AND ma.employeeid = v_employeeid);

        IF v_employeeid IS NOT NULL AND v_alreadyexists = 0 THEN
            INSERT INTO Manages (employeeid, idhotelbooking) VALUES (v_employeeid, v_bookingid);
        END IF;

        SET v_i = v_i + 1;
    END WHILE;
END$$

-- ---------------------------------------------------------------------------------------
-- 3.x  Ερωτήματα ανάκτησης.
-- ---------------------------------------------------------------------------------------

-- 3.1  Χώρα και πόλη των ξενοδοχείων που έχουν κάποια τιμή δωματίου με έκπτωση πάνω από 30%.
DROP PROCEDURE IF EXISTS `3_1_cities_countries_with_disc_over_30`$$
CREATE PROCEDURE `3_1_cities_countries_with_disc_over_30`()
    READS SQL DATA
BEGIN
    SELECT h.country, h.city
    FROM hotel AS h
    WHERE EXISTS (SELECT h1.idHotel, discount
                  FROM hotel AS h1 NATURAL JOIN roomrate AS rr
                  WHERE rr.discount > 30 AND h.idHotel = h1.idHotel);
END$$

-- 3.2  Ξενοδοχεία με τα αστέρια και το πρόθεμα ονόματος που δίνονται, που έχουν Restaurant και
--      Breakfast και Studio με τελική τιμή κάτω από 80.
DROP PROCEDURE IF EXISTS `3_2_search_specific_hotels`$$
CREATE PROCEDURE `3_2_search_specific_hotels`(IN p_num_of_stars VARCHAR(10), IN p_prefix_name VARCHAR(45))
    READS SQL DATA
BEGIN
    SELECT h.idHotel AS id_hotel, h.name AS name_hotel
    FROM hotel AS h
    NATURAL JOIN (SELECT hf.idHotel FROM hotelfacilities AS hf WHERE hf.nameFacility = 'Restaurant'
                  INTERSECT
                  SELECT hf.idHotel FROM hotelfacilities AS hf WHERE hf.nameFacility = 'Breakfast') AS hf1
    NATURAL JOIN roomrate AS rr
    WHERE rr.roomtype = 'Studio'
      AND rr.rate - (rr.discount / 100 * rr.rate) < 80
      AND LEFT(h.name, CHAR_LENGTH(p_prefix_name)) = p_prefix_name
      AND h.stars LIKE p_num_of_stars;
END$$

-- 3.3  Για κάθε ξενοδοχείο, ο τύπος (ή οι τύποι) δωματίου με τη μεγαλύτερη έκπτωση.
DROP PROCEDURE IF EXISTS `3_3_displayMaxDiscountRoomsPerHotel`$$
CREATE PROCEDURE `3_3_displayMaxDiscountRoomsPerHotel`()
    READS SQL DATA
BEGIN
    SELECT t2.hotelName AS name, t2.roomtype AS roomtype, CAST(t2.maxDiscount AS FLOAT) AS discount
    FROM (SELECT t1.hotelID, t1.hotelName, rr.roomtype, rr.discount, t1.maxDiscount
          FROM (SELECT h.idHotel AS hotelID, h.name AS hotelName, MAX(rr0.discount) AS maxDiscount
                FROM hotel AS h
                LEFT JOIN roomrate AS rr0 ON h.idHotel = rr0.idHotel
                GROUP BY h.idHotel, h.name) AS t1
          LEFT JOIN roomrate AS rr ON t1.hotelID = rr.idHotel
          LEFT JOIN roomtype AS rt ON rr.roomtype = rt.typename
          WHERE rr.discount = t1.maxDiscount) AS t2
    ORDER BY t2.roomtype;
END$$

-- 3.4  Οι κρατήσεις ενός ξενοδοχείου με τον πελάτη που τις έκανε· bookedby = 'Employee' όταν την
--      κράτηση τη διαχειρίζεται υπάλληλος (Manages), αλλιώς 'Client'.
DROP PROCEDURE IF EXISTS `3_4_displayBookingStatus`$$
CREATE PROCEDURE `3_4_displayBookingStatus`(IN p_hotelid INT)
    READS SQL DATA
BEGIN
    SELECT hb.idhotelbooking AS idhotelbooking,
           pe.fname AS clientfname,
           pe.lname AS clientlname,
           hb.reservationdate AS reservationdate,
           CASE WHEN EXISTS (SELECT 1 FROM Manages AS ma WHERE ma.idhotelbooking = hb.idhotelbooking)
                THEN 'Employee' ELSE 'Client' END AS bookedby
    FROM hotelbooking AS hb
    LEFT JOIN person AS pe ON pe.idPerson = hb.bookedbyclientID
    WHERE EXISTS (SELECT 1
                  FROM roombooking AS rb
                  JOIN room AS r ON r.idRoom = rb.roomID
                  WHERE rb.hotelbookingID = hb.idhotelbooking AND r.idHotel = p_hotelid)
    ORDER BY hb.idhotelbooking;
END$$

-- 3.5  Οι δραστηριότητες ενός ξενοδοχείου στις οποίες δεν συμμετέχει κανείς.
DROP PROCEDURE IF EXISTS `3_5_restoreActivities`$$
CREATE PROCEDURE `3_5_restoreActivities`(IN p_hotelid INT)
    READS SQL DATA
BEGIN
    SELECT ac.idhotel, ac.weekday, ac.starttime, ac.endtime
    FROM (SELECT * FROM Activity AS ac1 WHERE ac1.idhotel = p_hotelid) AS ac
    WHERE (ac.idhotel, ac.weekday, ac.starttime, ac.endtime)
          NOT IN (SELECT pa.idhotel, pa.weekday, pa.starttime, pa.endtime
                  FROM Participates AS pa
                  WHERE pa.idhotel = ac.idhotel);
END$$

-- 3.6  Όλοι οι υπο-τύποι μιας διευκόλυνσης, σε κάθε βάθος της ιεραρχίας, με τον γονέα τους.
DROP PROCEDURE IF EXISTS `3_6_findSubtypesOfAFacility`$$
CREATE PROCEDURE `3_6_findSubtypesOfAFacility`(IN p_facilitiesof VARCHAR(45))
    READS SQL DATA
BEGIN
    WITH RECURSIVE facilities_tree (child, parent) AS (
        SELECT f0.nameFacility, f0.subtypeOf
        FROM facility AS f0
        WHERE f0.subtypeOf = p_facilitiesof
        UNION
        SELECT f.nameFacility, f.subtypeOf
        FROM facilities_tree AS r, facility AS f
        WHERE r.child = f.subtypeOf
    )
    SELECT ft.child AS facility, ft.parent AS facilityof
    FROM facilities_tree AS ft;
END$$

-- 3.7  Ελεύθερα σήμερα δωμάτια με τη διευκόλυνση δωματίου που δίνεται, σε ξενοδοχεία με τη
--      διευκόλυνση ξενοδοχείου που δίνεται· μετράνε και όλοι οι υπο-τύποι των δύο διευκολύνσεων.
DROP PROCEDURE IF EXISTS `3_7_search_hotels_with_specific_facilities`$$
CREATE PROCEDURE `3_7_search_hotels_with_specific_facilities`(IN p_hotel_facility VARCHAR(45), IN p_room_facility VARCHAR(45))
    READS SQL DATA
BEGIN
    WITH RECURSIVE hotel_fac (name) AS (
        SELECT f.nameFacility FROM facility AS f
        WHERE f.nameFacility = p_hotel_facility AND f.type = 'hotel'
        UNION
        SELECT f.nameFacility FROM facility AS f JOIN hotel_fac AS p ON f.subtypeOf = p.name
    ), room_fac (name) AS (
        SELECT f.nameFacility FROM facility AS f
        WHERE f.nameFacility = p_room_facility AND f.type = 'room'
        UNION
        SELECT f.nameFacility FROM facility AS f JOIN room_fac AS p ON f.subtypeOf = p.name
    )
    SELECT r.idHotel AS id_hotel, r.idRoom AS id_room
    FROM room AS r
    WHERE EXISTS (SELECT 1 FROM hotelfacilities AS hf
                  WHERE hf.idHotel = r.idHotel AND hf.nameFacility IN (SELECT name FROM hotel_fac))
      AND EXISTS (SELECT 1 FROM roomfacilities AS rf
                  WHERE rf.idRoom = r.idRoom AND rf.nameFacility IN (SELECT name FROM room_fac))
      AND NOT EXISTS (SELECT 1 FROM roombooking AS rb
                      WHERE rb.roomID = r.idRoom AND rb.checkin <= CURRENT_DATE AND rb.checkout > CURRENT_DATE)
    ORDER BY r.idHotel, r.idRoom;
END$$

-- 3.8  Ξενοδοχεία που έχουν σήμερα τουλάχιστον ένα ελεύθερο δωμάτιο από κάθε τύπο δωματίου τους.
DROP PROCEDURE IF EXISTS `3_8_search_hotels_having_room_from_each_category`$$
CREATE PROCEDURE `3_8_search_hotels_having_room_from_each_category`()
    READS SQL DATA
BEGIN
    SELECT h.idHotel AS hotel_id
    FROM hotel AS h
    WHERE EXISTS (SELECT 1 FROM room AS r WHERE r.idHotel = h.idHotel)
      AND NOT EXISTS (
            SELECT 1
            FROM (SELECT DISTINCT r.roomtype FROM room AS r WHERE r.idHotel = h.idHotel) AS t
            WHERE NOT EXISTS (
                    SELECT 1
                    FROM room AS r2
                    WHERE r2.idHotel = h.idHotel
                      AND r2.roomtype <=> t.roomtype
                      AND NOT EXISTS (SELECT 1 FROM roombooking AS rb
                                      WHERE rb.roomID = r2.idRoom
                                        AND rb.checkin <= CURRENT_DATE AND rb.checkout > CURRENT_DATE)))
    ORDER BY h.idHotel;
END$$

-- ---------------------------------------------------------------------------------------
-- 4.x  Ερωτήματα με ομαδοποίηση και συναθροίσεις.
-- ---------------------------------------------------------------------------------------

-- 4.1  Για κάθε πελάτη και ξενοδοχείο όπου έχει μείνει (checkin ως σήμερα), σε πόσες
--      δραστηριότητες του ξενοδοχείου συμμετείχε.
DROP PROCEDURE IF EXISTS `4_1_find_clients_activities`$$
CREATE PROCEDURE `4_1_find_clients_activities`()
    READS SQL DATA
BEGIN
    SELECT stays.client_id AS id_client, stays.hotel_id AS id_hotel, COUNT(pa.amka_person) AS num_of_activities
    FROM (SELECT DISTINCT cl.idClient AS client_id, r.idHotel AS hotel_id
          FROM client AS cl
          JOIN roombooking AS rb ON rb.bookedforpersonID = cl.idClient
          JOIN room AS r ON r.idRoom = rb.roomID
          WHERE rb.checkin <= CURRENT_DATE) AS stays
    LEFT JOIN Participates AS pa
           ON pa.amka_person = stays.client_id
          AND pa.idhotel = stays.hotel_id
          AND pa.participant_role = 'participant'
    GROUP BY stays.client_id, stays.hotel_id
    ORDER BY stays.client_id, stays.hotel_id;
END$$

-- 4.2  Μέση ηλικία (σε συμπληρωμένα έτη, 2 δεκαδικά) όσων έχουν κράτηση σε δωμάτιο του τύπου που
--      δίνεται. Το CAST κρατά αρκετά δεκαδικά στον μέσο όρο ώστε η στρογγύλευση να γίνεται μία φορά.
DROP PROCEDURE IF EXISTS `4_2_countAvgAge`$$
CREATE PROCEDURE `4_2_countAvgAge`(IN p_roomtype_input VARCHAR(45))
    READS SQL DATA
BEGIN
    SELECT ROUND(AVG(CAST(TIMESTAMPDIFF(YEAR, pe.dateofbirth, CURRENT_DATE) AS DECIMAL(20, 10))), 2) AS average_age
    FROM person AS pe
    WHERE pe.idPerson IN (SELECT rb.bookedforpersonID
                          FROM roombooking AS rb
                          JOIN room AS ro ON ro.idRoom = rb.roomID
                          WHERE ro.roomtype = p_roomtype_input);
END$$

-- 4.3  Για κάθε τύπο δωματίου, η χαμηλότερη τελική τιμή στη χώρα που δίνεται και οι πόλεις όπου
--      βρίσκεται. Το γινόμενο rate * discount γίνεται FLOAT όπως στην PostgreSQL (real * real).
DROP PROCEDURE IF EXISTS `4_3_search_cheap_rooms_by_country`$$
CREATE PROCEDURE `4_3_search_cheap_rooms_by_country`(IN p_country_input VARCHAR(45))
    READS SQL DATA
BEGIN
    SELECT DISTINCT p.city AS city, p.roomtype AS roomtype, p.final_rate AS min_rate
    FROM (SELECT q.city, q.roomtype, q.final_rate,
                 MIN(q.final_rate) OVER (PARTITION BY q.roomtype) AS cheapest
          FROM (SELECT h.city, rr.roomtype,
                       CAST(rr.rate - CAST(rr.rate * rr.discount AS FLOAT) / 100 AS FLOAT) AS final_rate
                FROM hotel AS h
                JOIN roomrate AS rr ON rr.idHotel = h.idHotel
                WHERE h.country = p_country_input) AS q) AS p
    WHERE p.final_rate = p.cheapest
    ORDER BY p.roomtype, p.city;
END$$

-- 4.4  Ξενοδοχεία με έσοδα (πληρωμένες, επιβεβαιωμένες κρατήσεις) πάνω από τον μέσο όρο των
--      ξενοδοχείων της πόλης τους.
DROP PROCEDURE IF EXISTS `4_4_search_hotels_with_max_income`$$
CREATE PROCEDURE `4_4_search_hotels_with_max_income`()
    READS SQL DATA
BEGIN
    WITH booking_hotel AS (
        SELECT DISTINCT rb.hotelbookingID AS booking_id, r.idHotel AS hotel_id
        FROM roombooking AS rb
        JOIN room AS r ON r.idRoom = rb.roomID
    ), hotel_incomes AS (
        SELECT h.idHotel AS hotel_id, h.name, h.city, SUM(hb.totalamount) AS hotel_income
        FROM hotelbooking AS hb
        JOIN booking_hotel AS bh ON bh.booking_id = hb.idhotelbooking
        JOIN hotel AS h ON h.idHotel = bh.hotel_id
        WHERE hb.payed IS TRUE AND hb.status = 'confirmed'
        GROUP BY h.idHotel, h.name, h.city
    )
    SELECT hi.name AS hotel_name, hi.city AS hotel_city
    FROM hotel_incomes AS hi
    WHERE hi.hotel_income > (SELECT AVG(x.hotel_income) FROM hotel_incomes AS x WHERE x.city = hi.city)
    ORDER BY hi.name;
END$$

-- 4.5  Πληρότητα ενός ξενοδοχείου για κάθε μήνα του έτους: ποσοστό των δωματίων του που είχαν
--      κράτηση μέσα στον μήνα (2 δεκαδικά). Καμία γραμμή αν το ξενοδοχείο δεν έχει δωμάτια.
DROP PROCEDURE IF EXISTS `4_5_find_hotel_fullness`$$
CREATE PROCEDURE `4_5_find_hotel_fullness`(IN p_hotel_id INT, IN p_year_in INT)
    READS SQL DATA
BEGIN
    WITH RECURSIVE months (month_no) AS (
        SELECT 1
        UNION ALL
        SELECT month_no + 1 FROM months WHERE month_no < 12
    )
    SELECT p_hotel_id AS id_hotel,
           m.month_no AS month_value,
           ROUND(CAST(100.0 * (SELECT COUNT(DISTINCT r.idRoom)
                               FROM room AS r
                               JOIN roombooking AS rb ON rb.roomID = r.idRoom
                               WHERE r.idHotel = p_hotel_id
                                 AND rb.checkin < m.month_start + INTERVAL 1 MONTH
                                 AND rb.checkout > m.month_start) AS DECIMAL(30, 10))
                 / NULLIF((SELECT COUNT(*) FROM room AS r WHERE r.idHotel = p_hotel_id), 0), 2) AS month_fullness
    FROM (SELECT mo.month_no, MAKEDATE(p_year_in, 1) + INTERVAL (mo.month_no - 1) MONTH AS month_start
          FROM months AS mo) AS m
    WHERE EXISTS (SELECT 1 FROM room AS r WHERE r.idHotel = p_hotel_id)
    ORDER BY m.month_no;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------------------
-- 6.1  Ελεύθερα σήμερα δωμάτια ανά ξενοδοχείο και ως πότε μένουν ελεύθερα (η παραμονή της επόμενης
--      κράτησης· NULL αν δεν υπάρχει επόμενη).
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE VIEW `6_1_availableRoomsByHotel` AS
SELECT h.idHotel,
       h.name AS hotel_name,
       r.idRoom,
       r.number AS room_number,
       r.roomtype,
       (SELECT MIN(rb.checkin) - INTERVAL 1 DAY
        FROM roombooking AS rb
        WHERE rb.roomID = r.idRoom AND rb.checkin > CURRENT_DATE) AS available_until
FROM hotel AS h
JOIN room AS r ON r.idHotel = h.idHotel
WHERE NOT EXISTS (SELECT 1
                  FROM roombooking AS rb
                  WHERE rb.roomID = r.idRoom AND rb.checkin <= CURRENT_DATE AND rb.checkout > CURRENT_DATE);

DELIMITER $$

-- 6.1  Τα ελεύθερα σήμερα δωμάτια του ξενοδοχείου με το όνομα που δίνεται, από την παραπάνω όψη.
DROP PROCEDURE IF EXISTS `6_1_availableRoomsByHotel_function`$$
CREATE PROCEDURE `6_1_availableRoomsByHotel_function`(IN p_hotel_name_in VARCHAR(45))
    READS SQL DATA
BEGIN
    SELECT v.idRoom AS room_id, v.room_number AS room_number, v.roomtype AS room_type, v.available_until AS available_until
    FROM `6_1_availableRoomsByHotel` AS v
    WHERE v.hotel_name = p_hotel_name_in
    ORDER BY v.room_number;
END$$

DELIMITER ;
