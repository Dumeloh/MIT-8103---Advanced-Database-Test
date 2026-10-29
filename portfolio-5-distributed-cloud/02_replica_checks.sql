
-- Carbon Portfolio 5: Replica server checks
-- Run this against the isolated Carbon Docker replica.

\echo '=== Carbon replica: database and server ==='

SELECT
    current_database() AS database_name,
    current_user AS connected_user,
    pg_is_in_recovery() AS is_standby,
    version() AS postgres_version;

\echo '=== Carbon replica: read-only status ==='

SHOW hot_standby;
SHOW transaction_read_only;

\echo '=== Carbon replica: replay progress ==='

SELECT
    pg_last_wal_receive_lsn() AS last_received_lsn,
    pg_last_wal_replay_lsn() AS last_replayed_lsn,
    pg_last_xact_replay_timestamp() AS last_replay_timestamp;

\echo '=== Carbon replica: replication receiver ==='

SELECT
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    latest_end_lsn,
    latest_end_time,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;
