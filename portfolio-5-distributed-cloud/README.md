# MIT 8103 Portfolio 5: Distributed and Cloud Databases

## Carbon Case Study

**Project:** MIT 8103 — Advanced Database Test  
**Portfolio:** 5 — Distributed and Cloud Database Exercise  
**Database technologies:** PostgreSQL, Docker, MongoDB Atlas  
**Environment:** Windows, PowerShell, Docker, and Antigravity IDE

---

## 1. Project Overview

This portfolio explores distributed database concepts through a Carbon fintech case study. The practical work covers PostgreSQL streaming replication, primary and replica responsibilities, replica consistency, synchronous and asynchronous replication, hash partitioning, failover, and a cloud database deployment using MongoDB Atlas.

The work includes:

- Running PostgreSQL primary and replica containers using Docker.
- Verifying streaming replication and checking primary/replica row counts.
- Measuring a point-in-time WAL replay gap in an isolated asynchronous replication lab.
- Capturing a controlled stale-read interval by pausing and resuming WAL replay.
- Configuring and verifying synchronous replication in an isolated temporary lab.
- Recording the outcome of a standby-unavailability timeout test without assuming that the timed-out transaction rolled back.
- Creating and evaluating a four-partition hash-partitioned ledger table.
- Promoting a replica after stopping the original primary.
- Creating a MongoDB Atlas Free cluster and attempting the cloud verification script.
- Producing a proposed production architecture diagram as an additional contribution.

A controlled stale-read interval was captured in the separate temporary experiment lab: while WAL replay was paused, the primary contained one row in `replication_lag_demo` and the replica contained zero; after replay resumed, the replica contained one row. An earlier zero-byte WAL-gap measurement was a separate point-in-time observation. Experiment 3 verified synchronous standby configuration and a successful replicated write, but the standby-unavailability test remains inconclusive. Successful MongoDB Atlas authentication and cloud read/write verification remain unresolved. These limitations are documented rather than presented as successful experiments.

---

## 2. Architecture and Environment

| Component | Role | Observed status |
|---|---|---|
| PostgreSQL primary | Accepts writes and generates changes for replication | Used during the original replication experiment; subsequently stopped for failover |
| PostgreSQL replica | Receives streamed WAL records and supports read-only queries during recovery | Streaming replication verified; subsequently promoted |
| Docker | Runs isolated PostgreSQL database containers | Used successfully |
| Hash-partitioned ledger table | Demonstrates hash partitioning and partition pruning | Experiment completed |
| MongoDB Atlas `Carbon-nosql` | Cloud database component | Cluster created; authentication verification remains unresolved |

The original PostgreSQL containers were named `carbon-pg-primary` and `carbon-pg-replica`. They used PostgreSQL 16 inside Docker. The original database was `carbon_db`, using the database user `carbon`, with host ports 5433 (primary) and 5434 (replica). The host PostgreSQL 18 service on port 5432 was separate from the Docker containers.

A separate temporary Docker lab was used for replication experiments, with containers `carbon-exp2-primary` and `carbon-exp2-replica`, host ports 5435 and 5436, and separate Docker volumes. This lab was used for asynchronous replication, the controlled stale-read experiment, and the synchronous replication experiment.

**Safety warning:** The original primary was stopped and its replica was promoted. Do not restart the former primary as a writable server while the promoted node is writable. Doing so without a safe rejoin or reconfiguration procedure risks split-brain operation. The temporary lab's synchronous replication settings may also differ from its original configuration; verify its state before reusing it.

---

## 3. Workload Routing

| Workload | Intended destination | Reason |
|---|---|---|
| Transaction creation and updates | PostgreSQL primary | The primary accepts writes and generates WAL for replication |
| Read-only reporting | PostgreSQL replica | Can offload eligible reads from the primary |
| Consistency-sensitive reads | Primary or a specifically designed consistency-aware route | Reduces the risk of reading stale data |
| Ledger partitioning experiment | Hash-partitioned PostgreSQL table | Demonstrates partition pruning |
| Document-oriented cloud data | MongoDB Atlas | Provides the cloud database component |

A replica can be streaming and still be behind the primary. Applications must not assume that a healthy replication connection guarantees every replica read returns the latest committed state. This table describes intended workload placement; it does not imply that application-level routing has been implemented.

---

## 4. Experiment 1: Streaming Replication

### Objective

Verify that the PostgreSQL replica receives changes from the primary and operates in recovery mode.

### Implementation and verification

The original primary and replica containers were running during the replication experiment. The recorded checks showed:

- A connected replication client on the primary.
- Replication state `streaming`.
- Synchronization state `async`.
- The replica in recovery mode.
- Hot standby and read-only behaviour.
- Successful execution of primary and replica verification scripts.

The recorded primary replication status included:

| Property | Observed value |
|---|---|
| Application name | `walreceiver` |
| Replication state | `streaming` |
| Synchronization state | `async` |
| Replica client address | `172.18.0.3` |

The replica reported `pg_is_in_recovery() = true`, `hot_standby = on`, and `transaction_read_only = on`.

### Row-count consistency

| Table | Primary count | Replica count |
|---|---:|---:|
| `customers` | 5,001 | 5,001 |
| `transactions` | 206,096 | 206,096 |

These counts matched at the time of observation. They do not prove that replication can never lag or that every table is always synchronized.

**Result:** Streaming replication and the recorded row-count comparison were successful.

---

## 5. Experiment 2: Replica Lag and Read Consistency

### Objective

Observe how asynchronous replication can produce stale reads when the replica has not replayed the latest changes.

### Setup and point-in-time WAL measurement

Because the original replica had been promoted during the failover experiment, a separate temporary PostgreSQL 16 primary/replica environment was used. The temporary primary reported `state = streaming` and `sync_state = async`.

An initial test marker, `exp2-test-20261029`, was inserted into `exp2_stale_read_test` on the primary and was subsequently visible on the replica. At the time of an initial WAL measurement, the primary WAL position and replica replay position were both `0/F027C60`, giving a measured gap of `0 bytes`. This was a point-in-time measurement and did not capture lag.

### Controlled stale-read test

A separate controlled test paused WAL replay on the temporary replica, inserted one row into `replication_lag_demo` on the primary, and observed a count of 1 on the primary versus 0 on the replica. After replay resumed, the replica count became 1. Screenshots `screenshots/05_stale_read.png` and `screenshots/06_caught_up.png` record the stale and caught-up states.

This demonstrates a stale read during a deliberately controlled replay pause. It does not estimate typical production replication lag or its duration.

For a fintech ledger, consistency-sensitive reads—such as confirming a transfer or displaying a newly updated balance—should use the primary or an explicitly designed consistency mechanism. Replica reads are more suitable for reporting workloads that can tolerate some delay.

**Result:** Asynchronous streaming replication was verified, a zero-byte WAL replay gap was measured at one point in time, and a separate controlled pause-and-resume test demonstrated stale-read behaviour and subsequent catch-up.

**Evidence:** `output/02_replication_lag_results.txt`, `screenshots/05_stale_read.png`, and `screenshots/06_caught_up.png`.

---

## 6. Experiment 3: Asynchronous and Synchronous Replication

### Initial configuration

The isolated temporary lab initially used asynchronous replication. The recorded settings and status were:

| Property | Observed value |
|---|---|
| `synchronous_standby_names` | Empty |
| `synchronous_commit` | `on` |
| Replication state | `streaming` |
| Synchronization state | `async` |
| Standby application name | `walreceiver` |

`synchronous_commit = on` alone does not establish synchronous standby acknowledgement. The empty `synchronous_standby_names` setting and `sync_state = async` showed that the standby was not initially configured as synchronous.

### Synchronous configuration

The temporary primary was configured with:

```sql
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (walreceiver)';
SELECT pg_reload_conf();
```

The reload returned `true`. Afterwards, `pg_stat_replication` reported `state = streaming` and `sync_state = sync`. The recorded sent, write, flush, and replay LSN values were all `0/F027C60` at the time of measurement.

### Successful synchronous write

The marker `exp3-sync-20261029-001` was inserted into `exp3_sync_test` and subsequently queried successfully on the replica.

| Measurement | Recorded value |
|---|---|
| Test marker | `exp3-sync-20261029-001` |
| Total PowerShell command duration | `236.8052 ms` |
| Replica query | One row returned |

The duration includes Docker command execution and `psql` connection/setup overhead. It is not an isolated database commit-latency measurement and should not be treated as a direct asynchronous-versus-synchronous performance comparison.

### Standby availability and timeout test

The temporary replica container `carbon-exp2-replica` was stopped while synchronous replication was configured. A write was issued with a five-second statement timeout using the marker `exp3-sync-timeout-test-20261029`.

The command returned a statement-timeout error while inserting an index tuple in `exp3_sync_test_marker_key`. A subsequent primary query found the marker. After the replica restarted, `pg_stat_replication` again reported `state = streaming` and `sync_state = sync`; a query against the replica also found the same marker, with timestamp `2026-10-29 11:15:14.337494+00`. The earlier marker `exp3-sync-standby-down-001` was also observed on both servers after recovery.

**Interpretation:** The timeout error was observed and the associated marker was later found on both servers. The exact outcome and timing of the timed-out operation are inconclusive. The evidence does not establish that the insert was rolled back or precisely when the row committed or replicated.

### Conceptual comparison

| Consideration | Asynchronous replication | Synchronous replication |
|---|---|---|
| Commit latency | Generally lower because standby acknowledgement is not required | Can be higher because the configured acknowledgement is required |
| Dependence on standby response | Lower | Depends on synchronous configuration and acknowledgement level |
| Risk of losing recent acknowledged changes during failover | Generally higher | Can be reduced with suitable acknowledgement and failover procedures |
| Behaviour during standby failure | Writes may continue while the primary remains operational | Writes requiring synchronous acknowledgement may wait or block |
| Availability trade-off | Can favour write availability | Can sacrifice write availability when the required standby is unavailable |

For a fintech ledger, protecting acknowledged transactions is important. A production design could use synchronous replication for critical commits where latency and availability trade-offs are acceptable, alongside durable backups, monitoring, and tested recovery procedures.

**Result:** Synchronous standby configuration was verified, a successful test row was observed on the replica, and the timeout and recovery were documented.

**Limitations:** The command duration is not isolated commit latency; the timeout outcome remains inconclusive; no comparative latency benchmark or conclusive blocked-write duration was captured.

**Evidence:** `output/03_sync_replication_results.txt` and the corresponding synchronous replication screenshots.

---

## 7. Experiment 4: Hash Partitioning and Query Pruning

### Objective

Evaluate hash partitioning and determine whether a query on the partition key can prune irrelevant partitions.

### Row counts

| Measurement | Row count |
|---|---:|
| Source rows | 404,162 |
| Partitioned rows | 404,162 |

| Partition | Row count |
|---|---:|
| `ledger_entries_p0` | 103,146 |
| `ledger_entries_p1` | 100,901 |
| `ledger_entries_p2` | 102,145 |
| `ledger_entries_p3` | 97,970 |
| **Total** | **404,162** |

The source and partitioned counts matched.

### Partition pruning

The recorded query filtering on `account_id = 1001` scanned `ledger_entries_p0` only, demonstrating partition pruning for that query.

| Measurement | Recorded value |
|---|---:|
| Execution time | Approximately 12.343 ms |
| Rows returned | 57 |
| Rows removed by filter | 103,089 |
| Shared buffer hits | 1,064 |

These values describe the recorded execution, not a general performance guarantee. Hash partitioning organises data within a PostgreSQL database; it does not itself distribute data across independent database servers.

**Result:** Row counts matched and the recorded query demonstrated partition pruning.

**Evidence:** `output/03_partitioning_results.txt` and the partitioning screenshot.

---

## 8. Experiment 5: Failover

### Procedure and observations

The original primary container `carbon-pg-primary` was stopped. The following command was executed against the replica:

```sql
SELECT pg_promote(true, 30);
```

It returned `true`. After promotion, the recorded verification query showed `pg_is_in_recovery() = false` and a promoted-primary WAL LSN of `0/11BDB360`.

This demonstrates successful promotion of the replica after the original primary was stopped.

### Limitations and operational implications

The original primary was left stopped to avoid two writable nodes and the risk of split-brain operation. The available evidence does not establish:

- Exact recovery time objective (RTO).
- Exact recovery point objective (RPO).
- The precise number of transactions potentially lost.
- A measured sequence-number change.
- Successful application-level writes after promotion.

These values must not be claimed without additional evidence. In production, failover should be coordinated through tested orchestration and fencing, with monitoring, backups, recovery validation, and a controlled procedure for rejoining the former primary.

**Result:** Replica promotion succeeded; recovery-time, data-loss, sequence-number, and post-promotion application-write measurements remain unverified.

**Evidence:** `output/05_failover_results.txt` and the failover screenshots.

---

## 9. Experiment 6: MongoDB Atlas Cloud Replication

### Cluster observations

The Atlas cluster is named `Carbon-nosql`. The captured cluster overview showed:

| Property | Observed value |
|---|---|
| Cluster name | `Carbon-nosql` |
| Cloud provider | AWS |
| Region | Paris (`eu-west-3`) |
| Topology | Replica set |
| Displayed node count | 3 |
| Cluster status | Green status indicator |

The screenshot confirms the displayed cluster overview and topology. It does not prove successful database writes or reads.

### Verification status

A `mongosh` connection attempt returned:

```text
MongoServerError: bad auth : authentication failed
```

A later attempt failed during the TLS handshake with a fatal internal-error alert (alert 80). Neither attempt established a successful authenticated database session, and the cause of the TLS failure was not established.

The intended cloud test is to inspect the server topology, insert a uniquely identifiable test document with majority write concern, read it from the primary, attempt a secondary read when an eligible secondary is available, record the actual results, and clean up only the uniquely identified test document if appropriate. Credentials must remain outside source code and the repository. Existing collections and documents must not be dropped or recreated for this test.

A majority write acknowledgement does not guarantee that every secondary has already applied the write. Secondary-read results must be observed rather than assumed.

**Status:** The cluster overview was captured. Authentication, majority-write verification, and secondary-read verification remain unresolved. The TLS connection failure also remains unresolved; its cause is unknown.

**Evidence:** `output/04_atlas_cloud_check.txt`, `screenshots/Oluwarotimi_Oluwafemi_301930838_10_atlas_cluster.png`, and `screenshots/Oluwarotimi_Oluwafemi_301930838_11_atlas_check_output.png`.

---

## 10. Additional Contribution: Proposed Production Architecture

A production architecture diagram was created as an additional contribution.

**Filename:** `Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`  
**Project-relative path:** `screenshots/Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`

The proposed design includes client applications, a CDN/WAF, TLS protection, load balancing, application servers across three proposed availability zones, PostgreSQL primary/replica roles, a three-node MongoDB Atlas replica set, backups and point-in-time recovery, monitoring and alerting, secrets management, network controls, role-based access, and CI/CD/infrastructure management.

The design routes transactional writes to the PostgreSQL primary and eligible reporting reads to a replica, while recognising that consistency-sensitive reads must account for replication lag. MongoDB Atlas is shown as a separate document-data component; this does not imply automatic cross-database transactions or consistency guarantees between PostgreSQL and MongoDB.

**This is a proposed production design, not a claim that the current lab implements the full architecture.** The practical work did not establish automatic production failover, a three-zone application deployment, automated backup restoration, production-grade monitoring, or successful Atlas majority-write and secondary-read verification.

**Evidence:** `screenshots/Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`.

---

## 11. Distributed Database Design for Carbon

### Proposed multi-server design

For a larger Carbon deployment, I would partition ledger transactions by `account_id` and distribute account data across multiple PostgreSQL shards. This key supports common account-level balance and transaction-history queries and can keep related account records together. A hash-based distribution could spread accounts across shards, although routing and rebalancing would need to be planned as data volume grows.

Transfers between accounts on different shards are more complex than transfers within one shard. They require a coordinated transaction strategy, durable transfer records, idempotency controls, and reconciliation so that retries or partial failures do not cause duplicate debits or credits. The design must preserve ledger integrity if one shard becomes unavailable during a transfer.

Queries that do not include the shard key may need to contact multiple shards and combine results. This increases network traffic and query latency. Reporting workloads may therefore need carefully designed aggregation or separate reporting mechanisms.

Hot shards are another risk. An account with unusually high transaction volume can overload its assigned shard. Monitoring, workload limits, and an appropriate distribution strategy can help, but a single highly active account may still need special handling.

MongoDB sharding differs from PostgreSQL streaming replication and table partitioning. MongoDB sharding distributes documents across shards according to a shard key, whereas a MongoDB replica set maintains copies of data for availability and redundancy. PostgreSQL streaming replication copies WAL changes to a standby, while PostgreSQL table partitioning organises data within a database and does not itself distribute it across independent servers.

This multi-shard design is a proposal only; a multi-shard deployment was not implemented or benchmarked in this portfolio.

---

## 12. Limitations, Reproduction, and Safety

### Summary of results

- Streaming replication and primary/replica row-count checks were successful at the time recorded.
- Experiment 2 measured a zero-byte WAL replay gap at one point in time and separately captured a stale read during a controlled replay pause, followed by catch-up.
- Experiment 3 configured and verified synchronous replication and observed a successful test write on the replica. The standby-unavailability test timed out, and its exact commit outcome remains inconclusive.
- Hash partitioning preserved the recorded row count and demonstrated pruning for the `account_id = 1001` query.
- Replica promotion succeeded after the original primary was stopped.
- The Atlas overview showed a three-node replica set in AWS Paris, but authentication and cloud read/write verification remain unresolved.
- Exact RPO, RTO, sequence-number change, and post-promotion application-write results have not been established.
- No isolated database commit-latency benchmark or conclusive blocked synchronous-write duration was captured.
- The production architecture and multi-shard design are proposals, not fully implemented production capabilities.

### File and evidence map

The `portfolio-5-distributed-cloud` directory contains:

- `docker-compose.yml`
- `replica-entrypoint.sh`
- `primary-init/01_replication.sh`
- `primary-init/02_create_tables.sql`
- `primary-init/03_seed_data.sql`
- `01_primary_checks.sql`
- `02_replica_checks.sql`
- `03_partitioning.sql`
- `04_atlas_cloud_check.js`
- `output/01_primary_checks.txt`
- `output/02_replica_checks.txt`
- `output/02_replication_lag_results.txt`
- `output/03_partitioning_results.txt`
- `output/03_sync_replication_results.txt`
- `output/04_atlas_cloud_check.txt`
- `output/05_failover_results.txt`
- Screenshots of the Docker containers, row counts, primary/replica checks, replication status, stale-read/catch-up test, synchronous replication tests, partitioning, failover, Atlas overview, Atlas script output, and proposed architecture.

**Evidence provenance:** The recorded `output/01_primary_checks.txt` and `output/02_replica_checks.txt` reports were generated against the separate temporary lab containers `carbon-exp2-primary` and `carbon-exp2-replica`, not the original Portfolio 5 primary and promoted replica. They must not be interpreted as health checks of the original cluster.

### Reproduction guidance

The original topology has changed since the failover experiment: the former primary is stopped and the replica has been promoted. Therefore, do not start the original Compose stack blindly or assume it still has its original primary/standby roles.

Before running any reproduction commands:

1. Review `docker-compose.yml` and confirm the exact service names, ports, volume names, and initialization behaviour.
2. Confirm Docker is operational and identify which lab is being used.
3. Use the isolated temporary lab for the stale-read and synchronous-replication experiments; do not reuse or remove volumes unless their contents and purpose are understood.
4. Confirm the temporary lab's current synchronous replication settings before repeating Experiment 2.
5. Run SQL checks only against the intended Docker database, not the host PostgreSQL 18 service on port 5432.
6. Keep Atlas credentials in a local environment variable or other secrets mechanism; do not commit a connection string or password.
7. Preserve the existing data and evidence. Do not use `docker compose down -v` as routine cleanup because it removes volumes and can permanently delete experiment data.

The SQL and JavaScript scripts listed above are included in the project. Exact start, connection, and execution commands should be confirmed against the current Compose configuration before use; this README intentionally does not prescribe a potentially unsafe command that could restart the former primary or target the wrong database.

---

## 13. Reflection and AI-Use Declaration

### Reflection

This portfolio demonstrates important distributed-database trade-offs in the context of a fintech platform. Streaming replication can support read scaling and recovery, but asynchronous operation can introduce replication lag. Matching row counts provide useful point-in-time evidence but do not prove that stale reads cannot occur. The controlled replay-pause test captured a stale read and subsequent catch-up.

Experiment 3 demonstrated that PostgreSQL can be configured to recognise a synchronous standby. A successful test row was visible on the replica. During the standby-unavailability test, the insert command returned a statement-timeout error, but the marker was later found on both servers. The available evidence does not establish the precise commit outcome during the interruption. The recorded command duration included connection and execution overhead and is not a direct database commit-latency measurement.

Hash partitioning can reduce the amount of data examined by suitable queries. The source and partitioned row counts matched, and the recorded query demonstrated partition pruning. Partitioning alone does not distribute data across independent servers.

The failover experiment demonstrated successful promotion of the replica. A complete production assessment would additionally measure recovery time, possible data loss, sequence behaviour, and successful application writes after promotion.

The Atlas overview confirms the displayed three-node replica-set topology and region, but the failed authentication and subsequent TLS connection failure mean that majority-write and secondary-read behaviour cannot be concluded from the available evidence. The proposed architecture and multi-shard design connect the practical experiments to a possible larger fintech deployment while distinguishing implemented results from proposed capabilities.

### AI-use declaration

AI assistance was used to help draft configuration files, SQL checks, experiment procedures, and explanatory documentation, and to assist with the proposed production architecture and its explanation. The student remains responsible for reviewing, executing, validating, and understanding the work. Measurements and screenshots are reported according to the available experiment evidence. Incomplete tests and limitations are explicitly identified rather than presented as successful experiments.