-- 5.2 / 5.3  Ενημέρωση κράτησης δωματίου.
-- Το σώμα είναι αυτό της αρχικής παράδοσης (βλ. db/original/schema.sql) με τρεις αλλαγές:
--   1. Το rate ανανεώνεται με την τρέχουσα τιμή/έκπτωση (λάθος που αναφέρει η αναφορά).
--      Αν το UPDATE δίνει το ίδιο ρητά άλλο rate, κρατιέται αυτό που δόθηκε.
--   2. Έλεγχος ότι το checkout είναι μετά το checkin.
--   3. Ο έλεγχος διαθεσιμότητας ακολουθεί τη σύμβαση [checkin, checkout): κράτηση που
--      αρχίζει την ημέρα του checkout μας (ή τελειώνει την ημέρα του checkin μας) δεν
--      συγκρούεται. Πριν οι συγκρίσεις ήταν >= / <=.

CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_update"()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
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

IF NEW.checkout <= NEW.checkin THEN
	Raise Exception 'The checkout must be after the checkin.';
END IF;

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
			
				IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
	   			
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
				IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=OLD."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
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

-- Ανανέωση του rate, εκτός αν το UPDATE όρισε ρητά άλλη τιμή.
IF NEW.rate IS NOT DISTINCT FROM OLD.rate AND rate_room IS NOT NULL THEN
	NEW.rate = rate_room;
END IF;

RETURN NEW;
END;
$function$

;
