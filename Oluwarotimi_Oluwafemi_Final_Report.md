# MIT 8103: Advanced Database Systems — Final Portfolio Synthesis Report
**Miva Open University — School of Postgraduate Studies**  
**Master of Information Technology (MIT) | 2026/2027 Academic Session (September Cohort)**  
**Continuous Assessment: Individual Practical Database Portfolio (40 Marks)**  

---

### Student and Assessment Metadata
- **Student Surname:** Oluwarotimi
- **Student First Name:** Oluwafemi Emmanuel
- **Student ID:** 301930838
- **University Email:** o.oluwarotimi30838@miva.university
- **Chosen Case Study:** Carbon Simulated Fintech Platform (Digital Banking, Double-Entry Ledger & Polyglot Persistence)
- **Target Database Engines:** PostgreSQL 18.0 (Local & Containerized), MongoDB Atlas 7.0 (Cloud)
- **GitHub Repository URL:** [https://github.com/Dumeloh/MIT-8103---Advanced-Database-Test.git](https://github.com/Dumeloh/MIT-8103---Advanced-Database-Test.git)

---

## 1. Enterprise Case Study Overview: Carbon Financial Technologies
In modern digital financial systems, database architecture represents the foundation of institutional solvency, regulatory trust, and operational continuity. **Carbon Financial Technologies** is a digital banking platform operating within the Nigerian fintech ecosystem. The platform serves retail consumers, gig workers, and commercial merchants with services including high-velocity mobile wallet payments, peer-to-peer (P2P) transfers, bill settlement, and tiered micro-credit facilities.

### 1.1 Technical Challenges and Operational Invariants
Operating within high-latency, intermittently reliable mobile telecommunication environments introduces significant engineering complexities:
1. **Network Retries & Idempotency:** Unstable cellular networks frequently cause mobile applications to resend API transaction requests. The persistence layer must reject duplicate submissions deterministically to prevent duplicate customer charges.
2. **Double-Entry Bookkeeping:** To satisfy Central Bank of Nigeria (CBN) regulations and standard accounting principles, funds must never be arbitrarily updated in place. Every transaction must atomically generate complementary `DEBIT` and `CREDIT` entries such that $\sum \text{Debits} \equiv \sum \text{Credits}$.
3. **High-Concurrency Contention:** Simultaneous transactions targeting identical wallets (e.g., automated salary disbursements against merchant payouts) create severe race conditions, risking lost updates, phantom reads, and database deadlocks.
4. **Regulatory Governance & Data Privacy:** Adherence to the **Nigeria Data Protection Act (NDPA) 2023** and **PCI-DSS** mandates strict data classification—segregating mutable customer KYC documentation from immutable financial ledgers and prohibiting the plain-text storage of Primary Account Numbers (PAN).

---

## 2. Synthesis of Portfolio Deliverables (Portfolios 1 to 5)

### 2.1 Portfolio 1: Relational Schema Design, Integrity Constraints & Normalisation
Portfolio 1 established the declarative foundation of `carbon_db` on PostgreSQL 18. A comprehensive Entity-Relationship Diagram (ERD) was synthesized, comprising core entities: `customers`, `accounts`, `transactions`, `ledger_entries`, `cards`, `beneficiaries`, and `fraud_flags`.
- **Normalization Analysis:** The schema underwent rigorous mathematical normalization from 1NF through 3NF and Boyce-Codd Normal Form (BCNF). All non-key attributes were demonstrated to depend strictly on the whole primary key. Controlled denormalization was deliberately justified for the `accounts.available_balance` attribute as a cached performance projection, bounded by an invariant validation constraint against the underlying immutable ledger.
- **Declarative Invariant Enforcement:** Financial integrity was enforced directly within the PostgreSQL engine using check constraints (`balance >= 0`, `amount > 0`), foreign key restrictions (`ON DELETE RESTRICT` to ensure zero forensic data loss), and composite uniqueness constraints on client-supplied UUID idempotency keys. A synthetic dataset comprising over 6,000 accounts and 200,000 transactions was generated to stress the constraints.

### 2.2 Portfolio 2: Physical Query Optimisation & Execution Plan Analysis
Portfolio 2 evaluated the transition from logical correctness to physical execution performance. Using PostgreSQL's `EXPLAIN (ANALYZE, BUFFERS)` instrumentation, nine mission-critical production queries were benchmarked before and after index optimization:
- **Index Architecture:** A multi-tiered indexing strategy was engineered, including composite B-Tree indexes `(account_id, created_at DESC)` for customer statements, partial/filtered indexes `WHERE status = 'FLAGGED'` for real-time AML fraud queues, and covering indexes utilizing `INCLUDE` clauses to facilitate pure, zero-heap `Index Only Scans`.
- **Benchmark Findings & The Join Fan-Out Trap:** Sequential table scans scanning hundreds of thousands of heap blocks were reduced to memory-cached logarithmic index lookups, achieving query latency reductions exceeding **96%** (e.g., Q6 Distinct Balances dropping from 185.3 ms to 6.8 ms). Furthermore, Query 9 isolated and solved the classic **Join Fan-Out Trap**, proving that joining transaction headers directly to double-entry ledger lines inflates aggregated sums by exactly $2.0\times$, resolved via pre-aggregated Common Table Expressions (CTEs).

### 2.3 Portfolio 3: Transaction Management, ACID Invariants & Concurrency Control
Portfolio 3 investigated the database engine's lock manager and transaction isolation boundaries under high-throughput simulated concurrency:
- **PL/pgSQL Atomic Transfer Engine:** A hardened stored function `process_wallet_transfer()` was implemented. To eliminate the risk of cyclic wait conditions and system-halting deadlocks during concurrent reciprocal transfers (e.g., User A transferring to User B while User B transfers to User A), the function enforces a **deterministic ascending lock acquisition order** (`account_id = LEAST(acc1, acc2)` locked prior to `GREATEST(acc1, acc2)`).
- **Concurrency Isolation & Stress Testing:** Empirical tests demonstrated that under `READ COMMITTED`, explicit row-level locking (`SELECT ... FOR UPDATE`) is required to eliminate lost updates. High-contention workloads executed via `pgbench` (30 concurrent clients, 1,000 transactions) confirmed that deterministic lock ordering yielded **0 deadlocks and 0% rollbacks**, maintaining perfect ledger invariant balance ($\sum \text{Debits} - \sum \text{Credits} = 0.0000$).

### 2.4 Portfolio 4: NoSQL Document Data Modeling & Polyglot Architecture
Portfolio 4 addressed the architectural limitations of pure relational models when managing polymorphic, semi-structured, and high-velocity compliance data:
- **Polyglot Strategy:** Core financial accounting was retained in PostgreSQL, while customer KYC identity documentation, authentication sessions, and high-throughput security audit streams were offloaded to MongoDB.
- **Document Schemas & Validation:** Using MongoDB Atlas and `mongosh`, strict JSON Schema validators (`$jsonSchema`) were deployed on collections (`kyc_profiles`, `audit_events`, `login_sessions`). Time-to-Live (TTL) indexes were implemented on `login_sessions` to achieve automatic, zero-overhead background session expiry. Compound indexes were established to optimize audit trail event filtering, validated through MongoDB `explain("executionStats")`.

### 2.5 Portfolio 5: Distributed Architectures, Replication & High Availability
Portfolio 5 evaluated enterprise availability, fault tolerance, and data distribution:
- **Streaming Replication & Failover:** A multi-container PostgreSQL cluster was orchestrated using Docker Compose. Physical Write-Ahead Log (WAL) streaming replication was configured between `carbon-pg-primary` and `carbon-pg-replica`. Real-time replication health was monitored via `pg_stat_replication`. A simulated primary hardware failure was executed, and the standby replica was promoted to primary status via `pg_ctl promote` within 1.8 seconds, achieving near-zero Recovery Time Objective (RTO).
- **Horizontal Scalability:** Declarative hash partitioning was applied across the core `ledger_entries` table across 4 physical partitions based on `hash(account_id)`. Query plans confirmed effective partition pruning, confining query scans exclusively to the relevant physical partition.

---

## 3. Technical Reflection & Engineering Insights

### 3.1 Lessons Learned on Database Guarantees and Cost Models
1. **The Fallacy of Implicit Database Safety:** The primary lesson acquired throughout this portfolio is that relational engines do not automatically protect applications against concurrency anomalies by default. Under the standard `READ COMMITTED` isolation level, naive read-modify-write patterns result in severe lost updates and balance overdrafts. Data integrity is an intentional engineering discipline requiring explicit locking contracts, deterministic key ordering, and declarative database constraints.
2. **The Economic Cost of Indexes:** While indexes drastically reduce query read latency, they introduce tangible write amplification and WAL serialization overhead. Each additional secondary index requires index-tree traversal and leaf page splits during every `INSERT` and `DELETE`. Physical design requires balancing OLTP ingest velocity against analytical query SLAs through selective partial indexing.

### 3.2 Relational vs. Non-Relational Trade-offs
The dual implementation of PostgreSQL and MongoDB demonstrated that modern enterprise architectures are inherently polyglot. Relational engines excel at multi-entity transactional consistency and referential enforcement, making them non-negotiable for general ledgers. Conversely, document databases provide schema flexibility for evolving KYC tier requirements and superior append-only write throughput for security telemetry.

---

## 4. Academic Integrity & Artificial Intelligence Use Declaration
This submission represents the original practical work and technical analysis of the author, **Oluwafemi Emmanuel Oluwarotimi (Student ID: 301930838)**. In accordance with Miva Open University's academic integrity policies:
- **Generative AI Tools Utilised:** Generative AI assistants (Google Antigravity IDE / Gemini) were employed as interactive technical dialogue partners for exploratory query drafting, syntax validation, and code formatting.
- **Human Authorship & Verification:** All schema designs, mathematical normalization proofs, execution plan interpretations, PL/pgSQL locking algorithms, Docker configurations, and performance measurements were independently deployed, executed, and validated by the author on local and cloud database instances. No code or diagnostic conclusions were incorporated without empirical verification.
- **Complete Disclosure:** A dedicated academic disclosure document is provided in `Oluwarotimi_Oluwafemi_AI_Use_Declaration.md`.

---

## 5. Summary Conclusion
The MIT 8103 Practical Database Portfolio establishes an end-to-end, production-grade financial database architecture for the Carbon fintech platform. By integrating strict BCNF normalization, targeted physical indexing, deadlock-free ACID concurrency control, polyglot document modeling, and distributed streaming replication, the portfolio demonstrates practical mastery of advanced database engineering principles required for mission-critical enterprise systems.
