-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.1---------------------------------------------------------

CREATE OR REPLACE FUNCTION "3_1_cities_countries_with_disc_over_30"() 
RETURNS TABLE(country varchar(45), city varchar(45)) AS
$$
BEGIN 

RETURN QUERY

SELECT h.country,h.city
FROM "hotel" as h
WHERE EXISTS 
(SELECT h1."idHotel", discount FROM "hotel" as h1 natural join "roomrate" as rr 
 WHERE rr.discount >30 and h."idHotel" = h1."idHotel");

END;
$$
LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.2---------------------------------------------------------

CREATE OR REPLACE FUNCTION "3_2_search_specific_hotels"(num_of_stars varchar(10), prefix_name varchar(44)) 
RETURNS TABLE(id_hotel integer, name_hotel varchar(45)) AS
$$
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
$$
LANGUAGE 'plpgsql';

--select * from "3_2_search_specific_hotels"('4','B');


----------extra query for check

SELECT h2."idHotel", h2."name"
FROM "hotel" h2
WHERE EXISTS (
SELECT h."idHotel", h."name"
FROM "hotel" h natural join "hotelfacilities" hf
WHERE hf."nameFacility"='Breakfast' and h2."idHotel" = h."idHotel"
INTERSECT
SELECT h."idHotel", h."name"
FROM "hotel" h natural join "hotelfacilities" hf
WHERE hf."nameFacility"='Restaurant' and h2."idHotel" = h."idHotel"
			)
			
and EXISTS(
SELECT h3."idHotel", h3."name"
FROM "hotel" h3 natural join "roomrate" rr
WHERE rr."roomtype"='Studio' and (rr."rate"-(rr.discount*rr."rate")) < 80
		and h2."idHotel" = h3."idHotel"
		 )
and h2."name" like ('B%') and h2."stars"='4'

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.3---------------------------------------------------------
CREATE OR REPLACE FUNCTION "3_3_displayMaxDiscountRoomsPerHotel"()
RETURNS TABLE(idHotel integer, name varchar(45), roomtype varchar(45), discount real) AS 
$$
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
$$
LANGUAGE 'plpgsql';



----------------------------------------------------------------------------------------------------------
---mine
CREATE OR REPLACE FUNCTION "3_3_displayMaxDiscountRoomsPerHotel"()
RETURNS TABLE( name varchar(45), roomtype varchar(45), discount real) AS 
$$
BEGIN

RETURN QUERY
SELECT h.name, rr1.roomtype, rr1.discount
FROM "hotel" h natural join "roomrate" rr1 natural join (SELECT rr."idHotel", max(rr.discount) as maximum_disc
FROM   "roomrate" rr
GROUP BY rr."idHotel") as t2
WHERE h."idHotel"=t2."idHotel" and rr1.discount=t2.maximum_disc
ORDER BY rr1.roomtype


;
END;
$$
LANGUAGE 'plpgsql';

select * from "3_3_displayMaxDiscountRoomsPerHotel"()

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.4---------------------------------------------------------


-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.5---------------------------------------------------------



-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.6---------------------------------------------------------



-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.7---------------------------------------------------------


-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------3.8---------------------------------------------------------

CREATE OR REPLACE FUNCTION "3_8_search_hotels_having_room_from_each_category"() 
RETURNS TABLE(hotel_name varchar(45)) AS
$$
DECLARE
date_of_search date=SELECT CURRENT_DATE;

BEGIN

RETURN QUERY

SELECT r1."idHotel"
FROM "room" r1
WHERE r1."idRoom" NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin>CURRENT_DATE and rb.checkout<CURRENT_DATE)
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
$$
LANGUAGE 'plpgsql';

SELECT DISTINCT r."idHotel", r."roomtype"
FROM "room" r
WHERE r."idHotel"=35