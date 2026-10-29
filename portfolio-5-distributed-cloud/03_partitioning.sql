
-- Carbon Portfolio 5: Hash partitioning experiment
-- Run only against the isolated Carbon Docker primary.
-- This creates a separate partitioned copy; it does not alter ledger_entries.

\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE ledger_entries_partitioned (
    entry_id BIGINT,
    transaction_id BIGINT NOT NULL,
    account_id BIGINT NOT NULL,
    direction TEXT NOT NULL CHECK (direction IN ('DEBIT', 'CREDIT')),
    amount NUMERIC(19,4) NOT NULL,
    balance_after NUMERIC(19,4) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
) PARTITION BY HASH (account_id);

CREATE TABLE ledger_entries_p0
    PARTITION OF ledger_entries_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);

CREATE TABLE ledger_entries_p1
    PARTITION OF ledger_entries_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);

CREATE TABLE ledger_entries_p2
    PARTITION OF ledger_entries_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);

CREATE TABLE ledger_entries_p3
    PARTITION OF ledger_entries_partitioned
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

INSERT INTO ledger_entries_partitioned (
    entry_id,
    transaction_id,
    account_id,
    direction,
    amount,
    balance_after,
    created_at
)
SELECT
    entry_id,
    transaction_id,
    account_id,
    direction,
    amount,
    balance_after,
    created_at
FROM ledger_entries;

COMMIT;

\echo '=== Carbon: source and partitioned row counts ==='

SELECT
    (SELECT COUNT(*) FROM ledger_entries) AS source_rows,
    (SELECT COUNT(*) FROM ledger_entries_partitioned) AS partitioned_rows;

\echo '=== Carbon: rows in each partition ==='

SELECT 'ledger_entries_p0' AS partition_name, COUNT(*) AS row_count
FROM ledger_entries_p0
UNION ALL
SELECT 'ledger_entries_p1', COUNT(*) FROM ledger_entries_p1
UNION ALL
SELECT 'ledger_entries_p2', COUNT(*) FROM ledger_entries_p2
UNION ALL
SELECT 'ledger_entries_p3', COUNT(*) FROM ledger_entries_p3
ORDER BY partition_name;

\echo '=== Carbon: partition pruning demonstration ==='

EXPLAIN (COSTS OFF)
SELECT *
FROM ledger_entries_partitioned
WHERE account_id = 1001;

\echo '=== Carbon: partition pruning with execution statistics ==='

EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT *
FROM ledger_entries_partitioned
WHERE account_id = 1001;
