
#!/usr/bin/env bash
set -euo pipefail

export PGPASSWORD="${PGPASSWORD:?PGPASSWORD is required}"

echo "Waiting for Carbon primary to accept connections..."

until pg_isready -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; do
  sleep 2
done

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  echo "Initializing Carbon streaming replica..."

  rm -rf "${PGDATA:?}/"*

  until pg_basebackup \
    -h "$PGHOST" \
    -p "$PGPORT" \
    -U "$PGUSER" \
    -D "$PGDATA" \
    -Fp \
    -Xs \
    -P \
    -R
  do
    echo "Base backup failed; retrying in 5 seconds..."
    sleep 5
  done

  chmod 700 "$PGDATA"
fi

echo "Starting Carbon PostgreSQL replica..."

chown -R postgres:postgres "$PGDATA"
exec gosu postgres postgres -D "$PGDATA" -c hot_standby=on
