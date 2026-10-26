# Portfolio 3: Transactions and Concurrency (Carbon)

## Overview


This portfolio explains how PostgreSQL prevents errors in financial records when several transactions are run simultaneously. The project uses the Carbon ledger stored in the `carbon_db` database, which runs on PostgreSQL 18.6. It covers the work I carried out, including building a safe transfer function, demonstrating how commits and rollbacks work, conducting four experiments on transaction concurrency, running a pgbench stress test comparing ordered and unordered locking, and carrying out my own experiment on lock timeouts.

## Folder structure

- `Oluwarotimi_Oluwafemi_301930838_P3_01_transfer_function.sql`: I created two versions of the transfer function: one that handles locking safely and another with intentional flaws to help me understand how deadlocks happen.

- `Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql`: To make the demonstrations easier to follow, I created two test wallets, each starting with a balance of 500.00.

- `Oluwarotimi_Oluwafemi_301930838_P3_03_commit_rollback_demo.sql`: I used five practical examples to understand how PostgreSQL saves changes with COMMIT and reverses them with ROLLBACK.

- `Oluwarotimi_Oluwafemi_301930838_P3_05_stress_ordered.pgbench`: The workload that calls the safe transfer function, which locks accounts in id order.

- `Oluwarotimi_Oluwafemi_301930838_P3_06_stress_unordered.pgbench`: This is the same workload, but it calls the flawed function, so opposite transfers can deadlock.

- `Oluwarotimi_Oluwafemi_301930838_P3_07_integrity_check.sql`: The integrity check confirmed that no money had been lost or created unexpectedly.

- `Oluwarotimi_Oluwafemi_301930838_P3_11_own_experiment_notes.md`: My own experiment on lock timeouts: my prediction, what actually happened, and why.

- `Oluwarotimi_Oluwafemi_301930838_P3_analysis.md`: This is my written analysis of what happened and why it happened in each experiment.

- `output/`: the saved results (commit/rollback output, pgbench results and integrity check files).
- `screenshots/`: the screenshots that serve as evidence for each step.

## How to reproduce

1. First I loaded the safe transfer function and the flawed copy into the database. I run this inside psql:

   ```sql
   \i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_01_transfer_function.sql
   ```

2. I created the demo wallets. Command:
 ```sql
\i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
  ```

3. Run the commit/rollback demo. Run it from PowerShell, not inside psql. Command:
```sql
$env:PGPASSWORD = '<your password>'
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d carbon_db -a -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_03_commit_rollback_demo.sql -o portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_03_commit_rollback_output.txt
```

4. Next I ran the four concurrency experiments by hand. For each one I opened separate psql sessions side by side (A and B, plus a third session C for Experiment 2) and typed the steps in the order set out in the guide. Before each experiment I reset both demo wallets to 500.00 by running this in session A:

   ```sql
   \i portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_02_demo_setup.sql
   ```

   The experiments were: Experiment 1 (lost update with no locking), Experiment 2 (the fix using `SELECT ... FOR UPDATE`), Experiment 3 (READ COMMITTED and REPEATABLE READ isolation levels) and Experiment 4 (deadlock). Each session was started like this:

   ```powershell
   $env:PGPASSWORD = '<your password>'
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d carbon_db
   ```

5. Then I added an index on the ledger, because the integrity check was too slow without it, and ran the integrity check to record the baseline before any stress test. First, inside psql:

   ```sql
   CREATE INDEX IF NOT EXISTS idx_ledger_account_created ON ledger_entries (account_id, created_at DESC, entry_id DESC);
   ANALYZE ledger_entries;
   ```

   Then, from PowerShell:

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d carbon_db -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_07_integrity_check.sql -o portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_integrity_before.txt
   ```

6. Next I ran the stress test with the ordered workload, which calls the safe transfer function, and saved the result:

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\pgbench.exe" -U postgres -h localhost -n -c 10 -j 4 -t 200 -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_05_stress_ordered.pgbench carbon_db | Tee-Object portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_stress_ordered.txt
   ```

   Then I ran the integrity check again:

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d carbon_db -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_07_integrity_check.sql -o portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_integrity_after_ordered.txt
   ```

7. Finally I ran the same stress test with the unordered workload, which calls the flawed function. This run showed deadlocks and failed transactions:

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\pgbench.exe" -U postgres -h localhost -n -c 10 -j 4 -t 200 -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_06_stress_unordered.pgbench carbon_db | Tee-Object portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_stress_unordered.txt
   ```

   Then I ran the integrity check a last time and saved the result:

   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -h localhost -d carbon_db -f portfolio-3-transactions-concurrency/Oluwarotimi_Oluwafemi_301930838_P3_07_integrity_check.sql -o portfolio-3-transactions-concurrency/output/Oluwarotimi_Oluwafemi_301930838_P3_integrity_after_unordered.txt
   ```

## Key findings

- **Lost update:** What stood out to me was that both sessions started with Alice’s balance at 500.00, and each updated it to 100.00. In the end, the balance remained at 100.0000, showing that one withdrawal had been lost without any error or warning.
- **Ordered locking:** What impressed me was that all 2,000 transfers completed successfully with 0 failures, while the system handled 3,515.17 transactions per second.
- **Unordered locking:** I was disappointed to see that 51 transfers failed due to deadlocks, leaving only 1,949 successful transfers and reducing throughput to 48.87 transactions per second.
- **Integrity:** I was glad to see that the total amount remained unchanged at 1000000001000.0000, with zero unbalanced transactions, mismatched accounts, or stuck pending transactions across all three checks, even after the deadlocks.

## Evidence


- `Oluwarotimi_Oluwafemi_301930838_P3_01_function_test.png`: The same transaction ID returned twice, confirming that the retry did not transfer the money a second time..

- `Oluwarotimi_Oluwafemi_301930838_P3_02_commit_rollback_output.png and P3_02b_commit_rollback_output.png`: I saved the output for all five demonstrations in the `02/02b` file, making it easier to review how commits, rollbacks, failures, idempotency, and savepoints behaved during my tests.

- `Oluwarotimi_Oluwafemi_301930838_P3_03_exp1_lost_update.png`: I observed that both sessions read the same starting balance of 500, but the final balance dropped to 100, showing how concurrent transactions can lead to a lost withdrawal.

- `Oluwarotimi_Oluwafemi_301930838_P3_04_exp2_waiting.png, P3_04b_exp2_waiting.png`: I noticed Session B was stuck waiting, while Session C clearly showed the lock wait, helping me understand how one transaction can hold up another.

- `Oluwarotimi_Oluwafemi_301930838_P3_05_exp2_unblocked.png`: Session B resumed after the lock was released and correctly read the updated balance of 100.0000.

- `Oluwarotimi_Oluwafemi_301930838_P3_06_exp3a_read_committed.png`: I observed that Session A read a balance of `500` and later saw it change to `400` within the same transaction, helping me understand how balances can change between reads.

- `Oluwarotimi_Oluwafemi_301930838_P3_07_exp3b_repeatable_read.png`: Session A kept seeing a balance of 500 even after Session B committed its change. When A then tried to update the same row, PostgreSQL rejected it with the error "could not serialize access due to concurrent update", which shows that REPEATABLE READ stops a transaction from overwriting data that changed after its snapshot.

- `Oluwarotimi_Oluwafemi_301930838_P3_08_exp4_deadlock.png`: I captured the “deadlock detected” error, which helped me see how conflicting lock requests can prevent transactions from completing successfully.

- `Oluwarotimi_Oluwafemi_301930838_P3_09_stress_results.png and P3_09b_stress_results.png`: It compare the ordered and unordered `pgbench` results and see how much of a difference the locking approach made to performance and transaction success.

- `Oluwarotimi_Oluwafemi_301930838_P3_10_integrity.png, P3_10b_integrity.png, P3_10c_integrity.png`: I compared the before, after-ordered, and after-unordered integrity files and confirmed that the financial records remained consistent throughout the tests. 

- `Oluwarotimi_Oluwafemi_301930838_P3_11_own_experiment.png`: I captured the lock timeout error, which helped me understand how a transaction can be forced to stop waiting when a lock is held for too long.


## Reflection and AI-use declaration