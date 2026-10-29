
#!/usr/bin/env bash
set -e

psql \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set=replication_user="$REPLICATION_USER" \
  --set=replication_password="$REPLICATION_PASSWORD" \
  --set=ON_ERROR_STOP=1 <<'SQL'
CREATE ROLE replicator
  WITH REPLICATION
  LOGIN
  PASSWORD :'replication_password';

GRANT CONNECT ON DATABASE carbon_db TO replicator;

SQL

echo "Carbon primary replication role initialized."
