--
-- PostgreSQL database dump
--

\restrict Lle4oBBR7tO28oq5U3ox8cQZPsrXvItBcG2snlyIOjrmn30YKvReifOEcHBz4ih

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg13+2)
-- Dumped by pg_dump version 16.15 (Debian 16.15-1.pgdg13+2)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: activity_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.activity_type AS ENUM (
    'tennis',
    'golf',
    'swimming',
    'soccer'
);


--
-- Name: booking_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.booking_status AS ENUM (
    'confirmed',
    'canceled',
    'pending'
);


--
-- Name: card_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.card_type AS ENUM (
    'VISA',
    'MASTERCARD',
    'DINNERS CLUB',
    'AMERICAN EXPRESS'
);


--
-- Name: emp_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.emp_role AS ENUM (
    'reception',
    'manager',
    'staff'
);


--
-- Name: facility_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.facility_type AS ENUM (
    'hotel',
    'room'
);


--
-- Name: participant_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.participant_type AS ENUM (
    'responsible',
    'participant'
);


--
-- Name: payment_method; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_method AS ENUM (
    'card',
    'cash',
    'bank transfer'
);


--
-- Name: 1_1_check_employee_for_booking(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."1_1_check_employee_for_booking"(idemployee integer, idhotelbooking integer) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
     DECLARE
	 isfound boolean = false;
     BEGIN
       IF ((SELECT e.role FROM "employee" e WHERE e."idEmployee"=idemployee 
		   and e."hotelID"=(SELECT DISTINCT r."idHotel" FROM "room" r WHERE r."idRoom" 
			IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb."hotelbookingID"=idhotelbooking)))='manager')
		OR
	   	((SELECT e.role FROM "employee" e WHERE e."idEmployee"=idemployee
		  and e."hotelID"=(SELECT DISTINCT r."idHotel" FROM "room" r WHERE r."idRoom" 
			IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb."hotelbookingID"=idhotelbooking)))='reception') THEN
          isfound=true;
       END IF;
       RETURN isfound;
     END;
  $$;


--
-- Name: 1_1_check_person_for_participating(integer, integer, public.participant_type); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."1_1_check_person_for_participating"(idperson integer, id_hotel integer, rolep public.participant_type) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
     DECLARE
	 isfound boolean = true;
     BEGIN
	 IF rolep = 'participant' THEN
       IF idperson NOT IN (SELECT rb."bookedforpersonID" FROM "roombooking" rb WHERE rb."roomID" 
						   													IN (SELECT r."idRoom" FROM "room" r WHERE r."idHotel"=id_hotel)) THEN
          isfound=false;
       END IF;
	 ELSIF rolep = 'responsible' THEN
	 	IF idperson NOT IN (SELECT e."idEmployee" FROM "employee" e WHERE e."hotelID"=id_hotel) THEN
          isfound=false;
        END IF;
	 END IF;
       RETURN isfound;
     END;
  $$;


--
-- Name: 1_1_fill_manages(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."1_1_fill_manages"(n integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE 
bookingid integer;
employeeid integer;
alreadyexists boolean;
BEGIN

FOR i in 1..n LOOP
	bookingid = (SELECT * FROM "1_1_select_random_hotel_bookingID"(1) ):: integer;
	employeeid = (SELECT * FROM "1_1_select_random_employee_from_hotel_bookingID"(bookingID , 1)):: integer;
	IF (employeeid IN (SELECT ma.employeeid FROM "Manages" ma WHERE ma.idhotelbooking = bookingID)) THEN
		alreadyexists=true;
	ELSE
		alreadyexists=false;
	END IF;
	IF employeeid is not null AND alreadyexists=false then
		INSERT INTO "Manages" VALUES(employeeID,bookingID);
	end if;
	
END LOOP;
END;  
$$;


--
-- Name: 1_1_select_random_employee_from_hotel_bookingID(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."1_1_select_random_employee_from_hotel_bookingID"(hotelbookingid integer, n integer) RETURNS TABLE(employeeid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY

SELECT e."idEmployee"
FROM "employee" e
WHERE e."hotelID" = (SELECT DISTINCT r."idHotel" 
					  FROM "room" r 
					  WHERE r."idRoom" IN (SELECT rb."roomID"
										   FROM "roombooking" rb
										   WHERE rb."hotelbookingID"=hotelbookingID)
					 )
AND (e.role='manager' or e.role='reception')
ORDER BY random() LIMIT n;
 
END;  
$$;


--
-- Name: 1_1_select_random_hotel_bookingID(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."1_1_select_random_hotel_bookingID"(n integer) RETURNS TABLE(hotelbookingid integer)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY
SELECT hb."idhotelbooking"
FROM "hotelbooking" hb
ORDER BY random() LIMIT n;
 
END;  
$$;


--
-- Name: 2_1_update_clients_and_cards(character, character varying, character varying, character varying, character, date, character varying, character varying, character varying, character varying, character varying, date, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."2_1_update_clients_and_cards"(action_in character, documentclient_in character varying, fname_in character varying, lname_in character varying, sex_in character, date_of_birth_in date, address_in character varying, city_in character varying, country_in character varying, cardtype_in character varying, number_card_in character varying, expiration_card_in date, holder_in character varying) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
DECLARE 
success boolean=false;
number_of_persons integer;
id_client integer;
BEGIN

IF action_in='insert' THEN
	IF documentclient_in NOT IN (SELECT cl.documentclient FROM "client" cl) THEN
		number_of_persons = (SELECT max(p1."idPerson") FROM "person" p1);
		number_of_persons=number_of_persons+1;
		INSERT INTO "person" VALUES (number_of_persons,fname_in,lname_in,sex_in,date_of_birth_in,address_in,city_in,country_in);
		INSERT INTO "client" VALUES(number_of_persons,documentclient_in);
		
		IF cardtype_in is not null and number_card_in is not null THEN
			IF expiration_card_in>=current_date THEN
				IF expiration_card_in=current_date THEN
					RAISE NOTICE 'Card is expiring today.Person Id=%',number_of_persons;
				END IF;
				INSERT INTO "creditcard" VALUES (cardtype_in,number_card_in,expiration_card_in,holder_in,number_of_persons);
				success=true;
			ELSE
				RAISE NOTICE 'Card has expired. Need to insert new card. Person Id=%',number_of_persons;
			END IF;
		ELSE
			RAISE EXCEPTION 'Card type or card number cannot be null. Person Id=%',number_of_persons;
		END IF;
	ELSE 
		RAISE EXCEPTION 'The document client must be unique and there is other client with this document client.';
	END IF;

ELSIF action_in='delete' THEN
	id_client=(SELECT cl."idClient" FROM "client" cl WHERE cl.documentclient=documentclient_in);
	DELETE FROM "person" p1 WHERE p1."idPerson"=id_client;
	success=true;
--the others cascade 

ELSIF action_in='update' THEN
    id_client=(SELECT cl."idClient" FROM "client" cl WHERE cl.documentclient=documentclient_in);
	UPDATE "person" p2
	SET p2."fname"=fname_in,
		p2."lname"=lname_in,
		p2."sex"=sex_in,
		p2."dateofbirth"=date_of_birth_in,
		p2."address"=address_in,
		p2."city"=city_in,
		p2."country"=country_in
	WHERE p2."idPerson"=id_client;
	
	IF cardtype_in is not null and number_card_in is not null THEN
		IF expiration_card_in>=current_date THEN
			IF expiration_card_in=current_date THEN
				RAISE NOTICE 'Card is expiring today.Person Id=%',id_client;
			END IF;
			UPDATE "creditcard" cc
			SET cc.cardtype=cardtype_in,
				cc.number=number_card_in,
				cc.expiration=expiration_card_in,
				cc.holder=holder_in
			WHERE cc."clientID"=id_client;
			
			success=true;	
		ELSE
			RAISE EXCEPTION 'Card has expired. Need to insert new card. Person Id=%',client_id;
		END IF;
		
	END IF;
	
END IF;

return success;


END;
$$;


--
-- Name: 2_2_insertRandomBookings(integer, date, date, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."2_2_insertRandomBookings"(hotelid integer, start_date date, finish_date date, n integer) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
random_bookedbyclient integer;
random_bookedforperson integer;
random_number_of_rooms integer;
checkin_date date;
checkout_date date;
reservation_date date;
cancellation_date date;
hotel_bookingid integer;
country_of_random_bookedbyclient varchar(45);
random_room_available_from_hotelid integer;
room_rate real;

BEGIN
random_number_of_rooms= (SELECT floor(random() * (5-1+1) + 1))::int;

checkin_date  = (SELECT s1.checkin::date FROM
(SELECT * FROM generate_series(start_date, finish_date, '1 day') checkin ORDER BY random() LIMIT 1) as s1);
checkout_date = (SELECT s1.checkout::date FROM
(SELECT * FROM generate_series(start_date, finish_date, '1 day') checkout ORDER BY random() LIMIT 1) as s1);

IF checkout_date<checkin_date THEN
	WHILE (checkout_date<checkin_date) LOOP
		checkin_date  = (SELECT s1.checkin::date FROM
		(SELECT * FROM generate_series(start_date, finish_date, '1 day') checkin ORDER BY random() LIMIT 1) as s1);
		checkout_date = (SELECT s1.checkout::date FROM
		(SELECT * FROM generate_series(start_date, finish_date, '1 day') checkout ORDER BY random() LIMIT 1) as s1);
	END LOOP;

END IF;

reservation_date = checkin_date - integer '20';
cancellation_date = checkin_date - integer '10';

FOR i in 1..n LOOP
	random_bookedbyclient = (SELECT cl."idClient" FROM "client" cl ORDER BY random() LIMIT 1);
	hotel_bookingid = nextval('idhbooking'::regclass);
	INSERT INTO "hotelbooking" VALUES(hotel_bookingid,reservation_date,cancellation_date, null,random_bookedbyclient,false,null,'confirmed');
	
	country_of_random_bookedbyclient = (SELECT pe.country FROM "person" WHERE pe."idPerson" = random_bookedbyclient);
	
	FOR j in 1..random_number_of_rooms LOOP
		random_bookedforperson = (SELECT cl."idClient" FROM "client" cl inner join "person" pe on(cl."idClient"=pe."idPerson") WHERE pe.country=country_of_random_bookedbyclient ORDER BY random() LIMIT 1);
		random_room_available_from_hotelid = (SELECT r."idRoom" FROM "room" r WHERE r."idHotel" = hotelID 
											  and r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=checkin_date and rb.checkout>=checkin_date)
											  and r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin>=checkin_date and rb.checkout<=checkout_date) 
											  ORDER BY random() LIMIT 1);
	
		IF(random_room_available_from_hotelid is null) THEN
			Raise Exception 'No available room. Cannot add other room.';
		ELSE
			room_rate = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
			 WHERE rr."idHotel"= (SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=random_room_available_from_hotelid
			 AND rr.roomtype = (SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=random_room_available_from_hotelid))) :: real;
			 
			 INSERT INTO "roombooking" VALUES(hotel_bookingid,random_room_available_from_hotelid,random_bookedforperson, checkin_date, checkout_date,room_rate);
		END IF;
	END LOOP;
	
END LOOP;



END;
$$;


--
-- Name: 3_1_cities_countries_with_disc_over_30(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_1_cities_countries_with_disc_over_30"() RETURNS TABLE(country character varying, city character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN 

RETURN QUERY

SELECT h.country,h.city
FROM "hotel" as h
WHERE EXISTS 
(SELECT h1."idHotel", discount FROM "hotel" as h1 natural join "roomrate" as rr 
 WHERE rr.discount >30 and h."idHotel" = h1."idHotel");

END;
$$;


--
-- Name: 3_2_search_specific_hotels(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_2_search_specific_hotels"(num_of_stars character varying, prefix_name character varying) RETURNS TABLE(id_hotel integer, name_hotel character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY
SELECT h."idHotel", h."name"
FROM "hotel" h natural join 
(SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"='Restaurant'
INTERSECT 
SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"='Breakfast') hf1
				natural join "roomrate" rr
WHERE rr."roomtype"='Studio' and rr."rate"-(rr.discount/100*rr."rate") < 80
and left(h."name",length(prefix_name))=prefix_name and h."stars" like (num_of_stars);


END;
$$;


--
-- Name: 3_3_displayMaxDiscountRoomsPerHotel(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_3_displayMaxDiscountRoomsPerHotel"() RETURNS TABLE(name character varying, roomtype character varying, discount real)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY

select t2.hotelName, t2.roomtype, t2.maxDiscount
from(
	select t1.hotelID, t1.hotelName , rr.roomtype, rr.discount, t1.maxDiscount
	from(
		select hotel."idHotel" as hotelID, hotel.name as hotelName, max(rr.discount) as maxDiscount 
		from "hotel" 
		left join "roomrate" rr on (hotel."idHotel" = rr."idHotel")
		group by hotel."idHotel"
		order by hotel.name) t1
	left join "roomrate" rr on (t1.hotelID = rr."idHotel")
	left join "roomtype" rt on (rr."roomtype" = rt."typename")
	where rr.discount = t1.maxDiscount ) t2
order by t2.roomtype
;
END;
$$;


--
-- Name: 3_4_displayBookingStatus(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_4_displayBookingStatus"(hotelid integer) RETURNS TABLE(idhotelbooking integer, clientfname character varying, clientlname character varying, reservationdate date, bookedby character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN QUERY


SELECT t1.idhotelbooking, t1.fname as clientFname, t1.lname as clientLname, t1.reservationdate,
																									CASE WHEN(t1."employeeid" IS NULL) THEN 'Client'::varchar
																									WHEN (t1."employeeid" IS NOT NULL ) THEN 'Employee'::varchar
																									END as bookedBy
FROM (
	SELECT DISTINCT s1."idHotel", hb.idhotelbooking, hb.reservationdate, pe.fname, pe.lname, cl."idClient", ma.employeeid
	FROM (SELECT r."idHotel", r."idRoom" FROM room r WHERE r."idHotel"=hotelID) as s1
	INNER JOIN "roombooking" rb ON (rb."roomID" = s1."idRoom")
	INNER JOIN "hotelbooking" hb ON (rb."hotelbookingID" = hb."idhotelbooking")
	INNER JOIN "person" pe ON (pe."idPerson" = rb."bookedforpersonID")
	LEFT OUTER JOIN "client" cl ON (cl."idClient"=hb."bookedbyclientID")
	LEFT OUTER JOIN "Manages" ma ON(ma."idhotelbooking"=hb."idhotelbooking")
	) t1
;

END;
$$;


--
-- Name: 3_5_restoreActivities(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_5_restoreActivities"(hotelid integer) RETURNS TABLE(idhotel integer, weekday integer, starttime time without time zone, endtime time without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY

SELECT ac."idhotel", ac.weekday, ac.starttime, ac.endtime
FROM (SELECT * FROM "Activity" ac1 WHERE ac1."idhotel"=hotelID) ac
WHERE (ac."idhotel", ac.weekday, ac.starttime, ac.endtime) 
 NOT IN (SELECT pa."idhotel", pa.weekday, pa.starttime, pa.endtime FROM "Participates" pa WHERE pa."idhotel"= ac."idhotel") 

;
END;
$$;


--
-- Name: 3_6_findSubtypesOfAFacility(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_6_findSubtypesOfAFacility"(facilitiesof character varying) RETURNS TABLE(facility character varying, facilityof character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY
WITH RECURSIVE facilities_tree(child,parent) AS
(
SELECT "nameFacility" as child, "subtypeOf" as parent
FROM  "facility" 
WHERE "subtypeOf"=facilitiesOf
UNION
SELECT f."nameFacility" as child ,f."subtypeOf" as parent
FROM  facilities_tree r, "facility" f
WHERE r.child=f."subtypeOf"
)
SELECT * FROM facilities_tree;
END;
$$;


--
-- Name: 3_7_search_hotels_with_specific_facilities(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_7_search_hotels_with_specific_facilities"(hotel_facility character varying, room_facility character varying) RETURNS TABLE(id_hotel integer, id_room integer)
    LANGUAGE plpgsql
    AS $$

BEGIN

IF ((SELECT f."nameFacility" FROM "facility" f WHERE f.type='hotel' and f."nameFacility"=hotel_facility and f."nameFacility" IN(SELECT f."subtypeOf" FROM "facility" f WHERE f.type='hotel')) is null) THEN
	IF ((SELECT f."nameFacility" FROM "facility" f WHERE f.type='room' and f."nameFacility"=room_facility and f."nameFacility" IN(SELECT f."subtypeOf" FROM "facility" f WHERE f.type='room')) is null) THEN
		RETURN QUERY
		SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility"=room_facility);
	ELSE
		RETURN QUERY
		SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility" 
															 IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=room_facility and f.type='room'))
		UNION
		SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility" = room_facility);
															
	END IF;


ELSE 
																		   
	IF ((SELECT f."nameFacility" FROM "facility" f WHERE f.type='room' and f."nameFacility"=room_facility and f."nameFacility" IN(SELECT f."subtypeOf" FROM "facility" f WHERE f.type='room')) is null) THEN
	RETURN QUERY
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility" IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=hotel_facility and f.type='hotel'))
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility"=room_facility)
	UNION 
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility"=room_facility);
	ELSE  
	RETURN QUERY																   
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility" IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=hotel_facility and f.type='hotel'))
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility" 
															 				IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=room_facility and f.type='room'))
	UNION
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility" IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=hotel_facility and f.type='hotel'))
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility"=room_facility)
	
	UNION
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility" 
															 IN (SELECT f."nameFacility" FROM "facility" f WHERE f."subtypeOf"=room_facility and f.type='room'))
	
	UNION 
	SELECT r."idHotel", r."idRoom" FROM "room" r WHERE r."idHotel" IN (SELECT hf."idHotel" FROM "hotelfacilities" hf WHERE hf."nameFacility"=hotel_facility)
													AND r."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=current_date and rb.checkout>current_date)
													AND r."idRoom" IN (SELECT rf."idRoom" FROM "roomfacilities" rf WHERE rf."nameFacility"=room_facility)
	;
	END IF;
END IF;
END;
$$;


--
-- Name: 3_8_search_hotels_having_room_from_each_category(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."3_8_search_hotels_having_room_from_each_category"() RETURNS TABLE(hotel_id integer)
    LANGUAGE plpgsql
    AS $$

BEGIN

RETURN QUERY

SELECT r1."idHotel"
FROM "room" r1
WHERE r1."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=CURRENT_DATE and rb.checkout>CURRENT_DATE)
AND NOT EXISTS (SELECT DISTINCT r."roomtype"
				FROM "room" r
				WHERE NOT EXISTS (SELECT r2."idRoom"
								  FROM "room" r2 
								  WHERE r."roomtype"=r2."roomtype" AND r1."idHotel"=r2."idHotel"
								)
				)
GROUP BY r1."idHotel"

;
END;
$$;


--
-- Name: 4_1_find_clients_activities(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."4_1_find_clients_activities"() RETURNS TABLE(id_client integer, id_hotel integer, num_of_activities bigint)
    LANGUAGE plpgsql
    AS $$

BEGIN
RETURN QUERY
SELECT  cl."idClient", h."idHotel", count(s1.amka_person)
FROM "client" cl left outer join (SELECT pa.amka_person, pa.idhotel  FROM "Participates" pa) s1 
									on(s1.amka_person=cl."idClient")
 				 left outer join  "hotel" h on(h."idHotel"=s1.idhotel)
				 inner join (SELECT rb."bookedforpersonID",rb.checkout FROM "roombooking" rb) s2 
				 			on(s2."bookedforpersonID"=cl."idClient")
WHERE s2.checkout <= current_date
GROUP BY cl."idClient", h."idHotel"
ORDER BY cl."idClient";


END;
$$;


--
-- Name: 4_2_countAvgAge(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."4_2_countAvgAge"(roomtype_input character varying) RETURNS TABLE(average_age numeric)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY

SELECT ROUND(AVG(t1.age),2) as average_age
FROM (
	SELECT TO_CHAR(NOW()::DATE, 'YYYY')::integer - TO_CHAR("pe".dateofbirth::DATE, 'YYYY')::integer as age
	FROM (SELECT ro."idRoom", ro."roomtype" FROM "room" ro WHERE ro.roomtype=roomtype_input) s1
	INNER JOIN "roombooking" rb ON (rb."roomID" = s1."idRoom")
	INNER JOIN "person" pe ON (pe."idPerson" = rb."bookedforpersonID") ) AS t1

;

END;
$$;


--
-- Name: 4_3_search_cheap_rooms_by_country(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."4_3_search_cheap_rooms_by_country"(country_input character varying) RETURNS TABLE(city character varying, roomtype character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN

RETURN QUERY
SELECT h."city",rr."roomtype"
FROM "hotel" h natural join "roomrate" rr
WHERE rr.rate - (rr.discount/100 *rr.rate) = (SELECT min(rr1.rate - (rr1.discount/100 *rr1.rate))
											  FROM "hotel" h1 natural join "roomrate" rr1
											  WHERE rr.roomtype=rr1.roomtype and h1."country"=country_input
											  GROUP BY h1."country",rr1.roomtype)
		and h."country"=country_input

;

END;
$$;


--
-- Name: 4_4_search_hotels_with_max_income(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."4_4_search_hotels_with_max_income"() RETURNS TABLE(hotel_name character varying, hotel_city character varying)
    LANGUAGE plpgsql
    AS $$

BEGIN

RETURN QUERY

WITH hotel_incomes AS
(
SELECT h2."idHotel", sum(hb.totalamount) as hotel_income, h2.city
FROM "hotelbooking" hb inner join "roombooking" rb on(rb."hotelbookingID"=hb."idhotelbooking") inner join "room" r on (r."idRoom"=rb."roomID") natural join "hotel" h2 
WHERE hb.payed is true and hb.status='confirmed'
GROUP BY h2."idHotel"
)

SELECT h3.name,h3.city
FROM "hotel" h3 natural join "hotel_incomes" hi inner join
										(SELECT h1.city, avg(hi1.hotel_income) as average_city_hotel_incomes
										 FROM "hotel" h1 inner join "hotel_incomes" hi1 on (hi1.city=h1.city)
										 GROUP BY h1.city) s2 on (s2.city=h3.city)
WHERE hi.hotel_income>s2.average_city_hotel_incomes
;

END;
$$;


--
-- Name: 4_5_find_hotel_fullness(integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."4_5_find_hotel_fullness"(hotel_id integer, year_in integer) RETURNS TABLE(id_hotel integer, month_value integer, month_fullness numeric)
    LANGUAGE plpgsql
    AS $$

BEGIN

for i in 1..12 LOOP
	RETURN QUERY
	
	WITH trial AS(
	SELECT s1."idHotel", s1.year_checkin, s1.month_checkin, sum(booked_rooms) as num_booked_rooms
	FROM
	(SELECT r."idHotel",EXTRACT (year FROM rb.checkin) ::INTEGER as year_checkin,EXTRACT (year FROM rb.checkout) ::INTEGER as year_checkout,EXTRACT (month FROM rb.checkin) ::INTEGER as month_checkin,EXTRACT (month FROM rb.checkout) ::INTEGER as month_checkout, count(*) as booked_rooms
	FROM "room" r inner join "roombooking" rb on(r."idRoom"=rb."roomID")
	WHERE (EXTRACT (year FROM rb.checkin) ::INTEGER = year_in or EXTRACT (year FROM rb.checkout) ::INTEGER=year_in)
	AND r."idHotel"=hotel_id 
	AND (EXTRACT (month FROM rb.checkin) ::INTEGER = i OR EXTRACT (month FROM rb.checkout) ::INTEGER = i)
	GROUP BY r."idHotel",year_checkin,year_checkout,month_checkin,month_checkout) s1
	GROUP BY s1."idHotel", s1.year_checkin, s1.month_checkin
		)

	
	SELECT s3."idHotel",s3.month_checkin, (cast(s3.num_booked_rooms as decimal)/cast(s2.total_rooms as decimal))*100 as fulln
	FROM
	(
	SELECT r."idHotel", count(*) as total_rooms
	FROM "room" r 
	WHERE r."idHotel"=hotel_id
	GROUP BY r."idHotel"
	) s2 natural join
	(
		SELECT t1."idHotel", t1.month_checkin, t1.num_booked_rooms
		FROM "trial" t1
		WHERE t1.month_checkin=i and t1.year_checkin=year_in
	) s3

	;

END LOOP;
	
		

END;
$$;


--
-- Name: 5_1_transaction_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_1_transaction_update"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
IF(TG_OP = 'INSERT') THEN
	IF (NEW.status='confirmed') THEN
		IF((NEW.payed) and NEW.totalamount is not null) THEN
			INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'insert',NEW.totalamount, CURRENT_DATE);
		ELSIF (NEW.payed=false) THEN
			Raise Notice 'The booking is not checked to be payed.';
		ELSIF ((NEW.payed) and NEW.totalamount is null) THEN
			Raise Exception 'The amount is null.';
		END IF;
	END IF;
	RETURN NEW;
ELSIF (TG_OP = 'UPDATE') THEN
	IF (NEW.status='confirmed') THEN
		IF(OLD.payed=false and NEW.payed=true) THEN
			IF (NEW.totalamount is not null) THEN
				INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'update',NEW.totalamount, CURRENT_DATE);
			ELSIF (NEW.totalamount is null) THEN
				Raise Exception 'The amount is null.';
			END IF;
		ELSIF (OLD.payed=true and NEW.payed=true) THEN
			IF (NEW.totalamount is not null) THEN
				IF (OLD.totalamount is not null) THEN
					IF((NEW.totalamount - OLD.totalamount)!=(0::numeric)) THEN
						INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'update',NEW.totalamount - OLD.totalamount, CURRENT_DATE);	
					ELSE
						Raise Notice 'The old total amount is equal with the old.';
					END IF;
				ELSE 
					INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'update',NEW.totalamount, CURRENT_DATE);
					Raise Notice 'The old total amount was null so it has to be payed now.';
				END IF;
			ELSE
				Raise Exception 'The new amount is null.';
			END IF;
		ELSIF (OLD.payed=true and NEW.payed=false) THEN		
			Raise Notice 'The updated booking is not checked to be payed.';
		ELSIF (OLD.payed=false and NEW.payed=false) THEN	
			Raise Notice 'Neither the first nor the updated booking are not checked to be payed.';
		END IF;
	END IF;
	RETURN NEW;
ELSIF (TG_OP = 'DELETE') THEN
	IF(OLD.payed=true AND OLD.totalamount is not null) THEN
		INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'delete', - OLD.totalamount, CURRENT_DATE);
	ELSIF (OLD.payed=false) THEN
		Raise Notice 'The booking was not checked to be payed.';
	ELSIF (OLD.payed=true AND OLD.totalamount is null) THEN
		Raise Notice 'The booking was not payed because the old amount was null.';
	END IF;
	RETURN OLD;
END IF;


END;
$$;


--
-- Name: 5_2_5_3_after_roombooking_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_after_roombooking_delete"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
total_amount real;
BEGIN
	total_amount = (SELECT s1.new_total_amount 
			    FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
				  	  FROM "roombooking" rb 
				  	  WHERE rb."hotelbookingID" = OLD."hotelbookingID"
				 	  GROUP BY rb."hotelbookingID") as s1); 
			
	UPDATE "hotelbooking" SET totalamount = total_amount
	WHERE "idhotelbooking" = OLD."hotelbookingID";
RETURN OLD;
END;
	
$$;


--
-- Name: 5_2_5_3_after_roombooking_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_after_roombooking_insert"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

room_rate real;

BEGIN
room_rate = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
			 WHERE rr."idHotel"= (SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=NEW."roomID"
			 AND rr.roomtype = (SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=NEW."roomID"))) :: real;
			 
UPDATE "roombooking" SET rate=room_rate 
WHERE "roomID"=NEW."roomID" and "hotelbookingID"=NEW."hotelbookingID";

	
RETURN NEW;
END;
$$;


--
-- Name: 5_2_5_3_after_roombooking_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_after_roombooking_update"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
total_amount real;
BEGIN
	total_amount = (SELECT s1.new_total_amount 
			    FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
				  	  FROM "roombooking" rb 
				  	  WHERE rb."hotelbookingID" = NEW."hotelbookingID"
				 	  GROUP BY rb."hotelbookingID") as s1); 
			
	UPDATE "hotelbooking" SET totalamount = total_amount
	WHERE "idhotelbooking" = NEW."hotelbookingID";
RETURN NEW;
END;
	
$$;


--
-- Name: 5_2_5_3_before_roombooking_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_before_roombooking_delete"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
canc_date_hb date;

BEGIN
canc_date_hb = (SELECT hb.cancellationdate FROM "hotelbooking" hb WHERE hb.idhotelbooking=OLD."hotelbookingID"):: date;

	IF(current_date > canc_date_hb) THEN
		RAISE EXCEPTION 'Unable to execute operation! Cancelation date has expired.';
	END IF;

RETURN OLD;
END;
$$;


--
-- Name: 5_2_5_3_before_roombooking_insert(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_before_roombooking_insert"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE

availability_room boolean;
available_until date;
available_after date;

BEGIN

IF(NEW."hotelbookingID" NOT IN (select hb.idhotelbooking from "hotelbooking" hb)) THEN
	RAISE EXCEPTION 'Hotel booking does not exist!';				
---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
ELSE 
	IF((SELECT rb."hotelbookingID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb."hotelbookingID"=NEW."hotelbookingID") is not null) THEN
		RAISE EXCEPTION 'This room booking already exists.';
	END IF;
	
	IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin) is null) AND
		((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout) is null)) THEN

		availability_room=true;

		available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
							WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout);
		available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
							WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin);
							
		IF available_after is null THEN ---its not in the roombooking before the checkin
			available_after = NEW.checkin - integer '1';
		ELSE
			available_after = available_after + integer '1';
		END IF;

		IF available_until is null THEN ---its not in the roombooking after the checkout
			available_until = NEW.checkout + integer '1';
		ELSE 
			available_until = available_until - integer '1';	
		END IF;
	ELSE
		 availability_room=false;
	END IF;
			
	IF (availability_room=false) THEN
		RAISE EXCEPTION 'The room is not available.';		
	END IF;			
END IF; ---for hotelbookingID in/out "hotelbooking"
RETURN NEW;
END;
$$;


--
-- Name: 5_2_5_3_before_roombooking_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_5_3_before_roombooking_update"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
canc_date_hb date;
availability_room boolean;
available_until date;
available_after date;
rate_room real;
days_before integer;
days_after integer;

BEGIN
canc_date_hb = (SELECT hb.cancellationdate FROM "hotelbooking" hb WHERE hb.idhotelbooking=OLD."hotelbookingID"):: date;
rate_room = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
				 WHERE rr."idHotel"= (SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=OLD."roomID"
				 AND rr.roomtype = (SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=OLD."roomID")));

IF NEW.checkin <= current_date OR NEW.checkout <= current_date THEN
	Raise Exception 'You cannot do this! The day of the checkin or/both checkout has passed.';
END IF;

IF (canc_date_hb < current_date) THEN
	IF (NEW.checkin < OLD.checkin) THEN
		IF (NEW.checkout < OLD.checkout) THEN
			Raise Notice 'checkin<old checkout<old';
			days_before = OLD.checkout - OLD.checkin;
			days_after = NEW.checkout - NEW.checkin;
			IF (days_after >= days_before) THEN
			
				IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
					IF available_after is null THEN ---its not in the roombooking before the checkin
						available_after = NEW.checkin - integer '1';
					ELSE
						available_after = available_after + integer '1';
					END IF;
					
					IF available_until is null THEN ---its not in the roombooking after the checkout
						available_until = NEW.checkout + integer '1';
					ELSE 
						available_until = available_until - integer '1';	
					END IF;
					
					Raise Notice 'Room available until %',available_until;
					Raise Notice 'Room available after %',available_after;
				ELSE
					availability_room=false;
				END IF;

				IF (availability_room = false) THEN
					Raise Exception 'Your room is not available after your checkout or before your checkin.';
				END IF;
			ELSE
				Raise Exception 'The cancelation date has passed. You cannot decrease the days.';
				
			END IF;
		--------------------------------------------------------------------------------------------
		ELSIF (NEW.checkout > OLD.checkout) THEN
			Raise Notice 'checkin<old checkout>old';
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
					IF available_after is null THEN ---its not in the roombooking before the checkin
						available_after = NEW.checkin - integer '1';
					ELSE
						available_after = available_after + integer '1';
					END IF;
					
					IF available_until is null THEN ---its not in the roombooking after the checkout
						available_until = NEW.checkout + integer '1';
					ELSE 
						available_until = available_until - integer '1';	
					END IF;
					
					Raise Notice 'Room available until %',available_until;
					Raise Notice 'Room available after %',available_after;
				ELSE
					availability_room=false;
				END IF;

				IF (availability_room=false) THEN
					Raise Exception 'Your room is not available after your checkout or before your checkin.';
				END IF;
		--------------------------------------------------------------------------------------------
		ELSE
			Raise Notice 'checkin<old checkout=old';
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
	   			
				availability_room=true;
				
				available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									 WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
				IF available_after is null THEN ---its not in the roombooking before the checkin
					available_after = NEW.checkin - integer '1';
				ELSE
					available_after = available_after + integer '1';
				END IF;
				
				Raise Notice 'Room available after %',available_after;
	  		ELSE
	   			availability_room=false;
	    	END IF;
			
			IF (availability_room = false) THEN
				Raise Exception 'Your room is not available before your checkin.';
			END IF;
		END IF; --end if for checkout when new.checkin<old 
	--------------------------------------------------------------------------------------------------------------
	ELSIF (NEW.checkin > OLD.checkin) THEN
		IF (NEW.checkout < OLD.checkout) THEN
			Raise Notice 'checkin>old checkout<old';
			Raise Exception 'The cancellation date has passed you cannot decrease the number of days.';
		--------------------------------------------------------------------------------------------
		ELSIF (NEW.checkout > OLD.checkout) THEN
			Raise Notice 'checkin>old checkout>old';
			days_before = OLD.checkout - OLD.checkin;
			days_after = NEW.checkout - NEW.checkin;
			IF (days_after >= days_before) THEN
				IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
					IF available_after is null THEN ---its not in the roombooking before the checkin
						available_after = NEW.checkin - integer '1';
					ELSE
						available_after = available_after + integer '1';
					END IF;
					
					IF available_until is null THEN ---its not in the roombooking after the checkout
						available_until = NEW.checkout + integer '1';
					ELSE 
						available_until = available_until - integer '1';	
					END IF;
					
					Raise Notice 'Room available until %',available_until;
					Raise Notice 'Room available after %',available_after;
				ELSE
					availability_room=false;
				END IF;


				IF (availability_room = false) THEN
					Raise Exception 'Your room is not available after your checkout or before your checkin.';
				END IF;
			ELSE
				Raise Exception 'The cancellation date has passed you cannot decrease the number of days.';
			END IF;
		--------------------------------------------------------------------------------------------
		ELSE
			Raise Notice 'checkin>old checkout=old';
			Raise Exception 'The cancellation date has passed you cannot decrease the number of the days.';
		END IF; --end if for checkout when new.checkin>old 
----------------------------------------------------------------------------------------------------------------------
	ELSE
		IF (NEW.checkout < OLD.checkout) THEN
			Raise Notice 'checkin=old checkout<old';
			Raise Exception 'The cancellation date has passed you cannot decrease the number of the days.';
		--------------------------------------------------------------------------------------------
		ELSIF (NEW.checkout > OLD.checkout) THEN
			Raise Notice 'checkin=old checkout>old';
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
				availability_room=true;
				
				available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
								   
				IF available_until is null THEN ---its not in the roombooking after the checkout
					available_until = NEW.checkout + integer '1';
				ELSE 
					available_until = available_until - integer '1';	
				END IF;
				
				Raise Notice 'Room available until %',available_until;
			ELSE
				availability_room=false;
			END IF;

			IF (availability_room = false) THEN
				Raise Exception 'Your room is not available after your checkout.';
			END IF;
		--------------------------------------------------------------------------------------------
		ELSE
			Raise Notice 'checkin=old checkout=old';
			
		END IF; --end if for checkout when new.checkin=old 
	
	END IF;   ---end if for cheking checkin value
-------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------
ELSE --canc_date_hb >= current_date			 
	IF (NEW.checkin != OLD.checkin) THEN
		IF (NEW.checkout != OLD.checkout) THEN -- if both dates have changed
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
					IF available_after is null THEN ---its not in the roombooking before the checkin
						available_after = NEW.checkin - integer '1';
					ELSE
						available_after = available_after + integer '1';
					END IF;
					
					IF available_until is null THEN ---its not in the roombooking after the checkout
						available_until = NEW.checkout + integer '1';
					ELSE 
						available_until = available_until - integer '1';	
					END IF;
					
					Raise Notice 'Room available until %',available_until;
					Raise Notice 'Room available after %',available_after;
				ELSE
					availability_room=false;
				END IF;

			
			IF (availability_room=false) THEN
				Raise Exception 'Your room is not available after your checkout or before your checkin.';
			END IF;
		-------------------------------------------------------------------------------------------------	
		ELSE  ---if checkin has changed but not the checkout
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
	   			availability_room=true;
				
				available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
				IF available_after is null THEN ---its not in the roombooking before the checkin
					available_after = NEW.checkin - integer '1';
				ELSE
					available_after = available_after + integer '1';
				END IF;
					
				Raise Notice 'Room available after %',available_after;
	  		ELSE
	   			availability_room=false;
	    	END IF;
			
			IF (availability_room = false) THEN
				Raise Exception 'Your room is not available before your checkin.';
			END IF;
		END IF; --- if of equallity in checkout date case checkin date has changed
 	----------------------------------------------------------------------------------------------------------------------------------	
	ELSE ---if checkin hasnt changed
		IF (NEW.checkout != OLD.checkout) THEN  ---if checkin hasnt changed but checkout changed
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				availability_room=true;
				
				available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
								   
				IF available_until is null THEN ---its not in the roombooking after the checkout
					available_until = NEW.checkout + integer '1';
				ELSE 
					available_until = available_until - integer '1';	
				END IF;
					
				Raise Notice 'Room available until %',available_until;
			ELSE
				availability_room=false;
			END IF;

			IF (availability_room= false) THEN
				Raise Exception 'Your room is not available after your checkout.';
			END IF;
		END IF;  --- if of equallity in checkout date case checkin date hasnt changed
		
	END IF;  ----if of equallity on checkin date
END IF;  ---if cancellation date

RETURN NEW;
END;
$$;


--
-- Name: 5_2_hotelbooking_delete(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_hotelbooking_delete"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	IF(OLD.cancellationdate < current_date) THEN
		RAISE EXCEPTION 'Cannot delete the reservation.';
	END IF;
RETURN OLD;
	
END;
$$;


--
-- Name: 5_2_hotelbooking_update(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public."5_2_hotelbooking_update"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
manager_hb integer;

BEGIN
	IF(NEW.cancellationdate!=OLD.cancellationdate) THEN
		manager_hb=(SELECT employeeid FROM "Manages" WHERE idhotelbooking=OLD."idhotelbooking" 
					AND employeeid IN (SELECT e."idEmployee" FROM "employee" e WHERE e.role='manager')) :: integer;
		
		IF(manager_hb is null) THEN
			RAISE EXCEPTION 'Cannot update the cancellation date. Only the manager can.';
		END IF;
	
	END IF;
RETURN NEW;
	
END;
$$;


--
-- Name: idhotel; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idhotel
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: hotel; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hotel (
    "idHotel" integer DEFAULT nextval('public.idhotel'::regclass) NOT NULL,
    name character varying(45),
    stars character varying(10),
    address character varying(75),
    city character varying(45),
    country character varying(45),
    phone character varying(25),
    fax character varying(25)
);


--
-- Name: idroom; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idroom
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: room; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.room (
    "idRoom" integer DEFAULT nextval('public.idroom'::regclass) NOT NULL,
    number integer,
    area real,
    "idHotel" integer NOT NULL,
    roomtype character varying(45)
);


--
-- Name: roombooking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roombooking (
    "hotelbookingID" integer NOT NULL,
    "roomID" integer NOT NULL,
    "bookedforpersonID" integer,
    checkin date,
    checkout date,
    rate real
);


--
-- Name: 6_1_availableRoomsByHotel; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public."6_1_availableRoomsByHotel" AS
 SELECT r."idRoom",
    r.roomtype,
        CASE
            WHEN (s1.checkin IS NULL) THEN (CURRENT_DATE - 1)
            WHEN (s1.checkin IS NOT NULL) THEN (s1.checkin - 1)
            ELSE NULL::date
        END AS available_until
   FROM ((( SELECT h1."idHotel"
           FROM public.hotel h1
          WHERE ((h1.name)::text = 'Ramblewood Inn'::text)) h
     JOIN public.room r ON ((r."idHotel" = h."idHotel")))
     JOIN ( SELECT rb."roomID",
            min(rb.checkin) AS checkin
           FROM public.roombooking rb
          WHERE (rb.checkin > CURRENT_DATE)
          GROUP BY rb."roomID") s1 ON ((s1."roomID" = r."idRoom")));


--
-- Name: Activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Activity" (
    idhotel integer NOT NULL,
    starttime time without time zone NOT NULL,
    endtime time without time zone NOT NULL,
    weekday integer NOT NULL,
    activitytype public.activity_type,
    amka_employee_reserved integer,
    CONSTRAINT check_weekdaye CHECK (((weekday >= 0) AND (weekday <= 6))),
    CONSTRAINT violated_time CHECK ((starttime < endtime))
);


--
-- Name: Manages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Manages" (
    employeeid integer NOT NULL,
    idhotelbooking integer NOT NULL
);


--
-- Name: Participates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Participates" (
    amka_person integer NOT NULL,
    idhotel integer NOT NULL,
    weekday integer NOT NULL,
    starttime time without time zone NOT NULL,
    endtime time without time zone NOT NULL,
    participant_role public.participant_type
);


--
-- Name: idtransaction; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idtransaction
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: Transaction; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public."Transaction" (
    idtransaction integer DEFAULT nextval('public.idtransaction'::regclass) NOT NULL,
    idhotelbooking integer NOT NULL,
    action_tr character(6) NOT NULL,
    amount numeric NOT NULL,
    made_date date,
    CONSTRAINT check_amount CHECK ((((action_tr = 'insert'::bpchar) AND (amount > (0)::numeric)) OR (action_tr = 'update'::bpchar) OR ((action_tr = 'delete'::bpchar) AND (amount < (0)::numeric))))
);


--
-- Name: client; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.client (
    "idClient" integer NOT NULL,
    documentclient character varying(45)
);


--
-- Name: creditcard; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.creditcard (
    cardtype character varying(30) NOT NULL,
    number character varying(45) NOT NULL,
    expiration date,
    holder character varying(45),
    "clientID" integer NOT NULL
);


--
-- Name: employee; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee (
    "idEmployee" integer NOT NULL,
    idmanager integer,
    "hotelID" integer,
    role public.emp_role
);


--
-- Name: facility; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.facility (
    "nameFacility" character varying(45) NOT NULL,
    "subtypeOf" character varying(45),
    description character varying(100),
    type public.facility_type NOT NULL
);


--
-- Name: idhbooking; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idhbooking
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hotelbooking; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hotelbooking (
    idhotelbooking integer DEFAULT nextval('public.idhbooking'::regclass) NOT NULL,
    reservationdate date,
    cancellationdate date,
    totalamount real,
    "bookedbyclientID" integer,
    payed boolean NOT NULL,
    paymethod public.payment_method,
    status public.booking_status
);


--
-- Name: hotelfacilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hotelfacilities (
    "idHotel" integer NOT NULL,
    "nameFacility" character varying(45) NOT NULL
);


--
-- Name: idperson; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.idperson
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: person; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.person (
    "idPerson" integer DEFAULT nextval('public.idperson'::regclass) NOT NULL,
    fname character varying(45),
    lname character varying(45),
    sex character(1),
    dateofbirth date,
    address character varying(75),
    city character varying(45),
    country character varying(45)
);


--
-- Name: roomfacilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roomfacilities (
    "idRoom" integer NOT NULL,
    "nameFacility" character varying(45) NOT NULL
);


--
-- Name: roomrate; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roomrate (
    "idHotel" integer NOT NULL,
    roomtype character varying(45) NOT NULL,
    rate real,
    discount real
);


--
-- Name: roomtype; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roomtype (
    typename character varying(45) NOT NULL,
    samplephoto bytea
);


--
-- Name: Activity Activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Activity"
    ADD CONSTRAINT "Activity_pkey" PRIMARY KEY (idhotel, weekday, starttime, endtime);


--
-- Name: Manages Manages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Manages"
    ADD CONSTRAINT "Manages_pkey" PRIMARY KEY (employeeid, idhotelbooking);


--
-- Name: Participates Participates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Participates"
    ADD CONSTRAINT "Participates_pkey" PRIMARY KEY (idhotel, amka_person, weekday, starttime, endtime);


--
-- Name: Transaction Transaction_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Transaction"
    ADD CONSTRAINT "Transaction_pkey" PRIMARY KEY (idtransaction, idhotelbooking);


--
-- Name: Participates check_person_participating; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public."Participates"
    ADD CONSTRAINT check_person_participating CHECK (public."1_1_check_person_for_participating"(amka_person, idhotel, participant_role)) NOT VALID;


--
-- Name: Manages check_role_emp; Type: CHECK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE public."Manages"
    ADD CONSTRAINT check_role_emp CHECK (public."1_1_check_employee_for_booking"(employeeid, idhotelbooking)) NOT VALID;


--
-- Name: creditcard creditcard_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.creditcard
    ADD CONSTRAINT "creditcard_PK" PRIMARY KEY (cardtype, number);


--
-- Name: client dc_uniq; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT dc_uniq UNIQUE (documentclient);


--
-- Name: hotel fax_UNIQUE; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotel
    ADD CONSTRAINT "fax_UNIQUE" UNIQUE (fax);


--
-- Name: hotelfacilities hotelfacilities_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotelfacilities
    ADD CONSTRAINT "hotelfacilities_PK" PRIMARY KEY ("idHotel", "nameFacility");


--
-- Name: client idClient_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT "idClient_PK" PRIMARY KEY ("idClient");


--
-- Name: employee idEmployee_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT "idEmployee_PK" PRIMARY KEY ("idEmployee");


--
-- Name: hotel idHotel_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotel
    ADD CONSTRAINT "idHotel_PK" PRIMARY KEY ("idHotel");


--
-- Name: person idPerson_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.person
    ADD CONSTRAINT "idPerson_PK" PRIMARY KEY ("idPerson");


--
-- Name: room idRoom_UNIQUE; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT "idRoom_UNIQUE" UNIQUE ("idRoom");


--
-- Name: hotelbooking idhotelbooking_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotelbooking
    ADD CONSTRAINT "idhotelbooking_PK" PRIMARY KEY (idhotelbooking);


--
-- Name: facility nameFacility_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facility
    ADD CONSTRAINT "nameFacility_PK" PRIMARY KEY ("nameFacility");


--
-- Name: room number_UNIQUE; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT "number_UNIQUE" UNIQUE (number);


--
-- Name: hotel phone_UNIQUE; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotel
    ADD CONSTRAINT "phone_UNIQUE" UNIQUE (phone);


--
-- Name: room room_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT "room_PK" PRIMARY KEY ("idRoom");


--
-- Name: roombooking roombooking_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roombooking
    ADD CONSTRAINT "roombooking_PK" PRIMARY KEY ("hotelbookingID", "roomID");


--
-- Name: roomfacilities roomfacilities_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomfacilities
    ADD CONSTRAINT "roomfacilities_PK" PRIMARY KEY ("idRoom", "nameFacility");


--
-- Name: roomrate roomrate_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomrate
    ADD CONSTRAINT "roomrate_PK" PRIMARY KEY ("idHotel", roomtype);


--
-- Name: roomtype typename_PK; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomtype
    ADD CONSTRAINT "typename_PK" PRIMARY KEY (typename);


--
-- Name: fki_bookedbyclientID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_bookedbyclientID_FK" ON public.hotelbooking USING btree ("bookedbyclientID");


--
-- Name: fki_bookedforpersonID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_bookedforpersonID_FK" ON public.roombooking USING btree ("bookedforpersonID");


--
-- Name: fki_clientID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_clientID_FK" ON public.creditcard USING btree ("clientID");


--
-- Name: fki_hotelID2_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_hotelID2_FK" ON public.roomrate USING btree ("idHotel");


--
-- Name: fki_hotelID3_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_hotelID3_FK" ON public.room USING btree ("idHotel");


--
-- Name: fki_hotelID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_hotelID_FK" ON public.employee USING btree ("hotelID");


--
-- Name: fki_hotelbookingID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_hotelbookingID_FK" ON public.roombooking USING btree ("hotelbookingID");


--
-- Name: fki_idHotel_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_idHotel_FK" ON public.hotelfacilities USING btree ("idHotel");


--
-- Name: fki_idRoom_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_idRoom_FK" ON public.roomfacilities USING btree ("idRoom");


--
-- Name: fki_nameFacility2_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_nameFacility2_FK" ON public.hotelfacilities USING btree ("nameFacility");


--
-- Name: fki_nameFacility_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_nameFacility_FK" ON public.roomfacilities USING btree ("nameFacility");


--
-- Name: fki_parentNameFacility_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_parentNameFacility_FK" ON public.facility USING btree ("subtypeOf");


--
-- Name: fki_roomID_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_roomID_FK" ON public.roombooking USING btree ("roomID");


--
-- Name: fki_roomType_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_roomType_FK" ON public.room USING btree (roomtype);


--
-- Name: fki_roomtype_FK; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX "fki_roomtype_FK" ON public.roomrate USING btree (roomtype);


--
-- Name: roombooking after_roombooking_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER after_roombooking_delete AFTER DELETE ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_after_roombooking_delete"();


--
-- Name: roombooking after_roombooking_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER after_roombooking_insert AFTER INSERT ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_after_roombooking_insert"();


--
-- Name: roombooking after_roombooking_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER after_roombooking_update AFTER UPDATE ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_after_roombooking_update"();


--
-- Name: roombooking before_roombooking_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER before_roombooking_delete BEFORE DELETE ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_before_roombooking_delete"();


--
-- Name: roombooking before_roombooking_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER before_roombooking_insert BEFORE INSERT ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_before_roombooking_insert"();


--
-- Name: roombooking before_roombooking_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER before_roombooking_update BEFORE UPDATE ON public.roombooking FOR EACH ROW EXECUTE FUNCTION public."5_2_5_3_before_roombooking_update"();


--
-- Name: hotelbooking hotelbooking_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hotelbooking_delete BEFORE DELETE ON public.hotelbooking FOR EACH ROW EXECUTE FUNCTION public."5_2_hotelbooking_delete"();


--
-- Name: hotelbooking hotelbooking_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hotelbooking_update BEFORE UPDATE ON public.hotelbooking FOR EACH ROW EXECUTE FUNCTION public."5_2_hotelbooking_update"();


--
-- Name: hotelbooking transaction_edit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER transaction_edit AFTER INSERT OR DELETE OR UPDATE ON public.hotelbooking FOR EACH ROW EXECUTE FUNCTION public."5_1_transaction_update"();


--
-- Name: Activity Activity_amka_employee_reserved_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Activity"
    ADD CONSTRAINT "Activity_amka_employee_reserved_fkey" FOREIGN KEY (amka_employee_reserved) REFERENCES public.employee("idEmployee") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Activity Activity_idhotel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Activity"
    ADD CONSTRAINT "Activity_idhotel_fkey" FOREIGN KEY (idhotel) REFERENCES public.hotel("idHotel") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Manages Manages_employeeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Manages"
    ADD CONSTRAINT "Manages_employeeid_fkey" FOREIGN KEY (employeeid) REFERENCES public.employee("idEmployee") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Manages Manages_idhotelbooking_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Manages"
    ADD CONSTRAINT "Manages_idhotelbooking_fkey" FOREIGN KEY (idhotelbooking) REFERENCES public.hotelbooking(idhotelbooking) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Participates Participates_amka_person_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Participates"
    ADD CONSTRAINT "Participates_amka_person_fkey" FOREIGN KEY (amka_person) REFERENCES public.person("idPerson") ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Participates Participates_idhotel_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Participates"
    ADD CONSTRAINT "Participates_idhotel_fkey" FOREIGN KEY (idhotel, weekday, starttime, endtime) REFERENCES public."Activity"(idhotel, weekday, starttime, endtime) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: Transaction Transaction_idhotelbooking_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public."Transaction"
    ADD CONSTRAINT "Transaction_idhotelbooking_fkey" FOREIGN KEY (idhotelbooking) REFERENCES public.hotelbooking(idhotelbooking) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: hotelbooking bookedbyclientID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotelbooking
    ADD CONSTRAINT "bookedbyclientID_FK" FOREIGN KEY ("bookedbyclientID") REFERENCES public.client("idClient") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roombooking bookedforpersonID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roombooking
    ADD CONSTRAINT "bookedforpersonID_FK" FOREIGN KEY ("bookedforpersonID") REFERENCES public.person("idPerson") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: creditcard clientID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.creditcard
    ADD CONSTRAINT "clientID_FK" FOREIGN KEY ("clientID") REFERENCES public.client("idClient") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: employee hotelID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT "hotelID_FK" FOREIGN KEY ("hotelID") REFERENCES public.hotel("idHotel") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: room hotelID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT "hotelID_FK" FOREIGN KEY ("idHotel") REFERENCES public.hotel("idHotel") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roomrate hotelID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomrate
    ADD CONSTRAINT "hotelID_FK" FOREIGN KEY ("idHotel") REFERENCES public.hotel("idHotel") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roombooking hotelbookingID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roombooking
    ADD CONSTRAINT "hotelbookingID_FK" FOREIGN KEY ("hotelbookingID") REFERENCES public.hotelbooking(idhotelbooking) ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: client idClient_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.client
    ADD CONSTRAINT "idClient_FK" FOREIGN KEY ("idClient") REFERENCES public.person("idPerson") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: employee idEmployee_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT "idEmployee_FK" FOREIGN KEY ("idEmployee") REFERENCES public.person("idPerson") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: hotelfacilities idHotel_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotelfacilities
    ADD CONSTRAINT "idHotel_FK" FOREIGN KEY ("idHotel") REFERENCES public.hotel("idHotel") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roomfacilities idRoom_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomfacilities
    ADD CONSTRAINT "idRoom_FK" FOREIGN KEY ("idRoom") REFERENCES public.room("idRoom") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: employee idmanagerFK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee
    ADD CONSTRAINT "idmanagerFK" FOREIGN KEY ("idEmployee") REFERENCES public.employee("idEmployee") ON UPDATE SET NULL ON DELETE SET NULL NOT VALID;


--
-- Name: hotelfacilities nameFacility_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hotelfacilities
    ADD CONSTRAINT "nameFacility_FK" FOREIGN KEY ("nameFacility") REFERENCES public.facility("nameFacility") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roomfacilities nameFacility_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomfacilities
    ADD CONSTRAINT "nameFacility_FK" FOREIGN KEY ("nameFacility") REFERENCES public.facility("nameFacility") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roombooking roomID_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roombooking
    ADD CONSTRAINT "roomID_FK" FOREIGN KEY ("roomID") REFERENCES public.room("idRoom") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: room roomType_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.room
    ADD CONSTRAINT "roomType_FK" FOREIGN KEY (roomtype) REFERENCES public.roomtype(typename) ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: roomrate roomtype_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roomrate
    ADD CONSTRAINT "roomtype_FK" FOREIGN KEY (roomtype) REFERENCES public.roomtype(typename) ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- Name: facility subtypeof_FK; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.facility
    ADD CONSTRAINT "subtypeof_FK" FOREIGN KEY ("subtypeOf") REFERENCES public.facility("nameFacility") ON UPDATE CASCADE ON DELETE CASCADE NOT VALID;


--
-- PostgreSQL database dump complete
--

\unrestrict Lle4oBBR7tO28oq5U3ox8cQZPsrXvItBcG2snlyIOjrmn30YKvReifOEcHBz4ih

