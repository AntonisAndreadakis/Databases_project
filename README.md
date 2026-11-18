# Βάση δεδομένων κρατήσεων ξενοδοχείων (ΠΛΗ303)

Εργασία του μαθήματος ΠΛΗ303 «Βάσεις Δεδομένων», Πολυτεχνείο Κρήτης, εαρινό εξάμηνο 2020-2021.
Μια βάση PostgreSQL για κρατήσεις ξενοδοχείων, με συναρτήσεις PL/pgSQL, triggers, μία όψη και μια
μικρή εφαρμογή Java (JDBC).

Το README αυτό δείχνει πώς στήνεται η βάση τοπικά με Docker και πώς ελέγχεται η δομή της.
Όλες οι εντολές είναι για **PowerShell σε Windows** και έχουν δοκιμαστεί με Docker 29 και την εικόνα `postgres:16`.

## Περιεχόμενα φακέλου

| Διαδρομή | Τι είναι |
|---|---|
| `Phase1/` | Τα SQL της φάσης Α, όπως γράφτηκαν (σημειώσεις εργασίας, όχι εκτελέσιμα scripts)· στο `Phase1/drafts/` τα πρόχειρα |
| `Phase2/project_base.backup` | Αντίγραφο της βάσης (`pg_dump` custom format, PostgreSQL 11) με σχήμα, δεδομένα, συναρτήσεις και triggers |
| `Phase2/src/db_phase_B/`, `Phase2/pom.xml` | Η εφαρμογή JDBC της φάσης Β (βλ. [Η εφαρμογή Java](#η-εφαρμογή-java-φάση-β)) |
| `db/original/schema.sql` | Το σχήμα όπως είναι μέσα στο backup (πίνακες, συναρτήσεις, triggers, χωρίς δεδομένα), για ανάγνωση |
| `db/fixes/` | Οι διορθώσεις, ως script που εφαρμόζεται πάνω στο backup (βλ. [Διορθώσεις](#διορθώσεις)) |
| `db/checks/01_structure.sql` | Ερωτήματα ελέγχου της δομής |
| `db/checks/02_examples.sql` | Παραδείγματα κλήσης των συναρτήσεων |
| `db/checks/03_fix_tests.sql`, `04_weekly_plan_tests.sql` | Δοκιμές των διορθώσεων |
| `docker-compose.yml` | Τοπική PostgreSQL 16 για το project |
| `docs/REPORT.md` | Η αναφορά της ομάδας |
| `docs/*.pdf` | Οι εκφωνήσεις των δύο φάσεων |

Η «αλήθεια» για το τι παραδόθηκε είναι το backup: περιέχει και συναρτήσεις που δεν υπάρχουν στα αρχεία του `Phase1/`
(2.2, 3.4-3.7, 4.1, 4.2). Το `db/original/schema.sql` βγήκε από αυτό με `pg_dump --schema-only`.

## Branches

| Branch | Περιεχόμενο |
|---|---|
| `original` | Η παράδοση του Μαΐου 2021, αυτούσια (μαζί με τα `.class` και τα αρχεία του Eclipse) |
| `main` | README, Docker, τακτοποίηση φακέλων και οι μεταγενέστερες διορθώσεις |

## Γρήγορη εκκίνηση

Χρειάζεται μόνο το Docker Desktop να τρέχει.

**1. Μπείτε στον φάκελο του project.** Το όνομα του φακέλου έχει κενό και παρένθεση, γι' αυτό μπαίνει σε μονά εισαγωγικά:

```powershell
Set-Location -LiteralPath 'C:\Users\Antonis-PC\OneDrive\Desktop\sql_projects\6) Our'
```

Όλες οι επόμενες εντολές τρέχουν μέσα από αυτόν τον φάκελο.

**2. Ξεκινήστε το container.**

```powershell
docker compose up -d --wait
```

Αναμένεται στο τέλος `Container hotel-db Healthy`. Δημιουργείται ένα container `hotel-db` με μια άδεια βάση `hotel`.

**3. Επαναφέρετε το backup.**

```powershell
docker compose exec db pg_restore -U postgres -d hotel --no-owner --no-privileges /backup/project_base.backup
```

Δεν τυπώνει τίποτα όταν πετύχει και διαρκεί λίγα δευτερόλεπτα. Γίνεται μία φορά: αν το ξανατρέξετε στην ίδια βάση θα βγάλει σφάλματα «already exists» (βλ. [Καθαρή επανεκκίνηση](#σταμάτημα-και-καθάρισμα)).

**4. Επιβεβαιώστε ότι φορτώθηκε.**

```powershell
docker compose exec db psql -U postgres -d hotel -c "SELECT count(*) FROM hotel;"
```

Αναμένεται `101`.

## Σύνδεση με psql

```powershell
docker compose exec db psql -U postgres -d hotel
```

Ανοίγει διαδραστικό `psql` με prompt `hotel=#`. Έξοδος με `\q`.

Μέσα στο container δεν ζητείται κωδικός. Από εργαλείο στον υπολογιστή σας (pgAdmin, DBeaver, η εφαρμογή Java) τα στοιχεία είναι:

| | |
|---|---|
| Host | `127.0.0.1` |
| Port | `5433` |
| Database | `hotel` |
| User | `postgres` |
| Password | η τιμή της `POSTGRES_PASSWORD` (προεπιλογή `local_dev_only`) |

Ο κωδικός είναι placeholder για τοπική χρήση και η θύρα ακούει μόνο στο `127.0.0.1`. Για άλλη τιμή ή άλλη θύρα,
αντιγράψτε το `.env.example` σε `.env` και αλλάξτε το **πριν** από το πρώτο `docker compose up`
(ο κωδικός ορίζεται μόνο όταν δημιουργείται η βάση):

```powershell
Copy-Item .env.example .env
```

## Έλεγχος της δομής

### Όλα μαζί

```powershell
docker compose exec db psql -U postgres -d hotel -f /sql/checks/01_structure.sql
```

Τρέχει δώδεκα ελέγχους, καθένας με επικεφαλίδα `=== ... ===`. Αναμενόμενα πλήθη:

| Έλεγχος | Μετά το restore | Μετά και τις [διορθώσεις](#διορθώσεις) |
|---|---|---|
| 1. Πίνακες | 17 | 17 |
| 2. Στήλες | 79 | 79 |
| 3. Πρωτεύοντα κλειδιά και UNIQUE | 22 (17 PK, 5 UNIQUE) | 22 |
| 4. Ξένα κλειδιά | 25 | 24 |
| 5. Περιορισμοί CHECK | 5 | 5 |
| 6. Τύποι ENUM | 7 | 7 |
| 7. Sequences | 5 | 5 |
| 8. Ευρετήρια | 37 | 37 |
| 9. Συναρτήσεις | 29 | 38 |
| 10. Triggers | 9 | 11 |
| 11. Όψεις | 1 (`6_1_availableRoomsByHotel`) | 2 (και `6_2_weeklyPlan`) |
| 12. Πλήθος γραμμών | βλ. παρακάτω | ίδιο |

Πλήθος γραμμών ανά πίνακα:

| Πίνακας | Γραμμές | Πίνακας | Γραμμές |
|---|---:|---|---:|
| `person` | 10001 | `roomrate` | 823 |
| `client` | 6213 | `roomtype` | 15 |
| `creditcard` | 6212 | `facility` | 79 |
| `employee` | 2055 | `hotelfacilities` | 3206 |
| `hotel` | 101 | `roomfacilities` | 28564 |
| `room` | 2034 | `Activity` | 4 |
| `hotelbooking` | 6214 | `Participates` | 5 |
| `roombooking` | 14221 | `Manages` | 446 |
| | | `Transaction` | 0 |

Για να κρατήσετε την έξοδο σε αρχείο:

```powershell
docker compose exec db psql -U postgres -d hotel -f /sql/checks/01_structure.sql | Out-File -Encoding utf8 structure.txt
```

### Ένας-ένας έλεγχος

Οι εντολές `\d...` του `psql` δουλεύουν και απευθείας από το PowerShell:

```powershell
docker compose exec db psql -U postgres -d hotel -c "\dt"
```

Λίστα πινάκων, τελευταία γραμμή `(17 rows)`.

```powershell
docker compose exec db psql -U postgres -d hotel -c "\d roombooking"
```

Στήλες, πρωτεύον κλειδί, ευρετήρια, 3 ξένα κλειδιά και 6 triggers του πίνακα `roombooking`. Βάλτε όποιον πίνακα θέλετε.

| Εντολή μέσα στο `psql` | Τι δείχνει |
|---|---|
| `\dt` | πίνακες |
| `\d roombooking` | στήλες, κλειδιά, περιορισμοί, triggers ενός πίνακα |
| `\d "Activity"` | το ίδιο για πίνακα με κεφαλαίο στο όνομα (θέλει διπλά εισαγωγικά) |
| `\dT+` | τύποι ENUM με τις τιμές τους |
| `\ds` | sequences |
| `\df` | συναρτήσεις |
| `\dv` | όψεις |
| `\sf "4_2_countAvgAge"` | ο κώδικας μιας συνάρτησης |
| `\d+ "6_1_availableRoomsByHotel"` | ο ορισμός της όψης |

## Παραδείγματα κλήσης συναρτήσεων

```powershell
docker compose exec db psql -U postgres -d hotel -f /sql/checks/02_examples.sql
```

Καλεί εννέα από τις συναρτήσεις/όψεις του project, όλες μόνο για ανάγνωση. Ενδεικτικά αποτελέσματα:

| Κλήση | Αναμένεται |
|---|---|
| `"3_6_findSubtypesOfAFacility"('Business Services')` | 6 γραμμές (Fax, Laptop rental, Lounge, …) |
| `"3_4_displayBookingStatus"(11)` | πρώτη γραμμή: κράτηση 105, `Employee` |
| `"4_3_search_cheap_rooms_by_country"('Russia')` | πρώτη γραμμή: `Sukhoy Log`, `Apartment` |
| `"4_5_find_hotel_fullness"(11, 2021)` | 8 γραμμές, μήνες 5-12, π.χ. Ιούλιος 70.73 |
| `"4_2_countAvgAge"('Studio')` | 45.17 το 2026 (υπολογίζεται με το τρέχον έτος) |
| `"6_1_availableRoomsByHotel"` | 0 γραμμές μετά το restore (βλ. σημείωση)· 2034 μετά τις διορθώσεις |

Δύο πράγματα που αξίζει να ξέρετε:

- **Τα ονόματα των συναρτήσεων ξεκινούν με ψηφίο, άρα θέλουν πάντα διπλά εισαγωγικά.**
  Το Windows PowerShell 5.1 όμως αφαιρεί τα διπλά εισαγωγικά όταν περνά το όρισμα του `-c` στο `docker`, και η κλήση
  αποτυγχάνει με `trailing junk after numeric literal`. Γι' αυτό τρέξτε τις κλήσεις είτε από αρχείο `.sql` (όπως παραπάνω)
  είτε μέσα στο διαδραστικό `psql`:

  ```sql
  SELECT * FROM "4_2_countAvgAge"('Studio');
  ```

- **Οι κρατήσεις του dataset καλύπτουν 13/01/2021 έως 31/05/2022.** Ό,τι συγκρίνει με τη σημερινή ημερομηνία
  (`current_date`) βλέπει πλέον όλες τις κρατήσεις ως παρελθούσες. Γι' αυτό η αρχική όψη 6.1, που ζητούσε μελλοντική
  κράτηση, επιστρέφει 0 γραμμές, ενώ η διορθωμένη τα βγάζει όλα ελεύθερα.

Για δικά σας ερωτήματα, προσθέστε ένα αρχείο `.sql` στον φάκελο `db/` και τρέξτε το με `-f /sql/<αρχείο>.sql`
(ο φάκελος `db/` φαίνεται μέσα στο container ως `/sql`, μόνο για ανάγνωση).

## Διορθώσεις

Το backup μένει όπως παραδόθηκε. Οι διορθώσεις είναι ένα ξεχωριστό script που τρέχει **μετά** το restore
(όλα ή τίποτα· μπορεί να ξανατρέξει):

```powershell
docker compose exec db psql -U postgres -d hotel -v ON_ERROR_STOP=1 --single-transaction -f /sql/fixes/apply.sql
```

Τυπώνει πέντε αποτελέσματα `setval` και μερικά `CREATE FUNCTION` / `CREATE VIEW`, χωρίς `ERROR`. Την πρώτη φορά
βγάζει και δύο `NOTICE: ... does not exist, skipping`, που είναι αναμενόμενα.

Δοκιμές (τρέχουν μέσα σε transaction που κάνει ROLLBACK, δεν αφήνουν τίποτα στη βάση):

```powershell
docker compose exec db psql -U postgres -d hotel -f /sql/checks/03_fix_tests.sql
```

```powershell
docker compose exec db psql -U postgres -d hotel -f /sql/checks/04_weekly_plan_tests.sql
```

Αναμένονται 9 και 3 γραμμές `OK ...` αντίστοιχα, και στο τέλος της καθεμιάς `ALL TESTS PASSED`.

Τι διορθώθηκε (λεπτομέρειες στα σχόλια των αρχείων του `db/fixes/`):

| Ερώτημα | Πρόβλημα στην παράδοση | Διόρθωση |
|---|---|---|
| sequences | Ήταν πίσω από τα μέγιστα id· κάθε `nextval` έδινε duplicate key | Συγχρονισμός με τα μέγιστα id |
| 2.1 | Το `'update'` έσκαγε (alias μέσα στο `SET`, ανύπαρκτη μεταβλητή) | Σωστό `UPDATE`· σφάλμα αν ο πελάτης δεν υπάρχει |
| 2.2 | Έσκαγε (sequence, alias `pe` που έλειπε)· ελλιπής έλεγχος διαθεσιμότητας | Τρέχει· κανονικός έλεγχος επικάλυψης |
| 4.1 | Έλεγχος σε `checkout` αντί `checkin`· οι συμμετοχές πολλαπλασιάζονταν με τις κρατήσεις | Μία γραμμή ανά πελάτη και ξενοδοχείο διαμονής |
| 5.1 | Η διαγραφή πληρωμένης κράτησης έσκαγε (`NEW` σε `DELETE`) | Καταγράφεται επιστροφή· το `Transaction` δεν έχει πια ξένο κλειδί προς την κράτηση, για να μένει το ιστορικό |
| 5.3 insert | Ο έλεγχος διαθεσιμότητας κοίταζε το `OLD` (NULL), άρα επέτρεπε διπλοκράτηση | Κοιτά το `NEW`· το `rate` μπαίνει πριν την εισαγωγή |
| 5.3 update | Το `rate` δεν ανανεωνόταν | Παίρνει την τρέχουσα τιμή, εκτός αν το `UPDATE` ορίζει ρητά άλλη |
| 6.1 | Καρφωτό ξενοδοχείο· έλειπαν τα δωμάτια χωρίς μελλοντική κράτηση | Όψη για όλα τα ξενοδοχεία και συνάρτηση `"6_1_availableRoomsByHotel_function"(όνομα)` |
| 6.2 | Δεν είχε υλοποιηθεί | Όψη `"6_2_weeklyPlan"` με `INSTEAD OF` triggers |

Σύμβαση που ακολουθείται πλέον παντού: μια κράτηση πιάνει τις νύχτες από το `checkin` έως πριν το `checkout`,
άρα νέα κράτηση μπορεί να αρχίζει την ημέρα που η προηγούμενη κάνει checkout.

### Η όψη 6.2 (εβδομαδιαίο πλάνο)

Δείχνει την εβδομάδα μετά την τρέχουσα (Κυριακή έως Σάββατο), μία γραμμή ανά δωμάτιο: τιμή, έκπτωση και για κάθε
ημέρα το `documentclient` του πελάτη ή `'0'` αν το δωμάτιο είναι ελεύθερο. Μέσα στο `psql`:

```sql
SELECT room_number, rate, discount, sunday, monday, tuesday, wednesday, thursday, friday, saturday
FROM "6_2_weeklyPlan" WHERE "idHotel" = 11;
```

Επιτρέπονται μόνο ενημερώσεις στα `rate`, `discount` και στις επτά στήλες ημερών:

```sql
BEGIN;
UPDATE "6_2_weeklyPlan" SET monday = (SELECT documentclient FROM client WHERE "idClient" = 4971)
WHERE "idRoom" = 250;                                       -- κλείσιμο της Δευτέρας
UPDATE "6_2_weeklyPlan" SET monday = '0' WHERE "idRoom" = 250;   -- απελευθέρωση
ROLLBACK;
```

Το `rate`/`discount` ορίζεται ανά τύπο δωματίου, οπότε η αλλαγή του ισχύει για όλα τα δωμάτια του ίδιου τύπου στο
ξενοδοχείο.

### Γνωστά ανοιχτά σημεία

- Το trigger ενημέρωσης του `roombooking` απορρίπτει κάθε αλλαγή με `checkin` ή `checkout` έως και σήμερα (επιλογή της
  αρχικής παράδοσης). Με το dataset του 2021-2022 αυτό σημαίνει ότι οι υπάρχουσες κρατήσεις δεν αλλάζουν ημερομηνίες.
- Το dataset περιέχει ήδη επικαλυπτόμενες κρατήσεις για το ίδιο δωμάτιο (π.χ. δωμάτιο 856)· οι διορθώσεις εμποδίζουν
  τις νέες, δεν καθαρίζουν τις παλιές.
- Όλα τα ξένα κλειδιά του αρχικού σχήματος είναι `NOT VALID` και δύο `CHECK` καλούν συναρτήσεις που διαβάζουν άλλους
  πίνακες· δεν αλλάχτηκαν.
- Το 4.4 επιστρέφει ελάχιστα αποτελέσματα επειδή στο dataset το `totalamount` είναι NULL σε 6206 από τις 6214 κρατήσεις.

## Η εφαρμογή Java (φάση Β)

Δεν χρειάζεται εγκατεστημένη Java: η εφαρμογή μεταγλωττίζεται και τρέχει μέσα σε container με Maven
(την πρώτη φορά κατεβαίνουν η εικόνα και ο οδηγός JDBC, περίπου ένα λεπτό).

```powershell
docker compose run --rm app
```

Στις ερωτήσεις σύνδεσης δώστε:

| Ερώτηση | Απάντηση |
|---|---|
| Database address | `db` |
| Database name | `hotel` |
| Username | `postgres` |
| Password | η τιμή της `POSTGRES_PASSWORD` (προεπιλογή `local_dev_only`) |

Αναμένεται `Connection successful!` και το κεντρικό μενού. Ενδεικτική διαδρομή: `1`, πρόθεμα `ram`, ξενοδοχείο `1`
(Ramblewood Inn), μετά `1` με πρόθεμα `a` (3 πελάτες), ή `3` με ημερομηνίες `2030-05-01` και `2030-05-04` (11 ελεύθερα
δωμάτια) για νέα κράτηση. Έξοδος με `0` και μετά `2`.

Για κρατήσεις μέσα από την εφαρμογή πρέπει να έχουν εφαρμοστεί οι [διορθώσεις](#διορθώσεις): αλλιώς το sequence των
κρατήσεων δίνει id που υπάρχει ήδη.

Με δική σας Java 17+ και Maven, από τον φάκελο `Phase2`: `mvn compile exec:java`, με διεύθυνση `127.0.0.1:5433`.

Τι άλλαξε σε σχέση με την παράδοση (ο αρχικός κώδικας είναι στο branch `original`):

- Όλα τα ερωτήματα είναι `PreparedStatement` με παραμέτρους. Πριν, ό,τι πληκτρολογούσε ο χρήστης κολλούσε μέσα στο
  κείμενο του SQL (SQL injection).
- Η ενημέρωση κράτησης δουλεύει: πριν εκτελούνταν με `executeQuery`, χωρίς εισαγωγικά στις ημερομηνίες, χωρίς κενό
  πριν το `WHERE` και χωρίς `commit`.
- Το μενού ακολουθεί την εκφώνηση (επιλογή ξενοδοχείου με αύξοντα αριθμό, υπο-ερωτήματα i, ii, iii, `0` για επιστροφή)
  και τερματίζει κανονικά. Προστέθηκε το υπο-ερώτημα iii (διαθέσιμα δωμάτια και νέα κράτηση), που έλειπε.
- Το `StandardInputRead.java` ξαναγράφτηκε, γιατί από την παράδοση είχε μείνει μόνο το `.class`.
- Προστέθηκε `pom.xml` για μεταγλώττιση με τον οδηγό JDBC της PostgreSQL.

## Σταμάτημα και καθάρισμα

| Εντολή | Τι κάνει | Τα δεδομένα |
|---|---|---|
| `docker compose stop` | σταματά το container | μένουν |
| `docker compose start` | το ξαναξεκινά | — |
| `docker compose down` | σβήνει container και δίκτυο | μένουν (στο volume `hotel-db_hotel-db-data`) |
| `docker compose down -v` | σβήνει και τα volumes (βάση και cache του Maven) | **χάνονται** |

Καθαρή επανεκκίνηση από το backup (σβήνει ό,τι αλλαγές έχετε κάνει στη βάση):

```powershell
docker compose down -v
```

```powershell
docker compose up -d --wait
```

και μετά ξανά το βήμα 3 της γρήγορης εκκίνησης (και, αν θέλετε, το `apply.sql` των διορθώσεων).

## Αν κάτι δεν πάει καλά

| Σύμπτωμα | Αιτία και λύση |
|---|---|
| `port is already allocated` στο `up` | Η θύρα 5433 είναι πιασμένη. Ορίστε `HOTEL_DB_PORT=5434` στο `.env`. |
| `already exists` στο `pg_restore` | Το backup έχει ήδη φορτωθεί. Κάντε καθαρή επανεκκίνηση. |
| `no configuration file provided` | Δεν είστε στον φάκελο του project (βήμα 1). |
| `trailing junk after numeric literal` | Χάθηκαν τα διπλά εισαγωγικά (βλ. παραδείγματα κλήσης). |
| `error during connect` / `docker daemon is not running` | Ανοίξτε το Docker Desktop και περιμένετε να ξεκινήσει. |
