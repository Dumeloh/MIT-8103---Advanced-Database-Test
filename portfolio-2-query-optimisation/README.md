# Portfolio 2: Query Optimisation & Execution Plans

**Course:** MIT 8103 – Advanced Database Systems  
**Institution:** Miva Open University — Master of Information Technology (MIT)  
**Candidate / Author:** Oluwafemi Emmanuel Oluwarotimi ([@Dumeloh](https://github.com/Dumeloh))  
**Student ID:** 301930838  
**System:** Carbon / NairaPay Core Fintech Ledger System (`carbon_db`)  
**Database Engine:** PostgreSQL 18.0 (x64) | **Management Tool:** pgAdmin 4  

---

## 📌 Directory Navigation

- 📄 **[Master Performance Analysis & Theoretical Report](./Oluwarotimi_Oluwafemi_301930838_Query_Optimisation_Analysis.md)**
- 💾 **[Production Optimization Indexes DDL Script](./sql/Oluwarotimi_Oluwafemi_301930838_Optimisation_Indexes.sql)**
- 📁 **[SQL Query Benchmark Suite](./queries/)**
  - [Q1: Account Statement (Recent Ledger Lines)](./queries/q01_account_statement.sql)
  - [Q2: Daily Transfer Totals (Trailing 30 Days)](./queries/q02_daily_transfer_totals.sql)
  - [Q3: Customer Largest Outgoing Transfers](./queries/q03_customer_largest_transfers.sql)
  - [Q4: Large Transfer Fraud Pattern (AML Compliance)](./queries/q04_large_transfer_fraud.sql)
  - [Q5: Idempotency Key Lookup (Negative Control Benchmark)](./queries/q05_idempotency_lookup.sql)
  - [Q6: Balance Reconciliation Audit (Cached vs Ledger Head)](./queries/q06_balance_reconciliation.sql)
  - [Q7: Unbalanced Journals Audit (Core Accounting Invariant)](./queries/q07_unbalanced_journals.sql)
  - [Q8: Net Movement & Reversal-Aware Treasury Totals](./queries/q08_net_movement_reversals.sql)
  - [Q9: Join Fan-Out Trap Analysis (Relational Correctness)](./queries/q09_join_fanout_trap.sql)
- 🖼️ **[pgAdmin 4 Execution Plan & Results Screenshots](./screenshots/)**

---

## 📊 Summary Benchmark Matrix

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

*For full theoretical derivations, cost models, and execution plan diagrams, see [Oluwarotimi_Oluwafemi_301930838_Query_Optimisation_Analysis.md](./Oluwarotimi_Oluwafemi_301930838_Query_Optimisation_Analysis.md).*
