-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.1---------------------------------------------------------



-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.2---------------------------------------------------------




-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.3---------------------------------------------------------
----with helper function
CREATE OR REPLACE FUNCTION "4_3_help_func_find_the_min_rates"(country_input varchar(45)) 
RETURNS TABLE(country varchar(45),roomtype varchar(45),min_rate float) AS
$$
BEGIN

RETURN QUERY

SELECT h."country",rr.roomtype, min(rr.rate - (rr.discount/100 *rr.rate)) as minim
FROM "roomrate" rr natural join "hotel" h
WHERE h."country"=country_input
GROUP BY h."country",rr.roomtype
;

END;
$$
LANGUAGE 'plpgsql';

select* from "4_3_help_func_find_the_min_rates"('Russia') 


CREATE OR REPLACE FUNCTION "4_3_search_cheap_rooms_by_country"(country_input varchar(45)) 
RETURNS TABLE(idH integer, city varchar(45),roomtype varchar(45),rate float) AS
$$
BEGIN

RETURN QUERY
SELECT h."idHotel",h."city",rr."roomtype",rr.rate - (rr.discount/100 *rr.rate)
FROM "hotel" h natural join "roomrate" rr
WHERE rr.rate - (rr.discount/100 *rr.rate) = (SELECT s.min_rate 
											  FROM "4_3_help_func_find_the_min_rates"(country_input) as s
											  WHERE rr.roomtype=s.roomtype)
		and h."country"=country_input

;

END;
$$
LANGUAGE 'plpgsql';

select * from "4_3_search_cheap_rooms_by_country"('Russia') 


-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.3---------------------------------------------------------
----without helper function
CREATE OR REPLACE FUNCTION "4_3_search_cheap_rooms_by_country"(country_input varchar(45)) 
RETURNS TABLE(city varchar(45),roomtype varchar(45)) AS
$$
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
$$
LANGUAGE 'plpgsql';

select * from "4_3_search_cheap_rooms_by_country"('Russia') 

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.4---------------------------------------------------------
---without help func
CREATE OR REPLACE FUNCTION "4_4_search_hotels_with_max_income"() 
RETURNS TABLE(hotel_name varchar(45), hotel_city varchar(45)) AS
$$

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
$$
LANGUAGE 'plpgsql';

SELECT * FROM "4_4_search_hotels_with_max_income"() 

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
---without help func  attributes for check

CREATE OR REPLACE FUNCTION "4_4_search_hotels_with_max_income"() 
RETURNS TABLE(hotel_name varchar(45), hotel_city varchar(45), hotel_income real, avg_city_income float) AS
$$

BEGIN

RETURN QUERY

WITH hotel_incomes AS
(
SELECT h2."idHotel", sum(hb.totalamount) as hotel_income, h2.city
FROM "hotelbooking" hb inner join "roombooking" rb on(rb."hotelbookingID"=hb."idhotelbooking") inner join "room" r on (r."idRoom"=rb."roomID") natural join "hotel" h2 
WHERE hb.payed is true and hb.status='confirmed'
GROUP BY h2."idHotel"
)

SELECT h3.name,h3.city,hi.hotel_income,s2.average_city_hotel_incomes 
FROM "hotel" h3 natural join "hotel_incomes" hi inner join
										(SELECT h1.city, avg(hi1.hotel_income) as average_city_hotel_incomes
										 FROM "hotel" h1 inner join "hotel_incomes" hi1 on (hi1.city=h1.city)
										 GROUP BY h1.city) s2 on (s2.city=h3.city)
WHERE hi.hotel_income>s2.average_city_hotel_incomes
;

END;
$$
LANGUAGE 'plpgsql';

SELECT * FROM "4_4_search_hotels_with_max_income"() 
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------

---with help func
CREATE OR REPLACE FUNCTION "4_4_help_func_hotel_income"(city_in varchar(45)) 
RETURNS TABLE(hotel_id integer,hotel_income real) AS
$$
BEGIN

RETURN QUERY

SELECT s1."idHotel",sum(totalamount)
FROM "hotelbooking" hb inner join (SELECT rb."hotelbookingID",s."idHotel",s."city"
									FROM "roombooking" rb inner join 
								   (SELECT h."idHotel",h."city",r."idRoom"
									FROM "hotel" h inner join "room" r on(r."idHotel"=h."idHotel")
									WHERE h."city"=city_in
								   ) as s 
								   on(rb."roomID"=s."idRoom") 
								   WHERE s."city"=city_in ) as s1 on(s1."hotelbookingID"=hb."idhotelbooking")
WHERE hb."status"='confirmed' and hb."payed"=true
GROUP BY s1."idHotel"
;

END;
$$
LANGUAGE 'plpgsql';

SELECT * FROM "4_4_help_func_hotel_income"('Hiroshima') 


CREATE OR REPLACE FUNCTION "4_4_search_hotels_with_max_income"() 
RETURNS TABLE(hotel_name varchar(45), hotel_city varchar(45)) AS
$$
BEGIN

RETURN QUERY
SELECT h1.name,h1.city
FROM "hotel" h1 inner join 
				(SELECT h.city, avg(s1.hotel_income) as avg_income
				FROM "hotel" h natural join "4_4_help_func_hotel_income"(h.city) as s1
				GROUP BY h.city) as t1 on (t1.city=h1.city) 
				natural join "4_4_help_func_hotel_income"(h1.city) as t2 
WHERE t2.hotel_income >= t1.avg_income
;

END;
$$
LANGUAGE 'plpgsql';

SELECT * FROM "4_4_search_hotels_with_max_income"() 

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------4.5---------------------------------------------------------

year_v=(SELECT EXTRACT (YEAR FROM reg_date))::INTEGER;

CREATE OR REPLACE FUNCTION "4_5_find_hotel_fullness"(hotel_id integer, year_in integer) 
RETURNS TABLE(hotel_id integer, month_fullness integer) AS
$$
BEGIN

RETURN QUERY


;

END;
$$
LANGUAGE 'plpgsql';


CREATE OR REPLACE FUNCTION "4_5_find_hotel_fullness"(hotel_id integer, year_in integer) 
RETURNS TABLE(id_hotel integer, month_value integer, month_fullness float) AS
$$
BEGIN


for i in 1..12
	RETURN QUERY
	WITH number_of_total_rooms AS
	(
	SELECT r."idHotel", count(*) as total_rooms
	FROM "room" r 
	WHERE r."idHotel"=hotel_id
	GROUP BY r."idHotel"
	)


	WITH trial AS(
	SELECT r."idHotel",EXTRACT (month FROM rb.checkin) ::INTEGER as month_checkin,EXTRACT (month FROM rb.checkout) ::INTEGER as month_checkout, count(*) as booked_rooms
	FROM "room" r inner join "roombooking" rb on(r."idRoom"=rb."roomID")
	WHERE (EXTRACT (year FROM rb.checkin) ::INTEGER = 2022 or EXTRACT (year FROM rb.checkout) ::INTEGER=2022)
	AND r."idHotel"=11
	GROUP BY r."idHotel",month_checkin, month_checkout
		)
		
	SELECT s2."idHotel",s1.month_checkin, (s1.num_booked_rooms/s2.total_rooms) as fulln
	FROM
	(
	SELECT r."idHotel", count(*) as total_rooms
	FROM "room" r 
	WHERE r."idHotel"=11
	GROUP BY r."idHotel"
	) as s2,
	(SELECT tr."idHotel",tr.month_checkin,tr.month_checkout, tr.booked_rooms+tr1.booked_rooms as num_booked_rooms
	FROM "trial" tr inner join "trial" tr1 on(tr.month_checkin=tr1.month_checkout)
	WHERE tr1.month_checkin!=tr1.month_checkout
	UNION 
	SELECT *
	FROM "trial" tr2
	WHERE tr2.month_checkout NOT IN (SELECT tr.month_checkin
	FROM "trial" tr inner join "trial" tr1 on(tr.month_checkin=tr1.month_checkout)
	WHERE tr1.month_checkin!=tr1.month_checkout)) as s1
	
		

END;
$$
LANGUAGE 'plpgsql';

SELECT * 
FROM "4_5_find_hotel_fullness"(11, 2021) 