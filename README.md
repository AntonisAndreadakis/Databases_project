# Βάση δεδομένων κρατήσεων ξενοδοχείων (ΠΛΗ303)

Εργασία του μαθήματος ΠΛΗ303 «Βάσεις Δεδομένων», Πολυτεχνείο Κρήτης, εαρινό εξάμηνο 2020-2021.
Μια βάση PostgreSQL για κρατήσεις ξενοδοχείων, με συναρτήσεις PL/pgSQL, triggers, μία όψη και μια
μικρή εφαρμογή Java (JDBC).

Το README αυτό δείχνει πώς στήνεται η βάση τοπικά με Docker και πώς ελέγχεται η δομή της.
Όλες οι εντολές είναι για **PowerShell σε Windows** και έχουν δοκιμαστεί με Docker 29 και την εικόνα `postgres:16`.

## Περιεχόμενα φακέλου

| Διαδρομή | Τι είναι |
|---|---|
| `Phase1/` | Τα SQL της φάσης Α, όπως γράφτηκαν (σημειώσεις εργασίας, όχι εκτελέσιμα scripts) |
| `Phase2/project_base.backup` | Αντίγραφο της βάσης (`pg_dump` custom format, PostgreSQL 11) με σχήμα, δεδομένα, συναρτήσεις και triggers |
| `Phase2/src/db_phase_B/DbApp.java` | Η εφαρμογή JDBC της φάσης Β |
| `docker-compose.yml` | Τοπική PostgreSQL 16 για το project |
| `db/checks/01_structure.sql` | Ερωτήματα ελέγχου της δομής |
| `db/checks/02_examples.sql` | Παραδείγματα κλήσης των συναρτήσεων |

Η «αλήθεια» για το τι παραδόθηκε είναι το backup: περιέχει και συναρτήσεις που δεν υπάρχουν στα αρχεία του `Phase1/`.

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

| Έλεγχος | Αναμένεται |
|---|---|
| 1. Πίνακες | 17 |
| 2. Στήλες | 79 |
| 3. Πρωτεύοντα κλειδιά και UNIQUE | 22 (17 PK, 5 UNIQUE) |
| 4. Ξένα κλειδιά | 25 |
| 5. Περιορισμοί CHECK | 5 |
| 6. Τύποι ENUM | 7 |
| 7. Sequences | 5 |
| 8. Ευρετήρια | 37 |
| 9. Συναρτήσεις | 29 |
| 10. Triggers | 9 |
| 11. Όψεις | 1 (`6_1_availableRoomsByHotel`) |
| 12. Πλήθος γραμμών | βλ. παρακάτω |

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
| `"6_1_availableRoomsByHotel"` | 0 γραμμές (βλ. σημείωση) |

Δύο πράγματα που αξίζει να ξέρετε:

- **Τα ονόματα των συναρτήσεων ξεκινούν με ψηφίο, άρα θέλουν πάντα διπλά εισαγωγικά.**
  Το Windows PowerShell 5.1 όμως αφαιρεί τα διπλά εισαγωγικά όταν περνά το όρισμα του `-c` στο `docker`, και η κλήση
  αποτυγχάνει με `trailing junk after numeric literal`. Γι' αυτό τρέξτε τις κλήσεις είτε από αρχείο `.sql` (όπως παραπάνω)
  είτε μέσα στο διαδραστικό `psql`:

  ```sql
  SELECT * FROM "4_2_countAvgAge"('Studio');
  ```

- **Οι κρατήσεις του dataset καλύπτουν 13/01/2021 έως 31/05/2022.** Ό,τι συγκρίνει με τη σημερινή ημερομηνία
  (`current_date`) βλέπει πλέον όλες τις κρατήσεις ως παρελθούσες, γι' αυτό η όψη 6.1 επιστρέφει 0 γραμμές.

Για δικά σας ερωτήματα, προσθέστε ένα αρχείο `.sql` στον φάκελο `db/` και τρέξτε το με `-f /sql/<αρχείο>.sql`
(ο φάκελος `db/` φαίνεται μέσα στο container ως `/sql`, μόνο για ανάγνωση).

## Σταμάτημα και καθάρισμα

| Εντολή | Τι κάνει | Τα δεδομένα |
|---|---|---|
| `docker compose stop` | σταματά το container | μένουν |
| `docker compose start` | το ξαναξεκινά | — |
| `docker compose down` | σβήνει container και δίκτυο | μένουν (στο volume `hotel-db_hotel-db-data`) |
| `docker compose down -v` | σβήνει και το volume | **χάνονται** |

Καθαρή επανεκκίνηση από το backup (σβήνει ό,τι αλλαγές έχετε κάνει στη βάση):

```powershell
docker compose down -v
```

```powershell
docker compose up -d --wait
```

και μετά ξανά το βήμα 3 της γρήγορης εκκίνησης.

## Αν κάτι δεν πάει καλά

| Σύμπτωμα | Αιτία και λύση |
|---|---|
| `port is already allocated` στο `up` | Η θύρα 5433 είναι πιασμένη. Ορίστε `HOTEL_DB_PORT=5434` στο `.env`. |
| `already exists` στο `pg_restore` | Το backup έχει ήδη φορτωθεί. Κάντε καθαρή επανεκκίνηση. |
| `no configuration file provided` | Δεν είστε στον φάκελο του project (βήμα 1). |
| `trailing junk after numeric literal` | Χάθηκαν τα διπλά εισαγωγικά (βλ. παραδείγματα κλήσης). |
| `error during connect` / `docker daemon is not running` | Ανοίξτε το Docker Desktop και περιμένετε να ξεκινήσει. |
