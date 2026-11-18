-- Εφαρμόζει όλες τις διορθώσεις πάνω στη βάση που προέκυψε από το backup.
-- Εκτέλεση (όλα ή τίποτα, χάρη στο --single-transaction):
--   docker compose exec db psql -U postgres -d hotel -v ON_ERROR_STOP=1 --single-transaction -f /sql/fixes/apply.sql

\ir 01_bugfixes.sql
\ir 02_before_roombooking_update.sql
\ir 03_weekly_plan_view.sql
\ir 04_query_functions.sql
