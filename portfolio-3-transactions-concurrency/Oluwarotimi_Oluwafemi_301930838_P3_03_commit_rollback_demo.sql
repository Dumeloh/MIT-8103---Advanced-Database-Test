-- Portfolio 3: COMMIT, ROLLBACK, failure, idempotency, SAVEPOINT demos
-- Run from an ordinary terminal with psql -a, not from pgAdmin.

\echo '=== Reset demo wallets ==='
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql

\echo '=== DEMO 1: COMMIT ==='
BEGIN;
UPDATE accounts SET balance = balance - 100 WHERE account_number = '9000000001';
UPDATE accounts SET balance = balance + 100 WHERE account_number = '9000000002';
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;
COMMIT;
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;

\echo '=== DEMO 2: ROLLBACK ==='
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
BEGIN;
SELECT transfer_funds('9000000001','9000000002',50.00,'demo2-rollback-key');
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;
ROLLBACK;
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;
SELECT count(*) AS rows_for_key FROM transactions WHERE idempotency_key = 'demo2-rollback-key';

\echo '=== DEMO 3: FAILURE (insufficient funds) ==='
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
SELECT transfer_funds('9000000001','9000000002',9999.00,'demo3-fail-key');
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;
SELECT count(*) AS rows_for_key FROM transactions WHERE idempotency_key = 'demo3-fail-key';

\echo '=== DEMO 4: IDEMPOTENCY ==='
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
SELECT transfer_funds('9000000001','9000000002',25.00,'demo4-idem-key') AS first_call;
SELECT transfer_funds('9000000001','9000000002',25.00,'demo4-idem-key') AS second_call;
SELECT count(*) AS rows_for_key FROM transactions WHERE idempotency_key = 'demo4-idem-key';
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;

\echo '=== DEMO 5: SAVEPOINT ==='
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
BEGIN;
SELECT transfer_funds('9000000001','9000000002',10.00,'demo5-first-key');
SAVEPOINT after_first;
SELECT transfer_funds('9000000001','9000000002',9999.00,'demo5-second-key');
ROLLBACK TO SAVEPOINT after_first;
COMMIT;
SELECT account_number, balance FROM accounts WHERE account_number IN ('9000000001','9000000002') ORDER BY account_number;
SELECT idempotency_key, status FROM transactions WHERE idempotency_key LIKE 'demo5-%' ORDER BY idempotency_key;