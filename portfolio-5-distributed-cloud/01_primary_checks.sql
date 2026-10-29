
-- Carbon Portfolio 5: Primary server checks
-- Run this against the isolated Carbon Docker primary.

\echo '=== Carbon primary: database and server ==='

SELECT
    current_database() AS database_name,
    current_user AS connected_user,
    version() AS postgres_version;

\echo '=== Carbon primary: replication settings ==='

SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;

\echo '=== Carbon primary: replication role ==='

SELECT
    rolname,
    rolcanlogin,
    rolreplication
FROM pg_roles
WHERE rolname = 'replicator';

\echo '=== Carbon primary: connected replication clients ==='

SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn
FROM pg_stat_replication;

\echo '=== Carbon primary: replication slots ==='

SELECT
    slot_name,
    slot_type,
    active
FROM pg_replication_slots;
