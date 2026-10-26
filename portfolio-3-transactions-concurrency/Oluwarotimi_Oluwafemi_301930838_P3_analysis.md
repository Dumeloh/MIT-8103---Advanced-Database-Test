# PostgreSQL Transactions, Concurrency and Stress Testing

## 1. Environment

I carried out these experiments on my Windows laptop using PostgreSQL 18.6 and pgAdmin 4, with `carbon_db` as my working database. The default transaction isolation level was `READ COMMITTED`, which means that each statement normally sees data committed before that statement begins.

Before running the tests, my database contained 6,001 accounts, 206,096 transactions and 404,162 ledger entries. These seed values gave me a realistic starting point for examining how PostgreSQL handles transfers, concurrent requests and transaction failures.

I also created an index called `idx_ledger_account_created`. I added it because the ledger integrity check was taking too long without it. This reminded me that database correctness is important, but performance matters too. A system can protect financial records and still frustrate users if its queries take too long to finish.

## 2. The Transfer Function

I designed the transfer function as a sequence of five steps. The order matters because a transfer must protect customers' money, handle simultaneous requests safely and avoid leaving the database in an inconsistent state.

**Step 1: Check the idempotency key first**

The function first checks whether the request's idempotency key has already been used. If it has, the function should return the previous result instead of processing the same transfer again.

This is particularly important when a network connection drops. A customer may press the transfer button again because they are unsure whether the first request succeeded. Without this check, the same payment could be processed twice, creating unnecessary stress and potentially costing the customer money.

This step supports **consistency** by helping prevent duplicate financial operations. It also relies on a unique database constraint to prevent two requests from successfully creating the same key.

**Step 2: Resolve the account IDs**

Next, the function identifies the sender's and receiver's account IDs. At this stage, it does not acquire row locks.

Resolving the accounts before locking them helps keep the locking section focused on the records that actually need protection. This reduces unnecessary work while preparing the function for the next step.

This supports efficient transaction processing, while the account lookups and subsequent checks help maintain **consistency**.

**Step 3: Lock accounts in a consistent order**

The function locks the two accounts in ascending account-ID order, regardless of who is sending money and who is receiving it.

This ordering is important because two customers might transfer money to each other at the same time. If one transaction locks account A and waits for account B, while another locks account B and waits for account A, both can end up waiting for each other.

By acquiring the locks in the same order, the function reduces this risk of deadlocks.

This step supports **isolation**, helping concurrent transfers work safely without interfering with one another. It also improves reliability by reducing avoidable transaction failures.

**Step 4: Read balances after acquiring the locks**

Once both accounts are locked, the function reads their balances and checks whether the sender has enough money to complete the transfer.

Reading the balances after acquiring the locks is essential. If the function reads a balance too early, another transaction could change it before the transfer is applied. The function might then work with an outdated value and overwrite a more recent update.

The locks help prevent this lost-update problem for the protected account rows. The balance check also helps prevent a customer from spending more money than is available.

This step primarily protects **isolation and consistency**.

**Step 5: Update balances, record the ledger entries and complete the transaction**

Finally, the function updates the sender's balance, updates the receiver's balance, inserts the corresponding `DEBIT` and `CREDIT` ledger entries, and marks the transaction as `COMPLETED`.

All these changes must take place within the same database transaction. If an operation fails before the transaction commits, PostgreSQL should roll back the changes rather than leave the sender debited without the receiver being credited.

This step demonstrates **atomicity**: either all the financial changes succeed together, or none of them remain committed. Consistent ledger entries also support **consistency**, while the database's durability guarantees protect committed results.

Together, these five steps help make a transfer safer, more predictable and easier to investigate when something goes wrong.

## 3. Commit and Rollback: What Demos 1–5 Showed

The commit and rollback demonstrations helped me understand that a database transaction is more than a collection of SQL statements. It is a way of protecting related changes so that the database does not end up in an uncertain financial state.

The output file recorded several important results:

- **After `COMMIT`:** The balances were 400 and 600. The transfer was saved, and the changes remained in place after the transaction finished.
- **After `ROLLBACK`:** The balances returned to 500 and 500. This showed that PostgreSQL could undo the changes made within an uncommitted transaction.
- **Failed transaction:** The `rows_for_key` result was 0, confirming that the failed operation left no transaction row for that idempotency key.
- **Idempotent transaction:** The `rows_for_key` result was 1, showing that repeating the same request did not create a second transaction row.
- **After the `SAVEPOINT` demonstration:** The balances were 490 and 510. This showed how a savepoint could be used to roll back part of a transaction while retaining earlier changes that were still valid.

These results helped me appreciate the value of controlling exactly when changes become permanent. If a transfer encounters an error, the database should not leave customers wondering where their money went.

I also noticed gaps in the generated transaction IDs: 206100 and 206102 were missing. This is normal when PostgreSQL identity columns or sequences allocate IDs to operations that later fail or are rolled back. Sequence values are not normally returned just because a transaction rolls back, so gaps do not necessarily indicate missing transactions or corrupted financial records.

The important lesson is that transaction IDs are identifiers, not a guarantee that every number must correspond to a committed row.

## 4. Experiments 1–4: Concurrency Problems and Their Solutions

### Experiment 1: Lost update

**The problem:** Two concurrent transactions attempted to withdraw 400 from an account that initially held 500.

**What I observed:** The final balance was 100, even though both transactions completed without an error. Each transaction had effectively worked from the same original balance, allowing one update to overwrite the other.

This was particularly important because the database did not necessarily raise an error to warn me that the result was wrong. A transaction can complete successfully at the SQL level while still producing an incorrect business outcome.

**The fix:** I used explicit row locking with `SELECT ... FOR UPDATE` before reading and changing the balance. This ensures that competing operations on the same account cannot both proceed using the same unlocked balance.

### Experiment 2: Using `FOR UPDATE`

**The problem:** Concurrent transactions needed to access and change the same account safely.

**What I observed:** Transaction B had to wait while transaction A held the row lock. Once A completed, B continued and saw the updated balance of 100.

This showed me that PostgreSQL's locking mechanism can coordinate competing requests instead of allowing them to overwrite each other's changes.

**The fix:** Acquire the row lock before reading the balance and applying the withdrawal. This helps protect the account against lost updates and supports safe concurrent processing.

### Experiment 3a: Non-repeatable read

**The problem:** A transaction read a balance, another transaction changed and committed it, and the first transaction read the same row again.

**What I observed:** The first read returned 500, while the second returned 400. Under `READ COMMITTED`, each statement can see a newer committed version of the data.

This helped me understand why a transaction cannot assume that a value will remain unchanged simply because it read that value earlier.

**The fix:** Where a workflow requires a stable balance while making a decision, use appropriate row locking or a suitable isolation level. The correct choice depends on the business operation and how much concurrency the application needs.

### Experiment 3b: Serialization failure

**The problem:** A transaction attempted to update a row that had been changed by a concurrent transaction under serializable isolation.

**What I observed:** The transaction's snapshot continued to show 500, but its update failed with the message:

`could not serialize access due to concurrent update`

Unlike the non-repeatable read experiment, PostgreSQL did not simply allow the conflicting update to proceed. It rejected the transaction because the concurrent changes could not be safely reconciled with the serializable execution it was trying to guarantee.

**The fix:** The application should catch the serialization failure and retry the entire transaction from the beginning when appropriate. Retrying only the failed statement is not sufficient because the transaction's original decisions may have been based on an outdated snapshot.

### Experiment 4: Deadlock

**The problem:** Two transactions attempted to lock the same accounts in opposite orders.

**What I observed:** PostgreSQL reported:

`deadlock detected`

Each transaction was waiting for a lock held by the other, leaving neither able to continue.

**The fix:** I changed the locking strategy so that accounts are always locked in ascending account-ID order. This consistent order reduces the chance of two transfers waiting on each other in a cycle.

The experiments showed me that concurrency problems are not all the same. Some can silently produce incorrect results, while others cause PostgreSQL to block or reject a transaction. Each needs a deliberate solution.

## 5. Stress Test

I ran a stress test to compare transfers that acquired account locks in a consistent order with transfers that acquired them in an inconsistent order.

The results were:

| Run | Processed | Failed | TPS |
|---|---:|---:|---:|
| Ordered locking | 2,000/2,000 | 0 | 3,515.17 |
| Unordered locking | 1,949/2,000 | 51 | 48.87 |

The ordered run completed all 2,000 transfers without failures and achieved 3,515.17 transactions per second. In contrast, the unordered run completed 1,949 transfers, failed 51, and achieved 48.87 transactions per second.

This was a significant difference. It showed me how inconsistent locking can create serious contention and deadlocks, reducing the amount of useful work the database can complete. The ordered approach made the workload much more successful in this particular test.

### Ledger integrity results

The integrity checks also returned the following results:

| Integrity check | Result |
|---|---:|
| Total ledger amount | `1000000001000.0000` |
| First integrity discrepancy count | 0 |
| Second integrity discrepancy count | 0 |
| Third integrity discrepancy count | 0 |

All three discrepancy counts were zero in the output files. This indicated that the checks found no discrepancies in the conditions they tested, and the reported total ledger amount remained consistent with the test's expected result.

The ledger remained correct even during the unordered run because a failed transfer does not have to leave behind partial financial changes. When the transfer operations are correctly enclosed in a database transaction, PostgreSQL can roll back the changes from a transaction that fails. This prevents a failed transfer from leaving the sender debited without the corresponding credit or ledger records.

The important distinction is that **a failed transfer is not automatically an integrity failure**. It becomes a financial integrity problem if the system leaves behind incomplete or contradictory changes. My results showed that the tested integrity checks remained satisfied despite the failures, although they do not prove that every possible integrity problem is impossible.

## 6. My Own Experiment: Lock Timeout

For my own experiment, I examined the effect of setting `lock_timeout` to two seconds.

**My prediction:** I expected PostgreSQL to stop waiting when a transaction could not obtain a required lock within two seconds. Instead of allowing a blocked operation to wait indefinitely, the database would cancel the affected statement and return an error.

**What happened:** With the two-second timeout configured, an operation that waited too long for a lock was expected to fail with a lock-timeout error rather than continue waiting beyond the configured limit. The application could then catch the error and decide whether to retry or explain the problem to the user.

**Why it matters:** In a real application, a transaction waiting too long can hold up other work and leave users wondering whether their payments are going through. A lock timeout provides a limit on that waiting time and gives the application an opportunity to recover more gracefully.

However, a timeout is not the same as a fix for the underlying locking problem. The application still needs sensible locking rules, proper transaction handling and a controlled retry strategy.

*Note: The exact observed error text and elapsed time should be copied from the actual lock-timeout output before this section is submitted as experimental evidence.*

## 7. Limitations

Although these experiments helped me understand PostgreSQL's transaction and concurrency behaviour, there are limits to what I can conclude from testing ten clients on one laptop.

First, the results do not represent the performance of a production fintech platform. A laptop has limited processing power, memory, storage throughput and network capacity compared with a properly sized production environment.

Second, the workload did not reproduce every condition found in a real payment service. Production systems may have hundreds or thousands of concurrent users, external banking delays, network failures, application restarts and more complex transaction patterns.

Third, the measured throughput depends on the hardware, PostgreSQL configuration, query design, data volume and test method. The figures are useful for comparing the two locking strategies under the same test conditions, but they should not be treated as guaranteed production performance.

Finally, the integrity checks only prove that the conditions tested by those checks were satisfied. More extensive testing would be needed to cover every possible transaction failure and financial edge case.

One improvement I would make before deploying this design in production is to implement a controlled retry loop for deadlocks and serialization failures. The application should recognise the relevant PostgreSQL errors, roll back the failed transaction, wait briefly with a small random delay, and retry the entire transaction a limited number of times. If the retries are exhausted, it should log the failure and return a clear message rather than leaving the customer uncertain.

The retry mechanism must also preserve idempotency so that a repeated request cannot cause a transfer to be processed twice.

## 8. Reflection

The biggest surprise for me was that PostgreSQL could allow two withdrawals to finish without reporting an error and still leave an incorrect balance. Before these experiments, I thought that if a query completed successfully, the result would automatically be safe. I now understand that successful execution and correct business behaviour are not always the same thing.

I was also surprised by how much the order of acquiring locks could affect the outcome. Using a consistent account-locking order made the stress test far more successful, while inconsistent ordering caused failures and a sharp drop in throughput. This helped me see that concurrency control is not just about adding locks; it is about designing a clear and consistent way for transactions to acquire them.

The commit, rollback and savepoint demonstrations also made the ACID properties easier to understand. They showed me how PostgreSQL can protect related financial changes, undo work that should not be committed, and preserve a clear record of completed operations.

If I were doing the experiments again, I would capture the exact output of each run, document the PostgreSQL settings and hardware conditions, and repeat the stress tests several times to see how consistent the results were. I would also add more failure scenarios and test the retry mechanism under concurrent load.

Overall, this work has given me a better understanding of why a reliable financial database needs more than well-designed tables. It also needs carefully ordered operations, appropriate isolation, atomic updates, clear recovery behaviour and strong integrity checks. Most importantly, these techniques protect the people who depend on the system to handle their money accurately and give them confidence that their transactions have been processed as expected.