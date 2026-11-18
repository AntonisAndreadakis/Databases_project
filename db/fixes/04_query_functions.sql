-- Διορθώσεις στις συναρτήσεις των ερωτημάτων 3 και 4 που δεν υπολόγιζαν αυτό που ζητά η
-- εκφώνηση. Τα λάθη βρέθηκαν συγκρίνοντας κάθε συνάρτηση με ανεξάρτητο ερώτημα πάνω στα
-- δεδομένα του backup. Οι αρχικές εκδοχές είναι στο db/original/schema.sql.

-- ---------------------------------------------------------------------------------------
-- 3.4  Κρατήσεις ενός ξενοδοχείου: (idHotelbooking, clientFname, clientLname,
--      reservationdate, bookedBy).
--      Πριν: τα ονόματα ήταν του υπευθύνου κάθε δωματίου και έβγαινε μία γραμμή ανά δωμάτιο
--      και ανά υπάλληλο του Manages (162 γραμμές για 57 κρατήσεις στο ξενοδοχείο 13).
--      Τώρα: μία γραμμή ανά κράτηση, με τον πελάτη που την έκανε. Το bookedBy μένει όπως το
--      όρισε η ομάδα: 'Employee' αν την κράτηση τη διαχειρίζεται υπάλληλος (Manages).
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "3_4_displayBookingStatus"(hotelid integer)
RETURNS TABLE(idhotelbooking integer, clientfname character varying, clientlname character varying,
              reservationdate date, bookedby character varying)
LANGUAGE sql STABLE
AS $$
    SELECT hb.idhotelbooking, pe.fname, pe.lname, hb.reservationdate,
           CASE WHEN EXISTS (SELECT 1 FROM "Manages" AS ma WHERE ma.idhotelbooking = hb.idhotelbooking)
                THEN 'Employee' ELSE 'Client' END::character varying
    FROM hotelbooking AS hb
    LEFT JOIN person AS pe ON pe."idPerson" = hb."bookedbyclientID"
    WHERE EXISTS (SELECT 1
                  FROM roombooking AS rb
                  JOIN room AS r ON r."idRoom" = rb."roomID"
                  WHERE rb."hotelbookingID" = hb.idhotelbooking AND r."idHotel" = hotelid)
    ORDER BY hb.idhotelbooking;
$$;

-- ---------------------------------------------------------------------------------------
-- 3.7  Ξενοδοχεία με συγκεκριμένη διευκόλυνση και ελεύθερα δωμάτια με συγκεκριμένη
--      διευκόλυνση, «λαμβάνοντας υπόψη τις ιεραρχίες».
--      Πριν: τέσσερις περιπτώσεις με UNION που ακολουθούσαν μόνο ένα επίπεδο υπο-τύπων, ενώ οι
--      διευκολύνσεις δωματίων έχουν τρία (Beverages & Drinks -> Coffee Kit -> Espresso Maker).
--      Τώρα: αναδρομικά όλοι οι απόγονοι, και για τις δύο διευκολύνσεις, σε ένα ερώτημα.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "3_7_search_hotels_with_specific_facilities"(hotel_facility character varying, room_facility character varying)
RETURNS TABLE(id_hotel integer, id_room integer)
LANGUAGE sql STABLE
AS $$
    WITH RECURSIVE hotel_fac(name) AS (
        SELECT f."nameFacility" FROM facility AS f WHERE f."nameFacility" = hotel_facility AND f.type = 'hotel'
        UNION
        SELECT f."nameFacility" FROM facility AS f JOIN hotel_fac AS p ON f."subtypeOf" = p.name
    ), room_fac(name) AS (
        SELECT f."nameFacility" FROM facility AS f WHERE f."nameFacility" = room_facility AND f.type = 'room'
        UNION
        SELECT f."nameFacility" FROM facility AS f JOIN room_fac AS p ON f."subtypeOf" = p.name
    )
    SELECT r."idHotel", r."idRoom"
    FROM room AS r
    WHERE EXISTS (SELECT 1 FROM hotelfacilities AS hf
                  WHERE hf."idHotel" = r."idHotel" AND hf."nameFacility" IN (SELECT name FROM hotel_fac))
      AND EXISTS (SELECT 1 FROM roomfacilities AS rf
                  WHERE rf."idRoom" = r."idRoom" AND rf."nameFacility" IN (SELECT name FROM room_fac))
      AND NOT EXISTS (SELECT 1 FROM roombooking AS rb
                      WHERE rb."roomID" = r."idRoom" AND rb.checkin <= current_date AND rb.checkout > current_date)
    ORDER BY r."idHotel", r."idRoom";
$$;

-- ---------------------------------------------------------------------------------------
-- 3.8  Ξενοδοχεία με τουλάχιστον ένα ελεύθερο δωμάτιο από κάθε τύπο δωματίου ΠΟΥ ΔΙΑΘΕΤΟΥΝ.
--      Πριν: ζητούσε το ξενοδοχείο να έχει κάθε τύπο που υπάρχει οπουδήποτε (μόνο 5 ξενοδοχεία
--      έχουν και τους 15) και απλώς κάποιο ελεύθερο δωμάτιο.
--      Τώρα: η διαίρεση γίνεται ως προς τους τύπους του ίδιου του ξενοδοχείου.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "3_8_search_hotels_having_room_from_each_category"()
RETURNS TABLE(hotel_id integer)
LANGUAGE sql STABLE
AS $$
    SELECT h."idHotel"
    FROM hotel AS h
    WHERE EXISTS (SELECT 1 FROM room AS r WHERE r."idHotel" = h."idHotel")
      AND NOT EXISTS (
            SELECT 1
            FROM (SELECT DISTINCT r.roomtype FROM room AS r WHERE r."idHotel" = h."idHotel") AS t
            WHERE NOT EXISTS (
                    SELECT 1
                    FROM room AS r2
                    WHERE r2."idHotel" = h."idHotel"
                      AND r2.roomtype IS NOT DISTINCT FROM t.roomtype
                      AND NOT EXISTS (SELECT 1 FROM roombooking AS rb
                                      WHERE rb."roomID" = r2."idRoom"
                                        AND rb.checkin <= current_date AND rb.checkout > current_date)))
    ORDER BY h."idHotel";
$$;

-- ---------------------------------------------------------------------------------------
-- 4.2  Μέση ηλικία των προσώπων για τα οποία έγιναν κρατήσεις σε δωμάτια ενός τύπου.
--      Πριν: διαφορά ετών γέννησης (χωρίς να μετρά αν πέρασαν τα γενέθλια), μία φορά ανά
--      κράτηση δωματίου, άρα όποιος είχε πολλές κρατήσεις βάραινε περισσότερο.
--      Τώρα: πραγματική ηλικία σε συμπληρωμένα έτη, μία φορά ανά πρόσωπο.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "4_2_countAvgAge"(roomtype_input character varying)
RETURNS TABLE(average_age numeric)
LANGUAGE sql STABLE
AS $$
    SELECT round(avg(extract(year FROM age(current_date, pe.dateofbirth))), 2)
    FROM person AS pe
    WHERE pe."idPerson" IN (SELECT rb."bookedforpersonID"
                            FROM roombooking AS rb
                            JOIN room AS ro ON ro."idRoom" = rb."roomID"
                            WHERE ro.roomtype = roomtype_input);
$$;

-- ---------------------------------------------------------------------------------------
-- 4.3  Φθηνότερη τιμή δωματίου ανά τύπο στα ξενοδοχεία μιας χώρας, με την πόλη (ή τις
--      πόλεις) όπου βρίσκεται. Πριν επέστρεφε πόλη και τύπο, όχι την τιμή που ζητείται.
--      Αλλάζει ο τύπος επιστροφής (νέα στήλη min_rate), γι' αυτό προηγείται DROP.
-- ---------------------------------------------------------------------------------------
DROP FUNCTION IF EXISTS "4_3_search_cheap_rooms_by_country"(character varying);

CREATE FUNCTION "4_3_search_cheap_rooms_by_country"(country_input character varying)
RETURNS TABLE(city character varying, roomtype character varying, min_rate real)
LANGUAGE sql STABLE
AS $$
    SELECT DISTINCT p.city, p.roomtype, p.final_rate
    FROM (SELECT h.city, rr.roomtype,
                 (rr.rate - rr.rate * rr.discount / 100)::real AS final_rate,
                 min((rr.rate - rr.rate * rr.discount / 100)::real) OVER (PARTITION BY rr.roomtype) AS cheapest
          FROM hotel AS h
          JOIN roomrate AS rr ON rr."idHotel" = h."idHotel"
          WHERE h.country = country_input) AS p
    WHERE p.final_rate = p.cheapest
    ORDER BY p.roomtype, p.city;
$$;

-- ---------------------------------------------------------------------------------------
-- 4.4  Ξενοδοχεία με εισπράξεις μεγαλύτερες από τον μέσο όρο εισπράξεων της πόλης τους.
--      Πριν: το totalamount μιας κράτησης αθροιζόταν μία φορά για κάθε δωμάτιό της, άρα
--      κράτηση τριών δωματίων μετρούσε τριπλά. Τώρα μία φορά ανά κράτηση.
--      Όπως και πριν, ο μέσος όρος της πόλης υπολογίζεται στα ξενοδοχεία που έχουν εισπράξεις.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "4_4_search_hotels_with_max_income"()
RETURNS TABLE(hotel_name character varying, hotel_city character varying)
LANGUAGE sql STABLE
AS $$
    WITH booking_hotel AS (
        SELECT DISTINCT rb."hotelbookingID" AS booking_id, r."idHotel" AS hotel_id
        FROM roombooking AS rb
        JOIN room AS r ON r."idRoom" = rb."roomID"
    ), hotel_incomes AS (
        SELECT h."idHotel" AS hotel_id, h.name, h.city, sum(hb.totalamount) AS hotel_income
        FROM hotelbooking AS hb
        JOIN booking_hotel AS bh ON bh.booking_id = hb.idhotelbooking
        JOIN hotel AS h ON h."idHotel" = bh.hotel_id
        WHERE hb.payed IS TRUE AND hb.status = 'confirmed'
        GROUP BY h."idHotel", h.name, h.city
    )
    SELECT hi.name, hi.city
    FROM hotel_incomes AS hi
    WHERE hi.hotel_income > (SELECT avg(x.hotel_income) FROM hotel_incomes AS x WHERE x.city = hi.city)
    ORDER BY hi.name;
$$;

-- ---------------------------------------------------------------------------------------
-- 4.5  Πληρότητα ανά μήνα για ένα ξενοδοχείο και ένα έτος: ποσοστό των δεσμευμένων δωματίων
--      διά του πλήθους των δωματίων.
--      Πριν: μετρούσε τις αφίξεις του μήνα (τιμές έως 600%), παρέλειπε τους μήνες χωρίς άφιξη
--      και χρέωνε μια διαμονή που περνά σε επόμενο μήνα μόνο στον μήνα άφιξης.
--      Τώρα: για κάθε έναν από τους 12 μήνες, τα διαφορετικά δωμάτια που είχαν έστω μία
--      δεσμευμένη νύχτα μέσα στον μήνα, ως ποσοστό των δωματίων (0 έως 100).
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "4_5_find_hotel_fullness"(hotel_id integer, year_in integer)
RETURNS TABLE(id_hotel integer, month_value integer, month_fullness numeric)
LANGUAGE sql STABLE
AS $$
    SELECT hotel_id,
           m.month_no,
           round(100.0 * (SELECT count(DISTINCT r."idRoom")
                          FROM room AS r
                          JOIN roombooking AS rb ON rb."roomID" = r."idRoom"
                          WHERE r."idHotel" = hotel_id
                            AND rb.checkin < (m.month_start + interval '1 month')::date
                            AND rb.checkout > m.month_start)
                 / NULLIF((SELECT count(*) FROM room AS r WHERE r."idHotel" = hotel_id), 0), 2)
    FROM (SELECT g AS month_no, make_date(year_in, g, 1) AS month_start
          FROM generate_series(1, 12) AS g) AS m
    WHERE EXISTS (SELECT 1 FROM room AS r WHERE r."idHotel" = hotel_id)
    ORDER BY m.month_no;
$$;
