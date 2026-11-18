#!/bin/sh
# Ξαναφτιάχνει το db/mysql/init/02_data.sql από το backup της PostgreSQL.
# Τρέχει ΜΕΣΑ στο container hotel-db (βλ. README, «Αναπαραγωγή του αρχείου δεδομένων»):
#
#   docker compose exec db sh /sql/mysql/tools/export_from_postgres.sh
#   docker compose cp db:/tmp/02_data.sql db/mysql/init/02_data.sql
#
# Κάνει restore του backup σε προσωρινή βάση (ώστε να μην εξαρτάται από ό,τι έχει αλλάξει στη
# βάση hotel), βγάζει τα δεδομένα ως INSERT και τα προσαρμόζει στη σύνταξη της MySQL.
set -eu

TMP_DB=hotel_export
OUT=/tmp/02_data.sql
export PGUSER=postgres

dropdb --if-exists "$TMP_DB"
createdb "$TMP_DB"
pg_restore -d "$TMP_DB" --no-owner --no-privileges /backup/project_base.backup

{
    cat <<'EOF'
-- Δεδομένα της βάσης. ΠΑΡΑΓΕΤΑΙ από το db/mysql/tools/export_from_postgres.sh - μην το αλλάζετε με το χέρι.
-- Πηγή: Phase2/project_base.backup (η παράδοση του Μαΐου 2021).
SET NAMES utf8mb4;
SET @old_sql_mode = @@sql_mode;
SET sql_mode = 'ANSI_QUOTES,NO_BACKSLASH_ESCAPES,NO_AUTO_VALUE_ON_ZERO';
SET FOREIGN_KEY_CHECKS = 0;
SET UNIQUE_CHECKS = 0;
SET autocommit = 0;

EOF
    # --inserts: εντολές INSERT με ονόματα στηλών· το bytea '\x..' γίνεται x'..', φεύγει το «public.»
    # και ό,τι δεν είναι INSERT (SET, setval, σχόλια).
    pg_dump -d "$TMP_DB" --data-only --column-inserts --rows-per-insert=500 --no-owner --no-privileges \
        | sed -n '/^INSERT INTO /,/;$/p' \
        | sed -e 's/^INSERT INTO public\./INSERT INTO /' \
              -e "s/'\\\\x\([0-9a-fA-F]*\)'/x'\1'/g"
    cat <<'EOF'

COMMIT;
SET autocommit = 1;
SET UNIQUE_CHECKS = 1;
SET FOREIGN_KEY_CHECKS = 1;
SET sql_mode = @old_sql_mode;
EOF
} > "$OUT"

dropdb "$TMP_DB"
echo "Wrote $OUT: $(grep -c '^INSERT INTO ' "$OUT") INSERT statements, $(wc -c < "$OUT") bytes"
