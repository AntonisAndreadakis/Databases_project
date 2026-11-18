-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------5.1---------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_1_transaction_update"() RETURNS TRIGGER AS
$$
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
$$
LANGUAGE 'plpgsql';

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE TRIGGER transaction_edit
AFTER INSERT OR UPDATE OR DELETE ON "hotelbooking"
FOR EACH ROW EXECUTE PROCEDURE "5_1_transaction_update"();





-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------5.2---------------------------------------------------------

CREATE OR REPLACE FUNCTION "5_2_hotelbooking_update"() RETURNS TRIGGER AS
$$
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
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER hotelbooking_update
BEFORE UPDATE ON "hotelbooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_hotelbooking_update"();

UPDATE "hotelbooking" SET cancellationdate='2021-05-12'::date WHERE "idhotelbooking"=105;
SELECT * FROM "hotelbooking" hb WHERE hb."idhotelbooking"=105

--UPDATE "hotelbooking" SET cancellationdate=current_date WHERE "idhotelbooking"=5570;
--SELECT * FROM "hotelbooking" hb WHERE hb."idhotelbooking"=5570
--UPDATE "hotelbooking" SET cancellationdate=current_date WHERE "idhotelbooking"=5500 OR "idhotelbooking"=4618;
--UPDATE "hotelbooking" SET cancellationdate='2022-03-10'::date WHERE "idhotelbooking"=5500 OR "idhotelbooking"=4618;

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_hotelbooking_delete"() RETURNS TRIGGER AS
$$
BEGIN
	IF(OLD.cancellationdate < current_date) THEN
		RAISE EXCEPTION 'Cannot delete the reservation.';
	END IF;
RETURN OLD;
	
END;
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER hotelbooking_delete
BEFORE DELETE ON "hotelbooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_hotelbooking_delete"();

--DELETE FROM "hotelbooking" hb WHERE hb."idhotelbooking"=5570
--DELETE FROM "hotelbooking" hb WHERE hb."idhotelbooking"=5570 or hb."idhotelbooking"=116
--DELETE FROM "hotelbooking" hb WHERE hb."idhotelbooking"=5570 or hb."idhotelbooking"=974

--INSERT INTO "hotelbooking" VALUES(5570,('2022-02-19')::date,('2022-03-10')::date,null,4633,false,null,'confirmed');
--INSERT INTO "hotelbooking" VALUES(974,('2021-04-21')::date,('2021-05-12')::date,null,1888,false,null,'confirmed')
--INSERT INTO "hotelbooking" VALUES(116,('2021-05-22')::date,('2021-06-11')::date,null,3352,false,null,'confirmed')

--SELECT * FROM "hotelbooking" hb WHERE hb."idhotelbooking"=5570 or hb."idhotelbooking"=116 or hb."idhotelbooking"=974

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_update"() RETURNS TRIGGER AS
$$
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
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER before_roombooking_update
    BEFORE UPDATE 
    ON public.roombooking
    FOR EACH ROW
    EXECUTE PROCEDURE public."5_2_5_3_before_roombooking_update"();

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_update"() RETURNS TRIGGER AS
$$
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
	
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER after_roombooking_update
AFTER UPDATE ON "roombooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_5_3_after_roombooking_update"();

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_delete"() RETURNS TRIGGER AS
$$
DECLARE
canc_date_hb date;

BEGIN
canc_date_hb = (SELECT hb.cancellationdate FROM "hotelbooking" hb WHERE hb.idhotelbooking=OLD."hotelbookingID"):: date;

	IF(current_date > canc_date_hb) THEN
		RAISE EXCEPTION 'Unable to execute operation! Cancelation date has expired.';
	END IF;

RETURN OLD;
END;
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER before_roombooking_delete
BEFORE DELETE ON "roombooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_5_3_before_roombooking_delete"() ;

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_delete"() RETURNS TRIGGER AS
$$
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
	
$$
LANGUAGE 'plpgsql';


CREATE TRIGGER after_roombooking_delete
AFTER DELETE ON "roombooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_5_3_after_roombooking_delete"();
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_5_3_before_roombooking_insert"() RETURNS TRIGGER AS
$$
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
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER before_roombooking_insert
BEFORE INSERT ON "roombooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_5_3_before_roombooking_insert"();
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION "5_2_5_3_after_roombooking_insert"() RETURNS TRIGGER AS
$$
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
$$
LANGUAGE 'plpgsql';

CREATE TRIGGER after_roombooking_insert
AFTER INSERT ON "roombooking"
FOR EACH ROW
EXECUTE PROCEDURE "5_2_5_3_after_roombooking_insert"();

-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------

UPDATE "roombooking" SET checkin='2021-05-17'::date, checkout='2021-05-27'::date  WHERE "hotelbookingID"=105 and "roomID"=41;


select * from "roombooking" rb WHERE rb."hotelbookingID"=105;
select * from "hotelbooking" rb WHERE rb."idhotelbooking"=105;

select * from "Transaction" tr WHERE tr.idhotelbooking=105

select rb.checkin-rb.checkin from "roombooking" rb WHERE rb."hotelbookingID"=105;



INSERT INTO "roombooking" VALUES(762,35,4159,'2021-06-14'::date, '2021-07-02'::date);
INSERT INTO "roombooking" VALUES(762,25,6457,'2021-06-14'::date, '2021-07-02'::date);
INSERT INTO "roombooking" VALUES(762,40,3469,'2021-06-14'::date, '2021-07-02'::date);
DELETE FROM "roombooking" rb WHERE rb."hotelbookingID"=762 and rb."roomID"=35; 
DELETE FROM "roombooking" rb WHERE rb."hotelbookingID"=762 and rb."roomID"=25; 
DELETE FROM "roombooking" rb WHERE rb."hotelbookingID"=762 and rb."roomID"=40; 

select * from "roombooking" rb WHERE rb."hotelbookingID"=762

select * from "hotelbooking" hb WHERE hb."idhotelbooking"=762


UPDATE "hotelbooking" hb SET totalamount=0 WHERE hb."idhotelbooking"=762

DELETE FROM "roombooking" rb WHERE rb."hotelbookingID"=105 and rb."roomID"=41; 