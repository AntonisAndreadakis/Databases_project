-- Σχήμα της βάσης κρατήσεων ξενοδοχείων σε MySQL 8.4.
-- Μεταφορά του διορθωμένου σχήματος PostgreSQL (db/original/schema.sql + db/fixes/).
--
-- Αντιστοιχίες:
--   sequences                 -> AUTO_INCREMENT (συνεχίζει μόνο του από το μέγιστο id των δεδομένων)
--   τύποι ENUM                -> ENUM πάνω στη στήλη
--   real / numeric / bytea    -> FLOAT / DECIMAL(16,4) / LONGBLOB
--   boolean                   -> TINYINT(1)
--   ξένα κλειδιά NOT VALID    -> τα δεδομένα φορτώνονται με FOREIGN_KEY_CHECKS = 0
--   CHECK που καλούν συνάρτηση -> triggers στους πίνακες Manages / Participates (03_routines.sql)
--
-- Η σύγκριση κειμένου είναι με διάκριση πεζών-κεφαλαίων και τόνων (utf8mb4_0900_as_cs), όπως στην
-- PostgreSQL. Τα ονόματα πινάκων κρατούν τα κεφαλαία τους (Activity, Manages, Participates,
-- Transaction)· σε Linux η MySQL τα ξεχωρίζει.

SET NAMES utf8mb4;
ALTER DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs;

CREATE TABLE person (
    idPerson    INT NOT NULL AUTO_INCREMENT,
    fname       VARCHAR(45),
    lname       VARCHAR(45),
    sex         CHAR(1),
    dateofbirth DATE,
    address     VARCHAR(75),
    city        VARCHAR(45),
    country     VARCHAR(45),
    CONSTRAINT idPerson_PK PRIMARY KEY (idPerson)
);

CREATE TABLE hotel (
    idHotel INT NOT NULL AUTO_INCREMENT,
    name    VARCHAR(45),
    stars   VARCHAR(10),
    address VARCHAR(75),
    city    VARCHAR(45),
    country VARCHAR(45),
    phone   VARCHAR(25),
    fax     VARCHAR(25),
    CONSTRAINT idHotel_PK PRIMARY KEY (idHotel),
    CONSTRAINT fax_UNIQUE UNIQUE (fax),
    CONSTRAINT phone_UNIQUE UNIQUE (phone)
);

CREATE TABLE roomtype (
    typename    VARCHAR(45) NOT NULL,
    samplephoto LONGBLOB,
    CONSTRAINT typename_PK PRIMARY KEY (typename)
);

CREATE TABLE facility (
    nameFacility VARCHAR(45) NOT NULL,
    subtypeOf    VARCHAR(45),
    description  VARCHAR(100),
    type         ENUM('hotel', 'room') NOT NULL,
    CONSTRAINT nameFacility_PK PRIMARY KEY (nameFacility),
    INDEX fki_parentNameFacility_FK (subtypeOf),
    CONSTRAINT subtypeof_FK FOREIGN KEY (subtypeOf) REFERENCES facility (nameFacility)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE client (
    idClient       INT NOT NULL,
    documentclient VARCHAR(45),
    CONSTRAINT idClient_PK PRIMARY KEY (idClient),
    CONSTRAINT dc_uniq UNIQUE (documentclient),
    CONSTRAINT idClient_FK FOREIGN KEY (idClient) REFERENCES person (idPerson)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE creditcard (
    cardtype   VARCHAR(30) NOT NULL,
    number     VARCHAR(45) NOT NULL,
    expiration DATE,
    holder     VARCHAR(45),
    clientID   INT NOT NULL,
    CONSTRAINT creditcard_PK PRIMARY KEY (cardtype, number),
    INDEX fki_clientID_FK (clientID),
    CONSTRAINT clientID_FK FOREIGN KEY (clientID) REFERENCES client (idClient)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE employee (
    idEmployee INT NOT NULL,
    idmanager  INT,
    hotelID    INT,
    role       ENUM('reception', 'manager', 'staff'),
    CONSTRAINT idEmployee_PK PRIMARY KEY (idEmployee),
    INDEX fki_hotelID_FK (hotelID),
    CONSTRAINT idEmployee_FK FOREIGN KEY (idEmployee) REFERENCES person (idPerson)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT employee_hotelID_FK FOREIGN KEY (hotelID) REFERENCES hotel (idHotel)
        ON UPDATE CASCADE ON DELETE CASCADE,
    -- Στην PostgreSQL το "idmanagerFK" ορίστηκε κατά λάθος πάνω στο idEmployee (με SET NULL σε
    -- πρωτεύον κλειδί, που η MySQL δεν δέχεται). Εδώ μπαίνει στη στήλη που εννοούσε: idmanager.
    CONSTRAINT idmanagerFK FOREIGN KEY (idmanager) REFERENCES employee (idEmployee)
        ON DELETE SET NULL
);

CREATE TABLE room (
    idRoom   INT NOT NULL AUTO_INCREMENT,
    number   INT,
    area     FLOAT,
    idHotel  INT NOT NULL,
    roomtype VARCHAR(45),
    CONSTRAINT room_PK PRIMARY KEY (idRoom),
    CONSTRAINT number_UNIQUE UNIQUE (number),
    INDEX fki_hotelID3_FK (idHotel),
    INDEX fki_roomType_FK (roomtype),
    CONSTRAINT room_hotelID_FK FOREIGN KEY (idHotel) REFERENCES hotel (idHotel)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT roomType_FK FOREIGN KEY (roomtype) REFERENCES roomtype (typename)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE roomrate (
    idHotel  INT NOT NULL,
    roomtype VARCHAR(45) NOT NULL,
    rate     FLOAT,
    discount FLOAT,
    CONSTRAINT roomrate_PK PRIMARY KEY (idHotel, roomtype),
    INDEX fki_roomtype_FK (roomtype),
    CONSTRAINT roomrate_hotelID_FK FOREIGN KEY (idHotel) REFERENCES hotel (idHotel)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT roomrate_roomtype_FK FOREIGN KEY (roomtype) REFERENCES roomtype (typename)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE hotelfacilities (
    idHotel      INT NOT NULL,
    nameFacility VARCHAR(45) NOT NULL,
    CONSTRAINT hotelfacilities_PK PRIMARY KEY (idHotel, nameFacility),
    INDEX fki_nameFacility2_FK (nameFacility),
    CONSTRAINT idHotel_FK FOREIGN KEY (idHotel) REFERENCES hotel (idHotel)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT hotelfacilities_nameFacility_FK FOREIGN KEY (nameFacility) REFERENCES facility (nameFacility)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE roomfacilities (
    idRoom       INT NOT NULL,
    nameFacility VARCHAR(45) NOT NULL,
    CONSTRAINT roomfacilities_PK PRIMARY KEY (idRoom, nameFacility),
    INDEX fki_nameFacility_FK (nameFacility),
    CONSTRAINT idRoom_FK FOREIGN KEY (idRoom) REFERENCES room (idRoom)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT roomfacilities_nameFacility_FK FOREIGN KEY (nameFacility) REFERENCES facility (nameFacility)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE hotelbooking (
    idhotelbooking   INT NOT NULL AUTO_INCREMENT,
    reservationdate  DATE,
    cancellationdate DATE,
    totalamount      FLOAT,
    bookedbyclientID INT,
    payed            TINYINT(1) NOT NULL,
    paymethod        ENUM('card', 'cash', 'bank transfer'),
    status           ENUM('confirmed', 'canceled', 'pending'),
    CONSTRAINT idhotelbooking_PK PRIMARY KEY (idhotelbooking),
    INDEX fki_bookedbyclientID_FK (bookedbyclientID),
    CONSTRAINT bookedbyclientID_FK FOREIGN KEY (bookedbyclientID) REFERENCES client (idClient)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE roombooking (
    hotelbookingID    INT NOT NULL,
    roomID            INT NOT NULL,
    bookedforpersonID INT,
    checkin           DATE,
    checkout          DATE,
    rate              FLOAT,
    CONSTRAINT roombooking_PK PRIMARY KEY (hotelbookingID, roomID),
    INDEX fki_roomID_FK (roomID),
    INDEX fki_bookedforpersonID_FK (bookedforpersonID),
    CONSTRAINT hotelbookingID_FK FOREIGN KEY (hotelbookingID) REFERENCES hotelbooking (idhotelbooking)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT roomID_FK FOREIGN KEY (roomID) REFERENCES room (idRoom)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT bookedforpersonID_FK FOREIGN KEY (bookedforpersonID) REFERENCES person (idPerson)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE Activity (
    idhotel                INT NOT NULL,
    starttime              TIME NOT NULL,
    endtime                TIME NOT NULL,
    weekday                INT NOT NULL,
    activitytype           ENUM('tennis', 'golf', 'swimming', 'soccer'),
    amka_employee_reserved INT,
    CONSTRAINT Activity_pkey PRIMARY KEY (idhotel, weekday, starttime, endtime),
    CONSTRAINT check_weekdaye CHECK (weekday >= 0 AND weekday <= 6),
    CONSTRAINT violated_time CHECK (starttime < endtime),
    CONSTRAINT Activity_amka_employee_reserved_fkey FOREIGN KEY (amka_employee_reserved)
        REFERENCES employee (idEmployee) ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT Activity_idhotel_fkey FOREIGN KEY (idhotel) REFERENCES hotel (idHotel)
        ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE Participates (
    amka_person      INT NOT NULL,
    idhotel          INT NOT NULL,
    weekday          INT NOT NULL,
    starttime        TIME NOT NULL,
    endtime          TIME NOT NULL,
    participant_role ENUM('responsible', 'participant'),
    CONSTRAINT Participates_pkey PRIMARY KEY (idhotel, amka_person, weekday, starttime, endtime),
    CONSTRAINT Participates_amka_person_fkey FOREIGN KEY (amka_person) REFERENCES person (idPerson)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT Participates_idhotel_fkey FOREIGN KEY (idhotel, weekday, starttime, endtime)
        REFERENCES Activity (idhotel, weekday, starttime, endtime) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE TABLE Manages (
    employeeid     INT NOT NULL,
    idhotelbooking INT NOT NULL,
    CONSTRAINT Manages_pkey PRIMARY KEY (employeeid, idhotelbooking),
    CONSTRAINT Manages_employeeid_fkey FOREIGN KEY (employeeid) REFERENCES employee (idEmployee)
        ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT Manages_idhotelbooking_fkey FOREIGN KEY (idhotelbooking) REFERENCES hotelbooking (idhotelbooking)
        ON UPDATE CASCADE ON DELETE CASCADE
);

-- Χωρίς ξένο κλειδί προς την κράτηση: το ιστορικό μένει και όταν η κράτηση διαγραφεί (διόρθωση 5.1).
CREATE TABLE `Transaction` (
    idtransaction  INT NOT NULL AUTO_INCREMENT,
    idhotelbooking INT NOT NULL,
    action_tr      CHAR(6) NOT NULL,
    amount         DECIMAL(16, 4) NOT NULL,
    made_date      DATE,
    CONSTRAINT Transaction_pkey PRIMARY KEY (idtransaction, idhotelbooking),
    CONSTRAINT check_amount CHECK ((action_tr = 'insert' AND amount > 0)
                                   OR action_tr = 'update'
                                   OR (action_tr = 'delete' AND amount < 0))
);

-- Χρήστες της web εφαρμογής (webapp/). Δεν υπάρχει στην PostgreSQL. Ο κωδικός αποθηκεύεται μόνο
-- ως BCrypt hash· τον πρώτο χρήστη τον δημιουργεί η εφαρμογή στην εκκίνηση (βλ. README).
CREATE TABLE app_user (
    id            INT NOT NULL AUTO_INCREMENT,
    username      VARCHAR(50) NOT NULL,
    password_hash CHAR(60) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT app_user_PK PRIMARY KEY (id),
    CONSTRAINT app_user_username_UNIQUE UNIQUE (username)
);
