-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------6.1---------------------------------------------------------

CREATE OR REPLACE VIEW "6_1_availableRoomsByHotel" AS
SELECT r."idRoom", r.roomtype, CASE WHEN (s1.checkin is null) THEN current_date - integer '1'
									WHEN (s1.checkin is not null) THEN s1.checkin - integer '1'
									END as available_until
FROM (SELECT h1."idHotel" FROM "hotel" h1 WHERE h1.name='Ramblewood Inn') h inner join "room" r on(r."idHotel"=h."idHotel") 
				inner join 
				(SELECT rb."roomID", min(rb.checkin) :: date as checkin
				 FROM "roombooking" rb 
				 WHERE rb.checkin>current_date 
				 GROUP BY rb."roomID"
				) as s1 on(s1."roomID"=r."idRoom")
				
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
---6.1 with function

CREATE OR REPLACE VIEW "6_1_availableRoomsByHotel" AS
SELECT h."idHotel", r."idRoom", r.roomtype, s1.checkin as available_until
FROM "hotel" h inner join "room" r on(r."idHotel"=h."idHotel") 
				inner join 
				(SELECT rb."roomID", min(rb.checkin) :: date as checkin
				 FROM "roombooking" rb 
				 WHERE rb.checkin>current_date 
				 GROUP BY rb."roomID"
				) as s1 on(s1."roomID"=r."idRoom")

CREATE OR REPLACE FUNCTION "6_1_availableRoomsByHotel_function"(hotelName varchar(45))
RETURNS TABLE( roomId integer, roomType varchar(45), availableUntil date) AS 
$$
BEGIN

RETURN QUERY

SELECT v."idRoom", v.roomtype, v.available_until
FROM "6_1_availableRoomsByHotel" v
WHERE v."idHotel" = (SELECT h."idHotel" FROM "hotel" h WHERE h.name=hotelName)
;

END;
$$
LANGUAGE 'plpgsql';

SELECT * FROM "6_1_availableRoomsByHotel_function"('Ramblewood Inn')
SELECT * FROM "6_1_availableRoomsByHotel_function"('Harvest Moon Cottages')

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------6.2---------------------------------------------------------




