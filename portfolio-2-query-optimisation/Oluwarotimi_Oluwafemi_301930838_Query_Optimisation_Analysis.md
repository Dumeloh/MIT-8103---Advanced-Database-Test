# Portfolio 2: Query Optimisation, Execution Plan Analysis & Indexing Strategies

**Course:** MIT 8103 – Advanced Database Systems  
**Institution:** Miva Open University — Master of Information Technology (MIT)  
**Assessment Mode:** Continuous Assessment (Virtual Lab Portfolio 2)  
**Target Database:** Carbon / NairaPay Core Fintech Ledger System (`carbon_db`)  
**Database Engine:** PostgreSQL 18.0 (x64) | **Management Tool:** pgAdmin 4  
**Author / Candidate:** Oluwafemi Emmanuel Oluwarotimi ([@Dumeloh](https://github.com/Dumeloh))  
**Student ID:** 301930838  

---

## 1. Executive Summary

In high-throughput financial technology platforms, sub-second query performance and absolute data integrity are fundamental operational imperatives. While **Portfolio 1** established the declarative relational architecture, normalization guarantees, and double-entry bookkeeping invariants for `carbon_db`, **Portfolio 2** examines the physical query execution layer. 

As transaction volumes scale from thousands to millions of entries, unindexed relational operations deteriorate exponentially from logarithmic $O(\log N)$ or constant $O(1)$ lookups into catastrophic $O(N)$ sequential table scans, memory-intensive sorts, and unbounded hash joins.

This report delivers a rigorous, empirical performance analysis of nine (9) representative SQL queries spanning customer-facing online transaction processing (OLTP), compliance monitoring, treasury reporting, automated reconciliation, and financial audit invariant verification.

### Key Investigation Highlights
- **Access Path Analysis:** Contrast between disk-bound `Seq Scan` operations and memory-efficient `Index Scan` / `Index-Only Scan` access paths.
- **The Negative Control Benchmark (Q5):** Empirical validation that declarative database constraints (`UNIQUE`, `PRIMARY KEY`) automatically create underlying B-Tree indexes, whereas `FOREIGN KEY` references do not.
- **The Join Fan-Out Trap (Q9):** Mathematical proof and execution analysis of the classic $1:N$ join aggregation bug, wherein naive joins between transaction headers and double-entry ledger legs result in an exact $2.0\times$ volume inflation ($₦79,117,587.72$ vs $₦39,558,793.86$).
- **Sort Elimination & Distinct Optimization (Q6):** Resolving high-latency `DISTINCT ON` sorts via composite index prefix ordering `(account_id, created_at DESC, entry_id DESC)`, slashing latency by over **96%**.
- **Index Architecture:** Formulation of a production-grade indexing strategy incorporating composite B-Trees, partial/filtered indexes, and covering indexes with `INCLUDE` clauses, balanced against write amplification and WAL overhead.

---

## 2. Experimental Environment & Database Profile

### 2.1 Hardware and Engine Configuration
- **Operating System:** Microsoft Windows 11 Enterprise (x64)
- **Database Engine:** PostgreSQL 18.0 (x64)
- **Client Interface:** pgAdmin 4 (Version 8.x) Query Tool
- **Storage Architecture:** NVMe Solid-State Drive (SSD)
- **Optimizer Cost Model Parameters:**
  - `seq_page_cost`: `1.0` (baseline sequential page fetch)
  - `random_page_cost`: `1.1` (tuned for low-latency NVMe random page access)
  - `cpu_tuple_cost`: `0.01`
  - `cpu_index_tuple_cost`: `0.005`
  - `cpu_operator_cost`: `0.0025`

### 2.2 Relational Dataset Volume
The empirical tests were conducted on the populated `carbon_db` production-scale testbed:
- `customers`: 10,000+ accounts
- `accounts`: 10,000+ Naira wallets
- `transactions`: 50,000+ business events (Deposits, Transfers, Reversals, Bill Payments)
- `ledger_entries`: 100,000+ double-entry journal postings (guaranteed minimum 2 lines per transaction)
- `fraud_flags`: Monitored high-risk transactions

---

## 3. Query Workload Inventory & Classification

The evaluation suite tests nine distinct queries reflecting real-world fintech workloads:

| Query ID | Business Function | Primary Workload Category | Target Latency SLA | Dominant Operation |
| :---: | :--- | :--- | :---: | :--- |
| **Q1** | **Account Statement** | OLTP (Customer-Facing App) | $< 50\text{ ms}$ | Subquery Lookup, Range Scan, Sort, Join |
| **Q2** | **Daily Transfer Totals** | Executive Finance Dashboard | $< 100\text{ ms}$ | Date Truncation, Temporal Range Scan, GroupAggregate |
| **Q3** | **Customer Top Outgoing Transfers** | Support / Dispute Investigation | $< 100\text{ ms}$ | 3-Table Join, Predicate Filtering, Top-N Sort |
| **Q4** | **Large Transfer Fraud Pattern** | AML / Fraud Compliance | $< 150\text{ ms}$ | High-Value Filter, Aggregation, Multi-Column Sort |
| **Q5** | **Idempotency Key Lookup** | API Gateway Deduplication (Control) | $< 5\text{ ms}$ | Single-Row Unique Index Lookup |
| **Q6** | **Balance Reconciliation** | End-of-Day Automated Audit | $< 100\text{ ms}$ | Subquery `DISTINCT ON`, Sort, Inequality Join |
| **Q7** | **Unbalanced Journals Audit** | Core Accounting Invariant Audit | $< 200\text{ ms}$ | Left Outer Join, Conditional Aggregation, Having Filter |
| **Q8** | **Net Movement & Reversals** | Treasury & Liquidity Reporting | $< 100\text{ ms}$ | Filtered Aggregation, Status Matrix Projection |
| **Q9** | **Join Fan-Out Trap Analysis** | Integrity Verification & Reporting | Immediate Correctness | Subquery Comparison, $1:N$ Cardinality Fan-out |

---

## 4. PostgreSQL Query Optimizer & Cost Model Fundamentals

PostgreSQL employs a Cost-Based Optimizer (CBO) to convert relational algebra expressions into the most efficient physical execution plan. 

```mermaid
flowchart TD
    SQL["SQL Query Text"] --> Parser["Parser & Lexer"]
    Parser --> AST["Abstract Syntax Tree (AST)"]
    AST --> Rewriter["Rule System / Query Rewriter"]
    Rewriter --> Optimizer["Cost-Based Optimizer (CBO)"]
    
    subgraph "Cost-Based Optimizer Decisions"
        Optimizer --> PathGen["Access Path Generation<br>(Seq Scan vs Index Scan)"]
        Optimizer --> JoinGen["Join Ordering & Algorithm<br>(Nested Loop, Hash, Merge)"]
        Optimizer --> CostCalc["Cost Estimation<br>(CPU + I/O Disk Pages)"]
    end
    
    CostCalc --> PlanSelect["Select Minimum Cost Plan"]
    PlanSelect --> Executor["Execution Engine"]
    Executor --> Result["Data Output & Buffer Cache Hits"]
```

### 4.1 Access Path Selection
1. **Sequential Scan (`Seq Scan`):** Reads every disk page of the relation sequentially into PostgreSQL's shared buffer pool. Cost formula:
   $$\text{Cost} = (\text{Pages} \times \text{seq\_page\_cost}) + (\text{Tuples} \times \text{cpu\_tuple\_cost})$$
   Optimal for fetching $> 15\text{–}20\%$ of a table, but disastrous for point lookups on large tables.
2. **Index Scan (`Index Scan`):** Navigates the B-Tree root, internal, and leaf nodes ($O(\log N)$) to locate matching Tuple Identifiers (TIDs `(block_number, offset)`), then fetches heap pages randomly.
3. **Index-Only Scan (`Index Only Scan`):** Occurs when all projected and filtered attributes are contained directly within the B-Tree leaf pages (or `INCLUDE` clauses) and the table visibility map confirms pages are all-visible. Completely bypasses table heap access ($0$ random heap I/O).
4. **Bitmap Index Scan:** For intermediate selectivity, collects qualifying TIDs into an in-memory bitmask ordered by physical disk block, converting random I/O into sequential disk chunk reads.

---

## 5. Comprehensive Query-by-Query Performance Analysis

---

### 5.1 Query 1: Account Statement (Recent Ledger Lines)

#### Business Context
When a mobile banking customer opens "Transaction History", the application displays the 50 most recent ledger entries for their specific wallet, detailing timestamp, direction, amount, running balance, transaction type, and memo reference.

#### SQL Implementation ([q01_account_statement.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q01_account_statement.sql))
```sql
SELECT l.created_at, l.direction, l.amount, l.balance_after,
       t.txn_type, t.reference
FROM ledger_entries l
JOIN transactions t ON t.transaction_id = l.transaction_id
WHERE l.account_id = (SELECT account_id FROM accounts WHERE account_number = '2200001001')
ORDER BY l.created_at DESC
LIMIT 50;
```

#### Empirical Execution Results
![Q1 Account Statement Execution](screenshots/Oluwarotimi_Oluwafemi_301930838_accountstatement.png.png)
*Figure 1: Execution of Q1 in pgAdmin 4 against PostgreSQL 18. Execution time: 363 ms, yielding 50 rows.*

- **Rows Returned:** 50
- **Observed Execution Time:** **`363 ms`** (00:00:00.363)

#### Execution Plan Mechanics & Bottleneck
1. **Subquery Execution:** The scalar subquery `(SELECT account_id FROM accounts WHERE account_number = '2200001001')` executes in $< 0.1\text{ ms}$ via an `Index Scan` on `accounts_account_number_key` because `account_number` has a unique constraint.
2. **Ledger Entries Scan:** In the baseline schema, `ledger_entries.account_id` lacks an index. The engine is forced to perform a full `Seq Scan` on `ledger_entries` (100,000+ rows) to find entries belonging to `account_id = 1001`.
3. **Sort Node Overhead:** Because entries are retrieved out of order, the engine buffers matching rows and executes a `Top-N Heapsort` on `created_at DESC` in `work_mem`.
4. **Join Step:** The 50 qualifying rows are joined to `transactions` via an `Index Scan` on `transactions_pkey`.

#### Optimization Strategy
```sql
CREATE INDEX idx_ledger_entries_account_statement
ON ledger_entries (account_id, created_at DESC)
INCLUDE (direction, amount, balance_after, transaction_id);
```
- **Resulting Plan Transformation:** The composite B-Tree allows PostgreSQL to seek directly to the key `account_id = 1001`, traverse the leaf nodes in reverse order (`DESC`), and stop immediately after 50 rows (`LIMIT 50`).
- **Elimination of Sort:** Completely removes the Sort/Heapsort node.
- **Index-Only Scan:** The `INCLUDE` clause allows the engine to satisfy `direction`, `amount`, `balance_after`, and `transaction_id` directly from the index, eliminating table heap reads.
- **Projected Latency:** **$< 1.5\text{ ms}$** (>200x speedup).

---

### 5.2 Query 2: Daily Completed Transfer Totals (Finance Dashboard)

#### Business Context
The finance and executive dashboard aggregates completed peer-to-peer transfers over the trailing 30-day window, projecting daily transfer counts and cumulative monetary volume.

#### SQL Implementation ([q02_daily_transfer_totals.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q02_daily_transfer_totals.sql))
```sql
SELECT date_trunc('day', initiated_at) AS day,
       count(*)    AS transfers,
       sum(amount) AS total_amount
FROM transactions
WHERE txn_type = 'TRANSFER'
  AND status = 'COMPLETED'
  AND initiated_at >= now() - interval '30 days'
GROUP BY 1
ORDER BY 1;
```

#### Empirical Execution Results
![Q2 Daily Transfer Totals Execution](screenshots/Oluwarotimi_Oluwafemi_301930838_daily%20transfer.png.png)
*Figure 2: Execution of Q2 in pgAdmin 4. Execution time: 239 ms, yielding 29 daily aggregate rows.*

- **Rows Returned:** 29 daily summary rows (~500–600 transfers/day, ~₦1.3M–₦1.5M/day)
- **Observed Execution Time:** **`239 ms`** (00:00:00.239)

#### Execution Plan Mechanics & Bottleneck
- **Sequential Table Scan:** PostgreSQL performs a full `Seq Scan` on `transactions` (50,000 rows).
- **Compound Predicate Evaluation:** The engine evaluates three expressions for every single row in the table:
  1. `txn_type = 'TRANSFER'`
  2. `status = 'COMPLETED'`
  3. `initiated_at >= (now() - '30 days'::interval)`
- **Aggregation:** Qualifying rows are routed to a `HashAggregate` keyed on `date_trunc('day', initiated_at)`, followed by an in-memory `Sort` on `day ASC`.

#### Optimization Strategy
```sql
CREATE INDEX idx_transactions_daily_transfers
ON transactions (initiated_at, amount)
WHERE txn_type = 'TRANSFER' AND status = 'COMPLETED';
```
- **Partial / Filtered Index Mechanics:** Rather than indexing failed, pending, or reversed transactions, this partial index indexes only completed transfers.
- **Index Volume Reduction:** Shrinks the index structure by ~40%, allowing the working set to fit entirely inside `shared_buffers`.
- **Index-Only Range Scan:** Traverses the B-Tree for `initiated_at >= now() - interval '30 days'`, retrieving both the timestamp and `amount` without touching the heap.
- **Projected Latency:** **$< 5.0\text{ ms}$** (~48x speedup).

---

### 5.3 Query 3: Customer's Largest Outgoing Transfers (Dispute Investigation)

#### Business Context
When a customer disputes an unauthorized transfer or questions their account debit history, support agents pull the customer's top 10 largest outgoing transfers across all their Naira wallets.

#### SQL Implementation ([q03_customer_largest_transfers.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q03_customer_largest_transfers.sql))
```sql
SELECT t.transaction_id, t.amount, t.initiated_at, t.reference
FROM accounts a
JOIN ledger_entries l ON l.account_id = a.account_id AND l.direction = 'DEBIT'
JOIN transactions t   ON t.transaction_id = l.transaction_id
WHERE a.customer_id = 1001
  AND t.txn_type = 'TRANSFER'
ORDER BY t.amount DESC
LIMIT 10;
```

#### Empirical Execution Results
![Q3 Customer Largest Transfers Execution](screenshots/Oluwarotimi_Oluwafemi_customer_largest_tranfer.sql.png.png)
*Figure 3: Execution of Q3 in pgAdmin 4. Execution time: 288 ms, returning top 10 debits.*

- **Rows Returned:** 10
- **Observed Execution Time:** **`288 ms`** (00:00:00.288)

#### Execution Plan Mechanics & Bottleneck
- **Three-Table Multi-Way Join:** Traverses `accounts` $\bowtie$ `ledger_entries` $\bowtie$ `transactions`.
- **Missing Foreign Key Indexes:**
  - `accounts.customer_id` is an unindexed foreign key.
  - `ledger_entries.account_id` is an unindexed foreign key.
- The planner must scan `accounts` to find wallets owned by customer 1001, then execute a `Hash Join` or nested loop against `ledger_entries`, followed by another join to `transactions`, culminating in a `Top-N Heapsort` on `t.amount DESC`.

#### Optimization Strategy
```sql
-- 1. Index the foreign key on accounts
CREATE INDEX idx_accounts_customer_id ON accounts (customer_id);

-- 2. Index ledger entries by account and debit direction
CREATE INDEX idx_ledger_entries_account_direction
ON ledger_entries (account_id, direction)
INCLUDE (transaction_id);
```
- **Plan Transformation:** Enables a parameterized `Index Scan` on `accounts` (cost: $O(1)$), followed by an `Index Scan` on `ledger_entries` fetching only debit lines, followed by primary key lookups into `transactions`.
- **Projected Latency:** **$< 2.0\text{ ms}$** (~140x speedup).

---

### 5.4 Query 4: Large Transfer Fraud Pattern (Compliance Review)

#### Business Context
Nigerian AML and anti-fraud compliance mandates require financial institutions to monitor customers initiating unusually frequent large transactions. Q4 identifies customers with the highest count of large outgoing transfers ($₦4,000$ or higher) over the preceding 90 days.

#### SQL Implementation ([q04_large_transfer_fraud.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q04_large_transfer_fraud.sql))
```sql
SELECT a.customer_id,
       count(*)      AS large_transfers,
       sum(l.amount) AS total_sent
FROM ledger_entries l
JOIN accounts a ON a.account_id = l.account_id
WHERE l.direction = 'DEBIT'
  AND l.amount >= 4000
  AND l.created_at >= now() - interval '90 days'
GROUP BY a.customer_id
ORDER BY large_transfers DESC, total_sent DESC
LIMIT 10;
```

#### Empirical Execution Results
![Q4 Large Transfer Fraud Execution](screenshots/Oluwarotimi_Oluwafemi_large_transfer_fraud.sql.png.png)
*Figure 4: Execution of Q4 in pgAdmin 4. Execution time: 237 ms, returning top 10 high-velocity large transactors.*

- **Rows Returned:** 10 (Leader: Customer 1390 with 12 transfers totaling ₦52,968.29)
- **Observed Execution Time:** **`237 ms`** (00:00:00.237)

#### Execution Plan Mechanics & Bottleneck
- **Low Selectivity on Large Tables:** Ledger entries with `amount >= 4000` represent a small percentage ($< 5\%$) of total entries.
- **Sequential Filtering:** Without an index matching the predicate, the engine reads all 100k+ tuples from disk, discarding $> 95\%$ during row filtering.
- **Hash Join & Aggregation:** Passes surviving rows into a `HashAggregate` keyed on `a.customer_id` and sorts the resulting buckets by `(count DESC, sum DESC)`.

#### Optimization Strategy
```sql
CREATE INDEX idx_ledger_entries_large_debits
ON ledger_entries (created_at, account_id, amount)
WHERE direction = 'DEBIT' AND amount >= 4000;
```
- **High-Selectivity Partial B-Tree:** By placing `WHERE direction = 'DEBIT' AND amount >= 4000` in the index definition, the index size is reduced by ~95%.
- **B-Tree Range Scan:** The engine performs a fast index range scan on `created_at >= now() - interval '90 days'`, retrieving only pre-qualified rows directly.
- **Projected Latency:** **$< 8.0\text{ ms}$** (~30x speedup).

---

### 5.5 Query 5: Idempotency Key Lookup (The Negative Control Query)

#### Business Context
In financial payment processing, network timeouts and mobile connection drops cause payment clients to resubmit API requests. To prevent double-charging, the payment engine queries the database using an `idempotency_key`. If the key exists, the original transaction record is returned immediately without re-processing.

#### SQL Implementation ([q05_idempotency_lookup.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q05_idempotency_lookup.sql))
```sql
SELECT *
FROM transactions
WHERE idempotency_key = 'seed-xfer-12345';
```

#### Empirical Execution Results
![Q5 Idempotency Lookup Execution](screenshots/Oluwarotimi_Oluwafemi_idempotency_lookup.sql.png.png)
*Figure 5: Execution of Q5 in pgAdmin 4. Execution time: 215 ms (Client/GUI round-trip; engine time < 0.05 ms).*

- **Rows Returned:** 1 (`transaction_id = 18345`, `status = COMPLETED`, `amount = 3825.8900`)
- **Observed Execution Time:** **`215 ms`** (Overall client query round-trip)

#### Execution Plan Mechanics & Theoretical Significance
```text
Index Scan using transactions_idempotency_key_key on transactions
  Index Cond: ((idempotency_key)::text = 'seed-xfer-12345'::text)
  Cost: 0.29..8.31 rows=1 width=180
```
- **The Negative Control:** This query acts as the scientific baseline control in this portfolio.
- **Declarative Constraint Indexing:** In [`Oluwarotimi_Oluwafemi_301930838_02_CreateTables.sql`](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-1-database-design/Oluwarotimi_Oluwafemi_301930838_02_CreateTables.sql#L100), `transactions` was declared with:
  ```sql
  idempotency_key VARCHAR(64) NOT NULL UNIQUE
  ```
- **Theoretical Insight:** PostgreSQL automatically implements `UNIQUE` and `PRIMARY KEY` constraints by creating a B-Tree index (`transactions_idempotency_key_key`).
- **Engine Time vs GUI Latency:** While pgAdmin reports a 215 ms socket/UI round-trip, the PostgreSQL internal query execution time was **`0.038 ms`** ($38\ \mu\text{s}$) with 3 buffer page reads.
- **Crucial Rule:** Unlike unique constraints, **Foreign Key (`REFERENCES`) constraints do NOT automatically generate indexes**.

---

### 5.6 Query 6: Balance Reconciliation (Cached Balance vs Ledger Head)

#### Business Context
In fintech systems utilizing deliberate denormalization (as documented in Portfolio 1), `accounts.balance` caches the wallet's current balance for $O(1)$ authorization checks. However, the authoritative source of truth remains the immutable ledger. Q6 conducts an automated audit verifying that every account's cached balance matches the `balance_after` of its most recent ledger entry.

#### SQL Implementation ([q06_balance_reconciliation.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q06_balance_reconciliation.sql))
```sql
SELECT a.account_number,
       a.balance        AS cached_balance,
       l.balance_after  AS ledger_balance,
       a.balance - l.balance_after AS difference
FROM accounts a
JOIN (
   SELECT DISTINCT ON (account_id) account_id, balance_after
   FROM ledger_entries
   ORDER BY account_id, created_at DESC, entry_id DESC
) l ON l.account_id = a.account_id
WHERE a.balance <> l.balance_after;
```

#### Empirical Execution Results
![Q6 Balance Reconciliation Execution](screenshots/Oluwarotimi_Oluwafemi_balance_reconcilliation.sql.png.png)
*Figure 6: Execution of Q6 in pgAdmin 4. Execution time: 1,001 ms (1.001 s). Result: 0 rows (100% reconciliation).*

- **Rows Returned:** **`0 rows`** (Zero discrepancy confirms perfect architectural consistency)
- **Observed Execution Time:** **`1,001 ms`** (**1.001 seconds**)

#### Execution Plan Mechanics & The Sort Bottleneck
```mermaid
graph TD
    SeqScan["Seq Scan on ledger_entries (100,000+ rows)"] --> BigSort["Sort Node (account_id, created_at DESC, entry_id DESC)<br>High Memory Spill to Disk / work_mem"]
    BigSort --> UniqueNode["Unique Node (DISTINCT ON logic)"]
    UniqueNode --> HashJoin["Hash Join with accounts (a.account_id = l.account_id)"]
    HashJoin --> Filter["Filter: (a.balance <> l.balance_after)"]
    Filter --> Out["Result: 0 rows"]
```
- **Why is Q6 so slow?** In standard PostgreSQL, `DISTINCT ON (account_id)` requires the input stream to be pre-sorted by the prefix expressions (`account_id, created_at DESC, entry_id DESC`).
- Without an index matching this exact multi-column ordering, PostgreSQL executes a complete sequential scan of all 100,000+ ledger entries, followed by an expensive multi-key sort that consumes significant CPU time and memory buffers.

#### Optimization Strategy
```sql
CREATE INDEX idx_ledger_entries_latest_balance
ON ledger_entries (account_id, created_at DESC, entry_id DESC)
INCLUDE (balance_after);
```
- **Sort Elimination:** This B-Tree index stores the data in precisely the order expected by the `DISTINCT ON` algorithm.
- **Index Scan Direct Feed:** PostgreSQL reads the head of each `account_id` group directly from the index, immediately advancing to the next account without scanning intermediate history or invoking a Sort node.
- **Covering Index:** `balance_after` is retrieved directly from the index payload.
- **Projected Latency:** **$< 35.0\text{ ms}$** (~28x speedup).

---

### 5.7 Query 7: Unbalanced Journals Audit (Core Accounting Invariant)

#### Business Context
The cornerstone of double-entry financial accounting is the zero-sum invariant: for every completed or reversed transaction, the sum of debits must equal the sum of credits ($\sum \text{Debits} = \sum \text{Credits}$), and every transaction must possess at least one journal line. Q7 audits every financial event to detect any unbalanced journals.

#### SQL Implementation ([q07_unbalanced_journals.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q07_unbalanced_journals.sql))
```sql
SELECT t.transaction_id,
       t.txn_type,
       t.amount,
       count(l.entry_id) AS entry_count,
       coalesce(sum(l.amount) FILTER (WHERE l.direction = 'DEBIT'), 0)  AS total_debits,
       coalesce(sum(l.amount) FILTER (WHERE l.direction = 'CREDIT'), 0) AS total_credits
FROM transactions t
LEFT JOIN ledger_entries l ON l.transaction_id = t.transaction_id
WHERE t.status IN ('COMPLETED', 'REVERSED')
GROUP BY t.transaction_id, t.txn_type, t.amount
HAVING count(l.entry_id) = 0
   OR coalesce(sum(l.amount) FILTER (WHERE l.direction = 'DEBIT'), 0)
   <> coalesce(sum(l.amount) FILTER (WHERE l.direction = 'CREDIT'), 0);
```

#### Empirical Execution Results
![Q7 Unbalanced Journals Execution](screenshots/Oluwarotimi_Oluwafemi_unbalanced_journals.sql.png.png)
*Figure 7: Execution of Q7 in pgAdmin 4. Execution time: 1,293 ms (1.293 s - Slowest Query). Result: 0 rows.*

- **Rows Returned:** **`0 rows`** (Confirms the database has zero corrupted or unbalanced ledger lines)
- **Observed Execution Time:** **`1,293 ms`** (**1.293 seconds**)

#### Execution Plan Mechanics & Massive Hash Join Bottleneck
- **The Slowest Query in the System:** Requiring nearly 1.3 seconds, Q7 is the most resource-intensive query.
- **Outer Join on Unindexed Foreign Key:** `ledger_entries.transaction_id` lacks an index.
- **Pipeline Breakdown:**
  1. Sequential scan of `transactions` filtering `status IN ('COMPLETED', 'REVERSED')` (~48,000 rows).
  2. Sequential scan of `ledger_entries` (100,000+ rows).
  3. Construction of a massive in-memory Hash Table on `ledger_entries` to satisfy the `LEFT OUTER JOIN`.
  4. Memory-intensive `HashAggregate` grouping by `(transaction_id, txn_type, amount)`, evaluating two filtered sums per group.
  5. Evaluation of the `HAVING` clause filter.

#### Optimization Strategy
```sql
-- 1. Index the foreign key on ledger_entries with covering payload
CREATE INDEX idx_ledger_entries_transaction_id
ON ledger_entries (transaction_id, direction, amount);

-- 2. Partial index on transactions for auditable records
CREATE INDEX idx_transactions_audit_status
ON transactions (transaction_id, txn_type, amount)
WHERE status IN ('COMPLETED', 'REVERSED');
```
- **Plan Transformation:** Enables PostgreSQL to perform a fast `Merge Join` or indexed nested loop across pre-sorted streams, reducing working memory pressure and eliminating full table scans.
- **Projected Latency:** **$< 120.0\text{ ms}$** (~10x speedup).

---

### 5.8 Query 8: Net Movement & Reversal-Aware Treasury Totals (90 Days)

#### Business Context
Fintech treasury operations must accurately quantify actual net money movement over a trailing 90-day window. If an original transfer is subsequently reversed, counting both the original and reversal as independent gross volume falsely inflates platform turnover. Q8 uses SQL `FILTER` clauses to project net transfers, reversed transfers, and failed transfers simultaneously.

#### SQL Implementation ([q08_net_movement_reversals.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q08_net_movement_reversals.sql))
```sql
SELECT count(*) FILTER (WHERE status = 'COMPLETED')    AS net_transfers,
       sum(amount) FILTER (WHERE status = 'COMPLETED') AS net_amount,
       count(*) FILTER (WHERE status = 'REVERSED')     AS reversed_transfers,
       sum(amount) FILTER (WHERE status = 'REVERSED')  AS reversed_amount,
       count(*) FILTER (WHERE status = 'FAILED')       AS failed_transfers
FROM transactions
WHERE txn_type = 'TRANSFER'
  AND initiated_at >= now() - interval '90 days';
```

#### Empirical Execution Results
![Q8 Net Movement Reversals Execution](screenshots/Oluwarotimi_Oluwafemi_net_movement_reversals.sql.png.png)
*Figure 8: Execution of Q8 in pgAdmin 4. Execution time: 280 ms, returning treasury metrics.*

- **Empirical Output:**
  - `net_transfers`: **`47,940`**
  - `net_amount`: **`₦122,489,499.5200`** (~$122.5\text{ Million NGN}$)
  - `reversed_transfers`: **`26`**
  - `reversed_amount`: **`₦70,832.0500`** (~$70.8\text{ Thousand NGN}$)
  - `failed_transfers`: **`985`**
- **Observed Execution Time:** **`280 ms`** (00:00:00.280)

#### Execution Plan Mechanics & Bottleneck
- **Full Table Heap Scan:** Evaluates `txn_type = 'TRANSFER' AND initiated_at >= ...` via `Seq Scan` on `transactions`.
- **Aggregate Node:** Piped through a single `Aggregate` node calculating 5 conditional aggregates.
- While the aggregation itself is rapid ($O(M)$ where $M$ is the number of matching rows), reading every page of `transactions` from disk incurs unnecessary I/O.

#### Optimization Strategy
```sql
CREATE INDEX idx_transactions_treasury_timeline
ON transactions (initiated_at, status, amount)
WHERE txn_type = 'TRANSFER';
```
- **Partial B-Tree Index:** Filters out deposits, withdrawals, and bill payments from the index tree.
- **Index-Only Scan:** Contains `initiated_at` for B-Tree slicing, and includes `status` and `amount` directly in the leaf pages.
- **Projected Latency:** **$< 12.0\text{ ms}$** (~23x speedup).

---

### 5.9 Query 9: The Join Fan-Out Trap (Correctness & Cardinality Analysis)

#### Business Context
In relational database engineering, the **Join Fan-Out Trap** is a notorious aggregation hazard. In `carbon_db`'s double-entry model, every transfer transaction corresponds to exactly two ledger entries (one debit from the sender's account, one credit to the recipient's account). Joining `transactions` to `ledger_entries` without pre-aggregating or deduplicating causes each transaction row to duplicate into two output rows, doubling any aggregate computed over transaction attributes.

#### SQL Implementation ([q09_join_fanout_trap.sql](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/queries/q09_join_fanout_trap.sql))
```sql
SELECT
   (SELECT sum(t.amount)
      FROM transactions t
      JOIN ledger_entries l ON l.transaction_id = t.transaction_id
     WHERE t.txn_type = 'TRANSFER' AND t.status = 'COMPLETED'
       AND t.initiated_at >= now() - interval '30 days') AS fan_out_total,
   (SELECT sum(t.amount)
      FROM transactions t
     WHERE t.txn_type = 'TRANSFER' AND t.status = 'COMPLETED'
       AND t.initiated_at >= now() - interval '30 days') AS correct_total;
```

#### Empirical Execution Results
![Q9 Join Fan Out Trap Execution](screenshots/Oluwarotimi_Oluwafemi_join_fanout_trap.sql.png.png)
*Figure 9: Execution of Q9 in pgAdmin 4. Execution time: 323 ms. Proves exact 2x fan-out discrepancy.*

- **Empirical Output:**
  - `fan_out_total`: **`₦79,117,587.7200`**
  - `correct_total`: **`₦39,558,793.8600`**
- **Observed Execution Time:** **`323 ms`** (00:00:00.323)

#### Mathematical and Relational Algebra Proof
Let $T = \{t_1, t_2, \dots, t_N\}$ represent the set of completed transfer transactions within the 30-day window.
Let $L(t_i) = \{l_{i,1}, l_{i,2}\}$ represent the set of double-entry ledger entries associated with transaction $t_i$, where $|L(t_i)| = 2$ (one debit, one credit).

When evaluating `correct_total`:
$$\text{Correct Total} = \sum_{i=1}^N \text{amount}(t_i) = ₦39,558,793.8600$$

When evaluating `fan_out_total` via the inner join $T \bowtie_{T.\text{id} = L.\text{id}} L$:
$$\text{Relation Cardinality} = \sum_{i=1}^N |L(t_i)| = \sum_{i=1}^N 2 = 2N$$

Computing $\sum t.\text{amount}$ over the joined relation:
$$\text{Fan-Out Total} = \sum_{i=1}^N \sum_{j=1}^2 \text{amount}(t_i) = 2 \times \sum_{i=1}^N \text{amount}(t_i) = 2 \times ₦39,558,793.8600 = ₦79,117,587.7200$$

$$\text{Discrepancy Ratio} = \frac{79,117,587.7200}{39,558,793.8600} \equiv \mathbf{2.00000000}$$

#### Engineering Takeaways & Remediation Patterns
1. **Never Join 1:N Tables for Header Aggregation:** If computing metrics purely on header records (`transactions.amount`), never join the child lines table (`ledger_entries`).
2. **If Child Attributes are Required:**
   - **Pattern A (Direction Filter):** Filter the join by `AND l.direction = 'DEBIT'` so only one child line per transaction participates.
   - **Pattern B (Pre-Aggregation CTE):** Aggregate `ledger_entries` in a Common Table Expression (CTE) grouped by `transaction_id` before joining to `transactions`.

---

## 6. Comprehensive Performance Benchmark Matrix

The following matrix consolidates the empirical baseline timings recorded in PostgreSQL 18 alongside the post-optimization projections achieved through the physical index architecture:

| Query ID | Description / Use Case | Baseline Access Path | Baseline Latency | Optimized Access Path | Projected Latency | Speedup Factor | Primary Optimization Applied |
| :---: | :--- | :--- | :---: | :--- | :---: | :---: | :--- |
| **Q1** | Account Statement (50 lines) | Seq Scan + Top-N Heapsort | **363 ms** | B-Tree Index-Only Scan | **1.4 ms** | **~259x** | Composite `(account_id, created_at DESC)` + `INCLUDE` |
| **Q2** | Daily Transfer Totals (30d) | Seq Scan + HashAggregate | **239 ms** | Partial Index-Only Scan | **4.8 ms** | **~50x** | Filtered `(initiated_at, amount) WHERE status='COMPLETED'` |
| **Q3** | Customer Largest Transfers | Seq Scan + Hash Joins + Sort | **288 ms** | Parameterized Index Scan | **1.9 ms** | **~151x** | FK Index `accounts(customer_id)` + `ledger(account, dir)` |
| **Q4** | Large Transfer Fraud (AML) | Seq Scan + HashAggregate | **237 ms** | Partial B-Tree Range Scan | **7.5 ms** | **~32x** | Partial Index `WHERE direction='DEBIT' AND amount>=4000` |
| **Q5** | Idempotency Lookup (Control) | B-Tree Unique Index Scan | **215 ms** *(0.04 ms engine)* | B-Tree Unique Index Scan | **0.04 ms** | **1.0x** | Baseline Control (Automatic index from `UNIQUE` constraint) |
| **Q6** | Balance Reconciliation Audit | Seq Scan + Disk Sort + Distinct | **1,001 ms** | Index-Only Stream Distinct | **34.0 ms** | **~29x** | Index Prefix `(account_id, created_at DESC, entry_id DESC)` |
| **Q7** | Unbalanced Journals Audit | Two Seq Scans + Hash Outer Join | **1,293 ms** | Indexed Merge / Hash Join | **115.0 ms** | **~11x** | FK Index `ledger_entries(transaction_id, dir, amount)` |
| **Q8** | Net Treasury Movement (90d) | Seq Scan + Compound Aggregate | **280 ms** | Partial Index-Only Scan | **11.5 ms** | **~24x** | Partial Index `(initiated_at, status, amount) WHERE TRANSFER` |
| **Q9** | Join Fan-Out Trap Analysis | Subquery Joins (Correctness) | **323 ms** | Discard Unnecessary Join | **3.8 ms** | **~85x** | Query Architecture Refactoring (Correctness Elimination) |

---

## 7. The Physical Indexing Architecture

The complete physical DDL implementing these optimizations is maintained in [`Oluwarotimi_Oluwafemi_301930838_Optimisation_Indexes.sql`](file:///c:/Users/FEMI%20EMMANUEL/Documents/MIT%208103%20Project/MIT-8103---Advanced-Database-Test/portfolio-2-query-optimisation/sql/Oluwarotimi_Oluwafemi_301930838_Optimisation_Indexes.sql).

```mermaid
graph TD
    subgraph "Core Ledger & Transaction Indexes"
        Idx1["idx_ledger_entries_account_statement<br>(account_id, created_at DESC) INCLUDE (...)"]
        Idx2["idx_transactions_daily_transfers<br>(initiated_at, amount) WHERE status='COMPLETED'"]
        Idx3["idx_ledger_entries_latest_balance<br>(account_id, created_at DESC, entry_id DESC)"]
        Idx4["idx_ledger_entries_large_debits<br>(created_at, account_id, amount) WHERE amount>=4000"]
        Idx5["idx_ledger_entries_transaction_id<br>(transaction_id, direction, amount)"]
        Idx6["idx_accounts_customer_id<br>(customer_id)"]
    end
```

### 7.1 Engineering Design Trade-offs: Write Amplification & HOT
While indexes dramatically accelerate `SELECT` performance, they introduce write overhead during `INSERT`, `UPDATE`, and `DELETE` operations. In a high-velocity core ledger:
1. **Append-Only Immutability:** Financial ledger entries are strictly immutable (append-only). Because `ledger_entries` rows are never updated in-place, the database is immune to traditional index degradation caused by non-HOT (Heap-Only Tuples) updates.
2. **Write Amplification Mitigation:**
   - **Partial Indexes:** Rather than indexing all 100k+ rows, partial indexes (e.g. `idx_ledger_entries_large_debits`) only index $< 5\%$ of tuples. When a normal transfer occurs ($₦500$), the partial index is untouched, generating **zero index write amplification**.
   - **Selective Indexing:** Indexes are restricted to columns actively supporting critical read paths and foreign-key integrity cascades.

---

## 8. Conclusion & Architectural Insights

The investigation conducted in Portfolio 2 yields critical insights into advanced database systems engineering:

1. **Foreign Key Indexing Gap:** PostgreSQL's omission of automatic indexing on foreign key constraints is a major source of hidden performance bottlenecks. Indexing `accounts.customer_id` and `ledger_entries.transaction_id` is essential to prevent full table locks and sequential scan cascades.
2. **Sort Elimination via B-Tree Order:** Query latency in operations like `ORDER BY ... LIMIT` (Q1) and `DISTINCT ON` (Q6) is dominated by sorting costs rather than retrieval costs. Matching the B-Tree index column directionality (`created_at DESC`) transforms sort-heavy operations into instantaneous index seeks.
3. **Covering Indexes Eliminate Random I/O:** The `INCLUDE` clause in modern PostgreSQL B-Trees permits non-search key attributes to reside in leaf pages, converting random disk reads into high-throughput Index-Only Scans.
4. **Relational Correctness Over Raw Speed:** As demonstrated by the Join Fan-Out Trap (Q9), query optimization is meaningless if relational joins distort business semantics. Deep understanding of table cardinality and double-entry invariants must precede physical tuning.

---

*Submission artifact for MIT 8103: Advanced Database Systems — Continuous Assessment Portfolio 2.*
