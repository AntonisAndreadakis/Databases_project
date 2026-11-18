CREATE OR REPLACE FUNCTION "5_1_transaction_update"() RETURNS TRIGGER AS
$$
DECLARE 
amount numeric;
BEGIN
IF(TG_OP = 'INSERT') THEN
	IF(NEW.payed) THEN
		INSERT INTO "Transaction" VALUES(nextval('idtransaction'::regclass),NEW."idhotelbooking",'insert',NEW.totalamount, CURRENT_DATE);
	END IF;
ELSIF (TG_OP = 'UPDATE') THEN
	IF (NEW.totalamount<OLD.totalamount) THEN
		amount = OLD.totalamount-NEW.totalamount;
		UPDATE "Transaction" SET action_tr='update',amount=OLD.amount-amount
		WHERE idhotelbooking=NEW."idhotelbooking";
	ELSIF (NEW.totalamount>OLD.totalamount) THEN
		amount = NEW.totalamount-OLD.totalamount;
		UPDATE "Transaction" SET action_tr='update',amount=OLD.amount+amount
		WHERE idhotelbooking=NEW."idhotelbooking";
	END IF;
ELSIF (TG_OP = 'DELETE') THEN
	UPDATE "Transaction" SET action_tr='delete',amount=-OLD.amount
	WHERE idhotelbooking=NEW."idhotelbooking";
END IF;

RETURN NULL;
END;
$$
LANGUAGE 'plpgsql';







CREATE OR REPLACE FUNCTION "5_2_hotelbooking_update"() RETURNS TRIGGER AS
$$
BEGIN
IF (TG_OP = 'UPDATE') THEN
	IF(NEW.cancellationdate!=OLD.cancellationdate) THEN
		IF ((SELECT employeeid FROM "Manages" WHERE idhotelbooking=NEW."idhotelbooking") 
				NOT IN(SELECT e.idEmployee FROM "employee" e WHERE e.role='manager')) THEN
		RAISE EXCEPTION 'Cannot update the cancellation date.';
		ELSE
			UPDATE "hotelbooking" SET cancellationdate=NEW.cancellationdate
			WHERE "idhotelbooking"=NEW."idhotelbooking";
		END IF;
	END IF;
	IF (OLD.cancellationdate < current_date) THEN
		IF(NEW.totalamount<OLD.totalamount) THEN
			RAISE EXCEPTION 'Cannot update the reservation.';
		ELSIF (NEW.totalamount>OLD.totalamount) THEN
			UPDATE "hotelbooking" SET totalamount=NEW.totalamount, paymethod=NEW.paymethod, status=NEW.status, payed=NEW.payed
			WHERE "idhotelbooking"=NEW."idhotelbooking";
		END IF;
	ELSE 
		UPDATE "hotelbooking" SET totalamount=NEW.totalamount, paymethod=NEW.paymethod, status=NEW.status, payed=NEW.payed
		WHERE "idhotelbooking"=NEW."idhotelbooking";
	END IF;
ELSIF (TG_OP = 'DELETE') THEN
	IF(OLD.cancellationdate < current_date) THEN
		RAISE EXCEPTION 'Cannot delete the reservation.';
	ELSE
		DELETE FROM "hotelbooking" WHERE "idhotelbooking"= OLD."idhotelbooking";
	END IF;
END IF;

RETURN NEW;
END;
$$
LANGUAGE 'plpgsql';




CREATE OR REPLACE FUNCTION "5_2_hotelbooking_update"() RETURNS TRIGGER AS
$$
BEGIN
IF (TG_OP = 'UPDATE') THEN
	IF(NEW.cancellationdate!=OLD.cancellationdate) THEN
		IF ((SELECT employeeid FROM "Manages" WHERE idhotelbooking=NEW."idhotelbooking") 
				NOT IN(SELECT e.idEmployee FROM "employee" e WHERE e.role='manager')) THEN
		RAISE EXCEPTION 'Cannot update the cancellation date.';
		ELSE
			UPDATE "hotelbooking" SET cancellationdate=NEW.cancellationdate
			WHERE "idhotelbooking"=NEW."idhotelbooking";
		END IF;
	END IF;
	IF (OLD.cancellationdate < current_date) THEN
		IF(NEW.totalamount<OLD.totalamount) THEN
			RAISE EXCEPTION 'Cannot update the reservation.';
		ELSIF (NEW.totalamount>=OLD.totalamount) THEN
			UPDATE "hotelbooking" SET totalamount=NEW.totalamount, paymethod=NEW.paymethod, status=NEW.status, payed=NEW.payed
			WHERE "idhotelbooking"=NEW."idhotelbooking";
		END IF;
	ELSE
		UPDATE "hotelbooking" SET totalamount=NEW.totalamount, paymethod=NEW.paymethod, status=NEW.status, payed=NEW.payed;
	END IF;
ELSIF (TG_OP = 'DELETE') THEN
	IF(OLD.cancellationdate < current_date) THEN
		RAISE EXCEPTION 'Cannot delete the reservation.';
	ELSE
		DELETE FROM "hotelbooking" WHERE "idhotelbooking"= OLD."idhotelbooking";
	END IF;
END IF;

RETURN NEW;
END;
$$
LANGUAGE 'plpgsql';




CREATE OR REPLACE FUNCTION "5_2_hotelbooking_update"() RETURNS TRIGGER AS
$$
DECLARE
manager_hb integer;

BEGIN
IF (TG_OP = 'UPDATE') THEN
	IF(NEW.cancellationdate!=OLD.cancellationdate) THEN
		manager_hb=(SELECT employeeid FROM "Manages" WHERE idhotelbooking=NEW."idhotelbooking" 
					AND employeeid IN (SELECT e."idEmployee" FROM "employee" e WHERE e.role='manager')) :: integer;
		
		IF(manager_hb is null) THEN
			RAISE EXCEPTION 'Cannot update the cancellation date. Only the manager can.';
		ELSE
			UPDATE "hotelbooking" SET cancellationdate=NEW.cancellationdate
			WHERE "idhotelbooking"=NEW."idhotelbooking";
		END IF;
	
	END IF;
	RETURN NEW;
ELSIF (TG_OP = 'DELETE') THEN
	IF(OLD.cancellationdate < current_date) THEN
		RAISE EXCEPTION 'Cannot delete the reservation.';
	ELSE
		DELETE FROM "hotelbooking" WHERE "idhotelbooking"= OLD."idhotelbooking";
	END IF;
	RETURN OLD;
END IF;
	
END;
$$
LANGUAGE 'plpgsql';