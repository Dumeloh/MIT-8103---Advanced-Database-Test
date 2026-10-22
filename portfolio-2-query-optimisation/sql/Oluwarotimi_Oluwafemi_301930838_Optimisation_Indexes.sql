-- =====================================================================
-- MIT 8103: Advanced Database Systems — Continuous Assessment
-- Portfolio 2: Query Optimisation & Execution Plans
-- 
-- Candidate: Oluwafemi Emmanuel Oluwarotimi (Student ID: 301930838)
-- Institution: Miva Open University — Master of Information Technology
-- Database: Carbon / NairaPay Core Fintech Ledger System (carbon_db)
-- Engine: PostgreSQL 18 | Tool: pgAdmin 4
-- File: Oluwarotimi_Oluwafemi_301930838_Optimisation_Indexes.sql
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. FOREIGN KEY INDEXES (Relational Join & Referential Integrity)
-- In PostgreSQL, Primary Keys and UNIQUE constraints automatically generate
-- B-Tree indexes, but FOREIGN KEY constraints do NOT.
-- Without FK indexes, table joins (Q3, Q7) force sequential scans or
-- hash joins across massive ledger tables, and parent updates/deletes
-- incur full table locking.
-- ---------------------------------------------------------------------

-- Speed up customer account lookups (Q3) and prevent table locks on customers
CREATE INDEX IF NOT EXISTS idx_accounts_customer_id 
ON accounts (customer_id);

-- Speed up joining ledger entries by account (Q1, Q3, Q4, Q6)
CREATE INDEX IF NOT EXISTS idx_ledger_entries_account_id 
ON ledger_entries (account_id);

-- Speed up joining ledger entries by transaction (Q1, Q7, Q9)
CREATE INDEX IF NOT EXISTS idx_ledger_entries_transaction_id 
ON ledger_entries (transaction_id);


-- ---------------------------------------------------------------------
-- 2. QUERY 1: ACCOUNT STATEMENT (Customer Transaction History)
-- Business Workload: The customer opens "Transaction History" in mobile app.
-- Target: Fetch the 50 most recent ledger entries for a given account.
-- Optimization Pattern: Composite Index matching Equality + Sorting (ORDER BY DESC)
-- with covering INCLUDE columns to enable Index-Only Scans (zero heap access).
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_ledger_entries_account_statement
ON ledger_entries (account_id, created_at DESC)
INCLUDE (direction, amount, balance_after, transaction_id);


-- ---------------------------------------------------------------------
-- 3. QUERY 2: DAILY COMPLETED TRANSFER TOTALS (Finance Dashboard)
-- Business Workload: Daily aggregation of completed transfers over 30 days.
-- Optimization Pattern: Filtered / Partial Index.
-- Only 60-70% of transactions are COMPLETED TRANSFERs. Filtering out
-- other statuses (PENDING, FAILED) and types (DEPOSIT, BILL_PAYMENT)
-- drastically reduces index tree size, keeping it in buffer cache.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_transactions_daily_transfers
ON transactions (initiated_at, amount)
WHERE txn_type = 'TRANSFER' AND status = 'COMPLETED';


-- ---------------------------------------------------------------------
-- 4. QUERY 3: CUSTOMER LARGEST OUTGOING TRANSFERS (Dispute Resolution)
-- Business Workload: Customer support investigates a customer's top 10 debit transfers.
-- Optimization Pattern: Composite Index on ledger debits filtering by direction.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_ledger_entries_account_direction
ON ledger_entries (account_id, direction)
INCLUDE (transaction_id);


-- ---------------------------------------------------------------------
-- 5. QUERY 4: LARGE TRANSFER FRAUD DETECTION (Compliance Monitoring)
-- Business Workload: Daily compliance review of transfers >= 4,000 NGN in last 90 days.
-- Optimization Pattern: Partial B-Tree Index on high-magnitude debits.
-- Since large transfers represent < 5% of all ledger movements, a partial
-- index is 95% smaller than a full index and enables lightning-fast range scans.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_ledger_entries_large_debits
ON ledger_entries (created_at, account_id, amount)
WHERE direction = 'DEBIT' AND amount >= 4000;


-- ---------------------------------------------------------------------
-- 6. QUERY 6: BALANCE RECONCILIATION (Audit & End-of-Day Check)
-- Business Workload: Validates accounts.balance == latest ledger_entries.balance_after.
-- Optimization Pattern: Prefix Index matching DISTINCT ON (account_id) ORDER BY created_at DESC, entry_id DESC.
-- This allows PostgreSQL to eliminate the costly Sort node entirely,
-- reading the latest entry directly from the index head.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_ledger_entries_latest_balance
ON ledger_entries (account_id, created_at DESC, entry_id DESC)
INCLUDE (balance_after);


-- ---------------------------------------------------------------------
-- 7. QUERY 7: UNBALANCED JOURNALS AUDIT (Core Accounting Invariant)
-- Business Workload: Daily audit ensuring total debits == total credits per transaction.
-- Optimization Pattern: Partial index on audited transaction statuses.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_transactions_audit_status
ON transactions (transaction_id, txn_type, amount)
WHERE status IN ('COMPLETED', 'REVERSED');


-- ---------------------------------------------------------------------
-- 8. QUERY 8: NET MOVEMENT & REVERSAL-AWARE TREASURY REPORT
-- Business Workload: 90-day treasury report tracking net, reversed, and failed transfers.
-- Optimization Pattern: Composite covering index on transfer timeline.
-- ---------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_transactions_treasury_timeline
ON transactions (initiated_at, status, amount)
WHERE txn_type = 'TRANSFER';

COMMIT;
