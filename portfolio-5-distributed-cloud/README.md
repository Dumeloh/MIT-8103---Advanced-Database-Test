# MIT 8103 Portfolio 5: Distributed and Cloud Databases

## Carbon Case Study

**Project:** MIT 8103 â€” Advanced Database Test  
**Portfolio:** 5 â€” Distributed and Cloud Database Exercise  
**Database technologies:** PostgreSQL, Docker, MongoDB Atlas  
**Environment:** Windows, PowerShell, Docker, and Antigravity IDE

---

## 1. Project Overview

This portfolio explores distributed database concepts using a Carbon fintech case study. The practical work covers PostgreSQL streaming replication, primary and replica responsibilities, replica consistency, synchronous and asynchronous replication, hash partitioning, failover, and a cloud database deployment using MongoDB Atlas.

The project demonstrates how database architecture can support read scaling, data distribution, availability, and recovery from database failures.

The work completed includes:

- Running PostgreSQL primary and replica containers using Docker.
- Verifying PostgreSQL streaming replication.
- Executing primary and replica verification scripts.
- Comparing row counts between the primary and replica.
- Measuring a point-in-time WAL replay gap in an isolated asynchronous replication lab.
- Configuring and verifying synchronous replication in an isolated temporary lab.
- Inserting test markers and verifying their subsequent visibility on the replica.
- Creating and evaluating a hash-partitioned ledger table.
- Promoting the replica after stopping the original primary.
- Creating a MongoDB Atlas Free cluster and attempting the cloud verification script.
- Recording replication, partitioning, and failover results in the output directory.
- Capturing the Atlas cluster overview showing its three-node replica-set topology and AWS Paris region.
- Creating a proposed production architecture diagram as an additional contribution.

A controlled stale-read interval was captured in the separate temporary experiment lab: while WAL replay was paused, the primary contained one row in `replication_lag_demo` and the replica contained zero; after replay resumed, the replica contained one row. The earlier zero-byte WAL-gap measurement was a separate point-in-time observation. Experiment 3 verified synchronous standby configuration and a successful replicated write, while its standby-unavailability test remains inconclusive. Successful MongoDB Atlas authentication and cloud read/write verification remain unresolved.

These limitations are documented rather than presented as successful experiments.

---

## 2. Architecture

The practical environment contains the following components:

| Component | Role | Observed status |
|---|---|---|
| PostgreSQL primary | Accepts writes and generates changes for replication | Used during the replication experiment; subsequently stopped for failover |
| PostgreSQL replica | Receives streamed WAL records and supports read-only queries during recovery | Streaming replication verified; subsequently promoted |
| Docker | Runs the isolated PostgreSQL database containers | Used successfully |
| Hash-partitioned ledger table | Demonstrates hash partitioning and partition pruning | Experiment completed |
| MongoDB Atlas `Carbon-nosql` | Cloud database component | Cluster created; authentication verification remains unresolved |

The original PostgreSQL containers were named `carbon-pg-primary` and `carbon-pg-replica`. They used PostgreSQL 16 inside Docker. The host PostgreSQL 18 installation was separate from the Docker environment.

The original PostgreSQL database was `carbon_db`, using the database user `carbon`. The original host ports were 5433 for the primary and 5434 for the replica. The host PostgreSQL service on port 5432 was separate from these Docker containers.

During the original replication experiment, the primary and replica were connected. During the failover experiment, the original primary was stopped and the replica was successfully promoted.

A separate temporary Docker lab was subsequently created for replication experiments, using the container names `carbon-exp2-primary` and `carbon-exp2-replica`, host ports 5435 and 5436, and separate Docker volumes. This isolated lab was used to measure asynchronous replication and configure synchronous replication without restarting the promoted original replica or altering the original database volumes.

**Safety note:** The original primary must remain stopped until a safe rejoin or reconfiguration procedure is performed. Restarting it as a writable primary while the promoted replica is also writable could create split-brain operation.

---

## 3. Workload Routing

The intended workload placement is:

| Workload | Intended destination | Reason |
|---|---|---|
| Transaction creation and updates | PostgreSQL primary | The primary accepts writes and generates changes for replication |
| Read-only reporting | PostgreSQL replica | Can offload eligible reads from the primary |
| Consistency-sensitive reads | Primary, or an appropriate consistency-aware route | Reduces the risk of reading stale data |
| Ledger partitioning experiment | Hash-partitioned PostgreSQL table | Demonstrates partition pruning |
| Document-oriented cloud data | MongoDB Atlas | Supports the cloud database component |

A replica can be streaming and still be behind the primary. Applications must not assume that a successful replication connection guarantees that every read returns the latest committed state.

This table describes the intended workload-routing design; it does not imply that every application-level route has been implemented.

---

## 4. Experiment 1: Streaming Replication

### Objective

Verify that the PostgreSQL replica receives changes from the primary and operates in recovery mode.

### Implementation and verification

The original primary and replica containers were running during the replication experiment. The following checks were completed:

- The primary reported a connected replication client.
- The replication state was `streaming`.
- The synchronization state was `async`.
- The replica reported that it was in recovery mode.
- Hot standby and read-only behaviour were verified.
- The primary and replica verification scripts executed successfully.

The recorded primary replication status included:

| Property | Observed value |
|---|---|
| Application name | `walreceiver` |
| Replication state | `streaming` |
| Synchronization state | `async` |
| Replica client address | `172.18.0.3` |

The replica reported:

- `pg_is_in_recovery() = true`
- `hot_standby = on`
- `transaction_read_only = on`

### Row-count consistency

The following counts matched between the primary and replica during the checks:

| Table | Primary count | Replica count |
|---|---:|---:|
| `customers` | 5,001 | 5,001 |
| `transactions` | 206,096 | 206,096 |

These matching counts demonstrate consistency for the checked tables at the time of observation. They do not prove that replication can never lag or that every table is always synchronized.

**Result:** Streaming replication and the recorded row-count comparison were successful.

---

## 5. Experiment 2: Replica Lag and Read Consistency

### Objective

Understand how asynchronous replication can produce stale reads when the replica has not yet replayed the latest changes, and measure the replication state at the time of observation.

### Setup

Because the original replica had been promoted during Experiment 5, a separate temporary PostgreSQL 16 primary-replica environment was created for this experiment. The temporary lab used separate containers, ports, and database volumes.

The temporary primary and replica were confirmed to be connected using asynchronous streaming replication. The temporary primary's `pg_stat_replication` output reported:

| Property | Observed value |
|---|---|
| Application name | `walreceiver` |
| Replication state | `streaming` |
| Synchronization state | `async` |

### Test marker

A test table named `exp2_stale_read_test` was used in the temporary lab. The marker `exp2-test-20261029` was inserted on the primary.

The marker was subsequently queried successfully on the replica:

| Property | Observed result |
|---|---|
| Test marker | `exp2-test-20261029` |
| Replica query result | One row returned |
| Recorded creation time | `2026-10-29 09:46:53.141979+00` |

This initial marker check confirmed eventual visibility after replication caught up, but did not itself demonstrate a stale-read interval. A separate controlled pause-and-resume test below captured the stale read directly.

### WAL replay measurement

A point-in-time WAL measurement was taken from the temporary primary. The primary's current WAL position and the replica's replay position were compared using `pg_stat_replication`.

| Measurement | Recorded value |
|---|---|
| Primary WAL position at measurement | `0/F027C60` |
| Replica replay position | `0/F027C60` |
| Replication state | `streaming` |
| Synchronization state | `async` |
| Measured replay gap | `0 bytes` |

The zero-byte replay gap means the replica had caught up to the primary's measured WAL position at that instant.

### Interpretation

Asynchronous replication does not generally require the primary to wait for the replica to confirm receipt and replay of every transaction before acknowledging a commit. Therefore, a recently committed transaction may temporarily be absent from a replica while WAL changes are in transit or awaiting replay.

In the initial point-in-time measurement, the marker was visible on the replica and the measured WAL replay gap was zero. That measurement did not capture lag. A separate controlled test paused WAL replay on the temporary replica, inserted one row into `replication_lag_demo` on the temporary primary, and observed a count of 1 on the primary versus 0 on the replica. After replay resumed, the replica count became 1. Screenshots `screenshots/05_stale_read.png` and `screenshots/06_caught_up.png` record these states. This demonstrates a stale read during the controlled replay pause; it does not estimate typical production lag duration.

For a fintech ledger such as Carbon, consistency-sensitive readsâ€”such as confirming a transfer or displaying a newly updated balanceâ€”should be routed to the primary or handled using an explicitly designed consistency mechanism. Replica reads are more suitable for reporting and other workloads that can tolerate some delay.

**Result:** Asynchronous streaming replication was verified, the test marker was visible on the replica, and a zero-byte point-in-time replay gap was measured.

**Limitation:** The earlier WAL-gap measurement was only a point-in-time measurement. The later controlled pause-and-resume test did capture a stale-read interval, but it does not measure typical production lag duration.

**Evidence:** `output/02_replication_lag_results.txt`

---

## 6. Experiment 3: Asynchronous and Synchronous Replication

### Objective

Compare the consistency, durability, latency, and availability implications of asynchronous and synchronous replication.

### Initial asynchronous configuration

The isolated temporary lab initially operated with asynchronous replication.

The following settings and observations were recorded:

| Property | Observed value |
|---|---|
| `synchronous_standby_names` | Empty |
| `synchronous_commit` | `on` |
| Replication state | `streaming` |
| Synchronization state | `async` |
| Standby application name | `walreceiver` |

The setting `synchronous_commit = on` alone does not establish that synchronous standby acknowledgement is configured. The empty `synchronous_standby_names` setting and `sync_state = async` confirmed that the standby was not initially configured as synchronous.

### Synchronous replication configuration

Synchronous replication was configured in the isolated temporary primary using:

```sql
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (walreceiver)';
```

The PostgreSQL configuration was then reloaded:

```sql
SELECT pg_reload_conf();
```

The reload returned `true`, confirming that the configuration reload succeeded.

The primary's replication status subsequently showed:

| Property | Observed value |
|---|---|
| Standby application name | `walreceiver` |
| Replication state | `streaming` |
| Synchronization state | `sync` |
| Primary sent LSN | `0/F027C60` |
| Standby write LSN | `0/F027C60` |
| Standby flush LSN | `0/F027C60` |
| Standby replay LSN | `0/F027C60` |

This confirmed that PostgreSQL recognized `walreceiver` as the synchronous standby and that the recorded WAL positions matched at the time of measurement.

### Successful synchronous write

A dedicated table named `exp3_sync_test` was created in the temporary lab.

The successful test marker was:

```sql
INSERT INTO exp3_sync_test (marker)
VALUES ('exp3-sync-20261029-001');
```

The row was subsequently queried successfully on the replica.

The write was timed using PowerShell's `Measure-Command`.

| Measurement | Recorded value |
|---|---|
| Test marker | `exp3-sync-20261029-001` |
| Total command duration | `236.8052 ms` |
| Replica query | One row returned |

The measured duration includes Docker command execution and `psql` connection and setup overhead. It is **not an isolated database commit-latency measurement** and should not be treated as a direct comparison of asynchronous and synchronous commit performance.

### Standby availability and timeout test

To investigate the availability trade-off, the temporary replica container `carbon-exp2-replica` was stopped while synchronous replication was configured.

A write command was issued using a five-second statement timeout. The intended test marker was:

`exp3-sync-timeout-test-20261029`

The command returned the following error:

```text
ERROR: canceling statement due to statement timeout
CONTEXT: while inserting index tuple (0,4) in relation "exp3_sync_test_marker_key"
```

A subsequent query against the primary found the marker:

| Property | Observed result |
|---|---|
| Marker | `exp3-sync-timeout-test-20261029` |
| Primary query | Marker found |
| Recorded creation time | `2026-10-29 11:15:14.337494+00` |

After restarting the replica, `pg_stat_replication` reported:

| Property | Observed value |
|---|---|
| Replication state | `streaming` |
| Synchronization state | `sync` |

A query executed directly against the replica using `-h localhost` also found `exp3-sync-timeout-test-20261029`, with timestamp `2026-10-29 11:15:14.337494+00`.

The earlier marker `exp3-sync-standby-down-001` was also observed on both primary and replica after recovery.

**Interpretation:** The timeout error was observed, and the corresponding test marker was subsequently found on both servers. The exact outcome and timing of the timed-out operation are inconclusive. The evidence does not establish that the insert was rolled back, nor does it establish precisely when the row became committed or replicated.

### Conceptual comparison

| Consideration | Asynchronous | Synchronous |
|---|---|---|
| Commit latency | Generally lower because standby acknowledgement is not required | Can be higher because the configured acknowledgement is required |
| Dependence on standby response | Lower | Depends on the synchronous configuration and acknowledgement level |
| Risk of losing recent acknowledged changes during failover | Higher | Can be reduced when the appropriate standby acknowledgement and failover procedures are used |
| Behaviour during standby failure | Writes may continue while the primary remains operational | Writes requiring synchronous acknowledgement may wait or block |
| Availability trade-off | Can favour write availability | Can sacrifice write availability when the required standby is unavailable |

### Carbon ledger implications

For a fintech ledger, preserving acknowledged financial transactions is a high priority. A production design could use synchronous replication for critical commits where latency and availability trade-offs are acceptable, alongside durable backups, monitoring, and a tested recovery process.

The experiment verified asynchronous mode, configured and verified synchronous mode, and confirmed that a successful test row was visible on the replica. The standby-unavailability test produced a statement-timeout error, but the marker was subsequently found on both servers. No definitive conclusion can be made about the exact commit outcome during the interruption.

**Result:** Synchronous standby configuration was verified, a successful test write was observed on the replica, and the timeout and subsequent replication recovery were documented.

**Limitations:**

- The recorded `236.8052 ms` is the total command duration, not isolated database commit latency.
- The exact outcome of the timed-out operation remains inconclusive.
- No comparative asynchronous-versus-synchronous latency benchmark was completed.
- No isolated database commit-latency measurement was captured.

**Evidence:** `output/03_sync_replication_results.txt`

---

## 7. Experiment 4: Hash Partitioning and Query Pruning

### Objective

Evaluate hash partitioning as a method of distributing ledger records and reducing the amount of data examined by suitable queries.

### Results

The partitioning experiment completed successfully.

| Measurement | Row count |
|---|---:|
| Source rows | 404,162 |
| Partitioned rows | 404,162 |

The recorded counts for the four hash partitions were:

| Partition | Row count |
|---|---:|
| `ledger_entries_p0` | 103,146 |
| `ledger_entries_p1` | 100,901 |
| `ledger_entries_p2` | 102,145 |
| `ledger_entries_p3` | 97,970 |
| **Total** | **404,162** |

The source and partitioned row counts matched.

### Partition pruning

The query filtering on `account_id = 1001` scanned `ledger_entries_p0` only, demonstrating partition pruning for the recorded query.

The recorded `EXPLAIN ANALYZE` results included:

| Measurement | Recorded value |
|---|---:|
| Execution time | Approximately 12.343 ms |
| Rows returned | 57 |
| Rows removed by filter | 103,089 |
| Shared buffer hits | 1,064 |

These measurements describe the recorded query execution and are not a general performance guarantee.

### Interpretation

Hash partitioning distributes rows among partitions according to the partition key. When a query contains a compatible restriction on that key, PostgreSQL may be able to exclude irrelevant partitions from the scan.

Partitioning is not the same as distributing data across independent database servers. It organizes data within the PostgreSQL database and does not, by itself, provide cross-server sharding.

**Result:** The partitioned row count matched the source count, and the recorded query demonstrated partition pruning.

---

## 8. Experiment 5: Failover

### Objective

Explore recovery when the PostgreSQL primary becomes unavailable and verify promotion of the replica.

### Procedure and observations

The original primary container, `carbon-pg-primary`, was stopped.

The following promotion command was executed against the replica:

```sql
SELECT pg_promote(true, 30);
```

The command returned `true`, indicating successful promotion.

After promotion, the recorded verification query returned:

| Property | Observed value |
|---|---|
| `pg_is_in_recovery()` | `false` |
| Promoted primary WAL LSN | `0/11BDB360` |

The value `false` for `pg_is_in_recovery()` confirms that the promoted server was no longer operating as a standby in recovery mode.

### Interpretation and limitations

The experiment demonstrates successful promotion of the replica after the original primary was stopped.

The original primary was left stopped to avoid starting two writable nodes and creating a split-brain risk.

The available evidence does not establish:

- The exact recovery time objective (RTO).
- The exact recovery point objective (RPO).
- The precise number of transactions potentially lost.
- A measured sequence-number change.
- Successful application-level writes after promotion.

These results must not be claimed without further evidence.

In production, failover should be coordinated by a tested orchestration and fencing process, with monitoring, backups, recovery validation, and a controlled method for rejoining the former primary.

**Result:** Replica promotion succeeded. Recovery-time, data-loss, and sequence-number measurements remain unverified.

---

## 9. Experiment 6: MongoDB Atlas Cloud Replication

### Objective

Verify the Atlas deployment and test a majority-acknowledged write followed by a secondary read.

### Cluster observations

The Atlas cluster is named `Carbon-nosql`.

The captured Atlas cluster overview showed:

| Property | Observed value |
|---|---|
| Cluster name | `Carbon-nosql` |
| Cloud provider | AWS |
| Region | Paris (`eu-west-3`) |
| Topology | Replica set |
| Node count displayed | 3 |
| Cluster status | Green status indicator |

This screenshot confirms the cluster overview and displayed topology. It does not, by itself, prove that a majority write or secondary read succeeded.

### Verification status and connection failures

An Atlas connection attempt using `mongosh` returned an authentication failure:

```text
MongoServerError: bad auth : authentication failed
```

A later connection attempt also failed during the TLS handshake with a fatal internal-error alert (alert 80). Neither attempt established a successful authenticated database session. The cause of the TLS failure was not established.

Therefore, successful Atlas authentication and the cloud verification script's database operations have not been established by the available evidence. Troubleshooting was stopped, and the failure is documented as a limitation.

The intended cloud experiment is to:

1. Confirm the connection string and permitted network access.
2. Keep credentials outside the source code and repository.
3. Inspect the replica-set information returned by the server.
4. Insert a uniquely identifiable test document with majority write concern.
5. Read the document from the primary.
6. Attempt a secondary read when an eligible secondary is available.
7. Record actual results and clean up only the uniquely identified test document when appropriate.

A majority write acknowledgement does not guarantee that every secondary has already applied the write. Secondary-read results must be observed rather than assumed.

The existing collections and documents must not be dropped or recreated for this experiment.

**Status:** The cluster overview was captured. Authentication, majority-write verification, and secondary-read verification remain unresolved. The TLS connection failure also remains unresolved; its cause is unknown.

---

## 10. Additional Work: Proposed Production Architecture

### Objective

Extend the Carbon case study with a proposed production architecture showing how a fintech platform could be designed for higher availability, scalability, security, and disaster recovery.

### Contribution

A production architecture diagram was created as an additional piece of work for this portfolio.

**Diagram filename:** `Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`

**Project-relative path:** `screenshots/Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`

The diagram presents a proposed architecture with the following components:

- **Client applications:** Mobile, customer web, merchant, and administrative portals.
- **Traffic protection:** A CDN and web application firewall (WAF), with TLS protection and traffic filtering.
- **Load balancing:** Distributes requests across application servers.
- **Multi-zone application deployment:** Application servers across three proposed availability zones to reduce dependence on one zone.
- **PostgreSQL transactional database:** A primary for writes and a replica for eligible read-only reporting, connected through streaming replication.
- **MongoDB Atlas:** A three-node replica-set design for document-oriented data, such as KYC profiles and audit events.
- **Backups and disaster recovery:** Automated backups, point-in-time recovery, and cross-region backup storage.
- **Monitoring and observability:** Database and application metrics, logs, alerts, and replication monitoring.
- **Security:** Encryption in transit, secrets management, network controls, and role-based access.
- **CI/CD and infrastructure management:** Automated deployment and infrastructure configuration.

### Design rationale

A fintech platform needs to protect the consistency of financial transactions while also supporting reporting, document-oriented data, availability, and recovery.

The proposed design assigns transactional writes to PostgreSQL's primary and routes eligible reporting queries to a replica. This can reduce reporting load on the primary, but replica reads must account for replication lag when recent changes need to be visible.

MongoDB Atlas is shown as a separate document-data component. Its proposed role is to support document-oriented information and appropriate read workloads without implying that cross-database transactions or consistency guarantees are automatically provided between PostgreSQL and MongoDB.

Multiple application availability zones, managed failover, backups, and monitoring could improve resilience. However, these capabilities require appropriate infrastructure, configuration, operational procedures, and testing.

### Relationship to the implemented project

This diagram is a **proposed production design**, not a claim that the current Docker lab implements the complete architecture.

The practical project verified PostgreSQL streaming replication, tested replica promotion, evaluated hash partitioning, and created an Atlas cluster. It did not establish that the following proposed capabilities are implemented and tested:

- Automatic, orchestrated production failover.
- Three-zone application deployment.
- Automated backup restoration and point-in-time recovery.
- Production-grade monitoring and alerting.
- Successful Atlas majority-write and secondary-read verification.

The original primary remains stopped following replica promotion. It must not be restarted as a writable primary without a safe rejoin or reconfiguration procedure.

**Result:** The production architecture diagram provides an additional design contribution that connects the portfolio's database experiments to a possible production deployment. Its proposed features are distinguished from the capabilities verified in the practical environment.

**Evidence:** `screenshots/Oluwarotimi_Oluwafemi_301930838_06_carbon_production_architecture.png`

---

## 11. Limitations and Reproduction

### Current status

The experiments produced the following evidence:

- Streaming replication and primary/replica row-count checks were successful.
- Experiment 2 verified asynchronous streaming and recorded a zero-byte WAL replay gap during an initial point-in-time check. A separate controlled replay-pause test then observed one row on the primary and zero on the replica; after replay resumed, the replica count became one. The screenshots record both states.
- Experiment 3 configured and verified synchronous replication and observed a successful test write on the replica.
- Experiment 3's standby-unavailability test returned a statement-timeout error. The associated marker was subsequently found on both primary and replica, but the exact outcome during the interruption remains inconclusive.
- The hash-partitioning experiment completed, and the recorded query demonstrated partition pruning.
- The replica was successfully promoted after the original primary was stopped.
- The Atlas cluster overview showed a three-node replica set in AWS Paris.
- Atlas authentication failed during the recorded connection attempt, and a later TLS handshake attempt also failed.
- Exact RPO, RTO, sequence-number change, and post-promotion application-write results have not been established.
- No isolated database commit-latency benchmark or conclusive measurement of a blocked synchronous write was captured.
- A proposed production architecture diagram was created, but its proposed production capabilities have not all been implemented or tested.

### Environment and safety

The original PostgreSQL Docker environment used PostgreSQL 16 with the primary and replica on host ports 5433 and 5434. The host PostgreSQL 18 service on port 5432 was separate.

The original primary is stopped, and the original replica has been promoted. Do not restart the original primary as a writable node without a safe rejoin or reconfiguration procedure.

The temporary experiment lab uses the separate containers `carbon-exp2-primary` and `carbon-exp2-replica` on host ports 5435 and 5436. It has separate Docker volumes and is independent of the original database volumes.

Experiment 3 changed the temporary primary's synchronous standby configuration. The temporary primary should be returned to the intended asynchronous configuration before reproducing Experiment 2, or the active configuration should be explicitly documented. Do not assume the temporary lab remains in its original configuration.

### Reproduction

The original replication checks should be reproduced only after the primary/replica environment has been safely recreated or reconfigured. Do not assume the original replication topology is still active after failover.

The Experiment 2 measurements were taken in the isolated temporary lab. The recorded evidence is saved in `output/02_replication_lag_results.txt`.

Experiment 3's synchronous replication evidence is saved in `output/03_sync_replication_results.txt`.

Before starting the services, validate the Docker Compose configuration and confirm that Docker is operational. Execute database commands against the intended isolated Docker database, not the host PostgreSQL service.

The following project scripts and configuration files are part of the implementation:

- `docker-compose.yml`
- `primary-init/01_replication.sh`
- `primary-init/02_create_tables.sql`
- `primary-init/03_seed_data.sql`
- `replica-entrypoint.sh`
- `01_primary_checks.sql`
- `02_replica_checks.sql`
- `03_partitioning.sql`
- `04_atlas_cloud_check.js`

The output directory contains `01_primary_checks.txt`, `02_replica_checks.txt`, `03_partitioning_results.txt`, and `04_atlas_cloud_check.txt`, alongside the replication-lag, synchronous-replication, and failover reports. Important provenance note: the newly generated primary and replica health-check reports were run against the separate temporary lab containers `carbon-exp2-primary` and `carbon-exp2-replica`, not the original Portfolio 5 primary and promoted replica. They document the lab's observed state and must not be interpreted as health checks of the original cluster. The partitioning report records matching source and partitioned row counts and pruning to `ledger_entries_p0`. The Atlas output records an authentication failure; successful cloud database operations have not been verified.

**Reproduction commands still need to be verified against the current `docker-compose.yml` and script contents before adding exact start, connection, or execution commands.** This avoids accidentally restarting the original primary or running commands against the host PostgreSQL service.

Destructive Docker volume removal must not be used as a routine cleanup command because it may permanently remove experiment data.

---

## 12. Reflection and AI-Use Declaration

### Reflection

This portfolio demonstrates several important distributed database trade-offs in the context of a fintech platform.

Streaming replication can support read scaling and recovery, but asynchronous operation can introduce replication lag. Matching row counts provide useful point-in-time evidence but do not prove that stale reads cannot occur. Experiment 2 included an initial zero-gap measurement and a separate controlled replay-pause test that captured a stale read: the primary count was one while the replica count was zero, then the replica count became one after replay resumed.

Experiment 3 demonstrated that PostgreSQL can be configured to recognize a synchronous standby. The successful test row was visible on the replica. During the standby-unavailability test, the insert command returned a statement-timeout error, but the corresponding marker was subsequently found on both servers. The evidence does not establish the precise commit outcome during the interruption. The measured command duration included connection and execution overhead, so it cannot be used as a direct measure of database commit latency.

Hash partitioning can reduce the amount of data examined by suitable queries. In this experiment, the source and partitioned counts matched, and the recorded query demonstrated partition pruning. Partitioning alone does not distribute data across independent servers.

The failover experiment demonstrated successful promotion of the replica. However, a complete production assessment would also measure recovery time, possible data loss, sequence behaviour, and successful application writes after promotion.

The Atlas cluster overview confirms the displayed three-node replica-set topology and region. The failed authentication and subsequent TLS connection failure mean that majority-write and secondary-read behaviour cannot be concluded from the available evidence. The controlled stale-read screenshots now provide evidence of a stale read during a deliberate WAL replay pause, followed by catch-up after replay resumed.

The proposed production architecture diagram extends the project by illustrating how the database components could fit into a larger resilient fintech platform. It also highlights the difference between a working database experiment and a production deployment, where failover orchestration, backup recovery, security, monitoring, and multi-zone infrastructure must be implemented and tested.

### AI-use declaration

AI assistance was used to help draft configuration files, SQL checks, experiment procedures, and explanatory documentation. It was also used to assist with the proposed production architecture diagram and the explanation of its design.

The student remains responsible for reviewing, executing, validating, and understanding the work. All reported measurements and screenshots should be based on actual experiment results. Incomplete tests and limitations are explicitly identified rather than presented as successful experiments. The proposed architecture is identified as a design contribution and is not represented as a fully implemented production system.


