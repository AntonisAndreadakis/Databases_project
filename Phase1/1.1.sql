--Create types that will be needed
CREATE TYPE public.activity_type AS ENUM
    ('tennis', 'golf', 'swimming', 'soccer');

ALTER TYPE public.activity_type
    OWNER TO postgres;
	
CREATE TYPE public.participant_type AS ENUM
    ('responsible', 'participant');

ALTER TYPE public.participant_type
    OWNER TO postgres;

-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE "Transaction"
(idTransaction integer NOT NULL,
 idhotelbooking integer NOT NULL references "hotelbooking" ON UPDATE CASCADE ON DELETE CASCADE,
 action_tr CHAR(6) NOT NULL,
 amount numeric NOT NULL,
 made_date date,
 PRIMARY KEY(idTransaction,idhotelbooking),
 CONSTRAINT possible_actions CHECK(action_tr='insert' or action_tr='update' or action_tr='delete'),
 CONSTRAINT check_amount CHECK((action_tr='insert' and amount>0) or (action_tr='delete' and amount<0))
 
);

-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE "Activity"
(idhotel integer references "hotel" ON UPDATE CASCADE ON DELETE CASCADE,
 starttime time,
 endtime time,
 weekday integer,
 activitytype activity_type,
 amka_employee_reserved integer references "employee" ON UPDATE CASCADE ON DELETE CASCADE,
 CONSTRAINT violated_time CHECK(starttime<endtime),
 CONSTRAINT check_weekdaye CHECK(weekday>=0 and weekday<=6),
 PRIMARY KEY(idhotel,weekday,starttime,endtime)
);
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------

CREATE TABLE "Participates"(
	amka_person integer references "person" ON UPDATE CASCADE ON DELETE CASCADE,
	idhotel integer,
	weekday integer,
	starttime time,
	endtime time,
	participant_role participant_type,
	FOREIGN KEY(idhotel,weekday,starttime,endtime) references "Activity" ON UPDATE CASCADE ON DELETE CASCADE,
	PRIMARY KEY(idhotel,amka_person,weekday,starttime,endtime)
);

CREATE OR REPLACE FUNCTION check_person_for_participating(idperson integer, rolep participant_type) RETURNS boolean
  AS $$
     DECLARE
	 isfound boolean = true;
     BEGIN
	 IF rolep = 'participant' THEN
       IF idperson IN (SELECT e.idEmployee FROM "employee") THEN
          isfound=false;
       END IF;
	 ELSEIF rolep = 'responsible' THEN
	 	IF idperson IN (SELECT e.idClient FROM "client") THEN
          isfound=false;
        END IF;
	 END IF;
       RETURN isfound;
     END;
  $$
  LANGUAGE 'plpgsql';
	
ALTER TABLE "Participates" ADD CONSTRAINT "check_person_participating"  CHECK (check_person_for_participating(amka_person,participant_role))
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------------
CREATE TABLE "Manages"(
	employeeid integer references "employee" ON UPDATE CASCADE ON DELETE CASCADE,
	idhotelbooking integer references "hotelbooking" ON UPDATE CASCADE ON DELETE CASCADE,
	PRIMARY KEY(employeeid,idhotelbooking)
);
 CREATE OR REPLACE FUNCTION check_role_employee_for_booking(idemployee integer) RETURNS boolean
  AS $$
     DECLARE
	 isfound boolean = true;
     BEGIN
       IF idemployee NOT IN (SELECT e.idEmployee FROM "employee" WHERE e.role='manager' or e.role='reception') THEN
          isfound=false;
       END IF;
       RETURN isfound;
     END;
  $$
  LANGUAGE 'plpgsql';
	
ALTER TABLE "Manages" ADD CONSTRAINT "check_role_emp"  CHECK (check_role_employee_for_booking(employeeid))