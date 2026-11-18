CREATE OR REPLACE FUNCTION "2_1_update_clients_and_cards"(action_in char(6),documentclient_in varchar(45),fname_in varchar(45), 
lname_in varchar(45), sex_in char(1),date_of_birth_in date, address_in varchar(75), city_in varchar(45), country_in varchar(45),
cardtype_in varchar(30), number_card_in varchar(45), expiration_card_in date, holder_in varchar(45)) 
RETURNS BOOLEAN AS
$$
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
				RAISE NOTICE 'Card has expired. Need to insert new card. Client added. Person Id=%',number_of_persons;
			END IF;
		ELSE
			RAISE NOTICE 'Card type or card number cannot be null. Client added. Person Id=%',number_of_persons;
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
$$
LANGUAGE 'plpgsql';

SELECT "2_1_update_clients_and_cards"('insert','00000000','Sofia','Galanomati','F',
	current_date, 'agnosto 50', 'Athens','Greece','ejgfnjrgj','kjwgenkjregn', current_date,'jhefehwef'); 

SELECT "2_1_update_clients_and_cards"('insert','00000000','Sofia','Galanomati','F',
	current_date, 'agnosto 50', 'Athens','Greece','ejgfnjrgj','kjwgenkjregn',current_date - integer '1','jhefehwef'); 
