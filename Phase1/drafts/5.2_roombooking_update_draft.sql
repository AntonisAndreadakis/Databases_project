CREATE OR REPLACE FUNCTION "5_2_5_3_roombooking_update"() RETURNS TRIGGER AS
$$
DECLARE
canc_date_hb date;
availability_room boolean;
num_of_days integer;
total_amount real;
rate_rb_before real;
available_until date;
available_after date;

BEGIN
canc_date_hb = SELECT hb.cancellationdate FROM "hotelbooking" hb WHERE hb.idhotelbooking=OLD."hotelbookingID";

IF (canc_date_hb < current_date) THEN
	IF(NEW."bookedforpersonID"!= OLD."bookedforpersonID") THEN
		Raise Notice 'You cant change this because the cancellation date has passed.';
	END IF;
	IF((NEW.checkin=OLD.checkin AND NEW.checkout<OLD.checkout) OR (NEW.checkin>OLD.checkin AND NEW.checkout=OLD.checkout)) THEN
		Raise Notice 'Cancellation date has passed you cannot decrease the number of days of the reservation.';
	ELSIF ((NEW.checkin<OLD.checkin AND NEW.checkout=OLD.checkout)) THEN ---case when the days are increased because of the checkin
		IF((SELECT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb."idhotelbooking"=OLD."idhotelbooking") 
		   	NOT IN (SELECT rb1."roomID" FROM "roombooking" rb1 WHERE rb1.checkin<=NEW.checkin)) THEN
	   		availability_room=true;
			available_after = SELECT max(rb.checkout) FROM "roombooking" rb
							  WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin;
			Raise Notice 'Room available after %',available_after;
	  	ELSE
	   		availability_room=false;
	    END IF;
			
		IF (availability_room) THEN
			num_of_days = OLD.checkout - NEW.checkin;
			rate_room = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
						 WHERE rr."idHotel"= SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=OLD."roomID"
						 AND rr.roomtype = SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=OLD."roomID");
				
			UPDATE "roombooking" SET checkin=NEW.checkin, rate = rate_room
			WHERE "hotelbookingID"=OLD."hotelbookingID" AND "roomID"=OLD."roomID";
				
			total_amount = SELECT s1.new_total_amount 
			FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
				  FROM "roombooking" rb 
				  WHERE rb."hotelbookingID" = OLD."hotelbookingID"
				  GROUP BY rb."hotelbookingID") as s1; 
			
			UPDATE "hotelbooking" SET totalamount = total_amount
			WHERE "idhotelbooking" = OLD."hotelbookingID";
		ELSE
			Raise Notice 'Your room is not available before your checkin.';
		END IF;
			
	ELSIF ((NEW.checkin=OLD.checkin AND NEW.checkout>OLD.checkout)) THEN ---case when the days are increased because of the checkout
		IF((SELECT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb."bookedforpersonID"=OLD."bookedforpersonID") 
		   	NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=NEW.checkout)) THEN
	   		availability_room=true;
			available_until = SELECT min(rb.checkin) FROM "roombooking" rb
							  WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout;
			Raise Notice 'Room available until %',available_until;
	  	ELSE
	   		availability_room=false;
	    END IF;
			
		IF (availability_room) THEN
			num_of_days = NEW.checkout - OLD.checkin;
			rate_room = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
						 WHERE rr."idHotel"= SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=OLD."roomID"
						 AND rr.roomtype = SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=OLD."roomID");
							 
			UPDATE "roombooking" SET checkout=NEW.checkout, rate = rate_room
			WHERE "hotelbookingID"=OLD."hotelbookingID" AND "roomID"=OLD."roomID";
				
			total_amount = SELECT s1.new_total_amount 
			FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
				  FROM "roombooking" rb 
				  WHERE rb."hotelbookingID" = OLD."hotelbookingID"
				  GROUP BY rb."hotelbookingID") as s1; 
				  
			UPDATE "hotelbooking" SET totalamount = total_amount
			WHERE "idhotelbooking" = OLD."hotelbookingID";
		ELSE
			Raise Notice 'Your room is not available after your checkout.';
		END IF;
	END IF;
	RETURN NEW;
-------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------------------------------------
ELSIF (canc_date_hb >= current_date) THEN
	rate_room = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
				 WHERE rr."idHotel"= SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=OLD."roomID"
				 AND rr.roomtype = SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=OLD."roomID");
				 
	IF (NEW.checkin != OLD.checkin) THEN
		IF (NEW.checkout != OLD.checkout) THEN
			IF((SELECT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb."bookedforpersonID"=OLD."bookedforpersonID") 
		   	NOT IN (SELECT rb."roomID" FROM "roombooking" rb WHERE rb.checkin<=NEW.checkout and rb.checkin<=NEW.checkin)) THEN
	   			availability_room=true;
				available_until = SELECT min(rb.checkin) FROM "roombooking" rb
							  WHERE rb."roomID"=OLD."roomID" and rb.checkin>NEW.checkout;
				available_after = SELECT max(rb.checkout) FROM "roombooking" rb
							  WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin;
				Raise Notice 'Room available after %',available_after;
	  		ELSE
	   			availability_room=false;
	    	END IF;
			
			IF (availability_room) THEN
				num_of_days = NEW.checkout - NEW.checkin;
				UPDATE "roombooking" SET checkin=NEW.checkin, checkout=NEW.checkout, rate = rate_room
				WHERE "hotelbookingID"=OLD."hotelbookingID" AND "roomID"=OLD."roomID";
				
				total_amount = SELECT s1.new_total_amount 
				FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
				  	 FROM "roombooking" rb 
				  	 WHERE rb."hotelbookingID" = OLD."hotelbookingID"
				 	 GROUP BY rb."hotelbookingID") as s1; 
					 
			ELSE
				Raise Notice 'Your room is not available after your checkout or before your checkin.';
			END IF;
		-------------------------------------------------------------------------------------------------	
		ELSE
			IF((SELECT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb."idhotelbooking"=OLD."idhotelbooking") 
		   	NOT IN (SELECT rb1."roomID" FROM "roombooking" rb1 WHERE rb1.checkin<=NEW.checkin)) THEN
	   			availability_room=true;
				available_after = SELECT max(rb.checkout) FROM "roombooking" rb
							  	  WHERE rb."roomID"=OLD."roomID" and rb.checkout<NEW.checkin;
				Raise Notice 'Room available after %',available_after;
	  		ELSE
	   			availability_room=false;
	    	END IF;
			
			IF (availability_room) THEN
				num_of_days = OLD.checkout - NEW.checkin;
				UPDATE "roombooking" SET checkin=NEW.checkin, rate = rate_room
				WHERE "hotelbookingID"=OLD."hotelbookingID" AND "roomID"=OLD."roomID";
				
				total_amount = SELECT s1.new_total_amount 
				FROM (SELECT rb."hotelbookingID", sum(rb.rate*(rb.checkout-rb.checkin)) as new_total_amount 
					  FROM "roombooking" rb 
					  WHERE rb."hotelbookingID" = OLD."hotelbookingID"
					  GROUP BY rb."hotelbookingID") as s1; 

				UPDATE "hotelbooking" SET totalamount = total_amount
				WHERE "idhotelbooking" = OLD."hotelbookingID";
			ELSE
				Raise Notice 'Your room is not available before your checkin.';
			END IF;
		END IF;
 	----------------------------------------------------------------------------------------------------------------------------------	
	ELSE
		IF (NEW.checkout != OLD.checkout) THEN
		-------------------------------------------------------------------------------------------------
		ELSE
		
		END IF;
	END IF;
END IF;  ---if cancellation date




	
END;
$$
LANGUAGE 'plpgsql';