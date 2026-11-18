-- 5.2 / 5.3  Ενημέρωση κράτησης δωματίου.
-- Το σώμα είναι αυτό της αρχικής παράδοσης (βλ. db/original/schema.sql). Οι προσθήκες έχουν
-- σχόλιο [fix]. Επιπλέον, σε όλο το σώμα:
--   * οι έλεγχοι διαθεσιμότητας ακολουθούν τη σύμβαση [checkin, checkout) (πριν ήταν >= / <=),
--   * κοιτούν το δωμάτιο που θα έχει η γραμμή (NEW."roomID") και όχι το παλιό.

-- Σημειώνει ότι το UPDATE περιέχει τη στήλη rate στο SET. Τρέχει πριν από το
-- before_roombooking_update (τα triggers εκτελούνται με αλφαβητική σειρά ονόματος).
CREATE OR REPLACE FUNCTION "5_3_rate_given"()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
	PERFORM set_config('hotel.rate_given', '1', true);
	RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_roombooking_rate_given ON roombooking;
CREATE TRIGGER before_roombooking_rate_given
	BEFORE UPDATE OF rate ON roombooking
	FOR EACH ROW EXECUTE FUNCTION "5_3_rate_given"();

CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_update"() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
canc_date_hb date;
availability_room boolean;
available_until date;
available_after date;
rate_room real;
rate_given boolean;
free_until date;
days_before integer;
days_after integer;

BEGIN
canc_date_hb = (SELECT hb.cancellationdate FROM "hotelbooking" hb WHERE hb.idhotelbooking=OLD."hotelbookingID"):: date;
rate_room = (SELECT rr.rate-(rr.rate*rr.discount/100) FROM "roomrate" rr 
				 WHERE rr."idHotel"= (SELECT r."idHotel" FROM "room" r WHERE r."idRoom"=NEW."roomID"
				 AND rr.roomtype = (SELECT r."roomtype" FROM "room" r WHERE r."idRoom"=NEW."roomID")));

-- [fix] Το rate δόθηκε ρητά στο UPDATE; Το σημειώνει το trigger before_roombooking_rate_given.
rate_given = (current_setting('hotel.rate_given', true) = '1');
PERFORM set_config('hotel.rate_given', '', true);

-- [fix] Οι ημερομηνίες είναι υποχρεωτικές (με NULL όλοι οι έλεγχοι περνούσαν σιωπηλά).
IF NEW.checkin IS NULL OR NEW.checkout IS NULL THEN
	Raise Exception 'The checkin and the checkout cannot be null.';
END IF;
IF NEW.checkout <= NEW.checkin THEN
	Raise Exception 'The checkout must be after the checkin.';
END IF;

-- [fix] Πριν απορριπτόταν κάθε αλλαγή σε κράτηση με checkin έως σήμερα, άρα δεν γινόταν ούτε
-- παράταση διαμονής που έχει αρχίσει. Τώρα απαγορεύεται μόνο η μετακίνηση ημερομηνίας στο παρελθόν.
IF NEW.checkin <> OLD.checkin AND NEW.checkin < current_date THEN
	Raise Exception 'You cannot do this! The new checkin is in the past.';
END IF;
IF NEW.checkout <> OLD.checkout AND NEW.checkout < current_date THEN
	Raise Exception 'You cannot do this! The new checkout is in the past.';
END IF;

-- [fix] Μετά την προθεσμία ακύρωσης δεν επιτρέπεται ούτε η μεταφορά του δωματίου σε άλλη κράτηση
-- ούτε η μείωση της τιμής (ήταν παρακάμψεις του κανόνα «όχι αφαίρεση δωματίων / μείωση»).
IF canc_date_hb < current_date THEN
	IF NEW."hotelbookingID" <> OLD."hotelbookingID" THEN
		Raise Exception 'The cancellation date has passed. You cannot move the room to another booking.';
	END IF;
	IF rate_given AND NEW.rate < OLD.rate THEN
		Raise Exception 'The cancellation date has passed. You cannot decrease the rate.';
	END IF;
END IF;

-- [fix] Γενικός έλεγχος διαθεσιμότητας όταν αλλάζουν οι ημερομηνίες ή το δωμάτιο. Οι έλεγχοι της
-- αρχικής υλοποίησης δεν έπιαναν την αλλαγή δωματίου. Το κλείδωμα ανά δωμάτιο εμποδίζει δύο
-- ταυτόχρονες συναλλαγές να κλείσουν το ίδιο δωμάτιο.
IF NEW."roomID" <> OLD."roomID" OR NEW.checkin <> OLD.checkin OR NEW.checkout <> OLD.checkout THEN
	PERFORM pg_advisory_xact_lock(NEW."roomID");
	IF EXISTS (SELECT 1 FROM "roombooking" rb
			   WHERE rb."roomID" = NEW."roomID"
				 AND NOT (rb."hotelbookingID" = OLD."hotelbookingID" AND rb."roomID" = OLD."roomID")
				 AND rb.checkin < NEW.checkout AND rb.checkout > NEW.checkin) THEN
		free_until = (SELECT min(rb.checkin) FROM "roombooking" rb
					  WHERE rb."roomID" = NEW."roomID"
						AND NOT (rb."hotelbookingID" = OLD."hotelbookingID" AND rb."roomID" = OLD."roomID")
						AND rb.checkin >= OLD.checkout);
		IF NEW."roomID" = OLD."roomID" AND NEW.checkin = OLD.checkin AND free_until IS NOT NULL THEN
			Raise Exception 'The room is not available for these dates. You can extend the checkout up to %.', free_until;
		END IF;
		Raise Exception 'The room is not available for these dates.';
	END IF;
END IF;

IF (canc_date_hb < current_date) THEN
	IF (NEW.checkin < OLD.checkin) THEN
		IF (NEW.checkout < OLD.checkout) THEN
			Raise Notice 'checkin<old checkout<old';
			days_before = OLD.checkout - OLD.checkin;
			days_after = NEW.checkout - NEW.checkin;
			IF (days_after >= days_before) THEN
			
				IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
	   			
				availability_room=true;
				
				available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									 WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
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
				IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				  	((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
				availability_room=true;
				
				available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
								   
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				 ((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				
					availability_room=true;
					
					available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
					available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
					
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
			IF(((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
	   			availability_room=true;
				
				available_after = (SELECT max(rb.checkout) FROM "roombooking" rb
									WHERE rb."roomID"=NEW."roomID" and rb.checkout<=NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID");
					
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
			IF (((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin<=NEW.checkin AND rb.checkout>NEW.checkin and rb."hotelbookingID"!=OLD."hotelbookingID") is null) AND
				((SELECT DISTINCT rb."roomID" FROM "roombooking" rb WHERE rb."roomID"=NEW."roomID" AND rb.checkin>=NEW.checkin AND rb.checkin<NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID") is null)) THEN
				availability_room=true;
				
				available_until = (SELECT min(rb.checkin) FROM "roombooking" rb
									   WHERE rb."roomID"=NEW."roomID" and rb.checkin>=NEW.checkout and rb."hotelbookingID"!=OLD."hotelbookingID");
								   
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

-- [fix] Ανανέωση του rate με την τρέχουσα τιμή/έκπτωση (λάθος που αναφέρει η αναφορά),
-- εκτός αν το UPDATE όρισε ρητά rate (π.χ. η εφαρμογή Java).
IF NOT rate_given OR NEW.rate IS NULL THEN
	IF rate_room IS NULL THEN
		Raise Exception 'There is no rate for this room type in this hotel.';
	END IF;
	NEW.rate = rate_room;
END IF;

RETURN NEW;
END;
$$;
